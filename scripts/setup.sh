#!/bin/zsh
set -euo pipefail

cd "${0:A:h:h}"
export LEAN_CC=/usr/bin/clang
export MACOSX_DEPLOYMENT_TARGET=26.0

raylib_dir=".lake/packages/raylib/raylib"
raylib_lib="$raylib_dir/build/raylib/libraylib.a"
patch_file="$PWD/patches/raylib-macos-hidpi-resize.patch"
patch_stamp=".lake/axiom-raylib-macos-hidpi-v1"

patch_is_applied() {
  [[ -d "$raylib_dir/.git" || -f "$raylib_dir/.git" ]] &&
    git -C "$raylib_dir" apply --reverse --check "$patch_file" >/dev/null 2>&1
}

if [[ -f "$raylib_lib" && -f "$patch_stamp" ]]; then
  exit 0
fi

lake update
lake run raylib/buildSubmodule

if git -C "$raylib_dir" apply --check "$patch_file" >/dev/null 2>&1; then
  git -C "$raylib_dir" apply "$patch_file"
elif ! patch_is_applied; then
  echo "The pinned raylib source no longer matches the Retina resize patch." >&2
  exit 1
fi

cmake --build "$raylib_dir/build" --config Release
touch "$patch_stamp"
