import Foundation

enum LaunchArgs {
    nonisolated(unsafe) static var arguments: [String] = ProcessInfo.processInfo.arguments

    static func flag(_ name: String, in args: [String]? = nil) -> Bool {
        let argv = args ?? arguments
        return argv.contains("-\(name)")
    }

    static func value(after name: String, in args: [String]? = nil) -> String? {
        let argv = args ?? arguments
        guard let index = argv.firstIndex(of: "-\(name)"), index < argv.count - 1 else { return nil }
        return argv[argv.index(after: index)]
    }
}
