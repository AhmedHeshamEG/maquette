import Foundation

/// IFC, the open file architecture offices trade buildings in (G1: Sara's model to the office's Revit). IFC4 as a STEP
/// text file: one project, site, building and a storey for each floor level; each thing as the element its building
/// part says (walls, slabs, roofs, stairs, columns, beams, railings, doors, windows, terrain), anything else as
/// furniture or a proxy; rooms as spaces. Shapes go as triangle face sets in metres with their colour. Scale people stay
/// out (they're for pictures). Z is up in IFC, so (x, y, z) here is (x, −z, y) there.
public enum IFCWriter {
    public struct Element: Sendable {
        public var id: String
        public var name: String
        public var part: BuildingPart?
        /// A model placed from the library (furniture when it's no building part).
        public var placed: Bool
        public var positions: [Vec3]
        public var triangles: [(Int, Int, Int)]
        public var color: RGBA

        public init(id: String, name: String, part: BuildingPart?, placed: Bool = false, positions: [Vec3], triangles: [(Int, Int, Int)],
                    color: RGBA) {
            self.id = id
            self.name = name
            self.part = part
            self.placed = placed
            self.positions = positions
            self.triangles = triangles
            self.color = color
        }

        var lowest: Double { positions.map(\.y).min() ?? 0 }
    }

    public struct Space: Sendable {
        public var name: String
        /// On the plan (x east, y north).
        public var outline: [Vec2]
        public var floor: Double
        public var height: Double

        public init(name: String, outline: [Vec2], floor: Double, height: Double = Architecture.wallHeight) {
            self.name = name
            self.outline = outline
            self.floor = floor
            self.height = height
        }
    }

    /// The scene's things as elements, each in world space (Kit models through `extra`, as the 3D exports do).
    public static func elements(in scene: Scene, look: Look, extra: (SceneObject, Transform) -> [ExportMesh] = { _, _ in [] }) -> [Element] {
        var result: [Element] = []
        for root in scene.roots {
            for id in scene.subtree(of: root) {
                guard let object = scene.objects[id], scene.isEffectivelyVisible(id), object.kind.hasSurface else { continue }
                let part = object.buildingPart ?? scene.ancestors(of: id).lazy.compactMap { scene.objects[$0]?.buildingPart }.first
                guard part != .person else { continue }
                let world = scene.worldTransform(of: id)
                let meshes: [ExportMesh] = if let local = SceneExport.localMesh(of: object, look: look), !local.isEmpty {
                    [ExportMesh(name: object.name, transform: world, mesh: local, color: SceneExport.material(of: object, look: look).color)]
                } else {
                    extra(object, world)
                }
                let soup = TriangleSoup(meshes)
                guard !soup.isEmpty else { continue }
                result.append(Element(id: id.raw, name: object.name, part: part, placed: object.kind.assetID != nil, positions: soup.positions,
                                      triangles: soup.triangles, color: meshes.first?.color ?? .blockout))
            }
        }
        return result
    }

    /// The file. `levels` are the floors' heights (the ground's 0 is always one).
    public static func file(elements: [Element], spaces: [Space], levels: [Double] = [0], project: String, author: String?,
                            date: Date = Date()) -> Data {
        var out = StepOut()
        let frame = out.skeleton(project: project, floors: Array(Set(levels.map { ($0 * 1000).rounded() / 1000 } + [0])).sorted())
        var contained: [Int: [Int]] = [:]
        for element in elements where !element.triangles.isEmpty {
            let level = frame.storey(for: element.lowest)
            let shape = out.shape(element.positions, element.triangles, color: element.color, body: frame.body,
                                  offset: frame.storeys[level].height)
            let local = out.add("IFCLOCALPLACEMENT(#\(frame.storeys[level].placement),#\(frame.placement))")
            let line = entity(for: element, guid: guid("element", element.id), name: string(element.name), placement: local, shape: shape)
            contained[level, default: []].append(out.add(line))
        }
        var spaceIDs: [Int: [Int]] = [:]
        for (index, space) in spaces.enumerated() where space.outline.count >= 3 {
            let loop = space.outline.map { Vec3($0.x, space.floor, -$0.y) }
            let soup = TriangleSoup(Prism.make(outline: Architecture.upward(loop), holes: [], normal: .unitY, from: 0, to: space.height))
            let level = frame.storey(for: space.floor)
            let shape = out.shape(soup.positions, soup.triangles, color: RGBA(0.8, 0.9, 1, 0.3), body: frame.body,
                                  offset: frame.storeys[level].height)
            let local = out.add("IFCLOCALPLACEMENT(#\(frame.storeys[level].placement),#\(frame.placement))")
            let id = out.add("IFCSPACE('\(guid("space", "\(project)\(index)\(space.name)"))',$,\(string(space.name)),$,$,#\(local),"
                + "#\(shape),\(string(space.name)),.ELEMENT.,.SPACE.,$)")
            spaceIDs[level, default: []].append(id)
        }
        for (level, ids) in spaceIDs.sorted(by: { $0.key < $1.key }) {
            out.add("IFCRELAGGREGATES('\(guid("rel-spaces", "\(project)\(level)"))',$,$,$,#\(frame.storeys[level].id),\(list(ids)))")
        }
        for (level, ids) in contained.sorted(by: { $0.key < $1.key }) {
            out.add("IFCRELCONTAINEDINSPATIALSTRUCTURE('\(guid("rel-contained", "\(project)\(level)"))',$,$,$,\(list(ids)),"
                + "#\(frame.storeys[level].id))")
        }
        let stamp = ISO8601DateFormatter().string(from: date)
        let header = """
        ISO-10303-21;
        HEADER;
        FILE_DESCRIPTION(('ViewDefinition [ReferenceView]'),'2;1');
        FILE_NAME(\(string(project + ".ifc")),'\(stamp)',(\(string(author ?? ""))),(''),'Maquette','Maquette','');
        FILE_SCHEMA(('IFC4'));
        ENDSEC;
        DATA;

        """
        return Data((header + out.lines.joined(separator: "\n") + "\nENDSEC;\nEND-ISO-10303-21;\n").utf8)
    }

