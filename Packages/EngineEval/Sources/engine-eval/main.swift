import EngineEvalEngines
import EngineEvalKit
import Foundation

// engine-eval run --shard-dir DIR --results FILE [--engines apple,parakeet-v2,parakeet-ultra,whisperkit]
//                 [--repeats N] [--models-dir DIR] [--status FILE] [--whisper-model NAME] [--locale es-MX]
// --locale sets the Apple engine's SpeechTranscriber locale (default en-US; #158). Parakeet detects the language.
// One shard, every listed engine in turn (one model in memory at a time). Resumable. See
// docs/perf/engine-accuracy-design.md (#145).

func arg(_ name: String, _ args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("engine-eval: \(message)\n".utf8))
    exit(2)
}

setvbuf(stdout, nil, _IOLBF, 0)  // progress lines reach the driver log as they happen
let args = Array(CommandLine.arguments.dropFirst())
if args.first == "latency" { runLatency(args) }
if args.first == "memory" { runMemory(args) }
guard args.first == "run" else {
    fail("usage: engine-eval run --shard-dir DIR --results FILE [--engines a,b] [--repeats N] [--models-dir DIR] [--status FILE]")
}
guard let shardPath = arg("--shard-dir", args), let resultsPath = arg("--results", args) else {
    fail("--shard-dir and --results are required")
}
let shardDir = URL(fileURLWithPath: shardPath)
let results = URL(fileURLWithPath: resultsPath)
let repeats = Int(arg("--repeats", args) ?? "1") ?? 1
guard let engineSpecs = EngineSpec.parseList(arg("--engines", args) ?? EngineID.defaults.map(\.rawValue).joined(separator: ","))
else { fail("bad --engines list") }
let modelsDir = URL(fileURLWithPath: arg("--models-dir", args)
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("edacc-eval/models").path)
let status = arg("--status", args).map { StatusFile(url: URL(fileURLWithPath: $0)) }
let whisperModel = arg("--whisper-model", args) ?? WhisperKitFileTranscriber.defaultModel
guard let appleLocale = AppleLocale.parse(arg("--locale", args)) else { fail("bad --locale (want e.g. es-MX)") }

// Versions straight from this package's lock file, so result lines record what actually ran.
let resolved = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Package.resolved")
let versions = EngineVersions(fluidAudio: PackagePins.version(of: "fluidaudio", resolvedFile: resolved) ?? "unknown",
                              whisperKit: PackagePins.version(of: "argmax-oss-swift", resolvedFile: resolved) ?? "unknown")

let clips: [ManifestClip]
do { clips = try Manifest.load(shardDir: shardDir) } catch { fail("\(error)") }
let missing = Manifest.missingAudio(clips, shardDir: shardDir)
if !missing.isEmpty { print("ENGINE-EVAL-WARN \(missing.count) clip(s) missing audio, first \(missing[0])") }
let present = clips.filter { !missing.contains($0.clipID) }

let runner = ShardRunner(shardDir: shardDir, results: results, repeats: repeats, status: status)
let semaphore = DispatchSemaphore(value: 0)
var exitCode: Int32 = 0
Task {
    for spec in engineSpecs {
        do {
            let t = try makeTranscriber(spec: spec, modelsDir: modelsDir, versions: versions, whisperModel: whisperModel,
                                        locale: appleLocale)
            let r = try await runner.run(t, clips: present)
            print("ENGINE-EVAL-RESULT \(t.engine) \(t.model) done \(r.done) errors \(r.errors)")
            if r.errors > 0 { exitCode = 1 }  // the driver won't mark the shard done; a rerun retries the failures
        } catch {
            print("ENGINE-EVAL-ERROR \(spec) failed: \(error)")
            exitCode = 1
        }
    }
    semaphore.signal()
}
semaphore.wait()
exit(exitCode)

