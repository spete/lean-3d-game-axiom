#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export LEAN_CC=/usr/bin/clang
export MACOSX_DEPLOYMENT_TARGET=26.0
lake build
licenses="dist/Axiom.app/Contents/Resources/Licenses"
mkdir -p "dist/Axiom.app/Contents/MacOS" "$licenses"
cp "packaging/Info.plist" "dist/Axiom.app/Contents/Info.plist"
cp "LICENSE" "dist/Axiom.app/Contents/Resources/LICENSE-Axiom.txt"
cp "docs/THIRD_PARTY_NOTICES.md" "dist/Axiom.app/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp ".lake/packages/raylib/LICENSE" "$licenses/Raylib.lean-BSD-3-Clause.txt"
cp ".lake/packages/raylib/raylib/LICENSE" "$licenses/raylib-Zlib.txt"
cp ".lake/packages/pod/LICENSE" "$licenses/lean-pod-BSD-3-Clause.txt"
cp ".lake/packages/LSpec/LICENSE" "$licenses/LSpec-MIT.txt"
lean_bin="$(elan which lean)"
lean_root="${lean_bin:h:h}"
cp "$lean_root/LICENSE" "$licenses/Lean-4-Apache-2.0.txt"
cp ".lake/build/bin/axiom" "dist/Axiom.app/Contents/MacOS/Axiom"
chmod +x "dist/Axiom.app/Contents/MacOS/Axiom"
plutil -lint "dist/Axiom.app/Contents/Info.plist"
codesign --force --deep --sign - "dist/Axiom.app"
codesign --verify --deep --strict "dist/Axiom.app"
echo "Packaged dist/Axiom.app"
