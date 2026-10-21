import Foundation

/// A building drawn the way architects draw it (G1, Room): the plan (cut at 1.2 m above the floor, what's cut filled
/// black, what's below in thin lines, each room named with its area) and the four elevations (seen straight on, hidden
/// parts left out, a ground line under them). Black and white; drawing units are metres, north (−z) up a plan.
public enum PlanDrawing {
    public struct Options: Sendable {
        /// The floor the plan is of.
        public var floor: Double
        /// How far above the floor the plan cuts.
        public var cutHeight: Double
        /// Rooms named with their areas.
        public var rooms: Bool
        /// The unit lengths are written in.
        public var units: LengthUnit

        public init(floor: Double = 0, cutHeight: Double = 1.2, rooms: Bool = true, units: LengthUnit = .metre) {
            self.floor = floor
            self.cutHeight = cutHeight
            self.rooms = rooms
            self.units = units
        }
    }

    public enum Side: String, CaseIterable, Sendable {
        case north, east, south, west

        public var title: String {
            switch self {
            case .north: "North elevation"
            case .east: "East elevation"
            case .south: "South elevation"
            case .west: "West elevation"
            }
        }

        /// Seen from that side, looking at the building (north is −z).
        public var view: DrawingView {
            switch self {
            case .north: .back
            case .south: .front
            case .east: .right
            case .west: .left
            }
        }
    }

    /// A point of the world on the plan (x east, y north).
    public static func plan(_ point: Vec3) -> Vec2 { Vec2(point.x, -point.z) }

    /// The plan of the floor at `options.floor`. `enclosing` names the things that close rooms off (walls, columns);
    /// `labels` are names lying on the floor (a room takes the one inside it).
    public static func plan(_ soup: TriangleSoup, enclosing: Set<Int>? = nil, labels: [(text: String, at: Vec3)] = [],
                            options: Options = Options()) -> (art: LineArt, rooms: [RoomFinder.Room]) {
        let cut = options.floor + options.cutHeight
        var art = HiddenLines.draw(soup.below(cut), view: .top, options: HiddenLines.Options(outline: .thin, creasePen: .thin))
        for piece in Section.cut(soup, point: Vec3(0, cut, 0), normal: .unitY) where !piece.loops.isEmpty {
            let loops = piece.loops.map { $0.map(plan) }
            art.strokes.append(LineArt.Stroke(loops[0], closed: true, pen: .cut, filled: true, holes: Array(loops.dropFirst())))
        }
        let onFloor = labels.filter { $0.at.y >= options.floor - 0.05 && $0.at.y < options.floor + 2.4 }
        guard options.rooms else { return (art, []) }
        let rooms = RoomFinder.rooms(soup, floor: options.floor, enclosing: enclosing, labels: onFloor.map { ($0.text, plan($0.at)) })
        for room in rooms {
            art.labels.append(LineArt.Label(room.name, at: room.label + Vec2(0, 0.2), size: 3, bold: true))
            art.labels.append(LineArt.Label(area(room.area, units: options.units), at: room.label - Vec2(0, 0.25), size: 2.5))
        }
        return (art, rooms)
    }

    /// "12.4 m²", or square feet when the project works in feet or inches.
    public static func area(_ squareMetres: Double, units: LengthUnit) -> String {
        if units == .foot || units == .inch {
            return String(format: "%.0f sq ft", squareMetres / (0.3048 * 0.3048))
        }
        return String(format: "%.1f m²", squareMetres)
    }

    /// An elevation, with a heavy ground line across the foot of the building.
    public static func elevation(_ soup: TriangleSoup, side: Side, ground: Double = 0) -> LineArt {
        var art = HiddenLines.draw(soup, view: side.view)
        guard let bounds = art.bounds else { return art }
        let frame = side.view.frame
        let y = Vec3(0, ground, 0).dot(frame.up)
        let margin = (bounds.max.x - bounds.min.x) * 0.08 + 0.5
        art.strokes.append(LineArt.Stroke([Vec2(bounds.min.x - margin, y), Vec2(bounds.max.x + margin, y)], pen: .cut))
        return art
    }

    /// Plan and elevations on sheets: the plan alone on the first, the four elevations two by two on the second, each at
    /// the largest standard scale that fits, with its title and scale under it.
    public static func sheets(plan: LineArt, elevations: [(Side, LineArt)], paper: PaperSize, title: String, author: String?) -> Data {
        let (pageWidth, pageHeight) = paper.page(for: 2)
        let mm = 25.4 / 72
        let width = pageWidth * mm, height = pageHeight * mm
        let margin = 15.0, caption = 12.0
        var pages: [PDFWriter.Page] = []
        func place(_ art: LineArt, title: String, in box: (x: Double, y: Double, w: Double, h: Double)) -> [PDFWriter.Item] {
            guard let bounds = art.bounds else { return [] }
            let size = Vec2(bounds.max.x - bounds.min.x, bounds.max.y - bounds.min.y)
            let scale = PaperPlacement.fitting(size, into: Vec2(box.w, box.h - caption))
            let used = Vec2(size.x * scale * 1000, size.y * scale * 1000)
            let at = Vec2(box.x + (box.w - used.x) / 2, box.y + caption + (box.h - caption - used.y) / 2)
            let placement = PaperPlacement(scale: scale, origin: bounds.min, at: at)
            let ptPerMM = 72 / 25.4
            return art.pdfItems(placement) + [
                .text(title, x: box.x * ptPerMM, y: (box.y + 5) * ptPerMM, size: 10, bold: true),
                .text(PaperPlacement.title(of: scale), x: (box.x + 2) * ptPerMM + PDFWriter.textWidth(title, size: 10, bold: true),
                      y: (box.y + 5) * ptPerMM, size: 9, grey: 0.4)
            ]
        }
        func header(_ name: String) -> [PDFWriter.Item] {
            let ptPerMM = 72 / 25.4
            var items: [PDFWriter.Item] = [.text(name, x: margin * ptPerMM, y: (height - margin + 3) * ptPerMM, size: 12, bold: true)]
            if let author {
                let w = PDFWriter.textWidth(author, size: 9)
                items.append(.text(author, x: (width - margin) * ptPerMM - w, y: (height - margin + 3) * ptPerMM, size: 9, grey: 0.4))
            }
            return items
        }
        let inner = (x: margin, y: margin, w: width - margin * 2, h: height - margin * 2 - 6)
        pages.append(PDFWriter.Page(width: pageWidth, height: pageHeight, items: header(title) + place(plan, title: "Plan", in: inner)))
        if !elevations.isEmpty {
            var items = header(title)
            let cellW = inner.w / 2, cellH = inner.h / 2
            for (index, (side, art)) in elevations.prefix(4).enumerated() {
                let box = (x: inner.x + Double(index % 2) * cellW, y: inner.y + Double(1 - index / 2) * cellH, w: cellW - 6, h: cellH - 6)
                items += place(art, title: side.title, in: box)
            }
            pages.append(PDFWriter.Page(width: pageWidth, height: pageHeight, items: items))
        }
        return PDFWriter(pages: pages, title: title, author: author).data()
    }
}
