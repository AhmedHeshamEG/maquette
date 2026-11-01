import CoreGraphics
import LoweyCore
@testable import LoweyEngine
import XCTest

/// The Real Look on the simulator's GPU (U9, the S16 report): a low-key desk lit by a lamp, with spot shadows, metal,
/// a clear coat, glass and a glowing panel. Each feature has to change the picture the way it says; the frames are
/// attached for the eye and the desk is a golden.
@MainActor
final class RealLookRenderTests: XCTestCase {
    /// The dark studio in the Real Look, no sun, a floor, and the camera looking down -z at the desk.
    private func desk(_ extra: [SceneObject], shadows: Bool = true, look edit: (inout Look) -> Void = { _ in }) -> Document {
        var floor = SceneObject(id: "floor", name: "Floor", kind: .primitive(.cube), transform: Transform(position: Vec3(0, -0.1, 0),
                                                                                                          scale: Vec3(4, 0.1, 4)))
        floor[.color] = .color(.rgba(RGBA(0.55, 0.42, 0.3)))
        floor[.roughness] = .float(0.6)
        var factory = ObjectFactory(ids: .sequential("real"))
        // The lamp: up and to the left, tipped 45° down toward the right of the desk.
        var lamp = factory.light(.spot, at: Vec3(-1.2, 1.6, 0), color: RGBA(1, 0.78, 0.55))
        lamp.transform.rotation = (Quat(angle: -.pi / 2, axis: .unitY) * Quat(angle: -.pi / 4, axis: .unitX)).normalized
        lamp[.lightIntensity] = .float(3)
        lamp[.lightRange] = .float(6)
        lamp[.spotAngle] = .float(60)
        lamp[.spotSoftness] = .float(0.5)
        lamp[.lightShadows] = .bool(shadows)
        var look = Look.default.applying(.darkStudio)
        look.presetID = LookPreset.real.id
        look.ground.visible = false
        edit(&look)
        return TestDocuments.document("Real", objects: [floor, lamp] + extra, camera: Vec3(0, 1.1, 2.6),
                                      rotation: Quat(angle: -0.3, axis: .unitX), look: look)
    }

    private func block(_ id: String, at position: Vec3, size: Double = 0.4, color: RGBA = RGBA(0.8, 0.8, 0.8)) -> SceneObject {
        var object = SceneObject(id: ObjectID(raw: id), name: id, kind: .primitive(.cube), transform: Transform(position: position,
                                                                                                                scale: Vec3(size, size, size)))
        object[.color] = .color(.rgba(color))
        return object
    }

    private func ball(_ id: String, at position: Vec3, size: Double = 0.45, color: RGBA = RGBA(0.8, 0.8, 0.8)) -> SceneObject {
        var object = SceneObject(id: ObjectID(raw: id), name: id, kind: .primitive(.sphere), transform: Transform(position: position,
                                                                                                                  scale: Vec3(size, size, size)))
        object[.color] = .color(.rgba(color))
        return object
    }

    private func image(_ document: Document, longSide: Int = 480) async throws -> CGImage {
        try await TestDocuments.session(document).image(at: 0, framing: .landscape, longSide: longSide)
    }

    func testASpotLampCastsAShadow() async throws {
        let things = [block("box", at: Vec3(-0.1, 0, 0))]
        let shadowed = try await image(desk(things))
        let unshadowed = try await image(desk(things, shadows: false))
        GoldenImage().attach(shadowed, name: "real-spot-shadow")
        XCTAssertGreaterThan(ImageChecks.difference(shadowed, unshadowed), 0.0008, "the box's shadow lies on the desk")
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        XCTAssertLessThan(ImageChecks.brightness(shadowed, in: whole), ImageChecks.brightness(unshadowed, in: whole))
    }

