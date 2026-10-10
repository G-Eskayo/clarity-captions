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
            note: String(localized: "NVIDIA speaker-diarization model converted to CoreML format by FluidInference."),
            sourceURL: URL(string: "https://huggingface.co/nvidia/diar_streaming_sortformer_4spk-v2.1")
        ),
        ThirdPartyNotice(
            id: "fluidaudio",
            name: "FluidAudio",
            licenseName: "Apache 2.0",
            licenseURL: URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!,
            note: String(localized: "Speech processing library, including bundled fastcluster (BSD) and VBx (Apache 2.0) components."),
            sourceURL: URL(string: "https://github.com/FluidInference/FluidAudio")
        ),
        ThirdPartyNotice(
            id: "nemotextprocessing",
            name: "NeMo Text Processing",
            licenseName: "Apache 2.0 / MIT",
            licenseURL: URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!,
            note: String(localized: "Text-normalization grammars from NVIDIA NeMo Text Processing, with the rustfst and flate2 libraries, linked in through FluidAudio."),
            sourceURL: URL(string: "https://github.com/NVIDIA/NeMo-text-processing")
        ),
        ThirdPartyNotice(
            id: "opendyslexic",
            name: "OpenDyslexic",
            licenseName: "Bitstream Vera License",
            licenseURL: URL(string: "https://github.com/antijingoist/open-dyslexic/blob/e98e98ce61/README.md#license")!,
            note: String(localized: "Font by Abbie Gonzalez (classic version 2.020, based on Bitstream Vera Sans), bundled in the app as a lettering choice."),
            sourceURL: URL(string: "https://github.com/antijingoist/open-dyslexic")
        ),
        ThirdPartyNotice(
            id: "atkinsonhyperlegible",
            name: "Atkinson Hyperlegible",
            licenseName: "SIL OFL 1.1",
            licenseURL: URL(string: "https://openfontlicense.org")!,
            note: String(localized: "Font by the Braille Institute of America, bundled in the app as a lettering choice."),
            sourceURL: URL(string: "https://github.com/googlefonts/atkinson-hyperlegible")
        ),
    ]
}
