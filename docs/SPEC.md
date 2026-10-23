# Maquette — product spec

**Shapr3D's ease, Procreate's feel, Dreams' animation and ToonSquid's rigging, in 3D, for people without an
engineering or art degree.** The measure of success is the time from an idea to seeing it 100% ready. Maquette is the
continuation of 3D-lowey 2.0, made by **studio h.**; this file is studio-h's CONTEXT §10 kept true to the code: what
is built says so, what isn't says which phase brings it. Everything 2.0 does (sections 1–12 below) is the behavioural
reference and stays.

| Area (CONTEXT §10) | Status |
|---|---|
| Name, icon, bundle ids, `.maquette` projects | **0.1.** Temporary icon (2.0's cube in the studio neutrals) until the identity phase (S1). |
| Nothing is ever lost: the history journal, undo after relaunch, versions, the History scrubber | **0.1.** [PROJECT_FORMAT.md](PROJECT_FORMAT.md) |
| Apple Pencil: hover point at the tip in the stage's own pass, outline only while resizing | **0.1** |
| Device tiers (A/B/C) and the load meter | **0.1**; silent since **0.8** |
| The layout of §10.1 (the canvas owns the screen, timeline on call, floating inspector, living gallery, starter templates) | **0.2.** [LAYOUT.md](LAYOUT.md) |
| Modelling I (select, push/pull with numbers, sketch on surfaces, booleans) | **0.3** |
| Modelling II (bevel, round, inset, shell, mirror and live symmetry, array along a path, corner/edge/midpoint/face snapping, measure, section view, kept dimensions, 3D printing, architecture) and interop (glTF, USDZ, OBJ, STL, 3MF, the Blender package) | **0.4.** FBX isn't offered (D-133). |
| One brush engine, Brush Studio, Procreate/Photoshop brush import, drawing guides | **0.5.** Ink, flipbooks, painting on models and the Schizzo board draw with it; since 0.9 the engine is hmm-kit's (D-189). |
| Painting on models: xatlas unwrap, Paint ▸ Colour (paint, erase, fill, eyedropper), layers, projection from the camera, textures in exports | **0.6.** Roughness, metal and glow painting come later; objects with drawn skeletons are painted in their rest pose, imported skins not yet (D-171). |
| One skeleton system, draw a bone (bone-heat weights, weight painting), rig as a person, 2D drawn puppets, pose by dragging with IK, pose library, built-in clips on any humanoid | **0.7.** The person rig is placed by eight taps: Apple's body-pose model can't be checked on CI (D-168). |
| Fixes and touch: the silent load meter, one hold menu everywhere, Pencil or hand, the Motion row, the colour well, rigging in three steps with the bone redrawn | **0.8** |
| The Schizzo board: brush strokes, pictures, notes, arrows and frames on an endless sheet in every project; pins as reference cards and scene planes; the Sketch template | **0.9.** In hmm-kit (`HmmBoard`, `HmmBoardUI`), so Cutaway mounts the same board (D-200). Strokes blend normally; no MCP tools yet (D-201). |
| Live performance: the face, the voice and the hands driving any puppet (3D and 2D), blinking and breathing, triggers, draggers, dangling bones, takes and comping, the iPhone as the face camera | **0.10.** The voice gives the mouth the shape of the sound, not of the words (D-211); hands are the wrists (D-212); draggers stay where they're left (D-210). |
| The layout pass (U2): the Library and Rig, the scene as a door, the object panel on one screen and moved by hand, one menu per object, Perform and Keys, the dark studio, the resting sidebar, the held features | **0.12.** [LAYOUT.md](LAYOUT.md) is the map; D-226 … D-239. Live performance's entry points are held in App Store builds until 1.2 (D-228). |
| Draw (U3): the sheet (four shapes, placed by hand, kept and named), Sketch in Draw and talking back, flipbooks on the sheet with the frame strip, the hand shortcuts and the squeeze menu, the Snap magnet, our number pad, Settings ▸ Pencil and hands (who does what, the Pencil page with its test pad and calibration), the Reference window, the timeline as Dreams has it, the brush library dropping down | **0.13.** D-240 … D-258. Hold-to-clean-shape and the squeeze menu on the board's own drawings come with the Board's finish (M14) as far as clean shapes go. |
| Rig, and bring your sculpt: pins and dots, Person / Chain / Four legs / Wings guessed from the shape, rigs you change any time, solid parts hinged, shapes cut finer to bend; motion saved to the Library and dropped anywhere, repeats by a motion's end, four feels; sculpts in painted and lightened with Detail, landing with Rig it; skinned glTF and our own FBX for game engines | **0.14.** D-259 … D-278. The Nomad fixture joins when Hesham exports one (D-275); Unity is a computer check (D-276). |
| Draw again and one grammar (U5): one Draw where the brush decides (lines, paint, solids, shapes, shadow), zero setup (the surface, else the sheet facing you), the sheet as paper with a hold menu, strokes under the tip (a UI test), shapes in one drag pulled into solids, a tapped stroke's chip, flicked frames and onion skins on the timecode, every number a slider, two fingers on the view, press and carry, hover lighting, the lasso's three homes, the quick menu per tool, the eyedropper loupe, titles stuck to the camera, to the ground by the real shape | **0.15.** D-280 … D-300. Smudge on painted models comes with U7 Texture (D-283). |
| Shape (U6): touch and drag with no modes (the Pencil lights the face, edge or corner of the selected shape; drag pulls, rounds, moves), the part's chip (inset, shell, bridge, knife, bevel, round, loop cut, merge, fill hole), Model's bar (Shape, Brush, Cage, Bend, Measure), Smooth and making it real, the smooth angle and flat shading, triangle count, clean topology (Instant Meshes), linked copies, the pivot, typed sides, sweep / revolve / loft, sketch rules with our own solver, the view cube, the bridge's `model` and `profile` | **0.16.** D-301 … D-325. Strokes on placed models need them painted first (D-318); the cage doesn't animate yet (D-317). |
| Characters (K1): Characters ▸ New from five starts, parts with jobs from our own set (or drawn, or modelled) on a character or any thing, the rig built itself, 14 mouths and brows as bends, Say a line, proportions by handles, act it out, GLB for Godot / Unity / Unreal with blend shapes and named clips, sprite sheets, pixel art, turnarounds | **0.20.** D-386 … D-406. Rigid pieces (D-391); people act, animals don't yet (D-397). |
| Film (F1): the soft panel, setups (three-point, golden hour, moonlight, neon), haze and god rays, an HDRI as the sky and the light; camera bodies and real millimetres, the frame's shape (16:9, 2.39:1, 9:16, 4:5, 1:1), focus on a thing and focus pulls, rigs (dolly, crane, orbit, handheld); storyboards and animatics; spatial video and photos, 360° video and panoramas, HDR, wide colour; the rotoscope | **0.22.** D-433 … D-458. 360° is six views laid flat (D-450); HDR is HLG (D-451); only the sun throws god rays (D-442). |
| Motion design (D1): logos from SVG as solids, fonts brought in, letters that animate (seven presets), clones (grid, circle, line, a path) with effects (random, delay, push) through fields (everywhere, near a point, a ripple), links between things and to a sound's loudness, bass or beat, morphs, the seamless-loop check and Close the loop | **0.23.** D-459 … D-475. Copies live only in the shown scene (D-463); morphs are between shapes made here (D-467); 3D files carry copies and letters at rest (D-474). |
| Looks & the library (L2): Painterly, Watercolour, Gouache, Paperman, Anime cel, Clean product, Pixel; the Finish on any Look (Ben-Day, boil, misregistration, newsprint, riso, canvas; impact frames, focus lines, Kirby dots aimed at a thing); the Look, Effect and Part Studios; `.maquettepack` packs with an author and a licence; PSD, PSB and Procreate drawings as dioramas; eight grounds; stacks as folders; the Keeper's Tower sample turning | **0.24.** D-476 … D-496. The paint pass is a whole-frame pass (D-477); Pixel is the scene's (D-481); packs carry data only (D-485). |
| Guest kits (G1): Set up for Room, Print, Game, Study; Room's roofs, columns, beams, railings, people, terrain, plans per floor with room areas, elevations, walking through, underlays to scale, match a photo, scan a room, IFC / DXF / PDF / SVG; Print's overhangs, best way up, split with pegs, hollow, engraving, ISO screw holes and printed threads, the jar and lid, bolts and nuts, multi-colour 3MF, scan an object; Study's exploded view and technical drawing; Game's greybox, freeze, levels for Godot / Unity / Unreal; a mannequin, layered PSD, Procreate palettes, papercraft and laser nets, ink as SVG | **0.25.** D-497 … D-523. Doors and windows leave IFC inside their walls (D-502); gable and hip roofs cover the smallest rectangle (D-503); the iPhone companion's scans come with U8 (D-506). |
| Yours (U8): the left hand mirrors the chrome, each corner arranged (order, hidden) within itself, the sidebar along its edge, rebindable keys, defaults for the +; Present (the film, a walk, the model); review notes on spots, answered in place; reviews over FaceTime; the iPhone companion (face, camera, remote, AR, room and object scans) | **0.26.** D-524 … D-539. Reviews need the developer account's signing (D-532); the stage's transport keys stay fixed (D-527). |
| Texture (the full colour picker, layers, smudge on paint) | U7 |
| Mechanisms + AR, web layer (held) | M12 |
| Content and finish: the house kit, waiting designed, the Board's finish | M14 |
| Tutorials in Hesham's voice, artist info, Content Credentials, Time-lapse, Report a problem | M16 |

### Where 0.10's controls live since 0.12

Cast is gone (D-227): what said *Cast ▸ Voice & face*, *Triggers* and *Life* below is the selected character's
button beside Record in the timeline's Perform; *Cast ▸ Rig* is Rig; *Make it part of* is in Rig. Everything below
still works the same way.

### Yours (0.26)

- **Your layout** (D-524 … D-526): Settings ▸ Yours ▸ Your layout: Hand (left mirrors the corners and the sidebar), the
  document's corner, the making corner and the view corner in your order with any hidden (Home and Actions stay), the
  sidebar's place (the short line under it drags it along its edge), Reset layout.
- **Keyboard** (D-527): Settings ▸ Yours ▸ Keyboard: every menu-bar command, tap and press the new keys; hold a row for No
  key or Its own key.
- **New projects** (D-528): Settings ▸ Yours ▸ New projects: the + makes your set-up, Look, units and brush. Your name
  signs your notes.
- **Present** (D-530): Actions ▸ Present (⇧⌘P): the film round and round, Walk through, Show the model; a tap for the
  controls; AirPlay or a cable shows it on a TV.
- **Notes** (D-531): Actions ▸ Notes (⇧⌘N), Add a note, then the spot; a pin's tap opens its thread (reply, Resolve,
  Delete); Clear resolved.
