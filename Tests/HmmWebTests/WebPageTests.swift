@testable import HmmWeb
import XCTest

final class WebPageTests: XCTestCase {
    func testCDNLibrariesBecomeTheCarriedCopies() {
        let page = """
        <script type="importmap">{"imports":{"three":"https://unpkg.com/three@0.160.0/build/three.module.js",
        "three/addons/":"https://cdn.jsdelivr.net/npm/three@0.160.0/examples/jsm/"}}</script>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/lottie-web/5.12.2/lottie.min.js"></script>
        <script type="module">import * as THREE from "https://esm.sh/three@0.170.0";</script>
        """
        let rewritten = HmmWebPage.rewriteLibraries(page)
        XCTAssertTrue(rewritten.contains("\"three\":\"\(HmmWebPage.three)\""))
        XCTAssertTrue(rewritten.contains("\"three/addons/\":\"\(HmmWebPage.threeAddons)\""))
        XCTAssertTrue(rewritten.contains("src=\"\(HmmWebPage.lottie)\""))
        XCTAssertTrue(rewritten.contains("from \"\(HmmWebPage.three)\""))
        XCTAssertFalse(rewritten.contains("https://"))
    }

    func testAPageGetsThePolicyAndAnImportMapUnlessItHasOne() throws {
        let bare = HmmWebPage.prepare("<html><head><title>x</title></head><body></body></html>")
        XCTAssertTrue(bare.contains("Content-Security-Policy"))
        XCTAssertTrue(bare.contains("type=\"importmap\""))
        XCTAssertTrue(bare.contains("name=\"viewport\""), "laid out at its own size")
        XCTAssertEqual(HmmWebPage.prepare("<head><meta name=\"viewport\" content=\"width=500\"></head>").components(separatedBy: "viewport").count, 2)
        let map = try XCTUnwrap(bare.range(of: "importmap")), title = try XCTUnwrap(bare.range(of: "<title>"))
        XCTAssertLessThan(map.lowerBound, title.lowerBound, "first in the head")

        let mapped = HmmWebPage.prepare("<head><script type=\"importmap\">{\"imports\":{}}</script></head>")
        XCTAssertEqual(mapped.components(separatedBy: "importmap").count, 2, "one import map only")

        let fragment = HmmWebPage.prepare("<div>hi</div>")
        XCTAssertTrue(fragment.hasPrefix("<!doctype html><html><head>"))
        XCTAssertTrue(fragment.contains("<body><div>hi</div></body>"))
    }

    func testTheLottieHostTurnsTheAnimationOnTheClock() {
        let host = HmmWebPage.lottieHost(json: "{\"v\":\"5.7.0\"}")
        XCTAssertTrue(host.contains(HmmWebPage.lottie))
        XCTAssertTrue(host.contains("const data = {\"v\":\"5.7.0\"};"))
        XCTAssertTrue(host.contains("__hmm.onFrame"))
        XCTAssertTrue(host.contains("autoplay: false"))
        XCTAssertTrue(host.contains("name=\"viewport\""))
    }

    func testFramesAreSixtyASecond() {
        XCTAssertEqual(HmmWebTime.frame(at: 0), 0)
        XCTAssertEqual(HmmWebTime.frame(at: 0.5), 30)
        XCTAssertEqual(HmmWebTime.frame(at: 1.0 / 60), 1, "a frame's own start belongs to it")
        XCTAssertEqual(HmmWebTime.frame(at: -2), 0)
        XCTAssertEqual(HmmWebTime.seconds(ofFrame: 90), 1.5, accuracy: 1e-12)
    }

    func testKindFromTheFileName() {
        XCTAssertEqual(HmmWebPiece.kind(forFile: "logo.json"), .lottie)
        XCTAssertEqual(HmmWebPiece.kind(forFile: "scene.HTML"), .html)
        XCTAssertEqual(HmmWebPiece(kind: .html, source: .inline(""), width: 2, height: 2).width, 16, "never smaller than 16")
    }

    func testTheClockReplacesEveryTimeSource() {
        for name in ["performance, 'now'", "window.Date = HmmDate", "window.requestAnimationFrame", "window.setTimeout",
                     "window.setInterval", "Math.random", "getAnimations", "video,audio", "prime()"] {
            XCTAssertTrue(HmmWebClock.script.contains(name), name)
        }
        XCTAssertEqual(HmmWebClock.step(-3), "return window.__hmm.step(0);")
    }

    func testTheLibrariesAreCarried() throws {
        let root = try XCTUnwrap(HmmWebPage.libraryFolder)
        for file in ["three/three.module.js", "three/LICENSE", "three/addons/controls/OrbitControls.js",
                     "three/addons/loaders/GLTFLoader.js", "lottie.min.js", "lottie.LICENSE.md"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(file).path), file)
        }
    }
}
