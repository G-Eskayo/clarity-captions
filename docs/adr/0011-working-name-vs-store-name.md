# 0011 — Working name is separate from the store name; keep identifiers neutral

## Status

Accepted (2026-10-02). Amended 2026-10-05: the store name is chosen, see "Chosen name" below.
Amended 2026-10-06: the bundle ID is chosen, see "Bundle ID" below.

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

## Chosen name (2026-10-05)

The project owner chose **Seal** as the store name; his partner likes and supports it. It began as
the nickname, a spin on Otter, the tool that inspired the app.

- A search of the US App Store on 2026-10-05 found no app named exactly "Seal" in the top 25 results
  (near misses: "Seal - Instant Video Repost", "Seal Island"). That is a hint, not a guarantee:
  the real availability check is reserving the name in App Store Connect, which needs the paid
  membership. Trademark and domain checks are still to do.
- **Discoverability:** "Seal" says nothing about captions, so the subtitle and keywords must carry
  that ("Live captions" style wording; no health or medical claims, see
  `docs/app-store-compliance.md`). Wording is decided when the store listing is written.
- **Fallback if the name is taken:** "Clarity Captions" was checked the same way and found free.
- **Bundle ID:** decided 2026-10-06, see below.
- Avoid names derived from "Otter", which is a competitor's trademark.

## Bundle ID (2026-10-06)

The owner chose **`com.gileskayo.captions`**.

- Neutral, not derived from "Seal", so the fallback name (or any later rename) still fits it.
- Permanent from the moment the App Store Connect record is created (#14); never change it after that.
- The app target moves to it now, replacing the spike-era `com.gileskayo.captionspike`. A phone
  that has the old build installed sees the new one as a separate app; delete the old one.
- Only this app is affected. Other apps share the `com.gileskayo.` prefix by convention and pick
  their own suffix.
- **Universal purchase: yes**, confirming ADR 0010's preference. iPad and Mac versions, when they
  come, join this same App Store record and bundle ID instead of becoming separate apps.
