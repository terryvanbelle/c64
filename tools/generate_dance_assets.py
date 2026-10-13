#!/usr/bin/env python3
"""Build original, deterministic C64 dance graphics using only the standard library.

The dancer is drawn at 48 x 84 pixels and divided into eight 24 x 21 hires
sprites. Sprite order is left/right, top to bottom. The runtime doubles both
sprite dimensions. Each packed frame expands to 512 bytes, including the eight
unused sprite bytes. The initial frame is a plain keyframe of pose 95. Every
subsequent frame is XOR-delta data relative to the preceding pose, cyclically.
Tokens 1..127 introduce literal bytes; tokens 128..255
repeat the next byte (token & 127) + 1 times. No sentinel is required: the
decoder stops after 512 output bytes.

This is source art, not a conversion of somebody else's illustration. Its
joint paths, silhouette, drapery, and stage are all defined below.
"""

from collections import Counter
import math
from pathlib import Path
import struct
import zlib


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "dance"
FRAME_COUNT = 96
WIDTH, HEIGHT = 48, 84
SCALE = 4
PALETTE = (
    (8, 8, 17), (239, 235, 218), (129, 63, 68), (112, 186, 178),
    (126, 86, 160), (86, 143, 86), (43, 48, 102), (201, 209, 127),
    (139, 85, 52), (85, 65, 33), (181, 115, 113), (66, 66, 85),
    (117, 117, 130), (169, 208, 160), (118, 132, 195), (174, 174, 185),
)


def png(path, width, height, rgb):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(
            ">I", zlib.crc32(kind + data) & 0xffffffff)
    raw = b"".join(b"\0" + bytes(rgb[y * width * 3:(y + 1) * width * 3])
                   for y in range(height))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(
        ">IIBBBBB", width, height, 8, 2, 0, 0, 0)) +
        chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


class Canvas:
    """Small supersampled binary canvas: polygons, tapered limbs, and curves."""

    def __init__(self):
        self.w, self.h = WIDTH * SCALE, HEIGHT * SCALE
        self.pixels = bytearray(self.w * self.h)

    def polygon(self, vertices, value=1):
        vertices = [(x * SCALE, y * SCALE) for x, y in vertices]
        low = max(0, int(math.floor(min(y for _, y in vertices))))
        high = min(self.h - 1, int(math.ceil(max(y for _, y in vertices))))
        for y in range(low, high + 1):
            scan = y + 0.5
            intersections = []
            for (ax, ay), (bx, by) in zip(vertices, vertices[1:] + vertices[:1]):
                if (ay <= scan < by) or (by <= scan < ay):
                    intersections.append(ax + (scan - ay) * (bx - ax) / (by - ay))
            intersections.sort()
            for left, right in zip(intersections[::2], intersections[1::2]):
                x0 = max(0, math.ceil(left - 0.5))
                x1 = min(self.w, math.ceil(right - 0.5))
                for x in range(x0, x1):
                    self.pixels[y * self.w + x] = value

    def ellipse(self, center, rx, ry, value=1, tilt=0):
        cx, cy = center
        c, s = math.cos(tilt), math.sin(tilt)
        self.polygon([(cx + rx * math.cos(t) * c - ry * math.sin(t) * s,
                       cy + rx * math.cos(t) * s + ry * math.sin(t) * c)
                      for t in [i * math.tau / 32 for i in range(32)]], value)

    def limb(self, a, b, width_a, width_b, value=1):
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy) or 1
        nx, ny = -dy / length, dx / length
        self.polygon([(a[0] + nx * width_a / 2, a[1] + ny * width_a / 2),
                      (b[0] + nx * width_b / 2, b[1] + ny * width_b / 2),
                      (b[0] - nx * width_b / 2, b[1] - ny * width_b / 2),
                      (a[0] - nx * width_a / 2, a[1] - ny * width_a / 2)], value)
        self.ellipse(a, width_a / 2, width_a / 2, value)
        self.ellipse(b, width_b / 2, width_b / 2, value)

    def curve(self, points, width, value=1):
        for a, b in zip(points, points[1:]):
            self.limb(a, b, width, width, value)

    def raster(self):
        result = []
        for y in range(HEIGHT):
            row = []
            for x in range(WIDTH):
                count = sum(self.pixels[(y * SCALE + sy) * self.w + x * SCALE + sx]
                            for sy in range(SCALE) for sx in range(SCALE))
                row.append(int(count >= SCALE * SCALE * 0.42))
            result.append(row)
        return result


