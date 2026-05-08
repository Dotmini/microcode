// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodeTunnerLinux",
    platforms: [
        .macOS(.v13) // Just to align with root package when testing locally
    ],
    dependencies: [
        .package(name: "CodeTunner", path: "../")
    ],
    targets: [
        .executableTarget(
            name: "CodeTunnerLinux",
            dependencies: [
                .product(name: "CodeTunnerCore", package: "CodeTunner")
            ]
        ),
    ]
)
