#!/usr/bin/env python3
"""Deterministic, editable hires character art for A MOUTHFUL OF WEATHER.

A copper profile speaks into broken blue breath contours. The mouth has eight
opening levels and three widths, shared by the eight phonetic shape values.
Every visible pixel is an ordinary C64 character bit; no external art or font.
"""
from __future__ import annotations

import argparse
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FONT = {
    "A": (14,17,17,31,17,17,17), "B": (30,17,17,30,17,17,30),
    "C": (14,17,16,16,16,17,14), "D": (30,17,17,17,17,17,30),
    "E": (31,16,16,30,16,16,31), "F": (31,16,16,30,16,16,16),
    "G": (14,17,16,23,17,17,15), "H": (17,17,17,31,17,17,17),
    "I": (14,4,4,4,4,4,14), "J": (7,2,2,2,18,18,12),
    "K": (17,18,20,24,20,18,17), "L": (16,16,16,16,16,16,31),
    "M": (17,27,21,21,17,17,17), "N": (17,25,25,21,19,19,17),
    "O": (14,17,17,17,17,17,14), "P": (30,17,17,30,16,16,16),
    "Q": (14,17,17,17,21,18,13), "R": (30,17,17,30,20,18,17),
    "S": (15,16,16,14,1,1,30), "T": (31,4,4,4,4,4,4),
    "U": (17,17,17,17,17,17,14), "V": (17,17,17,17,17,10,4),
    "W": (17,17,17,21,21,21,10), "X": (17,17,10,4,10,17,17),
    "Y": (17,17,10,4,4,4,4), "Z": (31,1,2,4,8,16,31),
}
PALETTE = (
    (0,0,0), (255,255,255), (144,66,58), (117,206,200),
    (142,81,156), (86,172,77), (58,61,144), (233,237,129),
    (142,80,41), (85,56,0), (196,126,120), (74,74,74),
    (123,123,123), (169,255,159), (112,111,211), (178,178,178),
)


def screen_code(char: str) -> int:
    return 32 if char == " " else ord(char)-64


def rle(values: list[int]) -> list[int]:
    out: list[int] = []
    for value in values:
        if out and out[-1] == value and out[-2] < 255:
            out[-2] += 1
        else:
            out.extend((1,value))
    return out + [0]


def assembly_bytes(label: str, values: list[int] | bytes) -> str:
    return label + ":\n" + "".join(
        "    .byte " + ",".join(f"${v:02x}" for v in values[i:i+16]) + "\n"
        for i in range(0,len(values),16))


def png(path: Path, pixels: list[list[int]]) -> None:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I",len(data)) + kind + data + struct.pack(">I",zlib.crc32(kind+data))
    raw = b"".join(b"\0" + bytes(c for index in row for c in PALETTE[index]) for row in pixels)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR",struct.pack(">IIBBBBB",320,200,8,2,0,0,0))
                     + chunk(b"IDAT",zlib.compress(raw,9)) + chunk(b"IEND",b""))


