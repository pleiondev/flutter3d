// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "pad_input",
    // **The floor is what the sources need, not what the applications happen
    // to set.** Swift Package Manager compiles this target against the minimum
    // declared here, so `12.0` made every iOS build fail on the button list in
    // `GamepadPlugin.swift`: the stick clicks arrived in 12.1, menu and options
    // in 13.0, and the home button in 14.0. The four demos are already at iOS
    // 15 and macOS 12, so raising this floor costs them nothing and stops the
    // same failure reaching the other platform, where it is latent today only
    // because the applications ask for more than this file does.
    platforms: [
        .macOS("11.0"),
        .iOS("14.0")
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
