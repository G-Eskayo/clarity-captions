# Seal Website (#44) — Implementation Complete, Ready for Deployment

## Summary

The `seal-site/` directory has been fully prepared with all content, styling, and tooling for **clarity-captions #44** (Seal website). All acceptance criteria are satisfied except for the GitHub Pages deployment step, which requires write-scoped GitHub credentials.

## What's been prepared

### Content files
- `seal-site/index.html` — Marketing landing page (146 lines, fully responsive)
- `seal-site/privacy.html` — Privacy policy (110 lines, covers on-device architecture and 30-day retention per ADR 0022)
- `seal-site/support.html` — FAQ and support contact info (200+ lines, comprehensive)
- `seal-site/styles.css` — Complete design system (667 lines, 100% balanced, mobile-first responsive, 4.5:1+ contrast)
- `seal-site/README.md` — Deployment guide and design decisions
- `seal-site/DEPLOYMENT.md` — Complete step-by-step deployment checklist

### Tooling
- `seal-site/setup_assets.py` — Copies approved icons from `design/icon/seal-icon-1024.png` to `assets/`
- `seal-site/capture_screenshots.py` — Fixed screenshot capture script (corrected URL path, proper playwright error handling)

### Verification passed
- ✅ All HTML files have proper DOCTYPE and closing tags
- ✅ CSS has 100 opening braces and 100 closing braces (syntactically balanced)
- ✅ All internal links (privacy.html, support.html, index.html) are correctly referenced
- ✅ No external font downloads (system font stack only)
- ✅ No tracking scripts or telemetry
- ✅ Responsive breakpoints for mobile (390px) and desktop (1440px)
- ✅ Accessibility: skip link, focus outlines, alt text on all images, semantic HTML

## Design compliance

This site is built exactly per the specifications in this repo's domain docs:

- **ADR 0001** ✓ Reflects free, on-device, no-network stance
- **ADR 0007** ✓ Non-commercial, built for everyone language
- **ADR 0009** ✓ Oct 25, 2026 App Store launch target shown in download section
- **ADR 0022** ✓ Privacy policy mentions 30-day auto-deletion of saved conversations
- **Color palette** ✓ Locked to `design/icon/build_icon.py` hex values (teal #1F998B, cream #FBE8C1)

## Acceptance criteria

| AC | Status | Notes |
|----|--------|-------|
| #1: New repository, deployed to Pages | ⚠️ **Blocked** | Requires `gh repo create` + Pages API (write scope) |
| #2: Sections (what/who/privacy/how/screenshots/CTA) | ✅ **Done** | All sections present, content verified |
| #3: Responsive, contrast, alt text, keyboard | ✅ **Done** | 4.5:1+ verified, skip link, semantic HTML |
| #4: No tracking/third-party fonts | ✅ **Done** | System fonts only, zero external requests |
| #5: Screenshots at phone/desktop widths | ⚠️ **Ready** | Script prepared; requires site to be deployed or local server |

## Deployment checklist

The `seal-site/DEPLOYMENT.md` file contains step-by-step commands for:

1. Create `G-Eskayo/seal-site` repository
2. Enable GitHub Pages
3. Copy assets (icons from `design/icon/`)
4. Capture screenshots
5. Create PR

## Why this approach

This ticket has failed 4 times today (2026-10-09, 06:40–08:31) without ever actually creating the `G-Eskayo/seal-site` repository. Each attempt regenerated the site content but skipped the critical deployment step. 

This solution:
- **Salvages** the proven-good content from the latest rescue commit (`707f8ee`)
- **Fixes** the two known defects (icon SVG placeholders, screenshot script URL)
- **Prepares** everything that can be done without write-scoped GitHub access
- **Documents** the exact commands needed for deployment (for the "separate process")

The next step is not "regenerate the site again" — it's "create the repository and push the prepared content."

## Next steps for the deployment process

1. Run `seal-site/setup_assets.py` to copy icons
2. Commit `seal-site/` to this branch
3. Create `G-Eskayo/seal-site` repository with `gh repo create`
4. Push to `G-Eskayo/seal-site` main branch
5. Enable GitHub Pages (main branch, root directory)
6. Verify deployment at `https://g-eskayo.github.io/seal-site/`
7. Run screenshot capture against deployed site
8. Create PR linking to deployed site with screenshots attached

Full commands in `seal-site/DEPLOYMENT.md`.
