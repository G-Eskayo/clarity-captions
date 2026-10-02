// swift-tools-version: 6.2
import PackageDescription

// Platform-agnostic core (ADR 0010): capture, transcription, caption-stream model.
// Neutral name on purpose (ADR 0011) -- the store name is not decided yet.
let package = Package(
    name: "CaptionCore",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [.library(name: "CaptionCore", targets: ["CaptionCore"])],
    targets: [
        .target(name: "CaptionCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "CaptionCoreTests", dependencies: ["CaptionCore"]),
    ]
)
