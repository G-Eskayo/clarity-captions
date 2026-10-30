// swift-tools-version: 6.2
import PackageDescription

// Live Translation in your ear, spike (#233). A tool package, never referenced by the app project. Measures on this
// Mac (the `ear-spike` tool) and on the iPhone simulator (the opt-in probe tests, run through xcodebuild): which
// translation languages have an on-device voice, speech-to-voice lag with AVSpeechSynthesizer, and echo (the spoken
// translation captioned back as new speech).
let package = Package(
    name: "EarSpike",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .executable(name: "ear-spike", targets: ["ear-spike"]),
    ],
    targets: [
        // Pure: echo matching, voice-to-language matching, lag stats. Fast tests.
        .target(name: "EarSpikeKit"),
        // AVSpeechSynthesizer, Translation and SpeechAnalyzer measurements, shared by the Mac tool and the probe tests.
        .target(name: "EarProbe", dependencies: ["EarSpikeKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "ear-spike", dependencies: ["EarSpikeKit", "EarProbe"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "EarSpikeKitTests", dependencies: ["EarSpikeKit"]),
        // Opt-in (EAR_PROBE=1; through xcodebuild, TEST_RUNNER_EAR_PROBE=1): runs the probes on the iPhone simulator.
        .testTarget(name: "EarProbeTests", dependencies: ["EarSpikeKit", "EarProbe"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
