// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "pad_input",
    platforms: [
        .macOS("10.14"),
        .iOS("12.0")
    ],
    products: [
        // **A dash, and the underscore was a real break.** Flutter generates a
        // `FlutterGeneratedPluginSwiftPackage` that depends on
        // `.product(name: "pad-input", package: "pad_input")` — the package name
        // keeps its underscores and the *product* name is kebab-cased. The
        // plugin was called `gamepad` when this file was written, where the two
        // spellings are the same word, so the rename to `pad_input` produced a
        // product nothing could find and every macOS build failed to resolve.
        // `pointer_lock` next door has the dash and always did.
        .library(name: "pad-input", targets: ["pad_input"])
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