def bezier(a, b, c, d, samples=25):
    result = []
    for i in range(samples):
        t = i / (samples - 1)
        u = 1 - t
        result.append((u**3 * a[0] + 3*u*u*t*b[0] + 3*u*t*t*c[0] + t**3*d[0],
                       u**3 * a[1] + 3*u*u*t*b[1] + 3*u*t*t*c[1] + t**3*d[1]))
    return result


# Each pose supplies left elbow, left wrist, right elbow, right wrist, lifted
# knee, and pointed foot. Cubic interpolation provides continuous velocity at
# every pose and at the end of the loop. The supporting leg keeps contact with
# the stage, while the free leg describes a slow circular ballet gesture.
POSES = (
    ((14, 22), (14, 9), (35, 28), (43, 20), (31, 57), (37, 69)),
    ((12, 25), (4, 20), (33, 17), (29, 5), (35, 56), (42, 61)),
    ((13, 31), (4, 34), (32, 17), (26, 5), (34, 51), (43, 49)),
    ((16, 34), (10, 43), (34, 23), (43, 15), (30, 51), (33, 40)),
    ((15, 29), (6, 24), (35, 31), (44, 33), (30, 55), (28, 64)),
    ((15, 20), (19, 7), (35, 32), (42, 39), (28, 60), (30, 77)),
    ((17, 17), (23, 5), (34, 25), (43, 18), (24, 57), (16, 71)),
    ((15, 18), (17, 6), (33, 19), (33, 7), (27, 55), (24, 66)),
)


def pose_at(frame):
    position = frame * len(POSES) / FRAME_COUNT
    index = int(position)
    t = position - index
    points = []
    for joint in range(6):
        values = [POSES[(index + offset) % len(POSES)][joint]
                  for offset in (-1, 0, 1, 2)]
        point = []
        for axis in range(2):
            a, b, c, d = [value[axis] for value in values]
            point.append(0.5 * (2*b + (-a+c)*t +
                               (2*a-5*b+4*c-d)*t*t + (-a+3*b-3*c+d)*t*t*t))
        points.append(tuple(point))
    return points


