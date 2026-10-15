import CoreGraphics
import Foundation
import ImageIO
import LoweyCore
import Metal
import Synchronization

/// The GPU side of painted objects. Each one has a texture per layer and map (colour, roughness, metal, glow, bumps,
/// fur, and a layer's mask), filled from their tiles (the stage streams a few a frame and asks for another; exports
/// load every tile at once), composited map by map into the textures the shading pass reads. A stroke draws straight
/// into its layer's map (`PaintTextures+Encode`); the tiles it changed are read back and adopted, so the document's
/// next state needs no decoding.
final class PaintTextures {
    let device: RenderDevice
    /// The stage: tiles stream in a few per frame. Off for exports and stills, which need every tile now.
    var streams = false
    /// Tiles were left for later frames (the stage draws again).
    private(set) var wantsAnotherFrame = false
    private(set) var surfaces: [ObjectID: Surface] = [:]
    private var unwraps: [String: PaintUnwrap] = [:]
    private var normalMaps: [String: MTLTexture] = [:]
    private var fingerprints: [ObjectIdentifier: Fingerprint] = [:]
    /// Paint carried onto a changed shape, made off the main thread (`CarriedPaint`).
    let carried = CarriedPaint()
    /// Asks the stage for a frame (carried paint became ready).
    var onNeedsFrame: (@Sendable () -> Void)?
    /// Work queued by this frame's compile: tile uploads, then coverage and compositing.
    var uploads: [Upload] = []
    var scratch: (MTLTexture, MTLTexture)?
    /// The stroke being painted: its layer as it was before it (`PaintTextures+Encode`).
    var stroke: ActiveStroke?
    /// The last stroke's "before" copy, kept for the next stroke (a layer's size: 16 MB at 2048).
    var spareBefore: MTLTexture?
    var strokeTarget: MTLTexture?
    private var clock: UInt64 = 0
    private var liveCount = 0

    static let tilesPerFrame = 12

    init(device: RenderDevice) {
        self.device = device
    }

    /// One layer's map on the GPU (premultiplied, the stored values) and the file each tile holds now ("" = clear).
    final class Layer {
        let texture: MTLTexture
        var loaded: [String: String] = [:]
        /// Just made: cleared once by a pass (not tile by tile) before its tiles arrive.
        var needsClear = true

        init(texture: MTLTexture) {
            self.texture = texture
        }
    }

    /// A map's composite: the texture the finish pass writes and the view the shading pass samples.
    struct Composite {
        let texture: MTLTexture
        let view: MTLTexture
    }

    /// An object's paint on the GPU.
    final class Surface {
        let size: Int
        /// The unwrap it's drawn with (a file name, or the carried surface's key).
        var unwrap: String
        /// By `PaintPictures.key`: "l1" (colour), "l1#roughness", "l1#mask"…
        var layers: [String: Layer] = [:]
        /// The layers' settings in order (bottom first), as last composited (tiles left out, which maps they have kept).
        var settings: [PaintLayer] = []
        var composites: [PaintMap: Composite] = [:]
        var coverage: MTLTexture?
        var coverageMesh: ObjectIdentifier?
        /// The paint mesh this frame draws (coverage is made from it).
        var mesh: GPUMesh?
        /// The maps whose composite is out of date.
        var dirty: Set<PaintMap> = Set(PaintMap.channels)
        var lastUse: UInt64 = 0

        init(size: Int, unwrap: String) {
            self.size = size
            self.unwrap = unwrap
        }

        func markAll() {
            dirty = Set(PaintMap.channels)
        }
    }

    final class Fingerprint {
        weak var mesh: GPUMesh?
        let value: String

        init(mesh: GPUMesh, value: String) {
            self.mesh = mesh
            self.value = value
        }
    }

    /// A tile to copy into a layer this frame (nil bytes clear it).
    struct Upload {
        var layer: Layer
        var tile: PaintTileIndex
        var file: String
        var bytes: [UInt8]?
    }

    struct ActiveStroke {
        var id: Int
        var object: ObjectID
        var layer: String
        var before: MTLTexture
    }

    // MARK: Lookups

