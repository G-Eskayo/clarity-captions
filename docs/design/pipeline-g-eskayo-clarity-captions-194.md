## North-star fit

- **Reuses before adding:** `OneScreenSourceRulesTests.swift`'s `appSources()`/`code()`/`occurrences()` pattern (text-scan a source directory from `#filePath`, strip comments, assert on matches) — I'll copy this pattern into a new `MacExitLoggingSourceRulesTests.swift` pointed at `Apps/Mac/Sources` instead of `Apps/Spike/Sources`. I also reuse `Apps/Spike/Sources/DemoMode.swift`'s `flag(_:)`/`value(after:)` launch-argument parsing (`ProcessInfo.processInfo.arguments`, not `UserDefaults`) — same idea, promoted into a small testable `LaunchArgs` type. The `Logger(subsystem: "com.gileskayo.captions", …)` convention already in `CallFlow.swift:167` sets the subsystem string to reuse.
- **Simplest sufficient form:** one wrapper function (`ExitLogging.quit`) that every deliberate `exit()` call routes through, enforced by a text-scan test rather than a custom SwiftLint rule or build plugin. One `atexit()` registration catches *any* exit, including ones from library code, with zero new infrastructure (no new executable target, no subprocess harness).
- **Where it spends/saves:** spends a handful of small, pure files; saves future debugging time — any next silent quit now names itself in the unified log instead of leaving no trace. No network, no new dependencies, no new persisted state.
- **More capable, not more passive:** this doesn't automate away judgment — it gives Gil (or whoever runs the soak) the evidence needed to actually diagnose a quit, rather than doing that diagnosis for him.
- **Scope boundary (judgment call, not guessing):** `CallFlow.swift`'s `listenTo` key is documented in its own header as *meant* to be set by hand via `defaults write … listenTo both` and persist — that's a deliberate override, not a stray test flag, so it's excluded from the launch-args-only hardening. Likewise `CallFlow.runFakeCallIfRequested()`'s `SealFakeCall`/`SealFakeChoice`/`SealFakeSave`/`SealFakeShots` aren't named in the ticket, don't call `exit()`, and aren't the files called out — converting them would be scope creep against north star 1, so I'm leaving them as-is.
- **What I'm not able to do:** AC4 (10 real pretend-call soak runs with results recorded on the ticket) needs a live Mac with System Audio Recording/mic permission already granted and someone to watch/record outcomes — this agent has no audio hardware or interactive session and can't run it. I'll build AC1–3 so the soak (whenever the owner or pipeline runs it on real hardware) has something to read, and say this plainly rather than fake a result.

## Existing code already covered

Checked `ProcessTapAudioSource.swift`, `FailureReason.swift`, `EngineFallbackPolicy.swift` for existing handling of a dropped helper/XPC connection (the third "how we'll try to break it" bullet) — found no explicit invalidation handling, but building new resilience logic isn't in the ticket's "What to build" list; the ticket's own sequencing treats this as something the *soak* surfaces, fixed with a test only if it actually recurs. I'm not inventing that fix speculatively.

## Tests to write first

1. **`LaunchArgsTests.swift`** (new, `Packages/CaptionCore/Tests/CaptionCoreTests/`) — exercises the new `LaunchArgs` pure type:
   - *Ticket's attack 1 ("saved MarvinScene default, normal launch, must not quit"):* set `UserDefaults.standard.set(..., forKey: "MarvinScene")` (and `"MarvinScreenshot"`, `"MarvinHideCheck"`, `"CallAudioSelfTest"`), call `LaunchArgs.value(after:)`/`flag(_:)` with an empty/unrelated arguments array, assert `nil`/`false`, then clean up the stuck key (`removeObject`) in `defer` so the test doesn't leak into the real preferences domain.
   - Real launch argument present → correct value returned, regardless of whatever is also stuck in `UserDefaults`.
   - Malformed: flag name is the last argument with no following value → `value(after:)` returns `nil`, no crash.
   - Empty arguments array → `flag` false, `value(after:)` nil.
   - Flag name appears twice → first match wins (documents the behavior).
2. **`MacExitLoggingSourceRulesTests.swift`** (new, same directory, same `appSources()`-style helper pointed at `Apps/Mac/Sources`):
   - *AC1's own test-or-rule requirement:* every occurrence of the substring `exit(` (comments stripped) in `Apps/Mac/Sources` is inside `ExitLogging.swift` — fails the moment a new bare `exit(` is added anywhere else.
   - The five converted files (`CallAudioSelfTest.swift`, `HideCheck.swift`, `MarvinScreenshot.swift`, `MarvinScene.swift`, `IPhoneViewShims.swift`) contain no `UserDefaults.standard` at all (code-only) — proves the launch-args-only conversion is complete, not partial.
   - *Attack 4 ("App Store build: no extra logging of caption text"):* no `ExitLogging.quit(` call site's line also references `model.stream`/`.lines`/caption text — keeps the reason strings to identifiers/status only.
3. **Attack 2 ("a quit from inside a library, simulated with a test hook calling `exit(0)` from a background queue")** — this can't be an XCTest (there's no Mac test target, and actually calling `exit()` in-process would kill the test runner). I'll add a debug-only launch-argument hook (through `LaunchArgs`/`ExitLogging`) that triggers exactly this from a background queue, and document that it's verified by running the built app and checking the unified log for the `ExitBacktrace` fault line — **untested by `swift test`, explicitly called out as such in the PR.**
4. **Attack 3 (XPC/helper killed mid-call)** — no new mechanism built per the scope note above; this is exercised by AC4's manual soak, not by an automated test here.

## Task List

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