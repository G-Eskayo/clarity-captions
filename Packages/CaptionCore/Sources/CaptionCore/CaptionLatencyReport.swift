import Foundation

/// Aggregated latency metrics from a captioning measurement.
public struct CaptionLatencyReport: Sendable {
    /// Median lag in seconds.
    public let medianLagSeconds: Double
    /// 95th percentile lag in seconds.
    public let p95LagSeconds: Double
    /// Time to first non-empty caption in seconds.
    public let timeToFirstCaptionSeconds: Double?

    /// Initialize from a sequence of lag measurements (in seconds) and first-caption timestamp.
    /// Uses nearest-rank percentile calculation for p95.
    public init(lagSamples: [Double], timeToFirstCaption: Double? = nil) {
        let sorted = lagSamples.sorted()
        // Median via nearest-rank percentile.
        let medianIndex = Int(ceil(Double(sorted.count) * 0.5)) - 1
        self.medianLagSeconds = sorted.isEmpty ? 0 : sorted[max(0, min(medianIndex, sorted.count - 1))]
        // P95 via nearest-rank percentile.
        let p95Index = Int(ceil(Double(sorted.count) * 0.95)) - 1
        self.p95LagSeconds = sorted.isEmpty ? 0 : sorted[max(0, min(p95Index, sorted.count - 1))]
        self.timeToFirstCaptionSeconds = timeToFirstCaption
    }

    /// Check regression against a baseline using the 10% budget rule.
    /// - Returns: `.ok` if within budget, `.p95Warning` if p95 exceeds 10%, `.medianFailure` if median exceeds 10%.
    public func regressionStatus(against baseline: CaptionLatencyBaseline) -> LatencyRegressionStatus {
        let medianBudget = baseline.medianLagSeconds * 1.10
        let p95Budget = baseline.p95LagSeconds * 1.10

        if medianLagSeconds > medianBudget {
            return .medianFailure(measured: medianLagSeconds, budget: medianBudget, baseline: baseline.medianLagSeconds)
        }
        if p95LagSeconds > p95Budget {
            return .p95Warning(measured: p95LagSeconds, budget: p95Budget, baseline: baseline.p95LagSeconds)
        }
        return .ok
    }
}

/// Status of latency regression check against a baseline.
public enum LatencyRegressionStatus: Sendable {
    case ok
    case p95Warning(measured: Double, budget: Double, baseline: Double)
    case medianFailure(measured: Double, budget: Double, baseline: Double)
}

/// Baseline latency values parsed from `docs/perf/caption-latency-baseline.md`.
public struct CaptionLatencyBaseline: Sendable {
    public let device: String
    public let os: String
    public let date: String
    public let medianLagSeconds: Double
    public let p95LagSeconds: Double
    public let timeToFirstCaptionSeconds: Double?

    public init(device: String, os: String, date: String, medianLagSeconds: Double, p95LagSeconds: Double, timeToFirstCaptionSeconds: Double? = nil) {
        self.device = device
        self.os = os
        self.date = date
        self.medianLagSeconds = medianLagSeconds
        self.p95LagSeconds = p95LagSeconds
        self.timeToFirstCaptionSeconds = timeToFirstCaptionSeconds
    }

    /// Parse a baseline from markdown table format.
    /// Expects a table with columns: Device | OS | Date | Median | P95 | Time-to-First
    /// Rows with "TBD" in numeric columns are skipped (baseline not yet populated).
    /// Returns nil if no valid (non-TBD) row is found.
    public static func parse(markdown: String) -> CaptionLatencyBaseline? {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

        for line in lines {
            // Skip header and separator lines.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.contains("Device") || trimmed.allSatisfy({ $0 == "|" || $0 == "-" }) {
                continue
            }

            let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 5 else { continue }

            let device = cells[0]
            let os = cells[1]
            let date = cells[2]
            let medianStr = cells[3]
            let p95Str = cells[4]
            let timeToFirstStr = cells.count > 5 ? cells[5] : "TBD"

            // Skip rows with TBD in critical fields.
            if medianStr.uppercased() == "TBD" || p95Str.uppercased() == "TBD" {
                continue
            }

            // Parse numeric values (handle "0.123 s" format).
            guard let median = parseSeconds(medianStr),
                  let p95 = parseSeconds(p95Str) else {
                continue
            }

            let timeToFirst = parseSeconds(timeToFirstStr)

            return CaptionLatencyBaseline(
                device: device,
                os: os,
                date: date,
                medianLagSeconds: median,
                p95LagSeconds: p95,
                timeToFirstCaptionSeconds: timeToFirst
            )
        }

        return nil
    }
}

private func parseSeconds(_ str: String) -> Double? {
    let trimmed = str.trimmingCharacters(in: .whitespaces).lowercased()
    if trimmed == "tbd" { return nil }

    // Try to extract a number, optionally followed by " s".
    if let match = trimmed.range(of: #"(\d+\.?\d*)"#, options: .regularExpression) {
        let numStr = String(trimmed[match])
        return Double(numStr)
    }
    return nil
}