    /// The fingerprint of a mesh the renderer drew (computed once per cached mesh).
    func fingerprint(of mesh: GPUMesh) -> String {
        let key = ObjectIdentifier(mesh)
        if let known = fingerprints[key], known.mesh === mesh { return known.value }
        let value = PaintMesh.fingerprint(mesh.data)
        fingerprints[key] = Fingerprint(mesh: mesh, value: value)
        if fingerprints.count > 512 { fingerprints = fingerprints.filter { $0.value.mesh != nil } }
        return value
    }

    func unwrap(_ name: String, file: (String) -> Data?) -> PaintUnwrap? {
        if let known = unwraps[name] { return known }
        guard let data = file(name), let unwrap = try? PaintUnwrap(data: data) else { return nil }
        unwraps[name] = unwrap
        return unwrap
    }

    /// The map a layer key names ("l1" colour, "l1#bumps" bumps).
    static func map(ofKey key: String) -> PaintMap {
        guard let mark = key.lastIndex(of: "#") else { return .color }
        return PaintMap(rawValue: String(key[key.index(after: mark)...])) ?? .color
    }

    // MARK: Keeping a surface in step with the document

    /// The colour composite of an object's paint for this frame, its layers brought in step with `paint` (tiles read
    /// through `file`, or the pictures of paint carried onto a changed shape). Uploads wait in `uploads` for
    /// `encodeUpdates`. Its other maps are `maps(for:paint:file:)`.
    func texture(for object: ObjectID, paint: ObjectPaint, unwrap: String, mesh: GPUMesh, pictures: [String: RGBAImage]? = nil,
                 file: (String) -> Data?) -> MTLTexture? {
        clock &+= 1
        guard let surface = surface(object, size: paint.surface.size, unwrap: unwrap) else { return nil }
        surface.lastUse = clock
        surface.mesh = mesh
        if surface.coverageMesh != ObjectIdentifier(mesh) { surface.markAll() }
        let wanted = Self.keys(of: paint)
        for key in surface.layers.keys where !wanted.contains(key) {
            surface.layers[key] = nil
            if Self.map(ofKey: key) == .mask { surface.markAll() } else { surface.dirty.insert(Self.map(ofKey: key)) }
        }
        var budget = streams ? Self.tilesPerFrame : Int.max
        for layer in paint.layers {
            for map in PaintMap.allCases where wanted.contains(PaintPictures.key(layer.id, map)) {
                let key = PaintPictures.key(layer.id, map)
                guard let texture = surface.layers[key] ?? makeLayer(size: surface.size) else { continue }
                surface.layers[key] = texture
                if let pictures {
                    queuePicture(pictures[key], into: texture, surface: paint.surface, key: unwrap)
                } else {
                    queueTiles(layer.tiles(of: map), into: texture, surface: paint.surface, budget: &budget, file: file)
                }
            }
        }
        let settings = paint.layers.map(Self.settings)
        if surface.settings != settings {
            surface.settings = settings
            surface.markAll()
        }
        keepComposites(of: surface, for: paint, object: object)
        return surface.composites[.color]?.view
    }

    /// Every layer key a paint has textures for: each layer's colour (an empty layer is painted on), each other map with
    /// tiles, and each mask (even one with no tiles).
    static func keys(of paint: ObjectPaint) -> Set<String> {
        var keys = Set<String>()
        for layer in paint.layers {
            for map in PaintMap.allCases where map == .color || !layer.tiles(of: map).isEmpty || (map == .mask && layer.hasMask) {
                keys.insert(PaintPictures.key(layer.id, map))
            }
        }
        return keys
    }

    /// A composite for each map the paint shows (colour always), and none for the rest.
    private func keepComposites(of surface: Surface, for paint: ObjectPaint, object: ObjectID) {
        for map in paint.shownMaps where surface.composites[map] == nil {
            surface.composites[map] = makeComposite(size: surface.size, map: map, label: "paint \(map.rawValue) \(object.raw)")
            surface.dirty.insert(map)
        }
        for map in Array(surface.composites.keys) where map != .color && !paint.shows(map) {
            surface.composites[map] = nil
        }
    }

