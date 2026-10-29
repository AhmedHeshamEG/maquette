# Characters

## The cast

- **Blob** (default): `{"do":"blob","likeness":"hesham","name":"Hesham"}` — a round cartoon character with a thick
  stable outline, face decals and springy follow-through. Likenesses: hesham, newton, einstein, turing, curie, darwin,
  tesla, lovelace, edison, sherlock, wizard; or a recipe of 2–3 clues (hat, hair, accessories, prop).
- **Puppet** and **Rigged** characters work through the same verbs (clips, expressions, intents).

## Acting beats

Each line a character speaks or hears is a beat with one clear attitude.

| Beat | Do |
|---|---|
| hears something surprising | `animate(what="react", how="surprised")` on the word; a punch-in on the face |
| realises | `react` with `thinking`, then `happy` 0.5 s later; a slow push in |
| explains | `animate(what="talk")` (lip sync from the transcript) + `Point` toward the subject on its name |
| fails / is sad | `react` with `sad`; camera `pullOut` |
| arrives / leaves | `enter` / `exit` on the word |
| goes somewhere | `walk_to` the thing (it stops in front of it, not inside) |
| notices | `look_at` the thing, then `react` |

Expressions: neutral, happy, laugh, smug, surprised, shocked, scared, sad, angry, sleepy, wink, thinking.
Clips: Idle, Walk, Run, Talk, Wave, Point, Type, Nod, Shrug, Celebrate.

## Rules

- Faces change on words, and they hold. Don't flicker between expressions.
- A character on screen and not acting gets `idle` (it breathes and blinks), never a frozen pose.
- Keep the character's face toward the camera (the report's `facing` is the angle; under 60° reads).
- Exaggerate: `shocked` not `surprised` when the beat is a punchline.
- Lip sync only when the character is the one speaking; narration stays off-screen.

## Make a character (Maquette 0.20)

When none of the cast fits (a creature, a mascot, a thing that comes alive), make one from parts. It rigs itself.

```json
{"do":"character","op":"new","start":"fourLegs","name":"Biscuit","at":[1,0,0]}
```

Starts: `person` (plays every humanoid clip), `fourLegs`, `wings`, `blob`, `nothing` (add parts one by one).

- **The person's own model as the character** (Maquette 0.30): `{"do":"character","op":"adopt","target":"My Robot"}`. The
  thing itself becomes the character, whole, where it stands; it keeps its own rig (rig it with a person's dots in the
  app), and parts added later ride its joints. Prefer this to `new` whenever the person made the model themselves.
- Add parts to a character, or to **any thing** (it becomes the body): `{"do":"character","op":"add","target":"Teapot","part":"arm"}`.
  Parts: head, eye, brow, mouth, nose, ear, hair, body, arm, leg, tail, wing, extra. Paired parts (eyes, brows, ears,
  arms, legs, wings) come as a mirrored pair unless `"symmetric":false`; adding again adds another (a third eye, a second
  pair of arms). On `nothing`, the first eye is one big eye: a bodyless eye creature in two actions (eye, then mouth).
- `"style"` from the part's set (`style` op changes it later): head round/oval/square/bean · eye round/dot/sleepy/big ·
  brow line/thick/arched · mouth oval/grin/beak · nose button/long/snout · ear round/pointy/floppy/cat · hair
  short/spiky/tuft/long/mohawk · body bean/box/pear/round/long · arm tube/noodle/chunky · leg tube/stubby/paw/hoof ·
  tail thin/bushy/fin · wing feather/bat/bug · extra horns/antenna/hat/glasses/bow.
- A drawn or modelled thing becomes a part with `assign` (`"part":"mouth","character":"Biscuit"`); with
  `"state":"oh"` it becomes the drawing shown for that face state.
- Proportions: `{"do":"character","op":"proportion","target":"Biscuit","measure":"legs","by":1.3}` (or `"to"` metres):
  height, head, body, waist, arms, legs. Longer legs keep the feet on the ground.
- Faces: mouths have Character Animator's 14 shapes (neutral, ah, d, ee, f, l, m, oh, r, s, uh, wOo, smile,
  surprised), brows four (neutral, up, angry, sad), eyes open and blink. Lip sync and face capture choose them. Bend one
  with `{"op":"state","target":"Mouth","state":"oh","bend":{"open":1.2,"round":0.8}}` (open, wide, round, smile, lift,
  tilt, close).
- A line without a voice: `{"do":"character","op":"say","target":"Biscuit","line":"Who's a good boy?","at":2}`.
