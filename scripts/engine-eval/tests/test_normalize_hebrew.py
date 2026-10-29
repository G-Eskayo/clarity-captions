"""Adversarial tests for the Hebrew normalizer (#202). Each rule with real Hebrew pairs; the same function runs on the
reference and on every engine, so a pair that should match must normalize to the same string, and a real error must
still differ."""
import pytest

from edacc_eval.normalize import LANGUAGES, lenient_hebrew, normalize
from edacc_eval.wer import align_counts, char_counts


def he(text):
    return normalize(text, "he")


def test_hebrew_is_a_known_language():
    assert "he" in LANGUAGES


def test_empty_none_and_punctuation_only():
    assert he("") == "" and he(None) == "" and he(" ?!, ... ") == ""


# --- NFC ----------------------------------------------------------------------------------------------------------

def test_nfc_composed_and_decomposed_presentation_forms_match():
    # U+FB2A (shin with shin dot, one code point) vs shin + U+05C1; both are שׁ, and the dot is niqqud anyway.
    assert he("שׁלום") == he("שׁלום") == he("שלום") == "שלום"


# --- Niqqud and cantillation --------------------------------------------------------------------------------------

def test_niqqud_stripped():
    assert he("שָׁלוֹם עֲלֵיכֶם") == he("שלום עליכם") == "שלום עליכם"


def test_cantillation_stripped():
    # Genesis 1:1 with te'amim (etnahta U+0591, tipcha U+0596, sof pasuq U+05C3 is punctuation).
    assert he("בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים׃") == "בראשית ברא אלהים"


def test_dagesh_and_rafe_and_meteg_stripped():
    assert he("בּ") == he("ב") and he("כֿ") == he("כ") and he("הָֽאָרֶץ") == "הארץ"


# --- Maqaf --------------------------------------------------------------------------------------------------------

def test_maqaf_and_hyphen_are_spaces():
    assert he("בית־ספר") == he("בית-ספר") == he("בית ספר") == "בית ספר"


def test_maqaf_inside_niqqud_text():
    assert he("כָּל־הָעָם") == "כל העם"


# --- Geresh and gershayim -----------------------------------------------------------------------------------------

@pytest.mark.parametrize("variant", ["צה״ל", 'צה"ל', "צה''ל", "צה”ל", "צהל"])
def test_gershayim_unified_then_dropped(variant):
    assert he(variant) == "צהל"


@pytest.mark.parametrize("variant", ["ג׳ירפה", "ג'ירפה", "ג`ירפה", "ג’ירפה"])
def test_geresh_unified_then_dropped(variant):
    assert he(variant) == "גירפה"


def test_quotation_marks_around_words_are_dropped_too():
    assert he('הוא אמר "שלום" ו׳להתראות׳') == "הוא אמר שלום ולהתראות"


# --- Final letters are spelling, not error ------------------------------------------------------------------------

def test_final_letter_forms_kept_as_written():
    assert he("שלום") != he("שלומ")


# --- Numbers to one form ------------------------------------------------------------------------------------------

@pytest.mark.parametrize("words,digits", [
    ("חמש", "5"), ("חמישה", "5"), ("אפס", "0"), ("אחת", "1"), ("אחד", "1"), ("שתיים", "2"), ("שניים", "2"),
    ("עשר", "10"), ("עשרה", "10"),
    ("שלוש עשרה", "13"), ("שלושה עשר", "13"), ("אחת עשרה", "11"), ("שתים עשרה", "12"), ("שנים עשר", "12"),
    ("עשרים", "20"), ("עשרים ושלוש", "23"), ("ארבעים ושניים", "42"), ("תשעים ותשע", "99"),
    ("מאה", "100"), ("מאתיים", "200"), ("שלוש מאות", "300"), ("מאה עשרים וחמש", "125"), ("מאה ואחת", "101"),
    ("אלף", "1000"), ("אלפיים", "2000"), ("שלושת אלפים", "3000"), ("עשרת אלפים", "10000"),
    ("אלף תשע מאות ושמונים", "1980"), ("אלפיים ועשרים וארבע", "2024"), ("שני מיליון", "2000000"),
])
def test_number_words_become_digits(words, digits):
    assert he(words) == digits
    assert he(digits) == digits


def test_five_pair_from_the_ticket():
    assert he("יש לי 5 ילדים") == he("יש לי חמישה ילדים") == "יש לי 5 ילדים"


def test_number_words_with_niqqud_still_read():
    assert he("חָמֵשׁ") == "5"


def test_thousands_separator_and_decimals():
    assert he("1,000") == he("1000") == he("אלף") == "1000"
    assert he("3.5") == "3.5"  # a decimal stays one token, the same on both sides