    /// The object's painted maps besides colour, as this frame's compile left them (and its baked normal map).
    func maps(for object: ObjectID, paint: ObjectPaint, file: (String) -> Data?) -> PaintMapTextures? {
        guard let surface = surfaces[object] else { return nil }
        let maps = PaintMapTextures(roughness: surface.composites[.roughness]?.view, metal: surface.composites[.metal]?.view,
                                    glow: surface.composites[.glow]?.view, bumps: surface.composites[.bumps]?.view,
                                    normals: paint.normalMap.flatMap { normalMap($0, file: file) }, fur: surface.composites[.fur]?.view)
        return maps.flags.isEmpty && maps.fur == nil ? nil : maps
    }

    /// A layer's settings without its tiles (what compositing depends on besides the pixels): which maps it has stays.
    static func settings(_ layer: PaintLayer) -> PaintLayer {
        var copy = layer
        copy.tiles = [:]
        copy.maps = layer.maps.mapValues { _ in [:] }
        copy.fill = nil
        return copy
    }

    private func surface(_ object: ObjectID, size: Int, unwrap: String) -> Surface? {
        if let existing = surfaces[object], existing.size == size {
            if existing.unwrap != unwrap {
                // A new surface under the same object (prepared again, carried, restored): every tile again.
                existing.unwrap = unwrap
                existing.layers.removeAll()
                existing.coverage = nil
                existing.coverageMesh = nil
                existing.markAll()
            }
            return existing
        }
        let surface = Surface(size: size, unwrap: unwrap)
        guard let colour = makeComposite(size: size, map: .color, label: "paint \(object.raw)") else { return nil }
        surface.composites[.color] = colour
        surfaces[object] = surface
        return surface
    }

    /// A map's composite: mipmapped; colour and glow read through an sRGB view (so they arrive linear), the value maps
    /// as they're stored.
    func makeComposite(size: Int, map: PaintMap, label: String) -> Composite? {
        let levels = Int(log2(Double(size))) + 1
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: true)
        descriptor.mipmapLevelCount = levels
        descriptor.usage = [.renderTarget, .shaderRead, .pixelFormatView]
        descriptor.storageMode = .private
        guard let texture = device.device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = label
        let colour = map == .color || map == .glow
        guard let view = colour ? texture.makeTextureView(pixelFormat: .rgba8Unorm_srgb) : texture else { return nil }
        return Composite(texture: texture, view: view)
    }

    func makeLayer(size: Int) -> Layer? {
        guard let texture = try? device.makeTexture(RenderDevice.layerFormat, width: size, height: size,
                                                    usage: [.renderTarget, .shaderRead], label: "paint layer") else { return nil }
        return Layer(texture: texture)
    }

    /// A baked normal map, decoded once (as stored: no colour conversion).
    private func normalMap(_ name: String, file: (String) -> Data?) -> MTLTexture? {
        if let known = normalMaps[name] { return known }
        guard let data = file(name), let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        guard drawn, let texture = device.device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: width * 4)
        texture.label = "baked normals"
        if normalMaps.count > 16 { normalMaps.removeAll() }
        normalMaps[name] = texture
        return texture
    }

    private func queueTiles(_ tiles: [String: String], into texture: Layer, surface: PaintSurface, budget: inout Int, file: (String) -> Data?) {
        if texture.needsClear, texture.loaded.isEmpty {
            // A new layer is cleared in one pass (`encodeUpdates`): every tile starts transparent.
            for index in surface.allTiles {
                texture.loaded[index.key] = ""
            }
        }
        for index in surface.allTiles {
            let wanted = tiles[index.key] ?? ""
            guard texture.loaded[index.key] != wanted else { continue }
            if wanted.isEmpty {
                uploads.append(Upload(layer: texture, tile: index, file: "", bytes: nil))
                texture.loaded[index.key] = ""
                continue
            }
            guard budget > 0 else {
                wantsAnotherFrame = true
                continue
            }
            budget -= 1
            let bytes = file(wanted).flatMap(PaintPixels.premultiplied(png:))
            uploads.append(Upload(layer: texture, tile: index, file: wanted, bytes: bytes))
            texture.loaded[index.key] = wanted
        }
    }

    private func queuePicture(_ picture: RGBAImage?, into texture: Layer, surface: PaintSurface, key: String) {
        guard texture.loaded["picture"] != key else { return }
        texture.loaded["picture"] = key
        for index in surface.allTiles {
            let tile = picture?.tile(index, size: PaintSurface.tileSize)
            uploads.append(Upload(layer: texture, tile: index, file: key, bytes: tile.map(PaintPixels.premultiplied(image:))))
        }
    }

    /// Tiles worked out on the CPU while a stroke is still going (smudge, the faces brush): shown now, replaced by the
    /// document's tiles once the stroke is kept.
    func queueLive(object: ObjectID, layer key: String, tiles: [PaintTileIndex: RGBAImage]) {
        guard let surface = surfaces[object], let texture = surface.layers[key] ?? makeLayer(size: surface.size) else { return }
        surface.layers[key] = texture
        liveCount &+= 1
        for (index, tile) in tiles {
            uploads.append(Upload(layer: texture, tile: index, file: "live", bytes: PaintPixels.premultiplied(image: tile)))
            texture.loaded[index.key] = "live \(liveCount)"
        }
        surface.dirty.insert(Self.map(ofKey: key) == .mask ? .color : Self.map(ofKey: key))
        if Self.map(ofKey: key) == .mask { surface.markAll() }
    }

    /// The tiles a stroke wrote are already in the layer: they become what it holds, so nothing is decoded again.
    func adopt(object: ObjectID, layer: String, changes: [PaintTileChange]) {
        guard let surface = surfaces[object] else { return }
        for change in changes {
            guard let map = change.paintMap, let texture = surface.layers[PaintPictures.key(change.layer, map)],
                  PaintPictures.key(change.layer, map) == layer else { continue }
            texture.loaded[change.tile] = change.file ?? ""
        }
    }

    /// Every layer loads again from its tiles (and no stroke is in progress).
    func forget() {
        for surface in surfaces.values {
            surface.layers.removeAll()
            surface.markAll()
        }
        stroke = nil
    }

    /// Frees surfaces not drawn lately (and everything under memory pressure).
    func trim(keeping recent: UInt64 = 600) {
        let limit = clock > recent ? clock - recent : 0
        surfaces = surfaces.filter { $0.value.lastUse >= limit }
        if surfaces.isEmpty { scratch = nil }
        unwraps.removeAll()
        normalMaps.removeAll()
    }

    /// Called after a frame's work is queued: whether tiles are still to come.
    func startFrame() {
        wantsAnotherFrame = false
    }
}

