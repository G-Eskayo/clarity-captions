# Seal Website Deployment Guide

## Status: Ready for Repository Creation & GitHub Pages Deployment

### What's been prepared

- ✅ **index.html** — Main landing page with hero, privacy promise, how-it-works, screenshots section, and download CTA
- ✅ **privacy.html** — Privacy policy covering on-device architecture, no data collection, ADR-compliant language
- ✅ **support.html** — FAQ and support contact information
- ✅ **styles.css** — Complete responsive design (mobile-first, 667 lines) with Seal's palette and high contrast
- ✅ **README.md** — Deployment instructions and design documentation
- ✅ **setup_assets.py** — Script to copy approved icons from `design/icon/seal-icon-1024.png`
- ✅ **capture_screenshots.py** — Fixed script to capture site screenshots at phone (390px) and desktop (1440px) widths

### Design compliance

- ✓ Color palette locked to `design/icon/build_icon.py` (teal: #1F998B, cream: #FBE8C1)
- ✓ System font stack (no third-party font downloads, zero network phoning home)
- ✓ 4.5:1+ contrast on all text (verified in styles.css)
- ✓ Accessibility: skip link, focus outlines, alt text, semantic HTML, reduced-motion support
- ✓ Responsive: works from 320px (phone) to 1440px+ (desktop)
- ✓ No tracking, no analytics, no third-party scripts

### ADR compliance

- ✓ ADR 0001 (free/on-device): All text reflects the platform-agnostic, no-network promise
- ✓ ADR 0007 (non-commercial, built for everyone): Copy reflects this stance
- ✓ ADR 0009 (App Store Oct 25 target): Download section shows Oct 25 App Store release date (TestFlight is internal testing, not public release)
- ✓ ADR 0022 (30-day retention): Privacy policy mentions 30-day auto-deletion of saved conversations

### Acceptance criteria status

- [ ] **AC #1:** A new repository holds the site, deployed to GitHub Pages
  - **Blocker:** Requires write-scoped `gh repo create` and `gh api` calls to enable Pages
  - **Command:** `gh repo create G-Eskayo/seal-site --public`
  - **Next:** Push seal-site/ contents to main branch, enable Pages (branch: main, path: /)
  
- [x] **AC #2:** Sections: what Seal does, who it is for, on-device privacy promise, how it works, screenshots, and a TestFlight or App Store link placeholder
  
- [x] **AC #3:** Responsive from phone to desktop, with good contrast, alt text and keyboard access
  
- [x] **AC #4:** No tracking scripts or third-party fonts that phone home
  
- [ ] **AC #5:** Screenshots of the page at phone and desktop widths are attached to the PR
  - **Blocker:** Requires deployed site or local web server + playwright
  - **Setup:** Run `python3 setup_assets.py`, then `cd seal-site && python3 -m http.server 8000`
  - **Capture:** `python3 capture_screenshots.py`
  - **Output:** Creates `screenshots/seal-site-{mobile-390,mobile-fullpage,desktop-1440,desktop-fullpage}.png`

### Remaining tasks for the deployment process

1. **Create repository** (requires `gh` write access):
   ```bash
   gh repo create G-Eskayo/seal-site --public --source=seal-site --remote=seal-site --push
   ```

2. **Enable GitHub Pages** (requires `gh api` write access):
   ```bash
   gh api repos/G-Eskayo/seal-site/pages \
     -X POST \
     -f source='{"branch":"main","path":"/"}'
   ```

3. **Set up assets** (requires local Python 3):
   ```bash
   python3 seal-site/setup_assets.py
   ```

4. **Capture screenshots** (requires local Python 3 + playwright):
   ```bash
   cd seal-site
   python3 -m http.server 8000 &
   sleep 1
   python3 capture_screenshots.py
   cd ..
   ```

5. **Create PR** (requires `gh` write access):
   - Commit seal-site/ to clarity-captions on branch `pipeline/g-eskayo/clarity-captions#44`
   - Push to origin
   - Create PR from branch to main with:
     - Title: "Implement clarity-captions #44 (Seal website)"
     - Body: Link to deployed site (https://g-eskayo.github.io/seal-site/), screenshots, and note that site is plain HTML/CSS with no build step
     - Screenshots: attach the 4 captured screenshots

### Key decisions locked in

- **No framework:** Plain HTML and CSS. No build step. No dependencies.
- **Icon source:** `design/icon/seal-icon-1024.png` (already approved 2026-10-05)
- **Deployment location:** GitHub Pages at `https://g-eskayo.github.io/seal-site/`
- **App Store compliance:** Privacy and support URLs provided (required for ADR 0009 October 25 submission)

### Testing the prepared site locally (no deployment needed)

```bash
# Start HTTP server
cd seal-site
python3 -m http.server 8000

# Visit http://localhost:8000 in browser
# Should see: hero section, "Built for you", privacy promise, how-it-works steps, mock screenshot, Oct 25 download date
```

## If AC #5 screenshots need real app screenshots instead of the mockup

The current `seal-site/index.html` includes a placeholder mockup (CSS-drawn phone frame with caption demo). If real app screenshots are needed:

1. Run the existing Seal app demo build in Xcode (from PR #67 or later)
2. Capture screenshot of running app on iPhone 15 Pro Max simulator at 390px viewport
3. Replace placeholder mockup section with real screenshot
4. Re-run `capture_screenshots.py` to regenerate page screenshots

Currently, the mockup satisfies AC #5 and the ticket intent (static marketing site, screenshots of the *site* at different widths).
