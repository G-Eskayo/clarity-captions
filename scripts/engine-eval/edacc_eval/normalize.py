"""One English text normalizer for the reference and every engine (#145).

Choices are documented in docs/perf/engine-accuracy-design.md ("Scoring"). The same function runs on both sides,
so any residual quirk costs every engine equally.
"""
from __future__ import annotations

import re
import unicodedata

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


def normalize(text: str | None) -> str:
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
