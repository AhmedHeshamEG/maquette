# The app around the scene (Maquette 0.28)

Most of what you do changes the work and lands as one Proposal (one undo step). Some of what a person does changes how
they **see** it instead: the tool in their hand, a panel, playing, presenting, an export, the AR view. Those are
`{"do": "app", "op": …}` asks. They ride in the same `build` after its edits, in order, and are never undone (there is
nothing to undo).

| op | value | does |
|---|---|---|
| `tool` | model, draw, rig, animate, look, lasso, move, turn, size, precision, shapeByTouch, brushTheSurface, cage, bend, scatter, shadowBrush, flipbook | puts it in the hand (or opens its panel) |
| `panel` | actions, look, library, scene, model, rig, export, history, board, learn, settings, phone, audio, transcript, scripts, bridge, plans, matchPhoto, characterBuilder, gameExport, timelineSettings, lensAndFrame | opens it |
| `closePanel` | | closes what's open |
| `play`, `pause`, `playhead` | seconds (playhead) | the transport |
| `undo`, `redo` | | his last step (or yours), like Edit ▸ Undo |
| `present`, `stopPresenting` | film, walk, model | Present mode |
| `notes`, `timeline`, `directorView`, `hideInterface`, `fly` | true / false | shows or hides |
| `frameSelection` | a name (optional) | the view frames it |
| `show` | ghosts, forces, overhangs, dopeSheet (+ `"on"`) | a view aid |
| `select` | a name, a list of names, all, similar, none | the selection |
| `export` | film, vertical, still, gif, glb, usdz, obj, stl, 3mf, blender, fbx, or any export preset id | an export into the project's renders; fetch it from `/v1/renders` |
| `ar` | true / false | the AR view on the iPad (the scene in the room, in its own Look) |
| `monitor` | | a Monitor window |

```json
{"do": "app", "op": "export", "value": "usdz"}
{"do": "app", "op": "present", "value": "film"}
{"do": "app", "op": "playhead", "value": 3.2}
```

## Rules

- **Don't move his hands.** Change the tool, panel or selection only when he asked for it ("open the Look panel", "get
  me ready to draw on the roof"). Never as a side effect of building.
- **Exports take time.** Ask for one, then tell him it's running; the file is in the project's renders when it's done
  (`/v1/renders`). One at a time.
- **AR is his.** Open the AR view only when he asks; it uses the iPad's camera. For someone else's phone, export `usdz`:
  AR Quick Look opens it on any iPhone or iPad without the app.
- Present and the Monitor window are for showing someone the film: ask before you start presenting.
