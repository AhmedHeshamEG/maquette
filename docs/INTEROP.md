# Interop: what every format carries (X1)

Every Maquette feature against every format, both ways. A cell says one of:

- **carried**: it arrives as itself (a round trip, or the other side's own reader, proves it);
- **baked**: it goes out as keys, textures or geometry (the cell says what), and doesn't come back as itself;
- **extras**: it rides in the file's own extras, so it survives a round trip through Maquette only;
- **impossible**: the format has no place for it (the cell says why);
- **not offered**: a direction this format deliberately doesn't take (the cell says what to use);
- **after 1.0**: not proved before launch. X1 closed at the 2026-10-28 converge (CONTEXT §D.21: no new features until
  launch), so what no round trip proves yet waits for an update after 1.0 (D-596, BACKLOG "Interop after 1.0"). Some of
  it may already work (glTF's clips and text have left as keys and meshes since A1 and D1); the matrix only says what a
  test proves. No cell says `todo` any more, and the test fails if one does.

`InteropMatrixTests` (LoweyCore) reads this file. Every `carried`, `baked` and `extras` cell must name the test that
proves it in `InteropProofs.swift`, with the same word; a cell that claims more than its proof fails CI. In a format's
section, a row it doesn't list takes the section's **Not listed** line.

The rows: Meshes and hierarchy · Modelling steps · Paint layers and maps · Materials · The Looks · Ink and flipbooks ·
Sheets · Rigs and skins · Face states · Clips · Keys on any property · Motion paths · Cameras · Lights · HDRIs and the
sky · Physics bodies and joints · Baked runs · Clones and links · Text and logos · Sound and words · Web objects ·
Scenes and shots · Units and dimensions · The artist's credit.

## glTF (.glb, .gltf)

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | carried | carried |
| Modelling steps | after 1.0 | after 1.0 |
| Paint layers and maps | baked — every map as a texture (colour, metallic-roughness, glow, normal) | baked — colour, roughness, metal and glow pictures become a first layer, Model, on the editable copy; a normal map becomes its normals |
| Materials | carried | carried |
| The Looks | impossible — glTF holds surfaces, not a picture's style (the three.js folder and the engine shaders carry it) | impossible — as out |
| Ink and flipbooks | after 1.0 | after 1.0 |
| Sheets | after 1.0 | after 1.0 |
| Rigs and skins | carried | carried — the skeleton in its bind pose, the weights carried onto the editable surface, joints' turns as bone keys (their moves and sizes are left out) |
| Face states | extras | extras |
| Clips | after 1.0 | after 1.0 |
| Keys on any property | carried | carried |
| Motion paths | after 1.0 | after 1.0 |
| Cameras | after 1.0 — the lens is carried, focus and aperture aren't yet | after 1.0 |
| Lights | carried | carried |
| HDRIs and the sky | after 1.0 | after 1.0 |
| Physics bodies and joints | after 1.0 | after 1.0 |
| Baked runs | after 1.0 | after 1.0 |
| Clones and links | baked — clones as GPU instances (`EXT_mesh_gpu_instancing`) where they stand at the first frame, their recipe in extras; links don't leave yet | carried — another tool's instances as placed clones, Maquette's own recipe from extras |
| Text and logos | after 1.0 | after 1.0 |
| Sound and words | after 1.0 | after 1.0 |
| Web objects | after 1.0 | after 1.0 |
| Scenes and shots | after 1.0 | after 1.0 |
| Units and dimensions | carried | carried |
| The artist's credit | after 1.0 | after 1.0 |

## three.js folder (Export ▸ 3D ▸ three.js)

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | carried | after 1.0 |
| Materials | carried | after 1.0 |
| The Looks | baked — toon bands, ink lines, halftone and pixel passes in `maquette/look.js`; the paint Looks as toon bands and lines | after 1.0 |
| Keys on any property | carried | after 1.0 |
| Cameras | carried | after 1.0 |
| Lights | carried | after 1.0 |
| Scenes and shots | carried | after 1.0 |

Not listed: after 1.0

## three.js JSON (`scene.toJSON()`, `ObjectLoader`)

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | carried | carried |
| Materials | carried | carried |
| Rigs and skins | after 1.0 | carried — a skinned mesh's skeleton in its bind pose, its weights on the surface, its bones' turns as bone keys |
| Paint layers and maps | after 1.0 | baked — pictures the file carries (colour, roughness and metal, glow) become a first layer, Model, as glTF's do; a normal map becomes its normals |
| Clones and links | after 1.0 | carried |
| Keys on any property | carried | carried |
| Cameras | carried | carried |
| Lights | carried | carried |

Not listed: after 1.0

## three.js project (a page, a folder or a zip, played in the sandbox)

Library ▸ Import, a drop or Files: the page plays offline on the piece's clock and Maquette's recorder takes its scene
and 10 s of its motion (D-591). Out, a project is the three.js folder above.

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | not offered — Export ▸ 3D ▸ three.js writes a project | carried |
| Materials | not offered — as above | carried — standard and physical materials; a surface drawn by its own shader stays playing (Web objects) |
| Keys on any property | not offered — as above | baked — the page's motion sampled 30 times a second for 10 s (place, turn, size, visibility, colours, glow, opacity, lights, the lens), keys only where the motion bends |
| Clones and links | not offered — as above | carried — an instanced mesh as placed clones; instances that move on their own come in where they stood |
| Cameras | not offered — as above | carried — the camera the page draws with, where it stood |
| Lights | not offered — as above | carried |
| Web objects | not offered — as above | carried — a shader surface keeps playing on a card in its place, showing only itself; a page with no three.js scene plays over the frame |

Not listed: after 1.0

## USD / USDZ

| Feature | Out | In |
|---|---|---|
| Paint layers and maps | baked — colour, roughness, metal, glow and normal as textures | after 1.0 |

Not listed: after 1.0

## FBX

| Feature | Out | In |
|---|---|---|
| Rigs and skins | carried | after 1.0 |

Not listed: after 1.0

## OBJ / MTL

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | baked — world-space meshes, a group a thing | after 1.0 |
| Materials | baked — colour in the MTL | after 1.0 |
| Paint layers and maps | baked — the colour texture | baked — colours after each corner become vertex colours |
| The Looks | impossible — OBJ holds shapes and plain materials | impossible — as out |
| Rigs and skins | impossible — OBJ has no skeleton | impossible — as out |
| Face states | impossible — OBJ has no blend shapes | impossible — as out |
| Clips | impossible — OBJ has no time | impossible — as out |
| Keys on any property | impossible — OBJ has no time | impossible — as out |
| Motion paths | impossible — OBJ has no time | impossible — as out |
| Cameras | impossible — OBJ has no cameras | impossible — as out |
| Lights | impossible — OBJ has no lights | impossible — as out |
| HDRIs and the sky | impossible — OBJ has no environment | impossible — as out |
| Physics bodies and joints | impossible — OBJ has no bodies | impossible — as out |
| Sound and words | impossible — OBJ has no sound | impossible — as out |
| Web objects | impossible — OBJ has no media | impossible — as out |
| Scenes and shots | impossible — one OBJ is one set of shapes | impossible — as out |
| The artist's credit | after 1.0 | after 1.0 |

Not listed: after 1.0

## STL

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | baked — one closed solid in millimetres, Z up | baked — one mesh |
| Units and dimensions | carried | carried |

Not listed: impossible — STL holds triangles and nothing else

## 3MF

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | carried | carried |
| Materials | baked — a colour per part | baked — a colour per part |
| Paint layers and maps | baked — a filament slot per colour | after 1.0 |
| Units and dimensions | carried | carried |
| The artist's credit | after 1.0 | after 1.0 |

Not listed: impossible — 3MF holds printable parts, their colours and the build plate

## PLY

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | after 1.0 | after 1.0 |
| Paint layers and maps | after 1.0 | after 1.0 |
| Units and dimensions | after 1.0 | after 1.0 |

Not listed: impossible — PLY holds points and triangles with their colours

## Collada (.dae)

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | not offered — write glTF, Collada's successor | after 1.0 |
| Materials | not offered — write glTF | after 1.0 |
| Rigs and skins | not offered — write glTF | after 1.0 |
| Clips | not offered — write glTF | after 1.0 |
| Cameras | not offered — write glTF | after 1.0 |
| Lights | not offered — write glTF | after 1.0 |

Not listed: impossible — Collada has no place for it

## IFC

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | after 1.0 | after 1.0 |
| Materials | after 1.0 | after 1.0 |
| Units and dimensions | after 1.0 | after 1.0 |
| The artist's credit | after 1.0 | after 1.0 |

Not listed: impossible — IFC holds buildings, their parts and their spaces

## SVG

| Feature | Out | In |
|---|---|---|
| Ink and flipbooks | after 1.0 | after 1.0 |
| Text and logos | after 1.0 | baked — modelled solids, one a colour, the upper ones proud |
| Units and dimensions | baked — plans full size in millimetres | after 1.0 |

Not listed: impossible — SVG is flat

## DXF

| Feature | Out | In |
|---|---|---|
| Ink and flipbooks | after 1.0 | after 1.0 |
| Units and dimensions | baked — plans full size in millimetres, cut walls on their own layer | baked — lines, arcs and circles as an underlay in their units |

Not listed: impossible — DXF here is flat drawings

## BVH

| Feature | Out | In |
|---|---|---|
| Rigs and skins | after 1.0 | after 1.0 |
| Clips | after 1.0 | after 1.0 |

Not listed: impossible — BVH holds a skeleton's motion only

## VRM

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | after 1.0 | after 1.0 |
| Materials | after 1.0 | after 1.0 |
| Rigs and skins | after 1.0 | after 1.0 |
| Face states | after 1.0 | after 1.0 |
| The artist's credit | after 1.0 | after 1.0 |

Not listed: impossible — VRM holds one avatar

## Alembic (.abc)

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | after 1.0 | not offered — bring caches in as USD or glTF |
| Baked runs | after 1.0 | not offered — as above |
| Cameras | after 1.0 | not offered — as above |

Not listed: impossible — Alembic holds baked geometry and cameras

## STEP / IGES

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | not offered — CAD files are read, not written | after 1.0 |
| Units and dimensions | not offered — as above | after 1.0 |

Not listed: impossible — STEP and IGES hold exact solids

## Blender (the package out, the add-on in)

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | carried | after 1.0 |

Not listed: after 1.0

## Pictures and video (PNG, JPEG, HEIC, EXR, PSD, Lottie, image sequences, MP4, MOV)

| Feature | Out | In |
|---|---|---|
| Sheets | after 1.0 | baked — a layer a sheet, stacked in depth |
| Paint layers and maps | after 1.0 | after 1.0 |
| HDRIs and the sky | impossible — a picture out is the frame | after 1.0 |
| Web objects | after 1.0 | after 1.0 |
| Sound and words | after 1.0 | after 1.0 |
| The artist's credit | after 1.0 | after 1.0 |

Not listed: impossible — a picture or a film is the frame, not the scene
