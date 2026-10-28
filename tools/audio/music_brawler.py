"""FIRST PERSON BRAWLER's fight music (docs/piano-prima-persona.md, Fase 2 and 3):
a 32 s seamless stereo loop made from code, like every sound of the game.

The user's reference is "Fast fight / battle music" by Ville Nousiainen
(OpenGameArt, CC0), measured, not copied: 155 BPM, a four-on-the-floor kick
that drops in pitch, a bass pedal on C whose off-beats leap to F then to G, and a
synth riff of four repeated sixteenths followed by a three-note chromatic climb,
in A-B-A-B blocks of four bars. This piece keeps that energy and shape with its
own notes, at 150 BPM so that twenty bars are exactly 32 s (a sixteenth is
0.1 s), brighter (C major, never minor), and turned to a boxing ring:

  bars  1-4   A   kick, pumping bass C (off-beats F), riff on E
  bars  5-8   B   the same over off-beats on G, riff a third up, hats come in
  bars  9-12  A'  claps on 2 and 4, brass stabs in a 3-3-2 (tresillo) rhythm
  bars 13-16  B'  everything, the riff doubled an octave up
  bars 17-20  C   the ring bell rings twice (a new round), the bass goes to B flat
                  then G, the kick halves, a snare roll and a rising sweep lead
                  back into bar 1

Every four bars ends on a jab-jab-cross of leather thuds (the gloves). No voices.

    "C:/Program Files/Blender Foundation/Blender 3.5/3.5/python/bin/python.exe" tools/audio/music_brawler.py OUT_DIR

writes OUT_DIR/music_brawler.wav (stereo, 16 bit, 44.1 kHz) and its spectrogram.
"""
import math
import os
import sys
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dsp import (SR, bandpass, drive, env_adsr, env_perc, fm, hall, highpass, loudness_db, lowpass, n_samples,  # noqa: E402
                 peak_eq, remove_dc, rng, saw, sine, spectrogram_png, square, sweep_bandpass, white)

BPM = 150.0
STEP = 60.0 / BPM / 4          # a sixteenth: 0.1 s
BAR = 16 * STEP                # 1.6 s
BARS = 20
LOOP = BARS * BAR              # 32.0 s
TAIL = 2.5                     # rendered past the end, folded back onto the start
SEED = 2026


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


NOTE = {"C": 0, "C#": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9,
        "A#": 10, "Bb": 10, "B": 11}


def m(name):
    """'E4' -> MIDI 64; '.' -> None (a rest)."""
    if name == ".":
        return None
    return 12 * (int(name[-1]) + 1) + NOTE[name[:-1]]


def at(bar, step=0):
    return (bar - 1) * BAR + step * STEP


# --------------------------------------------------------------------------
# Instruments (dry, mono, numpy)

def kick(seed):
    d = 0.42
    t = np.arange(n_samples(d)) / SR
    f = 46 + 124 * np.exp(-t / 0.028)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.13)
    click = highpass(white(0.004, seed), 2500) * 0.35
    out = body.copy()
    out[:len(click)] += click
    return drive(out, 1.6) * 0.95


def bass_note(midi, length, seed):
    f = hz(midi)
    d = length
    x = 0.5 * saw(f * 2 ** (0.06 / 12), d) + 0.5 * saw(f * 2 ** (-0.06 / 12), d) + 0.4 * sine(f, d)
    # Its bite (the saw's upper harmonics) lets it be heard on small speakers, as in the reference.
    x = lowpass(x, 700, 2)
    env = env_adsr(d, 0.003, 0.04, 0.75, 0.012)
    return drive(x * env, 1.6) * 0.5


def lead_note(midi, length, bright, seed):
    f = hz(midi)
    d = length
    x = 0.55 * square(f, d, duty=0.42) + 0.45 * saw(f * 1.004, d)
    x = lowpass(x, 2600 + 3400 * bright, 2)
    x = peak_eq(x, 2400, 4, 1.2)
    return x * env_adsr(d, 0.003, 0.05, 0.62, 0.02) * 0.6


