import Axiom.World
import Raymath

open Raymath

namespace Axiom

@[inline] def vadd (a b : Vector3) : Vector3 := ⟨a.x + b.x, a.y + b.y, a.z + b.z⟩
@[inline] def vsub (a b : Vector3) : Vector3 := ⟨a.x - b.x, a.y - b.y, a.z - b.z⟩
@[inline] def vmul (v : Vector3) (s : Float32) : Vector3 := ⟨v.x * s, v.y * s, v.z * s⟩
@[inline] def vlength (v : Vector3) : Float32 := (v.x*v.x + v.y*v.y + v.z*v.z).sqrt

def vnormalize (v : Vector3) : Vector3 :=
  let len := vlength v
  if len < 0.0001 then ⟨0,0,0⟩ else vmul v (1 / len)

@[inline] def clamp32 (lo hi value : Float32) : Float32 := max lo (min hi value)

def floorInt (value : Float32) : Int := value.floor.toInt32.toInt

/-! The named simulation constants below are the single source of truth for
both the physics code and the formal step-bound specifications in
`Axiom/Theorems.lean`. Keeping them named (rather than inline literals)
is what lets the theorems constrain the live values: rebalancing one of
these re-evaluates the proofs. -/

/-- Half-width of the player's collision box, in blocks. -/
def playerRadius : Float32 := 0.29

/-- Height of the player's collision box, in blocks. -/
def playerHeight : Float32 := 1.78

/-- Upper bound applied to a frame's simulation timestep, in seconds. -/
def maxPhysicsDt : Float32 := 0.033

/-- Terminal falling speed, in blocks per second. -/
def maxFallSpeed : Float32 := 30.0

/-- Flying movement speed — the fastest horizontal speed, in blocks per
second. -/
def flySpeed : Float32 := 10.5

structure Player where
  position : Vector3
  velocity : Vector3 := ⟨0,0,0⟩
  yaw : Float32 := 0.65
  pitch : Float32 := -0.14
  grounded : Bool := false
  flying : Bool := false
  selected : Nat := 0
deriving Inhabited, Repr

def newPlayer (world : World) : Player :=
  let (x, y, z) := spawnPosition world
  { position := ⟨x.toFloat32 + 0.5, y.toFloat32, z.toFloat32 + 0.5⟩
    yaw := 2.12
    pitch := -0.08 }

def Player.eye (player : Player) : Vector3 :=
  vadd player.position ⟨0, 1.62, 0⟩

def Player.lookDirection (player : Player) : Vector3 :=
  let cp := player.pitch.cos
  vnormalize ⟨player.yaw.sin * cp, player.pitch.sin, -player.yaw.cos * cp⟩

def Player.cameraTarget (player : Player) : Vector3 :=
  vadd player.eye player.lookDirection

def playerCollides (world : World) (position : Vector3) : Bool := Id.run do
  let radius := playerRadius
  let height := playerHeight
  let minX := floorInt (position.x - radius)
  let maxX := floorInt (position.x + radius - 0.001)
  let minY := floorInt position.y
  let maxY := floorInt (position.y + height - 0.001)
  let minZ := floorInt (position.z - radius)
  let maxZ := floorInt (position.z + radius - 0.001)
  for xi in [0:(maxX - minX + 1).toNat] do
    for yi in [0:(maxY - minY + 1).toNat] do
      for zi in [0:(maxZ - minZ + 1).toNat] do
        if Block.isSolid (world.getI (minX + Int.ofNat xi) (minY + Int.ofNat yi) (minZ + Int.ofNat zi)) then
          return true
  return false

def blockIntersectsPlayer (player : Player) (x y z : Int) : Bool :=
  let radius := playerRadius
  let px0 := player.position.x - radius
  let px1 := player.position.x + radius
  let py0 := player.position.y
  let py1 := player.position.y + playerHeight
  let pz0 := player.position.z - radius
  let pz1 := player.position.z + radius
  let bx0 := (Int32.ofInt x).toFloat32
  let by0 := (Int32.ofInt y).toFloat32
  let bz0 := (Int32.ofInt z).toFloat32
  px1 > bx0 && px0 < bx0 + 1 && py1 > by0 && py0 < by0 + 1 && pz1 > bz0 && pz0 < bz0 + 1

structure Controls where
  forward : Bool := false
  backward : Bool := false
  left : Bool := false
  right : Bool := false
  jumpDown : Bool := false
  jumpPressed : Bool := false
  descend : Bool := false
  sprint : Bool := false
  toggleFly : Bool := false
  mouseX : Float32 := 0
  mouseY : Float32 := 0

def moveWithCollisions (world : World) (position delta : Vector3) : Vector3 × Bool :=
  let tryX : Vector3 := { position with x := position.x + delta.x }
  let afterX := if playerCollides world tryX then position else tryX
  let tryZ : Vector3 := { afterX with z := afterX.z + delta.z }
  let afterZ := if playerCollides world tryZ then afterX else tryZ
  let tryY : Vector3 := { afterZ with y := afterZ.y + delta.y }
  let yBlocked := playerCollides world tryY
  let afterY :=
    if yBlocked && delta.y < 0 then
      { afterZ with y := (Int32.ofInt (floorInt afterZ.y)).toFloat32 }
    else if yBlocked then afterZ
    else tryY
  (afterY, yBlocked)

