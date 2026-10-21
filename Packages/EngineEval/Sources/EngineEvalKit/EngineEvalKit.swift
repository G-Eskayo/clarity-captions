import Foundation

// Pure pieces of the engine accuracy run (#145): shard manifest, result lines, resume, ETA.
// The line format matches scripts/engine-eval/edacc_eval/results.py, which scores them.

public struct ManifestClip: Codable, Equatable, Sendable {
    public let clipID: String
    public let file: String
    public let accent: String
    public let audioSeconds: Double

    public init(clipID: String, file: String, accent: String, audioSeconds: Double) {
        self.clipID = clipID; self.file = file; self.accent = accent; self.audioSeconds = audioSeconds
    }

    enum CodingKeys: String, CodingKey {
        case clipID = "clip_id", file, accent, audioSeconds = "audio_seconds"
    }
}

public enum ManifestError: Error, CustomStringConvertible {
    case badLine(Int, String)
    case duplicate(String)

    public var description: String {
        switch self {
        case let .badLine(n, why): return "manifest line \(n): \(why)"
        case let .duplicate(id): return "manifest has duplicate clip \(id)"
        }
    }
}

public enum Manifest {
    public static func load(shardDir: URL) throws -> [ManifestClip] {
        let text = try String(contentsOf: shardDir.appendingPathComponent("manifest.jsonl"), encoding: .utf8)
        var clips: [ManifestClip] = []
        var seen = Set<String>()
        for (i, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let clip: ManifestClip
            do { clip = try JSONDecoder().decode(ManifestClip.self, from: Data(line.utf8)) } catch {
                throw ManifestError.badLine(i + 1, "\(error)")
            }
            guard seen.insert(clip.clipID).inserted else { throw ManifestError.duplicate(clip.clipID) }
            clips.append(clip)
        }
        return clips
    }

    public static func missingAudio(_ clips: [ManifestClip], shardDir: URL) -> [String] {
        clips.filter { !FileManager.default.fileExists(atPath: shardDir.appendingPathComponent($0.file).path) }
            .map(\.clipID)
    }

    /// "shard-007" -> 7; 0 if the directory isn't named like a shard.
    public static func shardNumber(of shardDir: URL) -> Int {
        Int(shardDir.lastPathComponent.split(separator: "-").last ?? "") ?? 0
    }
}

public struct ResultKey: Hashable, Sendable {
    public let clipID: String
    public let engine: String
    public let model: String
    public let `repeat`: Int

    public init(clipID: String, engine: String, model: String, repeat: Int) {
        self.clipID = clipID; self.engine = engine; self.model = model; self.repeat = `repeat`
    }
}

public struct ResultLine: Codable, Equatable, Sendable {
    public let clipID: String
    public let shard: Int
    public let accent: String
    public let engine: String
    public let model: String
    public let engineVersion: String
    public let `repeat`: Int
    public let hypothesis: String
    public let audioSeconds: Double
    public let processingSeconds: Double
    public let host: String
    public let finishedAt: String

    public init(clipID: String, shard: Int, accent: String, engine: String, model: String, engineVersion: String,
                repeat: Int, hypothesis: String, audioSeconds: Double, processingSeconds: Double, host: String,
                finishedAt: String) {
        self.clipID = clipID; self.shard = shard; self.accent = accent; self.engine = engine; self.model = model
        self.engineVersion = engineVersion; self.repeat = `repeat`; self.hypothesis = hypothesis
        self.audioSeconds = audioSeconds; self.processingSeconds = processingSeconds; self.host = host
        self.finishedAt = finishedAt
    }

    public var key: ResultKey { ResultKey(clipID: clipID, engine: engine, model: model, repeat: `repeat`) }

    enum CodingKeys: String, CodingKey {
        case clipID = "clip_id", shard, accent, engine, model, engineVersion = "engine_version", `repeat`
        case hypothesis, audioSeconds = "audio_seconds", processingSeconds = "processing_seconds", host
        case finishedAt = "finished_at"
    }
}

