import CaptionCore
import XCTest

/// #60: the face-to-face split. Where the Face to face button shows (a screen big enough for two halves, with
/// translation on), which half each speaker belongs to, and what each half shows: its own speaker's words as said, the
/// other person's finished words translated (translation on top, what was said underneath), never the reverse.
final class FaceToFaceTests: XCTestCase {
    private func stream(_ build: (inout CaptionStream) -> Void) -> [CaptionLine] {
        var s = CaptionStream()
        build(&s)
        return s.lines
    }

    // MARK: where the button shows

    func testTheButtonShowsOnAnIPadSizedScreenWithTranslationOn() {
        // iPad Pro 13-inch, portrait and landscape.
        XCTAssertTrue(FaceToFace.offersSplit(width: 1032, height: 1376, translationOn: true))
        XCTAssertTrue(FaceToFace.offersSplit(width: 1376, height: 1032, translationOn: true))
        // iPad mini, the smallest iPad.
        XCTAssertTrue(FaceToFace.offersSplit(width: 744, height: 1133, translationOn: true))
    }

    func testTheButtonShowsOnAnUnfoldedDuo() {
        // iPhone Duo's inner screen, unfolded: 669 x 951 points.
        XCTAssertTrue(FaceToFace.offersSplit(width: 669, height: 951, translationOn: true))
        XCTAssertTrue(FaceToFace.offersSplit(width: 951, height: 669, translationOn: true))
    }

    func testPlainIPhonesAndAFoldedDuoStayOneWay() {
        // iPhone 17 Pro Max portrait and landscape (landscape is wide but short), folded Duo's outer screen.
        XCTAssertFalse(FaceToFace.offersSplit(width: 440, height: 956, translationOn: true))
        XCTAssertFalse(FaceToFace.offersSplit(width: 956, height: 440, translationOn: true))
        XCTAssertFalse(FaceToFace.offersSplit(width: 466, height: 678, translationOn: true))
    }

    func testTranslationOffMeansNoButtonEvenOnAnIPad() {
        XCTAssertFalse(FaceToFace.offersSplit(width: 1032, height: 1376, translationOn: false))
    }

    // MARK: which half a speaker belongs to

    func testNoSpeakerHasAHalfUntilOneIsGiven() {
        let sides = FaceToFaceSides()
        XCTAssertNil(sides.half(ofSpeaker: 0))
        XCTAssertNil(sides.half(ofSpeaker: nil))
    }

    func testAGivenSpeakerKeepsTheirHalfAndCanBeMoved() {
        var sides = FaceToFaceSides()
        sides.assign(speaker: 0, to: .partner)
        sides.assign(speaker: 1, to: .owner)
        XCTAssertEqual(sides.half(ofSpeaker: 0), .partner)
        XCTAssertEqual(sides.half(ofSpeaker: 1), .owner)
        sides.assign(speaker: 0, to: .owner)   // the voices were mixed up: move them
        XCTAssertEqual(sides.half(ofSpeaker: 0), .owner)
    }

    func testEachHalfFacesTheOtherOne() {
        XCTAssertEqual(FaceToFaceHalf.owner.other, .partner)
        XCTAssertEqual(FaceToFaceHalf.partner.other, .owner)
    }

    // MARK: what each half shows

    private func sides() -> FaceToFaceSides {
        var s = FaceToFaceSides()
        s.assign(speaker: 0, to: .partner)
        s.assign(speaker: 1, to: .owner)
        return s
    }

    /// Stand-in translator: the half it goes into, then the words.
    private func translate(_ line: CaptionLine, _ into: FaceToFaceHalf) -> String? { "\(into):\(line.text)" }

    func testOwnWordsShowAsSaidAndTheOtherPersonsShowTranslated() {
        let lines = stream {
            $0.apply(text: "hola", isFinal: true, speaker: 0)
            $0.apply(text: "hello", isFinal: true, speaker: 1)
        }
        let owner = FaceToFace.entries(for: .owner, lines: lines, sides: sides(), translation: translate)
        XCTAssertEqual(owner.map(\.text), ["owner:hola", "hello"])
        XCTAssertEqual(owner.map(\.said), ["hola", nil], "the translated line keeps what was said, to show underneath")
        XCTAssertEqual(owner.map(\.isTranslated), [true, false])
        XCTAssertEqual(owner.map(\.from), [.partner, .owner])

        let partner = FaceToFace.entries(for: .partner, lines: lines, sides: sides(), translation: translate)
        XCTAssertEqual(partner.map(\.text), ["hola", "partner:hello"])
        XCTAssertEqual(partner.map(\.isTranslated), [false, true])
    }

