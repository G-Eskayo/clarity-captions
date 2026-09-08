# App Store review due diligence (2026-09-08)

Concrete findings on what Apple will/won't allow, gathered before build so requirements are
designed in from the start rather than discovered at rejection time. Overall context: Apple
reviewed ~7.77M submissions in 2026 and rejected ~25% — a real base rate, not a paranoid worry.

## What actually causes rejections, ranked

1. **Guideline 2.1 (App Completeness/Performance)** — crashes, bugs, excessive battery drain,
   device overheating, excessive CPU/memory use. **This is the single largest rejection category,
   larger than every other category combined.** Directly means: the battery/thermal budget and
   crash-free stability the independent design review already flagged as unscoped (continuous
   mic capture + two on-device ML pipelines for hours) are now an App Store compliance
   requirement, not just a UX nice-to-have. Needs real measurement before submission, not after.
2. **Guideline 5.1.1 (Privacy/Legal)** — missing or inaccurate privacy policy, a broken support
   URL, or an App Privacy "nutrition label" that contradicts actual behavior. Concrete
   requirements for this app:
   - A real, hosted privacy policy, linked both in App Store Connect and inside the app itself.
     For this app the actual content is simple and genuinely favorable (collects nothing, sends
     nothing anywhere, ever) — but it must exist as an actual document, not be assumed obvious.
   - The App Privacy questionnaire in App Store Connect must accurately declare "no data
     collected" across every category — filled in deliberately, not left at defaults.
   - A working support URL/contact method.
3. **Metadata/description accuracy** — screenshots and description must match real app behavior;
   new-version release notes need actual specifics, not generic text.
4. **Guideline 4.2/4.3 (Minimum functionality/spam)** — unlikely to be a real risk here given
   substantial native functionality, but worth confirming the app doesn't read as "just a thin
   wrapper around a system feature" given iOS's own built-in Live Captions exists — precedented
   fine (Ava, Live Transcribe, and others already ship independently on the App Store), not a
   blocker, just worth being ready to articulate what this app adds beyond the OS feature if asked.

## Microphone permission specifics

- `NSMicrophoneUsageDescription` must explain the *specific* reason in plain language, in this
  app's own context — not generic boilerplate. Apple audits whether the permission requested is
  proportional to what the app visibly does. For this app that's straightforward (captioning
  requires the mic, and the request should happen contextually — when the user starts a
  captioning session, not blind at first launch).

## Health/medical claims — real risk to avoid, not a blocker

Apple restricts apps that claim to diagnose, treat, or measure physiological data (explicitly
named: blood pressure, blood oxygen, glucose, temperature via sensors alone) and applies stricter
review to anything used "like a medical device." **This app is not doing any of that** — it's a
communication/accessibility aid, not a diagnostic or treatment tool, and existing precedent
(Ava, Live Transcribe, etc.) confirms this category is fine on the App Store.

The actual risk is in **marketing language, not functionality**: avoid phrasing that implies a
medical/health claim ("helps with hearing loss," "treats," "improves hearing") in the app
description, screenshots, or in-app copy. Frame it as what it is — real-time captioning for
conversation accessibility — not as anything health-outcome-related. When App Store Connect asks
whether the app is a regulated medical device, the honest answer is no.

## AI/external-service disclosure — exempt, and worth stating why

Apps using external AI services must show a consent modal naming the provider and what data is
shared before any personal data leaves the device. **This app is exempt by design**: every ML
component (`SpeechAnalyzer`, FluidAudio) runs on-device, per [[0001]] and [[0008]] — nothing is
sent to any external AI service, so there's no consent modal to build. Worth stating this
explicitly in the App Store Connect review notes so the reviewer doesn't have to infer it.

## Accessibility is an explicit review factor, not just good practice

Apple's review explicitly checks: text readability, color contrast, Dynamic Type support (text
scales with the system text-size setting), and Dark Mode support. This directly upgrades the
independent design review's finding about the app's *own* UI accessibility (as opposed to caption
display customization, which was already planned) from "nice to have" to **App Store compliance
requirement**: onboarding/settings screens need Dynamic Type and real contrast, not just the
caption text itself.

## What this changes about scope

Two things move from "should probably do" to "must do before submission, or risk rejection":
- Measured battery/thermal behavior under real, sustained use (Guideline 2.1's biggest category).
- Dynamic Type and contrast support across the app's own UI, not just caption display settings.

Both were already flagged by the independent design review on UX grounds — this confirms they're
also hard App Store gates, which changes their priority from "important" to "blocking."
