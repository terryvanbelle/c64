#!/usr/bin/env python3
"""Editable original score for The Shape of Listening (one stock SID).

The score is a sequence of gestures, not a transcription of an existing tune.
Voice 1 is a filtered triangle ring-modulated by the silent third oscillator;
voice 2 is a dry triangle. Frequencies describe oscillators, not equal-tempered
notes. An asymmetric 13-unit phrase persists through six transformations.

Compile continuous curves into sparse linear segments. The 6502 interpolates
five 16-bit parameters at 100 Hz, with a separate NTSC pitch conversion. No
samples, rapid arpeggio chord simulation, random runtime decisions, or digi.
"""
from __future__ import annotations

from dataclasses import dataclass, asdict
from pathlib import Path
import bisect
import json
import math
import struct

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/listening"
PAL = 985248
NTSC = 1022730
HZ = 100
CENTRE = 87.0
TAU = math.tau


@dataclass(frozen=True)
class Section:
    name: str
    cycles: int
    unit: int
    openness: int
    density: int


SECTIONS = [
    Section("A surface learns to breathe", 4, 32, 780, 0),
    Section("Unequal footsteps", 8, 28, 1050, 1),
    Section("The fold remembers", 10, 24, 1250, 2),
    Section("An opening inside the sound", 4, 40, 880, 0),
    Section("Edges becoming a body", 12, 22, 1510, 3),
    Section("What remains in the room", 8, 38, 900, 1),
]


@dataclass(frozen=True)
class Gesture:
    start: int
    end: int
    carrier: float
    ratio: float
    bend: float
    pressure: int
    attack: int
    sustain: int
    release: int


def smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def phrase_score():
    voices = [[], []]
    starts = []
    tick = 0
    # The motif's unequal intervals belong to an 87 Hz centre. Its changing
    # ring ratios make the heard spectrum more complex than these carriers.
    motif = [2, 11 / 4, 7 / 3, 9 / 4, 13 / 6, 3, 8 / 3, 2]
    ratios = [0.501, 0.749, 1.251, 0.667, 1.501, 0.875, 1.125, 0.502]
    for si, section in enumerate(SECTIONS):
        starts.append(tick)
        for cycle in range(section.cycles):
            unit = section.unit
            base = tick + cycle * 13 * unit
            # Recurrence is recognizable, but missing attacks and changing
            # spacing let the phrase breathe; this is deliberately authored.
            if si == 0:
                positions = [1, 8] if cycle < 2 else [0, 5, 9]
            elif si == 3:
                positions = [0, 7] if cycle % 2 == 0 else [3]
            elif si == 5:
                positions = [0, 5, 9] if cycle < 5 else [1, 8]
            elif si == 4:
                positions = [0, 3, 6, 8, 11] if cycle % 3 == 2 else [0, 3, 8]
            else:
                positions = [0, 3, 8] if cycle % 4 != 3 else [0, 5, 9]
            for j, pos in enumerate(positions):
                nextpos = positions[j + 1] if j + 1 < len(positions) else 13
                duration = max(12, int((nextpos - pos) * unit * 0.77))
                mi = (j + cycle % 4 + (2 if si == 2 else 0)) % len(motif)
                pitch = CENTRE * motif[mi]
                if si == 3:
                    pitch *= 1.5
                if si == 4 and cycle >= 6:
                    pitch *= (1, 7 / 6, 1, 9 / 8)[cycle % 4]
                if si == 5:
                    # Gradually return to the opening carrier and ring ratio.
                    pitch += (CENTRE * 2 - pitch) * cycle / section.cycles
                ratio = ratios[(j + cycle + si) % len(ratios)]
                if si == 0:
                    ratio = [0.501, 0.749, 0.502, 0.667][cycle]
                if si == 5:
                    ratio += (0.501 - ratio) * cycle / section.cycles
                start = base + pos * unit
                voices[0].append(Gesture(start, start + duration, pitch, ratio,
                    (-1 if (cycle + j) % 2 else 1) * (0.018 if si != 4 else 0.045),
                    [8, 10, 11, 7, 12, 8][si],
                    8 if duration >= 70 else 5, 7 if si != 4 else 9, 8))
            if si == 0:
                ground = [0] if cycle else [4]
            elif si == 3:
                ground = [2] if cycle % 2 == 0 else []
            elif si == 5:
                ground = [0, 6] if cycle < 5 else [0]
            else:
                ground = [0, 6, 11] if cycle % 2 == 0 else [0, 5, 10]
            for j, pos in enumerate(ground):
                ratio = [1, 7 / 6, 9 / 8, 1][(cycle + j) % 4]
                if si == 2 and j == 1:
                    ratio = 11 / 8
                if si == 4 and j == 2:
                    ratio = 3 / 2
                duration = int(unit * ([2.6, 1.8, 1.05][j % 3]))
                start = base + pos * unit + (7 if j else 0)
                voices[1].append(Gesture(start, start + duration, CENTRE * ratio,
                    1, 0.012, 7 if si != 3 else 4, 7, 3, 8))
        tick += section.cycles * 13 * section.unit
    # A final held interval is allowed to decay fully: this piece ends.
    voices[0].append(Gesture(tick + 30, tick + 380, CENTRE * 2, .501, -.008, 7, 9, 5, 10))
    voices[1].append(Gesture(tick + 90, tick + 320, CENTRE, 1, 0, 5, 9, 2, 10))
    total = tick + 800
    for notes in voices:
        notes.sort(key=lambda note: note.start)
        assert all(a.end + 4 <= b.start for a, b in zip(notes, notes[1:]))
    return voices, starts, total


