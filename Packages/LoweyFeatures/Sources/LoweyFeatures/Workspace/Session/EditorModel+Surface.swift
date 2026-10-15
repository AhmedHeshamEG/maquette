import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Draw ▸ Surface and the layers' fills (U7): materials, colours and wear as fill layers, masks, decals, the texture's
/// size, mirrored painting, normals baked from a detailed copy, and fur. Each is one undo step; heavy work (a fill at
/// 2048, a bake) runs off the main thread and lands when it's done, dropped if the thing changed meanwhile.
extension EditorModel {
    /// The thing Surface works on: the paint target, made ready to paint when it isn't.
    func surfaceTarget() -> SceneObject? {
        guard let object = paintTarget else {
            app.show("Tap a thing to work on its surface")
            return nil
        }
        if object.paint == nil {
            preparePaint(object.id)
            app.show("Getting \(object.name) ready to paint: try again in a moment")
            return nil
        }
        guard paintFitsShape(object) else {
            rebasePaint(object.id)
            return nil
        }
        return object
    }

    // MARK: Drops

    /// A colour (its hex) or a material dragged onto the stage: a colour becomes the thing's own colour (under any
    /// paint), a material a fill layer on top (D-360). False when it's neither, or lands on nothing.
    func dropSurface(_ item: String, at point: CGPoint) -> Bool {
        let colour = item.hasPrefix("#") ? HmmColour(hex: item) : nil
        let material = item.hasPrefix(MaterialDrop.prefix) ? app.materials.material(String(item.dropFirst(MaterialDrop.prefix.count))) : nil
        guard colour != nil || material != nil else { return false }
        guard let stage, let picked = stage.pickObject(at: point), let object = baseScene.objects[picked.0] else {
            app.show("Drop it on a thing")
            return true
        }
        if let colour {
            perform(.setProperties([PropertyChange(object: object.id, key: .color, value: .color(.rgba(RGBA(colour.red, colour.green, colour.blue))))]))
            HmmHaptics.play(.commit)
            return true
        }
        guard let material, object.isPaintable else {
            app.show("Materials go on shapes, modelled parts and placed models")
            return true
        }
        colourPaint.target = object.id
        select(object.id)
        guard object.paint != nil else {
            preparePaint(object.id)
            app.show("Getting \(object.name) ready: drop it again in a moment")
            return true
        }
        addFill(.material(material), to: object.id)
        return true
    }

    // MARK: Fills

    /// A new fill layer of a colour, a material or wear on top of the target (or on `id`).
    func addFill(_ fill: PaintFill, to id: ObjectID? = nil, masked: Bool = false) {
        guard let object = id.flatMap({ baseScene.objects[$0] }) ?? surfaceTarget(), let paint = object.paint,
              let surface = paintSurface(of: object) else {
            if let id, let object = baseScene.objects[id], object.paint == nil, object.isPaintable { preparePaint(id) }
            return
        }
        let inputs = fillInputs(fill, surface: surface.mesh, paint: paint)
        let folder = assetsFolder
        let above = paintLayer(of: object)?.id
        let mesh = surface.mesh
        Task {
            let made = await Task.detached(priority: .userInitiated) { () -> (command: EditCommand, layer: String, files: PaintOperations.Files)? in
                let images = PaintFills.images(fill, paintMesh: mesh, size: paint.surface.size, inputs: inputs)
                return PaintOperations.addFill(fill, to: paint, above: above, object: object.id, images: images, encode: PaintPixels.png)
            }.value
            guard var made else {
                app.show("A thing holds up to \(ObjectPaint.maximumLayers) layers")
                return
            }
            do {
                try await Self.write(made.files, to: folder)
            } catch {
                app.show("Couldn't save the fill: \(error.localizedDescription)", kind: .error)
                return
            }
            guard baseScene.objects[object.id]?.paint == paint else { return }
            if masked, case let .setPaint(target, filled?) = made.command, let index = filled.layerIndex(made.layer) {
                // Painted on: the fill starts hidden behind an empty mask, and the brush paints the mask.
                var hidden = filled
                hidden.layers[index].maps[PaintMap.mask.rawValue] = [:]
                made.command = .setPaint(target, hidden)
            }
            if perform(made.command) {
                colourPaint.layers[object.id] = made.layer
                if masked {
                    colourPaint.map = .mask
                    chooseDrawBrush(.paint)
                }
            }
        }
    }

