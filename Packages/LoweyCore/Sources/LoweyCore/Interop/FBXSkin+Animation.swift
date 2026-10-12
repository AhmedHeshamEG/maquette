import Foundation

extension FBXSkin.Builder {
    /// One animation stack and layer; each turned joint gets a rotation curve node with a curve per axis, sampled as
    /// glTF samples it (keys when every move is straight, else every frame).
    mutating func animate(_ tracks: [Track], skeleton: Skeleton, fps: Int) {
        let turning = tracks.compactMap { track in track.property.boneJoint.flatMap(skeleton.index(of:)).map { (track, $0) } }
        guard !turning.isEmpty else { return }
        let stack = id(), layer = id()
        connect(layer, stack)
        for (track, joint) in turning {
            let (times, _) = GLTFSceneWriter.times(track, fps: Double(fps))
            var angles: [Vec3] = []
            for time in times {
                guard let turn = track.value(at: time)?.quatValue else { continue }
                var angle = FBXSkin.euler(turn)
                // Each angle goes the short way from the one before (no jump from 179° to -179°).
                if let before = angles.last { angle = Self.unwrapped(angle, near: before) }
                angles.append(angle)
            }
            guard angles.count == times.count, let first = angles.first else { continue }
            stop = max(stop, times.last ?? 0)
            let node = id()
            objects.append(FBXNode("AnimationCurveNode", [.int64(node), .name("R", "AnimCurveNode"), .string("")], [
                FBXNode("Properties70", [], ["d|X", "d|Y", "d|Z"].enumerated().map { axis, name in
                    FBXNode.property(name, "Number", "", "A", [.double([first.x, first.y, first.z][axis])])
                })
            ]))
            connect(node, layer)
            connect(node, jointModels[joint], property: "Lcl Rotation")
            for (axis, name) in ["d|X", "d|Y", "d|Z"].enumerated() {
                let curve = id()
                objects.append(curveNode(curve, times: times, values: angles.map { [$0.x, $0.y, $0.z][axis] }))
                connect(curve, node, property: name)
            }
        }
        let end = Int64(stop * FBXSkin.ticksPerSecond)
        objects.append(FBXNode("AnimationStack", [.int64(stack), .name("Take 001", "AnimStack"), .string("")], [
            FBXNode("Properties70", [], [FBXNode.property("LocalStart", "KTime", "Time", "", [.int64(0)]),
                                         FBXNode.property("LocalStop", "KTime", "Time", "", [.int64(end)]),
                                         FBXNode.property("ReferenceStart", "KTime", "Time", "", [.int64(0)]),
                                         FBXNode.property("ReferenceStop", "KTime", "Time", "", [.int64(end)])])
        ]))
        objects.append(FBXNode("AnimationLayer", [.int64(layer), .name("BaseLayer", "AnimLayer"), .string("")]))
    }

    static func unwrapped(_ angle: Vec3, near before: Vec3) -> Vec3 {
        func near(_ value: Double, _ reference: Double) -> Double {
            value + 360 * ((reference - value) / 360).rounded()
        }
        return Vec3(near(angle.x, before.x), near(angle.y, before.y), near(angle.z, before.z))
    }

    /// A curve of straight segments between its keys.
    func curveNode(_ id: Int64, times: [Double], values: [Double]) -> FBXNode {
        FBXNode("AnimationCurve", [.int64(id), .name("", "AnimCurve"), .string("")], [
            FBXNode("Default", [.double(values.first ?? 0)]), FBXNode("KeyVer", [.int32(4009)]),
            FBXNode("KeyTime", [.int64s(times.map { Int64(($0 * FBXSkin.ticksPerSecond).rounded()) })]),
            FBXNode("KeyValueFloat", [.floats(values.map(Float.init))]),
            // Linear interpolation for every key (FbxAnimCurveDef::eInterpolationLinear).
            FBXNode("KeyAttrFlags", [.int32s([4])]), FBXNode("KeyAttrDataFloat", [.floats([0, 0, 0, 0])]),
            FBXNode("KeyAttrRefCount", [.int32s([Int32(times.count)])])
        ])
    }

    /// The whole file: header, settings (metres, y up), what kinds of objects it holds, the objects, how they connect.
    func document() -> [FBXNode] {
        func int(_ name: String, _ value: Int32) -> FBXNode { FBXNode.property(name, "int", "Integer", "", [.int32(value)]) }
        func double(_ name: String, _ value: Double) -> FBXNode { FBXNode.property(name, "double", "Number", "", [.double(value)]) }
        let settings = FBXNode("GlobalSettings", [], [
            FBXNode("Version", [.int32(1000)]),
            FBXNode("Properties70", [], [int("UpAxis", 1), int("UpAxisSign", 1), int("FrontAxis", 2), int("FrontAxisSign", 1),
                                         int("CoordAxis", 0), int("CoordAxisSign", 1), int("OriginalUpAxis", 1), int("OriginalUpAxisSign", 1),
                                         double("UnitScaleFactor", 100), double("OriginalUnitScaleFactor", 100),
                                         FBXNode.property("TimeSpanStart", "KTime", "Time", "", [.int64(0)]),
                                         FBXNode.property("TimeSpanStop", "KTime", "Time", "", [.int64(Int64(stop * FBXSkin.ticksPerSecond))])])
        ])
        var counts: [String: Int32] = [:]
        for object in objects {
            counts[object.name, default: 0] += 1
        }
        let definitions = FBXNode("Definitions", [], [FBXNode("Version", [.int32(100)]), FBXNode("Count", [.int32(Int32(objects.count))])]
            + counts.sorted { $0.key < $1.key }.map { FBXNode("ObjectType", [.string($0.key)], [FBXNode("Count", [.int32($0.value)])]) })
        return [
            FBXNode("FBXHeaderExtension", [], [FBXNode("FBXHeaderVersion", [.int32(1003)]), FBXNode("FBXVersion", [.int32(7400)]),
                                               FBXNode("Creator", [.string("Maquette")])]),
            settings, definitions, FBXNode("Objects", [], objects), FBXNode("Connections", [], connections)
        ]
    }
}
