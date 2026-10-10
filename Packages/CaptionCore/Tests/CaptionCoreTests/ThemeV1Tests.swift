import XCTest
@testable import CaptionCore

/// v1 looks (#103, design #96): three light and three relaxed dark themes, each with its own gear, speaker-label and
/// [ Saved ] colors, and six lettering choices with OpenDyslexic as the default (#100).
final class ThemeV1Tests: XCTestCase {
    private let expectedIDs = ["paper", "seaglass", "peach", "charcoal", "night", "harbor"]

    func testThereAreThreeLightAndThreeDarkThemesInOrder() {
        XCTAssertEqual(CaptionPreset.all.map(\.id), expectedIDs)
        XCTAssertEqual(CaptionPreset.all.filter { !$0.background.isDark }.map(\.id), ["paper", "seaglass", "peach"])
        XCTAssertEqual(CaptionPreset.all.filter { $0.background.isDark }.map(\.id), ["charcoal", "night", "harbor"])
    }

    func testBrightAndClassicAreGone() {
        XCTAssertNil(CaptionPreset.all.first { $0.id == "bright" })
        XCTAssertNil(CaptionPreset.all.first { $0.id == "classic" })
    }

    func testColorsMatchTheApprovedMockups() {
        // docs/design/mocks/2026-10-09/src/build.mjs, THEMES
        let paper = CaptionPreset.named("paper")
        XCTAssertEqual(paper.background, RGBA(hex: "#FAF5E6"))
        XCTAssertEqual(paper.text, RGBA(hex: "#141419"))
        XCTAssertEqual(paper.gear, RGBA(hex: "#14514B"))
        XCTAssertEqual(paper.speakers, [RGBA(hex: "#14514B"), RGBA(hex: "#7A350C")])
        XCTAssertEqual(paper.saved, RGBA(hex: "#12512F"))
        let harbor = CaptionPreset.named("harbor")
        XCTAssertEqual(harbor.background, RGBA(hex: "#173331"))
        XCTAssertEqual(harbor.text, RGBA(hex: "#ECE4D3"))
        XCTAssertEqual(harbor.gear, RGBA(hex: "#F2DDB5"))
        XCTAssertEqual(harbor.saved, RGBA(hex: "#A6E8BC"))
    }

    /// The main screen's gear takes each theme's own color (mock-up 06), not the caption text color.
    func testEveryThemeHasTheMockupGearAndTheStyleUsesIt() {
        // docs/design/mocks/2026-10-09/src/build.mjs, THEMES[].gear
        let mockup = ["paper": "#14514B", "seaglass": "#0B4842", "peach": "#6E2E0A",
                      "charcoal": "#E2D9C6", "night": "#C9D6F2", "harbor": "#F2DDB5"]
        XCTAssertEqual(Set(CaptionPreset.all.map(\.id)), Set(mockup.keys))
        for p in CaptionPreset.all {
            XCTAssertEqual(p.gear, RGBA(hex: mockup[p.id]!), p.id)
            XCTAssertEqual(CaptionStyle.standard.applying(p).gear, p.gear, "\(p.id): the style hands the screen the theme's gear")
        }
        // Colors no theme has (an older build's custom look) keep a visible gear: the text color.
        var odd = CaptionStyle.standard
        odd.background = RGBA(0.5, 0.2, 0.7)
        XCTAssertNil(odd.preset)
        XCTAssertEqual(odd.gear, odd.text)
    }

