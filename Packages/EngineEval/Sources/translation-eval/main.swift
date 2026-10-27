// Apple Translation framework runner for the translation comparison test (#159). Reads one pair's test sets
// (translation_eval.sets JSONL) and appends #145 result lines, one caption line at a time, resumable.
//
//   swift run --package-path Packages/EngineEval translation-eval --sets ~/translation-eval/sets/en-es \
//     --target es --results ~/translation-eval/results/en-es/apple.jsonl [--repeats 2] [--only edacc-lines]
//
// The languages must already be installed (System Settings > General > Language & Region > Translation
// Languages): installedSource sessions never show the download sheet, so the run fails fast instead.
import EngineEvalKit
import Foundation
@preconcurrency import Translation

func arg(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return a[i + 1]
}

if CommandLine.arguments.contains("--list") {
    let english = Locale.Language(identifier: "en")
    let languages = await LanguageAvailability().supportedLanguages
    for language in languages.sorted(by: { $0.maximalIdentifier < $1.maximalIdentifier }) {
        let status = await LanguageAvailability().status(from: english, to: language)
        print("\(language.maximalIdentifier)\t\(language.minimalIdentifier)\t\(status)")
    }
    exit(0)
}

let setNames = ["flores", "flores-caption", "speech", "speech-caption", "edacc-lines"]
guard let setsPath = arg("--sets"), let target = arg("--target"), let resultsPath = arg("--results") else {
    print("usage: translation-eval --sets DIR --target es --results FILE [--repeats N] [--only SET]")
    exit(2)
}
let repeats = Int(arg("--repeats") ?? "2") ?? 2
let only = arg("--only")
let source = Locale.Language(identifier: "en")
let targetLanguage = Locale.Language(identifier: target)

let status = await LanguageAvailability().status(from: source, to: targetLanguage)
guard status == .installed else {
    print("TRANSLATION-EVAL-ERROR en->\(target) is \(status), not installed. Install it in System Settings > General > "
          + "Language & Region > Translation Languages.")
    exit(1)
}
let session = TranslationSession(installedSource: source, target: targetLanguage)
let store = try ResultStore(url: URL(fileURLWithPath: resultsPath))
let model = "apple-en-\(target)"
let version = "Translation framework, macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
let host = ProcessInfo.processInfo.hostName
_ = try? await session.translate("warm up")

for name in setNames where only == nil || only == name {
    let url = URL(fileURLWithPath: setsPath).appendingPathComponent("\(name).jsonl")
    guard FileManager.default.fileExists(atPath: url.path) else { continue }
    let segments = try TranslationSet.load(url)
    let byID = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
    let reps = name == "edacc-lines" ? repeats : 1
    let pending = RunPlan.pending(clips: segments.map(\.asClip), engine: "apple", model: model, repeats: reps,
                                  done: store.done)
    var errors = 0
    for item in pending {
        let seg = byID[item.clip.clipID]!
        let start = ContinuousClock.now
        do {
            let text = try await session.translate(seg.source).targetText
            let d = ContinuousClock.now - start
            let secs = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
            try store.append(ResultLine(
                clipID: seg.id, shard: 0, accent: seg.set, engine: "apple", model: model, engineVersion: version,
                repeat: item.repeat, hypothesis: text, audioSeconds: 0, processingSeconds: secs, host: host,
                finishedAt: ISO8601DateFormatter().string(from: Date())))
        } catch {
            errors += 1
            FileHandle.standardError.write(Data("TRANSLATION-EVAL-ERROR apple \(seg.id): \(error)\n".utf8))
        }
    }
    print("\(model) \(name): \(pending.count - errors) translated, \(errors) errors")
}
