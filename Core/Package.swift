// swift-tools-version:5.9
// Exposes the platform-neutral Core layer as the library `PulseCore`
// – used by the self-test package (../SelfTest). The iOS app includes
// the same sources directly via project.yml (xcodegen) and ignores
// this manifest.
import PackageDescription

let package = Package(
    name: "PulseCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "PulseCore", targets: ["PulseCore"]),
    ],
    targets: [
        .target(
            name: "PulseCore",
            path: ".",
            exclude: ["Package.swift"]
        ),
    ]
)