    func testEveryColorDrawnOnEveryThemeIsAAA() {
        for p in CaptionPreset.all {
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.text, p.background), 7, "\(p.id) text")
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.gear, p.background), 7, "\(p.id) gear")
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.saved, p.background), 7, "\(p.id) [ Saved ] green")
            for (i, s) in p.speakers.enumerated() {
                XCTAssertGreaterThanOrEqual(RGBA.contrast(s, p.background), 7, "\(p.id) speaker \(i + 1)")
            }
        }
    }

    func testNoDarkThemeUsesPureBlackOrPureWhite() {
        for p in CaptionPreset.all where p.background.isDark {
            XCTAssertNotEqual(p.background, .black, "\(p.id)")
            XCTAssertNotEqual(p.text, .white, "\(p.id)")
        }
    }

    func testSpeakerColorsUseTheThemeFirstThenStayDistinctAndReadable() {
        for p in CaptionPreset.all {
            let colors = SpeakerPalette.colors(on: p.background, text: p.text)
            XCTAssertEqual(Array(colors.prefix(2)), p.speakers, "\(p.id): speakers 1 and 2 come from the theme")
            XCTAssertEqual(colors.count, 4)
            XCTAssertEqual(Set(colors.map { "\($0.r),\($0.g),\($0.b)" }).count, 4, "\(p.id) repeats a speaker color")
        }
    }

    func testStyleKnowsItsThemeColors() {
        let style = CaptionStyle.standard.applying(CaptionPreset.named("night"))
        XCTAssertEqual(style.preset?.id, "night")
        XCTAssertEqual(style.gear, CaptionPreset.named("night").gear)
        XCTAssertEqual(style.saved, CaptionPreset.named("night").saved)
    }

    func testUnfinishedCaptionsAreOnlyFirmedUpWhereNeeded() {
        for id in ["paper", "charcoal", "night", "harbor"] {
            XCTAssertEqual(CaptionStyle.standard.applying(CaptionPreset.named(id)).volatileOpacity, CaptionLine.volatileOpacity, id)
        }
        for id in ["seaglass", "peach"] {
            let opacity = CaptionStyle.standard.applying(CaptionPreset.named(id)).volatileOpacity
            XCTAssertGreaterThan(opacity, CaptionLine.volatileOpacity, id)
            XCTAssertLessThan(opacity, 0.8, "\(id): still visibly unfinished")
        }
    }

    func testStandardIsPaperWithOpenDyslexic() {
        // Owner's answer on PR #105 ("defaulttheme: Paper"), applied 2026-10-10.
        XCTAssertEqual(CaptionStyle.standard.preset?.id, "paper")
        XCTAssertEqual(CaptionStyle.standard.font, .openDyslexic)
    }

    // MARK: gummy button (style A, final)

    func testGummyLipIsTheFillShiftedAsInTheMockups() {
        // build.mjs lipColor(): a dark fill gets a lighter lip, a light fill a darker one, by 28%.
        XCTAssertEqual(RGBA(hex: "#141419").gummyLip.r, (20 + (255 - 20) * 0.28) / 255, accuracy: 0.003)
        XCTAssertEqual(RGBA(hex: "#E9E3D5").gummyLip.g, (227 * 0.72) / 255, accuracy: 0.003)
    }

    func testGummyLipStaysVisibleAgainstEveryTheme() {
        for p in CaptionPreset.all {
            // Start's fill is the theme's text color; its lip must read as a lip, not vanish into the background.
            XCTAssertGreaterThan(RGBA.contrast(p.text.gummyLip, p.background), 1.5, p.id)
            XCTAssertNotEqual(p.text.gummyLip, p.text, p.id)
        }
    }

    // MARK: quiet-stop choices, as the Settings mock-up labels them

    func testQuietStopShortLabelsMatchTheMockupAndVoiceOverKeepsTheFullWords() {
        XCTAssertEqual(IdleStopSetting.allCases.map(\.shortTitle), ["5 min", "15 min", "30 min", "Never"])
        XCTAssertEqual(IdleStopSetting.allCases.map(\.title), ["5 minutes", "15 minutes", "30 minutes", "Never"])
    }

    // MARK: lettering

    func testSixLetteringChoicesInOrderWithOpenDyslexicFirst() {
        XCTAssertEqual(CaptionFont.allCases, [.openDyslexic, .atkinsonHyperlegible, .system, .rounded, .serif, .monospaced])
        XCTAssertEqual(CaptionFont.allCases.map(\.label),
                       ["OpenDyslexic", "Atkinson Hyperlegible", "Standard", "Rounded", "Serif", "Typewriter"])
    }

    func testBundledFontsNameTheirFaces() {
        XCTAssertEqual(CaptionFont.openDyslexic.postScriptName(bold: false, italic: false), "OpenDyslexic-Regular")
        XCTAssertEqual(CaptionFont.openDyslexic.postScriptName(bold: true, italic: true), "OpenDyslexic-BoldItalic")
        XCTAssertEqual(CaptionFont.atkinsonHyperlegible.postScriptName(bold: false, italic: true), "AtkinsonHyperlegible-Italic")
        XCTAssertEqual(CaptionFont.atkinsonHyperlegible.postScriptName(bold: true, italic: false), "AtkinsonHyperlegible-Bold")
        for f in [CaptionFont.system, .rounded, .serif, .monospaced] {
            XCTAssertNil(f.postScriptName(bold: false, italic: false), "\(f) is a system design, not a bundled file")
        }
    }

    // MARK: one-time reset of looks saved before release (owner, 2026-10-10)

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "theme-v1-test-\(UUID())")! }

    /// A look saved under an older key, as the builds before release wrote it.
    private func saveOld(_ preset: CaptionPreset, font: String, size: Int = 3, key: String, in d: UserDefaults) {
        let b = preset.background, t = preset.text
        let json = """
        {"background":{"r":\(b.r),"g":\(b.g),"b":\(b.b),"a":1},\
        "text":{"r":\(t.r),"g":\(t.g),"b":\(t.b),"a":1},"size":\(size),"font":"\(font)","emphasisEffectsEnabled":false}
        """
        d.set(Data(json.utf8), forKey: key)
    }

    func testAFreshInstallStartsOnPaperWithOpenDyslexic() {
        let style = CaptionStyleStore(defaults: defaults()).load()
        XCTAssertEqual(style.preset?.id, "paper")
        XCTAssertEqual(style.font, .openDyslexic)
        XCTAssertEqual(style, .standard)
    }

    func testAnOlderSavedLookIsResetToTheDefaultOnce() {
        for key in CaptionStyleStore.retiredKeys {
            let d = defaults()
            saveOld(CaptionPreset.named("charcoal"), font: "system", key: key, in: d)
            XCTAssertEqual(CaptionStyleStore(defaults: d).load(), .standard,
                           "\(key): a look saved before release is replaced by Paper + OpenDyslexic")
            XCTAssertNil(d.data(forKey: key), "\(key) is cleared, so the reset happens only once")
        }
    }

    func testAChoiceMadeAfterTheResetPersists() {
        let d = defaults()
        saveOld(CaptionPreset.named("charcoal"), font: "system", key: "captionStyle.v2", in: d)
        let store = CaptionStyleStore(defaults: d)
        var style = store.load()
        style = style.applying(CaptionPreset.named("night"))
        style.font = .monospaced
        store.save(style)
        XCTAssertEqual(store.load(), style, "after the one-time reset, her own choice stays")
        XCTAssertEqual(CaptionStyleStore(defaults: d).load(), style, "and survives a relaunch")
    }

    func testTheCurrentKeyIsNotARetiredOne() {
        XCTAssertEqual(CaptionStyleStore.key, "captionStyle.v3")
        XCTAssertFalse(CaptionStyleStore.retiredKeys.contains(CaptionStyleStore.key))
        XCTAssertEqual(Set(CaptionStyleStore.retiredKeys), ["captionStyle.v1", "captionStyle.v2"])
    }

    func testCorruptSavedDataFallsBackToStandard() {
        let d = defaults()
        d.set(Data("nope".utf8), forKey: CaptionStyleStore.key)
        XCTAssertEqual(CaptionStyleStore(defaults: d).load(), .standard)
    }

    func testANewStyleWithUnknownFontFallsBackInsteadOfFailing() {
        let d = defaults()
        let json = """
        {"background":{"r":0.98,"g":0.96,"b":0.90,"a":1},"text":{"r":0.08,"g":0.08,"b":0.1,"a":1},"size":2,"font":"comicSans","emphasisEffectsEnabled":true}
        """
        d.set(Data(json.utf8), forKey: CaptionStyleStore.key)
        let style = CaptionStyleStore(defaults: d).load()
        XCTAssertEqual(style.font, .openDyslexic)
        XCTAssertEqual(style.preset?.id, "paper")
    }
}
