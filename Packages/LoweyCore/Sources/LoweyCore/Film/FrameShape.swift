import Foundation

/// The shape of the picture (F1): what the Director view frames, what Frame shot composes for and what every export
/// that renders comes out as. The scene's timeline keeps it (`Timeline.frame`), so the edit and its shape travel together.
public enum FrameShape: String, CaseIterable, Sendable, Identifiable, Codable {
    case landscape = "16:9"
    case cinema = "2.39:1"
    case portrait = "9:16"
    case vertical = "4:5"
    case square = "1:1"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .landscape: "16:9 (video)"
        case .cinema: "2.39:1 (cinema)"
        case .portrait: "9:16 (Reels, Shorts)"
        case .vertical: "4:5 (feed)"
        case .square: "1:1"
        }
    }

    /// Width over height.
    public var aspect: Double {
        switch self {
        case .landscape: 16.0 / 9.0
        case .cinema: 2.39
        case .portrait: 9.0 / 16.0
        case .vertical: 4.0 / 5.0
        case .square: 1
        }
    }

    /// Pixel size with the long side = `longSide` (always even, as encoders need).
    public func pixelSize(longSide: Int) -> (width: Int, height: Int) {
        let even = { (value: Int) in max(value - value % 2, 2) }
        let long = even(longSide)
        let short = even(Int((Double(longSide) / max(aspect, 1 / aspect)).rounded()))
        return aspect >= 1 ? (long, short) : (short, long)
    }

    /// The frame drawn over the stage for this shape (what you see is what you export).
    public func guideRect(in size: CGSize) -> CGRect {
        let target = CGFloat(aspect)
        var width = size.width * 0.86
        var height = width / target
        if height > size.height * 0.8 {
            height = size.height * 0.8
            width = height * target
        }
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }
}

public extension Timeline {
    /// The picture's shape (16:9 when never chosen).
    var frameShape: FrameShape { frame ?? .landscape }
}
