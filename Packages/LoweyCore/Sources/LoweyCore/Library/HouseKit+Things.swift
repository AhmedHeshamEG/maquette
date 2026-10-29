import Foundation

/// How each of the house kit's things is laid out from its size. Thicknesses that read as "made of something" (a
/// leg, a board, a wall's frame) stay fixed while the size changes; counts (shelves, steps, slats) follow it.
extension HouseKit.Maker {
    typealias Swatch = HouseKit.Swatch

    // MARK: Home

    mutating func home(_ item: HouseKit.Item, _ size: Vec3) {
        let (w, h, d) = (size.x, size.y, size.z)
        switch item {
        case .table:
            let top = min(0.05, h * 0.1), leg = min(0.07, w * 0.12, d * 0.12)
            legs(width: w, depth: d, height: h - top, thickness: leg, inset: leg * 0.6, color: Swatch.darkWood)
            part(.cube, "Top", at: Vec3(0, h - top, 0), size: Vec3(w, top, d), color: Swatch.wood)
        case .chair:
            let seat = h * 0.5, board = 0.045, leg = min(0.045, w * 0.12)
            legs(width: w, depth: d, height: seat - board, thickness: leg, inset: leg * 0.4, color: Swatch.darkWood)
            part(.cube, "Seat", at: Vec3(0, seat - board, 0), size: Vec3(w, board, d), color: Swatch.wood)
            part(.cube, "Back", at: Vec3(0, seat, -d / 2 + board / 2), size: Vec3(w, h - seat, board), color: Swatch.wood)
        case .stool:
            let board = 0.05, leg = min(0.04, w * 0.14)
            legs(width: w * 0.9, depth: d * 0.9, height: h - board, thickness: leg, inset: leg * 0.4, color: Swatch.darkWood)
            part(.cylinder, "Seat", at: Vec3(0, h - board, 0), size: Vec3(w, board, d), color: Swatch.wood)
        case .bed, .sofa:
            softFurniture(item, size)
        case .shelf:
            let board = 0.03
            for side in [-1.0, 1.0] {
                part(.cube, "Side", at: Vec3(side * (w / 2 - board / 2), 0, 0), size: Vec3(board, h, d), color: Swatch.wood)
            }
            part(.cube, "Back", at: Vec3(0, 0, -d / 2 + 0.01), size: Vec3(w - board * 2, h, 0.02), color: Swatch.darkWood)
            let shelves = max(2, Int((h / 0.36).rounded()))
            for index in 0 ... shelves {
                let y = min(Double(index) * (h - board) / Double(shelves), h - board)
                part(.cube, "Board", at: Vec3(0, y, 0), size: Vec3(w - board * 2, board, d), color: Swatch.wood)
            }
        case .floorLamp:
            part(.cylinder, "Foot", at: .zero, size: Vec3(w * 0.7, 0.04, d * 0.7), color: Swatch.metal)
            part(.cylinder, "Pole", at: Vec3(0, 0.04, 0), size: Vec3(0.03, h - 0.3, 0.03), color: Swatch.metal)
            part(.cone, "Shade", at: Vec3(0, h - 0.34, 0), size: Vec3(w, 0.34, d), color: Swatch.cream)
        case .rug:
            part(.cube, "Rug", at: .zero, size: Vec3(w, max(h, 0.01), d), color: Swatch.red, soft: 0.3)
            part(.cube, "Border", at: Vec3(0, max(h, 0.01), 0), size: Vec3(w * 0.8, 0.004, d * 0.75), color: Swatch.cream, soft: 0.1)
        case .pottedPlant:
            let pot = h * 0.35
            part(.cylinder, "Pot", at: .zero, size: Vec3(w * 0.7, pot, d * 0.7), color: Swatch.terracotta)
            part(.cylinder, "Soil", at: Vec3(0, pot, 0), size: Vec3(w * 0.62, 0.02, d * 0.62), color: Swatch.soil)
            part(.sphere, "Leaves", at: Vec3(0, pot * 0.9, 0), size: Vec3(w, h - pot * 0.9, d), color: Swatch.leaf)
        default:
            break
        }
    }

