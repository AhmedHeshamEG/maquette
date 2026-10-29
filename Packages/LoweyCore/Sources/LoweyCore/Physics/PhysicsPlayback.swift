import Foundation

/// What a run shows that isn't a property: cloth and jelly's bent surfaces (in the thing's own space) and fluids
/// (in the world). The renderer draws these in place of the thing's own mesh.
public struct SimulatedShapes: Sendable {
    public var meshes: [ObjectID: MeshData]
    public var fluids: [ObjectID: PhysicsFrames.FluidLook]
    /// Named regions of models made characters, bent by their face states (`FaceRegions`): moved on the model's own
    /// corners, before its rig and its paint.
    public var regions: [ObjectID: [FaceRegionBend]]

    public init(meshes: [ObjectID: MeshData] = [:], fluids: [ObjectID: PhysicsFrames.FluidLook] = [:], regions: [ObjectID: [FaceRegionBend]] = [:]) {
        self.meshes = meshes
        self.fluids = fluids
        self.regions = regions
    }

    public static let none = SimulatedShapes()
    public var isEmpty: Bool { meshes.isEmpty && fluids.isEmpty && regions.isEmpty }
}

/// A run played at a moment: the places of real things and ragdolls' joint turns as live values (so keys, clips and
/// everything after them see them), broken things swapped for their pieces, bent surfaces and fluids.
public enum PhysicsPlayback {
    /// Things' places in their parents' space and ragdolls' joint turns at `time`. `scene` gives the parents.
    public static func overrides(_ frames: PhysicsFrames, scene: Scene, at time: Double) -> [ObjectID: [PropertyKey: PropertyValue]] {
        guard time >= frames.start, !frames.frames.isEmpty else { return [:] }
        var result: [ObjectID: [PropertyKey: PropertyValue]] = [:]
        for (index, id) in frames.bodies.enumerated() {
            guard let object = scene.objects[id], object.physics?.motion == .falls,
                  let (position, rotation) = frames.transform(of: index, at: time) else { continue }
            result[id] = place(object, world: position, rotation: rotation, in: scene)
        }
        guard let (lower, upper, blend) = frames.position(at: time) else { return result }
        for (index, ragdoll) in frames.ragdolls.enumerated() {
            guard let object = scene.objects[ragdoll.object] else { continue }
            let a = frames.frames[lower].ragdolls[index]
            let b = frames.frames[upper].ragdolls[index]
            var values: [PropertyKey: PropertyValue] = [:]
            for (joint, name) in ragdoll.joints.enumerated() {
                let qa = quaternion(a, at: joint * 4)
                let qb = quaternion(b, at: joint * 4)
                values[.boneTurn(name)] = .quat(qa.slerp(to: qb, blend).normalized)
            }
            let offset = ragdoll.joints.count * 4
            let (pa, ra) = PhysicsFrames.read(a, at: offset)
            let (pb, rb) = PhysicsFrames.read(b, at: offset)
            values.merge(place(object, world: pa.lerp(to: pb, blend), rotation: ra.slerp(to: rb, blend), in: scene)) { _, placed in placed }
            result[ragdoll.object] = values
        }
        return result
    }

    static func quaternion(_ values: [Float], at offset: Int) -> Quat {
        guard values.count >= offset + 4 else { return .identity }
        return Quat(x: Double(values[offset]), y: Double(values[offset + 1]), z: Double(values[offset + 2]), w: Double(values[offset + 3]))
    }

    /// Position and rotation that put `object` at a world place under its parent (its own scale kept).
    static func place(_ object: SceneObject, world position: Vec3, rotation: Quat, in scene: Scene) -> [PropertyKey: PropertyValue] {
        let parent = object.parent.map { scene.worldTransform(of: $0) } ?? .identity
        let local = Transform.relative(world: Transform(position: position, rotation: rotation, scale: .one), toParent: parent)
        return [.position: .vec3(local.position), .rotation: .quat(local.rotation)]
    }

