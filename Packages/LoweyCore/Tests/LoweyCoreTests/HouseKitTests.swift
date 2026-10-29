@testable import LoweyCore
import XCTest

/// The house kit (Q2, M14's starting library): every thing builds as one group of bevelled parts standing on the
/// ground, and changing its size keeps what should stay fixed.
final class HouseKitTests: XCTestCase {
    func testEveryThingIsOneGroupOfPartsOnTheGround() {
        for item in HouseKit.Item.allCases {
            let fragment = HouseKit.build(item, ids: .sequential(item.rawValue))
            XCTAssertEqual(fragment.roots.count, 1, "\(item)")
            guard let root = fragment.objects.first else { return XCTFail("\(item) is empty") }
            XCTAssertEqual(root.kind, .group, "\(item)")
            XCTAssertEqual(root.name, item.title)
            XCTAssertGreaterThanOrEqual(root.children.count, 1, "\(item) has parts")
            XCTAssertEqual(root.children, fragment.objects.dropFirst().map(\.id), "\(item)'s parts are its children")
            for part in fragment.objects.dropFirst() {
                XCTAssertEqual(part.parent, root.id)
                let transform = part.transform
                XCTAssertTrue(transform.scale.x > 0 && transform.scale.y > 0 && transform.scale.z > 0, "\(item): \(part.name) has a size")
                for value in [transform.position.x, transform.position.y, transform.position.z] {
                    XCTAssertTrue(value.isFinite, "\(item): \(part.name)")
                }
                // Nothing is sunk far into the ground (a rock sits a little in it on purpose).
                XCTAssertGreaterThan(transform.position.y, -item.size.y * 0.2, "\(item): \(part.name)")
                if case let .primitive(shape) = part.kind, BevelSpec.applies(to: shape) {
                    XCTAssertNotNil(BevelSpec(part), "\(item): \(part.name) is soft")
                }
            }
        }
    }

    func testEveryCategoryHasThingsAndEveryThingIsFoundByItsID() {
        for category in HouseKit.Category.allCases {
            XCTAssertFalse(HouseKit.items(in: category).isEmpty, "\(category)")
        }
        for item in HouseKit.Item.allCases {
            XCTAssertEqual(HouseKit.item(libraryID: item.libraryID), item)
        }
        XCTAssertNil(HouseKit.item(libraryID: "kit.table"))
    }

    func testALongerTableKeepsItsLegsAtTheCornersAndAsThick() {
        let normal = HouseKit.build(.table, ids: .sequential("a"))
        let long = HouseKit.build(.table, size: Vec3(2.8, 0.75, 0.8), ids: .sequential("b"))
        let legs = { (fragment: SceneFragment) in fragment.objects.filter { $0.name == "Leg" } }
        XCTAssertEqual(legs(normal).count, 4)
        XCTAssertEqual(legs(long).count, 4)
        XCTAssertEqual(legs(normal).map(\.transform.scale), legs(long).map(\.transform.scale), "as thick")
        let reach = { (fragment: SceneFragment) in legs(fragment).map { abs($0.transform.position.x) }.max() ?? 0 }
        XCTAssertGreaterThan(reach(long), reach(normal) + 0.6, "at the corners")
    }

    func testATallerShelfGainsShelves() {
        let boards = { (height: Double) in
            HouseKit.build(.shelf, size: Vec3(0.9, height, 0.35), ids: .sequential("s")).objects.filter { $0.name == "Board" }.count
        }
        XCTAssertGreaterThan(boards(2.6), boards(1.2))
    }
}
