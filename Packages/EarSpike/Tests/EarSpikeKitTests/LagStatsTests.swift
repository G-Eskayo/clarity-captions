import EarSpikeKit
import Testing

@Suite struct LagStatsTests {
    @Test func medianAndP95() {
        let s = LagStats((1...100).map(Double.init))
        #expect(s.median == 50.5)
        #expect(s.p95 == 95.05)
        #expect(s.count == 100)
    }

    @Test func oneSample() {
        let s = LagStats([7])
        #expect(s.median == 7 && s.p95 == 7)
    }

    @Test func noSamplesIsNil() {
        #expect(LagStats([]).median == nil)
    }
}
