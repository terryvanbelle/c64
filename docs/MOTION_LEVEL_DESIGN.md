# Borrowed Motion level design

Borrowed Motion asks the player to treat movement as an object: take it, lend
it, exchange it, and recover it after a journey. The ten rooms form a short,
complete course in that relationship. Later rooms require changing a journey
halfway through and finding somewhere useful to put the movement that was
replaced.

The game gives the player control of time. Objects move only while the player
winds the world. Releasing the winding control leaves a stable situation to
inspect. Interesting decisions should concern whose movement is useful next,
not the speed at which the player can change selection.

These are original authored rooms for this repository. The reference model
establishes their mechanical solvability. Human play is still needed to judge
clarity, enjoyment, and the appropriate difficulty.

## Rules that the rooms rely on

The board is 18 by 9 tiles. There are at most six artifacts. A pearl can settle
into a nest; a brass bell provides a place to obtain or store movement. Artifacts
pass through one another, including through a pearl that has already settled.
Selection and exchanges work across the entire room.

The spool begins empty. Exchanging with a selected artifact swaps its complete
movement with the spool. An empty spool therefore stops a moving artifact. A
full spool changes that artifact's movement and acquires its previous movement.
Exchanges happen while the world is stopped.

A stationary pearl on an unused nest immediately settles. Moving across a nest
does not deliver a pearl: the player must stop it there. Settled pearls cannot
be selected or used as storage. Nests accept any pearl, and a used nest remains
passable. When two stationary pearls share an unused nest, the earlier actor
index settles first; the other pearl remains active.

A normal movement travels one tile per beat. A fast movement attempts two
consecutive microsteps. Hitting a wall or the edge reverses direction and uses
that microstep without entering the wall. The remaining microstep of a fast
beat still occurs. A slash or backslash changes direction on entry, preserving
speed. Entering soft glass immediately reduces a fast movement to normal speed
and ends any remaining microsteps of that beat.

