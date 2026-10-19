# Changelog

All notable changes. 1.x grew in four phases (v0.1 → v1.4); 2.0 is the remaster, released as betas first. Maquette
continues from 2.0 and numbers its phases again from 0.1 (each phase bumps the minor version until 1.0).

## [0.22] — Maquette — film (phase F1)

Light like a film set, shoot with a real lens, and deliver in every shape a film goes out in.

- **Light as a craft**: Model ▸ Add ▸ **Soft panel** (a softbox or a window: a rectangle that lights the way it faces)
  beside the bulb, spot and sun. **Setups** on a light's panel: **three-point**, **golden hour**, **moonlight**, **neon**
  (and the toon setups one step deeper), placed around the selection the way the camera sees it. **Haze** and **god
  rays** on Look ▸ World ▸ Air. **Sky from a picture**: an HDRI (.hdr) shows behind everything and lights the world, its sun
  and its sky; turn it until the shadow falls right.
- **The lens and the frame** (the camera's panel, and the camera button's Lens and frame…, ⌥⌘L): a **camera body** (full
  frame, Super 35, APS-C, Micro Four Thirds, Super 16, a phone, large format, IMAX) and the lens in its millimetres; the
  **frame's shape**, 16:9, **2.39:1**, 9:16, **4:5**, 1:1, which the Director view, Frame shot and every export follow;
  **focus on a thing** (the lens follows it) and **pull focus** to the next one on a word; the aperture for depth of field.
- **Rigs**: put the camera on a **dolly**, a **crane**, an **orbit** or **in the hand** (a person breathing), its moves keyed
  like any number.
