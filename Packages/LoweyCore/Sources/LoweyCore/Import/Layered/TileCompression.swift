import Foundation

/// The two codes Procreate packs its tiles with, in pure Swift: LZ4 in Apple's framing (newer files, `.lz4` tiles) and
/// LZO1X (older files, `.chunk` tiles).
enum TileCompression {
    /// Apple's LZ4 framing: blocks of `bv41` (compressed), `bv4-` (stored), ending with `bv4$`. A block may copy from
    /// the blocks before it (one window across the whole stream).
    static func appleLZ4(_ data: Data, expected: Int) throws(LayeredReadFailure) -> [UInt8] {
        let input = [UInt8](data)
        var output: [UInt8] = []
        output.reserveCapacity(expected)
        var position = 0
        func u32(_ at: Int) -> Int {
            Int(input[at]) | Int(input[at + 1]) << 8 | Int(input[at + 2]) << 16 | Int(input[at + 3]) << 24
        }
        while position + 4 <= input.count {
            let magic = String(decoding: input[position ..< position + 4], as: UTF8.self)
            switch magic {
            case "bv4$":
                return output
            case "bv41":
                guard position + 12 <= input.count else { throw .damaged("a tile") }
                let size = u32(position + 4), packed = u32(position + 8)
                guard position + 12 + packed <= input.count, size <= expected * 2 + 65536 else { throw .damaged("a tile") }
                try lz4Block(input[position + 12 ..< position + 12 + packed], into: &output, size: size)
                position += 12 + packed
            case "bv4-":
                guard position + 8 <= input.count else { throw .damaged("a tile") }
                let size = u32(position + 4)
                guard position + 8 + size <= input.count else { throw .damaged("a tile") }
                output.append(contentsOf: input[position + 8 ..< position + 8 + size])
                position += 8 + size
            default:
                throw .damaged("a tile's code")
            }
        }
        return output
    }

    /// One LZ4 block appended to `output` (its matches may reach back into what's already there).
    static func lz4Block(_ block: ArraySlice<UInt8>, into output: inout [UInt8], size: Int) throws(LayeredReadFailure) {
        var index = block.startIndex
        let end = block.endIndex
        let target = output.count + size
        func length(_ start: Int) throws(LayeredReadFailure) -> Int {
            var total = start
            guard start == 15 else { return total }
            while true {
                guard index < end else { throw .damaged("a tile") }
                let next = Int(block[index])
                index += 1
                total += next
                if next != 255 { return total }
            }
        }
        while index < end {
            let token = Int(block[index])
            index += 1
            let literals = try length(token >> 4)
            guard index + literals <= end else { throw .damaged("a tile") }
            output.append(contentsOf: block[index ..< index + literals])
            index += literals
            guard index < end else { break }
            guard index + 2 <= end else { throw .damaged("a tile") }
            let offset = Int(block[index]) | Int(block[index + 1]) << 8
            index += 2
            let count = try length(token & 15) + 4
            let from = output.count - offset
            guard offset > 0, from >= 0, output.count + count <= target else { throw .damaged("a tile") }
            for step in 0 ..< count {
                output.append(output[from + step])
            }
        }
        guard output.count == target else { throw .damaged("a tile's size") }
    }

    /// LZO1X, as minilzo decompresses it, with every read and copy checked.
    static func lzo1x(_ data: Data, expected: Int) throws(LayeredReadFailure) -> [UInt8] {
        var decoder = LZODecoder(input: [UInt8](data), capacity: expected)
        try decoder.run()
        return decoder.output
    }
}

/// minilzo's `lzo1x_decompress`, step for step, in a struct so the state machine reads as the original.
private struct LZODecoder {
    let input: [UInt8]
    var output: [UInt8] = []
    var ip = 0
    let capacity: Int

    init(input: [UInt8], capacity: Int) {
        self.input = input
        self.capacity = capacity
        output.reserveCapacity(capacity)
    }

    private mutating func next() throws(LayeredReadFailure) -> Int {
        guard ip < input.count else { throw .damaged("an old tile") }
        defer { ip += 1 }
        return Int(input[ip])
    }

    private mutating func literals(_ count: Int) throws(LayeredReadFailure) {
        guard ip + count <= input.count, output.count + count <= capacity else { throw .damaged("an old tile") }
        output.append(contentsOf: input[ip ..< ip + count])
        ip += count
    }

    private mutating func copy(from distance: Int, count: Int) throws(LayeredReadFailure) {
        let from = output.count - distance
        guard distance > 0, from >= 0, output.count + count <= capacity else { throw .damaged("an old tile") }
        for step in 0 ..< count {
            output.append(output[from + step])
        }
    }

    /// A run length: zero bytes add 255 each, then the next byte and `base`.
    private mutating func long(_ base: Int) throws(LayeredReadFailure) -> Int {
        var total = 0
        while ip < input.count, input[ip] == 0 {
            total += 255
            ip += 1
        }
        return try total + base + next()
    }

    mutating func run() throws(LayeredReadFailure) {
        var t = 0
        var state = State.start
        if let first = input.first, first > 17 {
            ip = 1
            t = Int(first) - 17
            if t < 4 {
                state = .matchNext
            } else {
                try literals(t)
                state = .firstLiteralRun
            }
        }
        while true {
            switch state {
            case .start:
                t = try next()
                if t >= 16 {
                    state = .match
                    continue
                }
                if t == 0 { t = try long(15) }
                try literals(t + 3)
                state = .firstLiteralRun
            case .firstLiteralRun:
                t = try next()
                if t >= 16 {
                    state = .match
                    continue
                }
                let distance = try 1 + 0x0800 + (t >> 2) + (next() << 2)
                try copy(from: distance, count: 3)
                state = .matchDone
            case .match:
                if try matchOrEnd(&t) { return }
                state = .matchDone
            case .matchDone:
                t = Int(input[ip - 2]) & 3
                state = t == 0 ? .start : .matchNext
            case .matchNext:
                try literals(t)
                t = try next()
                state = .match
            }
        }
    }

    /// One match from its token `t`; true at the end of the stream.
    private mutating func matchOrEnd(_ t: inout Int) throws(LayeredReadFailure) -> Bool {
        if t >= 64 {
            let distance = try 1 + ((t >> 2) & 7) + (next() << 3)
            try copy(from: distance, count: (t >> 5) + 1)
        } else if t >= 32 {
            var count = t & 31
            if count == 0 { count = try long(31) }
            let low = try next(), high = try next()
            try copy(from: 1 + (low >> 2) + (high << 6), count: count + 2)
        } else if t >= 16 {
            var distance = (t & 8) << 11
            var count = t & 7
            if count == 0 { count = try long(7) }
            let low = try next(), high = try next()
            distance += (low >> 2) + (high << 6)
            if distance == 0 { return true }
            try copy(from: distance + 0x4000, count: count + 2)
        } else {
            let distance = try 1 + (t >> 2) + (next() << 2)
            try copy(from: distance, count: 2)
        }
        return false
    }

    private enum State {
        case start, firstLiteralRun, match, matchDone, matchNext
    }
}
