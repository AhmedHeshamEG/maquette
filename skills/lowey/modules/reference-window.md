# The Reference window (Maquette 0.27)

A small window floating over the stage, like Procreate's Reference: it's how the person sees their work while they
make it, not part of the project, so it isn't a proposal and there's nothing to undo. It shows one of three things:

- **canvas**: the whole scene, live, from the window's own camera (to see the whole while working up close);
- **image**: a picture to work from (send it with `add_media(path, reference=True)`, which shows it at once);
- **face**: the iPad's front camera, for drawing expressions (the person allows the camera the first time).

```json
{"do":"reference","op":"open","mode":"canvas"}
{"do":"reference","op":"mode","mode":"face"}
{"do":"reference","op":"image","image":"references/….png"}
{"do":"reference","op":"frame"}
{"do":"reference","op":"close"}
```

- `open` brings it back where and as big as the person left it; `mode` alone switches it (it opens if closed).
- `image` names a picture already in the project: the name `add_media(…, reference=True)` replied with.
- `frame` makes Canvas show the whole scene again, from where the stage looks now (after things were added far away).
- Open it when it helps the person, say so in one line, and don't move it around: its place and size are theirs.
- Pictures for the scene itself (a card in the world, an overlay) are `add_media` without `reference`.
