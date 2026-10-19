import Foundation

/// Export ▸ Paper ▸ Storyboard (F1): one panel a shot, three across a landscape sheet, each with its number, the camera
/// and its lens, how long it lasts, what moves, and the words said over it. The pictures are the shots' key moments
/// (`Shot.keyMoment`), drawn by the engine; this is the sheet around them.
public enum Storyboard {
    public struct Panel: Hashable, Sendable {
        public var shot: Shot
        public var heading: String
        public var detail: String
        public var words: String
    }

    /// The panels for every shot of the scene (in `range`, the whole timeline by default).
    public static func panels(_ document: Document, range: TimeRange? = nil) -> [Panel] {
        let timeline = document.scene.timeline
        let words = timeline.words
        let camera = timeline.cuts.isEmpty ? document.scene.activeCamera : nil
        return timeline.shots(in: range).map { shot in
            let id = shot.camera ?? camera
            let object = id.flatMap { document.scene.objects[$0] }
            var heading = "Shot \(shot.index + 1)"
            if let object { heading += "  ·  \(object.name)" }
            var detail = [String(format: "%.1f s", shot.duration)]
            if let object {
                let sensor = CameraSensor.of(object)
                detail.append("\(Int(CameraLens(object).focalLength(on: sensor).rounded())) mm")
                let rig = CameraRig.of(object)
                if rig != .none { detail.append(rig.title.lowercased()) }
                if moves(object.id, in: timeline, during: shot) { detail.append("camera moves") }
            }
            let said = words.filter { $0.start >= shot.start - 1e-6 && $0.start < shot.end - 1e-6 }.map(\.text).joined(separator: " ")
            return Panel(shot: shot, heading: heading, detail: detail.joined(separator: "  ·  "), words: said)
        }
    }

    static func moves(_ camera: ObjectID, in timeline: Timeline, during shot: Shot) -> Bool {
        timeline.tracks.contains { track in
            track.target == camera && [.position, .rotation, .fieldOfView, .rigTravel, .rigLift, .rigSwing].contains(track.property)
                && track.keyframes.contains { $0.time > shot.start + 1e-6 && $0.time < shot.end - 1e-6 }
        }
    }

    /// The sheets: `pictures` in the panels' order (one each).
    public static func pdf(_ panels: [Panel], pictures: [PDFWriter.Picture], paper: PaperSize, title: String, author: String? = nil) -> Data {
        guard let first = pictures.first else { return PDFWriter(pages: [], title: title, author: author).data() }
        let page = paper.page(for: 2)
        let margin = 36.0
        let gap = 18.0
        let columns = 3
        let aspect = Double(first.width) / Double(max(first.height, 1))
        let cellWidth = (page.width - margin * 2 - gap * Double(columns - 1)) / Double(columns)
        let pictureHeight = cellWidth / aspect
        let textHeight = 46.0
        let cellHeight = pictureHeight + textHeight
        let top = 30.0
        let rows = max(Int((page.height - margin * 2 - top + gap) / (cellHeight + gap)), 1)
        var pages: [PDFWriter.Page] = []
        let perPage = rows * columns
        for start in stride(from: 0, to: min(panels.count, pictures.count), by: perPage) {
            var items: [PDFWriter.Item] = [.text(title, x: margin, y: page.height - margin - 12, size: 14, bold: true),
                                           .text("Storyboard  ·  \(start / perPage + 1)", x: page.width - margin - 110,
                                                 y: page.height - margin - 12, size: 9, grey: 0.4)]
            for offset in 0 ..< min(perPage, min(panels.count, pictures.count) - start) {
                let panel = panels[start + offset]
                let x = margin + Double(offset % columns) * (cellWidth + gap)
                let y = page.height - margin - top - Double(offset / columns + 1) * (cellHeight + gap) + gap
                items.append(.picture(pictures[start + offset], x: x, y: y + textHeight, width: cellWidth, height: pictureHeight))
                items.append(.frame(x: x, y: y + textHeight, width: cellWidth, height: pictureHeight))
                items.append(.text(panel.heading, x: x, y: y + textHeight - 12, size: 9, bold: true))
                items.append(.text(panel.detail, x: x, y: y + textHeight - 23, size: 7.5, grey: 0.4))
                for (index, line) in wrap(panel.words, width: cellWidth, size: 7.5).prefix(2).enumerated() {
                    items.append(.text(line, x: x, y: y + textHeight - 34 - Double(index) * 9, size: 7.5, grey: 0.15))
                }
            }
            pages.append(PDFWriter.Page(width: page.width, height: page.height, items: items))
        }
        return PDFWriter(pages: pages, title: title, author: author).data()
    }

    /// Lines of `text` that fit `width` points at `size` (Helvetica's average letter is about half its size); the last
    /// line ends with three dots when there's more.
    static func wrap(_ text: String, width: Double, size: Double, lines limit: Int = 2) -> [String] {
        let perLine = max(Int(width / (size * 0.5)), 8)
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ").map(String.init) {
            if current.isEmpty {
                current = word
            } else if current.count + 1 + word.count <= perLine {
                current += " " + word
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }
        guard lines.count > limit else { return lines }
        var kept = Array(lines.prefix(limit))
        kept[limit - 1] = String(kept[limit - 1].prefix(perLine - 3)) + "..." // Paper is Latin-1 (D-427)
        return kept
    }
}
