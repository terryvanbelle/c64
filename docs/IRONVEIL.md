# Ironveil

A deliberate tank duel for an unexpanded Commodore 64. Hunt through an
asymmetric procedural battlefield, use vegetation to disappear, turn the hull
to protect your armor, and aim the turret independently. Play two people locally
or choose a computer opponent. Bannerfall, Atlas, and Nocturne remain separate
projects.

![Ironveil opening screen in VICE](ironveil-title.png)

![Ironveil rendered by VICE](ironveil.png)

## Play

Destroy the opposing tank three times to win. A match lasts **three minutes**;
the higher knockout score wins at the deadline. A tie enters sudden death.
Simultaneous knockouts count for both players, including shells already in
flight when their owner is destroyed.

Each tank has **four armor points**. Front and side hits remove one point;
rear hits remove two. The eight-way hull determines armor orientation. A hit
briefly stuns the tank and grants a short damage shield. A knockout respawns the
tank after 1.5 seconds, with 1.2 seconds of spawn protection. Shooting reveals
the tank for one second, so firing from cover gives away its position.

Hull and turret turn separately. Joystick controls allow reversing while
keeping frontal armor and the gun pointed toward the opponent. Keyboard
movement turns the hull toward the chosen map direction; the turret remains
independent. One shell per player can be active; the normal firing cooldown is
half a second. Mountains stop shells, while water and vegetation allow shots
to pass.

## Controls

The original multicolor bitmap opening screen contains all configuration,
control help, and readiness prompts. Selected settings are highlighted in gold.
The same artwork returns after a match, with the winner and rematch prompt.
Gameplay keeps one compact status row above the map views.

Choose **K** for a shared keyboard or **J** for two joysticks on the title or
result screen. **H** selects two humans; **C** selects the computer. Keys
**1 / 2 / 3** select **Easy / Medium / Hard** and enable the computer opponent.
Medium is the initial computer difficulty. Opponent, difficulty, and input
choices persist across rematches and new maps.

Both human players trigger fire to ready: on joysticks, press **and release**
the button. In computer mode, player 1 readies the
match and the computer is ready automatically. Release gameplay controls before
changing menu settings. **F1** generates a new battlefield from setup. During a
match, pause first, release gameplay controls, then press **F1** to return to
setup with a new map.

The opening screen reports which player still needs to ready.

### Shared keyboard

| Action | Player 1, cyan | Player 2, gold |
|---|---|---|
| Move north / south | W / S | U / N |
| Move west / east | A / D | B / M |
| Turn turret left / right | Q / 2 | Semicolon / Return |
| Fire | X | Period |
| Pause / resume | 1 | 1 |

Return turns player 2's turret during keyboard play; **1** pauses the match.
Hold the movement keys to turn the hull along the shortest path toward the
requested map direction, then drive forward once aligned. Hull turning keeps
its normal ten-tick gate; keyboard movement does not bypass terrain or collision
rules. Two axes select a diagonal, such as **W+D** or **U+M** for northeast.
Opposing directions cancel independently on each axis.

The keyboard layout is intended for VICE's default symbolic mapping and the
corresponding physical C64 keys.

### Joysticks

Player 1 uses **port 2**; player 2 uses **port 1**. Joystick movement remains
relative to the hull.

- Button released: up/down drive forward/reverse; left/right turn the hull.
- Hold the button: left/right aim the turret; the tank holds position.
- Release the button: fire one shell.
- **RUN/STOP** pauses or resumes; macOS VICE normally maps it to Escape.

## Views, camouflage, and sensors

In human-versus-human play, each half of the screen follows its own tank through
a **9 × 12 tile**, 144 × 192 pixel view. The battlefield is **32 × 16 tiles**,
or **512 × 256 pixels**, so opponents can maneuver beyond each other's view.

