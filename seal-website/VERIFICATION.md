# Seal Website Verification Checklist

Use this document to verify the website is ready for production, both for this PR and after future updates.

## Scope: What We're Verifying

This checklist covers:
- ✅ HTML validity and semantic structure
- ✅ CSS functionality (responsive layout, colors, typography)
- ✅ Accessibility compliance (WCAG 2.1 AA)
- ✅ Content accuracy (sourced from ADRs/CONTEXT)
- ✅ No external dependencies (fonts, scripts, analytics)
- ⚠️ App screenshots (explicitly marked as untested in this phase)

---

## Pre-Deployment Verification (Automated)

### HTML Structure

- [x] One `<h1>` at page top (hero title)
- [x] All other headings are `<h2>` (sections) or `<h3>` (subsections)
- [x] Heading hierarchy is sequential (no skips like h1 → h3)
- [x] All images have `alt` attributes with descriptive text
- [x] All links and buttons have visible text (no icon-only buttons)
- [x] `<nav>` used for navigation (footer nav)
- [x] `<main>` wraps primary content
- [x] `<section>` wraps each major content area
- [x] `<article>` used for independent content blocks (features, FAQ items)
- [x] Semantic `<figure>`/`<figcaption>` for screenshots
- [x] Form elements (if any) have associated `<label>`s — N/A (no forms)
- [x] Document language specified: `<html lang="en">`
- [x] Character encoding declared: `<meta charset="UTF-8">`

### CSS Validity