- **Review over FaceTime** (D-532): in Actions during a FaceTime call: the project goes to the others; the same view,
  notes for everyone.
- **Your iPhone** (D-533): Actions ▸ Your iPhone: your face, Camera, Remote, See it in AR, Scan a room, Scan an object; on
  iPads without LiDAR, Room's and Print's scan tiles are Scan with your iPhone. On the iPhone the app is the companion.
- **The bridge** (D-534): `note` (add, list, reply, resolve, reopen, delete).

### Guest kits (0.25)

- **Set up for** (D-497): the scene's name ▸ Set up for: Blank, Room, Print, Game, Study, Animation; Home's quiet row
  starts any of them. A set-up's kit is in Model ▸ Add and Model ▸ Edit; Blank shows none.
- **Room** (D-499 … D-507): Model ▸ Add ▸ Building (walls, floor, door, window, stairs, roof and its kind, column, beam,
  railing, person, room name, terrain); Plans and the site (Plans: each floor's plan with the rooms' areas and the four
  elevations; Walk through; Underlay; Match a photo; Scan a room where the iPad has LiDAR). Export ▸ 3D ▸ IFC; Export ▸
  Paper ▸ Plans & elevations (PDF on A3, the ground floor as DXF or SVG).
- **Print** (D-508 … D-511): Model ▸ Add ▸ Print (Jar & lid, Bolt, Nut; the screw size); Model ▸ Edit ▸ 3D print: Show
  overhangs, Best way up, Split (across height, width or depth), Hollow, Screw hole and Write on it (then tap the part),
  the hole's kind and the screw, the words, the Fit, Scale to size, Share to the slicer, Scan an object.
- **Study** (D-512, D-513): Model ▸ Edit ▸ Study: Explode (a group), Forces; Export ▸ Paper ▸ Technical drawing (A4, A3).
- **Game** (D-514, D-515): Model ▸ Add ▸ Greybox; Model ▸ Edit ▸ Game: Freeze transforms; Export ▸ 3D ▸ Game level (for
  Godot, Unity, Unreal; One texture for everything).
- **For illustrators** (D-516): Characters ▸ New ▸ Mannequin; Export ▸ Picture ▸ Layered PSD, Ink as SVG; Library ▸ Yours
  ▸ Bring in a palette; Export ▸ Paper ▸ Papercraft (A4, Letter, a laser net).
- **The Kit menu** (D-517) and **the bridge's `guest`** (D-518).

### Looks & the library (0.24)

- **Looks** (D-476 … D-481): Look ▸ Style: Ink, Comic, Sketch, Painterly, Watercolour, Gouache, Paperman, Anime cel, Clay,
  Clean product, Low-poly, Pixel; then My Looks and Your Looks. Hold a Look: Duplicate, Open in the Look Studio, Save to
  Yours, Share as a pack, Delete.
- **The Look Studio** (D-484): Light (bands or soft, shadow tint, reflection), Lines, Paint (stroke size, strokes, wet edges,
  granulation, paper; pixel size and colours), Print, Motion, About.
- **The Finish** (D-482, D-483): Look ▸ Finish: textures (paper, collage, old film, newsprint, risograph, canvas), Print
  (Ben-Day dots, line boil, focus by misregistration), screen effects at the playhead with Impact frame, Focus lines and
  Kirby dots, which follow the selected thing.
- **Grounds** (D-489): Library ▸ Things ▸ Grounds.
- **Yours and packs** (D-485, D-486): Library ▸ Yours: Share a pack (pick things, your name, the pack's name, what others
  may do), Bring in a pack; your Looks, effects and parts (hold: Open in the Effect or Part Studio, Share, Delete). The
  particle effect's panel and a character's part: Save to Yours.
- **Drawings** (D-487, D-488): Model ▸ Add ▸ Drawing (PSD, Procreate); a drawing dropped on the stage or opened from Files.
- **Home** (D-490, D-491): stacks are folders; a project's menu ▸ Move to…; a stack's menu ▸ Sort inside; the Samples stack
  with the Keeper's Tower turning.
- **The bridge** (D-492): `look` (any Look, `ground`, `finish`), `effect` (`impact`, `focusLines`, `kirbyDots`; `target`,
  `center`), `add_media(drawing=True)`.

### Motion design (0.23)

- **Logos** (D-459, D-460): Model ▸ Add ▸ Logo (SVG): one solid a fill colour, grouped, a metre wide, the upper colours
  proud; the toast names what was left out.
- **Fonts and letters** (D-461, D-462): the text's panel: Font (the style's, the project's fonts, Bring in a font…) and
  Letters (None, Fly in, Bounce in, Cascade, Pop, Spin in, Type on, Wave; Order, Between letters, Each letter or One wave).
- **Clones** (D-463, D-464): the object's menu ▸ More ▸ Clone…; the object's panel ▸ Clones: Layout (Grid: across, deep,
  high, spacing; Circle: copies, radius, facing out; Line: copies, spacing; Along a path: copies, the path, turned along
  it), the effects with their numbers and Where (Everywhere, Near a point, Ripple), Add an effect, Effect strength, Remove.
- **Links** (D-465, D-466): More ways to move ▸ the links that move the selection (How much, Remove), Link to another thing…
  (four presets, then tap the driver), and, with sound on the timeline, To the sound's (Loudness, Bass, Beat) · It (what
  moves) · Move to the music….
- **Morph** (D-467): the object's menu ▸ More ▸ Morph into…, then tap; the object's panel ▸ Morph: what it becomes, Remove.
- **Loops** (D-468): the Export sheet beside a video or GIF: Loops seamlessly, or Jumps when it loops with what jumps and
  Close the loop.
- **The bridge** (D-470): `design` with `op` logo, clone, effect, link, morph, letters, loop; `text` `font`;
  `add_media(font=True)`, `add_media(logo=True)`.

### Film (0.22)

- **Lights** (D-440, D-441): Model ▸ Add ▸ Bulb · Spot · **Soft panel** · Sun. A light's panel: colour, strength, reach, a
  spot's cone, a panel's width and height, and **Setups**: Three-point, Golden hour, Moonlight, Neon (More setups: the six
  toon recipes), placed around the selection the way the shot camera sees it; the last setup's lights are replaced.
