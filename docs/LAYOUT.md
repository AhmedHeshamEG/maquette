# Layout

Where everything in Maquette lives. This is the map of CONTEXT §4.1 and §10.1: the layout that freezes at 1.0
(after that, it changes only through a converge session with Hesham). New features go into homes that already exist.
U2 (Maquette 0.12) drew this map; U5 (0.15) made Draw one tool and gave every making tool one bar. "What moved" at the
end says what came from where.

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│ ⌂ Home  … Actions  ◐ Look  ▤ Library                    Model  Draw  Rig  Animate    │  corner clusters (rest
│                                                                                      │  to faint rails while
│                                                                                      │  the hand draws)
│ Scene 1 ▾  (the scene's name is a door)                                              │
│ ┃ slider                                                                             │
│ ┃                         the stage (≥ 85 % of the screen at rest)          ┌──────┐ │
│ ◉ Pick                                                                      │object│ │  the object panel floats
│ ┃ slider       (rests as a thin rail when no tool uses it)                  │panel │ │  beside the selection
│ ● colour                                                                    └──────┘ │  (a chip while something
│                                                                                      │   bigger is open)
│                                                                                      │
│ (joystick)        (the tool's bar: Draw's is Brush Smudge Erase Sheets Colour)       │  bottom row
│                                                      Views · 🎥 · Joystick · Snap    │  the view corner
├──────────────────────────────────────────────────────────────────────────────────────┤
│ ▶ 0:01.12  Perform | Keys  ● Record  + Sound                     …  ⌄                │  time on call: hidden,
│ the ruler · the tracks (the whole timeline's height remembered per project)          │  the slim transport, or
└──────────────────────────────────────────────────────────────────────────────────────┘  the whole timeline
```

## Rules

1. **One home per control.** A function has one place on screen. The menu bar, the keyboard and the gestures are
   other ways to reach it, not other homes. The outliner's eye and lock on each row are the list's own grammar (they
   act on that row), so the object's menu keeps Hide and Lock too.
2. **Top left is the document and the app** (Home, Actions, Look, Library), **the scene's name under it is the scene**
   (its set-up, its scenes, its objects). **Top right is making** (Model, Draw, Rig, Animate), in the order a thing
   gets made; **each opens one bar of at most six verbs** under the stage, deeper things behind them (U5). A tool with
   nothing in it yet isn't shown (no stubs). Both clusters rest to a faint rail while the hand draws and come back when
   a finger or the hovering Pencil comes near.
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
| History scrubber, versions; over it, the selected thing's modelling steps to change (H1) | `Actions › open-history` |
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
| World: the real sun (a place, a date, a time; a shadow study across the timeline; which way north is), in Fine tune the world | Look ▸ World ▸ Fine tune the world ▸ Real sun |
| Finish: clean, cinematic, dreamy, retro, ink outlines, collage, old film; grain, bloom | `Look › look-finish › Cinematic` |
| Finish: Motion (smooth, on twos, on threes) for the whole scene | `Look › look-finish › finish-motion` |
| Finish: screen effects at the playhead (a flash, a shake…) | `Look › look-finish › finish-screen-effects` |

### Library

| Control | Walk |
|---|---|
| Search everything (the Kit, your models, builds, worlds, scripts) | `Library › library-search` |
| Things: the Kit by set | `Library › library-things › kit-sets` |
| Characters ▸ New: from a person, four legs, wings, a blob or nothing; the character lands with its panel open and rigs itself | `Library › library-characters › new-character-person` |
| Characters: a Blob | `Library › library-characters › add-blob` |
| Characters: Me | `Library › library-characters › add-me` |
| Characters: a Puppet | `Library › library-characters › add-character` |
| Motion: poses, clips and loops; tap one to drop it on the selected thing; hold for its menu | `Library › library-motion` |
| A dropped motion plays where the joints match and says which it skipped; a motion's menu: rename, favourite, delete | tap or touch and hold a motion |
| Characters: everything with a skeleton (the Kit's people, rigged models, saved rigged builds) | `Library › library-characters` |
| Yours: your models, builds, worlds, scripts, favourites, recent; import models (USDZ, glTF, GLB, OBJ, STL, 3MF) | `Library › library-yours › Import models` |
| An item's menu (the hold menu): rename, favourite; replace with the selection (builds); delete | touch and hold an item |
| Swap a shape for a model | the object's menu ▸ More ▸ Swap for a model… (the Library opens to swap) |

### The scene (its name)

| Control | Walk |
|---|---|
| Set up for: Blank, Print, Room, Animation (what's in reach changes, never the project) | `scene-name › setup-room` |
| Scenes: switch, new, duplicate, rename; copy this scene to another project | `scene-name › scene-rename` |
| Physics: gravity, wind, a solid ground, when things start; the run and Keep it | `scene-name › gravity-moon` |
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
| Add: forces (fan, pull, whirl) and fluids (pour water, splash, billowing smoke, flames) | `Model › model-add › add-force-fan` |
| | `Model › model-add › add-fluid-pour` |
| Add: Building, walls along tapped corners, floor, door, window, stairs | Model ▸ Add while the scene is set up for a Room |
| Edit: Shape it: Shape, Brush, Cage, Bend (no buttons for faces, edges or corners: the Pencil touches the part, U6) | `Model › model-shape › model-verb-shape` |
| | `Model › model-shape › model-verb-cage` |
| Edit: 3D print: the printer, check for printing, repair | `Model › model-shape › print-check` |
| Model's bar: Shape · Brush · Cage · Bend · Measure; the brushes (grab, smooth, inflate) and their mirror; the cage on, back or off; the bend's kind, axis and amount; the measurement and Keep, ✕ | shown at the bottom while the Model tool is on |
| Touch and drag (U6): over the selected shape the Pencil lights the face, edge or corner under its tip; a drag pulls a face, rounds an edge, moves a corner; a tap picks it | the Pencil on the selected shape, with any tool but Draw |
| The part's chip: a face's inset, shell, bridge (two faces), knife; an edge's bevel, round, loop cut, knife; corners' merge and fill the hole; ⋯ grow, shrink, similar, the pivot here | above the tool's bar |
| A sketch region's chip: sweep along a path, revolve around a line (or its own side), loft through more shapes | above the tool's bar |
| Sketch lines' rules: one line (lock its size, its angle, level), two (parallel, square, same size, twice that), a line and a circle (touching); a size's lock | above the tool's bar; the lock beside a size |
| The cage's points and the bend's handle | on the stage with Cage or Bend in the hand |
| The numbers on the stage (pull distance, sides, diameter, length, offset, a bevel's or shell's size, the wall height and thickness): tap to type | shown beside what they measure |
| Measurements and kept dimensions on the stage: tap one to keep it, or to select it | shown beside what they measure |
| Precision: the grid on the ground | `Model › model-precision › show-grid` |
| Precision: units (mm, cm, m, in, ft) | `Model › model-precision › units` |
| Precision: measure (two taps; keep it as a dimension) | `Model › model-precision › measure` |
| Precision: show kept dimensions | `Model › model-precision › show-dimensions` |
| Precision: section view across x, y or z, along the picked face; where it cuts; the other side | `Model › model-precision › section-x` |

### Draw

**One Draw** (U5): Procreate's five under the stage, Brush · Smudge · Erase · Sheets · Colour. No panel opens. What the
Brush holds decides what the Pencil makes: a library brush draws **lines** (one from a painting set puts **colour on a
model**, and then Sheets becomes **Layers**), and under the library's sets are the making sets **Solids**, **Shapes**
and **Shadow**. Zero setup: a stroke begun over a surface lands on it; in the air it lands on **the sheet**, which faces
you until a finger's tap places it, and reads as paper while you draw. Tap Draw again to put it down.

| Control | Walk |
|---|---|
| Draw's bar: Brush, Smudge, Erase, Sheets (or Layers), Colour | `Draw › draw-bar` |
| Brush: tap it while it's in the hand and the library drops down: sets on the left, brushes on the right | `Draw › draw-brush › brush-dropdown` |
| Solids: tube, ribbon, extrude, lathe; mirror, depth | `Draw › draw-brush › brush-set-solids` |
| Shapes: line, rectangle, circle, arc, spline, offset, each in one drag; a closed one gets an arrow to pull | `Draw › draw-brush › brush-set-shapes` |
| Shadow: shadow in, light out; presets on the selection | `Draw › draw-brush › brush-set-shadow` |
| The whole library: sets, choose a brush, new set, share a set, import Procreate (.brushset, .brush) and Photoshop (.abr) brushes | `Draw › draw-brush › brush-library-open` |
| Smudge: push lines into a new shape | `Draw › draw-smudge` |
| Erase (what's in the hand: lines, frames, paint) | `Draw › draw-erase` |
| Sheets: the sheets kept in the scene (draw on one again, rename, delete with its drawings), a new one | `Draw › draw-sheets › sheet-new` |
| Frames: frame by frame on the sheet (or stuck to the camera), tracks, blend, opacity, loop, hold, drawn effects | `Draw › draw-sheets › draw-frames` |
| Colour: the picker (disc, values, palettes, recent, the scene's palette) and Materials (fill, drag, Paint it on, Edit, Import) | `Draw › colour-well` |
| Layers (in place of Sheets while a paint brush is over a thing): what the brush paints (Colour, Roughness, Metal, Glow, Bumps, Fur, the Mask) and its value; show or hide, the one painted on, each layer's maps; swipe for Mask, Duplicate, Delete; drag to reorder; pinch to merge; a fill's controls; opacity, blend, Add (layer, colour fill, dirt, worn edges), the layer's menu; project a picture | shown while a paint brush is over a thing |
| Surface (beside Layers, U7): Brushes (Faces, Seams with Cut and Automatic), Wear, Decal, Mirror, Texture size, Flat view, Detail from a sculpt, Fur | shown while a paint brush is over a thing |
| The sheet's hold menu: place (nearer, farther, face me), shape (flat, around, dome, on the object), guide (grid, isometric, symmetry), rename, delete | touch and hold the sheet |
| The frame strip: the drawings; step, add, reorder, hold longer; hold one and let go for a copy; loop | over the bar while frames are drawn |
| Flick right with a finger for a new frame, left for the one before | on the stage while frames are drawn |
| Onion skins: up to eight each way, their colours | the time at the bottom left while frames are drawn |
| A stroke's chip: the brush and colour in the hand, thickness (drag or type), smooth, delete; drag along it with the Pencil to reshape it | tap a stroke with the Pencil |
| The eyedropper: a ring shows the colour under the finger and the one in the hand | a finger held on a thing while drawing |
| The frame's drawing guide (stuck to the camera): 2D grid, isometric, 1-, 2- and 3-point perspective, symmetry | Sheets ▸ Frames while stuck to the camera |
| A brush's menu (the hold menu): duplicate, rename; Brush Studio, reset, move to a set; delete | touch and hold a brush in the library |
| Brush Studio: stroke, shape, grain, dynamics, Pencil, rendering, about; the pad to try it | a brush's menu ▸ Edit in Brush Studio |
| Size and opacity of the brush | the sidebar's two sliders while drawing |
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
| On the selection: Model it (a placed library model; shapes are always editable) | in the panel of a placed model |
| On the selection: Combine (union, subtract, intersect), with two or more shapes | in the panel when two or more shapes are selected |
| Look of this object: glow, smoothing, bevel; its own Look, line weight, rim light, accent, gloss | `[cube] object-look` |
| Shape of this object: typed sides, Smooth, the smooth angle, triangles, clean up, holes, linked copies, the pivot | `[cube] object-shape` |
| Real: a material in words, how it moves, its weight; joints; Settle, Does it stand?, Keep it; exact numbers deeper | `[cube] object-real` |
| Give it parts: eyes, arms, a mouth… (the thing becomes the body of a character that rigs itself) | `[cube] character-give` |
| A made character's parts: every job a tap away (hold one for its styles), Mirrored; the picked part's styles, Take it away | in the panel of a made character |
| A made character: Face (the states of its mouth, brows and eyes; tap to see one, bend it one step deeper) | in the panel of a made character |
| A made character: Proportions (each in metres; handles on the stage: head, feet, hands, waist) | in the panel of a made character |
| A made character: Say a line (lip sync from typed words, from the playhead) | in the panel of a made character |
| A made character: Act it out (film yourself or a video; the character copies the body), people only | in the panel of a made person |
| A made character: For games (engines, sprite sheets, turnaround) | in the panel of a made character |
| A drawing or a modelled thing near a character: Make it a part (or the drawing of a face state) | in the panel of a drawing |
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
| 3D text: Stick to the camera (a title that stays put on the picture) | in the panel of 3D text |
| Every number is a slider: drag it (slowly for fine, fast for coarse) or tap it to type | the numbers in the panel and on the stage |

## The sidebar

| Control | Walk |
|---|---|
| Resting: a thin rail where the sliders sit (touch it for size and opacity) | `sidebar-rail` |
| Two sliders that follow the tool (size and opacity) | Draw, the weight brush, Perform |
| Pick a colour from the stage | `Draw › Pick` |
| The colour in the hand (the palette, any colour) while Model ▸ Add is open (Draw has its own) | the sidebar while Model ▸ Add is open |
| Undo, redo: only when Settings ▸ Gestures shows them (two fingers tap undo, three redo) | Settings ▸ Gestures ▸ Show undo buttons |

## The bottom row

| Control | Walk |
|---|---|
| The view cube: tap a side to look from there, drag to turn, double-tap for perspective or flat; hold for the views and Frame all | `view-cube` |
| Views (top, front, side; perspective or orthographic), when Settings ▸ Stage hides the view cube | in the cube's place |
| The Snap magnet: everything that snaps, on or off (a finger held down while the Pencil works flips it for that move) | `snap-magnet` |
| The magnet's details: the grid and its size, corners and middles, edges, faces, objects, the ground, turning in steps, how near | touch and hold the magnet |
| The camera button: tap to look through (again: the next, then back); hold for a new camera from this view | `camera-button` |
| The joystick, on or off (on by default) | `joystick-toggle` |
| The tool's bar (Draw, Model, Rig, scatter) | below the stage while that tool is on |
| The trigger deck: the selected character's triggers under the fingers *(held: 1.2)* | below the stage with Select in the hand while the timeline is in Perform |

## The timeline

Seven controls: play, the time, Perform | Keys, the mode's one button, + Sound, the menu, collapse (U5: + Overlay went;
titles are 3D text that sticks to the camera, screen effects are in Look ▸ Finish).

| Control | Walk |
|---|---|
| Keys | `[timeline] timeline-mode-keyframe` |
| Perform: Record arms it (Ready); touching the stage starts time, lifting the hand stops it | `[timeline] timeline-mode-perform › perform-record` |
| Key the selection at the playhead (Keys' one button, with something selected); after the first key, changes key themselves | the timeline in Keys, with a selection |
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
(Group or Ungroup, Array, To the ground, Settle, Swap for a model, Save to the library, Unpack); on the stage, with other
things selected, **Add to the selection** comes first. A finger held still on an object opens it; a finger that moves
is a drag. The same object has the same menu on the stage, in the outliner, on its timeline row and behind its panel's
⋯ button. Also on: keys, clips, flipbook drawings and tracks, cuts, screen effects, paint layers, brushes, Looks,
library items, poses, palette colours, Home's cards and stacks, and the things on the Board.

## Settings

In this order. From Home (the gear) and from Actions.

| Control | Where |
|---|---|
| Pencil or hand: draw with a finger too (automatic otherwise: a finger makes until an Apple Pencil has touched); the Pencil's hover point; the quick menu's six slots | Settings ▸ Pencil and hands |
| Every gesture and shortcut; show undo buttons | Settings ▸ Gestures |
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
  tap hides everything but the stage, pinch, double-tap to frame, touch and hold for the hold menu. Two fingers on the
  stage always move the view (U5); one finger dragging a selected thing carries it over the surfaces under it.
- **The lasso** (U5: the Select button went): the quick menu's first slot, the three-finger swipe's bar (with Select
  all), and the empty stage's hold menu (with Select all). One loop, then back to what was in the hand.
- **The quick menu** (squeeze, or the Pencil's double-tap when Settings says): Lasso · Eyedropper · Eraser ↔ the last
  brush · Snap · Hide the sheet and guides · Frame; with Rig: Pins · Dots · Mirror the pose · Reset the pose · Save the
  pose · Show the bones.
- **Pencil hover** lights what a tap would land on (on by default).
- **The undo line**: what an undo or a redo changed, for a second at the top centre.
- **Messages** (U5: one toast system): every message, the guide line at the bottom included, leaves after two seconds
  or on any touch.
- **Under load nothing is said on the stage** (CONTEXT §6): the preview lightens by itself and comes back.
- **The menu bar and keyboard** reach the same controls: ⌘1–⌘4 Model, Draw, Rig, Animate; ⌘6–⌘8 Actions, Look, the
  lasso; ⌘L the Library; ⌥⌘1–3 move, turn, size; ⌘T the timeline; Space/J/K/L and ⌥←→ the transport; the Physics
  menu: ⇧⌘J make real, ⌥⌘J not real, ⌘J settle, ⌥⌘U does it stand, ⇧⌘K keep the run as keys. Holding ⌘ lists
  them. The Perform menu (the microphone, the trigger keys) is *(held: 1.2)*.
- **Proposals** from the AI bridge appear at the bottom of the stage while one is waiting.

## What moved in 0.19 (P1)

Physics found homes that already existed. **Real** is a row on the object panel, beside Look and Shape (one step deeper,
as those are); **Physics** (gravity, wind, the ground, the run) sits behind the scene's name, where the scene's own
settings live; **forces and fluids** are tiles in Model ▸ Add beside the particle effects; the **real sun** is in Look ▸
World's fine tuning, where the sun already was (its height and direction sliders step aside while it's on); **Settle**
joins To the ground in the object's menu; the menu bar has a Physics menu. Nothing moved.

## What moved in 0.18 (U7)

| 0.17 | Now | Why |
|---|---|---|
| Colour: the palette and any colour | the colour picker (Procreate's), with Materials | Everything a texture artist leaves the app for |
| Layers: colour only | maps, masks, fills, swipe, drag, pinch | Same |
| (nothing) | Surface beside Layers while painting a thing | Wear, decals, seams and the rest one step deeper |

## What moved in 0.15 (U5)

| 0.14 | Now | Why |
|---|---|---|
| Draw and Paint (two buttons, two panels) | one Draw, no panel: Brush · Smudge · Erase · Sheets/Layers · Colour under the stage | Procreate's five; "basically everything" got worse in U3 |
| Draw ▸ Ink, Solid shape, Sketch, Flipbook | the brush library's sets (lines, Solids, Shapes) and Sheets ▸ Frames | Brushes are sets in one library |
| Paint ▸ Colour, Shadow Brush | a painting set's brushes; the Shadow set | Same |
| The sheet's floating bar (grip, shapes, menu) | the sheet's hold menu; Sheets in the bar | The floating bar sat on the drawing |
| Select (top left) | the lasso in the quick menu, the three-finger bar and the empty stage's hold menu | Fewer buttons |
| Undo and redo in the sidebar | Settings ▸ Gestures ▸ Show undo buttons (off) | The finger taps are universal |
| The timeline on call (bottom right), Frame the selection | Animate; a finger's double-tap and the quick menu's Frame | The view corner is four |
| The joystick's × | the view corner's Joystick | One place to switch it |
| The timeline's + Overlay | 3D text that sticks to the camera; screen effects in Look ▸ Finish | "A video editor's job" |
| Two fingers on the selection turned and sized it | two fingers always move the view | One grammar for the hands |

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
