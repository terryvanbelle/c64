# Atlas: The Long March

A procedural geography and army-movement prototype for a stock Commodore 64.
The complete world has **65,536 × 65,536 logical tiles**: 4,294,967,296 locations.
Its edges wrap. The C64 generates each location from a 16-bit seed and its
coordinates; neither a giant baked map nor disk streaming is required.

![Regional map rendered by VICE](atlas.png)

## Controls and terrain

- **WASD / IJKL / C64 cursor keys / joystick port 2:** move the army in the close
  view; pan the map independently at wider scales.
- **Space / joystick fire:** cycle scales 1, 4, 16, 64, 256, 1,024, 4,096, then
  return to the close view centered on the army.
- **N:** generate a different world and return to its guaranteed safe capital.
- The HUD shows the map focus's east/south coordinates, seed, march count, current
  army terrain and pace. Coordinates, seed and march count use hexadecimal.
- The army remains at its true location while inspecting the overview. Its marker
  disappears when outside the visible area. Zooming does not move the army.

| Destination terrain | Minimum interval, 50 Hz ticks | Nominal interval |
|---|---:|---:|
| Open water | Impassable | — |
| Plains | 10 | 0.20 s |
| Forest | 20 | 0.40 s |
| Desert | 24 | 0.48 s |
| Mountain | 48 | 0.96 s |
| River, crossed by fording | 36 | 0.72 s |
| City | 6 | 0.12 s |
| Road | 4 | 0.08 s |
| Bridge | 6 | 0.12 s |

Movement is cardinal and checks the actual destination tile. Simultaneous
directions have a fixed priority; diagonals do not bypass terrain costs.
Rendering and the next screen publication can extend a nominal interval,
particularly the fastest road movement. Cached close-view redraws take about
0.09 seconds before publication on PAL, so this limit is small.

A view contains 20 × 10 metatiles, each 16 × 16 pixels. At the widest scale the
sample spacing is 4,096 world tiles: the view spans 81,920 × 40,960 coordinate
units. Because the world wraps every 65,536, some horizontal territory repeats
at that scale. Panning covers the remaining latitude.

Fine overviews retain narrow roads, rivers and cities with representative area
sampling. At scales 256 and above, the map shows underlying natural geography;
drawing every settlement in these large areas would obscure the terrain.

There is no combat, opponent, conquest or save system in this prototype.

## Procedural geography

Everything is generated on the C64 at runtime:

1. The seed shuffles a 256-byte permutation with a bounded LFSR sequence.
2. Integer bilinear value noise describes 256-tile landmasses and 64-tile biome
   contours. Coastal detail softens the four-tile field sampling grid.
3. Height and moisture thresholds create plains, forests, deserts and mountain
   ridges. Winding rivers cross the land and stop at sea.
4. Regional settlement centers have cities on natural land. Curved roads link
   neighboring regional centers on dry ground; river crossings become bridges.
   Sea interrupts the land network.
5. A small graded land halo around the seed-selected capital guarantees a
   passable starting location even for an ocean-heavy seed.

A 32-entry field cache avoids repeating noise interpolation for nearby cells.
The 22 × 12 viewport includes a border for four-neighbor connection masks. When
the close view moves one tile, overlap-safe shifts reuse its interior and
generate only 12 or 22 new edge tiles.

[atlas_world_reference.py](../tools/atlas_world_reference.py) is a readable
integer model for development. It generates no assets used by the shipped PRG.

## Hardware and memory

| Region | Owner |
|---|---|
| `$0002` onward | Declared main-only zero-page pointers and world/cache scratch |
| `$0100–$01FF` | Application-owned hardware stack |
| `$0200–$07FF` | Explicitly cleared state budget; linker bounds actual usage |
| `$0801–$080C` | Standard BASIC `SYS 2061` stub |
| `$080D–$3FFF` | Code budget |
| `$4000–$5FFF` | Read-only tables budget |
| `$6000–$67FF` | Original character-graphics source |
| `$6800–$69FF` | Four army frames and four black backing frames |
| `$8000–$83FF`, `$8400–$87FF` | Complete alternate screen buffers and sprite pointers |
| `$8800–$8FFF` | Custom VIC character graphics |
| `$A000–$A1FF` | VIC-visible army sprite frames |
| `$B000–$B3FF` | Pending color buffer |
| `$D800–$DBE7` | Visible Color RAM |
| `$FFFA/$FFFB`, `$FFFE/$FFFF` | RAM NMI and IRQ vectors |

