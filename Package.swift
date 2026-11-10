// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Beam",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Everything but the entry point lives in BeamCore so tests can import it.
        .target(name: "BeamCore", dependencies: ["KeyboardShortcuts", .product(name: "Sparkle", package: "Sparkle")], path: "Sources/BeamCore"),
        .executableTarget(name: "Beam", dependencies: ["BeamCore"], path: "Sources/Beam"),
        .testTarget(name: "BeamTests", dependencies: ["BeamCore"], path: "Tests/BeamTests"),
    ]
)
