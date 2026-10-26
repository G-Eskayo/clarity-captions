"""Sentence splitting before a sentence-level model (#159): Marian drops sentences from long passages."""
from translation_eval.split import split_sentences, translate_split


def test_splits_on_sentence_end_followed_by_capital():
    assert split_sentences("Cheers, y'all. Now check it out! You know what I mean? So look.") == \
        ["Cheers, y'all.", "Now check it out!", "You know what I mean?", "So look."]


def test_keeps_decimals_abbreviation_like_lowercase_and_unpunctuated_text_whole():
    assert split_sentences("It costs 3.5 dollars. e.g. this one") == ["It costs 3.5 dollars. e.g. this one"]
    assert split_sentences("so look this is what i'm fixin to do you guys") == \
        ["so look this is what i'm fixin to do you guys"]


def test_closing_quotes_stay_with_their_sentence():
    assert split_sentences('He said "stop." Then he left.') == ['He said "stop."', "Then he left."]


def test_empty_and_whitespace():
    assert split_sentences("") == [] and split_sentences("   ") == []


def test_translate_split_rejoins_in_order_and_batches_once():
    calls = []

    def batch(lines):
        calls.append(list(lines))
        return [f"<{l}>" for l in lines]

    out = translate_split(["One. Two.", "Three", ""], batch)
    assert out == ["<One.> <Two.>", "<Three>", ""]
    assert calls == [["One.", "Two.", "Three"]]
