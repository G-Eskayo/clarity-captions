## North-star fit

**Reuses:** three existing patterns, no new structure:
- ADR shape — `Status / Context / Decision / Consequences` with dated amendments, as in `docs/adr/0011-working-name-vs-store-name.md` and `docs/adr/0017-speaker-model-comparison-deferred.md`.
- CONTEXT.md glossary bullet pattern — bold term, one-line domain definition, `See [[NNNN]].` — every existing entry in CONTEXT.md follows this; no new section mechanics needed, just one more bullet.
- `docs/app-store-listing.md`'s own **"Holds" list** ("decided in ADRs but not in the code") — already the repo's established place for a decided-but-unbuilt feature (background captioning, idle-stop, etc.). The $2 translation IAP is exactly that shape, so it reuses item slot 6 rather than inventing a second mechanism.

**Simplest sufficient approach:** one new short ADR + one CONTEXT.md bullet + two one-line edits to ADR 0007/0010 (the only two files with a live "free" claim) + one Holds-list line. No code, no Xcode/Swift touched, no new doc files beyond the ADR.

**Cost:** cheap — ~5 small text edits, no build/test cycle needed beyond a sanity `swift test` run (doc-only diff can't break it, but I'll run it once per the profile's own gate).

**Capability:** doesn't change what the user (app or Gil) can do — it fixes an AI-memory/documentation defect (a prior session recalled "free forever" and acted on it) so future sessions reason from the real decision instead of re-deriving or misremembering it. Pure Watts-check housekeeping: output future sessions will actually consume.

**North-star tension worth flagging, not working around:** `docs/app-store-listing.md`, `site/index.html`, `site/support.html` and `site/versions.html` all currently state **$4.99**, not $5 — and the issue's own "What" section asserts app-store-listing.md "doesn't mention a price" when it actually does (just not $5, and not the IAP). I'm not silently resolving that contradiction — see Decisions below.

## Tests / verification (no app code touched — no XCTest applies)

This is a documentation-only ticket; there is no "How we'll try to break it" or Attacks section in the issue, and no CaptionCore/Spike-app files are touched, so `swift test` behavior is unaffected and untested by anything new. The equivalent of "tests first" for a doc change:

1. Re-run `grep -rni 'free' docs site` after edits and confirm every surviving hit is either: (a) unrelated (font license text, "crash-free", "data-free" model-compression terms, "near-free" meaning low-effort) or (b) a pricing claim that is now correctly historical/superseded (ADR 0007's kept history, explicitly marked "Superseded").
2. Confirm no duplicate ADR number (0026 is free — checked, highest existing is 0025) and no duplicate CONTEXT.md glossary term.
3. Confirm ADR 0010's "free forever" line and ADR 0007's status line are the only two *live* (non-historical) "free" claims in the repo before vs. after (misuse case: editing the wrong occurrence, or missing one of the two, would leave a stale claim — the grep re-run in step 1 is what catches that).
4. Sanity check: `swift test --package-path Packages/CaptionCore` still green (confirms the doc-only diff didn't accidentally touch anything under `Packages/`).
5. Misuse case not explicit in the issue but worth covering: if Decision `price` below resolves to **B ($5.00)**, the ADR and the live listing/site would then disagree on the literal number — handled by *not* silently editing the listing/site price (out of this ticket's acceptance criteria) and instead recording the gap explicitly in the ADR's Consequences plus a Holds-list line, so no doc contradicts another doc without a stated reason.

## Decisions

<!-- marvin:decisions -->
### price: Is the canonical one-time price $4.99 or $5.00?
- [ ] A: $4.99 — matches the current live App Store Connect price, `docs/app-store-listing.md`, and all three site pages; "$5" in the issue and in `~/.claude/marvin-roadmap.md` is casual rounding in conversation, not a new decision
- [ ] B: $5.00 — the real target price; the current $4.99 in the listing and site is now stale and needs a follow-up ticket to raise the live App Store Connect price and reword the listing/site

## Task List

1. Create `docs/adr/0026-pricing-one-time-purchase-and-live-translation-iap.md`: short ADR (Status/Context/Decision/Consequences) stating the one-time price (per the `price` decision above), the $2 live-translation IAP (same price on iPhone and iPad, implementation differs by platform per ADR 0010's shared-core/thin-target architecture — no new implementation detail invented), and explicitly superseding ADR 0007's original free/non-commercial decision and ADR 0010's "free forever" constraint.
2. Add a CONTEXT.md glossary bullet **Live translation (IAP)** — domain definition only (a $2 in-app purchase for translated captions, same price on iPhone and iPad), linking `[[0026]]`. Placed as a new short section (or appended near "Product principles"/before "People") to minimize structural disruption.
3. Edit `docs/adr/0010-multi-platform-apple-expansion.md` line 18: replace "free forever ([[0007]])" with wording that the same pricing (not "free") applies to every platform, pointing at `[[0026]]`.
4. Edit `docs/adr/0007-free-and-non-commercial-by-design.md`'s Status line: add a forward pointer ("Further superseded 2026-10-26: see [[0026]] for the $5/$2 IAP pricing decision") without rewriting its kept history.
5. Add item 6 to `docs/app-store-listing.md`'s "Holds" list for the live-translation IAP (decided in `[[0026]]`, not yet built) — reusing the existing Holds pattern instead of editing the live Price field. If decision `price` = B, also note in ADR 0026's Consequences that the listing/site still say $4.99 pending a separate listing-update ticket.
6. Re-run `grep -rni 'free' docs site` and paste the reviewed hit list (fixed vs. unrelated) into the PR description per the acceptance criterion's exact wording.
7. Run `swift test --package-path Packages/CaptionCore` once as a sanity check (no code changed, expect unchanged green).