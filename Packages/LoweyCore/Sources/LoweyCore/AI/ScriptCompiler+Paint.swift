import Foundation

// MARK: - Texture (U7)

/// `{"do": "paint", "target": "Crate", "op": …}`: texturing for the bridge (D-359). Fills (a colour, a material, wear),
/// decals, faces, masks, mirror, texture size, seams, baked normals and fur, each one undo step with the files it makes.
/// Points are in the scene's metres; the paint lands where they meet the thing.
extension ScriptState {
    static let paintOps: [String: @Sendable (inout ScriptState, ObjectID, JSONValue) throws -> Void] = [
        "color": { try $0.paintColorFill($1, $2) },
        "material": { try $0.paintMaterial($1, $2) },
        "wear": { try $0.paintWear($1, $2) },
        "decal": { try $0.paintDecal($1, $2) },
        "faces": { try $0.paintFaces($1, $2) },
        "layers": { state, id, _ in try state.paintLayers(id) },
        "mask": { try $0.paintMask($1, $2) },
        "mirror": { try $0.paintMirror($1, $2) },
        "size": { try $0.paintSize($1, $2) },
        "seams": { try $0.paintSeams($1, $2) },
        "bakeNormals": { try $0.paintBakeNormals($1, $2) },
        "fur": { try $0.paintFur($1, $2) }
    ]

    mutating func paint(_ action: JSONValue) throws {
        let id = try target(action["target"])
        guard let op = string(action, "op"), let handler = Self.paintOps[op] else {
            throw fail("paint needs “op”: \(Self.paintOps.keys.sorted().joined(separator: ", "))")
        }
        try handler(&self, id, action)
    }

    // MARK: Ready to paint

    struct PaintReady {
        var object: SceneObject
        var paint: ObjectPaint
        var paintMesh: MeshData
        var source: MeshData
    }

    /// A file the script made, or one already in the project.
    func paintFile(_ name: String) -> Data? {
        files[name] ?? context.file(name)
    }

    /// `paintFile` as a closure that keeps the files as they are now.
    var paintReader: @Sendable (String) -> Data? {
        let made = files, project = context.file
        return { made[$0] ?? project($0) }
    }

    /// The thing laid flat for paint (done now if it never was; its paint carried first if it was modelled since).
    mutating func paintReady(_ id: ObjectID) throws -> PaintReady {
        guard let object = scene.objects[id], object.isPaintable else { throw fail("only shapes, modelled things and solid drawings take paint") }
        guard let source = PaintSource.unshaped(of: object) else {
            throw fail("“\(object.name)” is a placed model: paint it once on the iPad, then the bridge can texture it")
        }
        var paint: ObjectPaint
        if let existing = object.paint {
            paint = existing
            if PaintMesh.fingerprint(source) != paint.surface.mesh {
                let file = paintReader
                guard let made = PaintOperations.rebased(paint, source: source, file: file, encode: context.encodePNG) else {
                    throw fail("the paint on “\(object.name)” couldn't follow its new shape")
                }
                files.merge(made.files) { a, _ in a }
                paint = made.paint
                try run(.setPaint(id, paint), label: nil)
            }
        } else {
            do {
                let prepared = try PaintOperations.prepare(mesh: source, stretch: PaintSource.stretch(of: object), keepOwnUVs: false)
                files.merge(prepared.files) { a, _ in a }
                paint = prepared.paint
                try run(.setPaint(id, paint), label: nil)
            } catch {
                throw fail(String(describing: error))
            }
        }
        guard let unwrap = paintFile(paint.surface.unwrap).flatMap({ try? PaintUnwrap(data: $0) }), let mesh = unwrap.mesh(over: source) else {
            throw fail("the paint surface of “\(object.name)” is missing")
        }
        return PaintReady(object: scene.objects[id] ?? object, paint: paint, paintMesh: mesh, source: source)
    }

    func paintColor(_ action: JSONValue) throws -> RGBA {
        guard let value = try color(action["color"]) else { throw fail("needs “color” (\"#RRGGBB\" or \"palette:3\")") }
        return value.resolved(in: document.effectiveLook.palette)
    }

