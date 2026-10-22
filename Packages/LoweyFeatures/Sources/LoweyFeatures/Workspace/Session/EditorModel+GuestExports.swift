import Foundation
import LoweyCore
import LoweyEngine

/// G1's files for the guests: plans and elevations (PDF, DXF, SVG), IFC, a game level, a technical drawing, papercraft
/// and laser nets, a layered PSD and the frame's ink as SVG. Each is written from the scene as it shows at the playhead
/// (or only the selection, when asked).
extension EditorModel {
    /// Whether the scene holds a building (plans and IFC are offered only then).
    var hasBuilding: Bool {
        baseScene.objects.values.contains { [.wall, .slab, .roof, .stairs, .column].contains($0.buildingPart) }
    }

    func exportGuest(_ job: ExportJob, document: Document, progress: (Double) -> Void) async throws -> [URL] {
        let name = ProjectStore.sanitize(document.project.sceneNames[document.scene.id] ?? document.scene.name)
        let files: [(String, Data)] = switch job.preset.format {
        case .psd: try await [(name + " layers.psd", layeredPicture(job, document: document))]
        case .inkSVG: [(name + " ink.svg", Data(inkVectors(job).utf8))]
        case .ifc: [(name + ".ifc", buildingIFC(job, title: name))]
        case .level: [(name + " level.glb", gameLevel(job))]
        case .drawings: buildingDrawings(job, title: name)
        case .technical: [(name + " technical drawing.pdf", technicalDrawing(job, title: name))]
        case .papercraft: papercraft(job, title: name)
        default: []
        }
        guard !files.isEmpty, files.allSatisfy({ !$0.1.isEmpty }) else { throw ExportError.nothingToExport }
        let urls = try files.map { file in
            let url = rendersFolder.appendingPathComponent(file.0)
            try file.1.write(to: url, options: .atomic)
            return url
        }
        progress(1)
        return urls
    }

    /// The scene as it shows at the playhead, or only the selection.
    private func guestScene(_ job: ExportJob) -> CoreScene {
        let scene = displayed.scene
        return job.onlySelection && !selection.isEmpty ? ExportPrep.only(selection, in: scene) : scene
    }

    /// Placed models' parts as meshes in the world (the Kit and imports), for the Core writers.
    private func modelParts(_ object: SceneObject, _ world: LoweyCore.Transform) -> [ExportMesh] {
        ModelExport.localParts(object, look: look, catalog: library.catalog, models: library.models).map { part in
            ExportMesh(name: object.name, transform: world, mesh: part.mesh, color: part.material.color)
        }
    }

    private func layeredPicture(_ job: ExportJob, document: Document) async throws -> Data {
        let session = try makeExportSession(document)
        return try await session.layeredPSD(at: time, settings: job.settings)
    }

    private func inkVectors(_ job: ExportJob) -> String {
        let scene = guestScene(job)
        let meshes = ModelExport.meshes(nil, scene: scene, look: look, catalog: library.catalog, models: library.models)
        let size = job.settings.size
        let camera = RenderCamera.shot(displayed.camera, in: displayed.scene, fallback: stage?.viewpoint ?? .default,
                                       aspect: Double(size.width) / Double(max(size.height, 1)))
        let forward = camera.forward, up = camera.orientation.act(SIMD3<Float>(0, 1, 0))
        return InkVectors.svg(TriangleSoup(meshes), eye: Vec3(camera.position), forward: Vec3(forward), up: Vec3(up),
                              fieldOfView: Double(camera.fieldOfView), width: size.width, height: size.height)
    }

    private func buildingElements(_ job: ExportJob) -> [IFCWriter.Element] {
        IFCWriter.elements(in: guestScene(job), look: look) { [self] object, world in modelParts(object, world) }
    }

    /// The building as it shows now (the Plans sheet).
    func shownBuilding() -> (elements: [IFCWriter.Element], labels: [(text: String, at: Vec3)]) {
        (IFCWriter.elements(in: displayed.scene, look: look) { [self] object, world in modelParts(object, world) },
         BuildingDrawings.labels(in: displayed.scene))
    }

    private func buildingIFC(_ job: ExportJob, title: String) -> Data {
        let elements = buildingElements(job)
        let floors = BuildingDrawings.floors(elements, labels: BuildingDrawings.labels(in: guestScene(job)), units: units)
        return IFCWriter.file(elements: elements, spaces: BuildingDrawings.spaces(floors), levels: floors.map(\.height), project: title,
                              author: nil)
    }

