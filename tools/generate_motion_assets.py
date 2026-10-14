#!/usr/bin/env python3
"""Original deterministic character and sprite artwork for Borrowed Motion.

The editable artwork is the geometry in this file.  It uses a stock VIC-II
hires character screen (one foreground colour per 8x8 cell, black background),
plus ordinary 24x21 hires hardware sprites.  No external images or libraries
are required.  The small 5x7 interface alphabet is shared with the repository's
original Atlas alphabet; the illustration, ornaments, tile and sprite art are
new for this game.

Runtime contracts:
  * font_source: 256 x 8 bytes; uppercase screen codes 1..26, space 32,
    digits 48..57, arrows E/S/W/N 64..67 and 68..71, still marker 72.
  * tiles 0..6: four characters at 96 + tile*4, TL/TR/BL/BR order.
  * sprite_source: 57 x 64 bytes; pearls 0..3, bells 4..7, selection rings
    8..11, predicted position 12, dissolution sparks 13..16. Directional
    pearls 17..36 and bells 37..56 each have five motions (still/E/S/W/N),
    with four frames per motion. Each sprite retains centre (12,10).
  * title_screen_source / title_color_source: 1000 bytes each. Rows 20..24
    are blank for runtime setup/help. The title illustration uses glyphs
    124..255; all game and interface glyphs remain available concurrently.

Run from any directory. Output: build/motion/assets.inc and art-preview.png.
"""

from pathlib import Path
import math
import struct
import zlib

from generate_atlas_assets import FONT, PALETTE

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "motion"
W, H = 320, 200


def canvas(w, h):
    return [[0] * w for _ in range(h)]


def dot(a, x, y, v=1):
    if 0 <= x < len(a[0]) and 0 <= y < len(a):
        a[y][x] = v


def line(a, x0, y0, x1, y1, v=1):
    dx, sx = abs(x1 - x0), 1 if x0 < x1 else -1
    dy, sy = -abs(y1 - y0), 1 if y0 < y1 else -1
    err = dx + dy
    while True:
        dot(a, x0, y0, v)
        if x0 == x1 and y0 == y1:
            break
        twice = err * 2
        if twice >= dy:
            err += dy
            x0 += sx
        if twice <= dx:
            err += dx
            y0 += sy


def rect(a, x0, y0, x1, y1, v=1, fill=False):
    if fill:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                dot(a, x, y, v)
    else:
        line(a, x0, y0, x1, y0, v)
        line(a, x0, y1, x1, y1, v)
        line(a, x0, y0, x0, y1, v)
        line(a, x1, y0, x1, y1, v)


def ellipse(a, cx, cy, rx, ry, v=1, fill=False):
    if fill:
        for y in range(cy - ry, cy + ry + 1):
            for x in range(cx - rx, cx + rx + 1):
                if (x-cx)**2 * ry**2 + (y-cy)**2 * rx**2 <= rx**2 * ry**2:
                    dot(a, x, y, v)
    else:
        previous = None
        for step in range(257):
            angle = step * math.tau / 256
            point = (round(cx + rx * math.cos(angle)),
                     round(cy + ry * math.sin(angle)))
            if previous is not None:
                line(a, *previous, *point, v)
            previous = point


def diamond(a, cx, cy, radius, v=1):
    pts = ((cx, cy-radius), (cx+radius, cy),
           (cx, cy+radius), (cx-radius, cy), (cx, cy-radius))
    for p, q in zip(pts, pts[1:]):
        line(a, *p, *q, v)


def pack_char(a, left=0, top=0):
    return bytes(sum(bool(a[top+y][left+x]) << (7-x) for x in range(8))
                 for y in range(8))


def screen_code(char):
    return ord(char) - 64 if 64 <= ord(char) <= 95 else ord(char)


