import Foundation

/// Maquette's own kit (CONTEXT §10.9, M14's starting library, folded into Q2): things built by our code from soft,
/// chunky shapes, slightly toy-scale and low on detail on purpose, so they sit together in every Look. Each one is
/// made at a size (width, height, depth in metres) and keeps its proportions right when that changes: a longer table
/// keeps its legs at the corners and their thickness, a taller shelf gains shelves. The free CC0 packs stay as
/// "More sets".
///
/// A thing is a group (pivot at the base centre, facing +Z) of ordinary bevelled shapes: it can be taken apart,
/// recoloured and painted like anything made by hand.
public enum HouseKit {
    public enum Category: String, CaseIterable, Sendable, Identifiable {
        case home, building, nature, city, props, game, people

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .home: "Home"
            case .building: "Building"
            case .nature: "Nature"
            case .city: "City"
            case .props: "Props"
            case .game: "Game blocks"
            case .people: "Scale people"
            }
        }
    }

    public enum Item: String, CaseIterable, Sendable, Identifiable {
        case table, chair, stool, bed, sofa, shelf, floorLamp, rug, pottedPlant
        case wall, doorway, window, stairs, floorTile
        case roundTree, pine, bush, rock, flower
        case bench, streetLamp, cottage, car
        case crate, barrel, mug, books, ball
        case block, step, coin
        case person

        public var id: String { rawValue }
        /// The library's id for it.
        public var libraryID: String { "house.\(rawValue)" }

        public var title: String {
            switch self {
            case .table: "Table"
            case .chair: "Chair"
            case .stool: "Stool"
            case .bed: "Bed"
            case .sofa: "Sofa"
            case .shelf: "Shelf"
            case .floorLamp: "Floor lamp"
            case .rug: "Rug"
            case .pottedPlant: "Potted plant"
            case .wall: "Wall"
            case .doorway: "Doorway"
            case .window: "Window"
            case .stairs: "Stairs"
            case .floorTile: "Floor"
            case .roundTree: "Tree"
            case .pine: "Pine"
            case .bush: "Bush"
            case .rock: "Rock"
            case .flower: "Flower"
            case .bench: "Bench"
            case .streetLamp: "Street lamp"
            case .cottage: "Cottage"
            case .car: "Car"
            case .crate: "Crate"
            case .barrel: "Barrel"
            case .mug: "Mug"
            case .books: "Books"
            case .ball: "Ball"
            case .block: "Block"
            case .step: "Step"
            case .coin: "Coin"
            case .person: "Person"
            }
        }

        public var category: Category {
            switch self {
            case .table, .chair, .stool, .bed, .sofa, .shelf, .floorLamp, .rug, .pottedPlant: .home
            case .wall, .doorway, .window, .stairs, .floorTile: .building
            case .roundTree, .pine, .bush, .rock, .flower: .nature
            case .bench, .streetLamp, .cottage, .car: .city
            case .crate, .barrel, .mug, .books, .ball: .props
            case .block, .step, .coin: .game
            case .person: .people
            }
        }

        /// Words search finds it by, besides its name.
        public var tags: [String] {
            switch category {
            case .home: ["home", "furniture", "room", "house kit"]
            case .building: ["building", "architecture", "room", "house kit"]
            case .nature: ["nature", "outdoor", "plant", "house kit"]
            case .city: ["city", "street", "outdoor", "house kit"]
            case .props: ["prop", "object", "house kit"]
            case .game: ["game", "greybox", "level", "house kit"]
            case .people: ["person", "scale", "human", "house kit"]
            }
        }

        /// Its real size when placed: width (x), height (y), depth (z), in metres.
        public var size: Vec3 {
            switch self {
            case .table: Vec3(1.4, 0.75, 0.8)
            case .chair: Vec3(0.46, 0.9, 0.5)
            case .stool: Vec3(0.38, 0.65, 0.38)
            case .bed: Vec3(1.5, 0.95, 2.1)
            case .sofa: Vec3(2, 0.85, 0.9)
            case .shelf: Vec3(0.9, 1.8, 0.35)
            case .floorLamp: Vec3(0.4, 1.6, 0.4)
            case .rug: Vec3(2, 0.02, 1.4)
            case .pottedPlant: Vec3(0.45, 0.9, 0.45)
            case .wall: Vec3(3, 2.6, 0.15)
            case .doorway: Vec3(3, 2.6, 0.15)
            case .window: Vec3(3, 2.6, 0.15)
            case .stairs: Vec3(1, 1.5, 2.4)
            case .floorTile: Vec3(4, 0.08, 4)
            case .roundTree: Vec3(2.4, 4.2, 2.4)
            case .pine: Vec3(1.8, 5, 1.8)
            case .bush: Vec3(1.2, 0.8, 1)
            case .rock: Vec3(1, 0.6, 0.8)
            case .flower: Vec3(0.2, 0.45, 0.2)
            case .bench: Vec3(1.6, 0.85, 0.6)
            case .streetLamp: Vec3(0.5, 4, 0.5)
            case .cottage: Vec3(5, 4.6, 4.5)
            case .car: Vec3(1.8, 1.45, 3.9)
            case .crate: Vec3(0.6, 0.6, 0.6)
            case .barrel: Vec3(0.6, 0.9, 0.6)
            case .mug: Vec3(0.1, 0.1, 0.08)
            case .books: Vec3(0.24, 0.16, 0.18)
            case .ball: Vec3(0.24, 0.24, 0.24)
            case .block: Vec3(1, 1, 1)
            case .step: Vec3(2, 0.5, 1)
            case .coin: Vec3(0.5, 0.5, 0.08)
            case .person: Vec3(0.5, 1.75, 0.3)
            }
        }
    }

    /// The things of a category, in browsing order.
    public static func items(in category: Category) -> [Item] {
        Item.allCases.filter { $0.category == category }
    }

    /// The thing whose library id this is.
    public static func item(libraryID: String) -> Item? {
        guard libraryID.hasPrefix("house.") else { return nil }
        return Item(rawValue: String(libraryID.dropFirst("house.".count)))
    }

    /// Builds a thing at a size (its own when nil): a group named for it, with its parts as children.
    public static func build(_ item: Item, size: Vec3? = nil, ids: IDFactory = .random) -> SceneFragment {
        var maker = Maker(item: item, ids: ids)
        let size = size.map { Vec3(max($0.x, 0.02), max($0.y, 0.01), max($0.z, 0.02)) } ?? item.size
        maker.make(item, size: size)
        return maker.fragment
    }
}

