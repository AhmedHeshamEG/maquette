# The web layer (Maquette 0.28)

What you already write well, HTML, CSS, JavaScript, three.js, Lottie, can go straight into a scene: on a **screen in the
scene** (a card: lit at its edges, the camera walks round it, characters stand in front of it) or **over the frame** (a
title, a lower third, a chart). One verb: `web`.

```json
{"do": "web", "name": "Sales chart", "html": "<!doctype html>…", "width": 1280, "height": 720,
 "at": [0, 1.2, -2], "size": 1.4, "facing": 0, "start": {"word": "growth"}}
{"do": "web", "name": "Lower third", "on": "frame", "html": "<div class=bar>…</div>", "at": [0, -0.7], "size": 2.6}
{"do": "web", "name": "Logo sting", "on": "frame", "lottie": {"v": "5.7.0", "fr": 30, "w": 512, "h": 512, "layers": [...]}}
{"do": "web", "name": "Intro", "file": "intro"}            // a folder already in the project (add_media), its index.html
{"do": "web", "op": "edit", "target": "Sales chart", "html": "…", "duration": 4, "loop": true}
{"do": "web", "op": "list"}
```

`size` is metres tall in the scene, frame units over it (2.6 fills most of the height). `width`/`height` are the page's
CSS pixels: what `innerWidth` and `innerHeight` read. A Lottie brings its own size and length.

## The clock (why it matches the export)

The page runs on Maquette's clock, not the wall's: `performance.now()`, `Date`, `requestAnimationFrame`, `setTimeout`,
`setInterval`, CSS animations and transitions, the Web Animations API, `<video>` and `<audio>` and `Math.random` (seeded)
all read it, and it steps **60 frames a second from the piece's `start`**. Every way to a moment (the stage, scrubbing,
an export) steps through the same frames from frame 0, so what Hesham sees is what the file gets. So:

- **Animate from time**, not from counting frames you think you'll get: `t = performance.now() / 1000`, or a CSS
  animation, or a three.js `Clock`. All of them are exact here.
- `renderer.setAnimationLoop(...)` and `requestAnimationFrame` work as usual; the first round runs at time 0.
- Randomness is the same every run; seed nothing yourself unless you want a different pattern.
- Before `start` a card shows the first frame and an overlay isn't drawn; after `duration` it holds the last frame, or
  loops with `"loop": true`.

## What's there, what isn't

- **No network.** Nothing leaves the iPad: `fetch`, sockets, images and fonts from the web are blocked. Inline what you
  need (data, SVG, base64 images) or bring files in with `add_media` and use `"file"`.
- **three.js 0.170 and its addons come with the app**: `import * as THREE from 'three'` and
  `import { OrbitControls } from 'three/addons/controls/OrbitControls.js'` just work, and so do the usual CDN addresses
  for three (unpkg, jsDelivr, esm.sh, cdnjs, any version): they're swapped for the copy inside. Same for lottie-web 5.12.
- Other libraries (GSAP, D3, Chart.js…) must be inline in the page. GSAP's ticker runs on the clock like everything else.
- WebGL works (three.js draws through it). A transparent page background lets the card's or frame's own show through.
- A piece is drawn at its own pixel size (at most 3840 a side); a 4K film upsamples a 1280 page. Make the page as big
  as it will be seen.

## Taste

- One idea per piece: a chart that grows on the word, a title that types itself, a screen showing the thing the
  narrator names. A web page is not a slide deck.
- Match the project's Look and palette (`read_project` gives them): the same few colours, its fonts if it has them.
- Prefer a real Maquette thing when there is one: `text` for 3D words, `overlay` for marks, `design` for logos and
  letters. Use `web` for what only code does well: data, generative patterns, UI on a screen, an agent's three.js scene.
- `observe` after adding one: the piece takes a moment to draw the first time, so look at a time after its `start`.
