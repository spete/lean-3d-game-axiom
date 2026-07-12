# Architecture

Axiom is a Lean application with a deliberately narrow native boundary.

## Responsibility split

Lean owns the game and engine semantics: block definitions, compact voxel
storage, deterministic generation, visible-face meshing, worker-task rebuilds,
physics, collision, DDA targeting, edits, particles, sound synthesis, saves,
screen state and the main loop.

Raylib owns platform access: the macOS window, input events, GPU draw calls and
audio-device output. Raylib does not provide a voxel engine, world model or game
rules.

## Frame flow

1. Poll platform input through Raylib.
2. Update the Lean player/world state.
3. Schedule dirty section meshes on Lean worker tasks.
4. Upload at most one completed mesh per frame on the render thread.
5. Draw the sky, opaque section meshes, water, clouds, effects and HUD.
6. Autosave the authoritative Lean world independently of render completion.

## Data model

The finite `96 × 96 × 48` world uses one byte per voxel. Sections are `16³`.
Only faces adjacent to air are emitted. The world value captured by a mesh task
is immutable, so worker computation cannot race with subsequent edits; a newer
job supersedes an older pending job for the same section.

## Trust and verification

The project uses Lean primarily as a compiled functional language today. The
acceptance suite checks deterministic generation, mesh consistency, collision,
ray traversal, edit semantics, section seams, saves, audio and particles. It
does not yet contain formal proofs of gameplay properties.
