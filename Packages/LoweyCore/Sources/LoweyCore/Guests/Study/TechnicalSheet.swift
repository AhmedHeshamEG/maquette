import Foundation

/// The technical drawing a mechanics course asks for (G1, Study: Omar's report): the front, top and left views in
/// first-angle projection (ISO, the European convention) with hidden edges dashed and the overall sizes written on,
/// an isometric view of the assembly as it stands (exploded, if it is), a parts list with names, materials, counts and
/// masses, and a title block, on one landscape sheet at a standard scale.
public enum TechnicalSheet {
    public struct Part: Hashable, Sendable {
        public var name: String
        public var material: String
        /// Kilograms (nil when it can't be measured: an open surface).
        public var mass: Double?
        public var count: Int

        public init(name: String, material: String, mass: Double?, count: Int = 1) {
            self.name = name
            self.material = material
            self.mass = mass
            self.count = count
        }
    }

    /// The parts of a selection (each thing with a surface), alike ones counted together: material in words (a real
    /// thing's, else plastic, as printed parts are), mass from that material and the part's real volume.
    public static func parts(_ meshes: [(object: SceneObject, meshes: [ExportMesh])]) -> [Part] {
        var parts: [Part] = []
        for (object, pieces) in meshes where !pieces.isEmpty {
            let material = object.physics?.material ?? .plastic
            let volume = pieces.reduce(0.0) { $0 + signedVolume($1) }
            let mass = object.physics?.mass ?? (volume > 1e-12 ? volume * material.density : nil)
            let part = Part(name: object.name, material: material.title, mass: mass)
            if let index = parts.firstIndex(where: { $0.name == part.name && $0.material == part.material }) {
                parts[index].count += 1
            } else {
                parts.append(part)
            }
        }
        return parts
    }

    /// The volume a closed mesh encloses, in the world (cubic metres).
    static func signedVolume(_ mesh: ExportMesh) -> Double {
        var total = 0.0
        let positions = mesh.mesh.positions.map { mesh.transform.apply(to: Vec3(Double($0.x), Double($0.y), Double($0.z))) }
        for start in stride(from: 0, to: mesh.mesh.indices.count - 2, by: 3) {
            let a = positions[Int(mesh.mesh.indices[start])], b = positions[Int(mesh.mesh.indices[start + 1])]
            let c = positions[Int(mesh.mesh.indices[start + 2])]
            total += a.dot(b.cross(c)) / 6
        }
        return abs(total)
    }

    public struct Sheet: Sendable {
        public var title: String
        public var author: String?
        public var date: Date
        public var units: LengthUnit
        public var paper: PaperSize

        public init(title: String, author: String? = nil, date: Date = Date(), units: LengthUnit = .millimetre, paper: PaperSize = .a4) {
            self.title = title
            self.author = author
            self.date = date
            self.units = units
            self.paper = paper
        }
    }

    /// The sheet as a PDF. `soup` is the assembly as it stands now; `whole` the same put together (the three views
    /// show the parts in place even when the picture shows them exploded).
    public static func pdf(assembly soup: TriangleSoup, whole: TriangleSoup? = nil, parts: [Part], sheet: Sheet) -> Data {
        let (pageWidth, pageHeight) = sheet.paper.page(for: 2)
        let mm = 25.4 / 72
        let width = pageWidth * mm, height = pageHeight * mm
        let margin = 10.0, column = 100.0
        let together = whole ?? soup
        let options = HiddenLines.Options(hidden: true)
        let front = HiddenLines.draw(together, view: .front, options: options)
        let top = HiddenLines.draw(together, view: .top, options: options)
        let side = HiddenLines.draw(together, view: .left, options: options)
        let iso = HiddenLines.draw(soup, view: .isometric, options: HiddenLines.Options(hidden: false))
        // Four cells left of the parts list: front, the left view to its right, the top view under the front, the
        // isometric view under the left view.
        let area = (x: margin + 4, y: margin + 4, w: width - margin * 2 - column - 12, h: height - margin * 2 - 8)
        let cell = Vec2(area.w / 2, area.h / 2)
        let room = cell - Vec2(24, 24)
        let sizes = [front, top, side].compactMap(\.bounds).map { Vec2($0.max.x - $0.min.x, $0.max.y - $0.min.y) }
        let scale = sizes.map { PaperPlacement.fitting($0, into: room) }.min() ?? 1
        var items: [PDFWriter.Item] = [.path([rectangle(margin, margin, width - margin * 2, height - margin * 2).map(points)], closed: true,
                                             width: 0.7 / mm, grey: 0)]
        let cells = [(front, Vec2(area.x, area.y + cell.y), true), (side, Vec2(area.x + cell.x, area.y + cell.y), false),
                     (top, Vec2(area.x, area.y), false)]
        for (art, corner, isFront) in cells {
            items += view(art, scale: scale, corner: corner, cell: cell, units: sheet.units, heightToo: isFront)
        }
        if let bounds = iso.bounds {
            let size = Vec2(bounds.max.x - bounds.min.x, bounds.max.y - bounds.min.y)
            let fit = PaperPlacement.fitting(size, into: room)
            let used = size * (fit * 1000)
            let at = Vec2(area.x + cell.x + (cell.x - used.x) / 2, area.y + (cell.y - used.y) / 2)
            items += iso.pdfItems(PaperPlacement(scale: fit, origin: bounds.min, at: at))
        }
        let right = width - margin - column
        items += titleBlock(sheet, scale: scale, at: Vec2(right, margin), width: column)
        items += partsList(parts, at: Vec2(right, margin + 34), width: column)
        return PDFWriter(pages: [PDFWriter.Page(width: pageWidth, height: pageHeight, items: items)], title: sheet.title, author: sheet.author).data()
    }

