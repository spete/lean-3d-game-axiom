# Contributing

Thanks for helping improve Axiom. Small, focused pull requests are easiest to
review.

## Development setup

1. Install `elan`, `/usr/bin/clang`, CMake and the macOS command-line tools.
2. Run `./scripts/setup.sh` to fetch dependencies, apply the pinned platform
   patch, and compile raylib.
3. Run `./scripts/build.sh` and `lake exe axiom_tests`.

The current native target is Apple Silicon macOS 26. Portability work is
welcome, but should keep platform-specific linker configuration isolated.

## Pull requests

- Explain the player-visible or engine-level motivation.
- Add deterministic tests for world, physics, meshing or save-format changes.
- Run `lake exe axiom_tests` before submitting.
- For rendering changes, include before/after screenshots and run the built-in
  `--qa-motion`, `--qa-resize`, and `--qa-perf` modes.
- Avoid committing `.lake`, `dist`, save files or locally generated QA output.
- Preserve the boundary between Lean game/engine logic and Raylib's narrow
  platform role.

By submitting a contribution, you agree that it may be distributed under the
project's MIT License.
