import Foundation
import os.log
import CaptionCore

enum ExitLogging {
    static func quit(_ code: Int32, because reason: String) -> Never {
        let logger = Logger(subsystem: "com.gileskayo.captions", category: "exit")
        logger.info("Exiting with code \(code): \(reason)")
        exit(code)
    }

    #if DEBUG
    static func installExitFromBackgroundQueueHook() {
        guard LaunchArgs.flag("ExitFromBackgroundQueue") else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            ExitLogging.quit(0, because: "ExitFromBackgroundQueue test hook triggered from background queue")
        }
    }
    #endif
}

enum ExitBacktrace {
    static func installIfEnabled() {
        #if DEBUG
        let shouldInstall = true
        #else
        let shouldInstall = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
        guard shouldInstall else { return }

        installBacktraceHandler()
    }

    private static func installBacktraceHandler() {
        var once: Int32 = 0
        atexit_b {
            guard OSAtomicCompareAndSwap32(0, 1, &once) else { return }
            let symbols = Thread.callStackSymbols
            let logger = Logger(subsystem: "com.gileskayo.captions", category: "exit-backtrace")
            for (i, symbol) in symbols.enumerated() {
                logger.error("  [\(i)] \(symbol)")
            }
        }
    }
}
