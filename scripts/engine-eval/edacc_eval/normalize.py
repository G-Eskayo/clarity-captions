"""Text normalizer for the reference and every engine: English (#145) and Spanish, French, German (#158).

Choices are documented in docs/perf/engine-accuracy-design.md and docs/perf/language-accuracy-design.md ("Scoring").
The same function runs on both sides, so any residual quirk costs every engine equally.
"""
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass

_ONES = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
         "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
_TENS = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
_SCALES = [(10**12, "trillion"), (10**9, "billion"), (10**6, "million"), (1000, "thousand")]
_ORDINAL_IRREGULAR = {"one": "first", "two": "second", "three": "third", "five": "fifth", "eight": "eighth",
                      "nine": "ninth", "twelve": "twelfth"}

FILLERS = frozenset("um umm uh uhh uhm er erm hm hmm hmmm mm mmm mhm mhmm".split())

# Applied after lowercasing and before contraction handling (apostrophes still present).
_CONTRACTIONS = [
    (re.compile(r"\bcan'?t\b"), "can not"),
    (re.compile(r"\bcannot\b"), "can not"),
    (re.compile(r"\bwon'?t\b"), "will not"),
    (re.compile(r"\bshan't\b"), "shall not"),
    (re.compile(r"\bain't\b"), "aint"),
    (re.compile(r"(\w)n't\b"), r"\1 not"),
    (re.compile(r"(\w)'re\b"), r"\1 are"),
    (re.compile(r"(\w)'ve\b"), r"\1 have"),
    (re.compile(r"(\w)'ll\b"), r"\1 will"),
    (re.compile(r"\bi'm\b"), "i am"),
]

# Spelling and form variants -> one form (US spelling, the form Apple's en-US model writes).
_VARIANTS = {
    "ok": "okay", "alright": "all right",
    "colour": "color", "colours": "colors", "favour": "favor", "favourite": "favorite", "favourites": "favorites",
    "flavour": "flavor", "flavours": "flavors", "honour": "honor", "humour": "humor", "labour": "labor",
    "neighbour": "neighbor", "neighbours": "neighbors", "neighbourhood": "neighborhood", "behaviour": "behavior",
    "rumour": "rumor", "harbour": "harbor", "glamour": "glamor", "glamouring": "glamoring",
    "theatre": "theater", "theatres": "theaters", "centre": "center", "centres": "centers", "metre": "meter",
    "metres": "meters", "litre": "liter", "litres": "liters", "kilometre": "kilometer", "kilometres": "kilometers",
    "realise": "realize", "realised": "realized", "realising": "realizing", "organise": "organize",
    "organised": "organized", "organising": "organizing", "organisation": "organization",
    "recognise": "recognize", "recognised": "recognized", "apologise": "apologize", "apologised": "apologized",
    "analyse": "analyze", "analysed": "analyzed", "criticise": "criticize", "memorise": "memorize",
    "specialise": "specialize", "specialised": "specialized", "emphasise": "emphasize",
    "programme": "program", "programmes": "programs", "travelled": "traveled", "travelling": "traveling",
    "cancelled": "canceled", "cancelling": "canceling", "grey": "gray", "mum": "mom", "mums": "moms",
    "practise": "practice", "defence": "defense", "licence": "license", "catalogue": "catalog",
    "dialogue": "dialog", "jewellery": "jewelry", "cheque": "check", "tyre": "tire", "tyres": "tires",
    "aeroplane": "airplane", "mr": "mister", "mrs": "missus", "dr": "doctor",
}

_CURRENCY = {"$": "dollars", "£": "pounds", "€": "euros"}

_TAG = re.compile(r"<[^>]*>")
_BRACKETED = re.compile(r"\[[^\]]*\]|\([^)]*\)|\{[^}]*\}")
_CURRENCY_AMOUNT = re.compile(r"([$£€])\s?(\d[\d,]*(?:\.\d+)?)")
_PERCENT = re.compile(r"(\d)\s?%")
_ORDINAL = re.compile(r"\b(\d+)(st|nd|rd|th)\b")
_GROUPED = re.compile(r"\b\d{1,3}(?:,\d{3})+(?:\.\d+)?\b")
_DECIMAL = re.compile(r"\b(\d+)\.(\d+)\b")
_LETTER_DIGIT = re.compile(r"(?<=[a-z])(?=\d)|(?<=\d)(?=[a-z])")
_INTEGER = re.compile(r"\d+")


def number_to_words(n: int) -> str:
    if n < 0:
        return "minus " + number_to_words(-n)
    if n < 20:
        return _ONES[n]
    if n < 100:
        tens, ones = divmod(n, 10)
        return _TENS[tens] + ("" if ones == 0 else " " + _ONES[ones])
    if n < 1000:
        hundreds, rest = divmod(n, 100)
        return _ONES[hundreds] + " hundred" + ("" if rest == 0 else " " + number_to_words(rest))
    for value, name in _SCALES:
        if n >= value:
            head, rest = divmod(n, value)
            return number_to_words(head) + " " + name + ("" if rest == 0 else " " + number_to_words(rest))
    raise AssertionError("unreachable")


