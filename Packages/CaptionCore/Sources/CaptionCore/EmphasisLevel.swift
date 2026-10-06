import Foundation

public enum EmphasisLevel: Equatable, Sendable {
    case normal
    case loud
}

struct LoudnessBaseline: Sendable {
    private var levels: [Double] = []
    private let maxSize = 30
    private let minWarmupSize = 8

    var median: Double? {
        guard levels.count >= minWarmupSize else { return nil }
        let sorted = levels.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    mutating func update(_ level: Double) {
        levels.append(level)
        if levels.count > maxSize {
            levels.removeFirst()
        }
    }

    mutating func reset() {
        levels.removeAll()
    }
}

struct EmphasisMapper {
    private static let loudnessThreshold: Double = 8 // dB above baseline

    static func level(wordDBFS: Double, baseline: Double?) -> EmphasisLevel {
        guard let baseline = baseline else { return .normal }
        return wordDBFS - baseline >= loudnessThreshold ? .loud : .normal
    }
}
