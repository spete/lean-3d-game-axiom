import Axiom

open Raymath
open Axiom

inductive Screen where
  | title
  | playing
  | paused
deriving BEq, Inhabited

def playCamera (player : Player) : Raylib.Camera3D := {
  position := player.eye
  target := player.cameraTarget
  up := ⟨0, 1, 0⟩
  fovy := 61
  projection := .perspective
}

def titleCamera (time : Float32) : Raylib.Camera3D :=
  let angle := time * 0.085
  let center : Vector3 := ⟨56, 17, 53⟩
  {
    position := ⟨center.x + angle.cos * 48, 34 + (time * 0.21).sin * 2.5,
      center.z + angle.sin * 48⟩
    target := ⟨62, 15, 57⟩
    up := ⟨0, 1, 0⟩
    fovy := 52
    projection := .perspective
  }

def readControls : BaseIO Controls := do
  let mouse ← Raylib.getMouseDelta
  return {
    forward := ← Raylib.isKeyDown .w
    backward := ← Raylib.isKeyDown .s
    left := ← Raylib.isKeyDown .a
    right := ← Raylib.isKeyDown .d
    jumpDown := ← Raylib.isKeyDown .space
    jumpPressed := ← Raylib.isKeyPressed .space
    descend := ← Raylib.isKeyDown .leftControl
    sprint := ← Raylib.isKeyDown .leftShift
    toggleFly := ← Raylib.isKeyPressed .f
    mouseX := clamp32 (-80) 80 mouse.x
    mouseY := clamp32 (-80) 80 mouse.y
  }

def readHotbar (current : Nat) : BaseIO Nat := do
  if ← Raylib.isKeyPressed .one then return 0
  if ← Raylib.isKeyPressed .two then return 1
  if ← Raylib.isKeyPressed .three then return 2
  if ← Raylib.isKeyPressed .four then return 3
  if ← Raylib.isKeyPressed .five then return 4
  if ← Raylib.isKeyPressed .six then return 5
  if ← Raylib.isKeyPressed .seven then return 6
  if ← Raylib.isKeyPressed .eight then return 7
  if ← Raylib.isKeyPressed .nine then return 8
  let wheel ← Raylib.getMouseWheelMove
  if wheel > 0 then return (current + Block.palette.size - 1) % Block.palette.size
  if wheel < 0 then return (current + 1) % Block.palette.size
  return current

def coordInWorld (x y z : Int) : Bool :=
  x ≥ 0 && y ≥ 0 && z ≥ 0 && x < Int.ofNat worldWidth &&
    y < Int.ofNat worldHeight && z < Int.ofNat worldDepth

def saveGameSafe (world : World) (player : Player) : IO Bool := do
  try
    saveGame world player
    return true
  catch _ =>
    return false

def drawLoading (headline detail : String) : BaseIO Unit := do
  Raylib.beginDrawing
  Raylib.clearBackground Raylib.Color.black
  drawSky 0
  let (width, height) ← layoutSize
  Raylib.drawRectangle 0 0 width height (Raylib.Color.fromRgba 10 18 24 128)
  Raylib.drawText headline 72 (height / 2 - 55) 40 (Raylib.Color.fromRgba 255 238 202 255)
  Raylib.drawText detail 76 (height / 2 + 5) 18 (Raylib.Color.fromRgba 194 215 216 230)
  Raylib.drawRectangle 76 (height / 2 + 52) 280 3 (Raylib.Color.fromRgba 224 160 86 225)
  Raylib.endDrawing

