# Interop: what every format carries (X1)

Every Maquette feature against every format, both ways. A cell says one of:

- **carried**: it arrives as itself (a round trip, or the other side's own reader, proves it);
- **baked**: it goes out as keys, textures or geometry (the cell says what), and doesn't come back as itself;
- **extras**: it rides in the file's own extras, so it survives a round trip through Maquette only;
- **impossible**: the format has no place for it (the cell says why);
- **not offered**: a direction this format deliberately doesn't take (the cell says what to use);
- **todo**: X1 hasn't reached it yet. The phase is done when no `todo` is left.

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
| Modelling steps | todo | todo |
| Paint layers and maps | baked — every map as a texture (colour, metallic-roughness, glow, normal) | todo |
| Materials | carried | carried |
| The Looks | impossible — glTF holds surfaces, not a picture's style (the three.js folder and the engine shaders carry it) | impossible — as out |
| Ink and flipbooks | todo | todo |
| Sheets | todo | todo |
| Rigs and skins | carried | todo |
| Face states | extras | extras |
| Clips | todo | todo |
| Keys on any property | carried | carried |
| Motion paths | todo | todo |
| Cameras | todo — the lens is carried, focus and aperture aren't yet | todo |
| Lights | carried | carried |
| HDRIs and the sky | todo | todo |
| Physics bodies and joints | todo | todo |
| Baked runs | todo | todo |
| Clones and links | todo | todo |
| Text and logos | todo | todo |
| Sound and words | todo | todo |
| Web objects | todo | todo |
| Scenes and shots | todo | todo |
| Units and dimensions | carried | carried |
| The artist's credit | todo | todo |

## three.js folder (Export ▸ 3D ▸ three.js)

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | carried | todo |
| Materials | carried | todo |
| The Looks | baked — toon bands, ink lines, halftone and pixel passes in `maquette/look.js`; the paint Looks as toon bands and lines | todo |
| Keys on any property | carried | todo |
| Cameras | carried | todo |
| Lights | carried | todo |
| Scenes and shots | carried | todo |

Not listed: todo

## three.js JSON (`scene.toJSON()`, `ObjectLoader`)

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | carried | carried |
| Materials | carried | carried |
| Clones and links | todo | baked — an instanced mesh becomes a thing a copy |
| Keys on any property | carried | carried |
| Cameras | carried | carried |
| Lights | carried | carried |

Not listed: todo

## USD / USDZ

| Feature | Out | In |
|---|---|---|
| Paint layers and maps | baked — colour, roughness, metal, glow and normal as textures | todo |

Not listed: todo

## FBX

| Feature | Out | In |
|---|---|---|
| Rigs and skins | carried | todo |

Not listed: todo

## OBJ / MTL

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | baked — world-space meshes, a group a thing | todo |
| Materials | baked — colour in the MTL | todo |
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
| The artist's credit | todo | todo |

Not listed: todo

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
| Paint layers and maps | baked — a filament slot per colour | todo |
| Units and dimensions | carried | carried |
| The artist's credit | todo | todo |

Not listed: impossible — 3MF holds printable parts, their colours and the build plate

## PLY

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | todo | todo |
| Paint layers and maps | todo | todo |
| Units and dimensions | todo | todo |

Not listed: impossible — PLY holds points and triangles with their colours

## Collada (.dae)

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | not offered — write glTF, Collada's successor | todo |
| Materials | not offered — write glTF | todo |
| Rigs and skins | not offered — write glTF | todo |
| Clips | not offered — write glTF | todo |
| Cameras | not offered — write glTF | todo |
| Lights | not offered — write glTF | todo |

Not listed: impossible — Collada has no place for it

## IFC

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | todo | todo |
| Materials | todo | todo |
| Units and dimensions | todo | todo |
| The artist's credit | todo | todo |

Not listed: impossible — IFC holds buildings, their parts and their spaces

## SVG

| Feature | Out | In |
|---|---|---|
| Ink and flipbooks | todo | todo |
| Text and logos | todo | baked — modelled solids, one a colour, the upper ones proud |
| Units and dimensions | baked — plans full size in millimetres | todo |

Not listed: impossible — SVG is flat

## DXF

| Feature | Out | In |
|---|---|---|
| Ink and flipbooks | todo | todo |
| Units and dimensions | baked — plans full size in millimetres, cut walls on their own layer | baked — lines, arcs and circles as an underlay in their units |

Not listed: impossible — DXF here is flat drawings

## BVH

| Feature | Out | In |
|---|---|---|
| Rigs and skins | todo | todo |
| Clips | todo | todo |

Not listed: impossible — BVH holds a skeleton's motion only

## VRM

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | todo | todo |
| Materials | todo | todo |
| Rigs and skins | todo | todo |
| Face states | todo | todo |
| The artist's credit | todo | todo |

Not listed: impossible — VRM holds one avatar

## Alembic (.abc)

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | todo | not offered — bring caches in as USD or glTF |
| Baked runs | todo | not offered — as above |
| Cameras | todo | not offered — as above |

Not listed: impossible — Alembic holds baked geometry and cameras

## STEP / IGES

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | not offered — CAD files are read, not written | todo |
| Units and dimensions | not offered — as above | todo |

Not listed: impossible — STEP and IGES hold exact solids

## Blender (the package out, the add-on in)

| Feature | Out | In |
|---|---|---|
| Meshes and hierarchy | carried | todo |

Not listed: todo

## Pictures and video (PNG, JPEG, HEIC, EXR, PSD, Lottie, image sequences, MP4, MOV)

| Feature | Out | In |
|---|---|---|
| Sheets | todo | baked — a layer a sheet, stacked in depth |
| Paint layers and maps | todo | todo |
| HDRIs and the sky | impossible — a picture out is the frame | todo |
| Web objects | todo | todo |
| Sound and words | todo | todo |
| The artist's credit | todo | todo |

Not listed: impossible — a picture or a film is the frame, not the scene