def font_and_tiles():
    glyphs = [bytes(8) for _ in range(256)]
    for char, rows in FONT.items():
        code = screen_code(char)
        glyphs[code] = bytes([value << 2 for value in rows] + [0])

    # HUD directions are graphical screen codes rather than letter aliases.
    for direction in range(4):
        for long_form in range(2):
            a = canvas(8, 8)
            if direction == 0:
                line(a, 1 if long_form else 2, 3, 6, 3)
                line(a, 4, 1, 6, 3)
                line(a, 6, 3, 4, 5)
            elif direction == 1:
                line(a, 3, 1 if long_form else 2, 3, 6)
                line(a, 1, 4, 3, 6)
                line(a, 3, 6, 5, 4)
            elif direction == 2:
                line(a, 1, 3, 6 if long_form else 5, 3)
                line(a, 1, 3, 3, 1)
                line(a, 1, 3, 3, 5)
            else:
                line(a, 3, 1, 3, 6 if long_form else 5)
                line(a, 1, 3, 3, 1)
                line(a, 3, 1, 5, 3)
            if long_form:
                # A second tail notch makes fast motion distinct in monochrome.
                if direction in (0, 2):
                    dot(a, 1 if direction == 0 else 6, 2)
                    dot(a, 1 if direction == 0 else 6, 4)
                else:
                    dot(a, 2, 1 if direction == 1 else 6)
                    dot(a, 4, 1 if direction == 1 else 6)
            glyphs[64 + long_form*4 + direction] = pack_char(a)
    a = canvas(8, 8)
    diamond(a, 3, 3, 2)
    glyphs[72] = pack_char(a)

    # Optional HUD ornament characters, separate from the gameplay metatiles.
    for code, shape in ((73, "horizontal"), (74, "vertical"), (75, "lozenge"),
                        (76, "dot"), (77, "spark"), (78, "pause")):
        a = canvas(8, 8)
        if shape == "horizontal":
            line(a, 0, 3, 7, 3)
        elif shape == "vertical":
            line(a, 3, 0, 3, 7)
        elif shape == "lozenge":
            diamond(a, 3, 3, 3)
            dot(a, 3, 3)
        elif shape == "dot":
            dot(a, 3, 3)
        elif shape == "spark":
            line(a, 3, 0, 3, 6)
            line(a, 0, 3, 6, 3)
            dot(a, 2, 2)
            dot(a, 4, 4)
        elif shape == "pause":
            rect(a, 1, 1, 2, 6, fill=True)
            rect(a, 5, 1, 6, 6, fill=True)
        glyphs[code] = pack_char(a)

    tiles = []
    colors = [
        (6, 6, 6, 6),       # Quiet star dust.
        (8, 9, 9, 8),       # Brass architectural cases.
        (3, 1, 1, 3),       # Specular mirrors.
        (1, 3, 3, 1),
        (7, 7, 8, 8),       # Open brass cradle.
        (14, 3, 3, 14),     # Slowing glass.
        (13, 7, 7, 13),     # Fulfilled cradle blossoms.
    ]
    for kind in range(7):
        a = canvas(16, 16)
        if kind == 0:
            dot(a, 3, 3)
            dot(a, 12, 11)
        elif kind == 1:
            # Bevelled archive case; broad quiet faces keep walls readable.
            line(a, 2, 0, 13, 0)
            line(a, 0, 2, 0, 13)
            line(a, 2, 15, 13, 15)
            line(a, 15, 2, 15, 13)
            for x, y, sx, sy in ((1, 1, 1, 1), (14, 1, -1, 1),
                                  (1, 14, 1, -1), (14, 14, -1, -1)):
                dot(a, x, y)
                line(a, x+sx, y+2*sy, x+sx, y+4*sy)
                line(a, x+2*sx, y+sy, x+4*sx, y+sy)
            diamond(a, 7, 7, 2)
            dot(a, 8, 8)
        elif kind in (2, 3):
            # Visible end caps and a two-pixel silver face.
            if kind == 2:
                line(a, 2, 13, 13, 2)
                line(a, 3, 13, 13, 3)
                line(a, 1, 12, 3, 14)
                line(a, 12, 1, 14, 3)
                dot(a, 4, 12)
                dot(a, 12, 4)
            else:
                line(a, 2, 2, 13, 13)
                line(a, 3, 2, 13, 12)
                line(a, 1, 3, 3, 1)
                line(a, 12, 14, 14, 12)
                dot(a, 4, 3)
                dot(a, 12, 11)
        elif kind == 4:
            # The empty centre remains visibly open for a pearl.
            line(a, 2, 7, 2, 11)
            line(a, 13, 7, 13, 11)
            line(a, 2, 11, 5, 14)
            line(a, 13, 11, 10, 14)
            line(a, 5, 14, 10, 14)
            line(a, 4, 10, 6, 12)
            line(a, 11, 10, 9, 12)
            line(a, 6, 12, 9, 12)
            dot(a, 1, 6)
            dot(a, 14, 6)
            line(a, 6, 15, 9, 15)
        elif kind == 5:
            # Faceted hourglass, recognisable without its violet colour.
            line(a, 3, 1, 12, 1)
            line(a, 3, 14, 12, 14)
            line(a, 4, 2, 4, 4)
            line(a, 11, 2, 11, 4)
            line(a, 4, 4, 8, 8)
            line(a, 11, 4, 7, 8)
            line(a, 8, 8, 11, 11)
            line(a, 7, 8, 4, 11)
            line(a, 4, 11, 4, 13)
            line(a, 11, 11, 11, 13)
            line(a, 5, 12, 10, 12)
            dot(a, 7, 5)
            dot(a, 8, 5)
        else:
            # A once-empty cradle now unfolds into a fourfold star bloom.
            diamond(a, 7, 7, 6)
            diamond(a, 7, 7, 3)
            line(a, 7, 0, 7, 3)
            line(a, 7, 11, 7, 15)
            line(a, 0, 7, 3, 7)
            line(a, 11, 7, 15, 7)
            dot(a, 7, 7)
            dot(a, 2, 2)
            dot(a, 12, 12)
        tiles.append(a)
        for part, (x, y) in enumerate(((0, 0), (8, 0), (0, 8), (8, 8))):
            glyphs[96 + kind*4 + part] = pack_char(a, x, y)
    return glyphs, bytes(c for row in colors for c in row)


