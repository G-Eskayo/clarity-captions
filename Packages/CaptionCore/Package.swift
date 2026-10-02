// swift-tools-version: 6.2
import PackageDescription

// Platform-agnostic core (ADR 0010): capture, transcription, caption-stream model.
// Neutral name on purpose (ADR 0011) -- the store name is not decided yet.
let package = Package(
    name: "CaptionCore",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [.library(name: "CaptionCore", targets: ["CaptionCore"])],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.5"),
    ],
    targets: [
        .target(
            name: "CaptionCore",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CaptionCoreTests",
            dependencies: ["CaptionCore", .product(name: "FluidAudio", package: "FluidAudio")]
        ),
    ]
)
