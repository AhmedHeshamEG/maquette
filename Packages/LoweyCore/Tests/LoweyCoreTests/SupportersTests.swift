@testable import LoweyCore
import XCTest

final class SupportersTests: XCTestCase {
    func testReadsFoundingSupportersInOrderAndTheCoffeeList() {
        let list = SupportersList(markdown: """
        # Supporters

        <!--
        - #9 Not a supporter, a comment
        -->
        ## Founding Supporters
        - #2 Sara
        - #1 Omar
        - #2 Someone else with a taken number
        - #101 Too late for a number
        - #0 Nobody
        - Giulia without a number

        ## Coffee
        - Dev
        * Mina
        """)
        XCTAssertEqual(list.founding.map(\.number), [1, 2])
        XCTAssertEqual(list.founding.map(\.name), ["Omar", "Sara"])
        XCTAssertEqual(list.coffee, ["Dev", "Mina"])
        XCTAssertFalse(list.isEmpty)
    }

    func testTheShippedFileParses() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SUPPORTERS.md")
        let text = try String(contentsOf: file, encoding: .utf8)
        let list = SupportersList(markdown: text)
        XCTAssertLessThanOrEqual(list.founding.count, SupportersList.foundingLimit)
        XCTAssertEqual(Set(list.founding.map(\.number)).count, list.founding.count)
    }

    func testTheThankYouCardGetsOneTurnEver() {
        var shown = false
        let gate = ThankYouCardGate(isShown: { shown }, markShown: { shown = true })
        XCTAssertTrue(gate.takeTurn(), "after the first export")
        XCTAssertFalse(gate.takeTurn(), "never after the second")
        XCTAssertFalse(gate.takeTurn(), "or the third")
        // A relaunch reads the same flag.
        XCTAssertFalse(ThankYouCardGate(isShown: { shown }, markShown: { shown = true }).takeTurn())
    }
}