    /// A point of the scene in the paint mesh's space (the thing's own, as its paint mesh is built).
    func paintSpace(_ point: Vec3, of object: SceneObject) -> SIMD3<Float> {
        var local = scene.worldTransform(of: object.id).inverseApply(to: point).float3
        if PaintSource.toObjectSpace(of: object) != nil {
            let scale = object.transform.scale
            local *= SIMD3<Float>(Float(scale.x), Float(scale.y), Float(scale.z))
        }
        return local
    }

    func paintDirection(_ direction: Vec3, of object: SceneObject) -> SIMD3<Float> {
        normalize3(scene.worldTransform(of: object.id).inverseApplyDirection(direction).float3, fallback: SIMD3<Float>(0, 0, 1))
    }

    // MARK: Fills

    mutating func paintColorFill(_ id: ObjectID, _ action: JSONValue) throws {
        try paintFill(id, .color(paintColor(action)))
    }

    mutating func paintWear(_ id: ObjectID, _ action: JSONValue) throws {
        let kind = string(action, "kind").flatMap(PaintWear.Kind.init(rawValue:)) ?? .dirt
        let colour: RGBA? = action["color"] == nil ? nil : try paintColor(action)
        try paintFill(id, .wear(PaintWear(kind: kind, amount: number(action, "amount") ?? 0.5, color: colour)))
    }

    mutating func paintMirror(_ id: ObjectID, _ action: JSONValue) throws {
        let axis = string(action, "axis").flatMap(PaintMirror.init(rawValue:))
        var ready = try paintReady(id)
        ready.paint.mirror = axis
        try run(.setPaint(id, ready.paint), label: axis.map { "Mirror paint \($0.title.lowercased())" } ?? "No mirror")
    }

    mutating func paintFill(_ id: ObjectID, _ fill: PaintFill, pictures: MaterialPictureSource? = nil) throws {
        let ready = try paintReady(id)
        let images = PaintFills.images(fill, paintMesh: ready.paintMesh, size: ready.paint.surface.size, inputs: PaintFills.Inputs(pictures: pictures))
        guard let made = PaintOperations.addFill(fill, to: ready.paint, above: nil, object: id, images: images, encode: context.encodePNG) else {
            throw fail("“\(ready.object.name)” has \(ObjectPaint.maximumLayers) layers already")
        }
        files.merge(made.files) { a, _ in a }
        try run(made.command, label: "\(fill.title) on \(ready.object.name)")
    }

    mutating func paintMaterial(_ id: ObjectID, _ action: JSONValue) throws {
        guard let name = string(action, "material") else { throw fail("material needs “material”: \(BuiltInMaterials.all.map(\.id).joined(separator: ", "))") }
        let key = name.lowercased()
        guard var material = context.materials.material(key) ?? context.materials.all.first(where: { $0.name.lowercased() == key }) else {
            throw fail("no material “\(name)” (\(context.materials.all.map(\.id).joined(separator: ", ")))")
        }
        if let scale = number(action, "scale") { material.scale = max(scale, 0.001) }
        if action["color"] != nil { material.color = try paintColor(action) }
        var images: [String: RGBAImage] = [:]
        for key in material.pictures?.files ?? [] {
            images[key] = paintFile(key).flatMap { try? PNGCodec.decode($0) }
        }
        try paintFill(id, .material(material), pictures: images.isEmpty ? nil : MaterialPictureSource(images: images))
    }

    // MARK: Decals and faces

