"""Adversarial tests for the Spanish, French and German normalizer (#158). English must stay exactly #145's."""
import pytest

from edacc_eval.normalize import normalize, strip_accents


# --- English is untouched -------------------------------------------------------------------------------------

@pytest.mark.parametrize("text", ["OKAY I THINK IT'S 1990, RIGHT?", "Café 3.5% of £20", "<LAUGH> yeah mm"])
def test_english_default_and_explicit_en_are_identical(text):
    assert normalize(text) == normalize(text, "en") == normalize(text, None)


def test_unknown_language_is_refused():
    with pytest.raises(ValueError):
        normalize("hola", "xx")


# --- Shared rules ----------------------------------------------------------------------------------------------

@pytest.mark.parametrize("lang", ["es", "fr", "de"])
def test_empty_and_none(lang):
    assert normalize("", lang) == "" and normalize(None, lang) == "" and normalize("  ¿?  ", lang) == ""


@pytest.mark.parametrize("lang", ["es", "fr", "de"])
def test_tags_and_square_bracket_markers_dropped(lang):
    assert normalize("<noise> [Música] hola", lang) == "hola"


@pytest.mark.parametrize("lang", ["es", "fr", "de"])
def test_parenthesised_words_are_spoken_in_fleurs_and_kept(lang):
    # FLEURS reads Wikipedia sentences aloud, brackets included: "(al otro lado del río)" is said.
    assert normalize("la estación (al otro lado del río) abre", lang) == "la estación al otro lado del río abre"


@pytest.mark.parametrize("lang", ["es", "fr", "de"])
def test_space_thousands_in_every_language(lang):
    # FLEURS Spanish writes "800 000"; Apple writes "800,000"; both are one number.
    assert normalize("800 000", lang) == normalize("800,000", lang) == normalize("800000", lang)
    assert "cero" not in normalize("800 000", "es")


def test_clock_times():
    assert normalize("a las 12:00", "es") == "a las doce"
    assert normalize("entre las 6:30 y las 07:30", "es") == "entre las seis treinta y las siete treinta"
    assert normalize("um 22:00 Uhr", "de") == "um zweiundzwanzig uhr"
    assert normalize("à 11:35", "fr") == "à onze trente cinq"


def test_accents_kept_by_default():
    assert normalize("Está aquí", "es") == "está aquí"
    assert normalize("está", "es") != normalize("esta", "es")


def test_accent_blind_variant_merges_accent_only_differences():
    assert strip_accents(normalize("Está aquí", "es")) == strip_accents(normalize("esta aqui", "es")) == "esta aqui"
    assert strip_accents("où ça") == "ou ca"


def test_nfkc_and_combining_forms_compare_equal():
    composed = "canción"
    decomposed = "canción"
    assert normalize(composed, "es") == normalize(decomposed, "es")


# --- Spanish ---------------------------------------------------------------------------------------------------

def test_spanish_inverted_marks_and_case():
    assert normalize("¿Cierto? ¡Sí!", "es") == "cierto sí"


def test_spanish_reference_and_engine_meet():
    ref = "Esto parece tener sentido, ya que en la Tierra no se percibe su movimiento, ¿cierto?"
    hyp = "esto parece tener sentido ya que en la tierra no se percibe su movimiento cierto"
    assert normalize(ref, "es") == normalize(hyp, "es")


def test_spanish_numbers():
    assert normalize("21 años", "es") == "veintiuno años"
    assert normalize("en 1990", "es") == "en mil novecientos noventa"
    assert normalize("1.000 personas", "es") == normalize("1,000 personas", "es") == "mil personas"
    assert normalize("el 15%", "es") == "el quince por ciento"
    assert normalize("3,5", "es") == "tres coma cinco"


def test_spanish_ordinals():
    assert normalize("el 1.º lugar", "es") == normalize("el 1º lugar", "es") == "el primero lugar"
    assert normalize("la 2.ª vez", "es") == "la segunda vez"


def test_spanish_fillers():
    assert normalize("eh bueno ehm sí", "es") == "bueno sí"


# --- French ----------------------------------------------------------------------------------------------------

def test_french_elision_and_hyphen_split():
    assert normalize("L'homme est-il là ?", "fr") == "l homme est il là"
    assert normalize("l’homme", "fr") == normalize("l'homme", "fr")


