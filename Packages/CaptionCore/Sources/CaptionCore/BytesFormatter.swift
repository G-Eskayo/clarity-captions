import Foundation

public enum BytesFormatter {
    public static func format(bytes: Int64?) -> String {
        guard let bytes else { return "Size unknown" }
        guard bytes > 0 else { return "Already downloaded" }

        let units = ["B", "KB", "MB", "GB"]
        var size = Double(bytes)
        var unitIndex = 0

        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }

        let rounded = size < 10 ? String(format: "%.1f", size) : String(format: "%.0f", size)
        return "\(rounded) \(units[unitIndex])"
    }
}
