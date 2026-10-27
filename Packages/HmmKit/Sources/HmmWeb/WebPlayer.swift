#if canImport(UIKit) && canImport(WebKit)
    import UIKit
    import WebKit

    /// One web piece playing offscreen: a sandboxed `WKWebView` (no network, nothing kept) on the piece's own clock.
    /// `image(atFrame:)` steps the clock forward to that frame (or starts over from frame 0 to go back) and takes a picture.
    /// Every way to reach a frame runs the same steps from the start, so the stage and an export draw the same frame.
    @MainActor
    public final class HmmWebPlayer {
        /// The scene the offscreen windows join (the app sets it once; without one the window stands alone, as in tests).
        public static var windowScene: (@MainActor () -> UIWindowScene?)?

        public let piece: HmmWebPiece
        /// Scripts added to the page after the clock and before any of its own code (a recorder, a hook).
        public let scripts: [String]
        /// The frame the page is showing, or nil before it has loaded.
        public private(set) var frame: Int?
        /// What the page threw (kept for the bridge's report and the diagnostics).
        public private(set) var errors: [String] = []

        private var webView: WKWebView?
        private var window: UIWindow?
        private let handler: HmmWebSchemeHandler
        private let navigation = HmmWebNavigation()
        private var loading: Task<Bool, Never>?

        public init(piece: HmmWebPiece, scripts: [String] = []) {
            self.piece = piece
            self.scripts = scripts
            handler = HmmWebSchemeHandler(piece: piece)
        }

        /// The picture at `frame` (pixels = the piece's CSS size × `scale`), or nil if the page can't be shown.
        public func image(atFrame target: Int, scale: CGFloat = 1) async -> CGImage? {
            let target = max(target, 0)
            if let frame, target < frame { await reload() }
            guard await loaded() else { return nil }
            await step(to: target)
            guard frame == target else { return nil }
            return await snapshot(scale: scale)
        }

        /// What `body` (the body of an async JavaScript function) returns once the page shows `frame`, or nil if the page
        /// can't be shown or the code threw (kept in `errors`). Plain values only: numbers, strings, arrays, objects.
        public func evaluate(_ body: String, atFrame target: Int) async -> Any? {
            let target = max(target, 0)
            if let frame, target < frame { await reload() }
            guard await loaded() else { return nil }
            await step(to: target)
            guard frame == target, let webView else { return nil }
            do {
                return try await webView.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: .page)
            } catch {
                errors = Array((errors + [String(describing: error)]).suffix(20))
                return nil
            }
        }

        /// Drops the page (memory); the next picture loads it again.
        public func unload() {
            loading?.cancel()
            loading = nil
            webView?.removeFromSuperview()
            webView = nil
            window?.isHidden = true
            window = nil
            frame = nil
        }

        // MARK: Loading

        private func loaded() async -> Bool {
            if frame != nil { return true }
            if let loading { return await loading.value }
            let task = Task { await self.load() }
            loading = task
            let ok = await task.value
            loading = nil
            return ok
        }

        private func reload() async {
            unload()
            _ = await loaded()
        }

        private func load() async -> Bool {
            let view = await makeWebView()
            webView = view
            handler.reset()
            view.navigationDelegate = navigation
            let finished = await navigation.load(URLRequest(url: HmmWebSchemeHandler.entryURL(for: piece)), in: view)
            guard finished else {
                errors.append("the page didn't load")
                return false
            }
            do {
                let ready = try await view.callAsyncJavaScript(HmmWebClock.ready, arguments: [:], in: nil, contentWorld: .page)
                guard (ready as? Bool) == true || (ready as? NSNumber)?.boolValue == true else { return false }
            } catch {
                errors.append(String(describing: error))
                return false
            }
            frame = 0
            await collectErrors()
            return true
        }

        private func makeWebView() async -> WKWebView {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.setURLSchemeHandler(handler, forURLScheme: HmmWebPage.scheme)
            configuration.allowsInlineMediaPlayback = true
            configuration.mediaTypesRequiringUserActionForPlayback = []
            configuration.suppressesIncrementalRendering = true
            let content = WKUserContentController()
            content.addUserScript(WKUserScript(source: HmmWebClock.script, injectionTime: .atDocumentStart, forMainFrameOnly: false))
            for script in scripts {
                content.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            }
            if let rules = await Self.offline() { content.add(rules) }
            configuration.userContentController = content
            let size = CGRect(x: 0, y: 0, width: piece.width, height: piece.height)
            let view = WKWebView(frame: size, configuration: configuration)
            view.isOpaque = false
            view.backgroundColor = .clear
            view.scrollView.backgroundColor = .clear
            view.scrollView.isScrollEnabled = false
            view.scrollView.contentInsetAdjustmentBehavior = .never
            view.isUserInteractionEnabled = false
            host(view)
            return view
        }

        /// WebKit only paints a view that is in a window, so the page lives in a window of its own, off the screen's edge.
        /// Without a scene (tests, a background export) the view stands alone.
        private func host(_ view: WKWebView) {
            guard let scene = Self.windowScene?() else { return }
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: -CGFloat(piece.width) - 64, y: 0, width: CGFloat(piece.width), height: CGFloat(piece.height))
            window.windowLevel = UIWindow.Level(rawValue: -1000)
            window.isUserInteractionEnabled = false
            window.backgroundColor = .clear
            window.addSubview(view)
            window.isHidden = false
            self.window = window
        }

        // MARK: Frames

        private func step(to target: Int) async {
            guard let webView, var current = frame else { return }
            while current < target {
                let count = min(target - current, 120)
                do {
                    _ = try await webView.callAsyncJavaScript(HmmWebClock.step(count), arguments: [:], in: nil, contentWorld: .page)
                } catch {
                    // The page's process went away (memory): start over next time.
                    errors.append(String(describing: error))
                    unload()
                    return
                }
                current += count
            }
            frame = current
            await collectErrors()
        }

        private func snapshot(scale: CGFloat) async -> CGImage? {
            guard let webView else { return nil }
            let configuration = WKSnapshotConfiguration()
            configuration.afterScreenUpdates = true
            let screen = max(webView.window?.screen.scale ?? webView.traitCollection.displayScale, 1)
            configuration.snapshotWidth = NSNumber(value: Double(CGFloat(piece.width) * scale / screen))
            guard let image = try? await webView.takeSnapshot(configuration: configuration).cgImage else { return nil }
            return Self.sized(image, width: Int((CGFloat(piece.width) * scale).rounded()), height: Int((CGFloat(piece.height) * scale).rounded()))
        }

        /// The picture at exactly the size asked for (WebKit's own scale can differ a view without a screen).
        static func sized(_ image: CGImage, width: Int, height: Int) -> CGImage? {
            if image.width == width, image.height == height { return image }
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.interpolationQuality = .high
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return context?.makeImage()
        }

        private func collectErrors() async {
            guard let webView, let thrown = try? await webView.evaluateJavaScript("window.__hmm.errors.splice(0)") as? [String] else { return }
            errors = Array((errors + thrown).suffix(20))
        }

        // MARK: Offline

        private static var rules: WKContentRuleList?

        /// Blocks every http(s) and socket request (the content policy says the same inside the page).
        static func offline() async -> WKContentRuleList? {
            if let rules { return rules }
            let json = #"[{"trigger":{"url-filter":"^(https?|wss?|ftp)://"},"action":{"type":"block"}}]"#
            let store = WKContentRuleListStore.default()
            let list = try? await store?.compileContentRuleList(forIdentifier: "hmm-web-offline", encodedContentRuleList: json)
            rules = list
            return list
        }
    }

    /// Waits for a page's navigation to finish (or fail).
    @MainActor
    final class HmmWebNavigation: NSObject, WKNavigationDelegate {
        private var waiting: CheckedContinuation<Bool, Never>?

        func load(_ request: URLRequest, in view: WKWebView) async -> Bool {
            await withCheckedContinuation { continuation in
                waiting?.resume(returning: false)
                waiting = continuation
                view.load(request)
            }
        }

        private func finish(_ ok: Bool) {
            waiting?.resume(returning: ok)
            waiting = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finish(true)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(false)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            finish(false)
        }
    }
#endif
