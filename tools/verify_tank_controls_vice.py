#!/usr/bin/env python3
"""Exercise Ironveil's simplified controls in a fresh local VICE instance.

Start the distributed PRG normally with tools/run_vice.py and a monitor port,
then run this script with --port. It injects keyboard scan results immediately
after the actual CIA scan, and joystick samples at the shared decoder's entry.
The compiled input, menu, physics, and firing code execute normally. There is
no program-counter override, artificial actor placement, or game-state jump.
This does not establish host keyboard rollover or electrical joystick behavior.
The owned checkpoints are removed and the game resumes at setup on success.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct

from vice_monitor import ViceMonitor

ROOT = Path(__file__).resolve().parents[1]
REGIONS = {"pal": 0, "ntsc": 1, "oldntsc": 2}
KEYS = (((1, 2), (1, 32), (1, 4), (2, 4), (2, 128)),
        ((3, 64), (4, 128), (3, 16), (4, 16), (5, 16)))


def verify(port, model):
    labels = {p[2].lstrip("."): int(p[1], 16)
              for line in (ROOT / "build/tanks/ironveil.lbl").read_text().splitlines()
              if len(p := line.split()) == 3 and p[0] == "al"}
    program = (ROOT / "dist/ironveil.prg").read_bytes()
    code = program[2:]
    scan_call = bytes((0x20, labels["scan_keyboard"] & 255,
                       labels["scan_keyboard"] >> 8))
    scan_offset = code.index(scan_call, labels["duel_input_poll"] - 0x801,
                             labels["duel_menu_poll"] - 0x801)
    after_scan = 0x801 + scan_offset + 3
    checks = []
    report = {"model": model, "port": port,
              "sha256": hashlib.sha256(program).hexdigest(), "checks": checks,
              "method": "Normal autostart; simulated scan/joystick samples; no PC override or actor/game-state preparation."}
    with ViceMonitor(port=port, timeout=10) as monitor:
        owned = []

        def read(name, size=1):
            return monitor.memread(labels[name], size)

        def write(name, values):
            monitor.memwrite(labels[name], bytes(values))

        def check(name, condition):
            checks.append({"name": name, "passed": bool(condition)})
            if not condition:
                raise AssertionError(f"{name}; state={list(read('game_state'))}, ready={list(read('ready', 2))}, input={list(read('dual_controls', 2))}")

        def sample(raw0=0, raw1=0, pause=False):
            for _ in range(20):
                monitor.events.clear()
                monitor.resume()
                pc = struct.unpack_from("<H", monitor.wait_event(0x62, timeout=10).body)[0]
                if pc == after_scan:
                    matrix = [0] * 8
                    for player, raw in enumerate((raw0, raw1)):
                        for bit, (column, row) in enumerate(KEYS[player]):
                            if raw & (1 << bit):
                                matrix[column] |= row
                    if pause:
                        matrix[7] |= 1
                    write("input_matrix", matrix)
                elif pc == labels["decode_joystick"]:
                    if read("input_mode") == b"\x01":
                        player = monitor.registers()["X"]
                        monitor.set_registers({"A": (raw0, raw1)[player]})
                elif pc == labels["controls_sampled"]:
                    return tuple(read("dual_controls", 2))
            raise RuntimeError("Input checkpoints were not reached")

        def menu(bits):
            # The menu's scan output is a control fixture, like the live matrix.
            write("menu_raw", [bits])

        def positions():
            return read("tank_xlo", 2) + read("tank_xhi", 2) + read("tank_y", 2) + read("tank_xfrac", 2) + read("tank_yfrac", 2)

        def await_match():
            for _ in range(180):
                if read("game_state") == b"\x01":
                    return
                sample()
            raise RuntimeError("The normal match-loading transition did not finish")

        try:
            check("cold setup", read("game_state") == b"\x00")
            check("regional startup", read("video_standard") == bytes([REGIONS[model]]))
            check("normal load matches distributed PRG", monitor.memread(0x801, len(code)) == code)
            check("default keyboard PvP setup", read("input_mode") == b"\x00" and read("computer_player2") == b"\x00")
            owned = [monitor.checkpoint(address) for address in
                     (after_scan, labels["decode_joystick"], labels["controls_sampled"])]
            sample()
            check("hold both fire keys without a shot", sample(16, 16) == (0, 0))
            menu(2)
            check("held fire blocks new-map command", sample(16, 16) == (0, 0) and read("new_world_request") == b"\x00")
            check("held buttons do not ready", read("ready", 2) == bytes((0, 0)))
            check("cyan release emits one ready pulse", sample(0, 16) == (16, 0))
            sample(0, 16)
            check("one ready player waits for the other", read("ready", 2) == bytes((1, 0)) and read("game_state") == b"\x00")
            check("gold release emits one ready pulse", sample() == (0, 16))
            sample()
            await_match()
            check("both releases start the match naturally", read("game_state") == b"\x01")
            before, old_hulls, old_turrets = positions(), read("hull", 2), read("turret", 2)
            for _ in range(10):
                check("held fire maps left/right to turret only", sample(24, 20) == (64, 32))
            check("aim holds both tanks stationary", positions() == before)
            check("aim leaves both hulls unchanged", read("hull", 2) == old_hulls)
            check("aim turns both turrets", all(a != b for a, b in zip(read("turret", 2), old_turrets)))
            check("held fire never shoots", read("shell_cooldown", 2) == bytes(2) and read("reveal", 2) == bytes(2))
            check("both releases produce exactly one fire pulse", sample() == (16, 16))
            check("next sample clears both fire pulses", sample() == (0, 0))
            check("both release shots reach the firing code", read("shell_cooldown", 2) == bytes((25, 25)) and read("reveal", 2) == bytes((50, 50)))
            for _ in range(10):
                check("neutral input never repeats a shot", sample() == (0, 0))
            check("cooldowns count down without another shot", read("shell_cooldown", 2) == bytes((15, 15)))
            sample(16, 16, pause=True)
            sample(16, 16)
            check("keyboard pause works while fire is held", read("game_state") == b"\x03")
            paused_cooldown = read("shell_cooldown", 2)
            paused = positions() + read("turret", 2) + read("shell_cooldown", 2) + read("seconds_left", 2)
            for _ in range(10):
                sample(20, 24)
            check("pause freezes motion, aiming and cooldown", positions() + read("turret", 2) + read("shell_cooldown", 2) + read("seconds_left", 2) == paused)
            sample()
            sample()
            check("release while paused does not shoot", read("shell_cooldown", 2) == paused_cooldown)
            sample(pause=True)
            sample()
            check("pause key resumes normally", read("game_state") == b"\x01")
            check("resume does not create a stale shot", read("shell_cooldown", 2) == bytes(max(0, value - 1) for value in paused_cooldown))
            x0 = int.from_bytes(bytes((read("tank_xfrac")[0], read("tank_xlo")[0], read("tank_xhi")[0])), "little")
            x1 = int.from_bytes(bytes((read("tank_xfrac", 2)[1], read("tank_xlo", 2)[1], read("tank_xhi", 2)[1])), "little")
            y = read("tank_y", 2) + read("tank_yfrac", 2)
            for _ in range(20):
                sample(8, 4)
            sample()
            now0 = int.from_bytes(bytes((read("tank_xfrac")[0], read("tank_xlo")[0], read("tank_xhi")[0])), "little")
            now1 = int.from_bytes(bytes((read("tank_xfrac", 2)[1], read("tank_xlo", 2)[1], read("tank_xhi", 2)[1])), "little")
            check("map-relative movement resumes east/west", now0 > x0 and now1 < x1 and read("tank_y", 2) + read("tank_yfrac", 2) == y and read("hull", 2) == bytes((2, 6)))
            sample(pause=True)
            sample()
            check("pause before new map", read("game_state") == b"\x03")
            menu(2)
            sample()
            sample()
            check("new map returns to setup", read("game_state") == b"\x00")
            menu(16)  # J: ordinary joystick selection, clearing readiness.
            sample()
            check("joystick mode selection", read("input_mode") == b"\x01")
            check("joystick hold also does not fire", sample(16, 16) == (0, 0))
            check("joystick aiming shares button behavior", sample(20, 24) == (32, 64))
            check("joystick release creates the same ready pulse", sample(0, 16) == (16, 0))
            sample(0, 16)
            check("joystick ready waits for second player", read("ready", 2) == bytes((1, 0)) and read("game_state") == b"\x00")
            # Release gold to start, then return through the ordinary pause/new-
            # map flow before switching back to keyboard.
            sample()
            sample()
            await_match()
            check("joystick releases also start normally", read("game_state") == b"\x01")
            menu(1)
            sample()
            sample()
            check("joystick pause", read("game_state") == b"\x03")
            menu(2)
            sample()
            sample()
            check("joystick new map returns to setup", read("game_state") == b"\x00")
            menu(8)
            sample()
            check("keyboard selection restores setup", read("input_mode") == b"\x00" and read("ready", 2) == bytes(2))
            check("device switch produces no stale fire", sample() == (0, 0) and read("fire_button_previous", 2) == bytes(2))
            report["passed"] = len(checks)
            return report
        finally:
            for checkpoint in owned:
                monitor.delete_checkpoint(checkpoint)
            monitor.resume()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--model", choices=REGIONS, default="pal")
    args = parser.parse_args()
    report = verify(args.port, args.model)
    output = ROOT / f"build/tanks/simple-controls-vice-{args.model}.json"
    output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS {report['passed']} live VICE checks ({args.model}); returned to keyboard setup. Report: {output}")


if __name__ == "__main__":
    main()
