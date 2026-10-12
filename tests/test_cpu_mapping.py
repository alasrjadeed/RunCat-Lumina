"""
Tests for the CPU usage -> animation interval mapping
"""
import sys
from pathlib import Path

# Add the project root to the path so we can import main.py
sys.path.insert(0, str(Path(__file__).parent.parent))

from main import cpu_to_interval


def test_positive_correlation_is_monotonic():
    """Higher CPU must always mean a faster (smaller) interval."""
    values = [cpu_to_interval(c, True) for c in range(0, 101, 5)]
    assert values == sorted(values, reverse=True)


def test_negative_correlation_is_monotonic():
    """With the correlation off, higher CPU must mean a slower interval."""
    values = [cpu_to_interval(c, False) for c in range(0, 101, 5)]
    assert values == sorted(values)


def test_interval_stays_in_bounds():
    for correlation in (True, False):
        for cpu in range(0, 101):
            value = cpu_to_interval(cpu, correlation)
            assert 0.04 <= value <= 2.0, (cpu, correlation, value)


def test_reversed_high_load_does_not_speed_up():
    """Regression: above 50% CPU the reversed mode used to get faster."""
    low = cpu_to_interval(55, False)
    high = cpu_to_interval(95, False)
    assert high > low


if __name__ == "__main__":
    test_positive_correlation_is_monotonic()
    test_negative_correlation_is_monotonic()
    test_interval_stays_in_bounds()
    test_reversed_high_load_does_not_speed_up()
    print("All CPU mapping tests passed!")
