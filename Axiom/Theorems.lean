import Axiom.Mesh
import Axiom.Physics
import Axiom.Save

/-!
# First formal specifications

Machine-checked facts about the game, addressing the roadmap item
"Optional formal specifications for save round-trips, coordinate safety
and selected collision invariants". The proofs are checked by the
machine on every `lake build` (this module is imported from the library
root); **the statements are what a reader should scrutinize** — each
section below says what informal claim it formalizes and where the
formal statement is narrower than the informal one.

Two proof styles are used:

* **Symbolic** (`omega`): universal statements over all coordinates.
  These hold for every world and every seed.
* **Evaluated** (`native_decide`): closed facts about the concrete
  default island, checked by running the actual game code — world
  generation, collision, meshing — during type checking. The same facts
  are also exercised at run time by the acceptance suite, so the two
  checks back each other up.

## Trust base

Audited with `#print axioms`:

* The symbolic theorems depend only on Lean's standard axioms
  (`propext`, `Classical.choice`, `Quot.sound`) — kernel-level trust.
* The evaluated theorems additionally depend on `Lean.ofReduceBool`:
  `native_decide` trusts the Lean compiler and native evaluator, not
  just the kernel.

## What is NOT proven here (non-goals, for now)

* No statement quantifies over all seeds; evaluated facts are about the
  default island only.
* No reasoning about `Float32` arithmetic beyond evaluating closed
  comparisons; in particular "the player can never tunnel" is NOT a
  theorem — see the step-bounds section for exactly what is proven.
* The save-codec round-trip is not yet formalized (it remains covered by
  the acceptance suite).
* Mesh locality (below) proves edits outside a section's footprint leave
  its mesh unchanged; the companion enumeration statement — every
  in-world section whose footprint contains the edit appears in
  `affectedSections` — is not yet formalized. Note it would require the
  section to be in-world: out-of-world sections have footprint overlap
  at the boundary but empty meshes, so the game remains sound without
  rebuilding them.

This module has no runtime footprint: it exports proofs, not code.
-/

namespace Axiom

/-- The island the game generates for its default seed. -/
def defaultWorld : World := generateWorld

/-! ## Coordinate safety

`voxelIndex` addresses the flat voxel array. These two theorems say the
addressing is safe and faithful: in-bounds coordinates always map inside
the array, and distinct coordinates never collide. -/

theorem voxelIndex_lt_volume {x y z : Nat}
    (hx : x < worldWidth) (hy : y < worldHeight) (hz : z < worldDepth) :
    voxelIndex x y z < worldVolume := by
  simp only [voxelIndex, worldVolume, worldWidth, worldHeight, worldDepth] at *
  omega

theorem voxelIndex_injective {x₁ y₁ z₁ x₂ y₂ z₂ : Nat}
    (hx₁ : x₁ < worldWidth) (hz₁ : z₁ < worldDepth)
    (hx₂ : x₂ < worldWidth) (hz₂ : z₂ < worldDepth)
    (h : voxelIndex x₁ y₁ z₁ = voxelIndex x₂ y₂ z₂) :
    x₁ = x₂ ∧ y₁ = y₂ ∧ z₁ = z₂ := by
  simp only [voxelIndex, worldWidth, worldDepth] at *
  omega

/-! ## Collision step bounds

**Informal claim**: the player cannot tunnel through solid blocks.

**What is actually proven**: only the arithmetic premises of that claim.
The collision sweep tests each axis's *destination*, never the path
between (`moveWithCollisions`); that is sound only while one physics
step cannot move the player farther than the player's own extent along
any axis. The theorems below verify the required inequalities between
the *named* simulation constants in `Axiom/Physics.lean` — the same
definitions the physics code executes, so rebalancing a constant past
its safe bound breaks a proof instead of silently enabling tunneling.
The step from these inequalities to "no tunneling" — that `updatePlayer`
really never moves farther than speed × clamped-dt, and that
destination-overlap then suffices — is an informal argument about the
code, not a theorem. Its grep-checkable premise: the simulation uses the
named constants and no faster inline literals. -/