def dancer(frame):
    phase = math.tau * frame / FRAME_COUNT
    sway = 1.5 * math.sin(phase)
    lean = 1.2 * math.sin(phase - 0.5)
    breath = 0.55 * math.sin(phase * 2)
    canvas = Canvas()
    left_elbow, left_hand, right_elbow, right_hand, knee, toe = pose_at(frame)
    left_shoulder = (20 + sway + lean, 25 + breath)
    right_shoulder = (28 + sway + lean, 25 + breath)
    left_hip, right_hip = (21.5 + sway, 45), (26.5 + sway, 45)
    supporting_knee = (22 + sway * 0.6, 62)
    supporting_ankle = (23.5 + sway * 0.4, 77.5)

    # Legs are tapered anatomical forms rather than uniform sticks. Pointe
    # extends the supporting line, and an articulated lifted ankle defines the
    # free foot. The skirt is drawn afterwards and hides the upper thighs.
    canvas.limb(right_hip, knee, 4.4, 2.8)
    ankle = (toe[0] - 2.3, toe[1] - 1.7)
    canvas.limb(knee, ankle, 2.8, 1.5)
    canvas.limb(ankle, toe, 1.7, 0.7)
    canvas.limb(left_hip, supporting_knee, 4.4, 2.8)
    canvas.limb(supporting_knee, supporting_ankle, 2.7, 1.5)
    canvas.limb(supporting_ankle, (24.7 + sway * 0.4, 81.5), 1.6, 0.8)

    # Asymmetric translucent-looking dress: black channels carve long folds
    # into the light silhouette. The hem and streaming fabric lag the gesture.
    skirt_left = 14.0 + sway + 2.0 * math.sin(phase - 0.6)
    skirt_right = 35.0 + sway + 3.6 * math.sin(phase - 1.0)
    hem_y = 59.5 + 2.3 * math.sin(phase - 0.8)
    skirt = bezier((21+sway, 40), (19+sway, 48), (17, 52),
                   (skirt_left, hem_y-1), 12)
    skirt += bezier((skirt_left, hem_y-1), (21, hem_y+4), (29, hem_y+1),
                    (skirt_right, hem_y-3), 15)[1:]
    skirt += bezier((skirt_right, hem_y-3), (29+sway, 49), (28+sway, 45),
                    (27+sway, 40), 12)[1:]
    canvas.polygon(skirt)
    for offset in (-1.2, 2.4, 4.6):
        fold = bezier((23+sway+offset*0.35, 44),
                      (22+sway+offset, 49), (23+offset*1.4, hem_y-2),
                      (23+offset*1.6+1.5*math.sin(phase), hem_y+1), 18)
        canvas.curve(fold, 1.0, 0)

    # Torso narrows at the waist; neck and shoulders remain anatomically small.
    canvas.polygon([left_shoulder, (22+sway+lean, 23),
                    (26+sway+lean, 23), right_shoulder,
                    (27+sway+lean*0.4, 32), (26+sway, 40),
                    (27+sway, 45), (21+sway, 45),
                    (22+sway, 39), (21+sway+lean*0.4, 32)])
    canvas.limb((24+sway+lean, 24), (24+sway+lean, 19.5), 2.5, 2.0)
    head = (23.9+sway+lean, 15.9+breath)
    canvas.ellipse(head, 2.65, 3.85, tilt=lean*0.08)
    canvas.ellipse((head[0]-2.0, head[1]-2.1), 1.9, 1.6)  # restrained bun

    for shoulder, elbow, hand, side in (
            (left_shoulder, left_elbow, left_hand, -1),
            (right_shoulder, right_elbow, right_hand, 1)):
        canvas.limb(shoulder, elbow, 2.5, 1.8)
        canvas.limb(elbow, hand, 1.8, 0.9)
        dx, dy = hand[0] - elbow[0], hand[1] - elbow[1]
        length = math.hypot(dx, dy) or 1
        fingertip = (hand[0] + dx/length*2.0 + side*0.4,
                     hand[1] + dy/length*2.0)
        canvas.limb(hand, fingertip, 1.1, 0.4)

    return canvas.raster()


def sprite_bytes(raster):
    result = bytearray()
    for row in range(4):
        for col in range(2):
            for y in range(row*21, row*21+21):
                for byte in range(3):
                    value = 0
                    for x in range(col*24+byte*8, col*24+byte*8+8):
                        value = (value << 1) | raster[y][x]
                    result.append(value)
            result.append(0)
    assert len(result) == 512
    return bytes(result)


def pack(data):
    result = bytearray()
    i = 0
    while i < len(data):
        repeat = 1
        while i+repeat < len(data) and data[i+repeat] == data[i] and repeat < 128:
            repeat += 1
        if repeat >= 3:
            result.extend((0x80 | (repeat-1), data[i]))
            i += repeat
            continue
        start = i
        i += repeat
        while i < len(data) and i-start < 127:
            repeat = 1
            while i+repeat < len(data) and data[i+repeat] == data[i] and repeat < 3:
                repeat += 1
            if repeat >= 3:
                break
            i += min(repeat, 127-(i-start))
        result.append(i-start)
        result.extend(data[start:i])
    return bytes(result)


def unpack(data):
    out = bytearray()
    i = 0
    while i < len(data):
        token = data[i]
        i += 1
        assert token
        if token & 128:
            out.extend([data[i]] * ((token & 127)+1))
            i += 1
        else:
            out.extend(data[i:i+token])
            i += token
    return bytes(out)