def test_french_numbers_hyphenated_words_split_both_sides():
    assert normalize("90", "fr") == normalize("quatre-vingt-dix", "fr") == "quatre vingt dix"
    assert normalize("21", "fr") == "vingt et un"


def test_french_thousands_with_spaces():
    for sep in [" ", " ", " "]:
        assert normalize(f"1{sep}000 euros", "fr") == "mille euros"


def test_french_ordinals_and_roman_centuries():
    assert normalize("le 1er jour", "fr") == "le premier jour"
    assert normalize("la 2e fois", "fr") == normalize("la 2ème fois", "fr") == "la deuxième fois"
    assert normalize("au XIXe siècle", "fr") == "au dix neuvième siècle"


def test_french_percent_decimal_and_guillemets():
    assert normalize("« 3,5 % »", "fr") == "trois virgule cinq pour cent"


def test_french_fillers():
    assert normalize("euh je pense hum oui", "fr") == "je pense oui"


def test_french_letters_in_words_not_mistaken_for_roman_numerals():
    assert normalize("Il dit merci", "fr") == "il dit merci"
    assert normalize("vice", "fr") == "vice"


# --- German ----------------------------------------------------------------------------------------------------

def test_german_sharp_s_and_old_spelling():
    assert normalize("Straße", "de") == normalize("Strasse", "de") == "strasse"
    assert normalize("daß", "de") == normalize("dass", "de")


def test_german_years_and_cardinals():
    assert normalize("1990", "de") == "neunzehnhundertneunzig"
    assert normalize("2005", "de") == "zweitausendfünf"
    assert normalize("21 Jahre", "de") == "einundzwanzig jahre"


def test_german_thousands_decimal_percent():
    assert normalize("1.000.000", "de") == "eine million"
    assert normalize("2,5 %", "de") == "zwei komma fünf prozent"


def test_german_ordinal_dot_left_alone_as_cardinal():
    # "am 3. Mai" can't be told from a sentence-ending "3."; it reads as a cardinal on both sides.
    assert normalize("am 3. Mai", "de") == "am drei mai"


def test_german_umlauts_kept_fillers_dropped():
    assert normalize("Äh, schön ähm", "de") == "schön"


def test_currency_words_per_language():
    assert normalize("20 €", "de") == normalize("€20", "de") == "zwanzig euro"
    assert normalize("20 €", "es") == "veinte euros"
    assert normalize("$5", "fr") == "cinq dollars"


def test_letters_glued_to_digits_split():
    assert normalize("A4", "de") == "a vier"


def test_french_capitalised_words_that_look_like_roman_ordinals_survive():
    assert normalize("Ce livre. Le chat. Me voici. Mme Dupont", "fr") == "ce livre le chat me voici mme dupont"
    assert normalize("François Ier", "fr") == "françois premier"
    assert normalize("Louis XIV", "fr") == "louis xiv"  # bare Roman numerals stay as written (documented residual)


def test_invalid_roman_sequence_left_alone():
    assert normalize("IIIIe", "fr") == "iiiie"


def test_dates_and_lists_do_not_merge_into_one_number():
    assert normalize("el 11.09.2001", "es").split()[:2] == ["el", "once"]
    assert normalize("1990, 2000", "es") == "mil novecientos noventa dos mil"


def test_huge_number_falls_back_to_digits_never_crashes():
    out = normalize("9" * 40, "de")
    assert out and "9" not in out


def test_decimals_per_language():
    assert normalize("3,25", "es") == "tres coma veinticinco"
    assert normalize("3,25", "de") == "drei komma zwei fünf"
    assert normalize("0,05", "fr") == "zéro virgule zéro cinq"


def test_letters_glued_to_decimals_split_before_number_reading():
    assert normalize("802.11a", "es") == normalize("802.11 a", "es") == normalize("802.11 A", "es")
    assert normalize("2.4Ghz", "es") == normalize("2.4 GHz", "es")


def test_spanish_double_accepted_spellings_meet():
    # The RAE accepts both "período" and "periodo"; neither is a caption error.
    assert normalize("el período", "es") == normalize("el periodo", "es")
    assert normalize("los períodos", "es") == normalize("los periodos", "es")
    assert normalize("está", "es") != normalize("esta", "es")  # real accent errors still count