    /// The soft things to sit and lie on.
    private mutating func softFurniture(_ item: HouseKit.Item, _ size: Vec3) {
        let (w, h, d) = (size.x, size.y, size.z)
        switch item {
        case .bed:
            let frame = h * 0.35, mattress = min(0.22, h * 0.25)
            part(.cube, "Frame", at: Vec3(0, 0, 0), size: Vec3(w, frame, d), color: Swatch.wood)
            part(.cube, "Mattress", at: Vec3(0, frame, 0.02), size: Vec3(w - 0.08, mattress, d - 0.12), color: Swatch.cream)
            part(.cube, "Blanket", at: Vec3(0, frame + 0.01, d * 0.12), size: Vec3(w - 0.04, mattress, d * 0.62), color: Swatch.fabric)
            part(.cube, "Pillow", at: Vec3(0, frame + mattress, -d / 2 + 0.3), size: Vec3(w * 0.6, 0.12, 0.34), color: Swatch.cream, soft: 2)
            part(.cube, "Headboard", at: Vec3(0, 0, -d / 2 + 0.03), size: Vec3(w, h, 0.06), color: Swatch.darkWood)
        case .sofa:
            let seat = h * 0.5, arm = min(0.22, w * 0.12), back = min(0.25, d * 0.3)
            part(.cube, "Base", at: Vec3(0, 0, 0), size: Vec3(w, seat * 0.6, d), color: Swatch.fabric, soft: 2)
            let cushions = max(1, Int((w - arm * 2) / 0.7))
            let cushionWidth = (w - arm * 2) / Double(cushions)
            for index in 0 ..< cushions {
                let x = -w / 2 + arm + cushionWidth * (Double(index) + 0.5)
                part(.cube, "Cushion", at: Vec3(x, seat * 0.6, back / 2), size: Vec3(cushionWidth - 0.02, seat * 0.4, d - back), color: Swatch.fabric,
                     soft: 2.5)
            }
            part(.cube, "Back", at: Vec3(0, seat * 0.6, -d / 2 + back / 2), size: Vec3(w, h - seat * 0.6, back), color: Swatch.fabric, soft: 2.5)
            for side in [-1.0, 1.0] {
                part(.cube, "Arm", at: Vec3(side * (w / 2 - arm / 2), seat * 0.6, 0), size: Vec3(arm, seat * 0.55, d), color: Swatch.fabric,
                     soft: 2.5)
            }
        default:
            break
        }
    }

    /// Four legs at the corners, `inset` in from the edges.
    private mutating func legs(width: Double, depth: Double, height: Double, thickness: Double, inset: Double, color: RGBA) {
        for x in [-1.0, 1.0] {
            for z in [-1.0, 1.0] {
                let at = Vec3(x * (width / 2 - inset - thickness / 2), 0, z * (depth / 2 - inset - thickness / 2))
                part(.cube, "Leg", at: at, size: Vec3(thickness, max(height, 0.01), thickness), color: color)
            }
        }
    }

    // MARK: Building

