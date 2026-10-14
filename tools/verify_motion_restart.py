#!/usr/bin/env python3
"""Regression checks for Borrowed Motion's complete room restart.

Use a dedicated disposable VICE instance: this tool unlocks rooms, plays them,
and changes their state. It never changes PC, loads a program, or connects to
any port except the explicit --port. Ordinary gameplay commands are injected
after input_poll. Separate matrix cases inject scan results at input_poll's
menus label, before its real ghost guard and menu-edge decoding. Neither method
establishes physical keyboard operation or Mac keyboard rollover.

The normally loaded image must match --program and its labels. A fresh room's
canonical state, visible screen/color RAM, and enabled sprite coordinates are
compared after several restart situations. Unlocked rooms, best scores, music
phase and decorative sprite animation frames intentionally persist. Disabled
sprite registers and unused goal-array tails are not visible game state.

Example (after launching a separate matching VICE instance):
  python3 tools/verify_motion_restart.py --port 6567 --model pal --fast

--skip-help omits the help-page restart comparisons.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct

from generate_motion_levels import (
    authored_levels, initial_state, swap, wind, won,
)
from verify_motion import Validator, read_labels
from vice_monitor import ViceMonitor

ROOT = Path(__file__).resolve().parents[1]
SCALARS = ("scene", "room_index", "selected", "pocket", "settled", "swaps",
           "actor_count", "goal_count", "goal_used", "pearl_count", "anim_left",
           "micro_phase", "undo_count", "undo_head", "controls_buffer",
           "clear_age", "select_repeat", "undo_repeat", "fx_life", "hud_dirty",
           "preview_valid")
ARRAYS = ("actor_x", "actor_y", "actor_motion", "actor_active", "actor_type",
          "old_x", "old_y", "fast_pending")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def matrix_for(keys):
    """Passive switch network, PA/PB coordinates; includes phantom closures.

    Each scan grounds one PA column. Every PB pin in its connected component
    reads low. The returned bytes use the driver's positive pressed-bit form.
    No joystick is connected in these particular matrix fixtures.
    """
    graph = [set() for _ in range(16)]
    for column, row in keys:
        graph[column].add(8 + row)
        graph[8 + row].add(column)
    matrix = []
    for column in range(8):
        reached, frontier = {column}, [column]
        while frontier:
            for node in graph[frontier.pop()]:
                if node not in reached:
                    reached.add(node)
                    frontier.append(node)
        matrix.append(sum(1 << row for row in range(8) if 8 + row in reached))
    return bytes(matrix)


class RestartChecks:
    def __init__(self, monitor, labels, model):
        self.v = Validator(monitor, labels, model)
        self.m, self.l = monitor, labels
        self.results = []
        self.baselines = []
        self.matrix_results = []
        self.failures = []
        self.extra_checks = 0

    def require(self, condition, message, detail=None):
        self.extra_checks += 1
        if not condition:
            raise AssertionError(f"{message}: {detail}")

    def loaded_image(self, path, model):
        data = path.read_bytes()
        self.require(data[:2] == b"\x01\x08", "expected PRG load address")
        self.require(self.m.memread(0x0801, len(data) - 2) == data[2:],
                     "running image differs from PRG; reload matching build and labels")
        actual = self.v.state()["video_standard"]
        self.require(actual == {"pal": 0, "ntsc": 1, "oldntsc": 2}[model],
                     "video standard matches requested model", actual)

    def fresh_room(self, number):
        # Normal scene handlers leave help, ending or a room. Every room is
        # available from the title, including after a fresh launch.
        # A genuine restart consumes one neutral release tick before commands.
        self.v.tick()
        for _ in range(4):
            if self.v.state()["scene"] == 0:
                break
            self.v.tick(menu=8)
            self.v.tick()
        self.require(self.v.state()["scene"] == 0, "reached title for canonical load")
        for _ in range(len(authored_levels()) + 1):
            current = self.v.state()["room_index"]
            if current == number:
                break
            direction = 8 if current < number else 4
            self.v.tick(direction, pressed=direction)
            self.v.tick()
        self.require(self.v.state()["room_index"] == number, "selected requested room", number)
        self.v.tick(menu=1)
        self.require(self.v.state()["scene"] == 1, "fresh load enters play")
        return self.capture()

    def capture(self):
        low = self.l["__BSS_RUN__"]
        memory = self.m.memread(low, self.l["__BSS_SIZE__"])

        def block(name, size=1):
            offset = self.l[name] - low
            return memory[offset:offset + size]

        state = {name: block(name)[0] for name in SCALARS}
        state["wind_count"] = int.from_bytes(block("wind_count", 2), "little")
        for name in ARRAYS:
            state[name] = list(block(name, 6))
        state["goal_x"] = list(block("goal_x", state["goal_count"]))
        state["goal_y"] = list(block("goal_y", state["goal_count"]))
        state["room_map"] = block("room_map", 18 * 9).hex()
        state["undo_state"] = block("state_begin", self.l["state_end"] - self.l["state_begin"]).hex()
        if state["preview_valid"]:
            state["preview_x"] = block("preview_x")[0]
            state["preview_y"] = block("preview_y")[0]
        vic = self.m.memread(0xd000, 0x16)
        sprites = {str(slot): [vic[slot * 2] + (256 if vic[0x10] & (1 << slot) else 0),
                              vic[slot * 2 + 1]]
                   for slot in range(8) if vic[0x15] & (1 << slot)}
        return {"state": state, "sprites": sprites,
                "screen": self.m.memread(0x8000, 1000),
                "colors": bytes(value & 15 for value in self.m.memread(0xd800, 1000))}

    @staticmethod
    def byte_differences(expected, actual):
        cells = [i for i, (a, b) in enumerate(zip(expected, actual)) if a != b]
        return {"count": len(cells), "examples": [
            {"row": i // 40, "column": i % 40,
             "expected": expected[i], "actual": actual[i]} for i in cells[:16]]}

    def compare(self, canonical, room, phase):
        actual = self.capture()
        differences = {}
        names = canonical["state"].keys() | actual["state"].keys()
        for name in sorted(names):
            before, after = canonical["state"].get(name), actual["state"].get(name)
            self.extra_checks += 1
            if before != after:
                differences[name] = {"expected": before, "actual": after}
        self.extra_checks += 3
        if canonical["sprites"] != actual["sprites"]:
            differences["enabled_sprite_coordinates"] = {
                "expected": canonical["sprites"], "actual": actual["sprites"]}
        for name in ("screen", "colors"):
            if canonical[name] != actual[name]:
                differences[name] = self.byte_differences(canonical[name], actual[name])
        result = {"room": room + 1, "phase": phase, "passed": not differences,
                  "differences": differences, "screen_sha256": digest(actual["screen"]),
                  "color_sha256": digest(actual["colors"])}
        self.results.append(result)
        if differences:
            self.failures.append(result)
        print(f"Room {room + 1} {phase}: {'PASS' if not differences else 'FAIL'}", flush=True)
        return not differences

    def restart(self, canonical, room, phase):
        self.v.tick(menu=2)
        result = self.compare(canonical, room, phase)
        self.v.tick()  # consume the restart release latch before another action
        return result

    def play_until(self, level, predicate):
        expected = initial_state(level)
        self.v.match(expected, "restart scenario begins in authored state")
        for operation, value in level.solution:
            count = value if operation == "wind" else 1
            for _ in range(count):
                if operation == "wind":
                    self.v.beat()
                    expected = wind(level, expected)
                else:
                    self.v.exchange(value)
                    expected = swap(level, expected, value)
                self.v.match(expected, "restart scenario follows independent model")
                if predicate(expected):
                    return expected
        raise AssertionError("authored solution did not reach requested restart scenario")

    def prepare_pocket(self, level):
        return self.play_until(level, lambda state: state.pocket != 0)

    def all_rooms(self, skip_help):
        for number, level in enumerate(authored_levels()):
            canonical = self.fresh_room(number)
            self.v.match(initial_state(level), "canonical room matches authored state")
            self.baselines.append({"room": number + 1, "name": level.name,
                                   "state": canonical["state"], "sprites": canonical["sprites"],
                                   "screen_sha256": digest(canonical["screen"]),
                                   "color_sha256": digest(canonical["colors"])})
            for _ in range(3):
                self.v.beat()
            self.restart(canonical, number, "after_movement")

            self.fresh_room(number)
            self.prepare_pocket(level)
            self.restart(canonical, number, "with_motion_in_pocket")

            self.fresh_room(number)
            self.play_until(level, lambda state: state.nests_used != 0)
            self.restart(canonical, number, "after_first_settlement")

            self.fresh_room(number)
            self.v.tick(1, pressed=1)
            self.require(self.v.state()["anim_left"] > 0, "first microstep is animating")
            self.v.tick(16, pressed=16)
            self.require(self.v.state()["controls_buffer"] & 16,
                         "exchange is buffered during animation")
            self.restart(canonical, number, "during_animation_with_buffered_exchange")

            if any(actor.motion > 4 for actor in level.actors):
                self.fresh_room(number)
                self.v.tick(1, pressed=1)
                for _ in range(80):
                    if self.v.state()["micro_phase"] == 2:
                        break
                    self.v.tick()
                self.require(self.v.state()["micro_phase"] == 2,
                             "fast fixture reaches second microstep")
                self.v.tick(16, pressed=16)
                self.restart(canonical, number, "during_second_fast_microstep")

            self.fresh_room(number)
            self.play_until(level, won)
            self.require(self.v.state()["scene"] == 3, "solution enters completed scene")
            self.restart(canonical, number, "immediately_after_completion")

            if not skip_help:
                self.fresh_room(number)
                self.prepare_pocket(level)
                self.v.tick(menu=4)
                self.require(self.v.state()["scene"] == 2, "help opened from play")
                self.restart(canonical, number, "from_help_with_changed_room")

                self.fresh_room(number)
                self.play_until(level, won)
                self.v.tick(menu=4)
                self.require(self.v.state()["scene"] == 2, "help opened from completion")
                self.restart(canonical, number, "from_help_after_completion")

    def matrix_sample(self, matrix, raw_controls, previous_menu=0):
        """Run actual menu decoding, then consume its result in game_tick."""
        checkpoint = self.m.checkpoint(self.l["menus"])
        self.v.owned.append(checkpoint)
        try:
            self.m.events.clear()
            self.m.resume()
            event = self.m.wait_event(0x62, timeout=30)
            pc = struct.unpack_from("<H", event.body)[0]
            self.require(pc == self.l["menus"], "stopped at actual menu decoding", hex(pc))
            normalized = raw_controls
            if normalized & 3 == 3:
                normalized &= ~3
            if normalized & 12 == 12:
                normalized &= ~12
            self.v.write("input_matrix", matrix)
            self.v.write("raw_controls", raw_controls)
            self.v.write("input_controls", normalized)
            self.v.write("menu_keys", 0)
            self.v.write("previous_controls", 0)
            self.v.write("previous_menu", previous_menu)
        finally:
            self.m.delete_checkpoint(checkpoint)
            self.v.owned.remove(checkpoint)
        self.v.stop_next()
        decoded = {name: self.m.memread(self.l[name], 1)[0] for name in
                   ("input_controls", "input_pressed", "menu_keys", "menu_pressed", "raw_controls")}
        self.require(self.m.memread(self.l["input_matrix"], 8) == matrix,
                     "menu chord detection preserves the original scan matrix")
        self.require(decoded["raw_controls"] == raw_controls and
                     decoded["input_controls"] == normalized,
                     "menu chord detection preserves raw and normalized controls", decoded)
        self.v.stop_next()
        self.v.ticks += 2
        self.v.previous = normalized
        return decoded

    def raw_tick(self, raw, normalized):
        """Prepared held input for the engine's release latch, without menu keys."""
        self.m.memwrite(self.l["input_controls"], bytes((normalized, 0, 0, 0)))
        self.v.write("raw_controls", raw)
        self.v.stop_next()
        self.v.ticks += 1
        self.v.previous = normalized

    def matrix_cases(self):
        # Room 6 is the reported case; these fixtures retain its real authored
        # objects, rather than preparing artificial actor positions.
        room = 5
        level = authored_levels()[room]
        canonical = self.fresh_room(room)
        self.prepare_pocket(level)
        decoded = self.matrix_sample(matrix_for([(2, 1)]), 0)
        self.require(decoded["menu_pressed"] == 2, "R alone decodes to restart", decoded)
        self.compare(canonical, room, "matrix_R_alone")
        self.matrix_results.append({"case": "R alone", "decoded": decoded})

        self.fresh_room(room)
        self.prepare_pocket(level)
        before = self.v.state()
        decoded = self.matrix_sample(matrix_for([(2, 1)]), 0, previous_menu=2)
        self.require(decoded["menu_pressed"] == 0, "held R does not create a second edge", decoded)
        self.require(self.v.state()["snapshot"] == before["snapshot"],
                     "held R preserves the changed puzzle")
        self.matrix_results.append({"case": "R held after its first edge", "decoded": decoded})

        self.fresh_room(room)
        self.prepare_pocket(level)
        before = self.v.state()
        ghost = matrix_for([(1, 1), (1, 2), (2, 2)])  # W, A, D; R is unpressed.
        self.require(ghost[2] & 2, "electrical fixture contains phantom R")
        decoded = self.matrix_sample(ghost, 1 | 4 | 8)
        self.require(decoded["menu_pressed"] == 0, "W+A+D phantom R stays blocked", decoded)
        self.require(self.v.state()["pocket"] == before["pocket"] and
                     self.v.state()["swaps"] == before["swaps"],
                     "ghost chord does not restart room")
        self.matrix_results.append({"case": "W+A+D with phantom R", "matrix": list(ghost),
                                    "decoded": decoded})

        self.fresh_room(room)
        self.prepare_pocket(level)
        before = self.v.state()
        ghost = matrix_for([(1, 1), (1, 6), (2, 6)])  # W, E, T; R is unpressed.
        self.require(ghost[2] & 2, "second electrical fixture contains phantom R")
        decoded = self.matrix_sample(ghost, 1)
        self.require(decoded["menu_pressed"] == 0, "W+E+T phantom R stays blocked", decoded)
        self.require(self.v.state()["pocket"] == before["pocket"] and
                     self.v.state()["swaps"] == before["swaps"],
                     "second ghost chord does not restart room")
        self.matrix_results.append({"case": "W+E+T with phantom R", "matrix": list(ghost),
                                    "decoded": decoded})

        self.fresh_room(room)
        self.prepare_pocket(level)
        decoded = self.matrix_sample(matrix_for([(1, 1), (2, 1)]), 1)
        self.require(decoded["menu_pressed"] == 2, "R+W safely decodes restart", decoded)
        self.compare(canonical, room, "matrix_R_with_W")
        self.require(self.m.memread(self.l["restart_wait"], 1)[0] == 1,
                     "restart arms release latch")
        for _ in range(4):
            self.raw_tick(1, 1)
        # Opposing directions normalize to zero but still represent held keys.
        self.raw_tick(3, 0)
        self.raw_tick(12, 0)
        self.require(self.m.memread(self.l["restart_wait"], 1)[0] == 1,
                     "held and canceled directions retain release latch")
        self.compare(canonical, room, "restart_wait_with_held_and_opposing_keys")
        self.raw_tick(0, 0)
        self.require(self.m.memread(self.l["restart_wait"], 1)[0] == 0,
                     "fully released controls clear restart latch")
        self.compare(canonical, room, "neutral_release_tick_consumed")
        self.v.tick(1, pressed=1)
        self.require(self.v.state()["wind_count"] == 1 and self.v.state()["anim_left"] > 0,
                     "new W press works after release")
        self.matrix_results.append({"case": "R+W accepted; full release required before new movement",
                                    "decoded": decoded})
        # Finish on the canonical room using the real decoded restart event.
        self.matrix_sample(matrix_for([(2, 1)]), 0)
        self.compare(canonical, room, "matrix_R_after_gameplay_release")
        self.v.tick()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--model", choices=("pal", "ntsc", "oldntsc"), default="pal")
    parser.add_argument("--labels", type=Path, default=ROOT / "build/motion/borrowed-motion.lbl")
    parser.add_argument("--program", type=Path, default=ROOT / "build/borrowed-motion.prg")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--fast", action="store_true", help="temporarily run at 1000%% host speed")
    parser.add_argument("--skip-help", action="store_true", help="omit known old-build help restart failure")
    args = parser.parse_args()
    output = args.output or ROOT / f"build/motion/{args.model}-restart-verification.json"
    report = {"model": args.model, "port": args.port,
              "program_sha256": digest(args.program.read_bytes()), "skip_help": args.skip_help,
              "limitations": "Dedicated emulator fixtures; no physical keyboard or real hardware claim.",
              "setup_mutation": "Unlock ceiling set to room 10; rooms selected through title controls.",
              "matrix_method": "Passive switch model injected after scan, before actual menu guard/edges.",
              "host_speed_override": 1000 if args.fast else None}
    checks = None
    old_speed = None
    error = None
    with ViceMonitor(port=args.port, timeout=10) as monitor:
        try:
            checks = RestartChecks(monitor, read_labels(args.labels), args.model)
            checks.loaded_image(args.program, args.model)
            if args.fast:
                old_speed = monitor.resource_get("Speed")
                monitor.resource_set("Speed", 1000)
            checks.all_rooms(args.skip_help)
            checks.matrix_cases()
            report["passed"] = not checks.failures
        except Exception as exc:
            error = exc
            report["passed"] = False
            report["infrastructure_or_scenario_failure"] = str(exc)
        finally:
            if old_speed is not None:
                monitor.resource_set("Speed", old_speed)
            if checks:
                report.update(canonical_rooms=checks.baselines, restart_cases=checks.results,
                              matrix_cases=checks.matrix_results, failures=checks.failures,
                              checks=checks.v.checks + checks.extra_checks,
                              gameplay_ticks=checks.v.ticks)
                checks.v.close()
            else:
                monitor.resume()
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(report, indent=2) + "\n")
            print(f"Report: {output}", flush=True)
    if error is not None:
        raise error
    if not report["passed"]:
        raise SystemExit(f"FAIL: {len(report['failures'])} restart scenarios differ from canonical state")
    print(f"PASS: {len(report['restart_cases'])} restart scenarios and "
          f"{len(report['matrix_cases'])} menu-decoding cases", flush=True)


if __name__ == "__main__":
    main()
