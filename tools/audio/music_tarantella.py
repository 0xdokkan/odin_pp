"""BENVENUTI A NAPOLI's music (docs/piano-napoli.md, Fase 6): a tarantella, a
seamless stereo loop made from code like the first person cards' music (the
user's choice of 2026-11-03: no clean CC0 recording was found). It plays
behind the club's view and the grandpa's minute, in the mechanics lab.

A tarantella is a fast dance in 6/8; this one is the Neapolitan kind:

  - the mandolin plays the tune in running eighths, its long notes held in the
    tremolo of its paired strings (sfx_napoli._pluck: two strings a few cents
    apart);
  - a guitar keeps the dance's step, the bass on 1 and 4, the chord on the off
    eighths ("oom-pa-pa, oom-pa-pa");
  - the tammorra, the big frame drum of Campania: a deep thump on 1 and 4, its
    jingles shaken on every eighth, louder on the beats;
  - castanets click the second and third eighth of each beat.

A minor, the eighth 0.15 s (the dotted quarter at 133), 32 bars of 0.9 s:

  bars  1-8   A minor and E: the tune in arpeggios
  bars  9-16  again, through D minor, back home
  bars 17-24  the relative major, C and G, the tune running in scales
  bars 25-32  D minor, A minor, the Neapolitan B-flat, E, home: the turnaround

    "C:/Program Files/Blender Foundation/Blender 3.5/3.5/python/bin/python.exe" tools/audio/music_tarantella.py OUT_DIR

writes OUT_DIR/music_tarantella.wav (stereo, 16 bit, 44.1 kHz) and its spectrograms;
tools/audio/encode_music.py makes assets/audio/music/tarantella.ogg of it.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dsp import SR, bandpass, env_perc, highpass, karplus, loudness_db, lowpass, n_samples, peak_eq, rng, sine, spectrogram_png, white  # noqa: E402
from music_brawler import master, write_stereo  # noqa: E402
from sfx_napoli import _pluck  # noqa: E402

EIGHTH = 0.15
BAR = 6 * EIGHTH
BARS = 32
LOOP = BARS * BAR
TAIL = 2.0
SEED = 1799

# The chords, a bar each (root, its tones as MIDI notes in the guitar's range).
CHORDS = {
    "Am": (45, (57, 60, 64)), "E": (40, (56, 59, 62, 64)), "Dm": (50, (57, 62, 65)), "C": (48, (55, 60, 64)),
    "G": (43, (55, 59, 62)), "Bb": (46, (58, 62, 65)),
}
PROGRESSION = (
    "Am Am E E E E Am Am "
    "Am Am Dm Dm E E Am Am "
    "C C G G G G C C "
    "Dm Dm Am Am Bb E Am Am"
).split()
assert len(PROGRESSION) == BARS

# The tune's notes over each chord (melody MIDI, two octaves over the bass).
TONES = {
    "Am": (69, 72, 76, 81), "E": (68, 71, 74, 76), "Dm": (69, 74, 77, 81), "C": (72, 76, 79, 84),
    "G": (71, 74, 79, 83), "Bb": (70, 74, 77, 82),
}
# A minor's scale with its raised seventh, for the runs.
SCALE = (57, 59, 60, 62, 64, 65, 68, 69, 71, 72, 74, 76, 77, 80, 81, 83, 84)


def tune(bar):
    """The tune's notes in a bar: (eighth, MIDI, length in eighths)."""
    chord = PROGRESSION[bar]
    t = TONES[chord]
    phrase_end = bar % 8 == 7
    if phrase_end:
        # The phrase lands: a dotted quarter on the root, then a pick-up.
        return [(0, t[0] if chord != "Am" else 69, 3), (3, t[1], 2), (5, t[2], 1)]
    if 16 <= bar < 24 or bar % 4 == 3:
        # Runs: down the scale from the chord's top note, then up.
        top = t[3]
        i = min(range(len(SCALE)), key=lambda k: abs(SCALE[k] - top))
        notes = [SCALE[max(i - k, 0)] for k in range(4)] + [SCALE[max(i - 3 + k, 0)] for k in (1, 2)]
        return [(k, m, 1) for k, m in enumerate(notes)]
    if bar % 2 == 0:
        return [(0, t[0], 1), (1, t[1], 1), (2, t[2], 1), (3, t[3], 1), (4, t[2], 1), (5, t[1], 1)]
    return [(0, t[3], 2), (2, t[2], 1), (3, t[1], 2), (5, t[2], 1)]


def guitar_pick(midi, length, seed):
    """A nylon string: Karplus-Strong, darker than the mandolin, a body at 200 Hz."""
    f = 440.0 * 2 ** ((midi - 69) / 12)
    x = karplus(f, length, damping=0.995, brightness=0.35, seed=seed)
    return lowpass(peak_eq(x * env_perc(length, attack=0.002, decay=length * 0.7, curve=2.5), 200, 3.0, q=1.0), 3800, 2)


