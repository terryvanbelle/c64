#!/usr/bin/env python3
"""Check an isolated running VICE music instance, then leave it replaying.

Checks actual loaded code/score, region detection, IRQ intervals and costs,
pause/replay edges, and a natural ending. Controls are injected after the CIA
scan; this does not test host key mapping or a physical keyboard.
The program is restarted by its real R-key handler, never by changing PC.
"""
import argparse
import json
from pathlib import Path
import struct

from vice_monitor import ViceMonitor
from compose_listening import TOTAL

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build/listening"
MODELS = {"pal": (0, 312, 63, 9852), "ntsc": (1, 263, 65, 10227),
          "oldntsc": (2, 262, 64, 10227)}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--model", choices=MODELS, required=True)
    p.add_argument("--wait-end", action="store_true")
    args = p.parse_args()
    labels = {x[2].lstrip("."): int(x[1], 16)
              for line in (BUILD / "listening.lbl").read_text().splitlines()
              if len(x := line.split()) == 3 and x[0] == "al"}
    region, lines, cpl, period = MODELS[args.model]
    owned = []
    result = {"model": args.model, "checks": 0, "controls": "post-CIA-scan fixtures"}
    def check(condition, description):
        result["checks"] += 1
        if not condition:
            raise AssertionError(description)
    with ViceMonitor(port=args.port, timeout=30) as m:
        oldsound = m.resource_get("Sound")
        try:
            m.resource_set("Sound", 0)
            def state(name, length=1):
                return int.from_bytes(m.memread(labels[name], length, bank="ram"), "little")
            def stop():
                m.events.clear()
                m.resume()
                e = m.wait_event(0x62, timeout=30)
                return struct.unpack("<H", e.body)[0]
            check(state("video_standard") == region, "Video standard detection")
            image = (ROOT / "dist/the-shape-of-listening.prg").read_bytes()[2:]
            # The display overwrites the loaded gap at $4000-$4fff; compare
            # every other loaded byte, including all code and score data.
            for a, b in ((0x801, 0x4000), (0x5000, 0x801 + len(image))):
                check(m.memread(a, b-a, bank="ram") == image[a-0x801:b-0x801],
                      f"Distributed program RAM mismatch at ${a:04x}")
            cp = m.checkpoint(labels["key_sampled"])
            owned.append(cp)
            stop()
            def key(value):
                m.memwrite(labels["key_raw"], bytes([value]), bank=1)
                check(stop() == labels["key_sampled"], "Control checkpoint")
            key(0)
            key(2)
            check(state("play_tick", 2) == 0 and state("paused") == 0, "R resets score")
            for _ in range(8):
                key(2)
            check(state("play_tick", 2) == 8, "Held R must not continuously restart")
            key(0)
            key(1)
            frozen = state("play_tick", 2)
            check(state("paused") == 1, "Space pauses")
            for _ in range(8):
                key(1)
            key(0)
            check(state("play_tick", 2) == frozen, "Pause freezes score, held Space is one edge")
            key(1)
            check(state("paused") == 0 and state("play_tick", 2) == frozen+1, "Space resumes")
            key(0)
            key(1)
            key(0)
            key(2)
            check(state("paused") == 0 and state("play_tick", 2) == 0, "R replays from pause")
            key(0)
            m.delete_checkpoint(cp); owned.remove(cp)
            # Measure whole IRQ, including keyboard/player work and VIC stalls.
            begin = m.checkpoint(labels["irq"])
            end = m.checkpoint(labels["irq_done"])
            owned.extend((begin, end))
            costs, gaps = [], []
            last = start = None
            for _ in range(520):
                pc = stop()
                r = m.registers()
                stamp = r["LIN"] * cpl + r["CYC"]
                if pc == labels["irq"]:
                    if last is not None:
                        gaps.append((stamp-last) % (lines*cpl))
                    start = last = stamp
                elif pc == labels["irq_done"] and start is not None:
                    costs.append((stamp-start) % (lines*cpl))
                    start = None
            check(len(costs) >= 250, "Enough whole IRQ measurements")
            check(max(costs) + 22 < period, "IRQ fits 100 Hz deadline")
            # Main instructions and VIC DMA can delay IRQ acceptance slightly.
            check(all(abs(v-period) < 100 for v in gaps), "CIA timer cadence")
            result["irq_samples"] = len(costs)
            result["irq_max_cycles_including_rti"] = max(costs) + 22
            result["timer_period_cycles"] = period
            result["observed_irq_interval_range"] = [min(gaps), max(gaps)]
            for cp in (begin, end):
                m.delete_checkpoint(cp); owned.remove(cp)
            if args.wait_end:
                cp = m.checkpoint(labels["song_finished"])
                owned.append(cp)
                m.events.clear(); m.resume()
                # Bounded event waits so callers can report progress while the
                # real-time performance advances in its own tool session.
                while True:
                    try:
                        e = m.wait_event(0x62, timeout=30)
                        break
                    except TimeoutError:
                        print("Performance advancing toward its ending...", flush=True)
                check(struct.unpack("<H", e.body)[0] == labels["song_finished"], "Natural ending checkpoint")
                check(state("play_tick", 2) == TOTAL, "Complete song length")
                check(state("record_left") == 0, "No unplayed score ticks")
                m.delete_checkpoint(cp); owned.remove(cp)
                cp = m.checkpoint(labels["key_sampled"])
                owned.append(cp); stop()
                check(state("song_done") == 1, "Ending enters stopped state")
                key(0); key(2); key(0)
                check(state("song_done") == 0 and state("play_tick", 2) == 1, "Replay after natural ending")
                m.delete_checkpoint(cp); owned.remove(cp)
                result["complete_performance_ticks"] = TOTAL
            m.display_get().save_png(BUILD / f"vice-{args.model}.png", inner=True)
        finally:
            for cp in owned:
                m.delete_checkpoint(cp)
            m.resource_set("Sound", oldsound)
            m.resume()
    path = BUILD / f"vice-{args.model}.json"
    path.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
