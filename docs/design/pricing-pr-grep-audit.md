# Grep audit for pricing/free mentions — PR #156

## Files changed in this PR

### Created: `docs/adr/0026-pricing-and-live-translation-iap.md`
- Status: Accepted (2026-10-25), supersedes [[0007]]'s "free forever" framing
- Decision: $5 one-time purchase + $2 IAP for live translation
- Notes $4.99 vs $5 mismatch and defers per-platform mechanism to future ADR

### Edited: `CONTEXT.md`
- Added `## Monetization` section after `## Product principles`
- Term: "Live translation (IAP)" with pointer to [[0026]]

### Edited: `docs/adr/0010-multi-platform-apple-expansion.md` line 18
- Changed: "free forever ([[0007]])" 
- To: "the pricing model ([[0026]])"

### Edited: `README.md` line 11
- Changed: "It is free and non-commercial by design ([ADR 0007]...)"
- To: "One-time $5 USD purchase ([ADR 0026]...); see [0007](docs/adr/0007-free-and-non-commercial-by-design.md) for historical context."

### Edited: `docs/app-review-risks.md` line 142
- Changed: "A free app with no ads or IAP from an individual..."
- To: "A paid app ($5 purchase, no v1 IAP) sold by an individual..."

## Grep audit results

### AC literal command: `grep -rni "free" docs site` (excluding unrelated hits)

**Pricing-related hits (fixed in this PR):**
- `README.md:11` — "It is free and non-commercial" ✅ FIXED
- `docs/adr/0010-multi-platform-apple-expansion.md:18` — "free forever" ✅ FIXED
- `docs/app-review-risks.md:142` — "A free app with..." ✅ FIXED

**Pricing-related hits (left untouched per plan, noted as open decision):**
- `site/support.html:50` — "$4.99, once" — this is the v1 price; ADR 0026 notes the $4.99 vs $5 mismatch
- `docs/app-store-listing.md:121` — "$4.99 (one-time)" — same as above; left untouched per plan step 7

**Non-pricing hits (left as-is, unrelated to monetization):**
- `docs/app-store-listing.md:16` — "No prices, 'free'" (a rule about store listing format)
- `docs/app-store-compliance.md:12,81` — "crash-free stability", "crash-freeness" (quality, not pricing)
- `site/assets/fonts/*` — font license references (font attribution, not app pricing)
- `docs/adr/0016-sound-labels.md` — "free, on-device classifier" (technical feature, not pricing)
- `docs/adr/0003-harvard-sentences-for-enrollment.md` — "free-form talking", "free of licensing concern" (not pricing)
- `docs/adr/0013-radical-simplicity-for-older-users.md` — "free-form controls" (UX term, not pricing)
- `docs/adr/0011-working-name-vs-store-name.md` — "found free" (checking if name is available)
- `docs/adr/0021-interruptions-pause-and-resume-built-in-mic-always.md` — "mic is free" (technical, not pricing)
- `docs/adr/0007-free-and-non-commercial-by-design.md` — multiple mentions of "free"; this is the original decision document, kept for history as noted in ADR 0026
- `docs/ideas/v2-and-growth.md` — "near-free", "free on GitHub Pages" (cost of future features/hosting, not app monetization)
- `docs/design/parakeet-engine-switch.md` — "data-free", "free/low-friction", "free to the Mac app" (technical/engineering terms)

### Verification step 2: Broadened sweep on root-level docs

Files checked: `README.md`, `CLAUDE.md`, `CONTEXT.md`, `docs/agents/*.md`

**Pricing-related hits:**
- `README.md:11` ✅ FIXED (see above)
- `docs/design/pipeline-g-eskayo-clarity-captions-156.md` — multiple "free" references in the design doc (planning/task document, not user-facing; not changed)
- `docs/design/pipeline-g-eskayo-clarity-captions-156-tasks.md` — same (generated task doc)

## Summary

All user-facing, pricing-related mentions of "free" or "non-commercial" have been updated except for:
1. `site/support.html:50` — "$4.99" (v1 price; owner-gated per plan)
2. `docs/app-store-listing.md:121` — "$4.99" (same, owner-gated per plan)

Both left untouched per plan step 7. ADR 0026 documents the $4.99 vs $5 discrepancy and leaves it unresolved for owner decision.

No other "free" mentions in the codebase relate to pricing.
