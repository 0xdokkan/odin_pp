"""FIRST PERSON ARCHER's music (docs/piano-prima-persona.md, Fase 7): a seamless
stereo loop made from code, like every sound of the game. The user's choice: a
music of its own for the bow. A hunt in a neon world: tense and patient, then
quick, the way a bow is drawn and loosed:

  - a bowstring's ostinato (plucked strings, Karplus-Strong) on the chords
    A minor, F, C, E (the turn back through E major pulls to A each time);
  - the cams' ticks (soft clicks in sixteenths), deep drums, a breathing pad of
    voices with no words;
  - arrows flying past (bands of noise sweeping from one side to the other);
  - in the third block a whistle's melody over everything, and at its end a
    run of metal pings rising, an arrow bouncing faster and faster;
  - then the drop: the string and the pad alone, a sweep back to the top.

104 BPM, sixteen bars (a sixteenth is about 0.144 s), four blocks of four.

    "C:/Program Files/Blender Foundation/Blender 3.5/3.5/python/bin/python.exe" tools/audio/music_archer.py OUT_DIR

writes OUT_DIR/music_archer.wav (stereo, 16 bit, 44.1 kHz) and its spectrograms;
tools/audio/encode_music.py makes assets/audio/music/archer.ogg of it.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dsp import (SR, env_adsr, env_perc, fm, hall, highpass, karplus, loudness_db, lowpass, n_samples,  # noqa: E402
                 rng, sine, spectrogram_png, sweep_bandpass, white)
from music_brawler import hz, kick, master, onset, snare, write_stereo  # noqa: E402
from music_fencer import choir, taiko  # noqa: E402

BPM = 104.0
STEP = 60.0 / BPM / 4
BAR = 16 * STEP
BARS = 16
LOOP = BARS * BAR
TAIL = 3.5
SEED = 1415                     # Agincourt's year, near enough

A2, A3, A4 = 45, 57, 69
CHORDS = {
    "Am": (45, 52, 57, 60),
    "F": (41, 48, 53, 57),
    "C": (48, 55, 60, 64),
    "E": (40, 47, 52, 56),
}


def chord(bar):
    return ("Am", "F", "C", "E")[(bar - 1) % 4]


def at(bar, step=0):
    return (bar - 1) * BAR + step * STEP


def block(bar):
    return (bar - 1) // 4


_PLUCKS = {}


def pluck(midi, seed, bright=0.7):
    """A bowstring plucked: Karplus-Strong, faded out, kept once a note."""
    key = (midi, seed % 3, round(bright, 2))
    if key not in _PLUCKS:
        x = karplus(hz(midi), 0.5, damping=0.994, brightness=bright, seed=seed % 3)
        k = n_samples(0.08)
        x[-k:] *= np.linspace(1, 0, k)
        _PLUCKS[key] = onset(x) * 0.5
    return _PLUCKS[key]


def tick(seed):
    """A cam's tick: a tiny bright click."""
    d = 0.03
    x = highpass(white(d, seed), 5000, 2) * env_perc(d, 0.0003, 0.006)
    return onset(x) * 0.22


def whistle(midi, length, seed):
    """The whistle's note: a sine with vibrato and a breath of noise."""
    d = length
    t = np.arange(n_samples(d)) / SR
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * t) * np.clip(t / 0.15, 0, 1)
    tone = np.sin(2 * np.pi * np.cumsum(hz(midi) * vib) / SR)
    breath = sweep_bandpass(white(d, seed), hz(midi) * 2, hz(midi) * 2, 8.0) * 0.15
    return (tone + breath) * env_adsr(d, 0.04, 0.1, 0.8, 0.08) * 0.32


def ping(midi):
    """A metal ping, an arrow's bounce."""
    d = 0.35
    t = np.arange(n_samples(d)) / SR
    x = fm(hz(midi), hz(midi) * 1.41, 1.4 * np.exp(-t / 0.03), d) * np.exp(-t / 0.1)
    k = n_samples(0.06)
    x[-k:] *= np.linspace(1, 0, k)
    return onset(x) * 0.28


def flyby(length, seed, left_to_right):
    """An arrow flying past: a band of noise rising and falling, panned across."""
    x = sweep_bandpass(white(length, seed), 1200, 3400, 4.0)
    u = np.linspace(0, 1, len(x))
    env = np.sin(np.pi * u) ** 2
    pan = u if left_to_right else 1 - u
    return x * env * 0.3, pan


def sub(midi, length):
    d = length
    return sine(hz(midi), d) * env_adsr(d, 0.004, 0.05, 0.8, 0.04) * 0.4


