import Foundation

/// Pixel-art rendering (K1 step 6): a frame brought down to a small grid of hard pixels: each pixel the colour most of its
/// block has (no blur), snapped to a small palette (the Look's, or one found in the picture), solid or clear with nothing
/// between, and a one-pixel outline around the shape. Crisp at any whole-number zoom, as 2D games show sprites.
public enum PixelArt {
    public struct Settings: Hashable, Sendable {
        /// How many pixels tall the result is.
        public var height: Int
        /// The colours it may use; empty finds up to `colours` in the picture.
        public var palette: [RGBA]
        public var colours: Int
        public var outline: RGBA?

        public init(height: Int = 64, palette: [RGBA] = [], colours: Int = 16, outline: RGBA? = RGBA.hex("#1A1418")) {
            self.height = height
            self.palette = palette
            self.colours = colours
            self.outline = outline
        }
    }

    public static func render(_ image: RGBAImage, settings: Settings) -> RGBAImage {
        let height = max(min(settings.height, image.height), 4)
        let width = max(Int((Double(image.width) * Double(height) / Double(max(image.height, 1))).rounded()), 1)
        var small = RGBAImage(width: width, height: height, color: RGBA(0, 0, 0, 0))
        for y in 0 ..< height {
            for x in 0 ..< width {
                if let colour = majority(image, x0: x * image.width / width, x1: max((x + 1) * image.width / width, x * image.width / width + 1),
                                         y0: y * image.height / height, y1: max((y + 1) * image.height / height, y * image.height / height + 1)) {
                    small.setPixel(x, y, colour)
                }
            }
        }
        let palette = settings.palette.isEmpty ? found(small, count: settings.colours) : settings.palette
        if !palette.isEmpty {
            for index in 0 ..< width * height where small.pixels[index * 4 + 3] > 0 {
                let colour = nearest(small.pixel(index % width, index / width), in: palette)
                small.setPixel(index % width, index / width, colour)
            }
        }
        if let outline = settings.outline { small = outlined(small, with: outline) }
        return small
    }

    /// The colour most of a block's solid pixels share (by a coarse key), or nil when most of it is clear.
    static func majority(_ image: RGBAImage, x0: Int, x1: Int, y0: Int, y1: Int) -> RGBA? {
        var counts: [Int: (count: Int, colour: RGBA)] = [:]
        var clear = 0
        for y in y0 ..< min(y1, image.height) {
            for x in x0 ..< min(x1, image.width) {
                let index = y * image.width + x
                guard image.pixels[index * 4 + 3] >= 128 else {
                    clear += 1
                    continue
                }
                let r = Int(image.pixels[index * 4]) >> 4, g = Int(image.pixels[index * 4 + 1]) >> 4, b = Int(image.pixels[index * 4 + 2]) >> 4
                let key = r << 8 | g << 4 | b
                counts[key] = ((counts[key]?.count ?? 0) + 1, counts[key]?.colour ?? image.pixel(x, y))
            }
        }
        let solid = counts.values.reduce(0) { $0 + $1.count }
        guard solid > clear, let best = counts.values.max(by: { $0.count < $1.count }) else { return nil }
        return RGBA(best.colour.r, best.colour.g, best.colour.b, 1)
    }

    /// Up to `count` colours that stand for the picture (median cut).
    static func found(_ image: RGBAImage, count: Int) -> [RGBA] {
        var colours: [RGBA] = []
        for index in 0 ..< image.width * image.height where image.pixels[index * 4 + 3] > 0 {
            colours.append(image.pixel(index % image.width, index / image.width))
        }
        guard !colours.isEmpty else { return [] }
        var boxes = [colours]
        while boxes.count < count, let widest = boxes.indices.max(by: { spread(boxes[$0]).width < spread(boxes[$1]).width }),
              boxes[widest].count > 1 {
            let box = boxes.remove(at: widest)
            let axis = spread(box).axis
            let sorted = box.sorted { channel($0, axis) < channel($1, axis) }
            boxes += [Array(sorted[..<(sorted.count / 2)]), Array(sorted[(sorted.count / 2)...])]
        }
        return boxes.map { box in
            let n = Double(box.count)
            return RGBA(box.reduce(0) { $0 + $1.r } / n, box.reduce(0) { $0 + $1.g } / n, box.reduce(0) { $0 + $1.b } / n, 1)
        }
    }

    static func channel(_ colour: RGBA, _ axis: Int) -> Double {
        axis == 0 ? colour.r : (axis == 1 ? colour.g : colour.b)
    }

    static func spread(_ colours: [RGBA]) -> (width: Double, axis: Int) {
        let widths = (0 ..< 3).map { axis in
            (colours.map { channel($0, axis) }.max() ?? 0) - (colours.map { channel($0, axis) }.min() ?? 0)
        }
        let axis = widths.indices.max { widths[$0] < widths[$1] } ?? 0
        return (widths[axis], axis)
    }

    static func nearest(_ colour: RGBA, in palette: [RGBA]) -> RGBA {
        palette.min { a, b in distance(a, colour) < distance(b, colour) } ?? colour
    }

    static func distance(_ a: RGBA, _ b: RGBA) -> Double {
        // Weighted for how eyes see (green counts most).
        let dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b
        return 0.3 * dr * dr + 0.59 * dg * dg + 0.11 * db * db
    }

    /// A one-pixel line around the shape, on the clear pixels that touch it (the picture grows a pixel each side).
    static func outlined(_ image: RGBAImage, with colour: RGBA) -> RGBAImage {
        var result = RGBAImage(width: image.width + 2, height: image.height + 2, color: RGBA(0, 0, 0, 0))
        result.blit(image, x: 1, y: 1)
        let solid = { (x: Int, y: Int) -> Bool in
            x >= 0 && y >= 0 && x < image.width && y < image.height && image.pixels[(y * image.width + x) * 4 + 3] > 0
        }
        for y in 0 ..< result.height {
            for x in 0 ..< result.width where !solid(x - 1, y - 1) {
                if solid(x - 2, y - 1) || solid(x, y - 1) || solid(x - 1, y - 2) || solid(x - 1, y) { result.setPixel(x, y, colour) }
            }
        }
        return result
    }
}