/// Paint carried onto a changed shape, made off the main thread and picked up by the next frame.
final class CarriedPaint: Sendable {
    struct Result: Sendable {
        var key: String
        var unwrap: PaintUnwrap
        var layers: [String: RGBAImage]
    }

    private let state = Mutex<(results: [ObjectID: Result], working: Set<String>, failed: Set<String>)>(([:], [], []))

    /// The carried paint for this key, or nil (and the work started) when it isn't made yet.
    func result(for object: ObjectID, key: String, paint: ObjectPaint, source: MeshData, file: @escaping @Sendable (String) -> Data?,
                synchronously: Bool, ready: @escaping @Sendable () -> Void) -> Result? {
        let known: Result? = state.withLock { current in
            guard let result = current.results[object], result.key == key else { return nil }
            return result
        }
        if let known { return known }
        // Files that can't be read (or a shape that can't be laid flat) aren't tried again every frame.
        guard !state.withLock({ $0.failed.contains(key) }) else { return nil }
        if synchronously {
            guard let made = Self.make(key: key, paint: paint, source: source, file: file) else {
                state.withLock { _ = $0.failed.insert(key) }
                return nil
            }
            state.withLock { $0.results[object] = made }
            return made
        }
        let starts = state.withLock { $0.working.insert(key).inserted }
        guard starts else { return nil }
        Task.detached(priority: .userInitiated) { [self] in
            let made = Self.make(key: key, paint: paint, source: source, file: file)
            state.withLock { current in
                current.working.remove(key)
                if let made { current.results[object] = made } else { current.failed.insert(key) }
            }
            if made != nil { ready() }
        }
        return nil
    }

    private static func make(key: String, paint: ObjectPaint, source: MeshData, file: (String) -> Data?) -> Result? {
        guard let (unwrap, layers) = PaintExport.current(paint, source: source, file: file) else { return nil }
        return Result(key: key, unwrap: unwrap, layers: layers)
    }
}