    /// A view centred in its cell with its overall width written under it (and its height beside it).
    static func view(_ art: LineArt, scale: Double, corner: Vec2, cell: Vec2, units: LengthUnit, heightToo: Bool) -> [PDFWriter.Item] {
        guard let bounds = art.bounds else { return [] }
        let size = Vec2(bounds.max.x - bounds.min.x, bounds.max.y - bounds.min.y)
        let used = size * (scale * 1000)
        let at = Vec2(corner.x + (cell.x - used.x) / 2, corner.y + (cell.y - used.y) / 2)
        var drawing = art
        let gap = 7 / (scale * 1000)
        drawing.append(LineArt.dimension(from: Vec2(bounds.max.x, bounds.min.y), to: bounds.min, offset: gap,
                                         text: units.format(size.x)))
        if heightToo {
            drawing.append(LineArt.dimension(from: bounds.min, to: Vec2(bounds.min.x, bounds.max.y), offset: gap,
                                             text: units.format(size.y)))
        }
        return drawing.pdfItems(PaperPlacement(scale: scale, origin: bounds.min, at: at))
    }

    /// The title block: the drawing's name, who drew it and when, its scale and units, and the projection used.
    static func titleBlock(_ sheet: Sheet, scale: Double, at corner: Vec2, width: Double) -> [PDFWriter.Item] {
        let height = 30.0
        let pt = 72 / 25.4
        var items: [PDFWriter.Item] = [.path([rectangle(corner.x, corner.y, width, height).map(points)], closed: true, width: 0.5, grey: 0)]
        items.append(.path([[Vec2(corner.x, corner.y + 18), Vec2(corner.x + width, corner.y + 18)].map(points)], closed: false, width: 0.35))
        items.append(.text(sheet.title, x: (corner.x + 3) * pt, y: (corner.y + 22) * pt, size: 12, bold: true))
        let date = ISO8601DateFormatter.string(from: sheet.date, timeZone: TimeZone(secondsFromGMT: 0) ?? .current,
                                               formatOptions: [.withFullDate])
        let lines = [
            ("Drawn by", sheet.author ?? "—"), ("Date", date), ("Scale", PaperPlacement.title(of: scale)),
            ("Units", sheet.units.label), ("Projection", "First angle (ISO)")
        ]
        for (index, (label, value)) in lines.enumerated() {
            let x = corner.x + 3 + Double(index % 3) * (width / 3), y = corner.y + 12 - Double(index / 3) * 8
            items.append(.text(label, x: x * pt, y: (y + 3) * pt, size: 6, grey: 0.45))
            items.append(.text(value, x: x * pt, y: (y - 0.5) * pt, size: 8))
        }
        return items
    }

    /// The parts list, numbered from the bottom up as drawings number it, with its heading on top.
    static func partsList(_ parts: [Part], at corner: Vec2, width: Double) -> [PDFWriter.Item] {
        let pt = 72 / 25.4
        let row = 6.0
        let columns: [(String, Double)] = [("No.", 0.09), ("Name", 0.33), ("Material", 0.24), ("Qty", 0.1), ("Mass", 0.24)]
        var items: [PDFWriter.Item] = []
        let rows = parts.count + 1
        for line in 0 ... rows {
            let y = corner.y + Double(line) * row
            items.append(.path([[Vec2(corner.x, y), Vec2(corner.x + width, y)].map(points)], closed: false, width: line == rows - 1 ? 0.5 : 0.25))
        }
        var x = corner.x
        for (_, share) in columns {
            items.append(.path([[Vec2(x, corner.y), Vec2(x, corner.y + Double(rows) * row)].map(points)], closed: false, width: 0.25))
            x += share * width
        }
        items.append(.path([[Vec2(corner.x + width, corner.y), Vec2(corner.x + width, corner.y + Double(rows) * row)].map(points)],
                           closed: false, width: 0.25))
        func cells(_ values: [String], line: Int, bold: Bool) {
            var x = corner.x
            for (index, value) in values.enumerated() {
                items.append(.text(value, x: (x + 1.5) * pt, y: (corner.y + Double(line) * row + 1.8) * pt, size: 7, bold: bold))
                x += columns[index].1 * width
            }
        }
        cells(columns.map(\.0), line: rows - 1, bold: true)
        for (index, part) in parts.enumerated() {
            cells(["\(index + 1)", part.name, part.material, "\(part.count)", part.mass.map(massText) ?? "—"], line: index, bold: false)
        }
        return items
    }

    /// "12.3 g", "1.25 kg".
    public static func massText(_ kilograms: Double) -> String {
        kilograms < 1 ? String(format: "%.1f g", kilograms * 1000) : String(format: "%.2f kg", kilograms)
    }

    static func rectangle(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> [Vec2] {
        [Vec2(x, y), Vec2(x + w, y), Vec2(x + w, y + h), Vec2(x, y + h)]
    }

    /// Millimetres on the page to PDF points.
    static func points(_ p: Vec2) -> Vec2 { Vec2(p.x * 72 / 25.4, p.y * 72 / 25.4) }
}
