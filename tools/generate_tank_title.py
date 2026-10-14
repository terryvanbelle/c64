#!/usr/bin/env python3
"""Original, reproducible Ironveil opening art in native C64 multicolor bitmap.

No external artwork or font is required. The editable scene is made of integer
polygons, lines and an original five-bit font already used by the project.
Output is count/value RLE (counts 1..255, no terminator) over this exact stream:
8,000 bitmap bytes, 1,000 screen bytes, 1,000 Color RAM nibbles. Stop decoding
after 10,000 output bytes. MC pairs 00/01/10/11 select black/screen-high/
screen-low/Color-RAM respectively, as in the Commodore Programmer's Reference,
Chapter 3 pp.127–128. Bitmap cells contain four logical pixels by eight rows.
Rows 136..199 remain blank with screen $B1/color $07, including the menu area.
Only Python's standard library is required; this does not touch gameplay art.
"""

from collections import Counter
from pathlib import Path
import struct
import zlib

from generate_atlas_assets import FONT, PALETTE

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "tanks"
W, H = 160, 200


def scene():
    canvas = [[0] * W for _ in range(H)]

    def dot(x, y, color):
        if 0 <= x < W and 0 <= y < 136:
            canvas[y][x] = color

    def box(x0, y0, x1, y1, color):
        for y in range(max(0, y0), min(136, y1 + 1)):
            for x in range(max(0, x0), min(W, x1 + 1)):
                canvas[y][x] = color

    def line(x0, y0, x1, y1, color):
        dx, sx = abs(x1 - x0), 1 if x0 < x1 else -1
        dy, sy = -abs(y1 - y0), 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            dot(x0, y0, color)
            if x0 == x1 and y0 == y1:
                break
            twice = 2 * err
            if twice >= dy:
                err += dy
                x0 += sx
            if twice <= dx:
                err += dx
                y0 += sy

    def poly(points, color):
        # Integer pixel-center scan conversion, independent of graphics libs.
        for y in range(max(0, min(p[1] for p in points)),
                       min(135, max(p[1] for p in points)) + 1):
            crossings = []
            for a, b in zip(points, points[1:] + points[:1]):
                if (a[1] <= y < b[1]) or (b[1] <= y < a[1]):
                    crossings.append(a[0] + (y - a[1]) * (b[0] - a[0]) //
                                     (b[1] - a[1]))
            crossings.sort()
            for x0, x1 in zip(crossings[::2], crossings[1::2]):
                box(x0, y, x1, y, color)

    def ellipse(cx, cy, rx, ry, color):
        for y in range(cy - ry, cy + ry + 1):
            for x in range(cx - rx, cx + rx + 1):
                if (x - cx) ** 2 * ry ** 2 + (y - cy) ** 2 * rx ** 2 <= rx ** 2 * ry ** 2:
                    dot(x, y, color)

    # Quiet frame and a metal wordmark. Its bevel is drawn directly into pixels.
    line(5, 5, 154, 5, 11)
    line(5, 5, 5, 131, 11)
    line(154, 5, 154, 131, 11)
    line(5, 132, 154, 132, 7)
    word = "IRONVEIL"
    for i, char in enumerate(word):
        x0 = 12 + i * 17
        for row, bits in enumerate(FONT[char]):
            for col in range(5):
                if bits & (16 >> col):
                    box(x0 + col * 3 + 1, 13 + row * 3 + 2,
                        x0 + col * 3 + 3, 13 + row * 3 + 4, 11)
        for row, bits in enumerate(FONT[char]):
            for col in range(5):
                if bits & (16 >> col):
                    for yy in range(3):
                        color = 1 if row * 3 + yy < 5 else 7
                        box(x0 + col * 3, 13 + row * 3 + yy,
                            x0 + col * 3 + 2, 13 + row * 3 + yy, color)
    line(14, 40, 146, 40, 11)
    line(56, 42, 105, 42, 7)

    # A moonlit channel and angular distant ridges. Broad flat planes retain
    # the deliberate, restrained C64 palette and compress without a bitstream.
    box(6, 46, 153, 79, 6)
    ellipse(116, 60, 7, 10, 7)
    line(68, 48, 103, 48, 11)
    line(85, 51, 112, 51, 11)
    poly([(6, 71), (20, 60), (38, 73), (58, 57), (77, 75),
          (99, 57), (116, 75), (134, 62), (153, 79), (153, 89), (6, 89)], 0)
    poly([(58, 57), (58, 65), (72, 75), (66, 66)], 11)
    poly([(99, 57), (101, 66), (116, 76), (108, 64)], 11)
    poly([(134, 62), (137, 71), (153, 79), (144, 66)], 11)
    poly([(6, 83), (45, 78), (73, 84), (115, 76), (153, 87),
          (153, 132), (6, 132)], 11)
    poly([(6, 93), (58, 86), (104, 94), (153, 92), (153, 132), (6, 132)], 0)
    # River reflection, crossing, and the two quiet road approaches.
    poly([(110, 77), (116, 77), (127, 91), (123, 103),
          (139, 117), (153, 122), (153, 130), (132, 124),
          (116, 105), (118, 92)], 6)
    line(112, 80, 122, 91, 7)
    line(122, 96, 119, 104, 7)
    line(128, 114, 143, 123, 7)
    line(132, 119, 150, 127, 7)
    poly([(108, 95), (135, 87), (138, 91), (110, 100)], 11)
    line(111, 96, 135, 89, 7)
    line(136, 90, 136, 94, 7)
    line(107, 97, 86, 103, 11)
    line(136, 89, 150, 80, 11)

    # Forest silhouettes along the far bank; small gaps describe trunks.
    for x, y, height in ((11, 81, 12), (18, 80, 16), (27, 82, 13),
                         (35, 81, 18), (44, 84, 12), (146, 96, 17), (151, 100, 13)):
        poly([(x, y - height), (x - 4, y - 3), (x + 4, y - 3)], 0)
        line(x, y - 8, x, y + 1, 0)
        line(x - 1, y - height + 3, x - 3, y - 5, 5)

    # Hero tank: independent turret points across the river while the hull
    # faces the foreground. Separate tread masses, bevels, hatch and barrel
    # make the silhouette legible rather than relying on texture noise.
    poly([(16, 96), (26, 90), (77, 116), (69, 132), (17, 108)], 11)
    poly([(52, 80), (62, 77), (118, 104), (114, 117), (105, 114)], 11)
    poly([(24, 93), (58, 82), (109, 108), (73, 121)], 5)
    poly([(24, 93), (73, 118), (73, 126), (24, 101)], 11)
    poly([(73, 118), (109, 107), (109, 116), (73, 126)], 0)
    line(25, 93, 58, 83, 7)
    line(59, 83, 106, 107, 7)
    line(28, 97, 69, 118, 7)
    line(75, 120, 106, 111, 11)
    # Track wheels and narrow separated tread plates.
    for x, y in ((25, 107), (36, 113), (47, 119), (59, 125)):
        ellipse(x, y, 4, 3, 0)
        line(x - 2, y - 1, x + 2, y + 1, 11)
    for x, y in ((65, 81), (78, 87), (91, 94), (105, 101)):
        line(x, y, x - 2, y + 5, 0)
    # Engine louvres and a little reflected light on the rear armor.
    for x, y in ((34, 93), (39, 95), (44, 97), (49, 99)):
        line(x, y, x + 8, y - 3, 0)
    line(78, 112, 99, 106, 7)
    poly([(43, 89), (65, 83), (88, 94), (85, 104), (65, 110), (43, 99)], 11)
    poly([(43, 89), (65, 83), (88, 94), (65, 102)], 5)
    line(44, 89, 65, 84, 7)
    line(66, 85, 85, 94, 7)
    ellipse(63, 91, 6, 4, 0)
    line(58, 89, 64, 87, 7)
    # Dark barrel silhouette first, then one illuminated edge and muzzle.
    poly([(77, 94), (123, 69), (128, 71), (128, 77), (81, 101)], 0)
    poly([(80, 93), (124, 70), (126, 73), (83, 97)], 11)
    line(80, 93, 124, 70, 7)
    line(124, 71, 126, 72, 7)
    box(126, 73, 127, 76, 0)
    line(53, 86, 48, 70, 0)
    line(53, 86, 49, 71, 11)
    return canvas


