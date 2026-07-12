#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
export LEAN_CC=/usr/bin/clang
export MACOSX_DEPLOYMENT_TARGET=26.0
lake exe axiom