/// Append-only JSONL results with resume. One line per (clip, engine, model, repeat), written and synced before
/// the next clip starts. Corrupt or truncated lines (a crash mid-write) are skipped and counted; duplicates count once.
public final class ResultStore {
    public let url: URL
    public private(set) var done: Set<ResultKey>
    public let corruptLines: Int
    public let duplicateLines: Int
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    public init(url: URL) throws {
        self.url = url
        let read = try ResultStore.readLines(url)
        done = Set(read.rows.map(\.key))
        corruptLines = read.corrupt
        duplicateLines = read.duplicates
        try ResultStore.ensureTrailingNewline(url)
    }

    public static func readLines(_ url: URL) throws -> (rows: [ResultLine], corrupt: Int, duplicates: Int) {
        guard FileManager.default.fileExists(atPath: url.path) else { return ([], 0, 0) }
        let data = try Data(contentsOf: url)
        var rows: [ResultLine] = []
        var seen = Set<ResultKey>()
        var corrupt = 0, duplicates = 0
        for raw in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            if raw.allSatisfy({ $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\r") }) { continue }
            guard let row = try? JSONDecoder().decode(ResultLine.self, from: Data(raw)) else { corrupt += 1; continue }
            if seen.insert(row.key).inserted { rows.append(row) } else { duplicates += 1 }
        }
        return (rows, corrupt, duplicates)
    }

    private static func ensureTrailingNewline(_ url: URL) throws {
        guard let fh = try? FileHandle(forUpdating: url) else { return }
        defer { try? fh.close() }
        let end = try fh.seekToEnd()
        guard end > 0 else { return }
        try fh.seek(toOffset: end - 1)
        if fh.readData(ofLength: 1) != Data([UInt8(ascii: "\n")]) {
            try fh.seekToEnd()
            try fh.write(contentsOf: Data([UInt8(ascii: "\n")]))
        }
    }

    public func append(_ line: ResultLine) throws {
        var data = try encoder.encode(line)
        data.append(UInt8(ascii: "\n"))
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let fh = try FileHandle(forWritingTo: url)
        defer { try? fh.close() }
        try fh.seekToEnd()
        try fh.write(contentsOf: data)
        try fh.synchronize()
        done.insert(line.key)
    }
}

public struct PendingItem: Sendable {
    public let clip: ManifestClip
    public let `repeat`: Int
}

public enum RunPlan {
    /// Repeat-major: every clip once, then every clip again, so a stopped run still has full coverage at repeat 1.
    public static func pending(clips: [ManifestClip], engine: String, model: String, repeats: Int,
                               done: Set<ResultKey>) -> [PendingItem] {
        guard repeats > 0 else { return [] }
        return (1...repeats).flatMap { r in
            clips.filter { !done.contains(ResultKey(clipID: $0.clipID, engine: engine, model: model, repeat: r)) }
                .map { PendingItem(clip: $0, repeat: r) }
        }
    }
}

public struct ETAEstimator: Sendable {
    private var audio = 0.0
    private var processing = 0.0

    public init() {}

    public mutating func record(audioSeconds: Double, processingSeconds: Double) {
        audio += audioSeconds; processing += processingSeconds
    }

    public func secondsRemaining(audioRemaining: Double) -> Double? {
        audio > 0 ? audioRemaining * processing / audio : nil
    }

    public static func format(_ seconds: Double) -> String {
        let m = Int((seconds / 60).rounded(.up))
        return String(format: "%dh %02dm", m / 60, m % 60)
    }
}

public enum PackagePins {
    public static func version(of identity: String, resolvedFile: URL) -> String? {
        guard let data = try? Data(contentsOf: resolvedFile),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pins = obj["pins"] as? [[String: Any]] else { return nil }
        let pin = pins.first { ($0["identity"] as? String) == identity }
        let state = pin?["state"] as? [String: Any]
        return (state?["version"] as? String) ?? (state?["revision"] as? String)
    }
}

/// Parakeet (FluidAudio) refuses clips shorter than its minimum (1 s); about 28% of EdAcc segments are shorter
/// (mostly "yeah", "mm"). Trailing silence lets it hear them without changing what was said.
public enum SilencePadding {
    public static func padded(_ samples: [Float], toAtLeast minimum: Int) -> [Float] {
        samples.count >= minimum ? samples : samples + [Float](repeating: 0, count: minimum - samples.count)
    }
}
