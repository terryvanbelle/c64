# The Shape of Listening

An original composition for a stock Commodore 64 and one SID, written for this
repository in October 2026. It lasts **179.6 seconds**, then comes to rest.

## Listening

Open `dist/the-shape-of-listening.prg` in VICE, or load `LISTENING` from the D64
on a C64 and `RUN`. Playback starts automatically. **Space** pauses/resumes;
**R** begins again, including from the ending or a pause. No configuration is
needed. The Mac file association installed for this repository also opens the
PRG directly from Finder.

The starting idea was a sound that seems to learn its own shape. A phrase of
unequal lengths recurs, but its material changes: smooth surfaces acquire
edges, the pulse becomes crowded, a gap opens, and the phrase returns with
less weight. Listen for the relationship between the rounded low tone and the
shifting upper sound. The latter's changing color is part of the composition.

The six sections are connected without title cards:

| Starts | Section | Musical change |
|---|---|---|
| 0:00 | A surface learns to breathe | Widely spaced, soft entrances reveal the sound |
| 0:16.64 | Unequal footsteps | An asymmetric answering pulse becomes recognizable |
| 0:45.76 | The fold remembers | The phrase tightens and its spectral relationships change |
| 1:16.96 | An opening inside the sound | Fewer entrances, wider spacing, higher carriers |
| 1:37.76 | Edges becoming a body | Greatest density, brighter color, expanded phrase |
| 2:12.08 | What remains in the room | Spacing widens; pitch and modulation return toward the opening |

The final eight seconds contain a held interval and its decay. The piece ends
rather than looping. The title and the little control legend remain still;
the three contours respond to authored gesture estimates and the score clock.
They are an accompaniment, not a spectrum analyzer or SID envelope readback.

## Sound design and editable score

Voice 1 is a triangle wave with ring modulation, colored by a lowpass filter.
Voice 3 supplies its modulation frequency while its direct audio output is
disabled. Voice 2 is an unfiltered triangle: a steady point of reference when
the upper sound becomes unfamiliar. Only one SID at `$D400` is needed.

The score is built around an **87 Hz centre**, ratios including 7/6, 11/8 and
13/6, and a recurring 13-unit phrase with unequal attack positions. Carrier
pitch and modulation ratio travel within each gesture. The goal is audible
development and memory, with timbre doing some of the work usually assigned
to harmony. There are no samples, borrowed melodies, tracker-song imports,
rapid arpeggios simulating chords, volume-register sample playback, or noise
combined with another waveform.

`tools/compose_listening.py` is the editable composition. Its section plan,
motifs, durations, envelopes and continuous curves produce **136 ring gestures
and 110 lower gestures**. It compiles these into **1,081 sparse records**,
occupying **26,348 bytes**. The player linearly advances oscillator frequency,
pulse width and cutoff accumulators at 100 Hz. Pulse width is currently held
at its neutral value; the score uses triangle waveforms throughout.

Knots occur at most 400 ms apart and exactly at articulation boundaries.
Integer interpolation introduces small corrections at knots. The tests report
the difference from the editable continuous curves instead of treating them
as sample-identical. This is a deliberately economical C64 synthesis player.

ADSR is prepared with gate clear, AD=`$0F`, SR=`$00` for four ticks before
each new attack. Instruments are restored before the rising gate. The
master volume stays at 11 during playback; dynamics come from envelopes,
spacing, density and filter movement. Voice 2 stays outside the shared filter.
Pause freezes the score and mutes the output; SID envelope circuitry continues
to run, so a released tail may have decayed when playback resumes.

The actual 6581 filter varies between chips and differs from the 8580.
Both are intended interpretations of the piece. The dry voice remains audible
independently of cutoff behavior. No physical C64 was available for this release.

## Hardware and build

All code uses documented NMOS 6502 instructions. The program owns its stack,
RAM IRQ/NMI vectors, CIA1 Timer A, display, and SID. It disables inherited CIA
interrupts and timer port outputs, initializes all state, and uses a safe NMI
handler. No KERNAL service or disk access is needed during playback.

The high raster interval distinguishes PAL, common NTSC and early NTSC.
CIA timer periods are **9,852 PAL cycles** and **10,227 NTSC cycles**, giving
approximately 100 Hz on either clock. Pitch is corrected separately using the
clock ratio 985248/1022730. Exhaustive conversion testing bounds the rounding
error to one SID frequency-register unit.

| Memory | Use |
|---|---|
| `$0002–$0007` | Separate score and visual pointers |
| `$0200–$023F` | Initialized application state |
| `$0801–$1FB9` | BASIC stub, player, visual code, tables and compressed art |
| `$4000–$43FF` | Character screen |
| `$4800–$4FFF` | Custom character set |
| `$5000–$B6EB` | Compressed performance score |
| `$D400–$D418` | SID registers through visible I/O |