- **Shots**: **Paper ▸ Storyboard** (every shot's frame with its camera, lens, length and the words said over it) and
  **Video ▸ Animatic** (each shot held for its length, with the sound).
- **Spatial, 360° and HDR**: **spatial video** (where the iPad encodes it) and **spatial photos** that open in depth on Apple
  Vision Pro and in Photos; **360° video** (4K, 6K) for YouTube and headsets and **360° panoramas**; **HDR** video (HLG)
  with highlights past white; **wide colour** stills (Display P3, 16-bit).
- **Rotoscope**: Actions ▸ Rotoscope puts a video behind the stage, frame-synced to the playhead, to pose or draw over. It's
  never exported.
- **The bridge** (`film`): the lens on a body, the frame, focus, rigs, the air, turning the HDRI, the shots; HDRIs over
  `add_media`; `sketch` and `boolean` verbs and `profile` ▸ `pull` so bodies and cut-outs can be modelled; pictures come
  back over MCP again. The lowey skill learns film and installs cleanly over an old copy.
- **Fixed** (from the 0.19 device session): every bridge tool that returns a picture failed over MCP; cage point errors
  name the cage's size; a car's attached parts no longer "float"; a low angle on a low car stays above the floor; a build
  says who approved it, and v1's status sent auto-apply as a string; Dark studio brings its own dark ground.

## [0.21] — Maquette — animate & export (phase A1)

Draw how a thing moves, see the motion in the timeline, and export in the format a pro asks for.

- **Animate has a bar**: Path · Look at · Pick up · Properties · Ghosts · Dope sheet. Animate still brings the timeline.
- **Draw a motion** (Path): draw where the selected thing goes and it follows **at the speed you drew**, facing the way it
  goes and leaning into its turns (a character stays upright). It rides the surfaces under the line, up a ramp, over a
  table. The path's chip: how long it lasts (drag the number), **Even speed**, face the way it goes, lean into turns, turn
  its front. The path stays editable by its dots, the keys by the timeline.
- **The timeline shows motion**: thick rows with each thing's icon in its colour and a curve of how much it moves, frames as
  cells when you zoom in, and the **dope sheet** (every property's keys under its thing). **Ghosts** of where the selection
  was and will be while you scrub the ruler.
- **Pick up and hand off** (Pick up): tap the hand that takes the selected thing at the playhead; another hand later hands
  it on; the empty ground puts it down where it was left.
- **Look at**: tap what the selected thing watches; a character turns its head, anything else turns whole; later taps
  switch whom it watches from the playhead.
- **Any property** (Properties): key anything the thing has (colours, glow, a light's strength, the lens…) at the playhead;
  after that, changing it keys itself.
- **Export, formats first**: Video · Picture · 3D · Paper, then the format, then its named presets. New: **ProRes 4444**
  with transparency (on iPads that write it), **render passes** (colour, alpha, depth, a mask per thing), glTF ▸ **for
  Godot** · for the web · for Blender, FBX ▸ **for Unity** · for Unreal, **Paper** (the frame on A4, Letter or A3, or frames
  across the shot as a PDF), and **the Look as a shader** for Godot and Unity, with a licence to use it anywhere.
- **Final**: motion blur, edges smoother than the preview's, the best shadows and the finest water, for the export that
  matters. **Every scene** or **every shot** in one go, **only the selection**, a **transparent background**. Exports keep
  going in the background as before. 3D files carry holds, looks and behaviours as keys.
- **The bridge**: the `motion` verb (path, follow, lookAt, pickUp, putDown, letGo, evenSpeed, timing, front).
- Projects move to **schema 20**; 0.20 refuses them with its usual message.

## [0.20] — Maquette — characters (phase K1)

Make a character with your own hands, any anatomy, game-ready.

- **Library ▸ Characters ▸ New**: start from a Person, Four legs, Wings, a Blob or Nothing. The character lands where new
  things land, its panel open. (The Library's Rigs page is now Characters: New, the ready-made Blob, Me and Puppet, and
  everything with a skeleton.)
- **Parts**, every one optional and repeatable: head, eyes, brows, mouth, nose, ears, hair, body, arms, legs, tail,
  wings, extras, each in a few styles from our own set (hold a part for its styles); Mirrored makes pairs. Draw a part
  with the Pencil or model it, then **Make it a part**. **Give it parts** puts eyes on a rock and hands on a teapot.
- **It rigs itself**: a person gets the humanoid joints and plays every humanoid clip; four legs and wings get their
  animal joints; a bodyless creature gets one. Moving a part by hand rigs it again.
- **Faces**: Character Animator's **14 mouth shapes**, brows up, angry and sad, eyes open and blink, each made by bending
  the part and changeable (Bend it), or **drawn** (Make it a part ▸ the Oh). Lip sync from words reaches 12 of the 14;
  the live voice and face capture drive them on any creature. **Say a line**: type it and the character says it from the
  playhead, with no voice.
- **Proportions** by dragging handles on the stage (the head, the feet, the hands, the waist) or typing metres; longer
  legs keep the feet on the ground.
- **Act it out**: film yourself or pick a video and the character copies your body (Apple's on-device body pose; nothing
  leaves the iPad), as in a mirror or not.
- **For games**: a GLB for **Godot, Unity or Unreal** with the skeleton named for that engine's humanoid retargeting,
  the face as **blend shapes**, **named clips** (its own and the ten humanoid ones), **LODs**, a **collision capsule**,
  in real metres; **sprite sheets** from 4 or 8 directions with their JSON and a Godot SpriteFrames, in **pixel art** if
  you like; a **turnaround** sheet.
- The menu bar's **Character** menu (⇧⌘C, ⌥⌘P, ⇧⌘E).
- **The bridge**: the `character` verb makes characters (new, add, style, remove, assign, state, proportion, say, rig).
- **Fixed**: the view turned at a different speed in some places (the stage in portrait or a narrow window, the Director
  view, the view cube); one rate now everywhere.
- Projects move to **schema 19**; 0.19 refuses them with its usual message.

## [0.19] — Maquette — physics (phase P1)

Rigorous physics without an engineering degree: say what a thing is made of and press play.

- **Real**, on a thing's panel: a material in words (wood, steel, aluminium, stone, concrete, glass, ice, plastic,
  rubber, foam, cardboard, cloth, jelly), how it moves (falls, stays put, follows its keys); its weight comes from the
  material and its real size. Exact numbers (mass, grip, bounce, breaking, stiffness, a start speed) one step deeper.
- **Jolt Physics** under it, in real units, the same on every iPad: what you see on the stage is what the export shows.
  The run is worked out in the background and plays from there; the timeline waits for it rather than show a wrong frame.
- Falling, colliding, stacking; **joints and mechanisms** (hinge, slider, ball, glue, spring, rope, gear; motors on
  hinges and sliders); **ragdolls** from any rig; **cloth** (hanging from its top edge too) and **jelly**; **glass and
  ice break** into pieces that fit; **forces** (a fan, a pull to a point, a whirl) and the scene's **wind**.
- **Small-scale fluids** in Model ▸ Add: pour water, a splash, billowing smoke, flames, in a room-sized box.
- Particles feel the wind and land on the ground.
- **Keep it** turns a run into ordinary keys; **Settle** lays a thing on its natural resting face; **Does it stand?**
  shows its centre of mass over its footprint; **speed and force arrows** while it plays.
- Behind the scene's name: **gravity** (Earth, Moon, Mars, Jupiter, floating), wind, the ground, when things start.
- **The real sun** in Look ▸ World: a place, a date, a time, or a **shadow study** that runs the day across the timeline.
- Exports: video waits for the whole run; glTF, Blender and FBX carry it as keys, and glTF carries **colliders** Godot
  reads (OMI physics).
- The menu bar's **Physics** menu (⇧⌘J, ⌥⌘J, ⌘J, ⌥⌘U, ⇧⌘K).
- **The bridge**: a `physics` verb (real, scene, joint, force, fluid, keep, settle, stand, sun).
- Projects move to **schema 18**; 0.18 refuses them with its usual message.

## [0.18] — Maquette — texture (phase U7)

Everything a texture artist would leave the app for, on Draw's bar.

- **Layers per map.** A painted thing's layers each paint colour, roughness, metal, glow, bumps and fur; Layers chooses
  which the brush paints (and the value for the grey ones). Masks (paint shows the layer, erase hides it), fill layers,
  three new blend modes (Darken, Lighten, Soft light), swipe a layer for options, drag it to reorder, pinch two together
  to merge them. Smudge drags paint along the surface; Erase works with any brush and on any map.
- **The colour picker** (Procreate's): a disc, values with hex, saved palettes, the colour before and the ones used
  lately, the scene's palette first, and **Materials**. Drag a colour or a material onto any thing: a colour becomes its
  colour, a material a fill layer.
- **Materials.** Our own 24 (woods, metals, plastic, fabric, leather, glass, stone, marble, concrete, brick, tiles,
  sand…), procedural, so they wrap any shape with no seam. Tap one to fill, hold one to *Paint it on* (a fill behind a
  mask you paint) or edit it in the **Material Studio**. Import a PBR set by its pictures.
- **Surface** joins the bar while painting: automatic wear (dirt in the creases, worn edges), decals (a picture pressed
  on like a sticker), painting mirrored left and right, the faces brush (whole flat faces, the low-poly way), seams marked
  by hand, the texture's size (512 to 4096), the **flat view** to paint the surface in 2D, normals baked from a detailed
  sculpt onto its light copy, and **fur**: soft shells or hair cards, with a Fur map.
- **Hatched shadows** in the Look beside halftone.
- **Every map leaves**: glTF with roughness, metal, glow and a normal map; USDZ the same; **Maps (PNG)** as a set of
  pictures; painted colour as a texture, vertex colours or a palette; fur as cut-out shells or hair cards.
- **The bridge**: a `paint` verb (colour, material, wear, decal, faces, layers, mask, mirror, size, seams, bakeNormals,
  fur).
- **Fixed**: the iPad's own brushes were forgotten at every update since 0.5 (their file couldn't be read by a newer
  app); they now carry over.
- Projects move to **schema 17**; 0.17 refuses them with its usual message.

## [0.17] — Maquette — editable history (phase H1)

Shapr3D's history: every modelling step listed, and changing an early one updates everything after it.

- **The steps list.** Select a modelled thing and open Actions ▸ History (⌘Y): over the scrubber, its steps in plain
  words, "Hole, 6 mm", "Round, 2 mm". Tap one and its numbers appear; change a number and the steps after it replay, as
  one undo step. Push/pull, inset, bevel, round, shell, a sketch pulled out or cut in, and joining or cutting with
  another solid are steps.
- **The same face, after a change.** Each step remembers the faces and edges it was made on by name, not by number, so
  making a hole wider still finds the edges that were rounded after it. A cut that went right through goes through
  again; a drawing follows the face it was drawn on.
- **When it can't follow**, it says which step and why, in one line, and nothing changes.
- **Fixed steps.** A change by hand (a corner dragged, the knife, a loop cut, clean up) starts the list again from the
  shape as it is; the steps before it stay listed with a lock. Painting or rigging a thing fixes its steps the same way.
- **The bridge**: `model` gains `steps` (lists them) and `step` (changes one).
- Projects move to **schema 16** (an object's steps); 0.16 refuses them with its usual message.

## [0.16] — Maquette — shape (phase U6)

Modelling by touch, with every tool a modeller reaches for, and shapes that keep their sizes.

- **Touch and drag, no modes.** Select a shape and the Pencil lights the face, edge or corner under its tip. Drag a face
  to pull it, an edge to round it, a corner to move it. Tap a part and its chip has the rest. The Faces, Edges and Corners
  buttons are gone. Every shape can be edited: it becomes a modelled one quietly the first time you touch it. A placed
  library model has *Model it*. With no Pencil, the same moves are on Model ▸ Shape.
- **The part's chip**: a face can be inset, shelled, bridged to a second face (hold to add it) or cut with the **knife**.
  An edge can be bevelled, rounded, **loop cut** or knifed. Corners can be **merged**, or a **hole filled**. ⋯ grows,
  shrinks or picks the similar ones, and moves the pivot there.
- **Model's bar**: Shape · Brush · Cage · Bend · Measure.
  - **Brush**: grab, smooth and inflate on any surface, mirrored across the middle if you like. The sidebar sets size
    and strength. A shape too coarse to brush is cut finer first; a placed model is made paintable first.
  - **Cage**: a box of points around the thing. Drag a point and the shape follows smoothly.
  - **Bend**: bend, twist, taper or bulge along x, y or z, with one handle on the stage. It animates like any move.
- **Shape of this object**, in the object panel: width, height and depth typed or scrubbed; **Smooth** (subdivision,
  0–3, with *make it real*); the **smooth angle** or **flat shading**; its **triangle count**; **clean up the shape**
  (even quads for games and rigs, through Instant Meshes); close holes; join close corners; **linked copies** (change
  one, all change; unlink); the **pivot** to the middle or the base.
- **Profiles**: a closed sketch shape's chip **sweeps** it along a tapped path, **revolves** it around a tapped line (or
  its own side), or **lofts** it through more shapes.
- **Sketches keep rules.** Tap a line, then another: parallel, square, same size, twice that, touching, level. A size has
  a lock. Change one number and the rest follows; our own 2D solver does it.
- **The view cube**, on by default in the view corner. Tap a side to look from there, drag to turn, double-tap for
  perspective or flat, hold for the views and Frame all. Settings ▸ Stage hides it.
- **The bridge** gains `model` (all of the above on one thing; faces named by the way they face) and `profile` (sweep,
  revolve, loft).
- Projects move to **schema 15** (an object's cage and brush strokes, its smoothing and bend, sketches' rules); 0.15
  refuses them with its usual message.

## [0.15] — Maquette — draw again, and one grammar (phase U5)

Drawing put right, and the whole app speaking one language of hands and Pencil.

- **One Draw.** Top right is Model · Draw · Rig · Animate. Draw opens no panel: its bar is **Brush · Smudge · Erase ·
  Sheets · Colour**, and the brush in the hand decides what the Pencil makes. The library's sets draw lines, the
  Painting set paints models (Sheets turns into Layers over a thing), and under them are **Solids**, **Shapes** and
  **Shadow**. Smudge pushes lines; on painted models it comes with U7.
- **Zero setup.** A stroke begun over a thing lies on its surface; in the air it lands on the sheet, which turns to face
  you first. The sheet is warm paper while you draw and a faint trace between strokes; a finger held on it opens its menu
  (nearer, farther, face me, shape, guide, rename, delete). Drawings ride with the sheet they were drawn on.
- **Strokes start under the tip.** Extra smoothing is gone, and a test on every build checks a stroke's first point lands
  within three points of the touch. Settings ▸ Pencil's test pad shows a crosshair where the tip is read.
- **Shapes in one drag**: a line point to point, a rectangle corner to corner, a circle from the middle out. A closed
  shape shows one arrow: pull it into a solid. Hold-to-shape says the size it made.
- **A tapped stroke** gets a chip (the brush and colour in the hand, thickness, smooth, delete); the Pencil dragged along
  a picked stroke reshapes it.
- **Flick for frames**, Dreams' way: with frames on, a finger's quick flick right adds the next drawing, left goes back.
  The time at the bottom left opens the onion skins (up to eight each way, your colours). Hold a drawing on the strip to
  duplicate it.
- **Every number is a slider**: the stage's dimensions and the object panel's numbers are 44 pt pills; drag slowly for
  fine steps, fast for big ones, or tap to type on our pad.
- **Fingers move the view, always.** The point under two fingers stays under them, a pinch zooms toward them, a twist
  turns; one finger turns half a turn per screen width. A selected thing dragged with a finger lifts, slides over what's
  under it and sits down.
- **The Pencil hovering** lights what a tap would land on and wakes the sheet; near the top it wakes the clusters,
  which fold to faint rails while you draw.
- **The lasso** is the quick menu's first slot, in the three-finger bar beside Select all, and on the empty stage's
  hold menu. The quick menu has the eyedropper, the eraser, snap, hide the sheet and frame; with Rig it has the rig's own
  six. The Select button is gone.
- **The eyedropper** is Procreate's: hold a finger on a thing while drawing and a loupe shows the colour under it.
- **The view corner** is Views · Camera · Joystick · Snap. Undo and redo buttons are a switch in Settings ▸ Gestures, off.
- **Titles stick to the camera**: 3D text's *Stick to the camera* replaces the timeline's + Overlay; screen effects are
  in Look ▸ Finish. Old overlays still play.
- **To the ground** lands a thing by its real lowest point on whatever is under it.
- Every message leaves after two seconds or at a touch. The Apple Pencil Pro clicks on a snap, a picked part, each
  flipbook frame and a slider's end.
- Fixed: dragging a rig's dot or pin lagged behind the finger.
- Projects stay schema 14 (two new optional properties); 0.14 opens them.

## [0.14] — Maquette — rig, and bring your sculpt (phase U4)

Rig anything, fast, and change it afterwards; a sculpt from another app arrives painted, gets rigged and moves.

- **Pins and dots, one tool.** In Rig, the Pencil taps a **dot** on each joint (a shoulder, an elbow, a wrist) or a
  **pin** where a soft thing holds and bends (a tail, a rope, an ear). A stroke along a part lays a chain of them down its
  middle. Drag a mark to move it, hold it to take it away, double-tap it to switch pin and dot. Pull a dot and its limb
  follows; pull a pin and only its stretch bends while the mark above holds.
- **Body shortcuts**: **Person**, **Chain**, **Four legs**, **Wings**. Person, four legs and wings start from a guess
  read from the shape (the dots land where its joints are); drag the wrong ones. A shape that can't be read gets the dots
  in the usual places.
- **Change a rig any time.** Change the rig: the thing relaxes to its rest shape and shows its pins and dots; move, add or
  remove them and the skin updates by itself. Poses and keys stay. A person shows its dots again.
- **Rigging adds what a shape lacks**: a cube is cut finer so it can bend where its joints are.
- **Solid parts hinge.** Rig a group, or choose several things and *Rig these together*: each part rides the bone
  nearest it, and a dot between two parts hinges them, no skin.
- **Motion is library material.** The Library has four pages: Things, **Motion**, **Rigs**, Yours. Save a pose from its
  menu, or a row's whole move as a clip or a loop from its grip's menu; tap it in Motion to drop it on the selected thing.
  On a rig of another kind it plays where the joints match and says which it skipped.
- **Drag a motion's end to repeat it**: the dot at the end of a selected row's grip; repeats show lighter. *Loop forever*
  is in the grip's menu.
- **Four feels on a key**: Ease, Snap, Bounce, Straight; the curve one step deeper.
- **Bring your sculpt.** glTF and OBJ files keep the colours painted on their corners and arrive painted (and stay
  paintable). A sculpt heavier than this iPad keeps smooth is lightened as it comes in, with no question; the
  **Detail** slider in its panel asks for more or less. Open in, the share sheet, a drop and Home's import put it on the
  stage, with **Rig it** beside it once.
- **Out to game engines.** glTF exports carry rigged things as skins with their bones and keys; **FBX** (our own writer)
  is in Export for a rigged thing. Checked in Godot and Blender on every build.
- Settings ▸ Pencil and hands: placing pins and dots is the Pencil's by default.
- Fixed: joint handles, the lasso and motion paths were drawn a little below where a touch grabs them.
- Projects are schema 14; Maquette 0.13 can't open them.

## [0.13] — Maquette — draw (phase U3)

Drawing in 3D, rebuilt on **the sheet**, and hands and Pencil given their jobs.

- **The sheet.** A see-through sheet is always under the Pencil, so a stroke knows how deep it is. Tap with a finger to
  move it: onto a surface (it lies there and rides with that object), or into the air (it stands there facing you).
  Drag its grip to push it nearer or farther. The control on its edge makes it flat, wrapped around, a dome, or lying on
  the object itself. Sheets you drew on are kept, named, and can be drawn on again. The nine "Draws on" buttons and
  "Plane offset" are gone.
- **Everything the Pencil draws is in Draw**: ink, solid shapes, **Sketch** (moved from Model ▸ Edit) and flipbooks.
  Sketches start on the ground, lined up with the world; a face you start on lays the sheet there. **Sketching talks
  back**: draw a line with the Pencil and its length and angle float beside the tip; it snaps to round angles, corners,
  middles, and parallel or perpendicular to lines already there, with the snap named on a ghost line and felt in an
  Apple Pencil Pro. A finger sketching gets a magnifier.
- **Flipbooks on the sheet**, in perspective and staying in the space (stuck to the camera is still an option), with
  **the frame strip** along the bottom: the drawings as pictures, + for the next, step, hold and drag to reorder, drag
  an edge to hold longer, onion skin, and a loop that plays while you draw. Draw, then hold for a clean shape works on
  flipbooks too.
- **Our number pad** opens beside any number you tap; the system keyboard never covers the screen for one.
- **The hand shortcuts**, each switchable in Settings ▸ Gestures: two- and three-finger taps undo and redo (hold to
  repeat), four fingers hide everything, **three fingers swiped down cut, copy and paste**, a finger's double-tap frames
  a thing and, again, looks straight at the face you touched, **a finger held down flips snapping** for that move, hold
  at the end of a stroke for a clean shape. **Squeeze** an Apple Pencil Pro for a menu of six at its tip (you choose
  them); **double-tap** does what the iPad's Pencil setting says.
- **The Snap magnet** on the stage replaces Precision's switches: tap it on or off, hold it for the details.
- **Settings ▸ Pencil and hands**: who does what (moving and posing with fingers, pulling faces with the Pencil, or
  either), and **Your Pencil**: a test pad, a two-stroke calibration, presets for a light, normal or heavy hand, the
  curve to drag, stabilisation, thickness from speed for a Pencil without pressure. The Board follows it too.
- **The Reference window**: Actions ▸ Reference floats any picture over the stage; move it, size it, fold it, take a
  colour from it with Pick, or trace it on the sheet. The Board's pins work as before.
- **The timeline as Procreate Dreams has it**: draw around keys and clips with the Pencil to pick them (or with a finger,
  by choice; two fingers pan), the Pencil's hover scrubs, and holding a clip's edge retimes it.
- **The brush library drops down** from the brush, sets on the left and brushes on the right.
- Projects are schema 13 (sheets); Maquette 0.12 can't open them. hmm-kit 0.8.0.

## [0.12] — Maquette — layout (phase U2)

Everything moved, merged or folded into the map that freezes at 1.0 (docs/LAYOUT.md has the whole map and what came
from where). Nothing new to learn; everything easier to find.

- **New top buttons.** Top left: Home · Actions · Look · Select · **Library**. Top right: Model · Draw · Paint · **Rig**
  · Animate. Cast is gone: a Blob, Me and a Puppet are in the Library; rigging, poses and clips are in Rig; a
  character's expressions, lip sync and face are its button beside Record in the timeline's Perform.
- **The + on Home goes straight in**: a blank project in the new dark studio, named by itself (tap a card's name to
  rename it). Print, Room and Animation are a quiet row under the title; the samples are one card; no tagline.
- **Tap the scene's name** (under the top-left buttons) for what it's set up for (switch any time: Blank, Print, Room,
  Animation), its scenes and its objects. Select is a small bar.
- **The object panel fits on one screen**: Move · Turn · Size, colour, **Make it move** (every motion once, in one
  strip), what the selection can do (Combine, Mirror, Make editable, Scatter), and four rows one step deeper. Drag its
  header to move it anywhere; it stays there. It folds to a chip while anything bigger is open.
- **One menu per object**: touch and hold it, or its panel's ⋯, for everything it can do.
- **The timeline**: Perform and Keys, as words, and eight controls. Perform waits for your touch: time runs while you
  touch and stops when you lift. After a thing's first key, changes key themselves. Slide a whole animation by the
  grip under its row. Titles, marks and screen effects are its + Overlay.
- **Cameras live on the camera button**: tap to look through, hold for a new camera from this view.
- **Look** has three pages (Style, World, Finish; motion on twos is in Finish). **Export** asks the kind first.
  **Settings** is Pencil and hands · Gestures · Stage · Appearance · Assistant · About (Diagnostics inside). **Learn**
  holds the tour, the gestures and the switch for the instructions in panels.
- The sidebar rests as a thin rail when nothing uses it; a colour is always in the hand before making, shapes too.
- Undo and redo say what changed for a second; a guided step shows one line at the bottom. Nothing is greyed out and
  no label is cut, from the iPad mini to the 13-inch, in landscape and portrait.
- A trial: calmer chrome (neutral glass, amber only for the tool in your hand). Diagnostics switches it off to compare.
- Projects are schema 12 (the dark studio mood); Maquette 0.11 can't open them. hmm-kit 0.7.0.

## [0.11] — Maquette — feel (phase U1, shipped with 0.12)

- **The Library shows every model's picture.** The Kit's pictures now ship with the app, so they're there the first
  time you open it; a picture is never taken before its model has loaded (the grey tiles, and empty Home cards).
- **Sharp at rest.** When the view stops moving, the stage draws at full resolution; while it moves, it stays smooth.
- **No more "getting ready".** Choosing an object with Paint in the hand makes it ready to paint quietly; the layers
  simply appear. A drawn bone stays on the stage while it learns how to bend, and you can draw the next one straight away.
- An iPad with 8 GB (every M-chip iPad) always previews at full quality (hmm-kit 0.6.1).
- Opening the app doesn't read the Kit's pictures any more.

## [0.10.1] — Maquette — the feel recorder (phase U1, first step)

- **Diagnostics ▸ Feel ▸ Record a minute.** Use the app for a minute the way you normally do; a small red dot at the
  top says it's listening, and it stops by itself. Every touch is timed to the frame that answers it. Share the file
  from the same place (it's also in Export logs). Nothing leaves the iPad unless you share it.
- The log now notes how long a cold launch took to reach Home and how long each project took to show its first frame.
- hmm-kit 0.6.0.

## [0.10] — Maquette — live performance (phase M10)

- **Your face drives any character.** Front camera or iPhone: drawn rigs, person rigs, 2D drawn puppets and rigged
  models turn their head with yours now, not only Blobs and Puppets. A skeleton that isn't a person's can name the
  bone that is its head (Cast ▸ Life).
- **Your hands move its hands**: on every humanoid, by IK.
- **Your voice shapes its mouth**, live (Cast ▸ Mouth from the microphone). Nothing is recorded or sent.
- **Parts**: make a loose object part of a drawn rig and it rides the nearest bone; give it a face role and it
  blinks, looks and talks with the face. A drawn puppet gets its face this way; a prop sits in a hand.
- **Life**: characters breathe (a slider) and blink on their own.
- **Triggers**: one tap or the keys 1…0 for an expression, a saved pose or a swap of what it holds. While a take
  records they're performed, held or switched; the deck sits under the stage in Perform.
- **Draggers**: while a take records, drag a hand and it follows; the take keeps it.
- **Dangle** (Cast ▸ Rig ▸ Pose): touch a joint, slide Dangle. Hair, ears and tails trail and swing, and settle as
  drawn. The same on the stage and in every export.
- **Takes**: every recording is kept. They're listed above the lanes in Perform; drag across one to use it from there
  to there.
- The iPhone companion also sends eyes-wide and the brows' angle. Project files are schema 11.

## [0.9] — Maquette — the Schizzo board (phase M9)

- **A board in every project** (Actions ▸ Board): an endless 2D sheet for planning before you build. Sketch on it with
  the whole brush engine (every brush, pressure, tilt), drop pictures on it, write notes, draw arrows between them,
  and put frames around what belongs together.
- **Pin anything to the project.** Pick a frame, a note or a sketch and pin it: it floats over the stage as a
  reference card you can move and size. From the card's menu, **Stand it in the scene** makes it a plane in the 3D
  scene, an object like any other.
- The board works like the stage: Select top left; Draw, Erase, Note, Arrow, Frame top right; size, opacity, the
  colour and undo on the sidebar; touch and hold a thing for the same menu as everywhere. Two fingers move the view
  (one, once a Pencil has touched), pinch zooms, double-tap fills the view with a frame.
- The eraser cuts strokes where it touches. Arrows follow the notes and pictures they point at. Moving a frame moves
  what's in it.
- Nothing on the board is ever lost: every stroke is written as it's drawn, and undo is still there after closing the
  app.
- **Sketch** is a starter template in New project: it opens on the board.
- The paper is dark or light, with dots, a grid or nothing. Share a picture of a frame, a pick or the whole board.
- Don't want it? Settings ▸ Board switches it off (nothing is deleted).
- Under the hood the brush engine moved into hmm-kit, so Cutaway will draw with the same brushes on the same board.

## [0.8] — Maquette — fixes and touch (phase M8)

- **Nothing is said on the stage under load.** The "close to what this iPad keeps smooth" chip and its setting are
  gone; the preview lightens by itself and comes back when there's room. The numbers are in Diagnostics ▸ Smoothness.
- **One hold menu everywhere.** Touch and hold an object on the stage (a still finger; a moving one drags), a key, a
  clip, a flipbook drawing, a layer, a brush, a Look, a card: Duplicate · Rename · Copy · Paste, then what fits the
  thing, then Delete. Clips gained **Split at the playhead**. Adding to the selection is the menu's *Add to the
  selection*.
- **Pencil or hand, automatic.** With no Apple Pencil, a finger draws, paints and rigs; once a Pencil has touched,
  it makes and fingers move the view. One switch in Settings ▸ Pencil or hand.
- **Move it.** Six looping motions at the top of the inspector: Spin, Float, Bounce, Wiggle, Swing, Follow a path. One
  tap and it moves, one Speed slider, **Make keyframes** when you want keys. Bounce and Swing are new.
- **A colour well on the sidebar** while you draw or paint.
- **Rigging in three steps**: Bones → Skin → Pose, each with only its own tools. A drawn bone runs through the middle
  of the part it's drawn on (also where an arm lies in front of the body, or a tail goes into it), bends where the
  stroke bends, shows as you draw it, and replaces a bone you draw again.
- Fixed: an object that already had drawn bones refused more of them, and its Rig tools were replaced by a sentence.
- The sphere is findable: Model's second page is called **Edit**, and the sphere's tile looks like a ball.
- Panels opened from the corners sit above the sidebar.
- The inspector can be docked at the side (Settings ▸ Stage).
- Projects are schema 10 (two new motion kinds); 0.7 projects open unchanged.

## [0.7] — Maquette — rigging (phase M7)

- **Cast ▸ Rig ▸ Draw a bone**: draw through a limb, a tail or a rope with the Pencil and it bends there. Works on
  shapes, modelled parts, drawings and placed models; more strokes add more bones.
- The weights are worked out for you (bone heat): smooth bends at every joint, and parts that only touch don't drag
  each other. Prefer to paint them? **Paint weights** shows a bone's weight in colour and paints it with the brush.
- **Rig as a person**: tap eight dots on the model's front (the other side is mirrored), drag any of them, Rig. Every
  built-in clip (Idle, Walk, Run, Talk, Wave, Point, Type, Nod, Shrug, Celebrate) plays on it.
- **2D drawn puppets**: draw bones on a drawing's plane and its strokes bend with them.
- **Pose by dragging**: select any character (Blob, Puppet, Rigged or one you rigged) and drag its joints; the limb or
  chain follows. Keys land at the playhead in Keyframe mode; Reset the pose puts it back. The pose library works on every
  kind of character.
- **One skeleton system** underneath: Blobs, Puppets, imported Rigged models and drawn rigs pose, key and play clips the
  same way.
- Rigged objects can be painted (they stand as they were made while you paint them).
- **Exports carry the pose**: glTF and the Blender package as you posed it, USDZ, OBJ, STL and 3MF as posed at the
  playhead, so a posed character can be printed.

## [0.6] — Maquette — painting on models (phase M6)

- **Paint ▸ Colour**: paint colour straight onto shapes, modelled parts, solid drawings and placed models with any brush
  in the library, in the current colour, at the sidebar's size and opacity. Paint, erase, fill a layer, take a colour
  with the eyedropper. Fingers move around; the Pencil paints.
- A stroke lands exactly where the camera sees the model, in the frame that shows it: never behind something, never
  round the back.
- **Layers** on every painted object: show and hide, opacity, blend modes (Normal, Multiply, Screen, Overlay, Add),
  add, duplicate, merge down, move, clear, rename, delete.
- **Project a picture** from Photos or Files onto a model: place it over the stage, then Project.
- Models are laid flat for painting by xatlas the first time; placed models keep their own colours as a first layer.
- Every stroke, fill and layer change is one undo step and survives closing the app; modelling a painted object
  carries its paint onto the new shape.
- **Exports** carry the paint: glTF and the Blender package, USDZ (Quick Look) and OBJ with its texture.
- Diagnostics: the painting benchmark (a scripted Pencil paints a 50k-triangle model for 20 seconds).
- Settings ▸ Licences credits xatlas and Manifold.
- **Smoothness warnings are off by default.** The chip that says a scene is close to what the iPad keeps smooth only
  shows when Settings ▸ Stage ▸ Smoothness warnings is on. The stage still adapts its resolution to stay smooth.

## [0.5] — Maquette — brushes & drawing guides (phase M5)

- **One brush engine** for ink and flipbooks: a tip and a grain stamped along the stroke, with StreamLine, spacing,
  jitter, fall-off, tapers, pressure, tilt and speed, flow and wet edges. The stroke under the Pencil is drawn by the
  same engine as the one that's kept, with the Pencil's predicted path drawn ahead.
- **Ten brushes** in three sets (Inking, Sketching, Painting). Draw ▸ Ink and Draw ▸ Flipbook each hold a brush: tap it
  for the **brush library**.
- **Brush Studio**: every setting on seven pages, your own picture as a tip or a grain, a pad to try the brush on.
  Duplicate, reset, rename, move between sets, delete; make, rename and delete sets.
- **Import Procreate brushes** (`.brushset`, `.brush`) and **Photoshop brushes** (`.abr`) from the library or with
  Open in from Files and AirDrop. **Share a set** as a `.maquettebrushes` file.
- Strokes keep the brush they were drawn with: editing a brush never redraws finished work, and a project carries its
  brushes to another iPad.
- **Drawing guides**: for flipbooks a 2D grid, isometric, 1-, 2- and 3-point perspective and symmetry (vertical,
  horizontal, quadrant, radial); for ink a grid, isometric or symmetry on the guide plane. Drawing Assist straightens
  strokes along the guide; symmetry mirrors them as you draw.
- **Diagnostics ▸ Apple Pencil**: how long the Pencil takes to show on screen (median and 95th percentile).
- Projects are schema 7 (brushes); Maquette 0.4 asks for a newer version instead of opening them.

## [0.4] — Maquette — modelling II & interop (phase M4)

- **Bevel, round, inset, shell** from the Model tool's bar: pick edges and bevel or round them, pick faces and inset
  them or hollow the solid leaving them open. Each runs at once at a size that suits the units; tap the size that
  floats beside it to type an exact one.
- **Mirror** across the picked face or the middle, and **live symmetry** (left and right, front and back, top and
  bottom): change one side and the other follows (Model ▸ Shape).
- **Array along a sketch** from the inspector's Array, optionally turning with the curve.
- **Model ▸ Precision** (was Snapping): snap to corners, edge middles, edges and faces as well as the grid (grid sizes
  follow the units); the stage marks what a point snapped to.
- **Measure** between two points, with how far apart along x, y and z; **keep** it on the stage as a dimension that
  moves with what it measures.
- **Section view**: cut the stage open across x, y or z, or along a face; slide the cut, keep the other side. Exports
  are never cut.
- **3D printing** (Model ▸ Shape ▸ 3D print): the printer's build volume on the stage, **Check for printing** (holes,
  inside-out faces, walls too thin for the printer, fitting the bed) and **Repair**.
- **Building** (Model ▸ Add): walls along tapped corners (height and thickness typed beside them), floors, doors and
  windows cut into walls, stairs.
- **Export a 3D model** as **glTF** (the scene with its hierarchy, materials, cameras, lights and animation), **USDZ**,
  **OBJ**, **STL** or **3MF** (millimetres, standing on the bed), or a **Blender package** that builds a
  ready-to-render .blend with the Look, lights and cameras.
- **Import STL and 3MF**; **Make editable** takes a placed model apart, keeping a glTF's hierarchy and animation.
- Booleans are exact to the nanometre where shapes cross, and keep their faces whole.
- Projects are schema 6 (kept dimensions, symmetry); Maquette 0.3 asks for a newer version instead of opening them.

## [0.3] — Maquette — modelling I (phase M3)

- **Model ▸ Shape**: sketch, push/pull and booleans, Shapr3D's core loop. Choose a shape or a mode and the stage is
  yours, with the Model tool's bar at the bottom.
- **Sketch on any surface**: line, rectangle, circle, arc, spline and offset, by tapping, on the face you tap or the
  ground. Closed shapes fill; a shape inside another makes a hole.
- **Pull a region into a solid or cut it into the face below**, by dragging or by typing the distance.
- **Pick faces, edges and corners**: tap, touch and hold to add, a Pencil loop for many; grow, shrink, select similar.
- **Push/pull faces** with the distance floating beside them, snapping to other corners and to the unit. Tap any
  number on the stage and type an exact length: `25`, `25mm`, `2*12`, `1ft 6in`.
- **Union, subtract, intersect** two or more shapes; results are clean solids (flat faces merged, no seams), ready to
  keep modelling. Any shape becomes an editable mesh on the way.
- **Units**: millimetres, centimetres, metres, inches, feet (Model ▸ Snapping). Model to print starts in millimetres,
  Room or building in metres.
- The inspector shows the selection's size, and what's picked.
- The camera comes in to 3 cm, so double-tap frames a small printed part.
- Projects are schema 5 (meshes and sketches); Maquette 0.2 and 3D-lowey ask for a newer version instead of opening
  them.
- Booleans by Manifold (Apache-2.0), vendored.

## [0.2] — Maquette — the canvas owns the screen (phase M2)

- **The stage owns the screen.** At rest it holds at least 85% of it: two corner clusters, a thin sidebar, and
  everything else when called. The layout that freezes at 1.0, every control mapped to one home in
  [docs/LAYOUT.md](docs/LAYOUT.md).
- **Model, Draw, Paint, Animate, Cast** top right. Model gathers what you put into the world (shapes, lights,
  cameras, words, photos and videos, effects), the Kit and your models, and snapping. Paint has the Shadow Brush and
  Scatter. Animate opens the timeline. Top left is now **Home** · Actions · Look · Select.
- **Time on call.** New projects start without a timeline. The control at the bottom right calls the slim
  transport; Animate opens the whole timeline; each project remembers how it left it, and how tall.
- **The inspector floats beside what's selected**, on whichever side has room, and glides over when the view
  settles. Move, turn and size are at its top; align and distribute when several things are selected.
- **Every panel resizes** from the grip in its corner and remembers its size (double-tap the grip to reset).
- **The joystick is on by default**, with its own × to hide it (Settings ▸ Stage brings it back).
- **Home, the living gallery.** Each card is the model slowly turning in its own Look; tap it and it grows into the
  stage. Stacks (drag a card onto another), search, sort, and Select for several at once. Closing a project no
  longer waits for its card to be drawn.
- **Starter templates** in New project: Model to print, Room or building, Character, Animation, Blank.
- Nothing appears in two places any more: sound and the timeline's settings live in the timeline, photos and videos
  are added from Model, Pick is the sidebar's.
- **Diagnostics ▸ Run the Home benchmark**: a hundred projects turning while the gallery scrolls for 20 seconds.
- Section titles in panels are translated into Italian and Arabic too; Settings ▸ About says studio h.
- hmm-kit 0.3.0: resizable panels (`hmmResizable`), `HmmFloatingPlacement`, `GalleryArrangement`.

## [0.1] — Maquette — foundation & feel (phase M1)

- **3D-lowey is now Maquette**, by studio h.: its own name, icon (temporary, until the identity phase), bundle id and
  `.maquette` projects. It installs next to 3D-lowey; 3D-lowey's projects and `.loweypack` files open in it.
- **Nothing is ever lost.** Every change is written to the scene's history the moment it happens (the 1.2-second
  autosave delay that could drop your last edit is gone). Force-quit mid-edit, reopen: the edit is there and undo
  takes it back. Undo keeps 500 steps across relaunches.
- **History** (Actions ▸ History): drag back through every step and see the stage as it was; *Go back here* (the
  state you leave is kept as a version), name a version, restore any version as one undo step. Versions are kept
  automatically each time a scene opens and after each hour of work.
- **The Pencil feels right.** With hover preview on, a small point sits exactly under the tip, for every tool, drawn
  in the stage's own frame; with it off, nothing shows. The brush outline appears only while you resize the brush.
- **Every iPad, tuned.** Maquette reads the iPad's GPU and memory and picks a preview tier: full on M-chip iPads,
  lighter render scale and shadows on A-chip ones. Exports are always full quality. The stage holds the screen's
  own refresh (60 Hz iPads are no longer pushed to 120).
- **A load meter that speaks up before lag.** Invisible until a scene nears what the iPad keeps smooth; then a calm
  chip offers a lighter preview.
- **Diagnostics**: shows the tier; the benchmark's pass rule follows the screen, and M iPads can run it as Tier B.
- **Faster frames**: smears no longer rescan the scene every frame, the stroke preview uploads once, frame timing
  allocates nothing.
- **CI**: one run per change, routed by what it touches, the app build beside the render tests; one required check.
- [docs/PROJECT_FORMAT.md](docs/PROJECT_FORMAT.md) documents the package, `project.json` and the journal.
- hmm-kit 0.2.0: `HistoryJournal`, `HistoryVersions`, journaling on `CommandStack`, `DeviceTier`, `LoadMeter`.

## [2.0.0] — 2026-10-04 — Tools, the Kit, and a director that can see

The remaster's second half. Everything in 2.0.0-beta.1, plus:

- **Ink strokes.** Draw pressure ribbons with the Pencil on the guides, next to the solid shapes. Select strokes
  (tap or loop), move, erase, smooth and change their width; strokes are objects, so they animate like anything else
  and can write themselves on.
- **Flipbooks.** Draw frame-by-frame over the shot, anchored to the camera or to an object, with onion skin, holds,
  multiply / screen / add blending and several tracks. Five drawn effects ready to drop on a word: speed lines,
  impact burst, sweat drop, sparkle, smear.
- **Animation tools.** Per-object frame rate (ones to fours, keyable) — a character on twos, the camera on ones;
  motion paths with dots you drag; 3D onion skin; a graph editor; smears on fast moves; a pose library with mirror; IK
  handles; pick several clips with the Pencil lasso.
- **One Cast.** Blobs, Puppets and Rigged characters in one panel under the same verbs. Blobs get a steady thick
  outline, face decals that stay flat, Shadow Brush presets for designed shadow shapes, and ten built-in clips.
- **Fly the camera** with on-screen sticks or a game controller, eased like a real operator, and record the flight in
  Perform. Frame shot knows every shot type and composition, from either side of the subject.
- **The Kit.** About 350 CC0 models from Kenney and Quaternius in nine Sets — Room & Desk, Office & Computers, Nature,
  City & Street, Kitchen & Food, Lab & Science, Space, Props & Signs, Characters — at real size, knowing their surfaces
  and which way they face. The Library opens on them; thumbnails are drawn in the Ink Look.
- **Sound effects.** A track for them and a small synthesised foley set (whoosh, pop, impact, click, swell) whose hit
  lands on the word you pick.
- **New samples.** The Welcome island and the Enigma story rebuilt from the Kit: a desk at night in Ink, a room of
  computers in Comic on twos, a cave robot in Sketch with one accent, and the narrated three-shot story. A new tour.
- **Claude can see what it builds.** `observe` shows Claude the shot with numbered marks, top / front / side diagrams
  with the camera drawn in, a squint (value) view and the subject's silhouette, and measures it: what's visible and how
  much, what floats or intersects, where the subject sits, contrast, palette, light — graded against a critique rubric
  with a fix for each failure. `contact_sheet` adds how things move. Running it on our own samples found a glTF bug
  that drew whole Kit packs at a third of their size, a chair blocking a shot and a lamp that made a desk glow; all
  fixed.
- **MCP v2 and Scene Script v3.** The laptop tool is now `hmm-bridge`, and its `lowey` MCP server has sixteen intent
  tools. Scripts speak relations instead of coordinates ("the lamp on the desk, the books beside it"), frame shots,
  light them with six recipes and animate by intent (enter, react, walk to, look at, talk…); the solver grounds
  everything and keeps things apart. Proposals on the iPad show a preview picture. v2 scripts still work.
- **A new Claude skill** built around a director's loop — plan, build, look, critique, fix — with modules on sets,
  camera, light, animation, characters and style, a tool reference generated from the server, and twelve eval briefs
  with a harness that scores Claude's work from the app's own measurements.
- **Italian and Arabic.** The whole interface in English, Italian and Arabic, right to left in Arabic.
- **Accessibility.** VoiceOver reaches every control, the chrome follows Dynamic Type, and Reduce Motion, Reduce
  Transparency and Increase Contrast are respected.
- **Windows.** A Monitor window shows the shot live, as it will export — beside the editor in Stage Manager or on an
  external display (Actions ▸ Monitor, ⌥⌘N). The app reopens where you left off.
- **App Store ready.** A new icon, privacy manifests, App Store screenshots made by the UI tests, and a TestFlight
  upload in the release workflow. The App Store build ships without the laptop bridge until 2.1.

## [2.0.0-beta.1] — 2026-10-03 — A new engine, Looks, and a layout without modes

The remaster's first half: everything 1.4.3 did, on a new renderer, in a new layout. Projects from 1.x open as they
are. Every 1.x feature and what happened to it is in [docs/MIGRATION.md](docs/MIGRATION.md).

- **Looks.** Five ways to draw the same world: **Ink** (the new default: cel shading with soft-edged bands, shadows
  that shift toward the sky's colour, bounce light, contact shading, a rim light and ink lines), **Comic** (halftone
  shadows, colour misregistration, heavier lines, on twos), **Sketch** (pencil lines, paper, and one **Accent** that
  keeps its colour), **Clay** (the soft 1.x look, with soft shadows) and **Low-poly** (faceted). Duplicate any Look
  into your own; a scene or a single object can use a different one. Moods and the palette work with all of them.
  1.x projects open in Clay, so nothing looks different until you choose.
- **LoweyRender 2.** A Metal renderer of our own replaces RealityKit. The stage, thumbnails and exports are drawn by
  the same code, so what you see is what you export. Tapping picks exactly the object under your finger (even thin
  ones), the selection is outlined, rigged characters are skinned on the GPU, repeated objects are drawn in one go,
  and the picture drops to a lower resolution and upscales (MetalFX) when the iPad is busy or hot. Shadows come from
  the sun; up to 16 lamps light a shot.
- **One editor, no modes.** The stage sits over the timeline. Top left: Theater, Actions, Look, Select. Top right:
  Build, Draw, Transform, Cast, Library. A sidebar holds two sliders for whatever you're doing, Pick, undo and redo.
  The inspector slides in when something is selected. Four fingers hide everything but the stage. ⌘1–5 open Select,
  Build, Draw, Transform and Look.
- **The Theater.** Projects play a short loop of their first seconds; New project asks for a name, a mood and a Look.
- **Bevels** on primitives (on by default, small), so edges catch the light and the lines.
- **Shadow Brush.** Paint where shadows fall on any surface with the Pencil.
- **Director view** (⌥⌘D): look through the shot camera with the delivery frame, thirds and safe areas marked;
  drag, pinch and twist to aim, move, dolly and roll it, keyed. **Frame shot** places a camera on the selection with
  a shot size and a composition.
- **Auto-key lives in Keyframe mode.** Compose, the default, never makes keys by accident.
- **Export presets**: YouTube 4K, 1080p, Shorts / Reels, Square, Transparent, PNG stills, **GIF loop** (new), 3D, and
  captions. Every export is checked (frames, size, length, sound, transparency) before it's handed to you. Exports keep
  going in the background, with a Live Activity where the system shows one and a notification when they're done.
- **Diagnostics**: a performance HUD over the stage and the **Night Market** benchmark (a busy street with walkers and
  blobs under lamps) that writes a JSON report; log export.
- **The bridge is off until you turn it on.** Pairing uses a one-time code shown on the iPad, laptops get their own
  token (kept in the Keychain, listed, revocable), and nothing answers from outside the local network. `lowey-link pair
  <code>` takes the code; `lowey-mcp --public` and the tunnel modes are gone.
- **New identity**: bundle id `studio.hmm.lowey`; 2.0 installs next to 1.x.
- Under the hood: the code is now LoweyCore → LoweyEngine → LoweyFeatures → App, with shared parts in hmm-kit; Swift 6
  with no warnings; no file over 500 lines; golden-image tests for every Look; releases only from commits CI passed.

## [1.4.3] — Moving-around speed, a smoother stage, a real ground, a nicer joystick

- **Moving-around speed.** Scene menu → *Speed…* now has two sliders: *Moving around* (orbit, pan and pinch zoom with
  your fingers, and a camera's moves in Camera mode) and *Joystick*. Normal is the feel it always had.
- **Smoother in big scenes.** The live view now lights what you're looking at: the 8 nearest point / spot lights shine
  and only the 2 nearest cast shadows (a set with twenty lamps across five rooms used to light and shadow-map every
  room, every frame). Lens blur and ink outlines are worked out at a fraction of the size in the live view (the blur
  was the heaviest thing on screen). When the stage still drops below about 40 frames a second it draws a step fewer
  pixels until it's smooth, then climbs back. Exports are unchanged: full quality, every light.
- **The ground.** It no longer ends in a hard line against the sky: towards its edge it melts into the exact colour of
  the sky behind it, and a faint large-scale shading keeps a big floor from looking like one flat sheet. The building
  grid is drawn per pixel: crisp, anti-aliased lines at any distance, no shimmer far away, and it fades out instead of
  stopping at 20 m.
- **Joystick, redesigned.** A shaded well with tick marks, X and Z labels on a compass that turns with the view as you
  orbit (it used to update three times a second), the rim lighting up where and how hard you push, a glossy knob that
  springs back, a green height slider that fills from its centre notch, the mode (MOVE / TURN / SIZE) and speed on top,
  and a light tap when you grab it or hit full speed.

## [1.4.2] — Joystick speed, a calmer cartoon face

- **Joystick speed back to how it was**, and now yours to set: scene menu → *Joystick speed…* (a slider, tortoise to
  hare, with *Back to normal*). v1.4.1 made the pad count real time instead of frames; when the stage runs below 60
  frames a second that made it about twice as fast as before (turns up to three times). Normal is the old feel.
- **Squash & stretch that doesn't wreck the face.** The head used to squash by how far the face *lagged behind* a new
  expression, so the instant you keyed one the whole head, eyes and mouth included, was crushed to about half its
  height and then shot up to 1.6×. Now it's a quick take: the head stretches a little (at most 10%) in the direction
  the face is moving and is round again once it settles; a held expression keeps only a hint (2–3%). The hat follows
  the same take.
- **About half the bounce.** Expressions overshoot about 14% and settle (it was about 30%, a wobble). The *Cartoon*
  slider still goes from none to rubbery.

## [1.4.1] — Joystick, bridge that stays up, clean shots

- **Joystick, one layout in every mode.** The stick works on the ground (red X and blue Z, drawn inside the pad the way
  they lie from where you look), the green slider on the vertical (Y): Move slides / lifts, Rotate tips the object
  (stick) and spins it (slider). Analog: gentle near the middle, full speed at the rim, and speeds are per second (the
  pad assumed 60 frames a second, so on a 120 Hz screen or when frames dropped it jumped). No snap jump when you let go
  of a joystick turn. Stick and slider together are one undo step.
- **Cameras, light bulbs and particle emitters no longer show in the shot**: hidden while looking through a camera and
  in Export (exports never had them).
- **The bridge stays up.** It starts with the app (unless you switch it off) and keeps answering when 3D-lowey is in the
  background or the screen is locked (it plays silence, mixed with your music, which is how iOS lets an app keep
  running). A "Bridge on" notification shows while the app is away, and one tells you when Claude proposes a change.
  Snapshots need the app on screen (iOS doesn't let a background app draw). It restarts its listeners when the app
  returns to the front and saves a laptop's pairing at once (it was saved on the next status call, so a pairing could
  be lost).
- **The iPad no longer auto-locks while 3D-lowey is on screen.**
- **Pairing code**: permanent by default (000000 until you change it, *Change* in the bridge panel), or *New code after
  every pairing*. `lowey-link pair` with no code uses 000000. Ten wrong codes pause pairing for a minute.
- **lowey-mcp / lowey-link answer fast or fail fast**: 2.5 s to connect (a sleeping iPad used to hang a call for up to
  200 s), no proxy lookups, and if the iPad's address changed they find it again by Bonjour and remember it.

## [1.4.0] — Polish: feel, face, media

### Feel
- **Rotation that behaves.** Objects turn around their own pivot (several: the middle of their pivots) and never drift
  while turning (the pivot used to be re-measured from the bounding box every frame). Rotate rings are thin and picked
  by their drawn line, the ring facing you winning where they cross (overlapping hit boxes grabbed the wrong axis).
  Face-on rings turn by circling, edge-on rings by sliding along them. Snapping happens in steps during the turn, with a
  tick, instead of jumping at the end. The inspector keeps the angles you typed (X 100° stays 100°, not 80°/180°/180°).
- **Two fingers on the selected object** hold it: twist turns it, pinch sizes it (Reality Composer). Elsewhere two
  fingers still move the camera.
- **Squeeze the Apple Pencil Pro** to play or pause, in any mode, with the interface hidden too (unless Squeeze is set
  to Ignore in Settings).
- **The timeline scrolls up and down again** with many rows (the lanes' drag swallowed the list's scrolling), flicks
  glide, a thin bar shows where you are. To start and Add marker are back on the header.

### Simpler, lighter chrome
- Buttons on a panel draw no glass of their own (glass on glass); the top bar's glass is one group. Undo and redo sit in
  the top bar; move / turn / size only show with something selected; the inspector keeps the numbers folded and has
  three actions (duplicate, hide, delete) plus one menu for the rest.

### Faster stage
- The selection box is rebuilt only when the selection's size changes (it was rebuilt, and the selection re-measured,
  on every camera move and every frame of playback). The drawing guide likewise.
- Live bloom at quarter size (exports keep the full filter); video frames for the stage decode at 1280 px.
- The stage renders at 1.75× (about a quarter fewer pixels); *Full-resolution stage* in the scene menu brings back
  full density. Rigs are only looked up for clip tracks.

### Face, hands and the phone
- **Set rest pose** (Character Animator): sit relaxed and tap; head angles, gaze and dials are measured from there, so
  looking at the iPad from below no longer leaves the character nodding.
- **Hands**: body tracking (Vision) moves the blob's hands and the rubber-hose arms follow; recorded with the face.
- **A camera preview** floats over the stage while you perform: the picture, green dots on the face, lines on the arms,
  Set rest pose and stop. The iPhone companion shows its own preview and streams a small one to the iPad.
- Sides are consistent: every source reports the mirror's sides (the iPhone used to mix mirrored blinks with unmirrored
  turns); head turn, nod and tilt from the iPad camera come from the face's own geometry. The iPhone measures the head
  against the phone, not against where tracking started. Live values draw once per screen frame.

