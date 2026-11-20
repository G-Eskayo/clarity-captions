I've read issue #212, its 9 comments (including the already-answered Decisions and two prior "mixed"-verdict failures), the related issues (#178 closed, #195/#194 open single-call follow-ups, #231/#213 Live Translation — explicitly out of scope), the current `CallArrival`/`CallWatcher`/`CallFlow`/`CallNotifier` code, the existing test style, the `from-into-spec.md` table precedent, and a leftover WIP backup commit (`c039b20`) from an earlier automated attempt on this exact ticket — useful for seeing what was tried and why it stalled, not something I'm adopting wholesale.

## North-star fit

**Reuses:** `CallArrival` (`Packages/CaptionCore/Sources/CaptionCore/CallArrival.swift`) is the existing pure state machine for one call over the room — its `handle(_:captioning:)` shape, `Effect` list, and `CallFlow.perform(_:)`'s sequential effect-queueing (`Apps/Mac/Sources/CallFlow.swift:53-134`) are reused directly; this ticket generalizes the single paused level (`resumeRoomAfter: Bool` / `pausedRoom` tuple) into a stack of the same kind of frame, it doesn't replace the mechanism. `CallWatcher`/`CallSignal` stay the only detection source (no new permission). `CallNotifier` is reused for the one notification channel the owner picked, rather than adding a second path. `SessionRetention.shouldSave` / `SavedConversation.from` are reused unchanged for every save offer at every stack depth. The `from-into-spec.md` doc (`docs/design/from-into-spec.md`) is the pattern to reuse for citing evidence (file:line, test name, Status) once the behavior table is built — not its row shape, which is Case/Target-behaviour; the ticket itself prescribes a different shape (state rows × event columns), so that part is new structure, following the ticket's own letter.

**Why simplest sufficient:** reading `CallArrivalTests.swift` shows the single-call model already gets most of the table right (ringing-while-idle, decline, missed/ended-before-answer, duplicate-signal repeats, captions-off path). The owner's named bug is visible directly in `CallArrival.handle`: `(.call, .callStarted)` isn't a matched case, so it falls into `default: return []` — a second call during a captioned call is silently swallowed as a repeat signal today. Generalizing the one `Bool`/tuple into a small stack, plus one new event for "a second call started," covers the stacking rules without a parallel mechanism.

**Where it spends tokens, and the one real gap:** the product decisions are all already answered (checked in the issue). What is *not* settled, and what I believe caused the two prior "mixed" verdicts, is the **detection signal** for "a second call is ringing." `CallWatcher`/`CallSignal` currently expose only *one* `liveApp` name from Core Audio process activity (`CallSignal.liveCallApp`), and the one real recorded timeline we have (evidence E24, in `RealFaceTimeCallReplayTests`) only verifies first-call detection. A second FaceTime call during an active FaceTime call is the single most realistic version of "the owner's bug," and it would show the *same* process name (`com.apple.FaceTime`/`avconferenced`) both times — nothing in the current signal distinguishes "still one call" from "a second call joined." I will build the pure logic against an abstract `secondCallStarted` event (fully testable, no new permission) and propose a best-effort heuristic in `CallWatcher` (watching for a *new* audio object among call-app processes rather than just a name), but I'm flagging this plainly as unverified against a real second-call timeline — the same thing acceptance criterion 3 already asks the owner to confirm by hand. I will not guess silently here.

