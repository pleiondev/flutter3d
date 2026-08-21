// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "pad_input",
    platforms: [
        .macOS("10.14"),
        .iOS("12.0")
    ],
    products: [
        .library(name: "pad_input", targets: ["pad_input"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "pad_input",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
