import Foundation

/// What `ThreeRecorder` took out of a running three.js page, made ours: the scene as editable things (through
/// `ThreeObjectReader`, as a scene file would come in), its sampled motion as keys, and each surface drawn by its own
/// shader as a card in its place playing the page with only that surface showing (`ThreeRecorder.solo`), so a water
/// shader still plays as before.
public enum ThreeRecording {
    /// A surface kept playing as a web piece: where it is in the scene (a child-index path), its name, and its box in
    /// its own space.
    public struct StandIn: Equatable, Sendable {
        public var name: String
        public var uuid: String
        public var path: [Int]
        public var center: Vec3
        public var size: Vec3
    }

    public struct Result: Sendable {
        public var reader: ThreeObjectReader.Result
        /// The stand-ins, each with the card standing for it (already in the scene fragment, under the stand-in's group).
        public var standIns: [(standIn: StandIn, card: ObjectID)]
        /// How long the recorded motion is (s), and the page's moment it starts at.
        public var seconds: Double
        public var from: Double
        /// The page's size (CSS pixels).
        public var width: Int
        public var height: Int
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        /// The page ran, but no three.js scene showed itself (an HTML composition, or three.js loaded some other way).
        case noScene
        case unreadable(String)

        public var description: String {
            switch self {
            case .noScene: "That page doesn't make a three.js scene."
            case let .unreadable(message): "Couldn't read the page's scene: \(message)"
            }
        }
    }

    /// A stand-in's card size (pixels on its longer side).
    public static let cardPixels = 1024

    /// Reads the recorder's output. `piece` is the stored copy of the page (an `assets/` folder); each stand-in plays the
    /// page `soloEntry(index)` inside it, which the caller writes with `soloPage`.
    public static func read(_ output: String, folder: String, ids: inout IDFactory) throws -> Result {
        guard let data = output.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unreadable("not JSON")
        }
        if let error = json["error"] as? String {
            throw error == "noScene" || error == "noHook" ? Failure.noScene : Failure.unreadable(json["message"] as? String ?? error)
        }
        guard let scene = json["scene"], let recording = json["recording"] as? [String: Any],
              let sceneData = try? JSONSerialization.data(withJSONObject: scene) else { throw Failure.unreadable("no scene") }
        var reader = try ThreeObjectReader.read(sceneData, ids: &ids)
        let from = recording["from"] as? Double ?? 0
        let width = recording["width"] as? Int ?? 1280
        let height = recording["height"] as? Int ?? 720
        var standIns: [(StandIn, ObjectID)] = []
        for (index, source) in (recording["standIns"] as? [[String: Any]] ?? []).enumerated() {
            guard let standIn = standIn(source), let group = reader.objects[standIn.uuid],
                  let slot = reader.scene.fragment.objects.firstIndex(where: { $0.id == group }) else { continue }
            let card = card(for: standIn, under: group, piece: WebPiece(kind: .html, file: folder, entry: soloEntry(index), start: -from), ids: &ids)
            reader.scene.fragment.objects[slot].children.append(card.id)
            reader.scene.fragment.objects.append(card)
            standIns.append((standIn, card.id))
        }
        let notes = recording["notes"] as? [String] ?? []
        if notes.contains("morph") { reader.notes.append("Morph weights: the shapes came in at the recorded moment; their motion stayed in the page.") }
        if notes.contains("instances") { reader.notes.append("Moving instances: they came in where they stood; their own motion stayed in the page.") }
        for name in Set(standIns.map(\.0.name)).sorted() {
            reader.notes.append("\(name) shader: kept as a web object, plays as before.")
        }
        return Result(reader: reader, standIns: standIns, seconds: recording["seconds"] as? Double ?? 0, from: from, width: width, height: height)
    }

    /// The page inside the stored folder that plays stand-in `index`.
    public static func soloEntry(_ index: Int) -> String {
        "maquette-solo-\(index + 1).html"
    }

    /// The page's HTML with the hook and the stand-in's solo script added first in `<head>`.
    public static func soloPage(_ html: String, standIn: StandIn) -> String {
        let script = "<script>\(ThreeRecorder.hook)\n\(ThreeRecorder.solo(standIn))</script>"
        if let head = html.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            var page = html
            page.insert(contentsOf: script, at: head.upperBound)
            return page
        }
        if let open = html.range(of: "<html[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            var page = html
            page.insert(contentsOf: "<head>\(script)</head>", at: open.upperBound)
            return page
        }
        return script + html
    }

    /// How a card lies on a box: across its two longest sides, facing along the thinnest (`axis`), with the picture's
    /// `width` and `height` and the box's `depth` along the facing.
    public static func cardFrame(size: Vec3) -> (axis: String, width: Double, height: Double, depth: Double) {
        let x = abs(size.x), y = abs(size.y), z = abs(size.z)
        if z <= x, z <= y { return ("z", x, y, z) }
        if y <= x { return ("y", x, z, y) }
        return ("x", z, y, x)
    }

    /// The card, base-centred like every card: standing on the box's face, turned to face along the thinnest side.
    static func card(for standIn: StandIn, under parent: ObjectID, piece: WebPiece, ids: inout IDFactory) -> SceneObject {
        let frame = cardFrame(size: standIn.size)
        let turn: Quat = switch frame.axis {
        case "x": Quat(angle: .pi / 2, axis: .unitY)
        case "y": Quat(angle: -.pi / 2, axis: .unitX)
        default: .identity
        }
        let height = max(frame.height, 1e-3)
        let aspect = max(frame.width, 1e-3) / height
        var web = piece
        let longest = Double(cardPixels)
        web.width = aspect >= 1 ? cardPixels : max(Int((longest * aspect).rounded()), 16)
        web.height = aspect >= 1 ? max(Int((longest / aspect).rounded()), 16) : cardPixels
        let recipe = CardRecipe(aspect: aspect, thickness: 0.001, border: 0, web: web)
        let position = standIn.center + turn.act(Vec3(0, -height / 2, 0))
        return SceneObject(id: ids.next(), name: standIn.name, kind: .card(recipe), parent: parent,
                           transform: Transform(position: position, rotation: turn, scale: Vec3(height, height, height)))
    }

    static func standIn(_ source: [String: Any]) -> StandIn? {
        guard let uuid = source["uuid"] as? String, let path = source["path"] as? [Int],
              let center = GLTFReader.numbers(source["center"]), center.count == 3,
              let size = GLTFReader.numbers(source["size"]), size.count == 3 else { return nil }
        return StandIn(name: source["name"] as? String ?? "Shader", uuid: uuid, path: path,
                       center: Vec3(center[0], center[1], center[2]), size: Vec3(size[0], size[1], size[2]))
    }
}
