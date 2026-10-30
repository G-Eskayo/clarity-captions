#!/usr/bin/env python3
"""#208: the Bangor Miami corpus (real recorded Spanish-English conversations with code-switching) as JSON for the
face-to-face threshold comparison (FaceToFaceCodeSwitchingEvalTests).

Input: the CHAT files from https://bangortalk.org.uk/downloads/miami_chats.tar.gz (GPL v3, BangorTalk). They are
test data only: never committed, never shipped. Output: one JSON file, a list of conversations, each a list of
utterances {speaker, start, end, words: [[text, lang]]} with lang "en", "es" or "?" (undetermined), times in seconds.

Usage: miami_to_json.py <dir with *.cha> <out.json>
"""
import json
import os
import re
import sys

TIME = re.compile(r"\x15?(\d+)_(\d+)\x15?\s*$")
# CHAT codes that aren't words: [/] [//] [- spa] [=! laughs] (.) +/. +, &fragments xxx www 0 etc.
BRACKETS = re.compile(r"\[[^\]]*\]|<|>|\([.\d:]*\)")


def lang_of(token, head):
    m = re.search(r"@s:([a-z&+]+)", token)
    if not m:
        return head
    tag = m.group(1)
    if tag == "spa":
        return "es"
    if tag == "eng":
        return "en"
    return "?"


def words(text, default):
    # Untagged words are in the file's first @Languages language, or the one an utterance is headed with ([- spa]).
    head = "es" if "[- spa]" in text else "en" if "[- eng]" in text else default
    text = BRACKETS.sub(" ", text)
    out = []
    for token in text.split():
        if token.startswith(("&", "+", "#", "%")) or token in ("xxx", "yyy", "www", "0", ".", "?", "!", ","):
            continue
        lang = lang_of(token, head)
        word = re.sub(r"@s:[a-z&+]+|@[a-z]+", "", token)
        word = word.replace("_", " ").strip(".,?!\"'()")
        word = re.sub(r"[()]", "", word)
        if not word or not re.search(r"[^\W\d_]", word):
            continue
        for piece in word.split():
            out.append([piece, lang])
    return out


def utterances(path):
    lines, current, default = [], None, "en"
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            raw = raw.rstrip("\n")
            if raw.startswith("@Languages:"):
                default = "es" if raw.split(":", 1)[1].strip().startswith("spa") else "en"
            if raw.startswith("*"):
                current = raw
                lines.append(current)
            elif raw.startswith("\t") and current is not None and lines:
                lines[-1] += " " + raw.strip()
            else:
                current = None
    for line in lines:
        speaker, _, text = line[1:].partition(":")
        m = TIME.search(text)
        if not m:
            continue
        ws = words(text[: m.start()], default)
        if ws:
            yield {"speaker": speaker.strip(), "start": int(m.group(1)) / 1000, "end": int(m.group(2)) / 1000, "words": ws}


def main():
    src, out = sys.argv[1], sys.argv[2]
    conversations = []
    for name in sorted(os.listdir(src)):
        if name.endswith(".cha"):
            us = sorted(utterances(os.path.join(src, name)), key=lambda u: u["start"])
            if us:
                conversations.append({"name": name[:-4], "utterances": us})
    with open(out, "w") as f:
        json.dump(conversations, f, ensure_ascii=False)
    print(f"{len(conversations)} conversations, {sum(len(c['utterances']) for c in conversations)} utterances -> {out}")


if __name__ == "__main__":
    main()
