#!/usr/bin/env python3
"""Add the C64 load-address header to a linked image based at $0801."""

from pathlib import Path
import sys


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: make_prg.py INPUT.bin OUTPUT.prg")

    source = Path(sys.argv[1])
    target = Path(sys.argv[2])
    payload = source.read_bytes()
    if not payload:
        raise SystemExit(f"refusing to create an empty PRG from {source}")

    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(bytes((0x01, 0x08)) + payload)
    print(f"Wrote {target} ({len(payload) + 2} bytes, load address $0801)")


if __name__ == "__main__":
    main()
