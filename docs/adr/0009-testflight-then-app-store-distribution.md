# 0009 — TestFlight first, public App Store as the follow-on goal

## Status

Accepted (2026-09-08). Revises [[0001]]'s distribution decision.

## Context

[[0001]] chose personal install via the paid Apple Developer Program specifically to *avoid*
App Store review risk against the 2026-10-25 deadline. Two things have changed since:

1. The project owner now explicitly wants a real public App Store release, not just a personal
   install — this was never actually in tension with [[0007]]'s "free and non-commercial" or
   [[0008]]'s "generalized, no per-user training" decisions; it's a natural extension of both.
2. He wants to test the app himself before anyone else does, and bring the intended recipient in
   as a real tester in October — this is no longer a surprise-gift constraint, which removes the
   biggest objection the earlier review raised against personal-install-only distribution (no
   pre-release feedback loop).
3. The review separately flagged that personal-install builds expire (~1 year, tied to a
   registered device) with no update mechanism after handover — a real risk for a daily-use tool
   nobody else can push a fix to.

Apple's actual review mechanics (checked 2026-09-08): a new app's first public App Store
submission typically takes 2-5 days from submission to decision, with rejection/resubmission
cycles being the real timeline risk (each one can add days to weeks) — not the review itself.
TestFlight has two tiers: **internal testing** (people added to your App Store Connect team, up
to 100 testers) needs no review at all; **external testing** (a shareable link, up to 10,000
testers) needs one light "beta app review," typically 24-48 hours the first time, usually not
repeated for minor updates.

## Decision

**Distribution happens in two stages, not one:**

1. **TestFlight** — internal testing for the project owner's own pre-release testing (no review
   wait), then external TestFlight (one ~24-48h beta review) so the intended recipient can test in
   October without needing to be added as an App Store Connect team member. This is also the
   2026-10-25 milestone: a working, installable, updatable build via TestFlight, not necessarily
   a live public App Store listing by that exact date.
2. **Public App Store submission** follows once both the owner's own testing and her October
   testing have gone well — treated as the next milestone after the birthday, not a hard
   requirement to hit by it.

This directly resolves the "how do I ship a fix in November" gap the earlier review raised:
TestFlight builds can be updated over-the-air without physical device access, unlike a personal
Xcode install.

## Consequences

- Requires the Apple Developer Program enrollment ([[0001]]) regardless — TestFlight and the App
  Store both require it. Still the hard blocker on the critical path if not yet complete.
- App Store Connect setup (privacy nutrition label, screenshots, app description, accessibility
  metadata) becomes real work that needs to happen before either TestFlight external testing or
  App Store submission — not previously scoped under the personal-install-only plan.
- Realistic timeline risk is concentrated in the *full public* App Store submission, not
  TestFlight — a rejection there (e.g. over privacy label accuracy, accessibility claims, or
  metadata issues) could add real time, but by the time that submission happens, the app will
  already be working and updatable for the intended recipient via TestFlight, so a review delay
  no longer risks the birthday deadline itself.
- Accessibility/health-adjacent category scrutiny ([[0001]]'s original App Store concern) still
  applies to the eventual public submission — worth preparing accessibility-specific metadata and
  privacy documentation (this app's zero-server, zero-data-collection design, per [[0001]] and
  CONTEXT.md, is a genuine strength here, not a liability, if documented clearly).
