# Camera

## Shot types (frame_shot) and when

| Type | Use it for | Lens it picks |
|---|---|---|
| extremeWide | where we are; scale | 18 mm |
| wide | the set and who's in it | 24 mm |
| full | a whole character acting | 35 mm |
| medium | most explainer beats: subject and its context | 50 mm |
| closeUp | emotion, a face, a key object | 85 mm |
| extremeCloseUp | the one detail that matters (a dial, an eye) | 100 mm |
| overTheShoulder | a conversation, someone looking at something | 50 mm |
| twoShot | two characters together | 35 mm |
| insert | an object the story turns on | 65 mm |

Compositions: `leftThird` / `rightThird` (default for anything that looks or moves: leave room in front of it),
`center` (symmetry, confrontation, a reveal), `lowAngle` (power, scale), `highAngle` (smallness, overview).

## Lenses, with reasons

- Wider than 24 mm distorts faces; use it for rooms and landscapes.
- 35–50 mm feels like being there: the default.
- 85 mm+ compresses and isolates: emotion and detail. Background falls away.
- Change lens to change feeling, not to fix framing; move the camera to fix framing.

## Moves (camera_move), each with a motivation

- **pushIn** — attention gathers: a realisation, a reveal (1.5–3 s, eased).
- **punchIn** — one word of emphasis (0.2–0.4 s). Rare.
- **snapZoom** — the explainer snap: rush, overshoot, settle (0.35–0.5 s), for punchlines.
- **pullOut** — context: "and it's everywhere".
- **orbit** — a hero moment. Never a constant-speed orbit with nothing else happening.
- **crane** — scale, an opening.
- **dolly / truck** — travel with the action.
- **whipPan** — energy between subjects. **shake** — impact (with an FX).

One move per shot, landing on its word. Holds between moves. The contact sheet flags constant-speed moves.

## Film (0.22): the lens, the frame, focus, rigs

`build` with `{"do":"film", …}`; "camera" defaults to the shot camera.

- **A body and real millimetres**: `{"op":"lens","camera":"Shot","sensor":"super35","mm":32,"aperture":2.8}`. Bodies:
  fullFrame, super35 (cinema), apsC, microFourThirds, super16 (film), phone, largeFormat, imax. The picture is the
  field of view; the body only changes what the millimetres say, so match the lens to the body you name.
- **The frame's shape**: `{"op":"frame","shape":"2.39:1"}` (16:9, 2.39:1, 9:16, 4:5, 1:1). The Director view, Frame
  shot and every export follow it. 2.39 keeps 16:9's width and loses height: frame wider, not tighter.
- **Focus that follows**: `{"op":"focus","on":"Hero"}` keeps a thing sharp as it moves; a second one later is a pull:
  `{"op":"focus","on":"Letter","at":{"word":"letter"}}` (0.8 s, eased). Depth of field needs an aperture (2–4 for a
  shallow look). Pull focus on the word the audience should look at, never twice in a sentence.
- **Rigs** ride on top of any keyed move: `{"op":"rig","kind":"crane","arm":3,"keys":{"lift":[[0,0],[4,2.5]]}}`.
  dolly (`travel`, metres along where it faces), crane (`lift`, `swing`, `arm`; it keeps its subject in frame),
  orbit (`swing`, `lift`, around what it looks at or its focus point), handheld (`shake` 0…1, a person breathing;
  0.2–0.4 for documentary, 0.7+ for panic). `shake` adds to any rig.
- **Shots**: `{"op":"shots"}` lists them as a storyboard would (number, camera, lens, length, the words). Storyboards,
  the animatic, spatial video for Vision Pro, 360° and HDR are exports, made in the app by the person.

## Cuts

Cut on the first word of a new idea (`frame_shot ... on_word`). Straight cuts by default; `dipToBlack` when time passes.
Match shapes across a cut when you can (paper → screen in the same frame position).

## 9:16

`observe(framing="9:16")` when the video is vertical; keep the subject inside the vertical safe zone (the report's
frame cut and tangent notes catch edges).

## Titles that stay on the picture (0.15)

The app has no timeline overlays any more for a person: a title is 3D text that sticks to the camera. Through the
bridge: add the text, then `{"do":"set","target":"Title","property":"sticksToCamera","value":true}`; its position is
then read in the shot camera's frame (`[0, 0, -2]` is two metres straight ahead). Things drawn on a kept sheet carry
`drawnOn` (the sheet's id): moving that sheet in the app moves them with it.
