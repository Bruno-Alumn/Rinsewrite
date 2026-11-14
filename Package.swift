// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Rinsewrite",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Rinsewrite",
            path: "Sources/Rinsewrite",
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(
            name: "RinsewriteTests",
            dependencies: ["Rinsewrite"],
            path: "Tests/RinsewriteTests"
        ),
    ]
)
