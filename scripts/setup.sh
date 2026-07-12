#!/bin/zsh
set -euo pipefail

cd "${0:A:h:h}"
export LEAN_CC=/usr/bin/clang
export MACOSX_DEPLOYMENT_TARGET=26.0

lake update
lake run raylib/buildSubmodule
git -C .lake/packages/raylib/raylib apply \
  "$PWD/patches/raylib-macos-hidpi-resize.patch"
cmake --build .lake/packages/raylib/raylib/build --parallel
