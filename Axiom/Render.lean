import Axiom.Mesh
import Axiom.Physics
import Raylib

open Raymath

namespace Axiom

def rgbaColor (color : Rgba) : Raylib.Color :=
  Raylib.Color.fromRgba color.r color.g color.b color.a

structure Visuals where
  material : Raylib.Material

def layoutSize : BaseIO (Int32 × Int32) := do
  let renderWidth ← Raylib.getRenderWidth
  let renderHeight ← Raylib.getRenderHeight
  let scale ← Raylib.getWindowScaleDPI
  let scaleX := if scale.x > 0 then scale.x else 1
  let scaleY := if scale.y > 0 then scale.y else 1
  return (max 1 (renderWidth.toFloat32 / scaleX).toInt32,
    max 1 (renderHeight.toFloat32 / scaleY).toInt32)

def createVisuals (ctx : Raylib.Context) : BaseIO Visuals := do
  return { material := Raylib.Material.getDefault ctx }

def Visuals.updateUniforms (_visuals : Visuals) (_cameraPosition : Vector3) (_time : Float32) : BaseIO Unit :=
  pure ()

@[inline] def mixByte (a b : UInt8) (t : Float32) : UInt8 :=
  UInt8.ofNat (min 255 (a.toFloat32 + (b.toFloat32 - a.toFloat32) * t).toUInt32.toNat)

def mixRgba (a b : Rgba) (t : Float32) : Rgba :=
  ⟨mixByte a.r b.r t, mixByte a.g b.g t, mixByte a.b b.b t, mixByte a.a b.a t⟩

def daylight (time : Float32) : Float32 :=
  let angle := 0.85 + time * 0.0052359877 -- one full cycle every 20 minutes
  clamp32 0 1 (angle.sin * 1.18 + 0.12)

def drawSky (time : Float32) : BaseIO Unit := do
  let (width, height) ← layoutSize
  let light := daylight time
  let top := mixRgba ⟨15, 23, 48, 255⟩ ⟨77, 126, 166, 255⟩ light
  let bottom := mixRgba ⟨47, 49, 72, 255⟩ ⟨211, 192, 157, 255⟩ light
  Raylib.drawRectangleGradientV 0 0 width height
    (rgbaColor top) (rgbaColor bottom)
  let night := 1 - light
  if night > 0.05 then
    let starAlpha := UInt8.ofNat (min 220 (night * 230).toUInt32.toNat)
    for i in [0:38] do
      let x := Int32.ofNat ((hash2 0x57a2 i 9 % UInt64.ofNat width.toNatClampNeg).toNat)
      let starHeight := max 1 (height.toNatClampNeg * 2 / 3)
      let y := Int32.ofNat ((hash2 0x57a2 i 17 % UInt64.ofNat starHeight).toNat)
      let radius : Float32 := if i % 7 == 0 then 1.8 else 1.0
      Raylib.drawCircle x y radius (Raylib.Color.fromRgba 226 233 220 starAlpha)
  let angle := 0.85 + time * 0.0052359877
  let sunX := ((0.5 + angle.cos * 0.42) * width.toFloat32).toInt32
  let sunY := ((0.66 - angle.sin * 0.49) * height.toFloat32).toInt32
  let sunAlpha := UInt8.ofNat (min 245 (35 + light * 220).toUInt32.toNat)
  Raylib.drawCircle sunX sunY 72 (Raylib.Color.fromRgba 255 190 104 (sunAlpha / 8))
  Raylib.drawCircle sunX sunY 42 (Raylib.Color.fromRgba 255 222 156 (sunAlpha / 3))
  Raylib.drawCircle sunX sunY 18 (Raylib.Color.fromRgba 255 239 196 sunAlpha)

def drawWorldTint (time : Float32) : BaseIO Unit := do
  let darkness := 1 - daylight time
  if darkness > 0.02 then
    let (width, height) ← layoutSize
    let alpha := UInt8.ofNat (min 112 (darkness * 112).toUInt32.toNat)
    Raylib.drawRectangle 0 0 width height (Raylib.Color.fromRgba 13 20 42 alpha)

@[inline] def wrap32 (value span : Float32) : Float32 :=
  value - (value / span).floor * span

