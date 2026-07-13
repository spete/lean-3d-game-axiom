import Axiom

open Axiom

/-! Microbenchmark for the startup cost centers, CPU phases only (GPU
uploads need a live GL context and are excluded; in-game startup adds one
`uploadMeshCpu` per section on top of the numbers here).

Phases, in startup order:
1. `generateWorld` — terrain, caves, trees, landmark.
2. Audio synthesis — the four procedural WAVs from `loadAudioBank`.
3. Full-island CPU meshing, synchronous, one section in memory at a time —
   the exact shape (and peak-memory profile) of today's `buildGpuWorld`.
4. The same work on parallel worker tasks with all results retained until
   drained — the peak-memory profile of the streaming-startup design.
5. Build + vertex-stream packing per section (`floatArrayBytes` + colors),
   dropped immediately — the CPU half of `uploadMeshCpu`.

Each timing phase runs over three different seeds so no run can reuse a
previous result. Vertex/byte totals are printed both as sanity checks and
to keep the computations observably live.

Memory note: an earlier version of this benchmark retained all 108
`MeshCpu` values in an array and PANICKED OUT OF MEMORY on the reference
machine — `Array Float32` boxes every float, so a full island of retained
vertex data is far heavier than its packed size. Phase 4 exists to expose
exactly that hazard for the streaming design. -/

def sectionsOf (world : World) : Array (Nat × Nat × Nat) := Id.run do
  let mut out := #[]
  for sx in [0:sectionCountX] do
    for sy in [0:sectionCountY] do
      for sz in [0:sectionCountZ] do
        out := out.push (sx, sy, sz)
  return out

/-- Current startup shape: one mesh alive at a time. -/
def meshSyncDropping (world : World) : Nat := Id.run do
  let mut vertices := 0
  for (sx, sy, sz) in sectionsOf world do
    vertices := vertices + (buildSectionCpu world sx sy sz).vertexCount
  return vertices

/-- Streaming-startup shape: every task result alive until drained. -/
def meshParallelRetaining (world : World) : Nat := Id.run do
  let mut tasks : Array (Task MeshCpu) := #[]
  for (sx, sy, sz) in sectionsOf world do
    tasks := tasks.push (Task.spawn fun _ => buildSectionCpu world sx sy sz)
  let mut vertices := 0
  for task in tasks do
    vertices := vertices + task.get.vertexCount
  return vertices

/-- Upload-prep shape: build, pack to bytes, drop, per section. -/
def meshAndPackDropping (world : World) : Nat := Id.run do
  let mut bytes := 0
  for (sx, sy, sz) in sectionsOf world do
    let mesh := buildSectionCpu world sx sy sz
    bytes := bytes + (floatArrayBytes mesh.positions).size
      + (floatArrayBytes mesh.normals).size + mesh.colors.size
  return bytes

def phase (label : String) (worlds : Array World) (run : World → Nat)
    (unit : String) : IO Unit := do
  IO.println label
  for world in worlds do
    let t0 ← IO.monoMsNow
    let out := run world
    let t1 ← IO.monoMsNow
    IO.println s!"  {t1 - t0} ms ({out} {unit})"

def main : IO Unit := do
  IO.println "AXIOM startup microbenchmark (CPU phases; GPU upload excluded)"
  IO.println s!"world {worldWidth}x{worldHeight}x{worldDepth} = {worldVolume} voxels; {totalSections} sections of {sectionSize}^3"
  let seeds : Array UInt64 := #[0xa710f1, 0xbeef01, 0x51de77]

  IO.println "[1] generateWorld:"
  let mut worlds : Array World := #[]
  for seed in seeds do
    let t0 ← IO.monoMsNow
    let world := generateWorld seed
    let t1 ← IO.monoMsNow
    worlds := worlds.push world
    IO.println s!"  seed {seed}: {t1 - t0} ms ({world.voxels.size} voxels)"

  IO.println "[2] audio synthesis (4 sounds, loadAudioBank shape):"
  let t0 ← IO.monoMsNow
  let bank := #[synthWav 0 0.075, synthWav 1 0.13, synthWav 2 0.11, synthWav 3 0.15]
  let t1 ← IO.monoMsNow
  IO.println s!"  {t1 - t0} ms ({bank.foldl (fun s b => s + b.size) 0} WAV bytes)"

  phase "[3] full-island CPU meshing, synchronous, drop-per-section (current shape):"
    worlds meshSyncDropping "vertices"
  phase "[4] full-island CPU meshing, parallel tasks, all results retained (streaming shape):"
    worlds meshParallelRetaining "vertices"
  phase "[5] build + pack per section, dropped (CPU half of uploadMeshCpu):"
    worlds meshAndPackDropping "packed bytes"
