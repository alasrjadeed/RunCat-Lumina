"""
Tests for configuration functionality
"""
import json
import tempfile
import os
from pathlib import Path
import sys

# Add the project root to the path so we can import main.py
sys.path.insert(0, str(Path(__file__).parent.parent))

from main import load_config, save_config


def test_load_config_defaults():
    """Test that load_config returns defaults when no config file exists"""
    # Create a temporary directory and point CONFIG_PATH there
    import main
    original_config_path = main.CONFIG_PATH

    with tempfile.TemporaryDirectory() as tmpdir:
        test_config_path = Path(tmpdir) / "config.json"
        main.CONFIG_PATH = test_config_path

        try:
            settings, author = load_config()

            # Check defaults
            assert settings["dark_mode"] == True
            assert settings["positive_correlation"] == True
            assert settings["cat_color"] == "#FFFFFF"
            assert author["name"] == "AL ASAR JADEED"
            assert author["web"] == "https://alasarjadeed.com"
            assert author["email"] == "info@alasarjadeed.com"
        finally:
            main.CONFIG_PATH = original_config_path


def test_load_config_from_file():
    """Test that load_config reads from file when it exists"""
    import main
    original_config_path = main.CONFIG_PATH

    with tempfile.TemporaryDirectory() as tmpdir:
        test_config_path = Path(tmpdir) / "config.json"
        main.CONFIG_PATH = test_config_path

        # Create a test config file
        test_config = {
            "author": {
                "name": "Test Author",
                "web": "https://test.com",
                "email": "test@test.com"
            },
            "settings": {
                "dark_mode": False,
                "positive_correlation": False,
                "cat_color": "#FF0000"
            }
        }

        with open(test_config_path, "w") as f:
            json.dump(test_config, f)

        try:
            settings, author = load_config()

            # Check values from file
            assert settings["dark_mode"] == False
            assert settings["positive_correlation"] == False
            assert settings["cat_color"] == "#FF0000"
            assert author["name"] == "Test Author"
            assert author["web"] == "https://test.com"
            assert author["email"] == "test@test.com"
        finally:
            main.CONFIG_PATH = original_config_path


def test_save_config():
    """Test that save_config writes to file correctly"""
    import main
    original_config_path = main.CONFIG_PATH

    with tempfile.TemporaryDirectory() as tmpdir:
        test_config_path = Path(tmpdir) / "config.json"
        main.CONFIG_PATH = test_config_path

        try:
            settings = {
                "dark_mode": True,
                "positive_correlation": False,
                "cat_color": "#00FF00"
            }
            author = {
                "name": "Test Author",
                "web": "https://test.com",
                "email": "test@test.com"
            }

            save_config(settings, author)

            # Read back and verify
            with open(test_config_path, "r") as f:
                data = json.load(f)

            assert data["settings"]["dark_mode"] == True
            assert data["settings"]["positive_correlation"] == False
            assert data["settings"]["cat_color"] == "#00FF00"
            assert data["author"]["name"] == "Test Author"
            assert data["author"]["web"] == "https://test.com"
            assert data["author"]["email"] == "test@test.com"
        finally:
            main.CONFIG_PATH = original_config_path


if __name__ == "__main__":
    test_load_config_defaults()
    test_load_config_from_file()
    test_save_config()
    print("All tests passed!")