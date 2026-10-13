#!/usr/bin/env python3
"""Reference the C64 runtime arena generator; no map data is baked into the PRG.

The assembly generator is authoritative. This independent equivalent is useful
for reproducing a seed and inspecting the exact 20x10 geometry outside VICE.
"""

from __future__ import annotations

import argparse


WIDTH = 20
HEIGHT = 10
TERRAINS = "~.f^Mrc=#"  # Water, grass, forest, desert, mountain, river, city, road, bridge.


def generate(seed: int) -> bytes:
    """Generate the same mirrored, row-major map as arena_generate in arena.s."""
    if not 0 <= seed <= 0xFFFF:
        raise ValueError("seed must be an unsigned 16-bit integer")
    rng = seed or 0xACE1

    def random_byte() -> int:
        nonlocal rng
        for _ in range(8):
            carry = rng & 1
            rng >>= 1
            if carry:
                rng ^= 0xB400
        return rng & 0xFF

    def put(x: int, y: int, terrain: int) -> None:
        if not (0 <= x <= 9 and 0 <= y <= 9 and 0 <= terrain <= 8):
            raise ValueError((x, y, terrain))
        arena[y * WIDTH + x] = terrain
        arena[y * WIDTH + WIDTH - 1 - x] = terrain

    random_byte()
    arena = bytearray([1] * (WIDTH * HEIGHT))
    for y in range(HEIGHT):
        put(9, y, 5)
    put(8, 0, 0)
    put(8, 9, 0)

    for terrain in (2, 2, 3, 3, 4, 4, 0, 0, 2, 2, 3, 0):
        x = (random_byte() & 3) + 3
        y = (random_byte() & 7) + 1
        shape = random_byte()
        for dx, dy in ((0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)):
            put(x + dx, y + dy, terrain)
        for bit, dx, dy in ((1, -1, 1), (2, 1, 1), (4, -1, -1), (8, 1, -1)):
            if shape & bit:
                put(x + dx, y + dy, terrain)

    for y in range(1, 9):
        put(1, y, 7)
    for base in (2, 5, 8):
        down = bool(random_byte() & 1)
        bend = base + 1 if down and base != 8 else base - 1
        turn = (random_byte() & 1) + 3
        for x in range(1, turn + 1):
            put(x, base, 7)
        for x in range(turn, 7):
            put(x, bend, 7)
        for x in range(6, 9):
            put(x, base, 7)
        put(9, base, 8)

    for y in range(4, 7):
        for x in range(3):
            put(x, y, 7 if x == 1 else 1)
    put(1, 5, 6)
    put(8, 2, 6)
    put(8, 8, 6)
    for x, y, terrain in ((3, 0, 0), (5, 0, 4), (3, 9, 2), (5, 9, 3)):
        put(x + (random_byte() & 1), y, terrain)
    return bytes(arena)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("seed", nargs="?", default="0xACE1", type=lambda v: int(v, 0))
    args = parser.parse_args()
    arena = generate(args.seed)
    print(f"Seed ${args.seed:04X}; horizontal reflection gives equal route geometry")
    for y in range(HEIGHT):
        print("".join(TERRAINS[v] for v in arena[y * WIDTH:(y + 1) * WIDTH]))
    print("~ water | . grass | f forest | ^ desert | M mountain | r ford | c city | = road | # bridge")


if __name__ == "__main__":
    main()
