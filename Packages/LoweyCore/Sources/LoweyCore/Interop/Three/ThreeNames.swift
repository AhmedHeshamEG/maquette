import Foundation

/// Names three.js keeps as they are (X1): `GLTFLoader` strips spaces and `[ ] . : /` and adds `_1`, `_2` to a name it has
/// seen, in an order nobody can predict. A GLB written for the web carries names already clean and unique (nodes and
/// meshes together), so `getObjectByName`, the R3F component, `scene.json` and `AGENTS.md` all say the same thing. The
/// name as it was in Maquette stays in each node's `extras.maquette.name`.
public enum ThreeNames {
    /// What `PropertyBinding.sanitizeNodeName` makes of a name.
    public static func sanitized(_ name: String) -> String {
        let reserved: Set<Character> = ["[", "]", ".", ":", "/"]
        let kept = name.compactMap { character -> Character? in
            if character.isWhitespace { return "_" }
            return reserved.contains(character) ? nil : character
        }
        return String(kept)
    }

    /// The GLB with every node and mesh name clean and unique, the original kept in the node's extras.
    public static func prepared(_ glb: Data) -> Data {
        guard let unpacked = unpack(glb) else { return glb }
        var json = unpacked.json
        var used = Set<String>()
        func unique(_ name: String, fallback: String) -> String {
            let base = sanitized(name).isEmpty ? fallback : sanitized(name)
            var candidate = base, number = 1
            while used.contains(candidate) {
                candidate = "\(base)_\(number)"
                number += 1
            }
            used.insert(candidate)
            return candidate
        }
        var nodes = json["nodes"] as? [[String: Any]] ?? []
        for index in nodes.indices {
            let original = nodes[index]["name"] as? String ?? ""
            nodes[index]["name"] = unique(original, fallback: "node_\(index)")
            var extras = nodes[index]["extras"] as? [String: Any] ?? [:]
            var maquette = extras["maquette"] as? [String: Any] ?? [:]
            if maquette["name"] == nil, !original.isEmpty { maquette["name"] = original }
            extras["maquette"] = maquette
            nodes[index]["extras"] = extras
        }
        var meshes = json["meshes"] as? [[String: Any]] ?? []
        for index in meshes.indices {
            meshes[index]["name"] = unique("\(meshes[index]["name"] as? String ?? "mesh")_mesh", fallback: "mesh_\(index)")
        }
        if !nodes.isEmpty { json["nodes"] = nodes }
        if !meshes.isEmpty { json["meshes"] = meshes }
        return GLBContainer.pack(json: json, binary: unpacked.binary)
    }

    /// The JSON and the binary chunk of a GLB.
    static func unpack(_ glb: Data) -> (json: [String: Any], binary: Data)? {
        let bytes = [UInt8](glb)
        guard bytes.count >= 20, bytes[0 ..< 4] == [0x67, 0x6C, 0x54, 0x46] else { return nil }
        func u32(_ offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }
        var offset = 12
        var json: [String: Any]?
        var binary = Data()
        while offset + 8 <= bytes.count {
            let length = u32(offset), type = u32(offset + 4), start = offset + 8
            guard start + length <= bytes.count else { return nil }
            let chunk = Data(bytes[start ..< start + length])
            if type == 0x4E4F_534A { json = (try? JSONSerialization.jsonObject(with: chunk)) as? [String: Any] }
            if type == 0x004E_4942 { binary = chunk }
            offset = start + length
        }
        return json.map { ($0, binary) }
    }
}
