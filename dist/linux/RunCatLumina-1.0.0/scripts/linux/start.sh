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
ROOT="$(cd "$(dirname "$SOURCE")/../.." && pwd)"
cd "$ROOT"

if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 is required."
  exit 1
fi

if [ ! -x "$ROOT/.venv/bin/python" ]; then
  echo "Creating virtual environment..."
  python3 -m venv "$ROOT/.venv"
fi

"$ROOT/.venv/bin/python" -m pip install -q --upgrade pip
"$ROOT/.venv/bin/python" -m pip install -q -r "$ROOT/requirements.txt"
exec "$ROOT/.venv/bin/python" "$ROOT/main.py"
