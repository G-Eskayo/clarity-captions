"""Adversarial tests for the one text normalizer every engine and the reference go through (#145)."""
from edacc_eval.normalize import normalize, number_to_words


def test_case_and_punctuation():
    assert normalize("Hello, World!  How's it going?") == "hello world how's it going".replace("'", "")


def test_reference_and_engine_forms_meet():
    ref = "OKAY I THINK IT'S RECORDING RIGHT"
    hyp = "Ok, I think it's recording, right?"
    assert normalize(ref) == normalize(hyp)


def test_empty_and_whitespace_only():
    assert normalize("") == ""
    assert normalize("   \n\t ") == ""


def test_none_is_empty():
    assert normalize(None) == ""


def test_edacc_tags_removed():
    assert normalize("<LAUGH> YEAH <OVERLAP> THAT'S RIGHT <NO-SPEECH>") == "yeah thats right"


def test_tag_only_reference_is_empty():
    assert normalize("<DTMF>") == ""
    assert normalize("<NO-SPEECH> <BREATH>") == ""


def test_ignore_marker_is_empty():
    assert normalize("IGNORE_TIME_SEGMENT_IN_SCORING") == ""


def test_engine_nonspeech_markers_removed():
    assert normalize("[Music] hello (laughs) there [BLANK_AUDIO]") == "hello there"


def test_fillers_removed_both_sides():
    assert normalize("UM I UH THINK HMM MM SO") == "i think so"
    assert normalize("Um, I, uh, think. Hmm. Mm. So.") == "i think so"


def test_meaningful_interjections_kept():
    assert normalize("OH YEAH AH OKAY") == "oh yeah ah okay"


def test_numbers_digits_vs_words():
    assert normalize("I have 3 kids") == normalize("I HAVE THREE KIDS")
    assert normalize("twenty-one") == normalize("21") == "twenty one"
    assert normalize("C14-P1") == "c fourteen p one"


def test_large_and_decimal_numbers():
    assert normalize("1,250") == "one thousand two hundred fifty"
    assert normalize("3.5") == "three point five"
    assert normalize("2005") == "two thousand five"
    assert normalize("1990") == "nineteen ninety"
    assert normalize("1905") == "nineteen oh five"
    assert normalize("1900") == "nineteen hundred"


def test_ordinals():
    assert normalize("the 1st and 22nd") == "the first and twenty second"
    assert normalize("3rd 4th 11th 100th") == "third fourth eleventh one hundredth"


def test_currency_and_percent():
    assert normalize("$5") == "five dollars"
    assert normalize("£20") == "twenty pounds"
    assert normalize("50%") == "fifty percent"
    assert normalize("rock & roll") == "rock and roll"


def test_number_to_words_edges():
    assert number_to_words(0) == "zero"
    assert number_to_words(100) == "one hundred"
    assert number_to_words(1_000_000) == "one million"
    assert number_to_words(999_999_999_999) .startswith("nine hundred ninety nine billion")


def test_contractions_expanded_unambiguous_only():
    assert normalize("I don't know, they're here, we've gone, I'll go, I'm fine") == \
        "i do not know they are here we have gone i will go i am fine"
    assert normalize("can't won't cannot") == "can not will not can not"
    # 's and 'd are ambiguous: kept (then apostrophes dropped on both sides)
    assert normalize("it's") == normalize("IT'S") == "its"
    assert normalize("I'd") == "id"


def test_curly_apostrophes():
    assert normalize("don’t") == "do not"


def test_unicode_diacritics_stripped():
    assert normalize("Hạ LONG CAFé") == "ha long cafe"
    assert normalize("Café") == "cafe"
    assert normalize("BRüNNHILDE") == "brunnhilde"


def test_spelling_variants():
    assert normalize("colour favourite theatre realise") == normalize("color favorite theater realize")
    assert normalize("alright") == "all right"


def test_numbers_glued_to_letters_and_units():
    assert normalize("5pm") == "five pm"
    assert normalize("covid19") == "covid nineteen"


def test_idempotent():
    s = "Um, I've got 22 cats & 1.5 dogs [Music] <LAUGH>"
    assert normalize(normalize(s)) == normalize(s)
