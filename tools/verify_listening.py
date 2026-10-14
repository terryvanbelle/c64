#!/usr/bin/env python3
"""Check the real assembled score player with cc65's sim65 CPU simulator.

The original music_reset, music_tick, read_record, song_finished and
write_frequency routines execute unchanged. Only SID's address is redirected
to guarded RAM; machine startup, IRQ dispatch, and graphics are omitted.
An independent Python decoder predicts every tick using absolute linear
interpolation, and the compiled player must match its register/state trace.

This checks digital register values, not audible SID synthesis, CIA cadence,
IRQ timing, keyboard controls, loading, graphics, or physical C64 behavior.
Run after `make listening`; requires ca65, cl65 and sim65, no Python packages.
"""
from __future__ import annotations

import json
from pathlib import Path
import struct
import subprocess
import tempfile

import compose_listening as score


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build/listening"
BLOCKS = ((0, 4), (4, 4), (8, 4), (12, 4), (16, 4),
          (20, 9), (29, 2), (31, 4))
FRAME_BYTES = 73
TAIL_TICKS = 8
REPLAY_TICKS = 512
PITCH_BYTES = frozenset((0, 1, 7, 8, 14, 15))


HARNESS = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
extern unsigned char sid_guards[27], synth[35], voice_energy[3];
extern unsigned char video_standard, record_left, section_index, song_done, paused;
extern unsigned int play_tick;
extern unsigned char *score_ptr;
#pragma zpsym ("score_ptr")
extern unsigned char score_data[];
extern void music_reset(void), music_tick(void), pitch_probe(void);
static unsigned char frame[73];
static FILE *output;
static void snapshot(void) {
    unsigned int offset;
    memcpy(frame,sid_guards+1,25);
    memcpy(frame+25,synth,35);
    frame[60]=(unsigned char)play_tick; frame[61]=(unsigned char)(play_tick>>8);
    frame[62]=record_left; frame[63]=section_index;
    memcpy(frame+64,voice_energy,3);
    frame[67]=song_done; frame[68]=paused;
    offset=(unsigned int)(score_ptr-score_data);
    frame[69]=(unsigned char)offset; frame[70]=(unsigned char)(offset>>8);
    frame[71]=sid_guards[0]; frame[72]=sid_guards[26];
    if(fwrite(frame,1,sizeof(frame),output)!=sizeof(frame)) exit(3);
}
int main(int argc,char **argv) {
    unsigned int tick;
    if(argc!=4) return 2;
    video_standard=(unsigned char)atoi(argv[2]);
    output=fopen(argv[1],"wb"); if(!output) return 3;
    memset(sid_guards,0xa5,27); memset(synth,0x5a,35);
    memset(voice_energy,0x5a,3);
    play_tick=0xffff; record_left=section_index=song_done=paused=0xff;
    music_reset(); snapshot();
    for(tick=0;tick<SONG_TICKS;++tick) { music_tick(); snapshot(); }
    for(tick=0;tick<TAIL_TICKS;++tick) { music_tick(); snapshot(); }
    music_reset(); snapshot();
    for(tick=0;tick<REPLAY_TICKS;++tick) { music_tick(); snapshot(); }
    if(fclose(output)) return 3;
    /* Probe all 65,536 NTSC words through the original conversion routine. */
    if(video_standard==1) {
        output=fopen(argv[3],"wb"); if(!output) return 3;
        tick=0;
        do {
            synth[0]=(unsigned char)tick;
            synth[1]=(unsigned char)(tick>>8);
            pitch_probe();
            if(fwrite(sid_guards+1,1,2,output)!=2) return 3;
        } while(++tick);
        if(fclose(output)) return 3;
    }
    return 0;
}
'''


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def word(value):
    return struct.pack("<H", value)


def decode_records(raw):
    """Parse the on-disk mask format without calling the score compiler."""
    cursor = tick = 0
    state = bytearray(35)
    records = []
    while True:
        check(cursor < len(raw), "Score lacks a zero-duration terminator")
        duration = raw[cursor]
        if not duration:
            check(cursor == len(raw) - 1, "Bytes follow the score terminator")
            break
        check(cursor + 1 < len(raw), "Truncated record header")
        mask = raw[cursor + 1]
        check(records or mask == 255, "First record must initialize all blocks")
        cursor += 2
        for bit, (offset, length) in enumerate(BLOCKS):
            if mask & (1 << bit):
                check(cursor + length <= len(raw), "Truncated block payload")
                state[offset:offset + length] = raw[cursor:cursor + length]
                cursor += length
        check(1 <= duration <= 40, f"Interpolation span too long at tick {tick}")
        check(state[31] < len(score.SECTIONS), f"Invalid section at {tick}")
        records.append((tick, duration, bytes(state), cursor))
        # The next record inherits the final accumulator value, not the
        # previous descriptor's starting value. This catches omitted slopes.
        for offset, _ in BLOCKS[:5]:
            start, delta = struct.unpack_from("<Hh", state, offset)
            final = start + duration * delta
            check(0 <= final <= 65535, f"Accumulator wraps at {tick}, offset {offset}")
            state[offset:offset + 2] = word(final)
        tick += duration
    check(tick == score.TOTAL, f"Decoded duration {tick} != authored {score.TOTAL}")
    return records


def score_frames(records):
    """Compute each tick directly from record start + elapsed * signed slope."""
    frames = []
    ranges = [[65535, 0] for _ in range(5)]
    errors = [0.0] * 5
    for tick, duration, descriptor, next_pointer in records:
        for elapsed in range(duration):
            state = bytearray(descriptor)
            values = []
            for i, (offset, _) in enumerate(BLOCKS[:5]):
                start, delta = struct.unpack_from("<Hh", descriptor, offset)
                value = start + elapsed * delta
                limit = 65535 if i < 3 else 4095 if i == 3 else 2047
                check(0 <= value <= limit, f"Parameter {i} out of range at {tick + elapsed}")
                state[offset:offset + 2] = word(start + (elapsed + 1) * delta)
                values.append(value)
                ranges[i] = [min(ranges[i][0], value), max(ranges[i][1], value)]
            for i, ideal in enumerate(score.continuous(tick + elapsed)):
                errors[i] = max(errors[i], abs(values[i] - ideal))
            # Use the documented SID register layout, not assembly's stores.
            sid = bytearray(25)
            for voice in range(3):
                sid[voice * 7:voice * 7 + 2] = word(values[voice])
                sid[voice * 7 + 4:voice * 7 + 7] = descriptor[20 + voice * 3:23 + voice * 3]
            sid[2:4] = word(values[3])
            sid[21] = values[4] % 8
            sid[22] = values[4] // 8
            sid[23:25] = descriptor[29:31]
            frames.append(bytes(sid + state + word(tick + elapsed + 1)
                                + bytes((duration - elapsed - 1, descriptor[31]))
                                + descriptor[32:35] + bytes((0, 0))
                                + word(next_pointer) + bytes((0xA5, 0xA5))))
    return frames, ranges, errors


def verify_articulations(frames):
    """Check every audible gate against authored starts, ends and preparation."""
    checks = 0
    for voice, notes in enumerate(score.VOICES):
        base = voice * 7
        expected_gate = bytearray(score.TOTAL)
        for note in notes:
            expected_gate[note.start:note.end] = bytes((1,)) * (note.end - note.start)
            check(note.start >= 4, "First note needs four ticks of preparation")
            for tick in range(note.start - 4, note.start):
                sid = frames[tick]
                check(sid[base + 4] & 1 == 0 and sid[base + 5] == 0x0F
                      and sid[base + 6] == 0,
                      f"Missing four-tick hard restart: voice {voice + 1}, tick {tick}")
                checks += 1
        for tick, expected in enumerate(expected_gate):
            check(frames[tick][base + 4] & 1 == expected,
                  f"Gate disagrees with authored gesture: voice {voice + 1}, tick {tick}")
    return checks


def build_runtime(work):
    source = (ROOT / "src/listening/engine.s").read_text()
    # These contiguous original routines are copied verbatim. No branch,
    # instruction, arithmetic, record parser or register store is replaced.
    music = source[source.index(".proc music_reset\n"):source.index('.segment "RODATA"')]
    rodata = source[source.index('.segment "RODATA"'):source.index('.segment "BSS"')]
    rodata = rodata.replace('.assert * < $4000, lderror, "Code and tables overlap display bank"\n', "")
    rodata = rodata.replace('.include "score.inc"', 'score_data:\n    .incbin "score.bin"')
    bss = source[source.index('.segment "BSS"'):]
    symbols = ("synth", "voice_energy", "video_standard", "record_left", "section_index",
               "song_done", "paused", "play_tick", "score_ptr", "score_data",
               "music_reset", "music_tick")
    glue = '\n'.join(f'.export _{name}\n_{name} = {name}' for name in symbols)
    assembly = ('.setcpu "6502"\n.segment "ZEROPAGE"\nscore_ptr: .res 2\n'
                '.segment "BSS"\n.export _sid_guards\n_sid_guards: .res 27\n'
                'SID = _sid_guards+1\n.segment "CODE"\n'
                + music + rodata + bss + '\n' + glue
                + '\n.segment "CODE"\n.export _pitch_probe\n_pitch_probe:\n'
                '    ldx #0\n    ldy #0\n    jmp write_frequency\n')
    (work / "runtime.s").write_text(assembly)
    (work / "harness.c").write_text(
        f"#define SONG_TICKS {score.TOTAL}u\n#define TAIL_TICKS {TAIL_TICKS}u\n"
        f"#define REPLAY_TICKS {REPLAY_TICKS}u\n" + HARNESS)
    subprocess.run(["ca65", "-I", str(BUILD), "--bin-include-dir", str(BUILD), str(work / "runtime.s"),
                    "-o", str(work / "runtime.o")], check=True)
    subprocess.run(["cl65", "-t", "sim6502", "-O", str(work / "harness.c"),
                    str(work / "runtime.o"), "-o", str(work / "harness")], check=True)


def expected_sequence(frames):
    reset = bytes(71) + bytes((0xA5, 0xA5))
    ended = bytearray(frames[-1])
    for register in (4, 11, 18):
        ended[register] = 0
    ended[24] = 0x90
    ended[64:67] = bytes(3)
    ended[67] = 1
    return [reset, *frames, *([bytes(ended)] * TAIL_TICKS), reset, *frames[:REPLAY_TICKS]]


def compare_trace(actual, expected, region):
    check(len(actual) == len(expected) * FRAME_BYTES, "Wrong compiled trace length")
    worst_pitch = 0
    for frame_number, want in enumerate(expected):
        got = actual[frame_number * FRAME_BYTES:(frame_number + 1) * FRAME_BYTES]
        for byte in range(FRAME_BYTES):
            if byte not in PITCH_BYTES:
                check(got[byte] == want[byte],
                      f"Region {region}, frame {frame_number}, byte {byte}: "
                      f"got {got[byte]:02x}, expected {want[byte]:02x}")
        for offset in (0, 7, 14):
            pitch = struct.unpack_from("<H", want, offset)[0]
            ideal = round(pitch * score.PAL / score.NTSC) if region else pitch
            observed = struct.unpack_from("<H", got, offset)[0]
            difference = abs(observed - ideal)
            check(difference <= (1 if region else 0),
                  f"Region {region}, frame {frame_number}, SID {offset}: "
                  f"pitch {observed}, expected {ideal}")
            worst_pitch = max(worst_pitch, difference)
    return worst_pitch


def main():
    check((BUILD / "score.bin").exists(), "Run make listening before this verifier")
    raw = (BUILD / "score.bin").read_bytes()
    check(raw == bytes(score.compile_score()[0]), "Built score is stale; run make listening")
    records = decode_records(raw)
    frames, ranges, errors = score_frames(records)
    restart_checks = verify_articulations(frames)
    expected = expected_sequence(frames)
    report = {"score_ticks": score.TOTAL, "score_records": len(records),
              "score_bytes": len(raw), "parameter_ranges": ranges,
              "maximum_curve_error_register_units": [round(e, 4) for e in errors],
              "hard_restart_ticks_checked": restart_checks,
              "gate_ticks_checked": score.TOTAL * 2,
              "compiled_frames_per_model": len(expected), "models": {}}
    with tempfile.TemporaryDirectory(prefix="listening-verify-") as directory:
        work = Path(directory)
        build_runtime(work)
        previous_ntsc = None
        for region, name in enumerate(("pal", "ntsc", "oldntsc")):
            trace = work / f"{name}.bin"
            pitch = work / "pitch.bin"
            subprocess.run(["sim65", str(work / "harness"), str(trace), str(region), str(pitch)],
                           check=True, timeout=120)
            actual = trace.read_bytes()
            error = compare_trace(actual, expected, region)
            if region == 1:
                previous_ntsc = actual
            if region == 2:
                check(actual == previous_ntsc, "The two NTSC branches diverged")
            report["models"][name] = {"frames": len(expected), "maximum_pitch_error_units": error}
            print(f"PASS {name}: {len(expected):,} compiled frames, full score, end and replay.")
        pitches = (work / "pitch.bin").read_bytes()
        check(len(pitches) == 65536 * 2, "Incomplete exhaustive pitch trace")
        maximum_error = 0
        for source, (actual,) in enumerate(struct.iter_unpack("<H", pitches)):
            ideal = round(source * score.PAL / score.NTSC)
            maximum_error = max(maximum_error, abs(actual - ideal))
            check(abs(actual - ideal) <= 1, f"NTSC pitch conversion failed for {source}")
        report["exhaustive_ntsc_pitch_words"] = 65536
        report["exhaustive_ntsc_maximum_error_units"] = maximum_error
    report["limitations"] = (
        "CPU/runtime checks use SID RAM fixtures. They do not validate audible synthesis, "
        "CIA/IRQ timing, startup/loading, controls, graphics, or a physical C64.")
    (BUILD / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS all 65,536 NTSC pitch words (maximum error {maximum_error}); "
          f"{restart_checks:,} hard-restart samples; {score.TOTAL * 2:,} gate samples.")


if __name__ == "__main__":
    main()
