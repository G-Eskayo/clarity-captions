// swift-tools-version: 6.2
import PackageDescription

// Whole-system replay (#273). A tool package, never referenced by the app project. It drives the app's own
// CaptionSessionController and TranscriptionEngine with recorded audio through the AudioSource interface the
// microphone uses, at real-time pace, and logs what ran. See docs/perf/whole-system-replay-design.md.
//
// It depends on CaptionCore by path, so it builds against whatever CaptionCore is checked out next to it: main, or
// an older build's tree (scripts/system-replay/at-build.sh copies this package into a worktree of that build).
// It uses only CaptionCore API that 1.1.0 (9) already had, so one harness replays builds 9 and 10.
let package = Package(
    name: "SystemReplay",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "system-replay", targets: ["system-replay"]),
    ],
    dependencies: [
        .package(path: "../CaptionCore"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5"),
    ],
    targets: [
        // Pure: the real-time pacing schedule, the session log's shape, lag sampling. No audio, fast tests.
        .target(name: "SystemReplayKit"),
        .executableTarget(
            name: "system-replay",
            dependencies: ["SystemReplayKit", .product(name: "CaptionCore", package: "CaptionCore"),
                           .product(name: "FluidAudio", package: "FluidAudio")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "SystemReplayKitTests", dependencies: ["SystemReplayKit"]),
    ]
)