    /// "(#1,#2)".
    static func list(_ ids: [Int]) -> String {
        "(" + ids.map { "#\($0)" }.joined(separator: ",") + ")"
    }

    /// The element's line: its kind of IFC element and the attributes that kind has.
    static func entity(for element: Element, guid: String, name: String, placement: Int, shape: Int) -> String {
        let common = "'\(guid)',$,\(name),$,$,#\(placement),#\(shape),$"
        switch element.part {
        case .wall: return "IFCWALL(\(common),.NOTDEFINED.)"
        case .slab: return "IFCSLAB(\(common),.FLOOR.)"
        case .roof: return "IFCROOF(\(common),.NOTDEFINED.)"
        case .stairs: return "IFCSTAIR(\(common),.NOTDEFINED.)"
        case .column: return "IFCCOLUMN(\(common),.COLUMN.)"
        case .beam: return "IFCBEAM(\(common),.BEAM.)"
        case .railing: return "IFCRAILING(\(common),.HANDRAIL.)"
        case .door: return "IFCDOOR(\(common),$,$,.DOOR.,$,$)"
        case .window: return "IFCWINDOW(\(common),$,$,.WINDOW.,$,$)"
        case .terrain: return "IFCGEOGRAPHICELEMENT(\(common),.TERRAIN.)"
        case .furniture: return "IFCFURNITURE(\(common),.NOTDEFINED.)"
        case .person, nil:
            return element.placed ? "IFCFURNITURE(\(common),.NOTDEFINED.)" : "IFCBUILDINGELEMENTPROXY(\(common),.NOTDEFINED.)"
        }
    }

    /// IFC's 22-character id, made from a stable hash of what it names (the same thing gets the same id every export).
    static func guid(_ kind: String, _ name: String) -> String {
        var first = StableHasher(), second = StableHasher()
        first.add(kind + "|" + name)
        second.add(name + "|" + kind + "|ifc")
        var bytes: [UInt8] = []
        for value in [first.value, second.value] {
            for shift in stride(from: 56, through: 0, by: -8) {
                bytes.append(UInt8((value >> UInt64(shift)) & 0xFF))
            }
        }
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_$")
        func encode(_ value: Int, _ count: Int) -> String {
            String((0 ..< count).reversed().map { alphabet[(value >> (6 * $0)) & 63] })
        }
        var result = encode(Int(bytes[0]), 2)
        for index in stride(from: 1, to: 16, by: 3) {
            result += encode(Int(bytes[index]) << 16 | Int(bytes[index + 1]) << 8 | Int(bytes[index + 2]), 4)
        }
        return result
    }

    /// A STEP string: quotes doubled, backslashes doubled, anything past ASCII as UTF-16 in \X2\ … \X0\.
    static func string(_ text: String) -> String {
        var result = "'"
        for scalar in text.unicodeScalars {
            switch scalar {
            case "'": result += "''"
            case "\\": result += "\\\\"
            case _ where scalar.value >= 32 && scalar.value < 127: result.unicodeScalars.append(scalar)
            default:
                let units = String(scalar).utf16.map { String(format: "%04X", $0) }.joined()
                result += "\\X2\\\(units)\\X0\\"
            }
        }
        return result + "'"
    }

    /// A STEP real: always with its point ("0.", "2.7").
    static func real(_ value: Double) -> String {
        guard value.isFinite else { return "0." }
        var text = String(format: "%.6f", value)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text == "-0." { text = "0." }
        return text
    }

    struct StepOut {
        var lines: [String] = []

        /// Where the model's frame and its storeys are.
        struct Frame {
            var placement: Int
            var body: Int
            var storeys: [(height: Double, id: Int, placement: Int)]

            func storey(for height: Double) -> Int {
                storeys.lastIndex { $0.height <= height + 0.1 } ?? 0
            }
        }

