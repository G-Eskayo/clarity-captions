import Darwin
import Foundation
import os

enum ExitLogging {
    private static let log = Logger(subsystem: "com.gileskayo.captions", category: "exit")

    /// Logs a reason and exits with the given code. Always logs via os.Logger before calling Darwin.exit().
    static func exit(reason: String, code: Int32) -> Never {
        log.error("Exiting: \(reason)")
        Darwin.exit(code)
    }

    /// Installs a handler on app exit that logs the backtrace if the exit is unexpected (DEBUG builds or TestFlight).
    /// Useful for catching unintended exits during test runs. Never logs in App Store builds.
    static func installBacktraceOnExit() {
        #if DEBUG
        let shouldLog = true
        #else
        let receiptURL = Bundle.main.appStoreReceiptURL
        let receiptPath = receiptURL?.lastPathComponent ?? ""
        let shouldLog = receiptPath == "sandboxReceipt"
        #endif

        guard shouldLog else { return }

        let backtracePrinter: @convention(c) () -> Void = {
            let backtrace = Thread.callStackSymbols
            let log = Logger(subsystem: "com.gileskayo.captions", category: "exit-backtrace")
            for symbol in backtrace.prefix(15) {
                log.error("\(symbol)")
            }
        }
        atexit(backtracePrinter)
    }
}