// MARK: - The colours

extension HouseKit {
    /// One warm, slightly muted palette for the whole kit.
    enum Swatch {
        static let wood = RGBA.hex("#C8956B")
        static let darkWood = RGBA.hex("#8A5A3C")
        static let fabric = RGBA.hex("#6C8EBF")
        static let cream = RGBA.hex("#EFE6D2")
        static let leaf = RGBA.hex("#6FAE5C")
        static let pine = RGBA.hex("#3F7F55")
        static let bark = RGBA.hex("#7A5236")
        static let stone = RGBA.hex("#8C8A93")
        static let metal = RGBA.hex("#5B6170")
        static let red = RGBA.hex("#D9644A")
        static let yellow = RGBA.hex("#F2C14E")
        static let wall = RGBA.hex("#E8E1D5")
        static let roof = RGBA.hex("#B5523B")
        static let glass = RGBA.hex("#9CC9E0")
        static let skin = RGBA.hex("#F2C9A0")
        static let grey = RGBA.hex("#B8BCC4")
        static let soil = RGBA.hex("#5C4433")
        static let terracotta = RGBA.hex("#C46A45")
    }
}

// MARK: - Making

extension HouseKit {
    struct Maker {
        var ids: IDFactory
        var objects: [SceneObject] = []
        let root: ObjectID

        init(item: Item, ids: IDFactory) {
            self.ids = ids
            let root: ObjectID = self.ids.next()
            self.root = root
            objects.append(SceneObject(id: root, name: item.title, kind: .group))
        }

        var fragment: SceneFragment { SceneFragment(objects: objects, roots: [root]) }

        /// One part: a bevelled shape whose base centre sits at `at`, in the thing's own space.
        mutating func part(_ shape: PrimitiveShape, _ name: String, at position: Vec3, size: Vec3, color: RGBA, turn: Quat = .identity,
                           soft: Double = 1) {
            let id: ObjectID = ids.next()
            var object = SceneObject(id: id, name: name, kind: .primitive(shape), parent: root,
                                     transform: Transform(position: position, rotation: turn, scale: size))
            object[.color] = .color(.rgba(color))
            if BevelSpec.applies(to: shape) {
                // Chunky: a rounder edge than a new shape's, never more than a quarter of the part's thinnest side.
                let thinnest = min(size.x, size.y, size.z)
                object[.bevel] = .float(min(0.035 * soft, thinnest * 0.25))
                object[.bevelSegments] = .int(3)
            }
            objects.append(object)
            objects[0].children.append(id)
        }

        mutating func make(_ item: Item, size: Vec3) {
            switch item.category {
            case .home: home(item, size)
            case .building: building(item, size)
            case .nature: nature(item, size)
            case .city: city(item, size)
            case .props, .game, .people: props(item, size)
            }
        }
    }
}
