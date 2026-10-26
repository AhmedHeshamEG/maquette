import Foundation

/// `AGENTS.md` in a web folder (X1): written for an agent (or a person) about to wire the scene into their code. What's
/// in it, every named thing and what it is, the clips, and recipes for the usual jobs, with the folder's real names.
enum ThreeAgents {
    static func text(_ contents: ThreeContents, name: String, look: String) -> String {
        let meshes = contents.nodes.filter { $0.role == "mesh" || $0.role == "skinned mesh" }
        let example = meshes.first?.name ?? contents.nodes.first?.name ?? "Thing"
        let clip = contents.clips.first?.name
        var lines = [
            "# \(name), for the web",
            "",
            "Made in Maquette and exported for three.js \(ThreeProject.threeVersion) (carried in `lib/three`, no network needed).",
            "\(count(contents.nodes.count, "named thing")): \(count(meshes.count, "mesh", "meshes")), \(count(contents.cameras.count, "camera")), "
                + "\(count(contents.nodes.filter { $0.role == "light" }.count, "light")); \(count(contents.clips.count, "clip")); the \(look) Look.",
            "",
            "## Files",
            "",
            "| File | What it is |",
            "|---|---|",
            "| `scene.glb` | The scene: meshes, materials and pictures, cameras, lights, skins, every clip. glTF 2.0. |",
            "| `scene.json` | The same scene in three.js's own format, for `new THREE.ObjectLoader().parse(json)`. |",
            "| `index.html`, `main.js` | A player: the camera cuts, the timeline, the Look. Serve the folder and open it. |",
            "| `maquette/pointer.js` | `withPointerTracks(gltf)`: adds the keyed colours, glows, lights and lenses (`KHR_animation_pointer`) to the clips. |",
            "| `maquette/look.js` | `applyLook(renderer, scene, look)`: the Look as toon materials, ink lines and passes. |",
            "| `maquette/scene.js` | `MAQUETTE`: frame rate, length, camera cuts, sun, sky, ground, the Look's numbers. |",
            "| `Scene.jsx` | A React Three Fiber component with every node name and clip typed. |",
            "",
            "## Run it",
            "",
            "ES modules don't load from `file://`, so serve the folder: `npx serve .` or `python3 -m http.server`, then open",
            "`index.html`. `?t=2.5` holds that moment, `?orbit` lets you look around, `?transparent` drops the sky and the ground.",
            "`window.maquette` has `scene`, `mixer`, `actions`, `setTime(seconds)`, `play(clip)`, `pause()` and `object(name)`.",
            "",
            "## Named things",
            "",
            "Names are exactly what `scene.getObjectByName` finds (spaces became `_`; the Maquette name is in `userData.maquette.name`).",
            "",
            "| three.js name | In Maquette | What it is | Inside |",
            "|---|---|---|---|"
        ]
        lines += contents.nodes.map { node in
            let what = node.kind == node.role ? node.role : "\(node.role) (\(node.kind))"
            return "| `\(node.name)` | \(node.maquetteName) | \(what) | \(node.parent.map { "`\($0)`" } ?? "the scene") |"
        }
        lines += ["", "## Clips", ""]
        lines += contents.clips.isEmpty ? ["None: the scene holds still."] : contents.clips.map { clip in
            "- `\(clip.name)`: \(String(format: "%.2f", clip.duration)) s, \(clip.tracks) channels."
        }
        lines += recipes(example: example, clip: clip, extensions: contents.extensions)
        return lines.joined(separator: "\n") + "\n"
    }

    static func count(_ number: Int, _ one: String, _ many: String? = nil) -> String {
        "\(number) \(number == 1 ? one : many ?? one + "s")"
    }

    static func recipes(example: String, clip: String?, extensions: [String]) -> [String] {
        let clipName = clip ?? "animation_0"
        return [
            "",
            "## Recipes",
            "",
            "Load it in your own three.js app:",
            "",
            "```js",
            "import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';",
            "import { withPointerTracks } from './maquette/pointer.js';",
            "const gltf = await new GLTFLoader().loadAsync('scene.glb');",
            "scene.add(gltf.scene);",
            "const clips = await withPointerTracks(gltf); // the keyed materials, lights and lenses join the clips",
            "const mixer = new THREE.AnimationMixer(gltf.scene);",
            "mixer.clipAction(THREE.AnimationClip.findByName(clips, '\(clipName)')).play();",
            "// every frame: mixer.update(delta); keyed lenses need camera.updateProjectionMatrix()",
            "```",
            "",
            "Swap a material, or change one number:",
            "",
            "```js",
            "const thing = scene.getObjectByName('\(example)');",
            "thing.material = new THREE.MeshPhysicalMaterial({ color: '#d94f2b', clearcoat: 1 });",
            "// or: thing.material.color.set('#d94f2b');",
            "```",
            "",
            "In React Three Fiber: `import { Scene } from './Scene.jsx'` and `<Scene clip=\"\(clipName)\" onNodes={(nodes) => …} />`.",
            "",
            "## What's carried, what's baked",
            "",
            "Motion Maquette makes from rules (behaviours, holds, physics runs, follow-throughs) is baked into the clips as keys.",
            "Paint is in the textures; the Look is rebuilt in `maquette/look.js` (the paint Looks and paper use their nearest",
            "real-time pass: toon bands and ink lines). Keys glTF has no place for (face states, a reveal) ride in the GLB's",
            "`extras.maquette.tracks` so Maquette gets them back. Extensions used: "
                + (extensions.isEmpty ? "none." : extensions.map { "`\($0)`" }.joined(separator: ", ") + "."),
            "The full table is Maquette's `docs/INTEROP.md`."
        ]
    }
}
