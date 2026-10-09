# Evidence log: the research behind Seal's decisions

One entry per source. Each says what we took from it, how strong it is, and which decision it drives, so the
portfolio page and the marketing site (#44) can show the reasoning, not just the result. **Add an entry whenever
research informs a decision**, and link the ADR, PR or ticket it drove.

Confidence: **Strong** (controlled study or official documentation), **Moderate** (guideline or several consistent
sources), **Weak** (single small study, secondary report or anecdote), **Ours** (our own measurement).

Public use: **Yes** (fine to cite on the portfolio or marketing pages as written), **Careful** (cite with its
caveat), **Internal** (process detail, not for marketing).

---

## E1. Dark vs. light mode for older readers
- **Source:** Piepenbrock, Mayr, Mund & Buchner (2013), *Ergonomics*: younger (18–33) vs. older (60–85) adults on
  visual acuity and proofreading in light vs. dark mode. Summary: [Nielsen Norman Group, Dark Mode vs. Light Mode](https://www.nngroup.com/articles/dark-mode/).
- **What we took:** dark text on a light background read better for both age groups, but the advantage was smaller
  for older adults. Dark mode caused no measurable extra eye fatigue. Participants had healthy eyes (no cataracts).
- **Confidence:** Strong for healthy eyes; the result doesn't extend to eye conditions.
- **Drives:** equal choice of 3 light and 3 dark themes rather than dark by default (v1 polish spec §4, #96).
- **Public use:** Careful ("light and dark both work; we offer both equally").

## E2. Brightness contrast matters more than color
- **Source:** Legge, Parish, Luebker & Wurm (1990), *Psychophysics of reading XI: comparing color contrast and
  luminance contrast*, JOSA A. [PDF](https://legge.dl8.umn.edu/sites/legge.psych.umn.edu/files/files/media/legge90_psychophysics_of_reading._xi._comparing_luminance_and_color_contrast.pdf)
- **What we took:** low-vision readers all read better with luminance (brightness) contrast than color contrast;
  text color itself mattered for only a minority (mostly advanced photoreceptor disorders).
- **Confidence:** Strong.
- **Drives:** every theme must reach AAA contrast (7:1), enforced by a test; theme design focuses on brightness
  contrast, not on "special" text colors (#96).
- **Public use:** Yes.

## E3. Yellow-on-black isn't proven easier, and pure-black glare
- **Source:** no controlled study found that isolates yellow-on-black for older adults (searched 2026-10-09).
  Secondary: [NIH/NLM, Making Your Web Site Senior Friendly](https://corpora.tika.apache.org/base/docs/govdocs1/562/562513.html)
  (light lettering on dark backgrounds is acceptable; avoid yellow next to blue and green for older eyes).
  Astigmatism and halation on bright-on-black text: anecdotal, not verified.
- **What we took:** no evidence justifies the harsh black-and-yellow "Bright" theme; dark themes should be calm
  (no pure black, no pure white, warm off-white text) while keeping AAA contrast.
- **Confidence:** Moderate (guideline) for the yellow/blue caution; Weak for the glare reasoning.
- **Drives:** "Bright" theme removed; relaxed dark themes (owner, 2026-10-09; #96).
- **Public use:** Careful.

## E4. What makes captions readable for older viewers
- **Source:** caption readability study for elderly TV viewers. [Sun Repository](https://reposit.sun.ac.jp/dspace/handle/10561/231)
- **What we took:** readability depends on caption size, font, spacing and the contrast between caption and
  background, the four things Seal lets people adjust.
- **Confidence:** Moderate.
- **Drives:** size, lettering and color settings (ADR 0013 simplicity; #34 text size; #96 settings).
- **Public use:** Yes.

## E5. Dyslexia fonts don't measurably improve reading
- **Source:** Wery & Diliberto (2017), *The effect of a specialized dyslexia font, OpenDyslexic, on reading rate and
  accuracy*, Annals of Dyslexia. [PMC full text](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5629233/) ·
  [Springer](https://link.springer.com/article/10.1007/s11881-016-0127-1). Counterpoint: a 3-student study reported
  gains ([OHU](https://acikerisim.ohu.edu.tr/items/4a62b3fd-db56-44ff-bddf-1349ab8e6458)); overview:
  [Edutopia](https://www.edutopia.org/article/do-dyslexia-fonts-actually-work/).
- **What we took:** in 12 students with dyslexia, OpenDyslexic gave no improvement in reading rate or accuracy over
  Arial or Times New Roman, and none preferred it. Some people still find it more comfortable.
- **Confidence:** Strong (for no measured benefit, in children); Weak (for the counterpoint).
- **Drives:** **open decision** on the default lettering (v1 polish spec §5). Whatever is chosen, marketing must
  not claim a font improves reading.
- **Public use:** Careful ("offered for comfort", never "improves reading").

## E6. What App Review rejects, and how to avoid it
- **Source:** [docs/app-review-risks.md](../app-review-risks.md) and [docs/app-store-compliance.md](../app-store-compliance.md):
  Apple's App Review Guidelines, App Store Connect help, developer forums and Reddit, each claim marked as Apple doc
  or forum report.
- **What we took:** device-support check, privacy manifest, iPad orientations, export compliance, the in-app
  privacy link, no health claims, and holding background audio out of v1.
- **Confidence:** Strong (Apple docs); Weak (forum anecdotes, marked as such).
- **Drives:** #79, #80, #82, #83, the listing in docs/app-store-listing.md.
- **Public use:** Internal (the "no data collected, fully on-device" outcome is Yes).

## E7. Building on existing on-device speech and speaker tools
- **Source:** [docs/research-existing-resources.md](../research-existing-resources.md): Apple SpeechAnalyzer reference
  code, FluidAudio (Apache-2.0), Sortformer (CC BY 4.0).
- **What we took:** transcription and speaker separation are solved problems on-device; reuse them, bundle the
  models, and never call the network at runtime.
- **Confidence:** Strong.
- **Drives:** ADR 0001, 0008, 0014.
- **Public use:** Yes (credit the open-source projects).

## E8. Why one voice sometimes gets split into two speakers
- **Source:** our own replay measurements, [docs/perf/speaker-label-stability.md](../perf/speaker-label-stability.md) (#91, PR #94).
- **What we took:** the speaker model itself reassigns one voice after pitch or pace changes; smoothing cut live
  relabels (e.g. 8.1 → 4.5 per minute) without slowing real turn-taking; a full fix needs a voice-recognition model.
- **Confidence:** Ours (synthetic voices; real-device check pending).
- **Drives:** SpeakerLabelSmoother (#94); open decision on adding a speaker-embedding model.
- **Public use:** Careful (good "how we measure" story; don't overstate accuracy).
