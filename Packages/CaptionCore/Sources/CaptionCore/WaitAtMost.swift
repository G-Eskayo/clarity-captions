import Foundation

/// #245: runs `work` and waits for it for at most `limit`. True when it finished in time. Work still running after
/// that carries on unwatched; nothing waits for it (Stop in the split never waits on engines that won't stop).
public func waitAtMost(_ limit: Duration, _ work: @escaping @Sendable () async -> Void) async -> Bool {
    let (ended, done) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
    Task { await work(); done.yield(true); done.finish() }
    let timer = Task { try? await Task.sleep(for: limit); done.yield(false); done.finish() }
    defer { timer.cancel() }
    for await finished in ended { return finished }
    return false
}
