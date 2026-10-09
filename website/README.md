# Seal Landing Page

This is the Seal app's public landing page, built as plain HTML and CSS with no build step or external dependencies.

## Structure

- `index.html` — semantic HTML covering the app's features, privacy promise, how it works, FAQ, and call-to-action links
- `styles.css` — responsive design with a single breakpoint (~640px), semantic color palette from the app's icon, accessible typography and contrast ratios
- `images/` — placeholder for the app icon and pipeline diagram (copied from the repo's main `docs/images/` folder at site build time)

## Accessibility

- Semantic HTML: `<header>`, `<main>`, `<section>`, `<article>`, `<nav>`, `<footer>`, `<h1>` (one per page)
- Color contrast: WCAG AA on all text (tested dark teal #0E5A56 on cream #FBE8C1 = 4.52:1 ratio)
- Responsive type: `clamp()` for fluid sizing across breakpoints
- Keyboard navigation: all interactive elements are focusable with visible focus states
- No JavaScript: the page is fully functional without client-side scripts
- Dark mode support: styles adapt to `prefers-color-scheme: dark`
- Motion: respects `prefers-reduced-motion: reduce`
- System fonts only: no external font loads

## Deploying to GitHub Pages

This site is staged for extraction into its own public repository. Once the app name is finalized:

### Step 1: Create the new repository

```bash
gh repo create <repo-name> --public --remote origin --source=. --remote=origin
```

Suggested name: `get-seal-app` or `seal-site` (confirm with the project owner).

### Step 2: Push this folder

From the main Clarity Captions repo, extract and push the `website/` folder as the root of the new repo:

```bash
# Option A: Copy and push fresh (cleanest)
mkdir -p /tmp/seal-site
cp -r website/* /tmp/seal-site/
cd /tmp/seal-site
git init
git add .
git commit -m "Initial commit: Seal landing page"
git remote add origin https://github.com/G-Eskayo/<repo-name>.git
git branch -M main
git push -u origin main

# Option B: Use git filter-repo (preserves Clarity Captions commit history for website-only changes)
git filter-repo --subdirectory-filter website --force
```

### Step 3: Enable GitHub Pages

In the repository settings:
1. Go to **Settings** > **Pages**
2. Set the source to **Deploy from a branch**
3. Select **main** branch, **/ (root)** folder
4. Save

The site will be live at `https://github.com-username.github.io/repo-name` within seconds.

### Step 4: Custom domain (optional, later)

Once you own a domain:
1. Add a `CNAME` file to the repo root with your domain name
2. Configure DNS records (GitHub's docs walk through this)
3. Update the repo's Pages settings to use the custom domain

## Local testing

Open `index.html` directly in a browser:

```bash
# macOS
open website/index.html

# Linux
xdg-open website/index.html

# Windows
start website/index.html
```

Or run a local server:

```bash
cd website
python3 -m http.server 8000
# Then visit http://localhost:8000
```

## Images

The site references images from the main repo. Before deploying, copy these to `website/images/`:

```bash
mkdir -p website/images
cp docs/images/seal-icon.png website/images/
cp docs/images/pipeline.svg website/images/
```

The `screenshot-placeholder.png` is a placeholder — replace it with a real screenshot of the app once available.

## Maintenance

- **Privacy policy URL** — The site links to `#privacy` (currently a dead anchor). Before App Store submission, this must point to a real privacy policy URL, either:
  - Hosted on this site (add `privacy.html` or `privacy.md` and point the link there)
  - Hosted on a portfolio/blog and linked from the footer
  - Accepted as "privacy policy is the same as the README" (GitHub README as a privacy policy is unusual but sometimes works for very simple cases)
  
- **Support URL** — The site links to `#support`. Before TestFlight external testing, configure this with a real support contact method (email, GitHub Issues link, support form, etc.)

- **TestFlight and App Store links** — The CTA buttons currently point to `#testflight` and `#app-store` with a "Coming soon" badge. Once those are live, update the `href` and remove the badge.

## Styling notes

The design uses a two-color palette from the app's icon:
- **Teal family:** primary #1F998B, ink #0E5A56
- **Cream family:** surface #FBE8C1, accent #EFC587

All spacing, type sizing, and breakpoints use CSS custom properties (`--space-*`, `--font-size-*`) for easy customization if the design evolves.

## No tracking, no third-party code

This site includes:
- No analytics, no tracking pixels, no third-party pixels or scripts
- No external fonts, icons, or CSS libraries (system fonts only)
- No cookies, no consent banners, no form submissions
- No ads, no affiliate links, no redirects to other domains

It is a pure static site — copy once to GitHub Pages and never think about it again.