The CPU keeps RAM and I/O visible with `$01` low bits `101`. CIA2 selects VIC bank
`$8000` with serial bits preserved. The custom font and sprites avoid the VIC's
character-ROM window at `$9000–$9FFF`.

The raster IRQ starts at line 16. It owns the regional 50 Hz fractional clock,
keyboard/joystick polling, action-edge latch, sprite animation and publication.
Main owns generation and preparation. Held controls and accumulated action
presses are consumed atomically, retaining short Space/N taps during rendering.
Keyboard scanning drives only selected low output lines to avoid fighting held
joystick contacts. CIA sources are masked and acknowledged; RESTORE is safely
ignored by the RAM NMI handler.

The final publication flag is written after all pending screen/color/marker
state is complete. Color RAM is copied in increasing raster-row order with
unrolled loops. Actual PAL commits finish around raster 190–191, comfortably
before the last map row's fetch at raster 219. Main never edits a published
color buffer until the IRQ finishes.

No accelerator, REU, cartridge, undocumented instruction, VSP, FLI, fastloader,
KERNAL service during play, or emulator-only runtime service is needed.

## Build and load

```sh
make atlas
make run-atlas
make atlas-disk
make run-atlas-disk
```

The prebuilt files are [dist/atlas.prg](../dist/atlas.prg) and
[dist/atlas.d64](../dist/atlas.d64). For VICE's GUI, select the PRG with
**File → Smart attach**, load it, and enter `RUN` at the C64 prompt if it has
not started automatically. PRG autostart mode **Inject into RAM** is convenient.

On a physical C64, use ordinary `LOAD"ATLAS",8,1` followed by `RUN` from a
supported storage device. All graphics, code and tables are in the single load.

## Verification — 2026-10-13

The final 25,089-byte PRG, including load header, has SHA-256:

`d64b19637290944aaec52de93671e3e7a80314e32893088b9b9c27d9fcfc7616`.

VICE 3.10 `x64sc` passes normal cold autostart on PAL/6581, common NTSC/8580 and
early NTSC/6581. Each model exercises:

- All seven zoom scales, 12 overview pans and return to the army.
- Seven cardinal close-view scrolls using the incremental viewport cache.
- All eight passable terrain costs, blocked sea, both coordinate-wrap axes,
  and new-world generation with a new capital.
- 77 completed views, checking 20,328 generated terrain cells, 61,600 character
  quadrants and 61,600 color entries against the independent reference.
- Eight actual emulator-frame captures compared with source character pixels
  outside the hardware army sprites, with zero mismatches.
- VIC banking, font, sprite frames, pointer tables and model detection.

The exact D64 additionally passes a cold boot with 1541 true drive emulation
enabled and device-8 loading traps disabled, followed by screen/memory and
actual-frame comparisons.

Rendering performance is measured in emulated C64 cycles, including IRQ work
and VIC DMA. Host wall-clock speed or warp does not change the algorithm's
cycle cost. At normal 100% emulation speed this predicts stock-machine
performance; [VICE describes x64sc's cycle-based VIC emulation](https://vice-emu.sourceforge.io/vice_1.html).
Cached PAL scrolling uses 84,468–92,554 cycles. Fine overview redraws take about
0.9 seconds, and wide ones about 0.7 seconds. Publication follows at the next
raster commit.

Movement/action verification injects normalized controls into CPU A at the
documented input-snapshot label; bounded terrain probes also reposition the
army. These debug actions do not prove the CIA keyboard/joystick electrical
path. That path is source audited against the linked hardware references.
No PC jump is used to claim successful startup. macOS Accessibility permission
was unavailable for synthetic host keyboard input.

The verification helper is `tools/verify_atlas.py`; its reports, actual captures
and linker outputs live under `build/atlas/`. The known VICE 3.10 framebuffer
metadata quirks are handled with recorded crop offsets and exact pixel checks.

**A real C64 has not yet been available. Physical-machine validation remains
pending.**
