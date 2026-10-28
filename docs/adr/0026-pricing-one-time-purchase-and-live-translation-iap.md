# 0026 — One-time $5 purchase with $2 live-translation in-app purchase

## Status

Accepted (2026-10-26). Supersedes [[0007]]'s "no monetization" decision and [[0010]]'s "free forever" constraint. The app ships with a one-time $5 purchase price; live translation is a $2 in-app purchase available on both iPhone and iPad.

## Context

[[0007]] committed to free distribution at the app's inception. [[0010]] carried that forward as a constraint across all future platforms: "free forever". The project owner has since chosen to monetize the shipping v1: not as a subscription or a freemium model, but as a single one-time purchase, with an optional paid feature (live translation) as an in-app purchase.

The pricing reflects two things: recognition that the app "is perfect how it is" (owner's words, deciding that a tip jar / subscription overhead is not justified), and the choice to enroll in Apple's Small Business Program (15% commission instead of 30%) to support the project's visibility and credibility alongside the underlying code decision to keep it on-device, account-free, and ad-free.

## Decision

1. **v1 ships at $4.99 USD** (one-time purchase, no subscription). The price applies to all platforms where the app is distributed (currently iPhone and iPad; future platforms use the same price per [[0010]]'s shared-core architecture).

2. **Live translation is a $1.99 or $2.00 in-app purchase** (one-time, platform-agnostic pricing). When enabled, captions are translated to a second language in real time, shown alongside the original English. Both prices are equivalent USD values; Apple's currency conversion determines the exact amount in each region. Implementation differs between platforms per [[0010]]'s thin-target architecture (iOS/iPadOS frameworks differ), but the feature and pricing are identical.

3. **The app itself has no other monetization**: no ads, no subscriptions, no other in-app purchases, no paywalled features beyond live translation, no telemetry or data sale. This decision carries forward the spirit of [[0007]], just redirected toward a sustainable one-time model instead of free.

## Consequences

- The $4.99 price and live-translation IAP must be entered in App Store Connect before submission. The listing at `docs/app-store-listing.md` documents the current pre-submission state; once this ADR is merged, that file's Price field updates from the placeholder to the decision stated here.

- Future pricing changes (adjusting for inflation, regional variance, or product evolution) are owner decisions, made in the same deliberate way this one was, not quiet drifts. App Store Connect allows price changes at any time.

- The shared-core architecture ([[0010]]) means that once live-translation is built for iPhone, adapting it to iPad uses the same transcription/translation pipeline with different UI plumbing. The $2 price stays consistent across platforms despite implementation differences.

- [[0007]]'s original context (the decision not to monetize assistive technology for people who can't change their circumstances) remains a design principle: the core app (speaker turns, captions, saved conversations, all caption display settings) ships in the free part, never behind the IAP. Live translation is a convenience feature, not a feature gate.
