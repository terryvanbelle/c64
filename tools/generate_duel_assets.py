#!/usr/bin/env python3
"""Build Bannerfall's original flag/projectile sprites and reuse Atlas's art."""
from pathlib import Path
import shutil
import generate_atlas_assets as atlas

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "duel"


def sprite(points):
    data = bytearray()
    for y in range(21):
        row = sum(1 << (23 - x) for x in range(24) if (x, y) in points)
        data.extend(row.to_bytes(3, "big"))
    return bytes(data) + b"\0"


def main():
    # Keep this output separate from Atlas's concurrent make target.
    atlas.OUT = OUT / "atlas_source"
    atlas.main()
    OUT.mkdir(parents=True, exist_ok=True)
    for name in ("charset.bin", "assets.inc"):
        shutil.copyfile(atlas.OUT / name, OUT / name)
    flags = bytearray()
    for frame in range(2):
        pixels = {(2, y) for y in range(1, 17)} | {(x, 17) for x in range(6)}
        for x in range(3, 12):
            wave = (x + frame * 2) // 3 % 2
            for y in range(2 + wave, 7 + wave):
                pixels.add((x, y))
        flags.extend(sprite(pixels))
    bullet = sprite({(0, 1), (1, 0), (1, 1), (1, 2), (2, 1)})
    army = (atlas.OUT / "sprites.bin").read_bytes()
    shadow = (atlas.OUT / "army_shadow.bin").read_bytes()
    data = army + shadow + flags + bullet + bytes(64)
    assert len(data) == 768
    (OUT / "sprites.bin").write_bytes(data)
    print(f"Bannerfall: {len(data)} sprite bytes; shared original Atlas terrain/font")


if __name__ == "__main__":
    main()
