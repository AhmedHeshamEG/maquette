import Foundation
@testable import LoweyCore
import XCTest

final class KeepersTowerTests: XCTestCase {
    func testTheTowerTheLampAndTheKeeper() throws {
        let (info, scenes) = try KeepersTowerSample.build()
        XCTAssertEqual(info.name, "The Keeper's Tower")
        let scene = try XCTUnwrap(scenes.first)
        let names = Set(scene.objects.values.map(\.name))
        for name in ["Tower", "Course 1", "Course 5", "Lamp glass", "Roof", "The lamp", "Keeper", "Lantern", "Tower camera"] {
            XCTAssertTrue(names.contains(name), name)
        }
        let look = try XCTUnwrap(scene.look)
        XCTAssertEqual(look.presetID, "ink")
        XCTAssertEqual(look.lightingPreset, .night)
        XCTAssertEqual(look.ground.surface, .rock)
        let tower = try XCTUnwrap(scene.objects.values.first { $0.name == "Tower" })
        XCTAssertNotEqual(tower.transform.rotation, .identity, "the tower leans")
        let keeper = try XCTUnwrap(scene.objects.values.first { $0.name == "Keeper" })
        let coat = try XCTUnwrap(scene.objects.values.first { $0.name == "Coat" })
        XCTAssertEqual(coat.parent, keeper.id)
        XCTAssertLessThan(coat.transform.scale.y * 2, 1.2, "the keeper is tiny next to an eleven-metre tower")
        XCTAssertGreaterThan(scene.timeline.duration, 10)
        XCTAssertFalse(scene.timeline.cuts.isEmpty, "it turns through its own camera")
    }
}
