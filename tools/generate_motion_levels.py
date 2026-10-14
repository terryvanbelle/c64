#!/usr/bin/env python3
"""Author and independently check the rooms for Borrowed Motion.

No third-party dependencies. Running this writes deterministic ca65 tables and
JSON reference traces to build/motion. Import initial_state, swap, and wind to
compare an emulator implementation against the independent rules below.
"""
from __future__ import annotations

import argparse
from collections import deque
from dataclasses import dataclass, replace
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "motion"
WIDTH, HEIGHT, MAX_ACTORS = 18, 9, 6
FLOOR, WALL, SLASH, BACKSLASH, NEST, SLOWGLASS = range(6)
STILL, EAST, SOUTH, WEST, NORTH = range(5)
STEP = ((0, 0), (1, 0), (0, 1), (-1, 0), (0, -1))
REVERSE = (0, WEST, NORTH, EAST, SOUTH)
SLASH_TURN = (0, NORTH, WEST, SOUTH, EAST)
BACKSLASH_TURN = (0, SOUTH, EAST, NORTH, WEST)
MAP_CHARS = ".#/\\Og"


@dataclass(frozen=True)
class Actor:
    kind: int  # 0 pearl, 1 brass bell
    x: int
    y: int
    motion: int = STILL
    active: bool = True


@dataclass(frozen=True)
class State:
    actors: tuple[Actor, ...]
    pocket: int = STILL
    nests_used: int = 0


