import Foundation

/// The rig a made character builds itself (K1 step 2): the app knows each part's job, so it places U4's dots where the
/// parts hinge and the group's pieces ride their joints (`RigidParts`). A person gets the humanoid joints by their
/// standard names, so every humanoid clip plays on it and engines retarget it; four legs and wings get the animal
/// layouts `BodyGuess` uses; anything else gets what its parts need. The marks stay editable in Rig like any other.
public enum CharacterAutoRig {
    /// The joints a rig needs to count as a person (the humanoid standard `HumanRig` builds).
    public static let humanoidJoints: Set<String> = {
        var names: Set<String> = ["hips", "spine", "chest", "neck", "head"]
        for side in ["left", "right"] {
            for joint in ["Shoulder", "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot", "Toes"] {
                names.insert(side + joint)
            }
        }
        return names
    }()

    /// The dots for a character as its parts stand (the character's space).
    public static func marks(_ anatomy: CharacterAnatomy) -> [RigMark] {
        let body = anatomy.body?.rootBounds
        let head = anatomy.head?.rootBounds
        guard body != nil || head != nil else {
            // Nothing to hinge: one joint holds it all (an eye creature still blinks, looks and talks).
            let centre = anatomy.bounds?.center ?? .zero
            return [RigMark(name: RigMarks.rootName, kind: .dot, position: centre)]
        }
        var marks: [RigMark] = []
        if anatomy.walksOnFour, let body {
            marks += fourLegged(body: body, head: head)
        } else if let body {
            marks += upright(body: body, head: head)
        } else if let head {
            marks.append(RigMark(name: "head", kind: .dot, position: Vec3(head.center.x, head.min.y, head.center.z), thickness: head.size.x))
        }
        marks += limbs(anatomy, trunk: marks)
        return marks
    }

    /// Hips, spine, chest up an upright body; neck and head up the head.
    static func upright(body: Bounds, head: Bounds?) -> [RigMark] {
        let x = body.center.x, z = body.center.z
        let width = body.size.x
        var marks = [RigMark(name: "hips", kind: .dot, position: Vec3(x, body.min.y + body.size.y * 0.12, z), thickness: width),
                     RigMark(name: "spine", kind: .dot, position: Vec3(x, body.min.y + body.size.y * 0.45, z), parent: "hips", thickness: width),
                     RigMark(name: "chest", kind: .dot, position: Vec3(x, body.min.y + body.size.y * 0.78, z), parent: "spine", thickness: width)]
        if let head {
            marks.append(RigMark(
                name: "neck",
                kind: .dot,
                position: Vec3(head.center.x, head.min.y, head.center.z),
                parent: "chest",
                thickness: head.size.x * 0.4
            ))
            marks.append(RigMark(name: "head", kind: .dot, position: Vec3(head.center.x, head.min.y + head.size.y * 0.3, head.center.z), parent: "neck",
                                 thickness: head.size.x))
        }
        return marks
    }

    /// Hips at the back, shoulders at the front of a body lying along z; the head ahead (BodyGuess's animal names).
    static func fourLegged(body: Bounds, head: Bounds?) -> [RigMark] {
        let y = body.min.y + body.size.y * 0.55, x = body.center.x
        let thickness = body.size.y
        var marks = [RigMark(name: "hips", kind: .dot, position: Vec3(x, y, body.min.z + body.size.z * 0.18), thickness: thickness),
                     RigMark(name: "spine", kind: .dot, position: Vec3(x, y, body.center.z), parent: "hips", thickness: thickness),
                     RigMark(name: "shoulders", kind: .dot, position: Vec3(x, y, body.max.z - body.size.z * 0.18), parent: "spine", thickness: thickness)]
        if let head {
            marks.append(RigMark(name: "neck", kind: .dot, position: Vec3(head.center.x, head.min.y + head.size.y * 0.15, head.min.z + head.size.z * 0.2),
                                 parent: "shoulders", thickness: head.size.x * 0.4))
            marks.append(RigMark(name: "head", kind: .dot, position: Vec3(head.center.x, head.min.y + head.size.y * 0.35, head.center.z), parent: "neck",
                                 thickness: head.size.x))
        }
        return marks
    }

    /// The dots of every limb, hung from the trunk joint nearest its top.
    static func limbs(_ anatomy: CharacterAnatomy, trunk: [RigMark]) -> [RigMark] {
        var marks: [RigMark] = []
        let onFour = anatomy.walksOnFour
        for job in [CharacterPart.Job.arm, .leg, .tail, .wing] {
            for (side, limb) in anatomy.limbs(job) {
                let pieces = anatomy.limb(job, side: side, limb: limb)
                guard let first = pieces.first else { continue }
                let names = jointNames(job, side: side, limb: limb, count: pieces.count, onFour: onFour)
                let parent = attachment(job, side: side, limb: limb, onFour: onFour, top: first.toRoot.position, trunk: trunk)
                var previous = parent
                if job == .arm, !onFour, limb.isEmpty, let shoulder = parent {
                    // The humanoid's shoulder: a short bone from the chest toward the arm.
                    let at = trunk.first { $0.name == shoulder }?.position.lerp(to: first.toRoot.position, 0.7) ?? first.toRoot.position
                    let name = side.humanoidPrefix + "Shoulder"
                    marks.append(RigMark(name: name, kind: .dot, position: at, parent: shoulder))
                    previous = name
                }
                for (index, piece) in pieces.enumerated() {
                    let thickness = piece.bounds.map { min($0.size.x, $0.size.z) } ?? 0
                    marks.append(RigMark(name: names[index], kind: .dot, position: piece.toRoot.position, parent: previous, thickness: thickness))
                    previous = names[index]
                }
                if let last = pieces.last, let tip = tip(of: last, job: job, onFour: onFour), names.count > pieces.count {
                    marks.append(RigMark(name: names[pieces.count], kind: .dot, position: tip, parent: previous))
                }
            }
        }
        return marks
    }