    mutating func building(_ item: HouseKit.Item, _ size: Vec3) {
        let (w, h, d) = (size.x, size.y, size.z)
        switch item {
        case .wall:
            part(.cube, "Wall", at: .zero, size: size, color: Swatch.wall, soft: 0.4)
        case .doorway:
            // A wall with a door-sized gap in the middle: two sides and a lintel.
            let door = Vec3(min(0.9, w * 0.5), min(2.1, h * 0.85), d)
            let side = (w - door.x) / 2
            for x in [-1.0, 1.0] {
                part(.cube, "Wall", at: Vec3(x * (door.x / 2 + side / 2), 0, 0), size: Vec3(side, h, d), color: Swatch.wall, soft: 0.4)
            }
            part(.cube, "Lintel", at: Vec3(0, door.y, 0), size: Vec3(door.x, h - door.y, d), color: Swatch.wall, soft: 0.4)
            part(.cube, "Frame", at: Vec3(0, door.y, 0), size: Vec3(door.x + 0.08, 0.06, d + 0.02), color: Swatch.darkWood)
        case .window:
            let pane = Vec3(min(1.2, w * 0.5), min(1.2, h * 0.45), d)
            let sill = h * 0.35, side = (w - pane.x) / 2
            for x in [-1.0, 1.0] {
                part(.cube, "Wall", at: Vec3(x * (pane.x / 2 + side / 2), 0, 0), size: Vec3(side, h, d), color: Swatch.wall, soft: 0.4)
            }
            part(.cube, "Wall below", at: .zero, size: Vec3(pane.x, sill, d), color: Swatch.wall, soft: 0.4)
            part(.cube, "Wall above", at: Vec3(0, sill + pane.y, 0), size: Vec3(pane.x, h - sill - pane.y, d), color: Swatch.wall, soft: 0.4)
            part(.cube, "Glass", at: Vec3(0, sill, 0), size: Vec3(pane.x, pane.y, 0.02), color: Swatch.glass, soft: 0.2)
            part(.cube, "Mullion", at: Vec3(0, sill, 0), size: Vec3(0.05, pane.y, d * 0.6), color: Swatch.cream)
            part(.cube, "Sill", at: Vec3(0, sill - 0.04, 0.03), size: Vec3(pane.x + 0.12, 0.05, d + 0.08), color: Swatch.cream)
        case .stairs:
            let steps = max(2, Int((h / 0.18).rounded()))
            let rise = h / Double(steps), run = d / Double(steps)
            for index in 0 ..< steps {
                let z = d / 2 - run * (Double(index) + 0.5)
                part(.cube, "Step", at: Vec3(0, 0, z), size: Vec3(w, rise * Double(index + 1), run), color: Swatch.wood, soft: 0.5)
            }
        case .floorTile:
            part(.cube, "Floor", at: .zero, size: size, color: Swatch.wood, soft: 0.3)
        default:
            break
        }
    }

    // MARK: Nature

    mutating func nature(_ item: HouseKit.Item, _ size: Vec3) {
        let (w, h, d) = (size.x, size.y, size.z)
        switch item {
        case .roundTree:
            let trunk = h * 0.4
            part(.cylinder, "Trunk", at: .zero, size: Vec3(w * 0.12, trunk + h * 0.1, d * 0.12), color: Swatch.bark)
            part(.sphere, "Crown", at: Vec3(0, trunk, 0), size: Vec3(w, h - trunk, d), color: Swatch.leaf)
            part(.sphere, "Crown", at: Vec3(w * 0.22, trunk * 0.85, d * 0.1), size: Vec3(w * 0.55, (h - trunk) * 0.55, d * 0.55), color: Swatch.leaf)
        case .pine:
            let trunk = h * 0.15
            part(.cylinder, "Trunk", at: .zero, size: Vec3(w * 0.12, trunk + 0.2, d * 0.12), color: Swatch.bark)
            let tiers = 3
            for index in 0 ..< tiers {
                let share = 1 - Double(index) * 0.25
                let y = trunk + (h - trunk) * Double(index) * 0.25
                part(.cone, "Needles", at: Vec3(0, y, 0), size: Vec3(w * share, (h - trunk) * 0.5, d * share), color: Swatch.pine)
            }
        case .bush:
            part(.sphere, "Bush", at: .zero, size: Vec3(w * 0.75, h, d * 0.85), color: Swatch.leaf)
            part(.sphere, "Bush", at: Vec3(w * 0.25, 0, d * 0.05), size: Vec3(w * 0.5, h * 0.75, d * 0.6), color: Swatch.leaf)
            part(.sphere, "Bush", at: Vec3(-w * 0.28, 0, -d * 0.05), size: Vec3(w * 0.45, h * 0.65, d * 0.55), color: Swatch.leaf)
        case .rock:
            part(.sphere, "Rock", at: Vec3(0, -h * 0.15, 0), size: Vec3(w, h * 1.15, d), color: Swatch.stone,
                 turn: Quat(angle: 0.35, axis: .unitY))
            part(.sphere, "Pebble", at: Vec3(w * 0.45, -h * 0.05, d * 0.3), size: Vec3(w * 0.35, h * 0.4, d * 0.35), color: Swatch.stone)
        case .flower:
            part(.cylinder, "Stem", at: .zero, size: Vec3(0.012, h * 0.8, 0.012), color: Swatch.pine)
            part(.sphere, "Leaf", at: Vec3(0.03, h * 0.25, 0), size: Vec3(0.07, 0.02, 0.035), color: Swatch.leaf)
            part(.cylinder, "Petals", at: Vec3(0, h * 0.8, 0), size: Vec3(w, 0.03, d), color: Swatch.red, soft: 0.5)
            part(.sphere, "Heart", at: Vec3(0, h * 0.8 + 0.01, 0), size: Vec3(w * 0.35, 0.05, d * 0.35), color: Swatch.yellow)
        default:
            break
        }
    }