        /// The project, its units and context, the site, the building and a storey for each floor.
        mutating func skeleton(project: String, floors: [Double]) -> Frame {
            let origin = add("IFCCARTESIANPOINT((0.,0.,0.))")
            let zAxis = add("IFCDIRECTION((0.,0.,1.))")
            let xAxis = add("IFCDIRECTION((1.,0.,0.))")
            let placement = add("IFCAXIS2PLACEMENT3D(#\(origin),#\(zAxis),#\(xAxis))")
            let context = add("IFCGEOMETRICREPRESENTATIONCONTEXT($,'Model',3,1.E-05,#\(placement),$)")
            let body = add("IFCGEOMETRICREPRESENTATIONSUBCONTEXT('Body','Model',*,*,*,*,#\(context),$,.MODEL_VIEW.,$)")
            let units = [".LENGTHUNIT.,$,.METRE.", ".AREAUNIT.,$,.SQUARE_METRE.", ".VOLUMEUNIT.,$,.CUBIC_METRE.", ".PLANEANGLEUNIT.,$,.RADIAN."]
                .map { add("IFCSIUNIT(*,\($0))") }
            let unitAssignment = add("IFCUNITASSIGNMENT(\(IFCWriter.list(units)))")
            let name = IFCWriter.string(project)
            let projectID = add("IFCPROJECT('\(IFCWriter.guid("project", project))',$,\(name),$,$,$,$,(#\(context)),#\(unitAssignment))")
            let sitePlacement = add("IFCLOCALPLACEMENT($,#\(placement))")
            let site = add("IFCSITE('\(IFCWriter.guid("site", project))',$,'Site',$,$,#\(sitePlacement),$,$,.ELEMENT.,$,$,$,$,$)")
            let buildingPlacement = add("IFCLOCALPLACEMENT(#\(sitePlacement),#\(placement))")
            let building = add("IFCBUILDING('\(IFCWriter.guid("building", project))',$,\(name),$,$,#\(buildingPlacement),$,$,.ELEMENT.,$,$,$)")
            var storeys: [(height: Double, id: Int, placement: Int)] = []
            for (index, height) in floors.enumerated() {
                let point = add("IFCCARTESIANPOINT((0.,0.,\(IFCWriter.real(height))))")
                let axes = add("IFCAXIS2PLACEMENT3D(#\(point),#\(zAxis),#\(xAxis))")
                let storeyPlacement = add("IFCLOCALPLACEMENT(#\(buildingPlacement),#\(axes))")
                let title = IFCWriter.string(index == 0 ? "Ground floor" : "Level \(index)")
                let storey = add("IFCBUILDINGSTOREY('\(IFCWriter.guid("storey", "\(project)\(index)"))',$,\(title),$,$,#\(storeyPlacement),$,$,"
                    + ".ELEMENT.,\(IFCWriter.real(height)))")
                storeys.append((height, storey, storeyPlacement))
            }
            add("IFCRELAGGREGATES('\(IFCWriter.guid("rel-project", project))',$,$,$,#\(projectID),(#\(site)))")
            add("IFCRELAGGREGATES('\(IFCWriter.guid("rel-site", project))',$,$,$,#\(site),(#\(building)))")
            add("IFCRELAGGREGATES('\(IFCWriter.guid("rel-building", project))',$,$,$,#\(building),\(IFCWriter.list(storeys.map(\.id))))")
            return Frame(placement: placement, body: body, storeys: storeys)
        }

        @discardableResult
        mutating func add(_ line: String) -> Int {
            lines.append("#\(lines.count + 1)=\(line);")
            return lines.count
        }

        /// Triangles as a face set with a colour, wrapped as a body shape. `offset` is the storey's height (the shape is
        /// placed relative to its storey).
        mutating func shape(_ positions: [Vec3], _ triangles: [(Int, Int, Int)], color: RGBA, body: Int, offset: Double) -> Int {
            let coordinates = positions.map { "(\(real($0.x)),\(real(-$0.z)),\(real($0.y - offset)))" }.joined(separator: ",")
            let points = add("IFCCARTESIANPOINTLIST3D((\(coordinates)))")
            let indices = triangles.map { "(\($0.0 + 1),\($0.1 + 1),\($0.2 + 1))" }.joined(separator: ",")
            let faces = add("IFCTRIANGULATEDFACESET(#\(points),$,$,(\(indices)),$)")
            let colour = add("IFCCOLOURRGB($,\(real(color.r)),\(real(color.g)),\(real(color.b)))")
            let shading = add("IFCSURFACESTYLESHADING(#\(colour),\(real(1 - color.a)))")
            let style = add("IFCSURFACESTYLE($,.BOTH.,(#\(shading)))")
            add("IFCSTYLEDITEM(#\(faces),(#\(style)),$)")
            let representation = add("IFCSHAPEREPRESENTATION(#\(body),'Body','Tessellation',(#\(faces)))")
            return add("IFCPRODUCTDEFINITIONSHAPE($,$,(#\(representation)))")
        }
    }
}
