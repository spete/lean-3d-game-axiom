import Axiom.World
import Raylib
import Pod

namespace Axiom

@[inline] def audioPushU16 (bytes : ByteArray) (value : UInt16) : ByteArray :=
  bytes.push value.toUInt8 |>.push (value >>> 8).toUInt8

@[inline] def audioPushU32 (bytes : ByteArray) (value : UInt32) : ByteArray :=
  bytes
    |>.push value.toUInt8
    |>.push (value >>> 8).toUInt8
    |>.push (value >>> 16).toUInt8
    |>.push (value >>> 24).toUInt8

def pushAscii (bytes : ByteArray) (text : Array UInt8) : ByteArray := Id.run do
  let mut out := bytes
  for byte in text do out := out.push byte
  return out

@[inline] def audioNoise (kind i : Nat) : Float32 :=
  let raw := (hash2 (0xa710d10 + UInt64.ofNat kind) i (i * 17 + kind * 31) % 2001).toNat
  raw.toFloat32 / 1000 - 1

def synthSample (kind : Nat) (t duration : Float32) : Float32 :=
  let phase (frequency : Float32) := (6.2831853 * frequency * t).sin
  let life := max 0 (1 - t / duration)
  let value :=
    match kind with
    | 0 => (phase 620 * 0.55 + phase 930 * 0.2) * life * life
    | 1 => (audioNoise kind (t * 44100).toUInt32.toNat * 0.72 + phase 105 * 0.28) * life
    | 2 => (phase 132 * 0.72 + phase 66 * 0.28) * life * life
    | _ => phase (300 + 420 * (t / duration)) * life * 0.72
  max (-1) (min 1 value)

def synthWav (kind : Nat) (duration : Float32) : ByteArray := Id.run do
  let sampleRate : Nat := 44100
  let frameCount := (duration * sampleRate.toFloat32).toUInt32.toNat
  let dataSize := frameCount * 2
  let mut out := ByteArray.emptyWithCapacity (44 + dataSize)
  out := pushAscii out #[82, 73, 70, 70] -- RIFF
  out := audioPushU32 out (UInt32.ofNat (36 + dataSize))
  out := pushAscii out #[87, 65, 86, 69] -- WAVE
  out := pushAscii out #[102, 109, 116, 32] -- fmt
  out := audioPushU32 out 16
  out := audioPushU16 out 1
  out := audioPushU16 out 1
  out := audioPushU32 out (UInt32.ofNat sampleRate)
  out := audioPushU32 out (UInt32.ofNat (sampleRate * 2))
  out := audioPushU16 out 2
  out := audioPushU16 out 16
  out := pushAscii out #[100, 97, 116, 97] -- data
  out := audioPushU32 out (UInt32.ofNat dataSize)
  for i in [0:frameCount] do
    let t := i.toFloat32 / sampleRate.toFloat32
    let signed := (synthSample kind t duration * 30000).toInt32.toInt
    let raw : Nat := if signed < 0 then (signed + 65536).toNat else signed.toNat
    out := audioPushU16 out (UInt16.ofNat raw)
  return out

def loadSynthSound (ctx : Raylib.Context) (kind : Nat) (duration volume : Float32) : BaseIO (Option Raylib.Sound) := do
  let bytes := synthWav kind duration
  let wave := Raylib.loadWaveFromMemory ".wav" bytes.view
  let sound := Raylib.loadSoundFromWave ctx wave
  if Raylib.isSoundValid sound then
    Raylib.setSoundVolume sound volume
    return some sound
  else return none

structure AudioBank where
  ui : Option Raylib.Sound := none
  breakBlock : Option Raylib.Sound := none
  placeBlock : Option Raylib.Sound := none
  jump : Option Raylib.Sound := none

def loadAudioBank (ctx : Raylib.Context) : BaseIO AudioBank := do
  if !(← Raylib.isAudioDeviceReady) then return {}
  return {
    ui := ← loadSynthSound ctx 0 0.075 0.25
    breakBlock := ← loadSynthSound ctx 1 0.13 0.34
    placeBlock := ← loadSynthSound ctx 2 0.11 0.38
    jump := ← loadSynthSound ctx 3 0.15 0.22
  }

@[inline] def playSound? (sound : Option Raylib.Sound) : BaseIO Unit := do
  if let some value := sound then Raylib.playSound value

end Axiom