Visibility depends on the target's terrain and an unobstructed mountain line
of sight. Grass permits sightings up to 160 pixels, desert 112, reeds 64, and
forest 48, measured along the larger coordinate difference. Roads, bridges,
and a tank's shooting reveal bypass the cover range, but do not bypass the
view boundary or mountains.

Sensors provide an eight-way bearing, a near/mid/far range band, and a rough
**64 × 64 pixel sector** once per second. A hidden contact is represented by
that sector's center, rather than its exact location. When a visible tank
disappears, its exact contact is immediately replaced by the cached coarse
contact. Respawning tanks provide no contact.

A **yellow diamond** marks the reported sector centre when it is inside the
view. Otherwise a **yellow edge arrow** points along the reported eight-way
bearing. Both use the once-per-second sensor report, so the marker gives an
approximate search area rather than a concealed tank's exact coordinates.
No marker appears while the contact is unavailable. Terrain underneath a
marker retains its normal movement rules.

Against the computer, the right pane is a **contact map based on the human's
coarse sensor sector**, rather than a camera following the computer. The
computer's tank appears there only when the human's visibility rules reveal it;
its exact armor value is concealed until spotted. This keeps forest and
reed camouflage useful without giving the human a second view that tracks a
hidden opponent.
The solo right pane's marker also uses the human's reported contact, preserving
that same approximation.

### HUD legend

Each pane has a twenty-character status strip. Read it from left to right:

| Field | Meaning |
|---|---|
| **C / G** | Cyan / gold team |
| Four **\*** or **−** slots | Remaining / lost armor points |
| Score digit | Knockouts scored |
| **N, NE, E, SE, S, SW, W, NW** | Enemy compass bearing |
| **A–H / 1–4** | Coarse horizontal / vertical enemy sector |
| **N / M / F** | Near ≤96, mid ≤224, far >224 pixels |
| **O / H / !** | Open road or bridge / currently hidden / spotted on other terrain |
| **m:ss / PAUS / OT!!** | Time remaining / paused / sudden death |

Open terrain has no camouflage, even outside the opponent's current view or
behind a mountain. In solo play, the gold strip uses the human's sensor contact:
its armor slots and contact indicator are **?** while the computer is unspotted;
**!** marks a visual contact. Its knockout score remains visible.

## Deliberate movement

Simulation runs at a nominal **50 Hz** on PAL and both supported NTSC variants.
These speeds apply equally to humans and the computer, in forward and reverse:

| Terrain | Pixels per tick | Pixels per second |
|---|---:|---:|
| Road / bridge | 1 | 50 |
| Grass | 0.5 | 25 |
| Desert | 0.375 | 18.75 |
| Forest / reeds / ford | 0.25 | 12.5 |
| Water / mountain | Blocked | — |

Diagonal movement uses a normalized fixed-point speed, keeping its travel rate
close to the corresponding cardinal rate. Each 45-degree hull turn takes at
least ten ticks, or 0.2 seconds; a turret turn takes eight ticks, or 0.16 seconds.
Four body probes enforce terrain collision. Both tanks propose their movement
before either commits, so body collision rejects conflicting moves symmetrically.

## Engine sound and hearing

The original SID driver gives cyan and gold distinct low pulse engines, tuned
to A1 and D2 with 50% and 37.5% pulse widths. Actual translation, including
subpixel movement, or a hull turn powers the engine. Parked tanks, blocked
throttle, turret-only aiming, and respawn teleports remain quiet. Pause and
setup silence the voices. There is no ambient music.

In solo play, cyan's own engine stays at a modest level. The moving computer's
engine is strongest within 96 pixels, softer through 160 and 224 pixels, and
inaudible beyond 224. Distance uses the larger coordinate difference. In two
player mode, both engines follow the same proximity curve on the shared SID,
with a faint level at long distance so your own movement remains audible.
Engine sound supplies a rough hearing cue even when terrain conceals a moving
opponent; stopping in cover can hide both its image and its engine sound.