The PRG is **44,781 bytes**, including its load address and alignment gaps.
The source art generator uses the Python standard library; ca65/ld65 build
the player. `make listening-disk` uses `c1541`. Generated includes, listings,
labels, reports and audio captures stay under ignored `build/`.

```sh
make listening listening-disk
python3 tools/verify_listening.py
python3 tools/run_vice.py --model pal --sid 6581 --monitor-port 6590 \
    dist/the-shape-of-listening.prg
```

For an isolated VICE instance, the optional live verifier exercises pause and
replay, measures timer cadence and IRQ duration, and compares loaded code and
score with the distributed artifact:

```sh
python3 tools/verify_listening_vice.py --port 6590 --model pal --wait-end
```

For a WAV capture on this Mac:

```sh
python3 tools/run_vice.py --model pal --sid 6581 --monitor-port 6590 \
    --record-wav build/listening/performance.wav --limit-seconds 190 \
    dist/the-shape-of-listening.prg
```

The recording plays through the normal audio output and closes after the
specified emulated duration, including boot time. VICE intentionally reports
a nonzero exit when its cycle limit is reached. The installed Mac VICE build
produced empty recordings with its dummy backend; native CoreAudio recording
works. Capture without warp and allow the emulator to close the WAV cleanly.

## Verification

The CPU verifier executes the actual assembled player under `sim65`, changing
only SID's address to guarded RAM and omitting startup, graphics and IRQ code.
An independent decoder checks every written register, accumulator, record
pointer, counter, section and visual gesture value.

- **55,446 compiled snapshots passed** across PAL and both NTSC selectors:
  the complete score, eight finished-state calls, reset, and 512 replay ticks.
- All **65,536 NTSC pitch inputs** passed, with at most one unit of error.
- **984 hard-restart samples** and **35,920 gate samples** matched the score.
- All interpolated oscillator and cutoff values remained in range.

The shipped D64 was cold-loaded with VICE's true 1541 emulation on early NTSC.
All loaded bytes outside the deliberately overwritten display bank matched the
distributed PRG; extracting `LISTENING` from the disk also produced an exact
byte-for-byte PRG match. It played to tick 17,960, stopped, and replayed through
the normal R handler.

Live checks passed **125 assertions** across PAL, NTSC and early NTSC. They
cover pause/resume edges, held keys, replay while paused, detected video region,
loaded code/score and IRQ cadence. Input fixtures are injected immediately
after the CIA scan; host keyboard mapping and physical keys were not exercised.

| Video standard | Measured IRQs | Largest measured IRQ, including RTI | Timer budget |
|---|---:|---:|---:|
| PAL | 259 | 2,026 cycles | 9,852 cycles |
| NTSC | 259 | 2,263 cycles | 10,227 cycles |
| Early NTSC | 259 | 2,301 cycles | 10,227 cycles |

These samples cover the opening gestures and include VIC DMA stalls. They are
measurements of that passage, not an exhaustive worst-case profile. The full
score is covered by the CPU-state verification above. IRQ acceptance varied by
up to 47 cycles around the timer period, consistent with instruction and VIC
bus delays.

Complete native VICE audio captures were checked separately. Digital tests
verify implementation; signal measurements do not establish musical quality.

Both complete 190-second captures (including boot and silence after the ending)
use mono 44.1 kHz PCM. The PAL/6581 and NTSC/8580 recordings contain audio
throughout their musical sections and **zero clipped samples**. PAL peaks at
12,282 out of 32,767, with overall RMS 842.66; NTSC peaks at 6,090, with RMS
731.4. These values include startup transients. The captures are unnormalized
SID output, retained under `build/listening/` for listening. The assistant
checked the signal numerically and did not audition these recordings by ear.
No physical-chip listening test was performed.

Distributed PRG SHA-256:
`184fb70016b5ee58468bad1842336b020be60c551a22a76047f4cd75fd950b28`.

## Primary references

- [MOS 6581 SID datasheet](https://myoldcomputer.nl/Files/mos_6581_sid.pdf):
  oscillator topology, ring modulation, filter routing and register semantics.
- [MOS 6526 CIA datasheet](https://www.emuverse.ru/downloads/datasheets/peripherals/PIA/6526/mos_6526_cia.pdf):
  continuous phi2 timer and port ownership.
- [SID Factory II instrument discussion](https://blog.chordian.net/2022/08/27/composing-in-sid-factory-ii-part-4-instruments/):
  practical hard restart and waveform differences.
- [VICE C64 timing constants](https://raw.githubusercontent.com/VICE-Team/svn-mirror/main/vice/src/c64/c64.h):
  regional clocks and raster timings.
- [VICE binary monitor protocol](https://vice-emu.sourceforge.io/vice_13.html):
  isolated live verification and actual framebuffer capture.