    // MARK: City

    mutating func city(_ item: HouseKit.Item, _ size: Vec3) {
        let (w, h, d) = (size.x, size.y, size.z)
        switch item {
        case .bench:
            let seat = h * 0.5, slat = 0.04
            for x in [-1.0, 1.0] {
                part(.cube, "Leg", at: Vec3(x * (w / 2 - 0.12), 0, 0), size: Vec3(0.06, seat, d * 0.8), color: Swatch.metal)
            }
            let slats = max(2, Int((d * 0.8 / 0.12).rounded()))
            for index in 0 ..< slats {
                let z = -d * 0.4 + d * 0.8 * (Double(index) + 0.5) / Double(slats)
                part(.cube, "Slat", at: Vec3(0, seat, z), size: Vec3(w, slat, d * 0.8 / Double(slats) - 0.015), color: Swatch.wood)
            }
            part(.cube, "Back", at: Vec3(0, seat + 0.12, -d / 2 + 0.04), size: Vec3(w, h - seat - 0.12, slat * 2),
                 color: Swatch.wood, turn: Quat(angle: -0.15, axis: .unitX))
        case .streetLamp:
            part(.cylinder, "Base", at: .zero, size: Vec3(w * 0.5, 0.3, d * 0.5), color: Swatch.metal)
            part(.cylinder, "Post", at: Vec3(0, 0.3, 0), size: Vec3(0.09, h - 0.65, 0.09), color: Swatch.metal)
            part(.cylinder, "Lantern", at: Vec3(0, h - 0.4, 0), size: Vec3(w * 0.6, 0.3, d * 0.6), color: Swatch.yellow)
            part(.cone, "Cap", at: Vec3(0, h - 0.12, 0), size: Vec3(w, 0.12, d), color: Swatch.metal)
        case .cottage:
            let walls = h * 0.55
            part(.cube, "Walls", at: .zero, size: Vec3(w, walls, d), color: Swatch.wall, soft: 0.6)
            // The roof: two slabs, each centred on its slope, meeting at the ridge and overhanging the walls.
            let rise = h - walls
            let slope = atan2(rise, d / 2)
            let length = (rise * rise + d * d / 4).squareRoot() + 0.5
            for side in [-1.0, 1.0] {
                part(.cube, "Roof", at: Vec3(0, walls + rise / 2 - 0.1, side * d / 4), size: Vec3(w + 0.4, 0.14, length), color: Swatch.roof,
                     turn: Quat(angle: side * slope, axis: .unitX))
            }
            part(.cube, "Door", at: Vec3(-w * 0.15, 0, d / 2), size: Vec3(0.9, min(2, walls * 0.8), 0.08), color: Swatch.darkWood)
            part(.cube, "Window", at: Vec3(w * 0.25, walls * 0.4, d / 2), size: Vec3(0.9, 0.8, 0.06), color: Swatch.glass, soft: 0.3)
            part(.cube, "Chimney", at: Vec3(w * 0.3, walls + (h - walls) * 0.3, -d * 0.15), size: Vec3(0.45, (h - walls) * 0.7, 0.45),
                 color: Swatch.stone)
        case .car:
            let wheel = min(0.62, h * 0.43), body = h * 0.45
            part(.cube, "Body", at: Vec3(0, wheel * 0.45, 0), size: Vec3(w, body, d), color: Swatch.red, soft: 3)
            part(.cube, "Cabin", at: Vec3(0, wheel * 0.45 + body, -d * 0.06), size: Vec3(w * 0.85, h - wheel * 0.45 - body, d * 0.5),
                 color: Swatch.red, soft: 3)
            part(.cube, "Windows", at: Vec3(0, wheel * 0.45 + body + 0.06, -d * 0.06), size: Vec3(w * 0.87, (h - wheel * 0.45 - body) * 0.7, d * 0.46),
                 color: Swatch.glass, soft: 2)
            for x in [-1.0, 1.0] {
                for z in [-1.0, 1.0] {
                    // A cylinder turned on its side: its axis runs along x from where it's put, so it starts at its outer face.
                    let outer = x > 0 ? w / 2 + 0.02 : -w / 2 + 0.2
                    part(.cylinder, "Wheel", at: Vec3(outer, wheel / 2, z * d * 0.32), size: Vec3(wheel, 0.22, wheel), color: Swatch.metal,
                         turn: Quat(angle: .pi / 2, axis: .unitZ))
                }
            }
        default:
            break
        }
    }