Each tank's cannon briefly borrows its engine voice. The third voice supplies
finite armor-impact, knockout, and victory effects. Engine volume changes
release the SID gate before retriggering; pitches are corrected independently
for PAL and NTSC clocks. The driver uses pulse and noise waveforms with fixed
master volume, without filter tricks or volume digis.

## Geography

The C64 generates the entire logical map from a 16-bit seed. Rounded, overlapping
features create ponds, mountain outcrops, forests, and desert pockets. The map is
asymmetric; its two sides are generated independently.

A central water channel has fast bridge crossings at rows 3, 8, and 12, plus
slower fords at rows 5, 10, and 14. Reed banks connect the fords to the bridge
approaches and provide concealed flanking routes. Independently bent roads join
the crossings through vertical road spines to clear **3 × 3 spawn aprons** at
tiles **(1,1)** and **(30,14)**. Initial and respawn top-left pixels are
**(16,16)** and **(480,224)**; hulls initially face southeast and northwest.
Every generated map contains all eight terrain types and a connected route
between the spawns.

Eighteen additional rounded 5 × 5 woodland regions preserve existing ponds and
mountains. Roads, crossings, and spawn aprons are carved afterward. Across the
audited seeds, forest covers **30.46%** of the map on average, up from **6.56%**
in the earlier generator; observed coverage ranges from **20.51% to 38.67%**.

A temporary independent integer model checked **1,003 seed samples**: all eight
terrains, clear spawn aprons, connected spawns, all three bridges, and all three
fords passed. No fully mirrored layouts occurred. The actual ca65 generator
also produced byte-for-byte identical maps for all 1,003 seeds in temporary
sim65 runs. These generation checks do not measure video or IRQ timing.

## Computer opponent

The computer sends the same throttle, hull, turret, and fire inputs as a human.
It receives the same visibility and coarse sensor contacts, and never reads the
hidden human's exact coordinates. It has no movement, armor, damage, shield,
cooldown, or collision advantages.

Easy approaches the sensed contact. Medium seeks a side approach. Hard seeks
a rear approach using the **visible** opponent's observed hull orientation.
Hidden contacts cause a search around the coarse sector. A visible opponent's
occupied cells are private planning obstacles, helping flank routes pass around
the tank. They do not modify the battlefield or the physical collision rules.
Short terrain checks select a nearby rear angle or the other side when a
mountain blocks the intended firing approach. If every preferred approach
leaves the map or hits a mountain, the CPU approaches from the map interior.
Visible flank goals keep a cardinal or diagonal firing lane during terrain
sanitation. Failed fresh steering retries leave enough time for the flood
planner to progress, including near corners. A close contact also makes the
computer back away, allowing tanks overlapping after respawn to separate.

| Behavior | Easy | Medium | Hard |
|---|---:|---:|---:|
| Maximum cells per flood-planning tick | 1 | 1 | 1 |
| Earliest moving-goal refresh | 64 ticks | 40 ticks | 24 ticks |
| Earliest navigation decision interval | 8 ticks | 4 ticks | 1 tick |
| Minimum intended firing reaction | 16 ticks | 8 ticks | Immediate |
| Minimum intended shot spacing | 48 ticks | 24 ticks | Normal game limits |
| Intended firing range per axis | 96 pixels | 144 pixels | 180 pixels |

Planning uses word-sized indices and distances for all 512 cells. Each cell is
enqueued at most once per generation. Initialization clears eight visit stamps
per tick; large work arrays are not cleared during a match-start IRQ. The
computer can make legal direct approaches while its reverse flood field spreads.
Goal sanitation checks at most four nearby candidates per tick, and a fresh
flank-ray test defers those probes until the following tick. Ticks that search
a goal neighborhood or initialize visit stamps reserve the expensive work for
that tick. Other ticks choose one operation: a new navigation decision, an
exact firing-alignment calculation, or one flood cell. Failed waypoint and
firing-angle attempts leave planning ticks available.