### Characters
- **The neutral face is neutral**: a short level mouth, level brows, upright eyes. The smirk lives on as *Smug*.

### Media
- **Pictures and videos stand in the world as thin cards** (Add → Photo or video): a framed slab facing you, moved,
  turned, sized and keyed like any object; videos play on them frame-exact in exports. Transparent Manim renders still
  go over the frame. The bridge takes `?as=card|overlay`; `add_media(..., overlay=False)`, `lowey-link media --overlay`.

### Laptop tools
- `lowey-link pair 123456` finds the iPad by itself (Bonjour); `python -m lowey_tools` works when `Scripts` isn't on PATH.

## [1.3.1] — Smooth stage

- The live stage works out the glow halo at quarter size (it blurred the whole screen at full size every frame whenever
  anything glowed, including the blob's hover glow). Looks the same; exports keep the full-size halo.
- Blob faces stop making a new mesh every frame: springs settle to the exact pose and step in steps too small to see, so
  shapes are reused; the mouth works out each moment once instead of eight times.
- The renderer's mesh cache is bounded (it grew for as long as a face animated, so the app got slower the longer it ran).

## [1.3.0] — Phase 4: Characters, stability, feel

### Characters: the blob house style
- Hesham's own drawing turned into the house character (`assets/avatar`: traced from the drawing, built in Blender, GLB
  + .blend). In the app: **Add → Me**, or **Add → Blob** with a builder (who, hat and the name on it, hair, accessories,
  what they hold, colours).
