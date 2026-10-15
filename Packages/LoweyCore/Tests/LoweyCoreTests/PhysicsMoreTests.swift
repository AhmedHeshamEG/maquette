import Foundation
@testable import LoweyCore
import XCTest

/// P1, continued: ragdolls and Keep it, breaking, cloth and jelly, fluids, Settle, does it stand, the real sun.
final class PhysicsMoreTests: XCTestCase {
    private typealias Base = PhysicsTests

    static func stairs() -> SceneObject {
        let mesh = Architecture.stairs(Architecture.Stairs(rise: 1.4, width: 1.2), from: Vec3(0, 0, 1), direction: Vec3(0, 0, -1))
        var object = SceneObject(id: "stairs", name: "Stairs", kind: .mesh(mesh))
        object.physics = ObjectPhysics(material: .concrete, motion: .stays)
        return object
    }

    static func person(at position: Vec3) throws -> SceneObject {
        let local = Bounds(min: Vec3(-0.5, 0, -0.5), max: Vec3(0.5, 1, 0.5))
        let rig = try XCTUnwrap(HumanRig.rig(from: HumanRig.template(bounds: local), bounds: local))
        var object = SceneObject(id: "person", name: "Person", kind: .primitive(.cube),
                                 transform: Transform(position: position, scale: Vec3(0.45, 1.7, 0.25)))
        object.rig = rig
        object.physics = ObjectPhysics(material: .wood, startSpeed: Vec3(0, 0, 2.5))
        return object
    }

    /// A ragdoll falls down stairs, and Keep it makes the fall keys that play the same without the run.
    func testARagdollFallsDownStairsAndKeepItMakesKeys() throws {
        let top = Vec3(0, 1.4, 1 - 0.28 * 7.5)
        let document = try Base.document([Self.stairs(), Self.person(at: top)], duration: 3)
        let frames = try Base.run(document)
        XCTAssertEqual(frames.ragdolls.first?.object, "person")
        let start = try XCTUnwrap(Animator.evaluate(document, at: 0, physics: frames).scene.objects["person"]).transform.position
        let end = try XCTUnwrap(Animator.evaluate(document, at: 3, physics: frames).scene.objects["person"]).transform.position
        XCTAssertLessThan(end.y, start.y - 0.6, "it went down")
        XCTAssertGreaterThan(end.z, start.z + 0.5, "down the stairs, not through them")
        let bent = Animator.evaluate(document, at: 2, physics: frames).scene.objects["person"]
        XCTAssertTrue(bent?.properties.keys.contains { $0.boneJoint != nil } ?? false, "its joints turn")
        var ids = IDFactory.sequential("keep")
        let keep = try XCTUnwrap(PhysicsKeep.keep(frames, in: document, ids: &ids))
        let kept = try assertReverts(keep, on: document)
        XCTAssertEqual(kept.scene.objects["person"]?.physics?.motion, .follows)
        XCTAssertTrue(kept.scene.timeline.tracks.contains { $0.target == "person" && $0.property.boneJoint != nil })
        for time in [0.5, 1.5, 2.5] {
            let played = try XCTUnwrap(Animator.evaluate(document, at: time, physics: frames).scene.objects["person"]).transform.position
            let keyed = try XCTUnwrap(Animator.evaluate(kept, at: time).scene.objects["person"]).transform.position
            XCTAssertLessThan(played.distance(to: keyed), 0.02, "keys play the run at \(time)")
        }
    }

    func testGlassBreaksIntoPiecesThatFitAndKeepItAddsThem() throws {
        let document = Base.document([Base.cube("pane", at: Vec3(0, 1.5, 0), size: 0.4, material: .glass)], duration: 1.5)
        let frames = try Base.run(document)
        let breakable = try XCTUnwrap(frames.breakables.first)
        XCTAssertNotNil(breakable.brokeAt, "it broke when it hit the ground")
        let volume = breakable.pieces.reduce(0) { $0 + SoftMesh.volume($1.renderMesh()) }
        XCTAssertEqual(volume, 0.064, accuracy: 0.004, "the pieces fill the cube")
        let shown = Animator.evaluate(document, at: 1.4, physics: frames)
        XCTAssertEqual(shown.scene.objects["pane"]?.isVisible, false)
        XCTAssertNotNil(shown.scene.objects[PhysicsPlayback.pieceID("pane", 0)])
        var ids = IDFactory.sequential("glass")
        let kept = try assertReverts(XCTUnwrap(PhysicsKeep.keep(frames, in: document, ids: &ids)), on: document)
        XCTAssertNotNil(kept.scene.objects[PhysicsPlayback.pieceID("pane", 0)])
        XCTAssertEqual(Animator.evaluate(kept, at: 1.4).scene.objects["pane"]?.isVisible, false)
        XCTAssertEqual(Animator.evaluate(kept, at: 0.1).scene.objects[PhysicsPlayback.pieceID("pane", 0)]?.isVisible, false)
    }