# The string's ostinato in each block (indices into the chord's four notes,
# '.' a rest), and the whistle's line in the third (semitones over A4).
OSTINATO = {0: "0.2.1.3.0.2.1.3.", 1: "0.21.32.0.21.323", 2: "0321032103210321", 3: "0...2...1...3..."}
MELODY = {9: "0--3-5--", 10: "7--5-3--", 11: "3--7-a--", 12: "b--a-7--"}
DIGITS = {"a": 10, "b": 11}
KICKS = {0: (0, 6), 1: (0, 6, 10), 2: (0, 3, 6, 10, 14), 3: (0,)}


def render():
    n = n_samples(LOOP + TAIL)
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

    k = kick(SEED)
    for bar in range(1, BARS + 1):
        b = block(bar)
        for s in KICKS[b]:
            kick_times.append(at(bar, s))
            stereo(at(bar, s), k, 0.85)
        # A big drum on the fourth beat, and the snare's backbeat in the third block.
        if b != 3 or bar == 16:
            stereo(at(bar, 12), taiko(SEED + bar, A2 - 12, 0.8), 1.0, -0.2, 0.35)
        if b == 2:
            for s in (4, 12):
                stereo(at(bar, s), snare(SEED + bar * 2 + s), 0.7, 0.05, 0.3)

    # The string's ostinato, and the pad.
    for bar in range(1, BARS + 1):
        b = block(bar)
        notes = CHORDS[chord(bar)]
        for s, c in enumerate(OSTINATO[b]):
            if c == ".":
                continue
            midi = notes[int(c)] + 12
            stereo(at(bar, s), pluck(midi, SEED + bar * 16 + s, 0.6 + 0.3 * (s % 4 == 0)), 1.0, -0.35 if s % 2 else 0.35, 0.25)
        stereo(at(bar, 0), choir([m + 12 for m in notes[:3]], BAR * 1.05, SEED + bar, "o"), 0.8, 0.0, 0.5)

    # The cams' ticks in sixteenths from the second block (not in the drop).
    for bar in range(5, 13):
        for s in range(16):
            stereo(at(bar, s), tick(SEED + bar * 31 + s), 1.0 if s % 4 == 0 else 0.6, 0.45 if s % 2 else -0.45)

    # Sub bass on the roots in eighths, ducked by the kick.
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

    # Arrows flying past at the end of each block.
    for i, bar in enumerate((4, 8, 12)):
        x, pan = flyby(1.0, SEED + bar, i % 2 == 0)
        start = int(round(at(bar, 8) * SR))
        j = min(n, start + len(x))
        L[start:j] += (x * np.cos(pan * np.pi / 2))[:j - start] * math.sqrt(2)
        R[start:j] += (x * np.sin(pan * np.pi / 2))[:j - start] * math.sqrt(2)

    # The whistle's line, then the pings rising (an arrow bouncing ever faster).
    for bar in range(9, 13):
        row = MELODY[bar]
        for e, c in enumerate(row):
            if c in ".-":
                continue
            held = 1
            while e + held < 8 and row[e + held] == "-":
                held += 1
            midi = A4 + (DIGITS[c] if c in DIGITS else int(c))
            stereo(at(bar, e * 2), whistle(midi, STEP * 2 * held * 0.95, SEED + bar * 8 + e), 1.0, 0.1, 0.45)
    scale = [0, 2, 3, 5, 7, 8, 10, 12]
    for i, step in enumerate((0, 6, 10, 12, 13, 14, 15)):
        stereo(at(12, step) + 0.0, ping(A4 + 12 + scale[i]), 1.0, -0.4 + 0.13 * i, 0.4)

    # The sweep back to the top.
    x = sweep_bandpass(white(1.5 * BAR, SEED + 99), 300, 7000, 2.5)
    u = np.linspace(0, 1, len(x))
    stereo(at(15, 8), x * u ** 2 * 0.35, 1.0, 0.0, 0.3)

    wet = hall(send, wet=1.0, rt60=2.4, brightness=0.5)[:n]
    L += 0.45 * wet
    R += 0.45 * np.concatenate([np.zeros(n_samples(0.018)), wet])[:n]
    cut = n_samples(LOOP)
    for buf in (L, R):
        buf[:n - cut] += buf[cut:]
    return L[:cut].copy(), R[:cut].copy()


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    L, R = master(*render())
    write_stereo(os.path.join(out, "music_archer.wav"), L, R)
    mono = 0.5 * (L + R)
    spectrogram_png(os.path.join(out, "music_archer.png"), mono, width=1600, height=360)
    seam = np.concatenate([mono[-n_samples(4):], mono[:n_samples(4)]])
    spectrogram_png(os.path.join(out, "music_archer_seam.png"), seam, width=1600, height=360)
    print("WROTE %.2f s, loudness %.1f dB, peak %.2f" % (len(L) / SR, loudness_db(mono), float(np.max(np.abs(np.concatenate([L, R]))))))
