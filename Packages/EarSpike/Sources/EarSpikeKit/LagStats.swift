import Foundation

/// Median and 95th percentile of a set of timings (linear interpolation between ranks, as numpy does).
public struct LagStats: Sendable, Codable {
    public let count: Int
    public let median: Double?
    public let p95: Double?

    public init(_ samples: [Double]) {
        let s = samples.sorted()
        count = s.count
        median = Self.quantile(s, 0.5)
        p95 = Self.quantile(s, 0.95)
    }

    static func quantile(_ s: [Double], _ q: Double) -> Double? {
        guard !s.isEmpty else { return nil }
        let pos = q * Double(s.count - 1)
        let lo = Int(pos.rounded(.down)), hi = Int(pos.rounded(.up))
        return s[lo] + (s[hi] - s[lo]) * (pos - Double(lo))
    }
}
