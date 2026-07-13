# Changelog

All notable changes are documented here. This project follows semantic
versioning for tagged releases.

## [Unreleased]

### Added

- First formal specifications (`Axiom/Theorems.lean`): a machine-checked
  mesh-locality theorem (edits outside a section's axial footprint leave
  its mesh unchanged — the soundness core of incremental remeshing),
  accessor laws for the voxel store, voxel-index safety and injectivity,
  collision step bounds over the named tunneling-safety constants, and
  evaluated proofs that the default island has valid block ids, a safe
  grounded spawn, bounded terrain, and complete mesh triangles.

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
