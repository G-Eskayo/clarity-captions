import EarSpikeKit
import Testing

@Suite struct VoiceCoverageTests {
    let voices = ["en-US", "en-GB", "es-ES", "es-MX", "pt-BR", "zh-CN", "zh-TW", "zh-HK", "he-IL", "ar-001", "nb-NO"]

    @Test func aLanguageWithAVoiceInItsOwnRegionMatches() {
        #expect(VoiceCoverage.voice(for: "es-ES", among: voices) == "es-ES")
    }

    @Test func aBareLanguageTakesAnyRegionsVoice() {
        #expect(VoiceCoverage.voice(for: "he", among: voices) == "he-IL")
        #expect(VoiceCoverage.voice(for: "pt", among: voices) == "pt-BR")
    }

    @Test func aRegionWithoutItsOwnVoiceFallsBackToTheLanguage() {
        #expect(VoiceCoverage.voice(for: "pt-PT", among: voices) == "pt-BR")
    }

    @Test func serbianHasNoVoice() {
        #expect(VoiceCoverage.voice(for: "sr", among: voices) == nil)
        #expect(VoiceCoverage.voice(for: "sr-Latn", among: voices) == nil)
    }

    @Test func traditionalChineseTakesTaiwanOrHongKongNotMainland() {
        let v = VoiceCoverage.voice(for: "zh-Hant", among: voices)
        #expect(v == "zh-TW")
        #expect(VoiceCoverage.voice(for: "zh-Hans", among: voices) == "zh-CN")
        #expect(VoiceCoverage.voice(for: "zh-Hant", among: ["zh-CN"]) == nil)
    }

    @Test func norwegianBokmalAndNorwegianMatch() {
        #expect(VoiceCoverage.voice(for: "no", among: voices) == "nb-NO")
        #expect(VoiceCoverage.voice(for: "nb", among: voices) == "nb-NO")
    }

    @Test func aBareLanguageTakesItsMainRegionFirst() {
        let both = ["es-MX", "es-ES", "fr-CA", "fr-FR", "zh-TW", "zh-CN", "pt-PT", "pt-BR"]
        #expect(VoiceCoverage.voice(for: "es", among: both) == "es-ES")
        #expect(VoiceCoverage.voice(for: "fr", among: both) == "fr-FR")
        #expect(VoiceCoverage.voice(for: "pt", among: both) == "pt-BR")
    }

    @Test func bareChineseIsSimplified() {
        #expect(VoiceCoverage.voice(for: "zh", among: ["zh-TW", "zh-CN"]) == "zh-CN")
        #expect(VoiceCoverage.voice(for: "zh-TW", among: ["zh-CN", "zh-TW"]) == "zh-TW")
        #expect(VoiceCoverage.voice(for: "zh", among: ["zh-TW"]) == nil)
    }

    @Test func underscoresAndCaseDontMatter() {
        #expect(VoiceCoverage.voice(for: "EN_gb", among: voices) == "en-GB")
    }
}