- Famous people as blobs by their clues (Newton's wig and apple, Einstein's white hair and mustache, Turing, Curie,
  Darwin, Tesla, Lovelace, Edison, Sherlock…), in the app and in scripts (`{"do": "blob", "likeness": "Isaac Newton"}`).
- A real cartoon face: eyes, brows and one morphing mouth redrawn from dials every frame (happy crescents, wide eyes,
  curved closed lids, angry and worried brows, his smirk at rest). Springs make every pose **overshoot and settle**;
  the head squashes and stretches on the hits; the hat follows through; eyes blink on their own.
- **Expressions** (12) in one tap at the playhead, Character Animator-style, and `{"do": "expression"}` for Claude.
- Rubber-hose arms that follow the hands; no legs, a soft hover glow that stays on the ground.

### Stability
- First-launch crash fixed (the tour opened a scene with post-processing into a stage that hadn't rendered yet).
- Exports never hang: the screen stays awake, the export waits while the app is in the background and resumes, a
  stalled frame is retried and reported. The full narrated story exports start to end in CI.
- Playback no longer redraws the whole timeline every frame (lag while playing).
- Glow works (it did nothing: the surface shader multiplied it by an empty emission map); glow casts a halo; imported
  models glow in their own colours. Image overlays now reach exported videos.

### Timeline, camera, drawing
- Track groups: folders you fold; a folded group shows and moves everything inside. Drags lock to their direction,
  only selected keys and bars move, flicks glide, pinch zooms under the fingers, a quieter header with one menu.
- Camera Perform records the path you fly with your usual gestures. **Snap zoom** move.
- **QuickShape**: draw, then hold, and the stroke becomes a line, arc, circle, ellipse, triangle or rectangle.

### Media and Manim
- **Add → Photo or video**; videos play from a time and export frame-exact. `lowey-link media`, `lowey-link manim`
  (renders a Manim scene with a transparent background, ProRes 4444) and the MCP tools `add_media`, `render_manim`.

### Interface
- Liquid Glass chrome, focus mode (button, four-finger tap, ⌃⌘F), a small stats pill, Pencil hover preview off by
  default, remove colours from the palette, a gestures & shortcuts page.

### Claude
- One skill, `skills/lowey`: an orchestrator that routes to modules (breakdown, shots, sets, camera, characters,
  cartoon animation, Manim & media, style, troubleshooting). End-to-end test: pair over HTTP, send a script, approve
  on the iPad, find the result.

## [1.0.0] — Phase 3: Story, voice, VFX, AI, polish

### Timeline — keyframe multi-select (Procreate Dreams-style)
- Box-select keys across rows and time: long-press and drag, or switch on **Select** and drag. Taps add/remove in Select mode.
- **Pick** menu: all keys, everything after / before the playhead, keys at the playhead, keys in the loop, invert, none
  (scoped to the selected objects when something is selected).
- A band over the selected keys on the ruler: drag either end to **stretch or squash** their timing (proportions kept).
- Move many keys together (the earliest stops at 0), nudge by a frame (menu, ⌥⇧← / ⌥⇧→), ⌘⌥A selects all keys.
- Compose mode: pick several bars and slide them together.

### Audio & narration
- Voiceover, sound-effect and music clips: waveforms in the timeline, drag to move, volume, fade in/out, mute, trim to
  the playhead, split, delete; "duck music under the voice" from the transcript. Import from Files or record a voiceover
  while the animation plays.
- Playback follows the sound's clock (no drift). Exports carry the mixed soundtrack (AAC in .mp4/.mov; soundtrack.wav next
  to PNG sequences) — mixed exactly as previewed.
