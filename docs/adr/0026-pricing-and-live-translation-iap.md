# 0026 — Pricing model and live-translation in-app purchase

## Status

Accepted (2026-10-25). Supersedes [[0007]]'s "free forever" framing. Decision unresolved on
per-platform IAP implementation details — deferred to a future ADR when live translation is built.

## Context

The owner decided (2026-10-25) to monetize the app as follows:

1. **Base app**: one-time $5 USD purchase (no subscription, no ads, no free tier).
2. **Live translation feature**: $2 USD in-app purchase on iPhone and iPad, same price both, exact
   per-device implementation mechanism deferred.

This model replaces the historical [[0007]] "free forever" decision (which already noted a 2026-10-10
update to $4.99). Live translation itself is not yet built; this ADR only commits the pricing for when
it is ready.

The $4.99 vs. $5 discrepancy (v1 ships at $4.99; new pricing guidance is $5) is noted here and left
unresolved — either the v1 price stays at $4.99, or it is raised to $5 during or after TestFlight, or
the live-translation IAP is $2.50 to match $5 equivalence. These are pricing/business decisions, not
product architecture decisions, and are left to the owner.

## Decision

1. **Base app pricing**: one-time purchase in USD. Regional pricing via App Store can be set by the
   owner.
2. **Live translation IAP**: $2 USD, available on iPhone and iPad after the feature is built. Whether
   the implementation differs by device (e.g., server-backed translation on iPad, device-local on iPhone,
   or vice versa) is deferred.
3. **No other monetization**: no ads, no subscriptions, no account paywall, no free trial of paid
   features. The free/commercial distinction from [[0007]] no longer applies; this app is paid and
   commercial.
4. **Code changes**: the app's logic and architecture are unchanged by pricing. Pricing is a
   StoreKit/Business decision, not a product or architecture decision. Implement live translation
   first; wire pricing/SKU setup when the feature exists.

## Consequences

- [[0007]]'s reasoning ("free for everyone in similar circumstances") is revisited and departed from.
  The owner's stated reason: the app works and the owner is willing to maintain it; if people find
  value in it, a one-time purchase is fair. This is distinct from [[0007]]'s accessibility-software
  framing and restarts the pricing conversation cleanly.
- Revenue from base app sales and translation IAP can fund ongoing maintenance, beta testing, and
  future platforms (Mac, iPad, Vision Pro). No revenue target is set; the owner treats sales as
  "maybe it helps offset costs".
- Distribution stays on the App Store first (no sideload or free distribution yet, given the paid
  model). If future versions are free, or if a free tier is added, those are new decisions.
- TestFlight beta remains free; App Store tester installs use promo codes.
- The base-app price ($5 vs. $4.99) and the translation IAP price ($2) have no relationship to
  development costs; they are psychological/market prices the owner chose.
