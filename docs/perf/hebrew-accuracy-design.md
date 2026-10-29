# Hebrew accuracy test: design (#201, #202)

Design for #201 "[E] Hebrew: measure Apple's dictation engine against the open Hebrew models" and its scorer, #202
"[E] Hebrew text normaliser for fair scoring". Method and harness come from the #158 language test
([`language-accuracy-design.md`](language-accuracy-design.md)); this page records what changes for Hebrew.

## Scoring

### The normaliser (#202)

`normalize(text, "he")` in `scripts/engine-eval/edacc_eval/hebrew.py`, applied identically to the reference and to
every engine's text, so whatever quirk is left costs every engine the same. In order:

1. **Direction marks removed** (U+200E/F, U+061C, U+202A–E, U+2066–9, U+FEFF), not turned into spaces. Apple's
   DictationTranscriber starts its Hebrew text with U+200F; a mark inside a word would otherwise split it.
2. **Unicode NFKC, then casefold.** Presentation forms (שׁ as one code point, U+FB2A) decompose; no-break spaces
   become spaces; Latin words inside Hebrew are lower-cased.
3. **Niqqud and cantillation stripped:** every point in U+0591–U+05C7 except the four punctuation marks in that range.
   Maqaf (U+05BE), paseq (U+05C0), sof pasuq (U+05C3) and nun hafukha (U+05C6) become spaces.
4. **Engine markers dropped:** `<...>`, `[...]`, `{...}`. Parentheses stay, as in #158 (FLEURS reads them aloud).
5. **Geresh and gershayim unified, then dropped:** ׳ ״ and every stand-in (`'` `"` `` ` `` `’` `”` `´` `ʼ`), so
   צה״ל = צה"ל = צה''ל = צהל and ג׳ירפה = גירפה. Quotation marks around words go with them.
6. **Symbols to words:** `%` → אחוז (and אחוזים → אחוז), `₪` → שקלים, `$` → דולר.
7. **Thousands separators** (`1,000`) removed; a decimal point between digits (`3.5`) is kept, and every other
   punctuation mark becomes a space. A hyphen-minus is treated like a maqaf.
8. **A prefix letter glued to digits splits off:** `ב3` → `ב 3`, so it matches `ב-3` and `בשלוש`.
9. **Fillers dropped:** אה, אהה, אההה, אמ, אממ, אמממ, אהמ, הממ, המממ, מממ (and Latin uh/um/mm/hmm). אום is not one:
   it is also או"ם (the UN) once gershayim are gone.
10. **Numbers to one form: words become digits** (inverse normalisation), because the word form depends on gender
    and construct state (חמש, חמישה, חמשת are all 5) and digits don't. Both genders, construct forms, common full
    and defective spellings (שלוש/שלש, שישים/ששים), teens (שלוש עשרה, שלושה עשר), tens with or without ו,
    hundreds (מאה, מאתיים, שלוש מאות), thousands (אלף, אלפיים, שלושת אלפים, עשרת אלפים), millions and billions,
    and a digit or decimal before a scale word (`5 אלף`, `2.5 מיליון`). A number word behind up to three prefix
    letters (ו ה ב ל מ ש כ) keeps its prefix as a separate token: בשלוש → `ב 3`. Inside a number only the conjunction
    ו may continue it, and two units in a row are two numbers (חמש ושש → `5 ו 6`).
    - **שנים** is "two" only right before עשר/עשרה (שנים עשר = 12). Standing alone it is almost always "years", and
      reading it as 2 would turn מאה שנים into 102.
    - A lone plural scale word stays a word: אלפים אנשים is "thousands of people", not a number.
    - Words that are also numbers (שני = Monday, אחד in אף אחד) become digits on both sides; that is symmetric, so it
      costs nothing.
11. **Abbreviations always said in full:** ארה"ב → ארצות הברית and ק"מ → קילומטר (with any prefix letter;
    קילומטרים → קילומטר too), and the two accepted spellings לדוגמא / לדוגמה become one. FLEURS writes the
    abbreviations, every engine writes what was said. ק"מ and לדוגמא were added after reading the errors on Apple's
    FLEURS shard 1, before any scoring was final, the way #158 added its rules; each has a test.
12. **Final letter forms are kept** as written: ם/מ, ן/נ and the rest are spelling, and an engine that writes the
    wrong one has made a spelling error.

The ticket's title mentions prefixes. Prefix letters are **not** split from ordinary words: Hebrew writes them
joined, the references do too, and splitting them would hide real errors (ו־ vs ה־ changes the meaning). Their cost
is what CER is for (below). Prefixes are split only from numbers, where the reference and engines really do write
the same words differently (`ב-3`, `ב3`, `בשלוש`).

**Lenient score.** `lenient_hebrew()` folds full and defective spelling (ktiv male / ktiv haser): it drops ו and י
inside a Hebrew word, keeping its first and last letter, so שולחן = שלחן, תוכנית = תכנית, תקווה = תקוה,
קרייה = קריה. Word-initial ו ("and") and final י ("my") stay, since they change the meaning. It is reported **beside**
the strict score, never instead of it: it also merges a few real pairs (a word and its plural spelled only with a
mater lectionis), which is why strict is the headline.

**Known residual mismatches**, equal for every engine: other abbreviations (ת"א, וכו', ס"מ), Latin terms the reference
writes in Latin letters and an engine in Hebrew letters (or the reverse), and Hebrew numbers said as ordinals
(השלישי) against digits.

### WER and CER

- **WER** = (S + D + I) / N over words, pooled over clips (`wer.py`, the #145 alignment).
- **CER** = the same alignment over characters of the normalised text with single spaces between words
  (`char_counts`). In Hebrew one wrong prefix letter makes the whole fused word wrong in WER (ובבית vs בבית is one
  word error but one character), so CER is the in-house decision metric and WER is for comparing with published
  numbers. Research summary for #201: "Use WER to compare with the leaderboard and CER as the in-house decision
  metric."
- Strict and lenient, WER and CER: four numbers per engine per set, each with a 95% CI.

Tests: `scripts/engine-eval/tests/test_normalize_hebrew.py` (every rule with real Hebrew pairs, including the
ticket's שולחן/שלחן, צה״ל/צה"ל and 5/חמש).

## Complexity

- Normaliser: O(characters) per text; the number reader is one left-to-right pass over the tokens with constant
  lookahead, O(tokens).
- CER: O(R × H) in characters per clip (FLEURS clips are under 30 s, a few hundred characters).
