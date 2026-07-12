namespace Axiom

def worldWidth : Nat := 96
def worldDepth : Nat := 96
def worldHeight : Nat := 48
def worldVolume : Nat := worldWidth * worldDepth * worldHeight
def seaLevel : Nat := 10
def sectionSize : Nat := 16

structure Rgba where
  r : UInt8
  g : UInt8
  b : UInt8
  a : UInt8 := 255
deriving Inhabited, Repr, BEq

namespace Block

def air : UInt8 := 0
def grass : UInt8 := 1
def dirt : UInt8 := 2
def stone : UInt8 := 3
def sand : UInt8 := 4
def wood : UInt8 := 5
def leaves : UInt8 := 6
def marble : UInt8 := 7
def brick : UInt8 := 8
def glow : UInt8 := 9
def bedrock : UInt8 := 10

def maxId : UInt8 := bedrock

def isSolid (block : UInt8) : Bool := block != air

def name (block : UInt8) : String :=
  if block == grass then "Meadow grass"
  else if block == dirt then "Earth"
  else if block == stone then "Blue stone"
  else if block == sand then "Warm sand"
  else if block == wood then "Cedar wood"
  else if block == leaves then "Cedar leaves"
  else if block == marble then "Pale marble"
  else if block == brick then "Sunset brick"
  else if block == glow then "Sun crystal"
  else if block == bedrock then "Deep rock"
  else "Air"

def color (block : UInt8) : Rgba :=
  if block == grass then { r := 104, g := 157, b := 92 }
  else if block == dirt then { r := 126, g := 91, b := 66 }
  else if block == stone then { r := 105, g := 119, b := 126 }
  else if block == sand then { r := 218, g := 190, b := 130 }
  else if block == wood then { r := 125, g := 82, b := 53 }
  else if block == leaves then { r := 68, g := 128, b := 83 }
  else if block == marble then { r := 218, g := 211, b := 191 }
  else if block == brick then { r := 174, g := 88, b := 65 }
  else if block == glow then { r := 255, g := 194, b := 78 }
  else if block == bedrock then { r := 48, g := 53, b := 62 }
  else ⟨255, 255, 255, 0⟩

def palette : Array UInt8 :=
  #[grass, dirt, stone, sand, wood, leaves, marble, brick, glow]

end Block

structure World where
  voxels : ByteArray
  seed : UInt64
deriving Inhabited

@[inline] def voxelIndex (x y z : Nat) : Nat :=
  (y * worldDepth + z) * worldWidth + x

def validCoord (x y z : Nat) : Bool :=
  x < worldWidth && y < worldHeight && z < worldDepth

@[inline] def World.get (world : World) (x y z : Nat) : UInt8 :=
  if validCoord x y z then world.voxels.get! (voxelIndex x y z) else Block.air

def World.getI (world : World) (x y z : Int) : UInt8 :=
  if x < 0 || y < 0 || z < 0 then Block.air
  else
    let xn := x.toNat
    let yn := y.toNat
    let zn := z.toNat
    world.get xn yn zn

@[inline] def World.set (world : World) (x y z : Nat) (block : UInt8) : World :=
  if validCoord x y z then
    { world with voxels := world.voxels.set! (voxelIndex x y z) block }
  else world

def World.setI (world : World) (x y z : Int) (block : UInt8) : World :=
  if x < 0 || y < 0 || z < 0 then world
  else world.set x.toNat y.toNat z.toNat block

def emptyVoxels : ByteArray := Id.run do
  let mut voxels := ByteArray.emptyWithCapacity worldVolume
  for _ in [0:worldVolume] do
    voxels := voxels.push Block.air
  return voxels

@[inline] def mix64 (value : UInt64) : UInt64 :=
  let v1 := (value ^^^ (value >>> 30)) * 0xbf58476d1ce4e5b9
  let v2 := (v1 ^^^ (v1 >>> 27)) * 0x94d049bb133111eb
  v2 ^^^ (v2 >>> 31)

@[inline] def hash2 (seed : UInt64) (x z : Nat) : UInt64 :=
  mix64 (seed + UInt64.ofNat x * 0x9e3779b97f4a7c15 + UInt64.ofNat z * 0xc2b2ae3d27d4eb4f)

def latticeNoise (seed : UInt64) (gx gz : Nat) : Int :=
  Int.ofNat ((hash2 seed gx gz) % 101).toNat - 50

def lerpInt (a b : Int) (t scale : Nat) : Int :=
  if scale == 0 then a
  else
    let ti := Int.ofNat t
    let si := Int.ofNat scale
    (a * (si - ti) + b * ti) / si

def smoothNoise (seed : UInt64) (scale x z : Nat) : Int :=
  let gx := x / scale
  let gz := z / scale
  let fx := x % scale
  let fz := z % scale
  let a := latticeNoise seed gx gz
  let b := latticeNoise seed (gx + 1) gz
  let c := latticeNoise seed gx (gz + 1)
  let d := latticeNoise seed (gx + 1) (gz + 1)
  let top := lerpInt a b fx scale
  let bottom := lerpInt c d fx scale
  lerpInt top bottom fz scale

