import Foundation

public enum InterruptionWatchdogResult: Sendable, Equatable {
    case resumed
    case timedOut
}

/// Races "resume() was called" against a timeout. Returns .resumed if resume is called before the timeout,
/// or .timedOut if the timeout elapses first. Used to enforce ADR 0021's 30-second timeout for restoring
/// the microphone after an interruption.
public actor InterruptionWatchdog {
    private let timeoutSeconds: Double
    private var resumed = false
    private var timedOut = false

    public init(timeoutSeconds: Double = 30) {
        self.timeoutSeconds = timeoutSeconds
    }

    /// Mark the watchdog as resumed. Always returns .resumed.
    public func resume() async -> InterruptionWatchdogResult {
        resumed = true
        return .resumed
    }

    /// Wait for the timeout or for resume() to be called, whichever comes first.
    /// Returns .resumed if resume() was called, or .timedOut if the timeout elapses without resume.
    public func wait() async -> InterruptionWatchdogResult {
        if resumed { return .resumed }
        if timedOut { return .timedOut }

        let start = Date()
        while Date().timeIntervalSince(start) < timeoutSeconds {
            if resumed { return .resumed }
            try? await Task.sleep(nanoseconds: 100_000_000) // Check every 100ms
        }

        // If we get here, the timeout elapsed without resume being called.
        if resumed { return .resumed }
        timedOut = true
        return .timedOut
    }
}
