// Prints the locales Apple's speech engines support on this Mac, as JSON (#236).
//
//   swift scripts/speech-locales/probe.swift > docs/research/apple-speech-locales-macos-<version>.json
//
// Reads only Apple's APIs: no microphone, no network, no downloads.
import Foundation
import Speech

func ids(_ locales: [Locale]) -> [String] {
    locales.map { $0.identifier(.bcp47) }.sorted()
}

let done = DispatchSemaphore(value: 0)
Task {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    let report: [String: Any] = [
        "os": "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
        "date": ISO8601DateFormatter().string(from: Date()),
        "SpeechTranscriber.supportedLocales": ids(await SpeechTranscriber.supportedLocales),
        "SpeechTranscriber.installedLocales": ids(await SpeechTranscriber.installedLocales),
        "DictationTranscriber.supportedLocales": ids(await DictationTranscriber.supportedLocales),
        "DictationTranscriber.installedLocales": ids(await DictationTranscriber.installedLocales),
        "SFSpeechRecognizer.supportedLocales": ids(Array(SFSpeechRecognizer.supportedLocales())),
    ]
    let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    done.signal()
}
done.wait()
