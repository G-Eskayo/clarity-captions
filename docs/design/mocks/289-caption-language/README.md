# Caption language on the caption screen: mock-ups (#289)

Mock-ups only; nothing here ships. Drawn over real simulator screenshots of the current caption screen (`src/base-*`:
iPhone 17 and iPad Pro 13", `-ClarityDemoStatic`, Paper and Night; the Mac pop-up from #246's shots). Render with
`~/.agents/venv/bin/python src/render.py` (Pillow, SF Pro), which writes the sheets into `src/`.

Why: in #273 the demo ran on a non-English caption language saved in Seal, and nothing on screen showed it.

1. `01-option-a.png`: A, the language under the status, as face to face already shows it. When it isn't the
   phone's language, a warning sign and "not your phone's language" (icon and words, never colour alone).
2. `02-option-b.png`: B, nothing new while it matches; a note with **Change** only when it doesn't.
3. `03-option-c.png`: C, one line: "Listening · English", with a warning sign when it doesn't match.
4. `04-dark-themes.png`: all three on Night (iPhone) and Harbor (Mac).

The Mac follows the Mac's own language (English, or Hebrew) and has no saved caption language, so its mismatch
case is a Mac set to another language (French here) getting English captions.
