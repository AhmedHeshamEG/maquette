import Foundation

public extension GLTFScene {
    /// A rigged object as a skin, so a game engine gets bones it can play rather than a frozen pose: its surface at rest
    /// in the rig's space, each part with one set of weights per vertex.
    struct SkinnedExport: Sendable {
        public var rig: ObjectRig
        public var parts: [LocalPart]
        public var weights: [SkinWeights]
        /// What takes the rig's space into the object's (a bevelled shape is built at its size).
        public var toObject: Vec3
        /// Each joint's local turn as it stands (a pose set by hand), else its rest.
        public var pose: [Transform]?

        public init(rig: ObjectRig, parts: [LocalPart], weights: [SkinWeights], toObject: Vec3 = .one, pose: [Transform]? = nil) {
            self.rig = rig
            self.parts = parts
            self.weights = weights
            self.toObject = toObject
            self.pose = pose
        }
    }
}

/// Writing a skin: under the object's node, a rig node (the rig's space) holds the skinned mesh and the joints; each
/// joint's inverse bind matrix is its rest pose's inverse in that space, so every reader, whether it applies the mesh
/// node's place or not, puts the surface where Maquette does.
extension GLTFSceneWriter {
    static let unsignedShort = 5123

    mutating func addSkin(_ skin: GLTFScene.SkinnedExport, name: String, id: ObjectID) -> Int? {
        let joints = skin.rig.skeleton.joints
        guard !joints.isEmpty, skin.parts.count == skin.weights.count,
              zip(skin.parts, skin.weights).allSatisfy({ $0.mesh.positions.count == $1.count }) else { return nil }
        let rigNode = nodes.count
        nodes.append(["name": "\(name) rig", "scale": [skin.toObject.x, skin.toObject.y, skin.toObject.z]])
        var jointNode: [Int] = []
        let standing = skin.pose.flatMap { $0.count == joints.count ? $0 : nil } ?? joints.map(\.rest)
        for (joint, rest) in zip(joints, standing) {
            jointNode.append(nodes.count)
            nodes.append(["name": joint.name, "translation": [rest.position.x, rest.position.y, rest.position.z],
                          "rotation": [rest.rotation.x, rest.rotation.y, rest.rotation.z, rest.rotation.w],
                          "scale": [rest.scale.x, rest.scale.y, rest.scale.z]])
        }
        for (index, joint) in joints.enumerated() {
            guard let parent = joint.parent else { continue }
            nodes[jointNode[parent]]["children"] = (nodes[jointNode[parent]]["children"] as? [Int] ?? []) + [jointNode[index]]
        }
        let inverseBind = skin.rig.skeleton.modelRest.flatMap { GLTFMeshReader.columnMajor(Self.inverse($0)) }
        let matrices = addAccessor(Self.floats(inverseBind), target: nil, count: joints.count, type: "MAT4")
        skins.append(["name": "\(name) skin", "joints": jointNode, "inverseBindMatrices": matrices, "skeleton": rigNode])
        let primitives = zip(skin.parts, skin.weights).map { piece, weights -> [String: Any] in
            var attributes = attributes(piece.mesh, colors: piece.colors)
            attributes["JOINTS_0"] = addAccessor(Self.shorts(weights.joints.flatMap { [$0.x, $0.y, $0.z, $0.w] }), target: Self.arrayBuffer,
                                                 componentType: Self.unsignedShort, count: weights.count, type: "VEC4")
            let normalised = weights.weights.flatMap { w -> [Float] in
                let sum = w.x + w.y + w.z + w.w
                return sum > 1e-6 ? [w.x / sum, w.y / sum, w.z / sum, w.w / sum] : [1, 0, 0, 0]
            }
            attributes["WEIGHTS_0"] = addAccessor(Self.floats(normalised), target: Self.arrayBuffer, count: weights.count, type: "VEC4")
            return ["attributes": attributes, "indices": indices(piece.mesh), "material": addMaterial(piece)]
        }
        meshes.append(["name": name, "primitives": primitives])
        let meshNode = nodes.count
        nodes.append(["name": name, "mesh": meshes.count - 1, "skin": skins.count - 1])
        nodes[rigNode]["children"] = [meshNode] + joints.indices.filter { joints[$0].parent == nil }.map { jointNode[$0] }
        jointNodes[id] = Dictionary(zip(joints.map(\.name), jointNode), uniquingKeysWith: { first, _ in first })
        return rigNode
    }

    /// The inverse of a rest transform (uniform scale, as joints have).
    static func inverse(_ transform: Transform) -> Transform {
        let scale = max(abs(transform.scale.x), 1e-9)
        let rotation = transform.rotation.inverse
        return Transform(position: rotation.act(transform.position) * (-1 / scale), rotation: rotation, scale: Vec3(1, 1, 1) / scale)
    }

    static func shorts(_ values: [UInt16]) -> Data {
        var data = Data(capacity: values.count * 2)
        for value in values {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// The node a `bone.<joint>` key turns, when the object was written as a skin.
    func jointNode(for track: Track) -> Int? {
        track.property.boneJoint.flatMap { jointNodes[track.target]?[$0] }
    }
}