- Word timing with Apple's on-device SpeechAnalyzer (no Whisper): the model downloads once; English, Arabic, Italian first.
- Words lane in the timeline, transcript panel (tap a word to jump; long-press + tap to pick a phrase; fix words and keep
  their timing), snapping of keys, the playhead, sounds and effects to words, phrase actions (animate here, camera move,
  cut, marker, loop).

### Lip sync, face, your character
- Lip sync from the voiceover's words (CMU Pronouncing Dictionary + rules; Arabic and Italian), with the voice's loudness as
  fallback: stepped mouth shapes plus jaw and width keys — editable like any animation.
- Face performance from the iPad's front camera (Vision landmarks): blinks, brows, mouth, smile, eyes, head turn — live on
  the character, recorded with Perform. Optional iPhone companion (Face ID / ARKit) streaming over the local network.
- Character builder: head, hair, eyes, body, top, bottom, extras, colours → a low-poly character on the Humanoid standard
  with swappable mouth shapes; edit it later; save it to the library.
- Built-in humanoid clips (Idle, Walk, Run, Talk, Wave, Point, Type, Nod, Shrug, Celebrate) that play on built characters
  and imported humanoids; imported humanoid clips play on built characters too.

### Text, overlays, captions
- 2D overlays in frame space: titles, labels, arrows (draw themselves), highlights, the big X, question / exclamation
  marks, ticks, shapes, images; drag / pinch / twist on the stage; presets animate them (typewriter types, arrows draw);
  labels can follow a 3D object.
