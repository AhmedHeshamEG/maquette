# Layout

Where everything in Maquette lives. This is the map of CONTEXT §4.1 and §10.1: the layout that freezes at 1.0
(after that, it changes only through a converge session with Hesham). New features go into homes that already exist.
U2 (Maquette 0.12) drew this map; "What moved in 0.12" at the end says what came from where.

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│ ⌂ Home  … Actions  ◐ Look  ☝ Select  ▤ Library        Model  Draw  Paint  Rig  Animate │  corner clusters
│ Scene 1 ▾  (the scene's name is a door)                                              │
│ ┃ slider                                                                             │
│ ┃                         the stage (≥ 85 % of the screen at rest)          ┌──────┐ │
│ ◉ Pick                                                                      │object│ │  the object panel floats
│ ┃ slider       (rests as a thin rail when no tool uses it)                  │panel │ │  beside the selection
│ ● colour                                                                    └──────┘ │  (a chip while something
│ ↶ ↷                                                                                  │   bigger is open)
│                                                                                      │
│ (joystick)                    (tool options)         ⏱ Timeline · Views · ⌖ · 🎥     │  bottom row
├──────────────────────────────────────────────────────────────────────────────────────┤
│ ▶ 0:01.12  Perform | Keys  ● Record  + Overlay  + Sound          …  ⌄                │  time on call: hidden,
│ the ruler · the tracks (the whole timeline's height remembered per project)          │  the slim transport, or
└──────────────────────────────────────────────────────────────────────────────────────┘  the whole timeline
```

## Rules

1. **One home per control.** A function has one place on screen. The menu bar, the keyboard and the gestures are
   other ways to reach it, not other homes. The outliner's eye and lock on each row are the list's own grammar (they
   act on that row), so the object's menu keeps Hide and Lock too.
2. **Top left is the document and the app** (Home, Actions, Look, Select, Library), **the scene's name under it is
   the scene** (its set-up, its scenes, its objects). **Top right is making** (Model, Draw, Paint, Rig, Animate), in
   the order a thing gets made. A tool with nothing in it yet isn't shown (no stubs).
3. **Time lives in the timeline**, and the timeline comes when called: the corner control (⏱) or Animate. Performing
   live, overlays on the video, sound and words are there.
4. **Actions holds making and sharing**: export, the project file, the Monitor, the Board, History, Learn, Settings.
5. **The object panel belongs to the selection.** It floats beside it and never covers it, can be moved by hand and
   stays where it was left, and folds to a chip (its name and Move · Turn · Size) while anything bigger is open.
6. **One big thing open at a time.** Opening a panel folds the whole timeline to its transport and the object panel to
   its chip; unfolding the chip closes the panel.
7. **Nothing is greyed out.** What a thing can't do right now isn't shown; what needs a selection lives on the
   selection. A label is never cut: it takes a second line.
8. **Every panel resizes** from the grip in its corner and **moves by hand** from its title row (double-tap the title
   to send it home, double-tap the grip for the original size); each remembers both on the device.
9. **Held features have their places reserved.** A row marked *(held: 1.x)* is built and works in every build but the
   App Store one, which airs it in that update (CONTEXT §5). The layout doesn't move when it appears.

## The walk

Each row's **Walk** is tapped by `LayoutWalkTests` (UI tests) from a new project: every step but the last is tapped,
and the last must be there. A step is an accessibility identifier (or the control's English label; a panel section is
`section-<its title>`). A row may start with a precondition: `[cube]` a cube is added and selected, `[blob]` a Blob is
added, `[timeline]` the whole timeline is open, `[transport]` the slim transport is showing, `[home]` the steps start
on Home instead of in a project. `Tools/layout_walk.py` turns this file into `AppUITests/LayoutWalk.swift`; CI fails
when they disagree. In the App Store configuration the walk asserts every held row's last step is **absent**.

## Home

| Control | Walk |
|---|---|
| New project: the + opens a blank project in the dark studio, named by itself | `[home] new-project` |
| Or start set up for Print, Room or Animation (the quiet row under the title) | `[home] start-print` |
| | `[home] start-room` |
| Search projects and stacks | `[home] gallery-search` |
| Sort (Recent, Name, Date created) | `[home] gallery-sort` |
| Select several (stack, move out, duplicate, archive, delete: shown once something is chosen) | `[home] gallery-select` |
| Import a project, the archive, Learn | `[home] theater-menu` |
| Settings | `[home] Settings` |
| Samples, once, as one card (Welcome island, the Enigma story) | `[home] samples` |
| Rename a project: tap its name | a card's name |
| A project's menu (the hold menu): duplicate, rename; add to stack (and move out), share (one file, a folder), archive; delete | touch and hold a card |
| A stack's menu: rename, unstack | touch and hold a stack |
| Make a stack | drag a card onto another |

## Top left

### Home (⌂)

| Control | Walk |
|---|---|
| Back to Home (the stage shrinks into its card) | `Home` |

### Actions

| Control | Walk |
|---|---|
| Export: the kind first (Video, Picture, 3D model), then its presets, the last used already picked; background export | `Actions › open-export` |
| Share the project file | `Actions › Project file` |
| Monitor window (Stage Manager, external display) | `Actions › open-monitor` |
| The Board: plan before building (below) | `Actions › open-board` |
| History scrubber, versions | `Actions › open-history` |
| Learn: the tour, every gesture, the instructions switch | `Actions › open-learn` |
| Settings | `Actions › Settings` |

### Look

Three short pages; the page is remembered.

| Control | Walk |
|---|---|
| Only this scene | `Look › Only this scene` |
| Style: Looks (Ink, Comic, Sketch, Clay, Low-poly, My Looks) | `Look › look-style › look-clay` |
| Style: duplicate as My Look (and its editor) | `Look › look-style › duplicate-look` |
| Style: the palette (linked colours; the sidebar's Pick fills the slot being edited) | `Look › look-style › Add a colour` |
| World: moods (Day … Studio, Dark studio) | `Look › look-world › mood-dusk` |
| World: fine tune the world | `Look › look-world › Fine tune the world` |
| World: save the world to the library | `Look › look-world › Save this world to the library` |
| Finish: clean, cinematic, dreamy, retro, ink outlines, collage, old film; grain, bloom | `Look › look-finish › Cinematic` |
| Finish: Motion (smooth, on twos, on threes) for the whole scene | `Look › look-finish › finish-motion` |

### Select

A small bar.

| Control | Walk |
|---|---|
| Tap to select | `Select › Tap` |
| Lasso | `Select › tool-lasso` |
| All (with a selection, also None and Similar) | `Select › select-all` |

### Library

| Control | Walk |
|---|---|
| Search everything (the Kit, your models, builds, worlds, scripts) | `Library › library-search` |
| Things: a Blob | `Library › library-things › add-blob` |
| Things: Me | `Library › library-things › add-me` |
| Things: a Puppet | `Library › library-things › add-character` |
| Things: the Kit by set | `Library › library-things › kit-sets` |
| Motion: poses, clips and loops; tap one to drop it on the selected thing; hold for its menu | `Library › library-motion` |
| A dropped motion plays where the joints match and says which it skipped; a motion's menu: rename, favourite, delete | tap or touch and hold a motion |
| Rigs: everything with a skeleton (the Kit's people, rigged models, saved rigged builds) | `Library › library-rigs` |
| Yours: your models, builds, worlds, scripts, favourites, recent; import models (USDZ, glTF, GLB, OBJ, STL, 3MF) | `Library › library-yours › Import models` |
| An item's menu (the hold menu): rename, favourite; replace with the selection (builds); delete | touch and hold an item |
| Swap a shape for a model | the object's menu ▸ More ▸ Swap for a model… (the Library opens to swap) |

### The scene (its name)

| Control | Walk |
|---|---|
| Set up for: Blank, Print, Room, Animation (what's in reach changes, never the project) | `scene-name › setup-room` |
| Scenes: switch, new, duplicate, rename; copy this scene to another project | `scene-name › scene-rename` |
| The objects (the outliner): pick, show or hide, lock; a row's hold menu (also: to top level, into a group, frame) | `scene-name › outliner` |

## Top right

### Model

| Control | Walk |
|---|---|
| Add: shapes (cube, sphere, cylinder, cone, plane, torus, ramp; bevelled), in the colour in the hand | `Model › model-add › add-cube` |
| | `Model › model-add › add-ramp` |
| Add: lamp, spot, sun | `Model › model-add › add-spot` |
| Add: 3D text | `Model › model-add › add-text3d` |
| Add: a photo or video (a card in the world) | `Model › model-add › add-media` |
| Add: effects (fire, sparks, smoke…) | `Model › model-add › add-fx-fire` |
| Add: Building, walls along tapped corners, floor, door, window, stairs | Model ▸ Add while the scene is set up for a Room |
| Edit: push/pull: pick faces, edges or corners (tap, Pencil loop), or a shape sketched in Draw | `Model › model-shape › pick-face` |
| Edit: 3D print: the printer, check for printing, repair | `Model › model-shape › print-check` |
| The Model tool's bar: pick modes, grow / shrink / select similar, bevel / round (edges), inset / shell (faces), the measurement and Keep, ✕ | shown at the bottom while the Model tool is on |
| The numbers on the stage (pull distance, sides, diameter, length, offset, a bevel's or shell's size, the wall height and thickness): tap to type | shown beside what they measure |
| Measurements and kept dimensions on the stage: tap one to keep it, or to select it | shown beside what they measure |
| Precision: the grid on the ground | `Model › model-precision › show-grid` |
| Precision: units (mm, cm, m, in, ft) | `Model › model-precision › units` |
| Precision: measure (two taps; keep it as a dimension) | `Model › model-precision › measure` |
| Precision: show kept dimensions | `Model › model-precision › show-dimensions` |
| Precision: section view across x, y or z, along the picked face; where it cuts; the other side | `Model › model-precision › section-x` |

### Draw

Everything the Pencil draws, all on **the sheet** (0.13): one see-through sheet under the Pencil. A finger-tap places it
(on a surface it lies there; in empty space it stands facing you), its grip pushes it nearer or farther, and the control
on its edge gives it one of four shapes. The panel closes on the first stroke; the tool's bar under the stage stays. Tap
Draw again for the panel.

| Control | Walk |
|---|---|
| Ink: draw, erase, select strokes | `Draw › tool-ink › ink-erase` |
| The brush ink draws with (opens the brush library) | `Draw › tool-ink › brush-ink` |
| Ink's drawing guide on a flat sheet: grid, isometric, symmetry; Drawing assist | `Draw › tool-ink › drawing-guide` |
| The sheet's edge: the grip (drag down: nearer, up: farther) | `Draw › tool-ink › sheet-grip` |
| The sheet's edge: four shapes (flat, around, dome; on the object when it lies on one) | `Draw › tool-ink › sheet-dome` |
| The sheet's edge: kept sheets, a new one, rename, curve, delete (with its drawings) | `Draw › tool-ink › sheet-menu` |
| Solid shape: tube, ribbon, extrude, lathe; mirror | `Draw › tool-draw › Tube` |
| Sketch on the sheet: line, rectangle, circle, arc, spline, offset; length, angle and snaps beside the tip | `Draw › tool-sketch › sketch-rectangle` |
| | `Draw › tool-sketch › sketch-offset` |
| The sketch's bar: the shapes, Done, ✕ | shown at the bottom while sketching |
| Flipbook: draw, erase, tracks; on the sheet, or stuck to the camera | `Draw › tool-flipbook › flipbook-on-camera` |
| | `Draw › tool-flipbook › flipbook-tracks` |
| The brush flipbooks draw with (opens the brush library) | `Draw › tool-flipbook › brush-flipbook` |
| The frame strip: the drawings; step, add, reorder, hold longer, onion skin, loop, erase | `Draw › tool-flipbook › frame-strip` |
| The frame's drawing guide (stuck to the camera): 2D grid, isometric, 1-, 2- and 3-point perspective, symmetry; Drawing assist | in Flipbook while it's stuck to the camera |
| The brush library drops down from the brush row: sets on the left, the set's brushes on the right | `Draw › tool-ink › brush-ink › brush-dropdown` |
| The whole library: sets, choose a brush, new set, share a set, import Procreate (.brushset, .brush) and Photoshop (.abr) brushes | the drop-down's last row |
| A brush's menu (the hold menu): duplicate, rename; Brush Studio, reset, move to a set; delete | touch and hold a brush in the library |
| Brush Studio: stroke, shape, grain, dynamics, Pencil, rendering, about; the pad to try it | a brush's menu ▸ Edit in Brush Studio |

### Paint

The panel closes on the first stroke; the tool's bar under the stage stays. Tap Paint again for the panel.

| Control | Walk |
|---|---|
| Colour: paint, erase, fill and the eyedropper on models | `Paint › tool-paint › paint-pick` |
| The brush painting uses (opens the brush library) | `Paint › tool-paint › brush-paint` |
| The chosen object is made ready to paint the moment Paint is in the hand (laid flat, or its paint carried onto a changed shape): no button, no message; *Paint it* appears only if that didn't work | shown when Paint opens with an object chosen |
| Layers: show or hide, the one the Pencil paints on, its opacity and blend, add a layer | `[cube] Paint › tool-paint › paint-layer-add` |
| A layer's menu: duplicate, merge down, move up or down, clear, rename, delete; remove all paint | `[cube] Paint › tool-paint › paint-layer-menu` |
| A layer's hold menu: duplicate, rename; merge down, clear; delete | touch and hold a layer |
| Project a picture: from Photos or Files, placed with the fingers, Project from the options bar | Paint ▸ Colour on a painted object |
| Paint, erase, fill, eyedropper, the layer painted on, done (options bar) | shown under the stage while Colour is on |
| Size and opacity of the paint brush | the sidebar's two sliders while Colour is on |
| Shadow Brush: push shadow in, pull light out | `Paint › tool-shadow-brush › Push shadow in` |
| Shadow presets | `Paint › tool-shadow-brush › section-Presets` |
| Scatter's options (how many, size variety, spacing) | under the stage while Scatter (from the object panel) is on |

### Rig

| Control | Walk |
|---|---|
| With nothing selected: where characters come from | `Rig › rig-open-library` |
| Body shortcuts: Person (the dots guessed from the shape on its front view; drag the wrong ones, Rig) | `[cube] Rig › rig-body-person` |
| Body shortcuts: Chain (one stroke along a tail or a rope lays pins down it) | `[cube] Rig › rig-body-chain` |
| Body shortcuts: Four legs, Wings (the dots guessed from the shape, or in the usual places; drag the wrong ones) | `[cube] Rig › rig-body-fourLegs` |
| Pins and dots by hand (tap to place one, a stroke for a chain, drag to move, hold to take away) | `[cube] Rig › rig-marks` |
| A dot is a joint, a pin a soft bend; tap a mark so the next hangs from it, double-tap it to switch pin and dot | the marks on the stage while Rig is on |
| The Rig tool's bar: Dots or Pins for the Pencil, done; a person's Rig and cancel; the weight brush's bone, erase and done | shown under the stage while Rig is on |
| Several things chosen: rig them together (each part rides the bone nearest it; a dot between two parts hinges them) | Rig with two or more things selected |
| Rigged: change the rig (it relaxes to its rest shape and shows its pins and dots; poses and keys stay), reset the pose, remove the rig | Rig on a rigged thing |
| How it bends: paint weights; fit the weights to a new shape | Rig ▸ How it bends, on a rigged thing |
| Pose: Dangle for the joint last touched (and everything below it) *(held: 1.2)* | Rig on a rigged thing, after touching a joint |
| A character's poses: save, apply, mirror | `[blob] Rig › save-pose` |
| A pose's hold menu: apply mirrored, save a mirrored copy, save to the Library | touch and hold a pose |
| A character's clips: play from the playhead, tune, feet on the ground, look at, walk speed, crowds | `[blob] Rig › section-Clips` |
| Make a loose object a part of a drawn rig (it rides the nearest bone); a part's face role, its bone, take it off *(held: 1.2)* | Rig ▸ Make it part of / Part, with that object selected |
| The weight brush's size and strength | the sidebar's two sliders while painting weights |
| Pose any character by dragging its joints (IK): a pin bends only its stretch, a dot brings its limb along | the joints on the stage when a character is selected |
| A model that just came in (Open in, the share sheet, a drop, Home's import): Rig it, once, at the top of its panel | after a model lands |

### Animate

| Control | Walk |
|---|---|
| The whole timeline | `Animate › timeline` |

## The object panel (beside the selection)

| Control | Walk |
|---|---|
| Name (the header is the panel's grip: drag it anywhere; double-tap it to go back beside the selection) | `[cube] inspector-name` |
| Move, turn, size (the gizmo and the joystick) | `[cube] gizmo-rotate` |
| Its size in the project's units, and what the Model tool picked | `[cube] selection-size` |
| Colour (the scene's palette) | `[cube] section-Colour` |
| What kind of thing it is: a light's, a text's, an overlay's, an effect's own controls | in the panel for those things |
| Make it move, one strip: loops (spin, float, bounce, wiggle, swing, follow a path), then once-moves; speed, keyframes | `[cube] motion-bounce` |
| | `[cube] preset-popIn` |
| On the selection: Scatter copies on the ground | `[cube] tool-scatter` |
| On the selection: Mirror and symmetry | `[cube] mirror` |
| On the selection: Make editable | `[cube] make-editable` |
| On the selection: Combine (union, subtract, intersect), with two or more shapes | in the panel when two or more shapes are selected |
| Look of this object: glow, smoothing, bevel; its own Look, line weight, rim light, accent, gloss | `[cube] object-look` |
| More ways to move: once-moves' length, behaviours, animated on (ones…fours), physics, joints, paths, onion skin | `[cube] more-motion` |
| Numbers: position, rotation, size | `[cube] transform-toggle` |
| About this object | `[cube] inspector-more` |
| Duplicate, hide | `[cube] Duplicate` |
| The object's one menu (the same as touching and holding it) | `[cube] more-actions` |
| Delete | `[cube] Delete` |
| Resize | `[cube] resize-inspector` |
| Align and distribute (several selected) | in the panel when more than one thing is selected |
| Camera: shot, framing, lens, focus, moves, transitions | in the panel when a camera is selected |
| Fold to a chip (its name and Move · Turn · Size); tap the name to unfold | `[cube] fold-inspector` |

## The sidebar

| Control | Walk |
|---|---|
| Resting: a thin rail where the sliders sit (touch it for size and opacity) | `sidebar-rail` |
| Two sliders that follow the tool (size and opacity) | Draw, Paint, the weight brush, Perform |
| Pick a colour from the stage | `Draw › tool-ink › Pick` |
| The colour in the hand (the palette, any colour), for every tool that makes something, Model ▸ Add included | `Draw › tool-ink › colour-well` |
| Undo, redo (they never rest) | `Undo` |

## The bottom row

| Control | Walk |
|---|---|
| The timeline on call | `timeline-toggle` |
| Views (top, front, side; perspective or orthographic) | `views-menu` |
| The Snap magnet: everything that snaps, on or off (a finger held down while the Pencil works flips it for that move) | `snap-magnet` |
| The magnet's details: the grid and its size, corners and middles, edges, faces, objects, the ground, turning in steps, how near | touch and hold the magnet |
| Frame the selection | `Frame the selection` |
| The camera button: tap to look through (again: the next, then back); hold for a new camera from this view | `camera-button` |
| Joystick (on by default; its × hides it, Settings ▸ Stage brings it back) | `[cube] hide-joystick` |
| Tool options (ink, solid shape, sketch, the flipbook's frame strip, Shadow Brush, scatter, Model, Rig) | below the stage while that tool is on |
| The trigger deck: the selected character's triggers under the fingers *(held: 1.2)* | below the stage with Select in the hand while the timeline is in Perform |

## The timeline

Eight controls: play, the time, Perform | Keys, the mode's one button, + Overlay, + Sound, the menu, collapse.

| Control | Walk |
|---|---|
| Keys | `[timeline] timeline-mode-keyframe` |
| Perform: Record arms it (Ready); touching the stage starts time, lifting the hand stops it | `[timeline] timeline-mode-perform › perform-record` |
| Key the selection at the playhead (Keys' one button, with something selected); after the first key, changes key themselves | the timeline in Keys, with a selection |
| + Overlay: a title, a label, marks (arrow, circle, star…), screen effects at the playhead | `[timeline] add-overlay` |
| + Sound: voiceover, music, effects, transcript | `[timeline] Sound and words` |
| The menu: a marker, the loop; the mode's extras (keys, easing, the graph; what a touch performs); fit, settings | `[timeline] timeline-menu` |
| Collapse to the slim transport | `[timeline] Collapse the timeline` |
| Resize, or switch to the transport | `[timeline] timeline-divider` |
| The ruler: drag to scrub; tap just beside the playhead to step a frame; flick left to go to the start | `[timeline] timeline-ruler` |
| A selected row's whole animation: drag the grip under it to slide it in time; drag the dot at its end to repeat it (the repeats show lighter) | under a selected animated row |
| The grip's hold menu: loop forever or play once; save as a clip or a loop to the Library | touch and hold the grip |
| A key's hold menu: copy, paste; feel (ease, snap, bounce, straight; the curve one step deeper), reverse, mirror; delete | touch and hold a key |
| A clip's hold menu: split at the playhead, loop or play once; delete | touch and hold a clip |
| A flipbook drawing's hold menu: duplicate; hold longer, hold shorter; delete (the track's is on its name) | touch and hold a drawing |
| Perform with a character: its button beside Record | `[blob] Animate › timeline-mode-perform › perform-character` |
| The character's expressions, lip sync, face capture (front camera, iPhone) | inside the character's button |
| The microphone drives the mouth (live voice), with its level *(held: 1.2)* | `[blob] Animate › timeline-mode-perform › perform-character › voice-live` |
| Triggers: one tap for an expression, a saved pose or a swap, a key each *(held: 1.2)* | `[blob] Animate › timeline-mode-perform › perform-character › add-trigger` |
| Life: breathes, blinks on its own, which bone is its head *(held: 1.2)* | `[blob] Animate › timeline-mode-perform › perform-character › life-breathe` |
| Takes: every recording, newest on top, bright where it plays; drag across one to use it from there to there; its hold menu *(held: 1.2)* | above the lanes in Perform once something was recorded |
| Draggers: a joint dragged while a take records is performed *(held: 1.2)* | the joints on the stage while recording |
| The slim transport: play, the time, ±10 s, a frame back and forward | `[transport] Play` |
| Back to the whole timeline | `[transport] Show the timeline` |
| Send the timeline away | `[transport] hide-timeline` |

## The Board

A 2D sheet for planning, one in every project (CONTEXT §10.7). It covers the stage while it's open and has the same
grammar: the board itself top left, the making tools top right, the sidebar, the hold menu. It is hmm-kit's
`HmmBoardScreen`, so Cutaway's board will be the same board.

| Control | Where |
|---|---|
| Back to the stage | top left, first |
| Actions: add a picture (Photos), paste (what was copied on a board, or a picture copied anywhere), select all, the paper (dots, grid, plain; dark or light), share a picture, pin the whole board | top left |
| Select: tap to pick, drag to move, the handles to size, a box from empty space to pick several; tap a picked note again to type on it | top left |
| Draw (the brush engine: pressure, tilt, every brush), Erase (cuts strokes where it touches), Note, Arrow (its ends follow the notes and pictures they point at), Frame (a named area that carries what's in it) | top right |
| Size, opacity, the colour in the hand (the Look's palette, any colour), undo, redo | the sidebar |
| The brush the board draws with (opens the brush library) | under the board while Draw is on |
| Pin to the project, duplicate, delete | under the board while something is picked |
| The zoom (tap: show everything) | bottom right |
| Move the view: two fingers (one, once a Pencil has touched) pan, pinch zooms, double-tap fills the view with the frame under the finger or with everything | on the board |
| A thing's hold menu: duplicate, rename (frames), copy, paste; pin to the project, bring to the front, send to the back; delete | touch and hold a thing with Select |
| Pictures: drop them on the board from any app | on the board |
| Pinned pictures (reference cards): drag to move, the corner to size; their hold menu: open the board, stand it in the scene (a plane, an object like any other); delete | floating over the stage |

## The hold menu

Touch and hold any thing and the same menu opens in the same order (CONTEXT §4.1): **Duplicate · Rename · Copy ·
Paste**, then one to three extras that fit the thing, then **Delete** in red. The first four and Delete are always in
the same places; a row a thing can't do is dimmed. An object's menu holds everything it can do: Hide, Lock, and More
(Group or Ungroup, Array, To the ground, Swap for a model, Save to the library, Unpack); on the stage, with other
things selected, **Add to the selection** comes first. A finger held still on an object opens it; a finger that moves
is a drag. The same object has the same menu on the stage, in the outliner, on its timeline row and behind its panel's
⋯ button. Also on: keys, clips, flipbook drawings and tracks, cuts, screen effects, paint layers, brushes, Looks,
library items, poses, palette colours, Home's cards and stacks, and the things on the Board.

## Settings

In this order. From Home (the gear) and from Actions.

| Control | Where |
|---|---|
| Pencil or hand: draw with a finger too (automatic otherwise: a finger makes until an Apple Pencil has touched); the Pencil's hover point | Settings ▸ Pencil and hands |
| Every gesture and shortcut | Settings ▸ Gestures |
| Always show the sidebar, always full resolution, moving-around speed, dock the object panel, the joystick and its speed, the Board on or off | Settings ▸ Stage |
| Theme, sidebar on the right, haptics | Settings ▸ Appearance |
| The assistant on this network (the laptop bridge for MCP), pairing and proposals, Scripts, paste a script; with Hesham's note | Settings ▸ Assistant |
| Version, licences; Diagnostics: the feel recorder, the benchmarks, the Pencil's latency, smoothness, logs, the chrome-restraint trial | Settings ▸ About |
| iCloud Drive | Settings ▸ Storage |

## Learn

From Home (the ⋯ menu) and from Actions: the tour, every gesture and shortcut, and the instructions switch (the short
explanations in panels; on by default).

## Elsewhere, on purpose

- **Gestures** (CONTEXT §4.1): two-finger tap undo, three-finger tap redo, two-finger hold rapid undo, four-finger
  tap hides everything but the stage, pinch, double-tap to frame, touch and hold for the hold menu.
- **The undo line**: what an undo or a redo changed, for a second at the top centre.
- **The guide line**: one line at the bottom while a guided step runs (picking a colour, scattering, building walls),
  gone the moment it ends.
- **Under load nothing is said on the stage** (CONTEXT §6): the preview lightens by itself and comes back.
- **The menu bar and keyboard** reach the same controls: ⌘1–⌘5 Model, Draw, Paint, Rig, Animate; ⌘6–⌘8 Actions, Look,
  Select; ⌘L the Library; ⌥⌘1–3 move, turn, size; ⌘T the timeline; Space/J/K/L and ⌥←→ the transport. Holding ⌘ lists
  them. The Perform menu (the microphone, the trigger keys) is *(held: 1.2)*.
- **Proposals** from the AI bridge appear at the bottom of the stage while one is waiting.

## What moved in 0.12 (U2)

| 0.11 | Now | Why |
|---|---|---|
| Cast (top right) | gone: Blob, Me, Puppet in the Library; rigging in Rig; performing in the timeline's Perform | "idk why cast exists in the first place" (D-227) |
| Model ▸ Library | the Library, its own button top left (Things · Yours) | Placing a ready thing isn't modelling (D-227) |
| Model ▸ Add ▸ Camera | the camera button (bottom right) | Looking through a camera is about the view (D-229) |
| Model ▸ Add ▸ Title, Label, marks on the frame, screen effects | the timeline's + Overlay | They sit on the video, not in the world (D-229) |
| Model ▸ Add ▸ Building | Model ▸ Add while set up for a Room | Only the Room job needs it (D-229) |
| Actions ▸ Scenes | the scene's name | The scene is a door (D-230) |
| Select ▸ the outliner | the scene's name | The scene's objects are the scene (D-230) |
| Select (a panel) | a small bar | Five buttons don't need a panel |
| Actions ▸ Scripts, AI & laptop, Paste script | Settings ▸ Assistant | Actions shows only making and sharing |
| Actions ▸ Gestures, Tour | Learn (Actions and Home) | One Learn place |
| Actions ▸ Diagnostics | Settings ▸ About | |
| New project sheet (name, template, mood, Look) | the + goes straight in; set-ups a quiet row; Mood and Look in Look | No decision walls (D-233) |
| Inspector: Move it + Motion (two lists) | Make it move (one strip) and More ways to move | Every motion once (D-231) |
| Inspector: More actions menu | the object's one menu (the same as its hold menu) | One menu per object (D-232) |
| Model ▸ Edit ▸ Combine, Mirror, Make editable; Paint ▸ Scatter | on the selection, in its panel | What needs a selection lives on it |
| The sidebar's Snapping and Speed sliders | Model ▸ Precision (snapping distance); Settings ▸ Stage (speed) | The sidebar means size and opacity |
| Timeline: Compose · Perform · Keyframe | Perform · Keys, as words | Sliding an animation is its grip, in either (D-234) |
| Timeline: transport buttons, Add marker, auto-key, key menus in the bar | play only; markers, loop and the modes' extras in the menu; a flick and taps on the ruler | Eight controls (D-234) |
| Timeline settings ▸ Stepping | Look ▸ Finish ▸ Motion | It's how motion looks |
| Look: one long page | Style · World · Finish | Progressive disclosure |
| Export: every preset at once | the kind first | |

Earlier moves (2.0 → 0.8) are in the git history of this file.
