import Foundation

/// The smallest PDF that prints anywhere (A1's Paper): pages of pictures (JPEG, embedded as they are) and lines of
/// text in Helvetica, one of the fonts every PDF reader has, so nothing is embedded but the pictures. Units are points
/// (1/72 inch), from the page's bottom-left corner. Text outside Latin-1 prints as "?".
public struct PDFWriter: Sendable {
    public struct Picture: Hashable, Sendable {
        /// The JPEG file's bytes.
        public var jpeg: Data
        /// Its size in pixels.
        public var width: Int
        public var height: Int

        public init(jpeg: Data, width: Int, height: Int) {
            self.jpeg = jpeg
            self.width = width
            self.height = height
        }
    }

    public enum Item: Hashable, Sendable {
        /// A picture filling a rectangle (x, y, width, height).
        case picture(Picture, x: Double, y: Double, width: Double, height: Double)
        /// A line of text whose baseline starts at (x, y); `grey` 0 is black.
        case text(String, x: Double, y: Double, size: Double, bold: Bool = false, grey: Double = 0)
        /// A hairline rectangle around (x, y, width, height).
        case frame(x: Double, y: Double, width: Double, height: Double, grey: Double = 0.75)
    }

    public struct Page: Hashable, Sendable {
        public var width: Double
        public var height: Double
        public var items: [Item]

        public init(width: Double, height: Double, items: [Item] = []) {
            self.width = width
            self.height = height
            self.items = items
        }
    }

    public var pages: [Page]
    public var title: String
    public var author: String?

    public init(pages: [Page], title: String, author: String? = nil) {
        self.pages = pages
        self.title = title
        self.author = author
    }

    /// The file.
    public func data() -> Data {
        var objects: [Data] = []
        func add(_ object: Data) -> Int {
            objects.append(object)
            return objects.count
        }
        let catalog = add(Data())
        let pagesObject = add(Data())
        let regular = add(Data("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>".utf8))
        let bold = add(Data("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>".utf8))
        var kids: [Int] = []
        for page in pages {
            var pictures: [Int] = []
            for case let .picture(picture, _, _, _, _) in page.items {
                pictures.append(add(Self.imageObject(picture)))
            }
            let content = add(Self.stream(Data(Self.content(page).utf8)))
            let images = pictures.enumerated().map { "/Im\($0.offset) \($0.element) 0 R" }.joined(separator: " ")
            let resources = "<< /Font << /F1 \(regular) 0 R /F2 \(bold) 0 R >> /XObject << \(images) >> >>"
            kids.append(add(Data("<< /Type /Page /Parent \(pagesObject) 0 R /MediaBox [0 0 \(Self.n(page.width)) \(Self.n(page.height))] "
                    .utf8) + Data("/Resources \(resources) /Contents \(content) 0 R >>".utf8)))
        }
        objects[catalog - 1] = Data("<< /Type /Catalog /Pages \(pagesObject) 0 R >>".utf8)
        objects[pagesObject - 1] = Data("<< /Type /Pages /Kids [\(kids.map { "\($0) 0 R" }.joined(separator: " "))] /Count \(kids.count) >>".utf8)
        let info = add(Data(("<< /Title (\(Self.escaped(title))) /Producer (Maquette)"
                + (author.map { " /Author (\(Self.escaped($0)))" } ?? "") + " >>").utf8))
        var file = Data("%PDF-1.4\n%\u{E2}\u{E3}\u{CF}\u{D3}\n".utf8)
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(file.count)
            file += Data("\(index + 1) 0 obj\n".utf8) + object + Data("\nendobj\n".utf8)
        }
        let xref = file.count
        var table = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            table += String(format: "%010d 00000 n \n", offset)
        }
        table += "trailer\n<< /Size \(objects.count + 1) /Root \(catalog) 0 R /Info \(info) 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return file + Data(table.utf8)
    }

    static func imageObject(_ picture: Picture) -> Data {
        let head = "<< /Type /XObject /Subtype /Image /Width \(picture.width) /Height \(picture.height) /ColorSpace /DeviceRGB "
            + "/BitsPerComponent 8 /Filter /DCTDecode /Length \(picture.jpeg.count) >>\nstream\n"
        return Data(head.utf8) + picture.jpeg + Data("\nendstream".utf8)
    }

    static func stream(_ body: Data) -> Data {
        Data("<< /Length \(body.count) >>\nstream\n".utf8) + body + Data("\nendstream".utf8)
    }

    /// The page's drawing: pictures by their place, text in its font and grey, frames as hairlines.
    static func content(_ page: Page) -> String {
        var lines: [String] = []
        var picture = 0
        for item in page.items {
            switch item {
            case let .picture(_, x, y, width, height):
                lines.append("q \(n(width)) 0 0 \(n(height)) \(n(x)) \(n(y)) cm /Im\(picture) Do Q")
                picture += 1
            case let .text(text, x, y, size, bold, grey):
                lines.append("BT /\(bold ? "F2" : "F1") \(n(size)) Tf \(n(grey)) g \(n(x)) \(n(y)) Td (\(escaped(text))) Tj ET")
            case let .frame(x, y, width, height, grey):
                lines.append("q \(n(grey)) G 0.5 w \(n(x)) \(n(y)) \(n(width)) \(n(height)) re S Q")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// A number as PDF writes it (at most three decimals, no exponent).
    static func n(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.3f", rounded)
    }

    /// Text inside ( ): Latin-1 kept (WinAnsi), brackets and backslashes escaped, anything else a "?".
    static func escaped(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "(", ")", "\\": result += "\\" + String(scalar)
            case _ where scalar.value >= 32 && scalar.value < 127: result.unicodeScalars.append(scalar)
            case _ where scalar.value >= 160 && scalar.value < 256: result += String(format: "\\%03o", scalar.value)
            default: result += "?"
            }
        }
        return result
    }
}
