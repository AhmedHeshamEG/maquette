# Backlog

What's known and not done yet, so nothing lives only in someone's head. What Maquette is: [SPEC.md](SPEC.md). The
phase plan (the pass U1 … U5, M12, M14, M16, then 1.0) lives in studio-h's `PHASES.md`; ideas go to its `IDEAS.md`.

## Left from L2 (Maquette 0.24)

- [ ] The device checklist in the "Maquette 0.24 — L2" PR (each new Look on the Keeper's Tower, Painterly at full screen on
      a Tier B iPad, a pack AirDropped to a second iPad with its author, a five-layer PSD and a real Procreate file as
      dioramas, the grounds, focus lines following a running character, stacks in the Files app).
- [ ] The paint pass, Pixel, Ben-Day and the drawn set aren't in the Godot and Unity Look shaders yet: exported games show
      the Look's light and lines only.
- [ ] A drawing's layers that mixed (multiply, screen…) come in as plain pictures; the diorama doesn't composite them.
- [ ] PSD in CMYK, Lab, indexed and 32-bit isn't read; layer effects (shadows, strokes) and smart objects come in as their
      pixels or not at all.
- [ ] The Procreate reader follows files saved by Procreate 5; a newer format may stop it (PSD export always works).
- [ ] The Part Studio changes a part's job and name; its shape is changed on a character and saved again. A part's own
      paint isn't carried yet.
- [ ] The Effect Studio's preview is from the side, on a dark card; the effect seen in the project's Look is the stage.
- [ ] A thing shared in a pack carries its build and the library models it uses; paint laid on it in a project isn't
      carried yet, and its motions are shared as motions.
- [ ] Watercolour and Gouache are whole-frame paint over each thing's own amounts; a painted thing next to an unpainted
      one shows paint creeping a few pixels over the edge.

## Left from D1 (Maquette 0.23)

- [ ] The device checklist in the "Maquette 0.23 — D1" PR (a client's SVG logo, a font brought in from Files, letters flying
      in on the stage, 1000 rippling copies on a Tier B iPad, a gear pair, a ripple on the beat of a real song, a cube
      morphing into a ball, a ProRes 4444 loop played on repeat in a video editor).
- [ ] 3D files carry clones where they stand and letters at rest; their motion as keys (one node a copy, a letter) is to do
      (D-474).
- [ ] Morph needs shapes made in the app: a placed Kit model is made editable first (D-467). Morphing to a model's parts
      straight away, and painted surfaces carried through a morph, are to do.
- [ ] SVG strokes, text and pictures are counted, not imported (D-460). Outlining strokes needs a 2D boolean.
- [ ] Clone copies aren't paintable or riggable one by one, by design; "Make them real" (copies into things) would be the
      way, if testers ask.
- [ ] The Stepper titles with a count ("Across 5") are keyed `%@` by the strings tool and `%lld` by SwiftUI, so their
      Italian and Arabic don't show; they're English at 1.0 anyway (the languages come with the Mac).
