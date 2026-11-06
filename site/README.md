# The site

`https://ahmedheshameg.github.io/maquette/`, published by `.github/workflows/pages.yml` whenever `site/` changes on main.

One page. The scroll flies a camera through one world: the Keeper's Tower (rebuilt from `KeepersTowerSample`'s script)
with the eleven stops around it, made from Kit models (CC0, Kenney) and drawn in Maquette's own Ink Look
(`maquette/look.js`, from the app's three.js export). With reduced motion or no WebGL it shows `img/still.jpg`.

- **The bar:** `data-raised` on `.goal` in `index.html`, all-time dollars (Patreon + GitHub Sponsors). Change it with the
  monthly post.
- **The App Store link:** every "Get it free" points to the latest release until the store link exists; swap the two
  `releases/latest` links here and the two in the README.
- **Try it locally:** `python -m http.server --directory site`, then open `http://localhost:8000`. `?s=3` holds the
  camera on a stop, `?bare` hides the page (that's how `img/still.jpg` and `img/preview.jpg` were made).
