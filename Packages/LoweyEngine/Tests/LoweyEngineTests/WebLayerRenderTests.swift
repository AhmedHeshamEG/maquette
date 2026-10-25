import LoweyCore
@testable import LoweyEngine
import UIKit
import XCTest

/// M12's acceptance: a web piece on a card previews and exports the same. The page turns from red to blue over a second
/// on its own clock; the frame at a moment is the same picture however it's reached, and its colour is the clock's.
@MainActor
final class WebLayerRenderTests: XCTestCase {
    private static let page = """
    <!doctype html><html><head><style>html,body{margin:0;width:100%;height:100%}
    body{animation:turn 1s linear forwards}@keyframes turn{from{background:#ff0000}to{background:#0000ff}}</style></head>
    <body></body></html>
    """

    /// A screen filling the middle of the frame, facing the camera, on no ground.
    private func document() -> Document {
        let piece = WebPiece(source: Self.page, width: 320, height: 180, start: 0)
        var screen = SceneObject(id: "screen", name: "Screen", kind: .card(CardRecipe(aspect: piece.aspect, border: 0.01, web: piece)),
                                 transform: Transform(position: Vec3(0, 0, 0), scale: Vec3(2, 2, 2)))
        screen[.color] = .color(.rgba(RGBA(0.1, 0.1, 0.1)))
        var look = Look.default
        look.ground.visible = false
        return TestDocuments.document("Web", objects: [screen], camera: Vec3(0, 1, 4), look: look)
    }

    private func middle(_ image: CGImage) -> (r: Double, g: Double, b: Double) {
        ImageChecks.rgb(image, x: 0.5, y: 0.5)
    }

    func testTheScreenShowsThePagesClock() async throws {
        let session = try TestDocuments.session(document())
        let early = try await session.image(at: 0.1, framing: .landscape, longSide: 320)
        let late = try await session.image(at: 0.9, framing: .landscape, longSide: 320)
        GoldenImage().attach(early, name: "web-early")
        GoldenImage().attach(late, name: "web-late")
        XCTAssertGreaterThan(middle(early).r, middle(early).b + 0.3, "red at the start")
        XCTAssertGreaterThan(middle(late).b, middle(late).r + 0.3, "blue near the end")
    }

    func testAMomentIsTheSameStraightOrAfterScrubbing() async throws {
        let straight = try TestDocuments.session(document())
        let first = try await straight.image(at: 0.5, framing: .landscape, longSide: 320)
        let scrubbed = try TestDocuments.session(document())
        _ = try await scrubbed.image(at: 0.9, framing: .landscape, longSide: 320)
        let again = try await scrubbed.image(at: 0.5, framing: .landscape, longSide: 320)
        XCTAssertEqual(ImageChecks.difference(first, again), 0, accuracy: 0.002, "preview = export: one frame, one picture")
    }
}
