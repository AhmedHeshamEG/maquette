import Foundation

extension ThreeProjectScripts {
    /// The Look in three.js (X1): toon bands as `MeshToonMaterial` with a gradient made from the Look's bands, threshold
    /// and softness; ink lines as `OutlineEffect` at the Look's width; halftone and pixel art as passes. The paint Looks
    /// and paper are their nearest real-time pass (toon bands and lines), as `docs/INTEROP.md` says.
    static let lookJS = """
    // Made with Maquette: the scene's Look, rebuilt from its numbers in maquette/scene.js. Use it in anything,
    // commercial included (LICENSE.txt).
    import * as THREE from 'three';
    import { OutlineEffect } from 'three/addons/effects/OutlineEffect.js';
    import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
    import { Pass } from 'three/addons/postprocessing/Pass.js';
    import { HalftonePass } from 'three/addons/postprocessing/HalftonePass.js';
    import { RenderPixelatedPass } from 'three/addons/postprocessing/RenderPixelatedPass.js';
    import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';

    /** Puts the Look on the scene and returns `{ render(scene, camera), setSize(width, height) }`. */
    export function applyLook(renderer, scene, look) {
      if (look.model === 'toon') toonMaterials(scene, look);
      if (look.faceted) scene.traverse((object) => { if (object.material && !Array.isArray(object.material)) object.material.flatShading = true; });
      const outline = look.lines ? new OutlineEffect(renderer, {
        defaultThickness: look.lines.width / 540, defaultColor: new THREE.Color(look.lines.color).toArray(), defaultAlpha: 1,
      }) : null;
      const draw = (camera) => (outline ? outline.render(scene, camera) : renderer.render(scene, camera));
      if (!look.halftone && !look.pixel) return { render: (_, camera) => draw(camera), setSize() {} };

      const composer = new EffectComposer(renderer);
      let first;
      if (look.pixel) {
        first = new RenderPixelatedPass(look.pixel.size, scene, new THREE.PerspectiveCamera(), { normalEdgeStrength: 0, depthEdgeStrength: look.lines ? 0.4 : 0 });
      } else {
        first = new SceneRenderPass(draw);
      }
      composer.addPass(first);
      if (look.halftone) {
        composer.addPass(new HalftonePass(window.innerWidth, window.innerHeight, {
          shape: 1, radius: 2 + look.halftone.scale * 4, scatter: 0, blending: look.halftone.amount, blendingMode: 1, greyscale: false,
        }));
      }
      composer.addPass(new OutputPass());
      return {
        render(_, camera) { first.camera = camera; composer.render(); },
        setSize(width, height) { composer.setSize(width, height); },
      };
    }

    /** Draws the scene (with its lines) into the composer's buffer. */
    class SceneRenderPass extends Pass {
      constructor(draw) { super(); this.draw = draw; this.needsSwap = false; this.camera = null; }
      render(renderer, writeBuffer, readBuffer) {
        renderer.setRenderTarget(this.renderToScreen ? null : readBuffer);
        renderer.clear();
        if (this.camera) this.draw(this.camera);
      }
    }

    /** Every standard material becomes a toon one with the same colour, pictures and glow. */
    function toonMaterials(scene, look) {
      const gradient = bands(look);
      const made = new Map();
      scene.traverse((object) => {
        if (!object.isMesh || Array.isArray(object.material) || !object.material.isMeshStandardMaterial) return;
        const from = object.material;
        if (!made.has(from)) {
          const toon = new THREE.MeshToonMaterial({
            name: from.name, color: from.color, map: from.map, emissive: from.emissive, emissiveIntensity: from.emissiveIntensity,
            emissiveMap: from.emissiveMap, normalMap: from.normalMap, aoMap: from.aoMap, vertexColors: from.vertexColors,
            transparent: from.transparent, opacity: from.opacity, alphaTest: from.alphaTest, side: from.side, gradientMap: gradient,
          });
          // Keyed roughness and metal still have somewhere to land.
          toon.roughness = from.roughness;
          toon.metalness = from.metalness;
          toon.userData.standard = from;
          made.set(from, toon);
        }
        object.material = made.get(from);
      });
    }

    /** The Look's bands as a gradient: the shadow, (a mid tone,) the light, edges as soft as the Look's. */
    function bands(look) {
      const size = 256;
      const data = new Uint8Array(size * 4);
      const shadow = Math.min(Math.max(1 - look.shadowValue * 1.6, 0.2), 0.8);
      const mid = (shadow + 1) / 2;
      const soft = Math.max(look.edgeSoftness, 0.002);
      const step = (edge, x) => THREE.MathUtils.smoothstep(x, edge - soft, edge + soft);
      for (let i = 0; i < size; i++) {
        const x = i / (size - 1);
        let level = shadow + (1 - shadow) * step(look.threshold, x);
        if (look.bands >= 3) level = shadow + (mid - shadow) * step(look.threshold, x) + (1 - mid) * step(look.midThreshold, x);
        data.fill(Math.round(level * 255), i * 4, i * 4 + 3);
        data[i * 4 + 3] = 255;
      }
      const texture = new THREE.DataTexture(data, size, 1);
      texture.minFilter = THREE.LinearFilter;
      texture.magFilter = THREE.LinearFilter;
      texture.generateMipmaps = false;
      texture.needsUpdate = true;
      return texture;
    }

    """
}
