# V2 and growth: platforms, languages, landing page

Status: **thinking, not decisions** (2026-10-05). Facts marked verified were checked against the iOS 27 SDK or
the cited sources; the rest are judgments or things still to confirm.

## Other devices

| Platform | Can it run the same engine? | Realistic role |
|---|---|---|
| **iPad** | Yes, same SDK (verified: the engine and diarizer already build for iOS) | Near-free: adaptive layout of the phone app |
| **Mac** | Yes. Verified: the shared package builds and its tests run on macOS 27, and the speaker diarizer ran there | A native Mac app: a floating caption window for conversations and meetings. Capturing audio *from the computer* (calls, video) needs ScreenCaptureKit and extra permissions |
| **Apple Watch** | **No.** Verified: Apple marks `SpeechTranscriber` unavailable on watchOS and the watchOS SDK ships no Speech interface for it. FluidAudio's diarizer is not targeted at watchOS either | A **companion display**: the phone does the work and the watch shows the latest line and taps the wrist. A watch-as-remote-microphone is conceivable but hard |
| **Vision Pro** | Likely (visionOS has Speech); unverified here | Captions placed in view; later |
| **Apple TV** | No microphone | Out of scope unless it only displays captions from another device |
| **Android / Google Play** | Not the same code. Needs a native Kotlin app and a different engine. [sherpa-onnx](https://k2-fsa.github.io/sherpa/onnx/index.html) offers fully offline streaming recognition and speaker diarization on Android | A second product, close to a rewrite of the engine layer; the design, copy and tests carry over |
| **Chrome extension** | Not the same code. Chrome 139 added on-device recognition through `processLocally` (needs a downloaded language pack); Whisper can also run in the browser | A separate JavaScript build, and no speaker labels without extra work |

**Competition to keep in mind:** Apple's own [Live Captions](https://support.apple.com/guide/iphone/get-live-captions-of-spoken-audio-iphe0990f7bb/ios)
already captions real-world conversations from the microphone, on-device, on iPhone 11 and later; Chrome has a
built-in Live Caption. Seal's case rests on what they lack: **speaker labels, a very simple one-tap screen,
strong customization, dimming rather than dropping background speech, and sound labels.** Worth confirming
Live Captions' current speaker handling before writing the store description.

**Suggested order:** iPad, then Mac, then a Watch companion. Android is a real second project; decide after the
iPhone app has users. A Chrome extension only if a web audience matters.

## Languages (verified on macOS 27's speech engine)

`SpeechTranscriber.supportedLocales` lists **45 locales**, roughly 25 languages:

- **English:** AU, CA, GB, IE, IN, NZ, SG, US, ZA
- **Spanish:** CL, ES, MX, US. **French:** BE, CA, CH, FR. **German:** AT, CH, DE. **Italian:** CH, IT. **Portuguese:** BR, PT
- **Japanese, Korean, Mandarin** (CN, TW), **Cantonese** (CN, HK)
- **Indian languages:** Hindi, Bengali, Gujarati, Kannada, Kashmiri, Maithili, Malayalam, Marathi, Nepali, Odia, Punjabi, Tamil, Telugu, Urdu, plus a multilingual entry

Caveats: the iPhone list may differ slightly (confirm on a device); each language downloads its own model; and the
speaker diarizer is mostly acoustic, so it should carry over, but that is unverified for non-English speech.

**Realistic plan:** English first (with dialect choice), then Spanish, French and German, each only after a native
speaker tests it. Each language needs: translated app text (Xcode String Catalogs), a translated store listing, a
first-run step that picks the language and downloads its model, and real testers.

**App Store:** App Store Connect lets each language have its own name, subtitle, description, keywords and
screenshots. The App Store shows the listing in the language of the user's device when a localization exists, and
falls back to the primary language otherwise. This is how the "description for the language of that region" works;
confirm the exact selection rules and the localization limit in App Store Connect once the account is active.

## Settings

"Change look" becomes **Settings** (gear icon): colors, size and lettering today; language, sound-label and
emphasis switches and credits later. One clearly labeled place fits ADR 0013. Do it after the open pull
requests settle, to avoid merge conflicts in `LookSheet.swift`.

## Landing page

- A static site (plain HTML and CSS, no framework) in its own repo. Preview it free on GitHub Pages now; point a
  domain at it later.
- Pages needed anyway: **a privacy policy URL and a support URL** (App Store Connect and TestFlight external testing
  ask for them), plus the pitch, screenshots, a short demo, and the on-device privacy promise.
- Hosting on HostGator is possible (upload by SFTP or cPanel's Git deploy); it needs the account details, which should
  never be pasted into chat. GitHub Pages with a custom domain is the simpler fallback and keeps HostGator for the
  portfolio.
- Link it from the portfolio (a project card) now; a subdomain of the portfolio's domain works until a dedicated
  domain exists.
- The name "Seal" and the icon are decided, so the site can start before the domain does.