def terrainHeight (seed : UInt64) (x z : Nat) : Nat :=
  let centerX := worldWidth / 2
  let centerZ := worldDepth / 2
  let dx := if x > centerX then x - centerX else centerX - x
  let dz := if z > centerZ then z - centerZ else centerZ - z
  let dist2 := dx * dx + dz * dz
  if dist2 > 45 * 45 then
    seaLevel - 4
  else
    let broad := smoothNoise seed 18 x z / 7
    let detail := smoothNoise (seed + 0xa11ce) 7 x z / 16
    let ridge : Int :=
      let diagonal := Int.ofNat ((x * 3 + z * 5) % 29)
      (14 - Int.ofNat (diagonal - 14).natAbs) / 5
    let edgeDrop : Int :=
      if dist2 > 31 * 31 then Int.ofNat ((dist2 - 31 * 31) / 58) else 0
    let raw : Int := 17 + broad + detail + ridge - edgeDrop
    max (Int.ofNat (seaLevel - 2)) (min 35 raw) |>.toNat

def topSolidY (world : World) (x z : Nat) : Nat := Id.run do
  let mut result := 0
  for y in [0:worldHeight] do
    if Block.isSolid (world.get x y z) then result := y
  return result

def plantTree (world : World) (x z trunkHeight : Nat) : World := Id.run do
  let ground := terrainHeight world.seed x z
  let mut out := world
  for dy in [1:trunkHeight + 1] do
    out := out.set x (ground + dy) z Block.wood
  let crownY := ground + trunkHeight
  for ox in [0:5] do
    for oz in [0:5] do
      for oy in [0:4] do
        let dx : Int := Int.ofNat ox - 2
        let dz : Int := Int.ofNat oz - 2
        let dy : Int := Int.ofNat oy - 1
        let manhattan := dx.natAbs + dz.natAbs + dy.natAbs
        let px := Int.ofNat x + dx
        let py := Int.ofNat crownY + dy
        let pz := Int.ofNat z + dz
        if manhattan ≤ 4 && out.getI px py pz == Block.air then
          out := out.setI px py pz Block.leaves
  if crownY + 2 < worldHeight then
    out := out.set x (crownY + 2) z Block.leaves
  return out

def buildLandmark (world : World) : World := Id.run do
  let mut out := world
  let leftX := 68
  let rightX := 76
  let z := 61
  let baseY := Nat.max (terrainHeight world.seed leftX z) (terrainHeight world.seed rightX z)
  for x in [leftX:rightX + 1] do
    for zz in [z:z + 3] do
      for y in [baseY:baseY + 2] do
        out := out.set x y zz Block.marble
  for x in #[leftX, leftX + 1, rightX - 1, rightX] do
    for zz in [z:z + 3] do
      for y in [baseY:baseY + 15] do
        out := out.set x y zz Block.marble
  for x in [leftX:rightX + 1] do
    for zz in [z:z + 3] do
      for y in [baseY + 13:baseY + 16] do
        out := out.set x y zz Block.marble
  out := out.set (leftX + 1) (baseY + 10) (z + 1) Block.glow
  out := out.set (rightX - 1) (baseY + 10) (z + 1) Block.glow
  out := out.set ((leftX + rightX) / 2) (baseY + 14) (z + 1) Block.glow
  return out

def carveCaves (world : World) : World := Id.run do
  let mut out := world
  -- A deterministic meandering cave crosses the island below the meadow. Its
  -- ends open naturally through the lower coastal slopes, making it findable
  -- without adding a separate dungeon system.
  for x in [8:worldWidth - 8] do
    let centerZ : Int := 48 + smoothNoise (world.seed + 0xcafe) 17 x 3 / 3
    let centerY : Int := 8 + smoothNoise (world.seed + 0x51de) 19 x 11 / 18
    for oz in [0:9] do
      for oy in [0:7] do
        let dz := Int.ofNat oz - 4
        let dy := Int.ofNat oy - 3
        if dz * dz + dy * dy ≤ 12 then
          let y := centerY + dy
          if y > 2 then out := out.setI (Int.ofNat x) y (centerZ + dz) Block.air
  return out

def generateWorld (seed : UInt64 := 0xa710f1) : World := Id.run do
  let mut world : World := { voxels := emptyVoxels, seed }
  for x in [0:worldWidth] do
    for z in [0:worldDepth] do
      let surface := terrainHeight seed x z
      for y in [0:surface + 1] do
        let block :=
          if y == 0 then Block.bedrock
          else if y == surface then
            if surface ≤ seaLevel + 1 then Block.sand else Block.grass
          else if y + 3 ≥ surface then
            if surface ≤ seaLevel + 1 then Block.sand else Block.dirt
          else Block.stone
        world := world.set x y z block

  world := carveCaves world

  for x in [4:worldWidth - 4] do
    for z in [4:worldDepth - 4] do
      let surface := terrainHeight seed x z
      -- Keep a broad meadow around first spawn so the opening view is readable
      -- and players can learn movement before entering the cedar canopy.
      let nearSpawn := x ≥ 34 && x ≤ 62 && z ≥ 34 && z ≤ 62
      let nearLandmark := x ≥ 64 && x ≤ 80 && z ≥ 56 && z ≤ 68
      if surface > seaLevel + 2 && !nearSpawn && !nearLandmark && hash2 (seed + 77) x z % 127 == 0 then
        world := plantTree world x z (3 + (hash2 seed z x % 3).toNat)

  world := buildLandmark world
  return world

def spawnPosition (world : World) : Nat × Nat × Nat :=
  let x := worldWidth / 2
  let z := worldDepth / 2
  (x, topSolidY world x z + 2, z)

end Axiom
