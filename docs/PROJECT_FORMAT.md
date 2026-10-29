# Project format

A Maquette project is a folder package (it shows as one file in the Files app). This document is the public
surface of that package: power users, scripts and MCP clients may **read** any of it. **Writes go through the app**
(the laptop bridge), so undo and the history journal stay true; a file changed behind the app's back is overwritten at
the next checkpoint.

Format version: package **2**, document schema **26** (`LoweySchema.currentVersion`), journal **1**.

```
My film.maquette/                 (3D-lowey's .lowey packages open too, and are upgraded in place)
  manifest.json                   which app wrote it, what it is, its package version
  project.json                    the project: name, scene list, the project Look
  scenes/<scene-id>.json          one scene each: objects, hierarchy, camera, timeline
  history/<scene-id>/             that scene's history journal (below)
  assets/                         library models the project carries (written by "Share as one file"), media,
                                  brushes/<hash>.png: the pictures of the brushes its strokes use, and
                                  paint/<hash>.png, paint/<hash>.uv: painted objects' tiles and unwraps,
                                  rigs/<hash>.skin: rigged objects' weights,
                                  references/<hash>.png: pictures pinned from the board
  audio/                          voiceovers and sounds
  renders/                        exports kept with the project
  thumbnail.png, thumbnail-loop.gif   the Home card (a still, and the model turning once in its Look)
  workspace.json                  how the project shows: the timeline, snapping, the grid, the section view, pinned
                                  reference cards (not part of undo)
  board/                          the Schizzo board, once it has been opened (below)
```

Beside the packages, the projects folder holds `gallery.json`: Home's stacks and sort order (below).

Every JSON file is written atomically and keeps the previous good version beside it as `<name>.bak`; a damaged file
is read from its backup.

## manifest.json

```json
{"schemaVersion": 2, "app": "lowey", "kind": "project", "created": 781203000.0, "modified": 781203600.0}
```

Dates in every file are seconds since 2001-01-01 UTC (`timeIntervalSinceReferenceDate`). `app` stays `"lowey"` so
3D-lowey 2.0 and Maquette read each other's manifests.

## Versioned files

`project.json`, `scenes/*.json` and the journal's snapshots are envelopes:

```json
{"schemaVersion": 5, "kind": "project", "payload": { … }}
```

An older `schemaVersion` is migrated when read (every migration since 1.x is in `LoweySchema.migrations`); a newer one
is refused with a sentence asking to update the app. Keys are stable: a key is only ever added, and a removed or
renamed one gets a migration.

## project.json (`kind: "project"`)

| Key | Type | Meaning |
|---|---|---|
| `id` | string | The project's id. |
| `name` | string | Its name on the Home screen. |
| `created`, `modified` | number | Dates (see above). `modified` decides which of `project.json` and a scene's journal is newer for project-wide settings. |
| `look` | object | The project Look (every scene without its own uses it): `presetID` (`ink`, `comic`, `sketch`, `clay`, `lowPoly`), mood (`lightingPreset`: `day`, `goldenHour`, `dusk`, `night`, `space`, `studio`, and since schema 12 `darkStudio`), palette, sky, fog, ground, shading, post. |
| `sceneOrder` | [string] | Scene ids in order. |
| `sceneNames` | {id: string} | Scene names by id. |
| `lastOpenedScene` | string? | Where the project reopens. |
| `looks` | [object]? | The project's own Looks ("My Look"); absent when there are none. |
| `brushes` | {key: object}? | Since schema 7: a frozen copy of every brush a stroke uses, by its content key (`b-<hash>`); absent when there are none. See "Brushes" below. |

## scenes/<scene-id>.json (`kind: "scene"`)

| Key | Type | Meaning |
|---|---|---|
| `id`, `name` | string | |
| `objects` | {id: object} | Every object by id: `id`, `name`, `kind` (what it is: primitive, model, light, camera, text, drawing, mesh, sketch, character…; see below), `parent`, `children`, `properties` (typed values: `position`, `rotation`, `scale`, `color`, `visible`, …), `shadowPaint` when the Shadow Brush painted it, `paint` when colour is painted on it (schema 8, below), and `rig` when it has a drawn skeleton (schema 9, below). |
| `roots` | [string] | Top-level objects in outliner order. |
| `look` | object? | The scene's own Look (absent: the project's). |
| `activeCamera` | string? | The shot camera. |
| `viewpoint` | object | The work view's orbit camera. |
| `timeline` | object | fps, duration, tracks of keys, clips, markers, cuts, words and audio, effects, captions. |

The Scene Script schema (`schemas/scene-script.v3.schema.json`) documents the commands that change these files.

## The history journal: history/<scene-id>/

Every change to a scene is recorded moments after it happens, so a killed app loses nothing and undo survives a
relaunch. Opening a scene reads its latest checkpoint and replays the changes after it.

```
history/<scene-id>/
  checkpoint.json      the latest checkpoint (checkpoint.json.bak: the one before)
  snapshots/<n>.json   the scene and project at checkpoint n (a versioned file, kind "document")
  segments/<n>.jsonl   every change since checkpoint n, one JSON line each
  entries/<n>.jsonl    undo steps first stored by checkpoint n
  base.json            the scene when its journal began (where a time-lapse starts)
  versions/            named and automatic versions
```

### Segments

The first line is a header; every other line is one change, numbered across segments:

```json
{"journal":1,"schema":4,"segment":3}
{"op":{"command":{"op":"setProperties","changes":[…]},"key":"drag-…","op":"perform"},"seq":401,"t":781203612.4}
{"op":{"op":"endCoalescing"},"seq":402,"t":781203612.9}
{"op":{"op":"undo"},"seq":403,"t":781203614.0}
```

