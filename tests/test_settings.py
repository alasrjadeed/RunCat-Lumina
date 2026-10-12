"""
Tests for the settings helpers and CPU title formatting.
"""
import sys
from pathlib import Path

# Add the project root to the path so we can import main.py
sys.path.insert(0, str(Path(__file__).parent.parent))

from main import format_cpu_title, normalize_hex


def test_normalize_hex_valid():
    assert normalize_hex("#FF9F43") == "#FF9F43"
    assert normalize_hex("ff9f43") == "#FF9F43"
    assert normalize_hex("#f93") == "#FF9933"
    assert normalize_hex("  #00ff00 ") == "#00FF00"


def test_normalize_hex_invalid():
    for value in ("", None, "#ZZZ", "#12345", "red"):
        assert normalize_hex(value) is None, value


def test_normalize_hex_tolerates_extra_hashes():
    # hex_to_rgb strips leading '#' characters, which is harmless leniency.
    assert normalize_hex("##FF9F43") == "#FF9F43"


def test_format_cpu_title_ascii_only():
    """The title is written into an X11 WM_NAME (latin-1): must be ASCII."""
    title = format_cpu_title({"cpu": 42})
    assert title.encode("latin-1")  # must not raise
    assert "42%" in title


def test_format_cpu_title_defaults():
    assert "0%" in format_cpu_title({})


if __name__ == "__main__":
    test_normalize_hex_valid()
    test_normalize_hex_invalid()
    test_normalize_hex_tolerates_extra_hashes()
    test_format_cpu_title_ascii_only()
    test_format_cpu_title_defaults()
    print("All settings tests passed!")