    // MARK: Props, game blocks and people

    mutating func props(_ item: HouseKit.Item, _ size: Vec3) {
        let (w, h, d) = (size.x, size.y, size.z)
        switch item {
        case .crate:
            part(.cube, "Crate", at: .zero, size: size, color: Swatch.wood)
            for z in [-1.0, 1.0] {
                part(.cube, "Plank", at: Vec3(0, h * 0.42, z * d / 2), size: Vec3(w + 0.01, h * 0.16, 0.03), color: Swatch.darkWood)
            }
        case .barrel:
            part(.cylinder, "Barrel", at: .zero, size: size, color: Swatch.wood, soft: 2)
            for y in [0.15, 0.8] {
                part(.cylinder, "Hoop", at: Vec3(0, h * y, 0), size: Vec3(w + 0.02, 0.04, d + 0.02), color: Swatch.metal, soft: 0.3)
            }
        case .mug:
            part(.cylinder, "Mug", at: .zero, size: Vec3(d, h, d), color: Swatch.cream)
            part(.cube, "Handle", at: Vec3(d / 2 + (w - d) / 2, h * 0.25, 0), size: Vec3(max(w - d, 0.015), h * 0.5, 0.015), color: Swatch.cream)
        case .books:
            let colors = [Swatch.fabric, Swatch.red, Swatch.yellow, Swatch.pine]
            let count = max(1, Int((h / 0.04).rounded()))
            for index in 0 ..< count {
                let shift = Double(index % 2 == 0 ? 1 : -1) * w * 0.04
                part(.cube, "Book", at: Vec3(shift, h * Double(index) / Double(count), 0), size: Vec3(w * 0.92, h / Double(count) - 0.002, d),
                     color: colors[index % colors.count], soft: 0.3)
            }
        case .ball:
            part(.sphere, "Ball", at: .zero, size: size, color: Swatch.red)
        case .block:
            part(.cube, "Block", at: .zero, size: size, color: Swatch.grey, soft: 2)
        case .step:
            part(.cube, "Step", at: .zero, size: size, color: Swatch.grey, soft: 2)
        case .coin:
            part(.cylinder, "Coin", at: Vec3(0, h / 2, -d / 2), size: Vec3(w, d, h), color: Swatch.yellow, turn: Quat(angle: .pi / 2, axis: .unitX))
        case .person:
            // A scale figure: no face, no clothes, just how big a person is.
            let legs = h * 0.47, body = h * 0.33, head = h * 0.13
            for x in [-1.0, 1.0] {
                part(.cylinder, "Leg", at: Vec3(x * w * 0.14, 0, 0), size: Vec3(w * 0.24, legs, d * 0.6), color: Swatch.metal)
            }
            part(.cube, "Body", at: Vec3(0, legs, 0), size: Vec3(w * 0.75, body, d), color: Swatch.grey, soft: 3)
            for x in [-1.0, 1.0] {
                part(.cylinder, "Arm", at: Vec3(x * w * 0.44, legs + body * 0.05, 0), size: Vec3(w * 0.16, body * 0.95, d * 0.5), color: Swatch.grey)
            }
            part(.sphere, "Head", at: Vec3(0, h - head - 0.02, 0), size: Vec3(head * 0.85, head, head * 0.9), color: Swatch.skin)
        default:
            break
        }
    }
}
