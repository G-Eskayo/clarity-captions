import EngineEvalEngines
import EngineEvalKit
import Foundation

// engine-eval run --shard-dir DIR --results FILE [--engines apple,parakeet-v2,parakeet-ultra,whisperkit]
//                 [--repeats N] [--models-dir DIR] [--status FILE] [--whisper-model NAME]
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

let args = Array(CommandLine.arguments.dropFirst())
guard args.first == "run" else {
    fail("usage: engine-eval run --shard-dir DIR --results FILE [--engines a,b] [--repeats N] [--models-dir DIR] [--status FILE]")
}
guard let shardPath = arg("--shard-dir", args), let resultsPath = arg("--results", args) else {
    fail("--shard-dir and --results are required")
}
let shardDir = URL(fileURLWithPath: shardPath)
let results = URL(fileURLWithPath: resultsPath)
let repeats = Int(arg("--repeats", args) ?? "1") ?? 1
let engineIDs = (arg("--engines", args) ?? EngineID.allCases.map(\.rawValue).joined(separator: ","))
    .split(separator: ",").map { s -> EngineID in
        guard let id = EngineID(rawValue: String(s)) else { fail("unknown engine \(s)") }
        return id
    }
let modelsDir = URL(fileURLWithPath: arg("--models-dir", args)
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("edacc-eval/models").path)
let status = arg("--status", args).map { StatusFile(url: URL(fileURLWithPath: $0)) }
let whisperModel = arg("--whisper-model", args) ?? WhisperKitFileTranscriber.defaultModel

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
    for id in engineIDs {
        do {
            let t = makeTranscriber(id, modelsDir: modelsDir, versions: versions, whisperModel: whisperModel)
            let r = try await runner.run(t, clips: present)
            print("ENGINE-EVAL-RESULT \(t.engine) \(t.model) done \(r.done) errors \(r.errors)")
            if r.errors > 0 { exitCode = 1 }  // the driver won't mark the shard done; a rerun retries the failures
        } catch {
            print("ENGINE-EVAL-ERROR \(id.rawValue) failed: \(error)")
            exitCode = 1
        }
    }
    semaphore.signal()
}
semaphore.wait()
exit(exitCode)
