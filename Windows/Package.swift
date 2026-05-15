// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MicroCodeWindows",
    platforms: [
        .macOS(.v13) // Just to align with root package when testing locally
    ],
    dependencies: [
        .package(name: "MicroCode", path: "../")
    ],
    targets: [
        .executableTarget(
            name: "MicroCodeWindows",
            dependencies: [
                .product(name: "MicroCodeCore", package: "MicroCode")
            ]
        ),
    ]
)