- [ ] Letters animate in; letters leaving the same way at a set time is to do.
- [ ] A sound is measured when something first moves to it; a clip trimmed or replaced later keeps its measure (it's the
      file's, so trims are fine; a replaced file needs measuring again).

## Left from F1 (Maquette 0.22)

- [ ] The device checklist in the "Maquette 0.22 — F1" PR (the bridge's pictures over MCP with Claude Code, a spatial
      video and photo in Photos or on a Vision Pro, an HDR export on an HDR screen, a 360° video on YouTube, god rays and
      haze on the iPad, an HDRI's sun against its picture, the rotoscope's frame against the playhead; a 360° 4K export and
      a spatial export timed on the iPad).
- [ ] The build that applied with auto-apply off (step 0.8) wasn't reproduced; the reply now says who approved. Watch for it.
- [ ] 360° frames are six views: screen-space lines and contact shading can show a faint seam at a cube edge (D-450).
      Lines from a cube-aware pass, or a seventh overlapping view, if it shows.
- [ ] Spatial and 360° exports draw each view once: Final's motion blur and supersampling aren't applied (D-449, D-450).
- [ ] HDR files draw each frame once (Final's averaging is 8-bit) (D-451).
- [ ] Only the sun throws god rays; lamps and panels don't (D-442).
- [ ] An HDRI lights the world through the sun and the sky's colours; metal mirrors the sky's gradient, not the picture
      (D-443). Reflections of the HDRI on glossy things are to do.
- [ ] HDRIs are Radiance .hdr; OpenEXR needs a decoder (D-443).
- [ ] A soft panel's helper on the stage is a bulb; drawing its rectangle (and dragging its size) is to do.
- [ ] Spatial video and photos for Vision Pro: the disparity adjustment is a fixed 2 %; a "screen depth" option if testers
      want it.
- [ ] The rotoscope plays whole frames at the timeline's rate; a video at another rate shows its nearest frame (D-453).

## Left from A1 (Maquette 0.21)

- [ ] The device checklist in the "Maquette 0.21 — A1" PR (a path drawn with the Pencil and its timing, facing and
      leaning, look at and pick up on a character, the dope sheet and ghosts, an export carrying on in the background, a
      Final 1080p export and a passes export timed on the iPad, ProRes 4444 on Hesham's iPad, the Godot shader in a game).
- [ ] The Unity URP shader is checked on a computer: Unity has no licence-free headless run (D-426).
- [ ] Paper's text is Latin-1 (Helvetica, nothing embedded): names in Arabic or Japanese print as "?" (D-427). Embed a
      font with the languages phase.
- [ ] Ghosts while scrubbing show the selected thing only (D-414); ghosts of a character show its rig's pose, a held thing
      rides along in them.
- [ ] A drawn path lands on surfaces facing up; walls and ceilings aren't followed (D-408).
- [ ] The motion curve in a row is from keys (and parents); holds, looks, behaviours and physics move things it doesn't
      draw (D-412).
- [ ] Final's motion blur averages moments (eight a frame): very fast things show steps; a velocity blur is the way past
      it (D-422).
- [ ] Every scene for 3D files: another scene's physics run is made only when it's opened (D-423).
- [ ] An FBX in Unreal's own axes (Z up, centimetres) if a pipeline asks for it; the joint names are there (D-419).

## Left from K1 (Maquette 0.20)

- [ ] The device checklist in the "Maquette 0.20 — K1" PR (orbit speed the same in every tool and orientation, the five
      starts, parts and styles, face states and lip sync, proportion handles, acting out from the camera and a video,
      the GLB opened in Godot or Unity, a sprite sheet, a turnaround; reading a ten-second video timed on the iPad).
- [ ] Pieces are rigid: elbows and knees hinge, they don't bend softly (D-391). A skin per limb (bone heat on its own
      pieces) is the next step.
- [ ] A face state is changed with its dials; bending it on the stage with the surface brushes (grab on the shown state)
      is to do (D-392).
- [ ] Act it out is for people; four-legged acting needs an animal pose model (D-397).
- [ ] Hands from Act it out: the wrists aim the forearms; fingers and hand turns aren't read (Vision gives none in 3D).
- [ ] A mark moved by hand in Rig is replaced when the parts change and the character rigs itself again (D-390).
- [ ] Sprite sheets cover the humanoid clips, the character's timeline and standing still; any motion from the Library
      as a strip is to do.
- [ ] Engines get GLB; an FBX with several meshes and blend shapes (for older Unity and Unreal pipelines) is to do (D-398).
- [ ] A made character's parts are separate meshes in the stage's draw list; merging a character's pieces for drawing
      (crowds of made characters) is to do.

## Left from P1 (Maquette 0.19)

- [ ] The device checklist in the "Maquette 0.19 — P1" PR (the 500-body stack and a glass filling with water on Hesham's
      iPad and a Tier B one, cloth and jelly feel, a ragdoll down stairs, Keep it, the arrows, the real sun against a
      sun app, an exported glTF in Godot).
- [ ] A bent surface (cloth, jelly) shows the thing's colour, not its paint (D-374).
- [ ] Water doesn't push things back (one-way, D-377); boats and floating things need two-way coupling.
- [ ] Runs live in memory; a heavy fluid is worked out again after reopening the project (D-370).
- [ ] More ways to move's quick Fall and Explode still bake the old sphere approximation into keys; Real is the physics.
      Routing them through Jolt (make real, run, Keep it) is to do.
- [ ] A ragdoll's parts never collide with each other (D-373); arms can pass through the body in a long tumble.
- [ ] Joints are added from the selection with their anchor where the things meet; dragging a joint's mark on the stage
      to move it is to do (numbers move it today through the bridge).
- [ ] Gears join two hinges' turning; a rack (a gear and a slider) isn't offered.
- [ ] Fluids' colliders are measured once (a moving glass is followed, a bending one isn't).
- [ ] Khronos' physics extension for glTF replaces OMI's once ratified (D-380).

## Left from U7 (Maquette 0.18)

- [ ] The device checklist in the "Maquette 0.18 — U7" PR (painting maps and masks with the Pencil, smudge's feel, a
      material dropped, the Material Studio, wear on a real model, a decal, mirrored strokes, seams cut, the flat view,
      fur on Tier A and B, a 4096 texture on a Tier B iPad, the painting benchmark, an exported glTF in Blender and a game
      engine).
- [ ] Hesham's own painted Nomad export as the normal-bake fixture (D-352, D-275): a dense sphere stands in.
- [ ] A brush paints one map at a time (D-338); painting colour, roughness and metal of a material in one stroke is
      "Paint it on" (a fill and its mask).
- [ ] Hair cards aren't grown on skinned surfaces on the stage (they'd stay in the rest pose, D-355); exports and shells
      follow the skin. Skinning the cards by their root's weights is to do.
