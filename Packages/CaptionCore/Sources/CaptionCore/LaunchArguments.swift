import Foundation

public struct LaunchArguments {
    private let args: [String]

    public init(_ args: [String] = CommandLine.arguments) {
        self.args = args
    }

    /// Whether a flag is present in the arguments (e.g., `-flagName`).
    public func flag(_ name: String) -> Bool {
        args.contains("-\(name)")
    }

    /// The value immediately following a flag (e.g., `-flagName value` returns `value`).
    /// Returns nil if no value follows, or if what follows is another flag.
    public func value(after flag: String) -> String? {
        guard let index = args.firstIndex(of: "-\(flag)"), index + 1 < args.count else { return nil }
        let next = args[index + 1]
        return next.hasPrefix("-") ? nil : next
    }

    /// The value as a Double immediately following a flag.
    public func double(after flag: String) -> Double? {
        value(after: flag).flatMap { Double($0) }
    }
}
