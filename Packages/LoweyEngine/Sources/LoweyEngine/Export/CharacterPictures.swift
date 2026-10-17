import CoreGraphics
import Foundation
import LoweyCore

/// Pictures of a made character for games (K1): sprite frames of a clip from each direction and turnaround views, drawn
/// by the stage's renderer in the scene's Look, on a clear background, from a flat (orthographic) camera at the
/// character's own height. Only the character is drawn; everything else in the scene steps aside.
@MainActor
public final class CharacterPictures {
    /// Which motion a sheet plays.
    public enum Motion: Hashable, Sendable {
        /// What the character does on the timeline (its keys, clips and lip sync), over that stretch.
        case timeline
        /// One of the humanoid clips (people only).
        case clip(String)
        /// Standing still (one frame).
        case still

        public var name: String {
            switch self {
            case .timeline: "Timeline"
            case let .clip(name): name
            case .still: "Still"
            }
        }
    }

    private let renderer: FrameRenderer
    private let catalog: AssetCatalog
    private let paintFile: @Sendable (String) -> Data?

    public init(models: ModelLibrary = .shared, catalog: AssetCatalog, paintFile: @escaping @Sendable (String) -> Data? = { _ in nil }) throws {
        renderer = try FrameRenderer(device: RenderDevice.sharedDevice(), models: models)
        self.catalog = catalog
        self.paintFile = paintFile
    }

    /// The document with only the character showing, and the motion on it.
    static func alone(_ root: ObjectID, in document: Document, motion: Motion) -> (Document, ClosedRange<Double>) {
        var alone = document
        for id in alone.scene.roots where id != root {
            alone.scene.objects[id]?[.visible] = .bool(false)
        }
        alone.scene.objects[root]?[.visible] = .bool(true)
        var range = 0.0 ... 0.0
        switch motion {
        case .timeline:
            let timeline = document.scene.timeline
            let keyed = timeline.tracks.filter { $0.target == root }.compactMap(\.timeRange)
                + timeline.clipTracks.filter { $0.target == root }.flatMap { $0.segments.map { TimeRange(start: $0.start, end: $0.end) } }
            if let start = keyed.map(\.start).min(), let end = keyed.map(\.end).max(), end > start { range = start ... end }
        case let .clip(name):
            let duration = BuiltinClips.rig.clips[name]?.duration ?? 1
            let segment = ClipSegment(id: "sheet", clip: ClipRef(asset: BuiltinClips.assetID, name: name), start: 0, duration: duration, loop: false,
                                      blend: 0)
            alone.scene.timeline.tracks.removeAll { $0.target == root }
            alone.scene.timeline.clipTracks = [ClipTrack(id: "sheet", target: root, segments: [segment])]
            range = 0 ... duration
        case .still:
            break
        }
        return (alone, range)
    }

    /// The flat camera's view of the character from a direction (south looks at its face), framing `bounds`.
    static func viewpoint(_ root: ObjectID, in scene: Scene, bounds: Bounds, direction: SpriteSheet.Direction, pitch: Double) -> Viewpoint {
        let facing = scene.worldTransform(of: root).rotation.act(.unitZ)
        let characterYaw = atan2(facing.x, facing.z) * 180 / .pi
        // A flat view shows as much as the perspective view it stands for shows at its target: the whole character, a margin round it.
        let height = max(bounds.size.y, bounds.size.x, bounds.size.z) * 1.12
        let fieldOfView = 30.0
        return Viewpoint(target: bounds.center, yaw: characterYaw - direction.yaw, pitch: pitch, distance: height / (2 * tan(fieldOfView * .pi / 360)),
                         projection: .orthographic, fieldOfView: fieldOfView)
    }

    /// The frames of a motion from one direction, `size` pixels square, `fps` a second.
    public func frames(of root: ObjectID, in document: Document, motion: Motion, direction: SpriteSheet.Direction, size: Int, fps: Double,
                       pitch: Double = 12) async throws -> [RGBAImage] {
        let (alone, range) = Self.alone(root, in: document, motion: motion)
        guard let bounds = Self.bounds(of: root, in: alone, over: range, fps: fps) else { return [] }
        let count = motion == .still ? 1 : max(Int(((range.upperBound - range.lowerBound) * fps).rounded()), 1)
        var images: [RGBAImage] = []
        for index in 0 ..< count {
            let time = range.lowerBound + Double(index) / fps
            let animated = Animator.evaluate(alone, at: time)
            var input = RenderInput(document: Document(project: alone.project, scene: animated.scene), time: time, poses: animated.poses,
                                    catalog: catalog)
            input.paintFile = paintFile
            input.simulated = animated.simulated
            let camera = RenderCamera(viewpoint: Self.viewpoint(root, in: animated.scene, bounds: bounds, direction: direction, pitch: pitch))
            let request = FrameRequest(input: input, camera: camera, frameIndex: index, transparent: true)
            try await images.append(Self.rgba(renderer.image(request, width: size, height: size)))
        }
        return images
    }

    /// Front, three-quarter, side and back, standing.
    public func turnaround(of root: ObjectID, in document: Document, size: Int) async throws -> [RGBAImage] {
        var views: [RGBAImage] = []
        for direction in [SpriteSheet.Direction.south, .southEast, .east, .north] {
            views += try await frames(of: root, in: document, motion: .still, direction: direction, size: size, fps: 1, pitch: 0)
        }
        return views
    }

    /// Where the character reaches over the whole motion (so every frame keeps the same framing).
    static func bounds(of root: ObjectID, in document: Document, over range: ClosedRange<Double>, fps: Double) -> Bounds? {
        let steps = max(Int(((range.upperBound - range.lowerBound) * min(fps, 12)).rounded()), 1)
        var points: [Vec3] = []
        for step in 0 ... steps {
            let time = range.lowerBound + (range.upperBound - range.lowerBound) * Double(step) / Double(steps)
            let scene = Animator.evaluate(document, at: time).scene
            for id in scene.subtree(of: root) {
                guard let object = scene.objects[id], let bounds = CharacterAnatomy.coreBounds(object) else { continue }
                let world = scene.worldTransform(of: id)
                points += [bounds.min, bounds.max].map(world.apply(to:))
            }
        }
        return Bounds(points: points)
    }

    /// A rendered picture as straight-alpha RGBA bytes.
    static func rgba(_ image: CGImage) throws -> RGBAImage {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return RGBAImage(
            width: width,
            height: height,
            pixels: bytes
        ) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        for index in 0 ..< width * height {
            let alpha = Int(bytes[index * 4 + 3])
            guard alpha > 0, alpha < 255 else { continue }
            for channel in 0 ..< 3 {
                bytes[index * 4 + channel] = UInt8(min(255, Int(bytes[index * 4 + channel]) * 255 / alpha))
            }
        }
        return RGBAImage(width: width, height: height, pixels: bytes)
    }
}