def brass_stab(midis, seed):
    d = 0.2
    r = rng(seed)
    x = np.zeros(n_samples(d))
    for k, mm in enumerate(midis):
        for v in range(4):
            detune = 2 ** (r.uniform(-0.12, 0.12) / 12)
            x += saw(hz(mm) * detune, d) * 0.25
    x = lowpass(x, 3200, 2)
    x = peak_eq(x, 1300, 4, 1.0)
    return x * env_adsr(d, 0.008, 0.09, 0.45, 0.06) * 0.36


def clap(seed):
    d = 0.2
    x = np.zeros(n_samples(d))
    for k, off in enumerate((0.0, 0.009, 0.018)):
        burst = white(0.012, seed + k) * np.hanning(n_samples(0.012))
        i = n_samples(off)
        x[i:i + len(burst)] += burst
    tail = white(d, seed + 9) * env_perc(d, 0.001, 0.14)
    x += 0.5 * tail
    return bandpass(x, 1400, 0.9) * 0.9


def snare(seed):
    d = 0.18
    n = n_samples(d)
    body = sine(190, d) * env_perc(d, 0.001, 0.07)
    noise = highpass(white(d, seed), 1200) * env_perc(d, 0.001, 0.13)
    return (0.5 * body + 0.6 * noise) * 0.7


def hat(seed, open_=False):
    d = 0.16 if open_ else 0.045
    x = highpass(white(d, seed), 7500, 2)
    return x * env_perc(d, 0.0005, d * 0.8) * (0.34 if open_ else 0.26)


def glove(seed, heavy=False):
    """A leather glove on a paper body: a low thud and a slap."""
    d = 0.16
    t = np.arange(n_samples(d)) / SR
    f = 70 + 60 * np.exp(-t / 0.02)
    thud = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.05)
    slap = bandpass(white(d, seed), 1100, 1.4) * env_perc(d, 0.0005, 0.03)
    paper = bandpass(white(d, seed + 1), 3800, 1.2) * env_perc(d, 0.0005, 0.02) * 0.4
    return (thud * (0.9 if heavy else 0.6) + slap * 0.5 + paper) * (1.0 if heavy else 0.75)


def ring_bell(seed):
    d = 1.6
    t = np.arange(n_samples(d)) / SR
    tone = fm(1180, 1180 * 1.41, 3.0 * np.exp(-t / 0.25), d) * np.exp(-t / 0.55)
    tone += 0.4 * fm(2950, 2950 * 1.73, 1.5 * np.exp(-t / 0.15), d) * np.exp(-t / 0.3)
    strike = highpass(white(0.006, seed), 3000) * 0.5
    tone[:len(strike)] += strike
    return tone * 0.32


def riser(length, seed):
    x = white(length, seed)
    x = sweep_bandpass(x, 500, 7000, 2.5)
    u = np.linspace(0, 1, len(x))
    # It ends on the seam: closed in its last 40 ms, so the loop never clicks there.
    close = np.clip((len(x) - np.arange(len(x))) / n_samples(0.04), 0, 1)
    return x * u ** 2 * close * 0.35


# --------------------------------------------------------------------------
# The score

# The riff, sixteenth by sixteenth (16 a bar); its shape is the reference's (four
# repeated notes, a chromatic climb), its notes are its own.
RIFF_A = [
    "E4 E4 E4 E4 G4 A4 A#4 B4 C5 C5 B4 G4 A4 A4 G4 E4",
    "E4 E4 E4 E4 G4 A4 A#4 B4 D5 D5 C5 B4 C5 . G4 .",
    "E4 E4 E4 E4 G4 A4 A#4 B4 C5 C5 B4 G4 A4 A4 G4 E4",
    "D4 D4 E4 E4 G4 G4 A4 A4 C5 D5 E5 . D5 C5 A4 G4",
]
RIFF_B = [
    "G4 G4 G4 G4 B4 C5 C#5 D5 E5 E5 D5 B4 C5 C5 B4 G4",
    "G4 G4 G4 G4 B4 C5 C#5 D5 F5 F5 E5 D5 E5 . C5 .",
    "G4 G4 G4 G4 B4 C5 C#5 D5 E5 E5 D5 B4 C5 C5 B4 G4",
    "A4 G4 F#4 G4 B4 C5 D5 E5 G5 . E5 . D5 B4 C5 D5",
]
# The ring's last four bars: over B flat, then G, the riff climbs to the seam.
RIFF_C = [
    "D5 D5 D5 D5 F5 . D5 . A#4 A#4 A#4 A#4 C5 . D5 .",
    "D5 D5 D5 D5 F5 . G5 . F5 F5 D5 . C5 . A#4 .",
    "B4 B4 B4 B4 D5 . B4 . G4 G4 G4 G4 A4 . B4 .",
    "B4 C5 C#5 D5 D#5 E5 F5 F#5 G5 . G5 . G5 G5 G5 G5",
]


