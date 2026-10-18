"""Compares Godot's render of an exported Look (A1) with its golden picture.

Usage: python3 Tools/check_look_render.py render.png Tools/godot/golden/ink-look.png [diff.png]

Passes when the pictures are the same size, differ by at most 3 levels on average and 98 % of the pixels are within
24 levels (a different Mesa may move an edge by a pixel). Prints "MAQUETTE LOOK RENDER: ..." and exits 1 otherwise.
With a third path it writes the difference as a picture. Plain Python: PNG reading and writing are below.
"""
import struct
import sys
import zlib


def read_png(path):
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"MAQUETTE LOOK RENDER: FAILED: {path} isn't a PNG")
    offset, chunks, header = 8, [], None
    while offset < len(data):
        length, kind = struct.unpack(">I4s", data[offset:offset + 8])
        body = data[offset + 8:offset + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            chunks.append(body)
        offset += 12 + length
    width, height, depth, colour, _, _, interlace = header
    if depth != 8 or colour not in (2, 6) or interlace:
        sys.exit(f"MAQUETTE LOOK RENDER: FAILED: {path} must be 8-bit RGB or RGBA, not interlaced")
    channels = 3 if colour == 2 else 4
    raw = zlib.decompress(b"".join(chunks))
    stride = width * channels
    rows, previous, cursor = [], bytearray(stride), 0
    for _ in range(height):
        kind = raw[cursor]
        line = bytearray(raw[cursor + 1:cursor + 1 + stride])
        cursor += 1 + stride
        for index in range(stride):
            left = line[index - channels] if index >= channels else 0
            up = previous[index]
            corner = previous[index - channels] if index >= channels else 0
            if kind == 1:
                line[index] = (line[index] + left) & 255
            elif kind == 2:
                line[index] = (line[index] + up) & 255
            elif kind == 3:
                line[index] = (line[index] + (left + up) // 2) & 255
            elif kind == 4:
                guess = left + up - corner
                pa, pb, pc = abs(guess - left), abs(guess - up), abs(guess - corner)
                near = left if pa <= pb and pa <= pc else (up if pb <= pc else corner)
                line[index] = (line[index] + near) & 255
        rows.append([tuple(line[x * channels:x * channels + 3]) for x in range(width)])
        previous = line
    return width, height, rows


def write_png(path, width, height, rows):
    raw = b"".join(b"\x00" + bytes(value for pixel in row for value in pixel) for row in rows)

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    width, height, render = read_png(sys.argv[1])
    golden_width, golden_height, golden = read_png(sys.argv[2])
    if (width, height) != (golden_width, golden_height):
        sys.exit(f"MAQUETTE LOOK RENDER: FAILED: {width}x{height}, the golden is {golden_width}x{golden_height}")
    total, close, diff = 0, 0, []
    for y in range(height):
        line = []
        for x in range(width):
            worst = max(abs(a - b) for a, b in zip(render[y][x], golden[y][x]))
            total += sum(abs(a - b) for a, b in zip(render[y][x], golden[y][x]))
            close += worst <= 24
            line.append((min(worst * 4, 255),) * 3)
        diff.append(line)
    mean = total / (width * height * 3)
    share = close / (width * height)
    if len(sys.argv) > 3:
        write_png(sys.argv[3], width, height, diff)
    summary = f"{width}x{height}, mean difference {mean:.2f} levels, {share * 100:.2f} % of pixels within 24"
    if mean > 3 or share < 0.98:
        sys.exit("MAQUETTE LOOK RENDER: FAILED: " + summary)
    print("MAQUETTE LOOK RENDER: matches the golden: " + summary)


if __name__ == "__main__":
    main()
