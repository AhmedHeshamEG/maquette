# Guest kits (Maquette 0.25)

The guests' jobs: a building for an architect, parts for a 3D printer, an assembly for a mechanics report, a level for a
game. Each op is one undo step the person can change on the iPad. The person picks the set-up (Scene ▸ Set up for:
Room, Print, Game, Study); the verbs work in any set-up. Files (IFC, plans, 3MF, technical drawings, levels, papercraft)
are exported on the iPad: where a file goes is the person's.

## Room

```json
{"do":"add","shape":"cube","name":"Walls","at":[0,0,0],"size":[8,2.7,5]}
{"do":"guest","op":"roof","kind":"gable","over":"Walls","pitch":30}
{"do":"guest","op":"column","at":[4,0,2.5],"shape":"round"}
{"do":"guest","op":"beam","from":[0,2.7,2.5],"to":[8,2.7,2.5]}
{"do":"guest","op":"railing","path":[[0,0,6],[8,0,6]]}
{"do":"guest","op":"person","at":[2,0,4],"yaw":30}
{"do":"guest","op":"terrain","width":40,"hills":1.5,"at":[4,-0.01,2.5]}
{"do":"guest","op":"label","text":"Kitchen","at":[2,0,2]}
```

- Roofs: `gable`, `hip` (over the outline's smallest rectangle: an L-shaped house takes two), `shed`, `flat` (any
  outline). `over` covers a thing's box at its top; `outline` takes corners `[[x,y,z],…]` at the walls' top.
- Everything is tagged with its part of the building (wall, slab, roof, stairs, column, beam, railing): plans and IFC read
  it. Real walls come from the app's Walls tool; a cube named "Walls" is fine for a quick massing.
- A `label` lying in a room names it on the plans, which write each room's area under its name.
- People are flat 1.75 m cut-outs for scale; they stay out of IFC.

## Print

```json
{"do":"guest","op":"print","piece":"jar","at":[0,0,0]}
{"do":"guest","op":"print","piece":"bolt","screw":"M6"}
{"do":"guest","op":"hole","target":"Box","screw":"M3","kind":"insert","face":"top"}
{"do":"guest","op":"engrave","target":"Lid","text":"GIULIA","face":"top","size":0.006}
{"do":"guest","op":"split","target":"Helmet","axis":"y","at":0.12,"pegs":true}
{"do":"guest","op":"hollow","target":"Bust","wall":0.002}
{"do":"guest","op":"orient","target":"Bracket"}
{"do":"guest","op":"scale","target":"Box","size":0.1,"axis":"x"}
```

- Sizes are metres: 6 mm is `0.006`. Screws are ISO `M2`…`M10`; hole kinds `clearance`, `counterbore`, `tapped` (for a
  tap or a self-tapping screw), `threaded` (printed; good from M5 up), `insert` (heat-set brass).
- A hole or words go at the middle of the face that faces `face` (`top`, `bottom`, `front`, `back`, `left`, `right`), or
  at `"at":[x,y,z]` on it.
- `jar` makes the jar and its screw-on lid, the lid upside down beside it; `tolerance` (0.0002 a side) is the fit.
- Only shapes made here can be cut; a placed Kit model needs Make editable in the app first.

## Study

`{"do":"guest","op":"explode","target":"Gearbox"}` pulls a group's parts apart (again: back together). The amount is
`explode` on the group (0…1), so it can be keyed: `{"do":"keys","target":"Gearbox","property":"explode",…}`. Group parts
first with `{"do":"group","target":["Base","Gear*"],"name":"Gearbox"}`. Make parts real (`physics`) to give the technical
drawing their material and mass.

## Game

```json
{"do":"guest","op":"greybox","piece":"floor","at":[0,0,0]}
{"do":"guest","op":"greybox","piece":"ramp","at":[4,0,0]}
{"do":"guest","op":"freeze","targets":"Level*"}
```

Pieces: `floor` (4 × 4), `tile` (2 × 2), `wall`, `doorway`, `window`, `ramp`, `stairs`, `block`, `pillar`; they land on
whole metres. Turn them by quarter turns (`rotation`).

## For illustrators

`{"do":"character","op":"new","start":"mannequin","name":"Pose"}`: a faceless wooden person that rigs itself; pose it like
any character, light it, and the person exports a layered PSD.
