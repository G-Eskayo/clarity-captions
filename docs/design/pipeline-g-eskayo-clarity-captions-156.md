## North-star fit

- **Reuses**: ADR 0007 (`docs/adr/0007-free-and-non-commercial-by-design.md`)'s existing `## 2026-10-10: paid at $4.99` supersession pattern (an ADR amended with a dated subsection, old reasoning kept as history) and the same cross-link style CONTEXT.md already uses (`[[0007]]`, `[[0008]]`) for glossary entries that point at the ADR deciding them. No new machinery — a new ADR file following the existing `NNNN-title.md` numbering, one new CONTEXT.md glossary bullet in the same list style as `**Sound label**`.
- **Simplest sufficient approach**: this is a pure documentation ticket — no Swift/package/app code is in scope (no UI, no IAP implementation), so the whole task is three small file edits plus a grep audit. Nothing to build, no `swift test` surface changes.
- **Token cost**: cheap — a handful of markdown edits and a `grep -rni` pass across `docs/`, `site/`, and the repo root; no code, no simulator build needed for this ticket (it touches zero Swift/UI paths, so the pipeline's screenshot/look-proof stage doesn't apply).
- **User benefit**: corrects a documented fact so future sessions (and Gil) stop re-deriving or mis-recalling the price — directly fixes the "free forever" recall error named in the ticket. Pure correctness, not automation of judgment, so it doesn't trade off user capability either way.

**Correction to the ticket's stated price:** the ticket's "What" and acceptance criteria say **"$5 one-time purchase"**, but the actual decided and already-shipped price, recorded in ADR 0007 and already live in `site/index.html`, `site/support.html`, `site/versions.html`, and `docs/app-store-listing.md`, is **$4.99**, not an even $5. I treat "$5" as Gil's casual rounding when writing the issue, not a new pricing decision — there is no ADR, roadmap note, or App Store Connect reference anywhere in the repo for an actual $5.00 price change. I'm not silently picking this; it's listed as a Decision below so Gil can confirm or correct it with one tap, since getting it wrong means shipping a second wrong price fact right after fixing the first one.

## Tests first (this ticket has no "How we'll try to break it" section — these are the doc-correctness checks that substitute for it on a docs-only ticket)

Since nothing here is executable Swift, "tests" are verification passes, each one a concrete, re-runnable check:

