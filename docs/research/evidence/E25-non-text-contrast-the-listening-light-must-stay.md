# E25. Non-text contrast: the Listening light must stay at 3:1 even in a quiet room

- **Source:** W3C, [WCAG 2.2 Success Criterion 1.4.11 Non-text Contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html):
  visual information needed to identify a UI component or its state needs a contrast ratio of at least 3:1 against
  adjacent colours. Plus our own measurement: the contrast of the light's red against each of the six themes'
  backgrounds, using the app's WCAG contrast function.
- **What we took:** the light that follows the room (#180, option C) may fade toward the background only as far as
  3:1. Faded 70% (as first mocked up) it fell to 1.4:1 on Harbor and 1.6:1 on Paper, where a quiet room would make it
  look switched off. Faded at most 20%, every theme stays between about 3.3:1 (quiet) and 5:1 (talking). Full red
  measures 4.4:1 to 5.1:1 across the themes.
- **Confidence:** Strong (W3C guideline), with our own measurement of the themes.
- **Drives:** `ListeningLight.quietDepth = 0.2`, enforced by `ListeningLightTests` on every theme (PR #181, #180).
- **Public use:** Yes ("even in a silent room the Listening light keeps the 3:1 contrast WCAG asks of a status
  indicator").
