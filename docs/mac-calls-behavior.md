# Mac Call Behavior Table (#178)

A reference for handling multiple concurrent calls: the state × event matrix that drives `CallArrival` and the Mac app's call flow.

## States

| State | Meaning |
|-------|---------|
| **room** | Not in a call. Captioning the room (if captions are on). |
| **ringing** | A call is ringing; the banner is asking whether to caption it. |
| **declined** | The banner was dismissed or "Not now" was tapped; still ringing, but not asking again until the next call. |
| **call** | Captioning an active call; the room's conversation (if any) is paused on the stack. |
| **ended** | The active call ended; the banner is asking whether to save its transcript. |

## Frames

The stack of paused conversations:

| Frame | Meaning |
|-------|---------|
| `.room(captioning: Bool)` | The room conversation is on pause; `captioning` records whether it was being captioned when the call took over. |
| `.heldCall(app: String, captioning: Bool)` | A call (identified by app name) is on pause, e.g., held while a second call is active. `captioning` preserves the state for resume. |
| `.secondCallAwaiting(app: String)` | A second call is queued to start after the save prompt for the first call (used by `endAndAccept` only). |

## Events

| Event | Trigger | Allowed In |
|-------|---------|-----------|
| **callStarted** | A call app began using the microphone (or continued after a route change, like plugging in headphones). | `room`, `declined`, `ended` (waits for answer to previous save), `call` (second call) |
| **secondCallStarted** | A second call app or additional audio object started using the microphone while the first is still active. | `call` only |
| **secondCallEnded** | A second call app's ringing/hold ended without being answered or while held (not answered, no switch). | `call` only (after announcement cleared) |
| **callEnded** | The active call app stopped using the microphone (and stayed stopped for `endGrace` seconds). | `ringing`, `declined`, `call`, `ended` (waiting for save answer, stale) |
| **captionCall** | Tapped the ringing banner's [ Caption call ] button. | `ringing` only |
| **notNow** | Tapped the ringing banner's [ Not now ] button. | `ringing` only |
| **holdAndAccept** | Tapped the second-call notification's [ Hold & Accept ] (hold the first, start the second). | `call` only (new event, notified via second-call notification) |
| **endAndAccept** | Tapped the second-call notification's [ End & Accept ] (end the first, save prompt first, then start second). | `call` only (new event, notified via second-call notification) |
| **callHeld** | User tapped the system's Hold button during an active call (a pause with no second call involved). | `call` only (new event, from user action or system pause) |
| **callResumedFromHold** | User tapped the system's Resume button; the held call became active again. | `call` only (new event) |
| **saveTranscript** | Tapped [ Save ] on the transcript save prompt. | `ended` only |
| **returnToConversation** | Tapped [ Don't save ] or let the prompt time out. | `ended` only |

## Behavior Table: State × Event → Next State, Effects, Stack

### Room (no call, conversations running or idle)

| Event | Next State | Effects | Stack Change |
|-------|-----------|---------|--------------|
| **callStarted** | ringing | none | none |
| **secondCallStarted** | room | none (invalid) | none |
| **secondCallEnded** | room | none (invalid) | none |
| **callEnded** | room | none (stale) | none |
| **captionCall** | room | none (stale) | none |
| **notNow** | room | none (invalid) | none |
| **holdAndAccept** | room | none (invalid) | none |
| **endAndAccept** | room | none (invalid) | none |
| **callHeld** | room | none (invalid) | none |
| **callResumedFromHold** | room | none (invalid) | none |
| **saveTranscript** | room | none (stale) | none |
| **returnToConversation** | room | none (stale) | none |

### Ringing (banner asking about the call)

| Event | Next State | Effects | Stack Change |
|-------|-----------|---------|--------------|
| **callStarted** | ringing | none (repeat) | none |
| **secondCallStarted** | ringing | none (we're not captioning this call) | none |
| **secondCallEnded** | ringing | none | none |
| **callEnded** | room | none | none |
| **captionCall** | call | `[.pauseRoom, .startCall]` if captioning else `[.startCall]` | push `.room(captioning: bool)` |
| **notNow** | declined | none | none |
| **holdAndAccept** | ringing | none (invalid state) | none |
| **endAndAccept** | ringing | none (invalid state) | none |
| **callHeld** | ringing | none (invalid state) | none |
| **callResumedFromHold** | ringing | none (invalid state) | none |
| **saveTranscript** | ringing | none (stale) | none |
| **returnToConversation** | ringing | none (stale) | none |

### Declined (banner dismissed; call still ringing)

| Event | Next State | Effects | Stack Change |
|-------|-----------|---------|--------------|
| **callStarted** | declined | none (repeat) | none |
| **secondCallStarted** | declined | none (we're not captioning this call) | none |
| **secondCallEnded** | declined | none | none |
| **callEnded** | room | none | none |
| **captionCall** | declined | none (stale, ringing is over) | none |
| **notNow** | declined | none (repeat) | none |
| **holdAndAccept** | declined | none (invalid state) | none |
| **endAndAccept** | declined | none (invalid state) | none |
| **callHeld** | declined | none (invalid state) | none |
| **callResumedFromHold** | declined | none (invalid state) | none |
| **saveTranscript** | declined | none (stale) | none |
| **returnToConversation** | declined | none (stale) | none |

### Call (captioning an active call; room/earlier calls on stack)

| Event | Next State | Effects | Stack Change |
|-------|-----------|---------|--------------|
| **callStarted** | call | none (repeat) | none |
| **secondCallStarted** | call | `[.announceSecondCall(app:)]` | none (waits for hold&accept/end&accept/decline) |
| **secondCallEnded** | call | none (announcement cleared) | none |
| **callEnded** | ended | `[.stopCall]` | none (pop happens after save answer) |
| **captionCall** | call | none (stale, already captioning) | none |
| **notNow** | call | none (invalid state) | none |
| **holdAndAccept** | call | `[.holdCall, .startCall]` | push `.heldCall(app: previous, captioning: true)` |
| **endAndAccept** | ended | `[.stopCall]` | push `.secondCallAwaiting(app:)` (starts fresh after save) |
| **callHeld** | call | `[.holdCall]` | push `.heldCall(app: "paused-by-user", captioning: true)` |
| **callResumedFromHold** | call | `[.resumeHeldCall]` | pop `.heldCall(app: "paused-by-user", ...)` only |
| **saveTranscript** | call | none (invalid state) | none |
| **returnToConversation** | call | none (invalid state) | none |

### Ended (banner asking to save the transcript)

| Event | Next State | Effects | Stack Change |
|-------|-----------|---------|--------------|
| **callStarted** | ended | none (queues the call; don't start yet) | none |
| **secondCallStarted** | ended | none (invalid state, call ended) | none |
| **secondCallEnded** | ended | none (invalid state) | none |
| **callEnded** | ended | none (stale) | none |
| **captionCall** | ended | none (stale) | none |
| **notNow** | ended | none (stale) | none |
| **holdAndAccept** | ended | none (invalid state) | none |
| **endAndAccept** | ended | none (invalid state) | none |
| **callHeld** | ended | none (invalid state) | none |
| **callResumedFromHold** | ended | none (invalid state) | none |
| **saveTranscript** | room/call/ended | `[.saveCall, .resumeRoom]` / `[.saveCall, .resumeHeldCall]` / `[.saveCall, .startCall]` | pop: room→room, heldCall→call, secondCallAwaiting→call |
| **returnToConversation** | room/call/ended | `[.resumeRoom]` / `[.resumeHeldCall]` / `[.startCall]` | pop: room→room, heldCall→call, secondCallAwaiting→call |

## Special Rules

### Stack Unwinding

When a call ends, `callEnded` puts the state in `.ended` (asking to save). When the save answer arrives (`saveTranscript` or `returnToConversation`), pop one frame from the stack:

- If the popped frame is `.room(...)`: emit `.resumeRoom` or `.restoreRoom` (depending on whether it was captioning), transition to `.room`.
- If the popped frame is `.heldCall(app: ...)`: emit `.resumeHeldCall` (which restores the held call's stream and start time), transition to `.call`.
- If the popped frame is `.secondCallAwaiting(app: ...)`: emit `.startCall` (which starts the second call fresh), transition to `.call`.
- If the stack is now empty after popping, go to `.room`; otherwise, stay in `.ended` to ask about the next frame.

### Second Call Notifications

When `secondCallStarted` fires in the `call` state, emit `[.announceSecondCall(app:)]` but do not change any state. A separate notification category is posted with distinct actions: [ Hold & Accept ], [ End & Accept ], [ Not now ]. These action taps send `holdAndAccept`, `endAndAccept`, or (not now) no event (treated like ignoring a ringing banner).

### Hold Mechanics

Both plain holds and second-call holds use the same stack mechanism:

- **Plain hold** (`callHeld`): Pauses the current call by pushing `.heldCall(app: "paused-by-user", captioning: true)`. When resumed via `callResumedFromHold`, pops that frame and emits `.resumeHeldCall`, which restores the exact stream, speakers, and start time of the held call.

- **Second-call hold** (`holdAndAccept`): Pauses the current call by pushing `.heldCall(app: <held_call_app>, captioning: true)` and immediately starts the second call fresh. When the second call ends and `resumeHeldCall` fires, restores the first call's state.

The `captioning` field preserves the state for accurate resume; the `app` field distinguishes between plain holds (empty string marker) and second-call holds (first call's app name).

### Saving at Each Depth

Every time a call or held call ends and the state becomes `.ended`, the save question is asked. Only after it's answered do we pop from the stack and move to the next frame. This ensures no transcript is lost, even in a three-deep scenario (room → call1 → call2): each one asks independently before the previous is resumed.

### Notification Channel

Per the "announce" decision, second-call announcements appear in Notification Center only (no in-window banner), matching the approved removal of the first-call in-window announcement. The notification carries the second call's app name and offers three actions.

---

## Test Harness: the `run(...)` Pattern

Each test sequence is a list of `(event, captioning)` tuples, fed to `CallArrival.handle(_:captioning:)` one at a time. The test harness collects all emitted effects and compares the final state and effects to the expected values. See `CallArrivalTests.swift` for the implementation.
