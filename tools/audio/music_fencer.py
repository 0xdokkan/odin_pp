"""FIRST PERSON FENCER's fight music (docs/piano-prima-persona.md, Fase 5): a
40 s seamless stereo loop made from code, like every sound of the game.

The user's choice: a music of its own for the sword (not the one kept aside),
for the zweihänder they asked for, "cibernetica e maestosa". So it is slower
and grander than the fists' ring, a march for a great sword in a neon world:

  - the epic minor turn i - VI - III - VII (D minor, B flat, F, C), a bar each,
    an A major at the very end pulling back to D;
  - a choir made of saws through vowel formants (no words), war drums (deep
    taiko-like toms) and a kick under them;
  - steel: anvil strikes tuned to D on the offbeats, as blades meeting;
  - the Neon: a cyan arpeggio of plucked saws running the chords in sixteenths,
    a sub bass in eighths;
  - in the third block a heroic horn line over everything, the choir an octave
    up; then a drop to drums and choir, a snare roll and a sweep back to the top.

96 BPM, sixteen bars of 2.5 s (a sixteenth is 0.15625 s), four blocks of four:

  bars  1-4   a blade drawn at the top; choir, drums, sub bass
  bars  5-8   the arpeggio and the anvils
  bars  9-12  everything, the horn's melody
  bars 13-16  drums and choir alone, then the roll and the sweep

    "C:/Program Files/Blender Foundation/Blender 3.5/3.5/python/bin/python.exe" tools/audio/music_fencer.py OUT_DIR

writes OUT_DIR/music_fencer.wav (stereo, 16 bit, 44.1 kHz) and its spectrograms;
tools/audio/encode_music.py makes assets/audio/music/fencer.ogg of it.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dsp import (SR, bandpass, drive, env_adsr, env_perc, formant, hall, highpass, loudness_db, lowpass,  # noqa: E402
                 metal_modes, modal, n_samples, rng, saw, sine, spectrogram_png, square, sweep_bandpass, white)
from music_brawler import hz, kick, master, onset, snare, write_stereo  # noqa: E402

BPM = 96.0
STEP = 60.0 / BPM / 4          # a sixteenth: 0.15625 s
BAR = 16 * STEP                # 2.5 s
BARS = 16
LOOP = BARS * BAR              # 40.0 s
TAIL = 3.5                     # rendered past the end, folded back onto the start
SEED = 1519                    # the year of the great swords' heyday, near enough

D2, D3, D4, D5 = 38, 50, 62, 74

# The chords, a bar each (MIDI notes of a close voicing round D3).
CHORDS = {
    "Dm": (50, 53, 57),
    "Bb": (46, 50, 53),
    "F": (53, 57, 60),
    "C": (48, 52, 55),
    "A": (45, 49, 52),
}


def chord(bar):
    if bar == 16:
        return "A"
    return ("Dm", "Bb", "F", "C")[(bar - 1) % 4]


def at(bar, step=0):
    return (bar - 1) * BAR + step * STEP


def block(bar):
    return (bar - 1) // 4      # 0: A, 1: B, 2: C, 3: the drop


# --------------------------------------------------------------------------
# Instruments (dry, mono, numpy)

def taiko(seed, midi, accent=1.0):
    """A war drum: a deep skin dropping in pitch, a long body, a wooden crack."""
    d = 0.9
    t = np.arange(n_samples(d)) / SR
    f = hz(midi) * (1 + 0.8 * np.exp(-t / 0.025))
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.32)
    skin = bandpass(white(d, seed), 300, 0.9) * env_perc(d, 0.001, 0.09)
    crack = bandpass(white(d, seed + 1), 2400, 1.2) * env_perc(d, 0.0005, 0.012) * 0.4
    return onset(drive(body * 1.0 + skin * 0.55 + crack, 1.6)) * 0.62 * accent


def anvil(seed, accent=1.0):
    """Steel meeting steel, tuned: blade modes on D5, a hard tick."""
    d = 0.9
    x = modal(d, metal_modes(hz(D5), count=9, decay=0.5, seed=seed), seed=seed)
    tick = highpass(white(0.006, seed + 1), 3500) * 0.6
    x[:len(tick)] += tick
    x = x / (np.max(np.abs(x)) + 1e-12)
    return onset(x * np.exp(-np.arange(len(x)) / SR / 0.35)) * 0.32 * accent


def choir(midis, length, seed, vowel="a"):
    """A choir with no words: detuned saws through the formants of a vowel,
    breathing in slowly, a little vibrato."""
    d = length
    t = np.arange(n_samples(d)) / SR
    r = rng(seed)
    x = np.zeros(len(t))
    for mm in midis:
        for v in range(4):
            vib = 1 + 0.004 * np.sin(2 * np.pi * (5.0 + r.uniform(-0.4, 0.4)) * t + r.uniform(0, 6.3))
            f = hz(mm) * 2 ** (r.uniform(-0.12, 0.12) / 12) * vib
            x += np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.15 + saw(hz(mm) * 2 ** (r.uniform(-0.1, 0.1) / 12), d) * 0.2
    shapes = {"a": [(730, 5, 1.0), (1090, 5, 0.5), (2440, 6, 0.25)],
              "o": [(570, 5, 1.0), (840, 5, 0.45), (2410, 6, 0.18)]}
    x = formant(x, shapes[vowel])
    x = lowpass(x, 5000, 2)
    return x / (np.max(np.abs(x)) + 1e-12) * env_adsr(d, 0.35, 0.2, 0.85, 0.45) * 0.42


def pluck(midi, seed, bright=1.0):
    """The Neon arpeggio's note: a saw and a square, plucked, a filter closing fast."""
    d = 0.3
    t = np.arange(n_samples(d)) / SR
    f = hz(midi)
    x = 0.6 * saw(f, d) + 0.4 * square(f * 1.003, d)
    cut = 900 + 3800 * bright * np.exp(-t / 0.05)
    # A closing low pass, in three bands of time (cheap and smooth enough at this length).
    y = np.zeros(len(x))
    for k, lo in enumerate((0, len(x) // 6, len(x) // 3)):
        hi = (len(x) // 6, len(x) // 3, len(x))[k]
        y[lo:hi] = lowpass(x, float(np.mean(cut[lo:hi])), 2)[lo:hi]
    return onset(y * env_perc(d, 0.001, 0.12)) * 0.22


def sub(midi, length):
    """The sub bass: a sine and a little saw, an octave down."""
    d = length
    x = sine(hz(midi), d) + 0.25 * lowpass(saw(hz(midi), d), 400, 2)
    return x * env_adsr(d, 0.004, 0.05, 0.8, 0.03) * 0.42


def horn(midi, length, seed):
    """The heroic line: a brass of detuned saws with a slow bloom."""
    d = length
    t = np.arange(n_samples(d)) / SR
    r = rng(seed)
    x = np.zeros(len(t))
    for v in range(5):
        x += saw(hz(midi) * 2 ** (r.uniform(-0.08, 0.08) / 12), d)
    bloom = np.clip(t / 0.12, 0, 1)
    x = lowpass(x / 5, 1400 + 1800 * float(np.mean(bloom)), 2)
    x = drive(x * 1.4, 1.5)
    return x * env_adsr(d, 0.05, 0.15, 0.75, 0.12) * 0.36


def blade_drawn(seed):
    """The top of the loop: a blade drawn (a steel scrape up into a ring)."""
    d = 1.4
    scrape = sweep_bandpass(white(0.35, seed), 2000, 6000, 6.0) * np.linspace(0.3, 1, n_samples(0.35))
    ring = modal(1.05, metal_modes(hz(D5 + 7), count=9, decay=0.7, seed=seed + 1), seed=seed + 1)
    x = np.zeros(n_samples(d))
    x[:len(scrape)] += scrape / (np.max(np.abs(scrape)) + 1e-12) * 0.6
    i = n_samples(0.32)
    x[i:i + len(ring)] += ring / (np.max(np.abs(ring)) + 1e-12) * 0.7
    return onset(x) * 0.4


def riser(length, seed):
    x = sweep_bandpass(white(length, seed), 300, 7000, 2.5)
    u = np.linspace(0, 1, len(x))
    close = np.clip((len(x) - np.arange(len(x))) / n_samples(0.04), 0, 1)
    return x * u ** 2 * close * 0.4


# --------------------------------------------------------------------------
# The score

# The war drums, sixteenth by sixteenth: 'T' a big hit, 't' a lighter one.
DRUMS = {
    0: "T.....t.T.......",
    1: "T.....t.T...t...",
    2: "T..t..t.T..t.tt.",
    3: "T.......T.......",
}
KICKS = {0: (0, 8), 1: (0, 8, 10), 2: (0, 6, 8, 14), 3: (0,)}
ANVILS = (6, 14)

# The horn in the third block, eighth by eighth: semitones over D4 ('.' rest,
# '-' held). A rising line over D minor, B flat, F and C.
MELODY = {
    9: "7--C A-5",
    10: "3-578-7-",
    11: "A-737-AC",
    12: "E-CAC---",
}
DIGITS = {"A": 10, "C": 12, "E": 14}


def melody_note(c):
    return D4 + (DIGITS[c] if c in DIGITS else int(c))


def render():
    total = LOOP + TAIL
    n = n_samples(total)
    L, R = np.zeros(n), np.zeros(n)
    send = np.zeros(n)
    kick_times = []

    def put(buf, t0, x, gain=1.0):
        i = int(round(t0 * SR))
        if i >= len(buf):
            return
        j = min(len(buf), i + len(x))
        buf[i:j] += gain * x[:j - i]

    def stereo(t0, x, gain=1.0, pan=0.0, wet=0.0):
        a = math.cos((pan + 1) * math.pi / 4)
        b = math.sin((pan + 1) * math.pi / 4)
        put(L, t0, x, gain * a * math.sqrt(2))
        put(R, t0, x, gain * b * math.sqrt(2))
        if wet:
            put(send, t0, x, gain * wet)

    # The blade drawn at the top.
    stereo(at(1, 0), blade_drawn(SEED), 1.0, 0.1, 0.6)

    k = kick(SEED)
    for bar in range(1, BARS + 1):
        for s in KICKS[block(bar)]:
            kick_times.append(at(bar, s))
            stereo(at(bar, s), k, 0.9)

    for bar in range(1, BARS + 1):
        row = DRUMS[block(bar)]
        for s, c in enumerate(row):
            if c == ".":
                continue
            big = c == "T"
            stereo(at(bar, s), taiko(SEED + bar * 16 + s, D2 - 5 if big else D2, 1.0 if big else 0.7), 1.0,
                   -0.3 if s % 4 else 0.25, 0.35)

    # The choir, a chord a bar (an octave up in the third block, "o" in the drop).
    for bar in range(1, BARS + 1):
        b = block(bar)
        notes = CHORDS[chord(bar)]
        voiced = [m + (12 if b == 2 else 0) for m in notes] + [notes[0] + 12]
        stereo(at(bar, 0), choir(voiced, BAR * 1.05, SEED + bar, "o" if b == 3 else "a"), 1.0, 0.0, 0.55)

    # Sub bass in eighths on the roots, ducked by the kick.
    bass = np.zeros(n)
    for bar in range(1, BARS + 1):
        if block(bar) == 3 and bar < 16:
            continue
        root = CHORDS[chord(bar)][0] - 12
        for s in range(0, 16, 2):
            put(bass, at(bar, s), sub(root, STEP * 1.8))
    t = np.arange(n) / SR
    duck = np.ones(n)
    for t0 in kick_times + [tk + LOOP for tk in kick_times[:3]]:
        i = int(t0 * SR)
        if i >= n:
            continue
        seg = t[i:min(n, i + n_samples(0.3))] - t0
        duck[i:i + len(seg)] = np.minimum(duck[i:i + len(seg)], 1 - 0.6 * np.exp(-seg / 0.09))
    bass *= duck
    L += bass
    R += bass

    # The Neon arpeggio and the anvils, from the second block (not in the drop).
    for bar in range(5, 13):
        tones = list(CHORDS[chord(bar)])
        tones = [m + 12 for m in tones] + [m + 24 for m in tones]
        order = [0, 1, 2, 3, 4, 5, 4, 3, 2, 1, 0, 1, 2, 3, 4, 3]
        for s in range(16):
            bright = 0.6 + 0.4 * (s % 4 == 0)
            stereo(at(bar, s), pluck(tones[order[s]], SEED + bar * 16 + s, bright), 1.0, -0.45 if s % 2 else 0.45, 0.3)
        for i, s in enumerate(ANVILS):
            stereo(at(bar, s), anvil(SEED + bar * 4 + i, 1.0 if block(bar) == 2 else 0.8), 1.0, 0.35 if i else -0.35, 0.5)

    # The horn's line in the third block.
    for bar in range(9, 13):
        row = MELODY[bar]
        for e, c in enumerate(row):
            if c in ".- ":
                continue
            held = 1
            while e + held < 8 and row[e + held] == "-":
                held += 1
            stereo(at(bar, e * 2), horn(melody_note(c), STEP * 2 * held * 0.95, SEED + bar * 8 + e), 1.0, -0.1, 0.45)

    # The roll and the sweep back to the top.
    for s in range(8, 16):
        g = 0.3 + 0.7 * (s - 8) / 7
        stereo(at(16, s), snare(SEED + 700 + s), 0.7 * g, 0.05, 0.35)
    stereo(at(15, 8), riser(1.5 * BAR, SEED), 1.0, 0.0, 0.35)

    # A great hall: long and dark.
    wet = hall(send, wet=1.0, rt60=2.8, brightness=0.45)[:n]
    L += 0.5 * wet
    R += 0.5 * np.concatenate([np.zeros(n_samples(0.019)), wet])[:n]

    # Seamless: the tail past the end is folded onto the start.
    cut = n_samples(LOOP)
    for buf in (L, R):
        buf[:n - cut] += buf[cut:]
    return L[:cut].copy(), R[:cut].copy()


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    L, R = master(*render())
    write_stereo(os.path.join(out, "music_fencer.wav"), L, R)
    mono = 0.5 * (L + R)
    spectrogram_png(os.path.join(out, "music_fencer.png"), mono, width=1600, height=360)
    spectrogram_png(os.path.join(out, "music_fencer_0_10s.png"), mono[:n_samples(10)], width=1600, height=360)
    seam = np.concatenate([mono[-n_samples(4):], mono[:n_samples(4)]])
    spectrogram_png(os.path.join(out, "music_fencer_seam.png"), seam, width=1600, height=360)
    print("WROTE %.2f s, loudness %.1f dB, peak %.2f" % (len(L) / SR, loudness_db(mono), float(np.max(np.abs(np.concatenate([L, R]))))))
