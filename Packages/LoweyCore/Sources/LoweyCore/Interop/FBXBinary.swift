import Foundation

/// A node of an FBX file: a name, its values, and the nodes inside it.
struct FBXNode {
    var name: String
    var properties: [FBXValue]
    var children: [FBXNode]

    init(_ name: String, _ properties: [FBXValue] = [], _ children: [FBXNode] = []) {
        self.name = name
        self.properties = properties
        self.children = children
    }

    /// A `Properties70` entry: its name, type, label, flags, then its values.
    static func property(_ name: String, _ type: String, _ label: String = "", _ flags: String = "", _ values: [FBXValue]) -> FBXNode {
        FBXNode("P", [.string(name), .string(type), .string(label), .string(flags)] + values)
    }
}

/// The values an FBX node holds, each written with its type code.
enum FBXValue {
    case bool(Bool), int32(Int32), int64(Int64), float(Float), double(Double), string(String)
    case int32s([Int32]), int64s([Int64]), floats([Float]), doubles([Double])

    /// An object's name as FBX keeps it: the name, then its class after "\0\u{1}".
    static func name(_ name: String, _ kind: String) -> FBXValue {
        .string(name + "\u{0}\u{1}" + kind)
    }
}

/// FBX's binary form, version 7.4 (32-bit offsets), as Blender, Godot (ufbx) and Unity read it.
enum FBXBinary {
    static let version: UInt32 = 7400

    static func file(_ nodes: [FBXNode]) -> Data {
        var data = Data("Kaydara FBX Binary  ".utf8)
        data.append(contentsOf: [0x00, 0x1A, 0x00])
        put(version, into: &data)
        for node in nodes {
            write(node, into: &data)
        }
        data.append(Data(count: 13))
        footer(into: &data)
        return data
    }

    static func put(_ value: UInt32, into data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    /// One node: where it ends, how many values, their length, its name, the values, then its children closed by an
    /// empty record.
    static func write(_ node: FBXNode, into data: inout Data) {
        let start = data.count
        put(0, into: &data)
        put(UInt32(node.properties.count), into: &data)
        put(0, into: &data)
        let name = Data(node.name.utf8)
        data.append(UInt8(name.count))
        data.append(name)
        let valuesStart = data.count
        for value in node.properties {
            write(value, into: &data)
        }
        patch(UInt32(data.count - valuesStart), at: start + 8, in: &data)
        if !node.children.isEmpty || node.properties.isEmpty {
            for child in node.children {
                write(child, into: &data)
            }
            data.append(Data(count: 13))
        }
        patch(UInt32(data.count), at: start, in: &data)
    }

    static func patch(_ value: UInt32, at offset: Int, in data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { bytes in
            data.replaceSubrange(offset ..< offset + 4, with: bytes)
        }
    }

    static func write(_ value: FBXValue, into data: inout Data) {
        func code(_ letter: Character) { data.append(letter.asciiValue ?? 0) }
        func raw<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }
        func array<T>(_ letter: Character, _ values: [T]) {
            code(letter)
            put(UInt32(values.count), into: &data)
            put(0, into: &data)
            put(UInt32(values.count * MemoryLayout<T>.size), into: &data)
            values.withUnsafeBytes { data.append(contentsOf: $0) }
        }
        switch value {
        case let .bool(flag):
            code("C")
            data.append(flag ? 1 : 0)
        case let .int32(number):
            code("I")
            raw(number.littleEndian)
        case let .int64(number):
            code("L")
            raw(number.littleEndian)
        case let .float(number):
            code("F")
            raw(number.bitPattern.littleEndian)
        case let .double(number):
            code("D")
            raw(number.bitPattern.littleEndian)
        case let .string(text):
            let bytes = Data(text.utf8)
            code("S")
            put(UInt32(bytes.count), into: &data)
            data.append(bytes)
        case let .int32s(values): array("i", values.map(\.littleEndian))
        case let .int64s(values): array("l", values.map(\.littleEndian))
        case let .floats(values): array("f", values.map(\.bitPattern.littleEndian))
        case let .doubles(values): array("d", values.map(\.bitPattern.littleEndian))
        }
    }

    /// The closing block every FBX writer leaves: a code, padding to sixteen bytes, the version, and a magic tail.
    static func footer(into data: inout Data) {
        data.append(contentsOf: [0xFA, 0xBC, 0xAB, 0x09, 0xD0, 0xC8, 0xD4, 0x66, 0xB1, 0x76, 0xFB, 0x83, 0x1C, 0xF7, 0x26, 0x7E])
        data.append(Data(count: 4))
        let pad = (16 - data.count % 16) % 16
        data.append(Data(count: pad == 0 ? 16 : pad))
        put(version, into: &data)
        data.append(Data(count: 120))
        data.append(contentsOf: [0xF8, 0x5A, 0x8C, 0x6A, 0xDE, 0xF5, 0xD9, 0x7E, 0xEC, 0xE9, 0x0C, 0xE3, 0x75, 0x8F, 0x29, 0x0B])
    }
}