@[inline] def boolFloat (value : Bool) : Float32 := if value then 1.0 else 0.0

def updatePlayer (world : World) (controls : Controls) (dtRaw : Float32) (player : Player) : Player := Id.run do
  let dt : Float32 := min dtRaw maxPhysicsDt
  let yaw : Float32 := player.yaw + controls.mouseX * 0.0022
  let pitch : Float32 := clamp32 (-1.48) 1.48 (player.pitch - controls.mouseY * 0.0022)
  let flying : Bool := if controls.toggleFly then !player.flying else player.flying
  let forwardAmount : Float32 := boolFloat controls.forward - boolFloat controls.backward
  let sideAmount : Float32 := boolFloat controls.right - boolFloat controls.left
  let forward : Vector3 := ⟨yaw.sin, 0, -yaw.cos⟩
  let right : Vector3 := ⟨yaw.cos, 0, yaw.sin⟩
  let wish : Vector3 := vnormalize (vadd (vmul forward forwardAmount) (vmul right sideAmount))
  let speed : Float32 := if flying then flySpeed else if controls.sprint then 8.0 else 5.2
  let targetX : Float32 := wish.x * speed
  let targetZ : Float32 := wish.z * speed
  let accel : Float32 := if player.grounded then 16.0 else 5.0
  let response : Float32 := min 1.0 (dt * accel)
  let vx : Float32 := player.velocity.x + (targetX - player.velocity.x) * response
  let vz : Float32 := player.velocity.z + (targetZ - player.velocity.z) * response
  let vy : Float32 :=
    if flying then
      (boolFloat controls.jumpDown - boolFloat controls.descend) * speed
    else if controls.jumpPressed && player.grounded then 8.2
    else max (-maxFallSpeed) (player.velocity.y - 23.0 * dt)
  let initialVelocity : Vector3 := ⟨vx, vy, vz⟩
  let delta : Vector3 := vmul initialVelocity dt
  let moved := moveWithCollisions world player.position delta
  let position := moved.1
  let yBlocked := moved.2
  let grounded : Bool := !flying && yBlocked && decide (vy ≤ 0)
  let velocity : Vector3 := if yBlocked then { initialVelocity with y := 0 } else initialVelocity
  return {
    player with
    position := position
    velocity := velocity
    yaw := yaw
    pitch := pitch
    grounded := grounded
    flying := flying
  }

structure VoxelHit where
  x : Int
  y : Int
  z : Int
  placeX : Int
  placeY : Int
  placeZ : Int
  distance : Float32
deriving Inhabited, Repr

def raycastVoxel (world : World) (origin direction : Vector3) (maxDistance : Float32 := 6) : Option VoxelHit := Id.run do
  let dir := vnormalize direction
  let mut x := floorInt origin.x
  let mut y := floorInt origin.y
  let mut z := floorInt origin.z
  let stepX : Int := if dir.x > 0 then 1 else -1
  let stepY : Int := if dir.y > 0 then 1 else -1
  let stepZ : Int := if dir.z > 0 then 1 else -1
  let inf : Float32 := 1000000
  let deltaX := if dir.x.abs < 0.00001 then inf else (1 / dir.x).abs
  let deltaY := if dir.y.abs < 0.00001 then inf else (1 / dir.y).abs
  let deltaZ := if dir.z.abs < 0.00001 then inf else (1 / dir.z).abs
  let xBoundary := if stepX > 0 then (Int32.ofInt (x + 1)).toFloat32 else (Int32.ofInt x).toFloat32
  let yBoundary := if stepY > 0 then (Int32.ofInt (y + 1)).toFloat32 else (Int32.ofInt y).toFloat32
  let zBoundary := if stepZ > 0 then (Int32.ofInt (z + 1)).toFloat32 else (Int32.ofInt z).toFloat32
  let mut maxX := if deltaX == inf then inf else (xBoundary - origin.x) / dir.x
  let mut maxY := if deltaY == inf then inf else (yBoundary - origin.y) / dir.y
  let mut maxZ := if deltaZ == inf then inf else (zBoundary - origin.z) / dir.z
  let mut previous := (x, y, z)
  let mut distance : Float32 := 0
  for _ in [0:192] do
    if Block.isSolid (world.getI x y z) then
      let (px, py, pz) := previous
      return some {
        x := x
        y := y
        z := z
        placeX := px
        placeY := py
        placeZ := pz
        distance := distance
      }
    previous := (x, y, z)
    if maxX < maxY && maxX < maxZ then
      x := x + stepX
      distance := maxX
      maxX := maxX + deltaX
    else if maxY < maxZ then
      y := y + stepY
      distance := maxY
      maxY := maxY + deltaY
    else
      z := z + stepZ
      distance := maxZ
      maxZ := maxZ + deltaZ
    if distance > maxDistance then return none
  return none

end Axiom