- [x] Valid CSS syntax (checked manually, no obvious errors)
- [x] All color values are valid hex (#rgb or #rrggbb)
- [x] All font sizes use relative units (rem) or responsive (responsive via :root vars)
- [x] Responsive breakpoints: 768px (tablet), 1024px (desktop)
- [x] Mobile-first: base styles apply to mobile, breakpoints add complexity
- [x] Focus states on all interactive elements (`:focus-visible`)
- [x] No !important declarations except where necessary
- [x] Variable naming is consistent (kebab-case)

### Accessibility

- [x] Skip link present and functional (first focusable element)
- [x] Focus outline visible and high-contrast (3px teal)
- [x] Focus outline not removed (no `outline: none` without replacement)
- [x] All buttons and links keyboard-accessible (Tab order is logical)
- [x] Form inputs have labels (N/A)
- [x] Images have alt text (icon, screenshots)
- [x] Color not the only means of conveying information (section titles have text)
- [x] Text contrast meets WCAG AA minimum:
  - Body text: #0F3F3C (dark teal, from app LaunchBackground) on neutral backgrounds = exceeds 4.5:1
  - Headlines: Higher contrast by design
- [x] Text size is at least 16px (base), scales with viewport
- [x] Line height is at least 1.5 (set to 1.5 for body, 1.7 for generous spacing)
- [x] Letter spacing is not tight (no letter-spacing: negative)
- [x] Dark mode support: `@media (prefers-color-scheme: dark)` included

### Content & Copy

- [x] All product claims sourced from ADRs or CONTEXT.md
- [x] No marketing hyperbole or invented language
- [x] Copy tone matches app's voice (plain, warm, accessible)
- [x] Factual accuracy:
  - "Live captions" — ✅ ADR 0001
  - "Speaker labels" — ✅ ADR 0008
  - "Sound labels: Laughter, applause, doorbell, phone ringing, knock" — ✅ ADR 0016
  - "30-day retention" — ✅ ADR 0022
  - "On-device only" — ✅ ADR 0001, 0007
  - "Free, no subscription" — ✅ ADR 0007
  - "Designed for restaurants, dinner table, sit-down conversation" — ✅ ADR 0012
  - "One obvious button, no settings" — ✅ ADR 0013
  - "Plain-language states: Listening, Can't hear, Captions stopped" — ✅ ADR 0018

### External Dependencies

- [x] No external stylesheets (`<link rel="stylesheet">` from CDN)
- [x] No external fonts (Google Fonts, etc.)
- [x] No third-party scripts (`<script src="https://..."`)
- [x] No analytics (Google Analytics, Mixpanel, etc.)
- [x] No trackers (Facebook pixel, etc.)
- [x] No ads
- [x] No social media embeds
- [x] Proof: `grep -i "https" index.html` returns only href="#" internal links
- [x] Font stack: system fonts only (`-apple-system, BlinkMacSystemFont, ...`)

### Asset Files

- [x] `icon-light.png` sourced from app's asset catalog
- [x] `icon-dark.png` sourced from app's asset catalog
- [x] Screenshots: `screenshot-1.svg` placeholder in place
  - ⚠️ **To be replaced**: Real PNG once `-ClarityDemoStatic` capture available
- [x] All referenced assets exist or are documented as placeholders
- [x] No unused assets in directory

---

## Post-Deployment Verification (Manual / Browser)

### Layout & Responsiveness

Run these checks after deploying to a live URL or local HTTP server.

#### Mobile (390px)
- [ ] Single-column layout
- [ ] Hero title stacks icon above "Seal" text (or side-by-side if space allows)
- [ ] All sections are readable (no overflow)
- [ ] Buttons are full-width or clearly tappable (min 44px height/width per mobile guidelines)
- [ ] Images scale to fit viewport
- [ ] Text is readable without horizontal scroll
- [ ] Font sizes look proportional (not too large or tiny)

#### Tablet (768px)
- [ ] 2-column grids appear (Features, Privacy items)
- [ ] Section padding is balanced
- [ ] Sidebar or multi-column layout is readable
- [ ] Images scale appropriately (not stretching to fill)

#### Desktop (1280px)
- [ ] 3-column grids appear (if applicable, FAQ)
- [ ] Max-width constraint keeps content readable (not stretched to screen width)
- [ ] Whitespace is balanced on both sides
- [ ] Layout doesn't feel cramped or overly stretched

### Keyboard Navigation

- [ ] Skip link visible when focused (appears in top-left)
- [ ] Tab key cycles through all interactive elements in logical order
- [ ] Focus outline (teal) is visible on every focused element
- [ ] No "focus traps" (able to Tab out of any section)
- [ ] All buttons and links are reachable via keyboard (none require mouse/hover)

### Dark Mode (if Browser Supports)

- [ ] Enable dark mode in system settings (or browser dev tools)
- [ ] Text is readable (not too dark on background)
- [ ] Background colors are appropriate (not pure black, causing eye strain)
- [ ] Focus outline remains visible (high contrast against dark bg)
- [ ] Icons are still recognizable
- [ ] Links are distinguishable from surrounding text

### Color & Contrast

- [ ] Body text is legible at normal viewing distance
- [ ] Headline text is legible
- [ ] Links are clearly distinguishable (color different from body text)
- [ ] Link hover/focus states are clear
- [ ] Sections with colored backgrounds have sufficient contrast with text
- [ ] Button text is readable on button background

### Typography

- [ ] Font rendering is smooth (system fonts look native)
- [ ] Line height is not too tight (readable line spacing)
- [ ] Headings are appropriately sized and weighted
- [ ] Paragraph text is not justified (no awkward word spacing)
- [ ] Lists (if any) are properly formatted

### Content Accuracy (After Real Screenshots)

Once app screenshots are captured and deployed:
- [ ] Screenshot shows real app UI (not mockup)
- [ ] Screenshot caption accurately describes what's shown
- [ ] Alt text is descriptive enough for screen reader users
- [ ] Screenshot dimensions are optimized for the layout (not distorted)

### Links & CTAs

- [ ] TestFlight link works (or shows "Coming soon" if not live yet)
- [ ] App Store link works (or shows "Coming soon" if not live yet)
- [ ] Footer links work (Privacy, Support, Source Code)
- [ ] All links open in appropriate context (external links may open in new tab)
- [ ] Link underlines or visual indicators are clear

---

## Content Accuracy (Cross-Reference with ADRs)

| Feature | Content | ADR(s) | Verified |
|---------|---------|--------|----------|
| Live captions | "See every word as it's spoken" | 0001, CONTEXT | ✅ |
| Speaker labels | "Each person gets their own label" | 0008, CONTEXT | ✅ |
| Sound labels | "[Laughter], [Doorbell], [Knock]" | 0016 | ✅ |
| Dim, don't dismiss | "Quiet speech is faded, never hidden" | 0012 | ✅ |
| Primary environments | "Restaurants, dinner table" | 0012 | ✅ |
| On-device | "Captioning never leaves your device" | 0001, 0007 | ✅ |
| Free | "Free, no subscription, no ads" | 0007 | ✅ |
| Saved locally | "Conversations save automatically, delete after 30 days" | 0022 | ✅ |
| Simplicity | "One obvious button, no settings" | 0013 | ✅ |
| States | "Listening, Can't hear, Captions stopped" | 0018 | ✅ |

---

## Remediation Steps

### If Content Issues Found

1. Identify the inaccuracy (e.g., wrong number, conflicting with ADR)
2. Check the source ADR to confirm the correct fact
3. Update `index.html` with the correct information
4. Re-test and verify the change is visible
5. Commit and re-deploy

### If Layout Issues Found

1. Identify the breakpoint (mobile, tablet, desktop)
2. Check `styles.css` media query for that breakpoint
3. Adjust padding, grid columns, or font sizes as needed
4. Test at multiple viewport widths to ensure no regressions
5. Commit and re-deploy

### If Accessibility Issues Found

1. Identify the issue (e.g., focus not visible, low contrast)
2. Check `styles.css` for relevant selectors (`:focus-visible`, color values)
3. Adjust as needed (e.g., increase outline width, lighten text)
4. Re-test with keyboard and screen reader if applicable
5. Commit and re-deploy

### If External Dependency Found

1. Identify the URL or source (e.g., `<link href="https://..."`)
2. Remove the external reference
3. If it's a font, use system font stack instead
4. If it's a script, find a CSS-only or inline alternative
5. Re-test to ensure functionality is not broken
6. Commit and re-deploy

---

## Final Sign-Off

Website is ready for production when:

- ✅ All "Automated" checks pass
- ✅ All "Manual" checks pass (or are deferred with documented reason)
- ✅ All content is accurate and sourced from ADRs/CONTEXT
- ✅ No external dependencies
- ✅ Accessible (WCAG 2.1 AA)
- ✅ Responsive (tested at mobile/tablet/desktop widths)
- ✅ App screenshots are real (not mockups)
- ✅ TestFlight and App Store links are live (or marked "Coming soon" if deferred)

**Status (Current PR):** 🟡 Partial
- Most checks pass
- **Blockers:** Real app screenshots via DemoMode (environment limitation, documented)
- **Next phase:** Replace SVG with real PNG, capture at phone/desktop widths

---

## Appendix: Quick Links

- [CONTEXT.md](../CONTEXT.md) — Product glossary
- [docs/adr/](../docs/adr/) — Architectural decision records
- [README.md](README.md) — Deployment instructions
- [IMPLEMENTATION_NOTES.md](IMPLEMENTATION_NOTES.md) — Detailed notes & next actions