- 3D text: Blocky (built-in low-poly font) plus Rounded, Bold, Serif, Mono (any script).
- Captions from the transcript: Punchy (karaoke highlight), Subtitle, Pill, Outline; top / middle / bottom; burn-in on
  export; .srt and .vtt export. Portrait frames get shorter lines.

### VFX & post
- Particles: fire, sparks, smoke, dust, magic, rain, snow, confetti, embers, explosion — amount, size, speed, spread,
  colour; animate emission; bursts at a time. Deterministic (scrub and export exactly).
- Post (in the Look): glow, vignette, grain, exposure, contrast, colour, warmth, ink outlines, colour fringe, retro/PS1,
  paper / collage / old-film textures, depth of field from the camera (now rendered). One-tap finishes: Clean, Cinematic,
  Dreamy, Retro, Ink outlines, Collage, Old film. Identical in the live view and in exports.
- Screen effects on the timeline: flash, shake, speed lines, zoom blur, glitch. Transitions on cuts: fade, dip to black,
  wipe, zoom-through. Match-cut helper.

### AI layer & laptop link
- Scene Script v2: friendly actions (names, spoken-word times, presets, cameras, characters, look…) → preview → apply as
  one undo step. Paste from the clipboard, open a file, or send from the laptop. JSON Schema updated.