theorem vertical_step_below_player_height :
    maxFallSpeed * maxPhysicsDt < playerHeight := by native_decide

theorem vertical_step_below_one_block :
    maxFallSpeed * maxPhysicsDt < 1 := by native_decide

theorem horizontal_step_below_player_width :
    flySpeed * maxPhysicsDt < playerRadius * 2 := by native_decide

/-! ## Facts about the default island, proved by evaluation -/

/-- Every voxel the generator produces carries a valid block id. -/
theorem defaultWorld_valid_ids :
    validVoxelIds defaultWorld.voxels = true := by native_decide

/-- The player spawns free of the terrain. -/
theorem defaultWorld_spawn_clear :
    playerCollides defaultWorld (newPlayer defaultWorld).position = false := by
  native_decide

def spawnGroundIsSolid : Bool :=
  let (x, y, z) := spawnPosition defaultWorld
  Block.isSolid (defaultWorld.get x (y - 2) z)

/-- The player spawns standing on solid ground. -/
theorem defaultWorld_spawn_has_ground : spawnGroundIsSolid = true := by
  native_decide

def terrainHeightsBounded : Bool := Id.run do
  for x in [0:worldWidth] do
    for z in [0:worldDepth] do
      let h := terrainHeight defaultWorld.seed x z
      if h < seaLevel - 4 || h > 35 then return false
  return true

/-- Every column of the default island keeps its surface within the
generator's stated band, comfortably inside the world's height. -/
theorem defaultWorld_terrain_bounded : terrainHeightsBounded = true := by
  native_decide

/-- A meadow section of the default island meshes into complete
triangles. -/
theorem defaultWorld_sample_mesh_complete :
    (buildSectionCpu defaultWorld 3 0 3).vertexCount % 3 = 0 := by
  native_decide

/-! ## Accessor laws

`World.set` and `World.get` interact as a well-behaved accessor: writing
one cell reads back (`get_set_self`, assuming the world carries its full
voxel volume), and leaves every other cell untouched (`get_set_ne`, with
no assumptions at all — arbitrary voxel buffers, arbitrary coordinates).
These are the point lemmas the mesh-locality theorem below rests on.
Symbolic proofs; kernel-level trust. -/

