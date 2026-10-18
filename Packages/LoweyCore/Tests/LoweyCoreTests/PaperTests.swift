import Foundation
@testable import LoweyCore
import XCTest

/// A1: Export ▸ Paper. A frame on a page and frames across the shot, as PDFs every reader opens.
final class PaperTests: XCTestCase {
    /// The smallest JPEG there is (a grey pixel): the writer embeds JPEGs as they are.
    static let pixel = Data([
        0xFF, 0xD8, 0xFF, 0xDB, 0x00, 0x43, 0x00] + [UInt8](repeating: 0x01, count: 64) + [
        0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01, 0x00, 0x01, 0x01, 0x01, 0x11, 0x00,
        0xFF, 0xC4, 0x00, 0x14, 0x00, 0x01] + [UInt8](repeating: 0x00, count: 15) + [0x00,
        0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0x00, 0xFF, 0xD9])

    private func picture(_ width: Int = 1920, _ height: Int = 1080) -> PDFWriter.Picture {
        PDFWriter.Picture(jpeg: Self.pixel, width: width, height: height)
    }

    /// Every object the cross-reference table lists starts where it says, and the trailer points at the table.
    private func assertWellFormed(_ data: Data, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("%PDF-1.4"), file: file, line: line)
        XCTAssertTrue(text.hasSuffix("%%EOF\n"), file: file, line: line)
        let bytes = [UInt8](data)
        let start = try XCTUnwrap(text.components(separatedBy: "startxref\n").last?.split(separator: "\n").first.flatMap { Int($0) })
        XCTAssertEqual(String(decoding: bytes[start ..< start + 4], as: UTF8.self), "xref", file: file, line: line)
        let table = String(decoding: bytes[start...], as: UTF8.self).split(separator: "\n")
        let count = try XCTUnwrap(Int(table[1].split(separator: " ")[1]))
        for index in 1 ..< count {
            let offset = try XCTUnwrap(Int(table[2 + index].prefix(10)))
            let head = String(decoding: bytes[offset ..< min(offset + 12, bytes.count)], as: UTF8.self)
            XCTAssertTrue(head.hasPrefix("\(index) 0 obj"), "object \(index) at \(offset): \(head)", file: file, line: line)
        }
        return text
    }

    func testAFrameFillsALandscapePageWithItsTitleAndArtist() throws {
        let data = PaperLayout.frame(picture(), paper: .a4, title: "The Keeper's Tower (night)", caption: "0:03.20", author: "Ada Café")
        let text = try assertWellFormed(data)
        XCTAssertTrue(text.contains("/MediaBox [0 0 841.890 595.280]"), "a wide picture turns the page")
        XCTAssertTrue(text.contains("/Count 1"))
        XCTAssertTrue(text.contains("/Filter /DCTDecode"))
        XCTAssertTrue(text.contains("(The Keeper's Tower \\(night\\))"), "brackets are escaped")
        XCTAssertTrue(text.contains("by Ada Caf\\351"), "Latin-1 travels")
        XCTAssertTrue(text.contains("/Author (Ada Caf\\351)"))
        let portrait = try assertWellFormed(PaperLayout.frame(picture(1080, 1920), paper: .letter, title: "Reel", caption: ""))
        XCTAssertTrue(portrait.contains("/MediaBox [0 0 612 792]"))
        XCTAssertEqual(PDFWriter.escaped("سلام"), "????")
    }

    func testFramesAcrossTheShotFillPagesInOrder() throws {
        let moments = PaperLayout.moments(14, across: TimeRange(start: 0, end: 6.5))
        XCTAssertEqual(moments.first, 0)
        XCTAssertEqual(moments.last ?? 0, 6.5, accuracy: 1e-9)
        let data = PaperLayout.frames(moments.map { (picture(), $0) }, paper: .a4, title: "Shot 1", author: "Ada")
        let text = try assertWellFormed(data)
        XCTAssertTrue(text.contains("/Count 2"), "nine to a landscape A4, so fourteen take two pages")
        XCTAssertEqual(text.components(separatedBy: "/Subtype /Image").count - 1, 14)
        XCTAssertTrue(text.contains("(14   0:06.50)"))
        XCTAssertEqual(PaperLayout.timecode(63.456), "1:03.46")
        if let directory = ProcessInfo.processInfo.environment["ACCEPTANCE_DIR"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("paper")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try data.write(to: url.appendingPathComponent("frames.pdf"))
        }
    }
}