def main (args : List String) : IO Unit := do
  -- Retina resolution already gives crisp voxel edges; forcing 4x MSAA on top
  -- of it needlessly quadruples fragment work and misses the 60 Hz budget.
  Raylib.setConfigFlags (.windowResizable ||| .vsyncHint ||| .windowHighdpi)
  -- Keep the first window inside a laptop's usable work area. macOS otherwise
  -- clamps an oversized window without synchronizing Raylib's logical size.
  let ctx ← Raylib.initWindow 1280 760 "AXIOM: FIRST LIGHT — built in Lean 4".toSubstring
  Raylib.setExitKey .null
  Raylib.setTargetFPS 60
  Raylib.setWindowMinSize 960 600
  Raylib.enableCursor
  Raylib.setAudioThreadEntryCallback
  Raylib.setAudioThreadExitCallback
  Raylib.initAudioDevice
  Raylib.setMasterVolume 0.72
  let qaTitleArg := args.contains "--qa-title"
  let qaPlayArg := args.contains "--qa-play"
  let qaMotionArg := args.contains "--qa-motion"
  let qaInteractArg := args.contains "--qa-interact"
  let qaPerfArg := args.contains "--qa-perf"
  -- Window probes exercise Raylib's live Retina callbacks, not a mocked canvas.
  let qaResizeArg := args.contains "--qa-resize"
  let qaMaximizeArg := args.contains "--qa-maximize"
  let qaFirstMaximizeArg := args.contains "--qa-first-maximize"
  let qaWindowCycleArg := args.contains "--qa-window-cycle"
  let qaWindowArg := qaResizeArg || qaMaximizeArg || qaFirstMaximizeArg || qaWindowCycleArg
  if qaResizeArg then Raylib.setWindowSize 1180 720
  else if qaMaximizeArg then Raylib.maximizeWindow
  -- QA artifacts directory: /tmp on Unix, %TEMP% on Windows.
  let tempEnv ← IO.getEnv "TEMP"
  let qaTmp := if System.Platform.isWindows then tempEnv.getD "." else "/tmp"
  let envCapture ← IO.getEnv "AXIOM_QA_CAPTURE"
  let envPlay ← IO.getEnv "AXIOM_QA_PLAY"
  let envHold ← IO.getEnv "AXIOM_QA_HOLD"
  let qaHold := envHold == some "1"
  let qaCapture? :=
    if qaTitleArg then some s!"{qaTmp}/axiom-title.png"
    else if qaPlayArg then some s!"{qaTmp}/axiom-play.png"
    else if qaResizeArg then some s!"{qaTmp}/axiom-resize.png"
    else if qaMaximizeArg then some s!"{qaTmp}/axiom-maximize.png"
    else envCapture
  let qaPlay := qaPlayArg || qaInteractArg || qaPerfArg || qaWindowArg || envPlay == some "1"

  drawLoading "AXIOM: FIRST LIGHT" "Recovering the island from a proof..."
  let loaded ← loadGame?
  let mut hasSave := loaded.isSome
  let mut world := match loaded with
    | some state => state.1
    | none => generateWorld
  let mut player :=
    if qaInteractArg || qaPerfArg then { newPlayer world with pitch := -0.38 }
    else if qaPlay then newPlayer world
    else
      match loaded with
      | some state =>
        let pitch := if state.2.pitch.abs > 1.0 then -0.14 else state.2.pitch
        let candidate := { state.2 with pitch := pitch, velocity := ⟨0,0,0⟩ }
        if playerCollides world candidate.position then newPlayer world else candidate
      | none => newPlayer world

  drawLoading "BUILDING THE HORIZON" "Lean is meshing every visible face..."
  let visuals ← createVisuals ctx
  let audio ← loadAudioBank ctx
  let mut gpu ← buildGpuWorld ctx world
  let mut pendingMeshes : Array PendingMeshJob := #[]
  let mut screen := if qaWindowArg then Screen.paused else if qaPlay then Screen.playing else Screen.title
  if qaPlay && !qaWindowArg then Raylib.disableCursor
  let mut showDebug := false
  let mut hit : Option VoxelHit := none
  let mut lastBreak : Float32 := -10
  let mut lastSave : Float32 := 0
  let mut toast := ""
  let mut toastUntil : Float32 := 0
  let mut qaFrame : Nat := 0
  let mut particles : Array Particle := #[]
  let mut qaDtTotal : Float32 := 0
  let mut qaDtMax : Float32 := 0
  let mut qaDtMaxFrame : Nat := 0
  let mut qaDtCount : Nat := 0
  let mut normalizedFirstMaximize := false

  repeat do
    if qaFirstMaximizeArg && qaFrame == 20 then Raylib.maximizeWindow
    if qaWindowCycleArg then
      if qaFrame == 20 || qaFrame == 300 then Raylib.maximizeWindow
      else if qaFrame == 160 then Raylib.restoreWindow
    -- Cocoa's first live Retina maximize can leave Raylib's native viewport in
    -- its old window state. Replaying the transition once makes later resizes
    -- stable and happens before the maximized frame can remain on screen.
    if !normalizedFirstMaximize && (← Raylib.isWindowMaximized) then
      Raylib.restoreWindow
      Raylib.maximizeWindow
      normalizedFirstMaximize := true
    let time ← Raylib.getTime
    let dt ← Raylib.getFrameTime
    if qaFrame ≥ 10 && (qaTitleArg || qaPlayArg || qaMotionArg || qaInteractArg || qaPerfArg || qaWindowArg) then
      qaDtTotal := qaDtTotal + dt
      if dt > qaDtMax then
        qaDtMax := dt
        qaDtMaxFrame := qaFrame
      qaDtCount := qaDtCount + 1
    if ← Raylib.windowShouldClose then
      let _ ← saveGameSafe world player
      break

    let meshStep ← processOneMeshJob gpu ctx pendingMeshes
    gpu := meshStep.1
    pendingMeshes := meshStep.2

    match screen with
    | .title =>
      let beginClicked ← Raylib.isMouseButtonPressed .left
      if (← Raylib.isKeyPressed .enter) || beginClicked then
        playSound? audio.ui
        screen := .playing
        Raylib.disableCursor
        toast := "Welcome to First Light"
        toastUntil := time + 2.2
    | .playing =>
      if ← Raylib.isKeyPressed .escape then
        screen := .paused
        Raylib.enableCursor
        if ← saveGameSafe world player then
          hasSave := true
        else
          toast := "Save failed — world remains open"
          toastUntil := time + 3
        lastSave := time
      else
        showDebug := if (← Raylib.isKeyPressed .f3) then !showDebug else showDebug
        let controls ← readControls
        if controls.jumpPressed && player.grounded then playSound? audio.jump
        player := updatePlayer world controls dt player
        player := { player with selected := ← readHotbar player.selected }
        if player.position.y < -8 || player.position.x < -12 || player.position.z < -12 ||
            player.position.x > worldWidth.toFloat32 + 12 || player.position.z > worldDepth.toFloat32 + 12 then
          player := newPlayer world
          toast := "Returned to first light"
          toastUntil := time + 2

        hit := raycastVoxel world player.eye player.lookDirection
        if ← Raylib.isMouseButtonPressed .middle then
          if let some h := hit then
            let picked := world.getI h.x h.y h.z
            for i in [0:Block.palette.size] do
              if Block.palette[i]! == picked then
                player := { player with selected := i }
                toast := "Picked " ++ Block.name picked
                toastUntil := time + 1.15
        let wantsBreak := ((← Raylib.isMouseButtonDown .left) && time - lastBreak > 0.145) ||
          ((qaInteractArg || qaPerfArg) && qaFrame == 50)
        if wantsBreak then
          if let some h := hit then
            let block := world.getI h.x h.y h.z
            if block != Block.bedrock && block != Block.air && coordInWorld h.x h.y h.z then
              let x := h.x.toNat
              let y := h.y.toNat
              let z := h.z.toNat
              world := world.set x y z Block.air
              pendingMeshes ← enqueueMeshRebuilds pendingMeshes world x y z
              playSound? audio.breakBlock
              particles := particles ++ spawnBlockParticles block x y z
                (time * 1000).toUInt32.toNat 18
              lastBreak := time
              toast := "Mined " ++ Block.name block
              toastUntil := time + 1.15

        let wantsPlace := (← Raylib.isMouseButtonPressed .right) ||
          ((qaInteractArg || qaPerfArg) && qaFrame == 90)
        if wantsPlace then
          if let some h := hit then
            if coordInWorld h.placeX h.placeY h.placeZ &&
                !blockIntersectsPlayer player h.placeX h.placeY h.placeZ then
              let x := h.placeX.toNat
              let y := h.placeY.toNat
              let z := h.placeZ.toNat
              let block := Block.palette[player.selected]!
              world := world.set x y z block
              pendingMeshes ← enqueueMeshRebuilds pendingMeshes world x y z
              playSound? audio.placeBlock
              particles := particles ++ spawnBlockParticles block x y z
                (time * 1000).toUInt32.toNat 10
              toast := "Placed " ++ Block.name block
              toastUntil := time + 1.15

        if time - lastSave > 18 then
          if ← saveGameSafe world player then
            hasSave := true
          else
            toast := "Autosave failed"
            toastUntil := time + 3
          lastSave := time
    | .paused =>
      if !qaWindowArg then
        let resumeClicked ← Raylib.isMouseButtonPressed .left
        if (← Raylib.isKeyPressed .escape) || resumeClicked then
          playSound? audio.ui
          screen := .playing
          Raylib.disableCursor
        else if ← Raylib.isKeyPressed .q then
          if ← saveGameSafe world player then
            hasSave := true
            screen := .title
            hit := none
            Raylib.enableCursor
          else
            toast := "Could not save — staying in world"
            toastUntil := time + 3
        else if ← Raylib.isKeyPressed .r then
          player := newPlayer world
          toast := "Returned to first light"
          toastUntil := time + 2

    particles := updateParticles particles dt
    let camera := if screen == .title then titleCamera time else playCamera player
    visuals.updateUniforms camera.position time

    Raylib.beginDrawing
    -- Clearing the colour *and depth* attachments is essential. Repainting the
    -- 2D sky alone leaves last frame's depth values behind and makes moving 3D
    -- geometry flicker or disappear behind stale fragments.
    Raylib.clearBackground Raylib.Color.black
    drawSky time
    Raylib.beginMode3D camera
    drawGpuWorld gpu visuals.material
    drawOcean
    drawClouds time
    drawGlowHalos time
    drawParticles particles
    if screen == .playing then drawSelection hit
    Raylib.endMode3D
    drawWorldTint time

    if qaWindowArg then
      drawHud player false
      drawPauseOverlay
    else
      match screen with
      | .title => drawTitleOverlay hasSave
      | .playing =>
        drawHud player showDebug
        if time < toastUntil then drawToast toast
      | .paused =>
        drawHud player false
        drawPauseOverlay
        if time < toastUntil then drawToast toast
    qaFrame := qaFrame + 1
    let motionFrame := qaFrame == 60 || qaFrame == 120 || qaFrame == 180 || qaFrame == 240
    let capturePath? :=
      if qaFirstMaximizeArg && qaFrame == 120 then some s!"{qaTmp}/axiom-first-live-maximize.png"
      else if qaWindowCycleArg && qaFrame == 120 then some s!"{qaTmp}/axiom-cycle-maximize-1.png"
      else if qaWindowCycleArg && qaFrame == 260 then some s!"{qaTmp}/axiom-cycle-restored.png"
      else if qaWindowCycleArg && qaFrame == 400 then some s!"{qaTmp}/axiom-cycle-maximize-2.png"
      else if qaMotionArg && motionFrame then some s!"{qaTmp}/axiom-motion-{qaFrame}.png"
      else if qaInteractArg && qaFrame == 70 then some s!"{qaTmp}/axiom-interact-break.png"
      else if qaInteractArg && qaFrame == 110 then some s!"{qaTmp}/axiom-interact-place.png"
      else if qaFrame == 120 then qaCapture?
      else none
    if let some path := capturePath? then
        if qaWindowArg then
          let screenWidth ← Raylib.getScreenWidth
          let screenHeight ← Raylib.getScreenHeight
          let renderWidth ← Raylib.getRenderWidth
          let renderHeight ← Raylib.getRenderHeight
          let scale ← Raylib.getWindowScaleDPI
          let (layoutWidth, layoutHeight) ← layoutSize
          let mode :=
            if qaMaximizeArg then "maximize"
            else if qaResizeArg then "resize"
            else if qaFirstMaximizeArg then "first-live-maximize"
            else if qaFrame < 160 then "cycle-maximize-1"
            else if qaFrame < 300 then "cycle-restored"
            else "cycle-maximize-2"
          let metricsPath :=
            if qaWindowCycleArg then s!"{qaTmp}/axiom-window-{mode}-metrics.txt"
            else s!"{qaTmp}/axiom-window-metrics.txt"
          IO.FS.writeFile metricsPath
            s!"mode={mode}\nscreen={screenWidth}x{screenHeight}\nrender={renderWidth}x{renderHeight}\nlayout={layoutWidth}x{layoutHeight}\nscale={scale.x}x{scale.y}\n"
        -- Entering and leaving 3D mode flushes Raylib's queued 2D HUD batch,
        -- allowing the QA readback to sample the complete frame pre-swap.
        Raylib.beginMode3D camera
        Raylib.endMode3D
        let image ← Raylib.loadImageFromScreen
        let exported ← Raylib.exportImage image (System.FilePath.mk path)
        IO.eprintln s!"QA screenshot ({exported}): {path}"
    Raylib.endDrawing
    let qaShouldExit := !qaHold && ((qaMotionArg && qaFrame == 260) ||
      (qaInteractArg && qaFrame == 130) || (qaPerfArg && qaFrame == 600) ||
      (qaFirstMaximizeArg && qaFrame == 140) ||
      (qaWindowCycleArg && qaFrame == 420) ||
      (!qaMotionArg && !qaWindowCycleArg && qaFrame == 132 && qaCapture?.isSome))
    if qaShouldExit then
      let average := if qaDtCount == 0 then 0 else qaDtTotal / qaDtCount.toFloat32
      IO.FS.writeFile s!"{qaTmp}/axiom-qa-perf.txt"
        s!"frames={qaDtCount}\navg_ms={average * 1000}\nmax_ms={qaDtMax * 1000}\nmax_frame={qaDtMaxFrame}\n"
      break

  Raylib.enableCursor
  Raylib.closeAudioDevice
  Raylib.resetAudioThreadEntryCallback
  Raylib.resetAudioThreadExitCallback
  Raylib.closeWindow ctx