def drawClouds (time : Float32) : BaseIO Unit := do
  let white := Raylib.Color.fromRgba 245 240 225 185
  for i in [0:12] do
    let fi := i.toFloat32
    let x := wrap32 (fi * 17.3 + time * (0.38 + fi * 0.012)) 118 - 11
    let z := wrap32 (fi * 29.1 + 7) 112 - 8
    let y := 33 + (fi * 1.7).sin * 2.5
    Raylib.drawCubeV ⟨x, y, z⟩ ⟨8 + (i % 3).toFloat32 * 2.5, 0.65, 3.8⟩ white
    Raylib.drawCubeV ⟨x + 3.5, y + 0.35, z + 0.8⟩ ⟨5.5, 0.7, 3.1⟩ white

def drawOcean : BaseIO Unit := do
  let center : Vector3 := ⟨worldWidth.toFloat32 / 2, seaLevel.toFloat32 + 0.52, worldDepth.toFloat32 / 2⟩
  Raylib.drawPlane center ⟨108, 108⟩ (Raylib.Color.fromRgba 46 126 162 255)

def drawGlowHalos (time : Float32) : BaseIO Unit := do
  let pulse := 0.13 * (time * 2.2).sin + 0.58
  let color := Raylib.Color.fromRgba 255 184 72 (UInt8.ofNat (80 + (pulse * 70).toUInt32.toNat))
  for p in #[Vector3.mk 69.5 28.5 62.5, Vector3.mk 75.5 28.5 62.5, Vector3.mk 72.5 32.5 62.5] do
    Raylib.drawSphere p pulse color

def drawSelection (hit : Option VoxelHit) : BaseIO Unit := do
  if let some h := hit then
    let center : Vector3 := ⟨(Int32.ofInt h.x).toFloat32 + 0.5,
      (Int32.ofInt h.y).toFloat32 + 0.5, (Int32.ofInt h.z).toFloat32 + 0.5⟩
    Raylib.drawCubeWires center 1.014 1.014 1.014 (Raylib.Color.fromRgba 255 244 204 245)

def drawCrosshair : BaseIO Unit := do
  let (width, height) ← layoutSize
  let cx := width / 2
  let cy := height / 2
  let shadow := Raylib.Color.fromRgba 12 18 24 170
  let light := Raylib.Color.fromRgba 255 249 224 245
  Raylib.drawLine (cx - 8) (cy + 1) (cx + 8) (cy + 1) shadow
  Raylib.drawLine (cx + 1) (cy - 8) (cx + 1) (cy + 8) shadow
  Raylib.drawLine (cx - 7) cy (cx + 7) cy light
  Raylib.drawLine cx (cy - 7) cx (cy + 7) light

def drawHotbar (player : Player) : BaseIO Unit := do
  let (width, height) ← layoutSize
  let slot : Int32 := 52
  let gap : Int32 := 5
  let total := slot * 9 + gap * 8
  let startX := (width - total) / 2
  let y := height - 78
  for i in [0:Block.palette.size] do
    let x := startX + Int32.ofNat i * (slot + gap)
    let selected := i == player.selected
    let panel := if selected then Raylib.Color.fromRgba 247 232 192 235 else Raylib.Color.fromRgba 20 28 35 190
    let border := if selected then Raylib.Color.fromRgba 255 244 210 255 else Raylib.Color.fromRgba 133 158 166 145
    let rect : Raylib.Rectangle := ⟨x.toFloat32, y.toFloat32, slot.toFloat32, slot.toFloat32⟩
    Raylib.drawRectangleRounded rect 0.18 5 panel
    Raylib.drawRectangleRoundedLinesEx rect 0.18 5 (if selected then 3 else 1) border
    let block := Block.palette[i]!
    let swatch : Raylib.Rectangle := ⟨(x + 12).toFloat32, (y + 12).toFloat32, 28, 28⟩
    Raylib.drawRectangleRounded swatch 0.16 4 (rgbaColor (Block.color block))
    Raylib.drawText s!"{i + 1}" (x + 5) (y + 4) 11 (Raylib.Color.fromRgba 255 255 255 175)
  let selectedBlock := Block.palette[player.selected]!
  let label := Block.name selectedBlock
  let textWidth ← Raylib.measureText label 18
  Raylib.drawText label ((width - textWidth.toInt32) / 2) (y - 29) 18 (Raylib.Color.fromRgba 255 247 224 235)

