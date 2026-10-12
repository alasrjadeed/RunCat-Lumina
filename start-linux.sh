#!/usr/bin/env bash
set -euo pipefail

# Resolve the real script path even when launched through a symlink
# (for example ~/.local/bin/runcat-lumina).
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  case "$SOURCE" in
    /*) ;;
    *) SOURCE="$DIR/$SOURCE" ;;
  esac
done
ROOT="$(cd "$(dirname "$SOURCE")" && pwd)"
cd "$ROOT"

if [ ! -f "$ROOT/main.py" ]; then
  echo "Run this from the RunCat Lumina folder."
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 is required."
  echo "Ubuntu/Debian: sudo apt install python3 python3-venv python3-pip"
  exit 1
fi

VENV_PY="$ROOT/.venv/bin/python"

if [ ! -x "$VENV_PY" ]; then
  echo "First-time setup: creating virtual environment..."
  python3 -m venv "$ROOT/.venv"
fi

# Install the dependencies unless they are already importable. This makes the
# launcher self-healing if the venv exists but packages are missing.
if ! "$VENV_PY" -c "import PIL, psutil, pystray" >/dev/null 2>&1; then
  echo "Installing dependencies..."
  "$VENV_PY" -m pip install -q --upgrade pip
  "$VENV_PY" -m pip install -q -r "$ROOT/requirements.txt"
fi

exec "$VENV_PY" "$ROOT/main.py" "$@"
