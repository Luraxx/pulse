// swift-tools-version:5.9
// Dev-only manifest: kompiliert die plattformneutrale Core-Schicht auf macOS
// und führt den Self-Test-Runner aus. Die iOS-App wird über project.yml
// (xcodegen) gebaut und bindet dieselben Core-Quellen direkt ein.
import PackageDescription

let package = Package(
    name: "PulseCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    targets: [
        .target(
            name: "PulseCore",
            path: "Core"
        ),
        .executableTarget(
            name: "pulse-selftest",
            dependencies: ["PulseCore"],
            path: "SelfTest"
        ),
    ]
)
