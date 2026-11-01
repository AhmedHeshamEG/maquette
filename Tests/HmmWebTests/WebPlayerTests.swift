#if canImport(UIKit) && canImport(WebKit)
    import CoreGraphics
    @testable import HmmWeb
    import XCTest

    /// SPIKE (M12): an offscreen web view on a stepped clock gives the same picture of a moment however it is reached,
    /// for CSS animations, JavaScript animation frames, three.js (WebGL) and Lottie, with no network.
    @MainActor
    final class WebPlayerTests: XCTestCase {
        private static let slide = """
        <!doctype html><html><head><style>
        html,body{margin:0;background:transparent}
        #box{position:absolute;left:0;top:0;width:20px;height:20px;background:#ff0000;animation:go 1s linear forwards}
        @keyframes go{from{transform:translateX(0)}to{transform:translateX(200px)}}
        </style></head><body><div id="box"></div></body></html>
        """

        private static let frames = """
        <!doctype html><html><body style="margin:0"><canvas id="c" width="240" height="40"></canvas><script>
        const g = document.getElementById('c').getContext('2d');
        function draw(t) { g.clearRect(0, 0, 240, 40); g.fillStyle = '#00ff00'; g.fillRect(performance.now() / 10, 0, 20, 20);
          requestAnimationFrame(draw); }
        requestAnimationFrame(draw);
        </script></body></html>
        """

        private static let three = """
        <!doctype html><html><body style="margin:0"><script type="module">
        import * as THREE from 'three';
        const renderer = new THREE.WebGLRenderer({ alpha: true, antialias: false });
        renderer.setSize(240, 120); renderer.setPixelRatio(1); document.body.appendChild(renderer.domElement);
        const scene = new THREE.Scene();
        const camera = new THREE.OrthographicCamera(-2, 2, 1, -1, 0.1, 10); camera.position.z = 5;
        const box = new THREE.Mesh(new THREE.PlaneGeometry(0.5, 0.5), new THREE.MeshBasicMaterial({ color: 0x0000ff }));
        scene.add(box);
        const clock = new THREE.Clock();
        renderer.setAnimationLoop(() => { box.position.x = -1.5 + clock.getElapsedTime(); renderer.render(scene, camera); });
        </script></body></html>
        """

        private static let lottie = """
        {"v":"5.7.0","fr":60,"ip":0,"op":61,"w":200,"h":100,"layers":[{"ty":1,"ind":1,"sc":"#ff0000","sw":50,"sh":50,"ip":0,"op":61,
        "st":0,"ks":{"o":{"a":0,"k":100},"r":{"a":0,"k":0},"a":{"a":0,"k":[25,25,0]},"s":{"a":0,"k":[100,100,100]},
        "p":{"a":1,"k":[{"t":0,"s":[25,50,0],"i":{"x":[1],"y":[1]},"o":{"x":[0],"y":[0]}},{"t":60,"s":[175,50,0]}]}}}]}
        """

        func testACSSAnimationIsWhereItsClockSays() async throws {
            let player = HmmWebPlayer(piece: HmmWebPiece(kind: .html, source: .inline(Self.slide), width: 240, height: 40))
            let half = try await XCTUnwrapAsync(player.image(atFrame: 30))
            let left = try XCTUnwrap(Self.firstColumn(in: half) { $0.r > 200 && $0.g < 60 })
            XCTAssertEqual(Double(left), 100, accuracy: 3, "halfway through a 200 px slide; errors: \(player.errors)")
        }

        func testAnimationFramesRunOnTheClock() async throws {
            let player = HmmWebPlayer(piece: HmmWebPiece(kind: .html, source: .inline(Self.frames), width: 240, height: 40))
            let second = try await XCTUnwrapAsync(player.image(atFrame: 60))
            let left = try XCTUnwrap(Self.firstColumn(in: second) { $0.g > 200 && $0.r < 60 })
            XCTAssertEqual(Double(left), 100, accuracy: 2, "performance.now() is 1000 at one second; errors: \(player.errors)")
        }

        func testAMomentIsTheSameHoweverItIsReached() async throws {
            let piece = HmmWebPiece(kind: .html, source: .inline(Self.three), width: 240, height: 120)
            let straight = HmmWebPlayer(piece: piece)
            let first = try await XCTUnwrapAsync(straight.image(atFrame: 45))
            let wandering = HmmWebPlayer(piece: piece)
            _ = await wandering.image(atFrame: 10)
            _ = await wandering.image(atFrame: 100)
            let again = try await XCTUnwrapAsync(wandering.image(atFrame: 45))
            XCTAssertEqual(Self.pixels(first), Self.pixels(again), "errors: \(straight.errors) \(wandering.errors)")
            let blue = Self.firstColumn(in: first) { $0.b > 200 && $0.r < 60 }
            XCTAssertNotNil(blue, "three.js drew with WebGL from the carried copy; errors: \(straight.errors)")
        }

        func testAScriptAddedFirstReadsThePageAtAFrame() async throws {
            // three.js tells `__THREE_DEVTOOLS__` about every scene it makes: a script added before the page's own sees it.
            let hook = "window.__seen = []; window.__THREE_DEVTOOLS__ = new EventTarget();"
                + "__THREE_DEVTOOLS__.addEventListener('observe', e => { if (e.detail.isScene) __seen.push(e.detail); });"
            let player = HmmWebPlayer(piece: HmmWebPiece(kind: .html, source: .inline(Self.three), width: 240, height: 120), scripts: [hook])
            let x = await player.evaluate("return window.__seen[0].children[0].position.x;", atFrame: 60)
            XCTAssertEqual((x as? NSNumber)?.doubleValue ?? .nan, -0.5, accuracy: 0.02, "one second in; errors: \(player.errors)")
            let earlier = await player.evaluate("return window.__seen.length;", atFrame: 30)
            XCTAssertEqual((earlier as? NSNumber)?.intValue, 1, "going back starts the page over, with the script again")
        }

        func testALottieFileTurnsOnTheClock() async throws {
            let player = HmmWebPlayer(piece: HmmWebPiece(kind: .lottie, source: .inline(Self.lottie), width: 200, height: 100))
            let half = try await XCTUnwrapAsync(player.image(atFrame: 30))
            let left = try XCTUnwrap(Self.firstColumn(in: half) { $0.r > 200 && $0.g < 60 })
            XCTAssertEqual(Double(left), 75, accuracy: 3, "the 50 px square's middle runs 25 → 175; errors: \(player.errors)")
        }

        func testNothingReachesTheNetwork() async throws {
            let page = """
            <!doctype html><html><body style="margin:0"><canvas id="c" width="40" height="40"></canvas><script>
            let state = 'waiting';
            fetch('https://example.com/').then(() => { state = 'reached'; }, () => { state = 'blocked'; });
            const g = document.getElementById('c').getContext('2d');
            function draw() { g.fillStyle = state === 'blocked' ? '#00ff00' : (state === 'reached' ? '#ff0000' : '#0000ff');
              g.fillRect(0, 0, 40, 40); requestAnimationFrame(draw); }
            requestAnimationFrame(draw);
            </script></body></html>
            """
            let player = HmmWebPlayer(piece: HmmWebPiece(kind: .html, source: .inline(page), width: 40, height: 40))
            var colour = Pixel(r: 0, g: 0, b: 0, a: 0)
            for frame in 1 ... 40 {
                let image = try await XCTUnwrapAsync(player.image(atFrame: frame))
                colour = Self.pixel(image, x: 10, y: 10)
                if colour.b < 200 { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertGreaterThan(colour.g, 200, "the fetch failed (red: it reached the network, blue: still waiting)")
        }

        func testTheFramesCacheServesTheStageAndTheExportAlike() async throws {
            let piece = HmmWebPiece(kind: .html, source: .inline(Self.slide), width: 240, height: 40)
            let stage = HmmWebFrames()
            let export = HmmWebFrames()
            XCTAssertNil(stage.frameNow("a", piece: piece, frame: 20), "nothing drawn yet")
            let exported = try await XCTUnwrapAsync(export.frame("a", piece: piece, frame: 20))
            let shown = try await XCTUnwrapAsync(stage.frame("a", piece: piece, frame: 20))
            XCTAssertEqual(Self.pixels(exported), Self.pixels(shown))
            XCTAssertNotNil(stage.frameNow("a", piece: piece, frame: 20))
        }

        // MARK: Pixels

        struct Pixel: Equatable {
            var r: UInt8, g: UInt8, b: UInt8, a: UInt8
        }

        static func pixels(_ image: CGImage) -> [UInt8] {
            let width = image.width, height = image.height
            var data = [UInt8](repeating: 0, count: width * height * 4)
            let space = CGColorSpaceCreateDeviceRGB()
            data.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            return data
        }

        static func pixel(_ image: CGImage, x: Int, y: Int) -> Pixel {
            let data = pixels(image)
            let index = (y * image.width + x) * 4
            return Pixel(r: data[index], g: data[index + 1], b: data[index + 2], a: data[index + 3])
        }

        /// The first column (in CSS pixels, from the left) holding a pixel that passes `test`.
        static func firstColumn(in image: CGImage, _ test: (Pixel) -> Bool) -> Int? {
            let data = pixels(image)
            for x in 0 ..< image.width {
                for y in 0 ..< image.height {
                    let index = (y * image.width + x) * 4
                    if test(Pixel(r: data[index], g: data[index + 1], b: data[index + 2], a: data[index + 3])) { return x }
                }
            }
            return nil
        }
    }

    func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
        try XCTUnwrap(value, file: file, line: line)
    }
#endif
