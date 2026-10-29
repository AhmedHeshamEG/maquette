@testable import LoweyCore
import XCTest

/// A three.js page brought in (X1 step 3): the recorder's output becomes editable things, keys and stand-in cards. The
/// fixture is the acceptance's vibe-coded island, recorded in Chromium by `Tools/record_threejs.mjs`; CI records it
/// again and checks the recorder still says the same.
final class ThreeRecordingTests: XCTestCase {
    private static var fixtures: URL {
        get throws { try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("three-island") }
    }

    private static func island() throws -> ThreeRecording.Result {
        var ids = IDFactory.sequential("in")
        let output = try String(contentsOf: fixtures.appendingPathComponent("recording.json"), encoding: .utf8)
        return try ThreeRecording.read(output, folder: "Island", ids: &ids)
    }

    func testTheIslandComesInAsEditableThings() throws {
        let result = try Self.island()
        let objects = result.reader.scene.fragment.objects
        let byName = Dictionary(objects.map { ($0.name, $0) }) { first, _ in first }
        for name in ["Island", "Ground", "Boat", "Sun"] {
            XCTAssertNotNil(byName[name], "\(name) came in")
        }
        if case .mesh = byName["Ground"]?.kind {} else { XCTFail("the ground is an editable mesh") }
        XCTAssertTrue(objects.contains { $0.kind == .camera }, "the camera the page draws with came in")
        if case let .color(.rgba(ground)) = byName["Ground"]?[.color] {
            XCTAssertEqual(ground.r, Double(0x7C) / 255, accuracy: 0.01, "the ground's material colour")
        } else {
            XCTFail("the ground keeps its colour")
        }
        if case let .light(type) = byName["Sun"]?.kind {
            XCTAssertEqual(type, .directional)
        } else {
            XCTFail("the sun is a light")
        }
        let trees = try XCTUnwrap(objects.first { $0.motionDesign?.clones != nil }, "the instanced trees are one thing with clones")
        if case let .placed(places) = trees.motionDesign?.clones?.layout {
            XCTAssertEqual(places.count, 12)
        } else {
            XCTFail("the trees are cloned as placed")
        }
    }

    func testTheMotionBecomesKeys() throws {
        let result = try Self.island()
        let tracks = result.reader.scene.tracks
        let objects = result.reader.scene.fragment.objects
        let id = { (name: String) in objects.first { $0.name == name }?.id }
        let spin = try XCTUnwrap(tracks.first { $0.target == id("Island") && $0.property == .rotation }, "the island's spin")
        let bob = try XCTUnwrap(tracks.first { $0.target == id("Boat") && $0.property == .position }, "the boat's bob")
        XCTAssertEqual(result.seconds, 10, accuracy: 1e-9)
        XCTAssertEqual(spin.keyframes.last?.time ?? 0, 10, accuracy: 1e-6)
        // A steady turn needs few keys: the straight stretches between them were dropped.
        XCTAssertLessThan(spin.keyframes.count, 120)
        // The clip's own shape: up at 1 s, down at 2 s.
        let heights = bob.keyframes.compactMap { key -> (Double, Double)? in
            if case let .vec3(value) = key.value { return (key.time, value.y) }
            return nil
        }
        let atOne = try XCTUnwrap(heights.min { abs($0.0 - 1) < abs($1.0 - 1) })
        XCTAssertEqual(atOne.1, 0.05, accuracy: 0.01)
        XCTAssertFalse(tracks.contains { $0.target == id("Ground") }, "what didn't move has no keys")
    }

