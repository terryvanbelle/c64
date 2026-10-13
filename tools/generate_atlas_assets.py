#!/usr/bin/env python3
"""Original, deterministic character and sprite art for the C64 atlas.

All 8 x 8 glyphs are hires: one foreground color over the global black
background. ASCII 32..95 is a compact, original HUD font. Terrain is drawn as
16 x 16 metatiles, each four characters in TL, TR, BL, BR order. Graphic
characters occupy 96..247. Rivers and roads use connection bits N=1, E=2,
S=4, W=8; their 16 masks each occupy four consecutive glyphs. Bridges reuse
road geometry with a separate color. The army is a 24 x 21 hardware sprite
with 16 x 16 content at its top left. Four frames ripple its flag and legs.
Only Python's standard library is required. No external source art is used.
"""

from pathlib import Path
import struct
import zlib


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "atlas"
PALETTE = (
    (0, 0, 0), (255, 255, 255), (137, 64, 54), (122, 191, 199),
    (138, 70, 174), (104, 169, 65), (62, 49, 162), (208, 220, 113),
    (144, 95, 37), (92, 71, 0), (187, 119, 109), (85, 85, 85),
    (128, 128, 128), (172, 234, 136), (124, 112, 218), (171, 171, 171),
)
N, E, S, W = 1, 2, 4, 8
TERRAINS = (
    ("WATER", 96, 6, 0), ("GRASS", 100, 13, 0),
    ("FOREST", 104, 5, 0), ("DESERT", 108, 7, 0),
    ("MOUNTAIN", 112, 15, 0), ("RIVER", 184, 3, 15),
    ("CITY", 116, 1, 0), ("ROAD", 120, 8, 15),
    ("BRIDGE", 120, 7, 15),
)


# Five-bit rows; a one-pixel margin leaves the text legible over dense tiles.
# This is an explicit editable design, independent of the C64 character ROM.
FONT = {
    " ": [0, 0, 0, 0, 0, 0, 0],
    "!": [4, 4, 4, 4, 4, 0, 4], '"': [10, 10, 10, 0, 0, 0, 0],
    "#": [10, 31, 10, 10, 31, 10, 0], "$": [4, 15, 20, 14, 5, 30, 4],
    "%": [25, 25, 2, 4, 8, 19, 19], "&": [12, 18, 20, 8, 21, 18, 13],
    "'": [4, 4, 8, 0, 0, 0, 0], "(": [2, 4, 8, 8, 8, 4, 2],
    ")": [8, 4, 2, 2, 2, 4, 8], "*": [0, 21, 14, 31, 14, 21, 0],
    "+": [0, 4, 4, 31, 4, 4, 0], ",": [0, 0, 0, 0, 0, 4, 8],
    "-": [0, 0, 0, 31, 0, 0, 0], ".": [0, 0, 0, 0, 0, 0, 4],
    "/": [1, 1, 2, 4, 8, 16, 16],
    "0": [14, 17, 19, 21, 25, 17, 14], "1": [4, 12, 4, 4, 4, 4, 14],
    "2": [14, 17, 1, 2, 4, 8, 31], "3": [30, 1, 1, 14, 1, 1, 30],
    "4": [2, 6, 10, 18, 31, 2, 2], "5": [31, 16, 16, 30, 1, 1, 30],
    "6": [14, 16, 16, 30, 17, 17, 14], "7": [31, 1, 2, 4, 8, 8, 8],
    "8": [14, 17, 17, 14, 17, 17, 14], "9": [14, 17, 17, 15, 1, 1, 14],
    ":": [0, 4, 0, 0, 4, 0, 0], ";": [0, 4, 0, 0, 4, 4, 8],
    "<": [1, 2, 4, 8, 4, 2, 1], "=": [0, 0, 31, 0, 31, 0, 0],
    ">": [16, 8, 4, 2, 4, 8, 16], "?": [14, 17, 1, 2, 4, 0, 4],
    "@": [14, 17, 23, 21, 23, 16, 14],
    "A": [14, 17, 17, 31, 17, 17, 17], "B": [30, 17, 17, 30, 17, 17, 30],
    "C": [14, 17, 16, 16, 16, 17, 14], "D": [30, 17, 17, 17, 17, 17, 30],
    "E": [31, 16, 16, 30, 16, 16, 31], "F": [31, 16, 16, 30, 16, 16, 16],
    "G": [14, 17, 16, 23, 17, 17, 15], "H": [17, 17, 17, 31, 17, 17, 17],
    "I": [14, 4, 4, 4, 4, 4, 14], "J": [7, 2, 2, 2, 2, 18, 12],
    "K": [17, 18, 20, 24, 20, 18, 17], "L": [16, 16, 16, 16, 16, 16, 31],
    "M": [17, 27, 21, 21, 17, 17, 17], "N": [17, 25, 21, 19, 17, 17, 17],
    "O": [14, 17, 17, 17, 17, 17, 14], "P": [30, 17, 17, 30, 16, 16, 16],
    "Q": [14, 17, 17, 17, 21, 18, 13], "R": [30, 17, 17, 30, 20, 18, 17],
    "S": [15, 16, 16, 14, 1, 1, 30], "T": [31, 4, 4, 4, 4, 4, 4],
    "U": [17, 17, 17, 17, 17, 17, 14], "V": [17, 17, 17, 17, 17, 10, 4],
    "W": [17, 17, 17, 21, 21, 27, 17], "X": [17, 17, 10, 4, 10, 17, 17],
    "Y": [17, 17, 10, 4, 4, 4, 4], "Z": [31, 1, 2, 4, 8, 16, 31],
    "[": [14, 8, 8, 8, 8, 8, 14], "\\": [16, 16, 8, 4, 2, 1, 1],
    "]": [14, 2, 2, 2, 2, 2, 14], "^": [4, 10, 17, 0, 0, 0, 0],
    "_": [0, 0, 0, 0, 0, 0, 31],
}


