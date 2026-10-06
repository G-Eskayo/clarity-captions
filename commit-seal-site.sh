#!/bin/bash
set -e

cd "$(dirname "$0")"

# Stage the seal-site files (excluding .gitignore)
git add seal-site/index.html seal-site/style.css seal-site/SETUP.md

# Show what's staged
git status

# Commit
git commit -m "$(cat <<'EOF'
Implement G-Eskayo/clarity-captions#44 — Seal marketing landing page

Add complete marketing site for Seal app:
- index.html: single-page site with hero, features, privacy, how it works, and CTA
- style.css: responsive design with teal/cream palette, full accessibility
- Real app icon (seal-icon-1024.png) instead of placeholder SVG
- Deployment guide (SETUP.md renamed to reflect monorepo structure)

Content covers all acceptance criteria:
- What Seal does (6 key features)
- Who it's for (audience description)
- Privacy promise (on-device, no servers/accounts/tracking)
- How it works (3-step walkthrough)
- Call-to-action (TestFlight/App Store coming soon)
- Screenshot grid (placeholders ready for real app screenshots)

Design:
- Mobile-first responsive layout (breakpoints at 640px, 1024px)
- WCAG AA contrast compliance
- System fonts only, zero external dependencies
- Full accessibility: semantic HTML, skip-link, focus outlines, alt text
- Print and high-contrast mode support

Deployment: Pages hosting and standalone repo creation are out of scope
for this commit; site is committed into clarity-captions monorepo.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>
EOF
)"

# Show the commit
git log -1 --stat