def test_prefixed_number_word_and_prefixed_digit_match():
    # "in 3" written three ways: glued prefix + word, prefix + maqaf + digit, prefix glued to digit.
    assert he("בשלוש") == he("ב-3") == he("ב3") == "ב 3"
    assert he("ועשרים") == he("ו-20") == "ו 20"


def test_ordinary_words_that_contain_number_letters_are_left_alone():
    # Whole-word matches only: "שבוע" (week), "עשרות" (dozens), "מאוד" (very), "בשבוע" are words, not numbers.
    assert he("שבוע") == "שבוע" and he("עשרות") == "עשרות" and he("מאוד") == "מאוד"
    assert he("בשבוע הבא") == "בשבוע הבא"
    # A prefix letter only splits off when the rest is a number word.
    assert he("שמונה") == "8" and he("לשמונה") == "ל 8"
    assert he("הם עשו") == "הם עשו"


def test_percent_sign_and_word_match():
    assert he("5%") == he("חמישה אחוזים") == he("5 אחוז") == "5 אחוז"


def test_a_wrong_number_is_still_an_error():
    assert he("חמש") != he("שש")


# --- Fillers ------------------------------------------------------------------------------------------------------

def test_fillers_dropped():
    assert he("אה אז אממ הלכנו הממ") == he("אז הלכנו") == "אז הלכנו"


def test_engine_markers_dropped():
    assert he("<laugh> [מוזיקה] שלום") == "שלום"


# --- Latin text inside Hebrew -------------------------------------------------------------------------------------

def test_latin_words_are_casefolded():
    assert he("עבדתי ב-Google") == he("עבדתי ב google") == "עבדתי ב google"


# --- English and the other languages are untouched ----------------------------------------------------------------

def test_english_unchanged():
    assert normalize("OKAY 5%", "en") == normalize("OKAY 5%") == "okay five percent"


# --- Lenient score: full and defective spelling fold together -----------------------------------------------------

@pytest.mark.parametrize("full,defective", [
    ("שולחן", "שלחן"), ("תוכנית", "תכנית"), ("מיוחד", "מיחד"), ("תקווה", "תקוה"), ("קרייה", "קריה"),
    ("אומנם", "אמנם"),
])
def test_lenient_folds_full_and_defective(full, defective):
    assert he(full) != he(defective)  # strict counts it
    assert lenient_hebrew(he(full)) == lenient_hebrew(he(defective))


def test_lenient_keeps_word_initial_vav_and_final_yod():
    # ו at the start is "and"; final י is "my": both change meaning and stay errors.
    assert lenient_hebrew("ושלום") != lenient_hebrew("שלום")
    assert lenient_hebrew("ילדי") != lenient_hebrew("ילד")


def test_lenient_leaves_digits_and_latin_alone():
    assert lenient_hebrew("5 google") == "5 google"


# --- CER beside WER -----------------------------------------------------------------------------------------------

def test_cer_charges_one_prefix_letter_not_a_whole_word():
    ref, hyp = he("ובבית הספר"), he("בבית הספר")
    assert align_counts(ref, hyp).errors == 1  # WER: the whole fused word is wrong
    c = char_counts(ref, hyp)
    assert c.errors == 1 and c.n == len("ובבית הספר")


def test_cer_identical_and_empty():
    assert char_counts("שלום", "שלום").errors == 0
    assert char_counts("", "").n == 0
    c = char_counts("אב", "")
    assert c.dele == 2 and c.n == 2


def test_cer_ignores_repeated_spaces():
    assert char_counts("א  ב", "א ב").errors == 0


def test_decimal_before_a_scale_word_is_one_number():
    assert he("2.5 מיליון") == he("2,500,000") == he("2500000") == "2500000"
    assert he("1.1 מיליון") == "1100000" and he("1.25 אלף") == "1250"
    assert he("5 אלף") == he("חמשת אלפים") == "5000"


def test_hundred_years_is_not_102():
    # "שנים" is "years" unless עשר/עשרה follows; "מאה שנים" and "100 שנים" must read the same.
    assert he("מאה שנים") == he("100 שנים") == "100 שנים"
    assert he("לפני שלוש שנים") == "לפני 3 שנים"


def test_bidi_marks_are_removed_not_turned_into_spaces():
    # Apple's DictationTranscriber starts its Hebrew text with U+200F (right-to-left mark).
    assert he("‏שלום") == he("של‏ום") == he("‫שלום‬") == he("⁧שלום⁩") == "שלום"
    assert he("﻿שלום") == "שלום"


def test_usa_abbreviation_reads_as_it_is_said():
    # FLEURS writes ארה"ב; every engine writes what is said, ארצות הברית.
    assert he('ארה"ב') == he("ארה״ב") == he("ארצות הברית") == "ארצות הברית"
    assert he('בארה"ב') == he("בארצות הברית") == "בארצות הברית"
