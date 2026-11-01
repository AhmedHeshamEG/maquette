# Cinematography: the language, and what each word does in Maquette

You can't see the scene. Read it, fix it in words, then shoot it. Every term below maps to a verb, a property or a
tool; where a term is a habit rather than a button, the habit is written out.

## Bringing a finished scene in

If the scene already exists somewhere (three.js, Blender, a glTF), **don't rebuild it from cubes**: `import_scene`
with the file. A three.js `scene.toJSON()` arrives as meshes, materials, lights, cameras and its animation clips as
keys; a three.js project (folder, zip, page) is played offline and 10 s of its motion recorded; a GLB lands in the
library and stands where the file put it. For a long film, export `scene.toJSON()` with the camera's samples written
as an AnimationClip, not the project. Then `scene_graph` to see what came in, and set the Look.

## Spatial awareness

| Term | In Maquette |
|---|---|
| the scene graph | `scene_graph`: every thing by name, world position (a shape's or model's **bottom** middle), turn, box, parent, what it stands on, shown or not |
| the space, fixed in writing | metres; y up, the ground y = 0; the audience at +z looking toward −z; x right. Say it in the shot list |
| floor plan / set plan | `observe` with `views=["top"]`: the objects, the camera and its wedge from above |
| sightlines, occlusion | the rubric's **Camera** line: the camera inside a solid, an empty frame, the subject hidden behind something |
| clearance | keep the camera out of solids; `scene_graph` boxes tell you where they are |
| staging / blocking | move things for a clean path (`place` by relation, `transform`), not only the camera around them |
| marks | `{"do":"mark","name":"Plate","at":[…],"radius":0.05}` or `"on":"Plate 3"` (rides with it). Aim, frame and focus at marks, never loose numbers |
| depth staging, dirty frame | put something near the lens (foreground), the subject mid, the world behind; `place` `in_front_of` the camera's line |

## Camera language

| Term | In Maquette |
|---|---|
| a lens on a full-frame body | `{"do":"film","op":"lens","mm":50,"sensor":"fullFrame","aperture":2}`; 18/24 wide, 35/50 normal, 85/100 macro |
| shot sizes ECU … EWS | `frame_shot` types: extremeCloseUp, closeUp, medium, full, wide, extremeWide (+ insert, overTheShoulder, twoShot) |
| the framing solver | `frame_shot(subject, shot_type, composition, lens)`: subject can be a mark; composition leftThird/rightThird/center |
| a zoom | keys on `focalLength` (millimetres; converted) or `fov`: `{"do":"keys","target":"Cam","property":"focalLength","keys":[…]}` |
| a look-at target | `{"do":"camera","watch":"Plate"}`; to move what it looks at, key the **mark**, never the camera's angles |
| moves | `camera_move`: pushIn, pullOut, dolly/truck, crane, orbit, reveal; one per shot, motivated, eased |
| rigs | `{"do":"film","op":"rig","kind":"dolly|crane|orbit|handheld",…,"keys":{…}}` |
| organic drift | `"drift": 0.3` on the camera (or the rig op, keyable): a slow sway sized to the focus distance |
| rack focus, focus follows the voice | `{"do":"film","op":"focus","on":"Plate","at":{"word":"this"}}`; aperture and focusDistance key too |
| cuts, dissolves, dip to black | `cut` with transition cut / fade / dipToBlack / wipe / zoomThrough, on a word |
| showing a thing only in its shots | `{"do":"show","target":"Phone","shots":["Close on the phone"]}` or `"during":[[0,12]]` |

## Look development: the Real Look

The stylised Looks are drawings. **Real** is a camera's picture: `{"do":"look","look":"real"}`.

- **Low-key**: a dark mood (`darkStudio`, `night`), then practicals: spots with `cone`, `penumbra` (softness),
  `intensity`, `range`, `shadows` (on by default in Real), aimed at marks; soft panels for windows and light tables.
  Most of the frame near black; the lamps carve the subject.
- **Surfaces**: `set` roughness, metallic, clearcoat + clearcoatRoughness (enamel, bakelite), transmission + ior
  (glass, a loupe), `glow` only on the one thing that glows. `paint` op material (oak, floorboards, marble, brick,
  steel, gold…) gives shapes texture; on a placed Kit model it sets the material whole.
- **Light**: falls with the square of the distance; a lamp's reflection is the lamp's size; the sky (or an HDRI) is
  in every glossy surface.
- **Post** by numbers: `{"do":"look","post":{"exposure":-0.3,"bloom":0.2,"halation":0.3,"vignette":0.3,"grain":0.15,
  "fringing":0.1,"toneCurve":"filmic"}}`. Bloom takes only what's past white. Depth of field comes from the lens's
  aperture and the focus mark; haze and god rays are `{"do":"film","op":"air","haze":0.3,"godRays":0.5}`.
- **A picture's true colours** (a chart, a spectrogram, a screen): `set` `unlit` true on its card.

## Motion

Spacing matters more than timing: ease in and out, overshoot and settle (`animate` intents, key easing), holds
between moves. Every property is a function of time, so any frame renders alone: key states, don't simulate them.
Cut on action and on spoken words (`{"word": …}` everywhere a time goes).