def _integer_words(digits: str) -> str:
    n = int(digits)
    if len(digits) == 4 and 1100 <= n <= 1999:  # read as a year: "nineteen ninety", "nineteen oh five"
        hi, lo = divmod(n, 100)
        if lo == 0:
            return number_to_words(hi) + " hundred"
        return number_to_words(hi) + " " + ("oh " + _ONES[lo] if lo < 10 else number_to_words(lo))
    if len(digits) > 1 and digits.startswith("0"):  # "007", phone-like: digit by digit
        return " ".join(_ONES[int(d)] for d in digits)
    return number_to_words(n)


def _ordinal_words(n: int) -> str:
    words = number_to_words(n).split()
    last = words[-1]
    if last in _ORDINAL_IRREGULAR:
        words[-1] = _ORDINAL_IRREGULAR[last]
    elif last.endswith("y"):
        words[-1] = last[:-1] + "ieth"
    else:
        words[-1] = last + "th"
    return " ".join(words)


def _grouped_words(m: re.Match) -> str:
    """'1,250' is a quantity, never a year; '1,250.5' keeps its decimal part for the decimal rule."""
    whole, _, frac = m.group(0).replace(",", "").partition(".")
    return " " + number_to_words(int(whole)) + (" point " + " ".join(_ONES[int(d)] for d in frac) if frac else "") + " "


def _strip_diacritics(text: str) -> str:
    decomposed = unicodedata.normalize("NFKD", text)
    return "".join(ch for ch in decomposed if not unicodedata.combining(ch)).replace("đ", "d").replace("ı", "i")


def _normalize_en(text: str | None) -> str:
    if not text:
        return ""
    s = unicodedata.normalize("NFKC", text).casefold()
    s = s.replace("ignore_time_segment_in_scoring", " ")
    s = _TAG.sub(" ", s)
    s = _BRACKETED.sub(" ", s)
    s = _strip_diacritics(s)
    s = s.replace("’", "'").replace("‘", "'").replace("`", "'")
    s = s.replace("&", " and ")
    s = _CURRENCY_AMOUNT.sub(lambda m: f" {m.group(2).replace(',', '')} {_CURRENCY[m.group(1)]} ", s)
    s = _GROUPED.sub(_grouped_words, s)
    s = _PERCENT.sub(r"\1 percent", s)
    s = _ORDINAL.sub(lambda m: " " + _ordinal_words(int(m.group(1))) + " ", s)
    s = _DECIMAL.sub(lambda m: f" {_integer_words(m.group(1))} point "
                     + " ".join(_ONES[int(d)] for d in m.group(2)) + " ", s)
    s = _LETTER_DIGIT.sub(" ", s)
    s = _INTEGER.sub(lambda m: " " + _integer_words(m.group(0)) + " ", s)
    for pattern, repl in _CONTRACTIONS:
        s = pattern.sub(repl, s)
    s = s.replace("'", "")
    s = re.sub(r"[^a-z0-9 ]+", " ", s)
    words = []
    for w in s.split():
        if w in FILLERS:
            continue
        words.extend(_VARIANTS.get(w, w).split())
    return " ".join(words)


# --- Spanish, French, German (#158) ----------------------------------------------------------------------------

@dataclass(frozen=True)
class _Lang:
    comma: str
    percent: str
    currency: dict
    fillers: frozenset
    space_thousands: bool = False


_LANGS = {
    "es": _Lang("coma", "por ciento", {"€": "euros", "$": "dólares", "£": "libras"},
                frozenset("eh ehm em mm mmm hmm".split())),
    "fr": _Lang("virgule", "pour cent", {"€": "euros", "$": "dollars", "£": "livres"},
                frozenset("euh heu hum mm mmm hmm".split()), space_thousands=True),
    "de": _Lang("komma", "prozent", {"€": "euro", "$": "dollar", "£": "pfund"},
                frozenset("äh ähm öh öhm hm hmm mm mmm".split())),
}
LANGUAGES = ("en",) + tuple(_LANGS)

