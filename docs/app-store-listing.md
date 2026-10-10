# App Store listing, privacy answers and review notes (#69)

Paste-ready text for App Store Connect, plus the exact answer to each questionnaire. Nothing here
has been submitted. The owner reviews the wording first (acceptance criterion of #69).

Lengths were counted by script on 2026-10-09. Re-count after any edit: Apple rejects the field,
not the submission, but a truncated subtitle reads badly.

Ranked review risks with evidence: docs/app-review-risks.md.

Rules this text follows (docs/app-store-compliance.md, App Review Guidelines 1.4.1 and 2.3):

- No medical or health claims: nothing about treating, improving or helping hearing or hearing loss.
  Deaf and hard-of-hearing people are named as the audience, not as a condition the app acts on.
- No promise of accuracy. The description says captions can contain mistakes.
- No prices, "free" or other apps' names in the name, subtitle, keywords or screenshots (2.3.7).
- Only what the shipped build does. Background captioning, the hearing-aid/streamer behaviour and
  other languages are **left out** until they are built (see "Holds" at the end).

## Product page

| Field | Limit | Text | Length |
|---|---|---|---|
| Name | 30 | Seal | 4 |
| Subtitle | 30 | Captions for conversations | 26 |
| Promotional text | 170 | Follow the conversation at the table. Seal captions what people nearby say, starts a new line when the voice changes, and works with no internet. No ads, no account. | 165 |
| Keywords | 100 | `deaf,hard of hearing,subtitles,speech to text,transcribe,transcript,offline,accessibility,talk,live` | 99 |
| Primary category | | Utilities | |
| Secondary category | | Productivity | |
| Support URL | | `<host>/support.html` (site/support.html, PR #77) | |
| Privacy policy URL | | `<host>/privacy.html` (site/privacy.html, PR #77) | |
| Marketing URL | | Optional, leave empty until #44 | |
| Copyright | | 2026 Gil Brandon Eskayo | |

The store name is "Seal" (owner, 2026-10-09). Store names must be unique: if App Store Connect
refuses it when the record is created, fall back to a longer form such as "Seal Captions". "Live
Captions" is avoided because it is also the name of an Apple feature (Guideline 5.2.5).
Keywords skip words already in the name and subtitle (Apple indexes those),
so "captions" and "conversation" are not repeated.

### Description (limit 4,000)

```text
Seal shows what people around you are saying, as they say it, in large clear text.

Put your iPhone on the table, tap Start, and follow the conversation. When the voice changes, Seal starts a new line and labels it Speaker 1, Speaker 2. It goes by the sound of the voice, so it can mix people up.

MADE TO BE EASY
• One big button to start and stop
• Large text that follows your device's text size, with A− and A+ to go bigger or smaller
• Choose the text and background colours that are easiest for you to read
• Captions scroll on their own; scroll back to reread and tap to jump to the newest line
• Sounds like laughter, applause or a doorbell appear as short labels

PRIVATE BY DESIGN
• Captions are made on your device. Audio is never recorded or sent anywhere.
• Works with no internet connection after a one-time setup.
• No account, no ads, no tracking.
• Tap [ Save ] to keep a conversation on your phone for 30 days. Delete any of them sooner whenever you like.

MORE
• Highlight any words to copy them
• Works on iPhone and iPad

Seal is built for deaf and hard-of-hearing people, and for anyone who wants to read a conversation instead of only hearing it. Captions are made by a computer and can contain mistakes. Seal is not a medical device.

Captions are in English for now.
```

Notes for the owner:

- v1 is iPhone and iPad only (owner, 2026-10-09); the Mac target ships later.
- "Works with no internet connection after a one-time setup" matches CONTEXT.md's precise wording
  (Apple's language files may download once).

## App Privacy (the "nutrition label")

App Store Connect → App Privacy → Get Started.

| Question | Answer | Why |
|---|---|---|
| Do you or your third-party partners collect data from this app? | **No, we do not collect data from this app** | Apple counts data as "collected" only when it is sent off the device. Audio, transcripts, speaker names, vocabulary and settings never leave the device (ADR 0008, 0014, 0022). FluidAudio runs on the device with bundled models and makes no network calls (ADR 0014). |
| Result shown on the store | **Data Not Collected** | |
| Privacy policy URL | `<host>/privacy.html` | Must also be reachable inside the app (see checklist item P3). |

Copy/Share is user-initiated, goes to an app the user picks, and Apple's definitions exclude
data the user chooses to send elsewhere, so it does not change the answer.

## Age rating

App Store Connect's questionnaire (updated 2025: 4+, 9+, 13+, 16+, 18+). Answer **None / No** to
every content question:

- Violence, sexual content, profanity, horror, drugs, alcohol, gambling, contests: **None**
- Medical or treatment information: **None** (the app gives none)
- User-generated content shared with other users / messaging or chat: **No** (transcripts stay on
  the device; Share hands text to another app)
- Unrestricted web access: **No**
- Advertising: **No**
- In-app controls (parental controls, age assurance): **No**

Expected result: **4+**.

## Other App Store Connect questions

| Question | Answer |
|---|---|
| Export compliance: does the app use encryption? | **No** beyond what iOS itself provides. The app makes no network calls. Add `ITSAppUsesNonExemptEncryption = NO` to the app's Info.plist so TestFlight stops asking on every upload. |
| Content rights: does the app contain third-party content? | **Yes, and it has the rights to use it:** bundled Sortformer model (CC BY 4.0) and FluidAudio (Apache 2.0), credited in-app and in NOTICE.md (#21). |
| Is this app a regulated medical device? (if asked) | **No.** |
| Price | Free (tier 0); no in-app purchases |
| Availability | All countries where English captions are useful; owner's call. EU needs the trader-status answer (open question below). |
| Sign-in required? | **No** |

## Review notes

Paste into App Review Information → Notes. Plain, short and specific: reviewers read many apps a day.

```text
Seal shows live captions of nearby conversation for deaf and hard-of-hearing people. Everything runs on the device: Apple's SpeechAnalyzer turns speech into text, and a bundled Core ML model (FluidAudio, Sortformer) labels changes of speaker (Speaker 1, Speaker 2); it doesn't identify anyone. No account, no network service, no analytics, no ads, no in-app purchases. Seal does not use any external AI service, so no AI data-sharing consent is needed.

HOW TO TRY IT (about 1 minute)
1. Open Seal. The first screen explains what it does; tap through it and allow the Microphone.
2. The first launch may download Apple's English speech files (a few seconds on Wi-Fi). After that the app works in airplane mode.
3. Tap Start and talk, or play a podcast or video near the device. Captions appear as people talk. When a second voice speaks, a new "Speaker 2" line starts.
4. Tap ✕ to pause, then [ Save ] keeps it on the device for 30 days (Settings → Saved conversations), where it can be deleted.

PERMISSIONS
• Microphone: needed to caption what people nearby are saying. Used only while captioning is running; audio is never recorded or stored.

No demo account is needed.
```

If the background-captioning build ships (see Holds), add this paragraph and attach a screen
recording that shows it working, because background audio is checked against Guideline 2.5.4:

```text
BACKGROUND AUDIO
Seal declares the "audio" background mode so captioning continues when the screen locks or the user switches apps; a deaf user loses the conversation otherwise. The system microphone indicator stays on the whole time, captioning stops on its own after a quiet stretch (default 5 minutes, adjustable), and nothing is played or recorded. To check: start captioning, lock the device, speak for 20 seconds, unlock: the words spoken while locked are in the transcript after a "while you were away" marker.
```

## Compliance checklist walk-through

Items from docs/app-store-compliance.md, each marked **Done**, **N/A** (with reason) or **Open**.
"Open" items are what stands between today and a clean submission.

| # | Item | Status | Evidence / next step |
|---|---|---|---|
| C1 | 2.1 crash-free on a real device, including iPad if the build is universal | **Open** | Reviewers test universal apps on iPad. iPad layout shipped in #40 on 2026-10-09 and needs a real-iPad pass before submission. |
| C2 | 2.1 battery and thermal over a sustained session | **Open** | #12 (30-minute check). |
| C3 | Accessibility of the app's own UI (Dynamic Type, contrast, Dark Mode, VoiceOver) | **Done** | #13 closed 2026-10-05; docs/accessibility-audit.md. Re-check the iPad layout. |
| C4 | Microphone purpose string is specific | **Done** | "Captions need the microphone to show what people nearby are saying." (Apps/Spike/project.yml). |
| C5 | Mic requested in context, not cold at launch | **Done** | First run explains, then asks (#11). |
| P1 | Hosted privacy policy | **Open** | Written (PR #77); needs the contact email and hosting. |
| P2 | Working support URL | **Open** | Same as P1. |
| P3 | Privacy policy reachable inside the app | **Open** | Not in the app yet. Add a "Privacy policy" link in Settings / About & Credits (Guideline 5.1.1(i)). Small ticket. |
| P4 | Privacy label answered deliberately, not left at defaults | **Done (text)** | Answers above; enter them in App Store Connect once the record exists (#14). |
| P5 | Privacy manifest (`PrivacyInfo.xcprivacy`) for required-reason APIs | **Open** | The app has none. It uses UserDefaults/`@AppStorage` (required-reason API, reason `CA92.1`) and file timestamps for the 30-day expiry (likely `C617.1`). Missing manifests trigger ITMS-91053 on upload. Also check whether FluidAudio ships its own. |
| P6 | External AI consent modal | **N/A** | All ML runs on the device; stated in the review notes. |
| M1 | No health or medical claims in copy | **Done** | Checked against 1.4.1: no "treat/improve/help hearing" wording anywhere above; "not a medical device" stated. Re-check screenshots (#47) the same way. |
| M2 | Screenshots and description match the build | **Open** | #47. Use DemoMode `-ClarityDemoStatic` for repeatable screenshots; it is debug-only so it never ships. Screenshots must not show features that are on hold. |
| M3 | Explain what Seal adds over iOS Live Captions (4.2) | **Done** | Description covers speaker labels, saved conversations, vocabulary, colours, sound labels. Reply ready if asked. |
| E1 | Export compliance key | **Open** | Add `ITSAppUsesNonExemptEncryption = NO`. |
| E2 | Third-party credits | **Done** | #21. #32 (unused FluidAudio parts) is still open but is not a review blocker. |

## Holds: things to keep out of this submission unless they ship first

These are decided in ADRs but **not in the code as of 2026-10-09**, so the listing, screenshots and
review notes don't mention them:

1. **Background captioning** (ADR 0020): no `UIBackgroundModes` audio in the app. Part of #10.
2. **Screen stays awake + idle stop setting** (ADR 0019): no `isIdleTimerDisabled` and no idle-stop
   setting in the code, and no open ticket for it. Without it, the screen auto-locks mid-conversation.
3. **Always the built-in mic / route changes / calls** (ADR 0021): no `setPreferredInput` or
   interruption handling. Part of #10.
4. **Faded background speech** (#6): still open, so the description doesn't mention it.
5. **Other languages** (#37): the engine is fixed to en-US.

## Owner decisions (2026-10-09)

1. Contact email (support page, privacy page, App Review contact): gil.eskayo@icloud.com.
2. Copyright / legal name: Gil Brandon Eskayo.
3. v1 is iPhone and iPad only; the Mac app comes later.
4. v1 keeps the screen awake while captioning (#83) instead of background captioning (ADR 0020 deferred),
   so the background-audio review paragraph above is not used.
5. Store name: Seal.
6. Still open: EU trader status under the Digital Services Act, answered in App Store Connect.
