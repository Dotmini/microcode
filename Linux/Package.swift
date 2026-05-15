// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MicroCodeLinux",
    platforms: [
        .macOS(.v13) // Just to align with root package when testing locally
    ],
    dependencies: [
        .package(name: "MicroCode", path: "../")
    ],
    targets: [
        .executableTarget(
            name: "MicroCodeLinux",
            dependencies: [
                .product(name: "MicroCodeCore", package: "MicroCode")
            ]
        ),
    ]
)
