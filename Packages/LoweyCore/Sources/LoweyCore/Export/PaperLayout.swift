import Foundation

/// Paper sizes, in points (portrait).
public enum PaperSize: String, CaseIterable, Sendable, Identifiable, Codable {
    case a4, letter, a3

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .a4: "A4"
        case .letter: "US Letter"
        case .a3: "A3"
        }
    }

    public var points: (width: Double, height: Double) {
        switch self {
        case .a4: (595.28, 841.89)
        case .letter: (612, 792)
        case .a3: (841.89, 1190.55)
        }
    }

    /// The page turned to suit a picture of this shape (landscape for a wide one).
    public func page(for aspect: Double) -> (width: Double, height: Double) {
        let size = points
        return aspect >= 1 ? (size.height, size.width) : size
    }
}

/// Export ▸ Paper (A1): the frame at the playhead on a page, or frames across the shot on one sheet, each picture as big
/// as the page allows with the project's name and the artist's.
public enum PaperLayout {
    static let margin = 36.0

    /// One picture filling the page inside its margins, with the title and a caption under it.
    public static func frame(_ picture: PDFWriter.Picture, paper: PaperSize, title: String, caption: String,
                             author: String? = nil) -> Data {
        let aspect = Double(picture.width) / Double(max(picture.height, 1))
        let page = paper.page(for: aspect)
        let room = (width: page.width - margin * 2, height: page.height - margin * 2 - 40)
        let (width, height) = fit(aspect, into: room)
        let x = (page.width - width) / 2
        let y = margin + 40 + (room.height - height) / 2
        let items: [PDFWriter.Item] = [
            .picture(picture, x: x, y: y, width: width, height: height),
            .text(title, x: margin, y: margin + 18, size: 12, bold: true),
            .text(byline(caption, author: author), x: margin, y: margin + 4, size: 9, grey: 0.4)
        ]
        return PDFWriter(pages: [PDFWriter.Page(width: page.width, height: page.height, items: items)], title: title, author: author).data()
    }

    /// Frames across the shot, read left to right and down: `columns` across (3 by default), as many rows as fit a
    /// landscape page, then the next page. Each one is framed and marked with its moment.
    public static func frames(_ frames: [(picture: PDFWriter.Picture, time: Double)], paper: PaperSize, title: String,
                              author: String? = nil, columns: Int = 3) -> Data {
        guard let first = frames.first else { return PDFWriter(pages: [], title: title, author: author).data() }
        let page = paper.page(for: 2)
        let gap = 14.0
        let top = 26.0
        let aspect = Double(first.picture.width) / Double(max(first.picture.height, 1))
        let cellWidth = (page.width - margin * 2 - gap * Double(columns - 1)) / Double(columns)
        let cellHeight = cellWidth / aspect + 16
        let rows = max(Int((page.height - margin * 2 - top + gap) / (cellHeight + gap)), 1)
        var pages: [PDFWriter.Page] = []
        for start in stride(from: 0, to: frames.count, by: rows * columns) {
            var items: [PDFWriter.Item] = [.text(title, x: margin, y: page.height - margin - 12, size: 14, bold: true)]
            if let author { items.append(.text(author, x: page.width - margin - Double(author.count) * 5, y: page.height - margin - 12, size: 9, grey: 0.4)) }
            for (offset, frame) in frames[start ..< min(start + rows * columns, frames.count)].enumerated() {
                let x = margin + Double(offset % columns) * (cellWidth + gap)
                let y = page.height - margin - top - Double(offset / columns + 1) * (cellHeight + gap) + gap
                let height = cellWidth / aspect
                items.append(.picture(frame.picture, x: x, y: y + 16, width: cellWidth, height: height))
                items.append(.frame(x: x, y: y + 16, width: cellWidth, height: height))
                items.append(.text("\(start + offset + 1)   \(timecode(frame.time))", x: x, y: y + 4, size: 8, grey: 0.35))
            }
            pages.append(PDFWriter.Page(width: page.width, height: page.height, items: items))
        }
        return PDFWriter(pages: pages, title: title, author: author).data()
    }

    /// The moments a sheet shows: `count` evenly across `range`, the first at its start.
    public static func moments(_ count: Int, across range: TimeRange) -> [Double] {
        guard count > 1 else { return [range.start] }
        return (0 ..< count).map { range.start + range.duration * Double($0) / Double(count - 1) }
    }

    static func fit(_ aspect: Double, into room: (width: Double, height: Double)) -> (Double, Double) {
        room.width / aspect <= room.height ? (room.width, room.width / aspect) : (room.height * aspect, room.height)
    }

    static func byline(_ caption: String, author: String?) -> String {
        [caption, author.map { "by \($0)" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  ")
    }

    /// "0:03.20": minutes, seconds and hundredths.
    public static func timecode(_ time: Double) -> String {
        let hundredths = Int((max(time, 0) * 100).rounded())
        return String(format: "%d:%02d.%02d", hundredths / 6000, hundredths / 100 % 60, hundredths % 100)
    }
}