- LAN Bridge (off by default, pairing code, local network only): scene / assets / transcript / look queries, scripts
  (with approval on the iPad), snapshots, renders, file and audio import, undo, WebSocket events.
- `tools/lowey`: **lowey-mcp** (MCP server: 16 tools, 4 resources, 5 prompts) and **lowey-link** (pair, push, pull renders,
  watch a folder, Blender / text-to-3D generators, send scripts). Claude skills in `/skills`: script-breakdown,
  shot-planner, scene-builder, camera-director.

### Projects & polish
- Share a project as one `.loweypack` file and import it; archive / restore; copy a scene to another project.
- Welcome island sample (golden-hour fly-through) and a 60-second tour; the Enigma sample gains "5 · The story (narrated)"
  with a placeholder voice.
- Menu-bar commands with shortcuts (modes ⌘1–5, transcript ⇧⌘T, audio ⇧⌘U, record ⌥⌘R, bridge ⇧⌘B, markers ⌘M…),
  Apple Pencil hover preview, localisation scaffold (Arabic, Italian), thermal-aware preview, local diagnostics log and
  "Export diagnostics".

### Engineering
- Schema v3 (additive). New Core areas: `Audio/`, `Text/`, `VFX/`, `Face/`, `Character/`, `AI/`, `Project/ProjectPackage`.
- LoweyRender: `FrameCompositor`, `OverlayRenderer`, `StagePost`, depth world + `loweyDepth` / `loweyInverseDepth` shaders,
  particle meshes, text meshes; exporter composites, renders transitions and writes audio.