@dataclass(frozen=True)
class Level:
    name: str
    hint: str
    board: tuple[int, ...]
    actors: tuple[Actor, ...]
    solution: tuple[tuple[str, int], ...]
    lesson: str

    @property
    def nests(self):
        return tuple((i % WIDTH, i // WIDTH) for i, tile in enumerate(self.board)
                     if tile == NEST)


def direction(motion):
    return 0 if not motion else (motion - 1) % 4 + 1


def changed_direction(motion, heading):
    return heading + (4 if motion > 4 else 0)


def settle(level, state):
    """Settle stationary pearls in actor order after a swap or full beat."""
    actors = list(state.actors)
    used = state.nests_used
    nest_index = {p: i for i, p in enumerate(level.nests)}
    for i, actor in enumerate(actors):
        nest = nest_index.get((actor.x, actor.y))
        if (actor.active and actor.kind == 0 and actor.motion == STILL
                and nest is not None and not used & (1 << nest)):
            actors[i] = replace(actor, active=False)
            used |= 1 << nest
    return State(tuple(actors), state.pocket, used)


def initial_state(level):
    return settle(level, State(level.actors))


def swap(level, state, actor_index):
    if not 0 <= actor_index < len(state.actors):
        raise ValueError("Actor index is outside the room")
    actor = state.actors[actor_index]
    if not actor.active:
        raise ValueError("Settled pearls cannot exchange motion")
    actors = list(state.actors)
    actors[actor_index] = replace(actor, motion=state.pocket)
    return settle(level, State(tuple(actors), actor.motion, state.nests_used))


def wind(level, state, beats=1):
    if beats < 0:
        raise ValueError("Beat count cannot be negative")
    for _ in range(beats):
        actors = list(state.actors)
        for i, actor in enumerate(actors):
            if not actor.active or actor.motion == STILL:
                continue
            steps = 2 if actor.motion > 4 else 1
            for _step in range(steps):
                heading = direction(actor.motion)
                dx, dy = STEP[heading]
                x, y = actor.x + dx, actor.y + dy
                if (not 0 <= x < WIDTH or not 0 <= y < HEIGHT
                        or level.board[y * WIDTH + x] == WALL):
                    actor = replace(actor, motion=changed_direction(
                        actor.motion, REVERSE[heading]))
                    continue  # Bounce consumes this microstep without moving.
                tile = level.board[y * WIDTH + x]
                motion = actor.motion
                if tile == SLASH:
                    motion = changed_direction(motion, SLASH_TURN[heading])
                elif tile == BACKSLASH:
                    motion = changed_direction(motion, BACKSLASH_TURN[heading])
                elif tile == SLOWGLASS:
                    motion = heading
                actor = replace(actor, x=x, y=y, motion=motion)
                if tile == SLOWGLASS:
                    break  # Slowglass ends the current beat immediately.
            actors[i] = actor
        state = settle(level, State(tuple(actors), state.pocket, state.nests_used))
    return state


def won(state):
    return all(a.kind != 0 or not a.active for a in state.actors)


def check_state(level, state):
    assert 0 <= state.pocket <= 8
    assert 0 <= state.nests_used < (1 << len(level.nests))
    settled = 0
    for a in state.actors:
        assert 0 <= a.x < WIDTH and 0 <= a.y < HEIGHT
        assert level.board[a.y * WIDTH + a.x] != WALL
        assert 0 <= a.motion <= 8 and a.kind in (0, 1)
        if not a.active:
            assert a.kind == 0 and a.motion == 0
            assert (a.x, a.y) in level.nests
            settled += 1
    assert settled == state.nests_used.bit_count()


def moving_tokens(state):
    return int(state.pocket != 0) + sum(a.motion != 0 for a in state.actors)


def state_json(state):
    return {"pocket": state.pocket, "nests_used": state.nests_used,
            "actors": [{"type": a.kind, "x": a.x, "y": a.y,
                        "motion": a.motion, "active": a.active}
                       for a in state.actors]}


def replay(level, actions=None):
    state = initial_state(level)
    check_state(level, state)
    tokens = moving_tokens(state)
    trace = [{"action": {"initial": True}, "state": state_json(state)}]
    for operation, value in actions if actions is not None else level.solution:
        if operation == "swap":
            state = swap(level, state, value)
            check_state(level, state)
            assert moving_tokens(state) == tokens
            trace.append({"action": {"swap": value}, "state": state_json(state)})
        elif operation == "wind":
            for _ in range(value):
                state = wind(level, state)
                check_state(level, state)
                assert moving_tokens(state) == tokens
                trace.append({"action": {"wind": 1}, "state": state_json(state)})
        else:
            raise ValueError(operation)
    return state, trace


def solve_breadth_first(level, max_states=250000):
    """Independent bounded solver; shortest count of swaps plus individual beats.

    This is a correctness tool, not a claim that the study target is optimal.
    Return (solution, explored), or (None, explored) when the bound is reached.
    """
    start = initial_state(level)
    frontier = deque([start])
    previous = {start: None}
    while frontier and len(previous) <= max_states:
        state = frontier.popleft()
        if won(state):
            result = []
            while previous[state] is not None:
                state, action = previous[state]
                result.append(action)
            return tuple(reversed(result)), len(previous)
        choices = [(('wind', 1), wind(level, state))]
        choices += [(('swap', i), swap(level, state, i))
                    for i, a in enumerate(state.actors)
                    if a.active and a.motion != state.pocket]
        for action, successor in choices:
            if successor not in previous:
                previous[successor] = (state, action)
                frontier.append(successor)
    return None, len(previous)


def room(rectangles):
    board = [WALL] * (WIDTH * HEIGHT)
    for x1, y1, x2, y2 in rectangles:
        for y in range(y1, y2 + 1):
            for x in range(x1, x2 + 1):
                board[y * WIDTH + x] = FLOOR
    return board


def make_level(name, hint, actors, nests, solution, lesson, *, rectangles=None,
               walls=(), slash=(), backslash=(), glass=()):
    board = room(rectangles or [(1, 1, 16, 7)])
    for tile, cells in ((WALL, walls), (SLASH, slash), (BACKSLASH, backslash),
                        (SLOWGLASS, glass), (NEST, nests)):
        for x, y in cells:
            board[y * WIDTH + x] = tile
    return Level(name, hint, tuple(board), tuple(actors), tuple(solution), lesson)


def authored_levels():
    p = lambda x, y, motion=0: Actor(0, x, y, motion)
    b = lambda x, y, motion=0: Actor(1, x, y, motion)
    return [
        make_level(
            "THE FIRST LOAN", "TAKE. GIVE. WIND. TAKE TO REST.",
            [p(7, 4), b(2, 4, EAST)], [(12, 4)],
            [('swap', 1), ('swap', 0), ('wind', 5), ('swap', 0)],
            "Borrow the bell's movement, lend it to the pearl, then take it back on a nest.",
            rectangles=[(1, 2, 16, 6)]),
        make_level(
            "A CHANGE OF HEART", "FULL POCKET TRADES. EMPTY IT TO REST.",
            [p(3, 4, EAST), b(12, 6, NORTH)], [(3, 2)],
            [('swap', 1), ('swap', 0), ('swap', 1), ('wind', 2), ('swap', 0)],
            "Exchange two different movements, then park the unwanted movement in the bell.",
            walls=[(x, y) for x in range(6, 10) for y in range(2, 5)]),
        make_level(
            "THE PATIENT WALL", "A WALL TURNS MOTION BACK FOR YOU.",
            [p(12, 4), b(7, 4, EAST)], [(5, 4)],
            [('swap', 1), ('swap', 0), ('wind', 16), ('swap', 0)],
            "Use a wall to reverse an eastward loan before collecting it at the nest.",
            rectangles=[(1, 3, 16, 5)]),
        make_level(
            "AN UNEXPECTED TURN", "MIRRORS TURN THE MOTION YOU BORROW.",
            [p(4, 6), b(2, 2, EAST)], [(13, 2)],
            [('swap', 1), ('swap', 0), ('wind', 13), ('swap', 0)],
            "A slash mirror turns eastward movement northward on entry.",
            rectangles=[(1, 1, 6, 3), (3, 5, 14, 7), (12, 1, 14, 7)],
            slash=[(13, 6)]),
        make_level(
            "PASS IT ON", "AN ARRIVAL CAN BECOME ANOTHER LOAN.",
            [p(3, 2), p(5, 2), b(1, 6, EAST)], [(12, 6), (5, 6)],
            [('swap', 2), ('swap', 0), ('wind', 13), ('swap', 0),
             ('swap', 1), ('wind', 4), ('swap', 1)],
            "Collect southward movement at the first nest and reuse it for the second pearl.",
            backslash=[(12, 2)],
            walls=[(x, y) for x in range(8, 11) for y in range(4, 7)]),
        make_level(
            "A PLACE FOR EVERYTHING", "THE BELL CAN HOLD AN UNWANTED MOTION.",
            [p(3, 2, EAST), p(12, 6, SOUTH), b(2, 4)], [(3, 6), (6, 7)],
            [('swap', 1), ('swap', 0), ('swap', 2), ('wind', 4), ('swap', 0),
             ('swap', 1), ('wind', 7), ('swap', 1)],
            "Use the empty bell as storage, then turn the recovered motion through another mirror.",
            slash=[(12, 7)],
            walls=[(x, y) for x in range(8, 11) for y in range(2, 4)] +
                  [(x, y) for x in range(7, 10) for y in range(5, 7)]),
        make_level(
            "LONG STRIDES", "DOUBLE ARROWS TAKE TWO STEPS PER BEAT.",
            [p(3, 4), b(2, 2, 5)], [(13, 4)],
            [('swap', 1), ('swap', 0), ('wind', 5), ('swap', 0)],
            "A fast loan covers two tiles in one beat; stop after a complete beat.",
            rectangles=[(1, 2, 16, 6)]),
        make_level(
            "THE SOFT GLASS", "SOFT GLASS MAKES A FAST LOAN GENTLE.",
            [p(3, 4), b(2, 2, 5)], [(10, 4)],
            [('swap', 1), ('swap', 0), ('wind', 5), ('swap', 0)],
            "Slowglass cancels the rest of the current beat and preserves a single-step motion.",
            rectangles=[(1, 2, 16, 6)], glass=[(8, 4)],
            walls=[(x, 2) for x in (5, 6, 12, 13)]),
        make_level(
            "THE QUIET EXCHANGE", "SOMETIMES YOU MUST BORROW A TURN.",
            [p(3, 4), p(13, 6, NORTH), p(10, 6), b(2, 6, EAST)],
            [(7, 2), (13, 2), (10, 2)],
            [('swap', 3), ('swap', 0), ('wind', 4), ('swap', 1),
             ('swap', 0), ('swap', 3), ('wind', 2), ('swap', 0),
             ('swap', 2), ('wind', 4), ('swap', 2)],
            "Borrow a northward arrival to turn another pearl at a junction, store its old eastward movement, and pass the recovered northward motion onward.",
            rectangles=[(1, 4, 16, 4), (1, 6, 16, 6), (7, 1, 7, 6),
                        (10, 1, 10, 7), (13, 1, 13, 7)]),
        make_level(
            "BORROWED TOMORROW", "EVERY ENDING HOLDS A NEW BEGINNING.",
            [p(3, 6, NORTH), p(7, 2, 5), p(13, 7), b(2, 2)],
            [(11, 2), (12, 4), (15, 4)],
            [('wind', 2), ('swap', 1), ('swap', 0), ('swap', 2),
             ('wind', 5), ('swap', 2), ('swap', 3), ('wind', 2), ('swap', 0)],
            "Exchange direction halfway through a journey; lend the displaced northward movement to a mirror-bound pearl, then manage their different arrival times.",
            slash=[(13, 4)], glass=[(8, 4)],
            walls=[(x, 3) for x in (5, 6, 9, 10)] +
                  [(x, 5) for x in range(5, 12)]),
    ]


def screen_codes(text, width):
    assert text == text.upper() and len(text) <= width, (text, len(text), width)
    assert all(32 <= ord(c) <= 95 for c in text)
    return [ord(c) & 63 if ord(c) >= 64 else ord(c) for c in text.ljust(width)]


def validate_level(level):
    assert len(level.board) == WIDTH * HEIGHT
    assert all(FLOOR <= tile <= SLOWGLASS for tile in level.board)
    assert 1 <= len(level.actors) <= MAX_ACTORS
    assert 1 <= len(level.nests) <= 5
    assert len(level.nests) == sum(a.kind == 0 for a in level.actors)
    assert len({(a.x, a.y) for a in level.actors}) == len(level.actors)
    screen_codes(level.name, 24)
    screen_codes(level.hint, 38)
    start = initial_state(level)
    check_state(level, start)
    assert all(a.active for a in start.actors), "No free initial deliveries"
    assert not won(start)
    bells = sum(a.kind == 1 for a in start.actors)
    assert moving_tokens(start) <= bells + 1, "Not enough final motion storage"
    final, trace = replay(level)
    assert won(final), (level.name, state_json(final))
    # Advancing time alone must never make a moving pearl settle.
    assert not won(wind(level, start, 1000))
    return final, trace


def check_rule_examples():
    """Small independent edge cases, covering the rules that can change puzzles."""
    for fast in (0, 4):
        for heading in range(1, 5):
            dx, dy = STEP[heading]
            for tile, expected in ((SLASH, SLASH_TURN), (BACKSLASH, BACKSLASH_TURN)):
                board = room([(1, 1, 16, 7)])
                board[(4 + dy) * WIDTH + 8 + dx] = tile
                level = Level("RULE", "RULE", tuple(board),
                              (Actor(1, 8, 4, heading + fast),), (), "")
                result = wind(level, State(level.actors)).actors[0]
                assert result.motion == expected[heading] + fast
    # The failed first fast microstep reverses; the second moves away.
    level = make_level("RULE", "RULE", [Actor(1, 16, 4, 5)], [], [], "")
    assert wind(level, State(level.actors)).actors[0] == Actor(1, 15, 4, 7)
    # Entering glass on the first fast microstep stops the beat at that tile.
    level = make_level("RULE", "RULE", [Actor(1, 7, 4, 5)], [], [], "", glass=[(8, 4)])
    assert wind(level, State(level.actors)).actors[0] == Actor(1, 8, 4, EAST)
    # A moving pearl on a nest waits for braking; simultaneous stopped pearls
    # settle in actor order and may not share the same nest.
    level = make_level("RULE", "RULE", [Actor(0, 8, 4, EAST)], [(8, 4)], [], "")
    state = initial_state(level)
    assert state.actors[0].active
    assert not swap(level, state, 0).actors[0].active
    duplicate = State((Actor(0, 8, 4), Actor(0, 8, 4)))
    stopped = settle(level, duplicate)
    assert [a.active for a in stopped.actors] == [False, True]
    # Pearls may travel through an occupied nest; no collision is implied.
    passing = State((Actor(0, 8, 4, active=False), Actor(0, 7, 4, EAST)), 0, 1)
    passed = wind(level, passing)
    assert passed.actors[1] == Actor(0, 8, 4, EAST)


def write_tables(levels):
    tables = {
        "level_maps": [n for level in levels for n in level.board],
        "level_actor_count": [len(level.actors) for level in levels],
    }
    for field, attr in (("type", "kind"), ("x", "x"), ("y", "y"), ("motion", "motion")):
        tables[f"level_actor_{field}"] = [n for level in levels for n in
            ([getattr(a, attr) for a in level.actors] + [0] * (MAX_ACTORS - len(level.actors)))]
    tables["level_names"] = [n for level in levels for n in screen_codes(level.name, 24)]
    tables["level_hints"] = [n for level in levels for n in screen_codes(level.hint, 38)]
    tables["level_par_swaps"] = [sum(op == 'swap' for op, _ in level.solution) for level in levels]
    lines = ["; Generated by tools/generate_motion_levels.py. Do not hand edit.",
             '; Fixed widths: map162, actors6, names24, hints38.', '.segment "RODATA"']
    lines += [".export " + name for name in tables]
    for name, data in tables.items():
        lines += ["", name + ":"]
        for i in range(0, len(data), 18):
            lines.append("    .byte " + ",".join(str(n) for n in data[i:i + 18]))
        lines.append(f'.assert * - {name} = {len(data)}, error, "{name} size"')
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "levels.inc").write_text("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--solve", type=int, nargs="*", metavar="ROOM",
                        help="Also breadth-first solve these 1-based room numbers (default when flag alone: 1 2).")
    parser.add_argument("--max-states", type=int, default=250000)
    args = parser.parse_args()
    levels = authored_levels()
    assert len(levels) == 10
    check_rule_examples()
    records = []
    for number, level in enumerate(levels, 1):
        _, trace = validate_level(level)
        record = {
            "number": number, "name": level.name, "hint": level.hint,
            "lesson": level.lesson, "width": WIDTH, "height": HEIGHT,
            "map": list(level.board),
            "map_rows": ["".join(MAP_CHARS[t] for t in level.board[y * WIDTH:(y + 1) * WIDTH])
                         for y in range(HEIGHT)],
            "nests": [{"x": x, "y": y} for x, y in level.nests],
            "actors": state_json(initial_state(level))["actors"],
            "study_target_swaps": sum(op == 'swap' for op, _ in level.solution),
            "solution": [{op: value} for op, value in level.solution],
            "solution_trace": trace,
        }
        records.append(record)
        print(f"{number:2}. {level.name:24} {record['study_target_swaps']} exchanges, "
              f"{sum(n for op, n in level.solution if op == 'wind')} beats: solved")
    if args.solve is not None:
        for number in args.solve or [1, 2]:
            assert 1 <= number <= len(levels)
            solution, explored = solve_breadth_first(levels[number - 1], args.max_states)
            if solution is None:
                print(f"BFS room {number}: state bound reached ({explored}); authored solution remains checked")
            else:
                assert won(replay(levels[number - 1], solution)[0])
                print(f"BFS room {number}: solved in {len(solution)} actions; {explored} states")
    write_tables(levels)
    document = {"schema_version": 1, "game": "Borrowed Motion", "width": WIDTH,
                "height": HEIGHT, "max_actors": MAX_ACTORS,
                "tiles": {"floor": 0, "wall": 1, "slash": 2, "backslash": 3,
                          "nest": 4, "slowglass": 5},
                "motion": {"still": 0, "east": 1, "south": 2, "west": 3, "north": 4,
                           "fast_east": 5, "fast_south": 6, "fast_west": 7, "fast_north": 8},
                "levels": records}
    (OUT / "levels.json").write_text(json.dumps(document, indent=2) + "\n")
    print(f"Wrote {OUT / 'levels.inc'} and levels.json")


if __name__ == "__main__":
    main()
