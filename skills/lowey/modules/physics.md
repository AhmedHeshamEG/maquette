# Physics (Maquette 0.19)

Real things move when the timeline plays: they fall, collide, hang from joints, flop, drape, break, get blown about.
The run is worked out on the iPad and plays from there; the stage and the export always agree. Use it when the shot is
about weight: a thing dropped, knocked over, swinging, pouring. Animate by hand when the motion is acted.

## Make things real

```json
{"do":"physics","op":"real","target":"Crate","material":"wood"}
```

Materials, in words: wood, steel, aluminium, stone, concrete, glass, ice, plastic, rubber, foam, cardboard, cloth, jelly.
The mass is the material times the thing's real size (a 1 m wood cube weighs 700 kg); grip and bounce come from the
material. Glass and ice break when knocked hard; cloth drapes; jelly wobbles; a rigged character becomes a ragdoll.

- `"motion"`: `falls` (default), `stays` (a floor, stairs, a table), `follows` (moves by its keys and pushes what it
  meets: a paddle, a door you animate).
- Numbers only when the shot needs them: `"mass"` kg, `"bounce"` 0…1, `"friction"` 0…1, `"speed":[x,y,z]` m/s at the
  start (a throw), `"spin"`, `"breaks":true`, cloth `"hangs":true` (a flag, a curtain).
- Make the set real too: the floor or table it lands on `"motion":"stays"`. The ground at y = 0 is solid already.

## The scene

`{"do":"physics","op":"scene","gravity":"moon","wind":{"speed":6,"heading":90},"start":0.5}`: gravity earth, moon, mars,
jupiter or none (floating); wind heading is where it blows toward (0 = north, -Z; 90 = east, +X);
`start` holds everything still until that second (say it, then drop it).

## Mechanisms

`{"do":"physics","op":"joint","kind":"hinge","first":"Door","second":"Frame","anchor":[0.4,1,0],"axis":[0,1,0],"limits":[0,110]}`

hinge (a door, a wheel; `"motor"` in °/s turns it), slider (a drawer; `"motor"` m/s), ball (a pendulum), glue, spring
(`"to"` the other point, `"springiness"` bounces a second), rope (`"length"`), gear (`"gears":[hingeA, hingeB]`,
`"ratio"`). Without `second` the joint holds it to the world.

## Forces and fluids

- `{"do":"physics","op":"force","kind":"fan","at":[2,1,0],"aim":[-1,0,0],"strength":8}`; `pull` (negative pushes),
  `whirl`.
- `{"do":"physics","op":"fluid","kind":"pour","at":[0,0.35,0],"amount":0.3,"duration":3}` above a glass fills it;
  `splash` (litres let go at once), `smoke`, `fire`. Small scale: a box up to 4 m.

## After the run

- `{"do":"physics","op":"keep"}` turns the run into keys (the things then follow them): do this before hand-tweaking.
- `{"do":"physics","op":"settle","target":"Rock"}` lays a thing on its natural resting face.
- `{"do":"physics","op":"stand","target":"Tower"}` answers whether it stands (its centre of mass over its footprint).

## The real sun

`{"do":"physics","op":"sun","place":"Rome","date":"2026-06-21","hour":15}`; `"study":[7,19]` runs the day across the
timeline (a shadow study); `"north"` turns the compass on the grid; `"latitude"`/`"longitude"`/`"utcOffset"` for any place.

## Don't

- Don't make the whole set real: only what moves and what it touches.
- Don't hand-key something that's real; Keep it first.
- Don't use physics for an acted move; a character that walks is animated, one that trips can be real for the fall.
