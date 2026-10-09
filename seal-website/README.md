# Seal Website

[Seal](https://github.com/G-Eskayo/clarity-captions) — Live captions for conversation, right on your phone.

This repository contains the Seal marketing website, a static HTML + CSS site hosted on GitHub Pages.

## Building and Deploying

The site is built as follows:

1. **Assets setup:**
   - Copy `seal-icon.png` from the [clarity-captions repository](https://github.com/G-Eskayo/clarity-captions/blob/main/docs/images/seal-icon.png) to `assets/seal-icon.png`
   - Generate `assets/favicon.ico` from the same icon using a tool like ImageMagick:
     ```bash
     convert assets/seal-icon.png -define icon:auto-resize=256,128,96,64,48,32,16 assets/favicon.ico
     ```

2. **GitHub Pages:**
   - Enable Pages in repository settings: **Settings > Pages > Deploy from a branch > main / root**
   - The site is served at `https://g-eskayo.github.io/seal-website` (or the custom domain once configured)

3. **Local testing:**
   - Serve locally with Python: `python3 -m http.server 8000`
   - Visit `http://localhost:8000` in a browser

## Accessibility

- **Semantic HTML:** Uses proper heading hierarchy and landmark elements (`<header>`, `<main>`, `<section>`, `<footer>`)
- **Color contrast:** Verified against WCAG AA (cream on teal, ink on cream, all text on background)
- **Responsive:** Mobile-first layout, reflows from ~320px to desktop widths
- **Keyboard navigation:** All interactive elements (links, buttons) are focusable with visible focus styles
- **Images:** All images have descriptive `alt` text

## Privacy

No third-party analytics, tracking scripts, or external dependencies. The site is a single HTML file with embedded CSS. No CDNs, no frameworks, no JavaScript.

## Source

- Icon from [docs/images/seal-icon.png](https://github.com/G-Eskayo/clarity-captions/blob/main/docs/images/seal-icon.png)
- Color palette locked in [design/icon/build_icon.py](https://github.com/G-Eskayo/clarity-captions/blob/main/design/icon/build_icon.py)
- Compliance guidance from [docs/app-store-compliance.md](https://github.com/G-Eskayo/clarity-captions/blob/main/docs/app-store-compliance.md)
- Feature overview from [CONTEXT.md](https://github.com/G-Eskayo/clarity-captions/blob/main/CONTEXT.md)

## Related

- **Main project:** [G-Eskayo/clarity-captions](https://github.com/G-Eskayo/clarity-captions)
- **Portfolio:** [gileskayo.me](https://gileskayo.me)