    func testWordsStillBeingSpokenShowAsSaidOnBothHalves() {
        let lines = stream { $0.apply(text: "hol", isFinal: false, speaker: 0) }
        for half in [FaceToFaceHalf.owner, .partner] {
            let entries = FaceToFace.entries(for: half, lines: lines, sides: sides(), translation: translate)
            XCTAssertEqual(entries.map(\.text), ["hol"])
            XCTAssertEqual(entries.map(\.isTranslated), [false])
            XCTAssertEqual(entries.map(\.isFinal), [false])
        }
    }

    func testAFinishedLineWaitingForItsTranslationShowsAsSaidUntilItArrives() {
        let lines = stream { $0.apply(text: "hola", isFinal: true, speaker: 0) }
        let entries = FaceToFace.entries(for: .owner, lines: lines, sides: sides()) { _, _ in nil }
        XCTAssertEqual(entries.map(\.text), ["hola"])
        XCTAssertEqual(entries.map(\.isTranslated), [false])
    }

    func testALineWithNoHalfYetShowsAsSaidOnBothHalvesAndIsNeverTranslated() {
        let lines = stream { $0.apply(text: "hola", isFinal: true, speaker: 7) }
        var asked = 0
        for half in [FaceToFaceHalf.owner, .partner] {
            let entries = FaceToFace.entries(for: half, lines: lines, sides: sides()) { line, into in
                asked += 1
                return self.translate(line, into)
            }
            XCTAssertEqual(entries.map(\.text), ["hola"])
            XCTAssertEqual(entries.map(\.isTranslated), [false])
            XCTAssertEqual(entries.map(\.from), [nil])
        }
        XCTAssertEqual(asked, 0, "nobody knows which language it is, so it isn't sent to a translator")
    }

    func testSoundLabelsShowOnBothHalvesUntranslated() {
        let lines = stream { $0.insertSoundLabel(.laughter) }
        for half in [FaceToFaceHalf.owner, .partner] {
            let entries = FaceToFace.entries(for: half, lines: lines, sides: sides(), translation: translate)
            XCTAssertEqual(entries.count, 1)
            XCTAssertEqual(entries[0].isTranslated, false)
            XCTAssertTrue(entries[0].isSoundLabel)
        }
    }

    func testEmptyLinesAreLeftOut() {
        let lines = stream { $0.apply(text: "  ", isFinal: false, speaker: 0) }
        XCTAssertTrue(FaceToFace.entries(for: .owner, lines: lines, sides: sides(), translation: translate).isEmpty)
    }

    func testEntriesKeepTheLinesIdsAndOrder() {
        let lines = stream {
            $0.apply(text: "uno", isFinal: true, speaker: 0)
            $0.apply(text: "two", isFinal: true, speaker: 1)
            $0.apply(text: "tres", isFinal: true, speaker: 0)
        }
        let entries = FaceToFace.entries(for: .partner, lines: lines, sides: sides(), translation: translate)
        XCTAssertEqual(entries.map(\.id), lines.map(\.id))
    }
}

/// #208 mock-up: the stacked list each half picks its language from. The downloaded translation languages, one row
/// per language, in the order of the names people read, without the language the other half already chose.
final class FaceToFaceChoicesTests: XCTestCase {
    private let downloaded = ["es-ES", "en-US", "fr-FR"].map(Locale.init(identifier:))
    private func name(_ l: Locale) -> String {
        ["en": "English", "es": "Español", "fr": "Français", "de": "Deutsch"][l.language.languageCode?.identifier ?? ""] ?? l.identifier
    }
    private func ids(_ ls: [Locale]) -> [String] { ls.map(\.identifier) }

    func testEveryDownloadedLanguageInNameOrderWhenNobodyHasChosen() {
        XCTAssertEqual(ids(FaceToFace.choices(downloaded: downloaded, takenByOtherHalf: nil, name: name)),
                       ["en-US", "es-ES", "fr-FR"])
    }

    func testTheOtherHalfsLanguageIsNotOffered() {
        // Even when the other half's locale is written differently (a region): it's the same language.
        let taken = Locale(identifier: "en-GB")
        XCTAssertEqual(ids(FaceToFace.choices(downloaded: downloaded, takenByOtherHalf: taken, name: name)), ["es-ES", "fr-FR"])
    }

    func testTwoRegionsOfOneLanguageAreOneRow() {
        let more = downloaded + [Locale(identifier: "es-MX")]
        XCTAssertEqual(ids(FaceToFace.choices(downloaded: more, takenByOtherHalf: nil, name: name)), ["en-US", "es-ES", "fr-FR"])
    }

    func testNothingDownloadedOffersNothing() {
        XCTAssertTrue(FaceToFace.choices(downloaded: [], takenByOtherHalf: nil, name: name).isEmpty)
        XCTAssertTrue(FaceToFace.choices(downloaded: [downloaded[1]], takenByOtherHalf: downloaded[1], name: name).isEmpty)
    }
}
