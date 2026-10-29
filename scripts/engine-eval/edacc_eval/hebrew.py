"""Hebrew normalizer for scoring (#202). Rules and the reasons for them: docs/perf/hebrew-accuracy-design.md ("Scoring").

Applied identically to the reference and every engine's text, so any quirk left over costs every engine the same.
Strict form: `normalize_he`. Lenient form (full and defective spelling folded): `lenient_hebrew` on top of it.
"""
from __future__ import annotations

import re
import unicodedata
from decimal import Decimal

# Niqqud, cantillation and the other Hebrew points (U+0591-U+05C7), except the punctuation in that range, which
# becomes a space: maqaf U+05BE, paseq U+05C0, sof pasuq U+05C3, nun hafukha U+05C6.
_HEBREW_PUNCT_IN_POINTS = {"־", "׀", "׃", "׆"}
_POINTS = re.compile("[" + "".join(chr(c) for c in range(0x0591, 0x05C8)
                                   if chr(c) not in _HEBREW_PUNCT_IN_POINTS) + "]")
_HEBREW_PUNCT = re.compile("[" + "".join(_HEBREW_PUNCT_IN_POINTS) + "]")
# Geresh and gershayim, and every mark an engine or a typist uses for them; unified, then dropped.
_GERESH = re.compile("[׳״'\"`‘’“”´ʼ׳]")
_TAG = re.compile(r"<[^>]*>|\[[^\]]*\]|\{[^}]*\}")
_GROUPED = re.compile(r"\b\d{1,3}(?:,\d{3})+\b")
_PUNCT = re.compile(r"[^\w.]+|_+|(?<!\d)\.|\.(?!\d)")  # keeps the point of a decimal (3.5) and nothing else
_LETTER_DIGIT = re.compile(r"(?<=[^\W\d_])(?=\d)|(?<=\d)(?=[^\W\d_])")
_DIGITS = re.compile(r"\d+(?:\.\d+)?")
_HEBREW_LETTER = re.compile("[א-ת]")

FILLERS = frozenset("אה אהה אההה אמ אממ אמממ אהמ הממ המממ מממ eh uh um umm mm mmm hmm".split())
_SYMBOLS = {"%": " אחוז ", "₪": " שקלים ", "$": " דולר "}
_FOLD = {"אחוזים": "אחוז"}

# --- Numbers: words to digits (inverse normalization), so "5" and "חמש"/"חמישה" are one form ------------------------
# Both genders, the construct forms and the common full and defective spellings. "שנים" is left out on purpose:
# standing alone it is almost always "years", not "two" (it still counts inside "שנים עשר", twelve).
_UNITS = {}
for _v, _forms in {
    0: "אפס", 1: "אחד אחת", 2: "שתיים שתים שניים שתי שני", 3: "שלוש שלש שלושה שלשה שלושת שלשת",
    4: "ארבע ארבעה ארבעת", 5: "חמש חמישה חמשה חמשת", 6: "שש שישה ששה ששת", 7: "שבע שבעה שבעת",
    8: "שמונה שמונת", 9: "תשע תשעה תשעת",
}.items():
    for _f in _forms.split():
        _UNITS[_f] = _v
_TEEN_TWO = {"שנים"}  # "two", only before עשר/עשרה
_TEN = {"עשר", "עשרה", "עשרת"}
_TENS = {}
for _v, _forms in {20: "עשרים", 30: "שלושים שלשים", 40: "ארבעים", 50: "חמישים חמשים", 60: "שישים ששים",
                   70: "שבעים", 80: "שמונים", 90: "תשעים"}.items():
    for _f in _forms.split():
        _TENS[_f] = _v
_HUNDRED = {"מאה": 100, "מאתיים": 200, "מאתים": 200}
_HUNDREDS = {"מאות"}
_SCALE = {"אלף": 10**3, "אלפים": 10**3, "אלפיים": 2 * 10**3, "מיליון": 10**6, "מליון": 10**6,
          "מיליונים": 10**6, "מיליארד": 10**9, "מיליארדים": 10**9}
_NUMBER_WORDS = set(_UNITS) | _TEEN_TWO | _TEN | set(_TENS) | set(_HUNDRED) | _HUNDREDS | set(_SCALE)
_PREFIX_LETTERS = set("והבלמשכ")


def _split_prefix(token: str, starting: bool, before_ten: bool = False) -> tuple[str, str] | None:
    """(prefix, number word) if the token is a number word, bare or behind one to three prefix letters (shortest
    prefix first). A starting number keeps its prefix letters; a continuing one may only carry the conjunction ו.
    "שנים" counts as "two" only before עשר/עשרה (before_ten) or inside a number."""
    for k in range(0, 4):
        prefix, word = token[:k], token[k:]
        if k and (len(word) < 2 or not set(prefix) <= _PREFIX_LETTERS):
            break
        if word not in _NUMBER_WORDS:
            continue
        if not starting and prefix not in ("", "ו"):
            return None
        if word in _TEEN_TWO and not before_ten:  # "מאה שנים" is a hundred years, not 102
            return None
        return prefix, word
    return None


