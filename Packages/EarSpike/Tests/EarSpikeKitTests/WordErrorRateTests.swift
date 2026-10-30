import EarSpikeKit
import Testing

@Suite struct WordErrorRateTests {
    @Test func identicalIsZero() { #expect(WordErrorRate.of("The birch canoe slid", reference: "the birch canoe slid.") == 0) }
    @Test func oneSubstitutionInFour() { #expect(WordErrorRate.of("the birch canoe hid", reference: "the birch canoe slid") == 0.25) }
    @Test func deletionsAndInsertionsCount() {
        #expect(WordErrorRate.of("birch canoe", reference: "the birch canoe slid") == 0.5)
        #expect(WordErrorRate.of("the big birch canoe slid", reference: "the birch canoe slid") == 0.25)
    }
    @Test func emptyHypothesisIsOne() { #expect(WordErrorRate.of("", reference: "a b") == 1) }
    @Test func numbersAsDigitsMatchWords() { #expect(WordErrorRate.of("at 7", reference: "at seven") == 0) }
}
