# Seal Marketing Site — Deployment Guide

This directory contains the static HTML and CSS files for the Seal marketing website.

## Prerequisites

- GitHub repository: `G-Eskayo/seal-site` (must be created)
- Icon assets (see below)

## Icon Assets Setup

Icon source is in the `clarity-captions` repository at `design/icon/seal-icon-1024.png`.

### 1. Copy and resize the icon

The website expects:
- `assets/seal-icon-128.png` — for header display
- `assets/favicon-32.png` — for browser favicon (32×32)
- `assets/favicon-192.png` — for mobile home screen icon (192×192)

From the `clarity-captions` repo, copy `design/icon/seal-icon-1024.png` and resize:

```bash
# Using ImageMagick (if available):
convert seal-icon-1024.png -resize 128x128 seal-icon-128.png
convert seal-icon-1024.png -resize 32x32 favicon-32.png
convert seal-icon-1024.png -resize 192x192 favicon-192.png
```

Or use your preferred image editor to resize the 1024×1024 source to these sizes.

### 2. Place icons in the `assets/` directory

```
seal-site/
  assets/
    seal-icon-128.png
    favicon-32.png
    favicon-192.png
```

## GitHub Pages Deployment

1. **Create the repository** (if not already created):
   ```bash
   gh repo create G-Eskayo/seal-site --public \
     --description "Marketing site for Seal, a free on-device live-captioning app"
   ```

2. **Enable GitHub Pages**:
   - Go to repository Settings → Pages
   - Source: `main` branch, `/root` (serve from repository root)
   - GitHub will auto-detect the static site and publish to `https://g-eskayo.github.io/seal-site/`

3. **No build step required** — all files are static HTML/CSS. Push and done.

## File Structure

```
seal-site/
  index.html           # Main page
  styles.css           # Styles using locked color palette
  assets/
    seal-icon-128.png  # Header icon
    favicon-32.png     # Favicon
    favicon-192.png    # Home screen icon
  DEPLOYMENT.md        # This file
  README.md            # (optional) about the site
```

## Verification Checklist

- [ ] Icon assets are in place in `assets/`
- [ ] `index.html` and `styles.css` are in the repo root
- [ ] GitHub Pages is enabled and source is set to `main` branch, root
- [ ] Site is live at `https://g-eskayo.github.io/seal-site/`
- [ ] Keyboard navigation works (tab through links, focus visible)
- [ ] Mobile responsive (test at 390×844 and 1440×900 viewports)
- [ ] Color contrast meets WCAG AA (use browser DevTools or WebAIM Contrast Checker)
- [ ] No network requests (no analytics, no third-party fonts)
- [ ] Skip-to-content link is functional

## Notes

- The site is intentionally static, with no framework, build process, or JavaScript.
- The color palette is locked per `clarity-captions/design/icon/README.md`.
- All copy is grounded in `clarity-captions/CONTEXT.md` and ADRs (0007, 0008, 0011, 0013, etc.).
- Screenshots are placeholders (the app cannot be captured in this environment).
- TestFlight and App Store links will be updated once the app is live.