**Phone-OS / capability fit:** reliable behavior under multiple overlapping interrupting events (notifications, overlapping triggers, stacked saved state) is exactly the "nothing breaks silently" discipline north star 2 needs elsewhere. It protects an irreplaceable record (a call's transcript) rather than automating away a choice the user would want to make — every save/caption/hold choice still asks her.

**Where a north star argues against part of the approach:** north star 1 (minimize) would argue against a general `CallStack` abstraction if only two levels were ever realistic — but acceptance criterion 2 explicitly requires a three-deep stack test, so the generalization is spec'd by the ticket, not speculative.

## Design

**1. The behavior table (`docs/mac-calls-behavior.md`, linked from `CONTEXT.md`'s "Caption states" area).** Its rows and columns are the ticket's own words, not the internal FSM's enum names — these are two different things and I'll keep them visibly separate: rows = closed, idle (captions off), captioning the room, captioning a call, room paused for a call, save-transcript prompt showing, window hidden/minimized/other Space, Zoom full screen; columns = rings, answered, second call rings, held, hand-off (End & Accept / Hold & Accept), declined, missed, ended, ended before answered. Each cell states window / Notification Center / transcript outcome, citing the test that proves it (file + test name), following `from-into-spec.md`'s evidence convention. Two rows simplify once the "Notification Center only" decision is applied: window-visibility state (hidden/minimized/other Space, Zoom full screen) stops branching behavior, since the announcement never depends on window visibility any more — worth calling out explicitly as a simplification, not an oversight.

**2. Generalize `CallArrival` (CaptionCore) into a stack**, additive to the existing enums so every current test keeps passing unchanged:
- `Frame`: `.room(captioning: Bool)` or `.heldCall(app: String)`; `private var paused: [Frame]` replaces `resumeRoomAfter`.
- New events: `secondCallStarted(app:)`, `secondCallEnded` (rang/held without being answered), `holdAndAccept`, `endAndAccept`, plus a plain `callHeld`/`callResumedFromHold` pair for a single active call's own Hold button (same mechanics, no second call involved).
- New effects: `.holdCall` (mirrors `.pauseRoom` for a call frame), `.announceSecondCall(app:)` (Notification-Center only — never the in-window ringing banner, per the owner's checked "announce" decision), `.resumeHeldCall` (generalizes `.resumeRoom`/`.restoreRoom` to pop any frame kind).
- `endAndAccept` must not start call 2 until call 1's save prompt is answered — call 1 goes to `.ended` first; call 2's start is effect-queued behind the save answer, mirroring the existing queued-effects discipline in `CallFlow.send`.

**3. `CallFlow` (Mac app layer):** generalize the single `pausedRoom` tuple into a stack of the same tuple shape plus its `Frame`, so `perform(_:)` stays a straightforward switch — no new control-flow shape, matching the WIP's own (correct) observation that this keeps complexity flat.

**4. Notification policy change:** per the owner's checked decision ("Notification Center only"), drop the `!CallNotifier.windowInFront` gate in `CallFlow.send` (`CallFlow.swift:59`) and remove `CallBannerView(kind: .ringing)` from `CallBannerSlot` — every ringing/second-call announcement goes through `CallNotifier` exclusively, regardless of window state. This is a look change (removing an existing window state), but the owner's checked decision in this ticket is the written approval the pr-requirements gate asks for; `CallBannerView(kind: .ended)` (the save-transcript prompt) is untouched — it's a decision prompt, not a call announcement, and nothing in the Decisions moves it.

**5. `CallNotifier`:** a second notification identifier/category (distinct `requestID`, since both the "second call" and an "ended, save?" state can be live at once) with actions "Hold & Accept" / "End & Accept" / "Not now", using the ticket's own FaceTime terminology.

**6. Untested by me, flagged, not guessed:**
- Real-device second-call/hold/hand-off detection (see "where it spends tokens" above) — needs the owner's real-call pass, which acceptance criterion 3 already requires.
- Notifications-off / Focus-mode in-window "how to turn notifications on" copy (one new UI string, a small look change) — I'll add it but call it out for the owner's screenshot review rather than assume it's pre-approved by the existing Decisions.
- #194 (silent quit mid-call) and #231/#213 (Live Translation on calls) are explicitly out of scope — the issue's own Seal-lane note says any spec conflict with #231 goes on #213, never into this PR.

## Tests to write first

In `CallArrivalTests.swift` / `CallSignalTests.swift` (extend in place, same `run(...)` harness), plus one new `CallWatcherTests.swift`:

1. Second call rings during a captioned call: announces only, call 1's step/transcript untouched (the owner's bug, reproduced then fixed).
2. Second call declined/ignored: no effects, call 1 keeps running.
3. Second call rings then ends unanswered: no lasting notification, nothing left (missed decision).
4. Hold & Accept: `[.holdCall, .startCall]`, call 1 recoverable, now captioning call 2.
5. Call 2 ends after hold: save prompt scoped to call 2, then `.resumeHeldCall` brings back call 1 (not the room, not a fresh call 1).
6. End & Accept: call 1 goes to `.ended` (save prompt) before call 2 ever starts capturing; call 2 only starts after the save answer.
7. Three-deep stack (room → call1 held → call2 held → call3) unwinds with a save offer at each of the three steps, in order, room reached last (acceptance criterion 2, verbatim).
8. Plain Hold/Resume on a solo call (no second call): `.holdCall`/`.resumeHeldCall`, transcript kept.
9. A notification action tapped after its call already ended: no-op (extends existing `testAButtonFromAStaleBannerDoesNothing`).
10. The same second call reported twice by Core Audio: exactly one `.announceSecondCall` (extends existing `testRepeatedSignalsDoNotStackUp`).
11. A third call ringing while an earlier save-prompt is still up: waits, doesn't jump the queue (extends existing `testANewCallDuringTheSaveQuestionWaitsForTheAnswer`).
12. Zoom/Teams/Meet joined from a link (no ring, `liveCallApp` just becomes non-nil): reaches `.call` directly, no ringing banner ever — name this case explicitly; today it's only implicit.
13. A Continuity call answered on the iPhone: no call-app process ever uses the Mac's mic, so `isCallLive` stays false (`CallSignalTests.swift`).
14. Mic held by Voice Memos/dictation/marvin-voice: not a call (extends existing `testOtherAppsUsingTheMicAreNotACall`, confirm/extend rather than duplicate).
15. Headphones/AirPods connect or disconnect mid-call: doesn't trip `endGrace`'s end-detection (new `CallWatcherTests.swift`, synthetic route-change activity).
16. Mac sleep/lid close mid-call: looks identical to a hang-up to `CallWatcher` (same `endGrace` path — a "confirm by test" row, not a fix).
17. App quitting mid-call (#194 follow-up, no fix attempted here): a state-machine-level assertion that `callEnded` always produces a save prompt, never a silent discard — documents the expectation #194's own fix needs, without touching #194's scope.
18. Notifications-off/Focus-mode: not CaptionCore-testable (AppKit/UNUserNotificationCenter concern) — covered instead by inspecting `CallNotifier.setUp`'s `requestAuthorization` outcome and documented in the behavior table as the one row that needs the owner's screenshot review.

## Decisions

None needed for buttons — every product choice (second-call handling, announcement channel, missed-call aftermath, stacking/save rules) is already checked in the issue. The two open items (second-call detection heuristic's real-device accuracy, and the notifications-off copy) are flagged risks for the PR body, not decisions requiring a vote.

## Task List

1. Write `docs/mac-calls-behavior.md`: the state × event table using the ticket's literal rows/columns, every cell filled per the owner's Decisions, citing evidence once tests exist; link it from `CONTEXT.md`.
2. Write tests 1–18 above in `CallArrivalTests.swift`, `CallSignalTests.swift`, and new `CallWatcherTests.swift` — expect the new ones to fail against today's code.
3. Generalize `CallArrival`: add `Frame`, `paused: [Frame]`, the new events (`secondCallStarted`, `secondCallEnded`, `holdAndAccept`, `endAndAccept`, `callHeld`, `callResumedFromHold`) and effects (`.holdCall`, `.announceSecondCall`, `.resumeHeldCall`), reusing the existing `Step`/`Banner`/`Effect` enums and `handle(_:captioning:)` shape; keep every existing test passing unchanged.
4. Update `CallFlow`: generalize `pausedRoom` into a stack of paused frames; wire the new events; remove the `!CallNotifier.windowInFront` gate and the in-window ringing banner from `CallBannerSlot` (Notification-Center-only, per decision); leave `CallBannerView(kind: .ended)` untouched.
5. Extend `CallNotifier`: a second notification identifier/category for a ringing second call, with "Hold & Accept"/"End & Accept"/"Not now" actions wired to the new events.
6. Extend `CallWatcher`/`CallSignal` with a best-effort second-call-ring heuristic (distinct audio object appearing among call-app processes, not just app-name change), documented in code comments as an assumption, not a verified signal.
7. Run `swift test --package-path Packages/CaptionCore` green; run the Mac app build (xcodebuild / app-build verify step) to confirm `CallFlow`/`CallNotifier` still compile.
8. In the PR: state plainly that real-device second-call/hold/hand-off detection and the notifications-off copy are untested by this agent, and that acceptance criterion 3 (real FaceTime calls, screen recordings) still needs the owner's MacBook pass.