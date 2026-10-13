#!/usr/bin/env python3
"""Bake slow stage movement; the C64 needs no trigonometry or floats."""
from pathlib import Path
import math


def main():
    output = Path("build/dance/motion.inc")
    output.parent.mkdir(parents=True, exist_ok=True)
    tables = {
        "horizontal_motion": [136 + round(8 * math.sin(i * math.tau / 256))
                              for i in range(256)],
        "vertical_motion": [62 + round(math.sin(i * math.tau / 128))
                            for i in range(256)],
    }
    lines = ["; Generated motion table; VIC coordinates."]
    for name, values in tables.items():
        assert all(0 <= v < 256 for v in values)
        lines.append(name + ":")
        for start in range(0, 256, 16):
            lines.append("    .byte " + ",".join(str(v) for v in values[start:start+16]))
    output.write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
