# Borrowed Motion level design

Borrowed Motion asks the player to treat movement as an object: take it, lend
it, exchange it, and recover it after a journey. The original ten rooms form
the introductory course. The expanded campaign has 64 rooms, adding six
nine-room chapters about preparation, movement conversion and economical
relays. The first ten layouts and reference solutions are unchanged.

The game gives the player control of time. Tap W for one step; hold W to keep
stepping. Each complete step advances all objects together according to their
movement; fast motion can cover two tiles in that step. Releasing the step
control leaves a stable situation to inspect. Interesting decisions should
concern whose movement is useful next, not the speed at which the player can
change selection.

These are original authored rooms for this repository. The reference model
establishes their mechanical solvability. Human play is still needed to judge
clarity, enjoyment, and the appropriate difficulty.

## Rules that the rooms rely on

The board is 18 by 9 tiles. There are at most six artifacts. A pearl can settle
into a nest; a brass bell provides a place to obtain or store movement. Artifacts
pass through one another, including through a pearl that has already settled.
Selection and exchanges work across the entire room.

The pocket begins empty. Exchanging with a selected artifact swaps its complete
movement with the pocket. An empty pocket therefore stops a moving artifact. A
full pocket changes that artifact's movement and acquires its previous movement.
Exchanges happen while the world is stopped.

A stationary pearl on an unused nest immediately settles. Moving across a nest
does not deliver a pearl: the player must stop it there. Settled pearls cannot
be selected or used as storage. Nests accept any pearl, and a used nest remains
passable. When two stationary pearls share an unused nest, the earlier actor
index settles first; the other pearl remains active.

A normal movement travels one tile per step. A fast movement attempts two
consecutive microsteps. Hitting a wall or the edge reverses direction and uses
that microstep without entering the wall. The remaining microstep of a fast
step still occurs. A slash or backslash changes direction on entry, preserving
speed. Entering soft glass immediately reduces a fast movement to normal speed
and ends any remaining microsteps of that step.

