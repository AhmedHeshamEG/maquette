import Foundation

/// Makes characters (K1, Library ▸ Characters ▸ New): a start (Person, Four legs, Wings, Blob or nothing) is a group of
/// parts, each a thing of its own with its job on `SceneObject.part`, so it can be recoloured, painted, remodelled or
/// replaced like anything else. Parts that hinge (limbs, tails, wings) are pieces, each a child of the character's group
/// so it rides its own joint; face parts, ears and hair are children of the head. The rig is built from the parts
/// (`CharacterAutoRig`) right after.
public enum CharacterMaker {
    /// A part piece to make.
    struct Piece {
        var id: ObjectID
        var parent: ObjectID?
        var name: String
        var part: CharacterPart?
        var mesh: MeshData
        var transform: Transform
        var colour: RGBA
        var role: String?
        var range: Double?
    }

    /// Builds pieces into scene objects, children listed under their parents.
    struct Builder {
        var ids: IDFactory
        var objects: [SceneObject] = []

        init(ids: IDFactory) {
            self.ids = ids
        }

        mutating func add(_ object: SceneObject) {
            var object = object
            object.children = []
            if let parent = object.parent, let index = objects.firstIndex(where: { $0.id == parent }) {
                objects[index].children.append(object.id)
            }
            objects.append(object)
        }

        mutating func root(_ name: String, start: CharacterStart, at position: Vec3) -> ObjectID {
            var object = SceneObject(id: ids.next(), name: name, kind: .group, transform: Transform(position: position))
            object[.characterStart] = .enumeration(start.rawValue)
            object[.mouth] = .enumeration(Viseme.X.rawValue)
            object[.mouthShape] = .enumeration(MouthShape.neutral.rawValue)
            add(object)
            return object.id
        }

        mutating func make(_ piece: Piece) {
            add(CharacterMaker.object(piece))
        }

        /// A part of one piece (and an eye's pupil). Returns its id.
        @discardableResult
        mutating func part(_ job: CharacterPart.Job, style: String, side: CharacterPart.Side = .middle, parent: ObjectID,
                           at transform: Transform, limb: String = "") -> ObjectID {
            let id: ObjectID = ids.next()
            let part = CharacterPart(job: job, side: side, style: style, limb: limb)
            let mesh = PartSet.mesh(job, style: style, side: side)
            make(Piece(id: id, parent: parent, name: CharacterMaker.name(of: part), part: part, mesh: mesh, transform: transform,
                       colour: PartSet.colour(for: job, style: style), role: part.faceRole, range: nil))
            if job == .eye, let pupil = PartSet.pupil(for: style) {
                make(Piece(id: ids.next(), parent: id, name: "Pupil", part: nil, mesh: pupil, transform: .identity, colour: RGBA.hex("#1E1A1C"),
                           role: part.pupilRole, range: mesh.bounds?.size.x ?? 0.1))
            }
            return id
        }

        /// The pieces of a hinged part, each hanging from where the one above it ends (the character's space).
        @discardableResult
        mutating func limb(_ job: CharacterPart.Job, style: String, side: CharacterPart.Side, limb: String = "", parent: ObjectID,
                           top: Transform) -> [ObjectID] {
            var place = top
            var made: [ObjectID] = []
            for segment in 0 ..< job.segments {
                let id: ObjectID = ids.next()
                let part = CharacterPart(job: job, side: side, style: style, segment: segment, limb: limb)
                make(Piece(id: id, parent: parent, name: CharacterMaker.name(of: part), part: part,
                           mesh: PartSet.mesh(job, style: style, segment: segment, side: side), transform: place,
                           colour: PartSet.colour(for: job, style: style), role: nil, range: nil))
                made.append(id)
                place.position = place.apply(to: PartSet.nextPivot(job, style: style, segment: segment, side: side))
            }
            return made
        }
    }

