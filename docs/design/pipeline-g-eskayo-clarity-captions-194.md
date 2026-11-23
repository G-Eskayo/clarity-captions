## North-star fit

- **Reuses before adding anything new:**
  - `Apps/Spike/Sources/DemoMode.swift`'s `flag(_:)` / `value(after:)` (`ProcessInfo.processInfo.arguments`, never `UserDefaults`) is the existing "read launch arguments only" pattern — I'll lift it into a small, platform-agnostic `public` type in CaptionCore (`LaunchArguments`) instead of re-deriving it, so it's unit-tested once and usable by any future flag (Mac or iPhone).
  - `Packages/CaptionCore/Tests/CaptionCoreTests/OneScreenSourceRulesTests.swift`'s `appSources()` / `code()` / `occurrences()` helpers (scan an app's `Sources` dir as text, strip `//` comments, assert on substring counts) is the existing "a test or source rule fails if X reappears" pattern. I'll copy it pointed at `Apps/Mac/Sources` instead of `Apps/Spike/Sources` — that single pattern satisfies both AC #1 (no new bare `exit(`) and most of AC #2 (no test-only key read via `UserDefaults.standard`).
  - `CallFlow.swift:167`'s `Logger(subsystem: "com.gileskayo.captions", category: "calls")` is the existing logging pattern (ADR 0027's own debug harness) — reused verbatim with a new `category: "exit"` for the exit/backtrace logs, not a new logging mechanism.
- **Simplest sufficient approach:** one new tiny CaptionCore type (`LaunchArguments`, pure, no I/O) + one new Mac-app file (`ExitLogging.swift`: a single `exit()` chokepoint + the `atexit` install + the one new debug hook) + edits to route the 4 existing self-test files and `CallFlow.swift`'s fake-call harness through both. No new abstraction layer, no test target added to `Apps/Mac` (there isn't one, and the project's hard rule is that CaptionCore's XCTest is the only automated behavior check — so the parts that *can* be pure move to CaptionCore; the parts that can't (the real `atexit`/`exit()` call) stay thin and untested by design, same as every other `Apps/Mac` file today).
- **Where it spends tokens / where it saves them:** spends a little now writing one new pure type + its tests; saves on every *future* test-only flag (iPhone or Mac) that can reuse `LaunchArguments` instead of re-deriving `DemoMode`'s private helpers, and on every future "don't let old debug state haunt a shipped build" bug class.
- **More capable, not more passive:** the owner gets a named cause the next time this happens, instead of an unexplained vanished caption session — directly serves north star 3 ("captions never just disappear").
- **Important finding beyond the ticket's example list:** `CallFlow.swift:170–184` (`runFakeCallIfRequested`, the `-SealFakeCall` pretend-call harness used in the *original incident itself*, `-SealFakeCall 15,35`) also reads `SealFakeCall`/`SealFakeChoice`/`SealFakeSave`/`SealFakeShots`/`SealFakeStart`/`SealFakeHide` through `UserDefaults.standard`. The ticket says "for example `MarvinScene`, `MarvinScreenshot`" — not an exhaustive list — and this is the single most relevant one to fix, since it's the flag active 20s before the original silent quit. I'm folding it into AC #2's scope.
- **What's out of scope:** `listenTo` (`CallFlow.swift:19`, `CaptionMacModel.swift:20`) is a documented *persistent* user setting (ADR 0027, `defaults write com.gileskayo.captions listenTo facetime|room`), not a test-only flag — left untouched. `Apps/Spike` (iPhone) is untouched; the ticket is Mac-only.

## Decisions / blocked steps (not a design fork — flagging plainly, not guessing)

1. **AC #4, the 10-run soak test, cannot be executed from this worktree.** It needs the real MacBook, a granted "System Audio Recording" permission, and a human watching/running `-SealFakeCall` for 2+ minutes × 10. This pipeline run can ship the logging/hardening and its tests, but the soak itself — and "record results on the ticket" — is an owner-dependent step I cannot close. I'll say this plainly in the PR rather than fabricate results.
2. **The `defaults read` check on the MacBook** (ticket: "Check `defaults read` on the MacBook for any such key") is likewise a real-machine step I can't perform from an isolated worktree with no access to the owner's Mac.

Both are named as the last, unchecked task-list item below rather than invented away.

## Tests first (CaptionCore XCTest, `swift test --package-path Packages/CaptionCore`)

**New file `LaunchArgumentsTests.swift`** (pure type, from the ticket's break-it list + misuse additions):
1. Flag present → `true`; flag absent → `false`.
2. **Saved `UserDefaults` default does nothing** (AC #2, ticket's break-it item 1 directly): set `UserDefaults.standard.set(true, forKey: "MarvinHideCheck")`, build `LaunchArguments([])`, assert `.flag("-MarvinHideCheck") == false`.
3. `value(after:)` returns the next argument; returns `nil` when the flag is the last argument (malformed/missing value); returns `nil` when the flag is absent.
4. Empty-string value (`-MarvinScene ""`) is returned as `""`, not conflated with "absent".
5. Duplicate flags (`["-MarvinHideCheck", "-MarvinHideCheck"]`) don't crash; `value(after:)` with a flag repeated uses the first occurrence.
6. Empty argument list never matches anything (no crash on "huge/empty input").
7. A few thousand synthetic arguments don't crash or misbehave (states the O(n) time / O(1) extra space bound).
8. `double(after:)` parses a numeric value and returns `nil` for a non-numeric one (`-SealCallPhase notanumber`).
9. Concurrent reads from multiple tasks on one `LaunchArguments` instance don't crash (value-type, no shared mutable state — proves the "repeats/concurrency" misuse case structurally).

**New file `MacSourceRulesTests.swift`** (`#if os(macOS)`, pattern copied from `OneScreenSourceRulesTests.swift`, pointed at `Apps/Mac/Sources`):
10. **AC #1 regression gate:** every `exit(` occurrence in `Apps/Mac/Sources` is inside `ExitLogging.swift` (the one definition site) — fails if a new bare `exit(` appears anywhere else.
11. **AC #2 regression gate:** none of the known test-only key literals (`MarvinScene`, `MarvinScreenshot`, `MarvinAppearance`, `MarvinHideCheck`, `MarvinRouteWatch`, `CallAudioSelfTest`, `MarvinSettingsSection`, `MarvinLiveSnapshot`, `MarvinLiveSnapshotAfter`, `SealPopupMockup`, `SealTranslateMockup`, `SealCallMockup`, `SealCallPhase`, `SealFakeCall`, `SealFakeChoice`, `SealFakeSave`, `SealFakeShots`, `SealFakeStart`, `SealFakeHide`, `MarvinSimulateLibraryExit`) appear next to `UserDefaults.standard` anywhere in `Apps/Mac/Sources`. Also asserts `listenTo` *is* still read via `UserDefaults.standard` (sanity check the scan isn't vacuous, and that the real persistent setting wasn't accidentally swept up).
12. **Attack "App Store build: no extra logging of caption text"**: every `SealExit.now(` call site's literal reason string contains none of `stream`, `transcript`, `captionText`, `.lines` — i.e., nobody ever passes caption content into an exit reason.

**Untested by design (stated plainly, not hidden):** the real `atexit()` registration, the real backtrace capture at an actual process exit, and the real `os_log`/Console output — there's no `Apps/Mac` XCTest target and this is genuine OS/process-level behavior, consistent with every other file in `Apps/Mac/Sources` today. The soak test is the only thing that exercises this for real, and that's the owner-dependent step above.

## Task List

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