`op` is one of `perform` (a command, as in a Scene Script, with the gesture's coalescing `key`), `endCoalescing`,
`beginGroup` (`label`), `endGroup`, `cancelGroup`, `undo`, `redo`. Replaying them in order on the snapshot they
follow rebuilds the scene and its undo history exactly. A line cut short by a killed app is skipped. Segments are
never deleted: together they are the whole making-of. `schema` is the document schema the commands were written in;
older ones are migrated line by line (`ProjectHistory.opMigrations`).

### Checkpoints

Every 200 changes, after 5 seconds without one, when the app leaves the screen and when a scene closes:

```json
{"format":1,"seq":400,"segment":3,"saved":781203610.0,
 "undo":[{"id":"…","file":2,"offset":18233,"length":412,"label":"Move Lamp"}, …],
 "redo":[…]}
```

`undo` and `redo` point at steps in `entries/<file>.jsonl` (`offset` and `length` in bytes): each step is stored once,
and opening reads only the newest 64; older ones are read when undo reaches them. A checkpoint also rewrites
`project.json` and the scene file from the same state.

### Versions

`versions/index.json` lists them (`id`, `name`, `date`, `automatic`); `versions/<id>.json` holds each as a snapshot.
Maquette keeps one automatically each time a scene opens and after each hour of work (the newest 40), and whenever
the history scrubber goes back (the state it left). Named versions stay until deleted.

### Meshes and sketches (schema 5)

A modelled object is `{"type": "mesh", "mesh": {"v": [x, y, z, …], "f": [[[0, 1, 2, 3]], …]}}`: `v` is every vertex as
three numbers in a row, in the object's own space (metres, to the nanometre); `f` is every face as a list of loops of
vertex indices, the outline first (counter-clockwise seen from outside) and then its holes (clockwise). A closed,
outward-facing mesh is a solid.

A sketch is `{"type": "sketch", "sketch": {"plane": {"origin", "normal", "u", "v"}, "curves": […], "target": "<id>"?}}`:
the plane in world space (`u` and `v` are its in-plane axes; curve points are `[u, v]` metres along them), and the
object it was drawn on, if any. Each curve is one of `{"line": {"_0": p, "_1": p}}`, `{"rectangle": {"_0": p, "_1": p}}`
(opposite corners), `{"circle": {"center": p, "radius": r}}`, `{"arc": {"_0": start, "_1": through, "_2": end}}`,
`{"spline": {"_0": [p, …], "closed": bool}}`, `{"polyline": {"_0": [p, …], "closed": bool}}`. Sketches are construction
lines: renders and exports leave them out.

Schema 5 only added these two kinds; files from schema 4 open unchanged. Apps that read schema 4 refuse schema 5
files with a message saying the project needs a newer Maquette.

### Dimensions and symmetry (schema 6)

A kept dimension is `{"type": "dimension", "dimension": {"start": [x, y, z], "end": [x, y, z]}}`: its two ends in the
object's own space (it sits under the object it measured, so it moves with it). Like sketches, it's drawn on the stage
only: renders and exports leave it out.

A modelled object with live symmetry has the property `symmetry`: `{"enum": "x"}` (or `y`, `z`), the plane through its
pivot square to that axis. Model edits keep the side they touched and make the other side its mirror image; the mesh
stored is always the whole, symmetric shape.

Schema 6 only added the kind and the property; files from schema 5 open unchanged, and Maquette 0.3 refuses schema 6.

### Brushes (schema 7)

A brush (`project.json` › `brushes` › `b-<hash>`) is `{"id", "name", "shape", "grain", "stroke", "dynamics", "rendering",
"about"}`:

- `shape`: `source` (a built-in tip: `hardRound`, `softRound`, `pencilTip`, `chalkTip`, `bristleTip`, `flatTip`,
  `splatterTip`, or a picture key `brushes/<hash>.png` under `assets/`), `roundness`, `angle` (degrees),
  `followsStroke`, `rotationJitter`, `flipXJitter`, `flipYJitter`, `count`, `inverted`.
- `grain`: `source` (absent for none; `paper`, `canvas`, `noise`, `charcoal` or a picture key), `scale`, `depth`,
  `movement` (`rolling` or `texturized`), `inverted`.
- `stroke`: `spacing` (tip diameters), `streamline`, `jitter`, `falloff`, `taperStart`, `taperEnd`, `taperSize`,
  `taperOpacity`.
- `dynamics`: `pressureSize`, `pressureOpacity`, `pressureCurve` (`{"points": [{"x", "y"}…]}`), `tiltSize`,
  `tiltOpacity`, `speedSize`, `speedOpacity`, `sizeJitter`, `opacityJitter`, `minimumSize`, `minimumOpacity`.
- `rendering`: `flow`, `wetEdges`, `softness`. `about`: `origin` (`builtIn`, `made`, `procreate`, `photoshop`,
  `shared`), `author`, `resetsTo`.

The key is a hash of the settings, so the same brush is stored once however many strokes use it, and a brush edited in
the library is a new key. Pictures are grey PNGs (white paints).

An ink stroke (`drawing` › `strokes[]`) and a flipbook stroke (`timeline.flipbooks[]` › `frames[]` › `strokes[]`) may
carry `alphas` (each point's opacity, from the brush's dynamics), `brush` (a key in `brushes`) and `seed` (the jitter's
seed, so the stroke draws the same every time). A stroke without `brush` draws with Ink Pen, as 2.0's did. Points and
widths are the smoothed path the brush stamps along (widths are radii).

Schema 7 only added optional keys and the `setBrushes` journal command; files from schema 6 open unchanged, and
Maquette 0.4 refuses schema 7.

### Paint (schema 8)

Colour painted on an object is its `paint`: a surface and layers, bottom first.

```json
"paint": {
  "surface": {"size": 2048, "unwrap": "paint/1f3a…c2.uv", "mesh": "9b0e…41"},
  "layers": [
    {"id": "l1", "name": "Layer 1", "opacity": 1, "blend": "normal", "visible": true,
     "tiles": {"3,1": "paint/77ac…08.png", "4,1": "paint/e2d1…9f.png"}}
  ]
}
```

- `surface.size`: pixels a side of every layer, a multiple of 256 (2048 for new paint).
- `surface.unwrap`: where every corner of the mesh lies on the texture (below).
- `surface.mesh`: the fingerprint (FNV-1a, 16 hex digits) of the mesh the unwrap was made for: the triangles the app
  draws for the object, in its own space. When the object's shape changes (modelling, a bevel), the fingerprint no
  longer matches and the app carries the paint onto the new shape by position, without changing the file; the next
  stroke stores the carried paint.
- `layers[]`: `id`, `name`, `opacity` (0–1), `blend` (`normal`, `multiply`, `screen`, `overlay`, `add`: the W3C
  compositing formulas on the stored sRGB values), `visible`, and `tiles`: `"column,row"` (from the top left, 256
  pixels each) to a PNG under `assets/`. A missing tile is transparent. Tiles are RGBA, straight alpha, sRGB.

Every file is named by a hash of its bytes, so the same pixels are stored once and a stroke only adds the tiles it
changed. Files stay as long as the history may need them (undo puts old names back).

The `.uv` file is little-endian binary: `MQUV`, version (1), vertex count, index count (u32 each); then per vertex the
mesh vertex it came from (u32), its position in the object's space (3 × f32) and its uv (2 × f32, 0–1, v down); then the
triangles (u32 indices; triangle *t* is the mesh's triangle *t*). Placed models' surfaces are their parts as one mesh.

Two journal commands change paint: `setPaint` (`{"op": "setPaint", "id", "paint"}`, the whole paint or none) and
`paintTiles` (`{"op": "paintTiles", "id", "tiles": [{"layer", "tile", "file"}]}`, a stroke, a fill or a projected
picture; a missing `file` clears the tile).

Schema 8 only added the optional key and the two commands; files from schema 7 open unchanged, and Maquette 0.5
refuses schema 8.

### Rigs (schema 9)

A skeleton drawn into an object (drawn bones, "Rig as a person", a 2D drawn puppet) is its `rig`:

```json
"rig": {
  "skeleton": {"joints": [
    {"name": "root", "parent": null, "rest": {"position": [0, 0.5, 0], "rotation": [0, 0, 0, 1], "scale": [1, 1, 1]}},
    {"name": "j1", "parent": 0, "rest": {"position": [0.44, 0.12, 0], "rotation": [0, 0, 0, 1], "scale": [1, 1, 1]}}
  ]},
  "standard": "custom",
  "tips": {"head": [0, 1.8, 0]},
  "skin": "rigs/5c1e…a0.skin",
  "surface": "9b0e…41"
}
```

- `skeleton.joints[]`: parents first; `rest` is the joint's place relative to its parent, with no turn of its own (a
  drawn joint is a point; its bone runs to its child). Positions are in the rig's space: the object's own space, except
  bevelled shapes, whose triangles are built at their size (the object's scale comes out).
- `standard`: `humanoid` after "Rig as a person" (joint names are the humanoid bones: `hips`, `spine`, `chest`, `neck`,
  `head`, `leftShoulder`, `leftUpperArm`, …, `rightToes`), so humanoid clips play on it; `custom` for drawn chains
  (`root`, `j1`, `j2`, …).
- `tips`: where a leaf joint's bone ends (the top of the head, the fingertips, the toes).
- `skin`: the weights of a solid, a file under `assets/` named by a hash of its bytes; `points` instead holds a
  drawing's weights inline (`{"joints": [four per stroke point], "weights": [four per stroke point]}`, the drawing's
  points in stroke order).
- `surface`: the fingerprint of the surface the weights were made for (as `paint.surface.mesh`; for a drawing, of its
  points). When it no longer matches, the app offers to fit the weights to the new shape.

The `.skin` file is little-endian binary: `MQSK`, version (1), vertex count (u32 each); then per vertex four joint
indices (u16), then per vertex four weights (f32, adding up to 1). Vertices are the triangles' corners the app draws for
the object, in order; a placed model's are its parts' in order, as one surface.

The pose is in the object's properties: `bone.<joint name>` is a joint's turn relative to its parent (a quaternion,
`{"quat": [x, y, z, w]}`), keyed by the timeline like any property. Imported rigged models use the same keys with their
own joint names. A clip playing on the character sets the joints it moves; a `bone.` turn overrides the clip for that
joint.

One journal command changes rigs: `setRig` (`{"op": "setRig", "id", "rig"}`, the whole rig or none; its file is written
first). Schema 9 only added the optional key and the command; files from schema 8 open unchanged, and Maquette 0.6
refuses schema 9.

## Looping motions (schema 10)

A scene's timeline has `behaviors`: procedural motion evaluated at any time, each `{id, target, kind, start, end?,
enabled}` with `kind` an object whose `type` says which. Maquette 0.8 adds two kinds:

```json
{"type": "bounce", "height": 0.4, "period": 1}
{"type": "swing", "angle": 25, "period": 2}
```

`bounce` hops the object up to `height` metres and back down once every `period` seconds (a parabola per hop);
`swing` turns it `angle` degrees each way around its own z axis, there and back every `period` seconds. The
inspector's Motion row writes these and four older kinds with fixed numbers and one speed: `spin`
(`degreesPerSecond` = 90 × speed), `bob` (`period` = 3 ÷ speed), `noise` (`frequency` = 1.2 × speed), `followPath`
with `loop: true` (`duration` = 6 ÷ speed), `bounce` (`period` = 1 ÷ speed) and `swing` (`period` = 2 ÷ speed). Make
keyframes replaces the behaviours with ordinary tracks. Schema 10 only added the two kinds; files from schema 9 open
unchanged, and Maquette 0.7 refuses schema 10.

## Live performance (schema 11)

A scene's timeline has `takes`: every Perform recording, kept whole.

```json
{"id": "…", "name": "Take 2", "range": {"start": 1.5, "end": 4.2},
 "channels": [{"target": "<object id>", "property": "headYaw", "keyframes": [{"time": 1.5, "value": {"float": 0}, "easing": "linear"}]}],
 "used": [{"start": 1.5, "end": 2.8}]}
