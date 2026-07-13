import Axiom.World
import Raylib
import Pod

open Raymath

namespace Axiom

structure MeshCpu where
  positions : Array Float32 := #[]
  normals : Array Float32 := #[]
  colors : Array UInt8 := #[]

def MeshCpu.vertexCount (mesh : MeshCpu) : Nat := mesh.positions.size / 3

@[inline] def clampByte (value : Int) : UInt8 :=
  UInt8.ofNat (max 0 (min 255 value) |>.toNat)

def shadeColor (base : Rgba) (face : Nat) (x y z : Nat) : Rgba :=
  let faceLight : Int :=
    match face with
    | 0 => 24   -- top
    | 1 => -42  -- bottom
    | 2 => -12  -- north
    | 3 => 5    -- south
    | 4 => -24  -- west
    | _ => -4   -- east
  let grain := Int.ofNat ((hash2 0x51ade x (z + y * 31)) % 13).toNat - 6
  let adjust (channel : UInt8) := clampByte (Int.ofNat channel.toNat + faceLight + grain)
  ⟨adjust base.r, adjust base.g, adjust base.b, base.a⟩

@[inline] def MeshCpu.pushVertex
    (mesh : MeshCpu) (position normal : Vector3) (color : Rgba) : MeshCpu :=
  -- Destructure before pushing: consuming `mesh` first makes each field
  -- uniquely referenced, so every push is an in-place append. Projecting
  -- fields out of a still-live record shares them and each push then
  -- copies the whole array — an accidental O(n²) that dominated startup.
  let ⟨positions, normals, colors⟩ := mesh
  { positions := positions
      |>.push position.x |>.push position.y |>.push position.z
    normals := normals
      |>.push normal.x |>.push normal.y |>.push normal.z
    colors := colors
      |>.push color.r |>.push color.g |>.push color.b |>.push color.a }