VOICES, STARTS, TOTAL = phrase_score()
NOTE_STARTS = [[n.start for n in v] for v in VOICES]


def gesture_at(voice, tick):
    idx = bisect.bisect_right(NOTE_STARTS[voice], tick) - 1
    return VOICES[voice][idx] if idx >= 0 else None


def voice_state(voice, tick):
    note = gesture_at(voice, tick)
    nextidx = bisect.bisect_right(NOTE_STARTS[voice], tick)
    preparing = nextidx < len(VOICES[voice]) and VOICES[voice][nextidx].start - tick <= 4
    waveform = 0x14 if voice == 0 else 0x10
    if note is None:
        return (174 if voice == 0 else 87), .501, waveform, 0x0F, 0, 0
    age = tick - note.start
    phase = age / max(1, note.end - note.start)
    # Slow asymmetric pitch travel, never an octave sweep or fast arpeggio.
    carrier = note.carrier * (1 + note.bend * (smooth(phase) - .5))
    carrier *= 1 + .0018 * math.sin(age * TAU / 137)
    ratio = note.ratio + .037 * math.sin(min(phase, 1) * math.pi)
    gate = int(tick < note.end)
    if preparing:
        return carrier, ratio, waveform, 0x0F, 0, 0
    attack = note.attack << 4 | (7 if voice == 0 else 8)
    sustain = note.sustain << 4 | note.release
    # A visual gesture estimate, not a readback of SID envelope output.
    envelope = min(1, age / (15 if voice == 0 else 10))
    if not gate:
        envelope *= max(0, 1 - (tick - note.end) / (80 if voice == 0 else 45))
    return carrier, ratio, waveform | gate, attack, sustain, round(note.pressure * envelope)


def continuous(tick):
    si = min(5, bisect.bisect_right(STARTS, tick) - 1)
    a = voice_state(0, tick)
    b = voice_state(1, tick)
    # A vowel-like opening within each ring gesture and a slower shared breath.
    note = gesture_at(0, tick)
    breath = 0 if note is None else math.exp(-max(0, tick - note.start - 22) / 68)
    cutoff = SECTIONS[si].openness + 220 * breath + 100 * math.sin(tick * TAU / 941)
    cutoff = min(1850, max(620, cutoff))
    values = [a[0] * 2**24 / PAL, b[0] * 2**24 / PAL,
              a[0] * a[1] * 2**24 / PAL, 2048, cutoff]
    return values