- [ ] Fur cards take the thing's own colour, not its paint under each tuft (their uvs run along the strip, D-355).
- [ ] Wear bakes are kept while the app runs, not in the project; a big model bakes again after a relaunch (D-345).
- [ ] Glass is pale and glossy, not see-through (D-342).
- [ ] The flat view refreshes its picture after each stroke (a CPU composite); a live GPU view of the layer is nicer.
- [ ] Smudge reads its layer's picture when it starts (every tile decoded); on a 4096 layer that's a moment's wait.
- [ ] Projected pictures (Project a picture) paint colour only; decals too (D-348).
- [ ] Seams are marked on modelled faces' outlines; a placed model's own seams can't be marked yet (D-349).
- [ ] `.maquettepack` files for materials (law 12) come with L2's packs; materials travel in projects and the library.

## Left from H1 (Maquette 0.17)

- [ ] The device checklist in the "Maquette 0.17 — H1" PR (the steps list over the scrubber, a hole changed on M3's block,
      a replay's time on a heavier model, a Tier B iPad).
- [ ] Changes by hand aren't steps (D-329): corner drags could be named by their faces' tags, the knife by its plane.
- [ ] A step can't be removed, switched off or moved (Shapr3D can); the list only changes numbers.
- [ ] Sketch steps have numbers for circles and rectangles; lines, arcs and splines in a cut don't (D-331).
- [ ] Sketch pulls into a thing with its own scale aren't recorded (D-331).
- [ ] A history keeps its base shape and every boolean's tool in project.json; a thing with many booleans makes a larger
      file. Measure it on a real project; compress or move to `assets/` if it matters.

## Left from U6 (Maquette 0.16)

- [ ] The device checklist in the "Maquette 0.16 — U6" PR (parts lit and dragged with the Pencil, the chip, the brushes'
      feel on a sculpt, a cage dragged on a 50 000 triangle model at U1's gates, clean up on a real sculpt and its time, the
      view cube, typed sizes).
- [ ] Faces, edges and corners light for a modelled shape, a blockout or a drawing; a placed model lights whole until
      *Model it* (D-304).
- [ ] The cage doesn't animate yet; the bend does (D-317).
- [ ] One bend per thing (D-316).
- [ ] Brush strokes on a placed model need it painted first (one surface, D-318); a stroke's pressure isn't read yet
      (the strength slider sets it).
- [ ] A shape changed after brushing leaves its strokes behind when its corner count changes (D-318); carrying them by
      nearest point, as paint is carried, is to do.
- [ ] Clean topology in a debug build is slow (Eigen unoptimised, D-320); the app's builds are release.
- [ ] Sketch rules apply to lines, rectangles, circles and arcs; splines and polylines hold still (D-315).
- [ ] Typing one edge's length: H1 made steps' numbers editable, but an edge's length isn't a step's number (D-314);
      a CAD story after launch.
- [ ] Hover lights whole things; faces and edges light with U6's picking (D-291). **Done in U6** for the selected shape.

## Left from U5 (Maquette 0.15)

- [ ] The device checklist in the "Maquette 0.15 — U5" PR (the Pencil's feel and where strokes start, hover lighting,
      the Pencil Pro's clicks, flicks, carrying, the eyedropper's loupe, a rig dragged, the sheet seen in light and dark).
- [ ] On the simulator the pull number is redrawn (gone for a moment) right after a size is typed, so a tap can miss
      it; the block-with-a-hole test taps it again until its pad opens. Find what redraws it; check it on the iPad.
- [x] Smudge on painted models waits for U7 Texture's per-pixel tools (D-283): done in 0.18 (D-346).
- [x] Hover lights whole things; faces and edges light with U6's picking (D-291): done in 0.16 for the selected shape.
- [ ] A thing stuck to the camera is moved by its gizmo in the world; the gizmo doesn't follow the camera's frame yet
      (D-295).
- [ ] Only a selected thing is carried by a finger (D-293); carrying several at once carries the selection's middle.
- [ ] Overlays made before 0.15 still play and edit in the timeline, but no new ones are made; converting them to stuck
      titles is by hand (D-295).
- [ ] The UI language is English at 1.0 (CONTEXT); the Italian and Arabic catalog check stays until the languages phase
      (D-300).

## Left from U4 (Maquette 0.14)

- [ ] The device checklist in the "Maquette 0.14 — U4" PR (pins and dots with the Pencil, each body shortcut on real
      models, changing a rig after animating, rigid parts, motion saved and dropped, repeats, a real Nomad sculpt, a 1.5
      million triangle sculpt on a Tier B iPad, the FBX in Unity).
- [ ] Hesham's own painted Nomad export joins the test resources as the fixture, with his name as the author (D-275).
- [ ] Unity has no licence-free headless run: the rigged glTF (with glTFast) and the FBX are checked on a computer (D-276).
- [ ] Painted and drawn rigs still leave glTF posed, not as skins; FBX carries one rigged thing per file and no paint
      texture (D-276, D-277).
- [ ] Clip-track clips (a walk on a person) aren't baked into glTF or FBX skins: only `bone.` keys are (D-276).
- [ ] A person rig's dots move but can't be added to (a tail on a person is a separate chain on another object for now).
- [ ] Placed models aren't cut finer for rigging; a very low-poly model bends at its own corners (D-262).
- [ ] Motion drops with a tap on the selection; dragging a motion tile onto a thing isn't offered (D-268).
- [ ] A forever loop exports as one stretch (engines loop it); repeats are played out frame by frame (D-269).
- [ ] An old lighter copy is left in the asset's folder when Detail goes back to the original.
- [x] Who does what gains placing pins and dots (D-252, D-267). Done in 0.14.
- [x] The Library's Motion and Rigs pages (D-227). Done in 0.14.
- [x] The rig steps' dimmed chips (D-238): the steps are gone (D-266).

## Left from U3 (Maquette 0.13)

- [ ] The device checklist in the "Maquette 0.13 — U3" PR (every gesture with misfires counted over a session, the
      sheet placed by hand and its four shapes, flipbooks in the air and the strip, sketching with the Pencil and its
      snaps felt in a Pencil Pro, squeeze and double-tap, the test pad and calibration, a Pencil without pressure, the
      number pad, the Reference window, the timeline with the Pencil).
- [ ] Flipbooks on a sheet are drawn over the shot, not hidden behind what stands in front of them (D-245).
- [ ] A flipbook drawn on an "on the object" sheet lies on its plane there, not on the curved surface (D-245).
- [ ] The frame's drawing guide (grid, perspective, symmetry) serves flipbooks stuck to the camera only; the sheet's
      plane guide serves ink on a flat sheet.
- [ ] Hold-to-clean-shape on the Board's own strokes and its squeeze menu's slots are fixed (draw, erase, colour, select,
      undo, redo): the Board's finish (M14).
- [ ] The number pad isn't typed from a hardware keyboard yet.
- [ ] Who does what has two jobs; placing pins and dots joins with U4 (D-252).
- [ ] The two-finger pan on the timeline runs only while a finger selects (D-256); the hover scrub hears any pointer, not
      only the Pencil.
- [ ] The magnet's details are a context menu: one switch per opening (D-254).

## Left from U2 (Maquette 0.12)

- [ ] The device checklist in the "Maquette 0.12 — U2" PR (the new homes, moving and folding the object panel, Perform
      waiting for a touch, the dark studio's contrast to the eye, the resting sidebar, the chrome-restraint trial both
      ways, the mini and the 13-inch in both orientations).
- [ ] The Library's Motion and Rigs pages come with U4, when poses, clips and rigs are saved things (D-227).
- [x] Settings ▸ Gestures lists the gestures; switching each off is U3's (D-237). Done in 0.13.
- [ ] Hatched shadows are U5's; the Reference window and the brush library dropping down came in 0.13 (D-239).
- [ ] The rig steps' chips are still dimmed until a step opens: U4 rebuilds rigging (D-238).
- [ ] Held rows that can't be walked (Dangle, Make it part of, the takes, the trigger deck, draggers) are gated in code
      but not asserted by the App Store walk; they need a rigged character to reach (D-228).
- [ ] The pinned object panel spot is per device, not per project.

## U1 in progress (Maquette 0.10.1, shipped with 0.12)

- [ ] A Paint stroke that starts on an object before it is ready to paint is dropped (it is made ready while chosen,
      so this is rare now); keeping that stroke is U3/U5's (D-224).
- [ ] Only the bone being weighed is drawn while its weights are worked out, not the whole pending rig (D-225).

- [ ] Hesham's first feel recording on 0.10.1 (the "before"); U1's fixes are aimed at what it ranks (PHASES, U1 step 2).
- [ ] The recorder times a touch to the first refresh after its answer is ready; the compositor's own frame after that
      is the same for every app and isn't counted (D-217).

## Left from M10 (Maquette 0.10)

- [ ] The device checklist in the "Maquette 0.10 — M10" PR (the front camera driving a drawn rig, a person rig and a
      2D puppet; the iPhone as the face camera; the microphone's mouth in a quiet and a noisy room, in English, Italian
      and Arabic, and beside playback and voiceover recording; hands on a humanoid; triggers under the fingers and
      from a keyboard while recording; dragging a hand while recording; a dangling tail, ears and hair while moving,
      live and in an export; breathing and blinking; a part with a face role; several takes and comping by dragging).
- [ ] The voice's shapes are tuned on synthetic vowels (D-211): the thresholds in `VoiceSolver.shape` want a pass with
      real voices on the device.
- [ ] Draggers stay where they're left and one joint is dragged at a time: return-to-rest on release and two hands at
      once need the stage's drag to be per touch (D-210).
- [ ] The trigger keys come through the menu bar, which only hears a key go down: a held key can't let go by lifting
      (a second press does). (D-209)
- [ ] Dangle samples the pose thirty-six times a frame for the characters that dangle; many dangling characters in one
      shot want a cache across consecutive frames (M15's smoothness pass, with the device's numbers).
- [ ] Dangle has no gravity, wind or collisions (D-204); objects without bones can't dangle (draw a bone through one).
- [ ] A part can't be chosen by tapping it on the stage while the character is selected; it's selected first, then
      Cast ▸ Make it part of (D-207). Parts ride bones of drawn rigs; rigged models from the library take parts only
      through Scene Scripts for now (no "Make it part of" for them in Cast).
- [ ] Fingers aren't tracked (D-212).
- [ ] The MCP bridge has no tools for takes, triggers or dangle (Scene Script v3 can set the properties with
      `setProperties`).
- [ ] Recording a take and recording a voiceover are two buttons (D-211): one "perform with sound" is a candidate for
      M15.

- [ ] The UI job on main ran 77 to 80 minutes on the 0.10 merge (a first attempt lost to a cold simulator, D-216);
      watch whether booting first brings it back under an hour.

## Left from M9 (Maquette 0.9)

- [ ] The device checklist in the "Maquette 0.9 — M9" PR (drawing on the board with the Pencil: feel, pressure, tilt,
      latency; one finger pans once the Pencil has touched; pinch and pan on a full board; the eraser; notes and the
      keyboard; arrows and frames; pictures from Photos, the clipboard and a drop; pinning, the card over the stage,
      standing it in the scene; the board after a force-quit; Settings ▸ Board off and on).
- [ ] Strokes on the board blend normally: a brush's other blend modes need board layers (D-201; hmm-kit's backlog).
- [ ] The MCP bridge has no board tools (read the board, add notes and arrows as a proposal). (D-201)
- [ ] A pin is a picture taken when it was pinned; it doesn't follow the board afterwards (pin again). (D-194)
- [ ] Reference cards are the same in every scene of a project (they belong to the workspace, not a scene).
- [ ] A pinned picture taken off the stage stays in `assets/references/` (a plane in a scene may show it); a cleanup
      when nothing refers to it any more.