```

The timeline's `tracks` are always what plays (the comp); a take is what a stretch of them can be taken from again.
`used` lists where the comp plays this take, in order. One journal command changes takes: `setTakes`
(`{"op": "setTakes", "takes": [{"id", "take"?, "index"?}]}`: insert, replace, or remove when `take` is absent).
Recording and using a take are batches of `setTracks` and `setTakes`.

Objects gain optional properties:

| Property | On | Value |
|---|---|---|
| `dangle.<joint name>` | a character | 0…1, how loosely that joint hangs (absent: it doesn't) |
| `breathe` | a character | 0…1, how deeply it breathes by itself |
| `autoBlink` | a character with eye parts | `true`: it blinks by itself (a Blob does unless `false`) |
| `liveHead` | a character whose skeleton isn't a person's | the joint that turns with the head channels |
| `attachBone` | a child of a rigged object | the joint it rides |
| `triggers` | a character | a JSON list (as a string, like `poseLibrary`) of `{id, name, kind, key?, holds?, expression?, pose?, show?, hide?}`; `kind` is `expression`, `pose` or `swap` |

The head and hand channels (`headYaw`, `headPitch`, `headRoll`, `handLeftX/Y`, `handRightX/Y`) now also move drawn and
imported skeletons; a child with `faceRole` under a rigged object is a face part. Schema 11 only added these; files
from schema 10 open unchanged, and Maquette 0.9 refuses schema 11.

## The dark studio (schema 12)

Looks gain the mood `darkStudio` (a blank project's world: a near-black ground, one soft key light). Schema 12 only
added it; files from schema 11 open unchanged, and Maquette 0.11 refuses schema 12.

## Sheets (schema 13)

A scene keeps the sheets something was drawn on (`sheets`, missing when there are none). Each sheet:

| Key | Type | Meaning |
|---|---|---|
| `id` | string | Unique in the scene. |
| `name` | string | "Sheet 1"…, renamed by hand. |
| `shape` | string | `flat`, `around` (a standing cylinder whose front passes through `origin`), `dome` (a sphere, the same) or `onObject` (strokes land on `object`'s surface). |
| `origin` | [x, y, z] | Where it was placed: in `object`'s space when it lies on one (it rides with it), else the world. |
| `rotation` | [x, y, z, w] | Its turn: local +z faces whoever placed it, +y is its up. |
| `object` | string? | The object it lies on. |
| `width`, `height` | number | The size shown (metres); strokes still land past the edge. `height` is a cylinder's height too. |
| `radius` | number | How tightly `around` and `dome` curve (metres). |

One journal command changes sheets: `setSheets` (`{"op": "setSheets", "sheets": [{"id", "sheet"?, "index"?}]}`: insert,
replace, or remove when `sheet` is absent). A sheet is kept by the first stroke on it, in that stroke's step.

A flipbook track's `anchor` may be `"sheet:<id>"`: its strokes' points are then the sheet's own coordinates in metres
(flat: across and up; around: the arc from the front and the height; dome: the arcs across and up), drawn in
perspective through the camera; their half-widths are metres too. Schema 13 only added these; files from schema 12
open unchanged, and Maquette 0.12 refuses schema 13.

## Rigs you can change, repeats, motion and sculpts (schema 14)

A rig made of pins and dots keeps them, so it can be changed afterwards:

```json
"rig": {
  "skeleton": {"joints": [ … ]},
  "standard": "custom",
  "marks": [
    {"name": "j1", "kind": "pin", "position": [0.42, 0.62, 0], "thickness": 0.15},
    {"name": "j2", "kind": "pin", "position": [1.57, 0.62, 0], "parent": "j1", "thickness": 0.07}
  ]
}
```

- `marks[]`: each a joint of the same `name`; `kind` is `dot` (a joint) or `pin` (a soft bend: a pin with a mark above it
  makes three bones between them, joints `<name>~0`, `~1`, `~2`); `parent` is the mark it hangs from; `thickness` how thick
  the part is there (0 when unknown). The skeleton is built from them (plus a `root` in the middle of what they leave
  uncovered); joints keep their marks' names, so `bone.` keys survive a change.
- `person`: a person rig's dots (`head`, `chin`, `leftShoulder` … `rightAnkle` → a point in the limb's middle).
- A group's rig has no skin: each part names its joint in `attachBone`.
- `bendDetail` (property, a number): a shape rigging cut finer so it can bend, in cuts across its largest side; every
  reader cuts it the same way (split every edge longer than the side over the cuts at its middle, until none is).

A track may repeat: `"cycle": {"start": 1, "end": 3, "repeats": 2}` plays the stretch from `start` to `end` that many more
times after it ends (`repeats` missing: forever). A row's tracks share one cycle.

The library (`library.json`) keeps `motions`: `{id, name, kind: pose|clip|loop, standard, joints: {name: [keys]},
travel: {position|rotation: [keys relative to the start]}, duration, favorite, added, lastUsed}`. An asset lightened as it
came in has `original` (the file it came from, kept beside it) and `detail` (1 is what the device keeps smooth).

Schema 14 only adds optional keys; files from schema 13 open unchanged, and Maquette 0.13 refuses schema 14.

## Drawings on sheets and stuck titles (0.15, still schema 14)

Two optional properties:

- `drawnOn` (string): the id of the kept sheet a drawing was drawn on; moving the sheet moves the drawing with it.
- `sticksToCamera` (bool): the thing's transform is read in the shot camera's frame (its position and rotation relative
  to the camera), so it stays put on the picture as the camera moves.

Readers that don't know them ignore them; Maquette 0.14 opens 0.15's files.

## Shaping (schema 15)

What's done to a shape after it's built, in the order every reader applies it (`ShapeStack`): smoothed while built,
cut finer (`bendDetail`), then moved by brush strokes, the cage and the bend. Moving keeps every corner in order.

```json
"properties": {"subdivision": {"int": 2}, "smoothAngle": {"float": 40},
               "deform": {"enum": "twist"}, "deformAmount": {"float": 90}, "deformAxis": {"enum": "y"}, "linked": {"string": "link-box"}},
