import Foundation

/// An object's paint as an exporter writes it: the paint mesh (the object's surface with the paint's uvs, in the
/// object's own space), its colour flattened over the object's colour into an opaque PNG, and every other map it
/// paints (D-354).
public struct PaintedExport: Hashable, Sendable {
    public var mesh: MeshData
    public var texture: Data
    public var maps: ExportMaps
    /// The paint mesh's tangents (glTF's TANGENT), when there's a normal map.
    public var tangents: [SIMD4<Float>]?
    /// The colour at each corner of the paint mesh (sRGB; glTF's COLOR_0), when they were asked for.
    public var vertexColors: [SIMD4<Float>]

    public init(mesh: MeshData, texture: Data, maps: ExportMaps = ExportMaps(), tangents: [SIMD4<Float>]? = nil, vertexColors: [SIMD4<Float>] = []) {
        self.mesh = mesh
        self.texture = texture
        self.maps = maps
        self.tangents = tangents
        self.vertexColors = vertexColors
    }
}

/// A painted surface's maps besides its colour, as opaque PNGs (each nil when nothing paints it).
public struct ExportMaps: Hashable, Sendable {
    /// Grey, over the object's own roughness.
    public var roughness: Data?
    /// Grey, over the object's own metal.
    public var metal: Data?
    /// glTF's packing: roughness in green, metal in blue.
    public var metallicRoughness: Data?
    public var emissive: Data?
    /// Tangent space, from painted bumps and a baked normal map.
    public var normal: Data?

    public init(roughness: Data? = nil, metal: Data? = nil, metallicRoughness: Data? = nil, emissive: Data? = nil, normal: Data? = nil) {
        self.roughness = roughness
        self.metal = metal
        self.metallicRoughness = metallicRoughness
        self.emissive = emissive
        self.normal = normal
    }

    public var isEmpty: Bool {
        roughness == nil && metal == nil && emissive == nil && normal == nil
    }

    /// Every map with its file name in a PNG set (`<name>_roughness.png` …).
    public func named(_ name: String) -> [(String, Data)] {
        [("roughness", roughness), ("metal", metal), ("emissive", emissive), ("normal", normal)].compactMap { suffix, data in
            data.map { ("\(name)_\(suffix).png", $0) }
        }
    }
}

/// The paint of an object for exports and for the renderer's "shape changed" case: the stored unwrap when the shape
/// is the one it was made for, else a fresh unwrap with every layer carried over by position.
public enum PaintExport {
    /// The surface paint lands on now and the pictures on it, keyed as `PaintPictures.key` (a layer's colour under its
    /// id, its other maps and mask under "id#map"). `source` is the object's current mesh.
    public static func current(_ paint: ObjectPaint, source: MeshData, file: (String) -> Data?) -> (unwrap: PaintUnwrap, layers: [String: RGBAImage])? {
        guard let stored = file(paint.surface.unwrap).flatMap({ try? PaintUnwrap(data: $0) }) else { return nil }
        let layers = withoutActuallyEscaping(file) { PaintPictures(paint, file: $0).all() }
        if PaintMesh.fingerprint(source) == paint.surface.mesh, stored.source.allSatisfy({ Int($0) < source.positions.count }) {
            return (stored, layers)
        }
        guard let fresh = try? PaintUnwrap.unwrap(source, seams: paint.surface.seams) else { return nil }
        let map = PaintTransfer.correspondence(from: stored, to: fresh, size: paint.surface.size)
        return (fresh, layers.mapValues { PaintTransfer.carry($0, through: map, size: paint.surface.size) })
    }

    /// What a painted object's surface is made of where nothing is painted.
    public struct Base: Sendable {
        public var color: RGBA
        public var roughness: Double
        public var metal: Double
        public var glow: RGBA

        public init(color: RGBA, roughness: Double = 0.85, metal: Double = 0, glow: RGBA = .black) {
            self.color = color
            self.roughness = roughness
            self.metal = metal
            self.glow = glow
        }
    }

    /// The export of a painted object (nil when it has no paint that shows, or its files are missing).
    /// `posed` is the same surface bent by the object's rig, when it has one: the paint goes where the surface went.
    public static func painted(_ object: SceneObject, source: MeshData?, base: RGBA, file: (String) -> Data?, posed: MeshData? = nil,
                               encode: (RGBAImage) -> Data = PNGCodec.encode) -> PaintedExport? {
        painted(object, source: source, base: Base(color: base), file: file, posed: posed, encode: encode)
    }