def tremolo(midi, length, seed):
    """A long mandolin note held in tremolo: quick picks up and down."""
    out = np.zeros(n_samples(length + 0.3))
    r = rng(seed)
    t, k = 0.0, 0
    while t < length:
        s = _pluck(midi, 0.18, seed + k)
        i = n_samples(t)
        e = min(len(out), i + len(s))
        out[i:e] += (0.5 + 0.2 * r.random()) * s[:e - i]
        t += 1.0 / 14
        k += 1
    return out


def thump(seed):
    """The tammorra's deep stroke: the skin's low note falling, and its slap."""
    d = 0.35
    t = np.arange(n_samples(d)) / SR
    f = 95 * np.exp(-t * 6) + 55
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_perc(d, attack=0.002, decay=0.18, curve=3.0)
    slap = bandpass(white(0.05, seed), 900, 1.2) * env_perc(0.05, attack=0.001, decay=0.015)
    out = body.copy()
    out[:len(slap)] += 0.35 * slap
    return out


def jingles(seed, accent):
    """The tammorra's jingles (cymbals of tin): a bright shimmer that rings a little."""
    d = 0.16
    x = highpass(bandpass(white(d, seed), 7200, 1.5), 3000, 2)
    ring = sum(sine(f, d) for f in (5400, 6900, 8300)) * 0.15
    return (x + ring * accent) * env_perc(d, attack=0.001, decay=0.05 + 0.03 * accent, curve=2.0) * (0.45 + 0.55 * accent)


def castanet(seed):
    """Castanets: two hard wooden shells, a dry click."""
    d = 0.04
    return bandpass(white(d, seed), 2600, 2.5) * env_perc(d, attack=0.0005, decay=0.008)


def add(buf, at, x, gain=1.0):
    i = n_samples(at)
    e = min(len(buf), i + len(x))
    if e > i:
        buf[i:e] += gain * x[:e - i]


def render():
    n = n_samples(LOOP + TAIL)
    L, R = np.zeros(n), np.zeros(n)
    r = rng(SEED)
    for bar in range(BARS):
        start = bar * BAR
        chord = PROGRESSION[bar]
        root, tones = CHORDS[chord]
        # The guitar: oom on 1 and 4 (the root, then the fifth), pa-pa between.
        for beat in (0, 3):
            bass = root if beat == 0 else root + 7
            add(L, start + beat * EIGHTH, guitar_pick(bass, 0.45, SEED + bar * 31 + beat), 0.55)
            add(R, start + beat * EIGHTH, guitar_pick(bass, 0.45, SEED + bar * 31 + beat + 7), 0.35)
            for k in (1, 2):
                for j, m in enumerate(tones):
                    pick = guitar_pick(m, 0.16, SEED + bar * 97 + beat * 11 + k * 5 + j)
                    add(L, start + (beat + k) * EIGHTH + j * 0.005, pick, 0.22)
                    add(R, start + (beat + k) * EIGHTH + j * 0.005, pick, 0.12)
        # The tune on the mandolin, a little to the right.
        for eighth, midi, length in tune(bar):
            at = start + eighth * EIGHTH + r.uniform(0, 0.004)
            if length >= 2:
                note = tremolo(midi, length * EIGHTH * 0.95, SEED + bar * 53 + eighth)
            else:
                note = _pluck(midi, 0.32, SEED + bar * 53 + eighth)
            add(L, at, note, 0.42)
            add(R, at, note, 0.62)
        # The tammorra and the castanets.
        for eighth in range(6):
            at = start + eighth * EIGHTH
            if eighth in (0, 3):
                add(L, at, thump(SEED + bar * 7 + eighth), 0.7)
                add(R, at, thump(SEED + bar * 7 + eighth), 0.7)
            accent = 1.0 if eighth in (0, 3) else 0.45
            jing = jingles(SEED + bar * 13 + eighth, accent)
            add(L, at + 0.003, jing, 0.35)
            add(R, at, jing, 0.45)
            if eighth in (1, 2, 4, 5):
                add(L, at + 0.01, castanet(SEED + bar * 17 + eighth), 0.3)
                add(R, at, castanet(SEED + bar * 17 + eighth + 1), 0.22)
    # The tail folded back onto the start: a seamless loop.
    cut = n_samples(LOOP)
    for buf in (L, R):
        buf[:n - cut] += buf[cut:]
    return L[:cut].copy(), R[:cut].copy()


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    L, R = master(*render())
    write_stereo(os.path.join(out, "music_tarantella.wav"), L, R)
    mono = 0.5 * (L + R)
    spectrogram_png(os.path.join(out, "music_tarantella.png"), mono, width=1600, height=360)
    seam = np.concatenate([mono[-n_samples(4):], mono[:n_samples(4)]])
    spectrogram_png(os.path.join(out, "music_tarantella_seam.png"), seam, width=1600, height=360)
    print("WROTE %.2f s, loudness %.1f dB, peak %.2f" % (len(L) / SR, loudness_db(mono), float(np.max(np.abs(np.concatenate([L, R]))))))