- Tests: Core (~180, Linux), render and speech tests on the simulator (`Phase3Tests`), laptop tools (pytest) in CI.

## [0.8.0] — Phase 2: Motion, camera, characters, export

### Timeline
- Bottom timeline drawer in Animate and Camera modes: transport, frame stepping, scrubbing ruler, markers (tap to jump,
  long-press to rename/delete), loop region, zoom (pinch) and pan, one row per animated object (expand into property
  rows), behaviour spans, clip segments, camera-cut row.
- Modes: **Compose** (slide whole animations in time), **Perform** (record by touch), **Keyframe** (select, drag,
  retime keys). Frame rate 24/25/30/60, length, "fit to animation".
- Timeline evaluation, per-object and per-project stepping (cameras stay smooth) — all in LoweyCore, unit-tested.

### Keyframes & easing
- Keyframe any animatable property: auto-key (edits in Animate/Camera mode become keys at the playhead), animated
  properties always key, "Key" button (⌘K).
- Easing presets (linear, in, out, in-out, overshoot, bounce, elastic, step) + a curve editor with draggable handles.
- Copy/paste (also onto another object), mirror (there and back), reverse, twice as fast/slow, delete.

### Perform mode
- Record → "Ready 3-2-1" → the timeline plays; drag to move, pinch to scale, twist (or Apple Pencil Pro barrel roll)
  to turn. Lift = pause, touch again = resume. Smoothing 0–100 %. Sliders perform any number (glow, light, opacity,
  zoom, focus). Re-performing replaces only the performed range. One undo step per take.

### Presets & mass animation
- 15 one-tap presets: pop in/out, grow, shrink, bounce, wiggle, float, spin, shake, pulse, fade in/out, slide in,
  drop in, typewriter — real, editable keys.
- Many objects at once: delay, order (selection, left→right, right→left, front→back, wave), random timing and strength.
- Behaviours: follow a drawn path, look at, follow (with lag), orbit, wobble, wind sway, bob on water, spin —
  deterministic, bake to keys. Animated generators (arrays/scatters grow in one by one).
- Simulations baked to keys: fall, explode, flock of birds, crowd walks in.
- Scripting (JavaScriptCore): script panel with inline errors and a log; scripts saved in the library; examples:
  forest grows in, flock of birds, crowd walks in. Every run is one undo step.

### Characters
- Skeletons and clips read from glTF/GLB in LoweyCore; clips play on skinned models (poses → joint transforms).
- Standards Humanoid / Quadruped / Bird / Custom with auto bone mapping (Mixamo, Quaternius-style, Blender, generic).
- Retargeting: a clip for a standard plays on any character of that standard (tested on 2 humans, 2 quadrupeds).
- Clip track: play from the playhead, loop, speed, crossfade; walk speed matched to a path (no sliding); feet on the
  ground, head look-at, hand reach (IK). Crowd tool: N copies with offset, varied clips.
- Puppet joints: wrap parts in a joint that pivots at the top/middle/bottom (shoulders, hips, hinges).

### Camera
- Look through the shot camera; drag to aim, two fingers to move, pinch to dolly, twist to roll — keyed.
- Cameras + camera-cut track ("Cut here"). 10 one-tap moves: push in, pull out, punch in, orbit, dolly, truck, crane,
  whip pan, shake, reveal; follow the selection.
- Lens: focal length, focus distance, aperture, focus on selection, animated focus pull (rendered blur arrives with
  Phase 3's post-processing — see DECISIONS D50).
- Framing guides 16:9 / 9:16 / 1:1 with safe zones and thirds; per-camera 9:16 zoom and pan, so one camera exports both.
- The iPad as a virtual camera (ARKit world tracking, scale factor), recorded through Perform.

### Export
- Video rendered frame by frame at a fixed timestep: 16:9 + 9:16 (+ 1:1) in one job, HD/4K, H.264/HEVC, PNG sequences,
  transparent background (HEVC with alpha / PNG), whole timeline or the loop region; progress and cancel; saved in the
  project's renders folder; share or save to Photos. Single frames through the camera.
- 3D export of the selection or the scene: glTF (.glb) and USDZ.

### Engineering
- Schema v2 (Phase 1 files open unchanged). New commands: `setTracks`. Deleting/duplicating objects carries their animation.
- New package `LoweyScript`. New Core modules: Motion, Rig, Export. Sample project gains "4 · Opening (animated)".
- CI: `[build-only]` in a commit message runs a compile-only app job (saves macOS minutes).
- Fixed: Mixamo "Fo**rear**m" was read as a quadruped's rear leg by the rig classifier.

## [0.4.0] — Phase 1: Foundation & Build

### Engineering
- XcodeGen project (`project.yml`), Swift 6 strict concurrency, packages `LoweyCore` + `LoweyRender`, app `LoweyApp`.
- CI: SwiftFormat + SwiftLint → LoweyCore tests on Linux with ≥ 80 % coverage gate → iPad simulator build,
  render tests and UI smoke test (screenshots exported as artifacts).
- Release: unsigned device build → ad-hoc codesign → `Lowey.ipa` on every `main` push; GitHub Release on `v*` tags.
- Docs: README (Sideloadly install), ARCHITECTURE, DECISIONS, THIRD_PARTY.

### Core model
- Objects with typed, animatable properties; groups/hierarchy; lights; cameras; drawn objects (recipes); prefab instances.
- Command system with exact inverses, batches, JSON encoding (Scene Script vocabulary); undo/redo with gesture coalescing.
- Timeline, keyframes, easing (linear, in, out, in-out, back, bounce, elastic, step, bezier), on-twos stepping.
- Project folders (`.lowey`), schema versioning + migrations (v0 → v1), atomic writes with backup recovery, autosave.

### Render
- RealityKit bridge with diff-based sync, shared meshes/materials (instancing), fog + glow surface shader.
- Looks: smooth/flat shading, linked palette, 6 mood presets, sun with shadows, sky gradient + stars, fog, ground,
  sky-driven ambient light, custom point/spot/directional lights with shadows, emissive glow.
- Offscreen renderer (RealityRenderer) for snapshots and thumbnails — the Phase 2 export path.

### Building
- Blockout primitives (cube, sphere, cylinder, cone, plane, torus, ramp); swap blockout → library model (fit to size).
- Gizmos (move/rotate/scale), on-screen joystick, direct drag, numeric inspector.
- Snapping: grid, ground, flush to other objects, rotation steps.
- Duplicate, copy/paste, array (row, grid, circle), scatter an area in one gesture (seeded), group/ungroup,
  outliner with lock/hide/reparent, align/distribute.

### Drawing in 3D
- Pencil pressure strokes with smoothing → tube or ribbon; extrude a drawn outline; lathe a drawn profile; mirror.
- Guides: plane locked to the view (or ground/front/side) with offset, box, cylinder, sphere, or any existing object.
- Save anything to the library.

### Library
- Global library (USDZ, glTF/GLB with dependencies, OBJ; files, folders, drag & drop, share sheet).
- Auto thumbnails, search-first panel, tags, favorites, recents, RIGGED badge (skeleton + clips kept), prefabs that
  update everywhere, saved looks. Projects reference assets by id; "Export" copies them in.

### UI
- Home with project thumbnails; stage with left tool rail, top-right mode switcher (Build · Animate · Camera · Look ·
  Export), inspector, library, outliner, look panel; snapshot export as PNG in 16:9, 9:16 and 1:1 (HD / 4K).
- Keyboard shortcuts (⌘Z, ⇧⌘Z, ⌘D, ⌘C, ⌘V, ⌘G, ⌘A, ⌘⌫ delete, ⌘F frame, ⌘L library), haptics, Stage Manager friendly.
- Sample project: the Enigma sets.
