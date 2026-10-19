import CoreGraphics
import CoreText
import Foundation
import LoweyCore

/// Fonts brought into a project (D1: OTF, TTF, TTC), read from its files once and kept by name. The renderer asks for
/// one at a size; a file that isn't a font gives nil, and the text falls back to its style's font.
final class FontFiles {
    /// Reads a project file (`fonts/…` under the project's assets).
    var read: @Sendable (String) -> Data? = { _ in nil }
    private var descriptors: [String: CTFontDescriptor] = [:]
    private var unreadable: Set<String> = []

    func font(_ name: String, size: CGFloat) -> CTFont? {
        if let descriptor = descriptors[name] { return CTFontCreateWithFontDescriptor(descriptor, size, nil) }
        guard !unreadable.contains(name), let data = read(name), let descriptor = Self.descriptor(data) else {
            unreadable.insert(name)
            return nil
        }
        descriptors[name] = descriptor
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    static func descriptor(_ data: Data) -> CTFontDescriptor? {
        CTFontManagerCreateFontDescriptorFromData(data as CFData)
    }
}

/// What a font file is called, for the font list (nil: not a font).
public enum FontFileInfo {
    public static func name(of data: Data) -> String? {
        guard let descriptor = FontFiles.descriptor(data) else { return nil }
        let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
        return CTFontCopyDisplayName(font) as String
    }
}

/// One letter of 3D text on its own, so it can move by itself: its index among `recipe.text`'s characters, its solid,
/// and its middle (where it turns and grows from).
struct TextLetter {
    var index: Int
    var mesh: MeshData
    var centre: SIMD3<Float>
}

extension TextMesher {
    /// Each character's solid (laid out exactly as the whole text is), standing on the ground with the rest.
    static func letters(for recipe: TextRecipe, fonts: FontFiles?) -> [TextLetter] {
        if recipe.coreMeshable {
            return BlockFont.letters(for: recipe).map { TextLetter(index: $0.index, mesh: $0.mesh, centre: Self.centre(of: $0.mesh)) }
        }
        let size = CGFloat(max(recipe.size, 0.01))
        let font = recipe.font.flatMap { fonts?.font($0, size: size) } ?? Self.font(recipe.style, size: size)
        let lines = recipe.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let lineHeight = Double(size) * 1.25
        var byCharacter: [Int: [[Vec2]]] = [:]
        var lineStart = 0
        for (lineIndex, line) in lines.enumerated() {
            let (glyphs, width) = glyphOutlines(line, font: font)
            let xOffset: Double = switch recipe.alignment {
            case .left: 0
            case .center: -width / 2
            case .right: -width
            }
            let yOffset = Double(lines.count - 1 - lineIndex) * lineHeight - Double(CTFontGetDescent(font))
            for (character, contours) in glyphs {
                byCharacter[lineStart + character, default: []] += contours.map { $0.map { Vec2($0.x + xOffset, $0.y + yOffset) } }
            }
            lineStart += line.count + 1
        }
        let lift = byCharacter.values.flatMap { $0.flatMap(\.self) }.map(\.y).min().map { Float(-$0) } ?? 0
        return byCharacter.keys.sorted().compactMap { index in
            guard let contours = byCharacter[index] else { return nil }
            var mesh = Outlines.extrude(contours, depth: recipe.size * recipe.depth)
            guard !mesh.isEmpty else { return nil }
            mesh.positions = mesh.positions.map { SIMD3<Float>($0.x, $0.y + lift, $0.z) }
            return TextLetter(index: index, mesh: mesh, centre: centre(of: mesh))
        }
    }

    static func centre(of mesh: MeshData) -> SIMD3<Float> {
        guard let bounds = mesh.bounds else { return .zero }
        return SIMD3<Float>(Float(bounds.center.x), Float(bounds.center.y), Float(bounds.center.z))
    }

    /// One line's glyph contours by the character (within the line) each glyph draws, and the line's width.
    static func glyphOutlines(_ text: String, font: CTFont) -> (glyphs: [Int: [[Vec2]]], width: Double) {
        guard !text.isEmpty else { return ([:], 0) }
        let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        // UTF-16 offset → character index.
        var characterAt: [Int] = []
        for (index, character) in text.enumerated() {
            characterAt += Array(repeating: index, count: character.utf16.count)
        }
        var glyphs: [Int: [[Vec2]]] = [:]
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            let runFont = runFont(run) ?? font
            var ids = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var offsets = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &ids)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            CTRunGetStringIndices(run, CFRange(location: 0, length: count), &offsets)
            for index in 0 ..< count {
                var transform = CGAffineTransform(translationX: positions[index].x, y: positions[index].y)
                guard let path = CTFontCreatePathForGlyph(runFont, ids[index], &transform) else { continue }
                let character = characterAt.indices.contains(offsets[index]) ? characterAt[offsets[index]] : 0
                glyphs[character, default: []] += flatten(path)
            }
        }
        return (glyphs, Double(width))
    }

    /// Substituted glyphs (Arabic in a Latin font) come in their own font.
    private static func runFont(_ run: CTRun) -> CTFont? {
        let attributes = CTRunGetAttributes(run) as NSDictionary
        return (attributes[kCTFontAttributeName as String] as CFTypeRef?).flatMap { value -> CTFont? in
            CFGetTypeID(value) == CTFontGetTypeID() ? unsafeDowncast(value, to: CTFont.self) : nil
        }
    }
}
