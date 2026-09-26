#!/usr/bin/env bash
# SDK-059 license scan (Linux CI).
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check-licenses.py