def riff_events():
    events = []
    blocks = [(1, RIFF_A, 0), (5, RIFF_B, 0), (9, RIFF_A, 0), (13, RIFF_B, 12), (17, RIFF_C, 0)]
    for first, rows, octave in blocks:
        for k, row in enumerate(rows):
            for s, name in enumerate(row.split()):
                mm = m(name)
                if mm is None:
                    continue
                # A held note when a rest follows it.
                nxt = row.split()[s + 1] if s + 1 < 16 else ""
                length = STEP * (1.8 if nxt == "." else 0.78)
                bright = 0.35 + 0.65 * ((first + k - 1) / (BARS - 1))
                events.append((at(first + k, s), mm, length, bright))
                if octave:
                    events.append((at(first + k, s), mm + octave, length, bright * 0.8))
    return events


def bass_root(bar):
    """The pedal and its off-beat leap: C with F (A), C with G (B), B flat, G."""
    if bar in (17, 18):
        return m("A#1"), m("F2")
    if bar in (19, 20):
        return m("G1"), m("D2")
    if ((bar - 1) // 4) % 2 == 1:
        return m("C2"), m("G2")
    return m("C2"), m("F2")


def tresillo(bar):
    return [at(bar, 0), at(bar, 3), at(bar, 6), at(bar, 10), at(bar, 12)]


def brass_chord(bar):
    if bar in (17, 18):
        return [m("A#3"), m("D4"), m("F4")]
    if bar in (19, 20):
        return [m("G3"), m("B3"), m("D4")]
    if ((bar - 1) // 4) % 2 == 1:
        return [m("G3"), m("B3"), m("D4"), m("G4")]
    return [m("C4"), m("E4"), m("G4")]


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

    k = kick(SEED)
    # Kick: four on the floor; in the ring's last bars on 1 and 3, back on the beat for the last bar.
    for bar in range(1, BARS + 1):
        beats = (0, 8) if bar in (17, 18, 19) else (0, 4, 8, 12)
        for s in beats:
            t0 = at(bar, s)
            kick_times.append(t0)
            stereo(t0, k, 1.0)

    # Bass: a pumping sixteenth pedal, the off-beat eighths on its leap.
    bass = np.zeros(n)
    for bar in range(1, BARS + 1):
        root, leap = bass_root(bar)
        for s in range(16):
            mm = leap if s % 4 == 2 else root
            if bar == 20 and s >= 8:
                mm = root + (s - 8)          # climbs into the seam
            put(bass, at(bar, s), bass_note(mm, STEP * 0.92, SEED + bar * 16 + s))
    # The kick ducks the bass (the pump of the reference's dance kick).
    t = np.arange(n) / SR
    duck = np.ones(n)
    for t0 in kick_times + [tk + LOOP for tk in kick_times[:4]]:
        i = int(t0 * SR)
        if i >= n:
            continue
        seg = t[i:min(n, i + n_samples(0.25))] - t0
        duck[i:i + len(seg)] = np.minimum(duck[i:i + len(seg)], 1 - 0.7 * np.exp(-seg / 0.07))
    bass *= duck
    L += bass
    R += bass

    # The riff, a little left, with an echo a dotted eighth later on the right.
    for t0, mm, length, bright in riff_events():
        x = lead_note(mm, length, bright, SEED)
        stereo(t0, x, 1.0, -0.18, 0.25)
        put(R, t0 + 3 * STEP, x, 0.22)

    # Brass stabs in A', B' and the ring: the 3-3-2 of the walk to the ring.
    for bar in range(9, BARS + 1):
        times = tresillo(bar) if bar != 20 else [at(bar, s) for s in (0, 4, 8, 12, 14)]
        for i, t0 in enumerate(times):
            x = brass_stab(brass_chord(bar), SEED + bar * 7 + i)
            stereo(t0, x, 1.0, 0.25 if i % 2 else -0.05, 0.35)

    # Drums.
    for bar in range(1, BARS + 1):
        for s in range(16):
            t0 = at(bar, s)
            if bar >= 5 and bar <= 18:
                stereo(t0, hat(SEED + bar * 31 + s), 1.0 if s % 2 else 0.6, 0.35)
            if bar >= 9 and bar <= 16 and s % 4 == 2:
                stereo(t0, hat(SEED + bar * 37 + s, True), 1.0, -0.35)
        if 9 <= bar <= 16:
            for s in (4, 12):
                stereo(at(bar, s), clap(SEED + bar), 1.0, 0.0, 0.3)
        elif bar < 9:
            # The sparse snare of the reference's opening bars.
            for s in ((4,) if bar % 2 else (4, 13)):
                stereo(at(bar, s), snare(SEED + bar), 0.8, 0.05, 0.2)
        # Jab, jab, cross at the end of every four bars.
        if bar % 4 == 0 and bar != 20:
            for s, heavy in ((12, False), (13, False), (14, True)):
                stereo(at(bar, s), glove(SEED + bar * 3 + s, heavy), 1.0, -0.2 if s == 12 else 0.2 if s == 13 else 0.0, 0.2)
    # The ring: the bell twice, then a snare roll and a rising sweep into the seam.
    bell = ring_bell(SEED)
    stereo(at(17, 0), bell, 1.0, 0.0, 0.5)
    stereo(at(17, 3), bell, 0.85, 0.0, 0.5)
    for bar in (19, 20):
        for s in range(0, 16, 2 if bar == 19 else 1):
            g = 0.35 + 0.65 * ((bar - 19) * 16 + s) / 32
            stereo(at(bar, s), snare(SEED + 500 + bar * 16 + s), 0.7 * g, 0.1, 0.2)
    stereo(at(19, 0), riser(2 * BAR, SEED), 1.0, 0.0, 0.3)

    # A short room: a ring under a roof, not a stone crypt.
    wet = hall(send, wet=1.0, rt60=0.9, brightness=0.55)[:n]
    L += 0.5 * wet
    R += 0.5 * np.concatenate([np.zeros(n_samples(0.013)), wet])[:n]

    # Seamless: the tail past the end is folded onto the start.
    cut = n_samples(LOOP)
    for buf in (L, R):
        buf[:n - cut] += buf[cut:]
    L, R = L[:cut], R[:cut]
    return L, R


def master(L, R, target_db=-14.0):
    L, R = remove_dc(L), remove_dc(R)
    g = 10 ** ((target_db - loudness_db(0.5 * (L + R))) / 20)
    L, R = L * g, R * g
    ceiling = 10 ** (-1.0 / 20)
    L = np.tanh(L / ceiling) * ceiling
    R = np.tanh(R / ceiling) * ceiling
    return L, R


def write_stereo(path, L, R):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    data = np.empty(2 * len(L))
    data[0::2], data[1::2] = L, R
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(data, -1, 1) * 32767).astype("<i2").tobytes())


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    L, R = master(*render())
    write_stereo(os.path.join(out, "music_brawler.wav"), L, R)
    mono = 0.5 * (L + R)
    spectrogram_png(os.path.join(out, "music_brawler.png"), mono, width=1600, height=360)
    spectrogram_png(os.path.join(out, "music_brawler_0_8s.png"), mono[:n_samples(8)], width=1600, height=360)
    seam = np.concatenate([mono[-n_samples(4):], mono[:n_samples(4)]])
    spectrogram_png(os.path.join(out, "music_brawler_seam.png"), seam, width=1600, height=360)
    print("WROTE %.2f s, loudness %.1f dB, peak %.2f" % (len(L) / SR, loudness_db(mono), float(np.max(np.abs(np.concatenate([L, R]))))))
