# Borrowed Motion

A single-player puzzle game for an unexpanded Commodore 64. You are the keeper
of a celestial archive where movement can be borrowed, stored, and given away.
Recover the motion of brass bells, lend it to luminous pearls, and bring every
pearl to rest in a golden nest.

The ten rooms form a complete campaign. There is no deadline: the world advances
only when you wind it. Take as long as you like to inspect a room and plan the
next exchange.

![Borrowed Motion opening screen in VICE](borrowed-motion-title.png)

## Play

Select an artifact with **A/D**. Your pocket holds one movement (direction
and speed), and **Space** trades its contents with the selected artifact.

- An **empty pocket** takes an artifact's motion and leaves it still.
- A **full pocket** gives its motion to the artifact and receives the artifact's
  previous motion. It only stops the artifact if the pocket was empty.
- **Tap W** to advance one complete beat. **Hold W** to keep winding. All moving
  artifacts advance together; release the key to stop after the current beat.
- A pearl settles when it is **still on an unused golden nest**. Passing over
  a nest is not enough. Take its motion back when it arrives.

In the first room, take the bell's eastward motion, select the pearl, and lend it
that motion. Wind five beats to reach the nest, then take the motion back. The
empty cradle blossoms when the pearl settles. Later rooms ask you to find useful
places for displaced motion and change a journey partway through.

Bells can store motion throughout a room. A settled pearl cannot be selected
again. Artifacts pass through one another, and all nests accept any pearl.
Selection works across the whole room, including separate display areas.

![Pass It On, the fifth room, rendered in VICE](borrowed-motion.png)

## Controls

Use the keyboard, a joystick in **port 2**, or both. A/D and joystick left/right
cycle through artifacts; they do not steer an artifact directly.

| Action | Keyboard | Joystick port 2 |
|---|---|---|
| Select previous / next artifact | A / D | Left / right |
| Exchange selected artifact's motion | Space | Fire |
| Wind one beat / keep winding | Tap / hold W | Tap / hold up |
| Undo | S | Down |
| Start or continue to the next room | Return or Space | Fire |
| Restart the current room | R | Use keyboard |
| Open help | H | Use keyboard |
| Toggle sound | M | Use keyboard |
| Return to the title | RUN/STOP; normally Escape in macOS VICE | Use keyboard |

Release gameplay controls before using R, H, M, Return, or RUN/STOP. The input
scanner requires this to avoid ambiguous combinations on the C64 keyboard.

Undo remembers the last **32 exchanges and winding beats** in the current room;
hold S/down to undo repeatedly. You can undo the final exchange after a room
is complete. Starting the next room or restarting clears that room's undo
history. Restarting is always available if you want a fresh attempt.

On the title screen, A/D or left/right chooses an unlocked room. Completed rooms
remain available during the current session. Progress is held in RAM and is
lost when you reset or close the emulator; the game does not write a save file.

## Reading the room

**Cyan pearls** belong in nests. **Brass bells** supply or hold motion. White
corner brackets identify the selected artifact. The HUD shows the motion in
your **POCKET**, the selected artifact and its motion, and how many pearls
**REST**. **SWAPS** counts exchanges; winding does not increase that count.

Each artifact has a direction marker. A **2 beside a HUD arrow** identifies
fast motion. The **purple ghost** predicts the selected artifact's position
after the next complete beat, including reflections, mirrors, and slowing glass.
It is a preview, not another artifact or a destination to collect.

| Object or surface | Effect |
|---|---|
| Ordinary motion | Attempts one tile per beat |
| Fast motion | Attempts two consecutive steps per beat |
| Wall or room edge | Reverses direction; that attempted step is used without entering the wall |
| Slash or backslash mirror | Turns motion on entry; preserves speed |
| Hourglass-shaped soft glass | Reduces fast motion to ordinary speed and ends the current beat there |
| Empty golden nest | Accepts a stationary pearl |
| Filled star-shaped nest | Already restored; remains passable |

Fast motion completes both steps before another exchange. A wall reversal can
therefore be followed by a step in the opposite direction during the same beat.
Use the ghost to inspect the result before winding. You can stop and think
between beats without losing anything.

## The ten rooms

| Room | Name | Main idea |
|---|---|---|
| 1 | The First Loan | Take, lend, wind, and recover motion |
| 2 | A Change of Heart | Exchange with a full pocket |
| 3 | The Patient Wall | Find a useful reflection |
| 4 | An Unexpected Turn | Turn a journey with a mirror |
| 5 | Pass It On | Reuse motion after a delivery |
| 6 | A Place for Everything | Store displaced motion |
| 7 | Long Strides | Work with fast motion |
| 8 | The Soft Glass | Slow a journey |
| 9 | The Quiet Exchange | Change a journey partway through |
| 10 | Borrowed Tomorrow | Coordinate different journeys and arrival times |

Any sequence that restores every pearl completes the room. There is no required
command sequence, hidden timer, or penalty for taking an alternative route.

## Download and build

The release includes a PRG and a standard 1541 disk image:

- [Borrowed Motion PRG](../dist/borrowed-motion.prg)
- [Borrowed Motion D64](../dist/borrowed-motion.d64)

Build with Python 3 and cc65's `ca65`/`ld65`; VICE supplies `x64sc` and `c1541`:

```sh
make motion
make motion-disk
make run-motion
make run-motion-disk
```

The PRG launcher uses direct RAM autostart. The disk launcher uses true 1541
emulation with device-8 loading traps disabled. The disk's program name is
`borrowed-motion`. On a physical C64, transfer the PRG to compatible storage or
write the D64 to a disk, then enter:

```text
LOAD"BORROWED-MOTION",8,1
RUN
```

Game code is in [`src/motion/`](../src/motion/). Original character and sprite
art comes from [`generate_motion_assets.py`](../tools/generate_motion_assets.py).
The editable rooms and independent rules model are in
[`generate_motion_levels.py`](../tools/generate_motion_levels.py). Both generators
use Python's standard library and preserve reproducible source assets. Detailed
room rationale and reference solutions are in
[the level design notes](MOTION_LEVEL_DESIGN.md).

## Hardware and verification

The game targets a stock C64 with ordinary hires character graphics, eight
hardware sprites, and SID sound. It detects PAL, common NTSC, and old NTSC and
normalizes gameplay timing. The board fits on one screen; no memory expansion
or cartridge is required.

VICE checks of the original release, commit **`18b6a3f`**, covered **PAL
with a 6581**, **NTSC with an 8580**, and **old NTSC with a 6581**. Each
configuration completed all ten authored solutions, undo
checks, and 60 movement-rule cases. Regional pacing was checked explicitly on
NTSC and old NTSC. These checks establish agreement with the independent rules
model and the tested emulator configurations. The later pocket terminology
update is a rebuild without repeating those emulator checks.

That release's D64 was also launched from a fresh PAL/6581 VICE instance with
true 1541 emulation and device-8 loading traps disabled. It loaded successfully
to the game's title screen. Its distributed PRG was byte-for-byte identical to
the build used for the three regional gameplay checks.

The gameplay checks injected normalized controls into the compiled input path;
they did not exercise a physical keyboard or joystick. A native macOS
accessibility timeout prevented the planned keyboard check. Screenshots were
inspected in VICE, but audible playback and a physical C64 run have not been
verified. Human play is still needed to assess understanding, enjoyment, and
puzzle difficulty.