- [ ] The board's Pencil has no hold-to-clean-shape and no latency numbers of its own yet (its double-tap, squeeze and
      the Pencil's feel came in 0.13): the Board's finish, M14.
- [ ] Cutaway mounts `HmmBoardScreen` next to the script in C2 (D-200).
- [ ] The brush library, imports and Brush Studio still live in Maquette; they move to hmm-kit when Cutaway's board
      needs them (D-189).

## Left from M8 (Maquette 0.8)

- [ ] The device checklist in the "Maquette 0.8 — M8" PR (the hold menu on the stage and the timeline, Pencil or hand
      with and without a Pencil, the Motion row, the colour well, the sphere, the panels above the sidebar, the
      preview lightening without a word, a bone drawn through a tail and through an arm in front of a body, the
      three rig steps).
- [ ] The preview lightens by its render scale only; lines and shadows keep their quality (D-176). M15's smoothness
      pass decides with the device's numbers.
- [ ] A finger that may make can't orbit with one finger where the guide fills the screen (a plane facing the view,
      the flipbook's page): two fingers pan and pinch, and a twist turns the view (D-183).
- [ ] Keys have no Duplicate and clips no Duplicate, Rename, Copy or Paste in the hold menu (dimmed rows, D-180,
      D-182).
- [ ] The hold menu over the timeline's lanes listens from the window: a panel floating over the lanes would open the
      lanes' menu under it. Nothing floats there today.