    /// A fill layer's fill changed (wear's amount, a different material): its tiles made again.
    func changeFill(_ layer: String, of id: ObjectID, to fill: PaintFill) {
        guard let object = baseScene.objects[id], let paint = object.paint, let surface = paintSurface(of: object) else { return }
        let inputs = fillInputs(fill, surface: surface.mesh, paint: paint)
        let folder = assetsFolder
        let mesh = surface.mesh
        Task {
            let made = await Task.detached(priority: .userInitiated) { () -> (command: EditCommand, files: PaintOperations.Files)? in
                let images = PaintFills.images(fill, paintMesh: mesh, size: paint.surface.size, inputs: inputs)
                return PaintOperations.changeFill(layer, to: fill, in: paint, object: id, images: images, encode: PaintPixels.png)
            }.value
            guard let made else { return }
            do {
                try await Self.write(made.files, to: folder)
            } catch {
                app.show("Couldn't save the fill: \(error.localizedDescription)", kind: .error)
                return
            }
            guard baseScene.objects[id]?.paint == paint else { return }
            perform(made.command)
        }
    }

    /// What a fill needs besides the surface: the shape's wear bake (made once per shape) and a material's pictures.
    private func fillInputs(_ fill: PaintFill, surface mesh: MeshData, paint: ObjectPaint) -> PaintFills.Inputs {
        var inputs = PaintFills.Inputs()
        switch fill {
        case .wear:
            let key = "\(paint.surface.unwrap) \(paint.surface.mesh)"
            if let known = texture.wearBakes[key] {
                inputs.wear = known
            } else {
                let bake = WearBake.make(mesh)
                if texture.wearBakes.count > 4 { texture.wearBakes.removeAll() }
                texture.wearBakes[key] = bake
                inputs.wear = bake
            }
        case let .material(material):
            let file = paintFiles
            let library = app.materials
            var images: [String: RGBAImage] = [:]
            for key in material.pictures?.files ?? [] {
                images[key] = (file(key) ?? library.pictureData(key)).flatMap(PaintPixels.decode)
            }
            if !images.isEmpty { inputs.pictures = MaterialPictureSource(images: images) }
        case .color:
            break
        }
        return inputs
    }

    /// Gives the chosen layer a mask (showing all of it), or takes it away.
    func setMask(_ on: Bool, layer: String, of id: ObjectID) {
        guard let paint = baseScene.objects[id]?.paint,
              let made = PaintOperations.setMask(on, layer: layer, in: paint, object: id, encode: PaintPixels.png) else { return }
        let folder = assetsFolder
        Task {
            do {
                try await Self.write(made.files, to: folder)
            } catch {
                app.show("Couldn't save the mask: \(error.localizedDescription)", kind: .error)
                return
            }
            if perform(made.command) {
                colourPaint.layers[id] = layer
                colourPaint.map = on ? .mask : .color
            }
        }
    }

    // MARK: Decals

    /// A picture pressed onto the thing at a stage point, `size` metres wide, as a new layer named Decal (one step).
    func placeDecal(_ picture: RGBAImage, at point: CGPoint, size: Double) {
        guard let found = surfaceHit(at: point) else {
            app.show("Tap the thing where the picture goes")
            return
        }
        let paint = found.paint
        let decal = PaintDecal(center: found.hit.position, normal: found.hit.normal, size: Float(size))
        let mesh = found.mesh
        let id = found.object.id
        let folder = assetsFolder
        Task {
            let made = await Task.detached(priority: .userInitiated) { () -> (command: EditCommand, layer: String, files: PaintOperations.Files)? in
                guard let (added, layerID) = PaintOperations.addLayer(to: paint, above: nil, object: id),
                      case let .setPaint(_, withLayer?) = added, let index = withLayer.layerIndex(layerID) else { return nil }
                var named = withLayer
                named.layers[index].name = "Decal"
                let image = decal.image(picture, on: mesh, textureSize: paint.surface.size)
                let tiles = PaintOperations.tileChanges(image, layer: named.layers[index], surface: paint.surface, encode: PaintPixels.png)
                for change in tiles.changes {
                    named.layers[index].tiles[change.tile] = change.file
                }
                return (.setPaint(id, named), layerID, tiles.files)
            }.value
            guard let made else {
                app.show("A thing holds up to \(ObjectPaint.maximumLayers) layers")
                return
            }
            do {
                try await Self.write(made.files, to: folder)
            } catch {
                app.show("Couldn't save the decal: \(error.localizedDescription)", kind: .error)
                return
            }
            guard baseScene.objects[id]?.paint == paint else { return }
            if perform(.batch("Decal", [made.command])) { colourPaint.layers[id] = made.layer }
        }
    }

    // MARK: Size, mirror, normals

