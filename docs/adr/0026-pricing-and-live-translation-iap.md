# 0026 — Pricing and live translation IAP

## Status

Accepted (2026-10-26).

## Context

[[0007]] documents the owner's initial decision that the app would be free, motivated by the
principle that assistive technology for people with hearing loss should not be a monetization
opportunity. On 2026-10-10, the owner chose to sell v1 for a one-time $4.99 instead (enrolled in
Apple's Small Business Program). This caused a "free forever" claim in [[0010]] to become stale —
the line states a constraint that is no longer accurate.

During development, the team identified live translation as a natural next feature: showing the
user a translation of what's being said (in their language) alongside or instead of English
captions. This is not yet shipped; it is planned as a paid in-app purchase (IAP).

## Decision

1. **App purchase price stays at $4.99 one-time, unchanged from the 2026-10-10 choice.** The owner
   has confirmed this remains his intended pricing for v1.
2. **Live translation will be a $2 IAP, same on iPhone and iPad.** The feature is not yet shipped.
   Implementation differs by platform (iPad may render translations differently; iPhone renders inline),
   but the IAP itself carries one price across all Apple platforms.
3. **This decision supersedes the "free forever" framing** in [[0007]] and [[0010]] going forward.
   Wherever those documents assert a constraint on pricing or free-ness, this decision is the current
   authority.

## Consequences

- [[0010]] now needs a corrected constraint statement: not "free forever" but the actual $4.99 model
  and $2 IAP plan.
- The app's App Store listing, privacy page, and any marketing copy must reflect $4.99 + optional
  $2 IAP, not "free".
- [[0007]]'s original reasoning is preserved as history (the "free by design" motivation and when
  it changed), but [[0026]] is the current pricing decision.
- Live translation is not committed to any shipment date; it is a future feature decision. When it ships
  (if ever), it will be governed by this ADR's pricing, not a separate monetization decision.