Committed movement, waypoint arrival checks, and coarse turret tracking
continue every tick. Reaction counters run at the nominal 50 Hz, making Easy
and Medium's base delays 0.32 and 0.16 seconds. Every fifth tick publishes the
dynamic HUD and defers new navigation, firing calculations, and flood work.
The once-per-second sensor ping also reserves its tick for sensing, while
committed movement and the normal reaction counters continue. The AI reads
only the sensor's public countdown to schedule this work. This bounded schedule
reserves time for the tighter NTSC frame budget; stronger
levels retain faster reactions, navigation decisions, goal refreshes, and
their flanking choices. Work scheduling and the normal shell, cooldown, and
stun restrictions can delay an intended shot further.

## Build, run, and transfer

Install `cc65`, Python 3, and VICE, then run:

```sh
make tanks            # build/ironveil.prg
make run-tanks
make tanks-disk       # build/ironveil.d64
make run-tanks-disk
```

Prebuilt downloads: [PRG](../dist/ironveil.prg) ·
[1541 disk image](../dist/ironveil.d64).

For VICE without Terminal, open VICE and use its smart-attach/autostart file
dialog to select `ironveil.prg`. Direct RAM injection is useful for development.
The disk launcher instead enables true 1541 emulation and disables device-8
loading traps.

On a physical C64, transfer the PRG using supported storage, or write the disk
image to a 1541 disk, then enter:

```basic
LOAD"IRONVEIL",8,1
RUN
```

## Implementation and stock-hardware target

| Resource | Location / allocation |
|---|---|
| BASIC startup / code | PRG begins at $0801; SYS 2061 enters $080D |
| Tables and packed title | $4800–$5FFF, constrained by the linker |
| Font / sprite source data | $6000 / $6800 |
| Two screen buffers | $8000 and $8400, 1 KB each |
| Multicolor character set | $8800–$8FFF, 2 KB |
| Tank orientations / shell sprite | $A000–$B0FF, 4,352 bytes |
| World and planning work | $B100–$CFFF; no initialized PRG payload |
| Scalar state | $0200–$07FF, bounded by the linker |

During setup, a native multicolor bitmap occupies $A000–$BF3F with screen
attributes at $8000 and Color RAM at $D800. Its lifetime shares the later tank
sprite and world-work storage. Starting a match restores the gameplay assets
and generates the world before enabling play; returning to setup restores the
bitmap. The original editable title generator packs its 10,000 bitmap,
screen-attribute, and Color RAM bytes into 3,666 count/value RLE bytes. Its
fixed lower menu area uses black, gray, white, and gold, leaving configuration
text editable at runtime.

The original deterministic asset generator produces eight hull headings × eight
turret headings, plus terrain glyphs and the shell sprite. A fixed terrain
palette permits screen-buffer swaps without a full Color RAM copy in the IRQ.
The main loop expands the world into a 64 × 32 character map once, then draws
camera views. The IRQ owns simulation, input, sensors, SID updates, and sprite
publication. Completed views are published coherently; heavy rendering can
retain the previous view rather than exposing a half-drawn screen.
Each gameplay screen has one compact HUD row, 24 terrain rows, narrow outer
frames, and a two-character divider. No control instructions occupy the live
map area. The map columns are 1–18 and 21–38; columns 19–20 form the divider.
The main renderer overlays the yellow sensor marker in the inactive screen
using a coherent snapshot of the reported sector and bearing before publishing
the view. It does not read hidden enemy pixel positions for that marker.
In solo mode, the right view's origin is `(4×sectorX−2, 4×sectorY−4)`, clamped
to columns 0–23 and rows 0–4, using zero-based coarse-sector indices.

The engine owns RAM IRQ/NMI vectors, masks unwanted CIA sources, initializes
banking and video registers, and uses documented NMOS 6502 instructions. PAL,
common NTSC, and early NTSC have separate pacing paths. SID pitch and simulation
cadence are corrected independently. No cartridge, REU, SuperCPU, disk streaming,
or emulator-only instruction is required.

