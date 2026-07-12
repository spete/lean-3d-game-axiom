#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env-windows.sh

# Fail fast with a remedy instead of dying at link time after a full compile.
if [ ! -f .lake/packages/raylib/raylib/build/raylib/libraylib.a ]; then
  echo "error: raylib is not built yet — run ./scripts/setup-windows.sh first" >&2
  echo "       (full preflight: ./scripts/check-windows.sh)" >&2
  exit 1
fi

lake build "$@"