    public static func painted(_ object: SceneObject, source: MeshData?, base: Base, file: (String) -> Data?, posed: MeshData? = nil,
                               colors: PaintColorOutput = .texture, encode: (RGBAImage) -> Data = PNGCodec.encode) -> PaintedExport? {
        guard let paint = object.paint, paint.showsPaint, let source, let (unwrap, layers) = current(paint, source: source, file: file),
              var mesh = unwrap.mesh(over: posed.flatMap { $0.positions.count == source.positions.count ? $0 : nil } ?? source)
        else { return nil }
        if let factor = PaintSource.toObjectSpace(of: object) {
            mesh.positions = mesh.positions.map { $0 * factor }
            mesh.normals = mesh.normals.map { normalize3($0 / factor, fallback: SIMD3<Float>(0, 1, 0)) }
        }
        let size = paint.surface.size
        let coverage = PaintRaster.coverage(unwrap, size: size)
        let pictures = PaintPictures(paint, images: layers)
        func composite(_ map: PaintMap) -> RGBAImage? {
            guard paint.shows(map) else { return nil }
            var image = PaintComposer.composite(paint, map: map) { layer, map in
                layers[PaintPictures.key(layer.id, map)] ?? pictures.image(layer, map)
            }
            PaintRaster.dilate(&image, coverage: coverage)
            return image
        }
        let colour = PaintComposer.flattened(composite(.color) ?? .clear(width: size, height: size), over: RGBA(base.color.r, base.color.g, base.color.b, 1))
        if colors == .palette {
            // Flat colour per face from swatches: the other maps don't apply to a palette.
            let (split, palette) = PaintPalette.make(mesh, colour: colour)
            return PaintedExport(mesh: split, texture: encode(palette))
        }
        let roughness = composite(.roughness).map { PaintComposer.flattened($0, over: base.roughness) }
        let metal = composite(.metal).map { PaintComposer.flattened($0, over: base.metal) }
        let glow = composite(.glow).map { PaintComposer.flattened($0, over: base.glow) }
        var normal: RGBAImage?
        let baked = paint.normalMap.flatMap(file).flatMap { try? PNGCodec.decode($0) }.flatMap { $0.width == size ? $0 : nil }
        if paint.shows(.bumps) || baked != nil {
            normal = NormalBake.fromBumps(composite(.bumps), baked: baked, coverage: coverage, size: size)
        }
        var maps = ExportMaps(roughness: roughness.map(encode), metal: metal.map(encode), emissive: glow.map(encode), normal: normal.map(encode))
        if roughness != nil || metal != nil {
            maps.metallicRoughness = encode(packed(roughness: roughness, metal: metal, base: base, size: size))
        }
        return PaintedExport(mesh: mesh, texture: encode(colour), maps: maps, tangents: normal == nil ? nil : NormalBake.tangents(mesh),
                             vertexColors: colors == .vertexColors ? vertexColors(mesh, colour) : [])
    }

    /// A painted thing's maps as a PNG set: `<name>_color.png`, then each other map it paints.
    public static func pngSet(_ export: PaintedExport, name: String) -> [(String, Data)] {
        [("\(name)_color.png", export.texture)] + export.maps.named(name)
    }

    /// glTF's metallic-roughness texture: green roughness, blue metal (red unused, white).
    static func packed(roughness: RGBAImage?, metal: RGBAImage?, base: Base, size: Int) -> RGBAImage {
        var image = RGBAImage(width: size, height: size, color: RGBA(1, base.roughness, base.metal, 1))
        for index in 0 ..< size * size {
            if let roughness { image.pixels[index * 4 + 1] = roughness.pixels[index * 4] }
            if let metal { image.pixels[index * 4 + 2] = metal.pixels[index * 4] }
        }
        return image
    }

    /// The colour under each corner of the paint mesh (sRGB; the glTF writer makes it linear).
    static func vertexColors(_ mesh: MeshData, _ colour: RGBAImage) -> [SIMD4<Float>] {
        mesh.uvs.map { uv in
            let c = colour.sample(u: Double(uv.x), v: Double(uv.y))
            return SIMD4<Float>(Float(c.r), Float(c.g), Float(c.b), 1)
        }
    }
}
