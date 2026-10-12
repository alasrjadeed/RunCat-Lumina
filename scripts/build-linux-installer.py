#!/usr/bin/env python3
"""Build the standalone, self-extracting Linux installer (install-linux.sh).

The generated installer embeds the current project files so it can be shipped
on its own. Re-run this after changing main.py, config.json, resources, etc.

Usage:
    python3 scripts/build-linux-installer.py
"""
import base64
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "install-linux.sh"

TEXT_FILES = ["main.py", "config.json", "requirements.txt", "VERSION", "LICENSE"]
ICON_FILES = sorted((ROOT / "resources" / "cat").glob("*.ico")) + [ROOT / "resources" / "icon.png"]

# Read the launcher straight from the repo so the installer can never embed a
# stale copy of it.
START_SCRIPT = (ROOT / "start-linux.sh").read_text(encoding="utf-8")

DESKTOP = """[Desktop Entry]
Version=1.0
Type=Application
Name=RunCat Lumina
GenericName=CPU Cat
Comment=Running cat on the Linux taskbar with custom colors
Exec="$APP_DIR/start-linux.sh"
TryExec="$APP_DIR/start-linux.sh"
Path=$APP_DIR
Icon=$ICON_DIR/runcat-lumina.png
Terminal=false
Categories=Utility;Monitor;
Keywords=cat;cpu;taskbar;tray;runcat;lumina;
StartupNotify=false
StartupWMClass=RunCat_Lumina
"""


def heredoc(marker: str, content: str) -> str:
    """Wrap content in a quoted heredoc, guarding the terminator."""
    for line in content.splitlines():
        if line.strip() == marker:
            raise SystemExit(f"Content contains the heredoc marker {marker!r}")
    body = content if content.endswith("\n") else content + "\n"
    return f"<< '{marker}'\n{body}{marker}\n"


def b64_block(data: bytes) -> str:
    encoded = base64.b64encode(data).decode("ascii")
    return "\n".join(textwrap.wrap(encoded, 79)) + "\n"


def main() -> None:
    parts = [
        "#!/usr/bin/env bash\n",
        "set -euo pipefail\n",
        "\n",
        'APP_DIR="$HOME/RunCatLumina"\n',
        'BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"\n',
        'APP_MENU="${XDG_DATA_HOME:-$HOME/.local/share}/applications"\n',
        'ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"\n',
        "\n",
        'echo "RunCat Lumina Linux installer"\n',
        'echo "Install folder: $APP_DIR"\n',
        "\n",
        "if ! command -v python3 >/dev/null 2>&1; then\n",
        '  echo "Install Python first:"\n',
        '  echo "  sudo apt install python3 python3-venv python3-pip"\n',
        "  exit 1\n",
        "fi\n",
        "if ! python3 -c 'import venv' >/dev/null 2>&1; then\n",
        '  echo "Install venv first:"\n',
        '  echo "  sudo apt install python3-venv"\n',
        "  exit 1\n",
        "fi\n",
        "\n",
        'mkdir -p "$APP_DIR/resources/cat" "$BIN_DIR" "$APP_MENU" "$ICON_DIR"\n',
        "\n",
        "write_file() {\n",
        "  cat > \"$1\"\n",
        "}\n",
        "\n",
        "write_b64() {\n",
        "  base64 -d > \"$1\"\n",
        "}\n",
        "\n",
    ]

    for name in TEXT_FILES:
        content = (ROOT / name).read_text(encoding="utf-8")
        parts.append(f'write_file "$APP_DIR/{name}" {heredoc("FILE", content)}\n')

    for icon in ICON_FILES:
        rel = icon.relative_to(ROOT)
        parts.append(
            f'write_b64 "$APP_DIR/{rel}" {heredoc("B64", b64_block(icon.read_bytes()))}\n'
        )

    parts.append(
        'cat > "$APP_DIR/start-linux.sh" '
        + heredoc("START", START_SCRIPT)
        + 'chmod +x "$APP_DIR/start-linux.sh"\n'
        "\n"
        'echo "Installing Python packages..."\n'
        'if [ ! -x "$APP_DIR/.venv/bin/python" ]; then\n'
        '  python3 -m venv "$APP_DIR/.venv"\n'
        "fi\n"
        '"$APP_DIR/.venv/bin/python" -m pip install -q --upgrade pip\n'
        '"$APP_DIR/.venv/bin/python" -m pip install -q -r "$APP_DIR/requirements.txt"\n'
        "\n"
        'ln -sfn "$APP_DIR/start-linux.sh" "$BIN_DIR/runcat-lumina"\n'
        'cp "$APP_DIR/resources/icon.png" "$ICON_DIR/runcat-lumina.png"\n'
        "\n"
        'cat > "$APP_MENU/runcat-lumina.desktop" << DESKTOP\n'
        + DESKTOP
        + "DESKTOP\n"
        'chmod +x "$APP_MENU/runcat-lumina.desktop"\n'
        "\n"
        "echo\n"
        'echo "Installed to $APP_DIR"\n'
        'echo "Start:  bash ~/RunCatLumina/start-linux.sh"\n'
        'echo "Or:     runcat-lumina"\n'
        "echo\n"
        'exec "$APP_DIR/.venv/bin/python" "$APP_DIR/main.py"\n'
    )

    OUT.write_text("".join(parts), encoding="utf-8")
    OUT.chmod(0o755)
    print(f"Wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
