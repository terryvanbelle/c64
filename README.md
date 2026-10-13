# C64 experiments

## Bannerfall

A local two-player capture-the-flag game across a fresh procedural battlefield.
Guide cyan and gold armies through forests, deserts, cities, fords, roads, and
bridges. Mountains block movement and shots; fast roads reward bold raids,
while slower river crossings offer flanking routes. Mirrored geography gives
both players equal starting terrain.

Steal the enemy flag and bring it home while your own flag is safe. First to
three captures wins; a tied 2:30 match enters sudden death. Any hit drops a
carried flag, and a defeated army quickly respawns for another attempt.

**Shared keyboard:** player 1 uses **WASD + X**; player 2 uses
**U/B/N/M + period** (up/left/down/right + fire).
**Two joysticks:** player 1 uses **port 2**, player 2 **port 1**.
Choose **K** or **J** on the title screen, then both players press fire to ready.
Release gameplay controls to choose a mode or use **F1** for a new field.
**RUN/STOP** pauses (**Escape** in macOS VICE); **Return** also pauses in
keyboard mode.

![Bannerfall rendered by VICE](docs/bannerfall.png)

Download the prebuilt [Bannerfall PRG](dist/bannerfall.prg) or
[1541 disk image](dist/bannerfall.d64), or build and run with:

```sh
make duel
make run-duel
make duel-disk        # build/bannerfall.d64
make run-duel-disk
```

See [Bannerfall rules and hardware notes](docs/BANNERFALL.md) for movement costs,
controls, generation, audio, and compatibility status.

## Atlas: The Long March

A procedural world of water, forests, deserts, mountains, winding rivers,
cities, roads, and bridges. Move an army through the landscape; terrain changes
travel speed and water blocks movement. The world is 65,536 × 65,536 tiles and
wraps at its edges. Geography is generated on the C64 as needed, with no disk
streaming or memory expansion.

**Controls:** WASD or IJKL, C64 cursor keys, or a joystick in port 2. Space/fire
cycles seven zoom levels (1, 4, 16, 64, 256, 1,024 and 4,096 tiles per displayed
cell). Directions pan the overview while zoomed out; the army stays in place.
Cycling back to the close view returns to the army. N generates a new world.

![Atlas regional overview rendered by VICE](docs/atlas.png)

Download the prebuilt [Atlas PRG](dist/atlas.prg) or [1541 disk image](dist/atlas.d64),
or build and run with:

```sh
make atlas
make run-atlas
make atlas-disk       # build/atlas.d64
make run-atlas-disk
```

See [Atlas design and hardware notes](docs/ATLAS.md) for terrain costs,
procedural generation and compatibility results.

## Nocturne

An original dance animation for a stock Commodore 64: a luminous ballet figure,
lavender and cyan curtains of light, twinkling motes, water glints, and a gentle
three-voice SID score. It loops without text or user controls.

The dancer has 96 original poses in eight expanded hires sprites. XOR/RLE frame
compression, two sprite buffers, and a raster-driven scheduler keep animation,
lighting, and music coordinated. PAL, common NTSC and old NTSC are detected at
startup; simulation rate and SID pitch are adjusted separately.

![Nocturne rendered by VICE](docs/nocturne.png)

## Build and run

Download the prebuilt [Nocturne PRG](dist/nocturne.prg) to run it without building.

With Python 3, `cc65` (ca65/ld65) and VICE installed:

```sh
make all
make run
```

`make all` builds Bannerfall, Atlas, and Nocturne; `make run` launches Nocturne.
The Nocturne output is `build/nocturne.prg`. The build regenerates the original graphics
using Python's standard library; it needs no downloaded art or Python packages.
On macOS the launch helper supplies the native app context needed by GTK VICE.
Generated launchers and emulator logs stay under `build/dance/`.

To create a standard 1541 disk image, run `make disk`; `make run-disk` exercises
that image with true drive emulation and device-8 loading traps disabled.
On a physical C64, transfer the PRG to a supported storage device, or write the
generated D64 to a disk, then use `LOAD"NOCTURNE",8,1` followed by `RUN`.

See [the implementation and hardware notes](docs/NOCTURNE.md) for the memory map,
compatibility scope and verification record. Physical hardware testing remains
to be done when a C64 is available.

## Original proof of concept

The earlier border-animation demo remains in `src/demo.s`. Build it with
`make demo` and launch it with `make run-demo`.

## Game development reference

See [TIPS_AND_TRICKS.md](TIPS_AND_TRICKS.md) for researched guidance on C64
graphics, memory, interrupts, game architecture, input, audio, and debugging.
