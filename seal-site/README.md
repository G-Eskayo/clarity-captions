# Seal — Live Captions for Everyone

A static landing page for Seal, an on-device iPhone live captioning app.

## About Seal

Seal provides:
- **Caption stream**: live, scrolling transcript of conversations
- **Speaker labels**: identifies different speakers without enrollment
- **Sound labels**: recognizes ambient sounds like "[Doorbell]" or "[Laughter]"
- **On-device only**: all processing happens on your phone; nothing is sent anywhere
- **Free, always**: no subscriptions, no ads, no tracking

## How to build and deploy

This is a static site with no build step. Just push to GitHub and enable Pages.

### GitHub Pages setup

```bash
gh repo create G-Eskayo/seal-site --public
cd seal-site
git init
git add .
git commit -m "Initial commit: landing page"
git branch -M main
git remote add origin https://github.com/G-Eskayo/seal-site.git
git push -u origin main
gh api -X POST repos/G-Eskayo/seal-site/pages -f "source[branch]=main" -f "source[path]=/"
```

Then visit `https://g-eskayo.github.io/seal-site/` to verify it's live.

## Files

- `index.html` — main page with all sections
- `styles.css` — responsive styling with mobile-first design
- `README.md` — this file

## Accessibility

- Skip link to main content
- Semantic HTML structure
- Visible focus states on all interactive elements
- High-contrast text (WCAG AA compliant)
- Mobile-first responsive design
- System fonts only (no external resources)

## Design

Colors from the Seal brand palette:
- Teal: `#1F998B` (background, accents)
- Cream: `#FBE8C1` (highlights)
- Peach: `#EFC587` (call-to-action buttons)
- Deep teal: `#0E5A56` (text, strong accents)

## Privacy

This site has no tracking, no analytics, and no third-party scripts. It uses only system fonts and does not make any external requests.
