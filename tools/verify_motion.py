#!/usr/bin/env python3
"""Check normally autostarted Borrowed Motion through a loopback VICE monitor.

Inputs are injected after the actual CIA poll, at controls_sampled. This checks
the compiled game, not the physical keyboard/joystick scan or human enjoyment.
No program counter override or subroutine call injection is used. The default
run first checks an untouched title and loaded PRG, then plays all ten authored
solutions. Optional prepared fixtures overwrite documented game state to cover
physics boundaries and history capacity separately from normal progression.

Launch, for example:
  python3 tools/run_vice.py build/borrowed-motion.prg --monitor-port 6561
  python3 tools/verify_motion.py --port 6561 --model pal
"""
from __future__ import annotations

import argparse
from dataclasses import replace
import hashlib
import json
from pathlib import Path
import struct
import sys

from generate_motion_levels import (
    Actor, Level, State, WIDTH, HEIGHT, FLOOR, WALL, SLASH, BACKSLASH, NEST,
    SLOWGLASS, STEP, SLASH_TURN, BACKSLASH_TURN, authored_levels, direction,
    initial_state, state_json, swap, wind, won,
)
from vice_monitor import ViceMonitor, MonitorError

ROOT = Path(__file__).resolve().parents[1]
ARRAYS = {"actor_x": 6, "actor_y": 6, "actor_motion": 6, "actor_active": 6,
          "actor_type": 6, "goal_x": 5, "goal_y": 5}
WORDS = {"wind_count", "video_frames", "late_ticks"}
FIELDS = ("scene", "room_index", "unlocked", "selected", "spool", "settled",
          "swaps", "wind_count", "actor_count", "goal_count", "goal_used",
          "pearl_count", "anim_left", "micro_phase", "undo_count", "undo_head",
          "controls_buffer", "video_standard", "video_frames", "late_ticks")


def read_labels(path):
    return {p[2].lstrip("."): int(p[1], 16) for line in path.read_text().splitlines()
            if len(p := line.split()) == 3 and p[0] == "al"}


