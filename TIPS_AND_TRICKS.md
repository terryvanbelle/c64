# Tips and tricks for Commodore 64 game development

Research reviewed: **2026-10-13**. Target: a stock C64, developed with this
repository's **ca65 / ld65** toolchain and **VICE x64sc**.

This is a working reference for future games in this repository. Read the quick
defaults and the relevant sections before changing an engine. Hardware facts are
linked to original manuals, chip documentation, emulator source, or firsthand
technical investigations. Engine advice draws on original articles and game code,
especially Lasse Öörni's Covert Bitops work. Recommendations here are a synthesis;
they are starting points, not requirements for every genre.

## Contents

- [Quick defaults](#quick-defaults)
- [Plan the budgets and memory map](#plan-the-budgets-and-memory-map)
- [CPU banking and zero page](#cpu-banking-and-zero-page)
- [VIC-II memory and display modes](#vic-ii-memory-and-display-modes)
- [Sprites and multiplexing](#sprites-and-multiplexing)
- [Frame timing and interrupt ownership](#frame-timing-and-interrupt-ownership)
- [Game state, movement, and collision](#game-state-movement-and-collision)
- [Scrolling and world data](#scrolling-and-world-data)
- [6502 performance and correctness](#6502-performance-and-correctness)
- [Input](#input)
- [Music and sound effects](#music-and-sound-effects)
- [Assets, compression, and loading](#assets-compression-and-loading)
- [Build and debugging workflow](#build-and-debugging-workflow)
- [Troubleshooting and release checks](#troubleshooting-and-release-checks)
- [Sources and further reading](#sources-and-further-reading)

## Quick defaults

For a first playable game:

1. Build one complete gameplay loop on a static character screen, with fixed
   hardware sprite slots and joystick port 2.
2. Choose the supported video standards, interrupt model, and music player before
   assigning memory. Record those choices with the game's source.
3. Keep simulation, graphics preparation, and display deadlines separate. Publish
   a complete next display state; reuse the previous state if preparation is late.
4. Use bounded actor pools, explicit tile collision properties, and integer or
   fixed-point movement. Reserve essential actor slots before adding effects.
5. Measure the busiest scene with music, sprites, and scrolling active. Keep
   headroom for worst cases.
6. Make source art and conversion scripts reproducible. Check the actual shipped
   PRG/disk image from a cold reset, then on real hardware when available.

Add multiplexing, multidirectional scrolling, packed sprite caches, and exact
cycle effects when a measured need justifies their complexity. The current demo
proves assembly and display; its permanently disabled IRQs, busy-wait delay, and
assumed default display state are not yet a game engine.

## Plan the budgets and memory map

Write down the maximum actors, simultaneous sprites on one scanline, animation
frames, map dimensions, music size, scroll speed, and supported loading devices.
Budget **RAM**, **CPU time**, and **disk size** separately. A smaller packed file
can still require too much RAM or too much time to unpack.

Maintain an allocation table with start, end, size, alignment, owner, and lifetime
for code, zero page, stacks, screens, charset/bitmap, sprite frames, music,
collision data, and load/decompression buffers. Loading destinations and temporary
buffers are part of this map. Reuse memory only when the former owner is finished.

Use linker regions and segments to enforce the plan. Emit a map file with
`ld65 -m`, labels with `-Ln`, and debug information with `--dbgfile`. `BSS` consumes
RAM without adding initialized payload bytes; standalone assembly must initialize
it. Match linker alignment to assembly alignment. Avoid `fill=yes` on a large PRG
region unless the padded output is intentional. [ld65 documentation][ld65]

## CPU banking and zero page

The CPU and VIC-II have different views of memory. The 6510's `$0000` is its port
direction register; `$0001` controls CPU ROM/I/O visibility using bits 0–2. Preserve
unrelated cassette bits, and ensure the banking bits are configured as outputs.
[Commodore: CPU port][prg-port]

For a normal machine **without a cartridge**, these common settings illustrate the
CPU view. The full values assume the conventional upper port bits; prefer changing
only the intended bits in an established engine.

| `$01` low bits / common value | `$A000–$BFFF` | `$D000–$DFFF` | `$E000–$FFFF` |
|---|---|---|---|
| `111` / `$37` | BASIC ROM | I/O | KERNAL ROM |
| `110` / `$36` | RAM | I/O | KERNAL ROM |
| `101` / `$35` | RAM | I/O | RAM |
| `100` / `$34` | RAM | RAM | RAM |

Cross-checked against [VICE's no-cartridge memory configurations][vice-memory].

With both LORAM and HIRAM clear, I/O is unavailable even if CHAREN is set. Writes
beneath mapped BASIC/KERNAL ROM reach RAM; reads still see ROM. Mapped I/O writes
reach devices, so accessing RAM underneath I/O requires a deliberate banking
window. Keep interrupt code and data accessible. If I/O is hidden, a handler must
restore it before touching VIC/SID/CIA registers or be prevented from running
throughout the window; NMI still needs handling.
[Commodore: banking behavior][prg-banking], [all-RAM map][prg-allram]

Do not treat `$02–$FF` as free while using KERNAL, BASIC, a loader, a player, or a C
runtime. Declare ownership and separate IRQ scratch from main-loop scratch. Page
`$0100–$01FF` is the hardware stack; leave room for the deepest call chain plus
interrupt saves. The demo's `$02–$08` usage must be reconsidered when integrating
system services.

At startup, establish banking and interrupt ownership; initialize BSS and software
shadows; configure CIA/VIC state and disable unwanted sources/sprites; load assets;
initialize screen/pointer tables and actor state; prepare the first complete
display; clear pending flags; then enable the intended interrupts/display. Set
or reset the stack only when that startup path owns it. Avoid depending on values
left by BASIC, a previous scene, or an emulator snapshot.

In ca65, use `.ZEROPAGE` or a segment marked `zeropage`, with matching linker
placement. Use `.importzp` / `.exportzp` across modules. Add `.assert` checks for
alignment and size contracts; select `.setcpu "6502"` for ordinary NMOS code rather
than accidentally using 65C02 instructions. [ca65 documentation][ca65]

## VIC-II memory and display modes

The VIC-II sees a **16 KB bank**. CIA2 `$DD00` bits 0–1 select banks in inverted
order: `3 → $0000`, `2 → $4000`, `1 → $8000`, `0 → $C000`. Configure the corresponding
DDR bits and preserve the other CIA2 port bits, especially serial-bus signals.

Within that bank, `$D018` selects these bases:

| Resource | Address / allocation |
|---|---|
| Screen | `bank + (($D018 >> 4) * $0400)`; reserve 1 KB |
| Charset | `bank + (($D018 & $0E) * $0400)`; 2 KB alignment |
| Bitmap | `bank + (($D018 & $08) * $0400)`; 8 KB alignment |
| Sprite pointers | `screen_base + $03F8` through `+$03FF` |
| Sprite shape | `bank + pointer * 64`; 63 image bytes in a 64-byte slot |

Changing the screen base changes the sprite-pointer table too. VIC character ROM
appears at `$1000–$1FFF` and `$9000–$9FFF` independently of CPU banking; avoid those
windows for custom VIC graphics. [Oswald/Resource: VIC memory organization][vic-memory]

Clear only the 1,000 visible screen bytes, or rebuild sprite pointers after a full
1 KB clear/copy. Do this for every screen buffer. The current demo's four-page
clear also writes `$07F8–$07FF`, harmless while its sprites are disabled.

| Mode | Visible picture storage | Color constraints |
|---|---|---|
| Hires character | 2,048-byte font + 1,000 screen bytes | Global background; one foreground color per 8×8 cell |
| Multicolor character | Same font/screen sizes; 4×8 wide pixels per multicolor cell | Three global colors; cell color 0–7 |
| Hires bitmap | 8,000 picture bytes + 1,000 screen attribute bytes | Two colors per 8×8 cell |
| Multicolor bitmap | 8,000 picture bytes + screen attributes + Color RAM | Global background plus three colors per 4×8 cell |
| Extended background character | 64 usable glyphs (512 picture bytes) + screen | Four selectable backgrounds; one cell foreground |

These are visible data sizes; reserve the hardware-aligned regions and any buffers.
Character modes are a useful default for tile worlds, while bitmaps suit imagery
that needs individual cell patterns. Design art within the selected mode's local
color limits. [Commodore: character modes][prg-multicolor], [extended backgrounds][prg-ecm],
[bitmap modes][prg-bitmap]

Color RAM is separate 4-bit storage at `$D800–$DBFF`; only 1,000 cells are visible.
Mask reads to the low nibble when comparing colors. `$D018` cannot double-buffer it.
In multicolor character mode, Color RAM bit 3 selects multicolor for each cell;
cells with that bit clear remain hires, useful for readable text.
[Commodore: multicolor color selection][prg-colors]

Keep PETSCII, screen codes, and glyph indices distinct. Direct screen writes need
screen codes; KERNAL text routines interpret PETSCII and control characters. Have
the asset/text exporter perform the intended conversion instead of assuming host
ASCII bytes display correctly. [Character-set reference][charset]

## Sprites and multiplexing

There are eight hardware sprites. Hires shapes are 24×21 pixels; multicolor shapes
have 12×21 wide pixels. Each sprite has its own color; multicolor also uses shared
`$D025/$D026`. The private color registers are `$D027–$D02E`. Animation normally
changes the shape pointer rather than copying a shape every frame.

Sprite X is nine bits: low bytes occupy the even registers `$D000–$D00E`, and
`$D010` contains all eight high bits. Keep full logical X coordinates and update
both parts. Maintain software shadows for shared sprite-control bitfields so
updating one slot preserves the others. Reserve slots for combined sprites and
color overlays. [Oswald/Resource: sprites][sprite-intro]

A multiplexer reuses hardware slots at different vertical positions; it does not
remove the eight-sprites-per-line limit. Sort virtual sprites by Y, cull offscreen
ones, and define overload priority so essential actors remain visible. Allow time
between a slot's old and new uses; expanded sprites occupy more lines. Changing
pointer/color before the previous shape finishes can corrupt it.
Set a reused slot's Y before the beam reaches that position; a late write can make
the sprite disappear for that frame.

Prepare a complete sorted list outside the critical display IRQ and publish it
atomically, often by swapping buffers. Precalculate shared register values where
useful. Stress crowded overlaps, mass spawning, and order reversals; a calm scene
does not demonstrate the worst-case cost. [Öörni: sprite multiplexing][multiplex]

## Frame timing and interrupt ownership

### Budget for the actual video standard

| VIC variant | Lines/frame | Cycles/line | Raw cycles/frame |
|---|---:|---:|---:|
| PAL 6569 | 312 | 63 | 19,656 |
| Common NTSC 6567R8 | 263 | 65 | 17,095 |
| Old NTSC 6567R56A | 262 | 64 | 16,768 |

Frame totals are products of the official emulator constants, **before** DMA and
interrupt overhead. PAL is approximately 50 frames/s; common NTSC approximately
60. The faster NTSC CPU still has fewer cycles per video frame. Select/detect the
standard and budget every supported path. [VICE machine timing source][vice-timing]

Badlines fetch screen/color rows and steal CPU time; bitmap mode has them too.
Sprite DMA also costs cycles. Measure with the real display mode, active sprites,
and worst scrolling work rather than counting instruction cycles in an empty
border. [Bauer: VIC-II timing, §§3.5–3.8][bauer]

Choose an explicit simulation rate. A fractional tick accumulator can pace game
logic independently of display frames. Skipping roughly every sixth NTSC tick
approximates a PAL-rate simulation, but refresh rates are not exact integers.
Keep rendering, input latency, audio call cadence, and pitch correction as separate
decisions. Cycle-specific raster schedules also need regional variants.

### Choose one interrupt ownership model

| Model | Entry and exit contract | Consequence |
|---|---|---|
| KERNAL remains mapped | CPU enters ROM; KERNAL pushes A/X/Y and dispatches through `$0314/$0315`. Respect that stack frame and the saved handler. | Normal services can be preserved deliberately. |
| Engine owns RAM vectors | With KERNAL out, IRQ uses `$FFFE/$FFFF`. Save/restore your own registers and end with `RTI`. | `$0314` is not automatically consulted; system services need an explicit plan. |

`$EA81` is the stock KERNAL register-restore/RTI exit, not an `RTS` subroutine; it
skips normal keyboard/jiffy work. Do not use it as the exit of a bare RAM-vector
handler. Removing KERNAL IRQ service also removes automatic keyboard scanning.
[Original KERNAL dispatch][kernal-irq], [service and exit][kernal-editor]

Dispatch the sources deliberately. Running stock system service on every raster
IRQ can change its cadence; returning through `$EA81` does not acknowledge a CIA
source. Preserve or replace each service intentionally.

Install vectors and initialize state before enabling the IRQ. Save the registers
the entry path requires; `RTI` restores processor status and PC, not A/X/Y. `SEI`
does not disable NMI: when banking KERNAL out, provide an accessible NMI handler
and vector at `$FFFA/$FFFB`. Short critical sections must account for all possible
interrupt readers. [MOS: interrupt bus sequence][mos-cycles]

Give NMI a policy for CIA2 and RESTORE, including the bank state on return; an
accessible vector alone does not guarantee safe resumption. RESTORE is separate
from the scanned keyboard matrix. [Keyboard wiring][keyboard]

### Treat interrupt registers according to their semantics

Raster IRQ targets use written `$D012` plus `$D011` bit 7; reads give the **current**
raster position. Keep a `$D011` shadow rather than copying its readback bit 7 while
changing scroll bits. Enable raster IRQ with `$D01A` bit 0. For a raster-only source,
explicit `lda #$01` / `sta $d019` acknowledges that flag; pending sources need their
own handling. `$D01E/$D01F` collision latches clear when read: snapshot once if used.
[Bauer: raster IRQ and collision registers, §§3.8.2, 3.12][bauer]

CIA interrupt-control reads acknowledge pending flags. Disabling masks does not
automatically clear old flags. Coordinate CIA1 IRQ and CIA2 NMI ownership and clear
stale state before enabling your sources. Do not insert gratuitous `$DC0D` reads
into unrelated routines. [MOS 6526 datasheet][cia]

Use ordinary raster IRQs for frame scheduling. Exact horizontal effects need
stabilization and a proven cycle schedule. VSP scrolling can corrupt RAM on some
real machines; FLI, border opening, sprite stretching, and VSP need explicit
hardware assumptions and verification. [Åkesson: Safe VSP experiments][safe-vsp]

## Game state, movement, and collision

Keep the main loop responsible for input normalization, AI, movement, collision,
and preparation. Let bounded IRQ work commit display changes and meet audio
deadlines. Use a byte-sized publication flag/index or a protected pointer swap so
the IRQ never consumes half a new display list. Keep separate scratch state.

If preparation overruns, retain a coherent previous display state and count the
missed deadline. Lower-rate simulation with interpolated rendering is an option;
measure responsiveness before adopting it. Öörni reports that four-frame
interpolation felt lagged. Nested IRQs require separate state and correctly nested
register saves; they are an advanced architecture. [Öörni: frame scheduling][interpolation]

Use bounded actor pools with predictable work and memory. Reserve essential slots
for gameplay so particles cannot prevent shooting. Area-local active lists can
reduce searching. Reusing an actor slot as enemy → explosion is useful when its
state is reset deliberately. A common logical control format can serve player
input and AI. Exercise exceptional actor categories: an optimization in Steel
Ranger nearly left mines floating above moving platforms. [Öörni: interactions][interaction]

Keep world coordinates separate from camera-relative sprite coordinates. Use
fixed-point fractions when subpixel motion is needed; select ranges that cover
the world and velocities. Decide rounding, carry/borrow, clipping, and collision
behavior at boundaries explicitly. [Öörni: world coordinate design][scroll]

Store terrain properties independently from decorative glyphs: solid, ground,
climbable, hazard, slope. Store gameplay hitboxes/hurtboxes separately from sprite
pixels, changing them when a gameplay state calls for it. Probe the logical map.
Bound movement per update or handle traversal
of intermediate cells so a fast actor cannot skip a wall. Öörni's framework
provides inspectable property flags, indexed actor arrays, and slope tables; its
speed/collision assumptions belong to that engine. [Framework physics source][physics]

Hardware collision masks do not identify all colliding pairs, and multiplexing
changes which actor a hardware slot represents. Logical collision should remain
authoritative for gameplay; hardware latches can be an optional coarse signal.
[Bauer: collision semantics][bauer]

## Scrolling and world data

Fine scrolling uses the low three bits of `$D016` horizontally and `$D011`
vertically. When the offset wraps, coordinate the coarse character shift and new
edge. The 38-column/24-row border settings can hide incoming edges; stored screen
data still uses a 40-column stride. [Commodore: scrolling][prg-scroll]

Tiles/metatiles save map bytes. Power-of-two sizes and precomputed row/block
address tables simplify hot lookups. Larger blocks restrict art; choose them with
the artist/exporter. Double-buffering screen RAM can hide incomplete coarse
copies, but Color RAM still needs its own safe update schedule. Splitting copying
across frames constrains maximum scroll speed and direction changes. A
color-per-block rule can reduce work. [Öörni: multidirectional scrolling][scroll]

Double-buffering is an option, not a universal rule. Öörni's newer framework
redraws screen and color data in one frame using optimized code and data
constraints. Its editor enforces charset/tile limits and retains editable assets
alongside runtime exports. Adopt an architecture together with the asset rules
that make its deadlines achievable. [Original game framework][framework]

## 6502 performance and correctness

Profile first; improve data representation and avoid redundant work before
polishing individual instructions. Indexed property arrays let one actor index
address several byte fields. Lookup tables trade memory for repeated computation.

For hot loops, consider counting down to zero, using zero page, preserving useful
values in registers, and arranging the frequent branch path efficiently. Eligible
indexed reads gain a cycle on page crossing; taken branches cost more and can gain
another cycle on crossing. Alignment can stabilize timing but consumes space.
Self-modifying operands are useful in writable RAM when their ownership is clear;
an interrupt must not observe a partially patched operand. Undocumented opcodes
and repurposed stack-pointer tricks need their own compatibility review.
[Original optimization tutorial][optimize]

NMOS read-modify-write instructions write the original value before the modified
one. Avoid casually applying `INC/DEC/ASL` to I/O registers; extra writes and dummy
reads can have device side effects. Prefer an explicit masked store for ordinary
register updates. [MOS: instruction bus cycles][mos-cycles]

On NMOS CPUs, a `JMP (pointer)` whose pointer begins at `$xxFF` fetches the target's
high byte from `$xx00`. Assert that the pointer avoids this boundary. A zero-page
indirect pointer at `$FF` also wraps its second byte to `$00`, the C64 CPU port
register; allocate both pointer bytes deliberately. [MOS: indirect addressing][mos-cycles]

Initialize binary arithmetic with `CLD` when appropriate. Set carry deliberately
before an independent `ADC` or `SBC` chain; subtraction uses `SEC` for no incoming
borrow. `CMP` carry is useful for unsigned comparisons, but signed comparisons
need signed-aware logic. Document flag assumptions across calls. [MOS: arithmetic][mos-arithmetic],
[processor flags][mos-flags]

If adding cc65 C, inspect generated assembly and use unsigned byte types for
byte-sized data. Compiler `register` variables have save/restore costs; static
locals can reduce software-stack work while sacrificing reentrancy. IRQ code and
main-loop calls must not share static scratch accidentally. [cc65 guide][cc65]

## Input

Joystick port 2 reads through `$DC00`; port 1 through `$DC01`. Bits 0–4 are up,
down, left, right, fire, and **zero means pressed**. Normalize as
`pressed = (~raw) & $1F`. Sample once per chosen input tick; retain held state and
derive new presses as `pressed & ~previous` for menus and single-action controls.
[Commodore: joystick interface, pp. 343–345][prg]

Port 2 is a useful single-player default, but both ports share CIA1 lines with the
keyboard matrix. Test keyboard/joystick combinations and held directions. Custom
scanning and joystick reads must agree on latch/DDR state. [Firsthand keyboard
wiring investigation][keyboard]

A DDR bit value of 0 selects input; 1 selects output. CIA reads report pin levels
even for outputs, rather than the written output latch. Preserve intended latch
values in software instead of restoring a joystick-altered readback. Do not assume
setting `$DC02` to zero is always required: stock KERNAL
uses `$DC02=$FF` and `$DC03=0`. Document the helper's assumptions and preserve
state when other services still use the ports. [MOS 6526][cia], [original IOINIT][kernal-init]

## Music and sound effects

Select a game-compatible player before fixing the memory map. Document its load
range, entry points, register clobbers, zero page, call rate, and SFX interface.
Relocation may include zero-page addresses. A composer's export is not necessarily
a player that supports asynchronous game effects: SID Factory II's maintainer
explicitly describes that limitation for its drivers. [SF2 repository][sf2],
[maintainer's SFX answer, comments 15–16][sf2-sfx]

Give one audio subsystem ownership of SID writes. Reserve a voice for effects or
use a player that deliberately steals/resumes a voice while keeping song time.
The three voices share a filter and master volume; define ownership of those too.
Keep software shadows for settings instead of treating write-only register reads
as saved state. [Öörni: music routine design][music]

MiniPlayer 2 illustrates documented SFX support and the importance of its ABI:
music/page alignment, SFX page boundaries, atomic pointer updates, zero-page
footprint, and NTSC note-start behavior all need attention. These are that player's
constraints, not rules for every SID driver. [MiniPlayer 2 integration guide][miniplayer]

Correct **tempo and pitch separately**. The SID relation is
`frequency = register_value * machine_clock / 16777216`; changing how often a
player runs does not change that clock. Use regional frequency tables/player
support as well as the intended play-call cadence. [MOS 6581 datasheet][sid]

Listen with both 6581 and 8580 settings. Combined waveforms and filter behavior
differ; some waveforms audible on 8580 are weak on 6581, and noise combinations
can lock until reset. [JCH: SID instruments][sid-instruments]
GoatTracker's author also warns that emulated filters and individual real SIDs
differ. Preserve editable tracker projects; packed exports are not a substitute
for them. [GoatTracker manual (mirrored original documentation)][goattracker]

## Assets, compression, and loading

Have converters reject out-of-range colors, excess chars/tiles, invalid sprite
dimensions, misalignment, and impossible local palettes. Keep dimensions,
palette rules, frame order, and runtime encoding explicit in the asset format.
Bake repeated conversions on the host when possible. This is the repository's
recommended workflow, informed by the framework's integrated editor/exporter.

Compression must fit disk, live RAM, and decode-time budgets. Decode only the
current area when full-world expansion is too large. Simple byte-oriented formats
can suit fast room transitions better than a smaller but slower bitstream. Data
ordering and reconstructing repeated backgrounds can improve packing.
[Öörni: tile-map compression][tile-compression]

For packed animation, cache decoded frames shared by actors rather than unpacking
the same frame repeatedly. Protect cache slots used by both displayed and upcoming
frames. More cache reduces decoding at the cost of VIC-visible RAM.
[Öörni: sprite caching][sprite-cache]

Start with a single-load PRG if it fits. Move to disk loading when content needs
it, with explicit buffers and a transition state. Stock KERNAL IEC routines use
CIA1 Timer B, read its interrupt flags, briefly mask IRQs, and manipulate CIA2
serial bits. Ordinary loading does not promise uninterrupted raster/audio timing.
[Original KERNAL serial implementation][kernal-serial]

Fastloaders have device, banking, sprite, and save-file constraints. Follow the
chosen loader's contract and test each claimed device; 1541-specific code does not
automatically work with SD2IEC. [Öörni: loader documentation][loader]

## Build and debugging workflow

This repository builds with `make all`; `make run` invokes VICE with RAM autostart.
The PRG loads at `$0801`; its BASIC `SYS 2061` stub enters `$080D`. Keep that stub,
entry address, load header, and linker placement consistent as the program grows.

For a debug build, add ca65 `-g` and a listing (`-l`), and use ld65's map, VICE label,
and debug outputs. Assert hardware alignment and capacity constraints in the
source/configuration so asset growth fails during the build. These are documented
tool options, not extra targets already present in the Makefile.
[ca65][ca65], [ld65][ld65]

Use `x64sc` for raster work; VICE describes its VIC-II emulation as cycle-based and
pixel-accurate. Record the machine/SID model and input configuration with a bug
report so another run reproduces the environment. [VICE emulator features][vice-features]

The monitor can load ld65 labels using `ll "build/demo.lbl"` once that file is
generated. Use execution breakpoints and store watchpoints to catch overwrites;
inspect raster/cycle positions and stopwatch timing around expensive routines.
Toggle border colors around phases as a quick visual timing aid, then inspect the
longest frame. Watchpoints themselves pause the machine, so distinguish debugging
from an uninterrupted performance run. [VICE monitor][vice-monitor]

RAM autostart (`-autostartprgmode 1`) is a convenient iteration shortcut. It bypasses
the distribution's real loading path. For disk/fastloader compatibility, test the
disk image with true drive emulation and appropriate trap settings. Reset and boot
the artifact independently; a snapshot or monitor jump can hide startup bugs.
[VICE autostart settings][vice-settings], [drive-emulation distinctions][vice-features]

## Troubleshooting and release checks

| Symptom | First checks |
|---|---|
| Wrong glyphs or blank graphics | Screen-code conversion, VIC bank, `$D018`, ROM window, alignment |
| Sprites disappear or change shape | Enable mask, pointer table for the current screen, bank-relative pointer, cache lifetime |
| X wraps at 255 | Full logical coordinate and the appropriate `$D010` bit |
| IRQ fires continuously | Source acknowledgement, pending CIA flags, vector/exit contract |
| Raster split flickers | Entry jitter, page-crossing variation, DMA, regional schedule |
| Colors tear during scrolling | Color RAM update timing and screen/color coordination |
| Keys stop arriving | Keyboard scan ownership, CIA direction/latches, KERNAL service path |
| Works after monitor launch only | Initialization, load/stub address, vectors, uninitialized state |
| NTSC feels too fast or music sounds wrong | Simulation ticks, player call cadence, frequency tables, tighter frame budget |

Before claiming a release is ready:

- Cold-reset and start the exact distribution artifact using its documented path.
- Check start, play, pause, death, restart, level transitions, and save/load if used.
- Exercise maximum actors, overlaps, effects, scroll speed, and the busiest audio.
- Check held input, edges, diagonals, and supported keyboard/joystick combinations.
- Run each claimed video/SID/device configuration; record unsupported combinations.
- Inspect the final memory map and include load/decode buffers in the peak RAM use.
- Verify appearance and controls at normal speed, then on real hardware when
  available. Report emulator-only verification honestly.

Keep this guide current when a game establishes a better approach or exposes a
new hardware constraint. Record the circumstances and a source/reproducer rather
than turning a useful special case into a universal rule.

## Sources and further reading

The links throughout identify the relevant source at the point of use. Main
reference groups:

- **Original hardware:** Commodore's *Programmer's Reference Guide* (especially
  graphics, memory management, joystick interfaces), MOS CPU/CIA/SID manuals.
- **Firsthand hardware research:** Christian Bauer's VIC-II investigation; Linus
  Åkesson's Safe VSP experiments; original Codebase64 tutorials by their authors.
- **Game engineering:** Lasse Öörni's articles, C64 game framework, and player /
  loader documentation. Compare implementations before adopting their constraints.
- **Our tools:** author-maintained ca65/ld65/cc65 guides and the official VICE manual
  and source.

Old tutorials can contain inaccurate constants or unstable sample code. Prefer
the primary hardware/source reference for register semantics, and validate a
borrowed exact-cycle routine on the actual target model.

[prg]: https://www.zimmers.net/anonftp/pub/cbm/c64/manuals/c64-programmers-reference-guide.txt
[prg-port]: https://www.devili.iki.fi/Computers/Commodore/C64/Programmers_Reference/Chapter_5/page_260.html
[prg-banking]: https://www.devili.iki.fi/Computers/Commodore/C64/Programmers_Reference/Chapter_5/page_261.html
[prg-allram]: https://www.devili.iki.fi/Computers/Commodore/C64/Programmers_Reference/Chapter_5/page_265.html
[prg-multicolor]: https://www.devili.iki.fi/Computers/Commodore/C64/Programmers_Reference/Chapter_3/page_115.html
[prg-colors]: https://www.devili.iki.fi/Computers/Commodore/C64/Programmers_Reference/Chapter_3/page_117.html
[prg-ecm]: https://www.devili.iki.fi/Computers/Commodore/C64/Programmers_Reference/Chapter_3/page_120.html
[prg-bitmap]: https://www.devili.iki.fi/Computers/Commodore/C64/Programmers_Reference/Chapter_3/page_127.html
[prg-scroll]: https://www.devili.iki.fi/Computers/Commodore/C64/Programmers_Reference/Chapter_3/page_129.html
[charset]: https://www.pagetable.com/c64ref/charset/
[vic-memory]: https://codebase.c64.org/doku.php?id=base:vicii_memory_organizing
[sprite-intro]: https://codebase.c64.org/doku.php?id=base:spriteintro
[bauer]: https://www.cebix.net/VIC-Article.txt
[safe-vsp]: https://www.linusakesson.net/scene/safevsp/index.php
[mos-cycles]: https://xotmatrix.com/6502/6502-single-cycle-execution.html
[mos-arithmetic]: https://lbaeza.neocities.org/mcs6500/6500_ch02
[mos-flags]: https://lbaeza.neocities.org/mcs6500/6500_ch03
[cia]: https://www.emuverse.ru/downloads/datasheets/peripherals/PIA/6526/mos_6526_cia.pdf
[sid]: https://myoldcomputer.nl/Files/mos_6581_sid.pdf
[kernal-irq]: https://github.com/mist64/cbmsrc/blob/master/KERNAL_C64_03/irqfile
[kernal-editor]: https://github.com/mist64/cbmsrc/blob/master/KERNAL_C64_03/editor.2
[kernal-init]: https://github.com/mist64/cbmsrc/blob/master/KERNAL_C64_03/init
[kernal-serial]: https://github.com/mist64/cbmsrc/blob/master/KERNAL_C64_03/serial4.0
[multiplex]: https://cadaver.github.io/rants/sprite.html
[scroll]: https://cadaver.github.io/rants/scroll.html
[interpolation]: https://cadaver.github.io/rants/interp.html
[interaction]: https://cadaver.github.io/rants/interaction.html
[physics]: https://github.com/cadaver/c64gameframework/blob/master/physics.s
[framework]: https://github.com/cadaver/c64gameframework
[optimize]: https://codebase.c64.org/doku.php?id=base:advanced_optimizing
[tile-compression]: https://cadaver.github.io/rants/tilemap.html
[sprite-cache]: https://cadaver.github.io/rants/sprcache.html
[keyboard]: https://c64os.com/post/howthekeyboardworks
[sf2]: https://github.com/Chordian/sidfactory2
[sf2-sfx]: https://blog.chordian.net/sf2/
[music]: https://cadaver.github.io/rants/music.html
[miniplayer]: https://github.com/cadaver/miniplayer2#how-to-use
[sid-instruments]: https://blog.chordian.net/2022/08/27/composing-in-sid-factory-ii-part-4-instruments/
[goattracker]: https://github.com/leafo/goattracker2/blob/master/readme.txt
[loader]: https://cadaver.github.io/tools.html
[ca65]: https://cc65.github.io/doc/ca65.html
[ld65]: https://cc65.github.io/doc/ld65.html
[cc65]: https://cc65.github.io/doc/cc65.html
[vice-features]: https://vice-emu.sourceforge.io/vice_1.html
[vice-settings]: https://vice-emu.sourceforge.io/vice_6.html
[vice-monitor]: https://vice-emu.sourceforge.io/vice_12.html
[vice-timing]: https://raw.githubusercontent.com/VICE-Team/svn-mirror/main/vice/src/c64/c64.h
[vice-memory]: https://github.com/VICE-Team/svn-mirror/blob/main/vice/src/c64/c64meminit.c#L42
