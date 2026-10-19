@testable import HmmMedia
import XCTest

/// The 360° box added to a finished file: in the video track, the sizes grown, and the media's offsets moved when the
/// movie box comes first.
final class SphericalVideoTests: XCTestCase {
    private func box(_ type: String, _ body: [UInt8]) -> [UInt8] {
        SphericalVideo.be32(UInt32(8 + body.count)) + Array(type.utf8) + body
    }

    /// ftyp, then moov (one sound track, one video track with one chunk), then mdat, or mdat before moov.
    private func file(moovFirst: Bool, chunkAt offset: UInt32) -> [UInt8] {
        func track(_ handler: String) -> [UInt8] {
            let hdlr = box("hdlr", [0, 0, 0, 0] + [0, 0, 0, 0] + Array(handler.utf8) + [UInt8](repeating: 0, count: 13))
            let stco = box("stco", [0, 0, 0, 0] + SphericalVideo.be32(1) + SphericalVideo.be32(offset))
            return box("trak", box("tkhd", [UInt8](repeating: 0, count: 84)) + box("mdia", hdlr + box("minf", box("stbl", stco))))
        }
        let ftyp = box("ftyp", Array("isom".utf8) + [0, 0, 2, 0])
        let moov = box("moov", box("mvhd", [UInt8](repeating: 0, count: 100)) + track("soun") + track("vide"))
        let mdat = box("mdat", [UInt8](repeating: 7, count: 32))
        return moovFirst ? ftyp + moov + mdat : ftyp + mdat + moov
    }

    private func chunkOffsets(_ bytes: [UInt8]) -> [UInt32] {
        func child(_ type: String, of parent: SphericalVideo.Box?) -> SphericalVideo.Box? {
            parent.flatMap { parent in SphericalVideo.boxes(bytes, parent.body, parent.end).first { $0.type == type } }
        }
        let moov = SphericalVideo.boxes(bytes, 0, bytes.count).first { $0.type == "moov" }
        let tracks = moov.map { moov in SphericalVideo.boxes(bytes, moov.body, moov.end).filter { $0.type == "trak" } } ?? []
        return tracks.compactMap { track in
            child("stco", of: child("stbl", of: child("minf", of: child("mdia", of: track)))).map { SphericalVideo.u32(bytes, $0.body + 8) }
        }
    }

    func testTheBoxGoesInTheVideoTrackAndTheMediaMoves() throws {
        let original = file(moovFirst: true, chunkAt: 900)
        let marked = try [UInt8](SphericalVideo.inject(Data(original)))
        XCTAssertTrue(SphericalVideo.isSpherical(Data(marked)))
        XCTAssertFalse(SphericalVideo.isSpherical(Data(original)))
        let added = marked.count - original.count
        XCTAssertGreaterThan(added, 200)
        XCTAssertEqual(chunkOffsets(marked), [900 + UInt32(added), 900 + UInt32(added)], "every track's media moved along")
        let top = SphericalVideo.boxes(marked, 0, marked.count)
        XCTAssertEqual(top.map(\.type), ["ftyp", "moov", "mdat"], "the sizes still add up")
        XCTAssertEqual(top.last?.end, marked.count)
        XCTAssertTrue(String(decoding: marked, as: UTF8.self).contains("<GSpherical:ProjectionType>equirectangular"))
        XCTAssertThrowsError(try SphericalVideo.inject(Data(marked)), "only once")
    }

    func testMediaBeforeTheMovieStaysWhereItIs() throws {
        let marked = try [UInt8](SphericalVideo.inject(Data(file(moovFirst: false, chunkAt: 24))))
        XCTAssertEqual(chunkOffsets(marked), [24, 24])
        XCTAssertEqual(SphericalVideo.boxes(marked, 0, marked.count).map(\.type), ["ftyp", "mdat", "moov"])
    }

    func testNotAMovie() {
        XCTAssertThrowsError(try SphericalVideo.inject(Data("hello".utf8)))
    }
}
