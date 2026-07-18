#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
exec uv run \
  --python 3.12 \
  --with-requirements tools/scheduling_oracle/requirements.txt \
  python -u tools/scheduling_oracle/generate.py
