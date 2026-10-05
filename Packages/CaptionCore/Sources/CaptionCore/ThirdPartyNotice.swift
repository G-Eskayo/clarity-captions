import Foundation

/// A third-party library notice with license details for in-app display.
public struct ThirdPartyNotice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let licenseName: String
    public let licenseURL: URL
    public let note: String
    public let sourceURL: URL?

    public static let all: [ThirdPartyNotice] = [
        ThirdPartyNotice(
            id: "sortformer",
            name: "Sortformer",
            licenseName: "CC BY 4.0",
            licenseURL: URL(string: "https://creativecommons.org/licenses/by/4.0/")!,
            note: "NVIDIA speaker-diarization model converted to CoreML format by FluidInference.",
            sourceURL: URL(string: "https://huggingface.co/nvidia/diar_streaming_sortformer_4spk-v2.1")
        ),
        ThirdPartyNotice(
            id: "fluidaudio",
            name: "FluidAudio",
            licenseName: "Apache 2.0",
            licenseURL: URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!,
            note: "Speech processing library, including bundled fastcluster (BSD) and VBx (Apache 2.0) components.",
            sourceURL: URL(string: "https://github.com/FluidInference/FluidAudio")
        ),
    ]
}