_ES_ORDINAL = re.compile(r"\b(\d+)\.?\s?([º°ª])")
_FR_ORDINAL = re.compile(r"\b(\d+)(ère|ere|er|re|ème|eme|e)\b", re.IGNORECASE)
_FR_ROMAN_ORDINAL = re.compile(r"\b([IVXLCDM]+)(ère|er|re|ème|e)\b")
_ROMAN = {"I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000}
_NUM = r"\d[\d., ]*\d|\d"
_CUR_BEFORE = re.compile(r"([$€£])\s?(" + _NUM + r")")
_CUR_AFTER = re.compile(r"(" + _NUM + r")\s?([$€£])")
_PCT = re.compile(r"(\d)\s?%")
_DOT_COMMA_GROUPS = re.compile(r"\b\d{1,3}(?:([.,])\d{3})(?:\1\d{3})*\b")
_SPACE_GROUPS = re.compile(r"\b\d{1,3}(?: \d{3})+\b")
_ANY_DECIMAL = re.compile(r"\b(\d+)[.,](\d+)\b")


def strip_accents(text: str) -> str:
    """Accent-blind form for the secondary WER: diacritics removed, everything else as is."""
    return unicodedata.normalize("NFC", "".join(ch for ch in unicodedata.normalize("NFKD", text)
                                                 if not unicodedata.combining(ch)))


def _words(n: int, lang: str, to: str = "cardinal") -> str:
    from num2words import num2words
    try:
        return " " + num2words(n, lang=lang, to=to).casefold() + " "
    except (OverflowError, NotImplementedError, ValueError):
        return " " + " ".join(num2words(int(d), lang=lang) for d in str(n)) + " "


def _roman_value(s: str) -> int | None:
    total = 0
    for i, ch in enumerate(s):
        v = _ROMAN[ch]
        total += -v if i + 1 < len(s) and _ROMAN[s[i + 1]] > v else v
    return total if total > 0 and _to_roman(total) == s else None


def _to_roman(n: int) -> str:
    out = ""
    for v, sym in [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"), (50, "L"),
                   (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]:
        while n >= v:
            out += sym
            n -= v
    return out


def _fr_ordinal(n: int, suffix: str) -> str:
    if n == 1:
        return " première " if suffix.lower() in ("re", "ère", "ere") else " premier "
    return _words(n, "fr", "ordinal")


def _fr_roman(m: re.Match) -> str:
    numeral, suffix = m.group(1), m.group(2)
    n = _roman_value(numeral)
    if n is None or (len(numeral) == 1 and not (numeral == "I" and suffix == "er")):  # "Ce", "Le", "Me" are words
        return m.group(0)
    return _fr_ordinal(n, suffix)


def _es_ordinal(m: re.Match) -> str:
    w = _words(int(m.group(1)), "es", "ordinal").strip()
    if m.group(2) == "ª" and w.endswith("o"):
        w = w[:-1] + "a"
    return f" {w} "


def _int_words(digits: str, lang: str) -> str:
    if len(digits) > 1 and digits.startswith("0"):
        return " " + " ".join(_words(int(d), lang).strip() for d in digits) + " "
    n = int(digits)
    if lang == "de" and len(digits) == 4 and 1100 <= n <= 1999:
        return _words(n, lang, "year")
    return _words(n, lang)


def _decimal_words(m: re.Match, lang: str) -> str:
    whole, frac = m.group(1), m.group(2)
    if lang == "de" or frac.startswith("0"):
        frac_words = " ".join(_words(int(d), lang).strip() for d in frac)
    else:
        frac_words = _words(int(frac), lang).strip()
    return f"{_int_words(whole, lang)} {_LANGS[lang].comma} {frac_words} "


def _normalize_lang(text: str | None, lang: str) -> str:
    if not text:
        return ""
    cfg = _LANGS[lang]
    s = unicodedata.normalize("NFC", text)
    if lang == "es":
        s = _ES_ORDINAL.sub(_es_ordinal, s)  # before NFKC, which turns º/ª into o/a
    if lang == "fr":
        s = _FR_ROMAN_ORDINAL.sub(_fr_roman, s)  # case-sensitive: needs the capitals
        s = _FR_ORDINAL.sub(lambda m: _fr_ordinal(int(m.group(1)), m.group(2)), s)
    s = unicodedata.normalize("NFKC", s).casefold()  # no-break spaces become spaces; ß -> ss
    s = _TAG.sub(" ", s)
    s = _BRACKETED.sub(" ", s)
    s = _CUR_BEFORE.sub(lambda m: f" {m.group(2)} {cfg.currency[m.group(1)]} ", s)
    s = _CUR_AFTER.sub(lambda m: f" {m.group(1)} {cfg.currency[m.group(2)]} ", s)
    s = _PCT.sub(lambda m: f"{m.group(1)} {cfg.percent} ", s)
    if cfg.space_thousands:
        s = _SPACE_GROUPS.sub(lambda m: m.group(0).replace(" ", ""), s)
    s = _DOT_COMMA_GROUPS.sub(lambda m: m.group(0).replace(m.group(1), ""), s)
    s = _ANY_DECIMAL.sub(lambda m: _decimal_words(m, lang), s)
    s = _LETTER_DIGIT_ANY.sub(" ", s)
    s = _INTEGER.sub(lambda m: _int_words(m.group(0), lang), s)
    s = re.sub(r"[\W_]+", " ", s)
    return " ".join(w for w in s.split() if w not in cfg.fillers)


_LETTER_DIGIT_ANY = re.compile(r"(?<=[^\W\d_])(?=\d)|(?<=\d)(?=[^\W\d_])")


def normalize(text: str | None, language: str | None = None) -> str:
    """English (language None or "en") is #145's normalizer, unchanged; "es", "fr", "de" use the #158 rules."""
    if language in (None, "en"):
        return _normalize_en(text)
    if language not in _LANGS:
        raise ValueError(f"no normalizer for language {language!r}; have {', '.join(LANGUAGES)}")
    return _normalize_lang(text, language)
