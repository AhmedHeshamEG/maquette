@testable import LoweyCore
import XCTest

/// U5: titles are 3D text that sticks to the camera; a sticking thing rides the shot camera everywhere it renders.
final class StickToCameraTests: XCTestCase {
    func testAStickingThingRidesTheShotCamera() throws {
        var document = makeDocument()
        let camera = SceneObject(id: "cam", name: "Camera", kind: .camera, transform: Transform(position: Vec3(1, 2, 5)))
        var title = SceneObject(id: "title", name: "Title", kind: .primitive(.cube), transform: Transform(position: Vec3(0, 0, -2)))
        title[.sticksToCamera] = .bool(true)
        let loose = SceneObject(id: "loose", name: "Loose", kind: .primitive(.cube), transform: Transform(position: Vec3(0, 0, -2)))
        document.scene.objects[camera.id] = camera
        document.scene.objects[title.id] = title
        document.scene.objects[loose.id] = loose
        document.scene.activeCamera = camera.id
        let shown = Animator.evaluate(document, at: 0)
        XCTAssertEqual(shown.scene.worldTransform(of: "title").position, Vec3(1, 2, 3), "two metres in front of the camera")
        XCTAssertEqual(shown.scene.worldTransform(of: "loose").position, Vec3(0, 0, -2), "what doesn't stick stays in the world")
        XCTAssertTrue(shown.animated.contains("title"))
        document.scene.objects["cam"]?.transform.position = Vec3(-3, 0, 0)
        XCTAssertEqual(Animator.evaluate(document, at: 0).scene.worldTransform(of: "title").position, Vec3(-3, 0, -2), "it follows the camera")
        let local = StickToCamera.local(Transform(position: Vec3(1, 2, 3)), camera: Transform(position: Vec3(1, 2, 5)))
        XCTAssertEqual(local.position, Vec3(0, 0, -2), "sticking keeps it where it was")
    }
}
