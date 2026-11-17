#!/bin/sh
# Install the language engine Rinsewrite runs: a Python environment with
# MLX in ~/Library/Application Support/Rinsewrite/venv, and the LFM3 1.7B
# model (about 1 GB, from Hugging Face) in the usual Hugging Face cache.
#
# Run via: make engine, or Install Engine… in the app, which runs the copy
# in Rinsewrite.app/Contents/Resources/engine. Safe to run again; it only
# adds what's missing.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
if [ -f "$HERE/requirements.txt" ]; then ENGINE="$HERE"; else ENGINE="$(cd "$HERE/.." && pwd)/engine"; fi
SUPPORT="$HOME/Library/Application Support/Rinsewrite"
VENV="$SUPPORT/venv"
mkdir -p "$SUPPORT"
# While this marker exists the app waits instead of starting a half-installed engine.
touch "$SUPPORT/installing"
trap 'rm -f "$SUPPORT/installing"' EXIT

echo "Setting up Rinsewrite's engine. This takes a few minutes the first time."

if command -v uv >/dev/null 2>&1; then
    [ -x "$VENV/bin/python" ] || uv venv --python 3.12 "$VENV" -q
    uv pip install --python "$VENV/bin/python" -q -r "$ENGINE/requirements.txt"
else
    PYTHON=$(command -v python3.13 || command -v python3.12 || command -v python3.11 || command -v python3.10 || command -v python3 || true)
    if [ -z "$PYTHON" ] || ! "$PYTHON" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null; then
        echo "Rinsewrite needs Python 3.10 or later, or uv. Install uv from https://docs.astral.sh/uv/ and run this again."
        exit 1
    fi
    [ -x "$VENV/bin/python" ] || "$PYTHON" -m venv "$VENV"
    "$VENV/bin/python" -m pip install -q --upgrade pip
    "$VENV/bin/python" -m pip install -q -r "$ENGINE/requirements.txt"
fi

echo "Model:"
"$VENV/bin/python" -c "import sys; sys.path.insert(0, sys.argv[1]); import engine; print(engine.model_path())" "$ENGINE"
echo "Engine ready in $VENV. Rinsewrite starts it on its own; you can close this window."
