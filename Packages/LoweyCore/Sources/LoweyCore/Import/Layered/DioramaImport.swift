import Foundation

/// Bring your drawing (L2, D-487): a layered drawing stands up as a diorama. Each layer becomes a thin sheet cut to the
/// outline of what it shows and painted with its picture on the front, the bottom layer at the back and each one above
/// it a step nearer; groups stay groups, hidden layers come in hidden. The sheets are ordinary modelled shapes, so pins
/// and dots rig them, the paint stays paintable, and they light and line like everything else.
public enum DioramaImport {
    public struct Result: Sendable {
        /// The group first, then its things, parents before children.
        public var objects: [SceneObject]
        public var root: ObjectID
        /// Paint files to write into the project's assets before the objects are added.
        public var files: PaintOperations.Files
        /// What didn't come in (adjustment layers, empty layers), by kind.
        public var skipped: [String: Int]
        /// Layers that mixed with the ones below (multiply, screen…): in 3D each sheet shows its own picture.
        public var mixesLost: Int
    }

    /// The sheets' thickness and the gap between them, as shares of the drawing's long side.
    static let thickness = 0.004
    static let gap = 0.06

    /// `width`: the drawing's long side in metres. Throws when no layer shows anything.
    public static func make(_ image: LayeredImage, name: String, longSide: Double = 2, makeID: () -> ObjectID,
                            encode: (RGBAImage) -> Data = PNGCodec.encode) throws -> Result {
        let scale = longSide / Double(max(image.width, image.height, 1))
        let depth = longSide * thickness
        let step = longSide * gap
        var group = SceneObject(id: makeID(), name: name, kind: .group)
        var objects: [SceneObject] = []
        var groupsByPath: [[String]: ObjectID] = [:]
        var files: PaintOperations.Files = [:]
        var skipped = image.skipped
        var mixesLost = 0
        for (index, layer) in image.layers.enumerated() {
            guard let sheet = try sheet(layer, image: image, scale: scale, depth: depth, id: makeID(), encode: encode) else {
                skipped["empty layer", default: 0] += 1
                continue
            }
            var object = sheet.object
            object.transform.position.z = Double(index) * step - Double(max(image.layers.count - 1, 0)) * step
            object.parent = parent(for: layer.groups, under: group.id, paths: &groupsByPath, objects: &objects, makeID: makeID)
            files.merge(sheet.files) { first, _ in first }
            if layer.blend != .normal { mixesLost += 1 }
            objects.append(object)
        }
        // Only groups made means nothing on any layer showed.
        guard objects.contains(where: { $0.kind != .group }) else {
            throw LayeredReadFailure.unsupported("a drawing with nothing on its layers")
        }
        for index in objects.indices {
            if let parent = objects[index].parent, let at = objects.firstIndex(where: { $0.id == parent }) {
                objects[at].children.append(objects[index].id)
            }
        }
        group.children = objects.filter { $0.parent == group.id }.map(\.id)
        return Result(objects: [group] + objects, root: group.id, files: files, skipped: skipped, mixesLost: mixesLost)
    }

    /// The group a layer sits in, made the first time it's needed (nested groups nest).
    private static func parent(for path: [String], under root: ObjectID, paths: inout [[String]: ObjectID], objects: inout [SceneObject],
                               makeID: () -> ObjectID) -> ObjectID {
        guard !path.isEmpty else { return root }
        if let known = paths[path] { return known }
        let above = parent(for: Array(path.dropLast()), under: root, paths: &paths, objects: &objects, makeID: makeID)
        var group = SceneObject(id: makeID(), name: path.last ?? "Group", kind: .group)
        group.parent = above
        objects.append(group)
        paths[path] = group.id
        return group.id
    }

