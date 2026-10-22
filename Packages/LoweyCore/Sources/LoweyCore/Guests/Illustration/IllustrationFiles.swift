import Foundation

/// Procreate's `.swatches` file (G1): a zip whose `Swatches.json` hmm-kit's `HmmPalette.procreate` reads.
public enum ProcreateSwatchesFile {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notSwatches

        public var description: String { "This isn't a Procreate palette (.swatches)." }
    }

    public static func json(_ data: Data) throws(Failure) -> Data {
        guard let entries = try? ZipReader.entries(data, including: { $0.hasSuffix("Swatches.json") }),
              let json = entries.first?.data else { throw .notSwatches }
        return json
    }
}

/// The frame's ink as vectors (G1, for illustrators: Ink lines as an SVG to colour under, at any size): what the
/// camera sees drawn as a draughtsman would (outlines heavier, creases lighter, hidden lines left out), in the frame's
/// pixels.
public enum InkVectors {
    public static func svg(_ soup: TriangleSoup, eye: Vec3, forward: Vec3, up: Vec3, fieldOfView: Double, width: Int, height: Int,
                           weight: Double = 3) -> String {
        let view = DrawingView.perspective(eye: eye, forward: forward, up: up, fieldOfView: fieldOfView, width: Double(width),
                                           height: Double(height))
        let art = HiddenLines.draw(soup, view: view, options: HiddenLines.Options(crease: 35, resolution: max(width, height)))
        var svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)">
          <g fill="none" stroke="#000000" stroke-linecap="round" stroke-linejoin="round">

        """
        for stroke in art.strokes where stroke.points.count >= 2 {
            let points = stroke.points.map { "\(LineArt.number($0.x)),\(LineArt.number(Double(height) - $0.y))" }.joined(separator: " ")
            let width = stroke.pen == .outline ? weight : weight * 0.55
            svg += "    <polyline points=\"\(points)\" stroke-width=\"\(LineArt.number(width))\"/>\n"
        }
        return svg + "  </g>\n</svg>\n"
    }
}
