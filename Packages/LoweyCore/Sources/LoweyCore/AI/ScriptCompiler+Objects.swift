import Foundation

// MARK: - Making things

extension ScriptState {
    func format(_ seconds: Double) -> String { String(format: "%.2f s", seconds) }

    mutating func insert(_ object: SceneObject, action: JSONValue, verb: String) throws {
        var object = object
        let parent = try action["parent"].map { try target($0) }
        if let rotation = rotation(action["rotation"]) { object.transform.rotation = rotation }
        if let color = try color(action["color"]) { object[.color] = .color(color) }
        if let glow = number(action, "glow") {
            object[.emissiveIntensity] = .float(glow)
            if object[.emissive] == nil, let color = object[.color] { object[.emissive] = color }
        }
        try run(operations.add(object, parent: parent), label: "\(verb) “\(object.name)”")
        remember(action, object.id, name: object.name)
    }

    mutating func add(_ action: JSONValue) throws {
        let shapeName = string(action, "shape") ?? "cube"
        var object: SceneObject
        if shapeName == "group" {
            object = SceneObject(id: context.ids.next(), name: name(action, fallback: "Group"), kind: .group)
        } else {
            guard let shape = PrimitiveShape(rawValue: shapeName) else {
                throw fail("unknown shape “\(shapeName)” (\(PrimitiveShape.allCases.map(\.rawValue).joined(separator: ", ")))")
            }
            object = SceneObject(id: context.ids.next(), name: name(action, fallback: shape.displayName), kind: .primitive(shape))
            object[.color] = .color(.rgba(.blockout))
        }
        if let size = vec3(action["size"]) { object.transform.scale = size }
        let at = try point(action["at"]) ?? context.focus
        // Given a height (or told not to), it goes exactly there; otherwise it stands on the ground.
        let exact = bool(action, "onGround") == false || (action["at"].flatMap(vec3) != nil && at.y != 0)
        if exact {
            object.transform.position = at
        } else {
            object = operations.placeOnGround(object, at: at)
        }
        try insert(object, action: action, verb: "Add")
        try settle(object.id, action, at: at)
    }

    /// After a thing is added: `"anchor": "center"` puts its middle (not its bottom) at `at`, and a `relation` places it
    /// by the solver, for shapes as for Kit models (S16: a cube "on" a desk landed on the floor).
    mutating func settle(_ id: ObjectID, _ action: JSONValue, at: Vec3) throws {
        if action["relation"] != nil {
            var placed = action.objectValue ?? [:]
            placed["target"] = .string(id.raw)
            try relate(.object(placed))
            return
        }
        switch string(action, "anchor") {
        case nil, "bottom"?:
            return
        case "center"?, "centre"?, "middle"?:
            guard let box = SceneBounds(library: context.library).worldBounds(of: id, in: scene),
                  let position = scene.objects[id]?.transform.position else { return }
            let moved = position + (at - box.center)
            try run(.setProperties([PropertyChange(object: id, key: .position, value: .vec3(moved))]), label: nil)
        case let other?:
            throw fail("unknown anchor “\(other)” (bottom, center)")
        }
    }

    mutating func place(_ action: JSONValue) throws {
        guard let query = string(action, "asset") ?? string(action, "query") else { throw fail("place needs “asset” (a library search)") }
        let results = LibrarySearch.search(query, in: context.library).filter {
            switch $0 {
            case .asset, .prefab: true
            default: false
            }
        }
        var object: SceneObject
        switch results.first {
        case let .asset(asset)?:
            object = SceneObject(id: context.ids.next(), name: name(action, fallback: asset.name), kind: .asset(asset.id))
        case let .prefab(prefab)?:
            object = SceneObject(id: context.ids.next(), name: name(action, fallback: prefab.name), kind: .prefab(prefab.id))
        default:
            let names = context.library.assets.prefix(30).map(\.name) + context.library.prefabs.prefix(10).map(\.name)
            throw fail("nothing in the library matches “\(query)”. Library: \(names.joined(separator: ", "))")
        }
        if let scale = vec3(action["scale"]) { object.transform.scale = scale }
        let at = try point(action["at"]) ?? context.focus
        object = operations.placeOnGround(object, at: at)
        try insert(object, action: action, verb: "Place")
        try settle(object.id, action, at: at)
    }

    mutating func text(_ action: JSONValue) throws {
        guard let words = string(action, "text") else { throw fail("text needs “text”") }
        var recipe = TextRecipe(text: words, style: string(action, "style").flatMap(TextRecipe.Style.init(rawValue:)) ?? .blocky)
        if let size = number(action, "size") { recipe.size = size }
        if let font = string(action, "font") {
            guard context.file(font) != nil else { throw fail("no font “\(font)” in the project (bring one in with add_media)") }
            recipe.font = font
        }
        var object = SceneObject(id: context.ids.next(), name: name(action, fallback: "Text"), kind: .text(recipe))
        object[.color] = .color(.palette(0))
        object = try operations.placeOnGround(object, at: point(action["at"]) ?? context.focus)
        try insert(object, action: action, verb: "Add text")
    }

