#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"

./package.sh

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' packaging/Info.plist)"
archive="dist/Axiom-First-Light-v${version}-macOS-arm64.zip"

ditto -c -k --sequesterRsrc --keepParent "dist/Axiom.app" "$archive"
shasum -a 256 "$archive" > "${archive}.sha256"

echo "Release archive: $archive"
echo "Checksum: ${archive}.sha256"
