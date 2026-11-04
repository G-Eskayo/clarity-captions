import CaptionCore
import Testing

/// #246: the mock-up options for a translated caption. What each option puts on screen, before any of it is drawn.
struct TranslatedCaptionLookTests {
    @Test func theDemoFlagNamesAnOptionByLetter() {
        #expect(TranslatedCaptionLook(flag: "a") == .bar)
        #expect(TranslatedCaptionLook(flag: "B") == .tag)
        #expect(TranslatedCaptionLook(flag: "c") == .folded)
        #expect(TranslatedCaptionLook(flag: "today") == .today)
    }

    @Test func anUnknownFlagIsNoOption() {
        #expect(TranslatedCaptionLook(flag: "d") == nil)
        #expect(TranslatedCaptionLook(flag: "") == nil)
        #expect(TranslatedCaptionLook(flag: nil) == nil)
    }

    @Test func theTagIsTheSaidLanguagesCode() {
        #expect(TranslatedCaptionLook.languageTag("es-ES") == "ES")
        #expect(TranslatedCaptionLook.languageTag("en_US") == "EN")
        #expect(TranslatedCaptionLook.languageTag("he") == "HE")
        // Cantonese and Chinese scripts keep their language code, not the script or region.
        #expect(TranslatedCaptionLook.languageTag("yue-Hant-HK") == "YUE")
        #expect(TranslatedCaptionLook.languageTag("") == nil)
    }

    @Test func todayAndTheBarAndTheTagAlwaysShowWhatWasSaid() {
        for look in [TranslatedCaptionLook.today, .bar, .tag] {
            #expect(look.showsSaid(opened: false))
            #expect(look.showsSaid(opened: true))
        }
    }

    @Test func foldedShowsWhatWasSaidOnlyOnceTheLineIsOpened() {
        #expect(!TranslatedCaptionLook.folded.showsSaid(opened: false))
        #expect(TranslatedCaptionLook.folded.showsSaid(opened: true))
    }

    @Test func onlyTodayPutsAMarkBeforeTheTranslation() {
        #expect(TranslatedCaptionLook.today.markBeforeTranslation)
        #expect(!TranslatedCaptionLook.bar.markBeforeTranslation)
        #expect(!TranslatedCaptionLook.tag.markBeforeTranslation)
        #expect(!TranslatedCaptionLook.folded.markBeforeTranslation)
    }
}
