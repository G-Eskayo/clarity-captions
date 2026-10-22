import EngineEvalKit
import Foundation

/// Runs one engine over one shard, resumably: skips every (clip, engine, model, repeat) already in the results file,
/// appends one line per finished clip, keeps going past a bad clip.
public struct ShardRunner {
    public let shardDir: URL
    public let results: URL
    public let repeats: Int
    public let status: StatusFile?
    public let host = ProcessInfo.processInfo.hostName

    public init(shardDir: URL, results: URL, repeats: Int, status: StatusFile?) {
        self.shardDir = shardDir; self.results = results; self.repeats = repeats; self.status = status
    }

    @discardableResult
    public func run(_ t: FileTranscriber, clips: [ManifestClip]) async throws -> (done: Int, errors: Int) {
        let store = try ResultStore(url: results)
        let shard = Manifest.shardNumber(of: shardDir)
        let pending = RunPlan.pending(clips: clips, engine: t.engine, model: t.model, repeats: repeats, done: store.done)
        let total = clips.count * repeats
        var finished = total - pending.count
        var errors = 0
        var eta = ETAEstimator()
        var audioRemaining = pending.reduce(0) { $0 + $1.clip.audioSeconds }
        print("ENGINE-EVAL-START \(t.engine) \(t.model) shard \(shard): \(pending.count) to run, \(finished) already done")
        if pending.isEmpty { return (finished, 0) }
        status?.update(engine: "\(t.engine) \(t.model)", done: finished, total: total, eta: nil, note: "loading model")
        try await t.load()
        let iso = ISO8601DateFormatter()
        for item in pending {
            audioRemaining -= item.clip.audioSeconds
            let url = shardDir.appendingPathComponent(item.clip.file)
            let start = ContinuousClock.now
            do {
                let text = try await t.transcribe(url)
                let d = ContinuousClock.now - start
                let secs = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
                try store.append(ResultLine(clipID: item.clip.clipID, shard: shard, accent: item.clip.accent,
                                            engine: t.engine, model: t.model, engineVersion: t.version,
                                            repeat: item.repeat, hypothesis: text, audioSeconds: item.clip.audioSeconds,
                                            processingSeconds: (secs * 10_000).rounded() / 10_000, host: host,
                                            finishedAt: iso.string(from: Date())))
                finished += 1
                eta.record(audioSeconds: item.clip.audioSeconds, processingSeconds: secs)
            } catch {
                errors += 1
                print("ENGINE-EVAL-ERROR \(t.engine) \(item.clip.clipID) r\(item.repeat): \(error)")
            }
            status?.update(engine: "\(t.engine) \(t.model)", done: finished, total: total,
                           eta: eta.secondsRemaining(audioRemaining: audioRemaining), note: "repeat \(item.repeat)")
        }
        print("ENGINE-EVAL-DONE \(t.engine) \(t.model) shard \(shard): \(finished)/\(total), \(errors) errors")
        return (finished, errors)
    }
}

/// Small JSON status file the driver and the visible Terminal window read.
public final class StatusFile {
    public let url: URL
    private var last = Date.distantPast

    public init(url: URL) { self.url = url }

    public func update(engine: String, done: Int, total: Int, eta: Double?, note: String, force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(last) >= 2 || done == total else { return }
        last = now
        let obj: [String: Any] = [
            "engine": engine, "done": done, "total": total, "note": note,
            "eta": eta.map { ETAEstimator.format($0) } ?? "estimating",
            "updated": ISO8601DateFormatter().string(from: now),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
