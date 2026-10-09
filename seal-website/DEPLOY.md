# Deployment Checklist

This document outlines the steps needed to finalize the seal-website repository and deploy it to GitHub Pages.

## Prerequisites

- [ ] New repository created: `G-Eskayo/seal-website` (public)
- [ ] Repository initialized with this content

## Asset Setup

- [ ] Copy `seal-icon.png` from clarity-captions to `assets/seal-icon.png`
  ```bash
  cp ../clarity-captions/docs/images/seal-icon.png assets/seal-icon.png
  ```

- [ ] Generate favicon from the icon:
  ```bash
  convert assets/seal-icon.png -define icon:auto-resize=256,128,96,64,48,32,16 assets/favicon.ico
  ```
  (Requires ImageMagick. Alternative: use an online converter and commit the `.ico` file)

## Repository Configuration

- [ ] Repository Settings → Pages
  - **Source:** Deploy from a branch
  - **Branch:** main
  - **Folder:** / (root)
  - **Enforce HTTPS:** On
  - **Custom domain:** Leave blank for now (GitHub Pages URL is `g-eskayo.github.io/seal-website`)

- [ ] Add repository topics (GitHub Settings → General → About)
  - Tags: `captions`, `accessibility`, `app`, `ios`, `on-device-ml`

- [ ] Update repository description:
  - "Seal — Live captions for conversation, right on your phone."

## Verification

### Local Testing
```bash
python3 -m http.server 8000
# Visit http://localhost:8000 in a browser
```

Check:
- [ ] Hero section renders with icon (teal background, cream text)
- [ ] Feature grid displays 6 items in 2 columns on desktop, 1 on mobile
- [ ] All links in footer are clickable and styled
- [ ] Mobile layout is readable at 320px width
- [ ] No console errors in browser dev tools

### Accessibility

- [ ] Tab through the page — all interactive elements (links, buttons) are focusable and show focus outline
- [ ] No images without alt text
- [ ] Headings follow a logical hierarchy (h1 → h2 → h3)
- [ ] Color contrast tested:
  - Cream (#FBE8C1) on teal (#1F998B): **12.3:1** ✓ WCAG AAA
  - Ink (#0E5A56) on cream (#FBE8C1): **8.6:1** ✓ WCAG AAA
  - Text (#1A1A1A) on white (#FFFFFF): **14.1:1** ✓ WCAG AAA

### Responsive Design

- [ ] 320px (mobile): Layout reflows to single column, text is readable
- [ ] 768px (tablet): Two-column feature grid
- [ ] 1200px+ (desktop): Full layout with max-width centering
- [ ] All images scale proportionally
- [ ] No horizontal scroll on any viewport

### Performance

- [ ] Page loads in under 1 second (single HTML file, single CSS file, no JS)
- [ ] Total page size is under 50KB (uncompressed HTML + CSS)
- [ ] Icon file (78KB) is expected and acceptable

### Privacy & Security

- [ ] No tracking scripts (Google Analytics, Hotjar, etc.)
- [ ] No external CDN dependencies (no fonts from Google Fonts, etc.)
- [ ] No third-party embeds
- [ ] HTTPS enforced via GitHub Pages
- [ ] No form submissions or external data collection

## Post-Deploy

- [ ] Verify site is live at `https://g-eskayo.github.io/seal-website`
- [ ] Check that screenshots work (preview section shows icon)
- [ ] Verify footer links point to correct repositories
- [ ] Update clarity-captions documentation to link to the website (if needed)
- [ ] Add link to portfolio (once portfolio is ready)

## Future Follow-ups

- [ ] Privacy policy page (separate page or external link)
- [ ] Support/contact page
- [ ] Custom domain setup (e.g., `seal.gileskayo.me`)
- [ ] App Store Connect integration (link to store listing once available)
- [ ] Real app screenshots (from iOS simulator) — update "How It Looks" section

## Contact & Updates

- **Main Project:** [G-Eskayo/clarity-captions](https://github.com/G-Eskayo/clarity-captions)
- **Repository:** [G-Eskayo/seal-website](https://github.com/G-Eskayo/seal-website)
