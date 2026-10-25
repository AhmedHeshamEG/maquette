import Foundation

/// A web piece (schema 25): an HTML page, a three.js scene or a Lottie file, played on a card in the scene (a screen on
/// a wall, a floating panel) or over the frame (a title, a chart). The page runs sandboxed with no network on a clock the
/// timeline steps, 60 frames a second from its start, so scrubbing, the stage and an export show the same frame.
public struct WebPiece: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        /// A page: HTML, CSS and JavaScript (three.js, an HTML animation timed to the clock, anything a browser plays).
        case html
        /// A Lottie animation (Bodymovin JSON).
        case lottie
    }

    public var kind: Kind
    /// The page's (or the Lottie file's) whole text, kept in the project (what the bridge writes).
    public var source: String?
    /// Or a file or folder inside the project's `assets/` folder: a `.html`, a folder with its page, a Lottie `.json`.
    public var file: String?
    /// The page to open inside a folder (`index.html` when nil).
    public var entry: String?
    /// The page's size in CSS pixels (what `innerWidth` and `innerHeight` read).
    public var width: Int
    public var height: Int
    /// Timeline time (s) of the piece's first frame. Before it, the piece shows that first frame.
    public var start: Double
    /// How long it plays (s); after it, it holds its last frame or loops. Nil: it runs as long as the timeline.
    public var duration: Double?
    public var loop: Bool?

    public init(kind: Kind = .html, source: String? = nil, file: String? = nil, entry: String? = nil, width: Int = 1280,
                height: Int = 720, start: Double = 0, duration: Double? = nil, loop: Bool? = nil) {
        self.kind = kind
        self.source = source
        self.file = file
        self.entry = entry
        self.width = width
        self.height = height
        self.start = start
        self.duration = duration
        self.loop = loop
    }

    /// The largest page we draw (pixels a side): a piece is drawn at its own size, so a 4K film upsamples it.
    public static let largest = 3840

    /// Width ÷ height.
    public var aspect: Double {
        Double(max(width, 1)) / Double(max(height, 1))
    }

    /// The width and height kept within 16…`largest`, shape kept.
    public var clampedSize: (width: Int, height: Int) {
        let scale = min(1, Double(Self.largest) / Double(max(width, height, 1)))
        return (max(Int((Double(width) * scale).rounded()), 16), max(Int((Double(height) * scale).rounded()), 16))
    }

    /// The piece's frame at timeline `time` (60 a second from `start`; held or looped after `duration`).
    public func frame(at time: Double) -> Int {
        let step = 1.0 / Double(WebFrameKey.framesPerSecond)
        var local = max(time - start, 0)
        if let duration, duration > step {
            local = loop == true ? local.truncatingRemainder(dividingBy: duration) : min(local, duration - step)
        }
        return Int((max(local, 0) / step + 1e-6).rounded(.down))
    }

    /// The kind a file name suggests: `.json` and `.lottie` are Lottie, everything else a page.
    public static func kind(forFile name: String) -> Kind {
        let ext = (name as NSString).pathExtension.lowercased()
        return ext == "json" || ext == "lottie" ? .lottie : .html
    }

    /// Whether it has something to play.
    public var isPlayable: Bool {
        !(source ?? "").isEmpty || !(file ?? "").isEmpty
    }
}

/// Names a web piece's frame so it can be fetched like any picture: "web:<object id>#f=<frame>". The object's piece says
/// what to draw; the frame, which moment.
public enum WebFrameKey {
    public static let framesPerSecond = 60
    private static let prefix = "web:"

    public static func make(object: ObjectID, frame: Int) -> String {
        "\(prefix)\(object.raw)#f=\(max(frame, 0))"
    }

    public static func parse(_ key: String) -> (object: ObjectID, frame: Int)? {
        guard key.hasPrefix(prefix), let range = key.range(of: "#f=", options: .backwards), let frame = Int(key[range.upperBound...]) else {
            return nil
        }
        return (ObjectID(raw: String(key[key.index(key.startIndex, offsetBy: prefix.count) ..< range.lowerBound])), frame)
    }
}

public extension Scene {
    /// The web piece an object plays (on a card or over the frame), if any.
    func webPiece(_ id: ObjectID) -> WebPiece? {
        switch objects[id]?.kind {
        case let .card(recipe): recipe.web
        case let .overlay(recipe): recipe.web
        default: nil
        }
    }

    /// Every object playing a web piece.
    var webPieceIDs: [ObjectID] {
        orderedIDs().filter { webPiece($0) != nil }
    }
}
