import Foundation

/// Word error rate against a reference: (substitutions + deletions + insertions) / reference words. Case, accents and
/// punctuation are ignored, and number words up to twenty read as digits, so "seven" and "7" agree.
public enum WordErrorRate {
    public static func of(_ hypothesis: String, reference: String) -> Double {
        let ref = normal(reference), hyp = normal(hypothesis)
        guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }
        var row = Array(0...hyp.count)
        for (i, r) in ref.enumerated() {
            var next = [i + 1] + Array(repeating: 0, count: hyp.count)
            for (j, h) in hyp.enumerated() {
                next[j + 1] = min(row[j] + (r == h ? 0 : 1), row[j + 1] + 1, next[j] + 1)
            }
            row = next
        }
        return Double(row[hyp.count]) / Double(ref.count)
    }

    private static let numbers = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                                  "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
                                  "eighteen", "nineteen", "twenty"]

    public static func normal(_ text: String) -> [String] {
        EchoGuard.words(text).map { w in numbers.firstIndex(of: w).map(String.init) ?? w }
    }
}