    /// One layer as a painted sheet: its outline pulled `depth` thick, standing on the ground in the drawing's place,
    /// its picture pressed onto the front.
    static func sheet(_ layer: LayeredImage.Layer, image: LayeredImage, scale: Double, depth: Double, id: ObjectID,
                      encode: (RGBAImage) -> Data) throws -> (object: SceneObject, files: PaintOperations.Files)? {
        guard let box = layer.visibleBounds else { return nil }
        var picture = RGBAImage.clear(width: box.width, height: box.height)
        picture.place(layer.image, x: -box.x, y: -box.y)
        // The sheet's own origin: the middle of its bottom edge, where it stands.
        let left = Double(layer.x + box.x), top = Double(layer.y + box.y)
        let width = Double(box.width) * scale, height = Double(box.height) * scale
        func local(_ point: Vec2) -> Vec3 {
            Vec3(point.x * scale - width / 2, height - point.y * scale, 0)
        }
        var solids: [EditableMesh] = []
        for (outer, holes) in Outlines.shapes(AlphaOutline.contours(picture)) {
            solids.append(Prism.make(outline: outer.map(local), holes: holes.map { $0.map(local) }, normal: .unitZ, from: -depth / 2, to: depth / 2))
        }
        guard !solids.isEmpty else { return nil }
        var object = SceneObject(id: id, name: layer.name, kind: .mesh(LogoImport.joined(solids)))
        object.transform.position = Vec3((left + Double(box.width) / 2 - Double(image.width) / 2) * scale,
                                         (Double(image.height) - top - Double(box.height)) * scale, 0)
        object[.color] = .color(.rgba(averageColour(picture)))
        object[.smoothAngle] = .float(30)
        if layer.hidden { object[.visible] = .bool(false) }
        if layer.opacity < 0.999 { object[.opacity] = .float(layer.opacity) }
        guard let mesh = PaintSource.mesh(of: object) else { return (object, [:]) }
        let size = PaintSurface.sizes.first { Double($0) >= Double(max(box.width, box.height)) * 1.5 } ?? 2048
        var (paint, unwrap, files) = try PaintOperations.prepare(mesh: mesh, keepOwnUVs: false, size: min(size, 2048))
        guard let paintMesh = unwrap.mesh(over: mesh) else { return (object, [:]) }
        let decal = PaintDecal(center: SIMD3<Float>(0, Float(height / 2), Float(depth / 2)), normal: SIMD3<Float>(0, 0, 1),
                               size: Float(width))
        let pressed = decal.image(picture, on: paintMesh, textureSize: paint.surface.size)
        let tiles = PaintOperations.tileChanges(pressed, layer: paint.layers[0], surface: paint.surface, encode: encode)
        for change in tiles.changes {
            paint.layers[0].tiles[change.tile] = change.file
        }
        paint.layers[0].name = layer.name
        files.merge(tiles.files) { first, _ in first }
        object.paint = paint
        return (object, files)
    }

    /// The colour the sheet's edges and back take: what the picture shows, on average.
    static func averageColour(_ picture: RGBAImage) -> RGBA {
        var sum = (r: 0.0, g: 0.0, b: 0.0, a: 0.0)
        for index in stride(from: 0, to: picture.pixels.count, by: 4) {
            let alpha = Double(picture.pixels[index + 3]) / 255
            sum.r += Double(picture.pixels[index]) / 255 * alpha
            sum.g += Double(picture.pixels[index + 1]) / 255 * alpha
            sum.b += Double(picture.pixels[index + 2]) / 255 * alpha
            sum.a += alpha
        }
        guard sum.a > 0 else { return RGBA(0.8, 0.8, 0.8) }
        return RGBA(sum.r / sum.a, sum.g / sum.a, sum.b / sum.a)
    }
}

public extension LayeredImage {
    /// A layered drawing from a file's bytes: Photoshop (PSD, PSB) or Procreate, told apart by what the file starts with.
    static func read(_ data: Data) throws(LayeredReadFailure) -> LayeredImage {
        if PSDReader.isPSD(data) { return try PSDReader.read(data) }
        if data.count >= 4, data.prefix(4).elementsEqual([0x50, 0x4B, 0x03, 0x04]) { return try ProcreateReader.read(data) }
        throw .notLayered
    }

    /// The file extensions read as layered drawings.
    static let fileExtensions: Set<String> = PSDReader.fileExtensions.union([ProcreateReader.fileExtension])
}