class _Number:
    """One Hebrew cardinal read word by word. feed() returns False when the word can't continue this number."""

    def __init__(self) -> None:
        self.total = 0  # millions and thousands already closed
        self.small = 0  # below 1000
        self.ones = self.tens = self.hundreds = self.teen = False
        self.scales_used: set[int] = set()
        self.last_unit = None
        self.words = 0

    def _reset_small(self) -> None:
        self.small = 0
        self.ones = self.tens = self.hundreds = self.teen = False
        self.last_unit = None

    def feed_digits(self, digits: str) -> bool:
        if self.words:
            return False
        self.small = Decimal(digits) if "." in digits else int(digits)  # "2.5 מיליון"
        self.ones = self.tens = self.hundreds = True  # only a scale word may follow: "5 אלף", "2 מיליון"
        self.words = 1
        return True

    def feed(self, w: str) -> bool:
        if w in _UNITS or w in _TEEN_TWO:
            v = 2 if w in _TEEN_TWO else _UNITS[w]
            if self.ones or self.teen or (v == 0 and self.words):
                return False
            self.small += v
            self.ones = True
            self.last_unit = v
        elif w in _TEN:
            if self.ones and not self.tens and not self.teen and self.last_unit:
                self.small += 10  # "שלוש עשרה" = 13
                self.teen = True
                self.ones = False
            elif not (self.ones or self.tens or self.teen):
                self.small += 10
                self.teen = True
            else:
                return False
        elif w in _TENS:
            if self.tens or self.ones or self.teen:
                return False
            self.small += _TENS[w]
            self.tens = True
        elif w in _HUNDRED:
            if self.hundreds or self.tens or self.ones or self.teen:
                return False
            self.small += _HUNDRED[w]
            self.hundreds = True
        elif w in _HUNDREDS:
            if not (self.ones and not self.tens and not self.hundreds and not self.teen and self.small >= 3):
                return False
            self.small *= 100
            self.hundreds = True
            self.ones = False
        elif w in _SCALE:
            scale = 10**3 if _SCALE[w] == 2 * 10**3 else _SCALE[w]
            if scale in self.scales_used or any(s < scale for s in self.scales_used):
                return False
            if w == "אלפיים":
                if self.small:
                    return False
                self.total += 2000
            elif w in ("אלפים", "מיליונים", "מיליארדים"):  # plural needs a count: "שלושת אלפים"
                if not self.small:
                    return False
                self.total += self.small * scale
            else:
                self.total += (self.small or 1) * scale
            self.scales_used.add(scale)
            self._reset_small()
        else:
            return False
        self.words += 1
        return True

    @property
    def value(self) -> int | Decimal:
        v = self.total + self.small
        return int(v) if v == int(v) else v


def _numbers_to_digits(tokens: list[str]) -> list[str]:
    """Greedy left to right; O(tokens). A lone plural scale word ("אלפים", thousands of) stays a word."""
    out: list[str] = []
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        before_ten = i + 1 < len(tokens) and tokens[i + 1] in _TEN
        first = _split_prefix(tok, starting=True, before_ten=before_ten)
        if first is None and not _DIGITS.fullmatch(tok):
            out.append(tok)
            i += 1
            continue
        num = _Number()
        if first is None:
            prefix = ""
            num.feed_digits(tok)
        else:
            prefix, word = first
            if not num.feed(word):
                out.append(tok)
                i += 1
                continue
        j = i + 1
        while j < len(tokens):
            nxt = _split_prefix(tokens[j], starting=False, before_ten=j + 1 < len(tokens) and tokens[j + 1] in _TEN)
            if nxt is None or not num.feed(nxt[1]):
                break
            j += 1
        if prefix:
            out.append(prefix)
        out.append(str(num.value) if first is not None or j > i + 1 else tok)
        i = j
    return out


def normalize_he(text: str | None) -> str:
    if not text:
        return ""
    s = unicodedata.normalize("NFKC", text).casefold()  # presentation forms (שׁ as one code point) decompose
    s = unicodedata.normalize("NFD", s)
    s = _POINTS.sub("", s)
    s = unicodedata.normalize("NFC", s)
    s = _HEBREW_PUNCT.sub(" ", s)  # maqaf and friends
    s = _TAG.sub(" ", s)
    s = _GERESH.sub("", s)  # צה״ל = צה"ל = צהל
    for sym, word in _SYMBOLS.items():
        s = s.replace(sym, word)
    s = _GROUPED.sub(lambda m: m.group(0).replace(",", ""), s)
    s = _PUNCT.sub(" ", s)  # hyphen-minus is a maqaf too
    s = _LETTER_DIGIT.sub(" ", s)  # "ב3" -> "ב 3"
    tokens = [w for w in s.split() if w not in FILLERS]
    return " ".join(_FOLD.get(w, w) for w in _numbers_to_digits(tokens))


def lenient_hebrew(normalized: str) -> str:
    """Fold full and defective spelling (שולחן / שלחן): drop ו and י inside a Hebrew word, keeping its first and last
    letter (word-initial ו is "and", final י is "my"). Run on normalize_he output; reported beside strict, never
    instead of it."""
    out = []
    for w in normalized.split():
        if len(w) > 2 and _HEBREW_LETTER.match(w):
            w = w[0] + w[1:-1].replace("ו", "").replace("י", "") + w[-1]
        out.append(w)
    return " ".join(out)
