#!/usr/bin/env bash
# Preflight doctor: verifies every Windows build requirement and reports
# PASS/FAIL with a remedy for each. Read-only — changes nothing, downloads
# nothing. Exit code = number of failures.
set -uo pipefail
cd "$(dirname "$0")/.."

fails=0
ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n        fix: %s\n' "$1" "$2"; fails=$((fails+1)); }

echo "Axiom Windows preflight"

# --- elan (respects ELAN_HOME; default ~/.elan)
elan_bin="${ELAN_HOME:-$HOME/.elan}/bin"
export PATH="$elan_bin:$PATH"
if command -v elan >/dev/null 2>&1; then
  ok "elan ($(elan --version 2>/dev/null))"
else
  bad "elan not found (looked on PATH and in $elan_bin)" \
      "winget install leanprover.elan — or set ELAN_HOME; see docs/WINDOWS.md §1"
fi

# --- pinned Lean toolchain present (without triggering a download)
pin="$(tr -d '[:space:]' < lean-toolchain)"
if command -v elan >/dev/null 2>&1; then
  if elan toolchain list 2>/dev/null | grep -qF "$pin"; then
    ok "Lean toolchain $pin installed"
  else
    bad "pinned Lean toolchain $pin not installed" \
        "run 'lake --version' in the repo once; elan fetches the pin (~350 MB)"
  fi
fi

# --- build tools
for tool in cmake ninja git; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool ($("$tool" --version 2>/dev/null | head -1))"
  else
    bad "$tool not found on PATH" "install it; see docs/WINDOWS.md §1"
  fi
done

# --- viable UCRT gcc (delegates to the single source of truth)
if gcc_env="$(bash -c 'source scripts/env-windows.sh >/dev/null 2>&1 && echo "$MINGW_UCRT_CC|$MINGW_UCRT_LIBDIR"')"; then
  ok "UCRT MinGW gcc (${gcc_env%%|*})"
  libdir="${gcc_env##*|}"
  for lib in libopengl32.a libgdi32.a libwinmm.a libshell32.a libuser32.a; do
    if [ -f "$(cygpath -u "$libdir")/$lib" ]; then
      ok "import library $lib"
    else
      bad "import library $lib missing from $libdir" \
          "the toolchain is incomplete; reinstall mingw-w64-ucrt-x86_64-toolchain"
    fi
  done
else
  bad "no viable UCRT-targeting gcc" \
      "install MSYS2 + mingw-w64-ucrt-x86_64-toolchain, or set MINGW_UCRT_ROOT; see docs/WINDOWS.md §4"
fi

# --- fetched Lean deps and built raylib (products of setup-windows.sh)
if [ -f .lake/packages/raylib/lakefile.lean ]; then
  ok "Lean package deps fetched"
else
  bad "Lean package deps not fetched (.lake/packages/raylib missing)" \
      "./scripts/setup-windows.sh"
fi
if [ -f .lake/packages/raylib/raylib/src/raylib.h ]; then
  ok "raylib C source (submodule) present"
else
  bad "raylib C source submodule not initialized" "./scripts/setup-windows.sh"
fi
if [ -f .lake/packages/raylib/raylib/build/raylib/libraylib.a ]; then
  ok "libraylib.a built"
else
  bad "raylib static library not built" "./scripts/setup-windows.sh"
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "All checks passed — ready to build."
else
  echo "$fails check(s) failed."
fi
exit "$fails"
