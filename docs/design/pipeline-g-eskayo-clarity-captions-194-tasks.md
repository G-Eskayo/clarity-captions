1. Add `Packages/CaptionCore/Sources/CaptionCore/LaunchArgs.swift` — `flag(_:in:)` / `value(after:in:)`, `arguments` defaulting to `ProcessInfo.processInfo.arguments`, injectable for tests.
2. Add `Packages/CaptionCore/Tests/CaptionCoreTests/LaunchArgsTests.swift` per the tests above.
3. Add `Apps/Mac/Sources/ExitLogging.swift`: `ExitLogging.quit(_ code: Int32, because reason: String) -> Never` (logs via `Logger(subsystem: "com.gileskayo.captions", category: "exit")`, then exits), plus `ExitBacktrace.installIfEnabled()` (`atexit` + `Thread.callStackSymbols`, gated by `#if DEBUG` or `Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"` for TestFlight — synchronous, no StoreKit round-trip, since the handler must be live before anything can exit).
4. Call `ExitBacktrace.installIfEnabled()` as the first line of `CaptionMacApp.init()` (`CaptionMacApp.swift:12`).
5. `CallAudioSelfTest.swift`: convert lines 16/19/20 to `LaunchArgs`; convert `exit(` at lines 24, 107, 117 to `ExitLogging.quit(...)`.
6. `HideCheck.swift`: convert line 9 to `LaunchArgs.flag`; convert `exit(` at lines 27, 39 to `ExitLogging.quit(...)`.
7. `MarvinScreenshot.swift`: convert all `UserDefaults.standard` reads (lines 16–30, 48–58) to `LaunchArgs`; convert `exit(` at lines 40, 43 to `ExitLogging.quit(...)`.
8. `MarvinScene.swift`: convert lines 12, 19, 20 to `LaunchArgs`; convert `exit(` at line 52 to `ExitLogging.quit(...)`.
9. `IPhoneViewShims.swift`: convert line 54 to `LaunchArgs.value(after:)`.
10. Add the debug-only "exit from a background queue" hook (attack 2) through the new `LaunchArgs`/`ExitLogging` plumbing; document it as manually-verified in the PR body.
11. Add `Packages/CaptionCore/Tests/CaptionCoreTests/MacExitLoggingSourceRulesTests.swift` per above.
12. Run `swift test --package-path Packages/CaptionCore` until green.
13. In the PR: state plainly that AC4 (10×2-minute `-SealFakeCall` soak runs, results on the ticket) cannot be run by this agent — no real audio hardware/interactive permission grant available — and needs the owner or pipeline's real-machine step to run it post-merge using the new logging.