def sprite_art():
    frames = []
    for frame in range(4):
        a = canvas(24, 21)
        # The slightly scalloped opaque body gives a pearl a stable silhouette.
        ellipse(a, 12, 10, 6, 6, fill=True)
        ellipse(a, 13, 11, 4, 4, 0, fill=True)
        # A bright internal crescent and shifting specular point.
        line(a, 8, 8, 9, 6)
        line(a, 8, 8, 8, 11)
        for x, y in ((11, 6), (10, 7), (10, 8), (11, 7)):
            dot(a, x, y)
        dot(a, 14, 13)
        dot(a, 12 + (frame & 1), 9 + (frame >> 1))
        if frame == 1:
            dot(a, 18, 5)
        if frame == 3:
            dot(a, 6, 15)
        frames.append(a)
    for frame in range(4):
        a = canvas(24, 21)
        # Hollow, angular resonator. Unlike the circular pearl it reads as metal.
        line(a, 10, 3, 14, 3)
        line(a, 10, 3, 8, 6)
        line(a, 14, 3, 16, 6)
        line(a, 8, 6, 7, 12)
        line(a, 16, 6, 17, 12)
        line(a, 7, 12, 5, 15)
        line(a, 17, 12, 19, 15)
        line(a, 5, 15, 19, 15)
        line(a, 7, 17, 17, 17)
        line(a, 10, 6, 10, 10)
        diamond(a, 12, 10, 2)
        dot(a, 12 + (frame == 1) - (frame == 3), 18)
        if frame & 1:
            dot(a, 3, 10)
            dot(a, 21, 10)
        frames.append(a)
    for frame in range(4):
        a = canvas(24, 21)
        inset = 1 if frame in (1, 2) else 0
        # Corner brackets mark selection without hiding the body beneath them.
        for x, y, sx, sy in ((1+inset, 1+inset, 1, 1),
                             (22-inset, 1+inset, -1, 1),
                             (1+inset, 19-inset, 1, -1),
                             (22-inset, 19-inset, -1, -1)):
            line(a, x, y, x+sx*4, y)
            line(a, x, y, x, y+sy*4)
        dot(a, 12, inset)
        dot(a, 12, 20-inset)
        frames.append(a)
    a = canvas(24, 21)
    diamond(a, 12, 10, 4)
    dot(a, 12, 10)
    frames.append(a)
    for frame in range(4):
        a = canvas(24, 21)
        r = 2 + frame*2
        for dx, dy in ((1, 0), (0, 1), (-1, 0), (0, -1)):
            line(a, 12+dx*r, 10+dy*r,
                 12+dx*(r+2), 10+dy*(r+2))
        if frame < 3:
            for dx, dy in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
                dot(a, 12+dx*(r-1), 10+dy*(r-1))
        if frame == 0:
            diamond(a, 12, 10, 2)
        frames.append(a)
    assert len(frames) == 17
    # Every actor carries its own motion indicator. These remain solid while
    # the pearl highlights / bell clappers animate, avoiding ambiguous flicker.
    # Frame = 17 + type*20 + motion*4 + animation; motion 0/1/2/3/4 = still/E/S/W/N.
    for actor_type in range(2):
        for motion in range(5):
            for phase in range(4):
                a = [row[:] for row in frames[actor_type*4+phase]]
                if motion == 0:
                    rect(a, 9, 18, 15, 20, 0, fill=True)
                    line(a, 10, 18, 10, 20)
                    line(a, 14, 18, 14, 20)
                elif motion == 1:
                    line(a, 19, 10, 22, 10)
                    line(a, 20, 8, 22, 10)
                    line(a, 22, 10, 20, 12)
                elif motion == 2:
                    rect(a, 9, 18, 15, 20, 0, fill=True)
                    line(a, 12, 17, 12, 20)
                    line(a, 10, 18, 12, 20)
                    line(a, 12, 20, 14, 18)
                elif motion == 3:
                    line(a, 1, 10, 4, 10)
                    line(a, 1, 10, 3, 8)
                    line(a, 1, 10, 3, 12)
                else:
                    line(a, 12, 0, 12, 3)
                    line(a, 10, 2, 12, 0)
                    line(a, 12, 0, 14, 2)
                frames.append(a)
    assert len(frames) == 57
    data = bytearray()
    for a in frames:
        for row in a:
            for x in (0, 8, 16):
                data.append(sum(bool(row[x+i]) << (7-i) for i in range(8)))
        data.append(0)
    return bytes(data), frames


