#!/usr/bin/env python3
"""Readable reference for ATLAS's C64-side procedural geography.

This is a design/debugging aid, not an asset generator: the shipped game creates
its permutation and every terrain tile on the C64. The implementation mirrors
the unsigned arithmetic and integer interpolation in src/atlas/world.s.

An optional PPM preview makes seed and scale choices visible without adding a
graphics dependency. Coordinates wrap at 65,536, just as they do in the game.
"""

from __future__ import annotations

import argparse
from pathlib import Path

SEA, GRASS, FOREST, DESERT, MOUNTAIN, RIVER, CITY, ROAD, BRIDGE = range(9)
FOLD_X = (0, 71, 142, 213)
FOLD_Y = (0, 103, 206, 53)
ROAD_WAVE = tuple(range(9)) + tuple(range(7, -9, -1)) + tuple(range(-7, 0))
RIVER_WAVE = tuple(range(17)) + tuple(range(15, -17, -1)) + tuple(range(-15, 0))
PALETTE = (
    (30, 72, 110), (115, 147, 65), (29, 68, 46), (212, 185, 97),
    (106, 110, 118), (101, 165, 190), (232, 176, 86), (181, 146, 106),
    (229, 206, 160),
)


def lerp(a: int, b: int, fraction: int, bits: int) -> int:
    """Match the assembly's fractional multiply and its rounding direction."""
    offset = (abs(b - a) * fraction) >> bits
    return a + offset if b > a else a - offset


class World:
    def __init__(self, seed: int):
        self.seed = seed & 0xFFFF
        self.seed_low = self.seed & 255
        self.seed_high = self.seed >> 8
        state = self.seed ^ 0x5AA5
        if not state:
            state = 1
        permutation = list(range(256))
        for index in range(256):
            carry = state & 1
            state >>= 1
            if carry:
                state ^= 0xB400
            other = (state & 255) ^ (state >> 8)
            permutation[index], permutation[other] = (
                permutation[other], permutation[index]
            )
        self.permutation = permutation
        self.road_phase = (self.seed_low & 1) << 4

    @property
    def capital(self) -> tuple[int, int]:
        return (self.seed_low << 8) | 128, (self.seed_high << 8) | 128

    def corner_hash(self, x: int, y: int, fold_mask: int) -> int:
        p = self.permutation
        hx = FOLD_X[(x >> 8) & fold_mask] ^ (x & 255) ^ self.seed_low
        hy = FOLD_Y[(y >> 8) & fold_mask] ^ (y & 255) ^ self.seed_high
        return p[p[hx] ^ hy]

    def value_noise(self, x: int, y: int, shift: int) -> int:
        bits = shift - 2
        mask = (1 << shift) - 1
        fold_mask = 0 if shift == 8 else 3
        rx, ry = x >> shift, y >> shift
        fx, fy = (x & mask) >> 2, (y & mask) >> 2
        a = self.corner_hash(rx, ry, fold_mask)
        b = self.corner_hash(rx + 1, ry, fold_mask)
        c = self.corner_hash(rx, ry + 1, fold_mask)
        d = self.corner_hash(rx + 1, ry + 1, fold_mask)
        return lerp(lerp(a, b, fx, bits), lerp(c, d, fx, bits), fy, bits)

    def road_curve(self, fraction: int) -> int:
        return 128 + ROAD_WAVE[((fraction & 255) >> 3) ^ self.road_phase]

    def tile(self, x: int, y: int) -> int:
        x, y = x & 0xFFFF, y & 0xFFFF
        xl, yl, xh, yh = x & 255, y & 255, x >> 8, y >> 8
        height = self.value_noise(x, y, 8)
        biome = self.value_noise(x, y, 6)
        if xh == self.seed_low and yh == self.seed_high:
            distance = abs(xl - 128) + abs(yl - 128)
            if distance <= 20:
                height = max(height, 140 - distance)
        threshold = 106 + (self.permutation[xl ^ yl] & 3)
        if height < threshold:
            return SEA
        if height >= 192:
            terrain = MOUNTAIN
        elif biome < 101:
            terrain = FOREST
        elif biome >= 155:
            terrain = DESERT
        elif height >= 146 and 120 <= biome < 136:
            terrain = MOUNTAIN
        else:
            terrain = GRASS
        if xl == yl == 128:
            return CITY
        road = (
            yl in (self.road_curve(xl), self.road_curve(xl - 1))
            or xl in (self.road_curve(yl), self.road_curve(yl - 1))
        )
        river_base = 116 + (self.permutation[xh ^ self.seed_low] & 31)
        river = xl in (
            river_base + RIVER_WAVE[yl >> 2],
            river_base + RIVER_WAVE[((yl - 1) & 255) >> 2],
        )
        if river:
            return BRIDGE if road else RIVER
        return ROAD if road else terrain

    def natural_tile(self, x: int, y: int) -> int:
        """Underlying sea/biome before narrow transport/settlement features."""
        x, y = x & 65535, y & 65535
        xl, yl = x & 255, y & 255
        height = self.value_noise(x, y, 8)
        biome = self.value_noise(x, y, 6)
        if x >> 8 == self.seed_low and y >> 8 == self.seed_high:
            distance = abs(xl - 128) + abs(yl - 128)
            if distance <= 20:
                height = max(height, 140 - distance)
        if height < 106 + (self.permutation[xl ^ yl] & 3):
            return SEA
        if height >= 192:
            return MOUNTAIN
        if biome < 101:
            return FOREST
        if biome >= 155:
            return DESERT
        if height >= 146 and 120 <= biome < 136:
            return MOUNTAIN
        return GRASS

    def overview_tile(self, x: int, y: int, step: int) -> int:
        """Display LOD for a square centered here; gameplay uses tile()."""
        if step < 2:
            return self.tile(x, y)
        if step >= 256:
            return self.natural_tile(x, y)
        x, y = x & 65535, y & 65535
        xl, yl = x & 255, y & 255
        half = step // 2
        near = lambda coordinate, curve: ((coordinate - curve + half) & 255) < 2 * half + 1
        terrain = self.natural_tile(x, y)
        if near(xl, 128) and near(yl, 128):
            if self.tile((x & 0xFF00) | 128, (y & 0xFF00) | 128) == CITY:
                return CITY
        if terrain == SEA:
            return SEA
        road = (near(yl, self.road_curve(xl)) or near(yl, self.road_curve(xl - 1))
                or near(xl, self.road_curve(yl)) or near(xl, self.road_curve(yl - 1)))
        river_base = 116 + (self.permutation[(x >> 8) ^ self.seed_low] & 31)
        river = (near(xl, river_base + RIVER_WAVE[yl >> 2])
                 or near(xl, river_base + RIVER_WAVE[((yl - 1) & 255) >> 2]))
        if river:
            return BRIDGE if road else RIVER
        return ROAD if road else terrain


