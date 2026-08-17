// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "gamepad",
    platforms: [
        .macOS("10.14"),
        .iOS("12.0")
    ],
    products: [
        .library(name: "gamepad", targets: ["gamepad"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "gamepad",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