"shaping": {
  "cage": {"counts": [3, 3, 3], "bounds": {"min": [-0.55, -0.05, -0.55], "max": [0.55, 1.05, 0.55]}, "offsets": [[0, 0, 0], …]},
  "sculpt": {"vertexCount": 1536, "moved": "<base64>"}
}
```

- `subdivision` (0–3): Catmull–Clark levels a blockout or modelled shape is smoothed with; open borders keep their line.
- `smoothAngle` (degrees): edges softer than this are shaded smooth (missing: a modelled shape is crisp everywhere, a
  smoothed one smooth everywhere). Flat shading is `shading: "flat"`.
- `deform`: `bend` (around a circle that turns the whole length by `deformAmount` degrees, toward the next axis), `twist`
  (degrees at the far end), `taper` (the far end's size changes by the amount), `bulge` (the middle's); measured along
  `deformAxis` (x, y or z; missing: y) over the shape's own box before it was moved. `deformAmount` animates.
- `linked`: things with the same value share a shape; an edit to one is made to all in the same step.
- `shaping.cage`: `counts` points along x, y and z (2–4), standing on `bounds` (the shape's own space) at rest, each moved
  by its `offsets` entry (x fastest, then y, then z); every corner is the Bernstein blend of the moved points.
- `shaping.sculpt`: brush strokes as offsets of the built-and-cut surface's corners; `moved` is base64 of little-endian
  records (Int32 corner, Float32 x, y, z) for the corners that moved; ignored when the surface no longer has
  `vertexCount` corners.

A sketch may keep rules: `"constraints": [{"parallel": {"_0": 0, "_1": 2}}, {"length": {"_0": 1, "_1": 0.04, "side": 0}}]`
(Swift's enum coding: `parallel`, `perpendicular`, `equal`, `tangent` {line, circle}, `length` {curve, metres, side}, `angle`
{curve, degrees}, `ratio` {curve, curve, factor}); curves are named by their place in `curves`.

Schema 15 only adds optional keys; files from schema 14 open unchanged, and Maquette 0.15 refuses schema 15.

## Editable history (schema 16)

A modelled object may keep the steps that made its shape (`ModelHistory`), in its own space, metres:

```json
"modelHistory": {
  "base": {"v": [...], "f": [...]},
  "steps": [
    {"tag": 4211, "keepsPositive": true,
     "action": {"sketch": {"_0": {"plane": {...}, "curves": [{"circle": {"center": [0, 0], "radius": 0.003}}], "region": 0,
                                   "distance": -0.01, "through": true, "onFace": {"tag": 77, "at": [0, 0.01, 0]}}}}},
    {"tag": 9031, "keepsPositive": true,
     "action": {"bevel": {"edges": [{"faces": [12, 40], "at": [0.02, 0.005, 0.01]}], "size": 0.002, "style": "round"}}}
  ],
  "earlier": [],
  "tags": [77, 12, ...],
  "shape": 5512903311
}
```

- `base`: the shape the steps start from (an editable mesh, as `kind.mesh`).
- `steps`: in order; `action` is one of `pushPull` {faces, distance}, `inset` {faces, distance}, `bevel` {edges, size,
  style}, `shell` {thickness, open}, `sketch` {plane, curves, region, distance, through, onFace} or `combine` {tool, operation}
  (Swift's enum coding). `symmetry` (x, y, z) and `keepsPositive` say how live symmetry was kept. `tag` names the faces
  the step makes.
- A face is `{"tag", "at"}` (its tag and its middle when the step was made); an edge `{"faces": [tag, tag], "at"}`.
- `tags`: one per face of the shape the steps make, in face order; `shape`: that shape's key (FNV-1a over its corners as
  the file rounds them, under 2^53). When the object's shape doesn't match it, the steps are fixed.
- `earlier`: steps before a change the history can't replay, listed but fixed.
- One journal command changes it: `setModelHistory` (`{"op": "setModelHistory", "id", "modelHistory"}`, the whole history
  or none). Writers change it through the app (that command, or the bridge's `model` `step`), never by
  hand: a history that doesn't make the shape is simply read as fixed.

Schema 16 only adds the optional key and the command; files from schema 15 open unchanged, and Maquette 0.16 refuses
schema 16.

## Texture (schema 17)

Paint gains maps, masks and fills (0.18). A layer's colour stays in `tiles`; its other maps and its mask have tiles of
their own in `maps`, by name:

```json
{"id": "l2", "name": "Brick", "opacity": 1, "blend": "normal", "visible": true,
 "tiles": {"0,0": "paint/…png"},
 "maps": {"roughness": {"0,0": "paint/…png"}, "metal": {…}, "bumps": {…}, "mask": {"0,0": "paint/…png"}},
 "fill": {"type": "material", "material": {"id": "brick", "name": "Brick", "color": "#9E4A35", "secondColor": "#CFC8BC",
          "roughness": 0.85, "metal": 0, "glow": "#000000", "pattern": "bricks", "scale": 0.22, "variation": 1, "bumps": 0.6}}}
