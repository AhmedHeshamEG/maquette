#if canImport(UIKit) && canImport(WebKit)
    import Foundation
    import WebKit

    /// Serves a piece on `hmm-web://`: `piece/…` is the page and the files beside it (rewritten to play offline),
    /// `lib/…` the libraries the kit carries. Nothing else answers, so nothing outside the piece can be read.
    final class HmmWebSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
        private let piece: HmmWebPiece
        private let lock = NSLock()
        private var stopped = Set<ObjectIdentifier>()

        init(piece: HmmWebPiece) {
            self.piece = piece
        }

        /// The address the player opens.
        static func entryURL(for piece: HmmWebPiece) -> URL {
            let entry = switch piece.source {
            case .inline: "index.html"
            case let .folder(_, entry): entry.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entry
            }
            return URL(string: HmmWebPage.pageRoot + entry) ?? URL(fileURLWithPath: "/")
        }

        func reset() {
            lock.withLock { stopped.removeAll() }
        }

        func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
            guard let url = urlSchemeTask.request.url, let (data, type) = response(for: url) else {
                urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            let headers = ["Content-Type": type, "Content-Length": "\(data.count)", "Access-Control-Allow-Origin": "*", "Cache-Control": "no-store"]
            guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers),
                  !isStopped(urlSchemeTask) else { return }
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        }

        func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
            _ = lock.withLock { stopped.insert(ObjectIdentifier(urlSchemeTask)) }
        }

        private func isStopped(_ task: any WKURLSchemeTask) -> Bool {
            lock.withLock { stopped.contains(ObjectIdentifier(task)) }
        }

        // MARK: Files

        func response(for url: URL) -> (Data, String)? {
            let path = url.path.removingPercentEncoding ?? url.path
            let relative = String(path.drop(while: { $0 == "/" }))
            switch url.host {
            case "lib": return library(relative)
            case "piece": return pieceFile(relative)
            default: return nil
            }
        }

        private func library(_ relative: String) -> (Data, String)? {
            guard let root = HmmWebPage.libraryFolder,
                  let file = Self.inside(root, relative), let data = try? Data(contentsOf: file) else { return nil }
            return (data, Self.type(of: file.lastPathComponent))
        }

        private func pieceFile(_ relative: String) -> (Data, String)? {
            switch piece.source {
            case let .inline(text):
                guard relative == "index.html" || relative.isEmpty else { return nil }
                return (Data(page(text).utf8), "text/html; charset=utf-8")
            case let .folder(root, entry):
                guard let file = Self.inside(root, relative), let data = try? Data(contentsOf: file) else { return nil }
                let isEntry = relative == entry
                if isEntry || file.pathExtension.lowercased() == "html" || file.pathExtension.lowercased() == "htm" {
                    let text = String(decoding: data, as: UTF8.self)
                    return (Data((isEntry ? page(text) : HmmWebPage.prepare(text)).utf8), "text/html; charset=utf-8")
                }
                if ["js", "mjs"].contains(file.pathExtension.lowercased()) {
                    return (Data(HmmWebPage.rewriteLibraries(String(decoding: data, as: UTF8.self)).utf8), "text/javascript; charset=utf-8")
                }
                return (data, Self.type(of: file.lastPathComponent))
            }
        }

        private func page(_ text: String) -> String {
            piece.kind == .lottie ? HmmWebPage.lottieHost(json: text) : HmmWebPage.prepare(text)
        }

        /// `relative` inside `root`, never outside it (no `..` out of the folder, no links out of it).
        static func inside(_ root: URL, _ relative: String) -> URL? {
            let base = root.standardizedFileURL.resolvingSymlinksInPath()
            let file = base.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
            let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
            guard file.path.hasPrefix(prefix) else { return nil }
            return file
        }

        static func type(of name: String) -> String {
            switch (name as NSString).pathExtension.lowercased() {
            case "html", "htm": "text/html; charset=utf-8"
            case "js", "mjs": "text/javascript; charset=utf-8"
            case "css": "text/css; charset=utf-8"
            case "json", "lottie": "application/json"
            case "svg": "image/svg+xml"
            case "png": "image/png"
            case "jpg", "jpeg": "image/jpeg"
            case "webp": "image/webp"
            case "gif": "image/gif"
            case "glb": "model/gltf-binary"
            case "gltf": "model/gltf+json"
            case "wasm": "application/wasm"
            case "woff2": "font/woff2"
            case "woff": "font/woff"
            case "ttf", "otf": "font/ttf"
            case "mp4", "m4v": "video/mp4"
            case "mov": "video/quicktime"
            case "mp3": "audio/mpeg"
            case "wav": "audio/wav"
            default: "application/octet-stream"
            }
        }
    }
#endif
