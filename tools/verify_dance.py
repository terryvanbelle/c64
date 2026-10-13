#!/usr/bin/env python3
"""Verify a normally autostarted Nocturne instance through VICE's local monitor.

No PC/register override or program loading is performed. Each pending and active
sprite buffer is compared with all 96 independently regenerated source poses.
Elapsed decode time uses emulated raster line/cycle positions, including DMA and
IRQ work. Final pictures are captured at the raster IRQ above the picture, after
the previous visible frame has completed. The original emulation speed/warp
settings are preserved, owned checkpoints are removed, and VICE is resumed.

Example: python3 tools/verify_dance.py --port 6512 --standard pal --cycles 3
"""

from __future__ import annotations

import argparse
from dataclasses import replace
import hashlib
import json
from pathlib import Path
import struct
import sys

import generate_dance_assets as assets
from vice_monitor import MonitorError, ViceMonitor


STANDARDS = {
    "pal": (0, 312, 63),
    "ntsc": (1, 263, 65),
    "oldntsc": (2, 262, 64),
}
STATE_FIELDS = (
    "video_standard", "highest_raster", "video_frames", "simulation_ticks",
    "request_counter", "last_request", "frame_ready", "active_buffer",
    "pending_buffer", "pending_pose", "displayed_pose", "next_pose",
    "prepared_frames", "missed_requests",
)


def read_labels(path: Path) -> dict[str, int]:
    labels = {}
    for line in path.read_text().splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[0] == "al":
            labels[parts[2].lstrip(".")] = int(parts[1], 16)
    required = set(STATE_FIELDS) | {"__BSS_RUN__", "__BSS_SIZE__", "__CODE_RUN__",
                                  "__CODE_SIZE__", "decode_begin", "decode_end", "irq"}
    missing = required - labels.keys()
    if missing:
        raise ValueError(f"missing assembly symbols: {sorted(missing)}")
    return labels


def read_state(monitor: ViceMonitor, labels: dict[str, int]) -> dict[str, int]:
    address = labels["__BSS_RUN__"]
    data = monitor.memread(address, labels["__BSS_SIZE__"])
    return {name: data[labels[name] - address] for name in STATE_FIELDS}


def next_stop(monitor: ViceMonitor) -> tuple[int, dict[str, int]]:
    # Old monitor-entry events remain useful to a caller, but are not the next
    # breakpoint. Explicitly discard them before starting this wait.
    monitor.events.clear()
    monitor.resume()
    stopped = monitor.wait_event(0x62)
    if len(stopped.body) != 2:
        raise MonitorError("invalid stopped-event PC")
    return struct.unpack("<H", stopped.body)[0], monitor.registers()


