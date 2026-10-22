"""Atomic shard claims so the M4 and the 2012 mini never run sherpa-onnx on the same shard (#145)."""
from edacc_eval.claims import claim_next, mark_done, owner


def test_two_hosts_never_get_the_same_shard(tmp_path):
    a = claim_next(tmp_path, total=3, host="m4")
    b = claim_next(tmp_path, total=3, host="old")
    mark_done(tmp_path, a)
    c = claim_next(tmp_path, total=3, host="m4")
    assert {a, b, c} == {1, 2, 3} and len({a, b, c}) == 3


def test_resume_own_unfinished_claim_first(tmp_path):
    assert claim_next(tmp_path, 3, "m4") == 1
    assert claim_next(tmp_path, 3, "old") == 2
    assert claim_next(tmp_path, 3, "m4") == 1  # restart: m4 takes back its unfinished shard 1
    mark_done(tmp_path, 1)
    assert claim_next(tmp_path, 3, "m4") == 3


def test_all_claimed_returns_none(tmp_path):
    for _ in range(2):
        mark_done(tmp_path, claim_next(tmp_path, 2, "x"))
    assert claim_next(tmp_path, 2, "y") is None


def test_other_hosts_unfinished_claim_not_stolen(tmp_path):
    assert claim_next(tmp_path, 1, "old") == 1
    assert claim_next(tmp_path, 1, "m4") is None
    assert owner(tmp_path, 1) == "old"


def test_first_shard_respected(tmp_path):
    assert claim_next(tmp_path, 5, "m4", first=3) == 3