- **The air and the sky** (D-442, D-443): Look ▸ World ▸ **Sky from a picture** (an HDRI: Radiance .hdr; turn, brightness,
  back to the mood's sky) and **Air** (haze, god rays).
- **The lens and the frame** (D-444 … D-446): on the camera's panel and the camera button's **Lens and frame…** (⌥⌘L): the
  camera body, the focal length in its millimetres, the aperture, **Focus on selection** (the lens follows it), **Pull focus
  here** (from the playhead), By distance; the frame's shape and its thirds and safe areas.
- **Rigs** (D-447): On a tripod · Dolly (travel) · Crane (lift, swing, arm) · Orbit (swing, lift) · Handheld (shake); each
  number keyable with its diamond.
- **Exports** (D-448 … D-452): Video ▸ Animatic, Spatial video, 360° video, HEVC ▸ HDR 1080p and 4K; Picture ▸ Spatial
  photo, 360° panorama, PNG ▸ Wide colour 4K; Paper ▸ Storyboard (A4, US Letter). The option Depth for spatial ones.
- **Rotoscope** (D-453): Actions ▸ Rotoscope: a video from Photos behind the stage, from the playhead; opacity, over the
  scene, start at the playhead, another video, remove. Never exported.
- **The bridge** (D-454): `film` with `op` lens, frame, focus, rig, air, environment, shots; `light` `type: panel`;
  `lighting` gains the four setups; `add_media(environment=True)` for HDRIs; `sketch`, `boolean`, `profile` ▸ `pull`.

### Animate and export (0.21)

- **Animate's bar** (D-411): Path · Look at · Pick up · Properties · Ghosts · Dope sheet, under the stage while Animate is
  on (with the timeline). With no verb the Pencil picks, moves and poses, and keys add themselves. A making tool puts
  Animate away. Keys: ⌥⌘4 Path, ⌃⌘L Look at, ⌃⌘P Pick up, ⌃⌘G Ghosts, ⌃⌘D the dope sheet (the Timeline menu).
- **Path** (D-407 … D-410): with one thing selected, draw where it goes: keys from the playhead at the drawing's own
  speed, on the surface under the line (else level with where it last stood), facing the way it goes and leaning into
  turns (characters upright). The chip: Lasts (a number to drag or type), Even speed, Turn its front, Face the way it
  goes, Lean into turns. The path's dots on the stage still reshape it.
- **Look at** (D-416): tap the thing it watches (a character turns its head, the rest turns whole); a later tap switches
  from the playhead over a quarter second; the empty ground stops it. **Pick up** (D-415): tap the hand (or the thing)
  that takes it at the playhead; another holder later is a hand-off; the empty ground puts it down where it was left.
- **Properties** (D-417): everything the selection can have keyed; a tap keys it at the playhead (a diamond marks what
  moves).
- **The timeline** (D-412 … D-414): Motion rows (46 pt, the thing's icon in its colour, a curve of how much it moves,
  dots a frame), frames as cells when 9 pt wide; the Dope sheet style (every track under its thing). Ghosts: three
  moments either side of the playhead while the ruler is dragged.
- **Export** (D-418 … D-427): Video (MP4, HEVC, ProRes 4444 where the iPad writes it, GIF, PNG frames, Render passes,
  Captions) · Picture (PNG, Render passes) · 3D (glTF for Godot / the web / Blender and 3D apps, FBX for Unity / Unreal,
  USDZ, OBJ, STL, 3MF, Blender ▸ Render on a computer, Maps, the Look as a shader for Godot / Unity) · Paper (this frame on
  A4, US Letter or A3; frames across the shot). Options: Final, Transparent background, Only the selection, Every scene,
  Every shot, Only the loop, a glTF's painted colour, custom size, frame rate and quality.
- **The bridge** (D-428): `motion` with `op` path, follow, lookAt, pickUp, putDown, letGo, evenSpeed, timing, front.

### Characters (0.20)

- **Library ▸ Characters** (D-401): New (Person, Four legs, Wings, Blob, Nothing), Ready-made (Blob, Me, Puppet) and
  everything with a skeleton. A new character lands where new things land, selected, its panel open.
- **Parts** (D-387 … D-389): the object panel's Parts: head, eyes, brows, mouth, nose, ears, hair, body, arms, legs, tail,
  wings, extras; a tap adds one with its default style, a hold offers the others; Mirrored (on) makes paired parts a pair
  and changes both sides; added again, another one. The picked part's styles and Take it away. Any thing's panel: Give it
  parts (the thing becomes the body). A drawing or a modelled thing near a character: Make it a part (as a part, or as
  the drawing of a face state).
- **The rig** (D-390, D-391): built from the jobs with U4's dots as soon as the parts change, and again after parts are
  moved by hand; a person's is the humanoid (every humanoid clip plays on it). The dots are editable in Rig.
- **Face** (D-392 … D-394): the mouth's 14 shapes (Character Animator's), brows neutral/up/angry/sad, eyes open/blink;
  tap one to see it, Bend it (open, wide, round, smile, lift, tilt, close), As it came. Lip sync, the live voice and face
  capture drive them. **Say a line** (D-395): typed words from the playhead.
- **Proportions** (D-396): height, head, body, waist, arms, legs in the project's units to drag or type; handles on the
  stage while open; the feet stay on the ground.
- **Act it out** (D-397), people: As in a mirror; Film yourself (the system camera) or From a video (Photos); progress;
  keys from the playhead.
- **For games** (D-398 … D-400): a sheet: For an engine (Godot, Unity, Unreal) ▸ Export GLB; Sprite sheet (4 or 8
  directions, the motions: Still, Timeline, the humanoid clips; frame size; pixel art and its height) ▸ a zip of PNG, JSON
  and a Godot SpriteFrames; Turnaround ▸ a PNG.
- **The bridge** (D-402): `character` with `op` new, add, style, remove, assign, state, proportion, say, rig.
- **Keys**: ⇧⌘C New Character…, ⌥⌘P New Person, ⇧⌘E Export for Games….
- **Fixed** (D-386): one rate turns the view everywhere (the stage in any orientation, the Director view, the view cube).

### Physics (0.19)

- **Real** (D-367, D-369): the object panel's Real row. The switch; a material in words (wood, steel, aluminium, stone,
  concrete, glass, ice, plastic, rubber, foam, cardboard, cloth, jelly); how it moves (Falls, Stays put, Follows its
  keys); what it weighs once the run is made; Hangs from its top edge (cloth). Exact numbers one step deeper: mass (kg,
  or from its size), grip, bounce, breaks when knocked hard (or stiffness for cloth and jelly), a start speed, Show speed
  and forces. Several things at once: Make them real, Made of…, Not real.
- **The run** (D-366, D-370, D-371): from the scene's start time to the end of the timeline, worked out in the
  background and played as far as it's gone; playback waits at its edge. Rigid bodies, joints, ragdolls (a rigged thing
  that falls, D-373), cloth and jelly (D-374), breaking (D-375), wind and forces (D-376), fluids (D-377).
- **Joints** (D-369): Real ▸ Join them (two things) or Join to the world (one): hinge, slider, ball, glue, spring, rope,
  gear (two hinged wheels). Each joint is a row: its motor (°/s or m/s), a spring's bounces a second, ✕. Marks on the stage
  while the thing is selected.
- **Behind the scene's name** ▸ Physics: gravity (Earth, Moon, Mars, Jupiter, Floating), wind (speed, where it blows
  toward, gusts), a solid ground, when things start; the run's progress; Keep it.
- **Model ▸ Add ▸ Forces & fluids**: Fan, Pull, Whirl (strength, reach); Pour water, Splash, Billowing smoke, Flames
  (amount, seconds, the room's size, colour).
- **Keep it** (D-372): the run as keys; what fell follows its keys afterwards. **Settle** (D-378): the object's menu, or
  Real. **Does it stand?** (D-378): one line, and the centre of mass, plumb line and footprint on the stage.
- **The real sun** (D-379): Look ▸ World ▸ Fine tune the world ▸ Real sun: a place (ten cities, or latitude and
  longitude), a date, a time, which way north is; Shadow study across the timeline with its hours.
- **Export** (D-380): video and stills wait for the whole run; glTF, Blender and FBX bake it into keys; glTF carries
  colliders (OMI_physics_body, OMI_physics_shape).
- **The bridge** (D-382): `physics` with `op` real, unreal, scene, joint, unjoin, force, fluid, keep, settle, stand, sun.
- **Keys**: ⇧⌘J make real, ⌥⌘J not real, ⌘J settle, ⌥⌘U does it stand, ⇧⌘K keep the run.

### Texture (0.18)

- **Layers per map** (D-338): Draw ▸ Layers while painting a thing. The chips under the layer choose what the brush
  paints: Colour, Roughness, Metal, Glow, Bumps, Fur, or the layer's Mask; a grey map takes a value (Rough, Metal,
  Height, Length). Each layer shows its maps as badges. Swipe a layer: Mask, Duplicate, Delete; drag it to reorder; pinch
  two fingers together over the list to merge the chosen layer down. Add ▸ Layer, Colour fill, Dirt, Worn edges. Blend
  modes gain Darken, Lighten and Soft light.
- **Masks** (D-338, D-363): a layer's mask shows it where painted, hides it where erased; a new mask shows everything.
- **Fills** (D-340): a fill layer is made from a colour, a material or wear, and changes as a whole (wear's Amount, the
  colour in hand). Painting a fill paints its mask; *Paint it on* adds a material behind an empty mask.
- **Smudge** (D-346) drags paint along the surface; **Erase** works with the brush in hand on any map.
- **The colour picker** (D-361): the disc, values (HSB, RGB, hex), palettes, the colour before, recent colours, the
  scene's palette first, and Materials. **Drops** (D-360): a colour onto a thing is its colour; a material is a fill.
- **Materials** (D-341 … D-344): tap to fill, drag onto any thing, hold for Paint it on, Edit (the Material Studio:
  Look, Surface, Pattern, Bumps, About), Duplicate, Delete. Import a set takes a PBR set's pictures by their names.
- **Surface** (D-362, the bar's sixth button while painting): Brushes (Faces: a tap fills a flat face; Seams: tap edges,
  then Cut, or Automatic), Wear (Dirt, Worn edges), Decal (Photos or Files, then a tap where it goes, its size), Mirror
  (Off, Left and right, Top and bottom, Front and back), Texture size (512 … 4096), Flat view (paint the surface laid out
  in 2D), Detail from a sculpt (bake normals from another thing; Remove), Fur (length, density, droop, Soft or Hair cards).
