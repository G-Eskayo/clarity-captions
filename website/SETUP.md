# Website Setup

## Before deploying to GitHub Pages

This folder contains the complete Seal landing page. Two additional files from the main repo need to be copied to make the images work:

```bash
# From the repo root:
cp docs/images/seal-icon.png website/images/
cp docs/images/pipeline.svg website/images/
```

The `website/images/screenshot-placeholder.svg` is already included and renders a sample iPhone screen. Replace it with a real screenshot once available:

```bash
# After capturing a screenshot:
cp path/to/real-screenshot.png website/images/screenshot-placeholder.png
# Then update website/index.html line 47 to reference .png instead of .svg
```

## Validation

Test locally before deploying:

```bash
# Run the validation script from repo root
scripts/validate-website.sh

# Start a local server
cd website
python3 -m http.server 8000
# Then visit http://localhost:8000 in a browser
```

## Deployment notes

- The site is self-contained and requires no build step
- All external links (TestFlight, App Store, privacy policy, support) are placeholders with "Coming soon" badges
- Dark mode is automatically supported via `prefers-color-scheme: dark` in CSS
- Responsive design works from 320px (old iPhones) to 2560px+ (desktop)
