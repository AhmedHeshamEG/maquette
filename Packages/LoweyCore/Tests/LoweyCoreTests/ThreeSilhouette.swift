import Foundation
@testable import LoweyCore

/// Maquette's own golden for the three.js render check (X1 step 0): where its things are at a moment, seen through its
/// own camera, as a mask a browser render of the web folder must cover. Placement, keys and the lens are Maquette's;
/// nothing comes from three.js.
enum ThreeSilhouette {
    /// The scene at `time` (its keyed places and lenses), as one byte per pixel: 255 where a surface is, 0 elsewhere.
    static func mask(_ scene: Scene, at time: Double, camera id: ObjectID, width: Int, height: Int) -> [UInt8] {
        let posed = keyed(scene, at: time)
        guard let camera = posed.objects[id] else { return [] }
        let view = posed.worldTransform(of: id)
        let fov = (camera[.fieldOfView]?.floatValue ?? 50) * .pi / 180
        let focal = 1 / tan(fov / 2), aspect = Double(width) / Double(height)
        var pixels = [UInt8](repeating: 0, count: width * height)
        for objectID in posed.objects.keys where posed.isEffectivelyVisible(objectID) {
            guard let object = posed.objects[objectID], let mesh = SceneExport.localMesh(of: object, look: Look()) else { continue }
            let world = posed.worldTransform(of: objectID)
            let screen = mesh.positions.map { position -> (Double, Double, Bool) in
                let local = view.inverseApply(to: world.apply(to: Vec3(Double(position.x), Double(position.y), Double(position.z))))
                let depth = -local.z
                guard depth > 0.01 else { return (0, 0, false) }
                let x = (local.x * focal / aspect / depth + 1) / 2 * Double(width)
                let y = (1 - local.y * focal / depth) / 2 * Double(height)
                return (x, y, true)
            }
            for corner in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
                let a = screen[Int(mesh.indices[corner])], b = screen[Int(mesh.indices[corner + 1])], c = screen[Int(mesh.indices[corner + 2])]
                guard a.2, b.2, c.2 else { continue }
                fill(a, b, c, into: &pixels, width: width, height: height)
            }
        }
        return pixels
    }

    static func keyed(_ scene: Scene, at time: Double) -> Scene {
        var posed = scene
        for track in scene.timeline.tracks {
            guard var object = posed.objects[track.target], let value = track.value(at: time) else { continue }
            switch (track.property, value) {
            case let (.position, .vec3(position)): object.transform.position = position
            case let (.rotation, .quat(rotation)): object.transform.rotation = rotation
            case let (.scale, .vec3(scale)): object.transform.scale = scale
            default: object[track.property] = value
            }
            posed.objects[track.target] = object
        }
        return posed
    }

    static func fill(_ a: (Double, Double, Bool), _ b: (Double, Double, Bool), _ c: (Double, Double, Bool), into pixels: inout [UInt8],
                     width: Int, height: Int) {
        let area = (b.0 - a.0) * (c.1 - a.1) - (b.1 - a.1) * (c.0 - a.0)
        guard abs(area) > 1e-12 else { return }
        let minX = max(Int(min(a.0, b.0, c.0).rounded(.down)), 0), maxX = min(Int(max(a.0, b.0, c.0).rounded(.up)), width - 1)
        let minY = max(Int(min(a.1, b.1, c.1).rounded(.down)), 0), maxY = min(Int(max(a.1, b.1, c.1).rounded(.up)), height - 1)
        guard minX <= maxX, minY <= maxY else { return }
        for y in minY ... maxY {
            for x in minX ... maxX {
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                let w0 = (b.0 - a.0) * (py - a.1) - (b.1 - a.1) * (px - a.0)
                let w1 = (c.0 - b.0) * (py - b.1) - (c.1 - b.1) * (px - b.0)
                let w2 = (a.0 - c.0) * (py - c.1) - (a.1 - c.1) * (px - c.0)
                if (w0 >= 0 && w1 >= 0 && w2 >= 0) || (w0 <= 0 && w1 <= 0 && w2 <= 0) { pixels[y * width + x] = 255 }
            }
        }
    }

    /// A binary PGM (P5), the simplest picture a node script can read.
    static func pgm(_ pixels: [UInt8], width: Int, height: Int) -> Data {
        Data("P5\n\(width) \(height)\n255\n".utf8) + Data(pixels)
    }
}
