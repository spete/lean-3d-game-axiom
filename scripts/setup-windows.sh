#!/usr/bin/env bash
# One-time Windows setup: fetch Lean deps and build raylib's C library.
# Idempotent: safe to re-run; cmake reconfigures in place.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env-windows.sh

# Check the tools this script needs before doing any work.
for tool in cmake ninja git lake; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "error: '$tool' not found on PATH — see docs/WINDOWS.md §1" >&2
    echo "       (full preflight: ./scripts/check-windows.sh)" >&2
    exit 1
  }
done

lake update

# Fetch the pinned raylib C source (the binding tracks it as a submodule).
git -C .lake/packages/raylib submodule update --init --force --recursive raylib

# Configure and build static raylib with the UCRT64 toolchain.
# SUPPORT_WINMM_HIGHRES_TIMER stays ON: we link -lwinmm, and without it
# raylib's frame pacing quantizes to ~15.6 ms sleeps (30 FPS at a 60 FPS
# target). The binding's own script disables it only to avoid the winmm dep.
cmake -S .lake/packages/raylib/raylib -B .lake/packages/raylib/raylib/build \
  -G Ninja \
  -DCMAKE_C_COMPILER="$MINGW_UCRT_CC" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCUSTOMIZE_BUILD=ON \
  -DWITH_PIC=ON \
  -DBUILD_EXAMPLES=OFF \
  -DPLATFORM=Desktop \
  -DSUPPORT_WINMM_HIGHRES_TIMER=ON
cmake --build .lake/packages/raylib/raylib/build --parallel

echo "Windows setup complete. Next: ./scripts/build-windows.sh"
