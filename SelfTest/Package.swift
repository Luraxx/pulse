// swift-tools-version:5.9
// Dev-only: Verifiziert die Core-Logik ohne Xcode/iOS-SDK.
//   cd SelfTest && swift run pulse-selftest
import PackageDescription

let package = Package(
    name: "PulseSelfTest",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .executableTarget(
            name: "pulse-selftest",
            dependencies: [
                .product(name: "PulseCore", package: "Core"),
            ]
        ),
    ]
)
