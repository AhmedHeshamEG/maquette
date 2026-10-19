# Lighting (toon)

Toon lighting is about **value structure**: the subject reads against the world in a squint. Three values — light,
middle, dark — and the subject owns the contrast. `light` places a recipe relative to the shot camera, so "key from
camera left" means the same in every shot. Re-lighting replaces the recipe's lamps.

## Recipes and their reasons

| Recipe | When | What it does |
|---|---|---|
| `three-point` | a character or a product that must read round | soft-panel key camera-left, a dimmer fill camera-right, a spot rim from behind |
| `golden-hour` | the hour before sunset, endings, warmth | the sun very low and warm, a soft warm fill, haze and god rays |
| `neon` | a street at night, after the rain | night mood; a magenta panel and a cyan one from either side; light haze |
| `key-warm-world-cool` | the default story light | warm key on the subject from camera-left-front; the world cool and dimmer |
| `noir-single-source` | mystery, secrets, night | one hard lamp high to the side; deep shadow everywhere else |
| `golden-rim` | warmth, endings, hope, outdoors | low sun behind the subject outlines it in gold; soft warm fill |
| `monitor-glow` | someone at a screen at night | cold glow from below-front; the room near black |
| `moonlit` | calm or eerie night exteriors | blue, soft, from behind-right with a cool rim |
| `studio-soft` | explainers, clean object shots | even soft light from front-left, little shadow |

Overrides: `intensity` (×), `warmth` (−1 cooler … 1 warmer). `moonlit` is "Moonlight" in the app.

## Lights by hand (0.22)

`{"do":"light","type":"panel","name":"Window","at":[2,2,1],"size":[1.2,0.8],"aim":"Hero"}`: a **soft panel** (a
softbox, a window) lights the way it faces and only out of its front; `bulb` (point), `spot`, `sun` as before. Only
the Look's sun casts shadows.

## The air and the sky (0.22)

- Haze and god rays are the Look's: `{"do":"film","op":"air","haze":0.4,"godRays":0.6}` (0 clears). God rays stream
  from the sun past what stands in front of it, so they show when the camera looks toward the sun; haze fades far
  things into the sky's colour and glows on the sun's side.
- An HDRI: `add_media(path, environment=True)` with a Radiance `.hdr`. It shows behind everything and lights the world
  (its sun's direction and colour, its sky). Turn it with `{"do":"film","op":"environment","turn":40}` (the sun turns
  with it); `"off": true` goes back to the mood's sky.

## Check with `observe(views=["value"])`

- The **value** view must show the subject as the strongest light–dark contrast (ΔL* ≥ 25: the Read check).
- The **Light** check: the subject brighter than the world; not drowned in shadow; the silhouette separated (≥ 50% of
  its outline stands out). A rim (golden-rim, moonlit) fixes a merging silhouette.

## Fixes

- Subject merges with the background → darken the world (mood `night`/`dusk`, fog, a darker wall swatch) or light the
  subject (`key-warm-world-cool`, intensity 1.3).
- Everything the same brightness → a recipe with a single source; turn the sun down (noir, monitor-glow).
- Glow everywhere → glow belongs to one thing (a screen, the accent); remove the rest.
