import Foundation
import Testing
@testable import SystemReplayKit

/// The replay must arrive like a microphone: buffer k is handed over when its last sample has been "spoken", at
/// (k + 1) x buffer duration after the start, never earlier, and slow work in a callback must not push every later
/// buffer back (a fixed sleep after each buffer did: the app's FileAudioSource drifts slower than real time, and the
/// engine's lag clock, wall time minus audio time, then grows by the drift).
@Suite struct PacingTests {
    @Test func bufferIsDueWhenItsLastSampleWasSpoken() {
        let s = ReplaySchedule(sampleRate: 48_000, framesPerBuffer: 4_800)
        #expect(s.bufferSeconds == 0.1)
        #expect(abs(s.due(buffer: 0) - 0.1) < 1e-12)
        #expect(abs(s.due(buffer: 9) - 1.0) < 1e-12)
    }

    @Test func lastBufferIsShortAndCountIsCeiling() {
        let s = ReplaySchedule(sampleRate: 16_000, framesPerBuffer: 4_096)
        #expect(s.bufferCount(totalFrames: 10_000) == 3)
        #expect(s.frames(inBuffer: 2, totalFrames: 10_000) == 10_000 - 2 * 4_096)
        #expect(s.frames(inBuffer: 3, totalFrames: 10_000) == 0)
        #expect(s.bufferCount(totalFrames: 0) == 0)
        // The short last buffer is due when its own last sample was spoken, not a whole buffer later.
        #expect(abs(s.due(buffer: 2, totalFrames: 10_000) - 10_000.0 / 16_000) < 1e-12)
    }

    @Test func slowCallbacksDoNotAccumulateDrift() {
        // A fake clock: every callback costs 30 ms of a 100 ms buffer. Deadline pacing keeps buffer k at its due time.
        var clock = 0.0
        var delivered: [Double] = []
        let s = ReplaySchedule(sampleRate: 16_000, framesPerBuffer: 1_600)
        PacedLoop.run(schedule: s, totalFrames: 1_600 * 600, now: { clock }, sleepUntil: { clock = max(clock, $0) },
                      shouldContinue: { true }) { _, _ in
            delivered.append(clock)
            clock += 0.030
        }
        #expect(delivered.count == 600)
        for (k, t) in delivered.enumerated() { #expect(abs(t - s.due(buffer: k)) < 1e-9) }
    }

    @Test func aCallbackSlowerThanRealTimeIsLateButCatchesUp() {
        // One 350 ms stall (a model load, a GC pause): the next buffers go at once until the schedule is met again,
        // the way a real mic's queued buffers arrive in a burst. Nothing is dropped.
        var clock = 0.0
        var delivered: [Double] = []
        let s = ReplaySchedule(sampleRate: 16_000, framesPerBuffer: 1_600)
        PacedLoop.run(schedule: s, totalFrames: 1_600 * 10, now: { clock }, sleepUntil: { clock = max(clock, $0) },
                      shouldContinue: { true }) { k, _ in
            delivered.append(clock)
            if k == 2 { clock += 0.350 }
        }
        #expect(delivered.count == 10)
        #expect(abs(delivered[3] - 0.65) < 1e-9)   // late: the stall ended at 0.3 + 0.35
        #expect(abs(delivered[6] - 0.7) < 1e-9)    // back on schedule
        #expect(abs(delivered[9] - 1.0) < 1e-9)
    }

    @Test func stopEndsTheLoopBeforeTheNextBuffer() {
        var clock = 0.0
        var count = 0
        let s = ReplaySchedule(sampleRate: 16_000, framesPerBuffer: 1_600)
        PacedLoop.run(schedule: s, totalFrames: 1_600 * 100, now: { clock }, sleepUntil: { clock = max(clock, $0) },
                      shouldContinue: { count < 5 }) { _, _ in count += 1 }
        #expect(count == 5)
    }

    @Test func framesHandedOverCoverTheFileExactlyOnce() {
        var clock = 0.0
        var spans: [Range<Int>] = []
        let s = ReplaySchedule(sampleRate: 48_000, framesPerBuffer: 4_096)
        let total = 48_000 * 3 + 17
        PacedLoop.run(schedule: s, totalFrames: total, now: { clock }, sleepUntil: { clock = max(clock, $0) },
                      shouldContinue: { true }) { _, span in spans.append(span) }
        #expect(spans.first?.lowerBound == 0)
        #expect(spans.last?.upperBound == total)
        for (a, b) in zip(spans, spans.dropFirst()) { #expect(a.upperBound == b.lowerBound) }
    }
}