def check_background(frame, screen: bytes, charset: bytes, colors: bytes) -> dict:
    """Compare actual VIC pixels against static source art outside the dancer."""
    compared = mismatches = 0
    for y in range(200):
        for x in (*range(100), *range(220, 320)):
            cell = (y // 8) * 40 + x // 8
            glyph = screen[cell]
            if glyph >= 240:  # Animated glyphs are checked through live capture.
                continue
            expected = colors[cell] if charset[glyph * 8 + y % 8] & (0x80 >> (x % 8)) else 0
            actual = frame.pixels[(y + frame.y_offset) * frame.width + x + frame.x_offset]
            compared += 1
            mismatches += actual != expected
    return {"static_background_pixels_compared": compared,
            "static_background_pixel_mismatches": mismatches}


def verify(args) -> dict:
    labels = read_labels(args.labels)
    standard_id, lines, cycles_per_line = STANDARDS[args.standard]
    frame_cycles = lines * cycles_per_line
    expected = [assets.sprite_bytes(assets.dancer(pose)) for pose in range(96)]
    generated = args.output_dir / "sprites.bin"
    if generated.exists() and generated.read_bytes() != b"".join(expected):
        raise ValueError("generated sprite file differs from source-art generator")
    prg = args.prg.read_bytes()
    if len(prg) < 82:
        raise ValueError("PRG is too short")
    load_address = struct.unpack_from("<H", prg)[0]
    result = {
        "standard": args.standard,
        "prg_sha256": hashlib.sha256(prg).hexdigest(),
        "labels_sha256": hashlib.sha256(args.labels.read_bytes()).hexdigest(),
        "no_pc_override": True,
        "real_hardware_tested": False,
        "requested_pose_checks": 96 * args.cycles,
        "errors": [],
        "captures": [],
        "timing": {
            "lines_per_frame": lines, "cycles_per_line": cycles_per_line,
            "video_frame_cycles": frame_cycles,
            "method": "(end LIN*CPL+CYC minus begin LIN*CPL+CYC) modulo video-frame cycles; includes DMA and IRQ work",
            "limitation": "Single-frame wrap assumed; corruption/missed-request and cadence checks independently detect stalls.",
        },
    }
    checkpoints = []
    timings = []
    poses = []
    misses = []
    frame_deltas = 0
    tick_deltas = 0
    previous_state = None
    with ViceMonitor(args.host, args.port, args.timeout) as monitor:
        try:
            registers = monitor.registers()
            state = read_state(monitor, labels)
            start = labels["__CODE_RUN__"]
            code_end = start + labels["__CODE_SIZE__"]
            code_matches = monitor.memread(load_address, 80) == prg[2:82]
            result["cold_autostart"] = (
                start <= registers["PC"] < code_end
                and registers["01"] & 7 == 5 and code_matches
            )
            result["initial_registers"] = registers
            result["initial_state"] = state
            result["video_standard"] = state["video_standard"]
            result["program_start_matches_prg"] = code_matches
            resources = {}
            for name in ("Speed", "WarpMode", "VICIIModel", "SidModel", "RefreshOnBreak"):
                try:
                    resources[name] = monitor.resource_get(name)
                except MonitorError:
                    resources[name] = None
            result["resources"] = resources
            vic = monitor.memread(0xD000, 0x30)
            cia2 = monitor.memread(0xDD00, 3)
            result["display_config"] = {
                "cpu_port": registers["01"], "cia2_bank_bits": cia2[0] & 3,
                "cia2_ddr_bank_bits": cia2[2] & 3,
                "d018": vic[0x18] & 0xFE, "d011_mode_bits": vic[0x11] & 0x7F,
                "d016_mode_bits": vic[0x16] & 0x3F,
                "sprite_enable": vic[0x15], "sprite_x_expand": vic[0x1D],
                "sprite_y_expand": vic[0x17], "sprite_multicolor": vic[0x1C],
                "sprite_priority": vic[0x1B],
            }
            if not result["cold_autostart"]:
                result["errors"].append({"kind": "normal_autostart_not_confirmed"})
            if state["video_standard"] != standard_id:
                result["errors"].append({"kind": "video_standard", "expected": standard_id,
                                         "actual": state["video_standard"]})
            if not (cia2[0] & 3 == 2 and cia2[2] & 3 == 3
                    and vic[0x18] & 0xFE == 0x14 and vic[0x11] & 0x7F == 0x1B
                    and vic[0x16] & 0x3F == 0x08 and vic[0x15] == 0xFF
                    and vic[0x17] == 0xFF and vic[0x1D] == 0xFF
                    and vic[0x1C] == 0 and vic[0x1B] == 0):
                result["errors"].append({"kind": "unexpected_display_config"})
            screen = args.output_dir / "screen.bin"
            charset = args.output_dir / "charset.bin"
            colors = args.output_dir / "color.bin"
            result["screen_matches_source"] = monitor.memread(0x4400, 1000) == screen.read_bytes()
            result["static_charset_matches_source"] = monitor.memread(0x5000, 1920) == charset.read_bytes()[:1920]
            result["color_ram_matches_source"] = bytes(x & 15 for x in monitor.memread(0xD800, 1000)) == colors.read_bytes()
            for key in ("screen_matches_source", "static_charset_matches_source", "color_ram_matches_source"):
                if not result[key]:
                    result["errors"].append({"kind": key})
            print(json.dumps({"cold_autostart": result["cold_autostart"],
                              "video_standard": state["video_standard"],
                              "missed_requests": state["missed_requests"],
                              "prg_sha256": result["prg_sha256"]}), flush=True)

            checkpoints = [monitor.checkpoint(labels["decode_begin"]),
                           monitor.checkpoint(labels["decode_end"])]
            begin_stamp = None
            for _ in range(96 * args.cycles * 2 + 4):
                pc, registers = next_stop(monitor)
                stamp = registers["LIN"] * cycles_per_line + registers["CYC"]
                if pc == labels["decode_begin"]:
                    begin_stamp = stamp
                    continue
                if pc != labels["decode_end"]:
                    result["errors"].append({"kind": "unexpected_stop", "pc": pc})
                    continue
                state = read_state(monitor, labels)
                pose, displayed = state["next_pose"], state["displayed_pose"]
                active, pending = state["active_buffer"], state["pending_buffer"]
                if not (0 <= pose < 96 and 0 <= displayed < 96 and active in (0, 1) and pending in (0, 1)):
                    raise MonitorError(f"corrupt animation state: {state}")
                for name, buffer, current in (("pending", pending, pose), ("active", active, displayed)):
                    data = monitor.memread(0x4A00 if buffer else 0x4800, 512)
                    if data != expected[current]:
                        result["errors"].append({"kind": f"{name}_buffer", "pose": current,
                                                 "different_bytes": sum(a != b for a, b in zip(data, expected[current]))})
                pointers = monitor.memread(0x47F8, 8)
                pointer_base = 40 if active else 32
                if pointers != bytes(range(pointer_base, pointer_base + 8)):
                    result["errors"].append({"kind": "sprite_pointers", "pose": displayed,
                                             "actual": list(pointers)})
                if begin_stamp is not None:
                    timings.append((pose, (stamp - begin_stamp) % frame_cycles))
                poses.append(pose)
                misses.append(state["missed_requests"])
                if previous_state:
                    frame_deltas += (state["video_frames"] - previous_state["video_frames"]) & 255
                    tick_deltas += (state["simulation_ticks"] - previous_state["simulation_ticks"]) & 255
                previous_state = state
                if len(poses) >= 96 * args.cycles:
                    break
            for checkpoint in checkpoints:
                monitor.delete_checkpoint(checkpoint)
            checkpoints.clear()
            result["pose_checks"] = len(poses)
            result["unique_poses_checked"] = len(set(poses))
            result["active_and_pending_checks"] = len(poses) * 2
            result["missed_requests_min"] = min(misses)
            result["missed_requests_max"] = max(misses)
            result["simulation_cadence"] = {
                "video_frames_observed": frame_deltas,
                "simulation_ticks_observed": tick_deltas,
                "ticks_per_video_frame": tick_deltas / frame_deltas if frame_deltas else None,
            }
            result["timing"]["minimum_cycles"] = min(value for _, value in timings)
            result["timing"]["maximum_cycles"] = max(value for _, value in timings)
            result["timing"]["maximum_by_pose"] = {str(pose): max(value for p, value in timings if p == pose)
                                                       for pose in sorted(set(p for p, _ in timings))}
            if len(set(poses)) != 96 or len(poses) != 96 * args.cycles:
                result["errors"].append({"kind": "incomplete_pose_coverage"})
            if max(misses) != 0:
                result["errors"].append({"kind": "missed_animation_requests", "maximum": max(misses)})

            # A stop at IRQ entry occurs above the visible picture. The raster
            # framebuffer contains a completed prior frame, avoiding captures
            # of a partly rendered image during the background decode.
            checkpoints.append(monitor.checkpoint(labels["irq"]))
            captured = set()
            for _ in range(96 * 3 + 4):
                pc, registers = next_stop(monitor)
                if pc != labels["irq"]:
                    raise MonitorError("unexpected stop during capture")
                state = read_state(monitor, labels)
                pose = state["displayed_pose"]
                if pose in (0, 24, 48, 72) and pose not in captured:
                    path = args.output_dir / f"{args.standard}_pose_{pose:03}.png"
                    frame = monitor.display_get()
                    reported_y = frame.y_offset
                    background = check_background(frame, screen.read_bytes(),
                                                  charset.read_bytes(), colors.read_bytes())
                    # Installed VICE 3.10 reports the PAL inner picture one row
                    # below its actual pixels. Only adopt an adjacent crop if
                    # all static source pixels match exactly; framebuffer bytes
                    # remain untouched and the reported/corrected offsets are
                    # both recorded. This also catches future format changes.
                    if background["static_background_pixel_mismatches"]:
                        for offset in (-1, 1):
                            candidate_y = reported_y + offset
                            if not 0 <= candidate_y <= frame.height - frame.inner_height:
                                continue
                            candidate = replace(frame, y_offset=candidate_y)
                            comparison = check_background(candidate, screen.read_bytes(),
                                                          charset.read_bytes(), colors.read_bytes())
                            if comparison["static_background_pixel_mismatches"] == 0:
                                frame, background = candidate, comparison
                                break
                    frame.save_png(path, inner=True)
                    result["captures"].append({"pose": pose, "path": str(path),
                                                "raster_line": registers["LIN"],
                                                "inner_png": True, "reported_y_offset": reported_y,
                                                **frame.metadata(), **background})
                    if background["static_background_pixel_mismatches"]:
                        result["errors"].append({"kind": "rendered_background", "pose": pose, **background})
                    captured.add(pose)
                    print(f"Captured {args.standard} completed display pose {pose} at raster {registers['LIN']}", flush=True)
                if len(captured) == 4:
                    break
            if len(captured) != 4:
                result["errors"].append({"kind": "incomplete_capture_coverage", "poses": sorted(captured)})
        finally:
            for checkpoint in checkpoints:
                monitor.delete_checkpoint(checkpoint)
            monitor.resume()
    result["passed"] = not result["errors"]
    output = args.output_dir / f"{args.standard}_verification.json"
    output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"passed": result["passed"], "pose_checks": result["pose_checks"],
                      "unique_poses": result["unique_poses_checked"],
                      "max_decode_cycles": result["timing"]["maximum_cycles"],
                      "missed_max": result["missed_requests_max"],
                      "errors": result["errors"], "output": str(output)}, indent=2), flush=True)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--standard", choices=STANDARDS, required=True)
    parser.add_argument("--cycles", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=15)
    parser.add_argument("--labels", type=Path, default=Path("build/dance/nocturne.lbl"))
    parser.add_argument("--prg", type=Path, default=Path("build/nocturne.prg"))
    parser.add_argument("--output-dir", type=Path, default=Path("build/dance"))
    args = parser.parse_args()
    if args.cycles < 1:
        parser.error("--cycles must be positive")
    try:
        return 0 if verify(args)["passed"] else 1
    except (OSError, MonitorError, ValueError) as exc:
        print(f"verify_dance: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
