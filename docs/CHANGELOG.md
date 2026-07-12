# Changelog

All notable changes are documented here. This project follows semantic
versioning for tagged releases.

## [Unreleased]

### Added

- Windows (x86-64) build and runtime support: platform-conditional lakefile,
  Windows save location (`%APPDATA%\Axiom`), QA artifacts in `%TEMP%`, and
  `scripts/*-windows.sh` (preflight doctor, setup, build, run) with
  signature-based UCRT MinGW toolchain detection. See `docs/WINDOWS.md`.
- On-disk save persistence acceptance tests (round-trip, missing file,
  corrupt-file quarantine) via path-injectable `saveGameAt`/`loadGameAt?`.
- Windows release packaging (`scripts/package-windows.sh`): self-contained
  exe + license bundle as a checksummed zip.

## [0.2.1] - 2026-07-12

### Fixed

- Keep Raylib's 2D transform synchronized after macOS Retina window resizes,
  preventing the sky, HUD, and pause overlay from being trapped in one corner.

### Added

- Reproducible dependency setup that applies and rebuilds the pinned Raylib
  compatibility patch on clean machines and CI.
- A packaged-app resize regression mode for Retina viewport QA.

## [0.2.0] - 2026-07-12

### Added

- Playable finite-island creative voxel sandbox implemented in Lean 4.
- Deterministic terrain, forests, beaches, cave and marble landmark.
- First-person physics, collision, jumping, sprinting and flight.
- DDA block selection, mining, placement and nine-slot hotbar.
- Asynchronous section remeshing on Lean worker tasks.
- Procedural particles and runtime-synthesized PCM sound effects.
- Day/night sky, clouds, water, HUD, title and pause screens.
- Versioned atomic saves with checksums, semantic validation and quarantine.
- Deterministic acceptance suite and packaged-app visual/performance QA modes.
