#!/usr/bin/env python3
"""Make the original voice of A Mouthful of Weather, without recorded speech.

This is a small source/filter articulatory instrument, not a text reader. A
smooth glottal flow excites a moving cascade of vocal-tract resonances; lip
radiation differentiates the result. Nasal pole/zero shaping, aspirated vowels,
and separately filtered noise supply consonants. The 32 invented fragments
are deliberately reusable syllables, rather than a dictionary of words.

The general source/filter and cascade/parallel approach is described in:
D. H. Klatt, "Software for a cascade/parallel formant synthesizer", JASA 67,
971–995 (1980), https://doi.org/10.1121/1.383940 . This implementation, glottal
shape, tract gestures, and phrase fragments are original code and parameters;
no Klatt source code, speech recordings, or text-to-speech engine are included.

Render at 24 kHz, then explicitly low-pass and decimate to 6 kHz before making
the C64's unsigned 4-bit sample bank. Each byte plays low nibble first. Sample
boundaries are quiet and sit at DAC code 8. Python's standard library suffices.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import json
import math
import random
import struct
import wave

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/weather"
SAMPLE_RATE = 6000
OVERSAMPLE = 4
RENDER_RATE = SAMPLE_RATE * OVERSAMPLE
BANK_LIMIT = 27000

# F1/F2/F3 in Hz. The high formants stay useful under the final 3 kHz Nyquist
# limit. Vowels are trajectories between these tract shapes, not fixed tones.
VOWELS = {
    "a": (730.0, 1090.0, 2440.0),
    "ae": (660.0, 1720.0, 2410.0),
    "e": (500.0, 1840.0, 2480.0),
    "i": (300.0, 2180.0, 2750.0),
    "o": (490.0, 860.0, 2350.0),
    "u": (340.0, 780.0, 2200.0),
    "uh": (500.0, 1500.0, 2500.0),
}


@dataclass(frozen=True)
class Fragment:
    name: str
    onset: str
    vowel: str
    target: str
    seconds: float
    f0: tuple[float, float, float]
    mouth: int
    coda: str = ""


# Mouth poses: 0 closed, 1 narrow, 2 medium, 3 open, 4 round, 5 teeth,
# 6 breath, 7 nasal. Exact IDs are part of the score/voice-bank contract.
FRAGMENTS = (
    Fragment("ba", "b", "a", "uh", .220, (130, 144, 127), 3),
    Fragment("bai", "b", "a", "i", .300, (130, 146, 138), 3),
    Fragment("bo", "b", "o", "o", .230, (143, 137, 124), 4),
    Fragment("bu", "b", "u", "u", .210, (136, 143, 131), 4),
    Fragment("da", "d", "a", "ae", .220, (132, 141, 129), 3),
    Fragment("dei", "d", "e", "i", .280, (137, 146, 133), 2),
    Fragment("do", "d", "o", "uh", .230, (141, 136, 123), 4),
    Fragment("du", "d", "u", "u", .200, (129, 140, 133), 1),
    Fragment("ga", "g", "a", "a", .240, (128, 142, 126), 3),
    Fragment("geu", "g", "e", "u", .290, (131, 145, 136), 2),
    Fragment("go", "g", "o", "o", .240, (137, 146, 132), 4),
    Fragment("gu", "g", "u", "uh", .210, (140, 138, 125), 1),
    Fragment("ta", "t", "a", "a", .200, (141, 139, 130), 3),
    Fragment("tei", "t", "e", "i", .260, (137, 148, 142), 2),
    Fragment("to", "t", "o", "u", .220, (142, 138, 125), 4),
    Fragment("ka", "k", "a", "uh", .230, (133, 143, 130), 3),
    Fragment("sa", "s", "a", "ae", .260, (131, 143, 135), 5),
    Fragment("sei", "s", "e", "i", .310, (135, 146, 139), 5),
    Fragment("sho", "sh", "o", "o", .270, (143, 137, 126), 4),
    Fragment("shu", "sh", "u", "u", .250, (134, 141, 130), 4),
    Fragment("fa", "f", "a", "a", .240, (132, 145, 135), 5),
    Fragment("fou", "f", "o", "u", .290, (140, 143, 127), 4),
    Fragment("ha", "h", "a", "uh", .250, (128, 142, 130), 3),
    Fragment("hei", "h", "e", "i", .280, (131, 146, 139), 2),
    Fragment("ma", "m", "a", "a", .250, (128, 139, 126), 7),
    Fragment("mou", "m", "o", "u", .300, (133, 145, 130), 7),
    Fragment("na", "n", "a", "ae", .240, (131, 141, 133), 7),
    Fragment("nei", "n", "e", "i", .280, (134, 144, 136), 7),
    Fragment("am", "", "a", "uh", .290, (128, 140, 121), 3, "m"),
    Fragment("um", "", "u", "uh", .300, (134, 137, 119), 1, "m"),
    Fragment("breath", "breath", "uh", "a", .230, (130, 130, 130), 6),
    Fragment("murmur", "murmur", "u", "uh", .350, (122, 137, 116), 7),
)


def smooth(x: float) -> float:
    x = max(0.0, min(1.0, x))
    return x * x * (3.0 - 2.0 * x)


def mix(a: float, b: float, amount: float) -> float:
    return a + (b - a) * amount


class Resonator:
    """A second-order tract resonance, normalized for unity DC response."""

    def __init__(self) -> None:
        self.y1 = self.y2 = 0.0
        self.a = self.b = self.c = 0.0

    def tune(self, hz: float, bandwidth: float) -> None:
        radius = math.exp(-math.pi * bandwidth / RENDER_RATE)
        self.b = 2.0 * radius * math.cos(2.0 * math.pi * hz / RENDER_RATE)
        self.c = -radius * radius
        self.a = 1.0 - self.b - self.c

    def step(self, value: float) -> float:
        result = self.a * value + self.b * self.y1 + self.c * self.y2
        self.y2, self.y1 = self.y1, result
        return result


class Notch:
    """A nasal antiresonance: a pole/zero pair rather than another sine tone."""

    def __init__(self, hz: float, bandwidth: float) -> None:
        radius = math.exp(-math.pi * bandwidth / RENDER_RATE)
        cosine = math.cos(2.0 * math.pi * hz / RENDER_RATE)
        self.n1 = -2.0 * cosine
        self.d1 = 2.0 * radius * cosine
        self.d2 = -radius * radius
        self.gain = (1.0 - self.d1 - self.d2) / (2.0 + self.n1)
        self.x1 = self.x2 = self.y1 = self.y2 = 0.0

    def step(self, value: float) -> float:
        result = self.gain * (value + self.n1 * self.x1 + self.x2)
        result += self.d1 * self.y1 + self.d2 * self.y2
        self.x2, self.x1 = self.x1, value
        self.y2, self.y1 = self.y1, result
        return result


class Bandpass:
    """Constant-peak biquad for the separate turbulent-consonant branch."""

    def __init__(self, hz: float, bandwidth: float) -> None:
        omega = 2.0 * math.pi * hz / RENDER_RATE
        alpha = math.sin(omega) * bandwidth / (2.0 * hz)
        self.b0 = alpha / (1.0 + alpha)
        self.a1 = -2.0 * math.cos(omega) / (1.0 + alpha)
        self.a2 = (1.0 - alpha) / (1.0 + alpha)
        self.x1 = self.x2 = self.y1 = self.y2 = 0.0

    def step(self, value: float) -> float:
        result = self.b0 * (value - self.x2)
        result -= self.a1 * self.y1 + self.a2 * self.y2
        self.x2, self.x1 = self.x1, value
        self.y2, self.y1 = self.y1, result
        return result


def glottal_flow(phase: float, open_time: float) -> float:
    """Asymmetric, smooth opening and faster closure of a glottal cycle."""
    rising = open_time * .70
    if phase < rising:
        return .5 * (1.0 - math.cos(math.pi * phase / rising))
    if phase < open_time:
        return math.cos(.5 * math.pi * (phase - rising) / (open_time - rising))
    return 0.0


def antialias_kernel() -> tuple[float, ...]:
    # A 129-tap Blackman-windowed sinc: preserve the first three speech formants
    # and remove ultrasonic glottal harmonics before the four-to-one decimation.
    width, cutoff = 129, 2650.0 / RENDER_RATE
    centre = (width - 1) // 2
    taps = []
    for i in range(width):
        x = i - centre
        sinc = 2.0 * cutoff if x == 0 else math.sin(2.0 * math.pi * cutoff * x) / (math.pi * x)
        window = .42 - .5 * math.cos(2 * math.pi * i / (width - 1)) + .08 * math.cos(4 * math.pi * i / (width - 1))
        taps.append(sinc * window)
    total = sum(taps)
    return tuple(t / total for t in taps)


def synthesize(fragment: Fragment, index: int) -> list[float]:
    """Return one original speech fragment at SAMPLE_RATE, not yet quantized."""
    rng = random.Random(0x57454154484552 + index * 0x12347)
    count = round(fragment.seconds * RENDER_RATE)
    tract = [Resonator() for _ in range(3)]
    breath_tract = [Resonator() for _ in range(3)]
    nasal = Resonator()
    nasal.tune(270.0, 85.0)
    nasal_notch = Notch(1200.0 if fragment.onset == "n" else 750.0, 180.0)
    hiss_high = Bandpass(2510.0, 850.0)
    hiss_mid = Bandpass(1820.0, 700.0)
    hiss_low = Bandpass(900.0, 1000.0)
    onset = fragment.onset
    stop = onset in ("b", "d", "g", "t", "k")
    unvoiced_stop = onset in ("t", "k")
    vowel_start = {"b": .031, "d": .030, "g": .036, "t": .050,
                   "k": .053, "s": .062, "sh": .060, "f": .049,
                   "h": .040, "m": .041, "n": .039}.get(onset, .007)
    voice_start = .008 if onset in ("m", "n", "murmur") else vowel_start
    f_start, f_target = VOWELS[fragment.vowel], VOWELS[fragment.target]
    phase = rng.random() * .07
    jitter, shimmer = 0.0, 1.0
    previous_tract = previous_breath = previous_nasal = 0.0
    previous_out = dc_out = 0.0
    noise_low = 0.0
    output = []
    duration = fragment.seconds
    for sample in range(count):
        t = sample / RENDER_RATE
        unit = t / duration
        spoken = max(0.0, (t - vowel_start) / (duration - vowel_start))
        # A stable target for the first part, then an audible moving diphthong.
        travel = smooth((spoken - .22) / .63)
        formants = [mix(a, b, travel) for a, b in zip(f_start, f_target)]
        # Place of articulation affects the first 35 ms of the adjacent vowel.
        transition = 1.0 - smooth((t - vowel_start) / .035)
        if onset in ("b", "m"):
            formants[0] = mix(formants[0], 220.0, transition * .65)
            formants[1] = mix(formants[1], 760.0, transition * .60)
        elif onset in ("d", "t", "n"):
            formants[1] = mix(formants[1], 1780.0, transition * .60)
        elif onset in ("g", "k"):
            formants[1] = mix(formants[1], 1660.0, transition * .70)
            formants[2] = mix(formants[2], 2200.0, transition * .65)
        # A gentle nasal occlusion opens into the vowel, or closes its end.
        nasal_amount = 0.0
        if onset in ("m", "n"):
            nasal_amount = 1.0 - smooth((t - .035) / .035)
        if fragment.coda:
            nasal_amount = max(nasal_amount, smooth((t - duration + .075) / .035))
        if onset == "murmur":
            nasal_amount = .80 + .13 * math.cos(unit * math.pi * 2)
        if sample % 12 == 0:
            for i, (voice_filter, air_filter) in enumerate(zip(tract, breath_tract)):
                bw = (75.0, 115.0, 160.0)[i] + 95.0 * nasal_amount
                voice_filter.tune(formants[i], bw)
                air_filter.tune(formants[i], bw + 100.0)
        # Smooth intonation plus tiny independent cycle jitter/shimmer. There
        # is no sung vibrato or fixed oscillator at a vowel's formant frequency.
        f0a, f0b, f0c = fragment.f0
        f0 = mix(f0a, f0b, smooth(unit / .48)) if unit < .48 else mix(f0b, f0c, smooth((unit - .48) / .52))
        f0 *= 1.0 + jitter + .0025 * math.sin(t * 2.0 * math.pi * 7.3)
        phase += f0 / RENDER_RATE
        if phase >= 1.0:
            phase -= 1.0
            jitter = rng.uniform(-.008, .008)
            shimmer = rng.uniform(.975, 1.025)
        flow = glottal_flow(phase, .66 + .018 * math.sin(unit * math.pi)) * shimmer
        noise = rng.uniform(-1.0, 1.0)
        noise_low += .19 * (noise - noise_low)
        # Low aspiration through the open glottis makes the voice less buzzy.
        aspiration = .022 * noise_low * (.35 + flow)
        source = flow + aspiration
        voice = source
        airy = noise_low
        for voice_filter, air_filter in zip(tract, breath_tract):
            voice = voice_filter.step(voice)
            airy = air_filter.step(airy)
        # Lip radiation is the derivative of filtered glottal flow.
        voiced = (voice - previous_tract) * 13.0
        air = (airy - previous_breath) * 13.0
        previous_tract, previous_breath = voice, airy
        nasal_value = nasal.step(source)
        nasal_radiated = (nasal_value - previous_nasal) * 13.0
        previous_nasal = nasal_value
        notched = nasal_notch.step(voiced)
        voiced = mix(voiced, .26 * notched + 2.8 * nasal_radiated, nasal_amount)
        attack = smooth((t - voice_start) / .014)
        release = 1.0 - smooth((t - duration + .035) / .030)
        syllable = .89 + .11 * math.sin(math.pi * max(0.0, min(1.0, spoken)))
        voiced *= attack * release * syllable
        if onset == "breath":
            voiced = 0.0
        # Noise is made at a different point of the tract from the glottis.
        high, middle, low = hiss_high.step(noise), hiss_mid.step(noise), hiss_low.step(noise)
        turbulent = 0.0
        if onset in ("s", "sh", "f"):
            consonant = smooth((t - .003) / .012) * (1.0 - smooth((t - vowel_start + .012) / .032))
            if onset == "s":
                turbulent = (2.4 * high + .32 * middle) * consonant
            elif onset == "sh":
                turbulent = (1.5 * middle + .62 * high) * consonant
            else:
                turbulent = (.65 * low + .52 * high + .12 * noise) * consonant
        elif stop:
            burst_time = .017 if not unvoiced_stop else .013
            elapsed = t - burst_time
            burst = math.exp(-elapsed / (.006 if unvoiced_stop else .004)) if elapsed >= 0 else 0.0
            if onset == "b":
                turbulent = (.9 * low + .20 * middle) * burst
            elif onset in ("d", "t"):
                turbulent = (1.9 * high + .5 * middle) * burst
            else:
                turbulent = (1.7 * middle + .45 * low) * burst
            if unvoiced_stop:
                aspirated = smooth((t - burst_time) / .004) * (1.0 - smooth((t - vowel_start) / .018))
                turbulent += .21 * air * aspirated
        elif onset in ("h", "breath"):
            length = duration - .025 if onset == "breath" else vowel_start + .020
            airflow = smooth((t - .003) / .018) * (1.0 - smooth((t - length + .030) / .030))
            turbulent = .58 * air * airflow
            if onset == "breath":
                turbulent += .10 * (low + middle) * airflow
        result = voiced + turbulent
        # Gentle DC removal and a six-ms outer ramp are applied before the
        # antialias filter. No abrupt restart or nonzero sample-bank boundary.
        dc_out = result - previous_out + .995 * dc_out
        previous_out = result
        edge = smooth(t / .006) * (1.0 - smooth((t - duration + .009) / .009))
        output.append(dc_out * edge)
    taps = antialias_kernel()
    half = len(taps) // 2
    padded = [0.0] * half + output + [0.0] * half
    reduced = [sum(tap * padded[i + j] for j, tap in enumerate(taps))
               for i in range(0, count, OVERSAMPLE)]
    peak = max(abs(x) for x in reduced) or 1.0
    # Shared headroom but per-fragment scaling keeps quieter consonants useful
    # at four bits. Breath/murmur retain a quieter role within the same voice.
    level = .65 if onset == "breath" else .75 if onset == "murmur" else .88
    reduced = [x * level / peak for x in reduced]
    # Deterministic soft compression gives the low-resolution DAC more of the
    # quieter vowel/fricative detail without flattening the spectral envelope.
    drive = 1.18
    reduced = [math.tanh(x * drive) / math.tanh(drive) * .88 for x in reduced]
    for i in range(min(24, len(reduced) // 2)):
        ramp = smooth(i / 23.0)
        reduced[i] *= ramp
        reduced[-1 - i] *= ramp
    reduced[0] = reduced[-1] = 0.0
    return reduced


def pcm_wave(path: Path, samples: list[float]) -> None:
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(b"".join(struct.pack("<h", max(-32768, min(32767, round(x * 32767)))) for x in samples))


def generate() -> list[dict]:
    """Write the packed C64 bank, ca65 tables, metadata, and reference audio."""
    OUT.mkdir(parents=True, exist_ok=True)
    bank = bytearray()
    metadata = []
    reference: list[float] = []
    packed_reference: list[float] = []
    for index, fragment in enumerate(FRAGMENTS):
        floating = synthesize(fragment, index)
        # Code 8 is the silent baseline; seven positive and seven negative
        # steps give symmetric headroom. TPDF dither at this resolution would
        # add audible hiss to pauses, so deterministic rounding is preferable.
        codes = [max(0, min(15, round(8 + sample * 7))) for sample in floating]
        codes[0] = codes[-1] = 8
        if len(codes) & 1:
            codes.append(8)
            floating.append(0.0)
        packed = bytes(codes[i] | (codes[i + 1] << 4) for i in range(0, len(codes), 2))
        rms = math.sqrt(sum(sample * sample for sample in floating) / len(floating))
        metadata.append({
            "id": index, "name": fragment.name, "offset": len(bank),
            "bytes": len(packed), "samples": len(codes),
            "seconds": len(codes) / SAMPLE_RATE, "mouth": fragment.mouth,
            "energy": max(1, min(15, round(rms * 34))),
        })
        bank.extend(packed)
        reference.extend(floating + [0.0] * 360)
        packed_reference.extend([(code - 8) / 7 for code in codes] + [0.0] * 360)
    if len(bank) > BANK_LIMIT:
        raise ValueError(f"Voice bank {len(bank)} exceeds {BANK_LIMIT}-byte memory budget")
    (OUT / "voice.bin").write_bytes(bank)
    (OUT / "voice.json").write_text(json.dumps(metadata, indent=2) + "\n")
    lines = ["; Generated by tools/synthesize_weather.py; do not edit.",
             f"SAMPLE_COUNT = {len(metadata)}", f"SAMPLE_RATE = {SAMPLE_RATE}",
             '.segment "SAMPLES"', "sample_bank:", '    .incbin "voice.bin"',
             "sample_bank_end:", '.segment "RODATA"']
    for label, expression in (
        ("sample_lo", lambda row: f"<(sample_bank+{row['offset']})"),
        ("sample_hi", lambda row: f">(sample_bank+{row['offset']})"),
        ("sample_len_lo", lambda row: f"<{row['bytes']}"),
        ("sample_len_hi", lambda row: f">{row['bytes']}"),
        ("sample_mouth", lambda row: str(row["mouth"])),
        ("sample_energy", lambda row: str(row["energy"])),
    ):
        lines.append(label + ":")
        for start in range(0, len(metadata), 8):
            lines.append("    .byte " + ", ".join(expression(row) for row in metadata[start:start + 8]))
    lines += [f'.assert sample_bank_end - sample_bank <= {BANK_LIMIT}, error, "Voice bank exceeds budget"', ""]
    (OUT / "voice.inc").write_text("\n".join(lines))
    pcm_wave(OUT / "voice-reference.wav", reference)
    pcm_wave(OUT / "voice-4bit-reference.wav", packed_reference)
    print(f"Weather voice: {len(metadata)} fragments, {len(bank):,} packed bytes, "
          f"{sum(row['samples'] for row in metadata) / SAMPLE_RATE:.2f}s at {SAMPLE_RATE} Hz")
    return metadata


if __name__ == "__main__":
    generate()
