# Seal Marketing Site — Deployment Guide

This marketing site is committed as part of the clarity-captions monorepo. Future deployment to GitHub Pages is out of scope for this ticket.

## What's Included

- ✅ **index.html** — Single-page marketing site with:
  - Hero section with app icon and CTA
  - Feature highlights (6 key capabilities)
  - "Who It's For" section (audience & use cases)
  - Privacy promise (on-device, no servers/accounts/tracking)
  - How It Works (3-step walkthrough)
  - Screenshot grid (placeholders for real app screenshots)
  - Call-to-action (TestFlight/App Store coming soon)

- ✅ **style.css** — Production-ready design:
  - Responsive mobile-first layout (`clamp()` for type scales)
  - Teal/cream palette matching app icon (#1F998B, #0E5A56, #FBE8C1, #EFC587)
  - Full accessibility: semantic HTML, skip-link, focus outlines, alt text
  - WCAG AA contrast compliance
  - No external dependencies, no CDNs, no third-party fonts
  - System font stack only
  - Zero JavaScript, zero analytics, zero tracking
  - High-contrast and reduced-motion support
  - Print styles

- ✅ **Real app icon** — Uses the designed seal icon (`../design/icon/seal-icon-1024.png`) instead of placeholder SVG

## Testing Locally

To preview the site at different widths:

```bash
# Simple: open in your browser
open seal-site/index.html

# Or run a local HTTP server
cd seal-site
python3 -m http.server 8000
# Then visit http://localhost:8000
```

Test widths:
- Mobile: 390px (iPhone width)
- Tablet: 768px
- Desktop: 1440px

Verify:
- ✓ Text scales smoothly
- ✓ Layout reflows at 640px and 1024px breakpoints
- ✓ App icon renders
- ✓ All buttons/links are keyboard-navigable
- ✓ Focus outlines visible on interactive elements
- ✓ Screenshot grid renders at 9:16 aspect ratio

## Future Work

- **Real app screenshots** — Placeholder frames ready for replacement once app is built and published
- **GitHub Pages deployment** — Currently part of clarity-captions monorepo; Pages setup requires repo owner decision on hosting strategy
- **TestFlight/App Store links** — Placeholders ready for real URLs once beta/release is live