- [ ] Bounce and Swing aren't in Scene Script (the MCP's sixteen tools, D-184).
- [ ] A chain drawn again replaces the whole chain; redrawing just a part of one isn't offered (D-186).
- [ ] Hold-menu rows chosen in code (Hide / Show, Lock / Unlock, Loop / Play once) are in the String Catalog by hand:
      `Tools/strings.py` only sees a literal that follows the call's opening bracket.

## Left from M7 (Maquette 0.7)

- [ ] The device checklist in the "Maquette 0.7 — M7" PR (drawing bones with the Pencil on a placed model, a modelled
      part and a drawing; how fast the weights arrive on a big model; posing by dragging joints; painting weights and
      the weight view; rigging a person by the eight taps; a clip on the person rig; exporting a posed character and
      printing it).
- [ ] Apple's body-pose model placing the person rig's dots: the spike couldn't run it on CI (D-168); try it on the
      iPad, and ship it only with a device check of its own.
- [ ] glTF and the Blender package carry rigs as their posed shape, not as a skeleton with weights and keys (an
      armature in Blender). (D-173)
- [ ] Painting imported skinned characters (their own skeleton): still refused. (D-171, D-162)
- [ ] Weights update when a weight stroke ends, not under the brush as it moves. (D-172)
- [ ] Onion-skin ghosts of a rigged solid show it unposed.
- [ ] A drawn bone can't be removed on its own yet (Remove the rig takes them all; undo takes back the last one).
      Drawing along it again replaces it (0.8).
