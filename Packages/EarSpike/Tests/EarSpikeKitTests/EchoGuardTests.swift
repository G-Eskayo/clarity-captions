import EarSpikeKit
import Testing

@Suite struct EchoGuardTests {
    @Test func aCaptionOfWhatTheAppJustSaidIsEcho() {
        var guardian = EchoGuard()
        guardian.spoke("¿Dónde está la estación de tren?", from: 10.0, to: 12.0)
        #expect(guardian.isEcho("donde esta la estacion de tren", from: 10.4, to: 12.3))
    }

    @Test func realSpeechWhileTheAppSpeaksIsNotEcho() {
        var guardian = EchoGuard()
        guardian.spoke("¿Dónde está la estación de tren?", from: 10.0, to: 12.0)
        #expect(!guardian.isEcho("Can you tell me how to get there", from: 10.5, to: 12.5))
    }

    @Test func theSameWordsLongAfterTheAppSpokeAreNotEcho() {
        var guardian = EchoGuard()
        guardian.spoke("Thank you very much", from: 10.0, to: 11.0)
        // The other person says the same words a few seconds later: a real line.
        #expect(!guardian.isEcho("thank you very much", from: 15.0, to: 16.0))
    }

    @Test func theRoomTailCountsAsTheAppSpeaking() {
        var guardian = EchoGuard(tail: 0.8)
        guardian.spoke("Thank you very much", from: 10.0, to: 11.0)
        #expect(guardian.isEcho("thank you very much", from: 11.5, to: 12.0))
        #expect(!guardian.isEcho("thank you very much", from: 11.9, to: 12.5))
    }

    @Test func aPartialMisheardEchoStillMatches() {
        var guardian = EchoGuard()
        guardian.spoke("The train leaves at seven from platform two", from: 0, to: 3)
        // Recognisers drop and mishear words in the speaker-to-mic path.
        #expect(guardian.isEcho("the train leaves at 7 from platform", from: 0.3, to: 3.1))
    }

    @Test func oneSharedCommonWordIsNotEnough() {
        var guardian = EchoGuard()
        guardian.spoke("The train leaves at seven", from: 0, to: 2)
        #expect(!guardian.isEcho("the", from: 0.5, to: 0.8))
        #expect(!guardian.isEcho("I think the soup is cold", from: 0.5, to: 2.0))
    }

    @Test func emptyCaptionIsNotEcho() {
        var guardian = EchoGuard()
        guardian.spoke("Hello", from: 0, to: 1)
        #expect(!guardian.isEcho("   ", from: 0, to: 1))
    }

    @Test func oldUtterancesAreForgotten() {
        var guardian = EchoGuard(tail: 0.5)
        for i in 0..<100 { guardian.spoke("line \(i)", from: Double(i), to: Double(i) + 0.5) }
        guardian.forget(before: 90)
        #expect(guardian.count <= 11)
    }

    @Test func similarityIsTheShareOfCaptionWordsTheAppSaid() {
        #expect(EchoGuard.similarity(caption: "a b c d", spoken: "a b x y") == 0.5)
        #expect(EchoGuard.similarity(caption: "Hello, WORLD!", spoken: "hello world") == 1)
        #expect(EchoGuard.similarity(caption: "", spoken: "hello") == 0)
    }

    // The caption engine runs in the other person's language, so it hears the app's Spanish voice as English-sounding
    // nonsense (echo-digital-mac.json). The app captions its own rendered voice first and remembers what it heard.
    @Test func gibberishOfTheAppsVoiceMatchesWhatTheAppHeardItselfSay() {
        var guardian = EchoGuard()
        guardian.spoke("¿Nos trae la cuenta, por favor?", heardAs: "No, strike, la quanta, perfavor.", from: 10, to: 12)
        #expect(guardian.isEcho("No strike la quanta per favor", from: 10.3, to: 12.4))
    }

    @Test func heardAsDoesNotMakeRealSpeechEcho() {
        var guardian = EchoGuard()
        guardian.spoke("¿Nos trae la cuenta, por favor?", heardAs: "No, strike, la quanta, perfavor.", from: 10, to: 12)
        #expect(!guardian.isEcho("Can we get the bill please", from: 10.3, to: 12.4))
    }

    @Test func heardAsStillNeedsTheTimeOverlap() {
        var guardian = EchoGuard(tail: 0.8)
        guardian.spoke("¿Nos trae la cuenta, por favor?", heardAs: "No, strike, la quanta, perfavor.", from: 10, to: 12)
        #expect(!guardian.isEcho("No strike la quanta per favor", from: 14, to: 15))
    }

    // Sound-alike nonsense changes its word breaks between the clean render and the way back through a mic, but keeps
    // most of its letters (echo-fingerprint-mac.json): "yudadamuto" comes back as "yugada mucho".
    @Test func soundAlikeNonsenseWithOtherWordBreaksIsEcho() {
        var guardian = EchoGuard()
        guardian.spoke("Muchísimas gracias, me ha ayudado mucho.", heardAs: "Mutissimas gracias, mera yudadamuto.",
                       from: 0, to: 3)
        #expect(guardian.isEcho("Mutisimas gracias, mira, yugada mucho.", from: 0.2, to: 3.2))
    }

    @Test func realEnglishOverTheVoiceStaysACaption() {
        var guardian = EchoGuard()
        guardian.spoke("Muchísimas gracias, me ha ayudado mucho.", heardAs: "Mutissimas gracias, mera yudadamuto.",
                       from: 0, to: 3)
        for line in ["Thank you so much, that was really helpful.", "Where is the train station?",
                     "My daughter is coming to visit next week."] {
            #expect(!guardian.isEcho(line, from: 0.2, to: 3.2))
        }
    }

    @Test func letterSimilarityIgnoresSpacesAndAccents() {
        #expect(EchoGuard.soundsLike(caption: "yugada mucho", spoken: "yudadamuto") > 0.3)
        #expect(EchoGuard.soundsLike(caption: "Dónde", spoken: "donde") == 1)
        #expect(EchoGuard.soundsLike(caption: "ab", spoken: "ab") == 0) // too short for one trigram
    }
}
