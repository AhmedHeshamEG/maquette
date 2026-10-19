import Foundation
import HmmDesign
import HmmVector
import LoweyCore
import LoweyEngine
import UniformTypeIdentifiers

/// Motion design (D1): an SVG logo stood up, fonts brought in for 3D text, letters that animate, clones and their
/// effects, morphs. Each change is one undo step; the bridge's `design` verb makes the same commands.
extension EditorModel {
    // MARK: Logos

    /// Model ▸ Add ▸ Logo: the SVG's fill colours as solids, a metre wide, standing where you look.
    func importLogo(_ source: URL) {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let drawing: VectorDrawing
        do {
            drawing = try SVG.read(Data(contentsOf: source))
        } catch let failure as SVG.Failure {
            return app.show(String.LocalizationValue(failure.description), kind: .error)
        } catch {
            return app.show("Couldn't read \(source.lastPathComponent): \(error.localizedDescription)", kind: .error)
        }
        let name = ObjectFactory.uniqueName((source.lastPathComponent as NSString).deletingPathExtension, in: scene)
        guard var made = LogoImport.objects(drawing, name: name, width: 1, depth: 0.08, makeID: { .make() }),
              let index = made.objects.firstIndex(where: { $0.id == made.root }) else {
            return app.show("The drawing has no filled shapes", kind: .error)
        }
        made.objects[index] = operations.nudgedToFreeSpot(operations.placeOnGround(made.objects[index], at: dropPoint()), in: scene)
        guard perform(.insert(SceneFragment(objects: made.objects, roots: [made.root]), parent: nil, index: nil)) else { return }
        select(made.root)
        HmmHaptics.play(.commit)
        app.show(String.LocalizationValue(Self.logoLine(drawing)))
    }

    static func logoLine(_ drawing: VectorDrawing) -> String {
        let skipped = drawing.skipped
        var left: [String] = []
        if skipped.strokes > 0 { left.append(String(localized: "\(skipped.strokes) outlines drawn with a pen")) }
        if skipped.texts > 0 { left.append(String(localized: "\(skipped.texts) words not made into shapes")) }
        if skipped.images > 0 { left.append(String(localized: "\(skipped.images) pictures")) }
        guard !left.isEmpty else { return String(localized: "\(drawing.colors.count) colours, each a solid. Push a face to make it deeper") }
        return String(localized: "Left out: \(left.joined(separator: ", ")). Make them shapes in your drawing app to bring them too")
    }

    // MARK: Fonts

    var fontsFolder: URL { assetsFolder.appendingPathComponent("fonts", isDirectory: true) }