    /// Where a limb's last piece ends: the toes in front of the foot, the hand's and tail's and wing's far end.
    static func tip(of piece: CharacterAnatomy.Piece, job: CharacterPart.Job, onFour: Bool) -> Vec3? {
        guard let bounds = piece.bounds else { return nil }
        switch job {
        case .leg where !onFour: return piece.toRoot.apply(to: Vec3(bounds.center.x, bounds.min.y, bounds.max.z))
        case .arm: return piece.toRoot.apply(to: Vec3(bounds.center.x, bounds.min.y, bounds.center.z))
        case .tail: return piece.toRoot.apply(to: Vec3(bounds.center.x, bounds.center.y, bounds.min.z))
        case .wing:
            let far = piece.part.side == .right ? bounds.min.x : bounds.max.x
            return piece.toRoot.apply(to: Vec3(far, bounds.center.y, bounds.center.z))
        default: return nil
        }
    }

    /// A limb's joint names, top first (one more than its pieces when its end has a tip).
    static func jointNames(_ job: CharacterPart.Job, side: CharacterPart.Side, limb: String, count: Int, onFour: Bool) -> [String] {
        let suffix = limb.isEmpty || limb == "front" || limb == "back" ? "" : limb
        switch job {
        case .arm:
            let p = side.humanoidPrefix
            return ["\(p)UpperArm", "\(p)LowerArm", "\(p)Hand"].map { $0 + suffix } + ["\(p)HandTip" + suffix]
        case .leg where onFour:
            let name = (limb == "back" ? "back" : "front") + side.animalSide
            return ["\(name)Leg", "\(name)Knee", "\(name)Foot"].map { $0 + suffix }
        case .leg:
            let p = side.humanoidPrefix
            return ["\(p)UpperLeg", "\(p)LowerLeg", "\(p)Foot"].map { $0 + suffix } + ["\(p)Toes" + suffix]
        case .wing:
            let p = side.humanoidPrefix
            return ["\(p)Wing", "\(p)WingElbow"].map { $0 + suffix } + ["\(p)WingTip" + suffix]
        default:
            let base = "tail" + suffix
            return (0 ..< count).map { $0 == 0 ? base : "\(base)\($0 + 1)" } + ["\(base)Tip"]
        }
    }

    /// The trunk joint a limb hangs from.
    static func attachment(_ job: CharacterPart.Job, side: CharacterPart.Side, limb: String, onFour: Bool, top: Vec3,
                           trunk: [RigMark]) -> String? {
        let names = Set(trunk.map(\.name))
        let wanted: [String] = switch job {
        case .arm, .wing: onFour ? ["shoulders"] : ["chest"]
        case .leg: onFour ? [limb == "back" ? "hips" : "shoulders"] : ["hips"]
        case .tail: ["hips"]
        default: []
        }
        if let name = wanted.first(where: names.contains) { return name }
        return trunk.min { $0.position.distance(to: top) < $1.position.distance(to: top) }?.name
    }

    /// The command that rigs a made character as its parts stand now: the skeleton, and each piece riding its joint (nil
    /// when it isn't a made character). Poses keyed on joints that are gone are left alone (they do nothing).
    public static func command(_ root: ObjectID, in scene: Scene,
                               shapeBounds: (SceneObject) -> Bounds? = CharacterAnatomy.coreBounds) -> EditCommand? {
        guard scene.objects[root]?[.characterStart] != nil, let anatomy = CharacterAnatomy(root, in: scene, shapeBounds: shapeBounds) else { return nil }
        let rig = rig(marks(anatomy))
        var commands: [EditCommand] = [.setRig(root, rig)]
        let binding = RigidParts.binding(root, rig: rig, in: scene)
        if !binding.isEmpty { commands.append(.setProperties(binding)) }
        return .batch("Rig \(scene.objects[root]?.name ?? "character")", commands)
    }

    /// A change to a made character, then its rig built again from the parts it leaves (one undo step).
    public static func rigging(after change: EditCommand, root: ObjectID, in document: Document, label: String) -> EditCommand {
        var working = document
        guard (try? change.apply(to: &working)) != nil, let rig = command(root, in: working.scene) else { return change }
        return .batch(label, [change, rig])
    }

    /// The rig the marks make, a person's marked humanoid so its clips play.
    public static func rig(_ marks: [RigMark]) -> ObjectRig {
        var rig = RigMarks.rig(marks, surface: [])
        if humanoidJoints.isSubset(of: Set(rig.skeleton.names)) { rig.standard = .humanoid }
        return rig
    }
}

extension CharacterPart.Side {
    var humanoidPrefix: String { self == .right ? "right" : "left" }
    var animalSide: String { self == .right ? "Right" : "Left" }
}
