@testable import HmmDesign
import XCTest

final class ArrangementTests: XCTestCase {
    private let ids = ["home", "actions", "look", "library"]

    func testNothingSavedIsTheAppsOwnOrder() {
        let arrangement = HmmArrangement()
        XCTAssertEqual(arrangement.visible(ids), ids)
        XCTAssertTrue(arrangement.isDefault)
    }

    func testMovingStaysInTheGroupAndEnds() {
        var arrangement = HmmArrangement()
        arrangement.move("library", by: -1, in: ids)
        XCTAssertEqual(arrangement.visible(ids), ["home", "actions", "library", "look"])
        arrangement.move("library", by: -10, in: ids)
        XCTAssertEqual(arrangement.visible(ids), ["library", "home", "actions", "look"])
        arrangement.move("library", by: -1, in: ids)
        XCTAssertEqual(arrangement.visible(ids).first, "library", "it can't leave the group")
    }

    func testMovingBackIsStoredAsTheDefault() {
        var arrangement = HmmArrangement()
        arrangement.move("look", by: 1, in: ids)
        XCTAssertFalse(arrangement.isDefault)
        arrangement.move("look", by: -1, in: ids)
        XCTAssertTrue(arrangement.isDefault)
    }

    func testAListsDragMovesLikeOnMove() {
        var arrangement = HmmArrangement()
        arrangement.move(fromOffsets: IndexSet(integer: 0), toOffset: 3, in: ids)
        XCTAssertEqual(arrangement.ordered(ids), ["actions", "look", "home", "library"])
        arrangement.move(fromOffsets: IndexSet(integer: 3), toOffset: 0, in: ids)
        XCTAssertEqual(arrangement.ordered(ids), ["library", "actions", "look", "home"])
    }

    func testHiddenButtonsLeaveButFixedOnesStay() {
        var arrangement = HmmArrangement()
        arrangement.setHidden("look", true)
        arrangement.setHidden("home", true)
        XCTAssertEqual(arrangement.visible(ids, fixed: ["home"]), ["home", "actions", "library"])
        XCTAssertEqual(arrangement.ordered(ids), ids, "Settings still lists them")
        arrangement.setHidden("look", false)
        XCTAssertEqual(arrangement.visible(ids, fixed: ["home"]), ids)
    }

    func testAButtonAddedLaterTakesItsDefaultPlace() {
        let arrangement = HmmArrangement(order: ["library", "home", "actions", "look"])
        let later = ["home", "actions", "notes", "look", "library"]
        XCTAssertEqual(arrangement.ordered(later), ["library", "home", "actions", "notes", "look"])
        let first = HmmArrangement(order: ["actions", "home"])
        XCTAssertEqual(first.ordered(["new", "home", "actions"]), ["new", "actions", "home"])
    }

    func testRemovedButtonsAreForgotten() {
        let arrangement = HmmArrangement(order: ["gone", "look", "home", "actions", "library"])
        XCTAssertEqual(arrangement.ordered(ids), ["look", "home", "actions", "library"])
    }

    func testItIsRememberedAndResetTogetherWithTheHand() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ArrangementTests"))
        defaults.removePersistentDomain(forName: "ArrangementTests")
        var arrangement = HmmArrangement()
        arrangement.move("look", by: 1, in: ids)
        HmmLayoutStore.save(arrangement, "document", in: defaults)
        HmmHand.left.save(in: defaults)
        defaults.set(0.5, forKey: "sidebar.place")
        XCTAssertEqual(HmmLayoutStore.arrangement("document", in: defaults), arrangement)
        XCTAssertEqual(HmmHand.current(in: defaults), .left)
        HmmLayoutStore.reset(["document"], extraKeys: ["sidebar.place"], in: defaults)
        XCTAssertTrue(HmmLayoutStore.arrangement("document", in: defaults).isDefault)
        XCTAssertEqual(HmmHand.current(in: defaults), .right)
        XCTAssertNil(defaults.object(forKey: "sidebar.place"))
    }

    func testTheOldSidebarSwitchMeansTheLeftHand() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ArrangementTestsLegacy"))
        defaults.removePersistentDomain(forName: "ArrangementTestsLegacy")
        defaults.set(true, forKey: "sidebarOnRight")
        XCTAssertEqual(HmmHand.current(in: defaults, legacyKey: "sidebarOnRight"), .left)
        HmmHand.right.save(in: defaults)
        XCTAssertEqual(HmmHand.current(in: defaults, legacyKey: "sidebarOnRight"), .right, "a choice made since wins")
    }

    func testTheEdgePlaceIsAFractionOfTheRoom() {
        XCTAssertEqual(HmmEdgePlace.offset(0, content: 400, container: 800), 0)
        XCTAssertEqual(HmmEdgePlace.offset(-1, content: 400, container: 800), -200)
        XCTAssertEqual(HmmEdgePlace.offset(3, content: 400, container: 800), 200, "it can't leave the edge")
        XCTAssertEqual(HmmEdgePlace.offset(1, content: 900, container: 800), 0, "no room, no move")
        XCTAssertEqual(HmmEdgePlace.fraction(from: 0, dragged: 100, content: 400, container: 800), 0.5)
        XCTAssertEqual(HmmEdgePlace.fraction(from: 0.5, dragged: 1000, content: 400, container: 800), 1)
    }
}
