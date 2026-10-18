# Motion (Maquette 0.21)

A thing follows a path at the line's own timing, faces the way it goes and leans into its turns; a character turns its
head to watch something; a hand picks a cup up and hands it on. Each action is one undo step, and every one of them
is ordinary keys or a hold on the timeline, so the person can change it afterwards on the iPad.

## A path

```json
{"do":"motion","op":"path","target":"Car","points":[[0,0,0],[3,0,2],[6,0,0]],"times":[0,1.2,2],"at":1}
```

- `points` are where the thing's pivot goes, in metres. Put them at its height above the ground (a car's pivot is at its
  base: y 0; a bird's in the air).
- `times` are seconds from the first point: the speed of the line. Without them, `"speed"` (m/s, 1.5 by default) or a
  `"duration"` for the whole line, at a steady pace.
- `at` is when it starts (a time, a word, a marker). Keys already in that stretch go; the timeline grows to hold it.
- It turns to face the way it goes and leans into turns by itself (`"facesTheWay":false`, `"banks":false` to stop it).
  Characters stay upright and lean only like a runner.
- Many points close together read as a curve: give a turn five or six points, not two.

After it: `{"do":"motion","op":"timing","target":"Car","duration":3}` stretches or squeezes the whole motion;
`{"op":"evenSpeed","target":"Car"}` makes the pace steady along the same path; `{"op":"front","target":"Car","quarterTurns":1}`
turns a model whose front isn't +Z.

## Following a drawn line

`{"do":"motion","op":"follow","target":"Bee","path":"Flight line","duration":4,"loop":true}` for a line the person drew.

## Looking

- `{"do":"motion","op":"lookAt","target":"Ada","at":"Ball"}`: Ada watches the ball for the whole shot (a character turns
  its head, up to the neck's reach; anything else turns whole; a camera points its lens).
- `{"op":"lookAt","target":"Ada","at":"Door","from":{"word":"knock"}}`: from that moment she looks at the door, turning
  over a quarter of a second. `"at":"nothing"` stops looking.

## Holding

- `{"do":"motion","op":"pickUp","target":"Cup","by":"Ada","at":2}`: from 2 s the cup rides Ada as it sat at that moment.
  A rigged character holds by a joint: `"joint":"rightHand"` (a made character's hand is its own part: name the part).
- The same op again with another `by` is a hand-off. `{"op":"putDown","target":"Cup","at":5}` leaves it where the hand
  had it. `{"op":"letGo","target":"Cup"}` takes every hold away.
- Move the hand to where the cup is before the pick-up moment (it doesn't jump: it's taken as it sits).

## Don't

- Don't key position over a held stretch: the hold wins until it's put down.
- Don't draw a path for a walk on the spot: play a clip (`modules/characters.md`), then give the character a path for
  where it goes.
- Exports of 3D files bake holds, looks and behaviours into keys; video exports play them as they are.