def faceGeometry (face : Nat) (x y z : Nat) : Vector3 × Array Vector3 :=
  let x0 := x.toFloat32
  let y0 := y.toFloat32
  let z0 := z.toFloat32
  let x1 := (x + 1).toFloat32
  let y1 := (y + 1).toFloat32
  let z1 := (z + 1).toFloat32
  match face with
  | 0 => (⟨0, 1, 0⟩, #[⟨x0,y1,z0⟩, ⟨x0,y1,z1⟩, ⟨x1,y1,z1⟩, ⟨x1,y1,z0⟩])
  | 1 => (⟨0,-1, 0⟩, #[⟨x0,y0,z0⟩, ⟨x1,y0,z0⟩, ⟨x1,y0,z1⟩, ⟨x0,y0,z1⟩])
  | 2 => (⟨0, 0,-1⟩, #[⟨x0,y0,z0⟩, ⟨x0,y1,z0⟩, ⟨x1,y1,z0⟩, ⟨x1,y0,z0⟩])
  | 3 => (⟨0, 0, 1⟩, #[⟨x1,y0,z1⟩, ⟨x1,y1,z1⟩, ⟨x0,y1,z1⟩, ⟨x0,y0,z1⟩])
  | 4 => (⟨-1,0, 0⟩, #[⟨x0,y0,z1⟩, ⟨x0,y1,z1⟩, ⟨x0,y1,z0⟩, ⟨x0,y0,z0⟩])
  | _ => (⟨1, 0, 0⟩, #[⟨x1,y0,z0⟩, ⟨x1,y1,z0⟩, ⟨x1,y1,z1⟩, ⟨x1,y0,z1⟩])

def emitFace (mesh : MeshCpu) (block : UInt8) (face x y z : Nat) : MeshCpu := Id.run do
  let (normal, corners) := faceGeometry face x y z
  let color := shadeColor (Block.color block) face x y z
  let order : Array Nat := #[0, 1, 2, 0, 2, 3]
  let mut out := mesh
  for i in order do
    out := out.pushVertex corners[i]! normal color
  return out

def neighborForFace (face x y z : Nat) : Int × Int × Int :=
  let xi := Int.ofNat x
  let yi := Int.ofNat y
  let zi := Int.ofNat z
  match face with
  | 0 => (xi, yi + 1, zi)
  | 1 => (xi, yi - 1, zi)
  | 2 => (xi, yi, zi - 1)
  | 3 => (xi, yi, zi + 1)
  | 4 => (xi - 1, yi, zi)
  | _ => (xi + 1, yi, zi)

def buildSectionCpu (world : World) (sectionX sectionY sectionZ : Nat) : MeshCpu := Id.run do
  let startX := sectionX * sectionSize
  let startY := sectionY * sectionSize
  let startZ := sectionZ * sectionSize
  let stopX := Nat.min worldWidth (startX + sectionSize)
  let stopY := Nat.min worldHeight (startY + sectionSize)
  let stopZ := Nat.min worldDepth (startZ + sectionSize)
  let mut mesh : MeshCpu := {}
  for x in [startX:stopX] do
    for y in [startY:stopY] do
      for z in [startZ:stopZ] do
        let block := world.get x y z
        if Block.isSolid block then
          for face in [0:6] do
            let (nx, ny, nz) := neighborForFace face x y z
            if !Block.isSolid (world.getI nx ny nz) then
              mesh := emitFace mesh block face x y z
  return mesh

@[inline] def pushFloatBytes (bytes : ByteArray) (value : Float32) : ByteArray :=
  let bits := value.toBits
  bytes
    |>.push bits.toUInt8
    |>.push (bits >>> 8).toUInt8
    |>.push (bits >>> 16).toUInt8
    |>.push (bits >>> 24).toUInt8

def floatArrayBytes (values : Array Float32) : ByteArray := Id.run do
  let mut bytes := ByteArray.emptyWithCapacity (values.size * 4)
  for value in values do
    bytes := pushFloatBytes bytes value
  return bytes

def uploadMeshCpu (ctx : Raylib.Context) (cpu : MeshCpu) : IO (Option Raylib.Mesh) := do
  let vertexCount : UInt32 := UInt32.ofNat cpu.vertexCount
  if vertexCount == 0 then return none
  let packedPositions := floatArrayBytes cpu.positions
  let packedNormals := floatArrayBytes cpu.normals
  let packedColors : ByteArray := ⟨cpu.colors⟩
  if hp : packedPositions.size = vertexCount.toNat * 3 * Pod.byteSize Float32 then
    if hn : packedNormals.size = vertexCount.toNat * 3 * Pod.byteSize Float32 then
      if hc : packedColors.size = vertexCount.toNat * 4 * Pod.byteSize UInt8 then
        let positionBytes : Pod.BytesView (vertexCount.toNat * 3 * Pod.byteSize Float32) 1 :=
          hp ▸ packedPositions.view
        let normalBytes : Pod.BytesView (vertexCount.toNat * 3 * Pod.byteSize Float32) 1 :=
          hn ▸ packedNormals.view
        let colorBytes : Pod.BytesView (vertexCount.toNat * 4 * Pod.byteSize UInt8) 1 :=
          hc ▸ packedColors.view
        let mesh := Raylib.Mesh.mkBv ctx vertexCount positionBytes
          none none (some normalBytes) none (some colorBytes) none
        let uploaded ← Raylib.uploadMesh mesh false
        return some uploaded
      else return none
    else return none
  else return none

def sectionCountX : Nat := (worldWidth + sectionSize - 1) / sectionSize
def sectionCountY : Nat := (worldHeight + sectionSize - 1) / sectionSize
def sectionCountZ : Nat := (worldDepth + sectionSize - 1) / sectionSize
def totalSections : Nat := sectionCountX * sectionCountY * sectionCountZ

@[inline] def sectionIndex (sx sy sz : Nat) : Nat :=
  (sy * sectionCountZ + sz) * sectionCountX + sx

structure GpuWorld where
  sections : Array (Option Raylib.Mesh)

def buildGpuWorld (ctx : Raylib.Context) (world : World) : IO GpuWorld := do
  let mut sections : Array (Option Raylib.Mesh) := Array.replicate totalSections none
  for sx in [0:sectionCountX] do
    for sy in [0:sectionCountY] do
      for sz in [0:sectionCountZ] do
        let cpu := buildSectionCpu world sx sy sz
        let mesh ← uploadMeshCpu ctx cpu
        sections := sections.set! (sectionIndex sx sy sz) mesh
  return { sections }

def drawGpuWorld (gpu : GpuWorld) (material : Raylib.Material) : BaseIO Unit := do
  for entry in gpu.sections do
    if let some mesh := entry then
      Raylib.drawMesh mesh material Matrix.identity

def GpuWorld.rebuildSection (gpu : GpuWorld) (ctx : Raylib.Context) (world : World)
    (sx sy sz : Nat) : IO GpuWorld := do
  if sx ≥ sectionCountX || sy ≥ sectionCountY || sz ≥ sectionCountZ then return gpu
  let mesh ← uploadMeshCpu ctx (buildSectionCpu world sx sy sz)
  return { gpu with sections := gpu.sections.set! (sectionIndex sx sy sz) mesh }

def GpuWorld.rebuildAround (gpu : GpuWorld) (ctx : Raylib.Context) (world : World)
    (x y z : Nat) : IO GpuWorld := do
  let sx := x / sectionSize
  let sy := y / sectionSize
  let sz := z / sectionSize
  let mut out ← gpu.rebuildSection ctx world sx sy sz
  if x % sectionSize == 0 && sx > 0 then out ← out.rebuildSection ctx world (sx - 1) sy sz
  if x % sectionSize == sectionSize - 1 then out ← out.rebuildSection ctx world (sx + 1) sy sz
  if y % sectionSize == 0 && sy > 0 then out ← out.rebuildSection ctx world sx (sy - 1) sz
  if y % sectionSize == sectionSize - 1 then out ← out.rebuildSection ctx world sx (sy + 1) sz
  if z % sectionSize == 0 && sz > 0 then out ← out.rebuildSection ctx world sx sy (sz - 1)
  if z % sectionSize == sectionSize - 1 then out ← out.rebuildSection ctx world sx sy (sz + 1)
  return out

structure PendingMeshJob where
  sx : Nat
  sy : Nat
  sz : Nat
  task : Task MeshCpu

def affectedSections (x y z : Nat) : Array (Nat × Nat × Nat) := Id.run do
  let sx := x / sectionSize
  let sy := y / sectionSize
  let sz := z / sectionSize
  let mut sections := #[(sx, sy, sz)]
  if x % sectionSize == 0 && sx > 0 then sections := sections.push (sx - 1, sy, sz)
  if x % sectionSize == sectionSize - 1 && sx + 1 < sectionCountX then
    sections := sections.push (sx + 1, sy, sz)
  if y % sectionSize == 0 && sy > 0 then sections := sections.push (sx, sy - 1, sz)
  if y % sectionSize == sectionSize - 1 && sy + 1 < sectionCountY then
    sections := sections.push (sx, sy + 1, sz)
  if z % sectionSize == 0 && sz > 0 then sections := sections.push (sx, sy, sz - 1)
  if z % sectionSize == sectionSize - 1 && sz + 1 < sectionCountZ then
    sections := sections.push (sx, sy, sz + 1)
  return sections

def enqueueMeshRebuilds (pending : Array PendingMeshJob) (world : World)
    (x y z : Nat) : BaseIO (Array PendingMeshJob) := do
  let mut jobs := pending
  for (sx, sy, sz) in affectedSections x y z do
    let mut withoutOlder := #[]
    for job in jobs do
      if job.sx != sx || job.sy != sy || job.sz != sz then
        withoutOlder := withoutOlder.push job
    let task := Task.spawn (fun _ => buildSectionCpu world sx sy sz)
    jobs := withoutOlder.push { sx, sy, sz, task }
  return jobs

def processOneMeshJob (gpu : GpuWorld) (ctx : Raylib.Context)
    (pending : Array PendingMeshJob) : IO (GpuWorld × Array PendingMeshJob) := do
  let mut nextGpu := gpu
  let mut remaining := #[]
  let mut processed := false
  for job in pending do
    if !processed && (← IO.hasFinished job.task) then
      let mesh ← uploadMeshCpu ctx job.task.get
      nextGpu := { nextGpu with
        sections := nextGpu.sections.set! (sectionIndex job.sx job.sy job.sz) mesh }
      processed := true
    else
      remaining := remaining.push job
  return (nextGpu, remaining)

end Axiom
