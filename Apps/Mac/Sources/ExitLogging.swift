import CaptionCore
import Foundation
import os.log

private let exitLogger = Logger(subsystem: "com.gileskayo.captions", category: "exit")

@convention(c)
private func exitHandler() {
    let stack = Thread.callStackSymbols.joined(separator: "\n")
    exitLogger.fault("process exited:\n\(stack, privacy: .public)")
}

enum SealExit {
    static func now(_ reason: String, status: Int32 = 0) -> Never {
        exitLogger.info("exiting: \(reason, privacy: .public)")
        exit(status)
    }
}

enum ProcessExitLog {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        atexit(exitHandler)
    }
}

enum ExitFaultSelfTest {
    static func runIfRequested() {
        let args = LaunchArguments()
        guard args.flag("MarvinSimulateLibraryExit") else { return }
        Task.detached {
            try? await Task.sleep(nanoseconds: 500_000_000)
            DispatchQueue(label: "exit-test").async {
                SealExit.now("MarvinSimulateLibraryExit triggered", status: 42)
            }
        }
    }
}
