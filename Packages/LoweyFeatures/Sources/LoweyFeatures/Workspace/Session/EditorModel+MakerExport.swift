import Foundation
import LoweyCore
import LoweyEngine

/// A made character for games (K1 step 6): engine-ready (Godot, Unity, Unreal), a sprite sheet from 4 or 8 directions with
/// its JSON and Godot SpriteFrames (pixel art if asked), and a turnaround sheet. Files land in the project's renders.
extension EditorModel {
    /// The character to export: the selected one, else the only one in the scene.
    var gameCharacter: ObjectID? {
        if let root = makerCharacter ?? singleSelection.flatMap({ $0.rig != nil ? $0.id : nil }) { return root }
        let made = baseScene.objects.values.filter { $0[.characterStart] != nil }
        return made.count == 1 ? made.first?.id : nil
    }

    private func save(_ data: Data, as name: String) -> URL? {
        do {
            try FileManager.default.createDirectory(at: rendersFolder, withIntermediateDirectories: true)
            let url = rendersFolder.appendingPathComponent(ProjectStore.sanitize(name))
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            app.show("Couldn't save the file: \(error.localizedDescription)", kind: .error)
            return nil
        }
    }

    /// The character as a GLB for an engine: its skeleton named for that engine, blend shapes, named clips, LODs, a capsule.
    func exportForGame(_ engine: GameEngine) -> URL? {
        guard let root = gameCharacter, let object = baseScene.objects[root] else {
            app.show("Pick a character first")
            return nil
        }
        let parts: (SceneObject) -> [GLTFScene.LocalPart] = { [library, look] in
            ModelExport.localParts($0, look: look, catalog: library.catalog, models: library.models)
        }
        guard let data = GameCharacterExport.glb(root, document: document, options: .init(engine: engine), parts: parts) else {
            app.show("\(object.name) needs a rig first: Rig ▸ pins and dots, or make it in Characters ▸ New")
            return nil
        }
        return save(data, as: "\(object.name) for \(engine.title).glb")
    }

    /// The motion a sprite sheet setting names.
    private func spriteMotion(_ name: String) -> CharacterPictures.Motion {
        switch name {
        case "Timeline": .timeline
        case "Still": .still
        default: .clip(name)
        }
    }

    /// A sprite sheet as a zip: the sheet (PNG), where each frame is (JSON) and a Godot SpriteFrames (.tres).
    func exportSprites() async -> URL? {
        guard let root = gameCharacter, let object = baseScene.objects[root] else {
            app.show("Pick a character first")
            return nil
        }
        let settings = maker.sprites
        let person = object.rig?.standard == .humanoid
        let motions = settings.motions.isEmpty ? ["Still"] : settings.motions.filter { person || !BuiltinClips.names.contains($0) }
        defer { maker.working = nil }
        do {
            let pictures = try CharacterPictures(models: library.models, catalog: library.catalog, paintFile: paintFiles)
            var strips: [SpriteSheet.Strip] = []
            for motion in motions.isEmpty ? ["Still"] : motions {
                for direction in settings.directions {
                    maker.working = "Drawing \(motion.lowercased()), \(direction.rawValue)…"
                    var frames = try await pictures.frames(of: root, in: document, motion: spriteMotion(motion), direction: direction,
                                                           size: settings.size, fps: settings.fps)
                    if settings.pixelArt {
                        // Its colours found in its own frames (16 at most), crisp, with a one-pixel line around it.
                        let pixel = PixelArt.Settings(height: settings.pixelHeight)
                        frames = frames.map { PixelArt.render($0, settings: pixel) }
                    }
                    strips.append(SpriteSheet.Strip(clip: motion, direction: direction, frames: frames, fps: settings.fps))
                }
            }
            let base = ProjectStore.sanitize(object.name)
            guard let packed = SpriteSheet.pack(strips, imageName: "\(base).png") else { return nil }
            let zip = ZipWriter.storedArchive([("\(base).png", PNGCodec.encode(packed.image)), ("\(base).json", packed.json),
                                               ("\(base).tres", Data(packed.spriteFrames.utf8))])
            return save(zip, as: "\(object.name) sprites.zip")
        } catch {
            app.show("The sprite sheet couldn't be drawn: \(error.localizedDescription)", kind: .error)
            return nil
        }
    }

    /// Front, three-quarter, side and back on one picture.
    func exportTurnaround() async -> URL? {
        guard let root = gameCharacter, let object = baseScene.objects[root] else { return nil }
        defer { maker.working = nil }
        maker.working = "Drawing the turnaround…"
        do {
            let pictures = try CharacterPictures(models: library.models, catalog: library.catalog, paintFile: paintFiles)
            let views = try await pictures.turnaround(of: root, in: document, size: 512)
            guard let sheet = SpriteSheet.turnaround(views) else { return nil }
            return save(PNGCodec.encode(sheet), as: "\(object.name) turnaround.png")
        } catch {
            app.show("The turnaround couldn't be drawn: \(error.localizedDescription)", kind: .error)
            return nil
        }
    }
}
