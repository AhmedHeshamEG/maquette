# The Looks

A Look is the whole drawing style: line, shading, paint, texture and frame rate. Set it per project, per scene
(`{"do":"look","look":"painterly"}`, `"sceneOnly":true`), or per object (`"perObject":{"Robot":"sketch"}`: one thing drawn
differently on purpose). Names in any case (`lowpoly` works).

| Look | Use it for | References, and why |
|---|---|---|
| **Ink** (house default) | stories, explainers, anything with characters | *Hilda* and Cartoon Saloon (clean confident lines, flat shapes, warm/cool light that does the storytelling) |
| **Comic** | action beats, punchlines, energy; on twos | *Spider-Verse* (stepped motion, bold shadows, halftone as texture not decoration) |
| **Sketch** | memory, quiet moments, "the secret"; one accent colour | storyboards and pencil animatics; *Klaus*'s restraint with colour |
| **Painterly** | a world with weight: dusk streets, myth, drama | *Arcane*, *Puss in Boots: The Last Wish* (strokes that follow the forms, coloured shadows) |
| **Watercolour** | gentle stories, nature, childhood | picture books; washes that pool at their edges, the paper showing through, cool shadows |
| **Gouache** | warm, matte, storybook places | mid-century illustration (opaque flat strokes, chalky colour, the paper's tooth) |
| **Paperman** | romance, nostalgia, a single coloured detail | *Paperman* (soft filmic black and white, thin clean ink, one accent in colour) |
| **Anime cel** | characters, action, slice of life; on twos | TV anime cels (two hard tones, a lavender shadow, a hard rim, lines in each thing's own colour) |
| **Clay** | soft, playful, kids' explainers | Aardman (tactile, rounded) |
| **Clean product** | products, objects, architecture models | studio product shots (soft light, soft shadows, lacquer mirroring the room, no lines) |
| **Low-poly** | tech, data, games, abstract explainers | faceted indie games: geometry as the style |
| **Pixel** | games, retro, a 16-bit flashback; on twos | pixel art (square blocks, a few colours, a one-pixel line); the blocks follow the frame's height, so exports match the stage |

## The Finish, on any Look

`{"do":"look","finish":{"benDay":0.6,"boil":0.4,"misregistration":true,"texture":"newsprint","textureStrength":0.7}}`:
Ben-Day dots print flat colour as dots; boil makes lines tremble on twos; misregistration turns the camera's depth of field
into slipped colour plates (it needs an aperture on the camera); textures are paper, collage, film, newsprint, riso, canvas.

## Grounds

`{"do":"look","ground":"snow"}`: desert, grass, snow, rock, sand, pavement, waterEdge, roomFloor (a 12 m room), or plain.
The ground's colour follows the choice; change it after with the World if the palette needs it.

## Drawn effects

`{"do":"effect","kind":"impact|focusLines|comicDots","at":{"word":"Boom"},"target":"Hero"}`: an impact frame (two tones that
flip each drawing, a burst from the hit), focus lines closing in on the thing, Comic dots crackling round it. They follow
the target as it moves (or `"center":[0.5,0.4]` from the top left). One per beat, at most: they're punctuation.

## A drawing from Procreate or Photoshop

`add_media(path, drawing=True)` stands a layered PSD, PSB or `.procreate` file up as a diorama: one thin painted sheet a
layer, the bottom layer at the back, groups kept. Pin and rig the sheets afterwards; frame them with a slow push in.

## Choosing

- One Look per scene; change it when the story changes register, and say why in the shot list.
- Comic, Anime cel and Pixel want twos; Sketch and Paperman want one accent (`accent: true` on the one thing) and stillness;
  Ink and Painterly want a warm/cool light split; Watercolour wants light values (dark washes get muddy).
- Per-object Looks are a spotlight: a Sketch flashback object inside an Ink scene, a Comic impact object.

## Rejected

- Speed-line backgrounds behind every action, sparkle eyes, sweat drops on every line: they flatten every beat into the
  same intensity. Drawn effects are rare punctuation.
- Glowing bloom on everything, lens flares, heavy chromatic aberration: they hide value structure.
