import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine
import UniformTypeIdentifiers

/// F1, film: light setups, the lens on a camera body, focus that follows, rigs, the HDRI and the air, the rotoscope.
extension EditorModel {
    // MARK: Light

    /// A setup placed around the subject as the shot camera sees it (the selection that isn't a light, else what the view
    /// looks at); the last setup's lamps are replaced.
    func applyLightSetup(_ recipe: LightRecipe) {
        let subjects = selection.filter { id in
            guard let kind = baseScene.objects[id]?.kind else { return false }
            if case .light = kind { return false }
            return kind != .camera
        }
        let box = subjects.isEmpty ? nil : operations.bounds.worldBounds(of: subjects, in: scene)
        let subject = box?.center ?? stage?.viewpoint.target ?? .zero
        let eye = shotCamera.map { displayed.scene.worldTransform(of: $0).position } ?? stage?.viewpoint.eye ?? Vec3(0, 1.6, 6)
        let size = box.map { max($0.size.x, $0.size.y, $0.size.z) } ?? 1.7
        var ids = IDFactory.random
        perform(LightSetups.apply(recipe, look: look, scope: lookIsSceneOnly ? .scene : .project, eye: eye, subject: subject, size: size,
                                  in: baseScene, ids: &ids))
        HmmHaptics.play(.commit)
    }

    // MARK: The lens

    func sensor(of camera: ObjectID) -> CameraSensor {
        baseScene.objects[camera].map(CameraSensor.of) ?? .fullFrame
    }

    /// The camera body: the picture stays, the millimetres read in the body's own.
    func setSensor(_ sensor: CameraSensor) {
        guard let camera = editedCamera else { return }
        perform(.setProperties([PropertyChange(object: camera, key: .sensor, value: sensor == .fullFrame ? nil : .enumeration(sensor.rawValue))]))
    }

    /// Millimetres on the camera's body.
    func setBodyFocalLength(_ millimetres: Double, gesture: String? = nil) {
        guard let camera = editedCamera else { return }
        setCameraProperty(.fieldOfView, CameraLens.fieldOfView(focalLength: millimetres, on: sensor(of: camera)), gesture: gesture)
    }

    /// The lens keeps the selection sharp wherever it goes. `pull`: from the playhead, pulling from what it held.
    func focusOnSelection(pull: Bool) {
        guard let camera = editedCamera, let subject = selection.first(where: { $0 != camera }) else { return }
        var ids = IDFactory.random
        guard let command = FocusOperations.focus(camera, on: subject, at: pull ? time : 0, in: baseScene, ids: &ids) else { return }
        perform(command)
        if (displayed.scene.objects[camera]?[.aperture]?.floatValue ?? 0) < 0.9 {
            app.show("Everything is sharp until the aperture is set: try f/2.8")
        }
        HmmHaptics.play(.commit)
    }

    func focusTarget(of camera: ObjectID) -> String? {
        displayed.scene.objects[camera]?[.focusOn]?.stringValue.flatMap { $0.isEmpty ? nil : baseScene.objects[ObjectID(raw: $0)]?.name }
    }

    func stopFocusFollowing() {
        guard let camera = editedCamera else { return }
        var ids = IDFactory.random
        if let command = FocusOperations.focus(camera, on: nil, at: time, in: baseScene, ids: &ids) { perform(command) }
    }

    // MARK: Rigs

    func setRig(_ rig: CameraRig) {
        guard let camera = editedCamera else { return }
        var changes = [PropertyChange(object: camera, key: .rig, value: rig == .none ? nil : .enumeration(rig.rawValue))]
        if rig == .handheld, baseScene.objects[camera]?[.rigShake] == nil {
            changes.append(PropertyChange(object: camera, key: .rigShake, value: .float(0.5)))
        }
        perform(.batch(rig.title, [.setProperties(changes)]))
        HmmHaptics.play(.selection)
    }

    /// A rig's number keyed at the playhead as it is (after that, moving it keys itself).
    func keyRig(_ key: PropertyKey) {
        guard let camera = editedCamera else { return }
        var ids = IDFactory.random
        guard let command = PropertyAnimation.key(key, of: camera, at: time, shown: displayed.scene, timeline: timeline, ids: &ids) else { return }
        perform(command)
        HmmHaptics.play(.commit)
    }

