1. Add `Packages/CaptionCore/Sources/CaptionCore/LaunchArguments.swift`: a pure `public struct LaunchArguments` (`flag(_:)`, `value(after:)`, `double(after:)`) over an injected `[String]` (defaulting to `CommandLine.arguments`).
2. Add `LaunchArgumentsTests.swift` (tests 1–9 above) — red, then green.
3. Add `Apps/Mac/Sources/ExitLogging.swift`:
   - `enum SealExit { static func now(_ reason: String, status: Int32 = 0) -> Never }` — logs via `Logger(subsystem: "com.gileskayo.captions", category: "exit")` then calls `exit(status)`.
   - `enum ProcessExitLog { static func install() }` — registers one `atexit` handler that logs `Thread.callStackSymbols` at `.fault`, `privacy: .public`.
   - `enum ExitFaultSelfTest { static func runIfRequested() }` — `-MarvinSimulateLibraryExit`, read via `LaunchArguments`: after a short delay, calls `SealExit.now(...)` from a background queue (ticket's break-it item 2's "test hook"). No `#if DEBUG` gate, matching the sibling self-test files (`CallAudioSelfTest`, `HideCheck`, `MarvinScene`, `MarvinScreenshot`), since the atexit/backtrace behavior must also be verified on the sandboxed TestFlight build.
4. Wire `CaptionMacApp.init()`: call `ProcessExitLog.install()` first, then the existing `runIfRequested()` calls, then `ExitFaultSelfTest.runIfRequested()`.
5. Route every existing `exit(` call through `SealExit.now(reason:status:)`, keeping all existing stdout/stderr prints unchanged (other tooling parses them):
   - `CallAudioSelfTest.swift` (lines 24, 107, 117)
   - `HideCheck.swift` (27, 39)
   - `MarvinScene.swift` (52)
   - `MarvinScreenshot.swift` (40, 43)
6. Switch every test-only `UserDefaults.standard` read to `LaunchArguments`, leaving `listenTo` untouched:
   - `CallAudioSelfTest.swift` (`CallAudioSelfTest`, `MarvinRouteWatch`)
   - `HideCheck.swift` (`MarvinHideCheck`)
   - `MarvinScene.swift` (`MarvinScene`, `MarvinScreenshot`, `MarvinAppearance`)
   - `MarvinScreenshot.swift` (`MarvinScreenshot`, `MarvinScene`, `MarvinAppearance`, `SealPopupMockup`, `SealTranslateMockup`, `SealCallMockup`, `SealCallPhase`, `MarvinLiveSnapshot`, `MarvinLiveSnapshotAfter`)
   - `IPhoneViewShims.swift` (`MarvinSettingsSection`)
   - `CallFlow.swift` (`SealFakeCall`, `SealFakeChoice`, `SealFakeSave`, `SealFakeShots`, `SealFakeStart`, `SealFakeHide`)
7. Add `MacSourceRulesTests.swift` (tests 10–12 above) — red against the pre-refactor tree, green after steps 5–6.
8. Run `swift test --package-path Packages/CaptionCore` full suite; confirm no regression elsewhere.
9. PR: state plainly that the `atexit`/backtrace path is untested by XCTest (no Mac test target, can't run/kill the app from here), and that AC #4 (the 10-run soak, results on the ticket) and the `defaults read` check are owner-dependent steps this run cannot close — leave them as the open items on the ticket.