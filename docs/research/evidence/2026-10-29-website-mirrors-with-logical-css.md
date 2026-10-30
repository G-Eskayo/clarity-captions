# The website mirrors with logical CSS, at no cost to English; Hebrew needs its own direction marks

- **Source:** our own measurement on #207 (2026-10-29, Mac Mini, Chrome headless through `scripts/site-shots.mjs`):
  28 full-page screenshots of every English page and device tab at 390 px and 1280 px, light and dark, before and
  after moving `site/` to logical properties and building it from translation files; plus a Chrome walk of the
  language offer on a preview with Hebrew published. Background: the HTML `dir` attribute isolates its element for the
  Unicode bidi algorithm ([HTML spec, the dir attribute](https://html.spec.whatwg.org/multipage/dom.html#the-dir-attribute);
  [MDN, `<bdi>`](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/bdi)).
- **What we took:** all 28 English screenshots are pixel-identical before and after, so logical properties cost
  English nothing and one `dir="rtl"` mirrors a page. Kept physical on purpose: centring with `left: 50%` and
  `translateX(-50%)` (a logical start would push it off centre in right-to-left), anything a script places by
  `offsetLeft`, and the SVG charts (pictures don't mirror, ADR 0030 point 9). In Hebrew, an English button name with
  brackets (`[ Save ]`) or a trailing parenthesis (`Parakeet Ultra 6-bit (1.1)`) reorders unless isolated, so those
  go in `<bdi lang="en">`; and a question in one direction inside a page of the other ("This page in English?" on a
  Hebrew page) put its question mark at the wrong end until it carried its own `dir`.
- **Confidence:** High for English being unchanged (pixel comparison); Moderate for the Hebrew reading right (layout
  checked by eye by a non-native reader; the wording waits for a native speaker, #38's rule).
- **Drives:** #207: the logical-property rule in `check-site.mjs`, `<bdi lang="en">` around the app's English labels
  in `site-src/lang/he.json`, and the offer's words carrying their direction (`site/lang.js`).
- **Public use:** Careful ("the site mirrors itself for Hebrew and Arabic; English looked exactly the same after").