def encode(canvas):
    bitmap, screen, colors = bytearray(), bytearray(), bytearray()
    decoded = [[0] * W for _ in range(H)]
    for cy in range(25):
        for cx in range(40):
            pixels = [canvas[cy * 8 + yy][cx * 4 + xx]
                      for yy in range(8) for xx in range(4)]
            preferred = (11, 1, 7) if cy < 6 or cy >= 17 else (6, 11, 7)
            counts = Counter(c for c in pixels if c)
            if all(c in preferred for c in counts):
                local = preferred
            else:
                selected = sorted(counts, key=lambda c: (-counts[c], c))[:3]
                # Stable ordering improves packing of adjacent cell attributes.
                order = (6, 11, 5, 7, 1, 15, 12, 9, 8, 13, 14, 2, 3, 4, 10)
                local = tuple(c for c in order if c in selected)
                local += tuple(c for c in preferred if c not in local)[:3 - len(local)]
            assert len(local) == 3 and all(0 < c < 16 for c in local)
            native = (0,) + local
            screen.append(local[0] << 4 | local[1])
            colors.append(local[2])
            for yy in range(8):
                value = 0
                for xx in range(4):
                    original = pixels[yy * 4 + xx]
                    if original in native:
                        index = native.index(original)
                    else:
                        rgb = PALETTE[original]
                        index = min(range(4), key=lambda n: sum(
                            (rgb[k] - PALETTE[native[n]][k]) ** 2 for k in range(3)))
                    value |= index << (6 - 2 * xx)
                    decoded[cy * 8 + yy][cx * 4 + xx] = native[index]
                bitmap.append(value)
    assert len(bitmap) == 8000 and len(screen) == len(colors) == 1000
    assert all(c == 0 for row in decoded[136:] for c in row)
    assert screen[680:] == bytes([0xB1] * 320) and colors[680:] == bytes([7] * 320)
    return bytes(bitmap + screen + colors), decoded