- [ ] The MCP bridge can't draw bones or rig a person yet (Scene Script v3 knows Puppets and clips).
- [ ] The layout walk's Model (and now and then Home) rows time out a UI query on CI's simulator: M5, M6 and M7's
      merges needed re-runs. (PR #22 looked at the stall in the New project sheet.)
- [ ] "A block with a hole in under thirty seconds" is timed on CI against 45 s (D-175); the 30 s is a device check.

## Left from M6 (Maquette 0.6)

- [ ] The device checklist in the "Maquette 0.6 — M6" PR (painting feel with the Pencil, strokes landing only on what
      the camera sees, layers, fill and the eyedropper, a projected picture, painting a placed Kit model, undo after
      relaunch, the painting benchmark at Tier A and as Tier B, an exported glTF and USDZ opened elsewhere).
- [x] Roughness, metal and glow painting (CONTEXT §10.4 "later"): done in 0.18, with bumps, fur and masks (D-338).
- [x] Painting characters with M7's skeletons: drawn rigs are painted in their rest pose (D-171); imported skins
      are in "Left from M7".
- [ ] Paint files no history refers to any more are kept: a cleanup when old versions are pruned.
- [ ] Every painted object keeps its layers on the GPU while it's drawn (16 MB a layer at 2048); objects not being
      painted could keep only their composite.
- [ ] A soft brush on a curved surface stamps in screen space: its dabs stretch slightly where the surface turns away
      (faded by the facing falloff, D-152).
- [ ] The eyedropper finds the closest triangle by a scan of the surface (fine at 50k triangles, slow far beyond).

## Left from M5 (Maquette 0.5)

- [ ] The device checklist in the "Maquette 0.5 — M5" PR (drawing feel with every built-in brush, prediction, tilt
      shading, the latency numbers, Brush Studio and its pad, importing real Procreate and Photoshop files, the guides
      with the Pencil, sharing a set by AirDrop).
- [ ] Brush settings Procreate has and the engine doesn't yet: colour dynamics, dual brush, wet mix and bleed, smudge
      and erase per brush. (D-141)
- [ ] The eraser is still a circle of points on screen, not a brush.
- [ ] Vanishing points are set with sliders; dragging them on the stage while the guide is shown. (D-149)
- [ ] The touch-to-screen latency is an upper bound (GPU completion + one refresh) until the SDK gives a drawable's
      presented time again. (D-146)
- [ ] A texturized grain on ink is fixed to the screen, so it slides over a stroke when the camera moves.
- [ ] 3D exports (glTF, USDZ, the Blender package) carry ink as its ribbon, not its brush stamps. (D-143)

## Left from M4 (Maquette 0.4)

- [ ] The device checklist in the "Maquette 0.4 — M4" PR (bevel, round, inset and shell on real parts; symmetry while
      modelling; snapping and the snap marks with the Pencil; measure and kept dimensions; the section view; the
      print check on a real part and the STL in a slicer; walls, doors, windows and stairs; the Blender package on a
      computer).
- [ ] Moving picked corners and edges (dragging them): M3's picks can bevel now, but not move.
- [ ] Rounded corners where three rounded edges meet are pointed (the cuts meet), not a rolling-ball patch. (D-125)
- [ ] The section view's cut faces are back faces drawn flat, not real caps: a thin open surface shows through. (D-131)
- [ ] FBX: not offered while the SDK's licence keeps it out (D-133); glTF covers the same apps.
- [ ] Core failure messages (booleans, push/pull, bevel…) reach the screen in English; the String Catalog only holds
      chrome strings (an M3 gap too).

## Left from M3 (Maquette 0.3)

- [ ] The device checklist in the "Maquette 0.3 — M3" PR (sketching and push/pull with the Pencil and fingers, the
      floating numbers and the keyboard, picks and the Pencil loop, booleans on real models, the marks' look).
- [ ] Curves that cross each other don't split into separate regions yet: only closed curves (and open ones joined
      end to end) fill. (D-121)
- [x] Bevelling picked edges, snapping to edges, midpoints and faces, the measure tool and kept dimensions (0.4).

## Left from M2 (Maquette 0.2)

- [ ] The device checklist in the "Maquette 0.2 — M2" PR (the layout on the iPad, the inspector beside the
      selection, time on call, panel resizing, Home's turning cards and the zoom into the stage, stacks, the
      templates, the Home benchmark at Tier A).
- [x] The print-bed outline in *Model to print* and the walls tool (Model ▸ Add ▸ Building) arrived in 0.4. (D-111)
- [x] *Sketch* in New project arrived with the Schizzo board in 0.9. (D-199)

## Left from M1 (Maquette 0.1)

- [ ] The device checklist in the "Maquette 0.1 — M1" PR (hover, force-quit recovery, the History scrubber, the
      benchmark at Tier A and as Tier B, the load chip).
- [ ] Calibrate `SceneCost`'s comfortable amounts per tier from the device benchmark JSONs. (D-97)

## Left from the remaster

- [ ] The device-only checklist in the "Remaster 2.0 — Phase 1" PR (#11).
- [ ] The device-only checklist in the "Remaster 2.0 — Phase 2" PR.
- [ ] Run the skill's evals against the iPad (`python skills/lowey/evals/run_evals.py`) and record the results and
      Hesham's verdicts in `skills/lowey/evals/runs/`. CI can't: it has no paired iPad and no API key. (R50)

## Planned (from 2.0)

- The laptop bridge in the App Store build, after App Review of its local network use. (R52)
- A studio bundle with the other hmm. apps; the StoreKit configuration is ready for testing it. (R52)

## Known limitations

- **Booleans keep everything in one object.** Subtracting a shape that splits a solid in two leaves both pieces in
  the first object; there's no Separate yet. Booleans need closed solids; a plane or an open drawing is
  refused with a message.
- **The renderer's mesh cache keys editable meshes by a 64-bit fingerprint.** Two different meshes with the same
  fingerprint would share a GPU mesh; with FNV-1a over every coordinate that's vanishingly unlikely. (D-116)

- **The Model tool's and the painting tools' touch-and-hold still adds to the selection** (or picks a face); the
  hold menu on the stage is the Select tool's. (D-181)
- **The inspector moves after things stop.** While you orbit or drag, it stays where it was and glides beside the
  selection once the view or the object rests (measuring every frame would cost the stage frames). (D-105)
- **A card shows its still until the project is opened and closed once in 0.2.** Turntables are drawn when a
  project closes; projects from earlier versions keep their old preview until then.

- **A change made in the last 50 ms before the app is killed can be lost.** The journal group-commits within 50 ms
  (D-90); nobody force-quits that fast, but a crash can.
- **Undo keeps 500 steps.** Older ones are dropped from undo (they stay in the journal's segments); the automatic
  versions (each opening, each hour of work) reach further back.
- **3D-lowey projects start their journal when Maquette first opens them.** Their earlier history doesn't exist, so a
  future time-lapse of them starts there.
- **The load meter's scene costs are estimates** until the device benchmarks calibrate them (D-97).
- **The brush outline's line gets thicker with the brush.** It's the gizmo's ring mesh scaled (the Shadow Brush's
  resize outline), for every brush tool including Paint ▸ Colour.

- **A script loop that never calls the API can't be stopped.** The time limit is checked at every `lowey` / `scene`
  call; JavaScriptCore has no public execution time limit on iOS. A pure `while (true) {}` keeps its worker thread
  busy until the app quits. (R29)
- **Golden images come from the simulator.** They catch regressions in the pipeline, not device-specific GPU
  differences; device renders are checked by eye from the PR's device checklist. (R8)
- **4K HEVC isn't exercised in CI.** The simulator's encoder has none; CI runs the same pipeline at 1080p H.264 and 4K
  HEVC is a device check. (R9)
- **MetalFX upscaling is device-only.** The simulator falls back to bilinear scaling, so dynamic resolution quality is
  a device check. (R9)
- **Sideloaded builds have no iCloud.** A free Apple ID can't sign the iCloud entitlement; projects stay on the
  device and move between devices as `.loweypack` files. (R24)
- **Live Activities depend on the system.** The export's Live Activity shows where the system displays them; the
  finished-export notification always arrives. (R19)
- **Only the sun casts shadows.** Point and spot lights light but don't shadow. (R6)
- **Perception's raster is about 320 × 180.** Coverage and visibility are exact at that size; subjects under about 3%
  of the frame aren't judged on their silhouette, and skinned characters are measured by their box. (R48)
- **Anticipation isn't measured.** The Motion line checks arcs, holds, easing and words; anticipation before big moves
  is in the critique module's checklist for the model to look for. (R48)
- **Some messages stay English.** Plurals built inside a sentence ("model\(n == 1 ? "" : "s")") aren't in the String
  Catalog; everything else is translated. (R51)
- **Placement is by boxes and Kit surfaces.** The relation solver knows a model's box, its top surfaces and its front;
  it doesn't fit concave shapes (a chair can't be slid under a desk by relation; use `offset`). (R46)

## Device checks for every release

Pencil hover on and off with every tool · force-quit mid-edit, reopen, undo · the History scrubber · the Night Market
benchmark numbers and its JSON (and the Tier B run on an M iPad) · Pencil pressure on drawing and the Shadow Brush · Pencil Pro squeeze
and roll · face capture (front camera) and the iPhone companion · the ARKit virtual camera · SpeechAnalyzer on a real
voiceover (English, Italian, Arabic) · thermal behaviour during a 5-minute 4K export · iCloud sync between iPad and
iPhone (App Store build) · pairing the bridge from a laptop.
