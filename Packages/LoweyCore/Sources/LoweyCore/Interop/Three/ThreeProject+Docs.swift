import Foundation

/// What a web folder holds, read back from its own GLB, so the component and `AGENTS.md` name exactly what three.js
/// will find.
struct ThreeContents {
    struct Node {
        var name: String
        var maquetteName: String
        var kind: String
        var role: String
        var parent: String?
    }

    struct Clip {
        var name: String
        var duration: Double
        var tracks: Int
    }

    var nodes: [Node] = []
    var clips: [Clip] = []
    var cameras: [String] = []
    /// Each Maquette object's three.js name.
    var threeName: [ObjectID: String] = [:]
    var extensions: [String] = []

    init(glb: Data) throws {
        let file = try GLTFReader.parse(glb, baseURL: nil)
        let all = file.array("nodes")
        var parentOf: [Int: Int] = [:]
        for (index, node) in all.enumerated() {
            for child in node["children"] as? [Int] ?? [] {
                parentOf[child] = index
            }
        }
        let joints = Set(file.array("skins").flatMap { $0["joints"] as? [Int] ?? [] })
        for (index, node) in all.enumerated() {
            let name = node["name"] as? String ?? "node_\(index)"
            let maquette = (node["extras"] as? [String: Any])?["maquette"] as? [String: Any] ?? [:]
            if let id = maquette["id"] as? String { threeName[ObjectID(raw: id)] = name }
            let role: String = if node["camera"] != nil {
                "camera"
            } else if (node["extensions"] as? [String: Any])?["KHR_lights_punctual"] != nil {
                "light"
            } else if node["skin"] != nil {
                "skinned mesh"
            } else if node["mesh"] != nil {
                "mesh"
            } else if joints.contains(index) {
                "bone"
            } else {
                "group"
            }
            if role == "camera" { cameras.append(name) }
            nodes.append(Node(name: name, maquetteName: maquette["name"] as? String ?? name, kind: maquette["kind"] as? String ?? role,
                              role: role, parent: parentOf[index].flatMap { all[$0]["name"] as? String }))
        }
        for (number, animation) in file.array("animations").enumerated() {
            let samplers = animation["samplers"] as? [[String: Any]] ?? []
            let accessors = file.array("accessors")
            let end = samplers.compactMap { sampler -> Double? in
                guard let input = sampler["input"] as? Int, input < accessors.count else { return nil }
                return (accessors[input]["max"] as? [Double])?.first
            }.max() ?? 0
            clips.append(Clip(name: animation["name"] as? String ?? "animation_\(number)", duration: end,
                              tracks: (animation["channels"] as? [Any])?.count ?? 0))
        }
        extensions = file.json["extensionsUsed"] as? [String] ?? []
    }
}

/// `Scene.jsx`: the scene as a React Three Fiber component, with every node's name and every clip typed.
enum ThreeComponent {
    static func source(_ contents: ThreeContents) -> String {
        let quoted: (String) -> String = { "'" + $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") + "'" }
        let names = contents.nodes.map { quoted($0.name) }
        let clips = contents.clips.map { quoted($0.name) }
        let table = contents.nodes.map { node in
            "  \(quoted(node.name)): { role: \(quoted(node.role)), kind: \(quoted(node.kind)), maquette: \(quoted(node.maquetteName)) },"
        }
        return """
        // Made with Maquette: the scene as a React Three Fiber component. Needs react, three@\(ThreeProject.threeVersion),
        // @react-three/fiber and @react-three/drei. Put scene.glb in your public folder (or pass `url`).
        import { useEffect, useRef, useState } from 'react';
        import { useGLTF, useAnimations } from '@react-three/drei';
        import { withPointerTracks } from './maquette/pointer.js';

        /** @typedef {\(names.isEmpty ? "never" : names.joined(separator: " | "))} NodeName */
        /** @typedef {\(clips.isEmpty ? "never" : clips.joined(separator: " | "))} ClipName */

        /** Every named thing in the scene: what it is in three.js, what it was in Maquette. */
        export const NODES = /** @type {const} */ ({
        \(table.joined(separator: "\n"))
        });

        /** @type {ClipName[]} */
        export const CLIPS = [\(clips.joined(separator: ", "))];

        /**
         * The scene, playing `clip` (the first one unless you say; `null` holds still).
         * `onNodes` hands you every node by name once it's loaded.
         * @param {{ url?: string, clip?: ClipName | null, onNodes?: (nodes: Record<NodeName, import('three').Object3D>) => void } & Record<string, any>} props
         */
        export function Scene({ url = '/scene.glb', clip = CLIPS[0] ?? null, onNodes, ...props }) {
          const group = useRef();
          const gltf = useGLTF(url);
          const [clips, setClips] = useState(gltf.animations);
          useEffect(() => { withPointerTracks(gltf).then(setClips); }, [gltf]);
          const { actions } = useAnimations(clips, group);
          useEffect(() => {
            if (!clip || !actions[clip]) return undefined;
            actions[clip].reset().play();
            return () => actions[clip]?.stop();
          }, [actions, clip]);
          useEffect(() => {
            if (!onNodes) return;
            onNodes(Object.fromEntries(Object.keys(NODES).map((name) => [name, gltf.scene.getObjectByName(name)])));
          }, [gltf, onNodes]);
          return (
            <group ref={group} {...props} dispose={null}>
              <primitive object={gltf.scene} />
            </group>
          );
        }

        useGLTF.preload('/scene.glb');

        """
    }
}