// engine-eval latency --shard-dir DIR --out FILE [--engines ...] [--max-clip-seconds 30] [--hop 0.5]
func runLatency(_ args: [String]) -> Never {
    guard let shardPath = arg("--shard-dir", args), let outPath = arg("--out", args) else {
        fail("latency needs --shard-dir and --out")
    }
    let shardDir = URL(fileURLWithPath: shardPath)
    let hop = Double(arg("--hop", args) ?? "0.5") ?? 0.5
    let maxClip = Double(arg("--max-clip-seconds", args) ?? "30") ?? 30
    let modelsDir = URL(fileURLWithPath: arg("--models-dir", args)
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("edacc-eval/models").path)
    let ids = (arg("--engines", args) ?? "parakeet-v2,parakeet-ultra,whisperkit,apple").split(separator: ",").map(String.init)
    let status = arg("--status", args).map { StatusFile(url: URL(fileURLWithPath: $0)) }
    let clips: [ManifestClip]
    do { clips = try Manifest.load(shardDir: shardDir) } catch { fail("\(error)") }
    let runner = LatencyRunner(shardDir: shardDir, out: URL(fileURLWithPath: outPath), maxClipSeconds: maxClip, status: status)
    let sem = DispatchSemaphore(value: 0)
    var code: Int32 = 0
    Task {
        // Word times ("when was it said") come from Parakeet v2's offline token timestamps, written alongside its run.
        let timing = ParakeetWindowLatency(version: .v2, name: "parakeet-tdt-0.6b-v2-coreml", modelsDir: modelsDir, hop: hop)
        for id in ids {
            let engine: StreamingLatencyEngine
            switch id {
            case "apple": engine = AppleLiveLatency()
            case "parakeet-v2": engine = timing
            case "parakeet-ultra": engine = ParakeetWindowLatency(version: .ultra, name: "parakeet-ultra-coreml", modelsDir: modelsDir, hop: hop)
            case "whisperkit": engine = WhisperKitWindowLatency(model: WhisperKitFileTranscriber.defaultModel, modelsDir: modelsDir, hop: hop)
            default:
                guard let spec = EngineSpec.parse(id),
                      let p = try? makeTranscriber(spec: spec, modelsDir: modelsDir, versions: EngineVersions(fluidAudio: "", whisperKit: "")) as? ParakeetFileTranscriber
                else { print("LATENCY-ERROR unknown or non-Parakeet engine \(id)"); code = 2; continue }
                engine = ParakeetWindowLatency(inner: p, hop: hop)
            }
            do {
                try await runner.run(engine, clips: clips, timing: id == "parakeet-v2" ? timing : nil)
            } catch {
                print("LATENCY-ERROR \(id) failed: \(error)"); code = 1
            }
        }
        sem.signal()
    }
    sem.wait()
    exit(code)
}

// engine-eval memory --shard-dir DIR --engines SPEC --out FILE [--clips 60]
// Footprint of this process before load, after load, and peak while transcribing the first N clips. Run one engine
// per process so an earlier model doesn't inflate a later one.
func runMemory(_ args: [String]) -> Never {
    guard let shardPath = arg("--shard-dir", args), let outPath = arg("--out", args),
          let raw = arg("--engines", args), let specs = EngineSpec.parseList(raw), specs.count == 1 else {
        fail("memory needs --shard-dir, --out and exactly one --engines entry")
    }
    let n = Int(arg("--clips", args) ?? "60") ?? 60
    let modelsDir = URL(fileURLWithPath: arg("--models-dir", args)
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("edacc-eval/models").path)
    let shardDir = URL(fileURLWithPath: shardPath)
    let clips: [ManifestClip]
    do { clips = Array(try Manifest.load(shardDir: shardDir).filter { $0.audioSeconds <= 30 }.prefix(n)) } catch { fail("\(error)") }
    let sem = DispatchSemaphore(value: 0)
    var code: Int32 = 0
    Task {
        do {
            let t = try makeTranscriber(spec: specs[0], modelsDir: modelsDir,
                                        versions: EngineVersions(fluidAudio: "", whisperKit: ""))
            let before = MemoryFootprint.current() ?? 0
            try await t.load()
            let loaded = MemoryFootprint.current() ?? 0
            var peak = loaded
            for c in clips {
                _ = try await t.transcribe(shardDir.appendingPathComponent(c.file))
                peak = max(peak, MemoryFootprint.current() ?? 0)
            }
            let line: [String: Any] = ["engine": t.engine, "model": t.model, "clips": clips.count,
                                       "footprint_before_mb": Double(before) / 1_048_576,
                                       "footprint_loaded_mb": Double(loaded) / 1_048_576,
                                       "footprint_peak_mb": Double(peak) / 1_048_576,
                                       "host": ProcessInfo.processInfo.hostName]
            var data = try JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])
            data.append(UInt8(ascii: "\n"))
            let out = URL(fileURLWithPath: outPath)
            try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: out.path) { FileManager.default.createFile(atPath: out.path, contents: nil) }
            let fh = try FileHandle(forWritingTo: out); try fh.seekToEnd(); try fh.write(contentsOf: data); try fh.close()
            print("MEMORY-RESULT \(t.model) loaded \(loaded / 1_048_576) MB peak \(peak / 1_048_576) MB")
        } catch {
            print("MEMORY-ERROR \(error)"); code = 1
        }
        sem.signal()
    }
    sem.wait()
    exit(code)
}
