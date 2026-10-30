import CaptionCore
import XCTest

/// #213: Live Translation on the Mac, room and calls. On a call the Mac hears two streams, the call's sound (the other
/// people) and its microphone (her), so it knows whose words are whose without guessing from voices. Owner's
/// decisions on #213: only the other people's speech is translated on a call, and the same purchase translates the
/// room too. Apple's speech engine can't detect a language (E27), so each side has its own From language.
final class MacTranslationTests: XCTestCase {
    private let en = Locale(identifier: "en-US")
    private let es = Locale(identifier: "es-MX")
    private let fr = Locale(identifier: "fr-FR")

    private func lines(_ said: [String]) -> [CaptionLine] {
        var s = CaptionStream()
        for (i, text) in said.enumerated() {
            s.apply(text: text, isFinal: true, speaker: i)
            s.breakLine()
        }
        return s.lines
    }

    // MARK: whose words are whose

    func testTheCallsSoundIsTheOtherPeopleAndTheMicIsHerOnACall() {
        XCTAssertEqual(MacAudioSide(source: .call, onCall: true), .theirs)
        XCTAssertEqual(MacAudioSide(source: .microphone, onCall: true), .yours)
    }

    func testOffACallTheMicIsTheRoom() {
        XCTAssertEqual(MacAudioSide(source: .microphone, onCall: false), .room)
    }

    func testSystemSoundOffACallStillCountsAsTheOtherPeople() {
        // `ListenTo.call` captions every sound the Mac plays, a video too: it's never her own voice.
        XCTAssertEqual(MacAudioSide(source: .call, onCall: false), .theirs)
    }

    // MARK: which captions get translated

    func testOnACallOnlyTheOtherPeoplesWordsAreTranslated() {
        let t = MacTranslation(room: es, call: es, into: en)
        XCTAssertEqual(t.pair(for: .theirs), MacTranslation.Pair(from: es, into: en))
        XCTAssertNil(t.pair(for: .yours), "owner, #213: her own words are never translated, even in another language")
    }

    func testTheRoomIsTranslatedTooWithTheSamePurchase() {
        let t = MacTranslation(room: fr, call: es, into: en)
        XCTAssertEqual(t.pair(for: .room), MacTranslation.Pair(from: fr, into: en))
    }

    func testEachSideIsTranslatedFromItsOwnLanguage() {
        let t = MacTranslation(room: fr, call: es, into: en)
        XCTAssertEqual(t.pair(for: .room)?.from, fr)
        XCTAssertEqual(t.pair(for: .theirs)?.from, es)
    }

    func testASideAlreadyInHerLanguageIsNotTranslated() {
        let t = MacTranslation(room: Locale(identifier: "en-GB"), call: es, into: en)
        XCTAssertNil(t.pair(for: .room), "English into English is the same words: no second line")
        XCTAssertNotNil(t.pair(for: .theirs))
    }

    func testChineseScriptsAreDifferentLanguagesForTranslation() {
        let t = MacTranslation(room: Locale(identifier: "zh-TW"), call: Locale(identifier: "zh-CN"), into: Locale(identifier: "zh-CN"))
        XCTAssertNotNil(t.pair(for: .room), "Traditional into Simplified Chinese is a real translation")
        XCTAssertNil(t.pair(for: .theirs))
    }

    func testOnlyTheLinesOfASidesPairGoToItsTranslator() {
        let said = lines(["¿Me oyes bien?", "Yes, I can hear you.", "Bonjour à tous."])
        let side: [Int: MacAudioSide] = [said[0].id: .theirs, said[1].id: .yours, said[2].id: .room]
        let t = MacTranslation(room: fr, call: es, into: en)
        let fromSpanish = t.lines(said, for: MacTranslation.Pair(from: es, into: en)) { side[$0.id] }
        XCTAssertEqual(fromSpanish.map(\.text), ["¿Me oyes bien?"])
        let fromFrench = t.lines(said, for: MacTranslation.Pair(from: fr, into: en)) { side[$0.id] }
        XCTAssertEqual(fromFrench.map(\.text), ["Bonjour à tous."])
    }

    func testWhenRoomAndCallShareALanguageOneTranslatorTakesBoth() {
        let said = lines(["Hola a todos.", "¿Qué tal?", "Fine, thanks."])
        let side: [Int: MacAudioSide] = [said[0].id: .room, said[1].id: .theirs, said[2].id: .yours]
        let t = MacTranslation(room: es, call: Locale(identifier: "es-ES"), into: en)
        XCTAssertEqual(t.pairs.count, 1, "one session, not two, for the same pair")
        XCTAssertEqual(t.lines(said, for: t.pairs[0]) { side[$0.id] }.map(\.text), ["Hola a todos.", "¿Qué tal?"])
    }

    func testALineWithNoKnownSideIsNotTranslated() {
        // Safer to leave a line untranslated than to translate her own words by mistake.
        let said = lines(["¿Me oyes?"])
        let t = MacTranslation(room: es, call: es, into: en)
        XCTAssertTrue(t.lines(said, for: MacTranslation.Pair(from: es, into: en)) { _ in nil }.isEmpty)
    }

    func testPairsListsEachNeededTranslatorOnceAndNoneWhenAllIsInHerLanguage() {
        XCTAssertEqual(MacTranslation(room: fr, call: es, into: en).pairs,
                       [MacTranslation.Pair(from: fr, into: en), MacTranslation.Pair(from: es, into: en)])
        XCTAssertEqual(MacTranslation(room: en, call: en, into: en).pairs, [])
    }

    // MARK: saved choices

    func testTheCallsLanguageIsSavedAndFollowsTheRoomUntilChosen() {
        let defaults = UserDefaults(suiteName: "MacTranslationTests-\(UUID().uuidString)")!
        let store = CaptionLanguageStore(defaults: defaults)
        XCTAssertNil(store.callLanguage)
        XCTAssertEqual(MacTranslation(store: store, room: fr, into: en).call, fr, "nothing picked: the call is the room's language")
        store.callLanguage = es
        XCTAssertEqual(CaptionLanguageStore(defaults: defaults).callLanguage.map(CaptionLanguage.bcp47), "es-MX")
        XCTAssertEqual(MacTranslation(store: store, room: fr, into: en).call.identifier(.bcp47), "es-MX")
        store.callLanguage = nil
        XCTAssertNil(store.callLanguage)
    }

    // MARK: its own purchase

    func testTheMacSellsTranslationAsItsOwnProduct() {
        // ADR 0028 / #176: the Mac app has its own App Store record and price ($1.99, owner 2026-10-30), so its own
        // product, never the iPhone's.
        XCTAssertNotEqual(TranslationPurchase.macProductID, TranslationPurchase.productID)
        XCTAssertTrue(TranslationPurchase.macProductID.hasPrefix("com.gileskayo.captions.mac."))
    }
}
