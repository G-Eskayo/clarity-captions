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
        .executableTarget(name: "ear-spike", dependencies: ["EarSpikeKit"]),
        .testTarget(name: "EarSpikeKitTests", dependencies: ["EarSpikeKit"]),
    ]
)
