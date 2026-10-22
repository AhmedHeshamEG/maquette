import CoreGraphics
import Foundation
import LoweyCore

/// G1, for illustrators: the frame at the playhead as a layered PSD, a layer a thing (each top-level thing whole: a
/// posed mannequin is one layer, not its arms), the background under them, to draw over in Procreate.
public extension ExportSession {
    func layeredPSD(at time: Double, settings: ExportSettings) async throws -> Data {
        await loadModels()
        try await waitUntilRenderable()
        var plain = settings
        plain.final = false
        plain.transparent = false
        let size = plain.size
        let bytes = try await frameBytes(at: time, settings: plain)
        guard let found = frames.renderer.idBuffer() else { throw RenderError.readback }
        let scene = builder.document.scene
        var colour = RGBAImage.clear(width: size.width, height: size.height)
        for index in 0 ..< size.width * size.height {
            colour.pixels[index * 4] = bytes[index * 4 + 2]
            colour.pixels[index * 4 + 1] = bytes[index * 4 + 1]
            colour.pixels[index * 4 + 2] = bytes[index * 4]
            colour.pixels[index * 4 + 3] = 255
        }
        // Each pixel's top-level thing, numbered from 1 in the order they're met.
        var numbers: [ObjectID: UInt32] = [:]
        var names: [UInt32: String] = [:]
        var ids = [UInt32](repeating: 0, count: size.width * size.height)
        for y in 0 ..< size.height {
            for x in 0 ..< size.width {
                let sx = min(x * found.width / max(size.width, 1), found.width - 1)
                let sy = min(y * found.height / max(size.height, 1), found.height - 1)
                let packed = found.ids[sy * found.width + sx]
                guard PackedID.object(packed) != 0, let object = frames.renderer.object(forPacked: packed) else { continue }
                let top = scene.ancestors(of: object).last ?? object
                let number = numbers[top] ?? {
                    let next = UInt32(numbers.count + 1)
                    numbers[top] = next
                    names[next] = scene.objects[top]?.name ?? "Thing"
                    return next
                }()
                ids[y * size.width + x] = number
            }
        }
        return PSDWriter.data(LayeredPicture.split(colour: colour, ids: ids, names: names))
    }
}