    mutating func paintDecal(_ id: ObjectID, _ action: JSONValue) throws {
        guard let key = string(action, "picture"), let picture = paintFile(key).flatMap({ try? PNGCodec.decode($0) }) else {
            throw fail("decal needs “picture”: a PNG in the project's assets (send it with media first)")
        }
        guard let at = vec3(action["at"]) else { throw fail("decal needs “at” (a point on the thing)") }
        let ready = try paintReady(id)
        let facing = vec3(action["facing"]).map { paintDirection($0, of: ready.object) }
        let point = paintSpace(at, of: ready.object)
        let pick = PaintSurfacePick(paintMesh: ready.paintMesh)
        // Pressed on from in front: the nearest surface along the way it faces (or from outside toward its middle).
        let toward = facing.map { -$0 } ?? normalize3(-point, fallback: SIMD3<Float>(0, 0, -1))
        guard let hit = pick.hit(origin: point - toward * 10, direction: toward, size: ready.paint.surface.size) else {
            throw fail("“at” isn't on “\(ready.object.name)”")
        }
        let decal = PaintDecal(center: hit.position, normal: facing ?? hit.normal, size: Float(number(action, "size") ?? 0.2),
                               opacity: Float(number(action, "opacity") ?? 1))
        var paint = ready.paint
        guard let (command, layer) = PaintOperations.addLayer(to: paint, above: nil, object: id) else {
            throw fail("“\(ready.object.name)” has \(ObjectPaint.maximumLayers) layers already")
        }
        try run(command, label: nil)
        paint = scene.objects[id]?.paint ?? paint
        guard let index = paint.layerIndex(layer) else { return }
        paint.layers[index].name = "Decal"
        let image = decal.image(picture, on: ready.paintMesh, textureSize: paint.surface.size)
        let tiles = PaintOperations.tileChanges(image, layer: paint.layers[index], surface: paint.surface, encode: context.encodePNG)
        files.merge(tiles.files) { a, _ in a }
        try run(.setPaint(id, paint), label: nil)
        try run(.paintTiles(id, tiles.changes), label: "Decal on \(ready.object.name)")
    }

    mutating func paintFaces(_ id: ObjectID, _ action: JSONValue) throws {
        guard let at = vec3(action["at"]) else { throw fail("faces needs “at” (a point on the face) and “color”") }
        let colour = try paintColor(action)
        let ready = try paintReady(id)
        let point = paintSpace(at, of: ready.object)
        let pick = PaintSurfacePick(paintMesh: ready.paintMesh)
        let toward = normalize3(-point, fallback: SIMD3<Float>(0, -1, 0))
        guard let hit = pick.hit(origin: point - toward * 10, direction: toward, size: ready.paint.surface.size) else {
            throw fail("“at” isn't on “\(ready.object.name)”")
        }
        guard let layer = ready.paint.layers.last(where: { $0.fill == nil }) ?? ready.paint.layers.last else { return }
        let reader = paintReader
        let picture = PaintComposer.layerImage(layer, surface: ready.paint.surface) { reader($0).flatMap { try? PNGCodec.decode($0) } }
        let made = PaintOperations.fillFaces(pick.face(of: hit.triangle), color: colour, layer: layer, surface: ready.paint.surface,
                                             paintMesh: ready.paintMesh, image: picture, encode: context.encodePNG)
        files.merge(made.files) { a, _ in a }
        try run(made.changes.isEmpty ? nil : .paintTiles(id, made.changes), label: "Face of \(ready.object.name)")
    }

    // MARK: Layers, mask, size, seams

    mutating func paintLayers(_ id: ObjectID) throws {
        guard let paint = scene.objects[id]?.paint else {
            report.append("No paint")
            return
        }
        for (index, layer) in paint.layers.enumerated().reversed() {
            let maps = layer.paintedMaps.map(\.title).joined(separator: ", ")
            report.append("\(index + 1). \(layer.name)\(layer.fill.map { " (\($0.title))" } ?? ""): \(maps.isEmpty ? "empty" : maps)"
                + "\(layer.hasMask ? ", masked" : "")\(layer.visible ? "" : ", hidden") · \(layer.blend.title) \(Int(layer.opacity * 100)) %")
        }
    }

    mutating func paintMask(_ id: ObjectID, _ action: JSONValue) throws {
        let ready = try paintReady(id)
        let number = Int(number(action, "layer") ?? Double(ready.paint.layers.count))
        guard number >= 1, number <= ready.paint.layers.count else { throw fail("“layer” is 1 … \(ready.paint.layers.count) (1 is the bottom)") }
        let layer = ready.paint.layers[number - 1]
        guard let made = PaintOperations.setMask(bool(action, "on") ?? true, layer: layer.id, in: ready.paint, object: id, encode: context.encodePNG)
        else { return }
        files.merge(made.files) { a, _ in a }
        try run(made.command, label: "Mask on \(layer.name)")
    }