    func testTheShaderSeaStaysPlayingOnACard() throws {
        let result = try Self.island()
        XCTAssertEqual(result.standIns.count, 1)
        let objects = result.reader.scene.fragment.objects
        let (standIn, cardID) = try XCTUnwrap(result.standIns.first)
        XCTAssertEqual(standIn.name, "Sea")
        let card = try XCTUnwrap(objects.first { $0.id == cardID })
        let sea = try XCTUnwrap(objects.first { $0.id == card.parent })
        XCTAssertEqual(sea.name, "Sea")
        XCTAssertEqual(sea.kind, .group, "the sea's place stays, as a group")
        XCTAssertTrue(sea.children.contains(cardID))
        guard case let .card(recipe) = card.kind, let web = recipe.web else { return XCTFail("a card playing a web piece") }
        XCTAssertEqual(web.file, "Island")
        XCTAssertEqual(web.entry, "maquette-solo-1.html")
        XCTAssertEqual(recipe.aspect, 1, accuracy: 1e-6)
        XCTAssertEqual(card.transform.scale.y, 14, accuracy: 1e-6, "as tall as the sea is deep")
        XCTAssertEqual(card.transform.position.y, -7, accuracy: 1e-6, "base-centred on the sea's middle")
        XCTAssertTrue(result.reader.notes.contains("Sea shader: kept as a web object, plays as before."))
        XCTAssertTrue(result.reader.notes.contains { $0.hasPrefix("HemisphereLight") })
    }

    func testACardLiesAcrossTheTwoLongestSides() {
        XCTAssertEqual(ThreeRecording.cardFrame(size: Vec3(14, 14, 0)).axis, "z")
        let flat = ThreeRecording.cardFrame(size: Vec3(4, 0.1, 2))
        XCTAssertEqual(flat.axis, "y")
        XCTAssertEqual(flat.width, 4)
        XCTAssertEqual(flat.height, 2)
        XCTAssertEqual(ThreeRecording.cardFrame(size: Vec3(0.2, 3, 5)).axis, "x")
    }

    func testTheSoloPageRunsTheHookFirst() throws {
        let standIn = ThreeRecording.StandIn(name: "Sea", uuid: "u", path: [3], center: .zero, size: Vec3(14, 14, 0))
        let page = ThreeRecording.soloPage("<html><head><title>x</title></head><body></body></html>", standIn: standIn)
        let script = try XCTUnwrap(page.range(of: "<script>"))
        XCTAssertLessThan(script.lowerBound, try XCTUnwrap(page.range(of: "<title>")).lowerBound)
        XCTAssertTrue(page.contains("const path = [3]"))
        XCTAssertTrue(page.contains("__THREE_DEVTOOLS__"))
    }

    func testAPageWithoutAThreeSceneSaysSo() {
        var ids = IDFactory.sequential("in")
        XCTAssertThrowsError(try ThreeRecording.read(#"{"error":"noScene"}"#, folder: "x", ids: &ids)) { error in
            XCTAssertEqual(error as? ThreeRecording.Failure, .noScene)
        }
    }

    /// Writes the recorder's scripts (and the clock and three.js the sandbox gives a page) for `Tools/record_threejs.mjs`.
    func testWritesTheRecorderForTheBrowserCheck() throws {
        guard let directory = ProcessInfo.processInfo.environment["ACCEPTANCE_DIR"] else { throw XCTSkip("ACCEPTANCE_DIR not set") }
        let root = URL(fileURLWithPath: directory).appendingPathComponent("threejs/recorder")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let web = repo.appendingPathComponent("Packages/HmmKit/Sources/HmmWeb")
        let clockSwift = try String(contentsOf: web.appendingPathComponent("WebClock.swift"), encoding: .utf8)
        let open = try XCTUnwrap(clockSwift.range(of: "script = #\"\"\"\n"))
        let close = try XCTUnwrap(clockSwift.range(of: "\"\"\"#", range: open.upperBound ..< clockSwift.endIndex))
        let clock = clockSwift[open.upperBound ..< close.lowerBound].split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix("    ") ? $0.dropFirst(4) : $0 }.joined(separator: "\n")
        try Data(clock.utf8).write(to: root.appendingPathComponent("clock.js"))
        try Data(ThreeRecorder.hook.utf8).write(to: root.appendingPathComponent("hook.js"))
        try Data(ThreeRecorder.record(from: 0, seconds: 10, rate: 30).utf8).write(to: root.appendingPathComponent("record.js"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("three.module.js"), ifExists: true)
        try FileManager.default.copyItem(at: web.appendingPathComponent("Web/lib/three/three.module.js"), to: root.appendingPathComponent("three.module.js"))
    }
}

private extension FileManager {
    func removeItem(at url: URL, ifExists: Bool) throws {
        if fileExists(atPath: url.path) { try removeItem(at: url) }
    }
}