def draw_title(glyphs):
    """Compose an illustration from reusable exact 8x8 C64 character shapes."""
    screen = [32] * 1000
    colors = [0] * 1000
    used = {glyph: code for code, glyph in enumerate(glyphs[:124])}
    next_code = 124

    def place(col, row, pattern, color):
        nonlocal next_code
        if pattern not in used:
            assert next_code < 256, f"Title needs more than 132 custom glyphs ({next_code})"
            used[pattern] = next_code
            glyphs[next_code] = pattern
            next_code += 1
        screen[row*40+col] = used[pattern]
        colors[row*40+col] = color

    def art(a, col, row, color):
        assert len(a) % 8 == 0 and len(a[0]) % 8 == 0
        for y in range(0, len(a), 8):
            for x in range(0, len(a[0]), 8):
                pattern = pack_char(a, x, y)
                if any(pattern):
                    chosen = color(col+x//8, row+y//8) if callable(color) else color
                    place(col+x//8, row+y//8, pattern, chosen)

    def text(value, col, row, color):
        for i, char in enumerate(value):
            screen[row*40+col+i] = screen_code(char)
            colors[row*40+col+i] = color

    # Small stars reuse an exactly aligned shape, conserving precious glyphs.
    star = canvas(8, 8)
    dot(star, 3, 3)
    star4 = canvas(8, 8)
    line(star4, 3, 1, 3, 5)
    line(star4, 1, 3, 5, 3)
    for col, row, bright in ((2, 2, 0), (36, 2, 0), (5, 6, 1), (34, 7, 0),
                              (2, 10, 0), (37, 12, 1), (7, 14, 0), (32, 16, 0),
                              (3, 18, 1), (35, 18, 0), (10, 8, 0), (29, 8, 0),
                              (6, 11, 0), (33, 10, 0), (10, 17, 0), (28, 18, 0)):
        art(star4 if bright else star, col, row, 14 if bright else 6)

    # A restrained architectural frame sits entirely above the menu area.
    horizontal = canvas(8, 8)
    line(horizontal, 0, 3, 7, 3)
    corner = canvas(8, 8)
    line(corner, 3, 7, 3, 3)
    line(corner, 3, 3, 7, 3)
    for col in range(2, 38):
        if 16 <= col <= 23:
            continue
        art(horizontal, col, 0, 9)
    art(corner, 1, 0, 8)
    art([list(reversed(row)) for row in corner], 38, 0, 8)
    text("THE ARCHIVE", 14, 0, 8)

    # The large title uses a continuous two-pixel engraving, custom packed into
    # the charset rather than relying on doubled hardware text.
    for word, row in (("BORROWED", 2), ("MOTION", 4)):
        a = canvas(len(word)*16, 16)
        for i, char in enumerate(word):
            for y, bits in enumerate(FONT[char]):
                for x in range(5):
                    if bits & (16 >> x):
                        rect(a, i*16+3+x*2, y*2,
                             i*16+4+x*2, y*2+1, fill=True)
        art(a, (40-len(word)*2)//2, row,
            lambda col, rr: 7 if rr in (2, 4) else 8)

    # Hero image: a frozen armillary archive heart, four satellite pearls,
    # symmetric engraved supports, and a bright core held in suspension.
    a = canvas(96, 80)
    # Nested diamonds and an elliptical orbital belt establish a clear shape.
    diamond(a, 47, 34, 29)
    diamond(a, 47, 34, 25)
    ellipse(a, 47, 34, 43, 12)
    ellipse(a, 47, 34, 14, 29)
    # Occlude the orbital machinery behind the central capsule.
    rect(a, 35, 23, 59, 46, 0, fill=True)
    for x0, y0, x1, y1 in ((38, 21, 56, 21), (35, 24, 35, 43),
                           (59, 24, 59, 43), (38, 46, 56, 46),
                           (38, 21, 35, 24), (56, 21, 59, 24),
                           (35, 43, 38, 46), (59, 43, 56, 46)):
        line(a, x0, y0, x1, y1)
    ellipse(a, 47, 34, 7, 7, fill=True)
    ellipse(a, 49, 36, 5, 5, 0, fill=True)
    dot(a, 46, 31)
    dot(a, 45, 30)
    # Paired crowns of the archive heart and a tiered plinth.
    line(a, 43, 2, 51, 2)
    line(a, 41, 4, 53, 4)
    line(a, 43, 64, 51, 64)
    line(a, 41, 66, 53, 66)
    line(a, 47, 67, 47, 71)
    line(a, 35, 72, 59, 72)
    line(a, 30, 75, 64, 75)
    for x, y in ((5, 34), (89, 34), (47, 6), (47, 62)):
        diamond(a, x, y, 3)
        dot(a, x, y)
    art(a, 14, 8, lambda col, row: 3 if (18 <= col <= 21 and 11 <= row <= 13)
        else (7 if row in (8, 11, 16, 17) else 8))

    # Mechanical wings: repeated pieces imply a much larger archive, without
    # making the central object compete with busy background decoration.
    wing = canvas(40, 40)
    line(wing, 0, 19, 39, 19)
    line(wing, 0, 23, 23, 23)
    for x in (3, 11, 19):
        line(wing, x, 16, x, 26)
    diamond(wing, 31, 19, 7)
    diamond(wing, 31, 19, 3)
    line(wing, 31, 8, 31, 11)
    line(wing, 31, 27, 31, 30)
    art(wing, 7, 10, 9)
    art([list(reversed(row)) for row in wing], 28, 10, 9)

    # A tiny inscription makes the fiction legible without explaining mechanics.
    text("EVERYTHING MOVES. NOTHING IS LOST.", 4, 19, 12)
    # Root owns the 5 bottom rows and can add controls without erasing artwork.
    assert all(code == 32 for code in screen[800:])
    return bytes(screen), bytes(colors), next_code


def png(path, pixels, scale=3):
    h, w = len(pixels), len(pixels[0])
    rows = bytearray()
    for row in pixels:
        data = b"".join(bytes(PALETTE[color]) * scale for color in row)
        for _ in range(scale):
            rows.extend(b"\0" + data)
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind+data))
    header = struct.pack(">IIBBBBB", w*scale, h*scale, 8, 2, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
                     + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


def render_screen(glyphs, screen, colors):
    result = canvas(320, 200)
    for cell, code in enumerate(screen):
        x, y = (cell % 40)*8, (cell // 40)*8
        for yy, bits in enumerate(glyphs[code]):
            for xx in range(8):
                if bits & (128 >> xx):
                    result[y+yy][x+xx] = colors[cell]
    return result


def preview(glyphs, screen, colors, tile_colors, sprites):
    title = render_screen(glyphs, screen, colors)
    # Include a contact sheet below the native title, outside any game artifact.
    result = title + canvas(320, max(96, 36 + ((len(sprites)+8)//9)*28))
    for tile in range(7):
        x0, y0 = 16 + tile*40, 208
        for part, (dx, dy) in enumerate(((0, 0), (8, 0), (0, 8), (8, 8))):
            glyph = glyphs[96+tile*4+part]
            for y, bits in enumerate(glyph):
                for x in range(8):
                    if bits & (128 >> x):
                        result[y0+dy+y][x0+dx+x] = tile_colors[tile*4+part]
    for i, frame in enumerate(sprites):
        x0, y0 = 5+(i % 9)*35, 236+(i // 9)*28
        color = (3 if i < 4 or 17 <= i < 37 else 7 if i < 8 or i >= 37
                 else 1 if i < 12 else 14)
        for y, row in enumerate(frame):
            for x, value in enumerate(row):
                if value:
                    result[y0+y][x0+x] = color
    return result


def emit(label, data):
    lines = [f".export {label}, {label}_end", f"{label}:"]
    for i in range(0, len(data), 16):
        lines.append("    .byte " + ",".join(f"${value:02x}" for value in data[i:i+16]))
    lines.append(f"{label}_end:")
    lines.append(f'.assert {label}_end-{label} = {len(data)}, error, "{label} size"')
    return "\n".join(lines) + "\n"


def main():
    glyphs, tile_colors = font_and_tiles()
    sprites, frames = sprite_art()
    screen, colors, glyph_end = draw_title(glyphs)
    OUT.mkdir(parents=True, exist_ok=True)
    source = '; Original deterministic Borrowed Motion artwork. Do not edit generated bytes.\n'
    source += '; Regenerate with python3 tools/generate_motion_assets.py\n\n.segment "RODATA"\n\n'
    source += emit("font_source", b"".join(glyphs))
    source += emit("sprite_source", sprites)
    source += emit("title_screen_source", screen)
    source += emit("title_color_source", colors)
    source += emit("tile_chars", bytes(range(96, 124)))
    source += emit("tile_colors", tile_colors)
    source += '\nMOTION_FONT_BYTES = 2048\nMOTION_SPRITE_BYTES = 3648\nMOTION_SPRITE_FRAMES = 57\n'
    source += f'MOTION_TITLE_GLYPHS_END = {glyph_end}\n'
    (OUT / "assets.inc").write_text(source)
    png(OUT / "art-preview.png", preview(glyphs, screen, colors, tile_colors, frames))
    print(f"Motion art: 2048 charset bytes, {len(sprites)} sprite bytes, "
          f"{glyph_end-124}/132 title glyphs; {OUT / 'assets.inc'}")


if __name__ == "__main__":
    main()
