@testable import HmmLink
import XCTest

final class FramesTests: XCTestCase {
    func testAFrameComesBackWhole() throws {
        var reader = HmmFrameReader()
        let payload = Data("hello iPad".utf8)
        XCTAssertEqual(try reader.read(HmmFrames.frame(payload)), [payload])
        XCTAssertEqual(reader.waiting, 0)
    }

    func testFramesArriveInAnyPieces() throws {
        var reader = HmmFrameReader()
        let first = Data(repeating: 7, count: 3000)
        let second = Data("two".utf8)
        let stream = HmmFrames.frame(first) + HmmFrames.frame(second) + HmmFrames.frame(Data())
        var frames: [Data] = []
        var index = stream.startIndex
        // One byte, then growing pieces, as a network might hand them over.
        var size = 1
        while index < stream.endIndex {
            let end = min(stream.endIndex, index + size)
            frames += try reader.read(Data(stream[index ..< end]))
            index = end
            size = size * 2 + 1
        }
        XCTAssertEqual(frames, [first, second, Data()])
        XCTAssertEqual(reader.waiting, 0)
    }

    func testAHalfFrameWaits() throws {
        var reader = HmmFrameReader()
        let frame = HmmFrames.frame(Data("a scan".utf8))
        XCTAssertEqual(try reader.read(Data(frame.prefix(5))), [])
        XCTAssertEqual(reader.waiting, 5)
        XCTAssertEqual(try reader.read(Data(frame.dropFirst(5))), [Data("a scan".utf8)])
    }

    func testAStreamThatIsNotOursIsRefused() {
        var reader = HmmFrameReader()
        XCTAssertThrowsError(try reader.read(Data([0xFF, 0xFF, 0xFF, 0xFF, 1]))) { error in
            XCTAssertEqual(error as? HmmFrameReader.Failure, .tooLong(Int(UInt32.max)))
        }
        XCTAssertEqual(reader.waiting, 0)
    }

    func testMessagesAreJSONInFrames() throws {
        struct Ping: Codable, Equatable { var n: Int }
        var reader = HmmFrameReader()
        let frames = try reader.read(HmmFrames.frame(Ping(n: 3)))
        XCTAssertEqual(try JSONDecoder().decode(Ping.self, from: XCTUnwrap(frames.first)), Ping(n: 3))
    }
}
