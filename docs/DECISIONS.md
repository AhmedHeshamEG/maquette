# Decisions

Every non-obvious choice, with the reason. D1–D86 are the 1.x decisions, kept as history; where 2.0 replaced one,
the 2.0 entry (R…) says so. Maquette's decisions continue from D-87, one section per phase. What the product is lives in [SPEC.md](SPEC.md); how it's built in
[ARCHITECTURE.md](ARCHITECTURE.md).

## Engineering

**D1 — Three layers: LoweyCore (pure Swift) / LoweyRender (RealityKit) / App (SwiftUI).**
Core has zero Apple UI/3D imports, so its 100+ tests run on Linux in seconds (Docker on Windows, `swift:6.1` in CI).
RealityKit only exists in LoweyRender.

**D2 — Commands are an enum that returns its own inverse.**
`EditCommand.apply(to:)` returns `(inverse, changes)`. Undo = apply the inverse. This makes "every command reverts
perfectly" testable generically (`assertReverts` applies, inverts, re-applies and JSON round-trips each command)
and makes commands serialisable for Scene Scripts. Applying is atomic (works on a copy, commits on success).

**D3 — Gesture coalescing.** Continuous edits (joystick, gizmo drags, sliders) carry a `coalesceKey`; the session
merges them into one undo step and keeps the *first* inverse (pre-gesture state).

**D4 — Transform is stored as three animatable properties** (`position`, `rotation`, `scale`), not a separate field.
Phase 2 keyframes any property the same way; nothing about transforms is special.

**D5 — Colours quantised to 8 bits; dates stored as raw `timeIntervalSinceReferenceDate`.**
Hex colours and ISO dates lose precision, which broke "save → reopen → identical". Quantising on creation and storing
the native date value makes round trips bit-exact (tested).

**D6 — Versioned envelope + migration chain from day one.** Files are `{schemaVersion, kind, payload}`. Unversioned
files are treated as v0 and migrated (the v0 → v1 scene migration converts object arrays and nested transforms; tested
with a hand-written fake v0 file). Files from a newer app are refused with a clear message.

**D7 — Crash-safe writes.** `Data.write(.atomic)` plus a `.bak` of the previous good version; the loader falls back to
the backup when the main file is damaged (tested by corrupting a file). A damaged file never overwrites a good backup.

**D8 — Look lives on the project with an optional per-scene override.** `Scene.look == nil` inherits the project look.
The Enigma sets need three different moods in one project, but the palette should normally be shared.
"Only this scene" in the Look panel creates/removes the override.

**D9 — Primitives pivot at the centre of their base.** Things sit on the ground and grow upward when scaled (Lego-like),
which makes placing, stacking and swapping predictable.

**D10 — Smooth shading = auto-smooth (60°), not fully welded normals.** Hesham prefers soft low-poly; fully smoothed
cubes look like blobs. Auto-smooth keeps hard edges hard and round things soft. Flat = faceted.

**D11 — Drawn objects store the recipe (strokes + style), not triangles.** Small files, deterministic regeneration,
editable later (Phase 3 could re-style a stroke).

**D12 — Prefabs are referenced, not copied.** A prefab instance is one object (`kind: prefab(id)`); the renderer
expands the library fragment. Updating the prefab bumps its version and every instance rebuilds. "Unpack" turns an
instance back into editable objects. "Save a copy" keeps the selection as plain objects.

**D13 — Swap keeps position and rotation, fits the model uniformly into the blockout's size, keeps the base on the
ground.** Literally keeping the blockout's non-uniform scale would distort the model.

**D14 — Scatter is seeded.** The seed is part of the generated command, so undo/redo and re-applying a Scene Script
reproduce the same forest.

## Rendering

**D15 — ARView (non-AR) for the live stage, RealityRenderer for offscreen.**
`ARView(cameraMode: .nonAR)` is mature on iPadOS (not deprecated), gives direct UIKit gesture control, `ray(through:)`,
`project(_:)`, and statistics overlay. SceneKit is not used (soft-deprecated). `RealityView` was considered; ARView
won for picking/projection APIs and predictable camera control. Revisit in Phase 3 if RealityView gains something we need.

**D16 — Offscreen rendering spike: `RealityRenderer` (iPadOS 18+).**
Findings (verified against Apple's documentation):
- `RealityRenderer` is available on iPadOS 18+ (we target 26). It renders a separate set of entities
  (`entities`, `activeCamera`, `lighting` IBL, `cameraSettings.colorBackground/antialiasing`) into any `MTLTexture`
  via `updateAndRender(deltaTime:cameraOutput:…onComplete:)` with `CameraOutput(.singleProjection(colorTexture:))`.
- It needs its own entities, so we render a **clone** of the world (helpers stripped). Clones share meshes and
  materials, so this is cheap.
- `deltaTime` is ours to choose → Phase 2 video export renders frame by frame at a fixed timestep, independent of
  real-time speed. Output textures are `bgra8Unorm_srgb`, shared storage, read back with `getBytes`.
- Proven in CI by `RenderTests.testEnigmaSetsRenderOffscreen` (renders every Enigma set at 16:9 and 9:16 and checks the
  image isn't blank) and by library thumbnails. Fallbacks considered: `ARView.snapshot` (only what's on screen, fixed
  size) and raw Metal (too much to rebuild). Not needed.

**D17 — Fog is in the material, not a post-process.** RealityKit has no fog. ARView's post-process callback has depth
but `RealityRenderer` exposes no depth output, so a post-process fog would differ between preview and export.
A `CustomMaterial` surface shader computes exponential distance fog per pixel from the view-space position — identical
everywhere. Imported materials are converted with `CustomMaterial(from:surfaceShader:)` (textures kept). If the shader
library can't load, everything falls back to `PhysicallyBasedMaterial` without fog (logged; tested in CI).

**D18 — The shader lives in the LoweyRender package** and is compiled by Xcode into the package bundle
(`makeDefaultLibrary(bundle: .module)`), so the render tests exercise it too; the loader also checks the app bundle.

**D19 — Orthographic = 2° telephoto.** `OrthographicCameraComponent` exists (iOS 18) but ARView/RealityRenderer camera
support for it is less proven, and picking/projection would need a second code path. A 2° field of view from far away
is visually orthographic, works in both renderers, and keeps one ray/projection path. The sky dome follows the camera
and grows so it never clips.

**D20 — Sky = unlit dome with a generated gradient + stars texture; ambient light = IBL generated from the same sky.**
Night scenes get dark, cool ambient light automatically; day scenes get bright ambient — one decision (the mood)
drives both.

**D21 — Instancing: shared resources, not `MeshInstancesComponent` (yet).** Model clones share their prototype's
`MeshResource` and materials; identical Lowey surfaces share one material instance. RealityKit batches these.
`RenderTests.testFiftyInstancesPlaceAndRender` asserts the 50 foxes share one mesh. `MeshInstancesComponent` (iOS 26)
is the Phase 3 performance-pass option for thousands of static objects (it loses per-instance selection).

**D22 — Selection and picking use box collision shapes** from content bounds (cheap). Drawing on an object uses an
exact CPU raycast against the object's world mesh (`MeshRaycast`, tested), built on demand when a stroke starts.

**D23 — Snapshots match the on-screen framing guide.** The export camera's field of view is derived from the guide
rectangle drawn over the stage, so a 9:16 snapshot contains exactly what the portrait guide showed.

## Library & assets

**D24 — glTF/GLB are kept as files in the library and loaded with GLTFKit2 each session.** Converting to USDZ on device
isn't possible without Mac tools. `.gltf` imports copy their referenced `.bin`/textures (tested).

**D25 — Rig detection by joint-name heuristics** (Mixamo, Quaternius-style, generic; birds via wing/beak, quadrupeds via
front/back legs or tail without arms). Skeletons and clips are kept intact for Phase 2; the library shows a RIGGED badge.

**D26 — Search-first library with ranking** (exact name > prefix > word prefix > tag > substring > fuzzy subsequence,
every word must match, favourites get a boost). Filters: All, Favorites, Recent, Models, Built (prefabs), Looks.

## Product

**D27 — New project = a name + one mood.** Few decisions, big result; everything else can change later.

**D28 — First launch creates the "Enigma — sets" sample** (desk + paper + warm lamp; 12 people at PCs; hero robot in a
cave), built only from blockout, drawing recipes and lights through the command system. It's both onboarding and the
Phase 1 proof.

**D29 — Pencil draws, fingers navigate** (Draw tool). A toggle allows finger drawing for people without a Pencil.

**D30 — Tapping part of a group selects the top-most group; tapping again digs one level deeper** (Keynote/Figma
style), so blocked-out assemblies behave like Lego pieces.

## CI

**D31 — Runner `xcode-27` with Xcode 27.0 pinned (`DEVELOPER_DIR`).** It's the image with the iPadOS 27 SDK.
Deployment target stays iPadOS 26.0 (SpeechAnalyzer needs 26).

**D32 — Render tests run as an unhosted test bundle** linking the packages directly, so RealityKit code is tested on
the simulator without linking the packages twice into a hosted bundle. The UI smoke test drives the real app.

**D33 — Test screenshots and renders are exported from the xcresult as a CI artifact** (`test-attachments`) — visual
evidence without a Mac.

## Phase 2 — motion, camera, characters, export

**D34 — One evaluator for everything that moves: `Animator.evaluate(document, at:)`.** Tracks, per-object stepping,
behaviours, camera cuts and character poses are resolved by one pure function in LoweyCore. The stage, snapshots,
the exporter and the tests all call it, so preview and export can't drift apart and every rule is unit-tested on Linux.

**D35 — The stage shows the scene *as evaluated at the playhead*; tools edit what you see.** `EditorModel.scene` is
the evaluated scene. Editing an animated property (or any animatable property in Animate/Camera mode with auto-key on)
is rewritten into a key at the playhead (`EditorModel.keyed`). A brand-new track also gets a key at 0 holding the old
value, so the first edit already animates instead of just snapping. Structural edits (add, delete, group) are never keyed.

**D36 — `setTracks` is the fine-grained key command; everything else in the timeline uses `setTimeline`.** Keying
while dragging happens many times per second: `setTracks` carries only the touched tracks and coalesces (latest
track wins, first inverse kept), so a whole gesture or Perform take is one undo step. Markers, cuts, behaviours and
clip tracks change rarely and go through `setTimeline`.

**D37 — Deleting / duplicating objects takes their animation along.** Delete removes their tracks, behaviours, clips and
cuts in the same undo step; duplicate copies them (position keys of top-level copies are shifted with the copy).

**D38 — Schema v2.** New timeline fields are optional with defaults (Phase 1 files open unchanged; tested), but the
version is bumped so a Phase 1 app refuses v2 files instead of silently dropping animation when it re-saves them.

**D39 — Presets, camera moves, simulations and Perform takes all produce plain keyframes.** Nothing is a hidden effect:
everything can be edited, retimed, copied or deleted in the timeline. Presets are relative to how the object looks at
the playhead; applying one replaces keys only inside its own time span.

**D40 — Behaviours are stateless functions of time.** Noise is lattice value noise seeded by the behaviour id; `follow`
with lag reads the target's *keyed* position at `time - lag` (no simulation state). Any frame can be evaluated in any
order — required for scrubbing and for exact, parallelisable export. Baking samples them at the project fps.

**D41 — Simulations run in LoweyCore at a fixed timestep and bake, instead of RealityKit's live physics.** RealityKit's
simulation advances with the display clock, can't be stepped headlessly, and doesn't promise identical replays; a baked
take must be exact and testable. Rigid bodies are spheres fitted to the bounds (ground + body collisions, bounce,
friction, explode impulse); flocks are boids; crowds walk to targets with separation. All deterministic (tested).

**D42 — Perform = live override + recorded samples → `PerformBaker`.** While recording, touches drive a per-object
override on top of the evaluated scene (you see the motion immediately); samples are taken on every display frame at
the playhead time. Lifting the finger ends a segment (the timeline keeps playing). At the end the baker resamples to the
project fps, smooths with a zero-phase filter (the curve doesn't lag behind the finger), simplifies (Ramer–Douglas–Peucker)
unless smoothing is 0 % ("capture everything"), and replaces only the performed ranges — one undo step.

**D43 — Characters: skeletons and clips are read by LoweyCore from the glTF file (`GLTFReader`), not from RealityKit.**
RealityKit plays clips but can't sample, blend, retarget or apply IK to them deterministically. Reading the glTF skin
and animation channels in pure Swift makes clip playback, crossfades, retargeting, IK and path-speed matching part of
the tested evaluator. Poses are written to `ModelEntity.jointTransforms`, applied relative to the model's own rest pose
(so armature/axis conventions don't matter). USDZ models without Core rig data fall back to RealityKit's own animation,
paused and scrubbed (`applyClipFallback`).

**D44 — Retargeting in model space.** Bones are auto-mapped to a standard (Humanoid, Quadruped, Bird) by name and
chain; each mapped bone's rotation change from rest is transferred as a model-space delta, and the hips' travel is
scaled by hip height. Works across Mixamo/Quaternius/Blender naming and differing local bone axes, as long as rest
poses are similar (T/A pose facing +Z). Tested on two humans of different sizes and naming, and two quadrupeds.

**D45 — Walking without foot sliding = speed matching, plus feet-on-ground IK.** The clip's stride speed is measured
(root motion if the hips travel, otherwise from how far the feet sweep in a cycle); "Walk speed = path speed" sets the
clip speed to path speed ÷ stride speed. IK keeps feet above the ground; look-at turns the head; reach bends an arm.

**D46 — Cameras: the stage looks *through* the shot camera in Camera mode.** The stage widens its field of view so the
framing guide covers exactly the camera's frame (WYSIWYG with export). Dragging aims the camera (pan/tilt), two
fingers move it, pinch dollies, twist rolls — keyed at the playhead. Cuts are a list of (time, camera).

**D47 — One camera, two framings.** 16:9 uses the camera as framed; 9:16 uses the same vertical field of view × a
per-camera *portrait zoom* and a *portrait pan* (a small yaw), both animatable. One scene exports both without a
second camera.

**D48 — Virtual camera = ARKit world tracking relative to where you started.** The rear camera tracks the iPad
(works on iPad Air; no TrueDepth needed). The device's motion since the start is applied to the scene camera with a
scale factor (1 m of walking can be 10 m in the world) and recorded through Perform like any other take.

**D49 — Export renders frame by frame in a dedicated world.** `VideoExporter` owns a second `SceneRenderer` without
editor helpers and one persistent `RealityRenderer`; for each frame it evaluates the timeline, syncs only what moved,
renders every framing into its own texture and appends it to an `AVAssetWriter` (H.264/HEVC .mp4; HEVC-with-alpha
.mov when transparent) or writes PNGs. It waits for models to load and renders warm-up frames before frame 0. The
stage stays usable; progress and cancel are in the Export panel. Determinism is tested (same frame twice → same pixels).

**D50 — Depth of field is stored and animatable (focus distance, aperture, focus pulls) but not yet rendered.**
`RealityRenderer` exposes no depth output (see D17), so a correct lens blur needs a separate depth pass. The lens data
is in place so Phase 3's post-processing pass (bloom, grain, lens blur…) can render it identically in preview and export.

**D51 — Scripting is JavaScriptCore in its own package (`LoweyScript`), returning ONE command.** Scripts run on a
worker thread against a copy of the document with a time limit; every API call is a real command applied to that
copy (so later calls see earlier results); the collected commands come back as one batch the editor performs —
undoable like any tool. No file, network or timer APIs are exposed. `lowey.random(seed)` is a deterministic xorshift.
JavaScriptCore doesn't exist on Linux, so its tests live in the app test bundle.

**D52 — 3D export is written in LoweyCore (GLB + USDZ).** Blockout and drawn objects export from their exact recipes;
library models and prefab instances are read back from their loaded meshes (geometry only — textures aren't carried).
USDZ is an uncompressed zip with 64-byte-aligned entries around a USD text layer with `UsdPreviewSurface` materials.

## Phase 3 — story, voice, VFX, AI, polish

**D53 — Keyframe multi-select is one gesture layer over all lanes, with the logic in Core (`KeySelection`).** Procreate
Dreams-style: long-press-drag (or the Select toggle + drag) draws a box across rows and time; the Pick menu selects all /
after / before / at the playhead / in the loop / invert; a band on the ruler stretches or squashes the selected keys'
timing; Compose mode moves several bars together. One recogniser for every lane (instead of one per row) is what makes a
box that spans tracks possible. Selecting never changes the document; moves and stretches are one undo step each.

**D54 — Audio lives in the timeline (`audio`, `transcripts`) and is mixed in Core.** Clips reference files in the
project's `audio/` folder. `AudioMixer` (pure Swift) mixes exactly what the preview plays (volume × fades × envelope, soft
limiting), so exports are deterministic and tested on Linux; the app only decodes (AVAudioFile → 48 kHz float) and plays
(one `AVAudioPlayerNode` per clip). During playback the picture follows the audio clock (host-time anchor), so sound and
picture never drift. Schema v3 (additive).

**D55 — Word timing: SpeechAnalyzer + SpeechTranscriber with `.audioTimeRange` (no Whisper).** Verified against Apple's
documentation (Speech, iPadOS 26). Audio is converted to `SpeechAnalyzer.bestAvailableAudioFormat` first; the model is
installed on first use with `AssetInventory.assetInstallationRequest`. Recogniser runs holding several words are split by
length inside their range. Words are stored in *file* time per clip, so trimming or moving the clip keeps them in place.
Corrections replace words and keep (or share) their timing. English, Arabic and Italian are offered first when supported.

**D56 — Syncing to words = snapping + word-addressed times.** Keys, the playhead, audio clips and effects snap to word
edges; transcript phrases carry presets, camera moves, cuts and markers. Scene Scripts address time as
`{"word": "Enigma"}`, so AI-built shots land on the voice by construction.

**D57 — Overlays are scene objects in frame space.** `ObjectKind.overlay` (titles, labels, arrows, the X, the question
mark…) with x/y in −1…1 of the frame, so presets, keys, Perform, stagger and scripts animate them with no new machinery.
Size is relative to the frame's short side (the same overlay reads the same in 16:9 and 9:16; titles shrink to fit narrow
frames). An overlay can follow a 3D object (projected through the shot camera). One CoreGraphics renderer draws them for the
stage and for export.

**D58 — 3D text: a built-in 5×7 block font meshed in Core ("Blocky"), system fonts through RealityKit otherwise.** The
block font is low-poly by design, exact in bounds and in 3D export, and tested; `MeshResource.generateText` covers smooth
styles and every script (Arabic).

**D59 — Particles are a pure function of time.** Each particle's life is computed in closed form from its index and a seed
(ballistic motion with drag, swirl, colour over life). Scrubbing, loops and export are exact; the same frame is the same
pixels (tested). Meshes are octahedra (diamonds, streaks, tumbling cards) grouped into ≤ 8 colour bands — a few draw calls
per effect. RealityKit's `ParticleEmitterComponent` isn't used: it simulates with the display clock and can't be evaluated
at an arbitrary time.

**D60 — One compositor for preview and export (Core Image).** Order: shot (lens blur → ink outlines → bloom → grade →
chromatic aberration → retro) → transition → screen effects (shake, zoom blur, glitch, speed lines, flash) → film (texture,
vignette, grain) → overlays and captions. The stage runs it in ARView's post-process callback, the exporter on every
rendered frame. When nothing needs it the stage switches the pass off (no cost).

**D61 — Depth for lens blur and outlines is stored as v = 0.5 / distance.** The circle of confusion is linear in
1/distance, so this is the natural encoding. Export renders a second "depth world" (every surface the unlit `loweyDepth`
shader, sky off) at half resolution; the stage converts RealityKit's reverse-Z depth buffer with the `loweyInverseDepth`
compute kernel. Both give the same v, so blur matches. This resolves the Phase 2 limitation (D50).
`Phase3Tests.testDepthPassEncodesInverseDistance` checks the export path against known distances.

**D62 — Transitions are centred on their cut and render both shots in export.** The exporter renders the outgoing camera
into a second target and blends. The live preview shows the cut (two cameras live would halve the frame rate).

**D63 — Lip sync from words with the CMU Pronouncing Dictionary, not audio analysis.** `scripts/make_visemes.py` turns
CMUdict (BSD) into word → Rhubarb / Preston Blair mouth shapes (A–H, X), shipped as a Core resource; unknown English words
use letter-to-sound rules, Italian is phonetic, Arabic letters map directly (short vowels assumed). Shapes become keys
(`mouth`, stepped) plus eased `jawOpen` / `mouthWide`, so lip sync is editable like any animation. The voice's loudness is
the fallback for words without known sounds.

**D64 — Faces are channels on the character root, applied by a face rig inside the evaluator.** `jawOpen`,
`blinkLeft/Right`, `brows`, `smile`, `mouthWide`, `lookX/Y`, `headYaw/Pitch/Roll`, `mouth`. Parts carry a `faceRole`
("eye.L", "mouth.D"…); the rig scales eyes, lifts brows, swaps mouth shapes (Toonsquid-style) and turns the head after
clips. Keys, lip sync, live face capture and the iPhone companion all write the same channels; live values are evaluator
overrides, recorded by Perform like any slider.

**D65 — Face capture: Vision landmarks on the iPad; ARKit blend shapes from an optional iPhone.** The iPad Air has no
TrueDepth camera. Ratios (eye openness, brow height, mouth opening relative to eye distance) against a calibrated neutral
face, smoothed with a One Euro filter. The same app on an iPhone is the companion (device family 1,2; iPhones only show the
companion screen) and streams newline-delimited JSON over Bonjour (`_loweyface._tcp`) — no entitlements beyond local network.

**D66 — Hesham's character is a puppet built from parts on the Humanoid standard.** The builder makes low-poly parts
under joints named with humanoid bones. `PuppetRig` turns the joints into a skeleton (arms straightened to a T-pose for
retargeting only), so every humanoid clip — the ten built-in ones and any imported Mixamo-style clip — plays on it through
the existing retargeter; poses are written back onto the joint objects. The recipe is stored on the character so it can
be reopened and rebuilt (the root keeps its id and animation).

**D67 — AI speaks "actions", compiled in Core.** Scene Script v2 adds friendly actions (names instead of ids, word times,
presets, camera moves, characters, look…) that `ScriptCompiler` turns into ordinary commands against the current document —
one undo step, with a plain-language preview. Errors name the action and what exists, so a model can correct itself. The
same language is served by the bridge, used by lowey-mcp and the skills, and by the app's own samples (the narrated Enigma
story and the welcome island are scripts).

**D68 — The LAN Bridge: HTTP/1.1 + WebSocket on Network.framework; parsing, auth and routing in Core.** Off by default;
answers only private and link-local addresses; pairing with a 6-digit code (ten wrong guesses change it); bearer tokens.
Scripts from the bridge wait for Hesham's approval on the iPad (preview sheet) unless he turns on auto-apply.

**D69 — lowey-mcp and lowey-link are Python (official MCP Python SDK 2.x).** The laptop already runs Python for Blender;
the SDK makes each tool a typed function. Tools map 1:1 onto actions; replies are a few lines (token-cheap). Tested in CI
against a fake bridge.

**D70 — Projects travel as `.loweypack` (a stored zip).** Core writes and reads it (with CRC checks), so packaging is
tested on Linux; library assets are embedded first. Archive moves projects to `Projects/Archive`.

**D71 — Diagnostics stay on the iPad.** A rotating log, MetricKit diagnostic payloads (crashes, hangs) delivered on the
next launch, an "ended unexpectedly" marker, and "Export diagnostics" (a zip Hesham chooses to share). No telemetry.

**D72 — Thermal-aware preview.** At `.serious` the stage renders at ⅔ scale and skips depth effects; at `.critical`, 1×.
Exports render offscreen and are unaffected.

**D73 — Performance pass: what was done and what was deliberately not.** Done: particles as a few banded meshes (D59),
shared meshes and materials for repeated objects (D21), the post pass switched off when unused (D60), overlays redrawn
only when they change, thermal-aware preview (D72). Not done yet: distance LODs and texture compression for imported
models, and `MeshInstancesComponent` for thousands of static copies — the 60 fps budget scene (~300 low-poly objects,
3 characters, 2 particle systems) has to be profiled on the iPad Air first ("profile before optimizing"); CI simulators
can't measure GPU frame times. Show FPS & stats is in the scene menu for that.

## Phase 4

**D74 — The house character is traced, not redrawn.** `assets/avatar/trace_drawing.py` measures Hesham's drawing
(silhouette rows, every stroke as a contour, Poisson-inflated meshes for non-round parts) and the Blender build uses only
those numbers. The drawing stays the source of truth; the in-app blob uses the same measurements.

**D75 — Blobs are ordinary scene objects.** Lathes, slabs and ribbons (existing drawing kinds), so the face rig, keys,
Perform, scripts and exports needed no special cases. Face parts are true size; `faceRange` tells the rig how far.

**D76 — Cartoon timing is a spring convolution.** A blob's dials are the keyed target convolved with a damped spring's
impulse response over the last ~1.5 s. Deterministic (preview = export, any frame in any order), no simulation state.
Poses are keyed as steps; the springs make the in-betweens, overshoot and settle.

**D77 — Rubber hose over rigs.** Arms are bezier tubes rebuilt from shoulder and hand each frame, in the hose's own
space (so tilting or floating never changes their shape) and only when an end moved.

**D78 — RealityKit render callbacks wait for the first frames.** Installing `renderCallbacks.postProcess` before the
stage renders traps (EXC_BREAKPOINT); the stage now waits for two scene updates. Found by a UI test that plays the tour.

**D79 — Exports assume the GPU can disappear.** Every render has a deadline; the exporter waits while the app is in
the background; the idle timer is off during exports.

**D80 — Video overlays are keyed frames.** A video overlay becomes `file#t=seconds` at layout time; the export decodes
that exact frame, the stage the nearest one (never waiting). Manim renders arrive as ProRes 4444 with alpha, packed with
PyAV (ships with Manim), because the laptop is Windows (no HEVC-with-alpha encoder).

**D81 — One skill, an orchestrator and modules.** `skills/lowey/SKILL.md` routes and holds the rules; each module does
one job. Adding a capability is adding a module.

## v1.4

**D82 — Rotation pivots are origins.** One object turns around its own pivot; several around the mean of their pivots.
Both stay fixed while turning (a bounding-box centre moves as the box turns). Rings are picked on screen by distance to
the drawn ring, not by collision shapes.

**D83 — Face channels use the mirror's sides.** `blinkLeft` is the eye on the left of the (mirrored) picture, turns and
tilts likewise; trackers' left/right labels aren't trusted (they swap in mirrored pictures). The Mirror switch flips
everything in one place. Rest pose (head, gaze, dials) is subtracted; blinks, jaw and hands are absolute.

**D84 — Media cards are objects, overlays are graphics.** Pictures and videos default to a `card` object in the world;
overlays stay for graphics that belong to the frame (transparent Manim). Card textures change only when the frame does.

**D85 — Timeline rows scroll under our own gesture.** A SwiftUI `ScrollView` loses its pan to a `DragGesture` on its
content (iPadOS 18+), and the lanes need that drag. The lanes decide once per drag: keys, box, time or rows.

**D86 — The bridge keeps the app alive with silent audio.** iOS suspends a background app within seconds; a VPN-style
status icon needs a Network Extension (paid developer account), and Live Activities don't show on iPad. The app is
sideloaded, so it uses the audio background mode: while the bridge is on and the app is away it plays silence mixed with
other audio, and posts a quiet "Bridge on" notification. Drawing (snapshots, export) still waits for the foreground.

## 2.0 — Remaster, phase 1

**R1 — `legacy/v1` starts at the v1.4.3 tip, not v1.4.2.** 1.4.3 shipped after the remaster was specified; the legacy
branch and the `v1-final` tag point at what users actually have.

**R2 — Shared code lives in hmm-kit, a public package pulled in as a git subtree (`Packages/HmmKit`).** Public, so the
subtree needs no credentials in CI and its own CI runs on free minutes. Lowey depends on its products and never edits
the subtree in place: changes go to hmm-kit first, then `chore: sync hmm-kit`.

**R3 — Four layers: LoweyCore → LoweyEngine → LoweyFeatures → App** (supersedes D1). Core stays pure Swift and
Linux-tested. The engine owns Metal, import, export, the stage view, audio, face capture and scripting. Features are
the SwiftUI editor. The app target is only the entry point, menu commands, background tasks and the widget.

**R4 — LoweyRender 2 on Metal replaces RealityKit** (supersedes D15 and the 1.x rendering decisions). One renderer
draws the stage, thumbnails and every export, so the preview is the export (tested pixel for pixel). RealityKit
couldn't give lines, a Look system, exact picking, deterministic frames or control over the compositor.

**R5 — glTF is read by a pure-Swift reader in LoweyCore** (GLTFKit2 removed). It runs in the Linux tests, needs no
binary dependency, and the importer and the skeleton reader share one parser.

**R6 — Only the sun casts shadows (two cascades); point and spot lights don't.** Up to 16 of them light a frame (the
nearest to the camera win). Shadowed local lights cost a shadow map each; the Looks get their mood from the sun,
contact shading and lines.

**R7 — Metal front faces are counter-clockwise.** Every mesh in LoweyCore winds counter-clockwise; with Metal's
default (clockwise) every visible face read as a back face, normals flipped and objects shadowed themselves.

**R8 — Golden images are recorded on the CI simulator and reviewed before they're committed.** The simulator's GPU
differs from a device's, so goldens come from where they're checked: a missing or changed golden fails the test and
uploads the render; once it looks right it's committed. Tolerance: 1 % of pixels may differ by more than 24 levels.

**R9 — Spike results.** Metal and 4× MSAA work in the CI iPad simulator. The simulator's encoder has no 4K HEVC and
drops out (or hangs the test runner) at 4K and 1440p H.264, so the simulator runs the export pipeline at 1080p and
4K HEVC is on the device checklist. GPU
skinning works there (walker golden). MetalFX is device-only; the simulator falls back to bilinear scaling.

**R10 — 1.x projects open in the Clay Look** (Low-poly when the project used flat shading): the closest to the
RealityKit picture, so nothing looks broken after the update. Choosing another Look is one tap.

**R11 — Features are folders in one target, and folders never reference each other.** One SwiftPM target keeps build
times down; `Tools/check-feature-boundaries.py` (in CI) fails when a feature names a top-level type of another.
Workspace is shared by all (models, session API, controls); Shell is the composition root and may use every feature.
Theater settings and the tour go through `AppModel`, not across features.

**R12 — One editor, no modes, in Procreate Dreams' grammar.** Five modes hid tools behind a switcher. Now the Stage
sits over the Timeline; document things are in the top-left cluster, making tools in the top-right one, two context
sliders and undo / redo in a sidebar (mirrorable), and the inspector appears only while something is selected.
⌘1–5 open the Select, Build, Draw, Transform and Look panels.

**R13 — Auto-key belongs to the timeline's Keyframe mode; Compose (the default) never creates keys.** In 1.x an
accidental drag in Animate mode made keys nobody asked for.

**R14 — Universal gestures (two-, three- and four-finger taps, two-finger hold) live on hmm-kit's gesture layer at
the window**, so they work over panels and sheets the same way; the stage no longer handles them.

**R15 — The joystick stays, optional and off by default** (Transform ▸ Joystick). Direct touch covers most moves; the
game-controller Fly performer is phase 2.

**R16 — Selection is drawn as a silhouette outline, not a box.** It reads on any shape and in every Look, and comes
from the ID buffer the picking already has.

**R17 — Project cards play a looping GIF** (8 fps, 2.4 s) through the shot camera, next to a still PNG thumbnail.

**R18 — Export runs on the main actor, encoders on the caller's actor.** `ExportSession` is `@MainActor`, and HmmMedia
builds with `NonisolatedNonsendingByDefault`, so its async encoder API runs where it's called and pixel buffers are
never sent across actors (Swift 6, no warnings).

**R19 — Background export is a `BGContinuedProcessingTask`** (iPadOS 26), with GPU access where the device grants it;
otherwise the export waits while the app is away and continues when it's back (as in 1.x). Progress goes to a Live
Activity where the system shows them, and a notification says when it's done either way.

**R20 — Exports are verified before they're handed over** (frame count, size, length, audio track, alpha) by
HmmMedia's inspector. A broken file is an error, not a share sheet.