```

- `maps`: `roughness`, `metal`, `bumps` and `fur` are grey (white = 1; bumps' 0.5 is the surface itself), `glow` a colour;
  each tile's alpha is how much it covers (where a map is clear the thing's own value shows). `mask`'s alpha is how much
  of the layer shows; a layer with a `mask` key and no tiles under it is hidden. Absent when the layer has none.
- `blend` adds `darken`, `lighten` and `softLight`.
- `fill`: what a fill layer's tiles are made from: `{"type": "color", "color"}`, `{"type": "material", "material"}` (a
  frozen copy: two colours, `roughness`, `metal`, `glow`, `pattern` — `none`, `noise`, `wood`, `planks`, `brushed`,
  `marble`, `stone`, `concrete`, `bricks`, `tiles`, `weave`, `leather`, `rust`, `sand` — `scale` in metres, `variation`,
  `bumps`, and `pictures` for an imported set: keys of PNGs under `assets/materials/`), or `{"type": "wear", "wear":
  {"kind": "dirt" | "edges", "amount", "color", "roughness", "seed"}}`. The tiles are written whenever it changes.

`paint` gains `mirror` (`x`, `y` or `z`: strokes are painted again mirrored across that axis of the object's own space),
`normalMap` (a tangent-space normal map baked from a more detailed surface, a PNG at the surface's size: x along u, y up
the picture, z out) and `normalsFrom` (that surface's name). `surface` gains `seams`: edges marked by hand where the
unwrap cuts, `[{"a": [x, y, z], "b": [x, y, z]}]` in the object's own space.

`paintTiles`' changes gain `map` (absent for colour); a change to a `mask` needs the layer to have one. The Look's
`comic` gains `hatching` (0 off … 1). Objects gain the properties `furLength` (metres; absent or 0: no fur),
`furDensity` (0–1), `furStyle` (`shells` when absent, or `cards`) and `furDroop` (0–1).

The device's material library is `materials.json` beside `materials/` (a versioned envelope, `kind: "materials"`):
`{"materials": {id: material}, "order": [id]}`, the person's own and edited built-ins.

Schema 17 only added optional keys; files from schema 16 open unchanged, and Maquette 0.17 refuses schema 17.

## Physics (schema 18)

A real thing carries `physics` (absent: it takes no part in the run):

```json
"physics": {"material": "glass", "motion": "falls", "mass": 2.5, "friction": 0.4, "bounce": 0.3,
            "startSpeed": [0, 0, 1.5], "startSpin": [0, 2, 0], "breaks": true, "stiffness": 0.8, "hangs": true}
```

- `material`: `wood`, `steel`, `aluminium`, `stone`, `concrete`, `glass`, `ice`, `plastic`, `rubber`, `foam`, `cardboard`,
  `cloth`, `jelly`. `motion`: `falls`, `stays` or `follows` (its keys). Every other key is optional and overrides what the
  material says: `mass` (kg; absent: density × volume), `friction`, `bounce` (0–1), `startSpeed` (m/s) and `startSpin`
  (rad/s) in world space, `breaks`, `stiffness` (cloth and jelly, 0–1), `hangs` (cloth from its top edge).
- A real group is one body made of its parts; real things inside a real group are part of it.

A scene carries `physics` (absent: Earth's gravity, still air, a ground, no joints, from 0 s):

```json
"physics": {"gravity": "moon", "customGravity": 2.0, "windHeading": 90, "windSpeed": 6, "gusts": 0.3, "ground": true,
            "groundMaterial": "concrete", "start": 0.5,
            "joints": [{"id": "door", "kind": "hinge", "first": "<object id>", "second": "<object id>",
                        "anchor": [0.4, 1, 0], "axis": [0, 1, 0], "limits": [0, 110], "motorSpeed": 45}]}
```

- `gravity`: `earth`, `moon`, `mars`, `jupiter`, `none`; `customGravity` (m/s²) wins when present. `windHeading`: degrees
  around y the wind blows toward (0 toward −z, 90 toward +x).
- A joint: `kind` (`hinge`, `slider`, `ball`, `glue`, `spring`, `rope`, `gear`), `first`, `second` (absent: the world),
  `anchor` and `axis` in `first`'s own space, `otherAnchor` (springs and ropes: in `second`'s space, or the world's),
  `limits` (degrees for hinges, metres for sliders, as `[low, high]`), `motorSpeed` (°/s or m/s), `motorStrength`
  (N·m or N), `springiness` (oscillations a second), `length` (m), `gears` (two hinge joint ids) and `ratio`.

Two object kinds: `{"type": "force", "force": {"kind": "fan" | "pull" | "whirl", "strength", "reach"}}` (a fan blows
along its own −z) and `{"type": "fluid", "fluid": {"kind": "pour" | "splash" | "smoke" | "fire", "box": [x, y, z],
"amount", "duration", "color", "width"}}` (`amount`: litres a second to pour, litres to splash, 0–1 of smoke or fire;
`box` at most 4 m a side).

The Look's `lighting` gains `realSun`: `{"place", "latitude", "longitude", "utcOffset", "year", "month", "day", "hour",
"north", "study": [from, to]}` (hours, local clock time; with `study` the time runs from `from` to `to` across the
timeline).

The commands `setPhysics` (`id`, `physics`) and `setScenePhysics` (`physics`). A run itself isn't stored: the same scene
always simulates to the same frames.

Schema 18 only added optional keys and two object kinds; files from schema 17 open unchanged, and Maquette 0.18 refuses
schema 18.

## Characters (schema 19)

A part of a made character carries `part` (absent: a plain thing):

```json
"part": {"job": "arm", "side": "left", "style": "tube", "segment": 1, "limb": "2",
         "states": {"oh": {"open": 1.1, "wide": 0, "round": 0.8, "smile": 0, "lift": 0, "tilt": 0, "squash": 0}},
         "shows": "oh"}
