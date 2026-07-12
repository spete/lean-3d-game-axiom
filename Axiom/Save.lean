import Axiom.Physics

open Raymath

namespace Axiom

def saveVersion : UInt32 := 2
def saveHeaderSize : Nat := 62

@[inline] def pushU32 (bytes : ByteArray) (value : UInt32) : ByteArray :=
  bytes
    |>.push value.toUInt8
    |>.push (value >>> 8).toUInt8
    |>.push (value >>> 16).toUInt8
    |>.push (value >>> 24).toUInt8

@[inline] def pushU64 (bytes : ByteArray) (value : UInt64) : ByteArray :=
  bytes
    |>.push value.toUInt8
    |>.push (value >>> 8).toUInt8
    |>.push (value >>> 16).toUInt8
    |>.push (value >>> 24).toUInt8
    |>.push (value >>> 32).toUInt8
    |>.push (value >>> 40).toUInt8
    |>.push (value >>> 48).toUInt8
    |>.push (value >>> 56).toUInt8

@[inline] def pushF32 (bytes : ByteArray) (value : Float32) : ByteArray :=
  pushU32 bytes value.toBits

@[inline] def readU32 (bytes : ByteArray) (offset : Nat) : UInt32 :=
  (bytes.get! offset).toUInt32 |||
  ((bytes.get! (offset + 1)).toUInt32 <<< 8) |||
  ((bytes.get! (offset + 2)).toUInt32 <<< 16) |||
  ((bytes.get! (offset + 3)).toUInt32 <<< 24)

@[inline] def readU64 (bytes : ByteArray) (offset : Nat) : UInt64 :=
  (bytes.get! offset).toUInt64 |||
  ((bytes.get! (offset + 1)).toUInt64 <<< 8) |||
  ((bytes.get! (offset + 2)).toUInt64 <<< 16) |||
  ((bytes.get! (offset + 3)).toUInt64 <<< 24) |||
  ((bytes.get! (offset + 4)).toUInt64 <<< 32) |||
  ((bytes.get! (offset + 5)).toUInt64 <<< 40) |||
  ((bytes.get! (offset + 6)).toUInt64 <<< 48) |||
  ((bytes.get! (offset + 7)).toUInt64 <<< 56)

@[inline] def readF32 (bytes : ByteArray) (offset : Nat) : Float32 :=
  Float32.ofBits (readU32 bytes offset)

def checksum (bytes : ByteArray) (stop : Nat := bytes.size) : UInt32 := Id.run do
  let mut hash : UInt32 := 2166136261
  for i in [0:min stop bytes.size] do
    hash := (hash ^^^ (bytes.get! i).toUInt32) * 16777619
  return hash

def validVoxelIds (voxels : ByteArray) : Bool := Id.run do
  for block in voxels do
    if block > Block.maxId then return false
  return true

def encodeSave (world : World) (player : Player) : ByteArray := Id.run do
  let mut bytes := ByteArray.emptyWithCapacity (saveHeaderSize + world.voxels.size + 4)
  bytes := bytes.push 65 |>.push 88 |>.push 77 |>.push 49 -- AXM1
  bytes := pushU32 bytes saveVersion
  bytes := pushU32 bytes (UInt32.ofNat worldWidth)
  bytes := pushU32 bytes (UInt32.ofNat worldDepth)
  bytes := pushU32 bytes (UInt32.ofNat worldHeight)
  bytes := pushU64 bytes world.seed
  bytes := pushF32 bytes player.position.x
  bytes := pushF32 bytes player.position.y
  bytes := pushF32 bytes player.position.z
  bytes := pushF32 bytes player.velocity.x
  bytes := pushF32 bytes player.velocity.y
  bytes := pushF32 bytes player.velocity.z
  bytes := pushF32 bytes player.yaw
  bytes := pushF32 bytes player.pitch
  bytes := bytes.push (if player.flying then 1 else 0)
  bytes := bytes.push (UInt8.ofNat player.selected)
  bytes := bytes ++ world.voxels
  return pushU32 bytes (checksum bytes)

def decodeSave (bytes : ByteArray) : Option (World × Player) := do
  let expectedSize := saveHeaderSize + worldVolume + 4
  if bytes.size != expectedSize then none else pure ()
  if bytes.get! 0 != 65 || bytes.get! 1 != 88 || bytes.get! 2 != 77 || bytes.get! 3 != 49 then none else pure ()
  if readU32 bytes 4 != saveVersion then none else pure ()
  if readU32 bytes 8 != UInt32.ofNat worldWidth ||
      readU32 bytes 12 != UInt32.ofNat worldDepth ||
      readU32 bytes 16 != UInt32.ofNat worldHeight then none else pure ()
  if readU32 bytes (bytes.size - 4) != checksum bytes (bytes.size - 4) then none else pure ()
  let world : World := {
    seed := readU64 bytes 20
    voxels := bytes.extract saveHeaderSize (saveHeaderSize + worldVolume)
  }
  let player : Player := {
    position := ⟨readF32 bytes 28, readF32 bytes 32, readF32 bytes 36⟩
    velocity := ⟨readF32 bytes 40, readF32 bytes 44, readF32 bytes 48⟩
    yaw := readF32 bytes 52
    pitch := readF32 bytes 56
    flying := bytes.get! 60 != 0
    selected := min (bytes.get! 61).toNat (Block.palette.size - 1)
  }
  let finitePlayer := player.position.x.isFinite && player.position.y.isFinite && player.position.z.isFinite &&
    player.velocity.x.isFinite && player.velocity.y.isFinite && player.velocity.z.isFinite &&
    player.yaw.isFinite && player.pitch.isFinite
  if finitePlayer && validVoxelIds world.voxels then
    some (world, player)
  else none

def saveFileName : String := "first-light.axm"

def saveDirectory : IO System.FilePath := do
  if System.Platform.isWindows then
    let appData ← IO.getEnv "APPDATA"
    return System.FilePath.mk (appData.getD ".") / "Axiom"
  else
    let home ← IO.getEnv "HOME"
    return System.FilePath.mk ((home.getD ".") ++ "/Library/Application Support/Axiom")

def savePath : IO System.FilePath := do
  return (← saveDirectory) / saveFileName

def saveGameAt (directory : System.FilePath) (world : World) (player : Player) : IO Unit := do
  IO.FS.createDirAll directory
  let path := directory / saveFileName
  let temp := System.FilePath.mk (path.toString ++ ".tmp")
  IO.FS.writeBinFile temp (encodeSave world player)
  IO.FS.rename temp path

def saveGame (world : World) (player : Player) : IO Unit := do
  saveGameAt (← saveDirectory) world player

def loadGameAt? (directory : System.FilePath) : IO (Option (World × Player)) := do
  let path := directory / saveFileName
  try
    let bytes ← IO.FS.readBinFile path
    match decodeSave bytes with
    | some state => return some state
    | none =>
      -- Never silently overwrite a damaged or incompatible world. Move it
      -- aside before starting a fresh island so manual recovery stays possible.
      let nonce ← IO.monoMsNow
      let backup := directory / s!"first-light.corrupt-{nonce}.axm"
      try IO.FS.rename path backup catch _ => pure ()
      return none
  catch _ =>
    return none

def loadGame? : IO (Option (World × Player)) := do
  loadGameAt? (← saveDirectory)

end Axiom
