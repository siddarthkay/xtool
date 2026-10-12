import Foundation
import Testing
@testable import PackLib

@Test func cfBundleSupportedPlatformsFollowsBuildTriple() {
    #expect(Packer.cfBundleSupportedPlatforms(for: "arm64-apple-ios") == ["iPhoneOS"])
    #expect(Packer.cfBundleSupportedPlatforms(for: "arm64-apple-ios-simulator") == ["iPhoneSimulator"])

    #expect(Packer.cfBundleSupportedPlatforms(for: "arm64-apple-ios17.0") == ["iPhoneOS"])
    #expect(Packer.cfBundleSupportedPlatforms(for: "arm64-apple-ios17.0-simulator") == ["iPhoneSimulator"])
    #expect(Packer.cfBundleSupportedPlatforms(for: "x86_64-apple-ios-simulator") == ["iPhoneSimulator"])
    #expect(Packer.cfBundleSupportedPlatforms(for: "arm64-apple-macosx") == ["MacOSX"])
    #expect(Packer.cfBundleSupportedPlatforms(for: "x86_64-apple-macosx") == ["MacOSX"])

    #expect(Packer.cfBundleSupportedPlatforms(for: "unknown-triple") == ["iPhoneOS"])
}

@Test func buildVariablesExpandConfiguration() {
    #expect(
        PackSchema.expandBuildVariables(in: "build/$(CONFIGURATION)/React.xcframework", configuration: .debug)
            == "build/debug/React.xcframework"
    )
    #expect(
        PackSchema.expandBuildVariables(in: "build/$(CONFIGURATION)/React.xcframework", configuration: .release)
            == "build/release/React.xcframework"
    )
    #expect(PackSchema.expandBuildVariables(in: "plain/path", configuration: .debug) == "plain/path")
}

@Test func schemaRejectsNonXCFrameworkEntries() {
    #expect(throws: StringError.self) {
        try PackSchema(validating: .init(
            version: .v1,
            orgID: "com.example",
            frameworks: ["Vendor/Foo.framework"]
        ))
    }
    #expect(throws: Never.self) {
        try PackSchema(validating: .init(
            version: .v1,
            orgID: "com.example",
            frameworks: ["Vendor/Foo.xcframework"]
        ))
    }
}

private func makeXCFramework(libraries: [String]) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("PackerTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("Test.xcframework", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let info: [String: Any] = [
        "CFBundlePackageType": "XFWK",
        "AvailableLibraries": libraries.map { ["LibraryIdentifier": "ios-arm64", "LibraryPath": $0] },
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: url.appendingPathComponent("Info.plist"))
    return url
}

@Test func frameworkNameComesFromXCFrameworkInfoPlist() throws {
    let url = try makeXCFramework(libraries: ["hermesvm.framework"])
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    #expect(try Planner.frameworkName(ofXCFramework: url) == "hermesvm")
}

@Test func staticXCFrameworkHasNoFrameworkName() throws {
    let url = try makeXCFramework(libraries: ["libReactNativeHeaders-ios.a"])
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    #expect(try Planner.frameworkName(ofXCFramework: url) == nil)
}

@Test func missingXCFrameworkHasNoFrameworkName() throws {
    let url = URL(fileURLWithPath: "/nonexistent/Remote.xcframework")
    #expect(try Planner.frameworkName(ofXCFramework: url) == nil)
    #expect(try Planner.frameworkName(ofXCFramework: URL(fileURLWithPath: "/nonexistent/Not.framework")) == nil)
}

@Test func builderManifestDeclaresPrebuiltFrameworks() {
    let product = Plan.Product(
        type: .application,
        product: "Hello",
        deploymentTarget: "15.0",
        bundleID: "com.example.Hello",
        infoPlist: [:],
        resources: [
            .framework(name: "React", path: "ios/build/debug/React.xcframework"),
            .framework(name: "hermesvm", path: "ios/build/debug/hermes-engine.xcframework"),
        ],
        iconPath: nil,
        entitlementsPath: nil
    )
    let manifest = Packer.builderManifest(for: Plan(app: product, extensions: []))

    #expect(manifest.contains(#".binaryTarget(name: "React", path: "Frameworks/React.xcframework")"#))
    #expect(manifest.contains(#".binaryTarget(name: "hermesvm", path: "Frameworks/hermesvm.xcframework")"#))
    #expect(manifest.contains(#""React","#))
    #expect(manifest.contains(#""hermesvm","#))
}

@Test func builderManifestWithoutFrameworksHasNoBinaryTargets() {
    let product = Plan.Product(
        type: .application,
        product: "Hello",
        deploymentTarget: "15.0",
        bundleID: "com.example.Hello",
        infoPlist: [:],
        resources: [],
        iconPath: nil,
        entitlementsPath: nil
    )
    let manifest = Packer.builderManifest(for: Plan(app: product, extensions: []))
    #expect(!manifest.contains(".binaryTarget"))
}
