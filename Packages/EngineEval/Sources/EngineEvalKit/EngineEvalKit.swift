import Darwin
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

// MARK: - Streaming latency (#145)

public struct StreamUpdate: Codable, Equatable, Sendable {
    /// Seconds since the first audio sample was fed (the clip's own clock, like the app's FedWallTime).
    public let t: Double
    /// The full text on screen after this update.
    public let text: String

    public init(t: Double, text: String) { self.t = t; self.text = text }
}

/// The standard sliding (growing) window for engines that aren't natively streaming: re-decode all audio heard so
/// far, starting the next decode as soon as the previous one finishes and at least `hop` seconds of new audio
/// exist. Time is simulated: a decode that starts at t sees audio up to min(t, duration) and its text shows at
/// t + measured compute. The last decode always covers the whole clip.
public enum GrowingWindow {
    public static func simulate(duration: Double, hop: Double,
                                decode: (Double) async throws -> (text: String, compute: Double)) async rethrows -> [StreamUpdate] {
        var updates: [StreamUpdate] = []
        var t = min(hop, duration)
        while true {
            let a = min(t, duration)
            let (text, compute) = try await decode(a)
            let shown = t + compute
            updates.append(StreamUpdate(t: shown, text: text))
            if a >= duration { break }
            t = max(shown, min(a + hop, duration))
        }
        return updates
    }
}

/// What the app shows from SpeechTranscriber: finalized results accumulate; the latest volatile result replaces
/// the previous volatile tail.
public struct DisplayedText: Sendable {
    private var finals: [String] = []
    private var volatile = ""

    public init() {}

    public mutating func apply(_ text: String, isFinal: Bool) -> String {
        if isFinal { finals.append(text); volatile = "" } else { volatile = text }
        return (finals + [volatile]).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

public struct TimedWord: Codable, Equatable, Sendable {
    public let word: String
    public let start: Double
    public let end: Double

    enum CodingKeys: String, CodingKey { case word = "w", start, end }
}

public enum WordTiming {
    /// Sub-word tokens -> words: a token starting with "▁" or a space begins a new word.
    public static func group(_ tokens: [(String, Double, Double)]) -> [TimedWord] {
        var words: [TimedWord] = []
        for (tok, start, end) in tokens {
            let boundary = tok.hasPrefix("▁") || tok.hasPrefix(" ")
            let piece = tok.trimmingCharacters(in: CharacterSet(charactersIn: "▁ "))
            if boundary || words.isEmpty {
                if !piece.isEmpty { words.append(TimedWord(word: piece, start: start, end: end)) }
            } else if let last = words.popLast() {
                words.append(TimedWord(word: last.word + piece, start: last.start, end: end))
            }
        }
        return words
    }
}

// MARK: - Engine specs and memory (#145 compression test)

/// `--engines` entries: a built-in engine name, or `local:<name>` for a model folder under `<models>/variants/<name>`
/// (a compressed Parakeet build made by scripts/engine-eval/compress_parakeet.py).
public enum EngineSpec: Equatable, Sendable {
    case builtin(String)
    case local(String)

    public static func parse(_ raw: String) -> EngineSpec? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("local:") {
            let name = String(s.dropFirst("local:".count))
            guard !name.isEmpty, !name.contains("/"), !name.contains(".."), name != "." else { return nil }
            return .local(name)
        }
        return s.isEmpty ? nil : .builtin(s)
    }

    public static func parseList(_ raw: String) -> [EngineSpec]? {
        let parts = raw.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let specs = parts.compactMap(parse)
        return specs.count == parts.count && !specs.isEmpty ? specs : nil
    }
}

/// The variant folder's `variant.json`: which FluidAudio model contract the folder follows.
public struct VariantInfo: Codable, Equatable, Sendable {
    public let asrVersion: String
    public let method: String

    public init(asrVersion: String, method: String) { self.asrVersion = asrVersion; self.method = method }

    enum CodingKeys: String, CodingKey { case asrVersion = "asr_version", method }

    public static func load(_ dir: URL) throws -> VariantInfo {
        try JSONDecoder().decode(VariantInfo.self, from: Data(contentsOf: dir.appendingPathComponent("variant.json")))
    }
}

/// This process's physical memory footprint (what Activity Monitor and jetsam count), in bytes.
/// Core ML work on the Neural Engine also uses memory in system daemons, which this does not include.
public enum MemoryFootprint {
    public static func current() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? UInt64(info.phys_footprint) : nil
    }
}