```

`job`: head, eye, brow, mouth, nose, ear, hair, body, arm, leg, tail, wing, extra. `side`: left, right or middle
(absent: middle). `style`: a style of the part set, or `drawn`, `modelled`, `thing` (a thing given parts became the
body). `segment`: the piece of a hinged part, from 0 at the top (absent: 0). `limb`: which one when there are several
(`front`, `back`, `2`…; absent: the first). `states`: the face states the person changed, as bends of the part (absent:
the job's defaults). `shows`: present on a drawing of one face state, which shows in its part's place while that state is
on.

A made character is a group with the property `characterStart` (`person`, `fourLegs`, `wings`, `blob`, `nothing`). Its
rig is an ordinary rig (U4's marks), its pieces ride their joints with `attachBone`. Characters carry two more keyable
properties: `mouthShape` (one of `neutral`, `ah`, `d`, `ee`, `f`, `l`, `m`, `oh`, `r`, `s`, `uh`, `wOo`, `smile`,
`surprised`; stepped) and `browState` (`neutral`, `up`, `angry`, `sad`; stepped).

The command `setPart` (`id`, `part`).

Schema 19 only added optional keys; files from schema 18 open unchanged, and Maquette 0.19 refuses schema 19.

## Holds and looking (schema 20)

A scene's timeline has `holds` (absent: nothing is held), who holds what from when:

```json
"holds": [{"id": "h1", "target": "<cup>", "start": 2.0, "holder": "<hand or character>", "joint": "rightHand",
           "grip": {"position": [0, 0.05, 0.02], "rotation": [0, 0, 0, 1], "scale": [1, 1, 1]}},
          {"id": "h2", "target": "<cup>", "start": 5.0}]
