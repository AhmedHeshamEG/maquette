@testable import HmmDesign
import XCTest

final class KeyBindingsTests: XCTestCase {
    private let model = HmmKeyCommand("tools.model", "Model", menu: "Tools", HmmKeyCombo("1"))
    private let draw = HmmKeyCommand("tools.draw", "Draw", menu: "Tools", HmmKeyCombo("2"))
    private let present = HmmKeyCommand("present", "Present", menu: "View")
    private var commands: [HmmKeyCommand] { [model, draw, present] }

    func testTheAppsOwnKeysUntilChanged() {
        let bindings = HmmKeyBindings()
        XCTAssertEqual(bindings.combo(for: model), HmmKeyCombo("1"))
        XCTAssertNil(bindings.combo(for: present))
        XCTAssertEqual(bindings.command(for: HmmKeyCombo("2"), in: commands), draw)
    }

    func testAKeyTakenFromAnotherCommandLeavesItWithout() {
        var bindings = HmmKeyBindings()
        let losers = bindings.bind(present, to: HmmKeyCombo("1"), among: commands)
        XCTAssertEqual(losers, [model])
        XCTAssertEqual(bindings.combo(for: present), HmmKeyCombo("1"))
        XCTAssertNil(bindings.combo(for: model))
        XCTAssertEqual(bindings.command(for: HmmKeyCombo("1"), in: commands), present)
    }

    func testResettingOneTakesItsKeyBack() {
        var bindings = HmmKeyBindings()
        bindings.bind(present, to: HmmKeyCombo("1"), among: commands)
        let losers = bindings.reset(model, among: commands)
        XCTAssertEqual(losers, [present])
        XCTAssertEqual(bindings.combo(for: model), HmmKeyCombo("1"))
        XCTAssertNil(bindings.combo(for: present))
        XCTAssertTrue(bindings.chosen.isEmpty, "the app's own key is stored as no change")
    }

    func testAKeyCanBeTakenAway() {
        var bindings = HmmKeyBindings()
        bindings.bind(draw, to: nil, among: commands)
        XCTAssertNil(bindings.combo(for: draw))
        XCTAssertEqual(bindings.cleared, ["tools.draw"])
    }

    func testCombosReadLikeTheMenuBar() {
        XCTAssertEqual(HmmKeyCombo("D", shift: true).display, "⇧⌘D")
        XCTAssertEqual(HmmKeyCombo("delete").display, "⌘⌫")
        XCTAssertEqual(HmmKeyCombo("p", option: true, control: true).display, "⌃⌥⌘P")
        XCTAssertEqual(HmmKeyCombo("D").key, "d", "letters are kept lowercase")
    }

    func testABareLetterIsNoShortcut() {
        XCTAssertFalse(HmmKeyCombo("k", command: false).isUsable)
        XCTAssertTrue(HmmKeyCombo("k").isUsable)
        XCTAssertTrue(HmmKeyCombo("escape", command: false).isUsable)
        XCTAssertFalse(HmmKeyCombo("space", command: false).isUsable)
    }

    func testTheyAreRemembered() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "KeyBindingsTests"))
        defaults.removePersistentDomain(forName: "KeyBindingsTests")
        var bindings = HmmKeyBindings()
        bindings.bind(present, to: HmmKeyCombo("p", option: true), among: commands)
        bindings.save(to: defaults)
        XCTAssertEqual(HmmKeyBindings.load(from: defaults), bindings)
        HmmKeyBindings().save(to: defaults)
        XCTAssertNil(defaults.data(forKey: HmmKeyBindings.storageKey))
    }
}
