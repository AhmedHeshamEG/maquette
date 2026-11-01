import Foundation

/// What a web piece is made of: an HTML page (a three.js scene, an HTML animation timed by JavaScript or CSS) or a
/// Lottie file. A page can be inline (one file of HTML) or a folder with its `index.html` and the files it loads.
public struct HmmWebPiece: Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case html, lottie
    }

    public enum Source: Hashable, Sendable {
        /// The page's (or the Lottie file's) whole text.
        case inline(String)
        /// A folder, and the page inside it to open (`index.html`, or the Lottie `.json`).
        case folder(URL, entry: String)
    }

    public var kind: Kind
    public var source: Source
    /// The page's size in CSS pixels: what `innerWidth` and `innerHeight` read.
    public var width: Int
    public var height: Int

    public init(kind: Kind, source: Source, width: Int = 1280, height: Int = 720) {
        self.kind = kind
        self.source = source
        self.width = max(width, 16)
        self.height = max(height, 16)
    }

    /// The kind a file name suggests: `.json` and `.lottie` are Lottie, everything else a page.
    public static func kind(forFile name: String) -> Kind {
        let ext = (name as NSString).pathExtension.lowercased()
        return ext == "json" || ext == "lottie" ? .lottie : .html
    }
}

/// The piece's frames: a fixed step of 60 a second on its own clock, so every path to a moment (the stage, scrubbing,
/// an export) steps through the same frames from the start and draws the same picture.
public enum HmmWebTime {
    public static let framesPerSecond = 60

    /// The frame shown at `seconds` on the piece's clock.
    public static func frame(at seconds: Double) -> Int {
        Int((max(seconds, 0) * Double(framesPerSecond) + 1e-6).rounded(.down))
    }

    /// The moment a frame starts, in seconds.
    public static func seconds(ofFrame frame: Int) -> Double {
        Double(max(frame, 0)) / Double(framesPerSecond)
    }
}

/// Turns what an agent wrote into a page that runs with no network: libraries it fetched from a CDN come from the copies
/// inside the kit (three.js 0.170 and its addons, lottie-web 5.12), a bare `import "three"` finds them, and a content
/// policy keeps everything else out.
public enum HmmWebPage {
    /// The scheme the pages and the bundled libraries are served on.
    public static let scheme = "hmm-web"
    public static let pageRoot = "hmm-web://piece/"
    public static let libraryRoot = "hmm-web://lib/"
    public static let three = "hmm-web://lib/three/three.module.js"
    public static let threeAddons = "hmm-web://lib/three/addons/"
    public static let lottie = "hmm-web://lib/lottie.min.js"

    /// The carried libraries on disk.
    public static var libraryFolder: URL? {
        Bundle.module.resourceURL?.appendingPathComponent("Web/lib", isDirectory: true)
    }

    /// No fetch, socket or form leaves the page; the piece's own files, inline code, data and blob URLs do.
    public static let contentPolicy =
        "default-src hmm-web: data: blob: 'unsafe-inline' 'unsafe-eval'; connect-src hmm-web: data: blob:; form-action 'none'"

    /// The page, rewritten to play offline. `head` is added first in `<head>` (the clock is added by the player).
    public static func prepare(_ html: String) -> String {
        var page = rewriteLibraries(html)
        var head = "<meta http-equiv=\"Content-Security-Policy\" content=\"\(contentPolicy)\">"
        // Without one, WebKit lays a page out 980 px wide and shrinks it to fit: the piece's size is its CSS size.
        if page.range(of: "name=[\"']?viewport", options: [.regularExpression, .caseInsensitive]) == nil {
            head += "<meta name=\"viewport\" content=\"\(viewport)\">"
        }
        if page.range(of: "type=\"importmap\"", options: .caseInsensitive) == nil,
           page.range(of: "type='importmap'", options: .caseInsensitive) == nil {
            head += "<script type=\"importmap\">\(importMap)</script>"
        }
        return insertInHead(head, into: page, rewritten: &page)
    }

    public static let viewport = "width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"

    /// `three` and its addons by their bare names, as three.js's own examples import them.
    public static var importMap: String {
        "{\"imports\":{\"three\":\"\(three)\",\"three/addons/\":\"\(threeAddons)\",\"three/examples/jsm/\":\"\(threeAddons)\"}}"
    }

    /// A page that plays a Lottie file: lottie-web draws it as SVG, and the clock turns it to each frame.
    public static func lottieHost(json: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="\(viewport)">
        <meta http-equiv="Content-Security-Policy" content="\(contentPolicy)"><style>html,body{margin:0;width:100%;height:100%;overflow:hidden;\
        background:transparent}#a{width:100%;height:100%}</style><script src="\(lottie)"></script></head>
        <body><div id="a"></div><script>
        const data = \(json);
        const anim = lottie.loadAnimation({container: document.getElementById('a'), renderer: 'svg', loop: false,
          autoplay: false, animationData: data});
        __hmm.onFrame(t => anim.goToAndStop(Math.min(t * 1000, anim.getDuration(false) * 1000), false));
        </script></body></html>
        """
    }

    /// CDN addresses of the libraries we carry, swapped for the carried copies (any version: one copy serves them all).
    public static func rewriteLibraries(_ html: String) -> String {
        var text = html
        for (pattern, replacement) in libraryPatterns {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }
        return text
    }

    private static let cdn = #"https?://(?:unpkg\.com|cdn\.jsdelivr\.net/npm|esm\.sh|cdn\.skypack\.dev|ga\.jspm\.io/npm:)/?"#

    private static let libraryPatterns: [(String, String)] = [
        (cdn + #"three@[^/"'\s]*/build/three\.module(?:\.min)?\.js"#, three),
        (cdn + #"three@[^/"'\s]*/(?:examples/jsm|addons)/"#, threeAddons),
        (cdn + #"three@[^/"'\s]*/?(?=["'])"#, three),
        (#"https?://cdnjs\.cloudflare\.com/ajax/libs/three\.js/[^/"'\s]+/three\.module(?:\.min)?\.js"#, three),
        (cdn + #"(?:lottie-web|bodymovin)@[^/"'\s]*/build/player/lottie(?:_svg)?(?:\.min)?\.js"#, lottie),
        (#"https?://cdnjs\.cloudflare\.com/ajax/libs/(?:lottie-web|bodymovin)/[^/"'\s]+/lottie(?:_svg)?(?:\.min)?\.js"#, lottie)
    ]

    private static func insertInHead(_ head: String, into page: String, rewritten: inout String) -> String {
        if let open = page.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            rewritten.insert(contentsOf: head, at: open.upperBound)
        } else if let html = page.range(of: "<html[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            rewritten.insert(contentsOf: "<head>\(head)</head>", at: html.upperBound)
        } else {
            rewritten = "<!doctype html><html><head><meta charset=\"utf-8\">\(head)</head><body>\(page)</body></html>"
        }
        return rewritten
    }
}
