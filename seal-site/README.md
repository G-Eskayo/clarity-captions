# Seal — Marketing Website

The public marketing site for Seal, a free on-device live-captioning app for iPhone.

**Live at:** https://g-eskayo.github.io/seal-site/

## About Seal

Seal is a native iOS app that provides real-time live captions for conversations, entirely on your phone. No network required. No account. No setup. Free forever.

- **On-device only**: Everything runs locally on your phone.
- **No enrollment**: Works identically for every user, out of the box.
- **Free**: No cost now, no cost later. No ads. No subscriptions.
- **Accessibility first**: Built for anyone who needs live captions to follow conversations.

## About This Site

This is a static HTML and CSS site with no framework, no build step, and no third-party dependencies. The locked color palette is from the app's icon design (`design/icon/README.md` in the main `clarity-captions` repository).

### Pages

- **`index.html`** — The main public landing page, explaining what Seal does, who it's for, how it works, and how to get it.

### Styles

- **`styles.css`** — Responsive design using the locked icon palette colors.

## Development

No build process required. To test locally:

```bash
# Start a simple HTTP server
python3 -m http.server 8000

# Visit http://localhost:8000
```

## Deployment

GitHub Pages serves this site automatically from the `main` branch, root directory. See `DEPLOYMENT.md` for setup details.

## Accessibility

- Semantic HTML with proper heading hierarchy
- Keyboard navigation (Tab, Enter, Focus states visible)
- Color contrast meets WCAG AA standards
- Responsive design (mobile, tablet, desktop)
- Skip-to-content link for keyboard users
- Dynamic Type styling (rem units for text scaling)

## Icon Assets

Icon assets are copied from the main `clarity-captions` repository (`design/icon/seal-icon-1024.png`) and resized for web use. See `DEPLOYMENT.md` for icon setup instructions.

## License

This site's design and copy are subject to the same terms as the Seal app repository. See the main `clarity-captions` repository for full license information.

## Related

- **Main app repository**: [G-Eskayo/clarity-captions](https://github.com/G-Eskayo/clarity-captions)
- **App Store**: Coming October 2026
- **TestFlight**: Coming October 2026

## Contact

For questions, feedback, or support inquiries, see the links in the site footer.