| Tile | Entering east | Entering south | Entering west | Entering north |
|---|---|---|---|---|
| Slash `/` | North | West | South | East |
| Backslash `\` | South | East | North | West |

Settlement is checked after every exchange and after each complete beat. The
model does not settle a pearl during the middle of a fast beat. Intended fast
solutions remain straight during each beat; none requires interpreting a
visually diagonal interpolation across a corner.

### A useful conservation rule

Exchanges, reflections, and mirrors preserve the number of nonempty movements.
Soft glass changes speed but also preserves that count. Settling removes a
stationary pearl and therefore removes no movement.

A finished room can store movement only in its bells and the spool. Therefore,
with one bell, a solvable room must begin with at most two nonempty movements.
The generator checks this necessary condition. It also checks conservation
after every exchange and every beat of every reference solution. This condition
alone does not prove a room is solvable; the complete solution replay does that.

## The ten rooms

“Study target” means the exchange count of the checked authored solution. It is
not a claim that the count is optimal. Taking fewer exchanges is welcome.
Winding beats do not increase this count.

| Room | New relationship | Study target | Reference winding beats |
|---|---|---:|---:|
| 1 The First Loan | Take a bell's motion, lend it, and recover it to settle | 3 | 5 |
| 2 A Change of Heart | A full spool exchanges motion; an empty spool brakes | 4 | 2 |
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
movement. Swapping the bell into the spool and then exchanging with the pearl
provides the needed heading, but leaves eastward movement in the spool. Parking
that movement in the bell empties the spool so it can brake the arriving pearl.

This is the first room where pressing exchange does not necessarily mean stop.
The spool's current arrow must remain conspicuous. The lesson is useful before
adding more objects or geometry.

### The Patient Wall

The nest is west of the pearl, while the available movement heads east. The
right wall provides the reverse heading. The player may send the pearl to the
wall or wait for a suitable direction in the donor before borrowing it.

The route includes a short interval of predictable winding. Holding the winding
control is appropriate here; the room should not demand sixteen separate key
presses. It teaches a transformation that can later rescue an imperfect plan.

### An Unexpected Turn

The pearl's route crosses a slash mirror that turns eastward movement north.
The bell is in a separate display area. This emphasizes that the exchange is
between selected objects anywhere on the board; the player is not transporting
a cursor-bound item through walkable corridors.

This room deliberately has disconnected floor areas. There is no player avatar
that must traverse them, and the bell is accessible through selection. The
pearl's entire intended route is connected. All other rooms have connected
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
competing demands. A double eastward arrow covers ten tiles in five beats. The
nest is on that straightforward sequence of stopping positions.

The initial fast lesson avoids a skipped destination, a bounce, or a mirror.
Those interactions can be explored after the difference between a step and a
beat is apparent.

### The Soft Glass

The nest is an odd number of tiles away from the pearl. The eastward loan begins
fast, but a clearly drawn glass tile on the route reduces it to ordinary speed.
The pearl can then stop precisely at its destination.

The glass sits on every direct horizontal approach from the starting position.
The authored route encounters it on the first microstep of a beat, exercising
the immediate slowing rule. The source bell's separate lane contains no glass.

### The Quiet Exchange

Three north-facing branches connect to a horizontal corridor. One pearl begins
travelling north toward a nest. Another begins stationary to the west of its
own branch. The player borrows eastward movement from the bell to bring that
pearl to the junction.

After four beats, the first pearl is on its nest while the second is at the
junction. Braking the arrival supplies the northward movement needed to turn
the other pearl. That exchange puts eastward movement into the spool, so the
bell is useful again as storage. After the second delivery, the same northward
movement can serve the third pearl.

The critical insight is that an artifact's movement can be replaced anywhere
along its route. No mirror creates the necessary turn at the junction. A player
who treats every loan as an uninterrupted trip must revise that model.

### Borrowed Tomorrow

A slow northbound pearl approaches a horizontal route while a fast eastbound
pearl approaches a nest elsewhere. After two beats, braking the fast arrival
provides the motion that turns the first pearl east. Its displaced northward
movement starts the third pearl.

The eastbound pearl encounters soft glass. The third pearl encounters a slash
mirror and arrives first. The player stores its recovered movement in the bell
to empty the spool, then lets the remaining pearl finish its slower journey.

The finale combines the game's relationships with different arrival times. It
does not add a new rule, a deadline, or a precision input requirement.

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
winding beats respectively.

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
- Repeatedly exchanging with the same artifact without winding simply swaps
  the same two movements back and forth.
- Winding alone cannot settle an initially moving pearl. Every published room
  begins with all pearls away from nests.

The unlimited thinking time is deliberate. Freezing the world forever cannot
win a room, but the game does not penalize thought. Undo and restart should keep
experimentation inexpensive. There is no hidden clock that makes a seemingly
safe pause dangerous.

## Independent model and checks

The editable source and reference model are both in
[`tools/generate_motion_levels.py`](../tools/generate_motion_levels.py). They use
only Python's standard library. The model operates on immutable states, with
explicit functions for exchange, winding, settlement, and completion.

Run:

```sh
python3 tools/generate_motion_levels.py
```

Generation checks every room's dimensions, actor bounds, tile values, motion
values, initial placement, nest count, final storage capacity, and fixed text
widths. It replays every reference exchange and every individual beat, checking
state invariants and conservation throughout. All ten reference solutions finish
with every pearl settled. Every room also survives a thousand-beat no-exchange
check without being accidentally completed.

Small rule examples check every mirror heading at both speeds, a fast wall
reversal, immediate slowing on glass, braking on a nest, competing stationary
pearls on one nest, and movement through an occupied nest. These cases directly
affect the validity of the rooms.

The optional breadth-first solver searches independent command sequences:

```sh
python3 tools/generate_motion_levels.py --solve 1 2 3 4 5 7 8
```

It independently finds solutions for rooms 1 through 5, 7, and 8. The room 6
search, and separate searches of rooms 9 and 10, exceeded a 100,000-state bound;
their authored solutions remain fully replay-checked. The solver minimizes the
number of exchanges plus individual winding beats, which is a different measure
from the exchange-only study targets listed above. Neither measure establishes
human difficulty or enjoyment.

Three deterministic blind policies were also run for up to 300 iterations:
cycling through one exchange and one beat, exchanging every active actor before
one beat, and exchanging every active actor before two beats. None solved the
whole campaign. The first policy eventually solved rooms 1, 2, 3, and 9; the
second solved 1, 2, and 7; the third solved 1, 2, 3, and 9. None solved room 10.
The fastest blind completion of room 9 required 43 iterations of the four-actor
sweep, compared with the authored eight exchanges and ten beats. A blind search
can eventually reach valid states in a forgiving finite puzzle; these results
do not identify a simple repeated action that bypasses the complete design.

The JSON output contains the initial state, complete per-beat solution traces,
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
| `level_maps` | 1,620 bytes | Ten row-major 18 by 9 maps |
| `level_actor_count` | 10 bytes | Actual count in each room |
| `level_actor_type` | 60 bytes | Ten groups of six; 0 pearl, 1 bell |
| `level_actor_x` | 60 bytes | Ten groups of six |
| `level_actor_y` | 60 bytes | Ten groups of six |
| `level_actor_motion` | 60 bytes | Ten groups of six |
| `level_names` | 240 bytes | Ten strings of 24 screen-code bytes |
| `level_hints` | 380 bytes | Ten strings of 38 screen-code bytes |
| `level_par_swaps` | 10 bytes | Checked authored exchange counts |

Unused actor slots are zero padded; the actor count determines which slots are
active. Strings are space padded. Letters use standard uppercase C64 screen
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

A room is a win when every type-0 actor is inactive. The final nonempty spool
and the bell's continuing movement are valid; they are the motion recovered
from the completed work.
