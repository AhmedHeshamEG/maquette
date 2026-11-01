import Foundation

/// An element of a small XML tree: enough of XML for SVG files (elements, attributes, text, comments, CDATA,
/// declarations), read by hand so it behaves the same on every platform.
struct SVGNode: Sendable {
    var name: String
    var attributes: [String: String]
    var children: [SVGNode]
    var text: String

    init(name: String, attributes: [String: String] = [:], children: [SVGNode] = [], text: String = "") {
        self.name = name
        self.attributes = attributes
        self.children = children
        self.text = text
    }

    /// The name without a namespace prefix (`svg:path` → `path`).
    var localName: String { name.split(separator: ":").last.map(String.init) ?? name }

    /// Every element below this one, depth first.
    var descendants: [SVGNode] { children.flatMap { [$0] + $0.descendants } }
}

/// Reads XML text into a tree. Malformed input gives the elements read so far, never a crash.
struct XMLReader {
    private let scalars: [Unicode.Scalar]
    private var index = 0

    init(_ text: String) {
        scalars = Array(text.unicodeScalars)
    }

    /// The root element (the first element in the file), or nil when there is none.
    static func parse(_ text: String) -> SVGNode? {
        var reader = XMLReader(text)
        return reader.readChildren(closing: nil).children.first
    }

    private var atEnd: Bool { index >= scalars.count }

    private func starts(with literal: String) -> Bool {
        var position = index
        for scalar in literal.unicodeScalars {
            guard position < scalars.count, scalars[position] == scalar else { return false }
            position += 1
        }
        return true
    }

    private func string(_ range: Range<Int>) -> String {
        String(String.UnicodeScalarView(scalars[range]))
    }

    private mutating func skip(past literal: String) {
        while !atEnd, !starts(with: literal) {
            index += 1
        }
        index = min(index + literal.unicodeScalars.count, scalars.count)
    }

    private mutating func skipSpace() {
        while !atEnd, scalars[index].properties.isWhitespace {
            index += 1
        }
    }

    /// Elements up to `</closing>` (or the end), and the text between them.
    private mutating func readChildren(closing: String?) -> (children: [SVGNode], text: String) {
        var children: [SVGNode] = []
        var text = ""
        while !atEnd {
            if starts(with: "<!--") {
                skip(past: "-->")
            } else if starts(with: "<![CDATA[") {
                index += 9
                let start = index
                skip(past: "]]>")
                text += string(start ..< max(start, index - 3))
            } else if starts(with: "<?") {
                skip(past: "?>")
            } else if starts(with: "<!") {
                skipDeclaration()
            } else if starts(with: "</") {
                skip(past: ">")
                if closing != nil { return (children, text) }
            } else if starts(with: "<") {
                if let element = readElement() { children.append(element) }
            } else {
                let start = index
                while !atEnd, scalars[index] != "<" {
                    index += 1
                }
                text += Self.decodeEntities(string(start ..< index))
            }
        }
        return (children, text)
    }

    /// `<!DOCTYPE …>` with an internal subset in brackets.
    private mutating func skipDeclaration() {
        var depth = 0
        while !atEnd {
            let scalar = scalars[index]
            index += 1
            if scalar == "[" { depth += 1 }
            if scalar == "]" { depth -= 1 }
            if scalar == ">", depth <= 0 { return }
        }
    }

    private mutating func readElement() -> SVGNode? {
        index += 1
        let name = readName()
        guard !name.isEmpty else { return nil }
        var element = SVGNode(name: name)
        while !atEnd {
            skipSpace()
            if starts(with: "/>") {
                index += 2
                return element
            }
            if starts(with: ">") {
                index += 1
                (element.children, element.text) = readChildren(closing: name)
                return element
            }
            guard let (key, value) = readAttribute() else {
                index += 1
                continue
            }
            element.attributes[key] = value
        }
        return element
    }

    private mutating func readName() -> String {
        let start = index
        while !atEnd {
            let scalar = scalars[index]
            if scalar.properties.isWhitespace || scalar == ">" || scalar == "/" || scalar == "=" { break }
            index += 1
        }
        return string(start ..< index)
    }

    private mutating func readAttribute() -> (String, String)? {
        let key = readName()
        guard !key.isEmpty else { return nil }
        skipSpace()
        guard !atEnd, scalars[index] == "=" else { return (key, "") }
        index += 1
        skipSpace()
        guard !atEnd else { return (key, "") }
        let quote = scalars[index]
        guard quote == "\"" || quote == "'" else { return (key, readName()) }
        index += 1
        let start = index
        while !atEnd, scalars[index] != quote {
            index += 1
        }
        let value = string(start ..< index)
        index = min(index + 1, scalars.count)
        return (key, Self.decodeEntities(value))
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        for (entity, value) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&#10;", "\n"), ("&#xA;", "\n")] {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }
}
