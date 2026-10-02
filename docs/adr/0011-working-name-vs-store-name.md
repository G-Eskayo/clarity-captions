# 0011 — Working name is separate from the store name; keep identifiers neutral

## Status

Accepted (2026-10-02).

## Context

The project is called "Clarity Captions" in the repo, and informally "Seal" (a spin on Otter, its
inspiration). Neither is committed as the App Store name. The owner stated the colloquial name
and the released name do not have to match, but the team must stay aware of the gap.

Some identifiers are effectively permanent once created: the bundle ID is fixed at App Store
Connect record creation, and the app record's name is globally unique on the Store. Changing the
display name later is easy; changing the bundle ID is not.

## Decision

1. **Store name is undecided and deliberately deferred**, but must be chosen before the first
   App Store Connect record or TestFlight upload, which is the point of no return for the bundle
   ID. Target: decided by the end of the iPhone spike, not at submission time.
2. **Until then, keep the name out of code.** The Xcode project, targets, and Swift package use
   a neutral internal name, and the user-visible name comes from a single setting, so a rename is
   a one-line change.
3. **Name availability is checked before commitment** (App Store search, trademark search,
   domain). "Seal" in particular is a crowded word and must be checked, not assumed free.
4. **Docs use the terms deliberately**: "Clarity Captions" = current working title,
   "Seal" = nickname, "store name" = whatever ships.
