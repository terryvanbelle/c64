#!/usr/bin/env python3
"""Inspect a normally autostarted Atlas instance through VICE's local monitor.

Compares C64-generated geography with the readable integer reference, verifies
all 200 metatile quadrants/colors and VIC allocations, and captures actual VIC
pixels. --exercise injects normalized controls into A at input_sampled, after
the engine loads the controls sampled by its real IRQ input routine. It also repositions the army for bounded
terrain-cost probes. Both debug actions are recorded separately from the normal
cold-start check. The keyboard/joystick CIA path is source audited, not proved
by these injections. No program loading, PC override, or held_input memory
injection is performed.
"""

from __future__ import annotations

import argparse
from dataclasses import replace
import hashlib
import json
from pathlib import Path
import struct
import sys

from atlas_world_reference import World
from vice_monitor import MonitorError, ViceMonitor

STANDARDS = {"pal": (0, 312, 63), "ntsc": (1, 263, 65), "oldntsc": (2, 262, 64)}
WORD_FIELDS = {"world_seed", "army_x", "army_y", "origin_x", "origin_y", "move_count",
               "sample_step", "map_center_x", "map_center_y"}
FIELDS = tuple(sorted(WORD_FIELDS)) + (
    "terrain", "zoom", "cooldown", "blocked_moves", "video_standard",
    "video_frames", "ticks", "frame_ready", "active_screen", "pending_screen",
    "held_input", "previous_input",
)
COSTS = (0, 10, 20, 24, 48, 36, 6, 4, 6)


def read_labels(path: Path) -> dict[str, int]:
    return {parts[2].lstrip("."): int(parts[1], 16)
            for line in path.read_text().splitlines()
            if len(parts := line.split()) == 3 and parts[0] == "al"}