    /// The fonts brought into this project, by file (`fonts/…`) and name.
    var projectFonts: [(file: String, name: String)] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: fontsFolder.path)) ?? []
        return files.sorted().compactMap { file in
            guard let data = try? Data(contentsOf: fontsFolder.appendingPathComponent(file)), let name = FontFileInfo.name(of: data) else { return nil }
            return ("fonts/" + file, name)
        }
    }

    /// Brings a font file into the project and gives it to the text.
    func importFont(_ source: URL, for text: ObjectID) {
        if let file = bringFont(source) { setFont(file, for: text) }
    }

    /// Copies a font file into the project's fonts (the bridge's `add_media` with `as=font` too); its name under the
    /// assets, or nil when it isn't a font.
    func bringFont(_ source: URL) -> String? {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: source), FontFileInfo.name(of: data) != nil else {
            app.show("That file isn't a font. Fonts are OTF, TTF or TTC files", kind: .error)
            return nil
        }
        do {
            try FileManager.default.createDirectory(at: fontsFolder, withIntermediateDirectories: true)
            let file = source.lastPathComponent
            let destination = fontsFolder.appendingPathComponent(file)
            if !FileManager.default.fileExists(atPath: destination.path) { try data.write(to: destination, options: .atomic) }
            return "fonts/" + file
        } catch {
            app.show("Couldn't bring the font in: \(error.localizedDescription)", kind: .error)
            return nil
        }
    }

    /// The text's font (nil: its style's).
    func setFont(_ file: String?, for text: ObjectID) {
        updateText(text) { $0.font = file }
    }

    // MARK: Letters

    /// Letters that animate from the playhead (nil stops them).
    func setLetters(_ preset: TextAnimator.Preset?, for text: ObjectID) {
        changeDesign(of: text, label: "Letters") { design in
            design.letters = preset.map { TextAnimator.starting($0, at: time) }
        }
    }

    func updateLetters(of text: ObjectID, coalesce: String? = nil, _ change: (inout TextAnimator) -> Void) {
        changeDesign(of: text, label: "Letters", coalesce: coalesce) { design in
            guard var letters = design.letters else { return }
            change(&letters)
            design.letters = letters
        }
    }

    // MARK: Clones

    /// Hold menu ▸ More ▸ Clone…: a 5 × 5 grid of live copies, its panel open.
    func cloneSelection() {
        guard let id = singleSelection?.id else { return }
        let size = baseScene.objects[id].map { object in operations.worldBounds(of: object.id, in: baseScene).map { max($0.size.x, $0.size.z) } ?? 1 } ?? 1
        changeDesign(of: id, label: "Clone") { $0.clones = $0.clones ?? ObjectClones.starting(size: size) }
        foldInspector(false)
        app.show("Twenty-five copies that move together. Change the layout and add effects in its panel")
    }

    func updateClones(of id: ObjectID, coalesce: String? = nil, _ change: (inout ObjectClones) -> Void) {
        changeDesign(of: id, label: "Clones", coalesce: coalesce) { design in
            guard var clones = design.clones else { return }
            change(&clones)
            design.clones = clones
        }
    }

    func removeClones(of id: ObjectID) {
        changeDesign(of: id, label: "No clones") { $0.clones = nil }
    }

    func addCloneEffect(_ kind: CloneEffect.Kind, to id: ObjectID) {
        let size = operations.worldBounds(of: id, in: baseScene).map { max($0.size.x, $0.size.z) } ?? 1
        updateClones(of: id) { $0.effects.append(CloneEffect.starting(kind, id: ObjectID.make().raw, size: size)) }
    }

    // MARK: Morph

    /// Hold menu ▸ More ▸ Morph into…: the next tap names the shape to become.
    func beginMorph() {
        guard let id = singleSelection?.id else { return }
        guard let object = baseScene.objects[id], SceneExport.localMesh(of: object, look: look) != nil else {
            return app.show("Morphing works between shapes made here. Make a placed model editable first", kind: .error)
        }
        design.wait = .morph(id)
        app.show(String.LocalizationValue(DesignWait.morph(id).hint))
    }

    /// A tap while motion design waits for a thing. True when it took the tap.
    func designTap(picked: ObjectID?) -> Bool {
        guard let wait = design.wait else { return false }
        design.wait = nil
        guard let picked else {
            app.show("Nothing picked")
            return true
        }
        switch wait {
        case let .morph(source): morph(source, into: picked)
        case let .link(target, preset): link(target, to: picked, preset)
        }
        return true
    }

    private func morph(_ source: ObjectID, into target: ObjectID) {
        guard source != target, let object = baseScene.objects[target], SceneExport.localMesh(of: object, look: look) != nil else {
            return app.show("It can become a shape made here, other than itself", kind: .error)
        }
        var ids = IDFactory.random
        var design = baseScene.objects[source]?.motionDesign ?? MotionDesign()
        design.morph = ObjectMorph(target: target)
        perform(MorphOperations.command(source, into: target, design: design, from: time, duration: 1, in: document, ids: &ids))
        HmmHaptics.play(.commit)
        app.show("It becomes \(object.name) over a second from \(TimeFormat.clock(time)). Drag its keys to change when")
    }

    func removeMorph(of id: ObjectID) {
        perform(MorphOperations.removing(id, in: document))
    }

    // MARK: Shared

    /// One undo step on a thing's motion design (removed when it ends up empty).
    func changeDesign(of id: ObjectID, label: String, coalesce: String? = nil, _ change: (inout MotionDesign) -> Void) {
        guard let object = baseScene.objects[id] else { return }
        var design = object.motionDesign ?? MotionDesign()
        change(&design)
        guard design.orNil != object.motionDesign else { return }
        perform(.batch(label, [.setMotionDesign(id, design.orNil)]), coalesceKey: coalesce)
    }
}
