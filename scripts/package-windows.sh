#!/usr/bin/env bash
# Build a distributable Windows release zip: the self-contained exe plus the
# license bundle (the Windows analogue of package.sh + release.sh). The exe
# statically links Lean's runtime and imports only Windows system DLLs, so
# no other files are required.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env-windows.sh

./scripts/build-windows.sh axiom

version="$(grep -A1 CFBundleShortVersionString packaging/Info.plist \
  | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')"
stage="dist/Axiom-First-Light-v${version}-windows-x86_64"
licenses="$stage/Licenses"

rm -rf "$stage"
mkdir -p "$licenses"
cp .lake/build/bin/axiom.exe "$stage/Axiom.exe"
cp LICENSE "$stage/LICENSE-Axiom.txt"
cp docs/THIRD_PARTY_NOTICES.md "$stage/THIRD_PARTY_NOTICES.md"
cp .lake/packages/raylib/LICENSE "$licenses/Raylib.lean-BSD-3-Clause.txt"
cp .lake/packages/raylib/raylib/LICENSE "$licenses/raylib-Zlib.txt"
cp .lake/packages/pod/LICENSE "$licenses/lean-pod-BSD-3-Clause.txt"
cp .lake/packages/LSpec/LICENSE "$licenses/LSpec-MIT.txt"
lean_root="$(dirname "$(dirname "$(cygpath -u "$(elan which lean)")")")"
cp "$lean_root/LICENSE" "$licenses/Lean-4-Apache-2.0.txt"

archive="${stage}.zip"
rm -f "$archive" "${archive}.sha256"
# Windows' built-in bsdtar creates spec-conforming zips (forward-slash entry
# names). git-bash has no `zip`, and PowerShell's Compress-Archive writes
# backslash separators that non-Windows unzip tools reject or mangle.
(cd dist && /c/Windows/System32/tar.exe -a -cf "$(basename "$archive")" "$(basename "$stage")")
(cd dist && sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256")

echo "Release archive: $archive"
echo "Checksum: ${archive}.sha256"