    func isKeyed(_ key: PropertyKey, on camera: ObjectID) -> Bool { timeline.track(for: camera, key) != nil }

    // MARK: The HDRI and the air

    /// An HDRI (.hdr) into the project: it shows behind everything and lights the world (its sun, its sky).
    func importEnvironment(_ source: URL) async {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: source)
            let map = try await Task.detached(priority: .userInitiated) { try RadianceHDR.read(data, maxWidth: 512) }.value
            let key = "environment/" + uniqueMediaName(source.lastPathComponent)
            let destination = assetsFolder.appendingPathComponent(key)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            let light = EnvironmentLight.analyse(map)
            perform(.batch("HDRI", [.setLook(light.applied(to: look, environment: key, turn: 0), scope: lookIsSceneOnly ? .scene : .project)]))
            HmmHaptics.play(.commit)
        } catch {
            app.show("That HDRI can't be read (\(String(describing: error))). Maquette reads Radiance .hdr files.", kind: .error)
        }
    }

    /// Turns the HDRI and its sun together (degrees, left positive).
    func turnEnvironment(_ degrees: Double, gesture: String? = nil) {
        updateLook(coalesce: gesture) { look in
            look.lighting.sunAzimuth += degrees - (look.sky.environmentTurn ?? 0)
            look.sky.environmentTurn = degrees
        }
    }

    func setEnvironmentExposure(_ stops: Double, gesture: String? = nil) {
        updateLook(coalesce: gesture) { $0.sky.environmentExposure = stops }
    }

    /// Back to the mood's own sky.
    func removeEnvironment() {
        updateLook { look in
            look = look.applying(look.lightingPreset ?? .day)
            look.sky.environment = nil
        }
    }

    var atmosphere: Atmosphere { look.atmosphere ?? Atmosphere() }

    func setAir(haze: Double? = nil, godRays: Double? = nil, gesture: String? = nil) {
        updateLook(coalesce: gesture) { look in
            var air = look.atmosphere ?? Atmosphere()
            if let haze { air.haze = haze }
            if let godRays { air.godRays = godRays }
            look.atmosphere = air.isClear ? nil : air
        }
    }

    // MARK: The rotoscope

    /// A video behind the stage (copied into the project), starting at the playhead.
    func importRotoscope(_ source: URL) {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.createDirectory(at: assetsFolder, withIntermediateDirectories: true)
            let file = uniqueMediaName(source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: assetsFolder.appendingPathComponent(file))
            setRotoscope(Rotoscope(video: file, start: time))
            app.show("The video is behind the stage from \(TimeFormat.clock(time)); exports never show it")
        } catch {
            app.show("Couldn't add \(source.lastPathComponent): \(error.localizedDescription)", kind: .error)
        }
    }

    func setRotoscope(_ rotoscope: Rotoscope?) {
        self.rotoscope = rotoscope
        workspace.rotoscope = rotoscope
        workspaceChanged()
        stage?.redraw()
    }

    func updateRotoscope(_ change: (inout Rotoscope) -> Void) {
        guard var current = rotoscope else { return }
        change(&current)
        setRotoscope(current)
    }

    /// The video's frame under the playhead for the stage (nil when there's none, it's hidden or the playhead is outside it).
    func rotoscopeFrame() -> RotoscopeFrame? {
        guard let rotoscope, rotoscope.shown, let url = mediaURL(rotoscope.video),
              let frameTime = rotoscope.frameTime(at: time, fps: Double(timeline.fps)),
              let image = videoPreview.frameNow(VideoFrameKey.make(file: rotoscope.video, time: frameTime), url: url) else { return nil }
        return RotoscopeFrame(image: image, opacity: rotoscope.opacity, inFront: rotoscope.inFront)
    }
}

extension UTType {
    /// Radiance HDR pictures (HDRIs).
    static let radianceHDR = UTType(filenameExtension: "hdr") ?? .image
}