def byteword(value):
    return list(struct.pack("<H", int(value) & 65535))


def compile_score():
    # Small, regularly spaced knots plus exact articulation boundaries. Never
    # interpolate through a new note or a gate transition.
    knots = set(range(0, TOTAL + 1, 40)) | set(STARTS) | {TOTAL}
    for notes in VOICES:
        for n in notes:
            knots.update((max(0, n.start - 4), n.start, n.end))
    knots = sorted(knots)
    blocksizes = [4, 4, 4, 4, 4, 9, 2, 4]
    previous = [None] * len(blocksizes)
    output = bytearray()
    records = []
    for begin, end in zip(knots, knots[1:]):
        duration = end - begin
        assert 0 < duration <= 255
        startvals = continuous(begin)
        # Just before the boundary, so a discrete next-note jump isn't smeared.
        endvals = continuous(end - .001)
        blocks = []
        for start, finish in zip(startvals, endvals):
            delta = round((finish - start) / duration)
            start = round(start)
            blocks.append(byteword(start) + byteword(delta))
        a, b = voice_state(0, begin), voice_state(1, begin)
        blocks.append([a[2], a[3], a[4], b[2], b[3], b[4], 0x10, 0, 0])
        # Only ring voice 1 is filtered. Voice 2 is always a dry anchor.
        # Voice 3 OFF affects audio output, not the modulating oscillator.
        blocks.append([0x31, 0x9B])
        si = min(5, bisect.bisect_right(STARTS, begin) - 1)
        blocks.append([si, a[5], b[5], a[5] // 2])
        mask, payload = 0, []
        for i, block in enumerate(blocks):
            assert len(block) == blocksizes[i]
            # Oscillator/cutoff current values advance in runtime, therefore
            # resend a block with a nonzero slope even if descriptor repeats.
            changed = block != previous[i] or (i < 5 and block[2:] != [0, 0])
            if changed:
                mask |= 1 << i
                payload.extend(block)
        output.extend([duration, mask, *payload])
        previous = blocks
        records.append({"tick": begin, "duration": duration, "mask": mask})
    output.append(0)
    assert len(output) <= 0x8000, f"Score exceeds $5000-$cfff: {len(output)}"
    return output, records


def emit_bytes(label, data):
    lines = [label + ":"]
    lines += ["    .byte " + ",".join(f"${x:02x}" for x in data[i:i+16])
              for i in range(0, len(data), 16)]
    return "\n".join(lines)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    score, records = compile_score()
    (OUT / "score.bin").write_bytes(score)
    (OUT / "score.inc").write_text(
        f"SONG_TICKS = {TOTAL}\nSCORE_BYTES = {len(score)}\n"
        '.segment "SCORE"\nscore_data:\n    .incbin "score.bin"\nscore_end:\n'
        '.assert score_end <= $d000, lderror, "Score overlaps SID I/O"\n')
    # Split product with 8 fractional bits: full 16-bit pitch correction in
    # a few table reads. Error is at most one SID register unit.
    ratio = PAL / NTSC
    hi = [round(n * 256 * ratio * 256) for n in range(256)]
    lo = [round(n * ratio * 256) for n in range(256)]
    arrays = [
        ("ntsc_hi_frac", [n & 255 for n in hi]),
        ("ntsc_hi_lo", [(n >> 8) & 255 for n in hi]),
        ("ntsc_hi_hi", [n >> 16 for n in hi]),
        ("ntsc_lo_frac", [n & 255 for n in lo]),
        ("ntsc_lo_int", [n >> 8 for n in lo]),
    ]
    (OUT / "pitch.inc").write_text("\n\n".join(emit_bytes(n, a) for n, a in arrays) + "\n")
    report = {"title": "The Shape of Listening", "ticks": TOTAL,
              "seconds": TOTAL / HZ, "score_bytes": len(score),
              "records": len(records), "gestures": [len(v) for v in VOICES],
              "sections": [dict(asdict(s), start_seconds=t / HZ)
                           for s, t in zip(SECTIONS, STARTS)]}
    (OUT / "composition.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