theorem ByteArray.get!_set!_ne (bs : ByteArray) (i j : Nat) (b : UInt8)
    (h : i ≠ j) : (bs.set! i b).get! j = bs.get! j := by
  obtain ⟨data⟩ := bs
  show (data.setIfInBounds i b)[j]! = data[j]!
  by_cases hj : j < data.size
  · have hj' : j < (data.setIfInBounds i b).size := by
      simpa [Array.size_setIfInBounds] using hj
    rw [Array.getElem!_eq_getD, Array.getElem!_eq_getD,
        Array.getD_eq_getD_getElem?, Array.getD_eq_getD_getElem?,
        Array.getElem?_eq_getElem hj', Array.getElem?_eq_getElem hj]
    simp [Array.getElem_setIfInBounds_ne hj h]
  · have hsz : (data.setIfInBounds i b).size = data.size :=
      Array.size_setIfInBounds
    rw [Array.getElem!_eq_getD, Array.getElem!_eq_getD,
        Array.getD_eq_getD_getElem?, Array.getD_eq_getD_getElem?,
        Array.getElem?_eq_none (by omega), Array.getElem?_eq_none (by omega)]

theorem ByteArray.get!_set!_self (bs : ByteArray) (i : Nat) (b : UInt8)
    (h : i < bs.size) : (bs.set! i b).get! i = b := by
  obtain ⟨data⟩ := bs
  show (data.setIfInBounds i b)[i]! = b
  have h' : i < (data.setIfInBounds i b).size := by
    simpa [Array.size_setIfInBounds] using h
  rw [Array.getElem!_eq_getD, Array.getD_eq_getD_getElem?,
      Array.getElem?_eq_getElem h']
  simp [Array.getElem_setIfInBounds]

private theorem validCoord_bounds {x y z : Nat} (h : validCoord x y z = true) :
    x < worldWidth ∧ y < worldHeight ∧ z < worldDepth := by
  have := h
  simp only [validCoord, Bool.and_eq_true, decide_eq_true_eq] at this
  exact ⟨this.1.1, this.1.2, this.2⟩

theorem World.get_set_ne (world : World) (ex ey ez cx cy cz : Nat) (b : UInt8)
    (h : ¬(ex = cx ∧ ey = cy ∧ ez = cz)) :
    (world.set ex ey ez b).get cx cy cz = world.get cx cy cz := by
  unfold World.set
  split
  case isTrue hve =>
    unfold World.get
    split
    case isTrue hvc =>
      apply ByteArray.get!_set!_ne
      intro hidx
      obtain ⟨hex, hey, hez⟩ := validCoord_bounds hve
      obtain ⟨hcx, hcy, hcz⟩ := validCoord_bounds hvc
      have := voxelIndex_injective hex hez hcx hcz hidx
      exact h ⟨this.1, this.2.1, this.2.2⟩
    case isFalse => rfl
  case isFalse => rfl

/-- Writes read back. The `hsize` hypothesis is not incidental: the byte
store's `set!` silently ignores out-of-range indices, so on a world with
a short buffer a valid-coordinate write can be a no-op — the
unconditional statement is FALSE. Rather than quietly assuming the
precondition, the two theorems after this one prove it is an invariant:
every world the game constructs has full volume, and `World.set`
preserves it. -/
theorem World.get_set_self (world : World) (x y z : Nat) (b : UInt8)
    (hv : validCoord x y z = true) (hsize : world.voxels.size = worldVolume) :
    (world.set x y z b).get x y z = b := by
  obtain ⟨hx, hy, hz⟩ := validCoord_bounds hv
  unfold World.set World.get
  rw [if_pos hv, if_pos hv]
  exact ByteArray.get!_set!_self _ _ _
    (hsize ▸ voxelIndex_lt_volume hx hy hz)

theorem ByteArray.size_set! (bs : ByteArray) (i : Nat) (b : UInt8) :
    (bs.set! i b).size = bs.size := by
  obtain ⟨data⟩ := bs
  show (data.setIfInBounds i b).size = data.size
  exact Array.size_setIfInBounds

/-- Edits preserve the storage size: `get_set_self`'s precondition is an
invariant maintained by every `World.set`. -/
theorem World.size_set (world : World) (x y z : Nat) (b : UInt8) :
    (world.set x y z b).voxels.size = world.voxels.size := by
  unfold World.set
  split
  · exact ByteArray.size_set! ..
  · rfl

/-- The generated world establishes the invariant: `get_set_self`'s
precondition holds at creation (and the save decoder enforces it at the
load door, per the acceptance suite). -/
theorem defaultWorld_volume : defaultWorld.voxels.size = worldVolume := by
  native_decide

/-! ## Mesh locality (incremental-rendering soundness)

**Informal claim**: after a block edit, rebuilding only the sections the
game schedules (`affectedSections`) is visually indistinguishable from
rebuilding the whole world.

**What is proven here**: the heart of that claim — editing a voxel
outside a section's *footprint* leaves that section's mesh
byte-for-byte unchanged (`buildSectionCpu_set_of_not_footprint`). The
footprint is the section's box expanded by one cell along each axis via
the faces only — never edges or corners — because face culling reads
only face-adjacent neighbors. This is the fact that lets the game
rebuild at most four sections per edit instead of eight; the concluding
`example` below exhibits a diagonally-adjacent edit provably outside a
section's footprint.

Unlike the evaluated facts above, this is a universally quantified
symbolic proof (any world, any edit, any section) with kernel-level
trust; the machinery is a congruence argument through the mesh
builder's four nested loops.

**Remaining gap (stated in the module non-goals)**: the enumeration
statement `footprint ⊆ affectedSections` for in-world sections is not
yet formalized; the acceptance suite exercises it at the seams. -/

private theorem forIn_list_congr {β : Type} {l : List Nat} {init : β}
    {f g : Nat → β → Id (ForInStep β)}
    (h : ∀ i ∈ l, ∀ acc, f i acc = g i acc) :
    forIn l init f = forIn l init g := by
  induction l generalizing init with
  | nil => rfl
  | cons a t ih =>
    rw [List.forIn_cons, List.forIn_cons, h a (List.mem_cons_self ..)]
    cases g a init with
    | done b => rfl
    | yield b =>
      exact ih (fun i hi acc => h i (List.mem_cons_of_mem _ hi) acc)

private theorem forIn_range_congr {β : Type} {start stop : Nat} {init : β}
    {f g : Nat → β → Id (ForInStep β)}
    (h : ∀ i, start ≤ i → i < stop → ∀ acc, f i acc = g i acc) :
    forIn [start:stop] init f = forIn [start:stop] init g := by
  rw [Std.Range.forIn_eq_forIn_range', Std.Range.forIn_eq_forIn_range']
  apply forIn_list_congr
  intro i hi acc
  have hsize : ([start:stop] : Std.Range).size = stop - start := by
    simp [Std.Range.size]
  rw [hsize] at hi
  obtain ⟨k, hk, rfl⟩ : ∃ k, k < stop - start ∧ i = start + k := by
    simpa [List.mem_range'] using hi
  exact h _ (by omega) (by omega) acc

private theorem bind_congr_left {α β : Type} {a₁ a₂ : Id α} (k : α → Id β)
    (h : a₁ = a₂) : a₁ >>= k = a₂ >>= k := by rw [h]

/-- Two worlds that agree on a section's cells and on the face neighbors
of those cells produce identical meshes for that section. -/
theorem buildSectionCpu_congr (w₁ w₂ : World) (sx sy sz : Nat)
    (hget : ∀ cx cy cz,
      sx * sectionSize ≤ cx → cx < Nat.min worldWidth (sx * sectionSize + sectionSize) →
      sy * sectionSize ≤ cy → cy < Nat.min worldHeight (sy * sectionSize + sectionSize) →
      sz * sectionSize ≤ cz → cz < Nat.min worldDepth (sz * sectionSize + sectionSize) →
      w₁.get cx cy cz = w₂.get cx cy cz)
    (hnbr : ∀ cx cy cz face nx ny nz,
      sx * sectionSize ≤ cx → cx < Nat.min worldWidth (sx * sectionSize + sectionSize) →
      sy * sectionSize ≤ cy → cy < Nat.min worldHeight (sy * sectionSize + sectionSize) →
      sz * sectionSize ≤ cz → cz < Nat.min worldDepth (sz * sectionSize + sectionSize) →
      face < 6 → neighborForFace face cx cy cz = (nx, ny, nz) →
      w₁.getI nx ny nz = w₂.getI nx ny nz) :
    buildSectionCpu w₁ sx sy sz = buildSectionCpu w₂ sx sy sz := by
  unfold buildSectionCpu
  dsimp only [Id.run]
  apply forIn_range_congr
  intro x hx0 hx1 mesh
  apply bind_congr_left
  apply forIn_range_congr
  intro y hy0 hy1 mesh
  apply bind_congr_left
  apply forIn_range_congr
  intro z hz0 hz1 mesh
  rw [hget x y z hx0 hx1 hy0 hy1 hz0 hz1]
  split
  · apply bind_congr_left
    apply forIn_range_congr
    intro face hf0 hf6 mesh
    rcases hnf : neighborForFace face x y z with ⟨nx, ny, nz⟩
    simp only [hnf]
    rw [hnbr x y z face nx ny nz hx0 hx1 hy0 hy1 hz0 hz1 hf6 hnf]
  · rfl

/-- The cells whose byte value the mesh of section `(sx, sy, sz)` can
depend on: the section box expanded by one cell along each axis — via
the faces only, never edges or corners, because face culling reads only
face-adjacent neighbors. -/
def sectionFootprint (sx sy sz cx cy cz : Nat) : Prop :=
  (sy * sectionSize ≤ cy ∧ cy < Nat.min worldHeight (sy * sectionSize + sectionSize) ∧
   sz * sectionSize ≤ cz ∧ cz < Nat.min worldDepth (sz * sectionSize + sectionSize) ∧
   cx + 1 ≥ sx * sectionSize ∧ cx ≤ Nat.min worldWidth (sx * sectionSize + sectionSize)) ∨
  (sx * sectionSize ≤ cx ∧ cx < Nat.min worldWidth (sx * sectionSize + sectionSize) ∧
   sz * sectionSize ≤ cz ∧ cz < Nat.min worldDepth (sz * sectionSize + sectionSize) ∧
   cy + 1 ≥ sy * sectionSize ∧ cy ≤ Nat.min worldHeight (sy * sectionSize + sectionSize)) ∨
  (sx * sectionSize ≤ cx ∧ cx < Nat.min worldWidth (sx * sectionSize + sectionSize) ∧
   sy * sectionSize ≤ cy ∧ cy < Nat.min worldHeight (sy * sectionSize + sectionSize) ∧
   cz + 1 ≥ sz * sectionSize ∧ cz ≤ Nat.min worldDepth (sz * sectionSize + sectionSize))

/-- **Mesh locality.** Editing a voxel outside a section's footprint
leaves that section's mesh byte-for-byte unchanged — for any world, any
block value, and any coordinates, with no validity assumptions. -/
theorem buildSectionCpu_set_of_not_footprint (world : World) (b : UInt8)
    {sx sy sz ex ey ez : Nat}
    (hfar : ¬ sectionFootprint sx sy sz ex ey ez) :
    buildSectionCpu (world.set ex ey ez b) sx sy sz
      = buildSectionCpu world sx sy sz := by
  apply buildSectionCpu_congr
  · intro cx cy cz hx0 hx1 hy0 hy1 hz0 hz1
    apply World.get_set_ne
    rintro ⟨rfl, rfl, rfl⟩
    exact hfar (Or.inl ⟨hy0, hy1, hz0, hz1, by omega, by omega⟩)
  · intro cx cy cz face nx ny nz hx0 hx1 hy0 hy1 hz0 hz1 hf6 hnf
    have hface : face = 0 ∨ face = 1 ∨ face = 2 ∨ face = 3 ∨ face = 4 ∨ face = 5 := by
      omega
    have ofNatCast : ∀ n : Nat, Int.ofNat n = (n : Int) := fun _ => rfl
    rcases hface with rfl | rfl | rfl | rfl | rfl | rfl
    all_goals
      simp only [neighborForFace, Prod.mk.injEq, ofNatCast] at hnf
      rcases hnf with ⟨rfl, rfl, rfl⟩
      simp only [World.getI]
      split
      case isTrue => rfl
      case isFalse hcond =>
        simp only [Bool.or_eq_true, decide_eq_true_eq, not_or, ofNatCast] at hcond
        apply World.get_set_ne
        rintro ⟨rfl, rfl, rfl⟩
        exact hfar (by unfold sectionFootprint; omega)

/-- A diagonally-adjacent edit is outside the footprint: changing the
corner voxel `(15, 15, 5)` cannot affect section `(1, 1, 0)`, even
though that section's box touches the edit diagonally. Face culling has
no diagonal reads — the fact that lets `affectedSections` schedule at
most four sections per edit instead of eight. -/
example (world : World) (b : UInt8) :
    buildSectionCpu (world.set 15 15 5 b) 1 1 0 = buildSectionCpu world 1 1 0 := by
  apply buildSectionCpu_set_of_not_footprint
  unfold sectionFootprint sectionSize worldWidth worldHeight worldDepth
  omega

end Axiom
