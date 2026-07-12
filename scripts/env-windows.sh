#!/usr/bin/env bash
# Shared Windows build environment. Source this; do not execute it.
#
# Locates a viable UCRT-targeting MinGW C toolchain and exports, in Windows
# path style:
#   MINGW_UCRT_ROOT   toolchain root (informational + lakefile fallback paths)
#   MINGW_UCRT_CC     full path to the validated gcc
#   MINGW_UCRT_LIBDIR directory containing the Win32 import libraries
# It also puts the toolchain's bin dir and elan on PATH and unsets LEAN_CC
# (leanc must link; see docs/WINDOWS.md "cannot find -lc++").
#
# Detection order:
#   1. MINGW_UCRT_ROOT, if already set (validated; explicit settings fail loudly)
#   2. the standard MSYS2 install: C:\msys64\ucrt64
#   3. whatever `gcc` is on PATH, if it passes the viability signature
#
# Viability signature (location-independent; accepts any UCRT-targeting
# MinGW distribution, rejects MSVCRT-era toolchains and MSYS gcc):
#   - `gcc -dumpmachine` is x86_64-w64-mingw32  (right ABI family)
#   - compiling <stdio.h> defines _UCRT          (right C runtime, matches Lean)
#   - `gcc -print-file-name=libopengl32.a` exists (Win32 import libs present)

# Probe a gcc for viability. Its bin dir is prepended to PATH during probing:
# MSYS2 toolchains silently fail when invoked by full path off-PATH.
# On success sets: _VIA_CC, _VIA_BIN, _VIA_LIBDIR (unix-style paths).
_axiom_viable_gcc() {
  local g="$1" bin machine lib
  [ -x "$g" ] || return 1
  bin="$(dirname "$g")"
  machine="$(PATH="$bin:$PATH" "$g" -dumpmachine 2>/dev/null)" || return 1
  [ "$machine" = "x86_64-w64-mingw32" ] || return 1
  echo '#include <stdio.h>' | PATH="$bin:$PATH" "$g" -dM -E - 2>/dev/null \
    | grep -qw _UCRT || return 1
  lib="$(PATH="$bin:$PATH" "$g" -print-file-name=libopengl32.a 2>/dev/null)"
  [ -f "$lib" ] || return 1
  _VIA_CC="$g"
  _VIA_BIN="$bin"
  _VIA_LIBDIR="$(cd "$(dirname "$lib")" && pwd)"
  return 0
}

if [ -n "${MINGW_UCRT_ROOT:-}" ]; then
  # 1. Explicit setting: trust the location, still verify it is viable.
  _root_unix="$(cygpath -u "$MINGW_UCRT_ROOT")"
  if ! _axiom_viable_gcc "$_root_unix/bin/gcc.exe"; then
    echo "error: MINGW_UCRT_ROOT=$MINGW_UCRT_ROOT does not contain a viable UCRT gcc" >&2
    echo "       (needs x86_64-w64-mingw32 target, _UCRT runtime, Win32 import libs)" >&2
    return 1 2>/dev/null || exit 1
  fi
elif _axiom_viable_gcc /c/msys64/ucrt64/bin/gcc.exe; then
  : # 2. Standard MSYS2 location.
elif command -v gcc >/dev/null 2>&1 && _axiom_viable_gcc "$(command -v gcc)"; then
  : # 3. Whatever gcc is on PATH, since it passes the signature.
else
  echo "error: no viable UCRT-targeting MinGW gcc found." >&2
  echo "       Checked: \$MINGW_UCRT_ROOT, C:\\msys64\\ucrt64, and \`gcc\` on PATH." >&2
  echo "       Install MSYS2 + mingw-w64-ucrt-x86_64-toolchain, or set" >&2
  echo "       MINGW_UCRT_ROOT to a UCRT MinGW root (e.g. MINGW_UCRT_ROOT=D:/msys64/ucrt64)." >&2
  return 1 2>/dev/null || exit 1
fi

export MINGW_UCRT_ROOT="$(cygpath -m "$(dirname "$_VIA_BIN")")"
export MINGW_UCRT_CC="$(cygpath -m "$_VIA_CC")"
export MINGW_UCRT_LIBDIR="$(cygpath -m "$_VIA_LIBDIR")"
# elan respects ELAN_HOME; default install is %USERPROFILE%\.elan.
export PATH="${ELAN_HOME:-$HOME/.elan}/bin:$_VIA_BIN:$PATH"

# leanc must be the linker driver on Windows; LEAN_CC=gcc mixes CRT halves.
unset LEAN_CC
