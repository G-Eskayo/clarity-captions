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

    @Test func underscoresAndCaseDontMatter() {
        #expect(VoiceCoverage.voice(for: "EN_gb", among: voices) == "en-GB")
    }
}
