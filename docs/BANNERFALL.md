# Bannerfall

A local two-player capture-the-flag game for a stock Commodore 64. Cyan and gold
armies compete across a fresh procedural battlefield of forests, desert,
mountains, water, river fords, cities, roads, and bridges.

Bannerfall adapts Atlas's geography into a compact **20 × 10-tile arena**, with
16 × 16-pixel tiles. The entire battlefield is visible to both players. Three
bridge routes offer fast approaches; slower terrain provides alternative paths.
Each generated field is reflected horizontally so the starting geography is
equal for both sides.

## Start and controls

On the title screen, press **K** for a shared keyboard or **J** for two joysticks.
Both players press their fire controls when ready. **F1** generates a new field
on the title or result screen. Release movement and fire controls before
selecting a mode or generating a field.

| Action | Player 1: cyan | Player 2: gold |
|---|---|---|
| Move up | W | U |
| Move left | A | B |
| Move down | S | N |
| Move right | D | M |
| Fire | X | Period (`.`) |
| Joystick | Port 2 | Port 1 |

Movement is cardinal. A new direction changes facing; holding fire repeatedly
shoots in that direction. Each player has one projectile in flight, with a short
cooldown between shots. Mountains stop shots; bullets cross the other terrain.

**Return or RUN/STOP** pauses and resumes keyboard play. In joystick mode,
**RUN/STOP** pauses and resumes. The input modes are selected separately; release
joystick contacts when playing on the shared keyboard.
On macOS VICE's default keyboard mapping, **Escape** represents RUN/STOP.

The second player's unusual movement keys are deliberate. These ten gameplay
switches form a tree in the C64 keyboard matrix, avoiding phantom mapped controls
when only gameplay keys are held. Other simultaneously held keys can introduce
ghost paths, and the host keyboard used with VICE may impose its own rollover
limit. The game polls held switches directly, without KERNAL key-repeat delays.

## Rules

- Take the enemy flag by touching it, then return to your own base to score.
- **Your own flag must be home before you can capture.** A successful capture
  returns the enemy flag to its base.
- **First to three captures wins.** The match clock starts at **2:30**. When it
  expires, the leading player wins; a tie enters sudden death, where the next
  capture wins.
- Each army has **three health points**. A hit briefly stuns the army and gives
  it a short shield, preventing several hits from landing on the same instant.
- **Any hit makes a flag carrier drop the flag**, even when the army survives.
  The opposing army can pick it up again after its shield expires.
- Touch your own dropped flag to return it immediately. Otherwise it returns
  automatically after **three seconds**.
- A defeated army respawns at its base after **0.8 seconds**, with full health
  and a **0.7-second shield**. Shielded armies cannot take enemy flags.
- Carrying a flag slows movement by one pixel per simulation tick, with a
  minimum speed of one. Plan a return route before committing to the steal.

The two armies move and fire before either projectile is evaluated. A shot
survives its owner's defeat, so a simultaneous exchange can hit both players.

### Terrain

| Terrain | Ordinary army speed, pixels per 50 Hz tick | Tactical effect |
|---|---:|---|
| Water | Impassable | Channel movement around lakes and coastlines |
| Plains | 3 | Comfortable movement away from the roads |
| Forest | 2 | Slower alternative approaches |
| Desert | 2 | Slower open ground |
| Mountains | Impassable | Block movement and shots |
| River ford | 1 | Cross away from the predictable bridges |
| City | 3 | Recognizable landmarks and bases |
| Road | 4 | Fast approaches and retreats |
| Bridge | 4 | Fast river crossing |

Movement commits to an adjacent tile and traverses its 16 pixels. The destination
sets the speed for that traversal; a road move cannot jump a blocked tile. The
first movement tick commits the target; held movement commits subsequent targets
as each traversal finishes. There is
no scrolling or zoom during a match.

## Procedural battlefield

The C64 generates the map from a 16-bit seed, using a bounded `$B400` Galois LFSR.
Rounded overlapping features create clusters of terrain on the left half, and
each edit is mirrored to the right half. A fordable central river separates the
bases, with bridges on three rows. Seed-selected bends vary the approaches.

A road spine near each base joins the three routes. Road carving guarantees
connected paths, and clear aprons protect the bases from an unlucky obstacle
placement. Cities mark the bases and outside crossings. Representative water,
mountain, forest, and desert tiles remain at the edges after road carving.

All gameplay geography is generated at runtime. The build generates original
editable graphics with Python's standard library, reusing Atlas's terrain
vocabulary while adding two armies, bullets, flags, and game presentation.

## Audio

The original compact SID score, *Signal and Response*, reserves a voice for each
player's effects. Shots are short pulse notes, impacts use noise, and flag pickup
and return use opposing triangle chimes. The third voice plays sparse background
notes or a capture/victory fanfare. Important feedback takes priority over shot
spam. Pause discards pending effects and immediately silences all three voices.

The driver uses individual pulse, triangle, and noise waveforms, fixed pulse duty,
and master volume 7. It avoids filters, combined waveforms, and digital volume
effects. Separate PAL/NTSC pitch tables accompany the nominal 50 Hz call rate.

## Hardware architecture

The engine targets unexpanded PAL, common NTSC, and early NTSC C64 machines.
Its architecture uses a regional fractional clock for nominal 50 Hz simulation,
with explicit ownership of raster IRQs, input polling, sprite presentation, and
SID updates. Procedural generation runs while gameplay is inactive; the live
match uses bounded actor pools on a static character screen.

