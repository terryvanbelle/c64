# A Mouthful of Weather

An original **73-second piece of speech music** for an unexpanded Commodore 64
and one SID. An imagined person begins a thought, finds a rhythm, asks questions,
becomes insistent, and finds a softer answer. Its language is invented.

## Play

Open [the PRG](../dist/a-mouthful-of-weather.prg) in VICE. Playback starts
automatically. **Space** pauses/resumes; **R** starts again, including after the
ending. A copper profile changes its mouth shape while blue breath marks travel
outward. The animation follows the score's syllables and activity; it is not an
audio analyzer.

For a physical C64, use [the disk image](../dist/a-mouthful-of-weather.d64):

```basic
LOAD"WEATHER",8,1
RUN
```

The piece uses 32 reusable voice fragments to make 175 syllable/breath events
in 34 phrases. The recurring `mou-dei-nei` motif appears as a question, an
insistence, and a falling answer. Unequal syllable groups, short internal gaps,
longer breaths, and rising/falling delivery supply the musical structure.

| Starts, approximately | Section |
|---|---|
| 0:00 | A thought arrives |
| 0:09 | The mouth finds a rhythm |
| 0:23.5 | Questions in the air |
| 0:36 | A small storm of insistence |
| 0:49.7 | What the breath remembers |
| 0:59.3 | An answer, almost |

The score lasts 72.89 seconds plus 0.20 seconds of initial SID settling.
Actual timer rounding makes these nominal times approximate.

## Making the voice

[synthesize_weather.py](../tools/synthesize_weather.py) is the original voice
instrument. It generates an asymmetric glottal flow, passes it through three
moving vocal-tract resonances, and differentiates the result to model radiation
at the lips. A nasal resonance and notch, separate turbulent consonants,
aspiration, and small cycle-to-cycle pitch/amplitude changes supply the other
speech cues. There are no recordings, external speech engines, or imported
voice data.

The source/filter approach is informed by [Dennis Klatt's 1980 paper](https://doi.org/10.1121/1.383940).
This implementation and its fragment parameters are original. It renders at
24 kHz, low-pass filters and reduces to 6 kHz, then packs two four-bit samples
per byte. Quiet boundaries use sample value 8. All 32 fragments occupy
**24,510 bytes**, representing 8.17 seconds of unique material.

[compose_weather.py](../tools/compose_weather.py) authors the phrases and
prosody. Playback rates range from 0.78 to 1.16 times the source rate; changing
rate changes both pitch and formant color. Repetition and these delivery changes
let the small vocabulary sustain a longer composition. The score is 1,260 bytes.

## How the SID speaks

The C64 plays the generated waveform through the SID's four-bit master-volume
DAC at `$D418`. The sound is synthesized during the build and performed as
samples on the C64; it is not live speech synthesis using three pitched SID
oscillators.

All three oscillators are held at a DC level with pulse + TEST + gate (`$49`),
fast attack, maximum sustain, and no filter routing. This supplies a usable
offset for volume playback on the 8580 as well as the 6581. The approach is
documented in [C=Hacking #20, “The C64 Digi”](https://github.com/Jeff-Birt/C64_DIGI/blob/master/the_c64_digi.txt);
the [MOS SID datasheet](https://myoldcomputer.nl/Files/mos_6581_sid.pdf) describes
TEST holding the pulse output at DC. Chip-specific loudness, distortion, and
four-bit quantization remain part of the sound.

CIA2 Timer A generates sample NMIs; CIA1 Timer A drives the score and keyboard
at approximately 100 Hz. PAL, NTSC, and early NTSC detection selects regional
timer tables for both. A short NMI saves only A, alternates low/high nibbles,
and splits pointer and length work between them. Its longest path is statically
counted at 81 instruction cycles: 138 including interrupt entry, a conservative
instruction delay, and VIC bad-line stalls, against a shortest PAL period of
142 cycles. Sprites are disabled. This is a code timing calculation, not a
measured hardware result.

Only the sample NMI advances the playback cursor. The score publishes a new
fragment while playback is idle, and the enable flag is written last. Pause
freezes the cursor and score; rest and finish hold the DAC at midpoint 8. The
player needs no disk access after loading and uses documented NMOS 6502 opcodes.

| Memory | Use |
|---|---|
| `$0002–$000D` | Player and visual zero-page state |
| `$0200–$0215` | Other initialized state |
| `$0801–$202D` | BASIC stub, player, artwork, tables, phrase score |
| `$4000–$43FF` | Character screen |
| `$4800–$4FFF` | Custom character set |
| `$5000–$AFBD` | Packed voice fragments |

## Build and release

```sh
make weather weather-disk
make run-weather
# Or launch the disk:
make run-weather-disk
```

Python's standard library, ca65, ld65, and c1541 are sufficient. Source artwork
is in [generate_weather_art.py](../tools/generate_weather_art.py); all generated
includes, reports, and fragment-reference WAVs live under ignored `build/weather/`.
The PRG is **42,943 bytes**, including the load address and alignment gaps.

Assembly and disk packaging succeeded. The PRG was launched in native VICE with
PAL/6581 settings and CoreAudio output; the repository image is a capture of its
running display. The release targets physical hardware, but physical C64 playback,
NTSC playback, and the 8580 have not been exercised for this piece. No automated
playback tests were run, and the assistant has not auditioned the voice by ear.
Listening quality remains for the listener to judge.