- **Hatched shadows** (D-358): Look ▸ Hatching, beside Halftone.
- **Export** (D-354, D-356): glTF carries roughness, metal, glow and normal maps; USDZ the same; Maps (PNG) writes each
  painted thing's maps as pictures; glTF's Painted colour: Texture, Vertex colours or Palette. Fur leaves as cut-out
  shells or hair cards (D-355).
- **The bridge** (D-359): `paint` with `op` color, material, wear, decal, faces, layers, mask, mirror, size, seams,
  bakeNormals, fur.
- **Keys**: ⌘⇧F paint flat, ⌘⌥W dirt, ⌘⌥E worn edges, ⌘⌃M mirror paint, ⌘⌥⇧F the faces brush.

### Editable history (0.17)

- **The steps list** (D-327 … D-334): Actions ▸ History (⌘Y) shows, over the scrubber, the selected modelled thing's
  steps in plain words ("Hole, 6 mm", "Round, 2 mm"). Tap a step: its numbers as pills (a push/pull's distance, an inset's,
  a bevel's size, a round's radius, a shell's thickness; a sketch's depth unless it went through, a circle's diameter, a
  rectangle's sides). Changing one replays the steps after it off the main thread and lands as one undo step,
  "Change Hole". A replay that can't continue says which step and why in one line, and changes nothing.
- **Steps** are push/pull, inset, bevel, round, shell, a sketch area pulled out of or cut into a thing, and a boolean (one
  step per solid combined). Each finds its faces and edges by tag after earlier steps change (D-327).
- **Fixed**: a change by hand (corners, knife, loop cut, merge, fill, bridge, subdivide, clean up, a scale baked in)
  starts the steps again from the shape as it is; the old ones are listed with a lock (D-329). Painting or rigging fixes
  them too (D-330). While the scrubber shows an earlier moment, steps don't change ("Come back to now").
- **The bridge** (D-335): `model` with `op: steps` and `op: step`.

### Shape (0.16)

- **Touch and drag** (D-302 … D-305): select a shape; the Pencil lights the face, edge or corner under its tip (a corner
  within 16 points, an edge within 11, else the face). Drag: a face pulls, an edge rounds, a corner moves across the plane
  facing you. Tap: the part is picked and its chip offers the rest; hold to add a part. Blockout shapes become modelled
  quietly; a placed model has *Model it*. With no Pencil: Model ▸ Shape.
- **Model's bar**: Shape · Brush · Cage · Bend · Measure. The brushes (grab, smooth, inflate, mirrored) take the sidebar's
  size and strength (D-318); the cage puts a box of points on, back or off (D-317); the bend chooses bend, twist, taper
  or bulge, its axis and amount, with a handle on the stage (D-316).
- **Shape of this object** (the object panel, one step deeper): width, height and depth typed or scrubbed (D-314); Smooth
  0–3 and *Make the smoothing real* (D-306); flat shading and the smooth angle (D-307); triangles; *Clean up the shape*
  with a face count (D-320, D-321); close holes; join close corners (D-310); linked copy and unlink (D-312); the pivot to
  the middle or the base (D-313).
- **Profiles** (D-311): a picked sketch region's chip sweeps it along a tapped curve, revolves it around a tapped line or
  its own side, or lofts it through more tapped regions.
- **Sketch rules** (D-315): tap a line (lock its size, its angle, level) or two (parallel, square, same size, twice that;
  a line and a circle: touching); a size on the stage has a lock; changing a size solves the rest.
- **The view cube** (D-322) in the view corner; Settings ▸ Stage hides it.
- **The bridge** (D-323): `model` and `profile` verbs.

### Draw again, and one grammar (0.15)

- **One Draw** (D-283): Model · Draw · Rig · Animate; Draw's bar is Brush · Smudge · Erase · Sheets · Colour and the brush
  in the hand decides what the Pencil makes. Painting brushes paint models (Sheets becomes Layers over a thing); Solids,
  Shapes and Shadow sit under the library's sets.
- **Zero setup** (D-284, D-285): over a thing a stroke lies on its surface; in the air on the sheet, which faces you. The
  sheet is paper while drawing, a trace between strokes; its hold menu places, shapes, guides, renames and deletes it.
  Drawings move with their sheet (`drawnOn`).
- **Accuracy** (D-286, D-287): one smoothing, the brush's; `DrawTests` fails past three points between a touch and its
  stroke's first point.
- **Shapes and strokes** (D-288, D-289): one drag per shape; a closed one pulls into a solid by its arrow; a tapped stroke
  has a chip and reshapes under the Pencil.
- **Frames** (D-290): flick right for the next drawing, left for the one before; onion skins on the timecode.
- **The grammar** (D-291 … D-298): hover lights what a tap lands on; every number is a slider; two fingers move the view,
  one finger carries the selection; the clusters rest while drawing; the lasso in the quick menu, the edit bar and the
  empty stage's menu; the quick menu changes with the tool; the eyedropper loupe; one toast system; four Pencil Pro clicks.
- **Titles and the ground** (D-295, D-299): 3D text sticks to the camera in place of + Overlay; to the ground by the real
  lowest point.

### Rig, and bring your sculpt (0.14)

- **Pins and dots** (D-260, D-266): Rig ▸ *Pins and dots*, or a body shortcut. The Pencil taps a dot on a joint or a pin
  where a soft thing holds and bends; a stroke along a part lays a chain; a mark dragged moves, held goes, double-tapped
  switches. A dot pulled with a finger brings its limb along; a pin bends only its stretch.
- **Body shortcuts** (D-264, D-265): Person (its dots guessed on the front view; drag the wrong ones, Rig), Chain, Four
  legs and Wings (guessed, or in the usual places).
- **Rigs change** (D-260): *Change the rig* relaxes the thing and shows its marks; poses and keys stay. Shapes too coarse
  to bend are cut finer (D-262). Groups rig rigid, a dot between two parts hinges them; *Rig these together* for several
  things (D-263).
- **Motion in the Library** (D-268): Motion and Rigs pages; poses, clips and loops saved from their menus and dropped with
  a tap. A row's grip repeats the motion by its end dot and loops it forever from its menu (D-269); keys have four feels
  (D-270).
- **Bring your sculpt** (D-271 … D-275): vertex colours in from glTF and OBJ as paint; heavy sculpts lightened on the way
  in to the tier's budget; Detail in the panel; Open in, the share sheet, a drop and Home's import land it on the stage
  with *Rig it*.
- **Game engines** (D-276, D-277): glTF carries skins and joint keys; FBX from our own writer; both checked in Godot and
  Blender on CI.

### Live performance (0.10)

Adobe Character Animator's killer features, on any character in the scene (CONTEXT §10.6).

- **Your face drives any puppet.** Cast ▸ Voice & face, *Front camera* or *My iPhone* (the companion screen: an
  iPhone with Face ID as the face camera, over the local network). Blobs and built Puppets answered already; now
  drawn rigs, "Rig as a person" rigs and rigged models turn their head with yours (a neck takes a third of it), and a
  skeleton that isn't a person's turns the bone Cast ▸ Life names as its head. A 2D drawn puppet tilts in its own
  plane (D-206).
- **Your hands move its hands.** The body tracker's wrists bring a humanoid's hands out and up by IK, elbows back;
  Blobs as before. Fingers aren't tracked (D-212).
- **Your voice shapes its mouth.** *Mouth from the microphone*: loudness opens the jaw, the sound picks the shape
  (open, "ee", "oo", a hiss), a few dozen times a second, with nothing recorded or sent. It's the shape of the sound;
  lip sync from the transcript is still the exact one (D-211).
- **Parts.** Select a loose object, Cast ▸ *Make it part of* a drawn rig: it rides the nearest bone. Give it a face
  role (eye, pupil, brow, mouth, jaw, or one mouth of a set) and it blinks, looks and talks with the face: this is how
  a drawn puppet gets a face, and how a prop sits in a hand (D-207).
- **Life.** *Breathes* (a slider) and *Blinks on its own*: both come from the time alone, so they're the same in every
  export (D-208).
- **Triggers.** One tap, or the keys 1…0: an expression, a saved pose, or a swap of what it holds. Performed while a
  take records (*Only while held*, or *Stay on when let go*); an edit at the playhead otherwise. The deck sits under
  the stage while the timeline is in Perform (D-209).
- **Draggers.** While a take records, drag a joint and it follows the finger; the take keeps it (D-210).
- **Dangle.** Cast ▸ Rig ▸ Pose: touch a joint, slide *Dangle*. That bone and everything below it hang loose: they
  trail when the character moves and swing when it stops, with your live head and hands too. No simulation: the same
  time always gives the same picture (D-204, D-205).
- **Takes and comping.** Every recording is kept as a take, above the lanes in Perform. The newest plays where it was
  performed; drag across any take to use it from there to there, one undo step. Rename, delete, use all of it or just
  the loop from its hold menu (D-202, D-203).

### The Schizzo board (0.9)

A place to think before building, in the project itself (CONTEXT §10.7).

- **Actions ▸ Board** covers the stage with the project's board: an endless sheet, dark by default (light by choice;
  dots, a grid or plain). It is laid out like the stage: back, Actions and Select top left; Draw, Erase, Note, Arrow
  and Frame top right; size, opacity, the colour in the hand and undo / redo on the sidebar (D-193).
