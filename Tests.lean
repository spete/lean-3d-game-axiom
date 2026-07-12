import Axiom

open Axiom
open Raymath

def check (label : String) (condition : Bool) : IO Unit := do
  if condition then
    IO.println ("  ✓ " ++ label)
  else
    throw (IO.userError ("FAILED: " ++ label))

def approx32 (a b epsilon : Float32) : Bool :=
  decide ((a - b).abs ≤ epsilon)

def testEmptyWorld : World :=
  { voxels := emptyVoxels, seed := 0x1234 }

def testFlatWorld : World := Id.run do
  let mut world := testEmptyWorld
  for x in [0:worldWidth] do
    for z in [0:worldDepth] do
      world := world.set x 0 z Block.stone
  return world

def simulatePlayer (world : World) (controls : Controls) (dt : Float32)
    (steps : Nat) (start : Player) : Player := Id.run do
  let mut player := start
  for _ in [0:steps] do player := updatePlayer world controls dt player
  return player

def repairChecksum (bytes : ByteArray) : ByteArray :=
  if bytes.size < 4 then bytes
  else
    let body := bytes.extract 0 (bytes.size - 4)
    pushU32 body (checksum body)

def main : IO Unit := do
  IO.println "AXIOM verification suite"
  let worldA := generateWorld 0xa710f1
  let worldB := generateWorld 0xa710f1
  check "world has exact compact voxel volume" (worldA.voxels.size == worldVolume)
  check "generation is byte-for-byte deterministic" (worldA.voxels.data == worldB.voxels.data)

  let (spawnX, spawnY, spawnZ) := spawnPosition worldA
  check "spawn has solid ground" (Block.isSolid (worldA.get spawnX (spawnY - 2) spawnZ))
  let player := newPlayer worldA
  check "spawn does not intersect terrain" (!playerCollides worldA player.position)

  let changed := worldA.set 12 20 12 Block.brick
  check "block update addresses exact coordinate" (changed.get 12 20 12 == Block.brick)
  check "adjacent coordinate is unchanged" (changed.get 13 20 12 == worldA.get 13 20 12)

  let cpuMesh := buildSectionCpu worldA 3 0 3
  check "section mesh emits complete triangles" (cpuMesh.vertexCount % 3 == 0)
  check "mesh position and normal streams agree" (cpuMesh.positions.size == cpuMesh.normals.size)
  check "mesh color stream matches vertex count" (cpuMesh.colors.size == cpuMesh.vertexCount * 4)

  let rayOrigin : Vector3 := ⟨spawnX.toFloat32 + 0.5, 46, spawnZ.toFloat32 + 0.5⟩
  let hit := raycastVoxel worldA rayOrigin ⟨0,-1,0⟩ 48
  check "voxel DDA hits ground from above" hit.isSome
  if let some h := hit then
    check "ray hit is a solid voxel" (Block.isSolid (worldA.getI h.x h.y h.z))

  IO.println "Physics acceptance"
  let flat := testFlatWorld
  let standing : Player := {
    position := ⟨5.5, 1, 20.5⟩
    yaw := 0
    grounded := true
  }
  let walked := simulatePlayer flat { forward := true } 0.016 60 standing
  check "forward input moves in look direction" (decide (walked.position.z < standing.position.z - 1))
  check "ordinary walking does not drift sideways" (approx32 walked.position.x standing.position.x 0.001)
  check "walking remains grounded" walked.grounded

  let jumped := updatePlayer flat { jumpPressed := true, jumpDown := true } 0.016 standing
  check "grounded jump gives upward velocity" (decide (jumped.velocity.y > 8))
  check "jump leaves the ground" (!jumped.grounded && decide (jumped.position.y > standing.position.y))

  let falling : Player := { standing with position := ⟨5.5, 6, 20.5⟩, grounded := false }
  let landed := simulatePlayer flat {} 0.016 240 falling
  check "gravity lands player on floor" landed.grounded
  check "landing cannot penetrate floor" (decide (landed.position.y ≥ 1) && decide (landed.position.y < 1.1))
  check "vertical velocity clears on landing" (landed.velocity.y == 0)

  let flewUp := updatePlayer flat { toggleFly := true, jumpDown := true } 0.016 standing
  check "fly toggle enters flying mode" flewUp.flying
  check "fly ascent moves upward" (decide (flewUp.position.y > standing.position.y) && decide (flewUp.velocity.y > 0))
  let flewDown := updatePlayer flat { descend := true } 0.016 flewUp
  check "fly descend moves downward" (decide (flewDown.position.y < flewUp.position.y) && decide (flewDown.velocity.y < 0))

  let clampedLongFrame := updatePlayer flat { forward := true } 1.0 standing
  let explicitClamp := updatePlayer flat { forward := true } 0.033 standing
  check "physics clamps pathological frame times"
    (clampedLongFrame.position.x == explicitClamp.position.x &&
      clampedLongFrame.position.y == explicitClamp.position.y &&
      clampedLongFrame.position.z == explicitClamp.position.z)

  let wallWorld : World := Id.run do
    let mut world := flat
    for y in [1:4] do
      for z in [0:worldDepth] do world := world.set 7 y z Block.stone
    return world
  let besideWall : Player := { position := ⟨6.5, 1, 20.5⟩, yaw := 0, grounded := true }
  let slid := simulatePlayer wallWorld { forward := true, right := true } 0.016 120 besideWall
  check "solid wall prevents player penetration" (decide (slid.position.x < 6.72) && !playerCollides wallWorld slid.position)
  check "axis-separated collision permits wall sliding" (decide (slid.position.z < besideWall.position.z - 1))
  check "player overlap test detects occupied placement" (blockIntersectsPlayer besideWall 6 1 20)
  check "player overlap test permits distant placement" (!blockIntersectsPlayer besideWall 8 1 20)

  IO.println "Voxel interaction acceptance"
  let editWorld := testEmptyWorld.set 5 2 5 Block.stone
  let editHit := raycastVoxel editWorld ⟨5.5, 2.5, 2.5⟩ ⟨0, 0, 1⟩ 8
  check "edit ray finds intended block" editHit.isSome
  if let some h := editHit then
    check "ray identifies exact break coordinate" (h.x == 5 && h.y == 2 && h.z == 5)
    check "ray identifies adjacent placement coordinate" (h.placeX == 5 && h.placeY == 2 && h.placeZ == 4)
    let broken := editWorld.setI h.x h.y h.z Block.air
    check "breaking clears targeted voxel" (broken.get 5 2 5 == Block.air)
    let placed := broken.setI h.placeX h.placeY h.placeZ Block.brick
    check "placement writes adjacent voxel" (placed.get 5 2 4 == Block.brick && placed.get 5 2 5 == Block.air)

  IO.println "Section-boundary acceptance"
  let seamWorld := testEmptyWorld |>.set 15 1 5 Block.stone |>.set 16 1 5 Block.stone
  let seamLeft := buildSectionCpu seamWorld 0 0 0
  let seamRight := buildSectionCpu seamWorld 1 0 0
  check "cross-section neighbours hide shared faces" (seamLeft.vertexCount == 30 && seamRight.vertexCount == 30)
  let openedSeam := seamWorld.set 15 1 5 Block.air
  check "boundary edit empties owning section" ((buildSectionCpu openedSeam 0 0 0).vertexCount == 0)
  check "boundary edit exposes adjacent face" ((buildSectionCpu openedSeam 1 0 0).vertexCount == 36)
  check "interior edit schedules one section" ((affectedSections 7 7 7).size == 1)
  check "three-axis seam schedules owner and axial neighbours" ((affectedSections 15 15 15).size == 4)
  check "outer corner never schedules invalid neighbours" ((affectedSections 0 0 0).size == 1)

  let encoded := encodeSave changed player
  check "save has exact versioned size" (encoded.size == saveHeaderSize + worldVolume + 4)
  let decoded := decodeSave encoded
  check "valid save round-trips" decoded.isSome
  if let some (loadedWorld, loadedPlayer) := decoded then
    check "round-trip preserves every voxel" (loadedWorld.voxels.data == changed.voxels.data)
    check "round-trip preserves player position" (loadedPlayer.position.x == player.position.x &&
      loadedPlayer.position.y == player.position.y && loadedPlayer.position.z == player.position.z)

  let corrupt := encoded.set! 128 (encoded.get! 128 ^^^ 0xff)
  check "checksum rejects corrupt save" (decodeSave corrupt).isNone

  IO.println "Save-format acceptance"
  let richPlayer : Player := {
    player with
    velocity := ⟨1.25, -2.5, 3.75⟩
    yaw := 1.1
    pitch := -0.45
    flying := true
    selected := 7
  }
  let richSave := encodeSave changed richPlayer
  if let some (loadedWorld, loadedPlayer) := decodeSave richSave then
    check "round-trip preserves world seed" (loadedWorld.seed == changed.seed)
    check "round-trip preserves velocity"
      (loadedPlayer.velocity.x == richPlayer.velocity.x && loadedPlayer.velocity.y == richPlayer.velocity.y &&
        loadedPlayer.velocity.z == richPlayer.velocity.z)
    check "round-trip preserves camera, flight, and hotbar"
      (loadedPlayer.yaw == richPlayer.yaw && loadedPlayer.pitch == richPlayer.pitch &&
        loadedPlayer.flying == richPlayer.flying && loadedPlayer.selected == richPlayer.selected)
  else throw (IO.userError "FAILED: rich save did not decode")
  check "truncated save is rejected" (decodeSave (richSave.extract 0 (richSave.size - 1))).isNone
  check "oversized save is rejected" (decodeSave (richSave.push 0)).isNone
  check "wrong magic is rejected" (decodeSave (repairChecksum (richSave.set! 0 0))).isNone
  check "unsupported version is rejected" (decodeSave (repairChecksum (richSave.set! 4 99))).isNone
  check "mismatched dimensions are rejected" (decodeSave (repairChecksum (richSave.set! 8 95))).isNone
  let selected255 := repairChecksum (richSave.set! 61 255)
  if let some (_, loadedPlayer) := decodeSave selected255 then
    check "invalid hotbar index is clamped" (loadedPlayer.selected == Block.palette.size - 1)
  else throw (IO.userError "FAILED: clamped hotbar save did not decode")
  let nan : Float32 := Float32.ofBits 0x7fc00000
  check "non-finite position is rejected"
    (decodeSave (encodeSave changed { richPlayer with position := ⟨nan, 2, 3⟩ })).isNone
  check "non-finite velocity is rejected"
    (decodeSave (encodeSave changed { richPlayer with velocity := ⟨nan, 0, 0⟩ })).isNone
  check "non-finite camera is rejected"
    (decodeSave (encodeSave changed { richPlayer with pitch := nan })).isNone
  let invalidVoxelWorld : World := { changed with voxels := changed.voxels.set! 123 255 }
  check "unknown block IDs are rejected" (decodeSave (encodeSave invalidVoxelWorld richPlayer)).isNone

  IO.println "Save persistence acceptance"
  let tempBase ← IO.getEnv "TEMP"
  let saveDir := System.FilePath.mk (tempBase.getD "/tmp") / "axiom-test-saves"
  if ← saveDir.pathExists then IO.FS.removeDirAll saveDir
  saveGameAt saveDir changed richPlayer
  let diskLoaded ← loadGameAt? saveDir
  check "on-disk save round-trips" diskLoaded.isSome
  if let some (diskWorld, diskPlayer) := diskLoaded then
    check "disk round-trip preserves every voxel" (diskWorld.voxels.data == changed.voxels.data)
    check "disk round-trip preserves hotbar" (diskPlayer.selected == richPlayer.selected)
  check "missing save loads as none" (← loadGameAt? (saveDir / "nowhere")).isNone
  IO.FS.writeBinFile (saveDir / saveFileName) (ByteArray.mk #[1, 2, 3])
  check "corrupt save on disk loads as none" (← loadGameAt? saveDir).isNone
  check "corrupt save is moved aside, not left in place"
    (!(← (saveDir / saveFileName).pathExists))
  let entries ← saveDir.readDir
  check "corrupt save is quarantined on disk"
    (entries.any (fun entry => entry.fileName.startsWith "first-light.corrupt-"))
  IO.FS.removeDirAll saveDir

  IO.println "Effects acceptance"
  let wav := synthWav 1 0.1
  check "procedural sound is a complete PCM WAV" (wav.size > 44 && wav.get! 0 == 82 && wav.get! 8 == 87)
  let burst := spawnBlockParticles Block.brick 5 6 7 42 18
  check "block burst creates requested particle count" (burst.size == 18)
  check "particles advance while alive" ((updateParticles burst 0.016).size == burst.size)
  IO.println "All Axiom checks passed."