    static func object(_ piece: Piece) -> SceneObject {
        var object = SceneObject(id: piece.id, name: piece.name, kind: .mesh(savable(piece.mesh)), parent: piece.parent,
                                 transform: piece.transform)
        object[.color] = .color(.rgba(piece.colour))
        object[.smoothAngle] = .float(55)
        if let role = piece.role { object[.faceRole] = .string(role) }
        if let range = piece.range { object[.faceRange] = .float(range) }
        object.part = piece.part
        return object
    }

    /// A part's shape as it saves (corners to the nanometre, as project files keep them), so a part made and a part read back
    /// from the file are the same.
    static func savable(_ mesh: MeshData) -> EditableMesh {
        let editable = MeshBuilder.mesh(from: mesh)
        return EditableMesh(vertices: editable.vertices.map { $0.map(EditableMesh.rounded) }, faces: editable.faces)
    }

    /// "Left eye", "Upper arm", "Tail 2"…
    public static func name(of part: CharacterPart) -> String {
        let side = switch part.side {
        case .left: "Left "
        case .right: "Right "
        case .middle: ""
        }
        let limb = part.limb.isEmpty ? "" : part.limb.capitalized + " "
        let piece: String = switch (part.job, part.segment) {
        case (.arm, 0): "upper arm"
        case (.arm, 1): "forearm"
        case (.arm, _): "hand"
        case (.leg, 0): "thigh"
        case (.leg, 1): "shin"
        case (.leg, _): "foot"
        case (.tail, let segment): segment == 0 ? "tail" : "tail \(segment + 1)"
        case (.wing, let segment): segment == 0 ? "wing" : "wing tip"
        case (.eye, _): "eye"
        case (.brow, _): "brow"
        case (.ear, _): "ear"
        default: part.job.title.lowercased()
        }
        let whole = side + limb + piece
        return whole.prefix(1).uppercased() + whole.dropFirst().lowercased()
    }

    // MARK: Starting

    /// A new character of a start, standing at `position` (its feet on the ground there), as one fragment.
    public static func start(_ start: CharacterStart, name: String, at position: Vec3, ids: inout IDFactory) -> SceneFragment {
        var builder = Builder(ids: ids)
        let root = builder.root(name, start: start, at: position)
        switch start {
        case .person: person(&builder, root: root)
        case .fourLegs: fourLegs(&builder, root: root)
        case .wings: winged(&builder, root: root)
        case .blob: blob(&builder, root: root)
        case .nothing: break
        }
        ids = builder.ids
        return SceneFragment(objects: builder.objects, roots: [root])
    }

    static func person(_ builder: inout Builder, root: ObjectID) {
        let hip = PartSet.legReach("tube")
        let body = bodyBounds("bean", at: Vec3(0, hip - 0.03, 0))
        builder.part(.body, style: "bean", parent: root, at: Transform(position: Vec3(0, hip - 0.03, 0)))
        for side in [CharacterPart.Side.left, .right] {
            builder.limb(.leg, style: "tube", side: side, parent: root, top: PartPlacement.limbTop(.leg, side: side, limb: "", body: body, onFour: false))
            builder.limb(.arm, style: "tube", side: side, parent: root, top: PartPlacement.limbTop(.arm, side: side, limb: "", body: body, onFour: false))
        }
        let head = builder.part(.head, style: "round", parent: root, at: PartPlacement.head(on: body, onFour: false))
        face(&builder, on: head, bounds: headBounds("round"), eyes: "round", mouth: "oval", extras: [(.brow, "line"), (.ear, "round"), (.hair, "short")])
    }

