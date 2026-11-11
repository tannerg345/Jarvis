// swift-tools-version:5.8
// Tools version 5.8 so the app can also be built with the Command Line Tools
// that run on macOS 13 (see "Build it yourself" in README.md).
import PackageDescription

let package = Package(
    name: "JARVIS",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "JARVIS", targets: ["JARVIS"]),
        .library(name: "JARVISCore", targets: ["JARVISCore"]),
    ],
    targets: [
        // Everything that does not need AppKit or SwiftUI: storage, command
        // parsing, the butler's phrasing. Covered by unit tests.
        .target(
            name: "JARVISCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // The Mac app itself: windows, menu bar, command bar, notifications.
        .executableTarget(
            name: "JARVIS",
            dependencies: ["JARVISCore"]
        ),
        .testTarget(
            name: "JARVISCoreTests",
            dependencies: ["JARVISCore"]
        ),
    ]
)