    /// Broken things become their pieces (new things in the shown scene only, named after the original), cloth and
    /// jelly their bent surfaces, fluids what they look like now.
    public static func apply(_ frames: PhysicsFrames, to scene: inout Scene, at time: Double, animated: inout Set<ObjectID>) -> SimulatedShapes {
        guard let (lower, upper, blend) = frames.position(at: time) else { return .none }
        for (index, breakable) in frames.breakables.enumerated() {
            guard let broke = breakable.brokeAt, broke <= lower, var original = scene.objects[breakable.object] else { continue }
            let a = frames.frames[lower].pieces[index]
            let b = frames.frames[upper].pieces[index]
            for (piece, mesh) in breakable.pieces.enumerated() {
                let (pa, ra) = PhysicsFrames.read(a, at: piece * 7)
                let (pb, rb) = b.count >= piece * 7 + 7 ? PhysicsFrames.read(b, at: piece * 7) : (pa, ra)
                var object = SceneObject(id: pieceID(breakable.object, piece), name: "\(original.name) piece \(piece + 1)", kind: .mesh(mesh),
                                         transform: Transform(position: pa.lerp(to: pb, blend), rotation: ra.slerp(to: rb, blend).normalized))
                for key in [PropertyKey.color, .emissive, .emissiveIntensity, .shading, .roughness, .metallic, .opacity] {
                    object[key] = original[key]
                }
                scene.objects[object.id] = object
                scene.roots.append(object.id)
                animated.insert(object.id)
            }
            original[.visible] = .bool(false)
            scene.objects[breakable.object] = original
            animated.insert(breakable.object)
        }
        var shapes = SimulatedShapes()
        for (index, soft) in frames.softs.enumerated() {
            guard scene.objects[soft.object] != nil else { continue }
            let a = frames.frames[lower].soft[index]
            let b = frames.frames[upper].soft[index]
            let world = scene.worldTransform(of: soft.object)
            var positions: [SIMD3<Float>] = []
            positions.reserveCapacity(a.count / 3)
            for vertex in 0 ..< a.count / 3 {
                let pa = Vec3(Double(a[vertex * 3]), Double(a[vertex * 3 + 1]), Double(a[vertex * 3 + 2]))
                let pb = b.count == a.count ? Vec3(Double(b[vertex * 3]), Double(b[vertex * 3 + 1]), Double(b[vertex * 3 + 2])) : pa
                positions.append(world.inverseApply(to: pa.lerp(to: pb, blend)).floats)
            }
            shapes.meshes[soft.object] = smoothed(MeshData(positions: positions, indices: soft.triangles))
            animated.insert(soft.object)
        }
        let nearest = blend < 0.5 ? lower : upper
        for (index, fluid) in frames.fluids.enumerated() where index < frames.frames[nearest].fluids.count {
            shapes.fluids[fluid] = frames.frames[nearest].fluids[index]
        }
        return shapes
    }

    public static func pieceID(_ original: ObjectID, _ index: Int) -> ObjectID { ObjectID(raw: "\(original.raw)~piece\(index + 1)") }

    /// Smooth normals from the faces around each corner.
    static func smoothed(_ mesh: MeshData) -> MeshData {
        var normals = [SIMD3<Float>](repeating: .zero, count: mesh.positions.count)
        for triangle in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            let a = Int(mesh.indices[triangle])
            let b = Int(mesh.indices[triangle + 1])
            let c = Int(mesh.indices[triangle + 2])
            let normal = cross3(mesh.positions[b] - mesh.positions[a], mesh.positions[c] - mesh.positions[a])
            normals[a] += normal
            normals[b] += normal
            normals[c] += normal
        }
        var result = mesh
        result.normals = normals.map { n in
            let length = length3(n)
            return length > 1e-12 ? n / length : SIMD3<Float>(0, 1, 0)
        }
        result.uvs = Array(repeating: .zero, count: mesh.positions.count)
        return result
    }

    /// Arrows for the overlay: each moving thing's centre, its speed (m/s) and the net force on it (N).
    public static func arrows(_ frames: PhysicsFrames, at time: Double) -> [(object: ObjectID, centre: Vec3, velocity: Vec3, force: Vec3)] {
        guard let (lower, _, _) = frames.position(at: time) else { return [] }
        let earlier = max(lower - 1, 0)
        let dt = 1 / Double(max(frames.fps, 1))
        return frames.bodies.enumerated().compactMap { index, id in
            guard index < frames.masses.count, frames.masses[index] > 0, let place = frames.transform(of: index, at: time),
                  let now = frames.velocity(of: index, at: time) else { return nil }
            let before = frames.velocity(of: index, at: frames.start + Double(earlier) / Double(max(frames.fps, 1))) ?? now
            let acceleration = lower == earlier ? .zero : (now - before) / dt
            return (id, place.position, now, acceleration * frames.masses[index])
        }
    }
}