    static func fourLegs(_ builder: inout Builder, root: ObjectID) {
        let hip = PartSet.legReach("paw")
        let body = bodyBounds("long", at: Vec3(0, hip - 0.03, 0))
        builder.part(.body, style: "long", parent: root, at: Transform(position: Vec3(0, hip - 0.03, 0)))
        for limb in ["front", "back"] {
            for side in [CharacterPart.Side.left, .right] {
                builder.limb(.leg, style: "paw", side: side, limb: limb, parent: root,
                             top: PartPlacement.limbTop(.leg, side: side, limb: limb, body: body, onFour: true))
            }
        }
        builder.limb(.tail, style: "thin", side: .middle, parent: root, top: PartPlacement.limbTop(.tail, side: .middle, limb: "", body: body, onFour: true))
        var place = PartPlacement.head(on: body, onFour: true)
        place.scale = Vec3(0.8, 0.8, 0.8)
        let head = builder.part(.head, style: "round", parent: root, at: place)
        face(&builder, on: head, bounds: headBounds("round"), eyes: "round", mouth: "oval", extras: [(.nose, "snout"), (.ear, "floppy")])
    }

    static func winged(_ builder: inout Builder, root: ObjectID) {
        let hip = PartSet.legReach("stubby")
        let body = bodyBounds("round", at: Vec3(0, hip - 0.03, 0))
        builder.part(.body, style: "round", parent: root, at: Transform(position: Vec3(0, hip - 0.03, 0)))
        for side in [CharacterPart.Side.left, .right] {
            builder.limb(.leg, style: "stubby", side: side, parent: root, top: PartPlacement.limbTop(.leg, side: side, limb: "", body: body, onFour: false))
            builder.limb(.wing, style: "feather", side: side, parent: root, top: PartPlacement.limbTop(.wing, side: side, limb: "", body: body, onFour: false))
        }
        var place = PartPlacement.head(on: body, onFour: false)
        place.scale = Vec3(0.85, 0.85, 0.85)
        let head = builder.part(.head, style: "round", parent: root, at: place)
        face(&builder, on: head, bounds: headBounds("round"), eyes: "round", mouth: "beak", extras: [])
    }

    /// The house blob: a round body that carries its own face, little arms and feet.
    static func blob(_ builder: inout Builder, root: ObjectID) {
        let hip = PartSet.legReach("stubby")
        let body = bodyBounds("round", at: Vec3(0, hip - 0.03, 0))
        let id = builder.part(.body, style: "round", parent: root, at: Transform(position: Vec3(0, hip - 0.03, 0)))
        for side in [CharacterPart.Side.left, .right] {
            builder.limb(.leg, style: "stubby", side: side, parent: root, top: PartPlacement.limbTop(.leg, side: side, limb: "", body: body, onFour: false))
            builder.limb(.arm, style: "noodle", side: side, parent: root, top: PartPlacement.limbTop(.arm, side: side, limb: "", body: body, onFour: false))
        }
        face(&builder, on: id, bounds: bodyBounds("round", at: .zero), eyes: "round", mouth: "grin", extras: [])
    }

    /// Eyes (a pair), a mouth and the extras on a head (in its space).
    static func face(_ builder: inout Builder, on head: ObjectID, bounds: Bounds, eyes: String, mouth: String,
                     extras: [(CharacterPart.Job, String)]) {
        for side in [CharacterPart.Side.left, .right] {
            builder.part(.eye, style: eyes, side: side, parent: head, at: PartPlacement.onHead(.eye, style: eyes, side: side, bounds: bounds))
        }
        builder.part(.mouth, style: mouth, parent: head, at: PartPlacement.onHead(.mouth, style: mouth, side: .middle, bounds: bounds))
        for (job, style) in extras {
            for side in job.isPaired ? [CharacterPart.Side.left, .right] : [.middle] {
                builder.part(job, style: style, side: side, parent: head, at: PartPlacement.onHead(job, style: style, side: side, bounds: bounds))
            }
        }
    }

    static func headBounds(_ style: String) -> Bounds {
        PartSet.mesh(.head, style: style).bounds ?? Bounds(min: Vec3(-0.25, 0, -0.25), max: Vec3(0.25, 0.5, 0.25))
    }

    static func bodyBounds(_ style: String, at position: Vec3) -> Bounds {
        let local = PartSet.mesh(.body, style: style).bounds ?? Bounds(min: Vec3(-0.2, 0, -0.2), max: Vec3(0.2, 0.5, 0.2))
        return Bounds(min: local.min + position, max: local.max + position)
    }
}