- **Draw** with the brush engine: every brush of the library (built in, made, imported), pressure, tilt, coalesced
  and predicted Pencil samples. The stroke on screen while you draw is the stroke that is kept. Sizes are in the
  board's own units, so zooming in draws finer (D-195).
- **Erase** cuts strokes where it touches; the pieces stay strokes. It erases ink only.
- **Notes** are slips you type on (tap a picked note again to edit it; an empty one isn't kept). **Arrows** tie their
  ends to the note or picture they start or end on and follow it. **Frames** are named areas: moving, copying or
  deleting a frame takes what lies in it; a double-tap fills the view with the frame under the finger.
- **Pictures** come from Photos (Actions ▸ Add a picture), from the clipboard (Paste) or dropped from another app;
  they are kept in the board's own folder.
- **Select**: tap to pick, drag to move, the eight handles to size (corners keep the shape), a box from empty space
  to pick several. Touch and hold a thing for the hold menu; the bar under the board has Pin, Duplicate and Delete
  (D-197). Copy and paste work between boards.
- **Pin to the project**: the frame or the pick becomes a picture (on the board's paper, two pixels a unit) that
  floats over the stage as a **reference card**: drag it, size it from its corner. Its hold menu opens the board,
  **stands it in the scene** (a card object where you're looking, in every camera and export) or takes it off
  (D-194). Pinning with nothing picked pins the whole board.
- **Share a picture** of the frame, the pick or the whole board (PNG).
- **Moving around**: pinch to zoom (5 % to 3200 %), two fingers to pan (one, once a Pencil has touched), the zoom
  button to show everything. The board is kept in one cached layer, so it pans and zooms the same however much is
  on it (D-192).
- **Nothing is lost**: every change is one journal line within 50 ms, like the scene; undo survives closing the app.
- **Sketch** in New project opens the project on its board (D-199). **Settings ▸ Board** switches the board off
  (D-198).

### Fixes and touch (0.8)

What Hesham bumped into on the iPad, and touching things feeling the same everywhere.

- **Nothing is said on the stage under load** (D-176). The chip and its setting are gone. Near what the iPad keeps
  smooth, the preview's render scale drops a tier by itself and comes back after twenty calm seconds (longer if it
  doesn't hold). *Always full resolution* is the one thing that stops it. Diagnostics ▸ Smoothness has the numbers.
- **Panels sit above all chrome** (D-177): a panel opened from a cluster covers the sidebar, never the reverse.
- **A colour well on the sidebar** (D-178), under the two sliders, while Ink, a solid shape, Flipbook or Paint ▸ Colour
  is the tool: the Look's palette and any colour, the same chooser as Paint.
- **The sphere** (D-179): Model's second page is **Edit** (it was Shape, beside Add's Shapes), and the sphere's tile
  is a ball.
- **One hold menu everywhere** (D-180 to D-182): Duplicate · Rename · Copy · Paste, one to three extras, Delete in
  red; a row a thing can't do is dimmed. On objects (on the stage with a still finger, in the outliner, on their
  timeline row: Hide, Lock, Group, and Add to the selection when other things are selected), keys (easing, reverse,
  mirror), clips (split at the playhead, loop), flipbook drawings (hold longer or shorter) and tracks, cuts, screen
  effects, paint layers, brushes, Looks, library items, poses, palette colours, Home's cards and stacks.
- **Pencil or hand, automatic** (D-183): a finger makes with every making tool until an Apple Pencil has touched the
  stage; from then on the Pencil makes and fingers move the view. Settings ▸ Pencil or hand ▸ *Draw with a finger too*
  overrides it. A finger that may make still orbits where there is nothing to make on; two fingers pan and pinch.
- **The Motion row** (D-184), first thing in the inspector: Spin, Float, Bounce, Wiggle, Swing, Follow a path. One
  tap and the thing moves on the stage (they loop; several can run together), one Speed slider, and **Make keyframes**
  turns what's running into keys. The inspector can be **docked** at the side (Settings ▸ Stage, D-185).
- **Rigging, redone** (D-186, D-187). Cast ▸ Rig is three steps in order, **Bones → Skin → Pose**, each showing only
  its own tools; a step opens when the one before is done. A drawn bone takes its depth from the mesh for the whole
  stroke (it stays in the part in front, and runs straight on where the part goes into the body), puts joints where
  the stroke bends, and shows as bones inside the object while the Pencil is still down. Drawing along a chain again
  replaces it, and what hung from it hangs from the new one.

### Rigging (0.7)

- **One skeleton system** for every character (D-164): built Puppets (a joint per part), drawn rigs and imported
  Rigged models (`bone.<joint>` turns on the character), and the Blob (its mitten hands). Posing by dragging, IK, the
  pose library and clips all go through it.
- **Cast ▸ Rig ▸ Draw a bone** (how the chain is found changed in 0.8, above): a Pencil stroke through a limb, a tail
  or a rope on anything that has a surface
  (shapes, modelled parts, drawings, placed models) becomes a chain of bones down its middle; the first chain gets a
  root in the rest of the body, later ones hang from the bone they start on (D-165, D-166). The weights are worked
  out by **bone heat** (D-167): the surface bends smoothly across each joint and parts that only touch don't drag each
  other. Modelling the shape afterwards keeps the bones; **Fit the weights to the new shape** works them out again.
- **Paint weights** (optional): choose a bone and paint its weight with the brush (size and strength on the sidebar,
  Erase to take it away); the object shows that bone's weight in colour while you paint (D-172).
- **Rig as a person**: the stage turns to the model's front; tap the top of the head, the chin, a shoulder, an
  elbow, a wrist, a hip, a knee and an ankle (the other side is mirrored), drag any dot, then Rig. The joints sit in
  the middle of the limbs and follow the humanoid standard, so every built-in clip (Idle, Walk, Run, Talk, Wave, Point,
  Type, Nod, Shrug, Celebrate) and any humanoid clip from the library plays on it (D-168).
- **2D drawn puppets**: a drawing on a plane (ink or a solid stroke) takes bones drawn on its plane; its strokes bend
  with them, so the brush, picking and every export see the bent drawing (D-169).
- **Pose by dragging, IK by default**: select a character and drag any joint; the chain from its base follows
  (FABRIK), a humanoid's elbows bend back and its knees forward (D-170). In Keyframe mode the turns are keyed at the
  playhead like any property; **Reset the pose** puts every joint back. The pose library saves, applies and mirrors
  the poses of every character type.
- While the Rig tool is on, or a rigged object is being painted, the object stands as it was made (D-171).
- **Exports** carry the pose: glTF and the Blender package the pose as edited, USDZ, OBJ, STL and 3MF the pose at the
  playhead (print a posed character); painted rigged objects keep their paint on the bent surface (D-173).

### Painting on models (0.6)

- **Paint ▸ Colour** paints colour straight onto shapes, modelled parts, solid drawings and placed models with the
  brush engine: the brush the tool holds (the same library and Brush Studio), the current colour (the palette or any
  colour), size and opacity on the sidebar. Modes: Paint, Erase, Fill (the whole layer), Eyedropper (the painted colour
  under the touch). Fingers move around the scene; the Pencil paints.
- **Getting ready**: an object is laid flat for painting the first time (xatlas, D-154; "Paint <name>" or a first
  stroke on it). Placed models keep their own uvs when they're clean and keep their colours as a first layer, "Model"
  (D-155). Objects with drawn skeletons are painted as they were made; imported skinned characters aren't yet (D-171).
- **Strokes land where you see them**: each frame projects the stroke from the camera onto the texels the camera sees,
  through the frame's own ID buffer, so paint never goes behind something or round the back (D-152). The stroke under
  the Pencil is the stroke that's kept.
- **Layers** (up to 16 per object): show or hide, choose the one the Pencil paints on, opacity, blend (Normal,
  Multiply, Screen, Overlay, Add), add, duplicate, merge down, move, clear, rename, delete; remove all paint. Paint lies
  over the object's own colour (D-156).
- **Project a picture**: choose one from Photos or Files, place it over the model with your fingers, Project: it lands
  on what the camera sees, in the current layer (D-159).
- **Nothing is lost**: tiles are files named by their content and every stroke, fill, picture and layer change is one
  undo step (D-153). Modelling a painted object afterwards carries its paint onto the new shape (D-157).
- **Exports**: glTF, the Blender package, USDZ and OBJ carry the paint as a texture; STL and 3MF keep the closed shape
  (D-163).
- **Performance**: Diagnostics ▸ Run the painting benchmark paints a 50k-triangle model for 20 seconds (D-161).

### Brushes and drawing guides (0.5)

- **One brush engine** (D-139) draws ink in the scene, flipbooks over the shot and the stroke under the Pencil: a tip
  and a grain stamped along the stroke, with spacing, StreamLine, jitter, fall-off, tapers, pressure/tilt/speed
  dynamics, flow, wet edges and a soft edge. What's drawn while the Pencil moves is what's kept (UIKit's predicted
  touches draw ahead, the stroke's own seed keeps its jitter).
- **Brushes**: ten built-in brushes in three sets (Inking: Ink Pen, Technical Pen, Brush Pen, Marker; Sketching:
  Pencil, Charcoal; Painting: Dry Brush, Watercolour, Soft Airbrush, Splatter). Their tips and grains are drawn by code.
  Draw ▸ Ink and Draw ▸ Flipbook each hold a brush; the row at the top opens the library.
- **The brush library**: sets (make, rename, delete, share as a `.maquettebrushes` file), choose a brush, touch and hold
  for Brush Studio, duplicate, reset, rename, move to a set, delete. **Import** Procreate `.brushset` and `.brush` files
  and Photoshop `.abr` brushes (from the library, or Open in from Files and AirDrop); the mapping is D-141.
- **Brush Studio**: every setting on seven pages (Stroke, Shape, Grain, Dynamics, Pencil, Rendering, About), your own
  picture as a tip or grain, and a pad to try the brush as it changes.
- **Strokes keep their brush**: a project carries a frozen copy of each brush it used, so editing the library never
  redraws finished work and a project opens the same on another iPad (D-140).
- **Drawing guides** (D-149): over the frame for flipbooks a 2D grid, isometric, 1-, 2- and 3-point perspective, and
  symmetry (vertical, horizontal, quadrant, radial with mirror); on the guide plane for ink a grid, isometric and
  symmetry. Drawing Assist straightens strokes along the guide; symmetry mirrors them as you draw.
- **Latency**: Diagnostics ▸ Apple Pencil shows how long a Pencil sample takes to reach the screen (D-146).

### Nothing is ever lost (0.1)

Every change is a command; every command (and every undo and redo) is written to the scene's history journal within
50 ms, off the main thread. Every 200 changes, after 5 seconds of quiet, when the app leaves the screen and when a
scene closes, a checkpoint writes the scene, its undo history and the project files. Opening a scene reads the last
checkpoint and replays what came after it, so force-quitting mid-edit and reopening shows the last edit, and it can be
undone. Undo keeps 500 steps across relaunches.

**Actions ▸ History** opens the scrubber over the stage: drag back through every step and the stage shows that
moment. *Go back here* makes it the present (the state you left is kept as a version, and redo still goes forward
until you change something); *Name* keeps the moment as a named version; *Versions* lists named and automatic
versions (one each time a scene opens and after each hour of work) and restores any of them as one undo step.

### The Pencil (0.1)

With *Settings ▸ Pencil hover preview* on, a small point sits exactly under the hovering tip, for every tool, the same
size at every height, drawn by the stage in the frame it renders. Off, there is no mark at all. The brush's outline
shows only while its size slider moves.

### Every iPad (0.1)

All iPadOS 26 iPads. At launch Maquette reads the GPU family and memory: **Tier A** (M-chips) previews at full
quality; **Tier B** (recent A-chips) with a lighter render scale and shadows; **Tier C** (the oldest) lighter still.
Tiers never remove features, and exports always render at full quality. The stage's frame budget is the screen's own
refresh. Diagnostics shows the tier and runs the Night Market benchmark (and, on an M iPad, the same run with the
Tier B preview). When a scene nears what the iPad keeps smooth, **nothing is said on the stage** (0.8): the preview
lightens by itself, one tier at a time, and comes back after a calm stretch. Diagnostics ▸ Smoothness shows how full the
frame is and what the preview is doing. *Always full resolution* (Settings ▸ Stage) is the one thing that stops it.

### The canvas owns the screen (0.2)

The layout that freezes at 1.0; [LAYOUT.md](LAYOUT.md) maps every control to its one home and the UI tests walk it.
At rest the stage holds at least 85% of the screen.

- **Top left: the document and the app.** Home · Actions (export, the project file, the Monitor, scenes, history,
  scripts, the AI & laptop bridge, gestures, the tour, diagnostics, settings) · Look · Select.
- **Top right: making**, in the order a thing gets made. **Model**: shapes, lights, cameras, words, photos and videos,
  marks on the frame, effects and screen effects (Add); the Kit and your models (Library); snapping and the grid
  (Precision). **Draw**: ink, solid shapes, flipbooks. **Paint**: the Shadow Brush and Scatter. **Animate**: opens the
  whole timeline. **Cast**: characters, expressions, clips, lip sync, your face.
- **Time on call.** A new project shows no timeline. The control at the bottom right calls the slim transport (play,
  the time) and sends the timeline away; Animate opens the whole timeline. Its divider resizes it, and each project
  remembers whether it was hidden, slim or whole and how tall.
- **The inspector floats beside the selection**, on whichever side has room, flipping at the screen's edge and
  gliding over when the view settles. Move, turn and size are at its top; align and distribute appear when several
  things are selected.
- **Every panel resizes** from the grip in its corner (double-tap it for the original size) and remembers its size.
- **The joystick** shows under a selection by default; its × hides it, Settings ▸ Stage brings it back.
- **Home, the living gallery.** Each card is the project's model slowly turning in its own Look while the card is on
  screen (Reduce Motion keeps a still). Tap a card and it grows into the stage; Home in the corner shrinks it back.
  Drag a card onto another to stack them; search finds projects and stacks by name; sort by Recent, Name or Date
  created; Select acts on several (stack, move out, duplicate, archive, delete).
- **Starter templates** in New project: Blank, Model to print (millimetres, a 1 cm grid, 5 cm shapes, close up,
  Clay), Room or building (metres, a 25 cm grid, the view from above), Character (Cast open, eye level), Animation
  (the timeline open), Sketch (the Schizzo board first, since 0.9). Each suggests a Look and a Mood, both
  changeable there and later. The print-bed outline and the walls tool arrived with M4.
- **Keyboard**: ⌘1–⌘5 Model, Draw, Paint, Animate, Cast; ⌘6–⌘8 Actions, Look, Select; ⌘L the library; ⌥⌘1–3 move,
  turn, size; ⌘T the timeline.
- Diagnostics also runs the **Home benchmark**: a hundred projects turning while the gallery scrolls for 20 seconds.

### Modelling I (0.3)

Shapr3D's core loop, in **Model ▸ Edit**. Choosing a sketch shape or a pick mode closes the panel and puts the Model
tool's bar at the bottom of the stage (pick modes, sketch shapes, Done, grow / shrink / select similar, ✕).

- **Sketch on any surface.** The first tap lands on the face under it (or the ground) and the shape lies on that
  plane: **line** (tap the corners, tap the first to close), **rectangle** (two corners), **circle** (centre, edge),
  **arc** (start, end, bend), **spline** (tap through it; tap the start to close, or Done), **offset** (tap a curve,
  type the distance). Points snap to corners already drawn, else to the grid. Closed shapes fill into regions; a
  shape inside another makes a hole and is a region of its own. Sketches are construction lines: the stage shows them,
  renders and exports never do.
- **Pull a region into a solid, or cut it into the face below.** Tap a region and drag it, or tap its number and type:
  up makes a solid (or adds to the object it was drawn on), down cuts into that object. The region's lines are used
  up.
- **Pick faces, edges or corners**: tap one, touch and hold to add or remove, draw a loop with the Pencil around
  several; grow, shrink and select similar from the bar. Picks are highlighted in amber on the stage, with the
  object's edges drawn over it.
- **Push/pull a face** with its live distance floating beside it; snapping to other corners' heights and to the unit
  while dragging; tap the number to type an exact one. A face whose neighbours stand square to it slides (the number
  is the new size exactly); any other face adds or cuts a prism.
- **Exact lengths everywhere**: every number on the stage takes `25`, `25mm`, `2*12`, `1ft 6in`, `(40-6)/2`, in the
  project's units (Model ▸ Precision: mm, cm, m, in, ft).
- **Booleans**: union, subtract and intersect two or more selected shapes into the first one; results are clean
  (coplanar faces merged, welded) closed solids. Any shape (a cube, a drawn solid) becomes an editable mesh on the way,
  or with Make editable.
- **The inspector shows sizes**: the selection's width × height × depth in the project's units, and what's picked
  ("Face · 800 mm²", "2 edges · 80 mm").

### Modelling II and interop (0.4)

- **Shape operations on the pick**, from the Model tool's bar: **Bevel** and **Round** the picked edges (outside edges
  are cut, inside edges filled; where several meet the cuts meet in a point), **Inset** the picked faces (a ring
  around each, the middle stays picked to push or pull), **Shell** the solid (walls of an exact thickness; picked faces
  are left open). Each runs at once at a size that suits the units (1 mm in a print project, 5 cm in a room); its size
  then floats beside it, and typing a new one does it again from the same pick.
- **Mirror** (Model ▸ Edit): a mirror image across the picked face (it joins into one solid when it touches) or across
  the world's middle (a twin on the other side). **Symmetry**: left and right, front and back, or top and bottom, per
  object; switching it on moves the pivot to the middle on that axis and makes the shape symmetric; every Model edit
  afterwards keeps the side it touched and the other side follows (a push/pull shows both faces moving).
- **Array along a path**: the inspector's array follows a sketch's curve (copies spread evenly, optionally turning
  with it).
- **Precision** (Model ▸ Precision, was Snapping): points snap to corners, the middles of edges, edges and faces near
  the finger or Pencil (12 points on screen), then to the grid; the stage marks what a point snapped to. Sketching,
  measuring, walls and floors all snap this way. Grid sizes follow the units.
- **Measure**: two taps give the distance and how far apart along x, y and z; tap the number (or Keep) to leave it on
  the stage as a **dimension** that moves with the object it measures. Kept dimensions show whatever the tool (Show
  kept dimensions); tap one to select it. Like sketches, they're never rendered or exported.
- **Section view**: cut the stage across x, y or z through the middle of the selection, or along the picked face;
  slide where it cuts, keep the other side. Cut solids show their inside flat in their own colour. Exports are never
  cut.
- **3D printing** (Model ▸ Edit ▸ 3D print): pick the printer (its build volume is outlined on the stage; Model to
  print starts with a 220 mm one), **Check for printing** (holes, tangled edges, inside-out faces, walls thinner than
  the printer prints, fitting the bed, the thinnest wall) and **Repair** (joins, turns and closes what it can). STL and
  3MF exports are millimetres with Z up, so parts stand on the bed in a slicer.
- **Building** (Model ▸ Add): **Walls** along tapped corners (2.7 m high, 20 cm thick, both typed beside the walls
  being drawn; tap the first corner to close a room), **Floor** under tapped corners, **Door** and **Window** cut where
  a wall's side is tapped (90 × 210 cm; 120 × 120 cm at 90 cm), **Stairs** climbing away from you in 17.5 cm steps.
  Each is an editable mesh like everything else.
- **Interop.** Import (Model ▸ Library): USDZ, glTF, GLB, OBJ, STL, 3MF; **Make editable** takes a placed model apart
  into editable objects, keeping a glTF's hierarchy, materials, cameras, lights and animation. Export (Actions ▸ Export
  ▸ 3D model): **glTF** (the scene as built: hierarchy, materials, cameras, lights, the timeline's moves), **USDZ**,
  **OBJ** with its MTL, **STL**, **3MF**, and **Blender**: a folder with the scene, the Look, the sun, the sky, the
  ground, the camera cuts and render settings, and `setup_maquette.py`, which builds a ready-to-render .blend (Blender
  4.2 or newer). Kept dimensions, sketches, marks on the frame and effects stay in Maquette.

---

# 3D-lowey 2.0 — what Maquette starts from

**Procreate Dreams, in 3D, cel-shaded.** An iPad app where someone who isn't a 3D artist directs good-looking,
hand-drawn-feeling 3D animation (sets, characters, cameras, voice) and exports it as video. The measure of success
is the time from an idea to an animated shot on screen.

2.0 shipped in two steps: **2.0 beta** rebuilt the engine, the Look system and the layout and carried every 1.x
feature over; **2.0** added the drawing and animation tools, the Kit, one Cast system, perception and MCP v2, three
languages and App Store readiness. What happened to each 1.x feature is in [MIGRATION.md](MIGRATION.md); why things
are the way they are is in [DECISIONS.md](DECISIONS.md); what's next is in [BACKLOG.md](BACKLOG.md).

## 1. What changes from 1.x

| 1.x | 2.0 | Why |
|---|---|---|
| The identity was "low-poly": untextured primitives, fog and bloom doing the work, so renders read as greybox. | Cel shading with lines (the **Ink** Look) is the default; low-poly is one Look of five. | Flat colour bands and ink lines make a cube look drawn instead of unfinished. |
| RealityKit renderer. | **LoweyRender 2**, a Metal renderer of our own. | RealityKit gives no per-fragment access to lights (no real toon lighting with cast shadows) and no normals or object IDs after rendering (no good lines). Owning the renderer also makes the preview and the export the same picture. |
| Five mode tabs, a game-style HUD, the joystick always on. | Procreate-style layout: Stage and Timeline, two corner clusters, a slider sidebar, universal gestures. The joystick is optional. | Modes hide tools behind tabs; everything should be one tap from the canvas. |
| The bridge was on by default with a permanent code, and the laptop tool could open it to the internet. | Off until turned on; a one-time code per laptop, tokens in the Keychain; local network only. | A creative tool shouldn't be an open door on café Wi-Fi. |
| Releases were published before CI finished. | Releases are built only from commits CI passed. | |

**Style references:** *Spider-Man: Into / Across the Spider-Verse*, *Paperman*, *Arcane*, *Puss in Boots: The Last
Wish*, *The Mitchells vs. the Machines*, *Klaus*, *TMNT: Mutant Mayhem*, and the games *Sable* and *Borderlands* —
the western comic and hand-drawn lineage. No anime conventions (eyes, faces, speed-line framing).

Pixar's warmth (shape language, appeal, bounce light, colour scripts) is in reach and lives in the Clay Look; its
offline path tracing isn't, and chasing it would make everything slower and uglier.

## 2. Looks

A **Look** is data (`LookPreset` JSON): shading, lines, finish and a default frame rate. Five are built in; any can be
duplicated and changed ("My Look"); a scene can override the project's Look, and an object can override its scene's.

- **Ink** (default) — cel shading that holds up close: smoothed shading normals so faceted shapes shade as smooth
  forms; two or three bands with adjustable edge softness; sun shadows inside the same bands; shadow colours shifted
  toward the sky hue rather than darkened; hemisphere ambient for bounce light; contact shading inside the shadow
  band; a rim light; optional hard specular shapes for glossy materials; restrained bloom on emissive surfaces.
  Lines from the object-ID, normal and depth buffers, scaled with distance and per object, in a darkened object
  colour by default.
- **Comic** — Ink plus halftone dots in the shadow band, colour misregistration instead of depth-of-field blur,
  heavier lines, a print finish, animated on twos by default.
- **Sketch** — desaturated Ink with pencil lines and paper grain; objects flagged **Accent** keep their colour (one
  per shot is the intent; the inspector warns when there are more).
- **Clay** — the soft 1.x look (rough materials, sky light, fog, bloom) with soft shadows, no lines. 1.x projects
  open in Clay.
- **Low-poly** — flat per-triangle normals, Ink bands or Clay lighting, optional lines.

The six **moods** (Day, Golden hour, Dusk, Night, Space, Studio) set sun, sky, ambient, fog and stars and combine with
any Look. The **palette** (linked slots, eyedropper) is shared by both. **Finish** (Clean, Cinematic, Dreamy, Retro,
Comic, Collage, Old film, plus sliders) and **Finish ▸ Outline** work over every Look.

## 3. Renderer

- Per frame: sun shadow map (two cascades fitted to the shot) → prepass (depth, normal, object ID) → Look shading
  (4× MSAA) → contact shading → lines → post (halftone, misregistration, bloom, grade, grain, transitions, screen
  effects) → overlays and captions → the screen or the encoder.
- **One renderer** for the stage, snapshots, thumbnails and export. Export renders offscreen into IOSurface-backed
  pixel buffers for the video encoder. Tests compare the stage's frame with the exported frame.
- **Dynamic render scale** (0.66–1.0) with MetalFX upscaling when the frame budget is at risk or the device is hot;
  lines and overlays stay at native resolution. Exports always render at full scale.
- **Picking** reads the ID buffer (exact, even on thin objects). Gizmos, guides and the selection outline are drawn
  by the same renderer.
- GPU skinning for imported rigs; instanced draws for repeats; reverse-Z depth; up to 16 point and spot lights, with
  shadows from the sun only.
- The ARKit virtual camera feeds its pose to the renderer like any camera.

## 4. Building

- **Primitives** (cube, sphere, cylinder, cone, plane, torus, ramp) with a small **bevel** by default, pivoted at the
  centre of their base.
- **Ink strokes**: Pencil strokes in 3D on the guides, drawn with a brush (0.5: stamps turned to the camera); select
  (tap or loop), move, erase, smooth and change width; strokes are objects, animatable and able to write themselves on.
- **Solid shapes**: tube, ribbon, extrude, lathe on guides (facing me, ground, front, side, box, cylinder, sphere, on
  an object), mirror, Pencil-only, QuickShape.
- **The Kit**: about 350 CC0 models (Kenney, Quaternius) in nine Sets, at real size, with the surfaces things stand on
  and the way they face; the Library opens on them (`Tools/fetch-kit.py` builds it, licences checked per pack).
- **Shadow Brush**: paint where shadows fall on any surface with the Pencil (push the shadow in, pull it out).
- Array, scatter, group / ungroup, align / distribute, swap a blockout for a model, save to the library, linked
  prefabs.
- Import USDZ, glTF / GLB, OBJ and folders, from the share sheet, drag and drop, or the laptop.

## 5. Characters

One **Cast** panel and one set of verbs for every kind of character:

- **Blob** (the house character, from a traced drawing; its measurements are generated from it): hats, hair,
  accessories, props, marks, a likeness table for famous people, 12 expressions, springs, squash and stretch, a stable
  inverted-hull outline, flat face decals, Shadow Brush presets.
- **Puppet**: a humanoid of rigid parts with a builder.
- **Rigged**: imported glTF skins with rig classification, retargeting, IK and a clip mixer.
- Built-in clips on all three: Idle, Walk, Run, Talk, Wave, Point, Type, Nod, Shrug, Celebrate. A pose library with
  mirror; IK handles (two-bone limbs, blob hands). Maquette 0.7 puts all of them, and drawn rigs, on one skeleton
  system (Rigging, above).
- Lip sync from word timings (English dictionary plus rules, Arabic, Italian), face capture with the front camera or
  an iPhone companion, rest pose, hands through body tracking. Maquette 0.10 puts the face, the voice and the hands on
  every character, with triggers, draggers, dangle and takes (Live performance, above).

## 6. Animation

Three timeline modes, named as in Procreate Dreams: **Compose** (move animation in time without breaking keys),
**Perform** (record direct manipulation as keys, with filtering and Pencil roll), **Keyframe** (explicit keys, easing,
the curve editor, auto-key). Also: 15 presets with order, delay and randomness; behaviours (follow a path, look at,
orbit, wobble, wind sway, float, spin; bake to keys); fall, explode, flock; JavaScript scripts; markers; loops;
copy / paste / mirror / reverse / faster / slower; track groups; per-object frame rate (ones to fours, keyable);
motion paths with draggable key dots; 3D onion skin; a graph editor; smears on fast moves; multi-select of clips with
the Pencil lasso.

**Flipbooks**: frame-by-frame drawing with a brush over the shot, anchored to the camera or an object, with onion skin, holds,
blend modes (normal, multiply, screen, add) and several tracks; drawn FX (speed lines, impact burst, sweat drop,
sparkle, smear) placed on a word.

## 7. Camera

Camera objects, shots and cuts on the Camera lane, 11 moves, lens (focal length, focus, aperture), transitions,
match cut, 9:16 framing, the iPad as a camera (ARKit), camera Perform.

- **Director view**: look through the shot camera with framing guides (thirds, safe areas, the delivery shape); drag
  to aim, two fingers to move, pinch to dolly, twist to roll — all keyed.
- **Frame shot**: pick a subject, a shot type (extreme wide … extreme close-up, insert, over-the-shoulder, two-shot),
  a composition (thirds, centre, low or high angle) and a side; the camera is placed and aimed.
- **Fly**: fly the camera with on-screen sticks or a game controller, eased, and record the flight in Perform.

## 8. Voice and sound

Record a voiceover over the animation, import audio, transcription on the device (Apple's SpeechAnalyzer through
hmm-kit), the Words lane with snapping, the Transcript sheet (jump, pick a phrase → animate, camera move, cut,
marker; fix words), a placeholder voice, lip sync. Attaching things to a spoken word is a first-class action. A
sound-effects track with a synthesised CC0 foley set (whoosh, pop, impact, click, swell) whose hits land on words.

## 9. Layout (2.0; Maquette 0.2's layout above replaces it)

- **Theater** (home): project cards with looping previews; New project asks for a name, a Mood and a Look; samples;
  a card menu to share a `.loweypack`, duplicate, archive.
- **Stage** over **Timeline**, with a resizable divider; the timeline collapses to a transport bar.
- **Top-left cluster**: Theater · Actions (photos and video, sound, voiceover, export, the project file, scripts, the AI & laptop bridge, gestures, the tour, diagnostics, settings) · Look ·
  Select (tap, lasso, select similar).
- **Top-right cluster**: Build · Draw (ink, solid shapes, flipbooks, Shadow Brush) · Transform · Cast · Library.
- **Sidebar**: two sliders that follow the context (drawing, Shadow Brush, Perform, otherwise snapping and navigation
  speed), Pick, undo, redo; it can sit on either side.
- **Inspector**: slides in from the right while something is selected.
- **Gestures**: two-finger tap undo, three-finger tap redo, four-finger tap hides everything but the stage; one finger
  orbits, two fingers pan and zoom, double-tap frames the selection, two fingers on the selection twist and pinch it;
  Pencil hover previews, Pencil Pro squeeze plays and pauses, barrel roll during Perform.
- **Keyboard**: ⌘1–5 open Select, Build, Draw, Transform and Look; a full menu bar.
- Amber accent `#FFB847`; dark by default, light supported.
- **Languages**: English, Italian, Arabic (right to left; the timeline keeps time left to right).
- **Accessibility**: VoiceOver on every control, Dynamic Type in the chrome (panels scroll), Reduce Motion, Reduce
  Transparency and Increase Contrast.
- **Windows**: one window edits; a **Monitor** window shows the shot live as it exports (Stage Manager, external
  displays). The app reopens the project, scene, playhead and panel it was left in.

## 10. Documents and export

- A project is a folder package (`.maquette`; 2.0's `.lowey` opens too) of JSON scenes, assets, audio, renders and a
  thumbnail, with atomic saves and a backup of the last good version. Since Maquette 0.1 every change is in the
  scene's history journal the moment it happens (above, and [PROJECT_FORMAT.md](PROJECT_FORMAT.md)); the 2.0 autosave
  delay is gone. 1.x projects open and migrate. `.maquettepack` (and 2.0's `.loweypack`) shares a project with its
  assets.
  iCloud Drive in the App Store build; on the device otherwise.
- Export presets: YouTube 16:9 4K, 1080p, Shorts / Reels 9:16, Square, Transparent (HEVC alpha), PNG still (HD / 4K),
  GIF loop, 3D model (glTF, USDZ, OBJ, STL, 3MF, Blender; Maquette 0.4), Captions (.srt); custom size, frame rate
  (24 / 25 / 30 / 60), codec and quality.
- Every export is verified (length, frame count, size, audio, alpha) before it's offered. Exports keep running in the
  background, with a Live Activity where the system shows one and a notification when they finish.

## 11. Performance

- **Night Market** benchmark (Diagnostics): about 400 objects, six skinned walkers and four blob characters
  animating, sun shadows and three point lights, the Ink Look with lines and contact shading, a camera move. Pass on a
  device (since 0.1): no dropped frames for 95% of 20 seconds (p95 within 1.2 refreshes of the screen: 10 ms at
  120 Hz, 20 ms at 60 Hz) at a render scale near the top of the device tier's range (0.85 at Tier A), no hitch over
  33 ms. On an M iPad it also runs with the Tier B preview. It writes a JSON report.
- Launch to the Theater in under a second; a project's first frame in under 500 ms.
- **The feel recorder** (Diagnostics ▸ Feel ▸ Record a minute, 0.10.1): a minute of real use, every touch timed to
  the refresh that shows its answer and split into input, main thread, encode and GPU; a small red dot at the top
  while it listens. The JSON lands beside the benchmark reports; `Tools/feel_report.py` ranks the slowest moments
  against the gates: every touch answered within one frame, a panel in under 0.1 s, a project's first frame in under
  0.5 s, no dropped frames (D-217).
- A 60-second 1080p Ink export in 90 seconds or less on the reference device.

## 12. AI and the laptop

- **hmm-bridge** on the laptop: the `lowey` MCP server with sixteen intent tools (status, read_project, find_assets,
  build, frame_shot, light, set_look, animate, camera_move, add_overlay, flipbook, add_media, render_manim, observe,
  contact_sheet, commit) and a CLI for pairing, files, renders, media and Manim. The bridge is off until it's turned
  on, local-network only, paired with one-time codes; App Store builds ship without it until 2.1.
- **Scene Script v3**: relations instead of coordinates (on, beside, in front of, behind, above, under, inside,
  facing, around, row, grid, scatter, stack), real sizes, palette slots, the camera solver, six lighting recipes,
  animation by intent. The solver grounds what it places and keeps things apart. One script = one Proposal (with a
  preview picture) = one undo step. Schema: `schemas/scene-script.v3.schema.json`.
- **Perception**: `observe` returns the shot with set-of-marks, top / front / side diagrams, a value view and the
  subject's silhouette, plus a ShotReport (per object: coverage, visibility, grounding, intersections, frame cuts,
  facing; per frame: subject on the thirds, headroom, contrast, clutter, tangents, palette, light) graded against the
  critique rubric. `contact_sheet` returns frames with notes and motion stats (arcs, holds, speed, words).
- **The `lowey` skill**: a director loop (plan → build → observe → critique → fix), modules, style notes, a generated
  tool reference, lessons, and twelve eval briefs scored from the app's measurements.

## Device-only checks

Some things can only be checked on an iPad: the Night Market benchmark numbers · Pencil pressure on strokes and the
Shadow Brush · Pencil Pro squeeze and roll · face capture (front camera) and the iPhone companion · the ARKit virtual
camera · SpeechAnalyzer on a real voiceover (English, Italian, Arabic) · thermal behaviour during a 5-minute 4K
export · iCloud sync between iPad and iPhone · pairing the bridge from a laptop · drawing a path with the Pencil and
its timing · a Final export and ProRes 4444 on the iPad · an export carrying on in the background.