```

From `start` the `target` rides the `holder` (or the `joint` of the holder's skeleton) as `grip` places it, in the
holder's (or joint's) space; the latest hold that has started wins. A hold without `holder` puts the thing down where
its last holder had it at that moment. One journal command changes them: `setHolds` (`{"op": "setHolds", "holds": […]}`,
the whole list).

A thing can carry `lookAt`: the id of the thing it looks at (a string; keyable and stepped, `""` looks at nothing). A
character turns its head toward it, anything else turns whole.

Schema 20 only added optional keys; files from schema 19 open unchanged, and Maquette 0.20 refuses schema 20.

## Film (schema 21)

- **A soft panel** is a light of kind `{"light": "area"}` with `lightWidth` and `lightHeight` (metres; 1 and 0.6 when
  missing): a rectangle that lights the way it faces (its −z), only out of its front. In glTF it travels as a spot with
  an 80° cone and `extras.maquette.panel: [width, height]`, and reads back as a panel; the Blender package makes it a
  rectangular area light.
- **Cameras** carry `sensor` (`fullFrame` when missing, `super35`, `apsC`, `microFourThirds`, `super16`, `phone`,
  `largeFormat`, `imax`: the body the millimetres are read on; `fieldOfView` stays the truth); `rig` (`dolly`, `crane`,
  `orbit`, `handheld`; missing: on a tripod) with `rigTravel`, `rigLift` (m), `rigSwing` (degrees), `rigArm` (m, 3) and
  `rigShake` (0–1), all but `rigArm` keyable; and `focusOn`, the id of the thing the lens keeps sharp (a string, keyable
  and stepped, `""` = by distance). A new `focusOn` key pulls focus over 0.8 s.
- **The timeline** carries `frame`, the picture's shape (`"2.39:1"`, `"9:16"`, `"4:5"`, `"1:1"`; missing: 16:9).
- **The Look** carries `atmosphere` (missing: clear air): `{"haze": 0.4, "godRays": 0.6, "color": {…}}` (0–1 each;
  `color` missing takes the sky's horizon warmed by the sun). Its `sky` can carry `environment` (an HDRI under
  `assets/`, `environment/<name>.hdr`, a Radiance file), `environmentTurn` (degrees, left positive) and
  `environmentExposure` (stops); the sun and the sky's three colours are the picture's, read when it came in.

Schema 21 only added optional keys and a light kind; files from schema 20 open unchanged, and Maquette 0.21 refuses
schema 21.

## Motion design (schema 22)

- **Things** can carry `motionDesign` (absent: none), with any of:
  - `clones`: `{"layout": {"grid": {"columns": 5, "rows": 5, "layers": 1, "spacing": [1.4, 1.4, 1.4]}}, "effects": […],
    "seed": 1}`. Layouts: `grid` (columns along the thing's x, rows along its z, layers up its y, centred on it), `circle`
    (`count`, `radius`, `facesOut`), `line` (`count`, `step`, in the thing's own directions), `path` (`count`, `path`: the
    id of a drawn line, `along`), and since schema 26 `placed` (`{"placed": {"_0": [transform, …]}}`: each copy's
    place, turn and size against the thing's own, the first the thing itself; a three.js `InstancedMesh` comes in this
    way and the inspector can't make one). An effect: `{"id": "…", "kind": "random" | "delay" | "push", "move": [x, y, z] (m),
    "turn": [x, y, z] (degrees), "grow": 0.2 (a fraction), "delay": 0.1 (s), "field": …}`; a field is `{"everywhere": {}}`,
    `{"sphere": {"centre": [x, y, z], "radius": 2}}` or `{"wave": {"speed": 3, "width": 1.5, "every": 2}}` (`every` 0:
    once). The copies are never stored: they're made in the shown scene with ids `<thing>~clone<n>` and `cloneOf`, at most
    1000.
  - `morph`: `{"target": "<id>"}`: the thing becomes that thing's shape as its `morph` property (0–1, keyed) rises.
  - `letters` (3D text): `{"preset": "flyIn" | "bounce" | "cascade" | "pop" | "spin" | "typewriter" | "wave", "order":
    "forward" | "backward" | "middle" | "random", "start": 1.0, "stagger": 0.06, "length": 0.6}` (seconds; `length` is one
    wave for `wave`).
- **Properties**: `morph` (0–1) and `effectStrength` (how strongly the clone effects act, 1 when missing), both keyable.
- **3D text** carries `font` (absent: the style's): a font file under `assets/`, `fonts/<name>.otf` (or .ttf, .ttc).
- **The timeline** carries `links` (absent: none):
  `[{"id": "…", "target": "<id>", "channel": "turnY", "driver": {"thing": {"id": "<id>", "channel": "turnY"}}, "amount": -1,
  "delay": 0}]`, or a sound as the driver: `{"sound": {"clip": "<audio clip id>", "feature": "beat"}}` (`loudness`, `bass`,
  `beat`). Channels: `moveX`, `moveY`, `moveZ`, `turnX`, `turnY`, `turnZ`, `size`, `glow`, `opacity`, `effect`, `morph`,
  `reveal`. The target's channel gets `amount` × the driver's change since its edited place (metres, degrees, a
  fraction), or × the sound's value (0–1).
- **Audio clips** can carry `levels` (absent: not measured yet): `{"loudness": "<base64, one byte every 1/60 s>", "bass":
  "<the same>", "beats": [0.5, 1.0, …] (seconds into the file), "tempo": 120}`.
- Two journal commands: `setMotionDesign` (`{"op": "setMotionDesign", "id": "…", "motionDesign": {…}}`, none removes it)
  and `setLinks` (`{"op": "setLinks", "links": […]}`, the whole list).

Schema 22 only added optional keys; files from schema 21 open unchanged, and Maquette 0.22 refuses schema 22.

## Looks & the library (schema 23)

- **Looks** (built in or `looks` in the project) can carry `paint` (absent: none): `{"strokes": 0.8, "size": 6, "wetEdges":
  0, "granulation": 0, "paper": 0.2}` (size in points at 1080p, the rest 0–1) and `pixel` (absent: none): `{"size": 4,
  "colors": 6}` (blocks in points at 1080p, levels a channel; used from the scene's Look only). Shading can carry
  `shadowTint` (a colour, `"#8A7CC0B3"`: how much in its alpha) and `reflection` (0–1). Built-in names add `painterly`,
  `watercolour`, `gouache`, `paperman`, `animeCel`, `cleanProduct`, `pixel`.
- **The Finish** (`post`) can carry `misregistration` (bool), `boil` (0–1) and `benDay` (0–1); `texture` adds `newsprint`,
  `riso`, `canvas`. All off when missing.
- **Screen effects** add the kinds `impact`, `focusLines` and `comicDots`, and `center` (`[x, y]`, 0–1 from the top left) or
  `target` (a thing's id: the middle of its box as the shot's camera sees it).
- **The ground** can carry `surface` (absent: plain): `desert`, `grass`, `snow`, `rock`, `sand`, `pavement`, `waterEdge`,
  `roomFloor`.
- **A drawing** comes in as ordinary things: a group per drawing (and per layer group), each layer an editable shape with
  its picture painted on (`paint/`), named after its layer.

Schema 23 only added optional keys; files from schema 22 open unchanged, and Maquette 0.23 refuses schema 23.

### The library (Yours)

`library.json` adds `styles` (saved Looks, by id), `effects` (saved particle effects: `{"id", "name", "particles": {…}}`),
`parts` (saved character parts: `{"id", "name", "part": {…}, "mesh": "<file>"}`) and `origins` (by the thing's id, brushes
and materials too: `{"author": "…", "licence": {"kind": "anything" | "credit" | "personal" | "own", "text": "…"}, "pack":
"…", "imported": "<ISO 8601>"}`). All empty when missing.


## Guest kits (0.25, still schema 23)

Everything G1 keeps is a property, so 0.24 opens a 0.25 project and keeps it (D-519):

- `buildingPart` (enum): what a thing is in a building: `wall`, `slab`, `roof`, `stairs`, `column`, `beam`, `railing`,
  `door`, `window`, `person`, `terrain`, `furniture`. Plans and IFC read it; a thing without one inherits its group's.
- `explode` (float 0–1, animatable) on a group: how far its parts are pulled apart. `explodeOffset` (vec3) on each part:
  where it goes at 1, in the group's space.
- Room's names are 3D text lying face up on a floor; an underlay is a locked sketch on the ground (a DXF) or a locked,
  faint card lying flat (a PDF page or a picture under `assets/`).

## Review notes (schema 24)

A scene keeps its review notes (`notes`, missing when there are none). Each note:

| Key | Type | Meaning |
|---|---|---|
| `id` | string | Unique in the scene. |
| `object` | string? | The thing it's stuck on (it follows the thing). |
| `point` | [x, y, z] | Where: in `object`'s space when it has one, else the world. |
| `world` | [x, y, z] | Where it was in the world when written (for a note whose thing was deleted). |
| `author` | string | Who wrote it (Settings ▸ Your name, else the device's name; "Assistant" from the bridge). |
| `text` | string | The note. |
| `date` | number | When (seconds since 2001-01-01). |
| `time` | number? | The film's moment it was written at, through a camera. |
| `replies` | [{`id`, `author`, `text`, `date`}] | The thread (missing when there are none). |
| `resolved` | bool? | `true` once resolved (missing while open); an answer opens it again. |

One journal command changes notes: `setNotes` (`{"op": "setNotes", "notes": [{"id", "note"?, "index"?}]}`: insert,
replace, or remove when `note` is absent). Schema 24 only added them; files from schema 23 open unchanged, and Maquette
0.25 refuses schema 24.

## Web pieces (schema 25)

A card (`kind.card`) or an overlay (`kind.overlay`, shape `image`) may carry `web`, a web piece played on the
timeline's clock:

```json
"web": {"kind": "html", "source": "<!doctype html>…", "width": 1280, "height": 720, "start": 2.0, "duration": 6, "loop": true}
"web": {"kind": "lottie", "file": "logo.json", "width": 512, "height": 512, "start": 0}
"web": {"kind": "html", "file": "intro", "entry": "index.html", "width": 1920, "height": 1080, "start": 0}
```

| Key | Type | Meaning |
|---|---|---|
| `kind` | `html` · `lottie` | A page (HTML, CSS, JavaScript, three.js) or a Lottie animation. |
| `source` | string? | The page's (or the Lottie file's) whole text, kept in the project. |
| `file`, `entry` | string? | Or a file or folder under `assets/`, and the page inside a folder (`index.html` when absent). |
| `width`, `height` | int | The page's size in CSS pixels (16–3840 a side). |
| `start` | number | Timeline time (s) of the piece's frame 0. |
| `duration`, `loop` | number?, bool? | How long it plays; after it, it holds its last frame or loops. Absent: it runs as long as the timeline. |

Its frames step 60 a second from `start`; before it a card shows frame 0 and an overlay isn't drawn. It is edited with
`setKind` (no new command). Schema 25 only added the key; files from schema 24 open unchanged, and Maquette 0.27 refuses
schema 25.

## Clones as placed (schema 26)

Schema 26 adds one clone layout, `placed` (Motion design, above), so a file's instances stay one thing with its copies.
Nothing older changes shape: files from schema 25 open unchanged, and Maquette 0.28 refuses schema 26.

## workspace.json

How the project shows when it opens. It isn't the project (it's never undone and isn't in the journal); it's
written moments after it changes and when the project closes. A missing file means the defaults; a damaged value
falls back to its default; unknown keys are ignored. Plain JSON, no envelope.

| Key | Type | Meaning |
|---|---|---|
| `schemaVersion` | number | 1. |
| `template` | string? | What the project is set up for: `blank`, `print`, `room`, `animation`, and since 0.25 `game` and `study` (0.12: switchable any time from the scene's name, which rewrites `snap`, `showsGrid`, `shapeSize`, `units`, `printBed` and raises `timeline`); `character` and `sketch` from older projects read as `blank`. |
| `timeline` | string | `hidden` (the default), `transport` (the slim transport) or `full`. |
| `timelineHeight` | number | The whole timeline's height in points, 150–900 (260 by default). |
| `snap` | object | `grid`, `gridSize` (m), `rotation`, `rotationStep` (degrees), `ground`, `objects`, `objectThreshold` (m), and since 0.4 `corners`, `edges`, `faces` (points snap to corners and edge middles, edges, faces; on when missing); since 0.13 `magnet` (the Snap magnet: off, nothing snaps; on when missing). |
| `showsGrid` | bool | The grid on the ground. |
| `shapeSize` | number | New shapes' size in metres (1; `print` uses 0.05). |
| `firstPanel` | string? | A tool panel to open the first time the project opens (then removed): `model`, `rig` (`cast` before 0.12, now ignored), or `board` (0.9: the project opens on its Schizzo board). |
| `units` | string | The unit lengths are shown and typed in: `mm`, `cm` (the default), `m`, `in`, `ft`. `print` uses `mm`, `room` `m`. |
| `printBed` | string? | The 3D printer whose build volume the stage outlines (`PrintBed.presets`: `filament-220`, `filament-256`, `filament-180`, `prusa-mk4`, `bambu-x1`, `bambu-a1-mini`, `ender-3-v3`, `resin-218`, `form-4`); `print` starts with `filament-220`. An unknown id is dropped. |
| `section` | object? | The section view: `{"normal": [x, y, z], "offset": d}`; what's beyond the plane (`normal · p > offset`) is cut away on the stage. Missing: off. |
| `showsDimensions` | bool | Kept dimensions show on the stage (true). |
| `frameGuide` | object? | Since 0.5: the drawing guide over the frame for flipbooks. `kind` (`grid`, `isometric`, `perspective`, `symmetry`), `assisted`, `spacing` (frame heights), `origin` (`{"x","y"}`, frame heights from the centre, y up), `angle` (degrees), `vanishingPoints` (1–3, same units), `symmetry` (`vertical`, `horizontal`, `quadrant`, `radial`), `segments`, `mirrorRadial`. Missing: off. |
| `planeGuide` | object? | Since 0.5: the same, laid on a flat sheet for ink (`grid`, `isometric`, `symmetry`; `spacing` in metres). Missing: off. |

| `rotoscope` | object? | Since 0.22: the video behind the stage. `video` (a file under `assets/`), `opacity` (0–1), `start` (seconds on the timeline where the video's first frame is), `shown`, `inFront` (true: faintly over the scene, else behind it). The stage only; exports never show it. Missing: none. |
| `references` | array | Since 0.9: pictures pinned from the board, floating over the stage. Each: `id`, `image` (a file under `assets/`, `references/<hash>.png`), `title`, `x` and `y` (the card's middle as fractions of the stage, 0–1), `width` (points, 120–900), `aspect` (height ÷ width); since 0.13 `folded` (true: a small chip) and `window` (true: opened from Actions ▸ Reference, not pinned from the board, so it stays while the Board is off; since 0.27 the newest open one becomes `referenceWindow`'s picture when the file is read). Values out of range are brought back in; missing: none. |
| `referenceWindow` | object | Since 0.27 (Q1): the Reference window. `open`, `mode` (`canvas`, `image` or `face`), `x` and `y` (its middle as fractions of the stage, 0–1), `width` (points, 160–900) and `height` (120–900) of what it shows, `image` (a file under `assets/`, `references/<hash>.png`) and `imageAspect` (height ÷ width), `zoom` (1–12, 1 fits the picture), `panX` and `panY` (the picture's middle from the window's, as fractions of its size), `view` (Canvas's camera, a viewpoint like the scene's). Values out of range are brought back in; missing: never opened. |

## board/ (the Schizzo board)

Since 0.9. The folder is hmm-kit's `BoardStore`; it appears the first time the board is opened.

```
board/
  board.json        the board: a versioned envelope {schemaVersion: 1, kind: "board", payload}
  view.json         where the person was looking: {"center": {"x", "y"}, "scale"} (not part of undo)
  history/          the board's own history journal (the same format as a scene's, below)
  assets/           pictures on the board, named by their content
