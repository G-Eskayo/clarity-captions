# 0023 — Beta testers rate each conversation and send their metrics to the owner by text; App Store installs collect nothing

## Status

Accepted (2026-10-09, design PR #111); implemented by #112. Design: `docs/design/mocks/beta-feedback/`; report
format: `docs/beta/metrics-schema.md`; building a TestFlight build: `docs/beta/testflight.md`.

## Context

Before Seal goes on the App Store (target: submitted by about 15 Oct, live for 25 Oct), the owner is giving a beta
build to family and friends through TestFlight. Their phones range from iPhone 14 to iPhone 17. To fix what
actually goes wrong, we need to know how well people could follow a conversation, and how the app behaved
on each phone: lag, accuracy, speaker labels, stops, battery and heat.

TestFlight already supplies crash reports, the device model and iOS version, and screenshot feedback. It can't
supply the rest.

Seal's promise is that it collects nothing (ADR 0007, 0008, 0014, 0022; `site/privacy.html`; the App Store
privacy label "Data Not Collected"). A conversation holds other people's words, which are never ours to collect.

## Decision

1. **Beta only.** Feedback and metrics exist only in TestFlight installs. One binary serves both: at launch the
   app reads `AppTransaction.shared` (StoreKit 2, verified in the iOS 26 SDK). `environment == .sandbox` means
   TestFlight, so beta features are on. `.production` means App Store, so they're off: nothing is recorded and
   no feedback UI exists. `.xcode` means a development build, so they're on for testing.
   - The answer is cached for the install.
   - **Fail closed:** if the check fails or the result can't be verified, the app behaves as the App Store
     version.
   - This is the only StoreKit call. Like the one-time speech-model download, it goes to Apple, and the app makes
     no network calls of its own.
2. **Never collected, in any build:** caption text, audio, speaker names, vocabulary, saved conversations. A
   report holds only measurements and what the tester typed into the rating card.
3. **The 2-second card.** After a conversation, at most once per conversation and never mid-conversation:
   *"How well could you follow the conversation?"* with 1 to 10 in one row, an optional *Add a note*, and *Skip*.
   A skip is recorded as a skip.
   **When it appears** (owner, 2026-10-09): it depends on how the conversation paused. If she paused it herself
   (Stop/X), she may want to come back to it, so the card waits until she taps [ New ]. If it paused without her
   (quiet stop, or the app was closed or left mid-conversation), the card shows when she taps [ New ] or when she
   comes back to it. No accuracy question; testers don't get a separate screen of their own measurements (the
   send preview is enough).
4. **Measured per conversation, on the device:**
   - caption lag (p50 and p95, from the engine's existing `lagSeconds`)
   - how often a caption is rewritten before it's final (an accuracy proxy)
   - speaker relabels per minute, and the number of speakers detected
   - how it ended (her Stop, quiet stop, failure with its plain reason, or stuck)
   - time from launch to Start, and from Start to the first caption
   - session length
   - battery drop scaled to 30 minutes, and the highest thermal state
   - device model, iOS version, app build, theme, lettering, text size, and a mic-level summary

   This reuses what already exists: `TranscriptionEngine`'s startup laps, `WordLagTracker`,
   `ListeningActivityTracker`, `IdleStop` and `FailureReason`.
5. **Delivery by text.** Settings gets a beta-only *Send feedback to Gil* row.
   - It shows a plain preview of exactly what will be sent.
   - It then opens Apple's Messages compose sheet (`MFMessageComposeViewController`), addressed to the owner, with
     the report attached as `seal-feedback-<build>-<date>.json` and a short readable summary in the message body.
   - If Messages can't send (an iPad without Messages, for example), the share sheet opens instead.
   - Nothing leaves the phone unless the tester taps Send in Messages.
6. **The owner's number isn't in the public repo.** It's injected at build time from a gitignored
   `Apps/Spike/Beta.xcconfig.local` (`SEAL_FEEDBACK_RECIPIENT = +1…`) into an Info.plist key. Without it, the
   row falls back to the share sheet.
7. **Retention:** records stay on the phone until they're sent, with no limit (owner, 2026-10-09; about 1 KB per
   conversation). After Messages reports the text was sent, the sent records are deleted. If it's cancelled, they
   stay.
8. **What testers are told:**
   - A one-time notice on the first beta launch: *"This test version asks how each conversation went and keeps
     measurements like lag and battery. It never keeps what anyone said. You choose when to send them to Gil."*
   - The same, in TestFlight's *What to Test* text.

## Consequences

- **The App Store build's privacy label stays "Data Not Collected", and the privacy policy stays true.** In App
  Store installs the code paths are off and record nothing. TestFlight builds aren't covered by the App Store
  privacy label; testers are told plainly instead.
- Reports arrive as attachments in the owner's Messages. On his Mac they land under
  `~/Library/Messages/Attachments/`. MARVIN can ingest them from there, which needs Full Disk Access for the
  ingesting process (macOS privacy protection). See `docs/beta/metrics-schema.md`.
- Accuracy is a proxy plus the tester's own judgement, never a comparison against what was really said. That's
  the price of never collecting the words.
- Testers on one build can't receive a fix without a new TestFlight build. Each report carries the build number,
  so feedback is tied to the build that produced it.
