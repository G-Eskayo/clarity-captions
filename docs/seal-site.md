# Seal Marketing Site

The Seal marketing website has been moved to a standalone repository: **[G-Eskayo/seal-site](https://github.com/G-Eskayo/seal-site)**

## Purpose

A public-facing marketing site explaining what Seal is, who it's for, how it works, and privacy commitments. Deployed to GitHub Pages at https://g-eskayo.github.io/seal-site.

## Design

- **Brand:** Teal (#1F998B) and cream (#FBE8C1) color scheme, matching the Seal app icon (ADR 0011)
- **Accessibility:** Skip links, focus-visible outlines, proper semantic HTML, no external scripts
- **Responsiveness:** Optimized for mobile (390px) through desktop (1440px+)
- **Zero external dependencies:** Plain HTML/CSS, no JavaScript, fonts, or tracking

## Content

- Hero section with app name and tagline
- Feature overview (Live Captions, Speaker Labels, Smart Dimming, Sound Labels, Customization, On-Device)
- Who it's for (deaf/hard of hearing users and conversation participants)
- Privacy statement (no account, no servers, no tracking, on-device processing)
- How it works (three simple steps)
- Screenshots placeholder (to be filled with real app screenshots once available)
- Call-to-action for App Store and TestFlight beta

## Repository structure

```
seal-site/
├── index.html         # Main page
├── style.css          # Styling (responsive, accessible)
├── assets/
│   └── seal-icon-1024.png  # Seal logo
├── README.md          # Project overview
└── .gitignore         # Standard web project exclusions
```

## Development

To test locally:
```bash
python -m http.server 8000
# Then visit http://localhost:8000
```

Verify at mobile width (~390px) and desktop width (~1440px+).

## Deployment

The site is published to GitHub Pages automatically when changes are pushed to the `main` branch of G-Eskayo/seal-site.

## Related

- ADR 0011: Brand name is Seal
- ADR 0007: Free and on-device
- ADR 0013: Radical simplicity for older users