    func testRealIsLowKeyAndKeepsTheLampsHighlights() async throws {
        var panel = SceneObject(id: "panel", name: "Panel", kind: .primitive(.cube), transform: Transform(position: Vec3(0.8, 0.3, -0.4),
                                                                                                          scale: Vec3(0.5, 0.5, 0.05)))
        panel[.color] = .color(.rgba(RGBA(1, 0.95, 0.85)))
        panel[.emissiveIntensity] = .float(6)
        let frame = try await image(desk([panel, block("box", at: Vec3(-0.3, 0, 0))]))
        GoldenImage().attach(frame, name: "real-low-key")
        XCTAssertLessThan(ImageChecks.brightness(frame, in: CGRect(x: 0, y: 0, width: 1, height: 1)), 0.35, "most of the frame stays dark")
        // The glow is the brightest thing: past white, rolled off by the filmic curve to near white, not clipped flat.
        let bytes = GoldenImage.rgba(frame)
        var brightest = 0.0
        for index in stride(from: 0, to: bytes.count, by: 4) {
            brightest = max(brightest, (Double(bytes[index]) + Double(bytes[index + 1]) + Double(bytes[index + 2])) / 765)
        }
        XCTAssertGreaterThan(brightest, 0.8, "the glowing panel reads near white")
    }

    func testMetalAndAClearCoatShine() async throws {
        var metal = ball("metal", at: Vec3(0.2, 0, 0))
        metal[.metallic] = .float(1)
        metal[.roughness] = .float(0.15)
        var matte = ball("metal", at: Vec3(0.2, 0, 0))
        matte[.roughness] = .float(0.95)
        let shiny = try await image(desk([metal]))
        let flat = try await image(desk([matte]))
        GoldenImage().attach(shiny, name: "real-metal")
        XCTAssertGreaterThan(ImageChecks.difference(shiny, flat), 0.002, "metal and a matte ball read differently")
        var coated = matte
        coated[.clearcoat] = .float(1)
        coated[.clearcoatRoughness] = .float(0.05)
        let lacquered = try await image(desk([coated]))
        XCTAssertGreaterThan(ImageChecks.difference(lacquered, flat), 0.0001, "a clear coat adds its own highlight")
    }

    func testGlassLetsWhatsBehindThrough() async throws {
        let behind = block("red", at: Vec3(0.1, 0, -0.8), size: 0.6, color: RGBA(0.9, 0.1, 0.05))
        var glass = ball("glass", at: Vec3(0.1, 0, 0.2), size: 0.5, color: RGBA(0.95, 0.95, 0.95))
        var solid = glass
        glass[.transmission] = .float(0.95)
        glass[.ior] = .float(1.5)
        solid[.roughness] = .float(0.5)
        let clear = try await image(desk([behind, glass]))
        let opaque = try await image(desk([behind, solid]))
        GoldenImage().attach(clear, name: "real-glass")
        XCTAssertGreaterThan(ImageChecks.difference(clear, opaque), 0.002, "the red block shows through the glass")
    }

    func testTheDesk() async throws {
        var metal = ball("metal", at: Vec3(0.55, 0, 0.1), size: 0.35)
        metal[.metallic] = .float(1)
        metal[.roughness] = .float(0.2)
        metal[.color] = .color(.rgba(RGBA(0.95, 0.75, 0.4)))
        var lacquer = block("lacquer", at: Vec3(-0.45, 0, -0.1), size: 0.35, color: RGBA(0.6, 0.05, 0.04))
        lacquer[.clearcoat] = .float(1)
        lacquer[.clearcoatRoughness] = .float(0.08)
        var glass = ball("glass", at: Vec3(0.05, 0, 0.45), size: 0.3, color: RGBA(0.9, 0.95, 1))
        glass[.transmission] = .float(0.9)
        let document = desk([metal, lacquer, glass]) { $0.post.halation = 0.3; $0.post.grain = 0 }
        let frame = try await image(document, longSide: 640)
        try GoldenImage().assertMatches(frame, named: "real-desk")
    }
}