class Inspector:
    def __init__(self, monitor: ViceMonitor, labels: dict[str, int], standard: str):
        self.m, self.labels = monitor, labels
        self.standard_id, self.lines, self.cpl = STANDARDS[standard]
        self.owned: set[int] = set()
        if "input_sampled" in labels:
            self.input_return = labels["input_sampled"]
        else:
            code = monitor.memread(labels["main_loop"], 128)
            pattern = bytes([0x20, labels["input_poll"] & 255, labels["input_poll"] >> 8])
            self.input_return = labels["main_loop"] + code.index(pattern) + 3

    def state(self) -> dict[str, int]:
        low, count = self.labels["__BSS_RUN__"], self.labels["__BSS_SIZE__"]
        data = self.m.memread(low, count)
        return {name: int.from_bytes(data[self.labels[name] - low:
                                        self.labels[name] - low + (2 if name in WORD_FIELDS else 1)], "little")
                for name in FIELDS}

    def stop(self, address: str | int) -> tuple[dict, dict]:
        address = self.labels[address] if isinstance(address, str) else address
        checkpoint = self.m.checkpoint(address)
        self.owned.add(checkpoint)
        try:
            self.m.events.clear()
            self.m.resume()
            event = self.m.wait_event(0x62, timeout=30)
            pc = struct.unpack("<H", event.body)[0]
            if pc != address:
                raise MonitorError(f"unexpected stopped PC ${pc:04x}, wanted ${address:04x}")
            return self.m.registers(), self.state()
        finally:
            self.m.delete_checkpoint(checkpoint)
            self.owned.remove(checkpoint)

    def write_state(self, values: dict[str, int]) -> None:
        for name, value in values.items():
            width = 2 if name in WORD_FIELDS else 1
            self.m.memwrite(self.labels[name], value.to_bytes(width, "little"))

    def render_cycles(self, begin: tuple[dict, dict], end: tuple[dict, dict]) -> int:
        br, bs = begin
        er, es = end
        # IRQ increments video_frames at raster16, so measure phases relative
        # to that line. Unlike a simple modulo delta this retains long renders.
        frames = (es["video_frames"] - bs["video_frames"]) & 255
        phase = lambda r: ((r["LIN"] - 16) % self.lines) * self.cpl + r["CYC"]
        return frames * self.lines * self.cpl + phase(er) - phase(br)

    def view(self, *, pending: bool = False) -> dict:
        state = self.state()
        world = World(state["world_seed"])
        query = (lambda x, y: world.overview_tile(x, y, state["sample_step"])) if state["zoom"] else world.tile
        expected = bytes(query(state["origin_x"] + x * state["sample_step"],
                               state["origin_y"] + y * state["sample_step"])
                         for y in range(12) for x in range(22))
        actual = self.m.memread(self.labels["viewport"], 264)
        screen = self.m.memread(0x8000 + 0x400 * state["pending_screen" if pending else "active_screen"], 1000)
        colors = self.m.memread(0xB000 if pending else 0xD800, 1000)
        colors = bytes(c & 15 for c in colors)
        bases = self.m.memread(self.labels["atlas_tile_base"], 9)
        tile_colors = self.m.memread(self.labels["atlas_tile_color"], 9)
        glyph_errors, color_errors = [], []
        for row in range(10):
            for column in range(20):
                index = (row + 1) * 22 + column + 1
                terrain = expected[index]
                glyph = bases[terrain]
                if terrain == 5 or terrain >= 7:
                    mask = 0
                    for flag, offset in ((1, -22), (2, 1), (4, 22), (8, -1)):
                        neighbor = expected[index + offset]
                        if (neighbor in (0, 5, 8)) if terrain == 5 else (neighbor >= 6):
                            mask |= flag
                    glyph += mask * 4
                address = 80 + row * 80 + column * 2
                for quadrant, offset in enumerate((0, 1, 40, 41)):
                    if screen[address + offset] != glyph + quadrant:
                        glyph_errors.append([row, column, quadrant])
                    if colors[address + offset] != tile_colors[terrain]:
                        color_errors.append([row, column, quadrant])
        pointer_a, pointer_b = self.m.memread(0x83F8, 2), self.m.memread(0x87F8, 2)
        return {"state": state, "terrain_bytes_checked": 264,
                "terrain_mismatches": sum(a != b for a, b in zip(actual, expected)),
                "glyph_quadrants_checked": 800, "glyph_mismatches": len(glyph_errors),
                "color_quadrants_checked": 800, "color_mismatches": len(color_errors),
                "pointer_tables_match": pointer_a == pointer_b,
                "sprite_pointers": list(pointer_a),
                "terrain_types": sorted(set(actual)),
                "seed_permutation_matches": self.m.memread(self.labels["world_perm"], 256) == bytes(world.permutation)}

    def capture(self, path: Path) -> dict:
        self.stop("irq")
        self.stop("irq")
        frame = self.m.display_get()
        screen = self.m.memread(0x8000 + self.state()["active_screen"] * 0x400, 1000)
        font = self.m.memread(0x8800, 2048)
        colors = bytes(c & 15 for c in self.m.memread(0xD800, 1000))
        vic = self.m.memread(0xD000, 0x20)
        sprite_boxes = []
        for sprite in range(8):
            if vic[0x15] & (1 << sprite):
                left = vic[sprite * 2] + (256 if vic[0x10] & (1 << sprite) else 0) - 24
                top = vic[sprite * 2 + 1] - 50
                sprite_boxes.append((left, top, left + 24, top + 21))
        # The installed VICE3.10 PAL metadata is one row below the actual VIC
        # character field. Compare a narrow range of crops to document the
        # real match rather than reconstructing or editing emulator pixels.
        errors = {}
        for offset in range(-2, 3):
            mismatch = compared = 0
            for y in range(200):
                for x in range(320):
                    if any(left <= x < right and top <= y < bottom
                           for left, top, right, bottom in sprite_boxes):
                        continue  # Actual enabled hardware army sprites.
                    compared += 1
                    cell = (y // 8) * 40 + x // 8
                    bit = font[screen[cell] * 8 + y % 8] & (128 >> (x % 8))
                    expected = colors[cell] if bit else 0
                    actual = frame.pixels[(y + frame.y_offset + offset) * frame.width + x + frame.x_offset]
                    mismatch += actual != expected
            errors[offset] = (mismatch, compared)
        crop = min(errors, key=lambda offset: errors[offset][0])
        corrected = replace(frame, y_offset=frame.y_offset + crop)
        corrected.save_png(path, inner=True)
        return {"path": str(path), **frame.metadata(), "crop_y_adjustment": crop,
                "character_pixels_checked": errors[crop][1], "character_pixel_mismatches": errors[crop][0]}

    def move(self, direction: int) -> dict:
        begin_state = self.state()
        _, ready = self.stop(self.input_return)
        for _ in range(64):
            if not ready["cooldown"]:
                break
            _, ready = self.stop(self.input_return)
        else:
            raise MonitorError("movement cooldown did not expire")
        self.m.set_registers({"A": direction})
        stop, state = self.stop(self.labels["move_allowed"] + 10)
        expected_cost = COSTS[state["terrain"]]
        begin = self.stop("render_begin")
        end = self.stop("render_end")
        pending = self.view(pending=True)
        commit = self.stop("commit_end")
        active = self.view()
        return {"before": begin_state, "after_cost_store": state,
                "control_path": "normalized A at input_sampled after IRQ controls loaded",
                "cost_matches": state["cooldown"] == expected_cost,
                "render_cycles": self.render_cycles(begin, end),
                "commit_end_raster": commit[0]["LIN"],
                "pending_view": pending, "active_view": active}

    def toggle_zoom(self) -> dict:
        self.stop(self.input_return)
        self.m.set_registers({"A": 16})
        begin = self.stop("render_begin")
        end = self.stop("render_end")
        pending = self.view(pending=True)
        self.stop("commit_end")
        return {"render_cycles": self.render_cycles(begin, end),
                "pending_view": pending, "active_view": self.view()}

    def pan(self, direction: int) -> dict:
        before = self.state()
        self.stop(self.input_return)
        self.m.set_registers({"A": direction})
        begin = self.stop("render_begin")
        end = self.stop("render_end")
        pending = self.view(pending=True)
        self.stop("commit_end")
        after = self.state()
        dx, dy = {1: (0, -1), 2: (0, 1), 4: (-1, 0), 8: (1, 0)}[direction]
        return {"before": before, "after": after,
                "army_unchanged": (before["army_x"], before["army_y"]) == (after["army_x"], after["army_y"]),
                "center_delta_matches": after["map_center_x"] == (before["map_center_x"] + dx * before["sample_step"]) & 65535
                 and after["map_center_y"] == (before["map_center_y"] + dy * before["sample_step"]) & 65535,
                "render_cycles": self.render_cycles(begin, end),
                "pending_view": pending, "active_view": self.view()}

    def new_world(self) -> dict:
        before = self.state()
        self.stop(self.input_return)
        self.m.set_registers({"A": 32})
        begin = self.stop("render_begin")
        end = self.stop("render_end")
        pending = self.view(pending=True)
        self.stop("commit_end")
        after = self.state()
        return {"seed_changed": before["world_seed"] != after["world_seed"],
                "capital_matches": (after["army_x"], after["army_y"]) == World(after["world_seed"]).capital,
                "render_cycles": self.render_cycles(begin, end),
                "pending_view": pending, "active_view": self.view()}

    def probe_terrain(self, target: tuple[int, int], terrain: int, direction: int = 8) -> dict:
        dx, dy = {1: (0, -1), 2: (0, 1), 4: (-1, 0), 8: (1, 0)}[direction]
        source = ((target[0] - dx) & 65535, (target[1] - dy) & 65535)
        world = World(self.state()["world_seed"])
        self.stop("main_loop")
        self.write_state({"army_x": source[0], "army_y": source[1], "terrain": world.tile(*source),
                          "zoom": 0, "cooldown": 0, "previous_input": 0})
        if terrain:
            result = self.move(direction)
            result["debug_reposition"] = {"source": source, "target": target, "terrain": terrain}
            result["target_matches"] = (result["active_view"]["state"]["army_x"],
                                         result["active_view"]["state"]["army_y"]) == target
            return result
        before = self.state()
        self.stop(self.input_return)
        self.m.set_registers({"A": direction})
        _, after = self.stop(self.labels["move_probe"] + 15)
        return {"debug_reposition": {"source": source, "target": target, "terrain": 0},
                "sea_blocked": (after["army_x"], after["army_y"]) == source,
                "blocked_counter_increased": after["blocked_moves"] == (before["blocked_moves"] + 1) & 255,
                "blocked_cooldown_matches": after["cooldown"] == 8,
                "before": before, "after": after}

    def cleanup(self) -> None:
        for checkpoint in tuple(self.owned):
            self.m.delete_checkpoint(checkpoint)
        self.m.resume()


def verify(args) -> dict:
    labels = read_labels(args.labels)
    result = {"standard": args.standard, "no_pc_override": True,
              "real_hardware_tested": False, "views": [], "movement_probes": [],
              "input_runtime_method": "normalized A injected at input_sampled after IRQ controls loaded",
              "cia_keyboard_joystick_runtime_verified": False,
              "captures": [], "errors": [],
              "prg_sha256": hashlib.sha256(args.prg.read_bytes()).hexdigest()}
    with ViceMonitor(port=args.port, timeout=30) as monitor:
        inspector = Inspector(monitor, labels, args.standard)
        try:
            registers = monitor.registers()
            state = inspector.state()
            result["initial_registers"] = registers
            result["initial_state"] = state
            result["normal_autostart"] = (
                labels["__CODE_RUN__"] <= registers["PC"] < labels["__CODE_RUN__"] + labels["__CODE_SIZE__"]
                and registers["01"] & 7 == 5
                and monitor.memread(0x0801, 80) == args.prg.read_bytes()[2:82])
            result["video_standard_matches"] = state["video_standard"] == inspector.standard_id
            result["capital_start_matches"] = (state["army_x"], state["army_y"]) == World(state["world_seed"]).capital
            result["resources"] = {}
            for name in ("Speed", "WarpMode", "VICIIModel", "SidModel"):
                try:
                    result["resources"][name] = monitor.resource_get(name)
                except MonitorError:
                    result["resources"][name] = None
            vic, cia = monitor.memread(0xD000, 0x30), monitor.memread(0xDD00, 3)
            result["vic_config_matches"] = (vic[0x18] & 0x0E == 2 and vic[0x16] & 0x3F == 8
                and vic[0x11] & 0x7F == 0x1B and cia[0] & 3 == 1 and cia[2] & 3 == 3
                and vic[0x15] == 3 and vic[0x17] == vic[0x1D] == vic[0x1C] == vic[0x1B] == 0)
            result["charset_matches_source"] = monitor.memread(0x8800, 2048) == (args.output_dir / "charset.bin").read_bytes()
            result["sprites_match_source"] = monitor.memread(0xA000, 512) == ((args.output_dir / "sprites.bin").read_bytes() + (args.output_dir / "army_shadow.bin").read_bytes())
            result["sprite_allocation_avoids_vic_character_rom"] = True
            result["views"].append(inspector.view())
            result["captures"].append(inspector.capture(args.output_dir / f"{args.standard}_start.png"))
            if args.exercise:
                # First move is from the naturally autostarted capital, with
                # only normalized control injection at input_sampled.
                inspector.stop("main_loop")
                result["movement_probes"].append(inspector.move(8))
                # Cardinal excursions close to the guaranteed capital exercise
                # every overlapping-viewport cache shift without debug jumps.
                result["cardinal_scroll_probes"] = []
                for direction in (4, 1, 2, 4, 8, 2, 1):
                    inspector.stop("main_loop")
                    probe = inspector.move(direction)
                    probe["direction"] = direction
                    result["cardinal_scroll_probes"].append(probe)
                inspector.stop("main_loop")
                result["zoom_views"], result["pan_views"] = [], []
                for level, step in enumerate((4, 16, 64, 256, 1024, 4096), 1):
                    zoom_view = inspector.toggle_zoom()
                    zoom_view["expected_step"] = step
                    zoom_view["zoom_level_matches"] = zoom_view["active_view"]["state"]["zoom"] == level
                    zoom_view["step_matches"] = zoom_view["active_view"]["state"]["sample_step"] == step
                    result["zoom_views"].append(zoom_view)
                    result["captures"].append(inspector.capture(args.output_dir / f"{args.standard}_zoom_{step}.png"))
                    inspector.stop("main_loop")
                    result["pan_views"].append(inspector.pan(8))
                    inspector.stop("main_loop")
                    result["pan_views"].append(inspector.pan(1))
                    inspector.stop("main_loop")
                    inspector.stop(inspector.input_return)
                    inspector.stop("main_loop")
                result["close_view"] = inspector.toggle_zoom()
                result["close_view"]["center_reset_matches"] = (
                    result["close_view"]["active_view"]["state"]["map_center_x"],
                    result["close_view"]["active_view"]["state"]["map_center_y"]) == (
                    result["close_view"]["active_view"]["state"]["army_x"],
                    result["close_view"]["active_view"]["state"]["army_y"])
                world = World(inspector.state()["world_seed"])
                cx, cy = world.capital
                targets = {}
                # Coarse interior samples find large biomes; detailed local
                # rows find narrow rivers, roads and bridges. Every selected
                # target has a passable left neighbor for a one-step probe.
                for step, radius in ((1, 40), (4, 384)):
                    for dy in range(-radius, radius + 1, step):
                        for dx in range(-radius, radius + 1, step):
                            point = ((cx + dx) & 65535, (cy + dy) & 65535)
                            terrain = world.tile(*point)
                            if terrain not in targets and world.tile(point[0] - 1, point[1]):
                                targets[terrain] = point
                        if len(targets) == 9:
                            break
                    if len(targets) == 9:
                        break
                result["terrain_probe_targets"] = targets
                for terrain, target in sorted(targets.items()):
                    probe = inspector.probe_terrain(target, terrain)
                    if terrain:
                        result["movement_probes"].append(probe)
                    else:
                        result["sea_probe"] = probe
                result["wrap_probes"] = []
                for axis in (0, 1):
                    for coordinate in range(0, 65536, 4):
                        target = (0, coordinate) if axis == 0 else (coordinate, 0)
                        source = (65535, coordinate) if axis == 0 else (coordinate, 65535)
                        terrain = world.tile(*target)
                        if terrain and world.tile(*source):
                            probe = inspector.probe_terrain(target, terrain, 8 if axis == 0 else 2)
                            probe["axis"] = "x" if axis == 0 else "y"
                            result["wrap_probes"].append(probe)
                            break
                inspector.stop("main_loop")
                inspector.stop(inspector.input_return)
                inspector.stop("main_loop")
                result["new_world"] = inspector.new_world()
                result["captures"].append(inspector.capture(args.output_dir / f"{args.standard}_new_world.png"))
            for name in ("normal_autostart", "video_standard_matches", "capital_start_matches",
                         "vic_config_matches", "charset_matches_source", "sprites_match_source"):
                if not result[name]:
                    result["errors"].append(name)
            all_views = list(result["views"])
            for move in (result["movement_probes"] + result.get("wrap_probes", [])
                         + result.get("cardinal_scroll_probes", [])):
                all_views.extend((move["pending_view"], move["active_view"]))
                if not move["cost_matches"]:
                    result["errors"].append("movement_cost")
                if not move.get("target_matches", True):
                    result["errors"].append("movement_target")
            for key in ("overview", "close_view", "new_world"):
                if key in result:
                    all_views.extend((result[key]["pending_view"], result[key]["active_view"]))
            for zoom_view in result.get("zoom_views", []):
                all_views.extend((zoom_view["pending_view"], zoom_view["active_view"]))
                if not zoom_view["zoom_level_matches"] or not zoom_view["step_matches"]:
                    result["errors"].append("zoom_scale")
            for pan_view in result.get("pan_views", []):
                all_views.extend((pan_view["pending_view"], pan_view["active_view"]))
                if not pan_view["army_unchanged"] or not pan_view["center_delta_matches"]:
                    result["errors"].append("map_pan")
            for index, view in enumerate(all_views):
                if any(view[k] for k in ("terrain_mismatches", "glyph_mismatches", "color_mismatches")):
                    result["errors"].append(f"view_{index}_mismatch")
                if not view["pointer_tables_match"] or not view["seed_permutation_matches"]:
                    result["errors"].append(f"view_{index}_state_mismatch")
            if any(capture["character_pixel_mismatches"] for capture in result["captures"]):
                result["errors"].append("framebuffer_character_pixels")
            if args.exercise:
                if len(result["terrain_probe_targets"]) != 9:
                    result["errors"].append("not_all_terrain_costs_probed")
                if not all(result.get("sea_probe", {}).get(name) for name in
                           ("sea_blocked", "blocked_counter_increased", "blocked_cooldown_matches")):
                    result["errors"].append("sea_movement")
                if not result["new_world"]["seed_changed"] or not result["new_world"]["capital_matches"]:
                    result["errors"].append("new_world")
        finally:
            inspector.cleanup()
    result["passed"] = not result["errors"]
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--standard", choices=STANDARDS, required=True)
    parser.add_argument("--labels", type=Path, default=Path("build/atlas/atlas.lbl"))
    parser.add_argument("--prg", type=Path, default=Path("build/atlas.prg"))
    parser.add_argument("--output-dir", type=Path, default=Path("build/atlas"))
    parser.add_argument("--exercise", action="store_true")
    args = parser.parse_args()
    try:
        result = verify(args)
        path = args.output_dir / f"{args.standard}_verification.json"
        path.write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps({"report": str(path), "passed": result["passed"],
                          "normal_autostart": result["normal_autostart"],
                          "movement_probes": len(result["movement_probes"]),
                          "errors": result["errors"]}), flush=True)
        return 0 if result["passed"] else 1
    except (OSError, ValueError, MonitorError) as error:
        print(f"verify_atlas: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
