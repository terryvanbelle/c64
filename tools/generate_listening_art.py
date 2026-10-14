#!/usr/bin/env python3
"""Editable, deterministic character art for THE SHAPE OF LISTENING.

The three broken, interlaced contours are drawn mathematically, then tiled into
ordinary hires C64 characters. No bitmap mode, image library, or external font
is needed. Text uses explicit C64 screen codes and a small original 5x7 font.
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
    if char == " ":
        return 32
    if "A" <= char <= "Z":
        return ord(char) - 64
    raise ValueError(f"No screen code for {char!r}")


def rle(values: list[int]) -> list[int]:
    out: list[int] = []
    for value in values:
        if out and out[-1] == value and out[-2] < 255:
            out[-2] += 1
        else:
            out.extend((1, value))
    return out + [0]


def assembly_bytes(label: str, values: list[int] | bytes) -> str:
    lines = [label + ":"]
    for i in range(0, len(values), 16):
        lines.append("    .byte " + ",".join(f"${v:02x}" for v in values[i:i+16]))
    return "\n".join(lines) + "\n"


def png(path: Path, pixels: list[list[int]]) -> None:
    def chunk(kind: bytes, payload: bytes) -> bytes:
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))
    raw = b"".join(b"\0" + bytes(c for index in row for c in PALETTE[index]) for row in pixels)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB",320,200,8,2,0,0,0))
                     + chunk(b"IDAT",zlib.compress(raw,9)) + chunk(b"IEND",b""))


def generate(destination: Path) -> None:
    # Each pixel remembers its strand; a cell uses the majority strand's hue.
    pixels = [[-1] * 320 for _ in range(200)]
    phases: dict[tuple[int,int,int], int] = {}
    for strand in range(3):
        phase = strand * 2.0943951023931953
        tilt = (-0.14, 0.12, -0.025)[strand]
        for step in range(1400):
            t = 0.20 + step * (math.tau - 0.75) / 1399
            u = 113 * math.cos(t)
            v = 33 * math.sin(t) + 17 * math.sin(2*t + phase)
            x = round(160 + u * math.cos(tilt) - v * math.sin(tilt))
            y = round(106 + u * math.sin(tilt) + v * math.cos(tilt))
            pixels[y][x] = strand
            phases[(x//8, y//8, strand)] = (step * 64 // 1400) & 63

    glyphs = [bytes(8) for _ in range(64)]
    for char, rows in FONT.items():
        glyphs[screen_code(char)] = bytes([v << 2 for v in rows] + [0])
    cache = {glyph: i for i,glyph in enumerate(glyphs)}
    screen = [32] * 1000
    colors = [0] * 1000
    cells: list[list[tuple[int,int]]] = [[], [], []]
    for cy in range(25):
        for cx in range(40):
            glyph = []
            counts = [0,0,0]
            for dy in range(8):
                value = 0
                for dx in range(8):
                    strand = pixels[cy*8+dy][cx*8+dx]
                    if strand >= 0:
                        value |= 128 >> dx
                        counts[strand] += 1
                glyph.append(value)
            if not any(glyph):
                continue
            glyph_bytes = bytes(glyph)
            if glyph_bytes not in cache:
                cache[glyph_bytes] = len(glyphs)
                glyphs.append(glyph_bytes)
            index = cy*40 + cx
            owner = max(range(3), key=counts.__getitem__)
            screen[index] = cache[glyph_bytes]
            colors[index] = (14,10,3)[owner]
            phase = phases.get((cx,cy,owner), 0)
            cells[owner].append((index, phase))

    def text(row: int, message: str, color: int) -> None:
        start = row*40 + (40-len(message))//2
        for i,char in enumerate(message):
            screen[start+i] = screen_code(char)
            colors[start+i] = color

    text(3, "THE SHAPE OF LISTENING", 15)
    text(22, "SPACE PAUSE   R REPLAY", 12)
    if len(glyphs) > 256:
        raise ValueError(f"Artwork requires {len(glyphs)} characters (limit 256)")
    charset = b"".join(glyphs)
    # Padding costs zero bytes in the PRG; visual_init clears the unused chars.
    out = ["; Generated by tools/generate_listening_art.py. Edit the generator.\n",
           f"ART_CHAR_BYTES = {len(charset)}\n", f"ART_CELL_COUNT = {sum(map(len,cells))}\n",
           assembly_bytes("art_charset", charset),
           assembly_bytes("art_screen_rle", rle(screen)),
           assembly_bytes("art_colors_rle", rle(colors))]
    for voice, entries in enumerate(cells):
        # Eight phase bands per strand: one palette lookup followed by direct
        # color stores. This takes far less CPU time than an indirect per-cell
        # painter and keeps the SID interrupt's time budget comfortable.
        out.append(f"ART_STRAND_{voice}_COUNT = {len(entries)}\n")
        out.append(f".macro PAINT_STRAND_{voice}\n")
        for band in range(8):
            band_cells = [i for i,p in entries if p//8 == band]
            if not band_cells:
                continue
            out.extend(("    lda vis_phase\n    clc\n",f"    adc #{band*8}\n",
                        "    and #63\n    tax\n    lda art_glimmer,x\n    clc\n",
                        "    adc vis_energy\n    tax\n",f"    lda strand_palette+{voice*8},x\n"))
            out.extend(f"    sta ${0xd800+i:04x}\n" for i in band_cells)
        out.append(".endmacro\n")
    out.append(assembly_bytes("art_glimmer", [round((math.sin(i*math.tau/64)+1)*1.5) for i in range(64)]))
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("".join(out))
    rendered = [[0]*320 for _ in range(200)]
    for i,code in enumerate(screen):
        for dy,bits in enumerate(glyphs[code]):
            for dx in range(8):
                if bits & (128>>dx):
                    rendered[i//40*8+dy][i%40*8+dx] = colors[i]
    png(destination.with_suffix(".png"), rendered)
    data_size = len(charset) + len(rle(screen)) + len(rle(colors)) + 64
    print(f"Listening art: {len(glyphs)} characters, {sum(map(len,cells))} luminous cells, {data_size} data bytes plus bounded color-store macros")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT/"build/listening/art.inc")
    args = parser.parse_args()
    generate(args.output)


if __name__ == "__main__":
    main()
