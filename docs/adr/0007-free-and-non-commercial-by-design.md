# 0007 — Free and non-commercial by design

## Status

Accepted (2026-09-08)

## Context

This app started as a birthday gift for Gil's deaf mother, but is explicitly meant to be usable
by anyone in a similar situation (stated directly by the project owner, 2026-09-08, resolved to
single-user-per-install architecture without hardcoded assumptions about who the user is — now
also reinforced by [[0008]]'s "generalized, no per-user training" requirement). That raises the
obvious next question: what happens when someone other than her wants to use it?

Stated reasoning (2026-09-08): if this app wouldn't be charged to his own mother — someone who
didn't choose her hearing loss and can't change it — charging it to someone else in the same
situation, solely because they aren't family, doesn't hold up. This is a deliberate rejection of
the common pattern where assistive technology for people who can't control or change their
circumstances becomes a monetization opportunity.

## Decision

**No monetization of any kind, now or planned**: no purchase price, no subscription, no in-app
purchase, no ads, no paywalled features, no account requirement used as a monetization gate. The
public repo and this app's own distribution are both expressions of this, not separate decisions.

Open question, not yet resolved: whether this extends to the *code license* — i.e. whether a
future fork by someone else should be legally barred from charging for it (a share-alike/
non-commercial license), or whether this project only commits to its own distribution being free,
leaving what others do with a fork as their own call (a permissive license like MIT/Apache-2.0).

## Consequences

- No revenue to fund ongoing development, hosting, or support — sustainable only because the
  architecture itself requires none of those things ([[0001]]: zero servers, on-device only).
  There is nothing to keep paying for after the app is built.
- Distribution stays constrained by whatever free/low-friction paths exist (personal install now
  per [[0001]]; if broader distribution is ever pursued, e.g. the App Store, it would be as a free
  app, not monetized).
- Future contributors or future versions of this decision-maker who might feel pressure to
  monetize (to fund a feature, cover App Store fees, etc.) should treat this ADR as the answer,
  not a question to reopen casually — reversing it needs the same kind of direct, deliberate
  conversation that created it, not a quiet feature-by-feature drift.
