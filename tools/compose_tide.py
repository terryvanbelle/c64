#!/usr/bin/env python3
"""Tessellated Tide: an authored three-voice composition for one stock SID.

Four bass beats support three pulse-voice phrases and a slower triangle answer.
The score uses sustained, simultaneously audible harmony in rational tuning.
This is editable musical source; the C64 executes its compact gesture stream.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path
import bisect
import json
import struct

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/tide"
PAL, NTSC = 985248, 1022730
HZ, UNIT, BAR = 100, 24, 288
CENTRE = 104.0


@dataclass(frozen=True)
class Section:
    name: str
    bars: int
    progression: tuple[int, ...]
    cutoff: int


SECTIONS = [
    Section("The first interlock", 8, (0, 1, 2, 0), 1080),
    Section("Three surfaces", 12, (0, 1, 2, 3, 1, 0), 1260),
    Section("The current splits", 12, (4, 2, 5, 3, 2, 4), 1420),
    Section("A space between tides", 8, (1, 2, 3, 4), 940),
    Section("All the edges meet", 12, (0, 2, 5, 1, 3, 0), 1540),
    Section("The shore remembers", 8, (2, 1, 4, 0), 1110),
]

# Bass, middle, upper. Common tones connect successive shapes; the seventh
# and eleventh partials give the harmony an identity outside equal temperament.
CHORDS = (
    (1, 5/2, 3), (4/3, 7/3, 10/3), (7/6, 7/3, 7/2),
    (9/8, 9/4, 3), (1, 7/3, 3), (1, 11/4, 27/8),
)


@dataclass(frozen=True)
class Note:
    start: int
    end: int
    hz: float
    wave: int
    ad: int
    sr: int
    fall: float = 0.0


def phrase_score():
    voices: list[list[Note]] = [[], [], []]
    starts, tick = [], 0

    def put(v, start, duration, hz, *, quiet=False, noise=False, soft=False):
        if noise:
            wave, ad, sr = 0x80, 0x61, 0x01
        elif v == 0:
            wave, ad, sr = 0x40, 0x77, (0x56 if quiet else 0x76)
        elif v == 1:
            wave, ad, sr = 0x10, 0x67, (0x57 if quiet else 0x87)
        else:
            wave, ad, sr = 0x10, 0x04, (0x14 if quiet else 0x24)
        if soft and v == 2:
            ad, sr = 0x87, 0x47
        voices[v].append(Note(start, start + duration, hz, wave, ad, sr,
                              0.45 if v == 2 and not noise and not soft else 0))

    for si, section in enumerate(SECTIONS):
        starts.append(tick)
        for bar in range(section.bars):
            base = tick + bar * BAR
            chord = CHORDS[section.progression[bar // 2]]
            bass, middle, upper = (CENTRE * x for x in chord)
            sparse = si == 3 or (si == 5 and bar >= 6)

            # Establish the first interval immediately, then let its three
            # accents move against the four bass beats without changing tempo.
            if si == 0 and bar < 2:
                positions, durations = [0], [276]
            elif sparse:
                positions, durations = [0, 6], [132, 132]
            elif si == 4 and bar % 4 == 3:
                positions, durations = [0, 3, 6, 8, 10], [62, 62, 40, 40, 40]
            else:
                positions, durations = [0, 4, 8], [86, 86, 86]
            for j, (pos, duration) in enumerate(zip(positions, durations)):
                # The same arch-shaped motif returns in each new chord.
                ratios = (1, 9/8, 1) if bar % 2 == 0 else (1, 1, 8/9)
                pitch = upper * ratios[j % 3]
                if sparse:
                    pitch = upper if j == 0 else middle * 4/3
                if si == 4 and len(positions) == 5:
                    pitch = upper * (1, 9/8, 1, 8/9, 1)[j]
                put(0, base + pos * UNIT, duration, pitch, quiet=sparse)

            # In each two-bar harmony the answer either holds a common tone,
            # or answers off the bass accents. No fast simulated chords.
            if si == 0 and bar < 2:
                put(1, base, 270, middle)
            elif sparse:
                if bar % 2 == 0:
                    put(1, base, 2 * BAR - 12, middle, quiet=True)
            else:
                positions = [2, 8] if si in (2, 4) else [0, 6]
                for j, pos in enumerate(positions):
                    pitch = middle
                    if j == 1 and bar % 2:
                        # A small contrary motion before the harmonic arrival.
                        pitch *= 9/8 if si in (1, 4) else 8/9
                    put(1, base + pos * UNIT, 128 if pos < 8 else 84,
                        pitch, quiet=si == 5)

            bass_positions = [0, 6] if sparse else [0, 3, 6, 9]
            for j, pos in enumerate(bass_positions):
                pitch = bass
                # One fifth on the fourth beat gives forward motion while
                # every downbeat states the actual harmonic root.
                if pos == 9 and bar % 2 and si in (1, 2, 4):
                    pitch *= 3/2
                put(2, base + pos * UNIT, 42 if sparse else 32,
                    pitch, quiet=j % 2 == 1 or sparse)

            # Short, low-envelope air grains fit between the pitched beats.
            # Pure noise only: it never combines waveforms or steals a downbeat.
            if si in (1, 2, 4) and bar % 2 == 1:
                for pos in ([2, 8] if si == 4 else [8]):
                    put(2, base + pos * UNIT + 6, 3,
                        980 + 90 * (bar % 3), noise=True)
        tick += section.bars * BAR

    # A final quiet arrival, with enough silence for the hardware envelopes.
    put(0, tick, 360, CENTRE * 3, quiet=True)
    put(1, tick, 390, CENTRE * 5/2, quiet=True)
    put(2, tick, 300, CENTRE, quiet=True, soft=True)
    total = tick + 600
    for notes in voices:
        notes.sort(key=lambda n: n.start)
        assert all(a.end + 4 <= b.start for a, b in zip(notes, notes[1:]))
    return voices, starts, total


VOICES, STARTS, TOTAL = phrase_score()
NOTE_STARTS = [[n.start for n in voice] for voice in VOICES]


def note_at(voice, tick):
    index = bisect.bisect_right(NOTE_STARTS[voice], tick) - 1
    return VOICES[voice][index] if index >= 0 else None


def voice_state(voice, tick):
    note = note_at(voice, tick)
    next_index = bisect.bisect_right(NOTE_STARTS[voice], tick)
    preparing = (next_index < len(VOICES[voice]) and
                 VOICES[voice][next_index].start - tick <= 4)
    if note is None:
        return 104.0, 0x10, 0x0f, 0
    age = tick - note.start
    # A 60 ms downward bend makes a struck, pitched bass rather than a
    # standard drum imitation. After that its frequency is absolutely stable.
    pitch = note.hz * (1 + note.fall * max(0, 1 - age / 6))
    if preparing:
        return pitch, note.wave, 0x0f, 0
    return pitch, note.wave | int(tick < note.end), note.ad, note.sr


def triangle(phase):
    return 1 - abs(2 * (phase % 1) - 1)


def continuous(tick):
    si = min(5, max(0, bisect.bisect_right(STARTS, tick) - 1))
    # Broad linear timbral curves, independent of pitch. Their four-bar
    # breathing sits behind the faster three-against-four note pattern.
    width = 850 + 800 * triangle(tick / (4 * BAR))
    cutoff = SECTIONS[si].cutoff + 180 * triangle(tick / BAR)
    return [voice_state(v, tick)[0] * 2**24 / PAL for v in range(3)] + [width, cutoff]


def word(value):
    return list(struct.pack("<H", int(value) & 65535))


def compile_score():
    knots = set(range(0, TOTAL + 1, 144)) | set(STARTS) | {TOTAL}
    for voice in VOICES:
        for note in voice:
            knots.update((max(0, note.start - 4), note.start, note.end))
            if note.fall:
                knots.add(note.start + 6)
    knots = sorted(knots)
    sizes = (4, 4, 4, 4, 4, 3, 3, 3, 2, 1)
    predicted = [None] * 10
    output, records = bytearray(), []
    for begin, end in zip(knots, knots[1:]):
        duration = end - begin
        assert 0 < duration <= 255
        blocks = []
        for start, finish in zip(continuous(begin), continuous(end - .00001)):
            delta = round((finish - start) / duration)
            blocks.append(word(round(start)) + word(delta))
        for voice in range(3):
            _, control, ad, sr = voice_state(voice, begin)
            blocks.append([control, ad, sr])
        # Filter pulse voice only; triangle and bass stay audible and dry.
        # Bit 7 of D418 is CLEAR: this piece needs all three physical voices.
        blocks.append([0x21, 0x1b])
        blocks.append([min(5, bisect.bisect_right(STARTS, begin) - 1)])
        mask, payload = 0, []
        for i, block in enumerate(blocks):
            assert len(block) == sizes[i]
            if block != predicted[i]:
                mask |= 1 << i
                payload.extend(block)
        output.extend([duration, mask & 255, mask >> 8, *payload])
        predicted = [block[:] for block in blocks]
        for i in range(5):
            current = blocks[i][0] | blocks[i][1] << 8
            delta = blocks[i][2] | blocks[i][3] << 8
            predicted[i][:2] = word(current + delta * duration)
        records.append({"tick": begin, "duration": duration, "mask": mask})
    output.append(0)
    assert len(output) <= 0x8000, f"Score exceeds $5000-$cfff: {len(output)}"
    return output, records


def emit_bytes(label, data):
    return label + ":\n" + "\n".join(
        "    .byte " + ",".join(f"${x:02x}" for x in data[i:i+16])
        for i in range(0, len(data), 16))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    score, records = compile_score()
    (OUT / "score.bin").write_bytes(score)
    (OUT / "score.inc").write_text(
        f"SONG_TICKS = {TOTAL}\nSCORE_BYTES = {len(score)}\n"
        '.segment "SCORE"\nscore_data:\n    .incbin "score.bin"\nscore_end:\n'
        '.assert score_end <= $d000, lderror, "Score overlaps SID I/O"\n')
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
    report = {"title": "Tessellated Tide", "ticks": TOTAL, "seconds": TOTAL/HZ,
              "bpm": 60*HZ/(3*UNIT), "score_bytes": len(score), "records": len(records),
              "notes": [len(v) for v in VOICES],
              "sections": [dict(asdict(s), start_seconds=t/HZ)
                           for s, t in zip(SECTIONS, STARTS)]}
    (OUT / "composition.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
