import Foundation

/// A rigged, animated thing as an FBX, written by Maquette itself (Autodesk's SDK is out by its licence, D-133): the
/// surface, its joints as limb nodes, a skin of clusters with their bind matrices, a bind pose, and each joint's turns
/// as rotation curves. Metres, y up, as glTF; Blender, Godot and Unity read it.
public enum FBXSkin {
    /// FBX keeps time in these ticks a second.
    static let ticksPerSecond: Double = 46_186_158_000

    /// The file for a skin and the `bone.` tracks that turn its joints (others are left out).
    public static func file(_ skin: GLTFScene.SkinnedExport, name: String, tracks: [Track], fps: Int) -> Data {
        var builder = Builder(name: name)
        builder.add(skin)
        builder.animate(tracks.filter { $0.property.boneJoint != nil }, skeleton: skin.rig.skeleton, fps: max(fps, 1))
        return FBXBinary.file(builder.document())
    }

    /// Euler angles in degrees, x then y then z (FBX's default order), for a turn.
    static func euler(_ q: Quat) -> Vec3 {
        let x = atan2(2 * (q.w * q.x + q.y * q.z), 1 - 2 * (q.x * q.x + q.y * q.y))
        let y = asin(min(max(2 * (q.w * q.y - q.z * q.x), -1), 1))
        let z = atan2(2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z))
        return Vec3(x, y, z) * (180 / .pi)
    }

    /// A transform as FBX's sixteen numbers (column-major, as glTF's).
    static func matrix(_ transform: Transform) -> [Double] {
        GLTFMeshReader.columnMajor(transform).map(Double.init)
    }

    struct Builder {
        let name: String
        var objects: [FBXNode] = []
        var connections: [FBXNode] = []
        var nextID: Int64 = 1_000_000
        var jointModels: [Int64] = []
        var stop: Double = 0

        init(name: String) {
            self.name = name
        }

        mutating func id() -> Int64 {
            nextID += 1
            return nextID
        }

        mutating func connect(_ child: Int64, _ parent: Int64, property: String? = nil) {
            if let property {
                connections.append(FBXNode("C", [.string("OP"), .int64(child), .int64(parent), .string(property)]))
            } else {
                connections.append(FBXNode("C", [.string("OO"), .int64(child), .int64(parent)]))
            }
        }

        static func transformProperties(_ transform: Transform) -> FBXNode {
            let turn = FBXSkin.euler(transform.rotation)
            return FBXNode("Properties70", [], [
                FBXNode.property("Lcl Translation", "Lcl Translation", "", "A",
                                 [.double(transform.position.x), .double(transform.position.y), .double(transform.position.z)]),
                FBXNode.property("Lcl Rotation", "Lcl Rotation", "", "A", [.double(turn.x), .double(turn.y), .double(turn.z)]),
                FBXNode.property("Lcl Scaling", "Lcl Scaling", "", "A",
                                 [.double(transform.scale.x), .double(transform.scale.y), .double(transform.scale.z)])
            ])
        }

        /// The surface (one geometry of every part, the rig's space scaled into the object's), its model and material,
        /// the joints and the skin.
        mutating func add(_ skin: GLTFScene.SkinnedExport) {
            let scale = skin.toObject
            var points: [Double] = [], corners: [Int32] = [], normals: [Double] = []
            var influences: [[(vertex: Int32, weight: Double)]] = Array(repeating: [], count: skin.rig.skeleton.joints.count)
            var offset = 0
            for (part, weights) in zip(skin.parts, skin.weights) {
                let mesh = part.mesh
                points += mesh.positions.flatMap { [Double($0.x) * scale.x, Double($0.y) * scale.y, Double($0.z) * scale.z] }
                for triangle in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
                    let a = Int32(offset) + Int32(mesh.indices[triangle]), b = Int32(offset) + Int32(mesh.indices[triangle + 1])
                    let c = Int32(offset) + Int32(mesh.indices[triangle + 2])
                    corners += [a, b, -c - 1]
                    for index in triangle ..< triangle + 3 {
                        let n = mesh.normals.count == mesh.positions.count ? mesh.normals[Int(mesh.indices[index])] : SIMD3<Float>(0, 1, 0)
                        normals += [Double(n.x), Double(n.y), Double(n.z)]
                    }
                }
                for vertex in 0 ..< weights.count {
                    for slot in 0 ..< 4 where weights.weights[vertex][slot] > 1e-4 {
                        let joint = Int(weights.joints[vertex][slot])
                        if joint < influences.count { influences[joint].append((Int32(offset + vertex), Double(weights.weights[vertex][slot]))) }
                    }
                }
                offset += mesh.positions.count
            }
            let geometry = id(), model = id(), material = id()
            objects.append(geometryNode(geometry, points: points, corners: corners, normals: normals))
            objects.append(FBXNode("Model", [.int64(model), .name(name, "Model"), .string("Mesh")], [
                FBXNode("Version", [.int32(232)]), Self.transformProperties(.identity), FBXNode("Shading", [.bool(true)]),
                FBXNode("Culling", [.string("CullingOff")])
            ]))
            let colour = skin.parts.first?.material.color ?? RGBA(0.8, 0.8, 0.8)
            objects.append(FBXNode("Material", [.int64(material), .name(name, "Material"), .string("")], [
                FBXNode("Version", [.int32(102)]), FBXNode("ShadingModel", [.string("phong")]),
                FBXNode("Properties70", [], [FBXNode.property("DiffuseColor", "Color", "", "A",
                                                              [.double(colour.r), .double(colour.g), .double(colour.b)])])
            ]))
            connect(model, 0)
            connect(geometry, model)
            connect(material, model)
            addJoints(skin.rig.skeleton, pose: skin.pose, scale: scale)
            addSkin(skin.rig.skeleton, influences: influences, geometry: geometry, model: model, scale: scale)
        }

        func geometryNode(_ id: Int64, points: [Double], corners: [Int32], normals: [Double]) -> FBXNode {
            FBXNode("Geometry", [.int64(id), .name(name, "Geometry"), .string("Mesh")], [
                FBXNode("Vertices", [.doubles(points)]), FBXNode("PolygonVertexIndex", [.int32s(corners)]),
                FBXNode("GeometryVersion", [.int32(124)]),
                FBXNode("LayerElementNormal", [.int32(0)], [
                    FBXNode("Version", [.int32(101)]), FBXNode("Name", [.string("")]),
                    FBXNode("MappingInformationType", [.string("ByPolygonVertex")]), FBXNode("ReferenceInformationType", [.string("Direct")]),
                    FBXNode("Normals", [.doubles(normals)])
                ]),
                FBXNode("LayerElementMaterial", [.int32(0)], [
                    FBXNode("Version", [.int32(101)]), FBXNode("Name", [.string("")]),
                    FBXNode("MappingInformationType", [.string("AllSame")]), FBXNode("ReferenceInformationType", [.string("IndexToDirect")]),
                    FBXNode("Materials", [.int32s([0])])
                ]),
                FBXNode("Layer", [.int32(0)], [
                    FBXNode("Version", [.int32(100)]),
                    FBXNode("LayerElement", [], [FBXNode("Type", [.string("LayerElementNormal")]), FBXNode("TypedIndex", [.int32(0)])]),
                    FBXNode("LayerElement", [], [FBXNode("Type", [.string("LayerElementMaterial")]), FBXNode("TypedIndex", [.int32(0)])])
                ])
            ])
        }

        /// A limb node and its attribute for each joint, hung as the skeleton hangs.
        mutating func addJoints(_ skeleton: Skeleton, pose: [Transform]?, scale: Vec3) {
            let standing = pose.flatMap { $0.count == skeleton.joints.count ? $0 : nil } ?? skeleton.restPose
            for (joint, local) in zip(skeleton.joints, standing) {
                let model = id(), attribute = id()
                var placed = local
                placed.position = local.position.scaled(by: scale)
                objects.append(FBXNode("NodeAttribute", [.int64(attribute), .name(joint.name, "NodeAttribute"), .string("LimbNode")],
                                       [FBXNode("TypeFlags", [.string("Skeleton")])]))
                objects.append(FBXNode("Model", [.int64(model), .name(joint.name, "Model"), .string("LimbNode")],
                                       [FBXNode("Version", [.int32(232)]), Self.transformProperties(placed)]))
                connect(attribute, model)
                jointModels.append(model)
            }
            for (index, joint) in skeleton.joints.enumerated() {
                connect(jointModels[index], joint.parent.map { jointModels[$0] } ?? 0)
            }
        }

        /// The skin: one cluster a joint (its vertices and weights, where the joint and the surface stood when bound),
        /// and the bind pose.
        mutating func addSkin(_ skeleton: Skeleton, influences: [[(vertex: Int32, weight: Double)]], geometry: Int64, model: Int64, scale: Vec3) {
            let skin = id()
            objects.append(FBXNode("Deformer", [.int64(skin), .name(name, "Deformer"), .string("Skin")],
                                   [FBXNode("Version", [.int32(101)]), FBXNode("Link_DeformAcuracy", [.double(50)])]))
            connect(skin, geometry)
            var poseNodes = [FBXNode("PoseNode", [], [FBXNode("Node", [.int64(model)]), FBXNode("Matrix", [.doubles(matrix(.identity))])])]
            for (index, rest) in skeleton.modelRest.enumerated() {
                var bound = rest
                bound.position = rest.position.scaled(by: scale)
                let cluster = id()
                objects.append(FBXNode("Deformer", [.int64(cluster), .name(skeleton.joints[index].name, "SubDeformer"), .string("Cluster")], [
                    FBXNode("Version", [.int32(100)]), FBXNode("UserData", [.string(""), .string("")]),
                    FBXNode("Indexes", [.int32s(influences[index].map(\.vertex))]), FBXNode("Weights", [.doubles(influences[index].map(\.weight))]),
                    FBXNode("Transform", [.doubles(matrix(.identity))]), FBXNode("TransformLink", [.doubles(matrix(bound))])
                ]))
                connect(cluster, skin)
                connect(jointModels[index], cluster)
                poseNodes.append(FBXNode("PoseNode", [], [FBXNode("Node", [.int64(jointModels[index])]), FBXNode("Matrix", [.doubles(matrix(bound))])]))
            }
            objects.append(FBXNode("Pose", [.int64(id()), .name("BindPose", "Pose"), .string("BindPose")],
                                   [FBXNode("Type", [.string("BindPose")]), FBXNode("Version", [.int32(100)]),
                                    FBXNode("NbPoseNodes", [.int32(Int32(poseNodes.count))])] + poseNodes))
        }
    }
}
