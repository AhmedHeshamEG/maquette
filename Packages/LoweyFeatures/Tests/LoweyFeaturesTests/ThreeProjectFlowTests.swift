import LoweyCore
@testable import LoweyFeatures
import XCTest

/// A three.js project brought in (X1 step 3): it plays in the web sandbox, and its scene, its motion and its shader
/// surfaces come in as editable things, keys and a card still playing the page.
@MainActor
final class ThreeProjectFlowTests: XCTestCase {
    private var app: AppModel?

    private func makeEditor() throws -> EditorModel {
        let app = AppModel()
        self.app = app
        app.createProject(named: "Three \(UUID().uuidString.prefix(6))", template: .blank, mood: StarterTemplate.blank.mood,
                          look: StarterTemplate.blank.lookPresetID)
        return try XCTUnwrap(app.editor)
    }

    /// A page as an agent writes it: three.js from a CDN (the sandbox gives it the carried copy), a turning box, a shader floor.
    private static let page = """
    <!doctype html><html><head><meta charset="utf-8"></head><body><script type="module">
    import * as THREE from 'https://unpkg.com/three@0.170.0/build/three.module.js';
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(45, innerWidth / innerHeight, 0.1, 50);
    camera.position.set(0, 3, 6); camera.lookAt(0, 0, 0);
    const renderer = new THREE.WebGLRenderer();
    renderer.setSize(innerWidth, innerHeight); document.body.appendChild(renderer.domElement);
    const box = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), new THREE.MeshStandardMaterial({ color: 0xff8800 }));
    box.name = 'Box'; scene.add(box);
    const floor = new THREE.Mesh(new THREE.PlaneGeometry(6, 4), new THREE.ShaderMaterial({
      uniforms: { time: { value: 0 } },
      vertexShader: 'void main() { gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
      fragmentShader: 'uniform float time; void main() { gl_FragColor = vec4(0.5 + 0.5 * sin(time), 0.3, 0.8, 1.0); }' }));
    floor.name = 'Floor'; floor.rotation.x = -Math.PI / 2; scene.add(floor);
    renderer.setAnimationLoop((t) => { box.rotation.y = t / 1000; floor.material.uniforms.time.value = t / 1000; renderer.render(scene, camera); });
    </script></body></html>
    """

    private static func folder(_ html: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("web-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(html.utf8).write(to: folder.appendingPathComponent("index.html"))
        return folder
    }

    func testAThreeProjectComesInEditableWithItsMotion() async throws {
        let editor = try makeEditor()
        let folder = try Self.folder(Self.page)
        XCTAssertTrue(EditorModel.isWebProject(folder))
        await editor.bringInThreeProject(at: folder)
        // A shader floor lays pictures on nothing, so it lands at once; wait a moment for a painted path anyway.
        for _ in 0 ..< 50 where !editor.scene.objects.values.contains(where: { $0.name == "Box" }) {
            try await Task.sleep(for: .milliseconds(100))
        }
        let scene = editor.scene
        let box = try XCTUnwrap(scene.objects.values.first { $0.name == "Box" }, "the box came in")
        if case .mesh = box.kind {} else { XCTFail("the box is editable") }
        XCTAssertTrue(editor.timeline.tracks.contains { $0.target == box.id && $0.property == .rotation }, "its turn came in as keys")
        XCTAssertTrue(scene.objects.values.contains { $0.kind == .camera }, "the page's camera came in")
        let card = try XCTUnwrap(scene.objects.values.first {
            if case .card = $0.kind {
                true
            } else {
                false
            }
        }, "the shader floor stands as a card")
        guard case let .card(recipe) = card.kind, let web = recipe.web, let file = web.file else { return XCTFail("the card plays a page") }
        XCTAssertEqual(web.entry, "maquette-solo-1.html")
        XCTAssertEqual(recipe.aspect, 1.5, accuracy: 1e-6)
        let solo = editor.assetsFolder.appendingPathComponent(file).appendingPathComponent("maquette-solo-1.html")
        let text = try String(contentsOf: solo, encoding: .utf8)
        XCTAssertTrue(text.contains("__maquetteThree"), "the card's page shows only the floor")
        XCTAssertTrue(editor.canUndo, "it came in as a step")
    }

    func testAPageWithoutThreeJSPlaysOverTheFrame() async throws {
        let editor = try makeEditor()
        let folder = try Self.folder("""
        <!doctype html><html><body><h1 style="animation: in 1s">Hello</h1>
        <style>@keyframes in { from { opacity: 0 } }</style></body></html>
        """)
        await editor.bringInThreeProject(at: folder)
        let overlay = try XCTUnwrap(editor.scene.objects.values.first(where: \.kind.isOverlay))
        guard case let .overlay(recipe) = overlay.kind else { return XCTFail("an overlay") }
        XCTAssertEqual(recipe.web?.entry, "index.html")
    }
}
