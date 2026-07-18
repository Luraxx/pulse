// swift-tools-version:5.9
// Macht die plattformneutrale Core-Schicht als Bibliothek `PulseCore`
// verfügbar – genutzt vom Self-Test-Paket (../SelfTest). Die iOS-App bindet
// dieselben Quellen direkt über project.yml (xcodegen) ein und ignoriert
// dieses Manifest.
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
