import Foundation
import XCTest

/// `docs/INTEROP.md` (X1) says no more than the round trips prove: every `carried`, `baked` and `extras` cell has a
/// proof with the same word, every proof's test exists, and every proof still matches its cell.
final class InteropMatrixTests: XCTestCase {
    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let rows = [
        "Meshes and hierarchy", "Modelling steps", "Paint layers and maps", "Materials", "The Looks", "Ink and flipbooks", "Sheets",
        "Rigs and skins", "Face states", "Clips", "Keys on any property", "Motion paths", "Cameras", "Lights", "HDRIs and the sky",
        "Physics bodies and joints", "Baked runs", "Clones and links", "Text and logos", "Sound and words", "Web objects",
        "Scenes and shots", "Units and dimensions", "The artist's credit"
    ]
    static let words: Set = ["carried", "baked", "extras", "impossible", "not offered", "todo"]

    struct Cell: Hashable {
        var format: String
        var feature: String
        var direction: String
    }

    /// Every cell of the matrix, a section's unlisted rows filled from its **Not listed** line.
    static func matrix() throws -> [Cell: String] {
        let text = try String(contentsOf: repository.appendingPathComponent("docs/INTEROP.md"), encoding: .utf8)
        var cells: [Cell: String] = [:]
        var format: String?
        var listed = Set<String>()
        func close(with fallback: String?) {
            guard let format else { return }
            for row in rows where !listed.contains(row) {
                for direction in ["Out", "In"] {
                    cells[Cell(format: format, feature: row, direction: direction)] = fallback ?? "missing"
                }
            }
        }
        var fallback: String?
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                close(with: fallback)
                format = String(line.dropFirst(3))
                listed = []
                fallback = nil
            } else if line.hasPrefix("Not listed: ") {
                fallback = String(line.dropFirst("Not listed: ".count))
            } else if let format, line.hasPrefix("| "), !line.hasPrefix("| Feature"), !line.hasPrefix("|---") {
                let parts = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 3 else { continue }
                listed.insert(parts[0])
                cells[Cell(format: format, feature: parts[0], direction: "Out")] = parts[1]
                cells[Cell(format: format, feature: parts[0], direction: "In")] = parts[2]
            }
        }
        close(with: fallback)
        return cells
    }

    /// A cell's word: everything before " — ".
    static func word(_ cell: String) -> String {
        cell.components(separatedBy: " — ").first ?? cell
    }

    func testEveryCellSaysOneOfTheWordsAboutARealRow() throws {
        let cells = try Self.matrix()
        XCTAssertFalse(cells.isEmpty)
        for (cell, value) in cells {
            XCTAssertTrue(Self.rows.contains(cell.feature), "\(cell.format): no row called \(cell.feature)")
            XCTAssertTrue(Self.words.contains(Self.word(value)), "\(cell.format) ▸ \(cell.feature) ▸ \(cell.direction): \(value)")
            if ["impossible", "not offered"].contains(Self.word(value)) {
                XCTAssertTrue(value.contains(" — "), "\(cell.format) ▸ \(cell.feature): say why")
            }
        }
    }

    func testNoCellClaimsMoreThanItsProof() throws {
        let cells = try Self.matrix()
        let proofs = Dictionary(InteropProofs.all.map { (Cell(format: $0.format, feature: $0.feature, direction: $0.direction), $0) }) { first, _ in first }
        for (cell, value) in cells where ["carried", "baked", "extras"].contains(Self.word(value)) {
            guard let proof = proofs[cell] else {
                XCTFail("\(cell.format) ▸ \(cell.feature) ▸ \(cell.direction) says \(Self.word(value)) with no proof in InteropProofs")
                continue
            }
            XCTAssertEqual(proof.claim, Self.word(value), "\(cell.format) ▸ \(cell.feature) ▸ \(cell.direction)")
        }
        // Proofs go stale when a cell changes: each must still match its cell.
        for proof in InteropProofs.all {
            let cell = Cell(format: proof.format, feature: proof.feature, direction: proof.direction)
            XCTAssertEqual(cells[cell].map(Self.word), proof.claim, "the proof for \(proof.format) ▸ \(proof.feature) ▸ \(proof.direction)")
        }
    }

    func testEveryProofIsARealTest() throws {
        let folder = Self.repository.appendingPathComponent("Packages/LoweyCore/Tests/LoweyCoreTests")
        let sources = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }.map { try String(contentsOf: $0, encoding: .utf8) }
        for proof in InteropProofs.all {
            let parts = proof.test.split(separator: ".").map(String.init)
            XCTAssertEqual(parts.count, 2, proof.test)
            let found = sources.contains { $0.contains("class \(parts[0])") && $0.contains("func \(parts.last ?? "")(") }
            XCTAssertTrue(found, "\(proof.test) isn't a test")
        }
        let open = try Self.matrix().values.filter { Self.word($0) == "todo" }.count
        print("INTEROP: \(open) cells still to do")
    }
}