def drawStatus (player : Player) (showDebug : Bool) : BaseIO Unit := do
  Raylib.drawRectangleRounded ⟨18, 17, 192, 38⟩ 0.25 5 (Raylib.Color.fromRgba 16 25 32 185)
  Raylib.drawText "AXIOM  //  LEAN 4" 31 29 16 (Raylib.Color.fromRgba 246 232 193 245)
  if player.flying then
    Raylib.drawRectangleRounded ⟨18, 64, 112, 30⟩ 0.25 5 (Raylib.Color.fromRgba 170 111 55 205)
    Raylib.drawText "FLIGHT MODE" 30 74 13 Raylib.Color.raywhite
  if showDebug then
    Raylib.drawRectangle 16 108 210 82 (Raylib.Color.fromRgba 10 15 20 190)
    Raylib.drawFPS 26 118
    Raylib.drawText s!"x {player.position.x}  y {player.position.y}" 26 145 13 Raylib.Color.raywhite
    Raylib.drawText s!"z {player.position.z}" 26 166 13 Raylib.Color.raywhite

def drawHud (player : Player) (showDebug : Bool) : BaseIO Unit := do
  drawCrosshair
  drawHotbar player
  drawStatus player showDebug

def drawToast (message : String) : BaseIO Unit := do
  let (width, _) ← layoutSize
  let textWidth ← Raylib.measureText message 16
  let x := (width - textWidth.toInt32) / 2
  Raylib.drawRectangleRounded ⟨(x - 14).toFloat32, 112, (textWidth + 28).toFloat32, 34⟩ 0.3 5
    (Raylib.Color.fromRgba 18 27 33 218)
  Raylib.drawText message x 122 16 (Raylib.Color.fromRgba 255 240 207 245)

def drawTitleOverlay (hasSave : Bool) : BaseIO Unit := do
  let (width, height) ← layoutSize
  Raylib.drawRectangleGradientH 0 0 (width * 3 / 5) height
    (Raylib.Color.fromRgba 10 18 25 235) (Raylib.Color.fromRgba 10 18 25 0)
  Raylib.drawText "AXIOM" 74 112 72 (Raylib.Color.fromRgba 255 240 203 255)
  Raylib.drawText "FIRST LIGHT" 79 184 25 (Raylib.Color.fromRgba 235 176 104 255)
  Raylib.drawText "A voxel sandbox written entirely in Lean 4" 80 229 19 (Raylib.Color.fromRgba 203 220 220 235)
  Raylib.drawRectangleRounded ⟨74, 300, 340, 64⟩ 0.16 6 (Raylib.Color.fromRgba 235 215 173 226)
  Raylib.drawText (if hasSave then "CLICK / ENTER  CONTINUE" else "CLICK / ENTER  BEGIN") 94 320 20 (Raylib.Color.fromRgba 24 35 40 255)
  Raylib.drawText "WASD move   SPACE jump   F fly" 80 399 16 (Raylib.Color.fromRgba 238 238 220 220)
  Raylib.drawText "MOUSE look   SHIFT sprint   1-9 blocks" 80 426 16 (Raylib.Color.fromRgba 238 238 220 220)
  Raylib.drawText "LEFT mine   RIGHT build   ESC pause" 80 453 16 (Raylib.Color.fromRgba 238 238 220 220)
  Raylib.drawText "Every block, collision and world rule runs in Lean." 80 (height - 72) 14
    (Raylib.Color.fromRgba 180 199 200 180)

def drawPauseOverlay : BaseIO Unit := do
  let (width, height) ← layoutSize
  Raylib.drawRectangle 0 0 width height (Raylib.Color.fromRgba 7 12 17 178)
  let panelX := width / 2 - 230
  let panelY := height / 2 - 150
  Raylib.drawRectangleRounded ⟨panelX.toFloat32, panelY.toFloat32, 460, 300⟩ 0.08 8
    (Raylib.Color.fromRgba 22 31 38 244)
  Raylib.drawText "WORLD PAUSED" (panelX + 54) (panelY + 47) 34 (Raylib.Color.fromRgba 255 236 197 255)
  Raylib.drawText "CLICK / ESC   return to the island" (panelX + 56) (panelY + 116) 18 (Raylib.Color.fromRgba 206 221 218 235)
  Raylib.drawText "Q     save and return to title" (panelX + 56) (panelY + 151) 18 (Raylib.Color.fromRgba 206 221 218 235)
  Raylib.drawText "R     respawn at first light" (panelX + 56) (panelY + 186) 18 (Raylib.Color.fromRgba 206 221 218 235)
  Raylib.drawText "Your world is saved automatically." (panelX + 56) (panelY + 238) 14
    (Raylib.Color.fromRgba 149 176 178 210)

end Axiom
