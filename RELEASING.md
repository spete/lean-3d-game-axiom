# Releasing

1. Update `CHANGELOG.md` and the version/build values in
   `packaging/Info.plist`.
2. Run `lake exe axiom_tests`.
3. Run `./package.sh` and every relevant `--qa-*` mode documented in README.
4. Run `./release.sh` to create the app archive and SHA-256 checksum in `dist/`.
5. Verify the archive on a clean Apple Silicon Mac.
6. Create an annotated `vX.Y.Z` tag and attach the zip, checksum and release
   notes to the GitHub release.

The generated app is ad-hoc signed, not Developer ID signed or notarized.
Public binaries should state this clearly until a notarized release pipeline is
added.