```

`payload` is `{"items": […], "brushes": {…}, "paper": {"pattern": "dots" | "grid" | "plain", "color": "#16171A"}}`.
Lengths are board units (one unit is one point at 100 %), y runs down. `brushes` holds the frozen copies of the
brushes the strokes name, by content key, exactly like `project.json`'s. Items are back to front; each has an `id`
and a `kind`:

| `kind` | Fields |
|---|---|
| `stroke` | `points` (flat: x0, y0, x1, y1…), `widths` (a radius per point), `alphas` (0–1 per point), `color` (`#RRGGBB`), `brush` (a key of `brushes`; missing: Ink Pen), `seed`. |
| `picture` | `asset` (a file in `board/assets/`), `rect` (`{"x","y","width","height"}`). |
| `note` | `text`, `rect`, `color`. |
| `arrow` | `from`, `to` (`{"x","y"}`), `color`, `width`, and `fromItem` / `toItem`: the ids of the note or picture an end is tied to. |
| `frame` | `title`, `rect`. A frame carries the items whose middle lies inside it. |

Like `project.json`, the board is for reading: change it through the app so undo and the journal stay true.

## gallery.json (in the projects folder)

Home's arrangement, beside the packages (it moves with them to iCloud Drive). Plain JSON, dates in ISO 8601.

```json
{"schemaVersion": 1, "sort": "recent", "usesFolders": true, "sorts": {"Rooms": "name"}}
```

`sort` is `recent`, `name` or `created`. Since 0.24 a stack is a folder beside the packages, one level deep (the folder's
name is the stack's); `sorts` holds each stack's own sort by its name. A 0.23 file has `stacks` instead (`[{"id", "name",
"members": [<project ids>], "created"}]`): the first time Home reads it, the members are moved into a folder each and
`usesFolders` is written. `Archive` is reserved.

## Sharing

**Share as one file** writes a `.maquettepack`: a stored (uncompressed) zip of the package, with the library models
the project uses copied into `assets/`. 3D-lowey's `.loweypack` files import the same way.

**A library pack** (0.24) is a `.maquettepack` too; what's inside decides. It's a zip of:

```
pack.json           {"formatVersion": 1, "app": "maquette", "name": "…", "author": "…", "licence": {"kind": "credit"},
                     "created": "<ISO 8601>", "items": [{"kind": "look", "id": "…", "name": "…", "file": "items/<id>.json",
                     "files": ["pictures/…"], "author": "…", "licence": {…}}]}
LICENCE.txt         the licence in words
items/<id>.json     one versioned envelope an item (brush, look, material, effect, part, motion, thing)
pictures/ models/   what the items name
```

An item's own `author` and `licence` (when it came from someone else's pack) win over the pack's. Unknown kinds are counted
and skipped; a pack for another app, a newer `formatVersion`, more than 2000 items or a path that leaves the pack is
refused. Packs never carry scripts.