def rle(data):
    packed = bytearray()
    at = 0
    while at < len(data):
        count = 1
        while count < 255 and at + count < len(data) and data[at + count] == data[at]:
            count += 1
        packed.extend((count, data[at]))
        at += count
    assert bytes(v for n, v in zip(packed[::2], packed[1::2]) for _ in range(n)) == data
    return packed


def png(path, canvas, scale=2):
    # MC pixels are twice as wide physically. Preview preserves that aspect.
    width, height = W * 2 * scale, H * scale
    rows = bytearray()
    for row in canvas:
        pixels = b"".join(bytes(PALETTE[c]) * (2 * scale) for c in row)
        for _ in range(scale):
            rows += b"\0" + pixels

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">2I5B", width, height, 8, 2, 0, 0, 0)) +
                     chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    raw, decoded = encode(scene())
    packed = rle(raw)
    assert len(packed) <= 4000, f"Title exceeds packed budget: {len(packed)} bytes"
    (OUT / "title_packed.bin").write_bytes(packed)
    (OUT / "title_bitmap.bin").write_bytes(raw[:8000])
    (OUT / "title_screen.bin").write_bytes(raw[8000:9000])
    (OUT / "title_colors.bin").write_bytes(raw[9000:])
    (OUT / "title.inc").write_text('.segment "RODATA"\n.export title_packed, title_packed_end\n'
                                   'title_packed:\n.incbin "title_packed.bin"\n'
                                   'title_packed_end:\n'
                                   '.assert title_packed_end-title_packed <= 4000, error, "Title packing budget"\n')
    png(OUT / "title.png", decoded)
    print(f"Ironveil title: 10,000 native bytes -> {len(packed)} count/value RLE bytes")


if __name__ == "__main__":
    main()
