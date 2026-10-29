# Motion design (Maquette 0.23)

Brand loops and title sequences: a logo stood up from an SVG, copies of a thing laid out and rippled, letters that fly
in, one thing's motion driving another's, a thing moving to the music, a shape becoming another, and a loop that meets
itself. Every op is one undo step the person can change on the iPad.

## A logo

```json
{"do":"design","op":"logo","svg":"<svg viewBox='0 0 200 80'>…</svg>","name":"Brand","width":1.2,"depth":0.08,"at":[0,0,0]}
```

- Each fill colour becomes one solid (a group when there are several), upright, facing the front, standing on the
  ground, `width` metres across. Colours drawn later stand a little proud of the ones under them.
- `"file":"media/logo.svg"` reads one already in the project (`add_media`). Strokes, text and pictures inside the SVG
  can't become solids: the report says how many were left out; ask Hesham for a version with outlines.
- The solids are modelled shapes: `model` pushes a face deeper, rounds edges, paints them.

## Fonts

`{"do":"text","text":"STUDIO","font":"fonts/Brand.otf","size":0.5}`: the font must already be in the project
(Hesham brings it in from the text's panel, or `add_media`). Without `font`, `style` picks one of the five built in.

## Letters that animate

```json
{"do":"design","op":"letters","target":"Title","preset":"flyIn","order":"forward","at":{"word":"welcome"},"stagger":0.06,"length":0.6}
```

Presets: `flyIn`, `bounce`, `cascade`, `pop`, `spin`, `typewriter` arrive once and rest; `wave` keeps going (`length`
is one wave). `order`: forward, backward, middle, random. `"preset":"none"` stops them.

## Clones and effects

```json
{"do":"design","op":"clone","target":"Brand","layout":"grid","columns":5,"rows":5,"spacing":1.4}
{"do":"design","op":"effect","target":"Brand","kind":"push","move":[0,0.5,0],"grow":0.2,"field":"ripple","speed":3,"width":1.5,"every":2}
```

- Layouts: `grid` (columns across x, rows deep along z, layers up), `circle` (`count`, `radius`, `facesOut`), `line`
  (`count`, `step`), `path` (`count`, `path` a drawn line, `along`), `placed` (`places`: a list of
  `{"at":[x,y,z],"turn":[degrees],"size":[x,y,z]}` against the thing's own; the first is the thing). A three.js
  `InstancedMesh` comes in as `placed` clones. The thing itself is the first copy; the copies aren't things in the
  outliner and pick as the thing. At most 1000.
- Effects: `random` (each copy shifted, turned, sized by its own amount up to `move`, `turn`, `grow`), `delay` (each copy
  plays the thing's own motion `delay` seconds after the one before: give the thing a bounce or a spin first),
  `push` (moved and grown as much as the field reaches it). Fields: `everywhere`, `sphere` (`centre`, `radius`),
  `ripple` (a ring travelling out at `speed`, `width` wide, a new one `every` seconds). `"clear":true` removes them.
- The `effectStrength` property scales every effect: key it, or link it to a sound.

## Links

```json
{"do":"design","op":"link","target":"Gear B","channel":"turnY","from":"Gear A","fromChannel":"turnY","amount":-0.5}
{"do":"design","op":"link","target":"Brand","channel":"effect","sound":"Music","feature":"beat"}
```

- Channels: moveX, moveY, moveZ, turnX, turnY, turnZ, size (a fraction), glow, opacity, effect, morph, reveal. A thing
  drives through its motion channels (move, turn, size) since its edited place; `delay` makes it wait.
- A sound drives by its `loudness`, `bass` or `beat` (a hit on each beat that falls away). `amount` is the change at
  full strength (by default half a metre, 45°, half as big again, glow 3). A sound linked to `effect` starts the
  effects at nothing, so the ripple comes with the beat. The iPad measures a sound the first time something moves to
  it; until then the link waits.
- `"off":true` (with a `channel` or without) removes the target's links.

## Morph

`{"do":"design","op":"morph","target":"Cube","into":"Ball","at":1,"duration":1}`: the cube becomes the ball's shape and
colour over a second; the ball is hidden (it's the shape to reach). Both must be shapes made in the app (shapes,
modelled solids, logos, drawings, blocky text); a placed Kit model is made editable first, by Hesham.

## Loops

`{"do":"design","op":"loop","close":true}`: reports whether the timeline (or its loop region) loops seamlessly and what
jumps; with `close`, keys that end elsewhere get a last key back where they began and repeats are retimed to fit
(a spin to whole turns, a ripple's `every`, a wave's length). A wiggle or letters flying in once can't loop: say so.
Delayed copies and links that wait play a repeating motion as it repeats, so a closed loop stays closed with them.

## Don't

- Don't clone a thing and then key its copies: they aren't things. Key the thing, or its `effectStrength`.
- Don't stack two ripples on one cloner where one with a bigger `width` reads.
- Exports of 3D files carry the copies where they stand; video exports play everything.
