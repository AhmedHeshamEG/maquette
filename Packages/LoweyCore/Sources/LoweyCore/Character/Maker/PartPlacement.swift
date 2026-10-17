import Foundation

/// Where a part goes (K1): face parts on the front of the head (or of whatever carries the face), ears on its sides,
/// limbs from the body's sides and underside, a tail from its back, wings from its shoulders. Every answer is a place
/// in the space of the thing the part hangs from; the person moves it after if they like.
enum PartPlacement {
    /// A face part, hair, an ear or a head extra on a head (or a body carrying the face) with these bounds.
    static func onHead(_ job: CharacterPart.Job, style: String, side: CharacterPart.Side, bounds: Bounds) -> Transform {
        let s = side.sign
        func facing(_ point: Vec3) -> Transform {
            // Turned to face out from the middle of the head, a little.
            let yaw = atan2(point.x - bounds.center.x, max(bounds.size.z, 1e-6)) * 0.9
            return Transform(position: point, rotation: Quat(angle: yaw, axis: .unitY))
        }
        switch job {
        case .eye: return facing(bounds.front(across: s * 0.36, up: 0.58))
        case .brow: return facing(bounds.front(across: s * 0.36, up: 0.76))
        case .mouth: return facing(bounds.front(across: 0, up: 0.3))
        case .nose: return facing(bounds.front(across: 0, up: 0.45))
        case .ear: return ear(style: style, side: side, bounds: bounds)
        case .hair:
            // Hair is made for a 0.5 m head standing at its origin.
            let scale = bounds.size / 0.5
            return Transform(position: Vec3(bounds.center.x, bounds.min.y, bounds.center.z), scale: Vec3(scale.x, scale.y, scale.z))
        case .extra: return extra(style: style, side: side, bounds: bounds)
        default: return Transform(position: bounds.center)
        }
    }

    static func ear(style: String, side: CharacterPart.Side, bounds: Bounds) -> Transform {
        let s = side.sign
        let half = bounds.size / 2
        if style == "pointy" || style == "cat" {
            // On top, toward the side, leaning out.
            let top = Vec3(bounds.center.x + s * half.x * 0.55, bounds.min.y + bounds.size.y * 0.88, bounds.center.z)
            return Transform(position: top, rotation: Quat(angle: -s * 0.35, axis: .unitZ))
        }
        let side = Vec3(bounds.center.x + s * half.x * 0.94, bounds.min.y + bounds.size.y * (style == "floppy" ? 0.78 : 0.55), bounds.center.z)
        return Transform(position: side, rotation: Quat(angle: s * .pi / 2, axis: .unitY))
    }

    static func extra(style: String, side: CharacterPart.Side, bounds: Bounds) -> Transform {
        let s = side.sign
        let top = Vec3(bounds.center.x, bounds.max.y - bounds.size.y * 0.04, bounds.center.z)
        switch style {
        case "glasses": return Transform(position: bounds.front(across: 0, up: 0.6) + Vec3(0, 0, 0.01))
        case "hat": return Transform(position: top - Vec3(0, bounds.size.y * 0.06, 0))
        case "bow": return Transform(position: top + Vec3(s == 0 ? bounds.size.x * 0.25 : s * bounds.size.x * 0.25, 0, 0))
        default:
            let spread = s == 0 ? 0 : s * bounds.size.x * 0.28
            return Transform(position: top + Vec3(spread, -bounds.size.y * 0.04, 0))
        }
    }

    /// A face part with nothing to sit on (a bodyless creature): in the air where a face would be, stacked under what's
    /// already there.
    static func floating(_ job: CharacterPart.Job, side: CharacterPart.Side, existing: Bounds?) -> Transform {
        let s = side.sign
        guard let existing else {
            return Transform(position: Vec3(s * 0.1, job == .mouth ? 0.62 : 0.8, 0))
        }
        let below = existing.min.y - 0.06
        switch job {
        case .mouth, .nose: return Transform(position: Vec3(existing.center.x, below, existing.max.z - 0.02))
        case .brow: return Transform(position: Vec3(existing.center.x + s * existing.size.x * 0.25, existing.max.y + 0.03, existing.max.z - 0.02))
        default: return Transform(position: Vec3(existing.center.x + s * max(existing.size.x * 0.6, 0.14), existing.center.y, existing.center.z))
        }
    }

    /// The top of a limb on a body with these bounds (the character's space), and how it leans out.
    static func limbTop(_ job: CharacterPart.Job, side: CharacterPart.Side, limb: String, body: Bounds, onFour: Bool) -> Transform {
        let s = side.sign
        let half = body.size / 2
        switch job {
        case .arm:
            let top = Vec3(body.center.x + s * half.x * 0.92, body.min.y + body.size.y * 0.8, body.center.z)
            return Transform(position: top, rotation: Quat(angle: s * 0.14, axis: .unitZ))
        case .leg:
            guard onFour else { return Transform(position: Vec3(body.center.x + s * half.x * 0.42, body.min.y + 0.03, body.center.z)) }
            let z = body.center.z + (limb == "back" ? -1 : 1) * half.z * 0.66
            return Transform(position: Vec3(body.center.x + s * half.x * 0.55, body.min.y + 0.03, z))
        case .tail:
            let base = onFour ? Vec3(body.center.x, body.min.y + body.size.y * 0.7, body.min.z + 0.03)
                : Vec3(body.center.x, body.min.y + body.size.y * 0.25, body.min.z + 0.04)
            return Transform(position: base, rotation: Quat(angle: onFour ? -0.5 : 0.2, axis: .unitX))
        case .wing:
            let base = Vec3(body.center.x + s * half.x * 0.6, body.min.y + body.size.y * 0.72, body.center.z - half.z * 0.5)
            return Transform(position: base, rotation: Quat(angle: s * 0.35, axis: .unitZ) * Quat(angle: -s * 0.4, axis: .unitY))
        default:
            return Transform(position: body.center)
        }
    }

    /// Where a head sits on a body (the character's space).
    static func head(on body: Bounds, onFour: Bool) -> Transform {
        if onFour { return Transform(position: Vec3(body.center.x, body.max.y - body.size.y * 0.25, body.max.z - 0.08)) }
        return Transform(position: Vec3(body.center.x, body.max.y - 0.04, body.center.z))
    }
}
