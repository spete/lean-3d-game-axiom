#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env-windows.sh
lake build axiom
# The exe is self-contained (Lean runtime statically linked; only Windows
# system DLLs are imported), so no extra PATH setup is needed to run it.
exec ./.lake/build/bin/axiom.exe "$@"
