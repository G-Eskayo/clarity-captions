import Foundation

/// One line on the Credits page, as approved in #120 (mock-up round3/04): a name and one short line, in the same
/// borderless style as the saved list. The full license texts (NOTICE.md) are one tap further and carry every notice.
public struct CreditsEntry: Identifiable, Equatable, Sendable {
    public let name: String
    public let line: String
    /// The ThirdPartyNotice this entry credits; nil for Apple's own frameworks, which need no notice.
    public let noticeID: String?
    public var id: String { name }

    public static var intro: String { String(localized: "Seal is built on free, open work by these people.") }

    public static var all: [CreditsEntry] {
        [
            CreditsEntry(name: "Apple Speech", line: String(localized: "Speech to text, on this phone."), noticeID: nil),
            CreditsEntry(name: "FluidAudio", line: String(localized: "Telling voices apart. Apache 2.0."), noticeID: "fluidaudio"),
            CreditsEntry(name: "Sortformer (NVIDIA)", line: String(localized: "The voice model. CC BY 4.0."), noticeID: "sortformer"),
            CreditsEntry(name: "OpenDyslexic", line: String(localized: "Abbie Gonzalez. Bitstream Vera license."), noticeID: "opendyslexic"),
            CreditsEntry(name: "Atkinson Hyperlegible", line: String(localized: "Braille Institute. SIL Open Font License."),
                         noticeID: "atkinsonhyperlegible"),
        ]
    }

    /// Bundled works credited only in the full license texts (NOTICE.md), not on the page: the mock-up lists five.
    /// NeMo Text Processing comes in through FluidAudio; whether it gets its own line is a Decision on the PR.
    public static let coveredByFullLicenseTexts: Set<String> = ["nemotextprocessing"]
}