    func testClothDrapesOverABallAndJellyWobbles() throws {
        var cloth = SceneObject(id: "cloth", name: "Cloth", kind: .primitive(.plane), transform: Transform(position: Vec3(0, 1.3, 0), scale: Vec3(1.2, 1, 1.2)))
        cloth.physics = ObjectPhysics(material: .cloth)
        var ball = SceneObject(id: "ball", name: "Ball", kind: .primitive(.sphere), transform: Transform(position: .zero, scale: Vec3(1, 1, 1)))
        ball.physics = ObjectPhysics(material: .stone, motion: .stays)
        var jelly = Base.cube("jelly", at: Vec3(3, 1, 0), size: 0.5, material: .jelly)
        jelly.physics?.stiffness = 0.3
        let document = Base.document([cloth, ball, jelly], duration: 1.5)
        let frames = try Base.run(document)
        let draped = Animator.evaluate(document, at: 1.5, physics: frames)
        let surface = try XCTUnwrap(draped.simulated.meshes["cloth"])
        let world = draped.scene.worldTransform(of: "cloth")
        let heights = surface.positions.map { world.apply(to: Vec3($0)).y }
        XCTAssertGreaterThan(heights.max() ?? 0, 0.9, "the middle rests on the ball")
        XCTAssertLessThan(heights.min() ?? 9, 0.7, "the edges hang down")
        let wobbly = try XCTUnwrap(draped.simulated.meshes["jelly"])
        let bounds = try XCTUnwrap(wobbly.bounds)
        XCTAssertGreaterThan(bounds.size.y, 0.25, "it keeps its body")
    }

    func testWaterPouredIntoAGlassFillsIt() throws {
        let glass = Self.glass()
        var tap = SceneObject(id: "tap", name: "Tap", kind: .fluid(FluidRecipe(kind: .pour, box: Vec3(0.4, 0.5, 0.4), amount: 0.08, duration: 1)),
                              transform: Transform(position: Vec3(0, 0.2, 0)))
        tap.name = "Tap"
        let document = Base.document([glass, tap], duration: 1.4)
        let frames = try Base.run(document)
        let look = try XCTUnwrap(frames.frames.last?.fluids.first)
        XCTAssertGreaterThan(look.amount, 0.03, "water was poured")
        let surface = try XCTUnwrap(look.surface)
        let inside = surface.positions.filter { Double($0.y) > 0.005 && Double($0.y) < 0.12 && Double($0.x * $0.x + $0.z * $0.z).squareRoot() < 0.045 }
        XCTAssertGreaterThan(Double(inside.count) / Double(max(surface.positions.count, 1)), 0.6, "it stays in the glass")
        XCTAssertNotNil(Animator.evaluate(document, at: 1.5, physics: frames).simulated.fluids["tap"]?.surface)
    }

    /// A glass: an open cylinder 8 cm wide and 12 cm tall with a 4 mm wall and a base.
    static func glass() -> SceneObject {
        var positions: [Vec3] = []
        var triangles: [(Int, Int, Int)] = []
        let sides = 24
        for ring in [(0.04, 0.0), (0.04, 0.12), (0.036, 0.12), (0.036, 0.004)] {
            for side in 0 ..< sides {
                let angle = Double(side) / Double(sides) * 2 * .pi
                positions.append(Vec3(cos(angle) * ring.0, ring.1, sin(angle) * ring.0))
            }
        }
        for band in 0 ..< 3 {
            for side in 0 ..< sides {
                let a = band * sides + side
                let b = band * sides + (side + 1) % sides
                triangles += [(a, b + sides, b), (a, a + sides, b + sides)]
            }
        }
        positions += [Vec3(0, 0, 0), Vec3(0, 0.004, 0)]
        for side in 0 ..< sides {
            triangles += [(positions.count - 2, side, (side + 1) % sides), (positions.count - 1, 3 * sides + (side + 1) % sides, 3 * sides + side)]
        }
        var object = SceneObject(id: "glass", name: "Glass", kind: .mesh(MeshBuilder.mesh(positions: positions, triangles: triangles, weld: true)))
        object.physics = ObjectPhysics(material: .glass, motion: .stays)
        return object
    }

    func testSmokeRises() throws {
        let smoke = SceneObject(id: "smoke", name: "Smoke", kind: .fluid(FluidRecipe(kind: .smoke, box: Vec3(1, 2, 1), duration: 2)))
        let document = Base.document([smoke], duration: 1.5)
        let frames = try Base.run(document)
        let early = try XCTUnwrap(frames.frames[10].fluids.first?.puffs)
        let late = try XCTUnwrap(frames.frames.last?.fluids.first?.puffs)
        func height(_ puffs: [Particle]) -> Double { puffs.map(\.position.y).reduce(0, +) / Double(max(puffs.count, 1)) }
        XCTAssertFalse(late.isEmpty)
        XCTAssertGreaterThan(height(late), height(early) + 0.1)
    }