1. **Stale "free" claim sweep**: `grep -rni 'free' docs site` reviewed line-by-line (already run once during planning — see findings below) plus `README.md` at repo root, since it currently contains the exact kind of claim the ticket exists to eliminate. Every hit classified as *pricing claim → fixed* or *unrelated (license text, "free-form control", resource availability, hosting cost, etc.) → left alone*, with the reasoning for each borderline hit stated, not silently decided.
2. **New-ADR numbering collision check**: confirm `0026` is unused before creating the file (already checked: highest existing is `0025`).
3. **CONTEXT.md glossary — no implementation leak**: confirm the new **Live translation (IAP)** entry names no engine, no on-device/network detail, and no per-platform implementation detail (CONTEXT.md's own stated rule, line 3-4), matching how the ticket's own acceptance criterion phrases it ("with no implementation detail").
4. **Cross-link integrity**: every `[[NNNN]]` added (CONTEXT.md → new ADR, new ADR → ADR 0007/0010/0011) resolves to a real file in `docs/adr/`.
5. **"No free claims" does not become "no IAP claims is now false"**: verify that none of the currently-accurate "no in-app purchases" sentences in `docs/app-store-listing.md` / `site/*.html` need changing — they describe the *shipped* v1, and live translation IAP is explicitly still unbuilt/planned (same "Holds" pattern as ADR 0010's unbuilt platforms), so those sentences stay true and untouched. This is a check, not a code path — misreading this would cause a false positive fix that makes the listing internally contradictory with the Holds section.
6. **Misuse case the ticket's checklist doesn't name**: a stale pricing claim hiding in a file the literal `grep -rni 'free' docs site` command doesn't cover, because it isn't under `docs/` or `site/` — found one: `README.md:11` ("It is free and non-commercial by design"). Included in the fix even though it's technically outside the literal grep's scope, because leaving it would recreate the exact failure mode (a session reading the README and concluding "free") the ticket was filed to prevent. Flagged here rather than silently expanding scope.

### Findings from the grep sweep already run

| File:line | Verdict |
|---|---|
| `docs/adr/0007-free-and-non-commercial-by-design.md` (whole file) | Historical ADR, explicitly marked "kept as history" in its own 2026-10-10 section — **left untouched**, new ADR supersedes it instead of editing it. |
| `docs/adr/0010-multi-platform-apple-expansion.md:18` — "free forever ([[0007]])" | **Pricing claim, stale — fix**: update to point at the new ADR instead of asserting "free". |
| `docs/app-review-risks.md:142` — "A free app with no ads or IAP from an individual is plausibly non-trader" | **Pricing claim, stale — fix**: this is live reasoning behind an *open* EU-trader-status question; leaving it wrong could lead to the wrong App Store Connect answer. Update to reflect the actual $4.99 + planned $2 IAP facts. |
| `README.md:11` | **Pricing claim, stale — fix** (see misuse case above). |
| `docs/research/evidence-log.md:126` — "a license that allows use in a free app" | **Unrelated**: about whether CC BY 4.0 permits use regardless of the app's own price, not a claim about Seal's price. Left alone. |
| `docs/ideas/v2-and-growth.md:10,55`, `docs/adr/0011...`, `docs/adr/0013...`, `docs/adr/0021...`, `docs/accessibility-audit.md:58`, `docs/adr/0003...`, `docs/testing/test-plan.md`, `docs/design/mocks/**`, `docs/perf/**`, `docs/beta/metrics-schema.md`, `NOTICE.md`, font license files | **Unrelated**: "free-form control," "crash-free," "data-free," license boilerplate, hosting cost, decibel-meter app, etc. — none are claims about Seal's own price. Left alone. |
| `site/*.html`, `docs/app-store-listing.md` | Already correctly say $4.99 and "no subscriptions/IAP" (true for shipped v1) — no "free" pricing claim found. No edit needed. |

<!-- marvin:decisions -->
### d1: Is the one-time price $4.99 or an actual new $5.00?
- [ ] Keep $4.99 — ADR 0007, the live App Store listing text, and the site (`site/index.html`, `support.html`, `versions.html`) all already say $4.99; the ticket's "$5" was rounding, not a new decision. The new ADR documents $4.99 plus the $2 IAP and nothing in the listing/site changes.
- [ ] Change the price to an even $5.00 — the new ADR records $5.00 as current, and `docs/app-store-listing.md`'s price row, `site/index.html`, `site/support.html`, `site/versions.html` get a follow-up ticket to change the displayed price and App Store Connect pricing (out of scope for this ticket to execute, since that needs the owner's App Store Connect access).

## Task List

1. Create `docs/adr/0026-pricing-and-live-translation-iap.md`: Status (Accepted, dated), Context (cross-referencing ADR 0007's $4.99 history and the "free forever" recall error that prompted this ticket), Decision ($4.99 one-time purchase unchanged; live translation as a $2 IAP, same price on iPhone and iPad, implementation differs by device — stated as a fact, no implementation detail), Consequences (supersedes ADR 0007's and ADR 0010's "free" framing going forward; the Decisions block above is embedded here if `d1` needs resolving before merge).
2. Add one glossary bullet to `CONTEXT.md`'s "Core concept" section, right after **Sound label**: **Live translation (IAP)** — domain description only (shows a translation of what's said, in the user's language, alongside/instead of English captions), a paid in-app purchase, not yet shipped, linking to the new ADR. No engine, platform, or implementation wording.
3. Fix `docs/adr/0010-multi-platform-apple-expansion.md:18` — replace "free forever ([[0007]])" with wording that points at the new ADR's actual pricing instead of asserting free.
4. Fix `docs/app-review-risks.md:142` — replace "A free app with no ads or IAP from an individual" with wording that reflects the actual $4.99 price and the planned $2 IAP, since this line feeds a still-open EU trader-status decision.
5. Fix `README.md:11` — replace "It is free and non-commercial by design ([ADR 0007])" with a line that states the actual $4.99 price and links the new ADR, dropping the stale "free and non-commercial" framing.
6. Re-run `grep -rni 'free' docs site README.md` and confirm every remaining hit is the "unrelated" list above (table in this plan), with no new pricing claims introduced by the edits themselves.
7. Verify every `[[NNNN]]` link added in steps 1-5 resolves to an existing file in `docs/adr/`.

**Untested behavior**: none — this ticket touches no Swift code, no app UI, and no CaptionCore logic, so there is nothing for `swift test` or the simulator build/screenshot stage to exercise. All verification above is static doc review.