**R21 — The bridge is off until it's turned on, pairs with a one-time code and keeps tokens in the Keychain**
(supersedes the 1.x bridge decisions and D86's "on by default"). The permanent `000000` code and `lowey-mcp --public`
are gone, and so are the tunnel modes: a creative tool shouldn't be an open door on café Wi-Fi. Unpaired requests get
401, non-local ones 403, a pairing attempt with no code on screen 409 (tested).

**R22 — The silent-audio keep-alive (D86) stays for sideloaded builds only.** Feature flags in Info.plist
(`LoweyAIBridge`, `LoweyBackgroundBridge`) switch the bridge and the keep-alive off in the App Store configuration.

**R23 — LoweyCore's 1.x bridge code is removed.** Its HTTP parser and `BridgeAuth` (with the permanent code) are
replaced by HmmBridge; Core keeps only the compact scene, transcript and asset summaries the bridge sends.

**R24 — iCloud only in the App Store configuration.** A sideloaded build can't carry the iCloud entitlement, so
`DocumentLocator` falls back to on-device storage and says so.

**R25 — The Night Market benchmark uses a generated walker** (`BenchmarkFigure`, an 11-bone box figure with a walk
cycle, made in LoweyCore and seeded into the model library), so it needs nothing from the user's library and runs the
same everywhere. Target on a device: p95 frame time ≤ 8.3 ms at render scale ≥ 0.85.

**R26 — Finish ▸ Outline adds lines over any Look.** Lines are a renderer pass, so any Look can have them, not only
Ink and Comic.

**R27 — Lint at the STUDIO limits, strictly.** SwiftLint runs with `--strict`: files ≤ 500 lines, type bodies ≤ 350,
functions ≤ 60, complexity ≤ 12 (switch cases don't count: a switch over an enum is one decision, not twelve), no force
unwraps outside tests. Long lines inside multi-line strings are allowed: they're Scene Script and JavaScript examples
shown to people and to the AI, and wrapping JSON objects mid-line would make them harder to copy.

**R28 — Colour literals go through `RGBA.hex(_:)`,** which takes a `StaticString` and falls back to magenta, so a
mistyped literal shows on screen instead of crashing, and there are no force unwraps.

**R29 — Script time limits are checked at every API call.** JavaScriptCore has no public execution time limit on
iOS, so a loop that never calls `lowey` or `scene` can't be stopped (BACKLOG). Every loop that builds anything calls
the API, and those stop.

**R30 — Flipbook tracks are phase 2, and so is the Mac target.** Phase 1 rebuilds the engine and the editor; LoweyCore
and hmm-kit already compile for macOS.

**R31 — The 1.x app's render and export tests were ported, not dropped.** They moved from the hosted app tests to
LoweyEngine's tests on LoweyRender 2 (export, scene, library and script tests), with the animal-pack fixtures. Two
checks were 1.x-specific and are gone: the RealityKit depth-pass calibration (the Metal renderer has a real depth
buffer) and the RealityKit post-processing install timing.

**R32 — CI retries a failing engine test up to twice.** The simulator's software video encoder now and then stops
accepting frames or hangs the test runner, whatever the size (a 160 × 90 export did it once), and the same test passes
on the next run. Retrying keeps CI meaningful without hiding a real failure: a test that fails three times in a row
still fails the build, and every retry shows in the log and the result bundle. Video encoding itself is checked on a
device (the PR checklist).

**R33 — The UI smoke tests get the engine's retries, and both simulator jobs a second attempt.** On the same commit
each smoke test has passed and failed: the simulator now and then can't terminate the app between tests, or stops
answering a UI query (the app idle, the query never returning). Each UI test now gets up to three tries, like the
engine tests (R32). When the test runner itself hangs before it connects, no per-test retry runs, so the engine and
UI steps run `xcodebuild test` a second time; the build is incremental, so the second attempt costs only the tests.
A test that fails every time still fails the build, and each retry and attempt shows in the log.

## 2.0 — Remaster, phase 2

**R34 — Ink strokes are a drawing style, meshed toward the camera every frame.** `DrawingRecipe.Style.ink` keeps the
strokes (points + pressure widths) like the solid styles, so guides, mirror, Scene Scripts, export and undo all work
unchanged. The renderer builds each ink drawing as flat ribbons facing the frame's camera (`InkMesher`, cached by
eye position and reveal), unlit in the object's colour, with an ID flag that keeps the line pass from outlining
them: they are lines already. A billboarding vertex shader would have needed its own prepass, shading and shadow
pipelines for a few hundred vertices per drawing. Strokes join the selected ink drawing (a new one starts when
nothing ink is selected), like drawing on the current layer; `reveal` writes a drawing on.

**R35 — Frame rates resolve per object, every frame, in one place (`FrameRates`).** Own rate (keyable) → nearest
ancestor's → characters take their Look's (Comic: twos) → cameras ones → the project's. Phase 1 stored a Look frame
rate that nothing read; now it decides, and an animated `stepping` lets a character drop to twos for one beat.

**R36 — Flipbooks are timeline tracks drawn as 2D, blended in the composite.** A track is drawings with hold lengths
(the Dreams model) anchored to the camera (frame-height units, so 16:9 and 9:16 share one drawing) or to an object
(metres on the camera-facing plane through its pivot, so it shrinks with distance). Normal tracks draw into the
overlay image under titles and captions; multiply, screen and add tracks get one layer each, blended with the shot in
sRGB like a painting app. Drawing past the last drawing holds it to the playhead and starts a new one, so drawing at
the playhead is how you animate. The drawn-effects library is strokes too, so every effect stays editable. Speed lines
are parallel streaks behind the mover (Western comic), not radial focus lines.

**R37 — Motion paths, onion skin and smears are views of the keys, not new data.** Paths and smears read keys only
(object + parents, `MotionPath`), so they're cheap enough to compute every frame and the same in every export; ghosts
evaluate the whole scene at the neighbouring keys and are cached until the document or playhead frame changes. Ghosts
skip the prepass (never picked, outlined or shadowed) and only appear with the select tool.

**R38 — The graph editor edits the same per-segment easing the timeline already stored.** A segment's tangent
handles are its cubic-Bézier easing (normalised between the two keys), so the graph, the Easing menu and Scene Scripts
all speak one model and nothing old needed migrating. Rotations are drawn as the three turn angles.

**R39 — Poses and IK handles are for Blobs and built characters; imported rigs pose through their clips.** Blob and
puppet poses are values on objects the user owns (dials, joint rotations), so a pose is a set of property changes
(keyed in Keyframe mode) and a mirror is a swap of left and right. Imported skinned rigs have no joint objects to key;
their library of poses is their clip list. Poses are stored on the character (`poseLibrary`), so they travel with it.

**R40 — Characters get an inverted-hull outline on top of the Look's lines; face decals are flat.** The hull (mesh
pushed out along its normals, back faces, Look line colour, width scaled by the character and the Look's line width)
gives the stable, thick silhouette the line pass can't promise on a moving character. Eyes, brows, mouth, cheeks and
the hover glow are drawn unlit, like paint on the head, and get no hull; the line pass still draws their inner lines.

**R41 — Blob measurements are generated from `trace.json` and checked in CI.** `Tools/gen-blob-measurements.py`
reproduces the head profile, face placements and body size from the trace with the same rules as the Blender build
(the numbers came out identical to the hand-copied ones), writes `BlobCharacter+Measurements.swift`, and CI fails if
the committed file drifts. A Swift build plugin would have needed Python inside the package build on every machine;
a checked generated file gives the same guarantee. The smirk strokes stay authored: they are a design simplification
drawn over the traced mouth, not a measurement.

**R42 — Built-in clips work on all three character types.** Built and imported characters retarget the humanoid
clips; a Blob, which has no skeleton, plays the same ten clips written for its dials (hand reach, head turn, jaw,
squash, lift, lean), on the same clip tracks with the same crossfades, added on top of keys and face performances.

**R43 — Fly is a flight model with a short ease, fed by the on-screen sticks or any game controller.** Velocity and
turn rates follow the sticks with a time constant (the sidebar's Ease), moves stay level with the ground and tilt
stops short of straight up, so a flown take reads as an operator's move. It writes the camera through the same path
as the Director view's touch gestures: one undo step per flight, or the camera's keys while Perform records. A on a
controller records or stops a take, B stops flying.

**R44 — The Kit: 355 CC0 assets in nine Sets, all in the app (27 MB).** `Tools/fetch-kit.py` downloads Kenney packs
from kenney.nl and Quaternius packs through itch.io's free-download flow (their official pages), refuses any pack
whose own licence file doesn't say CC0, and converts the curated assets (`Tools/kit/curation.json`) into
`.loweyasset` folders: a GLB scaled to metres from each pack's reference asset of known size, pivot at the base
centre, facing +Z, toon-ready (normal, roughness and occlusion maps dropped, colour maps at most 512 px: the toon
Looks don't use the rest, and the Quaternius props shrank from 300 MB to 4 MB), plus `asset.json` with the semantic
metadata (real size, front, the surfaces things can stand on, tags, set, category, rig, clips, source, licence).
Faceted and smooth variants aren't separate files: every Look picks its normals in the shader. Thumbnails are
rendered by the app in the Ink Look the first time a tile shows and then cached, so they always match the renderer.
The whole Kit fits the 150 MB budget with room to spare, so the Background Assets spike's fallback is taken: no
download path (Apple-hosted Background Assets can't be exercised from CI or a sideloaded build anyway). CI checks the
built Kit against the curation, its licences and the budget. Kit assets live in the library manifest at runtime
only (`kit.` ids, never written to `library.json`), so projects using them open anywhere the app is installed.

**R45 — The foley set is synthesised, not sampled.** Whoosh, pop, impact, click and swell are generated by LoweyCore
(seeded noise, filters and oscillators shaped to the move each one sells), written once per project as WAV clips on
the sound-effects track. They're ours, so CC0 by construction; identical on every device; and weigh nothing in the
app. Each has a hit time, so attaching one to a word puts the whoosh's peak (not its start) on the word.

**R46 — The relation solver came before the samples.** Phase 2 lists the samples (step 7) before Scene Script v3
(step 9), but samples built from the Kit should be placed the way the AI will place things: by relation, with the
Kit's surfaces and fronts. So `RelationSolver` and the v3 verbs (`place … relation`, `add … asset`, `scaleTo`,
`recolor`) landed first, and the samples are built with them. Left and right are as seen from the reference's front
(for something facing the camera, screen left and right). Things put `on` furniture face the way it faces. Every
relation grounds what it places and slides it off anything it would intersect; `on` looks for a free spot on the
surface, nearest its middle. v2 scripts upgrade on compile (aliases become verbs, v2's `place` becomes `add asset`).

**R47 — The shipped samples are new, built from the Kit; the 1.x samples stay as fixtures.** The Theater's Welcome
island (Ink, golden hour) and Enigma story (a desk at night in Ink, a room of computers in Comic on twos, a cave robot
in Sketch with one accent, and the narrated story cut on the voiceover's words) are Scene Script v3 built with the
Kit and the relation solver, so they show what the app and the AI actually make. A Core test builds them from the real
Kit and fails if anything floats or intersects. The primitive-built 1.x samples (`IslandSample`, `EnigmaSample` and
its opening and story) keep driving the engine, export and file-format tests, which check exact names and frames;
rewriting those around Kit models would test less, not more.

**R48 — Perception measures geometry in Core and colour from the render.** `observe` (ShotReport) and
`contact_sheet` are pure Swift in LoweyCore (`Perception/`), so every number is unit-tested on Linux against scenes
where the answer is known (a floating cube reports `grounded: false` and a 100 cm gap). Coverage and visible % come
from a small depth-tested CPU rasteriser (about 320 × 180) of the meshes the renderer drew (Core's own meshes, else
boxes, in tests): exact enough to say "the lamp is 26% visible", deterministic everywhere. Contrast (ΔL* in the
squinted value view), silhouette separation (each outline pixel against the pixel a short step out, past the ink
line and glow the Looks draw on the edge), palette and the light read come from the rendered pixels; without them
those rubric lines are `skipped`, never guessed. Intersections compare surfaces, not boxes (a chair tucked under a
desk isn't intersecting), and set pieces (floors, walls, terrain over 6 m or 40% of the frame) may overlap each other.
Things in the air on purpose carry `airborne` (`above` sets it; 3D words count as signs). Clutter counts copies of one
model once (nine desks read as one pattern). Kit models may be half to twice their real size before Scale fails.
Focus passes when the subject is the accent, the biggest, the brightest or the most contrasty thing in frame. Motion
is measured on screen with velocities over a 0.17 s window, so animation on twos or fours isn't read as stop-start;
anticipation isn't measured (it's in the critique module's checklist instead). The Engine adds the pictures: the
camera view with set-of-marks, top/front/side diagrams from an orthographic camera with the shot camera drawn on,
the value view, and the subject's silhouette from the ID buffer. Turning perception on the shipped samples found a
chair blocking the desk push-in, Hesham hiding the one lit screen, the cave camera inside a rock and a chest scaled to
a third of its size; all four were fixed.

**R49 — MCP v2 is sixteen tools over one `build`.** The laptop's `hmm-bridge mcp` exposes the sixteen tools of PROMPT
§12.2. Seven of them (`frame_shot`, `light`, `set_look`, `animate`, `camera_move`, `add_overlay`, `flipbook`) are
small, typed front doors that each send one Scene Script v3 batch to `POST /v2/build`, so every change, however it
arrives, is the same thing on the iPad: one Proposal with a preview thumbnail, one undo step, and a reply carrying an
`observe` of the result. That needed three new v3 verbs in Core — `frameShot` (the camera solver), `lighting` (six
recipes placed relative to the shot camera; re-lighting replaces the recipe's lamps) and `intent` (enter, exit,
emphasise, react, walk_to, look_at, talk, idle, resolved to presets, clips, expressions, lip sync, keys and a look-at
behaviour) — and `look` learned the Look itself and per-object Looks. A dry run returns a `proposal_id` that `commit`
proposes for real, recompiled against the scene as it is then. The v1 routes stay for 1.x laptops; the package is
`hmm-bridge` (its CLI is `hmm-bridge`, and `lowey-link` / `lowey-mcp` remain as aliases).
`schemas/scene-script.v3.schema.json` lists every verb with its fields, and a Core test fails if the compiler and the
schema disagree.

**R50 — The skill is rewritten around looking; its evals score what the app measures.** The 1.x skill is archived in
`skills/_legacy/lowey`. The new one follows PROMPT §12.3: a director loop in `SKILL.md` (read → beats → shot list →
build → observe → critique → fix, at most three rounds; animate → contact sheet → fix, at most two), short modules,
style notes with references and reasons, `lessons.md` seeded with the 1.x failures and the bugs perception found in
the 2.0 samples. `reference/tools.md` is generated from the MCP server's own schemas (`Tools/gen-skill-tools.py`, checked
in CI). `evals/run_evals.py` drives Claude through the same sixteen tools against a real app, one fresh scene per brief
(the bridge gained `POST /v2/scenes/new` for this, outside the sixteen), and scores each brief from `observe` and
`contact_sheet` rather than from the model's own account; a Ground or Scale fail fails a brief whatever its score.
Voiceover briefs get a silent clip and their words through a new `transcript` verb (known words and timings on a
voiceover — also how a laptop TTS can sync). The evals are not run in CI: it has no paired iPad, no simulator bridge
reachable from a model, and no API key. The harness's parsing, scoring and bookkeeping are tested; the runs are
Hesham's to do on his iPad.

**R51 — Localisation, accessibility, windows and restoration (2.0).** English, Italian and Arabic live in one String
Catalog in the app (`App/Resources/Localizable.xcstrings`, plus `InfoPlist.xcstrings` for the permission prompts).
`Tools/strings.py` finds the chrome strings in the code (literals given to SwiftUI and the hmm. components, toasts,
accessibility labels, and the titles enums return for display) and CI fails when one is missing or untranslated.
hmm-kit's components now look their titles up in the app's catalog (changed upstream, then synced), so passing a
String to `HmmPillButton` localises like a literal; toasts take a `String.LocalizationValue`. Interpolated strings are
keyed the way SwiftUI keys them (integers `%lld`, the rest `%@`); English plurals built with `?:` inside a string are
not in the catalog and stay English. Arabic mirrors the chrome; the timeline and the stage's overlays stay left to
right (time and frame space aren't text). Accessibility: every tap target is a button to VoiceOver, panels scroll
under large Dynamic Type and numbers scale too, animations go through the Reduce Motion-aware helpers, and Increase
Contrast gets opaque outlined chrome like Reduce Transparency. Windows: one window edits (a stage edits one project
at a time); another main window offers to take over or become a monitor, and the Monitor window (Actions ▸ Monitor,
⌥⌘N) shows the shot live through its camera as it exports — beside the editor in Stage Manager or on an external
display. The app reopens the project, scene, playhead, panel, Director view and timeline state it was left in.

**R52 — App Store readiness without a Mac.** The icon follows the studio rule: one glyph on the accent (a faceted,
ink-outlined cube on #FFB847), full bleed so the system's corners match the other apps, with a dark variant; it's
drawn by `Tools/make_icon.py`. App Store screenshots come from UI tests on CI's iPad 13" and largest-iPhone
simulators, with a launch flag that hides the UI-test overlays. The App Store variant is made by the TestFlight job
from the same project by switching three Info.plist values (bridge off, no background audio) rather than keeping a
second target. The TestFlight upload signs with an App Store Connect API key and is skipped, not failed, when the
secrets aren't set. 2.0 is paid upfront: the StoreKit configuration exists for testing later purchases and is empty.

## Maquette 0.1 — M1, foundation & feel

**D-87 — 3D-lowey becomes Maquette; code names stay.** Display name, bundle ids `studio.h.maquette` (+ `.widgets`,
`.uitests`), app group `group.studio.h` (entitlement on the app and the widget), projects `.maquette` and packs
`.maquettepack`, licence "All rights reserved", the GitHub repo renamed to `maquette`. The modules, the Xcode target
and the bridge's wire name stay `Lowey`/`lowey` (CONTEXT §10: code names may stay), and the manifest's `app` stays
`"lowey"` so 2.0 and Maquette read each other's packages. A new bundle id is a new app with its own sandbox, so
3D-lowey's `.lowey` and `.loweypack` files are still declared, listed and imported. Maquette's phase tags are two-part
(`v0.1` … `v0.8`, then `v1.0.0`) beside 3D-lowey's three-part history tags, and its releases are marked Latest
explicitly (by version alone, 3D-lowey v2.0.0 would stay Latest). *Rejected:* keeping `.lowey` (the Files app shows
the extension); renaming every module (churn with no user-visible gain).

**D-88 — The journal records history ops, not just commands.** A line is `perform` (command + coalescing key),
`endCoalescing`, `begin/end/cancelGroup`, `undo` or `redo`; replaying them through `CommandStack.replay` rebuilds the
document *and* the undo stack exactly, including merged gestures and named groups. One journal per scene
(`history/<scene-id>/`), because an edit session is one scene. *Rejected:* journaling forward commands only (undo and
redo after a relaunch couldn't be rebuilt); one journal per project (scenes are opened and edited one at a time).

**D-89 — Checkpoints store each undo step once, by reference.** A checkpoint writes the snapshot and a list of
`{file, offset, length}` refs into append-only `entries/<n>.jsonl`; steps already stored are reused, files nothing
points at are removed. Opening reads the newest 64 steps; older ones load when undo reaches them (16 left). Opening
50 000 commands with a 150-change tail takes 23 ms in CI's Linux container (the test allows 1.5 s; the device budget
is 500 ms). *Rejected:* writing the whole 500-step stack into every checkpoint (megabytes rewritten every 5 s);
rebuilding the stack by replaying every segment (50 000 lines decoded on open).

**D-90 — Group commit within 50 ms, on a serial queue.** `record` buffers ops and schedules one write; a checkpoint
takes the ops recorded before it at call time (a test caught the queue flushing later ops into the old segment, behind
the checkpoint's sequence number, which lost them on replay). Leaving the screen and closing flush and `fsync`.
*Rejected:* writing on the main thread per change (a drag is 120 changes a second); the 100 ms the CONTEXT allows
(a shorter window costs nothing).

**D-91 — `project.json` and the scene file are written at every checkpoint, from the checkpoint's own state.** They
stay the readable surface (`docs/PROJECT_FORMAT.md`). Opening merges: the journal owns this scene's changes;
`project.json` owns the scene list and the project name, and its project Look wins when this scene replayed nothing
and the file is newer (another scene changed it since). *Rejected:* the journal as the only truth (scripts, MCP
clients and 2.0 read the files); writing the files on every change (the old debounce, the bug this phase removes).

**D-92 — Journal ops migrate by document schema.** A segment's header carries the `LoweySchema` version its commands
were written in; `ProjectHistory.opMigrations` upgrades older lines, and a Core test fails when a schema bump has no op
migration. The first journals are schema 4.

**D-93 — Going back in the history scrubber is undo, with the future kept as a version.** "Go back here" saves the
current state as an automatic version, then undoes to the moment; redo still goes forward until the next change,
which starts the new branch. Restoring a version is one undo step (`replaceScene`, a new command). Automatic versions:
each time a scene opens and each hour of work, the newest 40 kept; named ones stay. *Rejected:* a branch tree to
navigate (a decision wall; the versions list already holds every abandoned future).

**D-94 — The hover point is drawn in the stage's editor pass.** Two spheres (a dark rim, a light centre) just past the
near plane on the ray through the tip, sized from the view's height so they're 2.5 pt at any distance; the brush ring
faces the camera and shows only while a size slider moves (under the tip, or mid-stage when the Pencil is away). The
setting rules every tool. Hover position is no longer observed state, so hovering doesn't re-run SwiftUI. *Rejected:*
the SwiftUI overlay (a frame late); a CPU-drawn overlay image (a texture upload per hover event).

**D-95 — Device tiers set three preview knobs.** `DeviceTier` (hmm-kit) is A for GPU family ≥ 7 with ≥ 7.5 GB (M iPads
and the 8 GB A17 Pro mini), B for family ≥ 7 or ≥ 4.5 GB, C below; `-device-tier B` forces one. `PreviewQuality`
gives the render-scale range (A 0.66–1, B 0.6–0.85, C 0.5–0.7) and the sun's shadow map (2048/1536/1024); the frame
budget comes from the screen (most iPads are 60 Hz, and holding them to 120 fps lowered their scale for nothing).
Exports, stills and thumbnails always use `.full`. Lines stay native on every tier (crisp edges are the Looks). MSAA
isn't a knob: pipeline states are built for the device's sample count. There's no simulation-rate knob yet: 2.0's
simulations bake to keys at the timeline's rate, so nothing simulates live (it arrives with dangle physics and
mechanisms). The "Tier B/C configuration" is the Engine suite rendering every Look with each tier's quality: simulators
all use the Mac's GPU, so a Tier B simulator would test nothing more. *Rejected:* a model-identifier table (breaks on
every new iPad).

**D-96 — The benchmark's pass rule follows the screen.** Frames are timed present to present, so a perfect run sits at
the screen's interval with vsync jitter around it: p95 ≤ 1.2 intervals (10 ms at 120 Hz, 20 ms at 60 Hz) means no
frame dropped. The minimum render scale is 55% up the tier's range (0.85 at A). A Tier B run is offered on A iPads.
*Rejected:* the 2.0 rule (p95 ≤ 8.3 ms): Hesham's iPad Air M3 is 60 Hz and could never pass it.

**D-97 — The load meter measures work, not intervals.** The stage redraws on demand, so the interval between frames
says nothing when idle; the meter takes max(GPU time, CPU encode time) against the budget, plus a scene cost
(triangles and draw calls against what the tier draws comfortably: first estimates, refined by the device
benchmarks). The chip shows after a second at 85% and leaves after a second under 70%. Its fixes are the ones that
exist: a lighter preview for the session, or Adaptive resolution when Full-resolution stage is on. *Rejected:*
"instance repeats" (the renderer already instances every run of one mesh) and "simplify" (no simplify operation until
modelling).

**D-98 — The M1 performance pass was a code read of the per-frame paths.** Fixed: smears scanned and copied every
object on every frame (now cached per edit and playhead; hovering redraws at 120 Hz with neither changing); the
stroke preview was uploaded to the GPU every frame (now once per shape); each frame allocated a `Task` to report its
time (now a main-queue hop). Signposts mark "Build frame" and "Encode frame" for Instruments. GPU time can only be
measured on the device: the benchmark JSON in the device checklist is the gate (CONTEXT §6).

**D-99 — CI runs once per change, routed by what it touches.** PRs and main only (a PR used to run twice: as a push
and as a PR). A `changes` job sends docs-only changes nowhere, Core-only changes to lint and Linux, Engine changes to
the render tests, and Features/App changes to feature tests, the app build and the UI tests; every merge to main runs
everything, so a tagged commit passed the UI tests. The app job no longer waits for the Engine job (it builds the same
sources itself). DerivedData is cached per job. `CI result` is the one required check (skipped jobs count as passed),
so auto-merge waits for it. The release workflow skips commits marked `[build-only]`. Timings: D-100.

**D-100 — CI wall time, measured.** Before (2.0's workflow): 46.0 min for a push to main, 45.8 min for a PR, and every
PR ran twice (push + PR). After, on this phase's PR with every job routed in (Core, kit, Engine, Features and App all
changed): **21.5 min**, once. The slowest job is now the Engine render tests (21 min); the app build and UI tests
finish in 12 min beside it instead of 28 min after it. A docs-only change runs only the routing job and `CI result`.

## Maquette 0.2 — M2, the canvas owns the screen

**D-101 — The making tools are Model, Draw, Paint, Animate and Cast.** Model holds what 2.0 called Build (shapes,
lights, cameras, words, marks on the frame, effects, screen effects, and now photos and videos), the Library (the
Kit and your models) and snapping, as three pages; the modelling tools of M3 join it. Draw keeps ink, solid shapes
and flipbooks. Paint has the Shadow Brush and Scatter, which already paint (on objects and over the ground); colour
painting joins them in M6. Animate has no panel: it calls the whole timeline (again: back to the transport). Cast is
unchanged. *Rejected:* the Library as a sixth button (CONTEXT allows five); Animate as a panel (it would repeat the
timeline's header); hiding Paint until M6 (it has real tools today, so it isn't empty).

**D-102 — One home per function, and time lives in the timeline.** The audit (docs/LAYOUT.md) found six controls in
two places: Actions ▸ Sound and Voiceover beside the timeline's Sound and words, Actions ▸ Timeline beside the
timeline menu's settings, Transform's Drop to the ground beside the inspector's, the palette's own Pick beside the
sidebar's, Build's "Open the library" beside the Library button. Each now has one home; sound and the timeline's
settings stay in the timeline, which the corner control calls in one tap. The menu bar and the keyboard are other
ways in, not other homes. *Rejected:* keeping Sound in Actions for discoverability (the tour now says time is called
from Animate and the corner control).

**D-103 — The timeline is on call: hidden, the slim transport, or whole.** A new project shows no timeline. The
corner control (bottom right, beside the views) calls the transport and sends the timeline away; Animate opens it
whole and, tapped again, folds it to the transport. The divider resizes it; dragged down past the transport it goes
away. Each project remembers which of the three it was and its height. *Rejected:* one global height (2.0's
`@AppStorage`): a character piece and an animation want different room.

**D-104 — How a project shows lives in `workspace.json`, beside `project.json`.** The timeline's presence and
height, snapping, the grid, the starter template and its first panel. It's view state, not the project, so it stays
out of the history journal and undo, is written 0.4 s after a change (and when the project closes), and falls back
to the defaults when missing, damaged or from the future. It travels with the package (copies, `.maquettepack`,
iCloud Drive). *Rejected:* a `project.json` field (every resize would be a command in the journal and an undo step);
`UserDefaults` keyed by project (it wouldn't follow the project to another device).

**D-105 — The inspector floats beside the selection.** hmm-kit's `HmmFloatingPlacement` keeps it on its side while
it fits, flips it at the screen's edge and, when neither side fits, covers as little as it can. The selection's
box is projected onto the stage at once when the selection changes, 0.12 s after edits to it pause and 0.15 s after
the camera stops moving, so a drag or an orbit doesn't re-run SwiftUI 120 times a second; the inspector glides over
when things come to rest. It stays
in the room the chrome leaves (below the clusters, clear of the sidebar, an open panel and the bottom row), docks to
the edge when the selection is off screen, and hides while a making tool's panel is open. *Rejected:* tracking every
frame (layout per frame for a panel nobody reads mid-orbit); a popover (it closes on the first touch of the stage).

**D-106 — Every panel resizes from a corner grip and remembers its size on the device.** hmm-kit's `hmmResizable`
(`HmmPanel(sizing:)` uses it): drag the grip, double-tap it for the original size; sizes live in `UserDefaults` per
panel. *Rejected:* sizes per project (they fit the person's screen and hands, not the project).

**D-107 — The joystick is on by default and can leave from its own ×.** Settings ▸ Stage brings it back and holds its
speed. *Rejected:* keeping its toggle in a tool panel (a preference isn't a tool).

**D-108 — Home's cards turn: a turntable rendered once, played a frame at a time.** When a project closes, its card
is drawn after the editor has gone (closing no longer waits): the still first, then 48 frames of the scene turning
once around everything in it, from the work view's height, in its Look (6 s a turn at 8 fps, 480 px wide), cached in
the package as a GIF. A card opens the GIF only while it's on screen and decodes just the frame it shows; it pauses
while the gallery scrolls and while a project is open; Reduce Motion keeps the still. Stills load off the main
thread into an 80-card cache. *Rejected:* rendering each card live with Metal (a GPU pass per card); keeping decoded
frames (25 MB a project, 2.5 GB at a hundred); looping HEVC with a player per card (a dozen hardware decoders).

**D-109 — A card grows into the stage with the system's zoom transition.** The open project is a full-screen cover
over Home with `navigationTransition(.zoom)` from the card's picture, so it grows out of the card and shrinks back
into it. Interactive dismissal is off: pinching and dragging belong to the stage, and the project closes from Home in
the corner. *Rejected:* a hand-built matched-geometry overlay (it re-lays out the Metal stage every frame of the
animation).

**D-110 — Stacks, search and sort are hmm-kit's `GalleryArrangement`, saved as `gallery.json` beside the projects.**
Cutaway's home will use the same. Drop a card on another to stack them; projects that disappear are pruned; search
looks through every project and stack by name; the sort (Recent, Name, Date created) is remembered. *Rejected:*
stacks as folders on disk (the project list, iCloud Drive and Files bookmarks all follow package locations).

**D-111 — Starter templates prepare the workspace and place nothing.** Blank, Model to print (Clay, studio light, a
1 cm grid, 5 cm shapes, close up, Model open), Room or building (a 25 cm grid, the view from above, Model open),
Character (Cast open, eye level, the transport showing), Animation (the timeline open). Each suggests a Look and a
Mood that New project lets you change. Sketch arrives with the Schizzo board; millimetres and the print-bed outline
with M3/M4's precision tools; the walls tool with M4. *Rejected:* listing Sketch now (a template promising a tool
that isn't there is a stub); templates that place objects (CONTEXT §4.2: an empty project).

**D-112 — LAYOUT.md is walked by the UI tests, and the gates are measured.** `Tools/layout_walk.py` turns each walkable
row into `AppUITests/LayoutWalk.swift` (CI fails when they disagree) and `LayoutTests` taps every row from a new
project. The idle stage's share is the window minus the frames of the clusters, the sidebar and the bottom-right
controls. The Home benchmark (Diagnostics) builds a hundred projects in a scratch folder as clones of one real project
(no extra space on APFS), scrolls the real gallery grid down and back for 20 s at one speed and records every
presented frame with the Night Market's pass rule; CI runs it on the simulator to prove it runs, and the device JSON
is the gate (CONTEXT §6). *Rejected:* a synthetic grid of placeholder cards (it wouldn't measure the cards people see).

**D-113 — Panel section titles are translated too.** `Tools/strings.py` didn't scan `PanelSection`, so 27 section
titles (Shapes, Light & camera, Palette…) showed in English in the Italian and Arabic builds; they're found and
translated now. In Arabic, Move is نقل: it read the same as Animate (تحريك), now beside it.

**D-114 — People see "Home", and the studio is studio h.** The Theater is called Home everywhere a person reads it
(code names stay); Settings ▸ About says "Made by studio h.".

## Maquette 0.3 — M3, modelling I

**D-115 — Booleans are Manifold, vendored, behind a C face (spike passed).** The spike built Manifold v3.5.4 with
SwiftPM and ran it from Swift in the Linux container, on the iPad simulator and as an `iphoneos` arm64 build, on CI
(a throwaway `spike/manifold-ios` branch, since deleted). It lives in `Packages/Manifold` as a C++17 target (single
thread, no TBB, no 2D cross sections so no Clipper2) with `ManifoldBridge.h`, a few C functions Swift imports as plain
C. LoweyCore depends on it and still builds and tests on Linux. *Rejected:* Swift's C++ interop (it must be switched
on in every module that imports the target, Core through App and the tests); a prebuilt XCFramework (the Linux tests
couldn't link it); the BSP fallback (not needed).

**D-116 — The editable mesh is polygons with holes; its topology is built when needed.** `EditableMesh` stores
vertices and faces (an outline, counter-clockwise from outside, then holes); `MeshTopology` builds half-edges from it
for each operation and is thrown away. Stored compactly (`{"v": […], "f": […]}`, coordinates to the nanometre).
Equality and hashing go by a fingerprint computed once per mesh, so the renderer's cache keys on a mesh every frame
without walking it. *Rejected:* storing half-edges (larger files, and states that can't be valid become storable);
triangles only (nothing to push or pull: a face is what you touch).

**D-117 — Clean results: faces rebuilt from triangles.** `MeshBuilder` merges neighbouring triangles on one plane into
one face (holes kept, loops that touch at a corner split), then removes corners on a straight run where exactly two
faces meet, from both or neither. A boolean's result isn't welded (Manifold keeps near-coincident corners apart on
purpose; welding them broke edges in a 1 000-case soak); renderer meshes are, with a neighbour-cell search so seam
copies on either side of a grid cell still join. Corners Manifold kept come back with their exact Double positions, so
typed sizes survive any number of booleans. Cuts start a hair above the face and, when they end exactly on a face of
the solid (cutting through), go a hair past it: exactly coplanar faces can leave a skin. *Rejected:* trusting
Manifold's own face ids for merging (two coplanar faces from different inputs must still merge).

**D-118 — Modelling is the commands that already exist.** Push/pull, pulls, cuts, booleans and drawing are
`setKind` / `insert` / `delete` / `setProperties` in one labelled `batch`, so undo, the journal, versions and the
bridge needed nothing new. The schema goes to 5 (no-op migrations for documents and journal ops) only so 0.2 and
3D-lowey 2.0 refuse 0.3 files with a clear message instead of failing on an unknown object type. *Rejected:* new
command cases (more surface for the same result); keeping schema 4 (older apps would misreport the files as damaged).

**D-119 — Push/pull slides when it can, sweeps when it must.** When every face around the picked one stands square to
it (a block's top, a pocket's floor), its corners move and its neighbours stretch: the faces stay and the typed number
is the new size exactly; it refuses to pass the opposite side. Otherwise the face's outline is swept into a prism and
added or cut with a boolean, which works on any face. A shape is made an editable mesh, with its scale baked into the
vertices so lengths are real, before its first face moves (its own undo step); objects with children keep their scale
and the distance is converted. *Rejected:* always sweeping (renumbers the faces and loses the pick on every drag
step).

**D-120 — While dragging, nothing is committed.** A sliding face shows its new shape through `kindOverride` (the stage
draws the overridden kind; the document is untouched) and a sweep shows the prism it will add or cut; release commits
one command. *Rejected:* coalesced commands per drag step (each journal line would hold the whole mesh: megabytes per
drag).

**D-121 — Sketches are objects, drawn by taps, and only on the stage.** A `sketch` object holds a world plane, its
curves and the object it was drawn on. The first tap picks the plane (the face under it, else the ground) and joins a
sketch already on that plane; then taps place points (a rectangle's corners, a circle's centre and edge, an arc's
start, end and bend, a line's corners until the first is tapped again, a spline's points until closed or Done), so a
finger, the Pencil and a UI test all draw the same. Closed curves, and open ones that meet end to end, fill into
regions; a loop inside another makes a hole and is a region of its own. Pulling or cutting a region uses its curves
up; the sketch goes when empty. Sketches are construction lines: the editor pass draws them, exports never do.
Curves that cross aren't split into regions yet (BACKLOG). *Rejected:* drag-to-draw (a finger drag orbits:
CONTEXT §4.1 "fingers navigate"); sketches as children of the object (moving the object would have to rewrite them).

**D-122 — Exact numbers float beside what they measure.** The pull distance, a rectangle's two sides, a circle's
diameter, a line's length and an offset are chips on the stage; tapping one opens an empty field with the current
value as its placeholder, so typing replaces it. Lengths are typed in the project's units with any unit on any number
and arithmetic (`25`, `25mm`, `2*12`, `1ft 6in`, `(40-6)/2`). Units are `workspace.json`'s (Model to print: mm, Room:
m, others cm), set in Model ▸ Snapping. Dragging snaps to other corners' heights along the axis within 10 points,
else to one unit when grid snapping is on; sketch points snap to one unit too (or the grid when it's finer). The
stage's camera comes in to 3 cm (its near plane follows it in), so double-tap frames a millimetre part; a shape tool
shows its hint once, when chosen, not a toast per tap. *Rejected:* a numeric keypad sheet (a decision wall between the drag and
the number).

**D-123 — The marks are drawn in the editor pass; the element under a tap is found on the CPU.** The ID buffer finds
the object; `MeshPicking` then raycasts its faces (and picks the nearest edge or corner of the hit face on screen),
because element ids don't fit in the ID buffer without a second, larger pass. Wireframe, picked faces / edges /
corners, sketch lines and regions, pull previews are `EditorOverlay` meshes (bars sized from the camera so they stay
about two points wide), depth-tested against the frame except corners and the shape being drawn. *Rejected:* a
per-element ID pass (GPU memory and a readback for something the CPU answers in microseconds at these mesh sizes).

**D-124 — Model ▸ Shape holds the modelling tools; the bar holds the rest.** The page has the sketch shapes, the pick
modes and the booleans (and Make editable when a shape is selected); choosing a shape or a mode closes the panel so the
stage is free, and the Model tool's bar at the bottom switches modes, finishes a line or spline, grows / shrinks /
selects similar, and ✕ leaves it. A Pencil loop picks elements; a finger drag still orbits, except on the picked face
or region, where it pushes or pulls. The inspector shows the selection's size and what's picked; it steps aside while a sketch shape is chosen (the
floating numbers are the controls then, and it would cover them beside a large selection). *Rejected:* a sixth
top-right button (CONTEXT allows five); a separate Select-elements tool in the top left (picking faces is modelling).

## Maquette 0.4 — M4, modelling II & interop

**D-125 — Bevel and round are swept cutters through the boolean path.** Each edge gets its profile (the corner
beyond a flat cut, or beyond a quarter arc) swept along it in the plane square to the edge; outside edges are cut
away, inside edges filled, then the result is rebuilt into whole faces like every boolean. Cuts run a hair past the
edge's ends (beyond is empty space); fills stop exactly at them. Where several bevelled edges meet, the cuts meet in a
point (no rolling-ball corner patch). Arcs are eight strips a quarter turn. *Rejected:* a topological bevel with
vertex blends (a large, fragile algorithm for the same everyday result); Manifold has no fillet operation.

**D-126 — New boolean corners land exactly on their planes; faces close over T-junctions.** Corners Manifold creates
where two shapes cross came back in Float, so a 2 mm bevel was 1.9999999 mm and coplanar pieces failed to merge into
one face. Each new corner pinned by three or more input planes is solved in Double (least squares, Cramer's rule),
unless it would land within the tolerance of another corner (Manifold keeps nearly coincident corners apart on
purpose). Where two neighbouring faces kept different corners of one straight edge, `MeshBuilder` puts the missing
corner into the other face's edge. The 1 000-case soak passes. *Rejected:* welding (it joined pieces Manifold keeps
apart: D-117); leaving Float (faces split into slivers after a few operations).

**D-127 — Live symmetry is "keep the touched side, mirror it".** Symmetry is a per-object property (`symmetry`:
x, y or z, the plane through the pivot); switching it on moves the pivot to the middle of the shape on that axis and
makes it symmetric (keeping the bigger side). After every Model edit the side the edit touched is kept (cut with a
half-space), mirrored and joined with a boolean, so push/pull, bevel, inset, shell and sketch pulls all stay
symmetric without knowing about it. A push/pull drag previews the face and its mirror image sliding together.
*Rejected:* a mirror modifier storing half the mesh (every reader of a mesh would need the evaluated one); mirroring
the pick only (breaks as soon as the two sides differ by a hair).

**D-128 — Shape operations run at once at a size that suits the units; the size floats to retype.** Bevel, round,
inset and shell happen on the tap (1 mm in millimetres, 5 mm in centimetres, 5 cm in metres; halved up to four times
when it doesn't fit); the size floats beside the pick like every number on the stage (D-122), and typing a new one
undoes the operation and does it again from the same pick. *Rejected:* a size dialog first (a decision wall,
CONTEXT §3.4); drag handles (no exact number, and a second gesture grammar on the stage).

**D-129 — Points snap by distance on screen: corners, edge middles, edges, faces, the grid.** Within 12 points of the
finger or Pencil, in that order; corners hidden behind the surface under the finger don't count; of corners on top of
each other on screen the nearest the eye wins. Sketching, measuring, walls and floors share it; the stage marks a
corner, middle or edge snap. Snap settings gain the three switches and read older settings without losing them.
*Rejected:* a radius in metres (too much at a distance, nothing up close).

**D-130 — Kept dimensions are objects.** A `dimension` object (two points in its own space) sits under the object it
measured, so it moves with it, and is drawn on the stage only, like sketches. Schema 6 makes older apps refuse files
that have one (the D-118 precedent). *Rejected:* annotations in `workspace.json` (they'd stay behind when the object
moves, and undo wouldn't know them).

**D-131 — The section view is a hardware clip distance, and cut solids show flat inside.** The plane lives in
`workspace.json` and reaches the renderer through the stage's editor scene only, so exports and thumbnails are never
cut. The surface vertex stages emit `SurfaceOut` (the varyings plus `[[clip_distance]]`); the fragment stages read
`SurfaceVaryings`, a subset. With the cut on, back faces (the inside of a cut solid) shade flat in the object's colour
darkened, which reads as a solid section. *Rejected:* true caps with a stencil pass (another pass and pipeline states
for a preview aid); discarding in the fragment shader (it costs early depth testing on every frame, cut or not).

**D-132 — Print files are millimetres with Z up; the check is topology, Manifold and rays.** STL and 3MF turn the
scene a quarter turn about X (Y up → Z up, winding kept) and scale metres to millimetres, so a part stands on the bed
in any slicer. The check: every edge walked once each way by two faces, consistent winding, positive volume, Manifold
accepts it; walls by a ray straight in from each face's middle and its triangles' middles (thinner than 0.8 mm for
filament or 0.5 mm for resin is flagged); the bed by its build volume. Repair welds near corners, drops slivers and
doubled faces, turns faces to agree and point out, and closes holes with a fan. *Rejected:* exporting Y-up metres
(parts lie on their side, a thousand times too small).

**D-133 — FBX isn't offered (spike).** Autodesk's FBX SDK licence lets an app ship the runtime but forbids
redistributing or repackaging the SDK without written permission; open-source projects must link to Autodesk's site
for users to install it themselves. Maquette's repository is public until launch and its CI would have to fetch the
SDK from behind a click-through licence, so it can't be built in. glTF reaches the same apps (Blender, Unity, Unreal
import it natively). *Rejected:* vendoring the SDK; downloading it in CI; a home-made FBX writer (an undocumented,
versioned binary format to keep up with).

**D-134 — glTF keeps the scene as built, and comes back editable.** The export is one node per object with its own
transform under its parent, a material per surface, cameras, lights (KHR_lights_punctual) and the timeline's
position, rotation and size keys (linear and held keys as they are; eased ones sampled at the frame rate). Reading a
glTF scene gives groups and editable meshes with the same hierarchy, materials (read straight from the JSON so dark
colours don't lose precision to 8-bit steps), cameras, lights and keys, up to 200 000 triangles. Library imports stay
library models; **Make editable** takes a placed one apart into a group with the model's id (its keys still point at
it). *Rejected:* the 2.0 flat world-space export (no hierarchy, no animation); taking every import apart (a
100 000-triangle prop in the journal on every placement).

**D-135 — "Render on your computer" is a Blender package built by a script it carries.** A zip of `scene.glb`,
`maquette.json` (the Look, sun, sky, ground, camera cuts and render settings) and `setup_maquette.py`, which imports
the glTF (fps set first, so keys land on frames), turns toon Looks into Shader-to-RGB ramps and Ink outlines into
Freestyle, adds the sun and the sky, binds camera cuts to markers and saves a .blend. CI renders a frame with it in
Blender 4.2 LTS and 5.2 LTS. *Rejected:* writing .blend files (undocumented); USD (Blender reads it, but loses the
Look); shipping the script separately (it must match the app that wrote the package).

**D-136 — Walls are one solid from their centre line; openings are booleans.** The tapped corners are a centre line;
both sides are offset by half the thickness with mitred corners (capped at four times the thickness), and the
outline swept up the height: one closed solid, a ring for a closed room. Doors and windows cut a block square to the
wall through its measured thickness. Floors are slabs under an outline (their top where it was drawn); stairs are a
side profile swept across the width. Everything stays an editable mesh. *Rejected:* one object per wall segment
(corners that don't meet); parametric walls (a second modelling system before 1.0).

**D-137 — Zip entries are inflated in pure Swift.** 3MF files from slicers are deflated zips; Core must build and
test on Linux, where Apple's Compression framework doesn't exist, so a small RFC 1951 decoder (stored, fixed and
dynamic Huffman blocks) sits in Core. *Rejected:* zlib through a system module (another C dependency for every
platform); refusing deflated files (every 3MF from another app).

**D-138 — Homes for modelling II (LAYOUT.md).** What the pick can do (bevel, round, inset, shell) is in the Model
tool's bar, beside grow and shrink; mirror, symmetry and the 3D-print check are in Model ▸ Shape; snapping, units,
measuring, kept dimensions and the section view are Model ▸ **Precision** (was Snapping: M2 said measuring would join
it); walls, floors, doors, windows and stairs are Model ▸ Add ▸ Building; array along a sketch is in the inspector's
Array; the formats are a picker on Export's 3D model. No new button anywhere in the frozen layout. *Rejected:* a sixth
making tool for building (the ≤ 5 rule); a separate Print panel (printing is shaping).

## Maquette 0.5 — M5, brushes & drawing guides

**D-139 — One brush engine: Core plans the stamps, one Metal pipeline draws them.** A brush is a tip and a grain
stamped along the stroke (Procreate's model). `BrushStroker` (Core, pure Swift, Linux-tested) turns Pencil samples
into a stored path (streamline, pressure/tilt/speed dynamics) and a path into seeded stamps (spacing, jitter, scatter,
count, tapers, fall-off, flow). One instanced-quad pipeline (`Brush.metal`) samples the tip and the grain for every
target: billboards in the scene's shading pass for ink, a layer texture per blend mode for flipbooks, the stage's editor
layer for the stroke under the Pencil, Brush Studio's pad and the library's previews. *Rejected:* a ribbon mesh with a
brush shader (no stamps, so no scatter, rotation or count); Core Graphics for 2D (a second engine, CPU-bound); an
engine per target.

**D-140 — A stroke keeps its path, a brush key and a seed; a project freezes the brushes it uses.** Strokes store the
smoothed path with each point's radius and opacity (the dynamics already applied), the project brush's key and the
jitter seed, so a stroke draws the same in every frame and export, and erasing still splits it anywhere. The first
stroke with a brush adds a frozen copy to `ProjectInfo.brushes` under a content key (`BrushKey`: a hash of its
settings) with the new `setBrushes` command, in the same undo step; its pictures are copied into `assets/brushes/`.
Editing a brush in the library makes a new key, so old strokes keep the old brush (Procreate's behaviour: what you drew
stays drawn). Schema 7, with no-op migrations. Old strokes have no brush and draw with Ink Pen. *Rejected:* storing the
stamps (megabytes per drawing); strokes pointing at library brushes (an edit would redraw finished work, and the
project wouldn't open the same on another iPad); storing raw samples (dynamics would re-run on every frame).

**D-141 — Procreate and Photoshop import, checked against real files (spike passed).** The spike read four real
Procreate `.brush` files and two real `.brushset`s made from them (public GitHub repositories), and two real Photoshop
`.abr` files (18 and 13 sampled tips, from a file-format research collection), in Swift on Linux. Findings: a `.brush`
is a zip of `Brush.archive` (an `NSKeyedArchiver` binary plist of a `SilicaBrush`, 196 settings) with `Shape.png` and
`Grain.png` when the brush has its own pictures, else `bundledShapePath`/`bundledGrainPath` naming Procreate's own; a
`.brushset` is `brushset.plist` (name, brush folders) and a folder per brush. ABR 6 has `8BIM` sections: `samp` (tips:
an id, 10 bytes of header in 6.1 or 264 in 6.2, bounds, depth, raw or PackBits rows) and `desc` (names, spacing,
`sampledData` ids). Read with a pure-Swift binary plist reader (`BinaryPlist`, `KeyedArchive`) and the existing zip
reader. Mapping (Procreate → Maquette): plotSpacing s → spacing 0.02 + 1.98 s²; plotSmoothing / moving average →
streamline; plotJitter → jitter × 2; dynamicsFalloff → fall-off; pencil taper lengths × 0.4 → tapers, taper size and
opacity as they are; shapeRoundness; shapeRotation × 180°; oriented → turns with the stroke; shapeScatter → rotation
jitter; shapeCount → 1 + 15 c; flip jitters; inverted; textureScale → grain scale 0.05 + 2 t; grainDepth;
textureMovement ≥ 0.5 → rolling, else texturized; pressure size and opacity, the pressure size curve, tilt size and
opacity, speed size and opacity, size and opacity jitter; glazed flow → flow; wet edges. Not mapped (no counterpart
yet): colour dynamics, smudge and erase settings, dual brush, wet mix, bleed, height/metallic/roughness. Bundled
pictures become the nearest built-in by name (Hard/Point → hard round, Soft/Air → soft round, Pencil, Chalk / Charcoal /
Grit, Bristle / Acrylic / Oil, Splat / Spray, Flat; grains Canvas, Charcoal, Paper, else Noise). Photoshop: sampled
tips (grey, box-filtered to 512 px) with their names and spacing; computed brushes and Photoshop's dynamics are left
out. Fixtures are made from scratch in those formats by `Tools/make_brush_fixtures.py` (the repository is public:
nobody's brushes are committed). *Rejected:* Foundation's unarchiver (Procreate's classes don't exist, and Linux has no
keyed-archive UIDs); committing the real files (their licences don't allow it).

**D-142 — Stamps add up to the stroke's opacity.** About 1 / spacing stamps cover any point, so a half-opacity stroke
of plain stamps would pile up nearly solid. Each stamp's opacity is 1 − (1 − a)^spacing, so they add up to a; flow then
multiplies every stamp, so low flow still builds where the Pencil goes over the same place (Procreate's opacity and
flow). *Rejected:* drawing each stroke into its own layer with max blending (a render pass per stroke, every frame).

**D-143 — Ink shows its stamps; its ribbon stays for picking, shadows and export.** In the scene, each stroke's stamps
are camera-facing billboards in the stroke's space (the drawing's matrix moves them), drawn at the end of the shading
pass, depth-tested without writing depth. The camera-facing ribbon from 2.0 still draws into the prepass (the ID buffer
picks it, the selection outline follows it), casts the shadow and is what glTF, USDZ and the Blender package export;
onion-skin ghosts draw it tinted. Stamp buffers are cached per path, brush and seed. *Rejected:* every stamp in the ID
buffer (an alpha-tested prepass of thousands of quads for a pick); exporting stamps (no 3D file format carries them).

**D-144 — Flipbooks are stamped into a layer per blend mode.** The renderer stamps each blend mode's drawings into a
layer at the output size; the composite blends multiply, screen and add over the shot, then lays the normal layer under
the overlays and captions (where 2.0 drew normal flipbooks, inside the overlay image beneath the titles). A see-through
track paints into a scratch layer and is laid down at its opacity, so its own strokes don't darken where they cross.
Filled shapes (drawn effects) stay flat triangles with a rim of stamps; drawn effects' lines now draw with Ink Pen
(soft tapered ends). *Rejected:* keeping Core Graphics for flipbooks (two engines; the stage repainted them on the CPU).

**D-145 — The stroke under the Pencil is the stroke that's kept.** While drawing, the stage stamps the same path with
the same brush and the seed chosen at touch-down, in its editor layer, with UIKit's predicted touches appended (never
kept); a symmetry guide's copies show live too. Ink stamps are depth-tested in the world, flipbook stamps lie on the
screen. *Rejected:* the flat preview mesh and the SwiftUI path (a frame behind, and not what lands).

**D-146 — Latency is measured from the touch to the GPU finishing the frame, plus one refresh.** Each live stroke
sample's touch timestamp is compared with the moment its frame's command buffer completes, plus one refresh of the
screen (the frame appears at the next one): an upper bound, because this SDK (Xcode 27) gives a drawable no presented
time. A signpost marks each measured sample; Diagnostics ▸ Apple Pencil shows the median and 95th percentile, and every
tenth stroke writes them to the log. The device checklist records the numbers. *Rejected:* the drawable's presented
handler and presented time (unavailable to Swift in this SDK).

**D-147 — The built-in brushes are drawn by code.** Tips (hard and soft round, pencil, chalk, bristles, flat,
splatter) and grains (paper, canvas, noise, charcoal) are generated by `BrushImages` (value noise that tiles): no
bitmap of anyone else's ships, and every device draws the same bytes. Ten brushes in three sets (Inking, Sketching,
Painting); Ink Pen is the default for ink and flipbooks and draws 2.0's line. *Rejected:* bundling PNG tips (made or
licensed: more to ship and to keep consistent).

**D-148 — The brush library lives on the iPad; sets travel as files.** `Brushes/brushes.json` (a versioned envelope)
beside content-keyed PNGs, next to the model library. Built-in brushes can be edited and reset; imported brushes reset
to how they arrived; made and imported ones can be deleted; sets are made, renamed, deleted and shared as a
`.maquettebrushes` file (a zip of the set and its pictures). Procreate and Adobe publish no type identifiers, so
`.brushset`, `.brush` and `.abr` are declared by extension under Maquette's own imported types; they open from Files,
AirDrop and Import. *Rejected:* the library in iCloud (it follows the projects' storage when that arrives for both);
sharing as `.brushset` (Procreate's archive can't hold Maquette's settings).

**D-149 — Drawing guides: every kind on the frame, grid/isometric/symmetry on the guide plane.** Flipbooks get a 2D
grid, isometric, 1-, 2- and 3-point perspective and symmetry (vertical, horizontal, quadrant, radial with optional
mirror) over the frame; ink drawn on a guide plane gets the grid, isometric and symmetry laid on the plane (the stage is
already in real perspective, so vanishing points would only fight it). Drawing Assist straightens a stroke along the
guide direction nearest the way it was drawn (from where it began to its farthest point); symmetry copies are kept with
the stroke as one undo step. Both guides are how the project shows, so they live in `workspace.json`, outside undo.
Perspective is set by its horizon, how far apart the points are and where the third one sits. Solid shapes keep their
own Mirror. *Rejected:* dragging vanishing points on the stage (a second gesture grammar while the Pencil draws);
symmetry for solid shapes (Mirror already does it).

**D-150 — Homes for brushes and guides (LAYOUT.md).** The brush a tool holds is a row at the top of Draw ▸ Ink and
Draw ▸ Flipbook; tapping it opens the brush library sheet, and Brush Studio opens from a brush's menu inside it. The
drawing guides are a section of the same pages. Diagnostics gains Apple Pencil. No new button anywhere in the frozen
layout; Paint (M6) opens the same sheet for its own tool. *Rejected:* a brush button in the sidebar (the sidebar holds
the two context sliders and undo); a Brushes item in Actions (brushes belong to the tool that draws).

**D-151 — The load chip is off by default.** Device note after 0.5: the "close to what this iPad keeps smooth" chip
kept appearing while working and read as nagging, not help. Settings ▸ Stage gains *Smoothness warnings* (off); the
load meter still measures and dynamic scale still lowers the preview, so nothing about smoothness itself changes, and
the benchmark and the Performance HUD stay in Diagnostics. *Rejected:* removing the meter (it still feeds dynamic scale
and the benchmark); raising its thresholds (they're uncalibrated until the device JSONs arrive, D-97).

**D-152 — A paint stroke is projected from the camera through the frame's own ID buffer.** The brush engine stamps the
stroke on the screen exactly as a flipbook stroke (D-144), then a pass draws the object's paint mesh flat in its
texture (each vertex at its uv) and every texel looks itself up on the screen: it takes the stroke's colour only where
the frame's ID buffer shows this object and its depth is the surface seen there, faded on grazing faces. It runs in the
frame that shows it, after the prepass and before shading, so the paint appears with no frame of delay and never lands
behind something or round the back. The same pass projects a picture (D-159) and, with another blend state, erases.
*Rejected:* dabs as 3D spheres around the surface point (no tip shapes or grain, and they paint through thin parts);
painting the screen image onto the texture only when the stroke ends (nothing to see while painting).

**D-153 — Paint is stored as content-named tiles; a stroke is one `paintTiles` command.** A layer is 256-pixel tiles,
each a PNG under `assets/paint/` named by a hash of its bytes; the document holds only names. When a stroke ends, its
layer is read back with the layer as it was before it, the tiles that differ are encoded (ImageIO), written, and one
`paintTiles` command swaps their names, so the journal line is a few hundred bytes and undo is a name swap. The GPU
adopts the tiles it already holds (nothing is decoded again); undo loads only the tiles that changed back. Strokes
commit strictly in the order they were painted. Layer edits (add, delete, move, opacity, blend, name) are one
`setPaint`. Schema 8. *Rejected:* recording strokes and replaying them (replay costs grow with every stroke, and GPU
results aren't a stable file format); one PNG per layer per stroke (megabytes per stroke in the history); tiles inside
`project.json`.

**D-154 — xatlas, vendored with a C face; the unwrap is stored in the project.** xatlas (MIT, `Packages/XAtlas`) lays
a mesh flat into one square atlas with padded charts, single-threaded so the same mesh unwraps the same way. Like
Manifold (D-115) it's C++ behind a small C header, so no Swift module needs C++ interop and Linux CI tests it. The
result is a small binary `.uv` file (source vertex, position and uv per unwrap vertex, then the triangles) the paint
names, so paint never moves even if xatlas changes. A primitive is unwrapped at its stretch (a 4 m box gets four
times the pixels along its length). *Rejected:* unwrapping when a project opens (an xatlas update would scramble old
paint); Swift C++ interop (D-115's reasons).

**D-155 — Models keep their own uvs when they're clean; their colours become the first layer.** A placed model's parts
are painted as one surface. Its own uvs are kept when every one lies in 0…1 and no two triangles cover the same
pixels (checked on a 256 grid); otherwise (the Kit's shared colour maps, most of all) it's unwrapped. Either way its
colours (material colour times its texture) are baked into a first layer, "Model", with "Layer 1" above for the paint,
so erasing reveals the model as it was. *Rejected:* painting over each part's own texture through its own uvs (the
Kit's parts share one small palette texture: painting one place would paint every place that uses that colour); a
second uv channel in the vertex format (every pipeline changes for one feature).

**D-156 — Paint lies over the object's colour.** The composite is straight alpha: where nothing is painted the object's
own colour (and Look, glow, Shadow Brush) shows, so changing its colour still works under unpainted areas. Layers
composite in the stored sRGB values with the W3C formulas (Procreate's), on the GPU for the stage and on the CPU for
exports with the same maths. The composite is pushed four texels past every chart's edge so filtering never reaches
an empty texel (no seams). Exports flatten the paint over the object's colour into an opaque texture. *Rejected:*
multiplying the texture over the colour (paint could never be lighter than the object); dilating every layer (the
dilation would be stored and grow with edits).

**D-157 — When the shape changes under paint, the paint follows it.** The paint names the fingerprint of the mesh it
was made for. When the object is modelled (or bevelled) afterwards, the stage carries every layer onto a fresh unwrap
of the new shape by position (each texel takes the closest point of the old surface within 3 % of the object's size),
off the main thread, and draws that; exports do the same at once. The document doesn't change until you paint on it
again: the first stroke stores the carried paint as one step ("Carry paint"), then you paint. Undoing the modelling
brings the original paint back untouched. *Rejected:* clearing paint when the shape changes (law 5); carrying it inside
the modelling command (every modelling path would need to know about paint).

**D-158 — Homes for painting (LAYOUT.md).** Paint ▸ Colour is the Paint panel's first tool, beside the Shadow Brush and
Scatter: the mode (Paint, Erase, Fill, Eyedropper), the brush row (the same library sheet, its own held brush), the
palette and any colour, the object being painted, its layers and a picture to project. The sidebar's sliders are the
brush's size and opacity; the options bar under the stage repeats the mode and names the layer. A stroke paints the
object it starts on (a first stroke on an unpainted object gets it ready instead, as "Paint <name>" does). Fingers
navigate, the Pencil paints. *Rejected:* a Layers button in the corner clusters (the layout freezes at 1.0 and layers
belong to the tool); one stroke painting every object it crosses (layers are per object: which one would it be on?).

**D-159 — Projection painting is a picture placed over the stage.** Choose a picture (Photos or Files), place it with
the fingers over the model (it's see-through), then Project: it goes through D-152's pass into the current layer, at
the sidebar's opacity, landing on what the camera sees. *Rejected:* projecting the stage's rendered image (that bakes
lighting into paint); a stencil fixed to the camera while you orbit (a second gesture grammar on the stage).

**D-160 — Fill fills the layer; the eyedropper takes the paint's colour.** Fill sets every tile of the current layer to
the colour (one file for all of them): what isn't seen on the model is never drawn, so the whole layer is the honest
"fill this object". The eyedropper takes the composited paint under the touch, else the object's colour, and makes it
the current colour. *Rejected:* flood fill by colour (regions cross chart seams, so a fill would stop at invisible
edges); picking the lit colour from the screen (light and shadow would end up in the paint).

**D-161 — The painting benchmark is the performance gate.** Diagnostics ▸ Run the painting benchmark: a generated
sphere of 50 880 triangles, placed as a model and laid flat, is painted by a scripted Pencil for 20 seconds (a new
stroke every 1.5 s, the whole stroke re-stamped and projected each frame, the object composited each frame) against
the Night Market's pass rule. It writes `benchmark-paint-<device>-<version>.json`. CI runs it offscreen for 24 frames
to prove it works; the device run is the gate (CONTEXT §6). *Rejected:* timing a painting UI test on the simulator
(its GPU says nothing about an iPad's).

**D-162 — Characters are painted once M7's skeletons arrive.** A model whose parts move with a skeleton isn't offered
for painting, with a sentence saying why. *Rejected:* painting skinned models in their rest pose (the projection must
see the posed surface, and M7 rebuilds skinning for every character type).

**D-163 — Painted objects export their texture.** glTF (and the Blender package) and USDZ carry the paint mesh with the
flattened texture (`baseColorTexture`; a `UsdUVTexture` with v flipped for USD); OBJ writes `vt`, `map_Kd` and the PNG
beside it. STL and 3MF keep the closed shape (a printer takes the geometry). The Blender script's toon material keeps a
painted image: the ramp shades in grey and multiplies it. CI validates the painted glTF with the Khronos validator and
renders it, and a Blender package of it, in Blender 4.2 and 5.2, checking the paint's colour. *Rejected:* textures
only in glTF (USDZ is what Quick Look and architects' clients open).

## Maquette 0.7 — M7, rigging

**D-164 — One skeleton system: one door, three bodies.** `CharacterRig` gives every character the same skeleton
(joints, parents, rest pose, a standard and its bone map), its current local pose and the property changes that turn its
joints. A built Puppet's joints are its part objects (their `rotation`), a drawn rig's and an imported Rigged model's are
`bone.<joint>` turns on the character, a Blob's are its two mitten hands (its reach dials; its rubber-hose arms follow).
Dragging joints, IK, the pose library and clips go through that door, so a feature written once works on every kind.
Bone turns are ordinary properties: keyed by the timeline, coalesced while dragging, one line in the journal. A turn
overrides the clip for that joint. *Rejected:* converting Puppets to bones (their parts are rigid pieces made by the
builder, and 2.0 projects store their poses on the parts); one property holding the whole pose (it couldn't be keyed a
joint at a time, and a drag would rewrite every joint's history).

**D-165 — A drawn skeleton lives on the object; solid weights in a file, drawings' inline.** `SceneObject.rig`
(`ObjectRig`): the joints in the rig's space (the vertices the renderer draws: the object's space, bevelled shapes at
their size), each joint a point with no turn of its own, the standard, the leaf tips, and the weights. A solid's
weights (four joints a vertex) are a `.skin` file named by its content under `assets/rigs/`, so `setRig` is a few
hundred bytes in the journal however big the model is; a drawing's few hundred points keep theirs inline. The surface's
fingerprint is kept with them, so a reshaped object offers "Fit the weights to the new shape". Schema 9, with no-op
migrations. *Rejected:* weights inside `project.json` (megabytes per command); a separate skeleton object beside the
model (duplicate, delete, group and the library would have to keep the pair together).

**D-166 — Draw a bone: down the middle of what the stroke crosses.** Each Pencil sample's ray enters the surface and
leaves it again; the midpoint is the limb's middle there (a drawing's samples land on its plane). The centreline is
smoothed and cut into 2–8 bones by its length against the part's thickness. The end nearer the existing bones (or, on a
first chain, the rest of the body) is the base; a first chain gets a `root` joint in the middle of the body that isn't
the limb, so the body holds still while the limb bends; later chains hang from the bone they start on. *Rejected:*
bones on the surface where the Pencil touched (a limb would bend around its skin, not its middle); a fixed number of
bones (a tail and a finger need different counts).

**D-167 — Weights by bone heat.** Baran & Popović (2007): each bone heats the vertices for which it is the nearest
bone that can be seen (a BVH answers "can it be seen"), the heat diffuses over the surface (cotangent Laplacian, vertices
at the same place welded so seams don't block it), and each joint's weights are one preconditioned conjugate-gradient
solve; the four heaviest are kept. Weights fall off smoothly across a joint, and parts that only touch (an arm against
the body, a tail beside a leg) don't drag each other, because heat doesn't cross what can't be seen. It runs off the
main thread (seconds on a big model) and is pure Swift in Core, tested on Linux: a drawn tail on an imported model
bends as a smooth curve, keeps its thickness, and matches a recorded golden pose. *Rejected:* weights by distance to the
nearest bone (a tail drags the leg beside it); voxel/geodesic binding (needs a closed solid, which models from other
apps often aren't).

**D-168 — Rig as a person by eight taps (spike failed; fallback taken).** The spike rendered five Kit humanoids from
the front on CI's iPad simulator and asked Vision's body-pose model (`VNDetectHumanBodyPoseRequest`) for their joints:
the request can't be set up there (Vision error 9), on the simulator's GPU or forced to its CPU, so whether it finds the
joints of a stylised 3D model can't be checked before shipping it. The fallback ships: the stage turns to the model's
front and the person taps the top of the head, the chin, a shoulder, an elbow, a wrist, a hip, a knee and an ankle (the
other side is mirrored across the model's middle); any dot can be dragged; Rig. Each dot's ray finds the middle of the
limb it crosses; spine, chest and neck are spaced between hips and shoulders; feet get toes; head, hands and toes get
tips. The skeleton follows the humanoid standard, and its arms are turned out to a T-pose for retargeting exactly as
built Puppets' are (`TPose`), so every built-in and humanoid library clip plays on it: the Kit astronaut walks with the
built-in Walk, its feet taking turns in front (Core check and a golden image). *Rejected:* shipping Vision unchecked
(law 8, and the spike rule); a template pose snapped to the model's bounds (people aren't the same proportions).

**D-169 — 2D drawn puppets bend their strokes.** A drawing's weights are bone heat over its stroke points, chained
along each stroke and to the nearest point of every stroke it touches (so a drawn figure holds together). The animator
moves the points (linear blend skinning, on the CPU), so the brush engine stamps the bent strokes and picking, onion
skins and every export see the bent drawing; solid drawings (tubes, extrusions) bend the same way through their
strokes. *Rejected:* GPU-skinning the ink ribbon (the brush stamps are made from the path, not the ribbon); a separate
2D puppet object type (a drawing on a plane in the scene already is one).

**D-170 — Pose by dragging, IK by default.** Every joint of a drawn or imported skeleton is a handle: dragging it bends
the chain from where that chain begins (the joint hanging from the root or a fork) to it, by FABRIK on the joints'
positions, then each joint turned to point where its child went. A humanoid's handles are its hands, feet and head; a
straight limb bends toward its pole (elbows back, knees forward). The joints show for drawn rigs and rigged models in
every timeline mode (dragging them is the only way to pose them); Puppets and Blobs keep 2.0's rule (Keyframe and
Perform, so a drag in Compose still moves the character). *Rejected:* analytic two-bone IK for every chain (it can't
bend a tail of eight bones); CCD (it turns the joints nearest the end most, so a dragged tail hooks at its tip).

**D-171 — While rigging or painting, a rigged object stands as it was made.** With the Rig tool on, or Paint ▸ Colour
working on a rigged object, the stage shows it without its turned joints and clips: bones, weights and paint land on
the surface as it was made, which is where they're stored. Painting projects onto the rest surface (D-152), so painting
a posed object would put the paint where it was, not where it's seen. Imported skinned models still aren't painted
(their parts move with their own skeleton; D-162 stands for them). *Rejected:* a skinned projection pass (a second
vertex path through every paint pipeline, for a case the rest pose answers).

**D-172 — Weights are painted with the brush engine and shown by a twin mesh.** Paint weights strokes with the
airbrush through `BrushStroker` (spacing, pressure); each dab finds the surface under it and adds the chosen bone's
weight within its radius (Erase takes it away and hands it to the vertex's other bones in proportion); a stroke is one
`setRig` with a new file. While painting, the object is drawn by a twin of its skinned mesh whose uvs hold that bone's
weight, textured with a blue-to-red ramp and unlit: no shader or vertex format changes. *Rejected:* a weight colour
attribute in the vertex format (every pipeline changes for one view); updating the file on every dab (weights are
re-encoded once a stroke).

**D-173 — Exports carry the pose.** A rigged object leaves as it is posed: glTF and the Blender package (the scene as
edited) with its joints as turned by hand, USDZ, OBJ, STL and 3MF (the scene as shown) as posed at the playhead, so a
posed character can be printed. A painted rigged object's paint lies on the bent surface. Skinning is done on the CPU
by the same `Skinning` the drawings use. *Rejected for now:* writing the skeleton into glTF as a skin with its keys
(an armature in Blender: BACKLOG), because bevelled shapes and scaled objects need their rig space carried over
exactly.

**D-174 — Homes for rigging (LAYOUT.md).** Rigging is making a character, so it lives in Cast: a Rig section (Draw a
bone, Rig as a person; once rigged, Paint weights, Fit the weights, Reset the pose, Remove the rig). Drawing bones,
painting weights and placing a person's dots use a Rig tool on the stage with its options bar under the stage and the
sidebar's sliders (size and strength) while painting weights, like Paint ▸ Colour. Joints are dragged on the stage with
the Select tool. A rigged object joins the cast as a "Drawn rig". No new button in the clusters. *Rejected:* a sixth
making tool (the ≤ 5 rule); rigging inside Model (Model makes shapes; a skeleton is what turns one into a character).

**D-175 — The thirty-second block is timed on CI against 45 seconds.** The M3 acceptance ("a 40 × 20 × 10 mm block
with a 6 mm hole in under 30 s of taps") is about a person on an iPad. On CI's shared simulator every XCUITest tap
costs the runner a second or more, and the same taps took 32–38 s on the M5, M6 and M7 merges while passing on their
PRs. The test still times only the taps and attaches the number to every run; it fails past 45 s, which catches a real
slowdown (an extra step, a stalled command), and the 30 s goes on the device checklist. *Rejected:* re-running main
until a fast runner comes along (it hides real slowdowns the same way); dropping the timing (it's the point of the
test).

## Maquette 0.8 — M8, fixes & touch

**D-176 — The load meter is silent: the preview lightens by itself.** Device note: the "close to what this iPad keeps
smooth" chip *"is what makes me feel it's not smooth"*, even off by default (D-151). The chip, its two buttons, its
toasts and Settings ▸ Smoothness warnings are gone. The meter still measures; when it says near or over, the stage's
render-scale range drops one tier (A → B → C), and after twenty calm seconds it goes one tier back. A recovery the load
undoes within twenty seconds doubles the next wait (up to about five minutes), so a scene on the edge stays light
instead of flickering between two previews. Only the render scale moves: the shadow map belongs to the renderer and
rebuilding it mid-session would cost the hitch this is meant to avoid. *Always full resolution* is respected: someone
who asked for it gets it. Diagnostics ▸ Smoothness has the percentage and the current scale. *Rejected:* a quieter
chip (any message is the problem); lightening lines and shadows too (a visible pop; M15's smoothness pass can revisit
with device numbers); overriding Always full resolution (it's the user's switch, law 7).

**D-177 — Panels sit above all chrome.** Device note: Settings, reached through Actions, showed up beneath the
brush-size sidebar. The sheet itself is the system's and can't be covered; what was covered is the panel that leads to
it: `StageChrome` drew the clusters and their panels first and the sidebar and bottom row over them, so a tall panel
(Actions, Look, Select, on the sidebar's side) had the sliders drawn through it. The order is now sidebar, bottom
row, then clusters and panels. The panel's empty surroundings take no touches, so the sidebar works as before
wherever no panel covers it. *Rejected:* moving the sidebar down or the panel sideways while a panel is open (things
that move when you open something else; law 2); narrowing the panels.

**D-178 — A colour well on the sidebar, for every tool that puts colour down.** Device note: colour couldn't be chosen
while drawing (it lived in Look ▸ Palette and Paint ▸ Colour). The sidebar now shows the colour in the hand as a round
well under the two sliders while Ink, Flipbook, Draw (solid shapes) or Paint ▸ Colour is the tool; a tap opens the same
chooser Paint uses (the Look's palette + any colour), one `ColourChooser` for both. The kit's `HmmSidebar` gained an
`accessory` slot for it (hmm-kit 0.4.0). The Shadow Brush has no well: it has no colour of its own, it pushes the
Look's shadow in or out, and a well that changed nothing would be a stub (law 8). *Rejected:* a colour button in the
tool's options bar (the bar is different per tool; the sidebar is the same place for all of them); a well that's always
there (with Select in the hand it would look like it recolours the selection).

**D-179 — The sphere: Model's second page is called Edit, and the tile is a ball.** Device note: "Sphere missing on
Shapes". It is where it has always been (Model ▸ Add ▸ Shapes, second tile) and the panel doesn't clip it at any size
(the grid reflows; the new UI test checks all seven tiles are whole and tappable). What the code does show: the panel
remembers its page, the page next to Add was called **Shape**, and it lists Line, Rectangle, Circle, Arc: someone
looking for a sphere "under Shapes" lands there, finds a circle and no sphere. And on Add the sphere's tile was a flat
disc (SF Symbols has no sphere) beside a cube, a cylinder and a cone drawn in 3D. So the page is now **Edit** (it
sketches on, pushes, pulls, combines, mirrors and checks what's already there; nothing moved, its place and contents
are the same) and the sphere tile is a shaded ball. *Rejected:* moving the solids onto that page (it moves things
Hesham knows; the smoke tests and LAYOUT.md say where they are); listing them on both pages (one home each, M2's rule);
always opening Model on Add (remembering the page is right when you're modelling).

**D-180 — One hold menu, built in one place.** Touch and hold any thing and the menu is `HmmHoldMenu` (hmm-kit 0.4.0):
Duplicate · Rename · Copy · Paste, then one to three extras, then Delete in red. The four first rows and Delete are
*always* there in the same places; a row the thing can't do is dimmed (a key can't be renamed, a card can't be copied).
That keeps the hand's memory true (law 2) and is honest: a dimmed row promises nothing. Every menu the app had moved
onto it (poses, brushes, Looks, library items, paint layers, the outliner, flipbook tracks, screen effects, timeline
rows, cuts, palette swatches, Home's cards and stacks), and four new ones use it: objects on the stage, keys, clips and
flipbook drawings. Scene things get theirs from one file (`Workspace/UI/HoldMenus.swift`), so an object has the same
menu on the stage, in the outliner and on its timeline row. Where a menu had more than three extras they were folded:
a card's are *Add to stack ▸*, *Share ▸*, *Archive* (Open went: a tap opens). *Rejected:* leaving out rows that don't
apply (every menu a different shape); a fourth and fifth extra (it stops being a menu under a finger).

**D-181 — On the stage a still finger opens the menu; a moving one drags.** With the Select tool, holding a finger (or
the Pencil) still on an object opens its menu at the finger: a `UIContextMenuInteraction` on the stage view hung from
an invisible point, so the stage doesn't lift or dim. If the finger moves first, the stage's own drag takes it. The
held object becomes the selection unless it is already part of it (then the menu is about the whole selection).
Touch-and-hold used to add to the selection; that is now the menu's first extra, **Add to the selection**, shown when
other things were selected. The other tools keep hold-to-add and the Model tool's hold-to-pick, where a menu would be
in the way. Keys and clips are drawn into one picture, so the timeline asks what is under the finger
(`hmmHoldMenu(at:)`, listening from the window; the lanes' own taps, drags and box-select are untouched).
*Rejected:* a "several" switch in Select (a mode to remember); a second finger to add (two fingers already navigate
and undo).

**D-182 — Clips split at the playhead.** The clip menu's extras are *Split at the playhead* and *Loop / Play once*.
Splitting makes two segments from one: the second starts in the clip where the first stops (offset + elapsed × speed),
with no crossfade between them, in one undo step. Duplicate, Rename, Copy and Paste are dimmed on a clip: a clip is
placed from Cast, where its name comes from. *Rejected:* Reverse (the clip player has no negative speed; a stub
otherwise).

**D-183 — Pencil or hand is automatic.** Until an Apple Pencil has touched (or hovered over) the stage, a finger makes
with every making tool: Ink, Draw, Flipbook, Paint ▸ Colour, the Shadow Brush, Rig. From the first Pencil
touch (remembered on the device, `HmmPencilOrHand`) the Pencil makes and fingers only move the view. Settings ▸ Pencil
or hand ▸ *Draw with a finger too* is the one switch; nothing is asked at first launch and Draw's own toggle is gone
(no switch on the canvas). The Shadow Brush and the erasers used to be Pencil-only; they follow the same rule now, or
someone without a Pencil could never use them. A finger that may make still has to move the view, so each touch is
decided where it lands: on something the tool can make on (an object to paint, the guide to draw on) it makes;
anywhere else it orbits, as it always has. Two fingers pan and pinch as before. Where the guide fills the screen (a
plane facing the view, the flipbook's page) there is nowhere else, so while a finger makes a two-finger twist also
turns the view. *Rejected:* asking at first launch (a decision wall, law 4); a Pencil/finger toggle on the stage; making
two fingers orbit instead of pan for hand people (the same two fingers would do different things with and without a
Pencil in the drawer).

**D-184 — The Motion row: six looping motions are behaviours with one speed.** Tap a thing, tap Spin, Float, Bounce,
Wiggle, Swing or Follow a path at the top of the inspector, and it moves on the stage straight away (playback starts;
the timeline stays closed). A second tap stops it; several can run together. Each is a `Behavior` Core already
evaluates deterministically (Float = bob, Wiggle = noise, Follow a path = followPath looping), plus two new kinds,
`bounce` (a parabola per hop) and `swing` (a pendulum about the object's own pivot). Core's `LoopMotion` gives each
its numbers and reads a behaviour back as (motion, speed), so one slider (0.25× to 4×) retimes whatever runs and nothing
else is stored. **Make keyframes** bakes everything running on the selection in one step (`Simulation.bake` for several
behaviours at once: baking one by one would bake the others into each). Follow a path takes the scene's drawn line
(with several, the tile asks which); with none it says to draw one. Float, Spin, Wobble and the looping follow left
the inspector's *Add a behaviour* menu (one home each); Sway, Orbit, Look at and a path followed once stay there.
*Rejected:* writing keys at the tap (the loop would end at the timeline's end and couldn't be retimed with one slider);
a new motion system beside behaviours (two ways to move a thing); adding the new kinds to Scene Script now (backlog:
the MCP's sixteen tools are counted, R49).

**D-185 — The inspector can be docked.** Beside the selection stays the default (D-105). Settings ▸ Stage ▸ *Dock the
inspector at the side* keeps it at the trailing side whatever is selected, for people who'd rather it never moved.
*Rejected:* a pin on the inspector itself (a control on every panel for something set once).

**D-186 — Draw a bone, redone: one depth through the part, joints at the bends, shown as it's drawn.** Device note
on 0.7: *"it's not drawn correctly"*. Three things in D-166's centreline could put a chain where nobody drew it, and
all three are replaced. (1) **Depth comes from the mesh, per stroke, not per sample.** Each sample's ray is cut into
the stretches it spends inside the object (pieces pushed into each other count as one stretch; faces that don't say in
and out consistently fall back to pairing hits). The stroke then takes one stretch per ray so that their middles make
the shortest path in space, starting with the part in front (`CrossingPath`): a stroke along an arm stays in the arm
even where the body is behind it. Where the part runs into something much thicker (more than 2.5× the stroke's usual
thickness: a tail into a body), the point keeps the depth of the nearest sample where the part was on its own, so the
chain runs straight in instead of rising to the body's skin or diving to its middle. (2) **Joints land where the stroke
bends.** The centreline's corners are found by Ramer–Douglas–Peucker (tolerance: half the part's thickness, so a
wobbly hand isn't a bend), and the usual number of bones (two to eight, about 1.4 thicknesses long) is shared between
the stretches by length. A straight stroke is cut exactly as in 0.7. (3) **A live preview**: while the Pencil is down
the stage shows the joints and bones the stroke would make, inside the object, every few samples (the surface's BVH is
built once per stroke). **Drawing along a chain again replaces it** (`BoneStroke.redrawn`: bones within three quarters
of a thickness of the stroke and pointing its way, and the unbranched run that carries straight on from them, when the
stroke covers at least half): what hung from the old chain hangs from the nearest joint of the new one, keeping its
names and places; the replaced joints' poses and keys go with them, in the same undo step. A person's skeleton is
never taken for a redrawn chain. *Rejected:* the surface point under the tip pushed in by a fixed amount (wrong on
every part that isn't that thick); asking "replace or add?" (a decision wall; the stroke already says which);
replacing the whole rig on every stroke (a creature needs a tail and two arms).

**D-187 — Rig is one place with three steps: Bones → Skin → Pose.** Device note: the rig tools felt unorganised (six
buttons at once: draw, person, paint weights, reset pose, fit, remove). Cast ▸ Rig is now a row of three steps and,
under it, only the step's own tools. **Bones**: Draw a bone, Rig as a person, Remove the rig. **Skin**: says the skin
follows by itself, offers Paint weights (and Fit the weights when the shape changed). **Pose**: drag the joints (the
Select tool), Reset the pose; saved poses stay in the Poses section below. Skin opens once bones exist and their
weights have arrived; Pose opens once the skin fits. Nothing advances by itself: the next step lights up and you tap
it. The bar under the stage shows the same three steps while the Rig tool is in the hand. *Rejected:* a wizard that
moves on by itself (drawing a second bone would fight it); three separate sections (the old feeling, with headings).

**D-188 — A rigged object goes on being rigged.** Found while testing the redraw: in 0.7, once an object had a drawn
rig it counted as a cast member "with its skeleton built in", and `rigBlocker` refused it like a Blob. A second bone
could never be drawn, and Cast ▸ Rig showed that sentence instead of Paint weights, Fit, Reset and Remove. Only Blobs,
Puppets and imported rigged models are refused now; a drawn rig is what the three steps are for. A test draws a second
bone and walks the steps on a rigged cube. *Rejected:* nothing; it was a bug.

## Maquette 0.9 — M9, the Schizzo board

**D-189 — The brush engine moves into hmm-kit.** The board lives in the kit so Cutaway gets it, and it draws with the
full brush engine, so the engine goes first: `HmmBrush` (brushes, `BrushStroker`, the built-in tips, grains and
brushes, content keys, `Vec2`, `SeededRandom`) and `HmmBrushRender` (the stamp shader, `BrushStamper`, tip and grain
textures). LoweyCore re-exports the first and LoweyEngine the second, so ink, flipbooks, paint and Brush Studio read
as before and draw through the same code as the board. The brush *library* (sets, Procreate and Photoshop import,
`.maquettebrushes`, Brush Studio) stays in Maquette until a second app needs it. *Rejected:* the board in the kit with
a "stroke drawer" each app plugs in (two engines the moment Cutaway writes its own); a second copy of the shader in
the kit (the copies drift).

**D-190 — Flat strokes are placed by the shader.** A board's strokes keep their own units; the stamp shader takes
where a unit lands in pixels (`BrushBatch.Placement`), so a stroke's stamps are built once and serve every zoom. A
texturized grain is fixed to those units (it used to be fixed to the screen, which on a board would slide under the
strokes with every pan), and far out a stroke's widest part is never drawn thinner than 0.45 px. With no placement the
shader does exactly what it did (flipbooks, previews, Brush Studio: the goldens don't move). *Rejected:* re-stamping
in pixels at every zoom (thousands of buffers rebuilt per pinch).

**D-191 — The board is pure state; the screen is thin.** `BoardSession` (hmm-kit, pure Swift) takes touches as board
points and turns every finished gesture into one command: the six tools, picking, moving and resizing, the eraser,
notes, arrows, frames, copy and paste. What a board looks like is a list of draws (`BoardDrawList`) made by pure code
too. The Metal renderer, the UIKit canvas and the SwiftUI screen only carry touches in and draws out. Why: the
studio has no Mac, so everything that can be wrong should be wrong in a Linux test in seconds, not on a simulator in
CI an hour later. *Rejected:* the logic in the view (the usual place), tested only through the UI.

**D-192 — One layer, drawn again only when it must be.** The canvas keeps the whole board in one picture a quarter
of a screen larger than the screen on every side (`BoardLayerPlan`). A frame is that picture plus what moves: the
stroke under the Pencil, what a drag carries, the selection's marks. Panning shows the same picture shifted; pinching
shows it stretched (up to 2×, down to half) and it is drawn sharp again when the fingers lift or the view leaves it.
A new stroke is laid on top of the picture, nothing under it redrawn. So a board of thousands of strokes pans as
smoothly as an empty one (CONTEXT §3.3). The canvas draws only when something changed. *Rejected:* stamping every
stroke every frame (fine at a hundred strokes, not at five thousand); a tile pyramid (the right answer for boards
far larger than anyone has drawn yet; the layer is the first tile of it).

**D-193 — A board per project, in the project, opened from Actions.** The board is the project's (`board/` in the
package: `board.json`, its own history journal, its pictures), so it travels, duplicates and syncs with it, and its
undo survives relaunch like the scene's. It opens from Actions (the long tail's first Project tile, `open-board`) and
covers the stage; the top-left cluster stays Home · Actions · Look · Select (CONTEXT §4.1). It covers the stage as a
layer of the editor, not as a second full-screen cover, so the brush library and every other sheet open over it as
they do over the stage; the stage under it is hidden from VoiceOver and its keys rest. *Rejected:* a fifth button in
a cluster (the grammar is four and five); boards as their own documents on Home (planning is part of the project;
a loose board would need its own gallery, sharing and pin targets).

**D-194 — A pin is a picture, a card first.** Pin to the project (the hold menu, the bar under a pick, or Actions for
the whole board) renders the frame or the pick on the board's paper at two pixels a unit, keeps the PNG in
`assets/references/` and floats it over the stage as a reference card (`workspace.json`: how the project is seen,
never undone, outside the scene). The card's hold menu has *Stand it in the scene*: the same picture as a card object
where you're looking, in every camera and export. Nobody is asked "card or plane?" at the moment of pinning (CONTEXT
§3.4); the card is the default because a reference is usually for the maker, not the film. A frame's pin shows
everything in its area; a pick's shows only the pick. *Rejected:* a choice sheet on every pin; pins that stay linked
and redraw when the board changes (a reference that changes behind your back; pin again when you want the new one).

**D-195 — The board's sizes are the board's.** Brush size, the eraser's reach and an arrow's thickness are in board
units, so zooming in draws finer and a stroke is the same stroke at every zoom (Procreate's canvas, not a
screen-space marker). The eraser cuts strokes where it touched and erases ink only; pictures, notes, arrows and
frames are deleted whole, by choice. Arrows tie their ends to the note or picture they start or end on and follow
it; frames carry what lies in them (by each thing's middle) when moved, copied or deleted.

**D-196 — The paper is the board's own.** Dark (the studio's surface) by default, light by choice, with dots, a grid
or nothing; it doesn't follow the app's theme, because ink is drawn in a colour and a white sketch on a board that
turned white overnight is gone. Ink that was the paper's own default follows the paper when it is changed.

**D-197 — Hold is the Select tool's; a bar under the pick.** With Select, a still finger on a thing opens the one
hold menu (Duplicate · Rename, for frames · Copy · Paste │ Pin to the project, Bring to the front, Send to the back │
Delete); on empty space it offers Paste once something was copied. The same three most-used actions (Pin, Duplicate,
Delete) sit in a small bar under the board while something is picked: the board's inspector. With the drawing tools,
holding still is left free for M15's hold-to-clean-shape.

**D-198 — Switched off in Settings ▸ Board.** Off: the Board tile leaves Actions, Sketch leaves New project, and
pinned cards are put away. Nothing is deleted; on again and everything is where it was.

**D-199 — Sketch is a starter template now.** It opens the project on its board, once (`firstPanel: "board"`), in the
Sketch Look. (D-111 held it back until the board existed.)

**D-200 — Cutaway mounts the same screen when it exists.** PHASES said "integrated into Cutaway next to the script in
the same phase"; Cutaway starts after Maquette's launch (CONTEXT §10.10), so there is nothing to integrate into yet.
What is done is the half that can be: `HmmBoardScreen` is self-sufficient (its own brush menu and colour chooser when
an app brings none), and C2 (Record, where the script lives) now carries the step. *Rejected:* a placeholder Cutaway
target to host it (a stub).

**D-201 — What the board doesn't do yet.** Strokes blend normally (a brush's other blend modes need board layers);
the MCP bridge has no board tools; pictures decode on the main thread the first time they show. All three are in the
backlogs, none is offered in the UI.

## Maquette 0.10 — M10, live performance

**D-202 — Every recording is a take, kept whole; the tracks are the comp.** A Perform recording used to write its keys
over whatever was there: the second try destroyed the first. Now a recording is stored as a `Take` in the timeline
(the keys every performed channel got, its range, its name) *and* written into the tracks where it was performed. The
tracks stay what plays, so the animator, exports, the graph editor and every key tool see an ordinary timeline and
nothing about playback changed. Each take remembers where the comp plays it (`used`), kept true by the commands that
change the comp. Deleting a take leaves what plays. *Rejected:* takes as layers the animator mixes at playback (a
second evaluation path, and every key tool would need to know which take a key belongs to); keeping only the last N
takes (law 5).

**D-203 — Comping is dragging across the take you want.** The takes sit above the lanes in Perform, newest on top,
bright where they play. Drag across one and that stretch of the timeline plays it; touch and hold for *Use all of it*,
*Use it in the loop*, *Go to its start*, Rename and Delete. Using a take over a stretch replaces the keys of its
channels there, puts the take's value on both ends, and holds what played before one frame outside each end, so the
neighbours don't bend toward the new stretch. One undo step. *Rejected:* a take picker per range with split points to
place first (a decision wall: the drag says both things at once); crossfades at the joins (a performance cut on a
frame reads as intended; a blend of two smiles doesn't).

**D-204 — Dangle is a spring's answer to the past, not a simulation.** A loose bone's tip is where a damped spring
would be after following, for the last second or so, where the rest pose put that tip (a convolution, the way the
Blob's face springs work). The bone then points at it: it trails when the body moves, swings past when
it stops, and settles exactly as drawn. The same time always gives the same picture, whatever was played before, so a
scrubbed frame, the stage and an export agree, and nothing is stored or stepped. One slider (how loose: slow and
bouncy to quick and nearly stiff); a joint is loosened with everything below it, and what hangs further down lags
more by itself because it travels further. No gravity: the pose you drew is the pose it rests in. Swings are capped
at 85°. *Rejected:* a stepped rigid-body chain (its state depends on where playback started, so preview and export
drift apart, and scrubbing needs a re-simulation from zero); gravity and wind sliders (three more numbers before a
tail wags; they can come if someone asks); dangle on objects without bones (where is its pivot? draw a bone through
it: that question is answered by the stroke).

**D-205 — What was live a moment ago is part of the past.** A head turned by the camera isn't keyed yet, so the keyed
past doesn't know it moved. The editor keeps the last 1.4 s of live values (`LivePast`) and hands them to the animator
while a face, a voice or a recording is on; a dangling ear then follows a live nod. With nothing live the past is the
timeline alone, which is all an export ever sees. *Rejected:* dangle only after recording (the performer couldn't
see their own follow-through).

**D-206 — The face and hand channels drive any skeleton.** The channels a Blob and a built Puppet answered to
(`headYaw/Pitch/Roll`, `handLeft/Right X/Y`) now also turn the head and move the hands of drawn rigs, "Rig as a
person" rigs and rigged models (`LiveRig`): a humanoid's neck takes a third of a head turn and its head the rest; a
skeleton that isn't a person's turns the joint the character names as its head (Cast ▸ Life); a drawing tilts in its
own plane (roll, and half the yaw), since turning a flat puppet out of its plane only squashes it. Hands go where the
channels say by IK from the shoulder, elbows back, eased in from the rest pose. The channels use the picture's sides
(`FaceSolver`), so `handLeft` is the arm on the model's −x. Built Puppets' arms follow the hand channels too now (in 2.0 only
a Blob's did). Performed or keyed, it is the same path. *Rejected:* a second set of "live" properties per skeleton
type (a take recorded on one character couldn't be pasted onto another).

**D-207 — Parts ride a bone, and can be parts of a face.** Select a loose object, Cast ▸ *Make it part of* a drawn
rig: it goes inside the character, stays where it is, and rides the bone nearest to it (`attachBone`). Give it a face
role (an eye, a pupil, a brow, the mouth, the jaw, or one mouth of a set that takes turns) and it answers to the face
channels exactly as a built Puppet's parts do: that is how a drawn 2D puppet gets eyes that blink and a mouth that
talks, and how a prop sits in a hand. `FaceRig` now moves parts from where their bone carried them. *Rejected:* a
part picker on the stage (another gesture mode; the selection already says which object); attaching by a "socket"
object per bone (more things in the outliner than there are things).

**D-208 — Breathing and blinking are functions of time.** *Breathes* (a slider, off by default) fills a humanoid's
chest and, for anything else, lifts and narrows the whole body by about a percent, every 3.6 s, each character
starting somewhere else in its breath. *Blinks on its own* is the Blob's own blink for anything with eye parts; a
Blob has it by default, others once asked (so 0.9 projects look as they did). Keyed or performed blinks win. Both are
computed from the time and the character's id: no state, the same in every export.

**D-209 — Triggers live on the character.** A trigger is an expression, one of the character's saved poses, or a swap
(show one thing, hide the others it takes turns with), kept on the character like its poses, so it travels with it. A
new trigger takes the first free key of 1…0. While a take records, a trigger is performed: down is the state, up is
back to what was there (*Only while held*) or it stays until pressed again (*Stay on when let go*); it becomes held
keys at exactly those moments, never smoothed. One trigger of a kind is on at a time. Outside a recording a trigger is
an edit at the playhead like any other (keyed in Keyframe mode). The deck sits under the stage while the timeline is
in Perform, under the fingers; the keys work through the menu bar, so they show in the ⌘-hold overlay, and since a
menu command only hears a key go down, a second press lets go. *Rejected:* triggers in the project rather than on the
character (duplicate the character and its deck is gone); recording triggers as markers that fire at playback (a
second kind of animation data).

**D-210 — Draggers: a joint dragged while a take records is performed.** The joints stay on the stage during a
recording; drag a hand and it follows the finger (IK, as when posing), and the take keeps the turns of that chain.
Lift and it stays where it was left. One joint at a time. *Rejected for now:* return-to-rest on release and two hands
at once (backlog: both need the stage's drag to become per-touch).

**D-211 — The voice gives the mouth its shape, live, from the sound alone.** Cast ▸ *Mouth from the microphone*: the
mouth opens with loudness (measured against the room's quiet and this voice's loud, learnt as it listens) and takes a
shape from where the sound's energy sits: open vowels, "ee", "oo/oh", hisses; two blocks must agree before the shape
changes. It is the shape of the sound, not of the words: lip sync from the transcript (2.0) stays the exact one and
can replace a performed mouth afterwards. Nothing is recorded, recognised or sent. While the microphone is on it owns
the mouth and the camera keeps the rest of the face. Recording a voiceover is still its own button: the two use the
microphone differently, and a take of mouth shapes shouldn't silently add a sound file. *Rejected:* on-device speech
recognition for live visemes (a second or more behind the voice); a learnt viseme model (a model file to ship and to
be wrong in three languages).

**D-212 — Hand tracking is the wrists.** The hands come from the body tracker's shoulders and wrists (front camera or
iPhone), as in 2.0, now on every humanoid. Fingers aren't tracked: no character here has fingers to move.

**D-213 — The iPhone companion stays what it is.** The companion screen (2.0) already makes an iPhone with Face ID the
face camera over the local network. It now also sends eyes-wide and the brows' angle, which the Blob has dials for.

**D-214 — Homes for live performance (LAYOUT.md).** Everything lives where characters already do. Cast: the microphone
beside the face buttons, then *Triggers* and *Life* for the selected character, and *Make it part of* / *Part* for a
selected object. Cast ▸ Rig ▸ Pose: *Dangle* for the joint last touched on the stage. Under the stage (the tool
options' place) with Select in the hand and the timeline in Perform: the trigger deck. Above the lanes in Perform: the
takes. No new button in the clusters. *Rejected:* a Perform workspace of its own (law 2).

**D-215 — Schema 11.** Timelines gain `takes` and the journal the `setTakes` command; objects gain the optional
properties `dangle.<joint>`, `breathe`, `attachBone`, `liveHead` and `triggers`. Files from schema 10 open unchanged;
Maquette 0.9 refuses schema 11.

**D-216 — The UI job boots its simulator first and may take two hours.** On the 0.10 merge the first UI test
(`BoardTests`, first in the alphabet) twice hung on its first query against a cold simulator, past the five-minute
allowance: that fails the whole first attempt, the second attempt passes, and the two together left the iPhone
screenshot step past the job's 90 minutes, so `CI result` was red on a commit whose tests had passed. The job now
boots the simulator and waits for it before testing, and has 120 minutes. *Rejected:* re-running main until an
attempt passes first time (it was 88 minutes on the 0.9 merge already); dropping the second attempt (R33's flakes
are real).

## Maquette 0.11 — U1, feel

**D-217 — The feel recorder measures from the touch to the first refresh that can show the answer.** Each delivery of
touches is followed until the app's answer is ready (the stage's frame finished on the GPU for a touch on the stage,
else the main thread idle after the interface's commit) and then to the next refresh on the display link's grid. The
time is split into input (hardware to the app), main thread, encode and GPU; `missed` counts refreshes that went by
before the answer was ready, so 0 is "answered within one frame". The system compositor's own frame after that is the
same for every app and can't be seen from inside one, so it isn't counted. *Rejected:* Instruments traces (no Mac);
the existing signposts alone (only Instruments reads them); timing only the stage (panels and buttons are half of
"all the feel is shit").

**D-218 — The recorder lives in hmm-kit and watches through a gesture recogniser.** `FeelProbe` (HmmDiagnostics) is
the app-independent half, so Cutaway gets it; `FeelLog` is its pure arithmetic, tested on Linux. Touches are seen by a
recogniser on each window that never recognises, delays nor cancels anything, installed only while recording.
*Rejected:* a `UIWindow` subclass or swizzled `sendEvent` (SwiftUI owns the window; swizzling is a side door);
recording always (a cost on every touch for a file nobody reads).

**D-219 — While it records, a small red dot at the top; at the end a haptic and a toast.** Nothing to touch, nothing
that moves: the dot is drawn once. *Rejected:* a countdown (it redraws every second, inside the measurement);
nothing at all (he'd not know when the minute ends).

**D-220 — 0.10.1 ships the recorder alone.** So the first recording measures 0.10's feel unchanged: it is the "before"
the phase notes keep, and every speed fix after it is aimed at what it ranks and proved by the same recording.

**D-221 — The Kit's pictures are baked in CI and committed beside each model.** The simulator renders every Kit asset
with the app's renderer in the Ink Look (`KitPicturesTests`, run by the Kit pictures workflow) and the PNGs ship in the
app; the iPad only reads them, off the main thread, when a tile appears. The root of "the models never show their
pictures": the picture used to be taken before the model had loaded, so an empty one was drawn and then kept.
`Thumbnailer` now loads every model a picture places first, which also fixes empty Home cards. *Rejected:* rendering on
the iPad, fixed (a render per tile on the main actor while scrolling is exactly the feel U1 removes); baking at build
time in the release workflow (the pictures would differ between builds and couldn't be reviewed in a PR).

**D-222 — Sharp at rest, smooth in motion.** Moving, the stage holds the frame rate with the dynamic scale as before;
0.15 s after the last frame it draws one at full resolution on every tier, and an isolated change (a tap, a slider step)
is drawn at full resolution while the last such frame fit the budget. The extra frames don't feed the scale or the load
meter. A hot iPad keeps the lighter preview. *Rejected:* raising the scale slowly while calm (30 calm frames: a stage
that draws on request may never get them, which is how an empty scene sat at 80 %); full resolution all the time on
Tier A (the drag is what has to be smooth).

**D-223 — An 8 GB iPad is Tier A.** The line was 7.5 GiB of reported memory; an 8 GB iPad reports less than 8 GiB, and
so may land under it and preview like an A-chip iPad. The line is 7 GiB now (no 6 GB iPad comes near it). The recorder
writes the tier into every recording, so the device answers it.

**D-224 — Paint makes its object ready the moment it's chosen; no message.** With Paint in the hand, choosing an
object (or opening Paint with one chosen) lays it flat, or carries its paint onto a changed shape, in the background;
"Getting … ready to paint" and "Bringing the paint onto the new shape" are gone, and so is the *Paint …* button, except
when making it ready failed (then it's the way to try again). Starting it is an undo step of its own, as before.
*Rejected:* preparing on every selection whatever the tool (heavy work for objects nobody paints); keeping the result
off the document until the first stroke (a second path for the first stroke to commit through).

**D-225 — A bone is weighed quietly.** "Working out how it bends…" is gone: the stroke's bone stays on the stage, the
step keeps its controls, and Skin and Pose light up when the weights land. A stroke drawn meanwhile builds on the rig
being weighed, and only the newest result is stored (it holds the earlier bones too), as one step.

## Maquette 0.12 — U2, layout

**D-226 — U2 is stacked on U1 and ships U1's work with it.** U1 (PR #30) waits for Hesham's first feel recording
(steps 2 and 6 are aimed at what it ranks), and every phase ships (law 9). U2 branched from `phase/U1-feel`, so the
0.12 merge carries U1's sharp-at-rest, quiet work and baked pictures; U1 stays open for the recording's fixes, and its
gates are re-checked on 0.12. *Rejected:* holding U2 until the recording arrives (a phase that can't ship); rebasing U2
on main and leaving U1's finished steps unshipped.

**D-227 — Cast dissolves; the Library and Rig get buttons.** Top left: Home · Actions · Look · Select · Library; top
right: Model · Draw · Paint · Rig · Animate. Blob, Me and Puppet are things on the Library's first page; rigging (Bones,
Skin, Pose, poses, clips) is Rig, today's tools moved until U4 rebuilds them; expressions, lip sync, face capture and
the voice are the selected character's button beside Record in the timeline's Perform. The Library has two pages for
now, **Things** (the characters and the Kit) and **Yours** (imports, builds, worlds, scripts); Motion and Rigs join
when U4 makes poses, clips and rigs things you save (no stub pages). *Rejected:* a Perform workspace of its own
(law 2); the four pages now with two of them empty.

**D-228 — Held features travel in the Info.plist, not in compilation conditions.** `HmmHeld` (a new pure hmm-kit
module) reads the list once from the bundle's `HmmHeld` key, which `project.yml` fills from `MAQUETTE_HELD`: the
AppStore configuration names `livePerformance mechanisms ar webLayer`, every other configuration nothing. Swift
packages don't see an app target's `SWIFT_ACTIVE_COMPILATION_CONDITIONS`, and every entry point lives in a package
(LoweyFeatures). The bundle is sealed by its signature, so a store build still can't reach a held feature by any means.
A UI job builds the AppStore configuration and walks LAYOUT.md: rows marked *(held: 1.x)* must be absent, all others
present. *Rejected:* passing flags into the package through a generated Swift file (another file CI must keep in step);
a runtime setting (a hidden switch, which CONTEXT §5 rules out).

**D-229 — Model ▸ Add keeps making things in the world.** Shapes, Light, Words & pictures (3D text, a photo or video),
Effects. Building shows while the scene is set up for a Room. Cameras live on the camera button (tap: look through;
again: the next camera; after the last, back to the free view; hold: a new camera from this view, or pick one; with no
camera, the first tap makes one). Titles, labels, marks and screen effects are the timeline's + Overlay.

**D-230 — The scene's name is a door.** Under the top-left cluster, tapping it opens: Set up for (Blank, Print, Room,
Animation), the scenes, and the objects (the outliner, moved from Select). Setting up changes units, snapping, the
grid, the new-shape size, the printer and the timeline (raised, never hidden), never the project
(`ProjectWorkspace.settingUp`, Linux-tested). Character and Sketch remain as templates for old projects but aren't
offered: a character is a Library thing, the Board is in Actions. Select is a small bar.

**D-231 — The object panel fits one screen.** Move · Turn · Size, size, colour, the kind's own controls, Make it move
(one strip: the six loops, then the once-moves; Bounce, Wiggle, Float and Spin are loops only), what the selection can
do (Combine for two or more shapes, Mirror and symmetry, Make editable, Scatter copies), then four rows one step deeper:
Look of this object (glow, smoothing, bevel, its own Look, lines, rim, accent, gloss), More ways to move, Numbers,
About. Its header is a grip: moved by hand, it stays where it was left (as fractions of the room, so it survives a
rotation) until its header is double-tapped; a remembered spot that would cover the selection gives way to the place
beside it. *Rejected:* a horizontal list of every motion in a grid (five rows of tiles, off the first screen).

**D-232 — One menu per object, inside the kit's three extras.** Hide, Lock, and More (Group or Ungroup, Array, To the
ground, Swap for a model, Save to the library, Unpack): the same from the stage, the outliner, the timeline and the
panel's ⋯. *Rejected:* raising `HmmHoldMenu.maximumExtras` (more than three rows under a finger is a panel).

**D-233 — The + goes straight in.** A blank project named "Untitled" (then "Untitled 2"…), in the new **dark studio**
mood (schema 12): a near-black ground, one soft key, faint grid. Rename from the card's name. Set-ups are the quiet
row under the title; samples one card. `StageColorsTests` checks the default shape and ink colour, the grid, the axes
and the selection outline against the dark ground (WCAG contrast), with the editor colours moved into Core's
`StageColors` so the test reads the renderer's own values. *Rejected:* the dark studio as a Look override on the Studio
mood (Look ▸ World would then call it "Studio").

**D-234 — Perform and Keys; keys add themselves; Perform waits for a touch.** Compose is gone: a selected row's whole
animation has a grip along its bottom, in either mode. The bar is eight controls (play, the time, Perform | Keys,
Record or Key, + Overlay, + Sound, the menu, collapse); markers, the loop and each mode's extras are in the menu; the
ruler steps a frame on a tap just beside the playhead and goes to the start on a flick. Without Compose to protect a
set from stray keys, the rule CONTEXT decided takes over: the first key on a thing is deliberate (Key, a motion, a
performance); after it, a change in Keys keys itself. Record arms Perform ("Ready"); the first touch starts time,
lifting the hand stops it, touching again resumes; a face, a voice or the iPad's motion still runs time after a
3-2-1. *Rejected:* keeping auto-key's old rule with Keys as the default mode (moving a cube while building would key
it).

**D-235 — The sidebar rests; its sliders mean size and opacity.** With no tool that uses them they shrink to a faint
rail; a touch wakes them as ink's width and opacity (the drawing tool that comes first). Snapping distance moved to
Model ▸ Precision, moving-around speed was already in Settings ▸ Stage. Settings ▸ Stage ▸ Always show the sidebar.

**D-236 — Chrome restraint is on by default, as the trial.** Panels are near-opaque graphite glass that takes no colour
from the stage; amber marks only the tool in the hand (`HmmButton(accent:)`), an open panel's button gets a neutral
fill. Diagnostics ▸ Restrained chrome flips back to compare, on the device.

**D-237 — Settings keeps a door from Actions.** The spec lists what Actions keeps; Settings is added so a Pencil or
Stage preference isn't three screens away mid-project (Home's gear stays the other way in). Learn is the tour, every
gesture and the instructions switch; Settings ▸ Gestures shows the same gesture list until U3 makes gestures
switchable.

**D-238 — Nothing greyed out, no label cut, checked twice.** Panels hide what can't act (`shown(_:)`); pills, chips
and tiles take a second line instead of truncating or shrinking. `ChromeFitTests` fails when a chrome control sits on another or is cut by the
screen's edge, or a panel's control is cut by it (a panel covers the sidebar on purpose, so overlaps are the chrome's
check), in landscape and portrait; CI runs it on the 13-inch,
the Atlas workflow on the mini, the 11-inch and the 13-inch in both orientations.

**D-239 — Not in this phase, though CONTEXT lists it near the layout.** Hatched shadows (a new capability; U2 moves,
it doesn't add), the Reference window (U3), the brush library dropping down (U3), switchable gestures (U3).

## Maquette 0.13 — U3, draw

**D-240 — U3 starts from main, after U2.** U1 (PR #30) still waits for the first feel recording; main already carries
U1's finished steps through U2 (D-226), so U3 branches from main and ships as 0.13. *Rejected:* stacking on U1's branch
again (nothing in it that main lacks).

**D-241 — A sheet is a frame and a shape, kept with the scene by its first stroke.** `DrawingSheet` (Core) is an origin
and a turn (local +z faces whoever placed it, +y its up), a shape (flat, around, dome, on the object), a size and a
curve; laid on an object it lives in that object's space and rides with it. The sheet under the Pencil is view state
until something is drawn on it; then `setSheets` keeps it, in the stroke's undo step. Ink, solid shapes and sketches stay
objects of their own; only flipbooks name their sheet. *Rejected:* every placed sheet in the document (a scene full of
sheets nobody drew on); ink strokes owned by sheets (the 2.0 ink objects, their exports and their MCP shape would all
change for nothing a person sees).

**D-242 — Where the first sheet stands.** For ink, solid shapes and flipbooks: upright, facing the view, through what
the view looks at (Feather's easel); seen steeply from above or below it lies level. For Sketch: on the ground there,
its axes along the world's x and z (Shapr3D's ground sketch, and M3's block keeps its sides). A sketch begun on a solid's
face lays the sheet on that face, so pulling and cutting work as before. *Rejected:* the old view-locked principal plane
(it turned with every orbit, which is what made a stroke's depth a guess).

**D-243 — A finger's tap places the sheet; the Pencil's draws.** With a tool that draws on the sheet, a finger's tap
lays it on the surface under it or stands it in the air at the sheet's distance, facing you. An ink drawing under the
finger is picked instead (strokes join it). Until a Pencil has touched the iPad, a finger's tap with Sketch places a
point (it is the only hand there is). *Rejected:* a separate "move sheet" mode (one more mode to be in).

**D-244 — Strokes land past the sheet's edge.** A flat sheet is an endless plane and "around" an endless cylinder for
landing; the edge only shows where it is. Around and dome curve away behind the point they were placed on, so changing
the shape keeps the sheet touching the same spot. *Rejected:* clipping strokes at the drawn edge (a stroke that runs off
the sheet would be cut for no reason a person can see).

**D-245 — Flipbooks on a sheet keep their points in the sheet's own metres.** A flat sheet's across and up; around, the
arc and the height; a dome, the two arcs. `FlipbookLayout` takes each point through the camera, so the drawing keeps its
perspective and stays where it was drawn; a stretch behind the camera splits the stroke. They are still drawn over the
shot (not hidden behind objects), like every flipbook. A flipbook on an "on the object" sheet lies on its plane there.
Drawn effects keep riding objects (`.object` anchors), and stuck to the camera stays as an option. *Rejected:* 3D ribbons
for flipbook strokes (a second drawing path for the same brush).

**D-246 — The frame strip's pictures are the strokes themselves; the loop holds for the Pencil.** Each drawing is drawn
by SwiftUI from its strokes, all of a track at one scale so the motion shows; a drawing is as wide as it is held. While
the strip loops, the Pencil touching pauses on the drawing under the playhead and the loop goes on 0.45 s after it lifts.
*Rejected:* rendered thumbnails (a render per drawing per change); drawing into whatever drawing the playhead reaches
mid-stroke.

**D-247 — How sketching talks back.** The end of a line snaps, in this order: a corner already drawn, an edge's middle
(12 points on screen), a round angle (every 15°, within 2.5°), parallel or perpendicular to a line already on the plane
(within 2.5°). The readout beside the tip (length · angle · the snap's name) can't be typed while drawing; once the line
lands its length is the usual number to tap. The magnet switches all of it. *Rejected:* typing mid-stroke (the Pencil is
busy); snapping lengths to whole units (it fights the angle snaps; the grid does it for taps).

**D-248 — Our number pad is the kit's; the text it makes is read by the app's own parsers.** `HmmNumberPad` opens as a
popover beside the number; its text is `25`, `2*12`, `1.5 cm`, `1 ft 6 in`, so `LengthExpression` reads lengths and
`HmmArithmetic` plain numbers. Sliders keep their readouts. *Rejected:* a pad that computes (two parsers that could
disagree).

**D-249 — The hand shortcuts are kit switches, on until switched off.** `HmmShortcut` (two-, three-, four-finger taps,
three fingers swiped down, a finger's double-tap, a finger held down, hold at the end of a stroke, squeeze, Pencil
double-tap) live in Settings ▸ Gestures. Three fingers held redo again and again, as two undo. The edit bar (cut, copy,
paste, duplicate) waits four seconds. A finger's double-tap frames the thing under it; on the same thing again, it
turns to look straight at the face touched. *Rejected:* a look-straight button (no on-screen choices, CONTEXT §10.10).

**D-250 — The Pencil drags through its own recognizer, and never moves the view.** A Pencil-only pan beside the
fingers' means a finger resting as a modifier can't stop the Pencil's drag; a Pencil drag that would have orbited does
nothing. A finger resting (moving under 12 points) while the Pencil is down flips the Snap magnet for that move.
*Rejected:* one pan for both (two touches stopped it).

**D-251 — Squeeze and double-tap follow the iPad's Pencil setting.** The eraser, the last tool and the colours do
those; the tool palette (the iPad's default for squeeze) and anything else open our menu of six at the tip. Settings ▸
Your Pencil can make double-tap open the menu instead (for a Pencil that can't squeeze) or do nothing. Squeeze no longer
plays and pauses. *Rejected:* ignoring the iPad's setting (people set it once for every app).

**D-252 — Who does what is two jobs for now.** Moving objects and posing (fingers), pulling faces, edges and corners
(the Pencil); each Fingers, Pencil or Both. Until a Pencil has touched the iPad, a finger does the Pencil's jobs. Placing
pins and dots joins the page with U4, when they exist. *Rejected:* rows for jobs that don't exist yet (law 8).

**D-253 — The Pencil's feel is the kit's, read as each stroke starts.** `HmmPencilFeel`: the curve from two strokes is
fitted through the medians of the lightest and the heaviest (a thin visible line, a full one); presets for a light,
normal or heavy hand; the curve to drag; stabilisation added to ink's and flipbooks' streamline; a Pencil whose pressure
never moves gets it from its speed. The stage and the board both apply the curve. *Rejected:* a curve per tool.

**D-254 — The Snap magnet is a master switch over the snap settings.** `SnapSettings.magnet` (on when missing);
`snap.effective(flipped:)` is what every snap reads. Its details are its hold (a context menu), and Precision keeps the
grid on the ground and the units. *Rejected:* a popover of twelve switches (what changes rarely can take one at a time).

**D-255 — The Reference window is a reference card that didn't come from the Board.** Actions ▸ Reference (Photos, or
paste) keeps the picture under `assets/references/` and floats it as a card marked `window`, which stays when the Board
is switched off; any card folds to a chip. With Pick in the hand a tap on it takes its colour. Its menu traces it on the
sheet: a card object on the sheet, half see-through, in one step with the sheet kept. *Rejected:* a separate window
type (two floating-picture systems).

**D-256 — The timeline, as Dreams has it.** The Pencil's loop picks keys and clips (a clip by its middle); Settings ▸
Gestures can give the loop to one finger, and then two fingers pan; the Pencil's hover scrubs unless playing (its own
switch, on: hover preview on the stage stays off by default); holding a clip's edge and dragging retimes it (speed
changes, the other edge stays). *Rejected:* two-finger pan always on (it doubled the one-finger pan SwiftUI already does).

**D-257 — The brush library drops down.** A popover from the brush row: sets on the left, the set's brushes on the
right; the whole library (Brush Studio, sets, imports) is its last row. *Rejected:* Brush Studio inside the popover
(too much for a glance).

**D-258 — SPIKE: squeeze, the Pencil's haptics and the loupe are on the pinned SDK.** `PencilSDKSpikeTests` (hmm-kit)
builds and runs a `UIPencilInteraction` squeeze delegate, `UICanvasFeedbackGenerator` and `UITextLoupeSession` on CI's
simulator. Squeeze and haptics need an Apple Pencil Pro to happen: device checks. No fallback needed.

## Maquette 0.14 — U4, rig, and bring your sculpt

**D-259 — U4 starts from main, after U3.** U1 (PR #30) still waits for the first feel recording; main carries U1's
finished steps. *Rejected:* stacking on U1's branch.

**D-260 — Pins and dots are marks kept on the rig; the skeleton is built from them.** `RigMark` (a name, dot or pin, a
place, the mark it hangs from, the part's thickness) lives in `ObjectRig.marks`; `RigMarks.rig` builds the skeleton:
a dot is one joint, a pin with a mark above it gets three bones between them (`<pin>~0…~2`, the first sitting on the
mark above, so pulling the pin turns only its stretch). Joints keep their marks' names, so moving, adding or removing
a mark keeps every pose and key on the others. A dot pulled brings its limb along (up to a fork, a pin or the first
mark); a pin pulled bends its stretch while the mark above holds. Rigs from before 0.14 read their joints as dots.
*Rejected:* keeping draw-a-bone as the main move (he didn't know how to use it on device, "felt really useless");
storing only the skeleton (it couldn't be changed afterwards, his frustration).

**D-261 — A body the marks leave uncovered gets a root.** As drawn bones did: vertices farther than one and a half times
the part's thickness from every mark are the body; when there are enough of them and their middle is away from the first
mark, a `root` joint there carries it, so a cat's body holds still while its tail bends. *Rejected:* making the first
mark the root (pinning a tail would swing the whole cat).

**D-262 — Rigging adds the geometry a shape lacks, through one property.** When a shape's longest edge is more than
half again half its shortest bone between marks (a cube is eight corners), rigging sets `bendDetail` (cuts across the
largest side, up to 24: finer made a cylinder's weights take over 20 s on CI's simulator) in the same step; `MeshDensify` splits long edges at their middles until none is longer, the same in
`PaintSource`, the renderer's mesh cache (`MeshKey.dense`) and every export, so weights, paint and drawing agree.
Placed models aren't cut (they carry their own detail). *Rejected:* converting to an editable mesh (MeshBuilder merges
coplanar triangles back into one face); subdividing inside the skinned twin only (paint and picking would disagree).

**D-263 — A group rigs rigid: each part rides its bone, no skin.** Rigging a group (or several things, which are
grouped first: "Rig these together") keeps the rig on the group and sets each part's `attachBone` to the joint whose
bone runs nearest the part's middle (`RigidParts`, a chain's last joint reaching on past its end), so `LiveRig.carryParts`
moves the parts. The first dot on a group also places a dot in the middle of the part nearest it, which holds; a dot
between two parts hinges them. This is ToonSquid's "bind a whole group". *Rejected:* skinning every part to one skeleton
(solid parts would melt at the joints).

**D-264 — SPIKE passed: guessing a person, four legs and wings from the shape.** `BodyGuess` reads a shape standing on
its lowest point, facing +z, sampled at 96 cuts across: legs are the separate columns at the bottom (tracked up until
two meet), a person's hands are the points reaching out furthest sideways, its neck the narrowing below the head, its
hips above where the legs meet by an amount that grows with leg length; four legs take the higher end as the head and a
tail where the shape goes on past the hips; wings are where the body thins out across x. Checked on CI against the
Kit's rigged people's own skeletons (every joint within a tenth of the height; the UAL model too, kept out of the suite
for its half-minute of clips), the Kit's astronaut and made animals both ways round. Ship the guess; a shape that can't be
read gets the dots in a standard layout to drag (`fourLegsLayout`, `wingsLayout`, the person template). *Rejected:*
Apple's body-pose model (failed on CI in M7, D-168).

**D-265 — Person is guess then fix, and a person rig opens again with its dots.** The dots land placed (no eight taps);
the Pencil moves the nearest dot where it touches, any dot can be dragged, Rig builds the humanoid. `ObjectRig.person`
keeps the dots so Change the rig shows them again; a person rig from before reads them back from its joints. Standard
names stay, so poses and built-in clips survive a change.

**D-266 — Rig is two moves in one tool, with the body shortcuts first.** With nothing rigged, the panel shows Person ·
Chain · Four legs · Wings and "Pins and dots"; the tool's bar chooses Dots or Pins for the Pencil. A tap places a mark
(hung from the last one, or from one tapped first); a stroke along a part lays a chain down its middle (dots at every
joint, pins every three); a mark dragged moves, held goes, double-tapped switches pin and dot. Rigged: Change the rig,
Reset the pose, How it bends (weights, one step deeper), Remove. The three steps (Bones → Skin → Pose) are gone.
*Rejected:* a separate tool per move (one more mode).

**D-267 — Placing pins and dots joins who does what (the Pencil by default).** `InputJob.marks`; a stroke reports
whether it's the Pencil's (`StrokeGestureRecognizer.isPencil`). Marks themselves are dragged by either hand over the
stage. Closes D-252's "joins with U4".

**D-268 — Motion is library material: poses, clips and loops by joint name.** `MotionItem` keeps keys per joint name
(humanoids by the standard names) and the thing's own move and turn relative to where it started; the library manifest
keeps them (`motions`). Dropped on the selected thing: a pose turns its joints like applying a pose, a clip lays its keys
at the playhead, a loop loops forever; joints with no match are skipped and named in one line. Saved from a pose's menu
and from a row's grip menu. Dropping is a tap on the Motion page with the thing selected. *Rejected:* dragging motion
tiles onto the stage (a tile over a character and over empty space would need two meanings); clip tracks for saved
motion (they only play library models' clips).

**D-269 — A motion repeats by its end; one switch loops it forever.** `Track.cycle` (`TrackCycle`: start, end, repeats or
nil for forever) plays a stretch again; a row repeats over its whole stretch, so every property stays in step. The grip
under a selected row has a dot at its end: drag it on to repeat, back to repeat less; repeats are drawn lighter. Shifting
a row moves its repeats; duplicates keep them; glTF and FBX play repeats out frame by frame (a forever loop exports one
stretch: engines loop it). Clips on clip tracks already loop by stretching.

**D-270 — Four feels on a key.** Ease (ease in and out, the default), Snap (overshoot and settle), Bounce, Straight;
"Curve…" opens the graph editor. Keys already eased by default and add themselves after the first (D-234).

**D-271 — Vertex colours in, as paint.** glTF `COLOR_0` (linear, any component type) and OBJ's `v x y z r g b` (0…1 or
0…255) become `ImportedPart.colors` in sRGB; `AssetPaint.bake` multiplies them into the first paint layer, and a model
that carries them is made paintable the moment it lands, so it arrives painted and stays paintable. OBJ is read byte by
byte (a sculpt's OBJ is a hundred megabytes). *Rejected:* a vertex colour attribute in the renderer (a second colour
path beside paint).

**D-272 — SPIKE passed: our own quadric simplifier.** `MeshSimplify` (Garland–Heckbert error, Forstmann's fast threshold
form, MIT, in Swift, portable to Linux) lightens a 1.3 million triangle lumpy sphere to a tenth in about 4.5 s in a
release build on the Docker CPU and 2.55 s on CI's Linux runner, every corner within 1 % of the surface,
open edges kept; colours carry from the nearest original corner. Fallback (meshoptimizer) not needed.

**D-273 — Lightening budgets, by tier, and the Detail slider.** One model may keep 500 000 triangles on Tier A, 200 000
on B, 80 000 on C (`SculptImport.budget`). A heavier import with no picture wrapped on it is lightened on the way in,
written as `light-<detail>.glb` beside the original, which the asset keeps (`original`, `detail`). The object panel's
Detail slider (¼ to 2× the budget) lightens again from the original off the main thread, or goes back to the original
when asked for more than it has. Textured models aren't lightened (their pictures would lose their place).

**D-274 — The way in lands on the stage.** Open in, the share sheet, a drop on the editor and Home's import put a model
file on the stage (a new project when none is open), chosen, with "Rig it" offered once at the top of its panel; extra
files wait in the Library. The bridge's import still only adds to the Library. No Nomad name or logo anywhere.

**D-275 — The Nomad fixture waits for Hesham's export.** Until his painted sculpt arrives, the Core tests make one the
way Nomad writes one (a single mesh, colours on its corners, no texture) through glTF and OBJ. It joins the test
resources with his name as the author when he sends it (device checklist).

**D-276 — Rigged things leave glTF as skins.** A rigged solid writes a rig node holding the skinned mesh
(`JOINTS_0`/`WEIGHTS_0`) and its joints, inverse bind matrices from the rest pose (the same answer whether a reader applies
the mesh node's place or not), a still pose in the joints' rotations and `bone.` keys as rotation channels. Painted and
drawn rigs still leave posed. CI opens the rigged tail in Godot 4.3 (skeleton, skin, animation, bones moving) and in
Blender 4.2 and 5.2. Unity has no licence-free headless run: device (computer) checklist.

**D-277 — SPIKE passed: our own FBX writer.** A binary FBX 7.4 (`FBXBinary`, `FBXSkin`: geometry, limb nodes, a skin of
clusters with Transform and TransformLink, a bind pose, rotation curves in Euler degrees, metres with UnitScaleFactor 100,
y up) opens and plays in Godot 4.3 (ufbx) and Blender 4.2 and 5.2, on CI. Export ▸ 3D model offers FBX when a rigged solid
is in the export (one thing per file). *Rejected:* the fallback (the Blender package writing FBX on a computer): the
writer passed, and needing a computer for Unity breaks idea → done.

**D-278 — The stage's overlay reaches under the status bar, as the stage does.** Joint handles, the lasso, motion paths,
selected overlays' frames and the onion skin were drawn in a view inside the top safe area while the stage they mark
fills it, so on an iPad each was drawn about 24 points below where a touch grabs it (found by U4's timed tail test: a
pull on the ring moved the object). Since 0.14 the overlay ignores the top safe area like the stage.

**D-279 — The timed rig tests allow CI 20 s for the tail and pull slowly.** On main's first 0.14 run the tail took 16.7 s
(11.5 s on the PR) and a fast synthetic drag sometimes missed the handle; the pull is now held a moment and drawn at
250 points a second. The claim on the iPad stays 10 s and 30 s (device checklist).

## Maquette 0.15 — U5, draw again & the grammar

**D-280 — U5 starts from main, after U4, in a cloud session.** U1 (PR #30) still waits for the first feel recording;
main carries U1's finished steps. The phase ran in claude.ai/code with no Mac: Core was built and tested on Linux in the
session (Swift 6.1), everything else was proved on CI, the same as on the PC. *Rejected:* waiting for a PC session.

**D-281 — A dragged joint is a live value until the finger lifts.** Each move of a dot or a pin was a command (journal,
keys, every observing panel). While the finger moves, the IK result goes into the live values the renderer already skins
with on the GPU with the weights it has; the drag lands as one `setProperties` step on release (`finishIKDrag`), and keys
add themselves then. A Feature test fails if a move's median answer is over a sixtieth of a second. *Rejected:* rebuilding
weights during the drag (a mark's rest moving at rest pose shows nothing; the lag was the posing).

**D-282 — The cube at the stage's centre was the sheet.** Nothing in a blank project draws a cube; what stood at the
middle of the stage with a drawing tool in the hand, and moved for no drag, was the unused sheet with its floating bar.
It now shows as paper only while drawing (a trace between strokes) and has no bar (D-285). *Rejected:* guessing at the
helpers (they are picked and moved like any object).

**D-283 — Draw and Paint are one Draw, the brush decides.** Top right is Model · Draw · Rig · Animate; Draw opens no
panel and its bar is Brush · Smudge · Erase · Sheets · Colour. One brush is in the hand for lines, frames and paint
(`BrushTool.ink`'s choice); the library's sets draw lines, the built-in Painting set paints models (Sheets becomes
Layers over a thing, and a paint stroke begun in the air draws a line), and under the library's sets are Solids, Shapes
and Shadow (`DrawBrushKind`). Smudge pushes lines (`InkEditing.pushing`); on painted models Smudge waits for U7 Texture,
where the paint engine gets per-pixel tools. *Rejected:* a tool per kind of mark (the U3 panel that showed Draw, Erase
and Select strokes twice); a Paint button beside Draw.

**D-284 — Zero setup: the surface, else the sheet.** A line or a solid begun over a thing (not an ink drawing) lands on
its surface and keeps no sheet; past the surface's edge it carries on in the plane where it left. In the air it lands on
the sheet, which turns to face you before the stroke unless a finger placed it or something is drawn on it; a flat sheet
seen edge-on gives way to a new one facing you. Flipbooks keep their sheet. *Rejected:* every stroke on the sheet (U3:
lines landed in the wrong place over a model).

**D-285 — The sheet is paper, and its controls are its hold menu.** Warm paper at 15 %, a soft edge in three bands and
faint dots while drawing; a 4 % trace a moment after (`StageColors`, checked against the dark studio). A finger held on the
sheet's empty part opens its menu: place (nearer, farther, face me), shape, guide, rename, delete. The floating bar went.
Drawings remember their kept sheet (`drawnOn`) and `SheetCarry` moves them with it in the same step. *Rejected:* a
handle on the sheet (the floating bar sat on the drawing).

**D-286 — Extra smoothing is gone.** A line's streamline is the brush's own, and the Pencil page's stabilisation on top
(0 unless set). Smoothing twice pulled the line behind the tip. *Rejected:* keeping a per-tool slider.

**D-287 — Accuracy is a UI test.** Under `-ui-testing` each stroke writes where its touch began and where its first point
landed on screen; `DrawTests` draws in the air and on a cube and fails past three points, and checks a tap picks the
stroke under it. The Pencil page's pad shows a crosshair where the app reads the tip (touching or hovering). The lasso's
offset in U3 was the overlay sitting under the status bar (D-278, fixed in 0.14). *Rejected:* a device-only check.

**D-288 — Shapes are a set, drawn in one drag.** Line point to point, rectangle corner to corner, circle from the middle
out (U3's sketch already landed a drag as two points). A closed shape is picked as it lands and shows one arrow; a drag
on it pulls it into a solid; a tap on it keeps it picked. Hold-to-shape says the size it made. *Rejected:* a Sketch tool
beside Draw.

**D-289 — A tapped stroke has a chip; dragging along it reshapes it.** A Pencil tap that barely moves on a line picks it
(no dot is drawn there); the chip has the brush and the colour in the hand, thickness as a number pill, smooth, delete.
The Pencil started on a picked stroke pushes it like Smudge. *Rejected:* a Select strokes mode.

**D-290 — Frames are flicked, Dreams' way.** With frames on, a finger's flick (under 0.3 s, over 50 points, twice as
wide as tall, over 700 points a second) turns the frame: right adds the next drawing, left goes back; a flick draws
nothing and a turn of the view it began is put back. The time at the bottom left opens onion skins (0–8 each way, two
colours). Holding a drawing on the strip and letting go duplicates it; dragging still moves it. *Rejected:* a frame
button only (it was there; the flick is the gesture).

**D-291 — Hover lights what a tap lands on, on by default.** The thing under the hovering Pencil is tinted in the accent
(`StageView.showHover`); the sheet wakes; a Pencil near the top wakes the clusters. The point under the tip stays its own
setting, off. Without hover a tap already picks the nearest thing within six points. *Rejected:* lighting faces and
edges now (U6 rebuilds modelling's picking).

**D-292 — Every number is a slider.** `HmmNumberPill` / `HmmScrub` (hmm-kit 0.9): a point of slow drag is a fine step, fast
drags go up to twenty times as far, a tap types on our pad; the Pencil Pro clicks at a range's end. The stage's
dimensions and the object panel's numbers are 44 pt and scrub as one undo step per drag.

**D-293 — Fingers and the Pencil.** Two fingers always move the view (the point under them stays under them, a pinch
zooms toward them, a twist turns); they no longer turn or size the selection. One finger turns half a turn per screen
width on any iPad. A selected thing dragged by a finger lifts a little, slides over the surface under its middle (it
climbs onto things up to its own height) and sits down on release. *Rejected:* carrying a thing that isn't selected (a
drag from any object would leave nowhere to orbit from).

**D-294 — One grammar: a bar per tool, clusters that rest.** Draw has its bar of five; Model and Rig keep theirs. Both
clusters fold to faint rails when a stroke starts and come back on a touch, the Pencil hovering near the top, a panel or
leaving Draw. The Select button went: the lasso is the quick menu's first slot, in the three-finger bar (with Select all)
and on the empty stage's hold menu; one loop, then back. The view corner is Views · Camera · Joystick · Snap: the
timeline comes with Animate, framing with a double-tap or the quick menu. Undo and redo buttons are a Gestures switch,
off.

**D-295 — + Overlay went; titles stick to the camera.** 3D text has *Stick to the camera* (`sticksToCamera`): its place is
read in the shot camera's frame in every evaluated frame, so stage and export agree; switching it keeps it where it was
(a camera is made from the view if there is none). Screen effects at the playhead are in Look ▸ Finish. Existing
overlays still play and stay editable. *Rejected:* a line sending people to Cutaway.

**D-296 — The quick menu changes with the tool.** Lasso · Eyedropper · Eraser ↔ the last brush · Snap · Hide the sheet and
guides · Frame by default (slots refillable, saved under a new key so 0.13's six don't hide the lasso); with Rig: Pins ·
Dots · Mirror the pose · Reset the pose · Save the pose · Show the bones.

**D-297 — One toast system; the eyedropper is Procreate's.** Every message (toasts and the guide line) leaves after two
seconds or on any touch: hmm-kit's `HmmTouches` counts touches from the gesture layer, claiming none. While drawing, a
finger held on a thing shows `HmmColourLoupe` (the colour under it above, the one in the hand below), follows the finger
and takes the colour on lift. *Rejected:* holding anywhere (the sheet's hold menu needs the empty part).

**D-298 — The Pencil Pro clicks in four places.** A snap (sketching, carrying onto a surface), picking a part, each
flipbook frame (flick, duplicate), a slider's end. Elsewhere the UI is silent.

**D-299 — To the ground by the real shape.** The thing's lowest corners (from the stage's world mesh) land on the highest
surface under them, or the ground (`GroundDrop`); a sunk thing comes up. Lights and cameras still drop by their box.
The contact shading already darkens where a thing touches. *Rejected:* boxes (they left things hovering).

**D-300 — Translations still ride along.** CONTEXT now says English only at 1.0, but the catalog check (Italian and Arabic)
is CI's; new strings were translated rather than the check changed in a phase about drawing. The languages phase decides.

## Maquette 0.16 — U6, shape

**D-301 — U6 starts from main, after U5 was tagged.** U5 (PR #36) was merged from a cloud session that couldn't push
tags; v0.15 and hmm-kit v0.9.0 were tagged from the PC first, and the release published the .ipa. U1 (PR #30) still waits
for the first feel recording.

**D-302 — No modes: the Pencil models the selected shape from any tool but Draw.** Over the one selected shape the Pencil
lights the part under its tip; a drag pulls, rounds or moves it; a tap picks it. Fingers keep carrying the thing (D-293),
so with no Pencil the same moves are in Model ▸ Shape, where one finger shapes. *Rejected:* a Model mode for Pencil users
(the Faces, Edges and Corners buttons are what slowed him); fingers shaping in Select (carrying would break).

**D-303 — What's lit is decided by distance on screen.** A corner within 16 points of the tip, else an edge within 11,
else the face under it (`MeshPicking.nearestPart`). One obvious move each: a face pulls along its normal (push/pull as
before), an edge rounds by half the drag's length on screen, a corner moves across the plane facing you through where it
started (grid steps with snapping on). *Rejected:* a list of tools popping up (Shapr3D's, which slowed him).

**D-304 — Every shape is always editable; placed models keep a button.** A blockout shape or a drawing becomes a modelled
mesh quietly on the first touch (as push/pull already did). A placed library model would give up its parts and materials,
so it keeps one deliberate button, renamed *Model it*. *Rejected:* converting placed models on touch.

**D-305 — The part's chip holds the rest.** A face: inset, shell, bridge (two faces), knife. An edge: bevel, round, loop
cut, knife. Corners: merge (two or more), fill the hole. Behind ⋯: grow, shrink, similar, the pivot here. A held Pencil
adds a part to the pick. The chip is docked above the tool's bar, never over the work: the pick's floating numbers (a pull,
a size) stay free to tap (first it floated above the pick and covered them).

**D-306 — Subdivision is Catmull–Clark on whole faces; the Smooth switch is a property.** `subdivision` (0–3) smooths the
shape as it's built, everywhere it's shown; *Make the smoothing real* bakes it. Faces with holes become triangles first;
open borders keep their line and a border's corner stays put, so a half-built shape doesn't shrink from its edge.
*Rejected:* Loop subdivision (triangles: quads are what modellers keep cutting).

**D-307 — Modelled shapes are crisp by default; the smooth angle softens them.** `smoothAngle` (degrees) shades edges
softer than it smooth and keeps the rest crisp; a smoothed shape is smooth all over unless it's set. Flat shading is the
existing `shading` property.

**D-308 — A loop cut runs through four-sided faces only.** The ring stops at a face that isn't a quad or at the open
border, so it never tears a face; cuts are measured from one side of the ring so they line up all round. One cut sits in
the middle; more are spaced evenly.

**D-309 — The knife cuts along the plane its line sweeps from the eye.** Only faces whose cut's middle lies under the
drawn line are cut, each into two whole faces; a neighbour the cut ends on gets the new corner in its side (no T-junction);
a crossed face with a hole becomes triangles first. *Rejected:* loose edges inside a face (the mesh keeps whole faces).

**D-310 — Fill hole, merge and bridge.** A hole is an open border walked into one new face. Merged corners meet at their
middle and faces that collapse go; *Join close corners* welds within a tenth of the project's step. Bridging two faces
removes both and joins their outlines with quads; the one with fewer corners gets more along its longest sides first (its
neighbours too), and the loops start at the corners nearest each other.

**D-311 — Sweep, revolve and loft are rings of the profile joined side to side.** Sweep turns the profile with the path,
the turn that twists least; revolve welds the corners lying on the axis (a profile touching it makes a solid without a
hole); loft walks every outline with the larger corner count, starting at the nearest corners. Open ends close with the
profile. The region is used up, as a pull uses it; the path and the axis stay. Revolve without a line turns around the
region's own left side, upright on its sketch.

**D-312 — Linked copies share a shape, through `perform`.** Things with the same `linked` value change together: a shape
(`setKind`), strokes and cage (`setShaping`), smoothing, the smooth angle, the bend and symmetry. Where each stands, its
size and its look stay its own; a shape whose own scale was baked into it in the same step reaches the others at the size
it had in its own space. *Unlink* lets one go. *Rejected:* a shared mesh asset (a second kind of shape in the format).

**D-313 — Moving the pivot moves the corners the other way.** A modelled shape's corners shift, a group's children shift,
and the thing moves by the same amount, so nothing moves on screen. Presets: the middle of its box, the middle of its base,
or the picked part. A blockout shape becomes modelled first; a placed model can't (it has no corners of its own).

**D-314 — Shapes keep their dimensions: width, height and depth are numbers to type or scrub.** A modelled shape stretches
around its base (height) or its middle (width, depth); other things scale. *Rejected:* typing one edge's length (a CAD
story for the editable history, H1).

**D-315 — Sketch rules, our own solver.** `Sketch.constraints`: parallel, perpendicular, equal, tangent, a locked length
(a line, a circle's diameter, a rectangle's side), a locked angle, a ratio ("twice that"). Lines, rectangles, circles and
arcs are a few numbers each; Levenberg–Marquardt with a numeric Jacobian finds the nearest drawing that keeps every rule,
first with a gentle pull toward the drawing, then exactly. Ends that met keep meeting, judged on the sketch before a curve
changed. Rules that can't all hold are refused with a sentence. Splines and polylines hold still. Core, tested on Linux.

**D-316 — One whole-shape bend per thing, as properties.** `deform` (bend, twist, taper, bulge), `deformAmount` (degrees,
or the change in size; animatable, so keys add themselves) and `deformAxis`, measured over the thing's own box. One handle
on the stage. *Rejected:* a stack of several bends (the brief is one handle each; a stack can come if it's asked for).

**D-317 — The cage is a lattice of 2 to 4 points each way.** Bernstein weights over a box padded 5 % around the thing; a
cage at rest changes nothing; points outside follow its nearest face. It lives in the object's `shaping` and isn't
animated in 0.16 (the bend is). A 4 × 4 × 4 cage moves 50 000 triangles in 25 ms in a release build on the PC's Docker
CPU (CI's number is in the SPIKE step); the iPad's drag is a device check.

**D-318 — Brush strokes are offsets of the surface's corners, kept inline and sparse.** `SculptLayer`: only the moved
corners, base64 in the object's `shaping`, with a fingerprint for caches; strokes made for another number of corners are
left behind. Grab holds the patch it started on; smooth and inflate work on welded points so a surface never tears. A
shape too coarse to brush is cut finer first (the cuts rigging uses); a placed model is brushed as one surface, the one
painting uses, so it's made paintable first. *Rejected:* files under `assets/` (every reader would need a loader);
turning sculpts into modelled meshes (hundreds of thousands of faces in project.json and in every journal line).

**D-319 — One shape stack: built, cut, moved.** `ShapeStack`: a shape is built (smoothed), cut finer for bending, then
moved by its strokes, cage and bend. Moving keeps every corner in order, so paint and rigs are found on the unmoved mesh
(its fingerprint holds still while a bend animates) and drawn over the moved one; placed models' parts are bent over the
whole model's box. The stage, painting, rigging, picking and every export share it.

**D-320 — SPIKE passed: Instant Meshes, vendored.** `Packages/InstantMeshes`: upstream's mesh code (BSD-3-Clause), the
164 Eigen 3.4.0 headers it includes (MPL-2.0, built scalar, so the same input gives the same quads everywhere), and a small
stand-in for the Threading Building Blocks it calls (loops over up to eight threads). A 499 000 triangle sculpt becomes
2 421 faces (73 % quads) in 4.1 s in a release build on the PC's Docker CPU; CI's number is in the run summary, the
iPad's is a device check. Debug builds are slow (Eigen unoptimised), so the everyday tests use small meshes. Fallback (our
own triangle pairing after simplifying) not needed.

**D-321 — Clean up the shape bakes everything and runs off the main thread.** The shape as shown is remeshed; smoothing,
the bend, the cage, strokes and the cuts for bending are switched off in the same step. The command remeshes again from
the same surface (deterministic), so the app and the bridge share one path. *Rejected:* keeping the bend live on the new
mesh (it would bend twice).

**D-322 — The view cube sits in the view corner, above its row.** A small canvas turning with the view: a side tapped looks
from there (top and bottom keep the heading), a drag turns, a double-tap swaps perspective and flat, a hold has the views
and Frame all. Settings ▸ Stage ▸ The view cube hides it, and the views menu takes its place.

**D-323 — The bridge reaches the modelling set through two verbs.** `model` (smooth, subdivide, smoothAngle, flat, bend,
cage, brush, pull, loopCut, knife, fillHoles, mergeByDistance, cleanUp, linkedCopy, unlink, pivot, size) and `profile`
(sweep, revolve, loft). Without pointing, faces are named by the way they face and edges by the axis they run along; a
brush is one dab. The lowey skill learns them.

**D-324 — Schema 15.** Objects' optional `shaping` (cage, strokes) and the `setShaping` command; the `subdivision`,
`smoothAngle`, `deform`, `deformAmount`, `deformAxis` and `linked` properties; sketches' optional `constraints`. Nothing
older changes shape; 0.15 refuses a schema-15 file with its usual message.

**D-325 — Translations still ride along.** The 72 new strings were translated into Italian and Arabic for the catalog
check (D-300); the languages phase decides.

**D-326 — CI's allowance for the block with a hole is 80 s.** Between U5's main run and U6's, every UI test on CI's
shared simulator got 40–70 % slower, U6's code or not (the Home benchmark 60 → 100 s, the rigged tail 32 → 50 s); the
block's taps went from under 45 s to 62–83 s with them. The claim stays under 30 s for a person on an iPad (device
checklist). *Rejected:* dropping the timing (it caught U3's slow pad) and blaming the part chip without measuring (it was
docked anyway, since it covered the pick's numbers).

## Maquette 0.17 — H1, editable history

**D-327 — SPIKE passed: stable parts are face tags handed on by plane.** Every face of a modelled shape carries a tag. A
step hands them on by where its result's faces lie: a face lying in the plane of a face before the step, and inside it, is
(a piece of) that face and keeps its tag; one lying on a face of the step's tool (the prism a hole is cut with, the solid
it was combined with, a shell's cavity) takes that tool face's tag; a face a push/pull moved names the plane it moved to;
anything else is named by the step and its order among the new faces. Booleans, bevels and shells only trim faces inside
their own planes, so this holds through them without asking Manifold for its own ids. A face is referred to by its tag and
its middle (to choose between the pieces of a split face), an edge by its two faces' tags and its middle. On M3's block a
6 mm hole through it and its four upright edges rounded 2 mm, the hole changed to 8 mm in the history finds the four rounds
again and matches the block made with 8 mm from the start (`ModelHistoryTests`); the replay takes 0.2 s in a debug build on
the PC's Docker CPU. The fallback (a replay stops at the first step it can't place and says which) is kept as the failure
path. *Rejected:* Manifold's face ids (they don't reach our faces, which `MeshBuilder` rebuilds from triangles); ids by
index (every boolean renumbers).

**D-328 — The steps live on the object, and the tools run as their step.** `SceneObject.modelHistory`: the shape the steps
start from, the steps, the current faces' tags and a key of the shape they make. Each recorded tool builds its step and
runs it, so the shape and its history can't disagree; when they do anyway (something else changed the shape) the history
is fixed. *Rejected:* rebuilding the steps from the journal (it records results, a mesh per step, not picks and numbers).

**D-329 — What a step is.** Push/pull, inset, bevel, round, shell, a sketch area pulled out of or cut into a thing, and a
boolean (one step per solid combined into the one that stays). Changes by hand (corners, knife, loop cut, merge, fill,
bridge, subdivide, clean up, a scale baked in) aren't steps: the next step starts again from the shape as it is and the
steps before become `earlier`, listed with a lock. *Rejected:* keeping a hand-made change as a stored mesh (a whole mesh per
step in project.json, and a replay still couldn't move it).

**D-330 — Paint and rigs fix the steps at that point.** A painted or rigged thing lists its steps but they don't change,
and later modelling isn't recorded (paint and rigs aren't parametric; the brief says the list stops there).

**D-331 — A sketch step keeps only what made its area.** The curves of the region, in the thing's own space. A cut that
went right through goes through again however thick the shape becomes; the drawing follows the face it was drawn on when
that face moves. Its numbers: the depth (unless it went through), each circle's diameter, each rectangle's sides (changed
about its middle). Its title names the drawn size: "Hole, 6 mm". A pull into a thing whose own scale isn't one isn't
recorded (its steps become fixed). *Rejected:* baking the scale for a sketch pull (it would change 0.16's results).

**D-332 — A recorded step runs on exactly what was picked.** References are for replays; when the step is made, the
picked faces and edges are used as they are, so 0.16's results don't change.

**D-333 — The steps list sits over the scrubber, for the selected thing.** Chips in plain words; tap one for its numbers
as pills; a number is applied when the drag ends or when it's typed (a replay is a boolean per step: per frame it would
stutter on a Tier B iPad); the replay runs off the main thread and lands as one undo step ("Change Hole"); a result whose
thing changed meanwhile is dropped. While the scrubber shows an earlier moment, steps don't change. ⌘Y opens History.
*Rejected:* a separate Steps button (History is where "what happened" lives); live replay while scrubbing.

**D-334 — A replay that can't continue changes nothing.** "Step 2, Round, 3 mm, can't follow the change: That's wider than
the faces beside the edge." in one line; the shape, the steps and undo stay as they were.

**D-335 — The bridge reaches the steps through `model`.** `op: "steps"` lists them in the reply (name, numbers, fixed);
`op: "step"` with `step` (1 is the first listed), `number` (a name or 1-based) and `value` (metres) changes one. The lowey
skill learns both.

**D-336 — Schema 16.** Objects' optional `modelHistory` and the `setModelHistory` command; linked copies share it with
their shape. Tags and the shape key stay under 2^53 so any JSON reader keeps them exact. 0.16 refuses a schema-16 file
with its usual message.

**D-337 — Translations still ride along.** The 8 new strings were translated into Italian and Arabic for the catalog check
(D-300, D-325).

## Maquette 0.18 — U7, texture

**D-338 — A layer holds maps; a stroke paints one.** A paint layer keeps its colour as before (`tiles`) and, beside it,
tiles for roughness, metal, glow, bumps and fur, and a mask (`maps`). Value maps are grey (white = 1), glow a colour; where
a map is clear, the thing's own value shows. The brush paints one map at a time (Layers ▸ the map chips, with a value for
the value maps); a fill of a material writes all its maps at once. The GPU keeps a texture per layer and map only for maps
that have tiles, and composites map by map. *Rejected:* one channel per layer (a material would be five layers);
Substance's every-layer-every-channel (five textures per layer on a Tier B iPad).

**D-339 — The brush and material library files migrate like the rest.** The device's `brushes.json` had no migrations,
so every schema bump since 0.5 made it unreadable and the library fell back to the built-ins (the person's own brushes
were lost on the next save). Both library files now step through every version unchanged; a test reads a 16 file.

**D-340 — Fill layers make their tiles from what they're made of.** A colour, a material (a frozen copy, so the project
carries it), or wear. The tiles are made when the fill is added or changed (off the main thread; a plain colour or a
patternless material is one tile repeated, so one small file per map). A fill isn't painted on: its mask is (the brush
says so in one line). *Paint it on* (a material's hold menu) adds the fill behind an empty mask and puts the brush on the
mask: the Substance way, in two taps.

**D-341 — Materials are numbers, procedural.** Two colours, roughness, metal, glow, a pattern, its size in metres, how
strongly it shows, and bumps. Solid patterns (noise, wood, marble, stone, concrete, leather, rust, sand, brushed) are 3D,
so they wrap any shape with no seam; laid ones (bricks, tiles, planks, weave) blend over the three planes by how the
surface faces. Seeded arithmetic: the same everywhere, testable on Linux. *Rejected:* bundled photo textures (licences,
size, and the Looks are drawn, not photographed).

**D-342 — Our own library of 24.** Oak, pine, walnut, floorboards; brushed steel, aluminium, gold, copper, cast iron,
rusty metal; glossy plastic, rubber, cotton, denim, leather, glass, ceramic, neon; stone, marble, concrete, brick, tiles,
sand. Glass is glossy and pale, not see-through (the Looks have no refraction; a later Look may).

**D-343 — The Material Studio in the Brush Studio's grammar.** The ball on top changes as you go; pages Look, Surface,
Pattern, Bumps, About. The ball is drawn on the CPU (`MaterialPreview`), so the library shows without the renderer.
Edits reach the library at once (`materials.json`, newest of your own first); things already filled keep their copy.

**D-344 — PBR sets come in by their names.** basecolor/albedo/diffuse, roughness (gloss is turned into roughness), metallic,
normal (a DirectX one's green flipped), height/displacement, emissive, AO; stored as PNG in the library and laid on the
surface by triplanar projection, so they need no unwrap and show no seam. Pictures are copied into the project when a
fill uses them.

**D-345 — Wear from the shape's own bakes.** Ambient occlusion (24 rays a texel against the shape, at 256 texels: it's soft)
and the distance to sharp edges (faces meeting at more than 25°, outer and inner). Dirt gathers where it's enclosed and
in inner creases, worn edges on outer ones; noise breaks the line so it never reads as a gradient; Amount moves the
threshold. A bake is made once per shape and kept while the app runs.

**D-346 — Smudge on paint works in the texture.** Each Pencil sample is found on the surface (a ray against the paint
mesh), becomes a dab in texels sized by how many texels a stage point covers there, and drags the paint under the last
dab forward (premultiplied, so clear paint carries no colour). The changed tiles go to the GPU as the stroke goes and
are kept as one step. *Rejected:* smudging in screen space (the stroke texture can't read what's already painted).

**D-347 — Mirrored painting draws the stroke twice.** The second projection flips the object's own space across the chosen
axis, so each point takes the paint its mirror image would get, even on the side facing away. Stored on the paint
(`mirror`), so it travels with the thing.

**D-348 — A decal is a picture pressed on from in front.** Tapped onto the surface, it lands on what faces it within a box
its width deep, fading where the surface turns away; it's its own layer ("Decal"). The camera projection stays as
Project a picture.

**D-349 — Seams are marked edges that close an area.** Seams mode marks the outline edge of the flat face under the
Pencil (pending ones in amber), Cut lays the surface out again carrying the paint. Triangles are grouped across every
edge that isn't a seam and xatlas never lets a chart span two groups, so a seam cuts where it closes a loop (or meets the
border); an open seam cuts nothing. Stored as segments in the object's space, so they survive a re-triangulation.
*Rejected:* splitting vertices (xatlas joins vertices in the same place).

**D-350 — Texture size per thing: 512, 1024, 2048, 4096.** Every layer, map and mask resampled; baked normals dropped (bake
again at the new size). The device check covers 4096 on a Tier B iPad.

**D-351 — The flat view paints through the same GPU stroke.** Dabs are drawn in texture pixels onto the layer, kept where
the unwrap uses the texel; it's a sheet (not a cover) so the stage keeps drawing under it, and the picture refreshes after
each stroke.

**D-352 — Normals baked from a detailed copy.** For each texel of the light surface a ray from 5 % of its size above looks
down for the detailed surface (then from below); its normal goes into the texel's tangent frame (x along u, y up the
picture, as glTF reads). Stored on the paint (`normalMap`, `normalsFrom`), dropped when the shape changes. A dense sphere
stands in for the Nomad fixture (D-275): in the Core test the light copy's baked normals are under 4° from the true
shape and under half the facets' error; the engine test renders it closer to the sculpt than the bare facets.

**D-353 — How deep bumps are.** On the stage a unit of height is a centimetre (the slope across the screen tilts the
normal, no tangents needed); in an exported normal map a unit rises over 6 texels at 2048 (scaled with the size), close
to the stage's look on a thing a metre across.

**D-354 — Every map leaves.** glTF: the colour, roughness and metal packed as glTF wants (green and blue), emissive and a
normal map with tangents. USDZ: a reader per map into UsdPreviewSurface. PNG sets: the new Maps (PNG) format writes
`<name>_color.png` and each painted map. Where nothing is painted a map takes the thing's own value. Exported maps are the
person's own work; the built-in materials are ours and carry no licence of anyone else's.

**D-355 — Fur: four properties, shells and cards.** `furLength`, `furDensity`, `furStyle`, `furDroop`. Shells draw the
surface again outward (24 on Tier A, 14 on B, 9 on C; exports draw 24), keeping each cell's strand thinning to its tip; a
Fur map lengthens or bares it. Cards are crossed strips Core grows on the surface. 3D files get 8 cut-out shells or the
cards. On the stage cards aren't grown on skinned surfaces yet (they'd stay in the rest pose; backlog).

**D-356 — Painted colour leaves three ways.** Texture (as before), vertex colours (glTF's COLOR_0; the texture is left off,
since glTF multiplies them) or a palette (each face one swatch of a small picture). Export ▸ glTF ▸ Painted colour.

**D-357 — The faces brush fills a flat face.** A tap fills every triangle in the plane of the one under the Pencil and
touching it, a texel past its edge, with the colour (or value) in hand: low-poly colouring on any shape.

**D-358 — Hatched shadows beside halftone.** Lines in the shadow band, crossed where it's darkest, thickening with the
darkness, spaced as the halftone dots are. A Look setting (`comic.hatching`), saved only when it's on.

**D-359 — The bridge paints.** `{"do": "paint", "op": …}`: color, material, wear, decal, faces, layers, mask, mirror, size,
seams, bakeNormals, fur. The compiler reads the project's files and returns the files its command names; the app writes
them before applying (one undo step). A material fill at 2048 takes a moment in the proposal.

**D-360 — Dropping onto a thing.** A colour becomes the thing's own colour (under any paint); a material becomes a fill
layer on top. Swatches and materials drag out of the picker.

**D-361 — The colour picker is the kit's (hmm-kit 0.10).** Procreate's disc, values (HSB, RGB, hex) and saved palettes,
the colour before and the colours used lately, with the scene's palette first; Maquette adds Materials as a fourth page.
A swatch of the scene's palette stays bound to its slot.

**D-362 — Surface joins Draw's bar while painting a thing.** Brush · Smudge · Erase · Layers · Colour · Surface (six, the
most a bar holds). Surface holds the faces brush and seams, wear, a decal, mirror, the texture's size, the flat view,
normals from a sculpt and fur: one deliberate step past the layers.

**D-363 — Schema 17.** Layers' optional `maps` and `fill`; paint's `mirror`, `normalMap`, `normalsFrom`; the surface's
`seams`; tile changes' `map`; the fur properties; the Look's `comic.hatching`; the `materials` library file. A mask's tiles
change only a mask that's there (masks come and go with their layer), so undo is exact. 0.17 refuses a schema-17 file with
its usual message.

**D-364 — Translations still ride along.** The new strings were translated into Italian and Arabic for the catalog check
(D-300, D-325, D-337).

## Maquette 0.19 — P1, physics

**D-365 — SPIKE passed: Jolt Physics 5.6.0, vendored.** `Packages/Jolt`: upstream's `Jolt/` (MIT) minus the GPU compute
back ends and shaders, behind a C face (`JoltBridge.h`: rigid bodies, joints, soft bodies), the way Manifold is. It builds
for the iPad in CI's app build and on Linux in the test container. The 500-body stack (a 10 × 10 × 5 tower of boxes) stands
and steps in 1.2 ms per 60 Hz step in a release build on the PC's Docker CPU (14 ms in a debug build); CI's number is in
the run summary, a Tier B iPad's is the device check. Fallback (our own impulse solver) not needed.

**D-366 — One run, the same everywhere.** Single-threaded, `JPH_CROSS_PLATFORM_DETERMINISTIC`, `-ffp-contract=off`: the
same input gives the same frames on the iPad, the simulator and Linux. A run's input (`PhysicsInput`: the scene where
things start, the meshes of real things, the paths of what follows its keys) has a stable fingerprint; the stage and an
export with the same fingerprint show the same frames. *Rejected:* Jolt's job system (threads change the order of
contacts, and with it the run).

**D-367 — Materials in words, mass from the real volume.** Wood, steel, aluminium, stone, concrete, glass, ice, plastic,
rubber, foam, cardboard, cloth, jelly, each a density (kg/m³; cloth kg/m²), a grip, a bounce, a body (rigid, cloth,
jelly) and whether it breaks. Mass is the density times the volume Jolt measures of the body's shape. Mass, grip, bounce,
breaking, stiffness and a start speed can be typed, one step deeper.

**D-368 — What shape a thing has in the run.** A cube is an exact box, a round sphere a sphere, a round cylinder a
cylinder; anything else that moves is its convex hull; what stays or follows its keys keeps its triangles (stairs, a
glass); a real group is its parts' hulls glued into one body. *Rejected:* convex decomposition (a library, slow on big
meshes, and a falling cup reads the same as its hull).

**D-369 — Real lives on the thing, physics on the scene.** `SceneObject.physics` (material, how it moves: falls, stays,
follows its keys, and the numbers); `Scene.physics` (gravity by name, wind with gusts, a solid ground, when things start,
the joints). A joint's anchor and axis are in its first thing's own space, so moving the thing moves the joint.
*Rejected:* joints as objects in the outliner (they're relations, like a group).

**D-370 — The run is made in the background and played as far as it's gone.** Every frame of the timeline from the start,
Jolt stepped at 60 Hz or more; the stage takes a few frames at a time; playback waits at the edge of what's made rather
than show things that haven't moved; the last three finished runs are kept, so undo and redo don't wait. Runs live in
memory; reopening a project makes it again in the background. *Rejected:* a run cache on disk (a project would carry
megabytes that its own scene can make again).

**D-371 — How a run reaches the picture.** The Animator takes it as live values (places, ragdolls' joint turns) under
anything performed live; cloth, jelly and fluids arrive as shapes the renderer draws instead of the thing's own; a broken
thing is hidden and its pieces stand in the shown scene. Everything that renders (the stage, stills, exports) goes through
the one ShotBuilder, which carries the run.

**D-372 — Keep it.** A run becomes position and rotation keys (simplified, one undo step), ragdolls also get their joints'
keys, and the things that fell then follow their keys (they still push what they meet). A broken thing's pieces become
things of their own that appear when it breaks. Cloth, jelly and fluids aren't keys: they keep playing from the run.
*Rejected:* storing soft and fluid runs as files to "keep" them (a run is deterministic; nothing is lost by remaking it).

**D-373 — Ragdolls from any rig.** A capsule along each bone (its mass the thing's, shared by length), joined to its
parent's by a cone of 52° and a twist of ±26°; one ragdoll's parts never collide with each other. Its run writes the rig's
own `bone.<joint>` values, so Keep it gives ordinary pose keys. *Rejected:* filtering only neighbouring parts (Jolt's way;
our rigs have no limb volumes to tell, and limbs crossing in a short fall is rare).

**D-374 — Cloth and jelly are Jolt soft bodies.** The mesh is welded and cut finer until it bends (at most 1 600 vertices
for cloth, 900 for jelly), its vertices sharing the real mass; jelly is kept full by pressure, its stiffness a slider;
cloth can hang from its top edge. Wind pushes each face by the air moving across it (`JBSoftBodyApplyWind`). A bent surface
shows the thing's colour; paint isn't carried onto it yet (backlog).

**D-375 — Breaking.** A breakable thing is cut ahead into Voronoi cells intersected with it by Manifold, so the pieces fit
exactly (a surface that isn't solid splits by its triangles into shards); it breaks when one step changes its speed by
more than its material takes (glass: about a metre's fall). Pieces are saved to the nanometre so Keep it travels exactly.

**D-376 — Forces.** Wind is air: drag ½ρCA|v|v on each thing (A from its volume), so foam flies and steel doesn't; a fan
pushes the same way where it points; a pull and a whirl act on mass. Particles feel the scene's wind through their drag
and land on the ground.

**D-377 — Small-scale fluids.** Water is position-based fluid (Macklin & Müller 2013), at most 5 000 drops, each step
small enough that no drop crosses half its spacing; it meets every surface in its box through unsigned distance fields
(moving ones followed), loses a little speed where it touches, and doesn't push things back. Its surface is a blob field
cut by marching tetrahedra, made for each frame of the run, so playing it costs nothing (0.01 ms a frame). Neighbours come
from a dense grid of half-kernel cells over where the drops are, and many small steps take one solver pass each (Macklin
et al., "Small Steps"): a glass filling with a quarter litre bakes at 360 ms a frame in a release build on the PC's
Docker CPU, in the background. Smoke and fire are stable fluids
on a grid 40 cells along the box's long side, drawn as soft puffs in the scene's Look. The box is at most 4 m a side.
*Rejected:* grid water (FLIP: more code, the same look at a glass's scale); two-way coupling (a later step, if boats ask).

**D-378 — Settle and "does it stand?".** Settle is a short run of the one thing, damped, until it sleeps. Does it stand:
the centre of mass of the things (their materials' masses) over the outline of where they touch what's under them (the
points within 3 mm of the lowest); the answer in one line and the centre, a plumb line and the footprint on the stage. No
structural analysis (CONTEXT §10.11).

**D-379 — The real sun.** NOAA's solar position (Meeus) with refraction, within 0.5° of NREL's SPA reference; stored on the
Look's lighting (`realSun`: place, latitude, longitude, the clock's offset, date, time, which way north is); a shadow study
runs a span of hours across the timeline. Ten cities to start from, or typed coordinates. *Rejected:* the device's
location (a permission prompt for something a city list does).

**D-380 — Exports.** Video and stills wait for the whole run (the stage's, when it's finished for the same scene). glTF,
Blender and FBX bake the run into keys and keep how things move as made, with colliders in OMI_physics_body and
OMI_physics_shape (hulls for what moves, triangles for what stays), which Godot 4 reads; Khronos' own physics extension
replaces them once ratified. CI opens the dropped cube in Godot 4.3: a rigid body of 700 kg on a static floor, animated.

**D-381 — Homes.** Real is a row on the object panel (with Look and Shape); Physics is behind the scene's name; forces and
fluids are tiles in Model ▸ Add beside the particle effects, the fluids named Pour water, Splash, Billowing smoke and
Flames so they don't read as the particle Smoke and Fire; the real sun is in Look ▸ World's fine tuning (the sun's height
and direction step aside while it's on); Settle joins To the ground in the object's menu; the menu bar has a Physics menu
(⇧⌘J real, ⌥⌘J not real, ⌘J settle, ⌥⌘U does it stand, ⇧⌘K keep the run). Nothing moved.

**D-382 — The bridge's `physics`.** `real`, `unreal`, `scene`, `joint`, `unjoin`, `force`, `fluid`, `keep`, `settle`, `stand`,
`sun`; the compiler runs a whole run for `keep` with the app's meshes (`ScriptContext.mesh`). The lowey skill has a
physics module.

**D-383 — Schema 18.** Objects' optional `physics`, scenes' optional `physics`, the `force` and `fluid` objects, the
`setPhysics` and `setScenePhysics` commands, the Look's `realSun`. 0.18 refuses a schema-18 file with its usual message.

**D-384 — Every tier, the same run.** The run doesn't depend on the device: a Tier B iPad plays the same frames, made a
little later. The benchmark gates are the 500-body stack (D-365) and a glass filling with water (`PhysicsSpikeTests`, a
release build only, its bake time in CI's summary; 500 bodies take 2.1 ms a frame through the whole Core path); the device checklist times both on the iPad.

**D-385 — Translations still ride along.** The new strings were translated into Italian and Arabic for the catalog check
(D-300, D-325, D-337, D-364).

## Maquette 0.20 — K1, characters

**D-386 — One view-turning rate (K1 0.1, device note).** Hesham: the view sometimes turned faster "in another mode".
Three places turned it, each at its own rate: the stage's one-finger orbit at half a turn across *the stage view's*
width (so it changed with the iPad's orientation and the window's size), the Director view's camera at a fixed 0.15° a
point, and the view cube at 1.2° a point (eight times the stage, and deaf to the speed setting). All three now take one
rate, `AppSettings.orbitDegreesPerPoint`: half a turn across the *screen's* long side, times Settings ▸ Speed. A twist
stays one to one (it's direct manipulation, like the anchored pan). *Rejected:* a rate per tool (the law is one
sensitivity everywhere, CONTEXT §10.11).

**D-387 — A part is a thing with a job.** Parts are ordinary things (meshes from the set, drawings, anything modelled)
with `SceneObject.part`: their job (head, eye, brow, mouth, nose, ear, hair, body, arm, leg, tail, wing, extra), side,
style, piece and limb. Hinged parts are pieces (an arm is upper arm, forearm, hand), each a child of the character's
group so it rides its own joint; face parts, ears and hair are children of the head. A made character is a group with
`characterStart`. *Rejected:* a recipe rebuilt on every change (the Puppet's way: a part moved, painted or remodelled by
hand would be undone by the next change).

**D-388 — Our own part set.** Every part is built by our code in the house kit's look (chunky, softly rounded,
toy-scale): heads round/oval/square/bean, eyes round/dot/sleepy/big (with pupils that look), brows line/thick/arched,
mouths oval/grin/beak, noses button/long/snout, ears round/pointy/floppy/cat, hair short/spiky/tuft/long/mohawk, bodies
bean/box/pear/round/long, arms tube/noodle/chunky, legs tube/stubby/paw/hoof, tails thin/bushy/fin, wings
feather/bat/bug, extras horns/antennae/hat/glasses/bow. No Adobe puppets, no Mixamo (CONTEXT §10.11).

**D-389 — Parts attach to any thing.** Adding a part to a thing that isn't a character makes the thing the body of a new
character where it stands (a teapot gets hands, a rock gets eyes). Paired parts come as a mirrored pair while Mirrored is
on; a part added again is another one (a third eye above, a second pair of arms lower down). On a creature with no head
or body, the first eye is one big eye unless a style was picked.

**D-390 — The rig builds itself from the jobs.** The maker places U4's dots where the parts hinge (`CharacterAutoRig`): a
person gets the humanoid joints by their standard names (hips, spine, chest, neck, head, shoulders, upper and lower arms,
hands, legs, feet, toes) and the humanoid standard, so every humanoid clip plays on it; four legs and wings get the names
`BodyGuess` uses; a bodyless creature gets one joint. Every change to the parts (adding, restyling, removing, a
proportion, a part moved by hand) rigs it again in the same undo step. A mark moved by hand in Rig holds until the parts
change. *Rejected:* keeping hand-moved marks across part changes (which mark belongs to which new piece is a guess).

**D-391 — Pieces ride their joints.** A made character's pieces are rigid: each rides one joint, a dot hinges two
pieces (U4's groups). *Rejected:* one skinned mesh with bone heat (soft elbows, but the parts would stop being separate
things to restyle, paint and remodel); a skin per part is in the backlog.

**D-392 — Face states are bends of the part.** A state is a few numbers (open, wide, round, smile, lift, tilt, close) in
the part's own size, applied to whatever mesh the part has, so it works on a drawn or modelled part too and survives
remodelling. Only states the person changed are stored (`CharacterPart.states`). On the stage and in exports the bent
shape arrives like a physics run's bent surface (`SimulatedShapes`). Engines get each state as a blend shape (the bend of
the exported corners). *Rejected:* per-vertex offsets (they break when the part is remodelled).

**D-393 — Fourteen mouths.** The mouth's states are Adobe Character Animator's 14 (neutral, ah, d, ee, f, l, m, oh, r,
s, uh, w-oo, smile, surprised). The pronouncing dictionary is built again from CMUdict with one letter per shape, so lip
sync reaches 12 of them from words (smile and surprised come from the face and from keys); the nine Rhubarb shapes are
read from those, so Blobs, swap sets and the jaw keys work as before. Lip sync keys `mouthShape` beside `mouth`; the
live voice sets it; face capture reads one from the jaw, width, smile and brows. A drawing made a state's drawing shows
in its part's place while that state is on.

**D-394 — Who moves which face part.** Eyes blink and their pupils look through the face rig (as before); mouths and
brows bend through their face states, so a made mouth or brow has no face-rig role and the two never move it twice.

**D-395 — Say a line.** Typed words are laid out from the playhead at about 150 words a minute (a long word longer, a
breath at commas and full stops) and lip-synced, with no voice; the timeline grows to hold the line. A storyboard, a game
clip or a recording planned for later gets a talking character now.

**D-396 — Proportions change the parts as they stand.** Head bigger (its scale, the face with it), legs and arms longer
(the upper pieces stretch, hands and feet keep their size, the pieces below follow), the body taller (what sits on it
rises with the height it sits at), the waist narrower (limbs move in with its sides), the whole height. Longer legs lift
everything by as much as their lowest point went down, so the feet stay on the ground. Handles on the stage (head, feet,
hands, the waist's sides) while Proportions is open, and the measures in metres as numbers to drag or type; one drag is
one undo step and the rig follows when it ends. With Mirrored off a limb's handle changes its own side.

**D-397 — Act it out.** Film yourself (the system camera, front camera first) or pick a video; Apple's on-device 3D body
pose (`VNDetectHumanBodyPose3DRequest`) reads every frame in the background with progress; each bone of the humanoid is
turned to point where the person's matching bone points (the least twist from its parent), the hips take the person's
facing and lean, and the character travels as the hips do, scaled by its leg length over theirs. The first frame is
turned to face front, so the pose reader's own frame doesn't matter. As in a mirror is on by default. Keys land from the
playhead and replace that stretch. People only. *Rejected:* streaming the live camera (a recording reads every frame
reliably and is acted again by filming again); acting for four legs (it would need an animal pose model; backlog).

**D-398 — Game outputs are GLB for all three engines.** Godot reads glTF natively, Unity through glTFast, Unreal through
Interchange. The skeleton is named for the engine: Godot and Unity read the humanoid as "Hips", "LeftUpperArm"…
(Godot's humanoid profile and Mecanim both map those); Unreal gets the mannequin's names ("pelvis", "upperarm_l",
"calf_r", "ball_l"…) under a `root` bone on the ground. Each piece's corners follow its joint fully; mouths and brows are
their own meshes on the same skin with their states as blend shapes (`extras.targetNames`); the clips are named: what the
character does on the timeline ("Timeline": its keys, clips and lip sync as blend-shape weights) and, for a person, the
ten humanoid clips. Lower-detail copies at a half and a quarter of the triangles are named `_LOD1` and `_LOD2`; a capsule
around the standing character is an OMI collider; the top node carries its real size in metres. *Rejected:* FBX for
characters (ours writes one skin, without blend shapes or several meshes).

**D-399 — "Retargets in Godot", as CI checks it.** A made person's GLB opened in Godot 4.3: every bone Godot's humanoid
profile needs is in the skeleton under the profile's name and hangs from the profile's parent, a `BoneMap` over
`SkeletonProfileHumanoid` finds them all (21 mapped, the 17 needed), its named clips are there and Walk moves its bones,
and its mouth has 13 blend shapes. Run locally in Docker before CI.

**D-400 — Sprite sheets.** Frames are drawn by the stage's renderer in the scene's Look, from a flat camera at the
character's height, on a clear background, the character alone; south looks at its face and east faces the picture's
right. A cell is the largest frame, each frame sitting at its bottom middle. The JSON is Aseprite's hash form with a frame
tag per strip ("walk_E"); a Godot SpriteFrames (`.tres`) comes with it; all three in a zip. CI packs frames from a tiny
CPU test rasteriser and opens the sheet in Godot's AnimatedSprite2D (what's checked is the packing and the import).
Pixel art: each pixel the colour most of its block has, up to 16 colours found in the frames (median cut), solid or
clear, and a one-pixel outline. A turnaround is front, three-quarter, side and back on white.

**D-401 — Homes.** The Library's Rigs page is now **Characters** (CONTEXT §10.11: Things · Characters · Motion · Yours): New
(the five starts), Ready-made (Blob, Me, Puppet, moved from Things) and everything with a skeleton. The maker is the object
panel's character section: the parts (a tap adds one, a hold offers its styles, Mirrored), the picked part's styles and
Take it away, and one step deeper Face, Proportions, Say a line, Act it out (people) and For games (a sheet). Any thing's
panel has Give it parts; a drawing or a modelled thing near a character has Make it a part. The menu bar's Character
menu: ⇧⌘C New Character…, ⌥⌘P New Person, ⇧⌘E Export for Games…. The layout is still before 1.0; nothing else moved.

**D-402 — The bridge.** The `character` verb gains `op`: new, add, style, remove, assign (a part, or a state's
drawing), state (bend or reset), proportion (by a factor or to metres), say, rig; changes to parts rig it again in the
same step. Game exports stay in the app (where a file goes is the person's choice). The lowey skill's characters module
learns it.

**D-403 — Schema 19.** Objects' optional `part`, the `setPart` command, the `characterStart`, `mouthShape` and
`browState` properties. 0.19 refuses a schema-19 file with its usual message.

**D-404 — Every tier.** Parts are a few hundred triangles each, so making, rigging and bending faces is light on any iPad.
Sprite sheets and turnarounds are drawn off the stage with progress; reading a video runs in the background with progress.
The device checklist times reading a ten-second video on the iPad.

**D-405 — Translations still ride along.** The new strings were translated into Italian and Arabic for the catalog check.

**D-406 — No kit change.** Nothing here is something Cutaway needs (its people are footage, not 3D characters).

## Maquette 0.21 — A1, animate & export

**D-407 — A drawn motion is keys, timed by the drawing.** Animate ▸ Path: the Pencil draws where the selected thing goes,
and the stroke becomes position keys (and rotation keys while it faces the way) laid from the playhead. Each Pencil
sample's own timestamp times them, so the thing moves at the speed it was drawn and the motion lasts as long as the
drawing did. A time-synchronous Douglas–Peucker keeps a key wherever the line needs one to stay within 5 mm (or 0.2 % of
its size) of where it was drawn *at that moment*, so at every drawn moment the thing is there within a frame (Core test).
Keys of those properties already in the stretch go; the timeline grows to hold it. *Rejected:* a path object with its own
timing curve (a second kind of motion beside keys, which the dope sheet, the graph, Keep it and every export speak);
resampling to a steady speed (the drawing's timing is the point; Even speed is one tap away).

**D-408 — Where a drawn path lands.** On the surface under the tip (picked once per frame of samples from the ID buffer,
the moving thing's own surface ignored, only surfaces facing up), else on the level it last stood at; the pivot rides as
high above that as it does when the stroke starts, so a car drives up a ramp and a bird keeps its height. *Rejected:* a
ray per sample (a GPU round trip at 240 Hz); paths up walls (a path climbs ramps, not walls).

**D-409 — Facing the way it goes, leaning into turns.** The front is +Z (the models' convention, as Follow path uses);
the top leans toward the turn's centre by the turn's pull against gravity (a bike's lean, atan(v²/rg)), at most 35°;
characters stay level and lean a third as much (a runner). Where it stops it keeps its heading; before it first moves it
already faces the way it will go. Both are on by default, two switches on the path's chip. *Turn its front* adds a
quarter turn to every rotation key, for a model whose front isn't +Z. *Rejected:* asking which way the front is first
(a decision wall).

**D-410 — Retiming by dragging.** The path's chip shows how long the motion lasts as a number pill: drag to stretch or
squeeze it, tap to type. *Even speed* moves every key to where it lies along the way (a stop disappears). A key dragged in
the timeline or a dot on the stage still retimes or reshapes one moment. *Rejected:* timing ticks along the path to drag
(the timeline's job done a second way on the stage).

**D-411 — Animate has a bar like every tool.** Path · Look at · Pick up · Properties · Ghosts · Dope sheet: six, the most a
bar holds. Animate still calls the timeline. With no verb chosen the Pencil picks, moves and poses things and keys add
themselves (U2). A making tool puts Animate away; the Animate button brings a folded timeline back before it puts Animate
away. The verbs are also in the Timeline menu (⌥⌘4 Path, ⌃⌘L Look at, ⌃⌘P Pick up, ⌃⌘G Ghosts, ⌃⌘D the dope sheet).

**D-412 — The timeline shows motion.** In the Motion style a thing's row is 46 pt, with its icon in its own colour and a
filled curve of how much it moves at each frame (travel, turn and growth from its keys and its parents', scaled to its
fastest moment), a dot a frame once frames are 9 pt wide. Zoomed that far every row shows its frames as cells (a hairline
between them, every other faintly shaded). *Rejected:* a picture of the thing per frame (a render per cell; the curve says
when it moves at a glance).

**D-413 — The dope sheet is a style of the same timeline.** Every animated thing's tracks are listed under it, rows of
30 pt, the same keys and gestures; Animate ▸ Dope sheet switches, remembered on the device. *Rejected:* a separate sheet
(two places to edit the same keys).

**D-414 — Ghosts while scrubbing.** Dragging the ruler shows the selected thing three moments either side, a fifth of a
second apart, tinted as the onion skin is (red before, green after); on by default (Animate ▸ Ghosts). The selected thing's
path is drawn whenever Select or Path is in the hand. *Rejected:* ghosts of everything that moves (clutter, and a render
per ghost per thing).

**D-415 — Pick-up and hand-off are holds.** From a moment a thing rides a holder (a thing, or a joint of a skinned rig: the
nearest one, a hand when one is about as near) the way it sat then (its grip, in the holder's space). A hold by someone
else is a hand-off; a hold with no holder puts it down where its last holder had it at that moment, worked out as it plays,
so moving the hand later moves where the cup is left. Holders go first, so a tray carries its cups; picking up refuses a
loop and a thing's own parts. Deleting either thing deletes its holds. *Rejected:* reparenting (it moves the thing in the
outliner and loses where it was before and after); baking keys at the pick-up (moving the hand later would leave the cup
behind).

**D-416 — Look at is a property.** `lookAt` names a thing: a character turns its head (up to 70°, the neck's reach) and
its face parts ride along; anything else turns whole and a camera points its lens. Keyed, a new target turns the look over
a quarter of a second. From the bar the first tap sets it for the whole shot, a tap after the start switches from the
playhead, a tap on the empty ground stops looking. *Rejected:* the Look at behaviour (it turns the whole character).

**D-417 — Animate any property.** Animate ▸ Properties lists what the selection can have keyed (place, turn, size, shown,
opacity, then its kind's: colours and finish, a light's, the lens, reveal, an emitter's rate, a face's channels), and one tap
keys it at the playhead as it is; after that, changing it keys itself. *Rejected:* a key button beside every number of every
panel (an advanced control beside each basic one).

**D-418 — Export asks formats first.** Video · Picture · 3D · Paper, then the format (MP4, HEVC, ProRes 4444, GIF, PNG
frames, Render passes, Captions; PNG, Render passes; glTF, FBX, USDZ, OBJ, STL, 3MF, Blender, Maps, the Look as a shader;
PDF), then its named presets; the last format and preset are remembered. A format this iPad or scene can't make isn't
shown (ProRes without the media engine, FBX without a rigged thing, Maps without paint, Captions without a transcript).

**D-419 — A 3D preset is a real difference.** glTF ▸ for Godot leaves cameras and lights out (the engine brings its own)
and keeps the colliders; for the web writes painted colour as vertex colours, no colliders; for Blender and 3D apps keeps
everything. FBX ▸ for Unity names the joints for Unity's humanoid, for Unreal for the mannequin. Every animated format bakes
behaviours, holds and looks into keys (`MotionBake`), as physics was. *Rejected:* an FBX in Unreal's Z-up axes (both engines
turn a Y-up FBX on import; the joint names are what retargeting needs).

**D-420 — ProRes 4444 where the iPad writes it.** Offered when the kit's `VideoEncoder.canEncode` says so (0.11): always a
.mov with an alpha channel (opaque when the background is drawn), so its check expects alpha. Transparency on the other
video formats picks HEVC with alpha.

**D-421 — Render passes.** Colour (premultiplied, transparent), alpha (a grey matte), depth (16-bit grey: white near, black
far or empty; near and far in metres set by the first frame and kept for the sequence) and masks (each thing a flat colour
from its id, the same in every frame and export), with `passes.json` giving the depth's range and each mask colour's thing.
Depth and masks are the renderer's own prepass, pixel for pixel; with Final the colour is Final's and the other passes come
from a plain draw of the same moment. *Rejected:* EXR (no writer on iOS without a library; a 16-bit PNG opens everywhere);
Cryptomatte (it needs EXR).

**D-422 — Final.** Eight moments over half a frame (a 180° shutter) averaged: motion blur. Each drawn at twice the file's
size up to 4K and brought down with a Lanczos filter (vImage): anti-aliasing past the preview's MSAA. The sun's shadow map at
4096, twice the full preview's. Water's surface drawn twice as finely from the same drops (a run of its own,
`PhysicsInput.surfaceDetail`). An option beside every preset that renders; slower, and it carries on in the background like
any export. *Rejected:* velocity-buffer motion blur (the renderer has no per-object velocities; a pass to keep right forever).

**D-423 — Every scene, every shot.** "Every scene, one file each" (Video, Picture, Paper: the open scene as it is, the others
as last saved) and "Every shot, one file each" (the stretches between the timeline's camera cuts) are one job with one
progress, in the background as before. "All clips" are the shots: a character's clips already leave together in the game GLB
(D-398). *Rejected:* every scene for 3D files (another scene's physics run isn't made until it's opened).

**D-424 — Only the selection, a transparent background.** Video, Picture and Paper draw only the selected things (and what
they hang from); 3D files write only them, as before. Transparent background is a switch for everything that renders.

**D-425 — Render on a computer.** The Blender package is Blender ▸ Render on a computer, and its row says Blender renders it
close to the Look, never identical.

**D-426 — The Look as a shader.** Godot gets `maquette_<look>.gdshader` (the bands in `light()`, so Godot's own lights and
shadows drive it; the shadows' hue shift, the rim, stepped highlights; faceted and Clay variants),
`maquette_<look>_outline.gdshader` (an inverted hull of constant width on screen) and a `.tres` material joining them by
relative paths; Unity's URP gets one `.shader` with the lit pass (the main light and its shadows, the extra lights) and the
outline pass. Both carry LICENSE.txt ("use them in anything, commercial included") and README.txt (what travels, and what
stays: halftone, grain, misregistration, boiling lines, contact shading), zipped and named for the person ("Ink Look for
Godot.zip"). CI renders the Ink material in Godot 4.3 (GL Compatibility on Mesa's llvmpipe, in the Ubuntu 24.04 container
the golden was recorded in) and compares the frame with the golden: a mean of at most 3 levels, 98 % of pixels within 24.
Unity has no licence-free headless run, so its shader is checked on a computer (backlog).

**D-427 — Paper is our own PDF.** A pure-Swift writer (tested on Linux; JPEG pictures embedded as they are, Helvetica text,
no fonts embedded): the frame at the playhead on A4, US Letter or A3 (turned to the picture), or nine frames across the shot
on one sheet with their moments, the scene's name on top. Text outside Latin-1 prints as "?" (backlog: an embedded font).
F1's storyboards build on it. *Rejected:* `UIGraphicsPDFRenderer` (UIKit only: untestable on Linux and of no use to the kit).

**D-428 — The bridge's `motion`.** path (points with their times, or a speed or a duration), follow, lookAt (from a moment),
pickUp (by a thing or a joint), putDown, letGo, evenSpeed, timing, front; the lowey skill has a motion module. Exports stay
in the app: where a file goes is the person's choice (D-402).

**D-429 — Schema 20.** Timelines' optional `holds`, the `setHolds` command, the `lookAt` property. 0.20 refuses a schema-20
file with its usual message.

**D-430 — Every tier.** Drawing a path looks at the ID buffer once a frame; the timeline's motion curves are keys only and
kept per document revision; Final is export-only and the same picture on every iPad, slower on a smaller one. The device
checklist times a Final 1080p export and a passes export on the iPad.

**D-431 — Kit 0.11.** `VideoEncoder.canEncode(_:)`: Cutaway offers ProRes the same way.

**D-432 — Translations still ride along.** The new strings were translated into Italian and Arabic for the catalog check.

## Maquette 0.22 — F1, film

**D-433 — Pictures over MCP (step 0.1).** Every bridge tool that answered with words and pictures failed with a bare
"Error executing tool": the MCP SDK 2.x builds an output schema from a tool's return annotation (`list[Any] | str`) and
can't fit an `Image` into it. Every tool now replies as content (`structured_output=False`); a test calls them through the
MCP protocol, not as Python functions, which is why CI never saw it. *Rejected:* returning pictures as base64 text (the
model can't see them).

**D-434 — The skill that's installed (step 0.2).** The skill in the repo already taught Scene Script v3; the copy Claude
loaded was the 1.x one, left from before the rename. It was installed again; `SKILL.md` names the version it's for, and the
README says to remove the old folder first (Copy-Item into an existing folder nests the new copy inside). *Rejected:* a CLI
that installs the skill (one more thing to keep working for one person's laptop).

**D-435 — Sketches, cut-outs and cage errors from a script (steps 0.3–0.5).** `sketch` draws curves on a named plane (xy,
xz, yz, or an origin and normal) or on a thing's face; `profile` gains `pull` (a negative distance cuts into the face it was
drawn on); `boolean` subtracts, joins or intersects shapes into a target (the others are used up, as in the app). A cage
point out of range names the cage's size and the indices it takes; a count outside 2–4 says what it became. One axis out of
range used to land on another point silently; each axis is checked now.

**D-436 — A group stands as one thing (step 0.6).** The Ground check judged each part of a grouped thing against the floor,
so a car's rims, lights and wing "floated". The group's lowest parts take the group's verdict; a part touching a chain of
parts that reaches them (within 2 cm) is attached; a part touching nothing keeps its own verdict. *Rejected:* judging only
the group (a balloon tied to nothing would pass).

**D-437 — The lens stays above the floor (step 0.7).** A low angle on a low, wide subject sat the camera under the ground.
Frame shot keeps the lens a quarter of the subject's height (at most 30 cm) above the floor it stands on and looks up from
there.

**D-438 — Who said yes (step 0.8).** No path was found that applies a build without asking: status and build read one
switch, and every other path waits for the banner. A real bug nearby: v1's status sent `"autoApply": "false"` as a string,
which every client language reads as true. Replies now say who approved (`approved_by`: `ipad` or `autoApply`, and the
message in words), so a repeat is visible in the reply itself.

**D-439 — A mood brings its ground (step 0.9).** Applying a mood kept the ground's colour, so a project made in Day and
turned Dark studio kept a green floor under a black sky. A mood now brings its own ground unless the ground was changed by
hand (it no longer matches the old mood's or the default).

**D-440 — The soft panel.** A fourth light, `area`: a rectangle that lights out of its front, from the nearest point of its
rectangle, fading at the sides like a softbox's spill; brighter than a bulb of the same strength to light as much. It bands
like every light in the Look. In glTF it travels as a wide spot with its size in the node's extras (KHR_lights_punctual has
no area light) and comes back a panel; in the Blender package it's a rectangular area light. Bulb is the point light's name
now. *Rejected:* linearly transformed cosines (true area integrals: two lookup textures and a cost a toon Look doesn't
show); shadows from panels (only the sun casts them, as before).

**D-441 — Setups.** Three-point (soft key and fill panels, a spot rim), golden hour (a low warm sun, a soft fill, haze and
god rays), moonlight (the old `moonlit`) and neon (night, a magenta panel and a cyan one, light haze), beside the six toon
recipes ("More setups"). One Core operation for the light's panel and the bridge: placed around the selection as the shot
camera sees it, spots and panels aimed at it, the mood and the air it needs, the last setup's lamps replaced (their keys
with them). *Rejected:* setups as a group object that keeps its lamps together (one more kind of thing; the lamps are
ordinary lights to move afterwards).

**D-442 — Haze and god rays.** The Look's `atmosphere`, applied in the finish pass from the depth the prepass already has:
far things fade into the haze's colour, which glows on the sun's side of the frame; god rays are 24 taps from each pixel
toward the sun's place on the frame, counting sky. One pass, the same on every tier. *Rejected:* froxel volumetrics (a 3D
grid of light per frame: Tier B can't keep it smooth); rays from lamps (the sun is what throws them).

**D-443 — HDRIs.** Radiance `.hdr` read in pure Swift (flat and run-length scanlines), shrunk as it's read so a 16k map
never sits in memory. It shows behind everything (turned, brightened) and lights the world through what every Look already
reads: the sun found in the picture (direction, colour, its share of the light), the sky's three colours from the picture's
bands, the ambient from the rest. *Rejected:* EXR (no decoder without a library); image-based reflections and diffuse
light (the Looks are banded toon shading; a mirror-perfect environment would fight them).

**D-444 — Camera bodies.** The field of view stays the truth (every key, move and export already speaks it); a body only
changes what the millimetres say, by its crop factor against full frame. Eight bodies, from a phone to IMAX 70 mm.
*Rejected:* storing the focal length and the body (two numbers that could disagree with every existing field-of-view key).

**D-445 — The frame's shape.** 16:9, 2.39:1, 9:16, 4:5, 1:1, kept on the timeline (`frame`, undoable with it); the Director
view, Frame shot and every export that is a size (1080p, 4K, ProRes, frames, passes, stills) come out in it; the shaped
presets (Shorts, Square, the GIF loops) keep theirs. 2.39 keeps 16:9's width and loses height, as a cinema frame does; 4:5
is a tall frame. `Framing` is Core's `FrameShape` now. *Rejected:* a shape per camera (a cut film has one).

**D-446 — Focus on a thing.** `focusOn` keeps a thing sharp as it moves (its head for a character); a later key pulls
focus over 0.8 s, eased in focus distance, the way a ring turns. Focus on selection and Pull focus here replace keyed
distances in the panel (old keyed pulls still play). The bridge says when the aperture is off and nothing would show.

**D-447 — Rigs.** A camera rides a dolly (travel along the way it faces, level), a crane (lift, swing around a base behind
it, arm length; it keeps what it framed in frame), an orbit (swing and lift around what it watches or its focus point) or
the hand (smooth noise on turn and place, seeded by the camera, after it turns to look). They're keyed numbers on top of any
camera move, so a crane up is two keys of one slider. *Rejected:* rig objects (a track to lay, an arm to place: another
thing to select and keep beside the camera).

**D-448 — Shots, storyboards, animatics.** Shots in one scene were already cuts on the camera track; `Timeline.shots` lists
them. A storyboard is Paper ▸ Storyboard: three panels across a landscape sheet, each the shot's key moment (a third in,
after the cut and before anything leaves) with its number, camera, millimetres, length, rig, whether it moves, and the
words said over it. The animatic holds each shot's key moment for its length with the whole soundtrack. *Rejected:* the
first frame of each shot (a whip pan or a transition is still landing).

**D-449 — Spatial video and photos.** Two parallel cameras a person's 63 mm apart (times a Depth option, 0.5–2), MV-HEVC
with the eyes tagged, the baseline, field of view and a small disparity adjustment (the screen just behind the nearest
things), written by the kit; a HEIC stereo pair with each eye's camera for photos. Spatial video is offered where the iPad
encodes MV-HEVC. *Rejected:* toed-in eyes (keystone); side-by-side files (Vision Pro and Photos don't play them in depth).

**D-450 — 360°.** Six 90° views around the shot camera, level and facing where it faces, laid flat on the GPU (the face
maths is Core's, tested there); titles and flipbooks stay out of a world view. 360° video gets the Spherical Video V1 box
(the kit edits the finished MP4: the track and movie grow, chunk offsets move when the movie comes first); panoramas are
JPEGs with Photo Sphere tags. Screen-space lines can show a faint seam at a cube edge (backlog). *Rejected:* Spherical V2
(it lives inside the sample description; rewriting `stsd` is riskier for the same players); stereo 360 (twelve views a
frame).

**D-451 — HDR.** HEVC ▸ HDR 1080p and 4K: 10-bit HLG in BT.2020, where the iPad writes it. The finish keeps highlights up to
3.78× white instead of rolling them off, and the composite encodes HLG with diffuse white at 75 %. Final doesn't apply (its
averaging is 8-bit); the preset says so. *Rejected:* PQ (it needs mastering metadata and a reference display; HLG plays
well on SDR screens too).

**D-452 — Wide colour.** PNG ▸ Wide colour 4K: Display P3, 16 bits a channel. *Rejected:* P3 video (HDR is the wide-colour
video).

**D-453 — The rotoscope.** A video behind the stage (Actions ▸ Rotoscope), kept in the workspace: its frame is the whole
frame under the playhead, composited where nothing is drawn (or faintly over everything), cover-fit inside the Director
view's frame. Never exported. *Rejected:* a card in the scene (it would export and be selectable); a background plate in
exports (compositing over live footage is Cutaway's job).

**D-454 — The bridge's `film`.** lens (millimetres on a body, aperture), frame, focus (on, at), rig (kind, numbers, keys),
air, environment (turn, brightness, off) and shots (listed as a storyboard would). An HDRI comes over `add_media` with
`environment` and applies like the other media (one undo step). Exports and the rotoscope stay in the app: where a file
goes is the person's, and the rotoscope is a view aid. The lowey skill's camera and lighting modules teach it.

**D-455 — Schema 21.** The `area` light and its size, cameras' `sensor`, `rig…` and `focusOn`, timelines' `frame`, the
Look's `atmosphere`, the sky's `environment…`. 0.21 refuses a schema-21 file with its usual message.

**D-456 — Kit 0.12.** HDR (`hevcHDR`), `SpatialVideoEncoder`, spatial photos and panoramas, `SphericalVideo`: Cutaway
exports the same way.

**D-457 — Every tier.** Haze and god rays are one pass; the HDRI is 4096 wide on M-chips and 2048 elsewhere; a panel costs
what a spot does. Spatial frames draw twice and 360° frames six times, export only, the same picture on every iPad, slower
on a smaller one. The device checklist times a 360° 4K export and a spatial export on the iPad.

**D-458 — Translations still ride along.** The new strings were translated into Italian and Arabic for the catalog check.

## Maquette 0.23 — D1, motion design

The inbox had nothing for this phase (one queued idea is a session of its own), and F1 left no device notes yet.

**D-459 — A logo is modelled solids.** An SVG comes in as one modelled solid a fill colour (a group when there are
several): each shape pulled out with its holes, upright and facing the front, standing on the ground, centred, a metre
wide and 8 % of that deep. Colours drawn later stand proud of the ones under them by an eighth of the depth each, as an
embossed sign does, so no two faces fight for the same place. Being ordinary modelled shapes, they push and pull, round,
paint, break and export like anything modelled. *Rejected:* a logo kind that keeps its SVG (one more kind every tool must
learn, for a depth that push/pull already changes); every colour at the same depth (the faces flicker).

**D-460 — SVG, read in the kit.** hmm-kit's new `HmmVector` reads SVG with its own small XML reader and flattens every
path command, arcs included, within a thousandth of the drawing's size; groups, transforms, `<use>`, nested `<svg>`, CSS
classes and ids from `<style>`, `currentColor`, and gradients as the average of their stops. Strokes, text and pictures
can't become filled outlines, so they're counted and named ("left out: 2 outlines drawn with a pen") instead of
guessed at. Cutaway gets it for its templates. *Rejected:* Foundation's `XMLParser` (FoundationXML on Linux: a different
parser on each platform); turning strokes into outlines (overlapping pieces would read as holes without a 2D boolean).

**D-461 — Fonts belong to the project.** A font brought in from the text's panel is copied to `assets/fonts/` and named by
the text (`font`); CoreText makes its letters through a descriptor read from the file, so stage, export and another iPad
all draw it. A file that isn't a font is refused at the door; a font that can't be read later falls back to the style's.
*Rejected:* registering fonts with the system (the project would lose its letters on another iPad); a device-wide font
list (the same).

**D-462 — Letters animate from presets.** Fly in, Bounce in, Cascade, Pop, Spin in, Type on (arrive once and rest) and Wave
(keeps going); the order (first to last, last to first, from the middle, random), the time between letters and each
letter's length; they start at the playhead. Each letter's pose is pure Core (`TextAnimator`), and the renderer draws every
character on its own about its own middle; at rest the letters are exactly the still text (a render test). *Rejected:*
letters as separate things (the text would stop being one text you can retype).

**D-463 — Clones are a recipe on the thing.** Its copies exist only in the shown scene (as broken pieces do since P1): the
thing itself is the first copy, the others are named after it, pick and select as it, and aren't in the outliner. Layouts:
a grid (across, deep, high), a circle (facing out), a line, along a drawn path; in the thing's own directions, from where it
was put; at most 1000 copies. *Rejected:* real copies (that's Array, already in the same menu: a flood in the outliner,
and editing one isn't editing all); copies drawn only by the renderer (the bridge, observe and 3D files wouldn't see them).

**D-464 — Effects through fields.** Random (seeded, the same every time), Delay (each copy plays the thing's own motion a
moment after the one before; with a field, copies as far from its centre start together, so rings ripple out) and Push
(moved, turned, grown as much as the field reaches); fields are Everywhere, Near a point and Ripple (a ring travelling out,
a new one every few seconds). One `effectStrength` scales them all and is keyed or linked like any number. *Rejected:*
Cinema 4D's falloff shapes and remap curves (a second grammar to learn; a ripple and a sphere make the brand loop).

**D-465 — Links.** A link adds the driver's change since its edited place (things) or the sound's value (sounds), times an
amount, to one channel of the target: moves, turns, size, glow, opacity, clone effects, morph, reveal. Turns are followed
from the start in tenths of a second so a gear driven at half speed keeps turning past half a turn; drivers are read
without their own links, so two things linked both ways can't loop. Presets in the panel: turns with it, turns against it
(a gear), moves with it, grows as it rises. *Rejected:* expressions (code, and law 12 keeps packs data).

**D-466 — A sound measured once.** Loudness and bass sixty times a second against the sound's own quiet and loud, and its
beats: onsets from where the energy jumps (the bass counting double), a tempo from their autocorrelation between 60 and
180 a minute, a grid locked onto each kick; free-time sound gives its strong onsets instead. Kept on the clip (`levels`,
base64, about 20 KB for three minutes), measured in the background the first time something moves to it. A link follows
the clip's fades and mute, not its volume (turning the music down shouldn't calm the ripple). In the kit, for Cutaway.
*Rejected:* measuring every frame (costly, and the stage and the export could differ); a file beside the clip (the
Animator reads only the document).

**D-467 — Morph.** Hold menu ▸ More ▸ Morph into…, then tap the thing it becomes: the first shape, cut finer, has each
corner matched to the second by looking out from the middle of each in the same direction, measured against each one's
box, so a cube reaches the ends of a long bar; its colour goes the same way; at the end it is the second shape, which is
hidden while it serves as one. `morph` is keyed 0 → 1 over a second from the playhead. Between shapes made here (shapes,
modelled solids, logos, drawings, blocky text); a placed Kit model is made editable first. *Rejected:* matching to the
nearest point (folds on hollow shapes); a full correspondence solve (heavy, and still lost between a cup and a ball).

**D-468 — Seamless loops.** The export checks the stretch it loops over (the loop region, else the timeline): the moment
after the last frame against the first, for every thing's place, turn, size, colour, glow and opacity, copies and letters
included; real things are named as not repeating. Close the loop gives keys that end elsewhere a last key where they began
and fits repeats to the nearest whole number (spin, float, bounce, swing, orbit, sway, a path followed round, a ripple, a
wave of letters); a wiggle and letters flying in once stay on the list. Copies and links that wait play a motion that
repeats as it repeats, so a closed loop stays closed; a one-off motion rests before its start. *Rejected:* exporting one
frame fewer (it hides a jump instead of fixing it).

**D-469 — Where it lives.** Model ▸ Add ▸ Logo (SVG); the text's panel holds its font and its letters; the object's menu ▸
More holds Clone… and Morph into… (its three extras are taken); the object's panel shows Clones and Morph when a thing has
them; Links sit in More ways to move; the loop check sits beside a video or GIF preset in the Export sheet. The menu bar:
Clone (⌃⌘C), Morph Into… (⌃⌘O), Close the Loop (⌃⌘E).

**D-470 — The bridge's `design`.** logo (SVG text or a project file), clone, effect, link (to a thing or a sound), morph,
letters and loop (`close`); `text` takes a `font`; fonts and logos come over `add_media` (`font=True`, `logo=True`). The
lowey skill's motion-design module teaches it.

**D-471 — Schema 22.** Objects' `motionDesign` (clones, morph, letters), timelines' `links`, audio clips' `levels`, 3D
text's `font`, the `morph` and `effectStrength` properties, the `setMotionDesign` and `setLinks` commands. 0.22 refuses a
schema-22 file with its usual message.

**D-472 — Kit 0.13.** `HmmVector` (SVG) and HmmMedia's `SoundLevels`, `SoundAnalysis` and `SoundReader`.

**D-473 — Every tier.** A copy or a letter is one draw; at most 1000 copies. Delayed copies read the thing's motion on a
scene of just it; a morph moves a few thousand corners on the CPU a frame and caches its match; a sound is measured once,
in the background. The same features everywhere; the device checklist times 1000 rippling copies on a Tier B iPad.

**D-474 — 3D files.** Copies go out where they stand at the playhead, letters at rest; their motion as keys is in the
backlog.

**D-475 — Translations still ride along.** The new strings were translated into Italian and Arabic for the catalog check.

## Maquette 0.24 — L2, Looks & the library

The inbox had nothing for this phase (the queued video-planning session stays queued), and D1 left no device notes yet.

**D-476 — Seven Looks, not six.** Painterly, Watercolour, Gouache, Paperman, Anime cel, Clean product and Pixel join Ink,
Comic, Sketch, Clay and Low-poly: twelve, in the panel's order the toon family, paint, film, solid, pixels. The plan's
"Watercolour & gouache" became two Looks: one is transparent (the paper shows, washes pool at their edges), the other
opaque and flat; one Look with a slider between them would be neither. *Rejected:* one combined Look.

**D-477 — The paint pass.** Painterly, Watercolour and Gouache lay paint over the whole picture after the lines, so the
lines are painted too: a structure tensor of the picture's brightness gives each pixel a direction, then an anisotropic
Kuwahara filter (eight sectors on an ellipse along that direction) turns it into strokes that follow the forms, with
faint bristles along them; watercolour adds wet edges from the brightness gradient, granulation in the dark paint and the
paper in the light. Each pixel takes its own Look's amounts from the ID buffer, so a painted thing can stand in an Ink
world. The pass runs only when a Look in the frame paints, its two textures are made on first use, and Tier B and C
previews sample two rings a sector instead of three. `LookPreset.paint`. *Rejected:* placing stroke quads (thousands a
frame, never the same on two tiers); paint in the surface shader (strokes must cross edges and lines).

**D-478 — Paperman is a film, not a sketch.** Soft (clay) light in black and white, thin clean ink, grain and a vignette,
accents keeping their colour. Sketch stays pencil on paper.

**D-479 — Clean product.** Soft light and shadows, no lines, and `reflection`: every surface mirrors the room's gradient
(the sky above, the floor below) by its fresnel, as lacquer does. *Rejected:* image-based reflections of the HDRI (the
Looks are banded; D-443 holds).

**D-480 — Anime cel.** Two hard tones, `shadowTint` (a lavender laid over the shadow band, how much in its alpha), a hard
rim and highlight, lines in each thing's own colour, on twos.

**D-481 — Pixel.** `LookPreset.pixel`: blocks of `size` points at 1080p and `colors` levels a channel, stepped in display
gamma. Blocks are a whole-frame thing, so they come from the scene's Look (a block can't be half Pixel and half Ink); the
lines are drawn first and turn chunky with everything. Blocks follow the frame's height: a 4K export looks like the stage.
Its few colours are ordered-dithered block by block (darks keep their hue), and a Final export draws it once: supersampling
and motion blur would only soften pixel art.

**D-482 — The Finish on any Look.** `PostSettings` gains `misregistration` (the camera's depth of field drawn as slipped
colour plates, as Comic does), `boil` (lines tremble on twos, the larger of it and the Look's) and `benDay` (flat colour
printed as dots on paper, bigger where it's darker), and three print textures: newsprint, risograph, canvas. Files from
before read with every new field off. *Rejected:* per-object Ben-Day (dots of two sizes meeting at an edge look broken).

**D-483 — The drawn set.** Screen effects gain an impact frame (two tones flipping each drawing, a burst of rays from the
hit), focus lines (tapered ink closing in on a point, a clear oval round it) and Kirby dots (black blobs crackling out
from a point). They aim at `center` or follow a `target`: the middle of its box as the shot's camera sees it, every frame.
Added from Look ▸ Finish (or ⌃⌘I, ⌃⌘U, ⌃⌘K) they follow the selected thing. Drawn on twos. *Rejected:* drawing them in
3D (they are marks on the frame, as a comic artist's are).

**D-484 — Studios in one grammar.** hmm-kit's `HmmStudio`: the made thing at the top, changing as you go, its settings
in pages under it, About last (`HmmStudioAbout`). The Look Studio is new (the My Look rows moved into it: Light, Lines,
Paint, Print, Motion, About); the Effect Studio is new (a saved particle effect playing from the same simulator the stage
uses, seen from the side; Amount, Motion, Look, About); the Part Studio is new (a saved character part: its job and
About; its shape is changed on a character, then saved again). Brush and Material Studio keep their own views, which
already are this shape. *Rejected:* moving the Brush Studio onto the shell now (its pad is a drawing surface, not a picture).

**D-485 — One `.maquettepack`, two contents.** The extension already carried a whole project; it now carries library
things too, and what's inside decides: `pack.json` makes it a library pack, `project.json` a project. Opening either from
Files, AirDrop or the share sheet does the right thing. A pack is `pack.json` (hmm-kit's `HmmPackManifest`), a licence file
in words, one versioned envelope an item and the pictures and models they name; reading takes only the kinds it knows
(brush, look, material, effect, part, motion, thing) and counts the rest out, refuses another app's pack, a newer format
and any path outside itself. Things that arrive get a fresh id where one is taken, brushes come as a set named after the
pack, pictures are filed under what they are. *Rejected:* a second extension (two files people can't tell apart); scripts
in packs (law 12: data only).

**D-486 — Who made it, in words.** A pack's author and licence are chosen when it's shared and remembered for the next
one: Use in anything · Credit me · Personal use only · My own words. Every thing keeps where it came from
(`LibraryManifest.origins`, brushes and materials included) and shows it on its About page; passed on in another pack, it
keeps its own author and licence whatever the new pack says. *Rejected:* a licence per thing chosen by hand (nobody
would), legal codes (CC BY-NC means nothing to a hobbyist).

**D-487 — Bring your drawing.** A layered PSD, PSB or Procreate file stands up as a diorama: each layer a sheet 0.4 % of
the drawing's long side thick, cut to the outline of what it shows (the alpha read as cells, walked into loops with their
holes, straightened) and painted with its picture on the front through the usual unwrap, the bottom layer at the back,
each one above 6 % nearer; groups stay groups, hidden layers come in hidden, opacity kept; the sides and back take the
picture's average colour. Sheets are modelled shapes, so pins, dots, paint and Looks all work on them. Layers that mixed
(multiply, screen…) show as they are, and the toast says how many; adjustment and empty layers are counted out. The PSD
reader handles RGB and grey, 8 and 16 bits, raw, RLE and zip channels, Unicode names, groups and PSB. *Rejected:*
picture cards with see-through pixels (the renderer has no cut-outs, and a card can't be rigged by its outline).

**D-488 — SPIKE: `.procreate` read directly: passed.** A `.procreate` is a zip of `Document.archive` (a keyed archive) and
each layer's 256-pixel tiles: newer files LZ4 in Apple's `bv41` framing, whose blocks share one window; older ones LZO1X.
Tiles are premultiplied RGBA stored bottom row first, then the canvas turns by its `orientation` (3 and 4 a quarter turn
each way) and flips. A mask is one grey byte a pixel and, where it has no tile, shows everything. On silicate's
`Mask_Test_File.procreate` (MIT) the reader's picture matches the thumbnail Procreate saved inside it within 1.5 levels of
255; an older file's LZO tile matches python-lzo byte for byte. The Procreate format isn't published: if a future version
changes, the reader says it can't read the file and PSD (Procreate's own export) still works.

**D-489 — Grounds.** `Ground.surface`: desert, grass, snow, rock, sand, pavement, water's edge, room floor, drawn by the
ground's shader from where each point is (no texture, no seam, no repeat to spot), lit and banded by the Look like
everything on them; the ground's colour is the material's first colour. The water at the water's edge moves and shines
and is a picture, not a fluid. Library ▸ Things ▸ Grounds, one tap, one undo step; the room floor reaches 12 m.

**D-490 — Stacks are folders.** A stack on Home is a folder beside the projects, one level deep, so the Files app shows the
same arrangement and a folder made there is a stack. Moving, renaming and unstacking move files; each stack keeps its own
sort; 0.23's stacks (in `gallery.json` by id) are moved into folders the first time Home reads them. Renaming and
duplicating a project keep it in its folder. *Rejected:* deeper folders (the plan says one level; Procreate's stacks are one).

**D-491 — The Keeper's Tower.** `KeepersTowerSample`: a leaning stone tower on a dark outcrop of rock, one amber lamp in
its lantern, a tiny keeper with a lantern at its foot, at night in Ink with haze, an orbit through its own camera. It's the
first sample made on a first launch and the Samples stack shows it turning (drawn once a version into the caches).
The New project card stays first.

**D-492 — The bridge's L2.** Scene Script's `look` takes every Look by name in any case, `ground` and `finish`; `effect`
takes the drawn set with `target` or `center`; `add_media` takes `drawing=True`. Packs stay in the app: where a file goes
is the person's. The lowey skill's Looks guide teaches all of it.

**D-493 — Schema 23.** Looks' `paint` and `pixel`, shading's `shadowTint` and `reflection`, the Finish's `misregistration`,
`boil`, `benDay` and three textures, three screen effects with `center` and `target`, the ground's `surface`, the
library's `styles`, `effects`, `parts` and `origins`. 0.23 refuses a schema-23 file with its usual message.

**D-494 — Kit 0.14.** Packs and licences, stacks as folders, the Studio grammar.

**D-495 — Every tier.** The paint pass is two compute passes at full resolution, 48 taps a pixel (32 on Tier B and C
previews), only in frames that paint; grounds, Ben-Day, textures, pixels and the drawn set are a few lines of the passes
that already run. A diorama is its layers' sheets (a 30-layer drawing is 30 things); reading a drawing and painting the
sheets happen off the main thread. The device checklist times Painterly at full screen on a Tier B iPad.

**D-496 — Translations still ride along.** The new strings were translated into Italian and Arabic for the catalog check.

## Maquette 0.25 — G1, guest kits

The inbox had nothing for this phase (the queued video-planning session stays queued), and L2 left no device notes yet.

**D-497 — Six set-ups, in the plan's order.** Set up for: Blank · Room · Print · Game · Study · Animation. Game is metres
on a one-metre grid with quarter turns in the Low-poly Look; Study is millimetres on a five-millimetre grid with sizes
shown, in Clean product. Each set-up's kit lives in the homes that exist: Model ▸ Add (Room's building tools and its
plans and site, Print's pieces, Game's greybox) and Model ▸ Edit (Print's tools under 3D print, Study, Game). A Blank
project shows none of it. Home's quiet row keeps its icons and drops the words on a narrow screen. *Rejected:* a
"Guests" panel (a new home moves the layout); kits in the Library (they're tools, not things).

**D-498 — One drawing engine for every drawing.** Plans, elevations, a technical sheet's views, papercraft and a frame's
ink are all `LineArt` (metres on the drawing's plane, pens a draughtsman would name: cut, outline, thin, hidden,
dimension, mountain, valley, cut line) from `HiddenLines`: feature edges (outlines where a surface turns away, creases
past 30°, open edges) split into seen and hidden stretches against a depth picture of every triangle, the surface's own
slope allowed for so an edge isn't hidden by the face it bounds. Written as PDF (vector paths, Helvetica's metrics),
SVG and DXF (R12, millimetres, a layer a pen). *Rejected:* drawing plans with the renderer (pixels, not lines a CAD
program can use).

**D-499 — The plan.** Cut at 1.2 m above each floor: what's cut filled black (even-odd, so a ring of walls keeps its
room), what's below in thin lines, north (−z) up. One plan a floor: the ground and the top of every slab two metres or
more above the one below.

**D-500 — Rooms.** The walls are cut low (0.3 m, under a window's sill) and high (2.25 m, over a door's head) and laid on
a two-centimetre grid; the outside is flooded from the edge and what's left are rooms (a square metre or more), each
outline's corners snapped to the walls' own corners so a 4 × 5 m room measures exactly 20.0 m². A room takes the name
of the flat text lying in it (Room ▸ Room name puts one there), else "Room n". Areas in m², or square feet when the
project works in feet or inches. *Rejected:* only walls tagged as walls (modelled walls and scans have to work too:
when nothing is tagged, everything encloses).

**D-501 — Building parts.** Walls, floors, stairs, roofs, columns, beams, railings, people, terrain and scanned furniture
carry `buildingPart`; a thing inherits its group's. Plans and IFC read it. It's a property, so 0.24 keeps it untouched.

**D-502 — IFC4 as STEP text, checked by IfcOpenShell.** One project, site and building, a storey a floor; each thing as
the element its part says (IfcWall, IfcSlab, IfcRoof, IfcStair, IfcColumn, IfcBeam, IfcRailing, IfcGeographicElement
for terrain), library models as IfcFurniture, anything else as a proxy, rooms as IfcSpace; shapes as triangulated face
sets with their colour. Ids are stable hashes, so exporting again gives the same ids. Doors and windows are cut into
their walls (as Room cuts them), so they leave as the walls' shape, not as IfcDoor. Scale people stay out. CI validates
the file against the IFC4 schema. *Rejected:* DWG (a yearly licence, CONTEXT §10.11); extruded profiles (every shape
here is a mesh first).

**D-503 — Roofs.** Gable and hip over the outline's smallest enclosing rectangle (an L-shaped house takes two roofs);
shed and flat follow any outline; 30° and a 30 cm overhang by default; solid down to the walls' tops so they print and
boolean. *Rejected:* a straight skeleton for hips over any outline (rare in the people's houses, costly to make robust).

**D-504 — Underlays.** A DXF lands as a sketch on the ground at full size in its own units (unitless files read as
millimetres), centred where it's dropped, locked; its closed areas pull up like any sketch's. A PDF's first page is drawn
at 4096 pixels and laid flat at its drawing scale (1:100 unless set); a picture at a millimetre a pixel. Two taps on a
length you know and its real length set any of them to scale. *Rejected:* reading PDF vectors (pictures are what people
trace; the DXF path is for vectors).

**D-505 — Match a photo.** Two lines along one direction of the room and two along the direction square to it meet at
two vanishing points; with the photo's middle as the lens's centre those give the lens and the turn; the origin tapped on
the ground and the camera's height (1.6 m) place it. The photo stands behind the stage as a rotoscope that holds still
(a one-frame-a-second video of it), so exports never show it. *Rejected:* three vanishing points (people rarely see a
third), a photo card in the scene (lit by the scene's light, it would never match).

**D-506 — Scans on the iPad.** Scan a room is RoomPlan, shown only where `RoomCaptureSession.isSupported` (LiDAR iPads);
walls come in 12 cm thick with their doors, windows and openings cut through, the floor under them and each piece of
furniture as a block named for what it is, as one undo step. Scan an object is Object Capture and the on-device
photogrammetry at reduced detail, shown only where both are supported; the model lands in the Library and on the stage.
The iPhone companion's scans come with U8, where the companion is completed. *Rejected:* showing the buttons on iPads
that can't (law 8).

**D-507 — Walking through.** Fly with the camera kept at eye height (1.6 m above the floor where the walk starts); the
sticks and a game controller as for Fly.

**D-508 — Print's tools work in world space on one part.** Overhangs are faces leaning past 45° facing down, not on the
bed. Best way up tries the six sides and the hull's sixteen biggest faces as the bottom and keeps the one with the least
support volume, the most on the bed and the lowest. Split cuts across height, width or depth at the part's middle, with
up to two pegs (up to 3 mm across, at the cross-section's thickest spots) on one part and holes a fit larger in the other,
moved a centimetre apart. Hollow leaves 2 mm walls and drills two 3 mm drain holes through the floor. *Rejected:* a
movable cut plane on the stage (the middle and the axis cover the people's helmets and statues; a gizmo comes if testers
ask).

**D-509 — Screws and threads.** ISO metric M2…M10 from the standards' tables (pitch, medium clearance, tap drill, socket
heads, hex nuts) and common heat-set inserts. Printed threads are the ISO 60° profile wound into a right-hand helix,
faded in over their first and last half turn; a nut's or a lid's thread is the same shape a fit larger. The jar's thread
is sunk 0.3 mm into its wall (a thread exactly on the wall left slivers). The fit is 0.2 mm a side by default.
*Rejected:* threads as textures or "cosmetic" lines (people print them).

**D-510 — Words on a part.** The block font, squeezed to the exact depth (it keeps letters at least a millimetre deep),
upright on the face (its up is the world's up, or north on a face looking up); engraved 0.6 mm or raised 0.6 mm.

**D-511 — Multi-colour 3MF.** Each colour gets a filament slot (up to 16) told to PrusaSlicer (`Slic3r_PE_model.config`)
and Bambu Studio and OrcaSlicer (`model_settings.config`), beside the standard base materials. The 3MF's corners are now
joined within a tenth of a micron (booleans left a few a nanometre apart, which cracked the jar).

**D-512 — Explode.** `explode` (0…1, keyed like anything) on a group and `explodeOffset` on each part; the offsets are
worked out once from the parts' boxes (each part along the line from the group's middle, past its own size; parts in the
very middle spread along the longest side). The animator applies them right after links. One tap explodes, again puts
it together.

**D-513 — The technical sheet.** First-angle projection (ISO, as Italian and European courses use) on A4 or A3 landscape:
front, the view from the left on its right, the top under the front, all at one standard scale; hidden edges dashed;
overall sizes in the project's units (millimetres for metres and centimetres); an isometric view of the assembly as it
stands (exploded, if it is); a parts list numbered from the bottom with name, material, count and mass; a title block.
Material is a real thing's, else plastic; mass is the material's density times the part's closed volume (or the mass
typed). *Rejected:* third-angle by default (Omar is in Rome); balloons on the views (the list carries the numbers).

**D-514 — Game levels by each engine's convention.** Godot: a piece named `…-col` becomes a static body with its shape as
collision when the project imports the file, and Godot makes its own lighter copies, so none are written. Unity:
`…_LOD0…2` under one parent become a LOD group (halves and quarters by our own simplifier, UVs carried), and a convex
`…_collider` beside each piece takes a Mesh Collider. Unreal: a convex `UCX_…_00` beside each piece is its collision.
One texture for everything packs every piece's painted colour (at most 1024 px) or a swatch of its flat colour into one
square picture. CI imports Dev's level in Godot 4.3 and finds its static bodies. *Rejected:* FBX for levels (our FBX
writer is for rigged things; Unity's glTFast and Unreal's Interchange read glTF).

**D-515 — Greybox.** Nine pieces on a one-metre module whose middles and sides fall on whole metres, in developer colours
(floors grey-blue, walls light, ramps and stairs orange, blocks blue); Freeze transforms bakes a modelled thing's turn and
size into its shape (not for groups: their children would move).

**D-516 — For illustrators.** A Mannequin start in Characters ▸ New (a faceless person in pale wood that rigs itself as a
humanoid). The layered PSD is the frame at the playhead split by the id picture into a layer per top-level thing over the
background, RGB, 8 bits, layers cropped, names in Unicode, the flattened picture after them; Procreate, Photoshop and
our own reader open it. Procreate palettes (`.swatches`) join the colour picker's saved palettes, read in hmm-kit so
Cutaway gets them. Papercraft: faces joined along their longest edges into pieces that don't overlap, a numbered edge
and a tab wherever pieces part, mountain and valley folds, packed onto A4 or Letter at real size when they fit (else the
whole net scaled down); a laser net is red cuts and blue scores. Ink as SVG is the camera's outlines and creases with
hidden lines removed, in the frame's pixels.

**D-517 — Where it lives.** Model ▸ Add (set-ups' kits), Model ▸ Edit (Print, Study, Game), the Plans, Match a photo and
scan sheets, the Export sheet's new formats (Picture ▸ Layered PSD, Ink as SVG; 3D ▸ IFC, Game level; Paper ▸ Plans &
elevations, Technical drawing, Papercraft), Library ▸ Yours ▸ Bring in a palette, and a Kit menu on a keyboard: Plans
⌃⌘A, Walk through ⌃⌘W, Best way up ⌃⌘B, Split ⌃⌘S, Hollow ⌃⌘H, Show overhangs ⌃⌘V, Explode ⌃⌘X, Freeze transforms ⌃⌘T.
IFC and plans are offered only when the scene holds a building.

**D-518 — The bridge's `guest`.** roof, column, beam, railing, person, terrain, label (Room); orient, split, hollow,
engrave, emboss, hole, print, scale (Print); explode (Study); greybox, freeze (Game); and `character` `new` with
`start: mannequin`. Files stay in the app, as packs did (D-492). The lowey skill's guest kits module teaches it.

**D-519 — No schema change.** Everything new in a project is a property (`buildingPart`, `explode`, `explodeOffset`) or
a workspace value (the Game and Study set-ups); 0.24 opens a 0.25 project and keeps them. Schema stays 23.

**D-520 — Kit 0.15.** `HmmPalette.procreate(swatchesJSON:)`.

**D-521 — Every tier.** Drawings, rooms, unfolding and IFC run off the main thread (the Plans sheet draws in the
background); a depth picture of at most 1400 pixels a side for drawings; booleans for threads at 48 to 96 sides. The
device checklist times the plans of a two-storey house and a threaded jar on a Tier B iPad.

**D-522 — Permissions.** The camera's line now also names scanning a room or an object; nothing leaves the iPad.

**D-523 — Translations still ride along.** The new strings were translated into Italian and Arabic for the catalog check.

## Maquette 0.26 — U8, yours

The inbox had nothing for this phase (the queued video-planning session stays queued), and G1 left no device notes yet.

**D-524 — The left hand mirrors the chrome.** Settings ▸ Yours ▸ Your layout ▸ Hand: with the left hand the two top
corners swap (making top left, the document top right), the sidebar moves to the right edge, the bottom corners swap
(the view corner bottom left, the joystick bottom right), panels open from their own cluster's corner and the object
panel keeps clear of the sidebar on its new side. Inside a cluster the buttons keep their left-to-right order (Model ·
Draw · Rig · Animate is a sentence: the order a thing gets made). Words, icons and the timeline don't mirror. It replaces
Appearance ▸ Sidebar on the right: a device that had it on opens left-handed. *Rejected:* a right-to-left layout
direction (it flips words and time); a mirror image of each cluster (Animate first); moving only the sidebar (the old
switch, half a job).

**D-525 — Buttons arranged within their corner.** Three corners can be arranged: the document's (Home, Actions, Look,
Library), making (Model, Draw, Rig, Animate) and the view (the views, the camera, the joystick, snapping). In Settings ▸
Your layout each row has a menu (Move left, Move right, Hide or Show) and the list drags to reorder; top to bottom is left
to right. Home and Actions can't be hidden (the way home and the way to Settings). A hidden button's command stays in the
menu bar and on the keyboard. Nothing moves between corners (law 2), so a lesson's screen still matches once the layout
is reset. A button a later version adds takes its default place among the saved order. **Reset layout** brings back the
hand, every corner and the sidebar's place; keys and defaults have their own resets. *Rejected:* arranging the tools'
bars (their verbs change with the selection and run in the order of use) and the panels' rows (law 2, and they scroll).

**D-526 — The sidebar along its edge.** A short line under the sidebar drags it up or down its edge; the place is a
fraction of the room there (so it survives a rotation or Split View); a double-tap on the line puts it back in the
middle. *Rejected:* placing it anywhere (it belongs to an edge, as in Procreate).

**D-527 — Keys a person can rebind.** All 101 commands of the menu bar, and the three new ones (Present ⇧⌘P, Notes
⇧⌘N, Your iPhone…), carry a stable id and the keys they come with. Settings ▸ Yours ▸ Keyboard lists them by menu,
searchable; tap one and press the new keys. A combination another command had moves here and that one is left without,
said in a line; a key without ⌘, ⌃ or ⌥ is refused (it would steal typing). While recording, every shortcut is off so
the press reaches the recorder. Hold a row for No key or Its own key; one button gives back every key. The stage's own
keys (Space, J/K/L, ⌥←→, the arrows, Delete, Escape, ?) stay as they are: they're the transport's conventions (CONTEXT
§4.5) and a Perform trigger's letter is its deck's. *Rejected:* rebinding the transport keys.

**D-528 — Your defaults shape the +.** Settings ▸ Yours ▸ New projects: the set-up, the Look, the units and the brush the
+ on Home makes (the set-up's own Look and units unless one is chosen; the last brush used unless one is chosen). The
quiet set-up row under Home's title still starts each job as it comes. *Rejected:* your Look over every set-up (a print
wants Clay to read its shape).

**D-529 — What was there already.** Light or dark (Automatic, Dark, Light) stays in Appearance; the gestures page (U3)
and the quick menu's six slots (U5, Settings ▸ Your Pencil) were built; Your layout's footer points at them. Your name
(Settings ▸ Yours) signs your notes; empty, the iPad's name does.

**D-530 — Present.** Actions ▸ Present (⇧⌘P): every control leaves and the stage fills the screen. It plays the film from
the start through its cuts, round again at its end (paused by hand, it stays paused); or walks through at eye height
(G1's walk; with no iPhone and no game controller two faint sticks stay in the bottom corners); or shows the model,
turned by fingers. A tap brings back for three seconds what it plays, play and the shots for the film, and Done. A TV or
a projector shows it by AirPlay screen mirroring or a cable, which mirror by default; with Stage Manager on an external
display, the Monitor window is the shot. The screen stays awake. *Rejected:* a separate external-display scene with a
presenter's view on the iPad (mirroring needs nothing; the Monitor covers an extended display).

**D-531 — Review pins.** A note is a pin on a spot (`Scene.notes`, schema 24): on a thing it's kept in the thing's own
space, so it follows the thing; on the ground or with nothing under it, in the world. It carries who wrote it, the words,
when, the film's moment when it was written through a camera, the replies and whether it's resolved; an answer opens a
resolved note again. A thing deleted leaves its notes where they were. Each change is one undo step. Pins show only with
Actions ▸ Notes (⇧⌘N) or during a review (law 1: nothing on the canvas at rest); a tap opens the thread beside its pin,
answered in place (reply, Resolve, Delete). Exports never show them. *Rejected:* notes as 3D text in the scene (they'd
export); notes on the project (they're about spots).

**D-532 — Review over FaceTime.** SharePlay (`ReviewActivity`): Actions ▸ Review over FaceTime shows during a FaceTime
call; the project goes as a `.maquettepack` through the session's journal and the others open it as their own copy.
Everyone turns the same view: whoever moved it last leads, and views from the others wait until this person has been
still for 0.6 s (`ViewLead`), at most fifteen a second on the quick channel. Notes travel on the reliable channel and
arrive as the others' undo steps. It's a review, not two people modelling at once. SharePlay needs the
`com.apple.developer.group-session` entitlement: the sideloaded `.ipa` is ad-hoc signed with no entitlements, so reviews
work only in builds signed by the developer account (TestFlight, at launch); the device checklist says so. *Rejected:*
co-editing (merging two journals live; a converge if the testers ask).

**D-533 — The iPhone companion, complete.** On an iPhone the app is the companion: Your face · Camera · Remote · See it in
AR · Scan a room · Scan an object, each shown only where that iPhone can. A two-way link (hmm-kit's `HmmLink`: framed JSON
over Bonjour `_maquette._tcp`, the local network only); the iPad listens only once the person asks for the phone (Actions
▸ Your iPhone, a scan tile, the remote), so the local-network question comes then, not at launch. The iPad asks for a mode
and the phone switches by itself. Your face keeps its own 0.10 link. **Camera**: the phone's motion drives the scene's
camera as the iPad's own does (the same scale; Perform records it). **Remote**: the shot playing, previous (within a
second of a shot's start, the one before) and next, play, from the start, two sticks that walk, end. **AR**: the scene as
USDZ, opened in AR Quick Look on the phone. **Scans**: RoomPlan on a LiDAR iPhone sends the room as data; Object Capture
makes the model on the phone and sends the USDZ. On iPads without LiDAR the scan tiles become Scan with your iPhone (G1's
D-506 closed). *Rejected:* the phone as a second video camera recording footage (that's Cutaway's; here a camera is a
scene camera); a listener always on (a permission question at launch).

**D-534 — The bridge's `note`.** add (on a thing or at a point), list, reply, resolve, reopen, delete; signed "Assistant"
unless told otherwise. Present, reviews and the iPhone are the person's devices and calls: no verbs. The lowey skill's
review notes module teaches it.

**D-535 — Schema 24.** Scenes' optional `notes` and the `setNotes` command; nothing older changes shape.

**D-536 — Kit 0.16.** HmmDesign: `HmmHand`, `HmmArrangement`, `HmmLayoutStore`, `HmmEdgePlace` and `HmmEdgeSlide`,
`HmmKeyCombo`, `HmmKeyCommand`, `HmmKeyBindings`, `HmmKeyboard`, `HmmKeyRecorder`. A new module, HmmLink: `HmmFrames`,
`HmmFrameReader`, `HmmLinkHost`, `HmmLinkCompanion`, `HmmTogether`, `HmmTogetherCall`. Cutaway takes all of it (its
iPhones as cameras, its own reviews).

**D-537 — Every tier.** Nothing new is heavy: the AR model is made when asked (the export path), the review's pack once,
pins are projected only while shown. The device checklist runs Present's film on a Tier B iPad.

**D-538 — Permissions.** The local-network line names the iPhone's jobs; SharePlay asks nothing of its own (FaceTime
does). Nothing leaves the local network but a review, which goes only to the people on the call, through FaceTime.

**D-539 — Translations still ride along.** The new strings were translated into Italian and Arabic for the catalog check.

## Maquette 0.27 — Q1, fixes and the device sweep

**D-540 — What was wrong with the Reference window.** Hesham on 0.26: "buggy, doesn't work as intended at all, doesn't
even have a close button or controls". Read from the code in this session (no iPad here; the sweep checks the rebuild on
the device): (1) no close, only a fold to a 52-point chip and Delete in its hold menu; (2) it lost its place: every
Actions ▸ Reference made a *new* card at a stepped spot (`ReferenceCard.place(after:)`), so windows stacked and a deleted
one never came back; (3) dragging clamped only its middle to the stage, so half of it could hang off an edge or sit over
the clusters, and it stopped dead where the finger lifted; (4) the hold menu (a UIKit interaction) sat under the SwiftUI
drag on the whole card, so a drag that started slowly opened the menu; (5) the grip sized the width only and, the card
being placed by its middle, grew it both ways at once; (6) its fold and grip buttons sat on the picture's corners, so a
touch near a corner folded or sized it; (7) it showed only a picture. The rebuild answers each one below. *Rejected:*
patching the card (the window and a pinned card want different things).

**D-541 — One window per project.** `ReferenceWindow` in `workspace.json` (`referenceWindow`): open, mode, where (its
middle as fractions of the stage), its content's size in points, the picture and how it's zoomed and panned, Canvas's
camera. It's how the work is seen, so it's never undone. An older project's window cards: the newest open one becomes
the window's picture, the rest stay floating cards; the Board's pins stay cards. *Rejected:* several windows (Procreate
has one, and one keeps its place).

**D-542 — It settles.** Dragged by its 44-point bar it follows the finger, glides on a quarter of the throw and settles
with a spring 12 points from the stage's edges and off the clusters (the shortest way out); a stage that changes size
settles it again. Its corner sizes it from its top-left (160–900 × 120–900 points), a pinch on the bar sizes it about the
same corner; the content keeps its own shape, never stretched. ✕ closes it; Actions ▸ Reference and ⌘⌥R open it where
and as big as it was, on the mode it was left on. *Rejected:* snapping to the corners (Procreate doesn't).

**D-543 — Canvas.** The whole scene, live, from the window's own camera: framed to show everything from the angle the
stage had when Canvas first opened, kept until ⌖ ("the whole scene, from where you look") frames it again. A second
`StageView` draws the scene as the stage has it (poses, paint) through that camera at 30 frames a second with 8 lights
and no helpers. *Rejected:* the shot's camera (that's the Monitor window).

**D-544 — Image.** A picture from Photos, Files, the clipboard or a drop, fitted whole; one finger pans it, two zoom it
(1–12×) about the point between them; some of it always shows. Import, Paste and Clear sit on its lower edge; More keeps
the pinned picture's two uses (trace it on the sheet, stand it in the scene). Clear forgets the picture, its file stays
with the project's media. Paste reads the clipboard only when tapped.

**D-545 — Face.** The front camera, mirrored like a mirror, 1280 × 720 at 24 frames a second, shown and dropped: nothing is
recorded or kept, nothing leaves the iPad. It asks for the camera only on an iPad that has one; while a face performance
runs, the camera is that one's and the window says so. The camera line in the Info.plist now names it.

**D-546 — Pick on it.** With Pick (or the quick menu's Eyedropper), a tap on the window takes the colour there into the
hand: the picture's pixel, the camera's pixel, or on Canvas the paint or colour of the thing under the tap (the stage's
eyedropper rule, through the window's own picking). *Rejected:* the held finger's loupe on the window: one finger pans
the picture.

**D-547 — A two-finger tap** on the window hides it for two and a half seconds, then it fades back.

**D-548 — Keys.** ⌘⌥R is Reference Window (Scene menu), as the phase asks; Record Voiceover, which had it, moves to
⌘⌥⇧R. Both can be rebound in Settings ▸ Keyboard.

**D-549 — The bridge.** `{"do": "reference", "op": "open" | "mode" | "image" | "frame" | "close"}` isn't an edit: it rides
in `ScriptResult.reference`, is listed in the proposal's report, and the editor applies it after the script's command.
`POST /v2/media?as=reference` keeps a picture and shows it at once (as `as=environment` lights the world at once);
`add_media(path, reference=True)` on the laptop. The lowey skill's new module (`modules/reference-window.md`) teaches it.

**D-550 — The sheet on a face.** A finger's tap on a thing with a tool that draws on the sheet lays it on the face's own
plane: the connected triangles within 0.5° and a hundred-thousandth of the shape's size of the touched one's plane
(corners welded at a millionth), its flat normal facing the eye. It lines up with the face's longest outline edge (up the
way nearest the world's up), is as big as the face less a 4% margin and at most two thirds of the view (the old size),
stays inside the face and snaps within 16 points to the face's middle and edges, with the light tick. It sits a hair
above the surface (0.1% of its size, 0.5–5 mm) and rides with its object as before. *Rejected:* the largest rectangle
inside a face that isn't one (the box along the longest edge; strokes land past a sheet's edge anyway).

**D-551 — On a curve.** A patch under 5% of the shape's area whose outline mostly runs on into neighbours at under 25°
is part of a curved surface: the sheet lies on the tangent plane under the tip, no bigger than the shape seen on that
plane, and doesn't snap. Over 60,000 triangles (a sculpt) the shape is a curve without the scan, so hovering stays
quick; a found face is kept while the tip stays on it.

**D-552 — The preview.** The hovering Pencil, resting 0.3 s on a face the sheet isn't on, lights the face and shows the
sheet's ghost there; sliding moves it from face to face and ticks when it snaps. A finger's tap lays it as the ghost
showed, and the face lights for a moment as it lands. *Rejected:* "or a finger held" from the phase: a finger held on a
thing while drawing is the eyedropper (U5), and it stays the eyedropper. Sketches keep laying their own plane on the face
they start on (exact already).

**D-553 — Exact, from its chip.** A sheet laid on a face shows a chip above the tool's bar: Offset (along its normal from
where it was laid), Turn (about its normal, snapping to 15° within 4°, with a tick) and Size (its width, its shape kept),
each dragged as a slider or typed on our number pad; one drag is one undo step for a kept sheet. Done puts the chip away.
*Rejected:* sliders across the face (sliding on the face does that).

**D-554 — Every tier.** The Canvas window is the one new cost (a second, lighter draw at 30 fps); finding a face is one or
two passes over the mesh only when the tip reaches a new face. The device sweep times the window on a Tier B iPad.

**D-555 — Permissions.** No new one: the camera's line gains the Reference window. Nothing leaves the device.

**D-556 — Translations still ride along** (Italian and Arabic, for the catalog check).

**D-557 — The store docs.** `docs/APPSTORE.md` and BACKLOG's "Before launch" (from 2026-10-24) were read against
studio-h's `LAUNCH.md`: name, subtitle, keywords, the price and its launch week, Family Sharing, the education discount,
"Data Not Collected" and the age rating agree. APPSTORE's permissions line gains the Reference window's Face.


## Maquette 0.28 — M12, AR, the web layer and the bridge

**D-558 — Nothing is held.** `MAQUETTE_HELD` is empty in every configuration, the App Store one included (CONTEXT §D.3).
`MaquetteHeld` stays as the mechanism with no names (a struct whose every name reads as nothing, since an enum without
cases can't carry a raw type); the five entry points that asked about live performance no longer ask. The App Store walk
now fails if any LAYOUT.md row is marked held and walks every row as present, and a CI step reads the store build's
Info.plist and fails unless `HmmHeld` is empty. *Rejected:* deleting `Held.swift` (the phase keeps the mechanism).

**D-559 — SPIKE passed: a web view on a stepped clock.** hmm-kit's `HmmWeb` (0.17.0) plays a piece in an offscreen,
sandboxed `WKWebView`: a script added before the page's own replaces `performance.now`, `Date`, `requestAnimationFrame`,
timers, CSS and Web Animations, video and audio and `Math.random` (seeded) with a clock that stands still until the
player steps it, a frame of 1/60 s at a time; frame 0 is the first round of animation frames at time 0. On CI (iPad
simulator) a CSS slide and a `performance.now()` box sit where their clock says, a three.js scene drawn through WebGL is
pixel-identical at frame 45 whether reached straight or after frames 10 and 100, a Lottie square is at its keyframed
place, and a `fetch` to the web fails. The view paints with no window (tests, a background export); in the app it joins
the window scene offscreen. *Rejected:* snapshotting a canvas from JavaScript (WebGL needs `preserveDrawingBuffer`, and
HTML can't be drawn that way at all).

**D-560 — Pages are laid out at their own size.** Without a viewport tag WebKit lays a page out 980 px wide and shrinks
it (the spike's first run measured everything at a quarter); every page gets `width=device-width, initial-scale=1`
unless it brings its own, so `innerWidth` is the piece's width.

**D-561 — Every path to a moment steps from frame 0.** Forward is stepping on; going back starts the page again and steps
to the frame. So scrubbing back costs a reload, and a page that keeps state (a three.js simulation) always shows the same
frame for the same time. The stage and an export keep separate players and still match, because both step the same way.

**D-562 — Offline, with the libraries agents use.** A content policy and a content rule list block every http(s) and
socket request; the piece's own files come from `hmm-web://piece/…`. three.js 0.170 (with its addons but not the big
decoders) and lottie-web 5.12 are carried (MIT); their usual CDN addresses (unpkg, jsDelivr, esm.sh, Skypack, jspm, cdnjs,
any version) are swapped for the carried copies, and a page without an import map gets one for `three` and
`three/addons/`. *Rejected:* letting pieces reach the network (nothing leaves the device, CONTEXT §3).

**D-563 — A web piece is a card or an overlay (schema 25).** `CardRecipe.web` and `OverlayRecipe.web` hold a `WebPiece`
(an inline page or Lottie the bridge writes, or a project file or folder; its CSS size; `start`, `duration`, `loop`).
Its frames are named like a video's (`web:<object>#f=<frame>`, 60 a second from `start`), so the stage, the export and the
texture cache already know where to put them; a card's frames share one texture slot. Before its start a card shows frame
0 and an overlay isn't drawn (as a video). No new object kind and no new command: an edit is `setKind`. *Rejected:* a
`web` object kind (every switch over kinds would grow for what a card already does).

**D-564 — A piece is drawn at its own size**, at most 3840 pixels a side: a 4K film upsamples a 1280 page. The skill tells
the bridge to make a page as big as it will be seen.

**D-565 — Bringing one in.** Model ▸ Add ▸ Web page or Lottie takes a `.html`, a folder with a page (its `index.html`, else
its first page) or a Lottie `.json` (its size and length read from it), then asks "On a screen in the scene" or "Over the
frame". The bridge's `web` verb adds (`html`, `lottie`, `file`), edits and lists them; `start` takes a word.

**D-566 — AR on the iPad, in our own renderer.** Actions ▸ View in AR (⇧⌥⌘A) fills the screen with the camera; the scene
is drawn over it by LoweyRender with a transparent background (no sky, no ground), so its Look, light, paint and effects
are the stage's. The scene isn't moved: the iPad's camera is carried into the scene's space (`ARPlacement`), its lengths
divided by the size. A tap on a found floor or table puts it there turned to face you, sized for a table (`tableScale`:
40 cm across its widest side, never bigger than life); one finger moves it on the surface, two turn it, a pinch sizes it
and snaps to life size within 8% with a tick; On the table and Life size set it at once; Play runs the timeline in the
room. One pass composes the camera (full-range YCbCr) under the frame. Apple's coaching overlay asks for the floor.
Nothing is recorded or kept. *Rejected:* RealityKit (another renderer, another Look).

**D-567 — No ground shadow in AR (for now).** The transparent pass has no ground, so things stand on the real floor
without a contact shadow. The device sweep says whether it reads as floating; a shadow catcher is a BACKLOG line.

**D-568 — Share for AR.** Actions ▸ Share for AR and Scene ▸ Share for AR… write the scene as USDZ (the Apps preset,
painted colour as textures) and hand it to the share sheet: AR Quick Look opens it on any iPhone or iPad without the app
(architects send it to clients). The AR view's own Share does the same.

**D-569 — The bridge reaches everything through verbs.** `BridgeCoverage` (Core) maps every menu-bar command (107) and
every kind the Add page makes to a path: a verb and its op, an app ask, or a laptop tool. Core tests check every verb is
the compiler's, every op is in the schema and every tool is in the skill's reference; a Features test checks the table and
`KeyCommands.all` name the same commands. `skills/lowey/reference/coverage.md` is generated from it (CI checks).

**D-570 — `{"do": "app"}`: the app around the scene.** What changes how a person sees the work rather than the work (the
hand's tool, a panel, play, the playhead, undo and redo, present, notes, the timeline, the director's view, the
interface, framing, flying, view aids, the selection, an export into renders, the AR view, a Monitor window) rides in
`ScriptResult.app` beside the edit, as the Reference window's asks do, applied in order after it and never undone. The
editor's switch is over every `AppAsk.Op`, so none goes unhandled. *Rejected:* a tool per action (CONTEXT §12: tools stay
few, verbs carry the breadth).

**D-571 — `duplicate`.** Edit ▸ Duplicate (and Copy then Paste) had no friendly bridge path; the new verb copies beside the
originals and names a single copy. Ungroup keeps the raw `command` verb (a reparent), the only menu command that does.

**D-572 — The skill for the whole app.** `lowey` is now "Maquette — the director (and the second pair of hands)": two new
modules (`web-layer.md`, `the-app.md`), the reach table, and three new eval briefs (a web chart on a screen, a Lottie
title, a hand-off: a panel, a selection, the playhead and a USDZ). *Rejected:* rewriting the director loop (the evals
say it works).

**D-573 — Every tier.** A web piece is the new cost: the page draws once per new frame, off the render loop, and the stage
shows the last frame it has while the next one draws (as a video); four pieces stay loaded at once. The AR view draws at
60 fps with the stage's quality tier. The device sweep times both on a Tier B iPad.

**D-574 — Permissions.** The AR view uses the camera, whose Info.plist line now names it; nothing leaves the iPad. Web
pieces need none (no network).


## Maquette 0.29 — X1, import and export everything (in progress)

**D-575 — Keyed numbers point at their place.** A key on a material's colour, see-through, roughness, metal or glow, a
light's colour, strength, reach or cone, or a camera's lens leaves glTF as a `KHR_animation_pointer` channel at that
number, sampled like node keys (linear and held keys as they are, eased ones every frame). The extension is used, never
required, so a reader that doesn't know it skips those channels and plays the rest. Colour and see-through share one
channel (the base colour's alpha). Maquette reads the channels back as keys on the objects using that material, light or
camera. *Rejected:* baking them into extra nodes or morph targets (three.js, Blender and engines would each need their
own trick).

**D-576 — What glTF can't hold rides in its extras.** Keys with no place in glTF (face states, a reveal, a stepping)
are written as Maquette's own tracks in the file's `extras.maquette.tracks`, their targets the nodes'
`extras.maquette.id`, and come back as they were. The matrix calls these cells `extras`. *Rejected:* dropping them
silently (law 5: nothing is ever lost, and a round trip through Maquette is the common case).

**D-577 — Glow, see-through and lacquer reach every file.** A glow brighter than white keeps its strength with
`KHR_materials_emissive_strength` (it was clamped to white); an object's see-through is the material's alpha in every
format (it was left out); the Look's lacquer (Clean product's reflection) is every surface's clearcoat.

**D-578 — For the web is a folder, not a file.** Export ▸ 3D ▸ three.js writes one zip: `scene.glb`, the same scene as
three.js's own JSON, a player (`index.html` + `main.js`: the camera cuts, the timeline on an `AnimationMixer`, the
sun, sky and ground, the Look), `maquette/pointer.js`, a React Three Fiber component, `AGENTS.md` and three r170 from
the kit's own copy, so it plays with no network. *Rejected:* a single GLB (it can't carry the Look, the cuts or the
notes an agent needs), loading three from a CDN (nothing leaves the device, and folders must open offline).

**D-579 — Names three.js keeps.** `GLTFLoader` strips spaces and `[ ] . : /` and numbers duplicates in an order that
depends on its async loading. The web GLB is written with names already clean and unique (nodes and meshes together),
so `getObjectByName`, `scene.json`, the component and `AGENTS.md` agree; the Maquette name stays in
`extras.maquette.name`. Other glTF exports keep names as they are.

**D-580 — The Look in three.js is its numbers.** `maquette/look.js` rebuilds it: toon Looks as `MeshToonMaterial` with a
gradient from the Look's bands, threshold and softness; lines with `OutlineEffect` at the Look's width (pixels at
1080p); halftone and pixel art as passes; Clay and Clean product keep three's standard materials. The paint Looks and
paper use their nearest real-time pass (toon bands and lines), and the matrix says so. Toon materials keep a
`roughness` and `metalness` so keyed tracks still land.

**D-581 — SPIKE (step 0) passed with a render check, not only structure.** In node, three.js 0.170 reads the folder's
GLB (with `pointer.js`) and `scene.json`; their names, places, clips, tracks and values at a moment must agree with each
other and with what Maquette wrote. Then Chromium (Playwright, SwiftShader) plays `index.html?t=0.5&transparent`, and
its picture must cover Maquette's own silhouette of that moment: Core projects the scene through its camera and keyed
lens and rasterises a mask (`ThreeSilhouette`), so the golden is Maquette's, not three's. Locally: structure agrees,
overlap 94.1% (the ink lines are the rest). The job is `threejs` in CI. *Rejected:* headless-gl (three dropped WebGL 1
in r163), comparing to a Metal golden (two renderers never match pixel for pixel; the silhouette is what must).

**D-582 — The matrix is checked against proofs.** `docs/INTEROP.md` has a section a format, a row a feature, a word a
direction (`carried`, `baked`, `extras`, `impossible`, `not offered`, `todo`). `InteropMatrixTests` fails when a
`carried`, `baked` or `extras` cell has no proof in `InteropProofs` with the same word, when a proof's test doesn't
exist, or when a proof no longer matches its cell. Unlisted rows take the section's "Not listed" line. The phase ends
when no `todo` is left (333 at this point). *Rejected:* one wide table (24 rows × 20 formats × 2 directions doesn't
read).

**D-583 — three.js's JSON comes into the scene, not the library.** Library ▸ Import takes a `scene.toJSON()` file and
brings it into the open scene as one step (as a glTF made editable): `BufferGeometry` as its triangles, three.js's
boxes exactly, spheres, cylinders and cones as Maquette's own shapes at their sizes, planes as a quad standing in XY;
standard and physical materials as colour, roughness, metal, glow and see-through; cameras and lights as ours (a light
with no target aims at the origin, as three.js's does); an `InstancedMesh` as a thing a copy (the matrix says `baked`
until copies become clones); clips' tracks as keys, by name or uuid. A file Maquette wrote gets its own names back from
`userData.maquette.name`. What can't come in (ambient and hemisphere light, points and lines, custom shaders' code,
pictures on surfaces for now, other parametric shapes) is said after, in the same toast line; nothing is asked first.
*Rejected:* a library asset (a three.js scene is a scene, with cameras and clips, not a model to place).