The design keeps RAM and I/O visible, installs application-owned IRQ/NMI vectors,
initializes standalone BSS explicitly, and preserves CIA2 serial-bus bits when
selecting the VIC bank. Keyboard scanning drives only selected low output pins;
joystick mode samples both ports before scanning RUN/STOP. Main and interrupt
work use separate state ownership.

| Linker region | Allocation |
|---|---|
| `$0002–$00FF` | Declared zero-page budget |
| `$0100–$01FF` | Application-owned hardware stack |
| `$0200–$07FF` | Explicitly initialized state budget, including the 200-byte map |
| `$0801–$080C` | Standard BASIC `SYS 2061` stub |
| `$080D–$3FFF` | Code budget |
| `$4000–$5FFF` | Read-only tables budget |
| `$6000–$67FF` | Character graphics source |
| `$6800–$6FFF` | Sprite graphics source budget |
| `$8000–$83FF` | VIC character screen and eight sprite pointers |
| `$8800–$8FFF` | Runtime character set |
| `$A000–$A2FF` | Runtime army, outline, flag, and bullet sprites |
| `$D800–$DBE7` | Visible Color RAM |
| `$FFFA/$FFFB`, `$FFFE/$FFFF` | RAM NMI and IRQ vectors |

Collision uses the logical terrain and explicit actor coordinates. Projectile
movement checks every pixel of each six-pixel tick, including tile boundaries.
Full-width horizontal coordinates preserve collision across x255/256. No REU,
accelerator, cartridge, undocumented opcode, VSP, FLI, fastloader, or emulator
service is part of gameplay.

## Build and load

```sh
make duel
make run-duel
make duel-disk
make run-duel-disk
```

Build outputs are `build/bannerfall.prg` and `build/bannerfall.d64`. The release
files are [dist/bannerfall.prg](../dist/bannerfall.prg) and
[dist/bannerfall.d64](../dist/bannerfall.d64).

In VICE's GUI, select the PRG with **File → Smart attach**, load it, and enter
`RUN` at the C64 prompt if it has not started automatically. PRG autostart mode
**Inject into RAM** is convenient for development.

On a physical C64, use ordinary `LOAD"BANNERFALL",8,1` followed by `RUN` from a
supported storage device. The PRG contains all code, tables, and graphics in a
single load. The D64 is a standard 1541 disk image.

## Verification — 2026-10-13

The final PRG is **25,345 bytes**, including its `$0801` load header. SHA-256:

`51385c99973bdd11704ab2cc1743c447ec61f8eae7e3caa9e63c1ee443a6f205`.

VICE 3.10 `x64sc` normally cold-starts the exact release on PAL/6581, common
NTSC/8580, and early NTSC/6581, without a debug PC jump. The standard D64 also
boots on PAL/8580 with 1541 true drive emulation and device-8 loading traps
disabled. The loaded program matches every release byte. Generated map bytes
match the independent reference; all 800 terrain glyph/color quadrants match.
The screenshots are actual VIC output, including hardware sprites.

An independent 77-scenario PAL rules exercise covers both players' terrain
speeds and carrier penalties, movement bounds, x255/256 crossings, bullet
substeps/range, walls, shields, simultaneous knockouts, exact respawn/drop
timers, flag returns, capture restrictions, both third-capture wins, timeout,
sudden death, readiness, pause, rematch, and mode selection. A separate complete
raid steals a flag and returns it through ordinary interpolated movement,
without repositioning either army.

All three models also pass 170-frame timing exercises with both armies moving,
both bullets active, all eight sprites, SID events, HUD updates, and match
transitions. Measurements include VIC DMA:

| Model | Heavy live IRQ, cycles | Largest measured transition IRQ | Frame budget |
|---|---:|---:|---:|
| PAL | 9,020 | 11,194 | 19,656 |
| Common NTSC | 8,843 | 11,113 | 17,095 |
| Early NTSC | 8,876 | 11,173 | 16,768 |

Sprite publication finishes by raster **37**, before the earliest carried flag
at raster **60**. Fractional cadence agrees with the regional 50 Hz accumulator
within one tick of rounding. F1 regeneration returns to a new title field with
both players unready. Code occupies `$080D–$1CB3`; BSS uses 371 bytes and declared
zero page uses eight bytes. Main generation/paint runs under SEI with the display
off; it never races live state.

Gameplay exercises substitute normalized control bytes **after** CIA polling.
Bounded rule and timing scenarios also reposition declared actors/clock/terrain
state. These checks do not prove physical joystick contacts or host keyboard
rollover. The source CIA path is separately audited, and an electrical graph
model passes all 1,024 gameplay keyboard combinations, 4,096 combinations with
Return/RUN/STOP, and 2,048 two-joystick/RUN/STOP combinations. Additional menu
keys are gated while gameplay controls are held. No synthetic macOS key input
was available without Accessibility permission.

The arena reference passes 1,003 seed samples with all nine terrains, exact
reflection, connected bases, and three connected bridge routes. Local reports,
actual captures, and linker output are kept under `build/duel/`.

**A physical C64 run remains pending until hardware is available.**

Source references and development guidance are collected in
[TIPS_AND_TRICKS.md](../TIPS_AND_TRICKS.md).