    mutating func overlay(_ action: JSONValue) throws {
        let shapeName = string(action, "shape") ?? "title"
        guard let shape = OverlayRecipe.Shape(rawValue: shapeName) else {
            throw fail("unknown overlay “\(shapeName)” (\(OverlayRecipe.Shape.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        var recipe = OverlayRecipe.default(shape)
        if let words = string(action, "text") { recipe.text = words }
        if let follow = action["follow"] { recipe.anchor = try target(follow) }
        let at = vec3(action["at"]) ?? Vec3(0, shape == .title ? 0.55 : 0, 0)
        var object = SceneObject(id: context.ids.next(), name: name(action, fallback: shape.title), kind: .overlay(recipe),
                                 transform: Transform(position: Vec3(at.x, at.y, Double(scene.objects.values.filter(\.kind.isOverlay).count))))
        if let size = number(action, "size") { object.transform.scale = Vec3(size, size, 1) }
        try insert(object, action: action, verb: "Overlay")
    }

    mutating func particles(_ action: JSONValue) throws {
        guard let preset = string(action, "preset").flatMap(ParticleRecipe.Preset.init(rawValue:)) else {
            throw fail("particles need “preset” (\(ParticleRecipe.Preset.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        var recipe = ParticleRecipe.preset(preset, seed: UInt64(number(action, "seed") ?? 1))
        if recipe.burst { recipe.burstTime = try time(action["time"] ?? action["when"]) }
        var object = SceneObject(id: context.ids.next(), name: name(action, fallback: preset.title), kind: .particles(recipe))
        object.transform.position = try point(action["at"]) ?? context.focus
        if let amount = number(action, "amount") { object.transform.scale = Vec3(amount, amount, amount) }
        try insert(object, action: action, verb: "Add \(preset.title.lowercased())")
    }

    /// A puppet from a recipe, or (with “op”) the character maker (`ScriptCompiler+Character`).
    mutating func character(_ action: JSONValue) throws {
        if action["op"] != nil {
            try characterMaker(action)
            return
        }
        var recipe = CharacterRecipe()
        if let raw = action["recipe"] { recipe = try LoweyJSON.decode(CharacterRecipe.self, from: LoweyJSON.encode(raw)) }
        if let given = string(action, "name") { recipe.name = given }
        var fragment = CharacterBuilder.build(recipe, ids: &context.ids)
        guard let root = fragment.roots.first, let index = fragment.objects.firstIndex(where: { $0.id == root }) else { return }
        fragment.objects[index].name = ObjectFactory.uniqueName(recipe.name, in: scene)
        fragment.objects[index].transform.position = try point(action["at"]) ?? context.focus
        if let facing = number(action, "facing") { fragment.objects[index].transform.rotation = Quat(angle: facing * .pi / 180, axis: .unitY) }
        try run(.insert(fragment, parent: nil, index: nil), label: "Character “\(fragment.objects[index].name)”")
        remember(action, root, name: fragment.objects[index].name)
    }

    /// A blob character (the house style): {"do": "blob", "likeness": "Isaac Newton"} or {"recipe": {...}}, or both
    /// (the recipe's fields override the likeness). Optional: name, label (text on the hat), at, facing.
    mutating func blob(_ action: JSONValue) throws {
        var recipe = BlobRecipe()
        if let who = string(action, "likeness") ?? string(action, "person") {
            guard let known = Likeness.recipe(for: who) else {
                throw fail("unknown likeness “\(who)” (\(Likeness.people.keys.sorted().joined(separator: ", "))); describe them with “recipe” instead")
            }
            recipe = known
        }
        if let raw = action["recipe"]?.objectValue {
            // Overlay the given fields on the likeness (or the defaults).
            var merged = try LoweyJSON.decode(JSONValue.self, from: LoweyJSON.encode(recipe)).objectValue ?? [:]
            for (key, value) in raw {
                merged[key] = value
            }
            recipe = try LoweyJSON.decode(BlobRecipe.self, from: LoweyJSON.encode(JSONValue.object(merged)))
        }
        if let given = string(action, "name") { recipe.name = given }
        if let label = string(action, "label") { recipe.hatLabel = label }
        let build = BlobCharacter.build(recipe, ids: &context.ids)
        var fragment = build.fragment
        guard let root = fragment.roots.first, let index = fragment.objects.firstIndex(where: { $0.id == root }) else { return }
        fragment.objects[index].name = ObjectFactory.uniqueName(recipe.name, in: scene)
        fragment.objects[index].transform.position = try point(action["at"]) ?? context.focus
        if let facing = number(action, "facing") { fragment.objects[index].transform.rotation = Quat(angle: facing * .pi / 180, axis: .unitY) }
        try run(.insert(fragment, parent: nil, index: nil), label: "Character “\(fragment.objects[index].name)”")
        var withFloat = timeline
        withFloat.behaviors += build.behaviors
        try run(.setTimeline(withFloat), label: nil)
        remember(action, root, name: fragment.objects[index].name)
    }

    mutating func light(_ action: JSONValue) throws {
        let type: LightType = switch string(action, "type") {
        case "spot": .spot
        case "sun", "directional": .directional
        case "panel", "softPanel", "area": .area
        default: .point
        }
        var factory = ObjectFactory(ids: context.ids)
        var object = try factory.light(type, at: point(action["at"]) ?? context.focus + Vec3(0, 2, 0))
        context.ids = factory.ids
        object.name = name(action, fallback: object.name)
        if let color = try color(action["color"]) { object[.lightColor] = .color(color) }
        if let intensity = number(action, "intensity") { object[.lightIntensity] = .float(intensity) }
        if let range = number(action, "range") { object[.lightRange] = .float(range) }
        if let cone = number(action, "cone") ?? number(action, "angle") { object[.spotAngle] = .float(min(max(cone, 1), 179)) }
        if let softness = number(action, "penumbra") ?? number(action, "softness") { object[.spotSoftness] = .float(min(max(softness, 0), 1)) }
        if let shadows = bool(action, "shadows") { object[.lightShadows] = .bool(shadows) }
        if let size = action["size"]?.arrayValue?.compactMap(\.numberValue), size.count == 2 {
            object[.lightWidth] = .float(max(size[0], 0.05))
            object[.lightHeight] = .float(max(size[1], 0.05))
        }
        if let aim = try point(action["aim"]) {
            object.transform.rotation = BehaviorEvaluator.facing(aim - object.transform.position, cameraStyle: true)
        }
        try insert(object, action: action, verb: "Light")
    }

    /// `{"do": "mark", "name": "Plate", "at": [0, 0.8, 0], "radius": 0.1}` or `"on": "Plate 3"`: a named spot that
    /// draws nothing, for cameras to watch and focus on. On a thing, it rides with it.
    mutating func mark(_ action: JSONValue) throws {
        var object = SceneObject(id: context.ids.next(), name: name(action, fallback: "Mark"), kind: .group)
        object[.markRadius] = .float(max(number(action, "radius") ?? 0.1, 0.001))
        var parent: ObjectID?
        if let on = action["on"] {
            let host = try target(on)
            parent = host
            let box = SceneBounds(library: context.library).worldBounds(of: host, in: scene)
            let world = try point(action["at"]) ?? box?.center ?? scene.worldTransform(of: host).position
            object.transform = Transform.relative(world: Transform(position: world), toParent: scene.worldTransform(of: host))
        } else {
            object.transform.position = try point(action["at"]) ?? context.focus
        }
        try run(operations.add(object, parent: parent), label: "Mark “\(object.name)”")
        remember(action, object.id, name: object.name)
    }

    mutating func camera(_ action: JSONValue) throws {
        let from = try point(action["from"] ?? action["at"]) ?? (context.focus + Vec3(0, 1.6, 6))
        let look = try point(action["lookAt"]) ?? context.focus
        let direction = (look - from).normalized
        let yaw = atan2(-direction.x, -direction.z)
        let pitch = asin(max(-1, min(1, direction.y)))
        var object = SceneObject(id: context.ids.next(), name: name(action, fallback: "Camera"), kind: .camera,
                                 transform: Transform(position: from, rotation: (Quat(angle: yaw, axis: .unitY) * Quat(angle: pitch, axis: .unitX)).normalized))
        if let focal = number(action, "focalLength") { object[.fieldOfView] = .float(CameraLens.fieldOfView(focalLength: focal)) }
        object[.fieldOfView] = object[.fieldOfView] ?? .float(number(action, "fov") ?? 45)
        object[.focusDistance] = .float(from.distance(to: look))
        if let aperture = number(action, "aperture") { object[.aperture] = .float(aperture) }
        if let drift = number(action, "drift") { object[.rigDrift] = .float(min(max(drift, 0), 1)) }
        // Keeps turning to watch a thing (a mark that moves takes the camera with it), and keeps it sharp.
        if let watched = action["watch"] {
            let id = try target(watched)
            object[.lookAt] = .string(id.raw)
            object[.focusOn] = .string(id.raw)
        }
        try insert(object, action: action, verb: "Camera")
        if bool(action, "active") ?? (scene.activeCamera == nil) {
            try run(.setActiveCamera(object.id), label: nil)
        }
    }
}