def rows(*strings):
    assert len(strings) == 8 and all(len(row) == 8 for row in strings)
    return bytes(sum((character != ".") << (7 - x)
                     for x, character in enumerate(row)) for row in strings)


def canvas(width=8, height=8):
    return [[0] * width for _ in range(height)]


def dot(grid, x, y, value=1):
    if 0 <= y < len(grid) and 0 <= x < len(grid[0]):
        grid[y][x] = value


def line(grid, ax, ay, bx, by, value=1):
    dx, dy = bx - ax, by - ay
    steps = max(abs(dx), abs(dy))
    for step in range(steps + 1):
        t = step / max(1, steps)
        dot(grid, round(ax + t * dx), round(ay + t * dy), value)


def packed(grid):
    assert len(grid[0]) == 8
    return bytes(sum(bool(value) << (7 - x) for x, value in enumerate(row))
                 for row in grid)


def metatile(grid):
    """Pack a 16 x 16 image into TL, TR, BL, BR VIC characters."""
    assert len(grid) == 16 and all(len(row) == 16 for row in grid)
    return b"".join(packed([row[left:left + 8] for row in grid[top:top + 8]])
                    for top, left in ((0, 0), (0, 8), (8, 0), (8, 8)))


def texture(kind):
    grid = canvas(16, 16)
    if kind == "WATER":
        # An offset set of gently broken wave crests, never random noise.
        for y, phase in ((2, 0), (7, 5), (12, 9)):
            for x in range(16):
                if (x + phase) % 12 not in (0, 1, 2):
                    dot(grid, x, y + int((x + phase) % 12 >= 7))
        for x, y in ((1, 10), (7, 4), (12, 15), (15, 5)):
            dot(grid, x, y)
            dot(grid, x + 1, y)
    elif kind == "GRASS":
        # Deliberate clustered turf tufts with open ground between them.
        for x, y in ((2, 1), (10, 3), (6, 7), (14, 9), (2, 12), (9, 14)):
            dot(grid, x, y)
            dot(grid, x - 1, y + 1)
            dot(grid, x + 1, y + 1)
        for x, y in ((14, 0), (5, 4), (0, 6), (11, 11), (5, 15)):
            dot(grid, x, y)
    elif kind == "FOREST":
        # Three staggered conifers, with readable trunks below the crowns.
        for tx, ty, height in ((4, 4, 9), (11, 0, 11), (12, 10, 6), (2, 12, 4)):
            for depth in range(height - 1):
                half = min(3, depth // 2)
                for x in range(tx - half, tx + half + 1):
                    dot(grid, x, ty + depth)
                if depth > 2 and depth % 2 == 1:
                    dot(grid, tx - half, ty + depth, 0)
                    dot(grid, tx + half, ty + depth, 0)
            dot(grid, tx, ty + height - 1)
    elif kind == "DESERT":
        # Wide wind-shaped dune contours and a few low sand ridges.
        for x in range(16):
            y = 2 + abs(8 - x) // 4
            dot(grid, x, y)
            y = 10 + abs(3 - x) // 5
            dot(grid, x, y)
            if x % 3 == 1:
                dot(grid, x, y + 2)
        for x, y in ((3, 6), (4, 6), (10, 7), (11, 7), (14, 5), (0, 15)):
            dot(grid, x, y)
    elif kind == "MOUNTAIN":
        # Jagged range: a pale ridge, a broad lit face, dark right scree.
        for px, py in ((5, 1), (12, 5)):
            line(grid, px - 6, 15, px, py)
            line(grid, px, py, px + 7, 15)
            for y in range(py + 2, 16):
                left = max(0, px - (y - py) // 2)
                for x in range(left, min(px + 1, 16)):
                    if (x + y) % 4 != 0:
                        dot(grid, x, y)
            line(grid, px, py, px - 1, py + 4)
            dot(grid, px + 1, py + 1)
    elif kind == "CITY":
        # Compact fortified skylines: crenellations, gate, then masonry.
        for cx, top in ((3, 4), (8, 1), (13, 4)):
            line(grid, cx, top, cx - 2, top + 2)
            line(grid, cx, top, cx + 2, top + 2)
            for y in range(top + 3, 13):
                for x in range(cx - 1, cx + 2):
                    dot(grid, x, y)
            dot(grid, cx, top + 4, 0)
            dot(grid, cx, top + 7, 0)
        for y in range(8, 14):
            for x in range(1, 15):
                if y == 8 or y == 13 or x in (1, 14) or (x + y) % 3 != 0:
                    dot(grid, x, y)
        for y in range(10, 14):
            dot(grid, 7, y, 0)
            dot(grid, 8, y, 0)
        line(grid, 2, 15, 13, 15)
    return metatile(grid)


def connected(kind, mask):
    grid = canvas(16, 16)
    # The route center is identical at every edge, so adjacent tiles meet.
    endpoints = ((N, 7, 0), (E, 15, 7), (S, 7, 15), (W, 0, 7))
    if kind == "RIVER":
        for bit, x, y in endpoints:
            if mask & bit:
                for offset in (-1, 0, 1, 2):
                    if x == 7:
                        line(grid, 7 + offset, 7, x + offset, y)
                    else:
                        line(grid, 7, 7 + offset, x, y + offset)
        for y in (6, 7, 8, 9):
            for x in (6, 7, 8, 9):
                dot(grid, x, y)
        # Small glints carved into the broad channel (still connected).
        if mask & N:
            line(grid, 7, 1, 7, 3, 0)
            dot(grid, 9, 5, 0)
        if mask & E:
            line(grid, 11, 7, 13, 7, 0)
            dot(grid, 10, 9, 0)
        if mask & S:
            line(grid, 8, 11, 8, 13, 0)
            dot(grid, 6, 10, 0)
        if mask & W:
            line(grid, 1, 8, 3, 8, 0)
            dot(grid, 5, 6, 0)
    else:
        for bit, x, y in endpoints:
            if mask & bit:
                line(grid, 7, 7, x, y)
                if x == 7:
                    line(grid, 8, 7, 8, y)
                else:
                    line(grid, 7, 8, x, 8)
        for y in (7, 8):
            for x in (7, 8):
                dot(grid, x, y)
        # A tiny verge makes straight routes distinct from font rules.
        for bit, x, y in endpoints:
            if mask & bit:
                if x == 7:
                    for yy in ((2, 13) if y else (2,)):
                        dot(grid, 5, yy)
                        dot(grid, 10, yy + 1)
                else:
                    for xx in ((2, 13) if x else (2,)):
                        dot(grid, xx, 5)
                        dot(grid, xx + 1, 10)
    return metatile(grid)


def army(frame):
    grid = canvas(24, 21)
    # Pole and pennant; the full icon fits one 16 x 16 map tile.
    line(grid, 1, 0, 1, 13)
    for x in range(2, 11):
        top = 1 + ((x + frame) // 3) % 2
        for y in range(top, top + 4 - (x - 2) // 4):
            dot(grid, x, y)
    # Three helmeted soldiers standing under the standard.
    for index, (cx, cy) in enumerate(((3, 10), (8, 8), (13, 10))):
        line(grid, cx - 1, cy, cx + 1, cy)
        dot(grid, cx, cy - 1)
        dot(grid, cx, cy + 1)
        line(grid, cx - 1, cy + 2, cx + 1, cy + 2)
        dot(grid, cx, cy + 3)
        stride = (frame + index) & 1
        dot(grid, cx - stride, cy + 4)
        dot(grid, cx + stride, cy + 4)
    result = bytearray()
    for row in grid:
        for offset in (0, 8, 16):
            result.append(sum(bool(row[offset + x]) << (7 - x) for x in range(8)))
    result.append(0)
    assert len(result) == 64
    return bytes(result)


def png(path, width, height, rgb):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(
            ">I", zlib.crc32(kind + data) & 0xffffffff)
    raw = b"".join(b"\0" + bytes(rgb[y * width * 3:(y + 1) * width * 3])
                   for y in range(height))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(
        ">IIBBBBB", width, height, 8, 2, 0, 0, 0)) +
        chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def contact_sheet(charset, sprites):
    scale, columns, cell = 4, 16, 12
    width, height = columns * cell * scale, 18 * cell * scale
    rgb = bytearray(bytes((12, 16, 20)) * (width * height))

    def pixel(x, y, color):
        for dy in range(scale):
            for dx in range(scale):
                offset = ((y * scale + dy) * width + x * scale + dx) * 3
                rgb[offset:offset + 3] = bytes(PALETTE[color])

    colors = {code: color for name, base, color, mask in TERRAINS
              if name != "BRIDGE"
              for code in range(base, base + (mask + 1) * 4)}
    for code in range(256):
        gx, gy = (code % columns) * cell + 2, (code // columns) * cell + 2
        data = charset[code * 8:code * 8 + 8]
        for y, row in enumerate(data):
            for x in range(8):
                pixel(gx + x, gy + y, colors.get(code, 7) if row & (128 >> x) else 0)
    for frame in range(4):
        gx, gy = frame * 48 + 4, 16 * cell
        for y in range(21):
            for x in range(24):
                byte = sprites[frame * 64 + y * 3 + x // 8]
                pixel(gx + x, gy + y, 1 if byte & (128 >> (x & 7)) else 0)
    png(OUT / "assets.png", width, height, rgb)


def tile_sheet(charset):
    """Show whole metatiles, plus road/river bends rather than split glyphs."""
    scale, width, height = 4, 240, 144
    rgb = bytearray(width * height * scale * scale * 3)
    examples = [(name, base, color) for name, base, color, _ in TERRAINS]
    for index, (name, base, color) in enumerate(examples):
        origin_x, origin_y = (index % 3) * 80 + 8, (index // 3) * 48 + 3
        variant = 5 if name == "RIVER" else 15 if name in ("ROAD", "BRIDGE") else 0
        first = base + variant * 4

        def cell(glyph, ox, oy, foreground):
            for y, row in enumerate(charset[glyph * 8:glyph * 8 + 8]):
                for x in range(8):
                    if row & (128 >> x):
                        for yy in range(scale):
                            for xx in range(scale):
                                offset = (((oy + y) * scale + yy) * width * scale +
                                          (ox + x) * scale + xx) * 3
                                rgb[offset:offset + 3] = bytes(PALETTE[foreground])

        for quadrant, (dx, dy) in enumerate(((0, 0), (8, 0), (0, 8), (8, 8))):
            cell(first + quadrant, origin_x + dx, origin_y + dy, color)
        for character, letter in enumerate(name):
            cell(ord(letter), origin_x - 4 + character * 8, origin_y + 24, 15)
    png(OUT / "tiles.png", width * scale, height * scale, rgb)


def sprite_shadow(sprites):
    """Optional black rear sprite: a one-pixel rim around the white icon."""
    result = bytearray()
    for frame in range(4):
        grid = canvas(24, 21)
        for y in range(16):
            for x in range(16):
                byte = sprites[frame * 64 + y * 3 + x // 8]
                if byte & (128 >> (x & 7)):
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            if 0 <= x + dx < 16 and 0 <= y + dy < 16:
                                dot(grid, x + dx, y + dy)
        for row in grid:
            for offset in (0, 8, 16):
                result.append(sum(bool(row[offset + x]) << (7 - x)
                                  for x in range(8)))
        result.append(0)
    assert len(result) == 256
    return result


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    charset = bytearray(2048)
    for code in range(32, 96):
        glyph = FONT[chr(code)]
        assert len(glyph) == 7 and all(0 <= row < 32 for row in glyph)
        charset[code * 8:code * 8 + 8] = bytes([0] + [row << 2 for row in glyph])
    for name, base, _, mask in TERRAINS:
        if name == "BRIDGE":
            continue  # Same glyphs as ROAD, independently recolored at runtime.
        for variant in range(mask + 1):
            data = connected(name, variant) if mask == 15 else texture(name)
            assert len(data) == 32
            first = base + variant * 4
            charset[first * 8:(first + 4) * 8] = data
    # Optional horizontal rule / compact directional indicators in spare slots.
    charset[248 * 8:249 * 8] = bytes([0, 0, 0, 255, 0, 0, 0, 0])
    charset[249 * 8:250 * 8] = rows("...#....", "..###...", ".#####..", "...#....",
                                    "...#....", "...#....", "........", "........")
    charset[250 * 8:251 * 8] = rows("...#....", "...#....", "...#....", ".#####..",
                                    "..###...", "...#....", "........", "........")
    charset[251 * 8:252 * 8] = rows("........", "..#.....", ".##.....", "#######.",
                                    ".##.....", "..#.....", "........", "........")
    charset[252 * 8:253 * 8] = rows("........", "....#...", "....##..", ".#######",
                                    "....##..", "....#...", "........", "........")
    sprites = b"".join(army(frame) for frame in range(4))
    assert len(charset) == 2048 and len(sprites) == 256
    (OUT / "charset.bin").write_bytes(charset)
    (OUT / "sprites.bin").write_bytes(sprites)
    (OUT / "army_shadow.bin").write_bytes(sprite_shadow(sprites))
    include = ["; Generated by tools/generate_atlas_assets.py. Do not edit.",
               "; Connection bits: north=1 east=2 south=4 west=8."]
    for index, (name, base, color, mask) in enumerate(TERRAINS):
        include += [f"ATLAS_TILE_{name} = {index}", f"ATLAS_GLYPH_{name} = {base}"]
    include += ["ATLAS_METATILE_STRIDE = 4", "ATLAS_GLYPH_RULE = 248",
                "ATLAS_ARMY_FRAMES = 4",
                "ATLAS_ARMY_ORIGIN_X = 0", "ATLAS_ARMY_ORIGIN_Y = 0",
                '.segment "RODATA"', "atlas_tile_base:",
                "    .byte " + ",".join(str(base) for _, base, _, _ in TERRAINS),
                "atlas_tile_color:",
                "    .byte " + ",".join(str(color) for _, _, color, _ in TERRAINS),
                "atlas_tile_variant_mask:",
                "    .byte " + ",".join(str(mask) for _, _, _, mask in TERRAINS),
                "atlas_tile_masks:", "    .byte 0,0,0,0,0,5,0,15,5"]
    (OUT / "assets.inc").write_text("\n".join(include) + "\n")
    contact_sheet(charset, sprites)
    tile_sheet(charset)
    print(f"Atlas assets: {len(charset)} charset bytes, {len(sprites)} sprite bytes")


if __name__ == "__main__":
    main()
