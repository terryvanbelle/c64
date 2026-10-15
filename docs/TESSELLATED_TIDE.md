# Tessellated Tide

An original **178.8-second** composition for a stock Commodore 64 and one SID.
Three independent voices form sustained harmony, a returning melodic arch, and
an interlocking pulse. Six connected sections lead to a definite ending.

## Listening

Open [tessellated-tide.prg](../dist/tessellated-tide.prg) in VICE. On a C64,
load `TESSELLATED-TIDE` from the [disk image](../dist/tessellated-tide.d64) and
`RUN`. Playback begins automatically; no setup screen is needed.

- **Space:** pause or resume.
- **R:** restart, including while paused or after the ending.

Pause freezes the score and mutes the output. The SID's envelope circuits keep
running, so the sound of a held note can change before playback resumes.

Listen for three upper accents moving against four bass beats, then for the
slower middle voice answering between them. The underlying beat is
**83⅓ BPM**: four beats span a 2.88-second bar, divided into twelve equal units.
Some passages open up or add shorter gestures while keeping that shared pulse.

| Starts | Section | Development |
|---|---|---|
| 0:00 | The first interlock | Held harmony introduces the sounds before the three-against-four pattern enters |
| 0:23.04 | Three surfaces | The answering voice and small air grains fill out the rhythm |
| 0:57.60 | The current splits | Shifted answers and wider harmonic colors increase movement |
| 1:32.16 | A space between tides | Fewer attacks and longer notes open a quieter space |
| 1:55.20 | All the edges meet | The fullest passage expands the upper motif and rhythmic detail |
| 2:29.76 | The shore remembers | Familiar shapes return, thin out, and settle into the final arrival |

The final arrival begins at 2:52.8; the remaining six seconds allow its notes
and envelopes to come to rest. Three woven triangular ribbons respond to the
score clock and authored voice activity. They are a visual accompaniment;
their brightness is not a measurement of the SID's actual audio output.

## Sound and score

All **three physical SID voices** contribute audible notes at once. Voice 1 is
a slowly changing pulse wave through a lowpass filter. Voice 2 is a dry triangle
answer. Voice 3 provides a struck triangle bass with a brief downward pitch
bend, plus occasional short **pure-noise grains** between pitched beats.
Noise is never combined with another waveform. Master volume remains at 11
during playback; envelopes, arrangement, pulse width, and filtering shape it.

Harmony uses rational frequency ratios around a **104 Hz reference**. Six
three-note voicings share tones while introducing relationships to the seventh
and eleventh partials. A recurring arch-shaped motif changes with the harmony.
These are simultaneous sustained intervals, with no rapid arpeggios standing
in for chords, sampled instruments, or imported songs.

The editable [composition](../tools/compose_tide.py) specifies the notes,
sections, envelopes, and timbral curves. Its 522 note events compile into
1,446 sparse gesture records occupying **22,920 bytes**. The
[player](../src/tide/engine.s) advances pitch, pulse width, and filter values at
100 Hz, with integer interpolation between score boundaries. Four preparation
ticks clear the gate and set a fast release before each subsequent attack;
the opening attacks begin from the initialized SID state.

## Build and hardware design

Python's standard library generates the score and
[character artwork](../tools/generate_tide_art.py); ca65 and ld65 assemble and
link the program. `c1541` packages the disk image.

```sh
make tide
make tide-disk
make run-tide
```

Build outputs are `build/tessellated-tide.prg` and
`build/tessellated-tide.d64`. `make run-tide-disk` launches the disk version.
Generated includes, the composition summary, labels, and linker map live in
`build/tide/`. The [linker layout](../tide.cfg) keeps code and artwork below the
display bank and the score below I/O.

| Memory | Use |
|---|---|
| `$0002–$0007` | Separate score and visual pointers |
| `$0200–$0242` | Application state |
| `$0801–$1B75` | BASIC stub, player, visuals, tables, and compressed artwork |
| `$4000–$43FF` | Character screen |
| `$4800–$4FFF` | Custom character set |
| `$5000–$A987` | Performance score |
| `$D400–$D418` | SID registers |

The program targets an unexpanded C64 using documented NMOS 6502 instructions.
It owns the RAM interrupt vectors, CIA1 Timer A, display, and SID, initializes
its state, and needs no disk access during playback. Raster detection selects
PAL, common NTSC, or early NTSC. Timer periods are 9,852 PAL cycles or 10,227
NTSC cycles, approximately 100 Hz; a separate frequency conversion compensates
for the regional SID clock. This keeps intended tempo and tuning independent
of display refresh. The [visual code](../src/tide/visual.s) runs at about 25 Hz.

## Validation and limits

The PRG assembled and linked, the D64 was packaged, and the PRG was launched
in native VICE using PAL and a 6581. The repository screenshot was captured
from that running emulator. The final score has not undergone a complete
runtime regression or audio analysis; the assistant did not audition it by ear.

The 6581 and 8580 filters differ, and individual 6581 chips vary substantially.
Both dry triangle voices remain independent of the filter, but the balance and
color of the pulse voice will vary. Physical hardware, NTSC playback, the 8580,
disk startup, and pause/replay controls have not been exercised for this release.
