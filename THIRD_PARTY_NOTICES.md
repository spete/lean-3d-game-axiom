# Third-party notices

Axiom's own source code is licensed under the MIT License. The project builds
against the following separately licensed software. Exact revisions are pinned
in `lake-manifest.json`.

| Component | Purpose | License |
|---|---|---|
| [Lean 4](https://github.com/leanprover/lean4) | Compiler, runtime and standard library | Apache-2.0 |
| [Raylib.lean](https://github.com/KislyjKisel/Raylib.lean) | Lean bindings and FFI | BSD-3-Clause |
| [raylib](https://github.com/raysan5/raylib) | Windowing, input, GPU and audio platform layer | Zlib |
| [lean-pod](https://github.com/KislyjKisel/lean-pod) | Packed native byte views | BSD-3-Clause |
| [LSpec](https://github.com/argumentcomputer/LSpec) | Transitive Lean test dependency | MIT |

The release packaging script places the complete license text for every
dependency in `Axiom.app/Contents/Resources/Licenses`. Those texts remain the
authoritative terms for their respective components.

No third-party textures, models, music or sound samples are distributed. The
visuals are generated from game data and the sound effects are synthesized at
runtime by Lean code.
