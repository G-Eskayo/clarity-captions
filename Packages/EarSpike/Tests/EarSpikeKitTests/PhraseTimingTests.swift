import EarSpikeKit
import Testing

@Suite struct PhraseTimingTests {
    @Test func theFirstWordsAreStableFromTheLastUpdateThatChangedThem() {
        let updates: [(t: Double, text: String)] = [
            (1.0, "where"), (1.3, "where is"), (1.6, "wear is the"), (1.9, "where is the train"),
            (2.2, "where is the train station"),
        ]
        // The first three words read "where is the" for good from 1.9 s.
        #expect(PhraseTiming.stableAt(updates: updates, final: "Where is the train station?", words: 3) == 1.9)
    }

    @Test func aLaterWobbleMovesTheTimeLater() {
        let updates: [(t: Double, text: String)] = [(1.0, "can we get"), (1.5, "can we gets"), (2.0, "can we get the")]
        #expect(PhraseTiming.stableAt(updates: updates, final: "Can we get the bill", words: 3) == 2.0)
    }

    @Test func neverRightBeforeTheFinalIsNil() {
        let updates: [(t: Double, text: String)] = [(1.0, "is this"), (1.5, "is this seed")]
        #expect(PhraseTiming.stableAt(updates: updates, final: "Is this seat taken?", words: 3) == nil)
    }

    @Test func aLineShorterThanThePhraseIsNil() {
        #expect(PhraseTiming.stableAt(updates: [(1.0, "yes")], final: "Yes.", words: 3) == nil)
    }
}
