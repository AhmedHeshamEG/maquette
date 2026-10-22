import Foundation

/// A building's drawings and rooms from its things (G1, Room): one plan a floor (the ground and the top of every other
/// floor slab), the four elevations, and each floor's rooms as IFC spaces.
public enum BuildingDrawings {
    /// The things as one soup, and which of them close rooms off (walls and columns; everything when nothing is tagged).
    public static func soup(_ elements: [IFCWriter.Element]) -> (soup: TriangleSoup, enclosing: Set<Int>?) {
        var soup = TriangleSoup()
        var enclosing = Set<Int>()
        for element in elements where element.part != .terrain {
            if element.part?.encloses == true { enclosing.insert(soup.names.count) }
            soup.add(positions: element.positions, triangles: element.triangles, name: element.name)
        }
        return (soup, enclosing.isEmpty ? nil : enclosing)
    }

    /// The floors: the ground, and the top of each slab at least two metres above the one below.
    public static func levels(_ elements: [IFCWriter.Element]) -> [Double] {
        let tops = elements.filter { $0.part == .slab }.compactMap { $0.positions.map(\.y).max() }.map { ($0 * 100).rounded() / 100 }
        var levels: [Double] = [0]
        for top in Set(tops).sorted() where top - (levels.last ?? 0) >= 2 {
            levels.append(top)
        }
        return levels
    }

    /// Names lying flat on a floor (3D text turned face up): the rooms take them.
    public static func labels(in scene: Scene) -> [(text: String, at: Vec3)] {
        scene.objects.values.compactMap { object in
            guard case let .text(recipe) = object.kind, scene.isEffectivelyVisible(object.id) else { return nil }
            let world = scene.worldTransform(of: object.id)
            guard world.rotation.act(.unitZ).y > 0.9 else { return nil }
            return (recipe.text, world.position)
        }
    }

    public struct Floor: Sendable {
        public var title: String
        public var height: Double
        public var art: LineArt
        public var rooms: [RoomFinder.Room]
    }

    public static func floors(_ elements: [IFCWriter.Element], labels: [(text: String, at: Vec3)], units: LengthUnit) -> [Floor] {
        let (soup, enclosing) = soup(elements)
        let levels = levels(elements)
        return levels.enumerated().map { index, height in
            let (art, rooms) = PlanDrawing.plan(soup, enclosing: enclosing, labels: labels,
                                                options: PlanDrawing.Options(floor: height, units: units))
            return Floor(title: index == 0 ? "Ground floor plan" : "Level \(index) plan", height: height, art: art, rooms: rooms)
        }
    }

    /// The plans and elevations as one PDF.
    public static func pdf(_ elements: [IFCWriter.Element], labels: [(text: String, at: Vec3)], paper: PaperSize, title: String,
                           author: String?, units: LengthUnit) -> Data {
        let floors = floors(elements, labels: labels, units: units)
        let soup = soup(elements).soup
        let elevations = PlanDrawing.Side.allCases.map { ($0, PlanDrawing.elevation(soup, side: $0)) }
        return PlanDrawing.sheets(plans: floors.map { ($0.title, $0.art) }, elevations: elevations, paper: paper, title: title, author: author)
    }

    /// Every floor's rooms as IFC spaces, as tall as the floor's walls.
    public static func spaces(_ floors: [Floor]) -> [IFCWriter.Space] {
        floors.enumerated().flatMap { index, floor in
            let next = index + 1 < floors.count ? floors[index + 1].height : floor.height + Architecture.wallHeight
            return floor.rooms.map { IFCWriter.Space(name: $0.name, outline: $0.outline, floor: floor.height, height: min(next - floor.height, 4)) }
        }
    }
}

public extension TriangleSoup {
    /// Triangles already in the world (an IFC element's).
    mutating func add(positions: [Vec3], triangles: [(Int, Int, Int)], name: String) {
        var mesh = MeshData()
        mesh.positions = positions.map(\.float3)
        mesh.indices = triangles.flatMap { [UInt32($0.0), UInt32($0.1), UInt32($0.2)] }
        add(mesh, transform: .identity, name: name)
    }
}
