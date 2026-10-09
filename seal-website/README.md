# Seal Website

This folder contains the static website for Seal, the iOS live-captioning app.

## Purpose

This website serves as the public landing page for Seal, linking to the TestFlight beta and (later) the App Store. It's meant for distribution as a new, separate GitHub repository: `G-Eskayo/seal-website`.

## Building for a New Repository

These files are ready to deploy to GitHub Pages from the root of a new repository:

1. Create a new repository `G-Eskayo/seal-website` on GitHub
2. Copy all files from this folder to the new repository root
3. Enable GitHub Pages in the repository settings:
   - Settings → Pages → Source: Deploy from a branch
   - Branch: `main`, folder: `/ (root)`
4. GitHub Pages will serve `index.html` at the repository's Pages URL

## Contents

- `index.html` — Main landing page with all sections
- `styles.css` — Responsive, accessible CSS (no external dependencies)
- `assets/` — Images (app icon, screenshots)
  - `icon-light.png` — Seal app icon (copied from Apps/Spike/Assets)
  - `icon-dark.png` — Dark variant of the icon
  - `screenshot-1.svg` — Placeholder screenshot (to be replaced with real app screenshots)

## Design Notes

- **No build step:** Plain HTML and CSS, served directly by GitHub Pages
- **No external dependencies:** All fonts are system fonts; no third-party scripts or stylesheets
- **No tracking:** Zero analytics, zero external requests from the site
- **Responsive:** Mobile-first design, tested at phone (390px) and desktop (1280px) widths
- **Accessible:** WCAG 2.1 AA compliant, with focus states, skip links, semantic HTML, proper contrast

## Screenshots

The `screenshot-1.svg` is a placeholder based on the app's DemoMode script. It shows what the caption view would look like during a conversation. To update with real app screenshots:

1. Run the app with `-ClarityDemoStatic` launch flag in Xcode Simulator to show the caption view
2. Capture screenshots at two widths:
   - Phone width (~390px): portrait orientation
   - Desktop width (~1280px): side-by-side or landscape
3. Optimize the PNGs (pngquant or similar) and replace `assets/screenshot-*.png`
4. Update alt text and figcaption in `index.html` to describe the actual content

For now, the SVG mockup is acceptable for development and review.

## Content Sourcing

All copy is sourced directly from the project's ADRs and CONTEXT.md:
- ADR 0007: Free and non-commercial by design
- ADR 0008: Speaker-turn labeling
- ADR 0011: Store name "Seal"
- ADR 0012: Dim, don't dismiss and primary environments
- ADR 0013: Radical simplicity
- ADR 0016: Sound labels
- ADR 0022: Saved conversations, 30-day retention
- CONTEXT.md: Product principles and key terminology

No marketing copy is invented; everything is grounded in the project's decision record.

## Deployment

Once deployed as a separate repository with GitHub Pages enabled, the site is live at:
```
https://g-eskayo.github.io/seal-website/
```

(Or the custom domain, if one is configured in the GitHub repository settings.)

## Further Reading

- [Clarity Captions GitHub](https://github.com/G-Eskayo/clarity-captions) — Main app repository
- [ADRs](../docs/adr/) — Architectural decision records
- [CONTEXT.md](../CONTEXT.md) — Product glossary and principles
