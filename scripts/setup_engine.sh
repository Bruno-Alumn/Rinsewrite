#!/bin/sh
# Install the language engine Rinsewrite runs: a Python environment with
# MLX in ~/Library/Application Support/Rinsewrite/venv, and the LFM3 1.7B
# model (about 1 GB, from Hugging Face) in the usual Hugging Face cache.
#
# Run via: make engine. Safe to run again; it only adds what's missing.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUPPORT="$HOME/Library/Application Support/Rinsewrite"
VENV="$SUPPORT/venv"
mkdir -p "$SUPPORT"

if command -v uv >/dev/null 2>&1; then
    [ -x "$VENV/bin/python" ] || uv venv --python 3.12 "$VENV" -q
    uv pip install --python "$VENV/bin/python" -q -r "$ROOT/engine/requirements.txt"
else
    PYTHON=$(command -v python3.12 || command -v python3)
    [ -x "$VENV/bin/python" ] || "$PYTHON" -m venv "$VENV"
    "$VENV/bin/python" -m pip install -q --upgrade pip
    "$VENV/bin/python" -m pip install -q -r "$ROOT/engine/requirements.txt"
fi

echo "Model:"
"$VENV/bin/python" -c "import sys; sys.path.insert(0, '$ROOT/engine'); import engine; print(engine.model_path())"
echo "Engine ready in $VENV"