def write_preview(world: World, x: int, y: int, width: int, height: int,
                  stride: int, output: Path) -> None:
    pixels = bytearray()
    for row in range(height):
        for column in range(width):
            pixels.extend(PALETTE[world.tile(x + column * stride,
                                           y + row * stride)])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(f"P6\n{width} {height}\n255\n".encode() + pixels)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=lambda v: int(v, 0), default=0xC064)
    parser.add_argument("--x", type=lambda v: int(v, 0))
    parser.add_argument("--y", type=lambda v: int(v, 0))
    parser.add_argument("--width", type=int, default=320)
    parser.add_argument("--height", type=int, default=192)
    parser.add_argument("--stride", type=int, default=2)
    parser.add_argument("--output", type=Path, default=Path("build/atlas/world.ppm"))
    args = parser.parse_args()
    if not 1 <= args.width <= 4096 or not 1 <= args.height <= 4096:
        parser.error("preview dimensions must be between 1 and 4096")
    if not 1 <= args.stride <= 65536:
        parser.error("stride must be between 1 and 65536")
    world = World(args.seed)
    cx, cy = world.capital
    x = args.x if args.x is not None else cx - args.width * args.stride // 2
    y = args.y if args.y is not None else cy - args.height * args.stride // 2
    write_preview(world, x, y, args.width, args.height, args.stride, args.output)
    print(f"Seed ${world.seed:04X}; capital ({cx}, {cy}); wrote {args.output}")


if __name__ == "__main__":
    main()