def moving_glyphs():
    """Eight phases of eight twinkles and eight isolated reflected glints."""
    phases = []
    for phase in range(8):
        glyphs = bytearray()
        for mote in range(8):
            pulse = (phase+mote*3) % 8
            pixels = [[0]*8 for _ in range(8)]
            cx, cy = 3 + mote%2, 3 + (mote//2)%2
            pixels[cy][cx] = 1
            if pulse in (2, 3, 4):
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    pixels[cy+dy][cx+dx] = 1
            if pulse == 3:
                pixels[cy-2][cx] = pixels[cy+2][cx] = 1
            glyphs.extend(sum(bit << (7-x) for x, bit in enumerate(row)) for row in pixels)
        for glint in range(8):
            pixels = [[0]*8 for _ in range(8)]
            pulse = (phase+glint) % 8
            y = 3 + round(1.4*math.sin(pulse*math.tau/8))
            x = 2 + round(math.sin(pulse*math.tau/8))
            length = 2 + round(2*(1+math.sin(pulse*math.tau/8)))
            for dx in range(length):
                if x+dx < 8:
                    pixels[y][x+dx] = 1
            glyphs.extend(sum(bit << (7-x) for x, bit in enumerate(row)) for row in pixels)
        assert len(glyphs) == 128
        phases.append(bytes(glyphs))
    return phases


def stage():
    """Sparse stage light: curved silk curtains, constellations, a still pool."""
    bayer = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))
    dots = [[0]*320 for _ in range(200)]
    hue = [[6]*320 for _ in range(200)]
    for y in range(200):
        for x in range(320):
            # Two silk veils curve away from the body, and their density fades
            # smoothly into the central dark area. There are no tile outlines.
            left = 47 + 17*math.sin(y*0.027) + 0.065*y
            right = 273 - 17*math.sin(y*0.024 + 0.8) - 0.065*y
            ldist, rdist = abs(x-left), abs(x-right)
            curtain = max(math.exp(-ldist*ldist/620), math.exp(-rdist*rdist/800))
            intensity = 0.13*curtain
            color = 4 if ldist < rdist else 6
            for offset in (-16, -6, 8, 20):
                if abs(x-left-offset-2*math.sin(y*0.065+offset)) < 0.7:
                    intensity, color = 0.83, (4 if offset < 0 else 14)
                if abs(x-right-offset-2*math.sin(y*0.055+offset)) < 0.65:
                    intensity, color = 0.72, (6 if offset < 0 else 3)
            # A restrained halo provides depth without putting a bright patch
            # through the body; the two side veils are the main illumination.
            halo = math.exp(-((x-160)/96)**2-((y-68)/65)**2)
            intensity = max(intensity, 0.018*halo)
            if y >= 174:
                # Long ellipses imply reflections on polished floor/water.
                py = y-174
                ripple = math.sin(math.hypot((x-160)*0.5, py*4)*0.14)
                intensity = (0.75 if ripple > 0.99 else 0)
                intensity *= 0.6+0.4*math.exp(-((x-160)/145)**2)
                color = 6 if py%9 < 5 else 14
            threshold = (bayer[y%4][x%4]+0.5)/16
            if intensity > threshold:
                dots[y][x] = 1
                hue[y][x] = color

    # Tiny starlight points are placed explicitly, with generous negative space.
    for x, y in ((27, 19), (87, 11), (123, 28), (199, 16), (233, 36),
                 (296, 16), (102, 73), (218, 91), (23, 113), (285, 120),
                 (77, 147), (241, 151), (143, 8), (171, 41)):
        dots[y][x] = 1
        hue[y][x] = 14
        if x in (27, 199, 285):
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                dots[y+dy][x+dx] = 1
                hue[y+dy][x+dx] = 14

    tiles, colors = [], []
    for row in range(25):
        for col in range(40):
            tile = []
            counts = Counter()
            for y in range(row*8, row*8+8):
                value = 0
                for x in range(col*8, col*8+8):
                    value = (value << 1) | dots[y][x]
                    if dots[y][x]:
                        counts[hue[y][x]] += 1
                tile.append(value)
            tiles.append(bytes(tile))
            colors.append(counts.most_common(1)[0][0] if counts else 6)

    # Keep frequent shapes, then reserve most remaining slots for long curtains
    # (the shapes with most ink). Rare sparse dots can share a nearby glyph.
    frequencies = Counter(tiles)
    common = [shape for shape, count in frequencies.most_common() if count >= 2]
    rare = sorted((shape for shape in frequencies if shape not in common),
                  key=lambda shape: sum(v.bit_count() for v in shape), reverse=True)
    shapes = (common + rare)[:240]
    assert bytes(8) in shapes
    indices = {shape: i for i, shape in enumerate(shapes)}
    remap = {}
    screen = []
    for tile in tiles:
        if tile not in indices:
            if tile not in remap:
                remap[tile] = min(range(len(shapes)), key=lambda i:
                                 sum((a ^ b).bit_count() for a, b in zip(tile, shapes[i])))
            screen.append(remap[tile])
        else:
            screen.append(indices[tile])
    animated = moving_glyphs()
    charset = b"".join(shapes).ljust(240*8, b"\0") + animated[0]
    for mote, (x, y) in enumerate(((27, 19), (87, 11), (199, 16), (233, 36),
                                  (296, 16), (102, 73), (23, 113), (285, 120))):
        cell = (y//8)*40+x//8
        screen[cell], colors[cell] = 240+mote, 14 if mote%3 else 3
    for glint, col in enumerate((4, 8, 12, 16, 23, 27, 31, 35)):
        cell = 23*40+col
        screen[cell], colors[cell] = 248+glint, 6 if glint%2 else 14
    assert len(screen) == len(colors) == 1000 and len(charset) == 2048
    return bytes(screen), bytes(colors), charset, len(frequencies), len(remap)


def stage_rgb(screen, colors, charset):
    result = bytearray(320*200*3)
    for y in range(200):
        for x in range(320):
            cell = (y//8)*40+x//8
            bit = (charset[screen[cell]*8+y%8] >> (7-x%8)) & 1
            color = PALETTE[colors[cell] if bit else 0]
            p = (y*320+x)*3
            result[p:p+3] = bytes(color)
    return result


def stage_preview(background, raster, phase, scale=2):
    result = bytearray(background)
    # Match runtime composition: 96 x 168 pixels; dancer's origin is near the
    # center of the visible screen. Runtime may sway the whole body slightly.
    origin_x = 112 + round(3*math.sin(math.tau*phase/FRAME_COUNT))
    origin_y = 17
    for y, row in enumerate(raster):
        for x, bit in enumerate(row):
            if bit:
                for dy in range(2):
                    for dx in range(2):
                        p = ((origin_y+y*2+dy)*320+origin_x+x*2+dx)*3
                        result[p:p+3] = bytes(PALETTE[1])
    if scale == 1:
        return result
    enlarged = bytearray(320*scale*200*scale*3)
    for y in range(200):
        for x in range(320):
            color = result[(y*320+x)*3:(y*320+x)*3+3]
            for dy in range(scale):
                for dx in range(scale):
                    p = (((y*scale+dy)*320*scale)+x*scale+dx)*3
                    enlarged[p:p+3] = color
    return enlarged


def byte_lines(data):
    return "\n".join("    .byte " + ",".join(f"${value:02x}" for value in data[i:i+16])
                     for i in range(0, len(data), 16))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    frames = [dancer(i) for i in range(FRAME_COUNT)]
    raw = [sprite_bytes(frame) for frame in frames]
    deltas = [bytes(a ^ b for a, b in zip(raw[i], raw[(i-1) % FRAME_COUNT]))
              for i in range(FRAME_COUNT)]
    packed = [pack(frame) for frame in deltas]
    keyframe = pack(raw[-1])
    for i, compressed in enumerate(packed):
        decoded = unpack(compressed)
        assert decoded == deltas[i]
        assert bytes(a ^ b for a, b in zip(decoded, raw[(i-1) % FRAME_COUNT])) == raw[i]
    total = sum(map(len, packed)) + len(keyframe) + FRAME_COUNT*2
    assert total <= 27*1024, f"FRAMES exceeds budget: {total}"
    screen, colors, charset, distinct, remapped = stage()
    source = ['; Generated by tools/generate_dance_assets.py. Do not edit.',
              f'dance_frame_count = {FRAME_COUNT}',
              f'dance_packed_bytes = {total}',
              'dance_glyph_phase_count = 8',
              '.segment "BACKGROUND"', 'dance_screen_data:', byte_lines(screen),
              'dance_color_data:', byte_lines(colors),
              'dance_charset_data:', byte_lines(charset),
              '.segment "FRAMES"', 'dance_initial_frame:', byte_lines(keyframe),
              'dance_frame_lo:']
    for start in range(0, FRAME_COUNT, 8):
        source.append('    .byte '+','.join(f'<dance_frame_{i:03}' for i in range(start, start+8)))
    source.append('dance_frame_hi:')
    for start in range(0, FRAME_COUNT, 8):
        source.append('    .byte '+','.join(f'>dance_frame_{i:03}' for i in range(start, start+8)))
    for i, frame in enumerate(packed):
        source.extend((f'dance_frame_{i:03}:', byte_lines(frame)))
    source.extend(('dance_frames_end:',
                   '.assert dance_frames_end-dance_initial_frame <= 27*1024, error, "dance frames overflow"',
                   '.segment "RODATA"', 'dance_glyph_lo:',
                   '    .byte '+','.join(f'<dance_glyph_phase_{i}' for i in range(8)),
                   'dance_glyph_hi:',
                   '    .byte '+','.join(f'>dance_glyph_phase_{i}' for i in range(8))))
    source.append('dance_glyph_frames:')
    for i, phase in enumerate(moving_glyphs()):
        source.extend((f'dance_glyph_phase_{i}:', byte_lines(phase)))
    (OUT / 'assets.inc').write_text('\n'.join(source)+'\n')
    (OUT / 'screen.bin').write_bytes(screen)
    (OUT / 'color.bin').write_bytes(colors)
    (OUT / 'charset.bin').write_bytes(charset)
    (OUT / 'sprites.bin').write_bytes(b''.join(raw))
    (OUT / 'frame95.bin').write_bytes(raw[-1])
    background = stage_rgb(screen, colors, charset)
    png(OUT / 'stage.png', 640, 400, stage_preview(background, [[0]*WIDTH for _ in range(HEIGHT)], 0))
    for frame in (0, 12, 24, 36, 48, 60, 72, 84):
        png(OUT / f'preview_{frame:03}.png', 640, 400,
            stage_preview(background, frames[frame], frame))
    sheet_w, sheet_h = WIDTH*4*8, HEIGHT*4*3
    sheet = bytearray(bytes(PALETTE[0])*(sheet_w*sheet_h))
    for i, frame in enumerate(range(0, FRAME_COUNT, 4)):
        ox, oy = (i%8)*WIDTH*4, (i//8)*HEIGHT*4
        for y, row in enumerate(frames[frame]):
            for x, bit in enumerate(row):
                if bit:
                    for dy in range(4):
                        for dx in range(4):
                            p = (((oy+y*4+dy)*sheet_w)+ox+x*4+dx)*3
                            sheet[p:p+3] = bytes(PALETTE[1])
    png(OUT / 'contact_sheet.png', sheet_w, sheet_h, sheet)
    print(f'Dance assets: {FRAME_COUNT} frames, {total} packed bytes '
          f'({min(map(len, packed))}..{max(map(len, packed))}/frame); '
          f'background 4048 bytes, {distinct} source glyphs, {remapped} remapped.')


if __name__ == '__main__':
    main()
