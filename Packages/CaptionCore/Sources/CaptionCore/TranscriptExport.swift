import Foundation

public enum TranscriptFormatter {
    /// Minimum duration in seconds for a caption line when timing is missing.
    private static let minimumLineDuration: Double = 0.5

    /// Format lines as plain text, one line per caption, with speaker labels when available.
    public static func plainText(lines: [CaptionLine], speakerNames: SpeakerNames = SpeakerNames()) -> String {
        lines.map { line in
            let speaker: String
            if let sp = line.speaker {
                if let name = speakerNames.name(for: sp) {
                    speaker = "\(name): "
                } else {
                    speaker = "Speaker \(sp + 1): "
                }
            } else {
                speaker = ""
            }
            return speaker + line.text
        }.joined(separator: "\n")
    }

    /// Format lines as SubRip SRT: numbered blocks with HH:MM:SS,mmm timestamps.
    /// Lines missing timing get synthetic timestamps chained from the previous line's end.
    public static func srt(lines: [CaptionLine], speakerNames: SpeakerNames = SpeakerNames()) -> String {
        guard !lines.isEmpty else { return "" }

        var result: [String] = []
        var currentEndTime: Double = 0

        for (index, line) in lines.enumerated() {
            let blockNumber = index + 1

            let startTime = line.startTime ?? currentEndTime
            let endTime = line.endTime ?? (startTime + minimumLineDuration)

            let startTimestamp = formatTimestamp(startTime)
            let endTimestamp = formatTimestamp(endTime)

            let speaker: String
            if let sp = line.speaker {
                if let name = speakerNames.name(for: sp) {
                    speaker = "\(name): "
                } else {
                    speaker = "Speaker \(sp + 1): "
                }
            } else {
                speaker = ""
            }
            let text = speaker + line.text

            result.append("\(blockNumber)")
            result.append("\(startTimestamp) --> \(endTimestamp)")
            result.append(text)
            result.append("")

            currentEndTime = endTime
        }

        return result.joined(separator: "\n")
    }

    private static func formatTimestamp(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let milliseconds = Int((seconds - Double(totalSeconds)) * 1000)

        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        return String(format: "%d:%02d:%02d,%03d", hours, minutes, secs, milliseconds)
    }
}