| Tile | Entering east | Entering south | Entering west | Entering north |
|---|---|---|---|---|
| Slash `/` | North | West | South | East |
| Backslash `\` | South | East | North | West |

Settlement is checked after every exchange and after each complete step. The
model does not settle a pearl during the middle of a fast step. The renderer
shows the two microsteps separately, including turns and wall reversals.

### A useful conservation rule

Exchanges, reflections, and mirrors preserve the number of nonempty movements.
Soft glass changes speed but also preserves that count. Settling removes a
stationary pearl and therefore removes no movement.

A finished room can store movement only in its bells and the pocket. Therefore,
with one bell, a solvable room must begin with at most two nonempty movements.
The generator checks this necessary condition. It also checks conservation
after every exchange and every step of every reference solution. This condition
alone does not prove a room is solvable; the complete solution replay does that.

## Why the expansion limits exchanges

The first player completed the original campaign and found it pleasant but
too easy. Adding artifacts alone would not address that feedback. The storage
invariant guarantees that the bells and pocket can hold all motion while every
pearl is stationary. With unlimited exchanges, the player can usually turn
apparently simultaneous work into independent deliveries.

Rooms 11–64 therefore have an exchange allowance in Challenge. Selection and
steps remain free; there is still no real-time pressure. Undo refunds exchanges,
and the larger history retains 64 actions. Running out leaves the position
intact and offers undo/restart. Practice removes every allowance, and every room
can be selected after a cold start.

Each allowance is derived from its authored, replayable solution. Rooms 11–19
include one spare exchange; later rooms use that solution's count. These are
achievable limits, not proven minimums or prescribed command sequences.

The design review specifically rejects three misleading difficulty signals:

- **Long travel** costs no extra exchanges, so a long corridor is not a harder
  plan by itself.
- **Opposite directions** can usually be obtained with a free wall bounce.
  Exporting north and south separately is not necessarily a dependency.
- **Losing fast motion** is not inherently a sacrifice. Ordinary motion offers
  more stopping positions on the same path. Glass must contribute to a useful
  route or a schedule, rather than merely look consequential.

The useful pressures are changing an axis at an unmarked junction, preparing
positions before a converter is settled, sharing a recovered heading, and
avoiding storage exchanges when several journeys can cooperate. The allowance
should make an efficient plan preferable to an obvious sequential alternative.
Human difficulty can vary within a chapter; neither a longer witness nor a
larger search space establishes that a room is more enjoyable or harder.

The first ten lessons remain unrestricted, so the new constraint does not alter
their teaching. Room 11 explicitly introduces the allowance. The title shows it
before play, and the room HUD displays used/available exchanges continuously.

## The original ten rooms

“Study target” means the exchange count of the checked authored solution. It is
not a claim that the count is optimal. Taking fewer exchanges is welcome.
Steps do not increase this count.

| Room | New relationship | Study target | Reference steps |
|---|---|---:|---:|
| 1 The First Loan | Take a bell's motion, lend it, and recover it to settle | 3 | 5 |
| 2 A Change of Heart | A full pocket exchanges motion; an empty pocket brakes | 4 | 2 |
| 3 The Patient Wall | A wall can make a useful reverse movement | 3 | 16 |
| 4 An Unexpected Turn | A mirror converts a horizontal loan into a vertical one | 3 | 13 |
| 5 Pass It On | One pearl's arrival provides the next pearl's movement | 5 | 17 |
| 6 A Place for Everything | Use a bell as storage while exchanging moving directions | 6 | 11 |
| 7 Long Strides | Fast movement covers two tiles before the next decision | 3 | 5 |
| 8 The Soft Glass | Terrain can turn a fast loan into a precise one | 3 | 5 |
| 9 The Quiet Exchange | Borrow a turn halfway through a journey | 8 | 10 |
| 10 Borrowed Tomorrow | Combine a halfway exchange, different speeds, and different arrival times | 6 | 9 |

### The First Loan

A stationary pearl and an eastbound bell share a broad horizontal room. The
nest lies five tiles east of the pearl. The player needs only one direction,
one destination, and three exchanges. The final exchange is a meaningful part
of delivery: arriving with movement and settling without it are visibly
different states.

The intended first discovery is that the bell can stop while the pearl begins
moving. The intended second discovery is that the same movement can be recovered
at the nest. The hint gives the order of actions without introducing new terms.

### A Change of Heart

The pearl already moves east, but its nest is north. The bell holds northward
movement. Swapping the bell into the pocket and then exchanging with the pearl
provides the needed heading, but leaves eastward movement in the pocket. Parking
that movement in the bell empties the pocket so it can brake the arriving pearl.

This is the first room where pressing exchange does not necessarily mean stop.
The pocket's current arrow must remain conspicuous. The lesson is useful before
adding more objects or geometry.

### The Patient Wall

The nest is west of the pearl, while the available movement heads east. The
right wall provides the reverse heading. The player may send the pearl to the
wall or wait for a suitable direction in the donor before borrowing it.

The route includes a short interval of predictable stepping. Holding the step
control is appropriate here; the room should not demand sixteen separate key
presses. It teaches a transformation that can later rescue an imperfect plan.

### An Unexpected Turn

The pearl's route crosses a slash mirror that turns eastward movement north.
The bell is in a separate display area. This emphasizes that the exchange is
between selected objects anywhere on the board; the player is not transporting
a cursor-bound item through walkable corridors.

This room deliberately has disconnected floor areas. There is no player avatar
that must traverse them, and the bell is accessible through selection. The
pearl's entire intended route is connected. The other introductory rooms have connected
floor regions.

### Pass It On

There are two stationary pearls and one eastward movement. A backslash turns
the first pearl south into a nest. Braking it yields the southward movement
needed by the second pearl. The first delivery therefore changes the useful
options for the next decision.

This is the first room intended to feel like a chain reaction planned by the
player. The camera can remain static and both destinations remain visible.

### A Place for Everything

Both pearls begin with movement, while the bell is empty. The player exchanges
their directions and uses the bell to hold the displaced eastward movement.
The first arrival yields southward movement, which carries the second pearl
through a slash mirror toward its nest.

The room applies the storage lesson to two deliveries. Its geometry adds a
reason to care about the direction recovered at an arrival. It should not be
explained as a separate inventory system; the bell simply follows the same
exchange rule as the pearls.

### Long Strides

The game returns to one pearl and one bell to teach fast movement without
competing demands. A double eastward arrow covers ten tiles in five steps. The
nest is on that straightforward sequence of stopping positions.

The initial fast lesson avoids a skipped destination, a bounce, or a mirror.
Those interactions can be explored after the difference between a tile move
and a complete step is apparent.

### The Soft Glass

The nest is an odd number of tiles away from the pearl. The eastward loan begins
fast, but a clearly drawn glass tile on the route reduces it to ordinary speed.
The pearl can then stop precisely at its destination.

The glass sits on every direct horizontal approach from the starting position.
The authored route encounters it on the first microstep of a step, exercising
the immediate slowing rule. The source bell's separate lane contains no glass.

### The Quiet Exchange

Three north-facing branches connect to a horizontal corridor. One pearl begins
travelling north toward a nest. Another begins stationary to the west of its
own branch. The player borrows eastward movement from the bell to bring that
pearl to the junction.

After four steps, the first pearl is on its nest while the second is at the
junction. Braking the arrival supplies the northward movement needed to turn
the other pearl. That exchange puts eastward movement into the pocket, so the
bell is useful again as storage. After the second delivery, the same northward
movement can serve the third pearl.

The critical insight is that an artifact's movement can be replaced anywhere
along its route. No mirror creates the necessary turn at the junction. A player
who treats every loan as an uninterrupted trip must revise that model.

### Borrowed Tomorrow

A slow northbound pearl approaches a horizontal route while a fast eastbound
pearl approaches a nest elsewhere. After two steps, braking the fast arrival
provides the motion that turns the first pearl east. Its displaced northward
movement starts the third pearl.

The eastbound pearl encounters soft glass. The third pearl encounters a slash
mirror and arrives first. The player stores its recovered movement in the bell
to empty the pocket, then lets the remaining pearl finish its slower journey.

The finale combines the game's relationships with different arrival times. It
does not add a new rule, a deadline, or a precision input requirement.

## The expanded campaign

The intended difficulty rises by chapter through longer dependencies and
combinations of earlier ideas. Individual rooms change emphasis; exchange
counts are not a difficulty ranking. These tables record the shipped allowance
and one authored route, not the only solution or a proven optimum. Detailed
tactics and exact commands are retained in the three chapter source modules.

### Rooms 11–19: The Deeper Shelves

Unfinished converters, prepared corners and cooperative arrivals introduce the exchange allowance. One spare exchange gives room to experiment with the new constraint.

| Room | Name | Pearls | Exchange allowance | Reference steps |
|---|---|---:|---:|---:|
| 11 | The Unfinished Journey | 3 | 10 | 25 |
| 12 | Prepared Positions | 3 | 12 | 18 |
| 13 | The Second Corner | 3 | 12 | 21 |
| 14 | Three Requests | 4 | 18 | 32 |
| 15 | Cross Purposes | 3 | 7 | 8 |
| 16 | The Two Empty Bells | 3 | 9 | 6 |
| 17 | The Shared Minute | 4 | 9 | 10 |
| 18 | The Far Side Of Fast | 3 | 7 | 7 |
| 19 | Borrowed Exits | 4 | 10 | 13 |

### Rooms 20–28: The Quiet Machines

Closed paths make stopping positions matter. Glass and shared arrivals turn spare movement into useful loans, building toward five pearls.

| Room | Name | Pearls | Exchange allowance | Reference steps |
|---|---|---:|---:|---:|
| 20 | The Missing Landing | 3 | 7 | 10 |
| 21 | The Other Half | 3 | 6 | 11 |
| 22 | Between Two Circles | 3 | 8 | 30 |
| 23 | Before The Softening | 3 | 9 | 13 |
| 24 | The Folded Orbit | 4 | 8 | 16 |
| 25 | The Glass Ferry | 3 | 10 | 22 |
| 26 | Three At Once | 4 | 9 | 6 |
| 27 | A Loan Between Arrivals | 4 | 9 | 10 |
| 28 | The Fivefold Promise | 5 | 12 | 15 |

### Rooms 29–37: The Mirror Vaults

Nest allocation, borrowed speeds and deferred deliveries ask the player to choose which journey should remain available.

| Room | Name | Pearls | Exchange allowance | Reference steps |
|---|---|---:|---:|---:|
| 29 | The Reluctant Mirror | 4 | 9 | 21 |
| 30 | The Rightful Nest | 4 | 9 | 18 |
| 31 | Which Pearl Belongs | 4 | 7 | 12 |
| 32 | The Wrong Speed | 4 | 9 | 6 |
| 33 | The Waiting Key | 5 | 11 | 19 |
| 34 | The Long Conversation | 5 | 10 | 34 |
| 35 | Four Open Accounts | 5 | 21 | 37 |
| 36 | An Appointment In Glass | 5 | 11 | 14 |
| 37 | The Last Open Circle | 5 | 9 | 19 |

### Rooms 38–46: The Inner Archive

Plain corners need deliberate exchanges of axes. Short plans introduce full-pocket reserves and staggered arrivals before combining them.

| Room | Name | Pearls | Exchange allowance | Reference steps |
|---|---|---:|---:|---:|
| 38 | Double Entry | 3 | 7 | 7 |
| 39 | The Return Address | 3 | 7 | 14 |
| 40 | Three Signatures | 4 | 10 | 14 |
| 41 | Three Open Accounts | 3 | 7 | 7 |
| 42 | The Glass Reserve | 4 | 10 | 8 |
| 43 | Before The First Rest | 3 | 10 | 9 |
| 44 | The Forward Pocket | 3 | 8 | 20 |
| 45 | Double Counterpoint | 4 | 13 | 11 |
| 46 | The Third Voice | 3 | 9 | 7 |

### Rooms 47–55: The Constellations

Multiple pairs cooperate through successive turns. Later arrivals supply earlier unfinished journeys, culminating in a five-pearl composition.

| Room | Name | Pearls | Exchange allowance | Reference steps |
|---|---|---:|---:|---:|
| 47 | The Fourth Hand | 4 | 12 | 8 |
| 48 | The Second Tempo | 4 | 13 | 11 |
| 49 | The Empty Chair | 4 | 12 | 11 |
| 50 | The Cross Index | 3 | 12 | 8 |
| 51 | Compound Interest | 4 | 19 | 14 |
| 52 | Duplex Glass | 4 | 19 | 12 |
| 53 | The Pocket Pilgrim | 3 | 13 | 16 |
| 54 | The Three Keys | 4 | 15 | 8 |
| 55 | Five Point Proof | 5 | 23 | 19 |

### Rooms 56–64: The Heart of Motion

Longer plans combine interrupted journeys, returning glass carriers, parity-aware nest allocation and repeated preparation before a converter retires. The last room shares one motion across five pearls and four preparation phases.

| Room | Name | Pearls | Exchange allowance | Reference steps |
|---|---|---:|---:|---:|
| 56 | The Staircase Of Loans | 5 | 28 | 23 |
| 57 | The Returning Current | 5 | 22 | 13 |
| 58 | The Pocket Reserve | 4 | 24 | 27 |
| 59 | The Fast Return | 5 | 22 | 15 |
| 60 | The Unfinished Thread | 5 | 25 | 16 |
| 61 | The Last To Wake | 5 | 22 | 22 |
| 62 | The Order Of Belonging | 5 | 14 | 16 |
| 63 | What The Glass Remembers | 5 | 15 | 27 |
| 64 | Five Unfinished Thoughts | 5 | 29 | 48 |

## Design review and alternative tactics

The first eight rooms establish one rule or relationship at a time. Rooms five
and six reuse familiar actions but change what a completed delivery makes
possible. Rooms seven and eight deliberately simplify the scene while teaching
a new speed. The last two rooms require changing a journey before its endpoint,
which gives an exchange a different strategic purpose.

An earlier draft of the final pair used simultaneous arrivals and straightforward
storage. Those arrangements were mechanically valid but repeated the earlier
loop too closely. The current pair introduces the missing turn at a junction,
a displaced direction that becomes another artifact's tool, and staggered
arrival times. Their complete authored solutions still use only ten and nine
steps respectively.

There is no requirement to reproduce the authored solution. Borrowing a
reflected direction from a bell, reaching a different acceptable nest, or using
a wall to recover from a poor choice are legitimate alternatives. The game
should acknowledge the resulting state, rather than compare the player's
commands with a hidden script.

Several apparent shortcuts are intentionally prevented by the rules:

- The player cannot rotate an acquired movement arbitrarily. Direction changes
  require an exchange, a wall, or a mirror.
- A pearl cannot finish merely by passing over a nest. Braking is part of the
  repeated action.
- Settled pearls cannot become free storage. Bells retain that role throughout
  the room.
- Repeatedly exchanging with the same artifact without stepping simply swaps
  the same two movements back and forth.
- Stepping alone cannot settle an initially moving pearl. Every published room
  begins with all pearls away from nests.

The unlimited thinking time is deliberate. Freezing the world forever cannot
win a room, but the game does not penalize thought. Undo and restart should keep
experimentation inexpensive. There is no hidden clock that makes a seemingly
safe pause dangerous.

## Independent model and checks

The original rooms and reference model are in
[`tools/generate_motion_levels.py`](../tools/generate_motion_levels.py). The new
rooms are in [`motion_chapter_middle.py`](../tools/motion_chapter_middle.py),
[`motion_chapter_expert.py`](../tools/motion_chapter_expert.py), and
[`motion_chapter_finale.py`](../tools/motion_chapter_finale.py). They use
only Python's standard library. The model operates on immutable states, with
explicit functions for exchange, stepping, settlement, and completion. The
existing reference-model API calls stepping `wind`, with a `beats` parameter;
those internal names still represent complete steps and are retained in the
developer example below.

Run:

```sh
python3 tools/generate_motion_levels.py
```

Generation checks every room's dimensions, actor bounds, tile values, motion
values, initial placement, nest count, final storage capacity, and fixed text
widths. It replays every reference exchange and every individual step, checking
state invariants and conservation throughout. Every reference solution finishes
with every pearl settled within its allowance. Every room also survives a thousand-step no-exchange
check without being accidentally completed.

Small rule examples check every mirror heading at both speeds, a fast wall
reversal, immediate slowing on glass, braking on a nest, competing stationary
pearls on one nest, and movement through an occupied nest. These cases directly
affect the validity of the rooms.

The optional breadth-first solver searches independent command sequences,
respecting the room's exchange allowance. It is not part of the ordinary build:

```sh
python3 tools/generate_motion_levels.py --solve 1 2 3 4 5 7 8
```

For the original release it independently found solutions for rooms 1 through
5, 7, and 8. The room 6
search, and separate searches of rooms 9 and 10, exceeded a 100,000-state bound;
their authored solutions remain fully replay-checked. The solver minimizes the
number of exchanges plus individual steps, which is a different measure
from the exchange-only study targets listed above. Neither measure establishes
human difficulty or enjoyment.

For that original release, three deterministic blind policies were also run
for up to 300 iterations:
cycling through one exchange and one step, exchanging every active actor before
one step, and exchanging every active actor before two steps. None solved the
whole campaign. The first policy eventually solved rooms 1, 2, 3, and 9; the
second solved 1, 2, and 7; the third solved 1, 2, 3, and 9. None solved room 10.
The fastest blind completion of room 9 required 43 iterations of the four-actor
sweep, compared with the authored eight exchanges and ten steps. A blind search
can eventually reach valid states in a forgiving finite puzzle; these results
do not identify a simple repeated action that bypasses the complete design.

The JSON output contains the initial state, complete per-step solution traces,
and exact expected states after exchanges. The implementation can compare its
memory state against these traces in VICE. Such a comparison establishes
agreement with these rules; it does not establish that players find them clear
or enjoyable.

## Generated data contract

The script writes `build/motion/levels.inc` and `build/motion/levels.json`.
Outputs are deterministic and contain no timestamps. The include file declares
`.segment "RODATA"` and exports these symbols:

| Symbol | Size | Layout |
|---|---:|---|
| `level_maps` | 5,184 bytes | 64 row-major maps; two tiles per byte, first tile in low nibble |
| `level_actor_count` | 64 bytes | Actual count in each room |
| `level_actors` | 1,536 bytes | 64 records of six actors; each actor is type, x, y, motion |
| `level_swap_limits` | 64 bytes | Zero for lessons, achievable allowance for later rooms |
| `level_names` | 1,536 bytes | 64 strings of 24 screen-code bytes |
| `level_hints` | 2,432 bytes | 64 strings of 38 screen-code bytes |
| `level_par_swaps` | 64 bytes | Authored exchange counts; legacy symbol, not optimal scores |

Only the selected map expands to 162 bytes of working RAM. Room and actor
records are addressed through 16-bit pointers, avoiding eight-bit offset wrap
after room 42. The linker confines code and source assets below the VIC screen
at `$8000`. The 64-entry undo buffer occupies `$C000–$CFFF`.

The linked 64-room release is a 27,721-byte PRG, including its two-byte load
address. Code and source data occupy `$0801–$7447`, leaving 3,000 bytes before
the screen at `$8000`. BSS uses `$0200–$038A`; the undo area occupies the full
4 KiB work region. All rooms are resident after the initial load.

Unused actor slots are zero padded; the actor count determines which slots are
active. Actor type is 0 for a pearl and 1 for a bell. Strings are space padded.
Letters use standard uppercase C64 screen
codes, with `A` equal to 1. The tile codes are floor 0, wall 1, slash 2,
backslash 3, nest 4, and soft glass 5. Movement codes are still 0; east, south,
west, north 1 through 4; and the corresponding fast movements 5 through 8.

The JSON nests are ordered by their row-major tile position. Its `nests_used`
field is a bit mask in that order. Actor indices and room coordinates are zero
based. For example, the first room's checked actions are:

```text
swap actor 1
swap actor 0
wind 5 beats
swap actor 0
```

A room is a win when every type-0 actor is inactive. The final nonempty pocket
and the bell's continuing movement are valid; they are the motion recovered
from the completed work.
