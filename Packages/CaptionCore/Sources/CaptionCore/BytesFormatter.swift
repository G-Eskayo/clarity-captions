import Foundation

public enum BytesFormatter {
    /// Format byte count as "B", "KB", "MB", or "GB". Returns "Already downloaded" for 0, "Size unknown" for nil.
    public static func format(_ bytes: Int64?) -> String {
        guard let bytes, bytes > 0 else { return bytes == 0 ? "Already downloaded" : "Size unknown" }

        let units = ["B", "KB", "MB", "GB"]
        var size = Double(bytes)
        var unitIndex = 0

        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }

        if size < 10 {
            return String(format: "%.1f %@", size, units[unitIndex])
        } else {
            return String(format: "%.0f %@", size, units[unitIndex])
        }
    }
}