    mutating func paintSize(_ id: ObjectID, _ action: JSONValue) throws {
        guard let pixels = number(action, "pixels").map(Int.init), PaintSurface.sizes.contains(pixels) else {
            throw fail("size needs “pixels”: \(PaintSurface.sizes.map(String.init).joined(separator: ", "))")
        }
        let ready = try paintReady(id)
        let pictures = PaintPictures(ready.paint, file: paintReader)
        guard let made = PaintOperations.resized(ready.paint, to: pixels, pictures: pictures, encode: context.encodePNG) else { return }
        files.merge(made.files) { a, _ in a }
        try run(.setPaint(id, made.paint), label: "Texture \(pixels) px")
    }

    mutating func paintSeams(_ id: ObjectID, _ action: JSONValue) throws {
        let ready = try paintReady(id)
        let edges: [PaintSeam] = (action["edges"]?.arrayValue ?? []).compactMap { edge in
            guard let ends = edge.arrayValue, ends.count == 2, let a = vec3(ends[0]), let b = vec3(ends[1]) else { return nil }
            let pa = paintSpace(a, of: ready.object), pb = paintSpace(b, of: ready.object)
            return PaintSeam(Vec3(Double(pa.x), Double(pa.y), Double(pa.z)), Vec3(Double(pb.x), Double(pb.y), Double(pb.z)))
        }
        let file = paintReader
        guard let made = PaintOperations.rebased(ready.paint, source: ready.source, file: file, seams: .some(edges.isEmpty ? nil : edges),
                                                 encode: context.encodePNG) else { throw fail("the seams couldn't be laid flat") }
        files.merge(made.files) { a, _ in a }
        try run(.setPaint(id, made.paint), label: edges.isEmpty ? "Automatic seams" : "\(edges.count) seam\(edges.count == 1 ? "" : "s")")
    }

    // MARK: Normals and fur

    mutating func paintBakeNormals(_ id: ObjectID, _ action: JSONValue) throws {
        let from = try target(action["from"])
        guard let high = scene.objects[from], let highMesh = PaintSource.mesh(of: high) else { throw fail("“from” has to be a shape with a surface") }
        let ready = try paintReady(id)
        // The detailed surface in the light one's space.
        let toWorld = scene.worldTransform(of: from)
        var moved = highMesh
        moved.positions = highMesh.positions.map { paintSpace(toWorld.apply(to: Vec3(Double($0.x), Double($0.y), Double($0.z))), of: ready.object) }
        moved.normals = highMesh.normals.map { paintDirection(toWorld.applyDirection(Vec3(Double($0.x), Double($0.y), Double($0.z))), of: ready.object) }
        let image = NormalBake.bake(low: ready.paintMesh, high: moved, size: ready.paint.surface.size)
        let png = context.encodePNG(image)
        let name = PaintFiles.tileName(for: png)
        files[name] = png
        var paint = ready.paint
        paint.normalMap = name
        paint.normalsFrom = high.name
        try run(.setPaint(id, paint), label: "Normals from \(high.name)")
    }

    mutating func paintFur(_ id: ObjectID, _ action: JSONValue) throws {
        let length = number(action, "length") ?? 0
        var changes = [PropertyChange(object: id, key: .furLength, value: length > 0 ? .float(length) : nil)]
        if let density = number(action, "density") { changes.append(PropertyChange(object: id, key: .furDensity, value: .float(min(max(density, 0), 1)))) }
        if let style = string(action, "style").flatMap(FurSettings.Style.init(rawValue:)) {
            changes.append(PropertyChange(object: id, key: .furStyle, value: style == .shells ? nil : .enumeration(style.rawValue)))
        }
        if let droop = number(action, "droop") { changes.append(PropertyChange(object: id, key: .furDroop, value: .float(min(max(droop, 0), 1)))) }
        try run(.setProperties(changes), label: length > 0 ? "Fur \(Self.short(length * 100)) cm" : "No fur")
    }
}
