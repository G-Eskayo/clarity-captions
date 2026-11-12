# Mac calls: each line is translated from the language its words are in

- **Source:** our own measurements for face to face, [docs/perf/face-to-face-spike.md](../../perf/face-to-face-spike.md)
  (#60) and [docs/perf/face-to-face-code-switching.md](../../perf/face-to-face-code-switching.md) (#208): Apple's
  NaturalLanguage on the device, scored on the words the caption engine wrote. Parakeet takes no language setting and
  writes what it hears (ADR 0029), so the words' language is the language spoken; Apple's engine hears only the language
  it was started in (E27).
- **What we took:** the lock rule as measured, **4 or more words and 99% sure** (`LanguageMatchPolicy`): every real
  Spanish sentence and every English line of 4+ words scored 99% or more, while one word ("Hi.") reached only 68%, and
  99% beat 95% on the recorded code-switching conversations. Shorter or mixed lines are not trusted on their own.
- **Confidence:** Ours, and borrowed: measured on face-to-face Spanish and English on an iPhone, not on Mac call audio or
  other language pairs. Re-measure on a real Mac call when it is wired (#213's lag check).
- **Drives:** PR #231 (#213), the owner's note on `from-labels`: on the Mac each finished line goes to the translator
  for its words' language among the conversation's languages already set up (Room, Calls), when its side runs on
  Parakeet; her language is left alone; a sure language nobody set up is shown as said; a short line follows its
  voice's last sure language. `MacTranslationRouter` in CaptionCore.
- **Public use:** Careful ("on a call in several languages, Seal translates each line from the language it was said
  in, among the languages you set up").
