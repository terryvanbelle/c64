# Nocturne

A text-free, unattended dance piece for a stock 64 KB Commodore 64. Original
procedural art and an original 24-bar SID composition, *Suspension*, are built
from source. The mood is a quiet contemporary ballet on a moonlit stage.

## How it works

- 96 looping, smoothly interpolated poses form a 48×84 source silhouette. Eight
  hires sprites expand it to 96×168 display pixels. The asymmetric dress and
  wrist/ankle gestures are drawn procedurally, rather than downloaded artwork.
- A keyframe plus cyclic XOR differences use 13,427 bytes, including frame
  pointers. RLE zero runs skip unchanged bytes. The decoder writes the inactive
  sprite buffer; the IRQ commits a complete frame through its pointer table.
- A custom 256-glyph stage combines lavender/cyan light curtains and curved floor
  ripples. Sixteen animated glyphs provide independent twinkles and water glints.
- Raster IRQs above the picture update sprite position, illumination and the
  50 Hz simulation clock. Pose changes run at 25 Hz, with slow spatial movement.
- The three-voice 6/8 score has triangle melody, soft pulse arpeggios and a triangle
  bass/pad. Its 43.2-second loop uses no filters or combined waveforms. The
  playback cadence and PAL/NTSC pitch tables are separate.

## Memory and hardware contract

| Region | Owner |
|---|---|
| `$0002–$0008` | Main-loop copy/decoder scratch; IRQ/NMI do not touch it |
| `$0100–$01FF` | Hardware stack, owned by this non-returning application |
| `$0200` onward | Explicitly cleared BSS; bounded to under 256 bytes |
| `$0801–$080C` | BASIC `SYS 2061` entry stub |
| `$080D–$1FFF` | Code budget, including music and writable decoder operands |
| `$2000–$2FFF` | Motion, glyph animation and music tables |
| `$3000–$3FCF` | Packed stage source: screen, colors, charset |
| `$4400–$47FF` | VIC screen and eight sprite pointers |
| `$4800–$49FF`, `$4A00–$4BFF` | Two complete sprite buffers |
| `$5000–$57FF` | VIC-visible character graphics |
| `$6000–$9472` | Compressed choreography and its keyframe |
| `$D800–$DBE7` | 1,000 visible Color RAM cells |
| `$FFFA/$FFFB`, `$FFFE/$FFFF` | RAM NMI and IRQ vectors |

The VIC bank is `$4000`, selected by CIA2 with its other port bits preserved.
CPU mapping remains `$35` after startup; I/O is always accessible. CIA interrupt
sources are masked/acknowledged. Own handlers preserve CPU registers, use no
shared decoder scratch, and acknowledge the VIC raster flag explicitly. RESTORE
is ignored safely through the application's RAM NMI handler. Exit via reset or
the emulator's normal close action; there are no application input controls.

The PRG begins at `$0801`, ends below I/O, and uses the standard BASIC startup
stub. The D64 contains a single normal PRG file, with no fastloader, accelerator,
cartridge, REU, VSP, FLI, undocumented opcode or emulator-only service.

Regional timing is detected from raster length: PAL 312×63, common NTSC263×65,
old NTSC262×64. A 16-bit fractional accumulator schedules nominal 50 Hz work
using increments `$FF5D`, `$D5F4`, `$D1DC`; the SID uses the appropriate machine
clock for note pitch. These values follow the [official VICE timing constants](https://raw.githubusercontent.com/VICE-Team/svn-mirror/main/vice/src/c64/c64.h).

## Build and run

```sh
make all             # build/nocturne.prg
make run             # native VICE window
make disk            # build/nocturne.d64
make run-disk        # emulated 1541, true drive, no device-8 loading traps
```

For a chosen model or SID:

```sh
python3 tools/run_vice.py --model ntsc --sid 8580 build/nocturne.prg
python3 tools/run_vice.py --model oldntsc --sid 6581 build/nocturne.prg
```

The physical-machine path is `LOAD"NOCTURNE",8,1` then `RUN`. All graphics and
music are included in the load; no disk traffic occurs once the dance starts.

## Verification

Validation uses x64sc's rasterized display, CPU state and actual RAM. Frame data
is compared against the generated source for every pose; this catches errors
in the 6502 decoder that a host-side codec round trip alone cannot detect.
The monitor helper accepts only loopback connections. No PC jump is used to
claim startup success.

Verified on 2026-10-13 in VICE 3.10 `x64sc`, at normal emulation speed, with
ordinary cold autostart and no monitor PC override:

| Machine / SID | Pose preparations checked | Active + pending buffer comparisons | Worst preparation cycles | Video frame cycles | Missed requests |
|---|---:|---:|---:|---:|---:|
| PAL / 6581 | 288 (three loops) | 576 | 15,582 | 19,656 | 0 |
| Common NTSC / 8580 | 288 (three loops) | 576 | 15,583 | 17,095 | 0 |
| Early NTSC / 6581 | 288 (three loops) | 576 | 15,582 | 16,768 | 0 |

Every comparison checks all 512 sprite-buffer bytes against the source pose.
The checks also cover VIC mode/bank configuration, pointer tables, screen,
static charset, Color RAM, and regional simulation cadence. Preparation timing
includes active sprite DMA and interrupted IRQ work from buffer copy through
decode completion; animated glyph updates run afterward. Raster/cycle deltas
assume completion within one frame, supported by the measured headroom and
independent zero-missed-request checks.

Four quarter-loop captures per machine confirm distinct poses in the actual
emulator framebuffer. Static stage pixels outside the moving dancer also match
the generated screen/charset/colors exactly. VICE 3.10's PAL debug framebuffer
reports its inner viewport one row below the actual picture; the verifier
records both offsets and adjusts its crop only after an exact background match.
This affects screenshot cropping, not the C64 program or visible emulator image.

The standard D64 also cold-boots using a 1541 with true drive emulation enabled
and device-8 loading traps disabled. A further complete choreography loop checks
all 96 poses after that disk load. The original proof-of-concept still builds.

The verified PRG is 35,956 bytes including its load header; SHA-256:
`e65fe1eed7623b9d6ff2c0a4f41101f4f46d0fb391803ef466ca3470536c0c30`.

A real C64 has not yet been available. These are emulator results; the first
physical-machine run remains to be done when hardware is available.

For development, start a monitor-enabled instance and check it with:

```sh
python3 tools/run_vice.py --monitor-port 6512 build/nocturne.prg
python3 tools/verify_dance.py --port 6512 --standard pal --cycles 3
```

The generated linker map, labels, source-art contact sheet, emulator captures
and verification reports live under `build/dance/`. The original proof-of-concept
demo remains available with `make demo` / `make run-demo`.