    func testSettleLaysAThingOnItsFace() throws {
        var cube = Base.cube("c", at: Vec3(0, 1, 0), size: 0.5)
        cube.properties[.rotation] = .quat(Quat(angle: 0.5, axis: Vec3(1, 0, 1).normalized))
        let document = Base.document([cube])
        let meshes = try ["c": XCTUnwrap(SceneExport.localMesh(of: cube, look: document.effectiveLook))] as [ObjectID: MeshData]
        let settled = try XCTUnwrap(PhysicsTools.settle("c", in: document.scene, meshes: meshes))
        let up = settled.rotation.act(.unitY)
        let aligned = [Vec3.unitX, .unitY, .unitZ].map { abs(up.dot($0)) }.max() ?? 0
        XCTAssertGreaterThan(aligned, 0.99, "a face lies flat")
        let lowest = (0 ..< 8).map { corner -> Double in
            let local = Vec3(corner & 1 == 0 ? -0.5 : 0.5, corner & 2 == 0 ? 0 : 1, corner & 4 == 0 ? -0.5 : 0.5)
            return settled.apply(to: local).y
        }.min() ?? 9
        XCTAssertEqual(lowest, 0, accuracy: 0.01, "on the ground")
    }

    func testDoesItStand() throws {
        let upright = Base.cube("u", at: .zero, size: 1)
        var leaning = SceneObject(id: "l", name: "Leaning", kind: .primitive(.cube),
                                  transform: Transform(position: Vec3(3, 0, 0), rotation: Quat(angle: 0.35, axis: .unitZ), scale: Vec3(0.2, 2, 0.2)))
        leaning.physics = ObjectPhysics(material: .steel)
        let document = Base.document([upright, leaning])
        let meshes = Dictionary(uniqueKeysWithValues: [upright, leaning].compactMap { object in
            SceneExport.localMesh(of: object, look: document.effectiveLook).map { (object.id, $0) }
        })
        let stands = try XCTUnwrap(PhysicsTools.stability(of: ["u"], in: document.scene, meshes: meshes))
        XCTAssertTrue(stands.stands)
        XCTAssertEqual(stands.mass, 700, accuracy: 6)
        XCTAssertEqual(stands.margin, 0.5, accuracy: 0.02)
        let tips = try XCTUnwrap(PhysicsTools.stability(of: ["l"], in: document.scene, meshes: meshes))
        XCTAssertFalse(tips.stands, "a thin pole leaning 20° falls")
    }

    // MARK: The sun

    /// NREL's SPA reference (Reda & Andreas 2008): Golden, Colorado, 17 October 2003, 12:30:30 local (UTC−7): zenith
    /// 50.11162°, azimuth 194.34024°. NOAA's calculation lands within 0.5°.
    func testTheRealSunMatchesTheSolarPositionReference() {
        let sun = SolarPosition.at(latitude: 39.742476, longitude: -105.1786, year: 2003, month: 10, day: 17, hour: 12 + 30.5 / 60, utcOffset: -7)
        XCTAssertEqual(90 - sun.elevation, 50.11162, accuracy: 0.5)
        XCTAssertEqual(sun.azimuth, 194.34024, accuracy: 0.5)
        // Equinox noon at the equator: overhead, within a degree and a half (the equation of time, the date's declination).
        let equator = SolarPosition.at(latitude: 0, longitude: 0, year: 2026, month: 3, day: 20, hour: 12 + 7.5 / 60, utcOffset: 0)
        XCTAssertGreaterThan(equator.elevation, 88.5)
        // Rome's summer solstice: high in the south at local noon, below the horizon at midnight.
        var rome = RealSun.places[0]
        // Solar noon in Rome in summer time is about ten past one on the clock.
        rome.hour = 13 + 10.0 / 60
        let noon = rome.position(at: 0, duration: 0)
        XCTAssertEqual(noon.elevation, 90 - 41.9 + 23.44, accuracy: 1.5)
        var night = rome
        night.hour = 0
        XCTAssertLessThan(night.position(at: 0, duration: 0).elevation, 0)
    }

    func testAShadowStudyMovesTheSunAcrossTheTimeline() {
        var document = Base.document([])
        var sun = RealSun.places[0]
        sun.study = 7 ... 19
        document.project.look.lighting.realSun = sun
        let morning = Animator.evaluate(document, at: 0).scene.look?.lighting
        let evening = Animator.evaluate(document, at: 3).scene.look?.lighting
        XCTAssertNotNil(morning)
        XCTAssertNotEqual(morning?.sunAzimuth, evening?.sunAzimuth)
        // North is -Z: the morning sun is in the east (+X), so its light travels toward -X.
        XCTAssertLessThan(morning?.sunDirection.x ?? 1, 0)
        XCTAssertGreaterThan(evening?.sunDirection.x ?? -1, 0)
    }
}