    private func buildingDrawings(_ job: ExportJob, title: String) -> [(String, Data)] {
        let elements = buildingElements(job)
        let labels = BuildingDrawings.labels(in: guestScene(job))
        switch job.preset {
        case .planDXF, .planSVG:
            guard let ground = BuildingDrawings.floors(elements, labels: labels, units: units).first, let bounds = ground.art.bounds else { return [] }
            if job.preset == .planDXF { return [(title + " plan.dxf", DXF.data(ground.art))] }
            let size = Vec2(bounds.max.x - bounds.min.x, bounds.max.y - bounds.min.y)
            let scale = PaperPlacement.fitting(size, into: Vec2(400, 277))
            let svg = ground.art.svg(PaperPlacement(scale: scale, origin: bounds.min, at: Vec2(10, 10)), width: size.x * scale * 1000 + 20,
                                     height: size.y * scale * 1000 + 20)
            return [(title + " plan.svg", Data(svg.utf8))]
        default:
            return [(title + " plans.pdf", BuildingDrawings.pdf(elements, labels: labels, paper: .a3, title: title, author: nil, units: units))]
        }
    }

    private func gameLevel(_ job: ExportJob) -> Data {
        let scene = ExportPrep.withoutCamerasAndLights(guestScene(job))
        let meshes = ModelExport.meshes(nil, scene: scene, look: look, catalog: library.catalog, models: library.models, painted: { [self] in
            ModelExport.painted($0, look: look, catalog: library.catalog, models: library.models, file: paintFiles)
        })
        return GameLevel.glb(meshes, options: GameLevel.Options(engine: job.preset.levelEngine ?? .godot, atlas: job.atlas))
    }

    /// The selection (or every thing) as parts, drawn as it shows and put together.
    private func technicalDrawing(_ job: ExportJob, title: String) -> Data {
        let ids = selection.isEmpty ? baseScene.roots : selection
        let shown = displayed.scene
        func things(_ scene: CoreScene) -> [(object: SceneObject, meshes: [ExportMesh])] {
            ids.flatMap { scene.subtree(of: $0) }.compactMap { id in
                guard let object = scene.objects[id], object.kind.hasSurface, scene.isEffectivelyVisible(id) else { return nil }
                let world = scene.worldTransform(of: id)
                let own = SceneExport.localMesh(of: object, look: look).map {
                    [ExportMesh(name: object.name, transform: world, mesh: $0, color: SceneExport.material(of: object, look: look).color)]
                } ?? modelParts(object, world)
                return (object, own)
            }
        }
        let posed = things(shown)
        let together = things(baseScene)
        let sheet = TechnicalSheet.Sheet(title: title, units: units == .metre || units == .centimetre ? .millimetre : units,
                                         paper: job.preset == .technicalA3 ? .a3 : .a4)
        return TechnicalSheet.pdf(assembly: TriangleSoup(posed.flatMap(\.meshes)), whole: TriangleSoup(together.flatMap(\.meshes)),
                                  parts: TechnicalSheet.parts(together), sheet: sheet)
    }

    /// The selection (or the scene) unfolded as one piece of card, at real size when it fits the page.
    private func papercraft(_ job: ExportJob, title: String) -> [(String, Data)] {
        let ids = selection.isEmpty ? nil : selection
        let meshes = ModelExport.meshes(ids, scene: displayed.scene, look: look, catalog: library.catalog, models: library.models)
        var merged = MeshData()
        for mesh in meshes {
            var placed = mesh.mesh
            placed.positions = placed.positions.map { mesh.transform.apply(to: Vec3($0)).float3 }
            merged.append(placed)
        }
        guard !merged.isEmpty else { return [] }
        let solid = MeshBuilder.mesh(from: merged)
        let paper: PaperSize = job.preset == .papercraftLetter ? .letter : .a4
        let net = Papercraft.unfold(solid, paper: paper)
        if job.preset == .laserSVG {
            return net.pages.indices.map { ("\(title) laser \($0 + 1).svg", Data(net.svg(page: $0).utf8)) }
        }
        return [(title + " papercraft.pdf", net.pdf(title: title, author: nil))]
    }
}
