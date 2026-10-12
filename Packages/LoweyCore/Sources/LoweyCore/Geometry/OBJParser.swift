import Foundation

/// Minimal Wavefront OBJ reader: positions, normals, UVs, polygon faces (triangulated),
/// negative indices. Materials are ignored; the object takes a palette color instead.
public enum OBJParser {
    public enum ParseError: Error, Equatable {
        case noGeometry
    }

    public static func parse(_ text: String) throws -> MeshData {
        try read(Data(text.utf8)).mesh
    }

    /// An OBJ as a model: one part, with the colours a sculpting app writes after each corner (`v x y z r g b`).
    public static func model(_ data: Data, name: String) throws -> ImportedModel {
        let (mesh, colors) = try read(data)
        return ImportedModel(parts: [ImportedPart(name: name, mesh: mesh, material: 0, colors: colors)], materials: [ImportedMaterial(name: name)])
    }

    /// Positions, normals and uvs as the faces use them, and a colour per vertex when the file has them. Read byte by
    /// byte: a sculpt's OBJ runs to a hundred megabytes.
    static func read(_ data: Data) throws -> (mesh: MeshData, colors: [SIMD4<Float>]) {
        var reader = Reader()
        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var line = 0
            while line < bytes.count {
                var end = line
                while end < bytes.count, bytes[end] != 10, bytes[end] != 13 {
                    end += 1
                }
                reader.line(bytes, from: line, to: end)
                line = end + 1
            }
        }
        guard !reader.mesh.indices.isEmpty else { throw ParseError.noGeometry }
        var mesh = reader.mesh
        let colors = reader.hasColors && mesh.positions.count == reader.vertexColors.count ? reader.vertexColors : []
        if !reader.hasNormals || reader.normals.isEmpty {
            // A painted sculpt is smooth all over and keeps its corners (each has its colour); anything else gets its
            // creases back.
            if colors.isEmpty { mesh = mesh.autoSmoothed() } else { mesh.computeSmoothNormals() }
        }
        // Colours written as 0…255 are brought to 0…1.
        let scale: Float = colors.contains { $0.x > 1 || $0.y > 1 || $0.z > 1 } ? 1.0 / 255 : 1
        return (mesh, colors.map { SIMD4<Float>($0.x * scale, $0.y * scale, $0.z * scale, 1) })
    }

    /// The state of a file being read.
    struct Reader {
        var positions: [SIMD3<Float>] = []
        var colorsOfPositions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var mesh = MeshData()
        var vertexColors: [SIMD3<Float>] = []
        var cache: [SIMD3<Int32>: UInt32] = [:]
        var hasNormals = true
        var hasColors = false

        mutating func line(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int) {
            var index = start
            skipSpaces(bytes, &index, end)
            guard index + 1 < end else { return }
            let first = bytes[index], second = bytes[index + 1]
            let spaced = second == 32 || second == 9
            if first == 118, spaced { // "v "
                index += 2
                vertexLine(bytes, &index, end)
            } else if first == 118, second == 110 { // "vn"
                index += 2
                let n = numbers(bytes, &index, end, limit: 3)
                if n.count == 3 { normals.append(SIMD3<Float>(Float(n[0]), Float(n[1]), Float(n[2]))) }
            } else if first == 118, second == 116 { // "vt"
                index += 2
                let n = numbers(bytes, &index, end, limit: 2)
                if n.count == 2 { uvs.append(SIMD2<Float>(Float(n[0]), Float(n[1]))) }
            } else if first == 102, spaced { // "f "
                index += 2
                faceLine(bytes, &index, end)
            }
        }

        mutating func vertexLine(_ bytes: UnsafeBufferPointer<UInt8>, _ index: inout Int, _ end: Int) {
            let n = numbers(bytes, &index, end, limit: 7)
            guard n.count >= 3 else { return }
            positions.append(SIMD3<Float>(Float(n[0]), Float(n[1]), Float(n[2])))
            if n.count >= 6 {
                hasColors = true
                colorsOfPositions.append(SIMD3<Float>(Float(n[3]), Float(n[4]), Float(n[5])))
            } else {
                colorsOfPositions.append(SIMD3<Float>(1, 1, 1))
            }
        }

        mutating func faceLine(_ bytes: UnsafeBufferPointer<UInt8>, _ index: inout Int, _ end: Int) {
            var face: [UInt32] = []
            while index < end {
                skipSpaces(bytes, &index, end)
                guard index < end, bytes[index] != 35 else { break } // "#"
                var corner = SIMD3<Int32>(0, 0, 0)
                for slot in 0 ..< 3 {
                    if index < end, bytes[index] != 47, let value = integer(bytes, &index, end) { corner[slot] = Int32(clamping: value) }
                    guard index < end, bytes[index] == 47 else { break } // "/"
                    index += 1
                }
                while index < end, bytes[index] != 32, bytes[index] != 9 {
                    index += 1
                }
                if let vertex = vertex(corner) { face.append(vertex) }
            }
            guard face.count >= 3 else { return }
            for corner in 1 ..< face.count - 1 {
                mesh.addTriangle(face[0], face[corner], face[corner + 1])
            }
        }

        func resolve(_ index: Int32, count: Int) -> Int? {
            let resolved = index > 0 ? Int(index) - 1 : count + Int(index)
            return index != 0 && (0 ..< count).contains(resolved) ? resolved : nil
        }

        mutating func vertex(_ corner: SIMD3<Int32>) -> UInt32? {
            if let known = cache[corner] { return known }
            guard let position = resolve(corner.x, count: positions.count) else { return nil }
            let uv = resolve(corner.y, count: uvs.count).map { uvs[$0] } ?? SIMD2<Float>(0, 0)
            let normal: SIMD3<Float>
            if let index = resolve(corner.z, count: normals.count) {
                normal = normals[index]
            } else {
                normal = SIMD3<Float>(0, 1, 0)
                hasNormals = false
            }
            let index = mesh.addVertex(positions[position], normal: normal, uv: uv)
            vertexColors.append(colorsOfPositions[position])
            cache[corner] = index
            return index
        }

        func skipSpaces(_ bytes: UnsafeBufferPointer<UInt8>, _ index: inout Int, _ end: Int) {
            while index < end, bytes[index] == 32 || bytes[index] == 9 {
                index += 1
            }
        }

        func numbers(_ bytes: UnsafeBufferPointer<UInt8>, _ index: inout Int, _ end: Int, limit: Int) -> [Double] {
            var result: [Double] = []
            while result.count < limit {
                skipSpaces(bytes, &index, end)
                guard index < end, let value = number(bytes, &index, end) else { break }
                result.append(value)
            }
            return result
        }

        func integer(_ bytes: UnsafeBufferPointer<UInt8>, _ index: inout Int, _ end: Int) -> Int? {
            var sign = 1
            if index < end, bytes[index] == 45 { // "-"
                sign = -1
                index += 1
            }
            var value = 0
            var digits = 0
            while index < end, bytes[index] >= 48, bytes[index] <= 57 {
                value = value &* 10 &+ Int(bytes[index] - 48)
                index += 1
                digits += 1
            }
            return digits > 0 ? value * sign : nil
        }

        /// A decimal number with an optional sign, fraction and exponent.
        func number(_ bytes: UnsafeBufferPointer<UInt8>, _ index: inout Int, _ end: Int) -> Double? {
            var sign = 1.0
            if index < end, bytes[index] == 45 || bytes[index] == 43 { // "-" or "+"
                if bytes[index] == 45 { sign = -1 }
                index += 1
            }
            var value = 0.0
            var digits = 0
            while index < end, bytes[index] >= 48, bytes[index] <= 57 {
                value = value * 10 + Double(bytes[index] - 48)
                index += 1
                digits += 1
            }
            if index < end, bytes[index] == 46 { // "."
                index += 1
                var scale = 0.1
                while index < end, bytes[index] >= 48, bytes[index] <= 57 {
                    value += Double(bytes[index] - 48) * scale
                    scale *= 0.1
                    index += 1
                    digits += 1
                }
            }
            guard digits > 0 else { return nil }
            if index < end, bytes[index] == 101 || bytes[index] == 69, let power = exponent(bytes, &index, end) { // "e"
                value *= pow(10, Double(power))
            }
            return sign * value
        }

        func exponent(_ bytes: UnsafeBufferPointer<UInt8>, _ index: inout Int, _ end: Int) -> Int? {
            var probe = index + 1
            if probe < end, bytes[probe] == 43 { probe += 1 } // "+"
            guard let value = integer(bytes, &probe, end) else { return nil }
            index = probe
            return value
        }
    }
}

// Files a glTF (.gltf JSON) references, so importing copies its .bin and textures along.
public enum GLTFDependencies {
    public static func referencedURIs(in json: Data) -> [String] {
        guard let root = try? LoweyJSON.decode(JSONValue.self, from: json) else { return [] }
        var uris: [String] = []
        for key in ["buffers", "images"] {
            for entry in root[key]?.arrayValue ?? [] {
                if let uri = entry["uri"]?.stringValue, !uri.hasPrefix("data:") {
                    uris.append(uri.removingPercentEncoding ?? uri)
                }
            }
        }
        return uris
    }
}
