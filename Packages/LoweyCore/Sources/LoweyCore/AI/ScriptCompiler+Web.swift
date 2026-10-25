import Foundation

// MARK: - The web layer (M12)

extension ScriptState {
    /// `{"do": "web", "op": "add" | "edit" | "list", …}`: web pieces, pages, three.js scenes and Lottie files played on a
    /// screen in the scene or over the frame, on the timeline's clock.
    mutating func web(_ action: JSONValue) throws {
        switch string(action, "op") ?? "add" {
        case "add": try addWeb(action)
        case "edit": try editWeb(action)
        case "list": listWeb()
        case let other: throw fail("web has no op “\(other)” (add, edit, list)")
        }
    }

    /// `{"op": "add", "name": "Chart", "on": "scene" | "frame", "html": "<!doctype html>…"}` (or `"lottie": {…}`, or
    /// `"file": "chart.html"` already in the project), with `width`/`height` (CSS pixels), `start` (seconds or a word),
    /// `duration`, `loop`,
    /// and where: `at` and `size` (metres tall in the scene; frame units over it), `facing` (degrees, in the scene).
    private mutating func addWeb(_ action: JSONValue) throws {
        var piece = try webPiece(action, base: WebPiece(start: context.now))
        guard piece.isPlayable else { throw fail("web needs “html”, “lottie” or “file”") }
        if piece.kind == .lottie, action["width"] == nil, let size = Self.lottieSize(action["lottie"]) {
            piece.width = size.width
            piece.height = size.height
            if piece.duration == nil { piece.duration = size.duration }
        }
        let fallback = piece.file.map { ($0 as NSString).deletingPathExtension } ?? (piece.kind == .lottie ? "Lottie" : "Web piece")
        if string(action, "on") == "frame" {
            let at = vec3(action["at"]) ?? Vec3(0, 0, 0)
            let layer = Double(scene.objects.values.filter(\.kind.isOverlay).count)
            var object = SceneObject(id: context.ids.next(), name: name(action, fallback: fallback),
                                     kind: .overlay(OverlayRecipe(shape: .image, aspect: piece.aspect, web: piece)),
                                     transform: Transform(position: Vec3(at.x, at.y, layer)))
            let size = number(action, "size") ?? 2.6
            object.transform.scale = Vec3(size, size, 1)
            try insert(object, action: action, verb: "Web piece over the frame")
            return
        }
        var object = SceneObject(id: context.ids.next(), name: name(action, fallback: fallback),
                                 kind: .card(CardRecipe(aspect: piece.aspect, border: 0.015, web: piece)))
        object[.color] = .color(.rgba(RGBA(0.08, 0.08, 0.09)))
        let size = number(action, "size") ?? 1.2
        object.transform.scale = Vec3(size, size, size)
        if let facing = number(action, "facing") { object.transform.rotation = Quat(angle: facing * .pi / 180, axis: .unitY) }
        object.transform.position = try point(action["at"]) ?? context.focus
        try insert(object, action: action, verb: "Web piece")
    }

    /// `{"op": "edit", "target": "Chart", "html": "…"}`: a new page (or Lottie, file, size, start, duration, loop).
    private mutating func editWeb(_ action: JSONValue) throws {
        let id = try target(action["target"])
        guard let object = scene.objects[id], let current = scene.webPiece(id) else { throw fail("“\(scene.objects[id]?.name ?? id.raw)” isn't a web piece") }
        let piece = try webPiece(action, base: current)
        guard piece.isPlayable else { throw fail("web needs “html”, “lottie” or “file”") }
        switch object.kind {
        case var .card(recipe):
            recipe.web = piece
            recipe.aspect = piece.aspect
            try run(.setKind(id, .card(recipe)), label: "Edit web piece “\(object.name)”")
        case var .overlay(recipe):
            recipe.web = piece
            recipe.aspect = piece.aspect
            try run(.setKind(id, .overlay(recipe)), label: "Edit web piece “\(object.name)”")
        default: break
        }
    }

    private mutating func listWeb() {
        let ids = scene.webPieceIDs
        guard !ids.isEmpty else {
            report.append("No web pieces")
            return
        }
        for id in ids {
            guard let object = scene.objects[id], let piece = scene.webPiece(id) else { continue }
            let place = object.kind.isOverlay ? "over the frame" : "in the scene"
            let what = piece.file ?? "\(piece.source?.count ?? 0) characters inline"
            let length = piece.duration.map { ", \(format($0))\(piece.loop == true ? " looping" : "")" } ?? ""
            report.append("“\(object.name)” [\(id.raw)] \(piece.kind.rawValue) \(piece.width)×\(piece.height) \(place), "
                + "from \(format(piece.start))\(length): \(what)")
        }
    }

    /// `base` with what the action says.
    private func webPiece(_ action: JSONValue, base: WebPiece) throws -> WebPiece {
        var piece = base
        if let html = string(action, "html") {
            piece.kind = .html
            piece.source = html
            piece.file = nil
        } else if let lottie = action["lottie"] {
            piece.kind = .lottie
            piece.source = try lottie.stringValue ?? String(decoding: LoweyJSON.encode(lottie), as: UTF8.self)
            piece.file = nil
        } else if let file = string(action, "file") {
            guard context.file(file) != nil || context.file(file + "/" + (string(action, "entry") ?? "index.html")) != nil else {
                throw fail("no file “\(file)” in the project (bring it in with add_media)")
            }
            piece.kind = string(action, "kind").flatMap(WebPiece.Kind.init(rawValue:)) ?? WebPiece.kind(forFile: file)
            piece.file = file
            piece.entry = string(action, "entry")
            piece.source = nil
        }
        if let width = number(action, "width") { piece.width = Int(width) }
        if let height = number(action, "height") { piece.height = Int(height) }
        let size = piece.clampedSize
        (piece.width, piece.height) = (size.width, size.height)
        if action["start"] != nil { piece.start = try time(action["start"]) }
        if let duration = number(action, "duration") { piece.duration = duration > 0 ? duration : nil }
        if let loop = bool(action, "loop") { piece.loop = loop }
        return piece
    }

    /// A Lottie's own size and length (`w`, `h`, `op − ip` frames at `fr`).
    static func lottieSize(_ value: JSONValue?) -> (width: Int, height: Int, duration: Double?)? {
        var object = value?.objectValue
        if object == nil, let text = value?.stringValue, let parsed = try? LoweyJSON.decode(JSONValue.self, from: Data(text.utf8)) {
            object = parsed.objectValue
        }
        guard let object, let width = object["w"]?.numberValue, let height = object["h"]?.numberValue else { return nil }
        let frames = (object["op"]?.numberValue ?? 0) - (object["ip"]?.numberValue ?? 0)
        let rate = object["fr"]?.numberValue ?? 0
        return (Int(width), Int(height), frames > 0 && rate > 0 ? frames / rate : nil)
    }
}
