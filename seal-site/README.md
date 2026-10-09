# Seal Marketing Site

A static HTML/CSS marketing website for Seal, built with plain HTML and CSS (no framework, no build step).

## Files

- `index.html` — Main landing page
- `styles.css` — All styling (mobile-first, system fonts, locked color palette from `design/icon/build_icon.py`)
- `assets/` — Images and icons (to be populated)

## Assets needed

Before deployment, populate `assets/` with:

- `seal-icon.png` — App icon (1024px or 512px, copied from `../design/icon/seal-icon-1024.png`)
- `seal-icon-dark.png` — Dark mode variant (optional, for dark theme support)
- `favicon.png` — Small favicon for browser tabs (16×16, 32×32, or up to 64×64)

## Running locally

```bash
cd seal-site
python3 -m http.server 8000
# Then open http://localhost:8000 in your browser
```

## Design decisions

- **Color palette**: Locked hex values from `../design/icon/build_icon.py`
  - Teal light: `#1F998B`, dark: `#0E5A56`
  - Cream light: `#FBE8C1`, dark: `#EFC587`
- **Typography**: System font stack (no third-party fonts, zero network requests)
- **Responsive**: Mobile-first, single CSS file
- **Accessibility**: 4.5:1+ contrast, focus outlines, skip link, semantic HTML, reduced-motion support
- **Browser support**: Modern browsers (ES6+, CSS Grid, CSS custom properties)

## Deployment

1. Create a new repository at `G-Eskayo/seal-site`
2. Push this folder's contents to `main` branch
3. Enable GitHub Pages in repository settings (deploy from `main` branch, root directory)
4. Site will be live at `https://g-eskayo.github.io/seal-site/`

## Pages

- `index.html` — Main landing page
- `privacy.html` — Privacy policy (on-device, no data collection, required for App Store)
- `support.html` — Support/FAQ and contact information (required for App Store)

All pages share the same header, footer, and styling system.
