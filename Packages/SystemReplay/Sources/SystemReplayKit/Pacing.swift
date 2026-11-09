/// When each buffer of a replayed recording is handed to the app (#273). A microphone delivers a buffer once its
/// last sample has been spoken, so buffer k (frames k*n ..< (k+1)*n) is due (k+1)*n / rate seconds after the start.
/// Deadline pacing against this schedule, not a fixed sleep after each buffer: work done in the callback must not
/// push every later buffer back, or the replay runs slower than real time and the engine's lag clock (wall time
/// minus audio time) grows by the drift.
public struct ReplaySchedule: Sendable, Equatable {
    public let sampleRate: Double
    public let framesPerBuffer: Int

    public init(sampleRate: Double, framesPerBuffer: Int) {
        precondition(sampleRate > 0 && framesPerBuffer > 0)
        self.sampleRate = sampleRate
        self.framesPerBuffer = framesPerBuffer
    }

    public var bufferSeconds: Double { Double(framesPerBuffer) / sampleRate }

    public func bufferCount(totalFrames: Int) -> Int {
        totalFrames <= 0 ? 0 : (totalFrames + framesPerBuffer - 1) / framesPerBuffer
    }

    public func frames(inBuffer k: Int, totalFrames: Int) -> Int {
        max(0, min(framesPerBuffer, totalFrames - k * framesPerBuffer))
    }

    /// Seconds after the start when buffer k is due: when its last sample has been spoken. With `totalFrames`, the
    /// short last buffer is due at the end of the file, not a whole buffer later.
    public func due(buffer k: Int, totalFrames: Int? = nil) -> Double {
        var end = (k + 1) * framesPerBuffer
        if let totalFrames { end = min(end, totalFrames) }
        return Double(end) / sampleRate
    }
}

/// The replay loop, with the clock and the sleep injected so the pacing is tested without waiting.
public enum PacedLoop {
    /// Calls `deliver(k, frames)` for every buffer of a `totalFrames`-long recording, each no earlier than its due
    /// time. A late buffer (the callback stalled) goes at once and the loop catches up; nothing is dropped. Stops
    /// before the next buffer once `shouldContinue` is false. O(buffers) time, O(1) space.
    public static func run(schedule: ReplaySchedule, totalFrames: Int, now: () -> Double, sleepUntil: (Double) -> Void,
                           shouldContinue: () -> Bool, deliver: (Int, Range<Int>) -> Void) {
        let start = now()
        for k in 0..<schedule.bufferCount(totalFrames: totalFrames) {
            let due = start + schedule.due(buffer: k, totalFrames: totalFrames)
            if now() < due { sleepUntil(due) }
            guard shouldContinue() else { return }
            let first = k * schedule.framesPerBuffer
            deliver(k, first..<(first + schedule.frames(inBuffer: k, totalFrames: totalFrames)))
        }
    }
}
