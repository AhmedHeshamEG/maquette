import CoreGraphics
import Foundation
import HmmMedia
import LoweyCore

/// Render passes (A1), for compositing: each frame's colour with transparency, its alpha as a matte, its depth and a
/// mask per thing, each in a folder of its own, and `passes.json` saying how to read them (the depth's near and far in
/// metres, each mask colour's thing). Depth and masks come from the renderer's own prepass, pixel for pixel.
public extension ExportSession {
    /// The passes of every frame of `settings` (one frame for a picture).
    func passes(_ settings: ExportSettings, to folder: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        await loadModels()
        try? FileManager.default.removeItem(at: folder)
        let names = ["colour", "alpha", "depth", "masks"]
        for name in names {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        var colour = settings
        colour.transparent = true
        if colour.codec != .prores4444 { colour.codec = .hevcAlpha }
        var plain = colour
        plain.final = false
        var key = PassKey()
        for frame in 0 ..< settings.frameCount {
            try Task.checkCancellation()
            try await waitUntilRenderable()
            let time = settings.range.start + Double(frame) / Double(settings.fps)
            let bytes = try await frameBytes(at: time, settings: colour)
            // Depth and masks come from a plain draw of the same moment (Final's last moment was drawn larger).
            if settings.final { _ = try await frames.render(frameRequest(at: time, settings: plain), width: plain.size.width, height: plain.size.height) }
            let name = String(format: "frame_%05d.png", frame + 1)
            let size = settings.size
            try ImageWriters.writePNG(FrameRenderer.image(bgra: bytes, width: size.width, height: size.height, transparent: true),
                                      to: folder.appendingPathComponent("colour").appendingPathComponent(name))
            try ImageWriters.writePNG(PassPictures.matte(bytes, width: size.width, height: size.height),
                                      to: folder.appendingPathComponent("alpha").appendingPathComponent(name))
            try writeDepthAndMasks(name, in: folder, key: &key)
            progress(Double(frame + 1) / Double(settings.frameCount))
            await Task.yield()
        }
        try key.json().write(to: folder.appendingPathComponent("passes.json"), options: .atomic)
        return folder
    }

    private func writeDepthAndMasks(_ name: String, in folder: URL, key: inout PassKey) throws {
        guard let depth = frames.renderer.depthBuffer(), let ids = frames.renderer.idBuffer() else { throw RenderError.readback }
        let objects = ids.ids.map { PackedID.object($0) == 0 ? nil : frames.renderer.object(forPacked: $0) }
        if key.near == nil {
            // The first frame sets the range (a little either side), so the whole sequence reads the same way.
            let drawn = zip(depth.depths, objects).compactMap { $1 == nil || $0 <= 0 ? nil : Double($0) }
            key.near = max((drawn.min() ?? 0.1) * 0.8, 0.01)
            key.far = max((drawn.max() ?? 10) * 1.25, (key.near ?? 0.01) + 0.01)
        }
        try ImageWriters.writePNG(PassPictures.depth(depth.depths, drawn: objects.map { $0 != nil }, width: depth.width, height: depth.height,
                                                     near: key.near ?? 0.1, far: key.far ?? 10),
                                  to: folder.appendingPathComponent("depth").appendingPathComponent(name))
        let scene = builder.document.scene
        for object in Set(objects.compactMap { $0 }) where key.masks[PassPictures.hex(PassPictures.colour(of: object))] == nil {
            key.masks[PassPictures.hex(PassPictures.colour(of: object))] = scene.objects[object]?.name ?? object.raw
        }
        try ImageWriters.writePNG(PassPictures.masks(objects, width: ids.width, height: ids.height),
                                  to: folder.appendingPathComponent("masks").appendingPathComponent(name))
    }
}

/// How to read a folder of passes.
struct PassKey {
    var near: Double?
    var far: Double?
    /// Mask colour (#RRGGBB) → the thing's name.
    var masks: [String: String] = [:]

    func json() throws -> Data {
        let body: [String: Any] = [
            "depth": ["near": near ?? 0, "far": far ?? 0, "units": "metres", "reads": "white is near, black is far or empty"],
            "masks": masks,
            "colour": "premultiplied alpha", "alpha": "white is drawn"
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
    }
}

/// The pictures of the passes.
enum PassPictures {
    /// The alpha of BGRA bytes as a grey picture.
    static func matte(_ bgra: [UInt8], width: Int, height: Int) throws -> CGImage {
        let alpha = (0 ..< width * height).map { bgra[$0 * 4 + 3] }
        return try grey(Data(alpha), width: width, height: height, bits: 8)
    }

    /// Depth as 16-bit grey: white at `near`, black at `far` and where nothing was drawn.
    static func depth(_ depths: [Float], drawn: [Bool], width: Int, height: Int, near: Double, far: Double) throws -> CGImage {
        var data = Data(capacity: width * height * 2)
        for index in 0 ..< width * height {
            let along = drawn[index] ? min(max((far - Double(depths[index])) / (far - near), 0), 1) : 0
            let value = UInt16((along * 65535).rounded())
            data.append(UInt8(value & 0xFF))
            data.append(UInt8(value >> 8))
        }
        return try grey(data, width: width, height: height, bits: 16)
    }

    /// Each thing in its own flat colour, black where nothing was drawn.
    static func masks(_ objects: [ObjectID?], width: Int, height: Int) throws -> CGImage {
        var data = Data(capacity: width * height * 4)
        for object in objects {
            let colour = object.map(colour(of:)) ?? (0, 0, 0)
            data.append(contentsOf: [colour.0, colour.1, colour.2, 255])
        }
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                                  decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw RenderError.readback }
        return image
    }

    /// A thing's mask colour: from its id, so it's the same in every frame and every export of the scene.
    static func colour(of id: ObjectID) -> (UInt8, UInt8, UInt8) {
        let hash = id.raw.utf8.reduce(UInt64(1_469_598_103_934_665_603)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        let hue = Double(hash % 360) / 360
        let shade = 0.65 + Double((hash >> 16) % 30) / 100
        // Hue round the wheel at 75 % saturation.
        let sector = hue * 6
        let fraction = sector - sector.rounded(.down)
        let low = shade * 0.25
        let falling = shade * (1 - 0.75 * fraction)
        let rising = shade * (1 - 0.75 * (1 - fraction))
        let rgb: (Double, Double, Double) = switch Int(sector) % 6 {
        case 0: (shade, rising, low)
        case 1: (falling, shade, low)
        case 2: (low, shade, rising)
        case 3: (low, falling, shade)
        case 4: (rising, low, shade)
        default: (shade, low, falling)
        }
        return (UInt8(rgb.0 * 255), UInt8(rgb.1 * 255), UInt8(rgb.2 * 255))
    }

    static func hex(_ colour: (UInt8, UInt8, UInt8)) -> String {
        String(format: "#%02X%02X%02X", colour.0, colour.1, colour.2)
    }

    static func grey(_ data: Data, width: Int, height: Int, bits: Int) throws -> CGImage {
        let info = bits == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : 0
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: bits, bitsPerPixel: bits, bytesPerRow: width * bits / 8,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider,
                                  decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw RenderError.readback }
        return image
    }
}
