#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

python3 -m venv "$LAB_DIR/.venv"
"$LAB_DIR/.venv/bin/pip" install --upgrade pip
"$LAB_DIR/.venv/bin/pip" install -r "$LAB_DIR/requirements.txt"
