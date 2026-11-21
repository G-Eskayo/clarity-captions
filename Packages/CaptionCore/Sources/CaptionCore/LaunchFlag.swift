import Foundation

enum LaunchFlag {
    /// Returns true if the flag is present in the given arguments.
    static func isSet(_ flag: String, in arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(flag)
    }

    /// Returns the string value immediately after the flag in the arguments, or nil if not found.
    static func value(after flag: String, in arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
        guard let index = arguments.firstIndex(of: flag), index < arguments.count - 1 else { return nil }
        return arguments[arguments.index(after: index)]
    }

    /// Returns the double value immediately after the flag in the arguments, or nil if not found or not a valid double.
    static func double(after flag: String, in arguments: [String] = ProcessInfo.processInfo.arguments) -> Double? {
        guard let stringValue = value(after: flag, in: arguments) else { return nil }
        return Double(stringValue)
    }
}
