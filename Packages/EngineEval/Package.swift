// swift-tools-version: 6.2
import PackageDescription

// Engine accuracy test (#145). A tool package, never referenced by the app project: WhisperKit and the engine
// runner stay out of the shipping target. CaptionCore is used only for SpeechModelInstaller (the app's own
// AssetInventory path for Apple's en-US speech model).
let package = Package(
    name: "EngineEval",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "engine-eval", targets: ["engine-eval"])],
    dependencies: [
        .package(path: "../CaptionCore"),
        // Same FluidAudio as the app (CaptionCore pins 0.17.5).
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.1"),
    ],
    targets: [
        // Pure: manifest, result lines, resume, status. No engine dependencies, fast tests.
        .target(name: "EngineEvalKit"),
        .target(
            name: "EngineEvalEngines",
            dependencies: [
                "EngineEvalKit",
                .product(name: "CaptionCore", package: "CaptionCore"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "engine-eval",
            dependencies: ["EngineEvalKit", "EngineEvalEngines"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "EngineEvalKitTests", dependencies: ["EngineEvalKit"]),
        // Opt-in (CAPTION_ENGINE_EVAL=1), same shape as CaptionCore's SpeakerModelComparisonTests.
        .testTarget(
            name: "EngineEvalEnginesTests",
            dependencies: ["EngineEvalKit", "EngineEvalEngines"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
