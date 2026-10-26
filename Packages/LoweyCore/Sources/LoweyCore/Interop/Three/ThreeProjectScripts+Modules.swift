import Foundation

extension ThreeProjectScripts {
    /// `KHR_animation_pointer` for `GLTFLoader`, which skips those channels: each becomes the track three.js plays
    /// itself (a material's colour, a light's cone, a lens), added to the clip it belongs to. Works on any GLB, not only
    /// ours; R3F's `Scene.jsx` uses it too.
    static let pointerJS = """
    // Made with Maquette. Use it in anything, commercial included.
    import * as THREE from 'three';

    const KEY = 'KHR_animation_pointer';

    /** The file's clips with every pointer channel as a three.js track (an `AnimationClip[]`). */
    export async function withPointerTracks(gltf) {
      const parser = gltf.parser;
      const json = parser.json;
      const clips = gltf.animations.slice();
      const nodes = new Map();
      const meshesOfMaterial = new Map();
      gltf.scene.traverse((object) => {
        const link = parser.associations.get(object);
        if (link?.nodes !== undefined && !nodes.has(link.nodes)) nodes.set(link.nodes, object);
        if (!object.material || Array.isArray(object.material)) return;
        const index = parser.associations.get(object.material)?.materials;
        if (index === undefined) return;
        if (!meshesOfMaterial.has(index)) meshesOfMaterial.set(index, []);
        meshesOfMaterial.get(index).push(object);
      });
      const attached = (test, kind) => (json.nodes ?? []).flatMap((node, index) => {
        const object = test(node) ? nodes.get(index) : undefined;
        if (!object) return [];
        return [object[kind] ? object : object.children.find((child) => child[kind]) ?? object];
      });
      const places = { meshesOfMaterial, nodes, attached };
      for (const [number, animation] of (json.animations ?? []).entries()) {
        const tracks = [];
        for (const channel of animation.channels) {
          const pointer = channel.target?.extensions?.[KEY]?.pointer;
          if (channel.target?.path !== 'pointer' || !pointer) continue;
          const sampler = animation.samplers[channel.sampler];
          const [input, output] = await Promise.all([
            parser.getDependency('accessor', sampler.input), parser.getDependency('accessor', sampler.output),
          ]);
          const cubic = sampler.interpolation === 'CUBICSPLINE';
          const width = output.itemSize;
          const values = cubic ? Array.from({ length: input.count }, (_, k) => Array.from(output.array.slice((k * 3 + 1) * width, (k * 3 + 2) * width))).flat() : Array.from(output.array);
          const interpolation = sampler.interpolation === 'STEP' ? THREE.InterpolateDiscrete : THREE.InterpolateLinear;
          tracks.push(...pointerTracks(pointer, Array.from(input.array), values, width, interpolation, places));
        }
        if (tracks.length === 0) continue;
        const name = animation.name ?? `animation_${number}`;
        const index = clips.findIndex((clip) => clip.name === name);
        const all = index >= 0 ? clips[index].tracks.concat(tracks) : tracks;
        const clip = new THREE.AnimationClip(name, -1, all);
        if (index >= 0) clips[index] = clip; else clips.push(clip);
      }
      return clips;
    }

    function pointerTracks(pointer, times, values, width, interpolation, { meshesOfMaterial, nodes, attached }) {
      const pick = (from, count, map = (v) => v) => times.flatMap((_, k) => values.slice(k * width + from, k * width + from + count).map(map));
      const make = (Type, name, list) => new Type(name, times, list, interpolation);
      let match;
      if ((match = pointer.match(/^\\/materials\\/(\\d+)\\/(.+)$/))) {
        const meshes = meshesOfMaterial.get(Number(match[1])) ?? [];
        return meshes.flatMap((mesh) => {
          const at = `${mesh.uuid}.material.`;
          switch (match[2]) {
            case 'pbrMetallicRoughness/baseColorFactor': {
              const result = [make(THREE.ColorKeyframeTrack, at + 'color', pick(0, 3))];
              if (width > 3) {
                const alpha = pick(3, 1);
                if (alpha.some((a) => a < 1)) { mesh.material.transparent = true; result.push(make(THREE.NumberKeyframeTrack, at + 'opacity', alpha)); }
              }
              return result;
            }
            case 'pbrMetallicRoughness/roughnessFactor': return [make(THREE.NumberKeyframeTrack, at + 'roughness', pick(0, 1))];
            case 'pbrMetallicRoughness/metallicFactor': return [make(THREE.NumberKeyframeTrack, at + 'metalness', pick(0, 1))];
            case 'emissiveFactor': return [make(THREE.ColorKeyframeTrack, at + 'emissive', pick(0, 3))];
            case 'extensions/KHR_materials_emissive_strength/emissiveStrength': return [make(THREE.NumberKeyframeTrack, at + 'emissiveIntensity', pick(0, 1))];
            default: return [];
          }
        });
      }
      if ((match = pointer.match(/^\\/extensions\\/KHR_lights_punctual\\/lights\\/(\\d+)\\/(.+)$/))) {
        const lights = attached((node) => node.extensions?.KHR_lights_punctual?.light === Number(match[1]), 'isLight');
        const property = { color: ['color', THREE.ColorKeyframeTrack, 3], intensity: ['intensity', THREE.NumberKeyframeTrack, 1],
          range: ['distance', THREE.NumberKeyframeTrack, 1], 'spot/outerConeAngle': ['angle', THREE.NumberKeyframeTrack, 1] }[match[2]];
        if (!property) return [];
        return lights.map((light) => make(property[1], `${light.uuid}.${property[0]}`, pick(0, property[2])));
      }
      if ((match = pointer.match(/^\\/cameras\\/(\\d+)\\/perspective\\/yfov$/))) {
        const cameras = attached((node) => node.camera === Number(match[1]), 'isCamera');
        return cameras.map((camera) => make(THREE.NumberKeyframeTrack, `${camera.uuid}.fov`, pick(0, 1, THREE.MathUtils.radToDeg)));
      }
      if ((match = pointer.match(/^\\/nodes\\/(\\d+)\\/(translation|rotation|scale)$/))) {
        const object = nodes.get(Number(match[1]));
        if (!object) return [];
        const [name, Type] = { translation: ['position', THREE.VectorKeyframeTrack], rotation: ['quaternion', THREE.QuaternionKeyframeTrack],
          scale: ['scale', THREE.VectorKeyframeTrack] }[match[2]];
        return [make(Type, `${object.uuid}.${name}`, values)];
      }
      return [];
    }

    """
}
