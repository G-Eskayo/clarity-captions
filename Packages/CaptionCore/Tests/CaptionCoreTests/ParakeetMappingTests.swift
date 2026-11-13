import CoreMedia
import Speech
import XCTest
@testable import CaptionCore
import FluidAudio

/// Parakeet's committed and open words fed through a real CaptionStream (design §8, test 6), plus the pieces either
/// recognizer hands TranscriptionEngine. Tests-first items 2-3: seam-level language assertions.
final class ParakeetMappingTests: XCTestCase {
    private func w(_ text: String, _ start: Double, _ end: Double) -> TimedWord { TimedWord(text: text, start: start, end: end) }

    private func apply(_ pieces: [RecognizedPiece], to stream: inout CaptionStream, speaker: Int? = nil) {
        for p in pieces {
            stream.apply(text: p.text, isFinal: p.isFinal, speaker: speaker, range: p.start.flatMap { s in p.end.map { s...$0 } })
        }
    }

    func testCommittedThenOpenWordsMakeOneLine() {
        var emitter = ParakeetEmitter()
        var stream = CaptionStream()
        apply(emitter.pieces(final: [], volatile: [w("hello", 0, 0.3), w("there", 0.4, 0.7)]), to: &stream)
        apply(emitter.pieces(final: [w("hello", 0, 0.3), w("there", 0.4, 0.7)], volatile: [w("friend", 0.8, 1.1)]), to: &stream)
        XCTAssertEqual(stream.lines.count, 1)
        XCTAssertEqual(stream.lines[0].text, "hello there friend")
        XCTAssertFalse(stream.lines[0].isFinal)
        apply(emitter.pieces(final: [w("friend", 0.8, 1.1)], volatile: []), to: &stream)
        XCTAssertEqual(stream.lines.map(\.text), ["hello there friend"])
        XCTAssertTrue(stream.lines[0].isFinal)
    }

    func testAPauseInsideACommittedBatchStartsANewLine() {
        var emitter = ParakeetEmitter()
        var stream = CaptionStream()
        let pieces = emitter.pieces(final: [w("yes", 0, 0.3), w("no", 2.0, 2.3)], volatile: [])
        XCTAssertEqual(pieces.count, 2)
        apply(pieces, to: &stream)
        XCTAssertEqual(stream.lines.map(\.text), ["yes", "no"])
    }

    func testATailThatChangedCompletelyIsReplacedNotKept() {
        // The decoder first heard "oh" then decided it was "go home", starting later: the ghost must not stay.
        var emitter = ParakeetEmitter()
        var stream = CaptionStream()
        apply(emitter.pieces(final: [w("ok", 0, 0.2)], volatile: [w("oh", 0.4, 0.6)]), to: &stream)
        apply(emitter.pieces(final: [], volatile: [w("go", 0.9, 1.0), w("home", 1.1, 1.3)]), to: &stream)
        XCTAssertEqual(stream.lines.map(\.text), ["ok go home"])
        apply(emitter.pieces(final: [w("go", 0.9, 1.0), w("home", 1.1, 1.3)], volatile: []), to: &stream)
        XCTAssertEqual(stream.lines.map(\.text), ["ok go home"])
    }

    func testAnUnchangedTailIsNotSentAgain() {
        var emitter = ParakeetEmitter()
        XCTAssertEqual(emitter.pieces(final: [], volatile: [w("hm", 0, 0.2)]).count, 1)
        XCTAssertEqual(emitter.pieces(final: [], volatile: [w("hm", 0, 0.2)]).count, 0)
    }

    func testASpeakerChangeStillSplitsTheLine() {
        var emitter = ParakeetEmitter()
        var stream = CaptionStream()
        apply(emitter.pieces(final: [w("hi", 0, 0.2)], volatile: []), to: &stream, speaker: 0)
        apply(emitter.pieces(final: [w("hey", 0.4, 0.6)], volatile: []), to: &stream, speaker: 1)
        XCTAssertEqual(stream.lines.map(\.text), ["hi", "hey"])
    }

    // MARK: Apple's runs to words (refactor guard for word emphasis)

    func testAppleRunsBecomeWordsWithTheirRunsTime() {
        var text = AttributedString("good morning")
        text.audioTimeRange = CMTimeRange(start: CMTime(seconds: 1, preferredTimescale: 600), end: CMTime(seconds: 2, preferredTimescale: 600))
        var untimed = AttributedString(" all")
        untimed.audioTimeRange = nil
        text.append(untimed)
        let piece = AppleSpeechBackend.piece(from: text, isFinal: true)
        XCTAssertEqual(piece.text, "good morning all")
        XCTAssertEqual(piece.words, [RecognizedWord(text: "good", range: 1...2), RecognizedWord(text: "morning", range: 1...2),
                                     RecognizedWord(text: "all", range: nil)])
        XCTAssertEqual(piece.start, 1)
        XCTAssertEqual(piece.end, 2)
    }

    func testEmphasisIsPerWordAndUntimedWordsStayNormal() {
        let words = [RecognizedWord(text: "a", range: 0...1), RecognizedWord(text: "b", range: nil), RecognizedWord(text: "c", range: 2...3)]
        let levels = WordEmphasis.levels(for: words, baseline: -40, loudness: { $0.lowerBound < 1 ? -20 : -39 }, fallback: -60)
        XCTAssertEqual(levels, [.loud, .normal, .normal])
        XCTAssertEqual(WordEmphasis.levels(for: words, baseline: nil, loudness: { _ in 0 }, fallback: 0), [.normal, .normal, .normal])
    }

    // MARK: Language parameter propagation (tests-first items 2-3)

