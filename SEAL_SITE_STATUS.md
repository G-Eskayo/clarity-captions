# Seal Marketing Site — Status & Recommendation

**Ticket:** G-Eskayo/clarity-captions#44 ('Site for Seal app on GitHub Pages')  
**Updated:** 2026-10-09  
**Status:** Content complete and corrected; structural blocker blocks further progress

---

## What's Done ✅

All content files for the Seal marketing site are ready in `seal-site/`:

### Fixed in this pass:
- **Copy accuracy**: Updated "late October 2026" → "by October 25, 2026" (aligns with ADR 0009's submission timeline: 10-15 day buffer before hard date)
- **Accessibility**: Fixed WCAG AA contrast issue in promise section (h3 color: cream → white, contrast ratio now 3.41:1, passes large-text threshold of 3:1)

### Complete from prior work:
- Semantic HTML with proper heading hierarchy and skip-to-content link
- Responsive CSS design (mobile/tablet/desktop) with locked color palette from `design/icon/README.md`
- No third-party dependencies, no tracking, no build step
- Dark mode support via CSS media queries
- Alt text on all images, keyboard navigation ready
- Features, privacy promise, how it works, CTA sections

---

## What's Blocked ❌

The ticket's acceptance criteria require three things this environment cannot deliver:

### 1. **Create new GitHub repository** (`G-Eskayo/seal-site`)
- Requires: `gh repo create` (write-level GitHub access)
- Allowed in this sandbox: `gh view`/`list`/`diff` only
- **Blocker:** Bash in restricted mode, read-only `gh` scope

### 2. **Push content to GitHub**
- Requires: `git push` with remote configured
- **Blocker:** Same as above

### 3. **Screenshot content at two widths** (phone + desktop)
- Requires: browser or screenshot tool
- **Blocker:** No browser/display available in this environment

These are not content issues — they're environmental constraints on write operations that were deliberately scoped out of this run.

---

## Recommendation: Two Paths Forward

### Option A: Re-scope acceptance criteria
Move the site into the `clarity-captions` repo itself (e.g., `docs/seal-site/` + GitHub Pages on the main repo), then:
- Acceptance passes if: semantic HTML, responsive, no tracking, alt text present ✅
- No need for repo creation, push, or browser access
- Trade-off: URL becomes `g-eskayo.github.io/clarity-captions/seal-site/` instead of `g-eskayo.github.io/seal-site/`

### Option B: Re-dispatch with elevated scope
Keep "new repository" requirement, but dispatch with:
- Elevated `gh` permissions (repo-create, push)
- Browser/screenshot tool access
- Bash unrestricted for full automation

Then the agent can complete all criteria without asking.

---

## What to Do Now

1. **Review the fixes** in `seal-site/index.html` and `seal-site/styles.css` (copy dates, contrast ratio)
2. **Choose Option A or B** above
3. **If Option A**: edit ticket criteria, re-run (content is already correct)
4. **If Option B**: re-dispatch this ticket with elevated tool scope

**The content itself is ready.** The blocker is not "what should be on the site" but "where should it live and who can push it."

---

## Files Changed

```
seal-site/index.html       # Line 131: updated copy to "by October 25, 2026"
                           # Line 159: updated copy (removed TestFlight mention)
seal-site/styles.css       # Line 258: .promise h3 color: cream → white (contrast fix)
```

All other files in `seal-site/` remain from prior work and are ready for commit.