def generate(destination: Path) -> None:
    pixels = [[0]*320 for _ in range(200)]
    breath_cells: list[set[int]] = [set() for _ in range(4)]

    def point(x: int, y: int, color: int, band: int | None = None) -> None:
        pixels[y][x] = color
        if band is not None:
            breath_cells[band].add((y//8)*40+x//8)

    def line(x0: int, y0: int, x1: int, y1: int, color: int) -> None:
        x,y = x0,y0
        dx,dy = abs(x1-x0),-abs(y1-y0)
        sx,sy = (1 if x0<x1 else -1),(1 if y0<y1 else -1)
        error = dx+dy
        while True:
            point(x,y,color)
            if (x,y) == (x1,y1):
                return
            twice = 2*error
            if twice >= dy:
                error += dy
                x += sx
            if twice <= dx:
                error += dx
                y += sy

    def contour(vertices: tuple[tuple[int,int],...], color: int) -> None:
        for (x0,y0),(x1,y1) in zip(vertices,vertices[1:]):
            line(x0,y0,x1,y1,color)

    # An open, asymmetric profile rather than a mascot or a literal portrait.
    contour(((98,170),(100,150),(91,135),(83,115),(81,95),(86,77),
             (97,63),(111,55),(127,54),(140,60),(148,72),(148,86),
             (153,94),(168,102),(159,106),(158,111)),8)
    contour(((155,128),(153,134),(145,140),(140,152),(138,170)),8)
    contour(((92,81),(99,68),(112,62),(128,61),(139,67)),10)
    contour(((132,82),(144,84)),15)
    contour(((133,91),(139,93),(145,91)),15)
    contour(((116,101),(110,98),(105,103),(106,113),(111,120),
             (116,115),(113,108)),8)
    contour(((122,123),(131,133),(139,133)),10)
    contour(((116,136),(121,148),(121,169)),9)
    # Sparse shoulder marks suggest the voice has a body without enclosing it.
    contour(((98,159),(87,163),(72,170)),8)
    contour(((139,159),(155,164),(165,170)),8)

    # Four broken expanding breath contours. Disjoint character columns allow
    # one color lookup per contour, with direct stores only during playback.
    for band,(cx,rx,ry) in enumerate(((177,7,12),(197,9,22),(221,11,32),(250,13,43))):
        for step in range(121):
            angle = -1.15 + step*2.3/120
            if (step+band*7)%41 in range(29,41):
                continue
            x = round(cx+rx*math.cos(angle))
            y = round(119+ry*math.sin(angle))
            point(x,y,14,band)
        # Detached grains make the contours breathe rather than read as radar.
        point(cx+rx+4,113-band*3,3,band)
        point(cx+rx+5,124+band*3,14,band)

    glyphs = [bytes(8) for _ in range(33)]
    for char,rows in FONT.items():
        glyphs[screen_code(char)] = bytes([row<<2 for row in rows]+[0])
    cache = {glyph:i for i,glyph in enumerate(glyphs)}

    def glyph_code(glyph: bytes) -> int:
        if glyph not in cache:
            cache[glyph] = len(glyphs)
            glyphs.append(glyph)
        return cache[glyph]

    screen = [32]*1000
    colors = [0]*1000
    for cy in range(25):
        for cx in range(40):
            tile = [pixels[cy*8+y][cx*8:cx*8+8] for y in range(8)]
            glyph = bytes(sum((128>>x) for x,color in enumerate(row) if color) for row in tile)
            if any(glyph):
                counts = [sum(row.count(color) for row in tile) for color in range(16)]
                color = max(range(1,16),key=counts.__getitem__)
                screen[cy*40+cx] = glyph_code(glyph)
                colors[cy*40+cx] = color

    # Six screen cells choose a precomputed mouth. Six parallel tables avoid
    # multiplication and indirect stores in the high-frequency sample player.
    mouth_indices = [(14+row)*40+18+col for row in range(2) for col in range(3)]
    frames: list[list[int]] = []
    widths = (4,7,5,7,4,5,7,4)
    for shape in range(8):
        for opening in range(8):
            mouth = [[0]*24 for _ in range(16)]
            width = widths[shape]
            # A closed mouth is identical for every phonetic shape.
            if opening == 0:
                for x in range(9,19):
                    mouth[7][x] = 1
                for x,y in ((14,0),(15,1),(16,2),(17,3),(18,4),(18,5),
                            (17,9),(16,10),(15,11),(14,12),(13,13),(12,14),(11,15)):
                    mouth[y][x] = 1
            else:
                for step in range(80):
                    angle = step*math.tau/80
                    x = round(14+width*math.cos(angle))
                    y = round(7+opening*math.sin(angle))
                    mouth[y][x] = 1
                # Keep an anatomical bridge from nose to lips to chin.
                for y in range(0,7-opening):
                    mouth[y][14] = 1
                for y in range(8+opening,16):
                    mouth[y][13] = 1
            codes = []
            for row in range(2):
                for col in range(3):
                    codes.append(glyph_code(bytes(
                        sum((128>>x) for x in range(8) if mouth[row*8+y][col*8+x])
                        for y in range(8))))
            frames.append(codes)
    for index,code in zip(mouth_indices,frames[0]):
        screen[index] = code
        colors[index] = 10

    def text(row: int, message: str, color: int) -> None:
        start = row*40+(40-len(message))//2
        for offset,char in enumerate(message):
            screen[start+offset] = screen_code(char)
            colors[start+offset] = color

    text(3,"A MOUTHFUL OF WEATHER",15)
    text(23,"SPACE PAUSE   R REPLAY",12)
    charset = b"".join(glyphs)
    data_size = len(charset)+len(rle(screen))+len(rle(colors))+64*6
    if len(glyphs)>256 or data_size>4096:
        raise ValueError(f"Art exceeds character/data budget: {len(glyphs)} glyphs, {data_size} bytes")
    out = ["; Generated by tools/generate_weather_art.py. Edit that source.\n",
           f"ART_CHAR_BYTES = {len(charset)}\n",
           f"ART_BREATH_CELLS = {sum(map(len,breath_cells))}\n",
           assembly_bytes("art_charset",charset),
           assembly_bytes("art_screen_rle",rle(screen)),
           assembly_bytes("art_colors_rle",rle(colors))]
    for cell in range(6):
        out.append(assembly_bytes(f"art_mouth_{cell}",[frame[cell] for frame in frames]))
    out.append(".macro DRAW_MOUTH\n")
    for cell,index in enumerate(mouth_indices):
        out.append(f"    lda art_mouth_{cell},x\n    sta ${0x4000+index:04x}\n")
    out.append(".endmacro\n.macro PAINT_BREATH\n")
    for band,entries in enumerate(breath_cells):
        out.append(f"    lda vis_phase\n    clc\n    adc #{band*3}\n    and #15\n"
                   "    tax\n    lda breath_palette,x\n")
        for index in sorted(entries):
            out.append(f"    sta ${0xd800+index:04x}\n")
    out.append(".endmacro\n.macro QUIET_BREATH\n    lda #6\n")
    for index in sorted(set().union(*breath_cells)):
        out.append(f"    sta ${0xd800+index:04x}\n")
    out.append(".endmacro\n")
    destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_text("".join(out))
    rendered = [[0]*320 for _ in range(200)]
    # Preview an open syllable. Program startup itself uses the closed frame.
    for index,code in zip(mouth_indices,frames[8+4]):
        screen[index] = code
    for index,code in enumerate(screen):
        for y,bits in enumerate(glyphs[code]):
            for x in range(8):
                if bits & (128>>x):
                    rendered[index//40*8+y][index%40*8+x] = colors[index]
    png(destination.with_suffix(".png"),rendered)
    print(f"Weather art: {len(glyphs)} characters, {data_size} data bytes, "
          f"{sum(map(len,breath_cells))} breath cells, 64 mouth frames")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",type=Path,default=ROOT/"build/weather/art.inc")
    generate(parser.parse_args().output)


if __name__ == "__main__":
    main()
