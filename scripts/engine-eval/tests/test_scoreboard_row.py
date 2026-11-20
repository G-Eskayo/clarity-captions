"""Tests for scoreboard_eval.row normalizers."""
import pytest
from scoreboard_eval.row import normalize_bytes, normalize_ci, normalize_percentage


def test_normalize_bytes_mb():
    assert normalize_bytes("123 MB") == 123000000
    assert normalize_bytes("1.5 MB") == 1500000


def test_normalize_bytes_mib():
    assert normalize_bytes("123 MiB") == 123 * 1024 * 1024


def test_normalize_bytes_kb():
    assert normalize_bytes("512 KB") == 512000


def test_normalize_bytes_kib():
    assert normalize_bytes("512 KiB") == 512 * 1024


def test_normalize_bytes_plain():
    assert normalize_bytes("1234 bytes") == 1234
    assert normalize_bytes("1234 B") == 1234


def test_normalize_bytes_gib():
    assert normalize_bytes("1 GiB") == 1024 ** 3


def test_normalize_bytes_gb():
    assert normalize_bytes("1 GB") == 1000000000


def test_normalize_bytes_empty():
    assert normalize_bytes("") is None
    assert normalize_bytes("–") is None
    assert normalize_bytes(None) is None


def test_normalize_ci_dash_format():
    lo, hi = normalize_ci("12.7% – 14.7%")
    assert abs(lo - 0.127) < 0.001
    assert abs(hi - 0.147) < 0.001


def test_normalize_ci_to_format():
    lo, hi = normalize_ci("0.5 to 1.0")
    assert abs(lo - 0.005) < 0.001
    assert abs(hi - 0.01) < 0.001


def test_normalize_ci_bracket_format():
    lo, hi = normalize_ci("[12.7%, 14.7%]")
    assert abs(lo - 0.127) < 0.001
    assert abs(hi - 0.147) < 0.001


def test_normalize_ci_empty():
    assert normalize_ci("") == (None, None)
    assert normalize_ci("–") == (None, None)
    assert normalize_ci(None) == (None, None)


def test_normalize_percentage():
    assert abs(normalize_percentage("13.8%") - 0.138) < 0.001
    assert abs(normalize_percentage("100%") - 1.0) < 0.001
    assert abs(normalize_percentage("0.1%") - 0.001) < 0.0001


def test_normalize_percentage_empty():
    assert normalize_percentage("") is None
    assert normalize_percentage("–") is None
    assert normalize_percentage(None) is None
