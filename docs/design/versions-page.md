# Versions page (#151)

Design note for `site/versions.html` ("Versions" on seal-speak.gileskayo.me). Written before the HTML.

## Purpose

A saved history of what changed in each release, plus the decision stories behind the changes. The first story is how and why we chose the caption engine. Plain language for users; the numbers are for anyone who wants to check.

## Look

Same as `site/index.html`: Peach in light, Harbor in dark (`prefers-color-scheme`), the same header (seal + name + nav), the same footer, `.band` sections, `.card`, `ul.ticks`. No new colours: bars use `--teal`, the reference line uses `--accent`, text uses `--text` / `--muted`. No script, no external requests, no tracking. The home page has no page-wide OpenDyslexic toggle (the lettering choice lives inside its demo phone), so there is none here.

## Sections

1. **Header / intro.** What this page is. States that unreleased versions are labelled as such.
2. **Releases**, newest first, each with an honest status badge:
   - *Coming next, 1.1 (build 6)*: full-screen iPad layout, iPhone Duo, and the engine switch to Parakeet Ultra 6-bit. The iPad/Duo build is uploaded, not submitted; the engine build is not uploaded yet; iPhone checks still to do.
   - *In review, 1.0 (build 5)*: everything in the 1.0 App Store listing, in user language. Runs on iPad in the iPhone-sized layout. Not released.
3. **How we chose the caption engine.** Story in short paragraphs, then:
   - Method diagram (inline SVG).
   - Chart A: WER with 95% CI per engine.
   - Chart B: size vs WER of the Parakeet builds, Apple 17.2% as a reference line.
4. **What we chose and why.** Plain language: Parakeet Ultra 6-bit, 498 MB, 13.8% WER; fallback Ultra 4-bit. Caveats: one corpus, measured on a Mac, iPhone check pending.
5. **Full report.** Links to the GitHub report and evidence log E12.

## Charts

Both are inline SVG with `role="img"`, `<title>`, `<desc>`, and a `<details>` data table right after.

**A. WER bars.** Horizontal bars, axis 0 to 20%, whiskers = 95% CI, a dashed line at 15% ("good" target from docs/testing/test-plan.md). Rows: Parakeet Ultra 6-bit, Parakeet v2, sherpa-onnx, Apple SpeechAnalyzer. The table adds median "time to correct word" and speed.

**B. Size vs WER.** x = on-disk size (MB), y = WER, vertical whiskers = 95% CI, one dot per Parakeet build, a horizontal line at Apple's 17.2%. The chosen build is highlighted.

## Data sources

All numbers are copied from the #145 branch (`origin/feature/145-engine-eval`), not computed or typed from memory:

| Number | Source |
|---|---|
| Corpus 31.4 h, 17,528 clips, 32 shards, 122 speakers, CI method (speaker bootstrap, 1,000 resamples) | `docs/perf/engine-accuracy-comparison.md`, header and "Overall" |
| Overall WER and CI per engine | same, "Overall" |
| Speed (x real time) | same, "Overall" / "Speed" |
| Live latency (median correct word, 526 clips, 45 min) | same, "Live latency (streaming sample)" |
| Size, WER and CI per Parakeet build | same, "Size options (Parakeet builds)"; evidence log E12 |
| Decision: Ultra 6-bit, fallback Ultra 4-bit | owner decision, 2026-10-22, recorded on #150 |
| Release contents | `docs/app-store-listing.md`, git log, ADR 0001 (1.0 uses Apple's recognizer), #147 (1.1) |

The report currently lives on the #145 branch, so the page links to that branch. Once #145 merges, the links should point at `main`.

## Honesty rules

Never present an unreleased version as live. WER numbers are from a Mac, not an iPhone; the page says so. Accent-level results are in the report, not repeated here.

## Footer

"Versions" is added to the footer of every site page (home, privacy, support, versions).
