# Mac calls behavior

What happens in every state when every event occurs. Rows = states; columns = events. Per owner decisions (2026-10-29): second call → keep call 1, announce call 2; announcements → Notification Center only; missed call → nothing left. Owner approval (#212 comment) covers every product choice here.

| State | Rings | Answered (Caption) | Answered (Not now) | Second call rings | Hold | End & Accept | Hold & Accept | Declined | Missed (unanswered) | Ended | Ended before answered |
|-------|-------|----|----|----|----|----|----|----|----|----|----|
| Closed | — | — | — | — | — | — | — | — | — | — | — |
| Idle (captions off) | Notify (ringing) | Caption call, start captions | Nothing | — | — | — | — | — | — | — | — |
| Captioning room | Notify (ringing) | Pause room, caption call | Nothing | Notify (second call) | — | — | — | Nothing | — | — | — |
| Captioning call | — | — | — | Notify (second call) | Hold call 1 | End call 1, offer save, start call 2 | Hold call 1, start call 2 | — | Nothing | Offer save, then resume room (or restore if captions were off) | — |
| Room paused for call | — | — | — | Notify (second call) | Hold call 1 | End call 1, offer save, start call 2 | Hold call 1, start call 2 | — | Nothing | Offer save, then resume room | — |
| Call 1 held, call 2 active | — | — | — | Notify (call 3 ringing) | — | End call 2, offer save, resume call 1 | Hold call 2, resume call 1 | — | Nothing | Offer save, then resume call 1 | — |
| Save prompt showing (after call) | (Waits for answer) | — | — | (Queued after answer) | — | — | — | — | — | — | — |
| Window hidden/minimized | Notify (ringing) | Notify → Caption call | Notify → Nothing | Notify (second call) | — | — | — | Notify → Nothing | Nothing | Notify → Offer save | — |
| Zoom full screen | Notify (ringing) | Notify → Caption call | Notify → Nothing | Notify (second call) | — | — | — | Notify → Nothing | Nothing | Notify → Offer save | — |

## Simplifications

- **Window visibility no longer branches behavior:** once announcements moved to Notification Center only, the window state (hidden/minimized/other Space, Zoom full screen) became identical to the in-focus case — the notification works the same way, so rows 7 and 8 above match rows 2–5. Kept visible here for completeness; implementers can simplify.
- **"Ended before answered" row:** when a call ends before the first banner tap, it's identical to "missed" (a notification arrives, then clears with nothing). Included as explicit acceptance criterion 2 step in stacking tests (three-deep stack test).

## Evidence

Tests will cite specific test names and line numbers once written (references to `CallArrivalTests.swift`, `CallSignalTests.swift`, `CallWatcherTests.swift`). For the notifications-off case (row 8, column 10 of the original definition), screenshot review of `CallNotifier.setUp` and the app-level notification behavior is needed — not CaptionCore-testable.