## Verification status

The released PRG's SHA-256 starts with `0aadca83`. These checks use the updated
corner starts, larger forests, map-relative keyboard controls, and yellow markers.

- The independent generation audit checked **1,003 seeds**, with all terrain,
  base/apron, bridge, and ford connectivity checks passing. The actual compiled
  generator matched every model map byte for byte.
- Compiled keyboard checks passed **4,096 direction/hull/turret/fire cases** and
  **768 canceled-chord guard checks**, preserving menu state and the input ABI.
  The unchanged fifteen-switch gameplay/pause matrix passed all **32,768**
  combinations in an independent electrical-switch model, without ghosting.
- **191 compiled physics assertions** passed, including the new initial and
  respawn positions. The unchanged sensor and SID modules retain their prior
  **770 sensor/camera** and **38 SID-driver** passing assertions. SID-driver
  checks observe writes in flat RAM; they do not simulate electrical SID behavior.
- **318 complete compiled CPU matches** across 106 seeds and all difficulties
  ended in natural 3–0 computer wins, in **27.94–48.72 simulated seconds**.
  All **54 moving-input scenarios** completed, including 106 human and 10 CPU
  respawns, without a 300-tick terrain-throttle stall. The longest concealed
  pursuit ended naturally in overtime at 320.26 seconds. These runs use a sound
  stub and exclude CIA input, rendering, and IRQ timing.
- **46 prepared marker/render fixtures** checked **44,160 map, divider, and
  Color RAM cells** across all bearings, sector positions, unavailable contacts,
  and solo/PvP views. Rendering changed only the inactive screen before
  publication. Actual VIC output matched **61,440 gameplay pixels**, including
  the markers and active sprites, with zero differences.

Busy-frame VICE timing uses eleven-cell sensor rays, bounded AI planning,
moving tanks, two shells, new SID notes, screen publication, and all eight
sprites at the earliest map Y coordinate. The allowance adds **419 cycles**:
29 for interrupt entry/return, 160 for the main-loop camera/contact snapshot,
and 230 for held-key decoding and keyboard direction conversion.

| Video region | Cycles per frame | Largest measured IRQ | With allowances | Remaining cycles |
|---|---:|---:|---:|---:|
| PAL | 19,656 | 15,930 | 16,349 | 3,307 |
| Common NTSC | 17,095 | 15,928 | 16,347 | 748 |
| Early NTSC | 16,768 | 15,927 | 16,346 | 422 |

Each regional run checks 120 prepared frames. Active gameplay left no pending
raster interrupt, and sprite publication completed by line 48, before the
earliest sprite at line 58. Fractional pacing produced exactly the expected
50 Hz simulation ticks. Both corner approach fallbacks and firing-lane
acceptance/rejection passed. Bitmap/loading transitions disable sprites and
mask interrupts while restoring shared memory; their delayed interrupts are
recorded separately from live gameplay deadlines. These are measured stress
cases with conservative allowances, not an exhaustive proof of every state.

The release PRG completed uninterrupted VICE matches against a stationary
human on Easy, Medium, and Hard in **36, 35, and 32 seconds**, respectively;
each ended in a natural 3–0 computer win. Only setup/start controls were
injected; tank coordinates and the program counter were not changed. Host
emulation speed was accelerated for these runs, then restored to 100%.

The distributed D64 was cold-booted with true 1541 emulation and device-8 traps
disabled on PAL/8580. Its extracted PRG matches the distributed PRG byte for
byte, and the entire loaded program image matches before the first match.

VICE control checks inject normalized inputs after the actual CIA poll, and
compiled keyboard checks exercise the conversion code. Neither establishes
Mac keyboard rollover or constitutes a physical C64 keyboard test.
**A physical C64 has not been used for this project.**