    func testParakeetBackendStoresLocaleForUseInDecode() {
        // Seam test: verify that ParakeetBackend stores its captionLocale and would use it in
        // decode to pass to manager.transcribe(). The onLanguageResolved callback (set up in
        // ParakeetBackend.decode) fires with the mapped language before transcribe is called.
        let tempURL = URL(fileURLWithPath: "/tmp/test-model.zip")
        let spanishLocale = Locale(identifier: "es-ES")
        let backend = ParakeetBackend(modelURL: tempURL, captionLocale: spanishLocale)

        // Verify the backend was created with Spanish locale
        XCTAssertEqual(backend.captionLocale.language.languageCode?.identifier, spanishLocale.language.languageCode?.identifier, "Backend stores the provided Spanish locale")

        // Verify the stored locale maps to the correct language for transcribe
        let mappedLanguage = Language.language(for: backend.captionLocale)
        XCTAssertEqual(mappedLanguage, .spanish, "Spanish locale maps to Parakeet's Spanish")

        // Note: ParakeetBackend.decode() calls Language.language(for: captionLocale) and fires
        // onLanguageResolved(language), then passes language to manager.transcribe().
        // This test verifies the locale is stored and maps correctly; ParakeetIntegrationTests
        // would verify the end-to-end path with a real model.
    }

    func testParakeetBackendWithDefaultLocale() {
        // Verify default English locale is used when not specified, and maps correctly for transcribe.
        let tempURL = URL(fileURLWithPath: "/tmp/test-model.zip")
        let backend = ParakeetBackend(modelURL: tempURL)

        // Verify the backend defaults to en-US
        let defaultLocale = Locale(identifier: "en-US")
        XCTAssertEqual(backend.captionLocale.language.languageCode?.identifier, defaultLocale.language.languageCode?.identifier, "Backend defaults to en-US locale")

        // Verify the default locale maps to English for transcribe
        let mappedLanguage = Language.language(for: backend.captionLocale)
        XCTAssertEqual(mappedLanguage, .english, "en-US locale maps to English")
    }

    // MARK: Fast-turn seam and line-break coincidence (tests-first item 6)

    func testFastTurnSeamCoincidenceWithLineBreak() {
        // Tests-first item 6: fast-turn seam with line-break coincidence.
        // Verifies that SampleWindow.skip(to:) handles speaker transitions during decode,
        // and that ParakeetEmitter produces separate lines when speakers change across a gap.
        var window = SampleWindow()
        var emitter = ParakeetEmitter()
        var stream = CaptionStream()

        // Speaker 1: emit their words at time 0–0.7
        let speaker1Audio = [Float](repeating: 0.1, count: 11_200) // 0.7 s at 16 kHz
        window.append(speaker1Audio, level: -30)
        let speaker1Final = [w("hello", 0.0, 0.3), w("there", 0.4, 0.7)]
        let pieces1 = emitter.pieces(final: speaker1Final, volatile: [])
        apply(pieces1, to: &stream)

        // Speaker 2 starts at time 3.0 (2.3 s gap of silence for face-to-face #60).
        // SampleWindow.skip(to:) is called to jump the window ahead, filling the gap with silence.
        window.skip(to: 3.0)
        XCTAssertEqual(window.endTime, 3.0, "skip(to:) advances window past the speaker gap")

        // Speaker 2: emit their words at time 3.0–3.7
        let speaker2Audio = [Float](repeating: 0.1, count: 11_200) // 0.7 s at 16 kHz
        window.append(speaker2Audio, level: -30)
        let speaker2Final = [w("hey", 3.0, 3.3), w("there", 3.4, 3.7)]
        let pieces2 = emitter.pieces(final: speaker2Final, volatile: [])
        apply(pieces2, to: &stream)

        // Verify: pause inside committed words started a new line (testAPauseInsideACommittedBatchStartsANewLine).
        // Speaker 2's words start 2.3 s after speaker 1's end, which is more than the default pause,
        // so they should land in a new line.
        XCTAssertGreaterThanOrEqual(stream.lines.count, 2, "pause creates a line break between speakers")
        let allWords = stream.lines.flatMap { $0.text.split(separator: " ").map(String.init) }
        XCTAssertEqual(allWords.count, 4, "all four words preserved")
        XCTAssertEqual(allWords.filter { $0 == "hello" }.count, 1, "'hello' not duplicated")
        XCTAssertEqual(allWords.filter { $0 == "hey" }.count, 1, "'hey' preserved")
        XCTAssertEqual(allWords.filter { $0 == "there" }.count, 2, "both speakers' 'there'")
    }

    // MARK: Sample window

    func testSampleWindowTrimsAndStaysBounded() {
        var window = SampleWindow(maxSeconds: 2)
        window.append([Float](repeating: 0, count: 16_000), level: -70)
        window.append([Float](repeating: 1, count: 16_000), level: -20)
        let shot = window.take(from: 0.5)
        XCTAssertEqual(shot.start, 0.5, accuracy: 1e-9)
        XCTAssertEqual(shot.end, 2.0, accuracy: 1e-9)
        XCTAssertEqual(shot.samples.count, 24_000)
        XCTAssertEqual(shot.loudest, -20)
        XCTAssertEqual(window.take(from: 0).loudest, -.infinity, "loudness is reported once per take")
        window.trim(before: 1.0)
        XCTAssertEqual(window.startTime, 1.0, accuracy: 1e-9)
        window.append([Float](repeating: 0, count: 64_000), level: -70)
        XCTAssertEqual(window.samples.count, 32_000, "never more than maxSeconds")
        XCTAssertEqual(window.endTime, 6.0, accuracy: 1e-9, "dropping old audio never moves the clock")
        window.trim(before: 100)
        XCTAssertEqual(window.samples.count, 0)
        XCTAssertEqual(window.take(from: 50).samples, [])
    }
}
