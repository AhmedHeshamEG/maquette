# Set building — the theater-set rule

Build only what the lens sees, from the Kit, placed by relation, at real size.

## Order

1. **Decide the frame first** (shot type and where the camera is). Everything outside it doesn't exist.
2. `find_assets` for the 3–7 things the shot needs, by plain words ("desk", "desk lamp", "old radio", "bookcase").
   Use each result's `id` in `add`; its `size` is real metres, `surfaces` are the heights you can put things `on`.
3. One `build` with the hero piece first, then everything relative to it:

```json
[{"do":"add","asset":"kit.office-desk","name":"Desk","at":[0,0,0]},
 {"do":"add","asset":"kit.room-lamproundtable","name":"Lamp","relation":"on","reference":"Desk","offset":[-0.45,0,-0.1]},
 {"do":"add","asset":"kit.room-books","name":"Books","relation":"on","reference":"Desk","offset":[0.5,0,-0.1]},
 {"do":"add","asset":"kit.room-bookcaseopen","name":"Bookcase","relation":"beside_left","reference":"Desk"},
 {"do":"add","shape":"cube","name":"Wall","at":[0,0,-1.2],"size":[6,3,0.1],"color":"palette:1"}]
```

4. `observe` with `top`: the diagram shows where everything stands and where the camera looks from.

## Relations

`on` (top surface; picks a free spot; faces the reference's front) · `beside_left` / `beside_right` (as seen from the
reference's front) · `in_front_of` · `behind` · `above` (in the air on purpose) · `under` · `inside` · `facing` ·
`around` (radius) · `row` (spacing) · `grid` (columns, spacing) · `scatter_in` (seed) · `stack`.
`offset` nudges in the reference's frame: x right, y up, z toward its front.

## Scale

Kit models arrive at real size. `scaleTo` only when the story needs a different size ("the tree is 6 m") or a stand-in
must match a real object (an old radio standing in for an Enigma machine: `{"do":"scaleTo","target":"Enigma","meters":0.26}`).
The Scale check fails beyond half or double a model's real size.

## Walls, floors, skies

Big flat primitives in palette colours are fine for walls and floors (they're the set, not props). Hide the ground
(`look` / the project setting) inside rooms. Fog sells depth outdoors.

## Groups of things

A room of computers is one desk and one screen arrayed (`array`, `row`, `grid`), not twelve hand placements. Copies
read as one pattern; they don't count as clutter.

## Shaping a thing (Maquette 0.16)

When no Kit model fits, shape one from a blockout with `model` (one thing, one op per action; the script stays one step).
Faces are named by the way they face, edges by the axis they run along:

- Taller, thicker: `{"do":"model","target":"Plinth","op":"pull","face":"top","distance":0.3}`; exact sides:
  `{"op":"size","axis":"y","length":0.04}`.
- Softer: `{"op":"smooth","levels":2}` (a pebble from a cube); crisp edges with `{"op":"smoothAngle","degrees":40}`.
- More lines to bend or pull: `{"op":"loopCut","along":"x","cuts":2}`; a cut where you want it: `{"op":"knife","point":[…],"normal":[…]}`.
- Character in a prop: `{"op":"bend","kind":"bend|twist|taper|bulge","amount":45,"axis":"y"}`. The amount keys like any
  property, so a tower can twist on a word.
- Bulges and dents: `{"op":"cage","counts":[3,3,3]}` then pull a point `{"op":"cage","point":[2,2,2],"offset":[0.2,0,0]}`,
  or one brush dab `{"op":"brush","brush":"inflate","at":[x,y,z],"radius":0.2}`.
- A row of the same thing that changes together: `{"op":"linkedCopy","offset":[1.2,0,0]}`.
- A sculpt for a game: `{"op":"cleanUp","faces":2000}` (even quads; it bakes everything in).
- From a sketch region: `{"do":"profile","target":"Sketch","op":"revolve","axis":{"point":[0,0,0],"direction":[0,1,0]}}`
  (a vase), `"sweep"` with a `"path"` (a rail), `"loft"` `"through"` other sketches (a hull).
- Change your mind later (0.17): `{"do":"model","target":"Plinth","op":"steps"}` lists its modelling steps and their
  numbers in the reply; `{"op":"step","step":1,"number":"distance","value":0.5}` changes one and the steps after it
  follow. Prefer this to pulling again: the rounds and holes made after it stay where they belong. A step listed as
  fixed (changed by hand, painted or rigged) can't change; say so to Hesham rather than rebuilding it.

Shape the hero prop only; the set itself is still Kit models placed by relation.

## Don't

- Don't build greybox sets from cubes when a Kit model exists.
- Don't fill the frame. ≤ 7 significant things; empty space frames the subject.
- Don't place by coordinates and hope: anything floating or sunk fails Ground.
