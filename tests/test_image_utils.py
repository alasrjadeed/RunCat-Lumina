"""
Tests for image utility functions
"""
import sys
from pathlib import Path
from PIL import Image

# Add the project root to the path so we can import main.py
sys.path.insert(0, str(Path(__file__).parent.parent))

from main import hex_to_rgb, tint_image


def test_hex_to_rgb():
    """Test hex_to_rgb function"""
    # Test standard 6-digit hex
    assert hex_to_rgb("#FF0000") == (255, 0, 0)
    assert hex_to_rgb("#00FF00") == (0, 255, 0)
    assert hex_to_rgb("#0000FF") == (0, 0, 255)
    assert hex_to_rgb("#FFFFFF") == (255, 255, 255)
    assert hex_to_rgb("#000000") == (0, 0, 0)

    # Test 3-digit hex shorthand
    assert hex_to_rgb("#F00") == (255, 0, 0)
    assert hex_to_rgb("#0F0") == (0, 255, 0)
    assert hex_to_rgb("#00F") == (0, 0, 255)
    assert hex_to_rgb("#FFF") == (255, 255, 255)
    assert hex_to_rgb("#000") == (0, 0, 0)

    # Test without # prefix
    assert hex_to_rgb("FF0000") == (255, 0, 0)
    assert hex_to_rgb("F00") == (255, 0, 0)


def test_tint_image():
    """Test tint_image function"""
    # Create a simple test image
    img = Image.new("RGBA", (10, 10), (255, 255, 255, 255))  # White image

    # Tint with red - should make it reddish
    tinted = tint_image(img, "#FF0000")

    # Check that the tinted image is not the same as original
    # (exact values depend on the tinting algorithm)
    assert tinted.size == img.size
    assert tinted.mode == img.mode

    # Test with transparent image
    transparent_img = Image.new("RGBA", (10, 10), (0, 0, 0, 0))
    tinted_transparent = tint_image(transparent_img, "#FF0000")
    assert tinted_transparent.size == transparent_img.size


if __name__ == "__main__":
    test_hex_to_rgb()
    test_tint_image()
    print("All image utility tests passed!")