class Validator:
    def __init__(self, monitor, labels, model):
        self.m, self.l, self.model = monitor, labels, model
        self.checks = 0
        self.ticks = 0
        self.previous = 0
        self.owned = []
        self.log = []
        self.level_results = []
        self.fixture_results = []
        self.checkpoint = self.m.checkpoint(self.l["controls_sampled"])
        self.owned.append(self.checkpoint)
        self.stop_next()

    def close(self):
        for checkpoint in self.owned:
            self.m.delete_checkpoint(checkpoint)
        self.owned.clear()
        self.m.resume()

    def check(self, condition, message, detail=None):
        self.checks += 1
        if not condition:
            raise AssertionError(f"{message}: {detail}")

    def stop_next(self):
        self.m.events.clear()
        self.m.resume()
        event = self.m.wait_event(0x62, timeout=30)
        pc = struct.unpack_from("<H", event.body)[0]
        self.check(pc == self.l["controls_sampled"], "unexpected stop", hex(pc))

    def state(self):
        low = self.l["__BSS_RUN__"]
        data = self.m.memread(low, self.l["__BSS_SIZE__"])
        result = {}
        for field in FIELDS:
            at = self.l[field] - low
            result[field] = int.from_bytes(data[at:at + (2 if field in WORDS else 1)], "little")
        for field, size in ARRAYS.items():
            at = self.l[field] - low
            result[field] = list(data[at:at + size])
        start, end = self.l["state_begin"] - low, self.l["state_end"] - low
        result["snapshot"] = data[start:end].hex()
        return result

    def tick(self, held=0, pressed=None, menu=0):
        if pressed is None:
            pressed = held & ~self.previous
        self.previous = held
        # input_controls, input_pressed, menu_keys, menu_pressed are contiguous.
        self.m.memwrite(self.l["input_controls"], bytes((held, pressed, menu, menu)))
        self.stop_next()
        self.ticks += 1
        return self.state()

    def idle(self, count=1):
        result = self.state()
        for _ in range(count):
            result = self.tick()
        return result

    def match(self, expected, context):
        actual = self.state()
        actors = tuple(Actor(actual["actor_type"][i], actual["actor_x"][i],
                             actual["actor_y"][i], actual["actor_motion"][i],
                             bool(actual["actor_active"][i]))
                       for i in range(actual["actor_count"]))
        observed = State(actors, actual["spool"], actual["goal_used"])
        self.check(observed == expected, context,
                   {"expected": state_json(expected), "actual": state_json(observed)})
        self.check(actual["settled"] == expected.nests_used.bit_count(),
                   context + " settled count", actual["settled"])
        return actual

    def select(self, index):
        for _ in range(7):
            current = self.state()
            if current["selected"] == index:
                return
            self.check(current["actor_active"][index], "select target inactive", index)
            self.tick(8, pressed=8)
            self.tick()
        raise AssertionError(f"could not select actor {index}")

    def exchange(self, index):
        self.select(index)
        before = self.state()
        after = self.tick(16, pressed=16)
        self.tick()
        return before, after

    def beat(self):
        before = self.state()
        self.check(before["anim_left"] == 0, "beat starts while animating", before)
        after = self.tick(1, pressed=1)
        for _ in range(80):
            if not after["anim_left"]:
                break
            after = self.tick()
        else:
            raise AssertionError("beat animation failed to finish")
        self.check(after["wind_count"] == (before["wind_count"] + 1) & 65535,
                   "wind increments one beat", after)
        self.check(after["micro_phase"] == 0, "microsteps complete", after)
        return before, after

    def undo(self, snapshot):
        if self.state()["scene"] == 3:
            self.idle(31)
        else:
            self.idle(8)
        after = self.tick(2, pressed=2)
        self.check(after["scene"] == 1, "undo returns to play", after)
        self.check(after["snapshot"] == snapshot["snapshot"], "undo restores full state",
                   {"before": snapshot, "restored": after})
        self.tick()

    def cold(self, program):
        state = self.state()
        self.check(state["scene"] == 0, "normal cold startup reaches title", state)
        expected_region = {"pal": 0, "ntsc": 1, "oldntsc": 2}[self.model]
        self.check(state["video_standard"] == expected_region, "video detection", state)
        self.check(state["unlocked"] == 0 and state["room_index"] == 0,
                   "cold progression starts at room one", state)
        data = program.read_bytes()
        self.check(data[:2] == b"\x01\x08", "PRG load address")
        self.check(self.m.memread(0x0801, len(data) - 2) == data[2:],
                   "complete normally loaded PRG matches artifact")
        self.check(self.m.memread(1, 1)[0] & 7 == 5, "I/O visible and ROMs out")
        self.log.append("Untouched normal autostart reached title; loaded image matches PRG.")

    def pacing(self):
        before = self.state()
        fraction = int.from_bytes(self.m.memread(self.l["tick_fraction"], 2), "little")
        increment = int.from_bytes(self.m.memread(self.l["tick_step"], 2), "little")
        self.check(increment == {"pal": 0xff5d, "ntsc": 0xd5f4,
                                 "oldntsc": 0xd1dc}[self.model], "regional tick increment")
        after = self.idle(256)
        frames = (after["video_frames"] - before["video_frames"]) & 65535
        carries = (fraction + frames * increment) // 65536
        self.check(carries == 256, "fractional pacing emits exactly 256 gameplay ticks",
                   {"video_frames": frames, "carries": carries})
        self.check(after["late_ticks"] == before["late_ticks"], "idle pacing has no missed ticks")
        self.log.append(f"Regional accumulator emitted 256 ticks across {frames} video frames.")

    def progression(self):
        levels = authored_levels()
        self.tick(menu=1)
        for room, level in enumerate(levels):
            expected = initial_state(level)
            first = self.match(expected, f"room {room + 1} initial state")
            self.check(first["scene"] == 1 and first["room_index"] == room,
                       "natural progression loads next room", first)
            self.check(self.m.memread(self.l["room_map"], WIDTH * HEIGHT) == bytes(level.board),
                       "compiled room map matches authored board", room + 1)
            # Help round-trip preserves the complete puzzle state.
            self.tick(menu=4)
            self.check(self.state()["scene"] == 2, "help opens")
            self.idle(3)
            self.tick(menu=4)
            self.check(self.state()["snapshot"] == first["snapshot"], "help preserves puzzle")
            self.check(self.state()["scene"] == 1, "help closes to play")
            actions = 0
            undo_checked = False
            for operation, value in level.solution:
                if operation == "wind":
                    for _ in range(value):
                        self.beat()
                        expected = wind(level, expected)
                        self.match(expected, f"room {room + 1}, beat {actions + 1}")
                        actions += 1
                else:
                    self.select(value)
                    snapshot = self.state()
                    prior = expected
                    self.exchange(value)
                    expected = swap(level, expected, value)
                    self.match(expected, f"room {room + 1}, exchange {actions + 1}")
                    actions += 1
                    if not undo_checked or won(expected):
                        self.undo(snapshot)
                        self.match(prior, f"room {room + 1}, undo exchange")
                        self.exchange(value)
                        self.match(expected, f"room {room + 1}, replay exchange")
                        undo_checked = True
            self.check(won(expected), "reference solution reaches completion", room + 1)
            final = self.state()
            self.check(final["scene"] == 3, "compiled room completion", final)
            self.check(final["unlocked"] == min(room + 1, 9), "unlock progression", final)
            self.level_results.append({"room": room + 1, "name": level.name,
                                       "model_comparisons": actions, "swaps": final["swaps"],
                                       "beats": final["wind_count"], "undo_round_trips": 2})
            print(f"Room {room + 1}: solution and undo passed ({actions} actions)", flush=True)
            self.idle(31)
            self.tick(menu=1)
        self.check(self.state()["scene"] == 4, "ten rooms reach ending")
        self.tick(16, pressed=16)
        self.check(self.state()["scene"] == 0 and self.state()["unlocked"] == 9,
                   "ending returns to unlocked title")
        self.tick(8, pressed=8)
        self.check(self.state()["room_index"] == 1, "unlocked title selection")
        self.tick(menu=1)
        self.exchange(1)
        self.tick(menu=2)
        self.match(initial_state(levels[1]), "restart restores authored room")
        self.check(self.state()["undo_count"] == 0, "restart clears history")
        self.log.append("All ten solutions, help, undo, ending, unlock and restart passed.")

    def write(self, name, data):
        if isinstance(data, int):
            data = data.to_bytes(2 if name in WORDS else 1, "little")
        else:
            data = bytes(data)
        self.m.memwrite(self.l[name], data)

    def fixture(self, level, state=None):
        state = initial_state(level) if state is None else state
        self.write("room_map", level.board)
        self.write("actor_count", len(state.actors))
        self.write("pearl_count", sum(a.kind == 0 for a in state.actors))
        for field, attribute in (("actor_x", "x"), ("actor_y", "y"),
                                 ("actor_motion", "motion"), ("actor_active", "active"),
                                 ("actor_type", "kind")):
            values = [int(getattr(a, attribute)) for a in state.actors]
            self.write(field, values + [0] * (6 - len(values)))
        self.write("goal_count", len(level.nests))
        self.write("goal_x", [p[0] for p in level.nests] + [0] * (5 - len(level.nests)))
        self.write("goal_y", [p[1] for p in level.nests] + [0] * (5 - len(level.nests)))
        self.write("goal_used", state.nests_used)
        self.write("spool", state.spool)
        self.write("settled", state.nests_used.bit_count())
        self.write("selected", next(i for i, a in enumerate(state.actors) if a.active))
        for field in ("swaps", "wind_count", "undo_count", "undo_head", "anim_left",
                      "micro_phase", "controls_buffer", "select_repeat", "undo_repeat"):
            self.write(field, 0)
        self.write("scene", 1)
        self.previous = 0
        return state

    def physics_fixtures(self):
        def prepared(x=8, y=4, motion=1, first=FLOOR, second=None):
            board = [FLOOR] * (WIDTH * HEIGHT)
            board[7 * WIDTH + 16] = NEST
            heading = direction(motion)
            dx, dy = STEP[heading]
            nx, ny = x + dx, y + dy
            if 0 <= nx < WIDTH and 0 <= ny < HEIGHT:
                board[ny * WIDTH + nx] = first
                if second is not None:
                    heading2 = SLASH_TURN[heading] if first == SLASH else (
                        BACKSLASH_TURN[heading] if first == BACKSLASH else heading)
                    dx2, dy2 = STEP[heading2]
                    board[(ny + dy2) * WIDTH + nx + dx2] = second
            return Level("fixture", "", tuple(board), (Actor(0, x, y, motion),), (), "")

        cases = []
        for motion in range(1, 9):
            for tile in (FLOOR, WALL, SLASH, BACKSLASH, SLOWGLASS):
                cases.append((f"motion {motion}, tile {tile}", prepared(motion=motion, first=tile)))
        for motion in range(5, 9):
            for first in (FLOOR, SLASH, BACKSLASH):
                cases.append((f"fast {motion}, first {first}, then glass",
                              prepared(motion=motion, first=first, second=SLOWGLASS)))
        for motion, x, y in ((1, 17, 4), (2, 8, 8), (3, 0, 4), (4, 8, 0)):
            for speed in (0, 4):
                cases.append((f"boundary {motion + speed}", prepared(x, y, motion + speed)))
        for name, level in cases:
            start = self.fixture(level)
            before, _ = self.beat()
            self.match(wind(level, start), name)
            self.undo(before)
            self.match(start, name + " undo")
            self.fixture_results.append(name)
        # A press during interpolation must be buffered, then execute once.
        level = prepared()
        start = self.fixture(level)
        self.tick(1, pressed=1)
        self.tick(16, pressed=16)
        state = self.state()
        self.check(state["spool"] == 0 and state["controls_buffer"] == 16,
                   "exchange waits during animation", state)
        for _ in range(80):
            if not self.state()["anim_left"]:
                break
            self.tick()
        self.match(swap(level, wind(level, start), 0), "buffered exchange executes at rest")
        self.check(self.state()["swaps"] == 1, "buffered exchange occurs once")
        # Help freezes an in-flight animation, including its pending fast step.
        level = prepared(motion=5, first=SLASH)
        self.fixture(level)
        self.tick(1, pressed=1)
        before = self.state()
        self.tick(menu=4)
        self.idle(12)
        after = self.state()
        self.check(after["snapshot"] == before["snapshot"] and
                   after["anim_left"] == before["anim_left"], "help freezes animation")
        self.tick(menu=4)
        for _ in range(80):
            if not self.state()["anim_left"]:
                break
            self.tick()
        self.match(wind(level, initial_state(level)), "help resumes second fast microstep")
        # Bounded counters and equal-motion no-ops must not corrupt history.
        level = prepared()
        self.fixture(level)
        self.write("wind_count", 65535)
        self.beat()
        self.check(self.state()["wind_count"] == 0, "16-bit wind counter wraps safely")
        self.fixture(level)
        self.write("swaps", 255)
        self.exchange(0)
        self.check(self.state()["swaps"] == 255, "swap counter saturates")
        self.fixture(level, replace(initial_state(level), spool=1))
        before = self.state()
        self.exchange(0)
        self.check(self.state()["snapshot"] == before["snapshot"] and
                   self.state()["undo_count"] == 0, "equal motion exchange is harmless")
        self.log.append(f"{len(cases)} prepared physics/undo cases plus buffered/help/counter cases passed.")

    def history(self):
        # A normal room with an unmoving pearl cannot complete while its bell winds.
        self.write("room_index", 0)
        self.tick(menu=2)
        snapshots = []
        expected = initial_state(authored_levels()[0])
        for _ in range(40):
            snapshots.append(self.state())
            self.beat()
            expected = wind(authored_levels()[0], expected)
            self.match(expected, "history wind")
        self.check(self.state()["undo_count"] == 32, "history capacity is bounded")
        for snapshot in reversed(snapshots[-32:]):
            self.undo(snapshot)
        self.check(self.state()["undo_count"] == 0, "all retained history restored")
        final = self.state()
        self.idle(8)
        self.tick(2, pressed=2)
        self.check(self.state()["snapshot"] == final["snapshot"], "empty undo is harmless")
        self.log.append("40 beats overflowed the 32-slot undo ring; all retained records restored.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=6561)
    parser.add_argument("--model", choices=("pal", "ntsc", "oldntsc"), default="pal")
    parser.add_argument("--program", type=Path, default=ROOT / "build/borrowed-motion.prg")
    parser.add_argument("--labels", type=Path, default=ROOT / "build/motion/borrowed-motion.lbl")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--skip-fixtures", action="store_true")
    parser.add_argument("--cold-only", action="store_true")
    parser.add_argument("--fast", action="store_true", help="use 1000%% host emulation speed; restore afterward")
    args = parser.parse_args()
    output = args.output or ROOT / f"build/motion/{args.model}-verification.json"
    report = {"model": args.model, "port": args.port,
              "program_sha256": hashlib.sha256(args.program.read_bytes()).hexdigest(),
              "input_method": "normalized controls after real CIA poll; no PC override",
              "host_speed_override": 1000 if args.fast else None,
              "limitations": "Emulator game checks; no physical keyboard, real hardware, or enjoyment proof."}
    validator = None
    old_speed = None
    with ViceMonitor(port=args.port, timeout=10) as monitor:
        try:
            validator = Validator(monitor, read_labels(args.labels), args.model)
            validator.cold(args.program)
            if args.fast:
                old_speed = monitor.resource_get("Speed")
                monitor.resource_set("Speed", 1000)
            validator.pacing()
            if not args.cold_only:
                validator.progression()
                if not args.skip_fixtures:
                    validator.physics_fixtures()
                    validator.history()
            report["passed"] = True
        except Exception as error:
            report["passed"] = False
            report["failure"] = str(error)
            raise
        finally:
            if old_speed is not None:
                monitor.resource_set("Speed", old_speed)
            if validator:
                report.update(checks=validator.checks, injected_ticks=validator.ticks,
                              levels=validator.level_results, prepared_physics=validator.fixture_results,
                              notes=validator.log, final_state=validator.state())
                validator.close()
            else:
                monitor.resume()
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(report, indent=2) + "\n")
            print(f"Report: {output}", flush=True)
    print(f"PASS: {report['checks']} checks, {report['injected_ticks']} gameplay ticks", flush=True)


if __name__ == "__main__":
    main()
