import Foundation

/// Where an added part goes on the character as it stands (`CharacterAnatomy`).
extension CharacterMaker {
    /// Hinged parts: a pair (or one, or a tail) hanging from the body; another set when there are already some. Legs
    /// added to a body that sits on the ground lift it by their length (`rise`).
    static func addLimbs(_ job: CharacterPart.Job, style: String, symmetric: Bool, anatomy: CharacterAnatomy,
                         builder: inout Builder) -> (made: [ObjectID], rise: Double) {
        let body = anatomy.body?.rootBounds ?? anatomy.head?.rootBounds ?? Bounds(min: Vec3(-0.15, 0, -0.15), max: Vec3(0.15, 0.4, 0.15))
        let onFour = job == .leg && (anatomy.walksOnFour || body.size.z > body.size.y * 1.4)
        let existing = anatomy.limbs(job)
        var limbs: [String] = [nextLimb(existing.map(\.limb))]
        if onFour, existing.isEmpty { limbs = ["front", "back"] }
        let sides: [CharacterPart.Side] = !job.isPaired ? [.middle] : (symmetric ? [.left, .right] : [freeSide(existing, limb: limbs[0])])
        var rise = 0.0
        if job == .leg, anatomy.pieces(.leg).isEmpty {
            rise = max(PartSet.legReach(style) - (body.min.y + 0.03), 0)
        }
        var made: [ObjectID] = []
        for limb in limbs {
            for side in sides {
                var top = PartPlacement.limbTop(job, side: side, limb: limb, body: body, onFour: onFour)
                top.position.y += rise
                // Another pair of arms sits lower; another tail beside the first.
                let prior = Double(existing.filter { $0.side == side }.count)
                if job == .arm { top.position.y -= prior * body.size.y * 0.22 }
                if job == .tail { top.position.x += prior * 0.08 }
                made += builder.limb(job, style: style, side: side, limb: limb, parent: anatomy.root, top: top).prefix(job.segments)
            }
        }
        return (made, rise)
    }

    /// The first unused limb name: "" for the first, then "2", "3"…
    static func nextLimb(_ used: [String]) -> String {
        guard used.contains("") else { return "" }
        var number = 2
        while used.contains(String(number)) {
            number += 1
        }
        return String(number)
    }

    static func freeSide(_ existing: [(side: CharacterPart.Side, limb: String)], limb: String) -> CharacterPart.Side {
        existing.contains { $0.side == .left && $0.limb == limb } ? .right : .left
    }

    /// Parts of one piece: a head, a body, and the face parts, ears, hair and extras on the head (or on the body when
    /// there's no head, or in the air when there's neither).
    static func addSingles(_ job: CharacterPart.Job, style: String, styleChosen: Bool, symmetric: Bool, anatomy: CharacterAnatomy,
                           builder: inout Builder) -> [(parent: ObjectID, made: [ObjectID])] {
        switch job {
        case .head:
            return [(anatomy.root, [builder.part(.head, style: style, parent: anatomy.root, at: headPlace(anatomy))])]
        case .body:
            return [(anatomy.root, [builder.part(.body, style: style, parent: anatomy.root, at: bodyPlace(style, anatomy))])]
        default:
            break
        }
        let host = anatomy.head ?? anatomy.body
        let count = anatomy.pieces(job).filter { $0.part.shows == nil }.count
        var sides: [CharacterPart.Side] = job.isPaired && symmetric ? [.left, .right] : [.middle]
        if job.isPaired, count >= 2 { sides = [.middle] }
        guard let host, let bounds = host.bounds else {
            // A bodyless creature: its first eye is one big eye unless a style was picked.
            let floatingStyle = job == .eye && count == 0 && !styleChosen ? "big" : style
            let floatingSides: [CharacterPart.Side] = job == .eye && count == 0 && !styleChosen ? [.middle] : sides
            let made = floatingSides.map { side in
                builder.part(job, style: floatingStyle, side: side, parent: anatomy.root,
                             at: PartPlacement.floating(job, side: side, existing: count == 0 && job == .eye ? nil : anatomy.bounds))
            }
            return [(anatomy.root, made)]
        }
        let made = sides.map { side -> ObjectID in
            var place = PartPlacement.onHead(job, style: style, side: side, bounds: bounds)
            if count >= (job.isPaired ? 2 : 1) {
                // Another one goes above the ones already there.
                place.position.y += bounds.size.y * 0.16 * Double(count / (job.isPaired ? 2 : 1))
            }
            return builder.part(job, style: style, side: side, parent: host.id, at: place)
        }
        return [(host.id, made)]
    }

    /// A head: on the body, beside another head, or in the air.
    static func headPlace(_ anatomy: CharacterAnatomy) -> Transform {
        if let other = anatomy.head?.rootBounds {
            return Transform(position: Vec3(other.max.x + other.size.x * 0.55, other.min.y, other.center.z))
        }
        if let body = anatomy.body?.rootBounds { return PartPlacement.head(on: body, onFour: anatomy.walksOnFour) }
        return Transform(position: Vec3(0, 0.5, 0))
    }

    /// A body: under the head, beside another body, or standing on the ground (on the legs' tops when there are legs).
    static func bodyPlace(_ style: String, _ anatomy: CharacterAnatomy) -> Transform {
        let size = PartSet.mesh(.body, style: style).bounds?.size ?? Vec3(0.4, 0.5, 0.3)
        if let other = anatomy.body?.rootBounds {
            return Transform(position: Vec3(other.max.x + size.x * 0.6, other.min.y, other.center.z))
        }
        if let head = anatomy.head?.rootBounds {
            return Transform(position: Vec3(head.center.x, max(head.min.y - size.y + 0.04, 0), head.center.z))
        }
        let legTops = anatomy.pieces(.leg).filter { $0.part.segment == 0 }.map(\.toRoot.position.y)
        return Transform(position: Vec3(0, (legTops.max() ?? 0.03) - 0.03, 0))
    }
}
