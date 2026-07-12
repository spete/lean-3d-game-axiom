import Axiom.Physics
import Raylib

open Raymath

namespace Axiom

structure Particle where
  position : Vector3
  velocity : Vector3
  color : Rgba
  life : Float32
  size : Float32

@[inline] def particleRandom (seed i salt : Nat) : Float32 :=
  let raw := (hash2 (UInt64.ofNat seed + 0xeffec7) (i + salt * 101) (salt + i * 19) % 2001).toNat
  raw.toFloat32 / 1000 - 1

def spawnBlockParticles (block : UInt8) (x y z seed count : Nat) : Array Particle := Id.run do
  let mut particles := #[]
  let base := Block.color block
  for i in [0:count] do
    let rx := particleRandom seed i 1
    let ry := particleRandom seed i 2
    let rz := particleRandom seed i 3
    let speed := 1.7 + (particleRandom seed i 4 + 1) * 1.4
    let position : Vector3 := ⟨x.toFloat32 + 0.5 + rx * 0.28,
      y.toFloat32 + 0.5 + ry * 0.28, z.toFloat32 + 0.5 + rz * 0.28⟩
    let velocity : Vector3 := ⟨rx * speed, (0.7 + ry.abs) * speed, rz * speed⟩
    particles := particles.push {
      position
      velocity
      color := base
      life := 0.38 + (particleRandom seed i 5 + 1) * 0.17
      size := 0.07 + (particleRandom seed i 6 + 1) * 0.035
    }
  return particles

def updateParticles (particles : Array Particle) (dtRaw : Float32) : Array Particle := Id.run do
  let dt := min 0.033 dtRaw
  let mut alive := #[]
  for particle in particles do
    let life := particle.life - dt
    if life > 0 then
      let velocity : Vector3 := ⟨particle.velocity.x * 0.985,
        particle.velocity.y - 10.5 * dt, particle.velocity.z * 0.985⟩
      alive := alive.push {
        particle with
        position := vadd particle.position (vmul velocity dt)
        velocity := velocity
        life := life
      }
  return alive

def drawParticles (particles : Array Particle) : BaseIO Unit := do
  for particle in particles do
    let alpha := UInt8.ofNat (min 255 (80 + (particle.life * 310).toUInt32.toNat))
    let color := Raylib.Color.fromRgba particle.color.r particle.color.g particle.color.b alpha
    Raylib.drawCubeV particle.position ⟨particle.size, particle.size, particle.size⟩ color

end Axiom