    /// Every layer resampled to a new texture size (one step).
    func setTextureSize(_ size: Int) {
        guard let object = surfaceTarget(), let paint = object.paint, paint.surface.size != size else { return }
        let file = paintFiles
        let folder = assetsFolder
        Task {
            let made = await Task.detached(priority: .userInitiated) {
                PaintOperations.resized(paint, to: size, pictures: PaintPictures(paint, file: file), encode: PaintPixels.png)
            }.value
            guard let made else { return }
            do {
                try await Self.write(made.files, to: folder)
            } catch {
                app.show("Couldn't save the texture: \(error.localizedDescription)", kind: .error)
                return
            }
            guard baseScene.objects[object.id]?.paint == paint else { return }
            perform(.batch("Texture \(size) px", [.setPaint(object.id, made.paint)]))
        }
    }

    /// Strokes on the target mirrored across one of its axes (or not).
    func setPaintMirror(_ mirror: PaintMirror?) {
        guard let object = surfaceTarget(), var paint = object.paint, paint.mirror != mirror else { return }
        paint.mirror = mirror
        perform(.batch(mirror == nil ? "No mirror" : "Mirror paint", [.setPaint(object.id, paint)]))
    }

    /// Mirrored painting on or off (left and right when it comes on): the menu bar's Mirror Paint.
    func togglePaintMirror() {
        setPaintMirror(paintTarget?.paint?.mirror == nil ? .x : nil)
    }

    /// The faces brush in the hand, or back to the brush.
    func toggleFacesBrush() {
        colourPaint.mode = colourPaint.mode == .faces ? .paint : .faces
        tool = .paint
    }

    /// Normals baked onto the target from a more detailed thing in the scene (a sculpt and its light copy, D-352).
    func bakeNormals(from detailed: ObjectID) {
        guard let object = surfaceTarget(), let paint = object.paint, let surface = paintSurface(of: object),
              let high = displayed.scene.objects[detailed], let highMesh = paintSource(of: high) else { return }
        // The detailed surface brought into the light one's paint space.
        let toWorld = displayed.scene.worldTransform(of: detailed)
        var moved = highMesh
        moved.positions = highMesh.positions.map { paintSpace(toWorld.apply(to: Vec3(Double($0.x), Double($0.y), Double($0.z))), of: object) }
        let fromWorld = displayed.scene.worldTransform(of: object.id)
        moved.normals = highMesh.normals.map { normal in
            fromWorld.inverseApplyDirection(toWorld.applyDirection(Vec3(Double(normal.x), Double(normal.y), Double(normal.z)))).float3
        }
        let mesh = surface.mesh
        let folder = assetsFolder
        let name = high.name
        Task {
            let png = await Task.detached(priority: .userInitiated) {
                PaintPixels.png(NormalBake.bake(low: mesh, high: moved, size: paint.surface.size))
            }.value
            let file = PaintFiles.tileName(for: png)
            do {
                try await Self.write([file: png], to: folder)
            } catch {
                app.show("Couldn't save the normals: \(error.localizedDescription)", kind: .error)
                return
            }
            guard baseScene.objects[object.id]?.paint == paint else { return }
            var baked = paint
            baked.normalMap = file
            baked.normalsFrom = name
            perform(.batch("Normals from \(name)", [.setPaint(object.id, baked)]))
            app.show("Baked \(name)'s detail onto \(object.name)")
        }
    }

    func removeBakedNormals() {
        guard let object = paintTarget, var paint = object.paint, paint.normalMap != nil else { return }
        paint.normalMap = nil
        paint.normalsFrom = nil
        perform(.batch("No baked normals", [.setPaint(object.id, paint)]))
    }

    // MARK: Fur

    /// Fur on the target (length 0 takes it off); dragging a slider is one step (`gesture`).
    func setFur(_ change: (inout FurSettings) -> Void, gesture: String? = nil) {
        guard let object = paintTarget ?? selection.first.flatMap({ baseScene.objects[$0] }) else { return }
        var fur = FurSettings(object) ?? FurSettings(length: 0)
        change(&fur)
        let changes = [
            PropertyChange(object: object.id, key: .furLength, value: fur.length > 0 ? .float(fur.length) : nil),
            PropertyChange(object: object.id, key: .furDensity, value: .float(fur.density)),
            PropertyChange(object: object.id, key: .furStyle, value: fur.style == .shells ? nil : .enumeration(fur.style.rawValue)),
            PropertyChange(object: object.id, key: .furDroop, value: .float(fur.droop))
        ]
        perform(.setProperties(changes), coalesceKey: gesture)
    }
}
