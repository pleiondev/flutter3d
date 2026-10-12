// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "flutter3d_pointer_lock",
    // iOS 14: `prefersPointerLocked`, `UIPointerLockState` and `GCMouse` all
    // arrived in it, and there is no pointer lock to offer before.
    platforms: [
        .iOS("14.0")
    ],
    products: [
        .library(name: "flutter3d-pointer-lock", targets: ["flutter3d_pointer_lock"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "flutter3d_pointer_lock",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                // No privacy manifest is needed: nothing here uses a required
                // reason API or collects anything.
                // .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)
