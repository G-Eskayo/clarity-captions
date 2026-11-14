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
| `.heldCall(app: String)` | A call (identified by app name) is on pause, e.g., held while a second call is active. |

## Events

| Event | Trigger | Allowed In |
|-------|---------|-----------|
| **callStarted** | A call app began using the microphone (or continued after a route change, like plugging in headphones). | `room`, `declined`, `ended` (waits for answer to previous save), `call` (second call) |
| **secondCallStarted** | A second call app started using the microphone while the first is still active. | `call` only |
| **secondCallEnded** | A second call app's ringing/hold ended without being answered or while held (not answered, no switch). | `ringing`, `call` (after hold&accept) |
| **callEnded** | The active call app stopped using the microphone (and stayed stopped for `endGrace` seconds). | `ringing`, `declined`, `call`, `ended` (waiting for save answer, stale) |
| **captionCall** | Tapped the ringing banner's [ Caption call ] button, or tapped [ Hold & Accept ] for a second call. | `ringing` only (or second-call notification actions) |
| **notNow** | Tapped the ringing banner's [ Not now ] button. | `ringing` only |
| **holdAndAccept** | Tapped the second-call notification's [ Hold & Accept ] (hold the first, start the second). | `call` only (new event, notified via second-call notification) |
| **endAndAccept** | Tapped the second-call notification's [ End & Accept ] (end the first, save prompt first, then start second). | `call` only (new event, notified via second-call notification) |
| **callHeld** | User tapped the system's Hold button during an active call (a pause with no second call involved). | `call` only (new event, from CallWatcher heuristic or user action) |
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
| **secondCallStarted** | ringing | `[.announceSecondCall]` | none (stacked notifications) |
| **secondCallEnded** | ringing | none (repeat announcement cleared) | none |
| **callEnded** | room | none | none |
| **captionCall** | call | `[.pauseRoom, .startCall]` if captioning else `[.startCall]` | push `.room(captioning: false)` if captioning, else nothing |
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
| **secondCallStarted** | call | `[.announceSecondCall]` | none (waits for hold&accept/end&accept/decline) |
| **secondCallEnded** | call | none (repeat cleared) | none |
| **callEnded** | ended | `[.stopCall]` | none (pop happens after save answer) |
| **captionCall** | call | none (stale, already captioning) | none |
| **notNow** | call | none (invalid state) | none |
| **holdAndAccept** | call | `[.holdCall, .startCall]` | push `.heldCall(app: previous)` |
| **endAndAccept** | ended | `[.stopCall]` | pop happens after save answer; next call pending |
| **callHeld** | call | `[.holdCall]` | push `.heldCall(app: "")` (temporary hold) |
| **callResumedFromHold** | call | `[.resumeHeldCall]` (resume from hold state) | pop `.heldCall("")` |
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
| **saveTranscript** | room or (call if stack has heldCall) | `[.saveCall, .resumeRoom]` or `[.saveCall, .resumeHeldCall]` | pop from stack |
| **returnToConversation** | room or (call if stack has heldCall) | `[.resumeRoom]` or `[.resumeHeldCall]` | pop from stack |

## Special Rules

### Stack Unwinding

When a call ends, `callEnded` puts the state in `.ended` (asking to save). When the save answer arrives (`saveTranscript` or `returnToConversation`), pop one frame from the stack:

- If the popped frame is `.room(...)`: emit `.resumeRoom` or `.restoreRoom` (depending on whether it was captioning).
- If the popped frame is `.heldCall(app: ...)`: emit `.resumeHeldCall` (which starts captioning that call again).
- If the stack still has more frames after popping: stay in `.ended` (ask to save the next level). If the stack is now empty, go to `.room`.

### Second Call Notifications

When `secondCallStarted` fires in the `call` state, emit `[.announceSecondCall]` but do not change any state. A separate notification category is posted with distinct actions: [ Hold & Accept ], [ End & Accept ], [ Decline ]. These action taps send `holdAndAccept`, `endAndAccept`, or (decline) no event (treated like ignoring a ringing banner).

### Hold Mechanics

`callHeld` pauses the current call (same as `pauseRoom` pauses the room) by pushing `.heldCall(app: "")` onto the stack. `callResumedFromHold` resumes it, popping that frame and emitting `.resumeHeldCall`. Both plain holds and second-call holds use the same stack mechanism; the difference is that a plain hold is triggered by a UI button on the call itself, while a second-call hold (`holdAndAccept`) is triggered by a notification action.

### Saving at Each Depth

Every time a call or held call ends and the state becomes `.ended`, the save question is asked. Only after it's answered do we pop from the stack and move to the next frame. This ensures no transcript is lost, even in a three-deep scenario (room → call1 → call2): each one asks independently before the previous is resumed.

---

## Test Harness: the `run(...)` Pattern

Each test sequence is a list of `(event, captioning)` tuples, fed to `CallArrival.handle(_:captioning:)` one at a time. The test harness collects all emitted effects and compares the final state and effects to the expected values. See `CallArrivalTests.swift` for the implementation.
