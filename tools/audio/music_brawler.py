"""FIRST PERSON BRAWLER's fight music (docs/piano-prima-persona.md, Fase 2 and 3):
a 32 s seamless stereo loop made from code, like every sound of the game.

The user's brief, after the first try (kept as music_battle_riserva.py): rawer,
"più da stile battle, quindi più ritmica, più severa", a game where people beat
each other up, the mood of boxing, the air of a ring in an arena. So this one is
rhythm first, and the rhythm is made of the fight itself:

  - the groove is played by gloves: jabs, crosses, hooks and body blows are
    leather thuds of their own weight, ghost punches between the beats;
  - war drums (low toms) and a distorted kick with a sub tail under them;
  - a severe harmony in the game's own scale, D Phrygian (D Eb F G A Bb C): a
    distorted bass and low strings in short strokes, hard brass hits;
  - the ring: the bell rings the round in at the top of the loop, a crowd made of
    filtered noise (no voices, no words) roars under it and swells after the
    heavy blows, a big arena's reverb.

120 BPM, sixteen bars of 2 s (a sixteenth is 0.125 s), four blocks of four:

  bars  1-4   the bell; gloves, kick and toms; bass and strings on D
  bars  5-8   the snare on 2 and 4, hats, brass hits on the accents
  bars  9-12  everything: toms in eighths, the strings an octave up, the crowd up
  bars 13-16  two bars of gloves, toms and crowd alone, then a flurry of punches,
              a snare roll and a rising sweep back into the bell

    "C:/Program Files/Blender Foundation/Blender 3.5/3.5/python/bin/python.exe" tools/audio/music_brawler.py OUT_DIR

writes OUT_DIR/music_brawler.wav (stereo, 16 bit, 44.1 kHz) and its spectrograms.
"""
import math
import os
import sys
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dsp import (SR, bandpass, drive, env_adsr, env_perc, fm, hall, highpass, loudness_db, lowpass, n_samples,  # noqa: E402
                 peak_eq, remove_dc, rng, saw, sine, spectrogram_png, sweep_bandpass, white)

BPM = 120.0
STEP = 60.0 / BPM / 4          # a sixteenth: 0.125 s
BAR = 16 * STEP                # 2.0 s
BARS = 16
LOOP = BARS * BAR              # 32.0 s
TAIL = 3.0                     # rendered past the end, folded back onto the start
SEED = 1977


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


# D Phrygian, as MIDI numbers.
D1, D2, D3, D4, D5 = 26, 38, 50, 62, 74
EB = 1                          # the flat second, the scale's bite
F, G, A, BB, C = 3, 5, 7, 8, 10


def onset(x, seconds=0.001):
    """A millisecond's entrance, so no attack starts on a jump."""
    x = x.copy()
    k = min(len(x), n_samples(seconds))
    x[:k] *= np.linspace(0, 1, k)
    return x


def at(bar, step=0):
    return (bar - 1) * BAR + step * STEP


def block(bar):
    return (bar - 1) // 4      # 0: A, 1: B, 2: C, 3: the break


# --------------------------------------------------------------------------
# Instruments (dry, mono, numpy)

def kick(seed):
    d = 0.6
    t = np.arange(n_samples(d)) / SR
    f = hz(D1) + 140 * np.exp(-t / 0.022)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.22)
    click = highpass(white(0.005, seed), 2000) * 0.45
    out = body.copy()
    out[:len(click)] += click
    return onset(drive(out, 2.4)) * 0.72


def glove(seed, weight):
    """A punch landing: a leather thud (deeper and longer the heavier the blow), the
    slap of the glove, a little paper. weight 0.3 (a ghost) .. 1.0 (a body blow)."""
    d = 0.12 + 0.14 * weight
    t = np.arange(n_samples(d)) / SR
    # Tuned to the scale: the heavy blows on D, the light ones a fifth up on A.
    f = hz(D2 if weight >= 0.75 else D2 + A) + 90 * np.exp(-t / 0.018)
    thud = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / (0.035 + 0.06 * weight))
    slap = bandpass(white(d, seed), 900 + 500 * (1 - weight), 1.3) * env_perc(d, 0.0005, 0.035)
    paper = bandpass(white(d, seed + 1), 3600, 1.2) * env_perc(d, 0.0005, 0.018) * 0.35
    return onset(drive(thud * (0.5 + 0.6 * weight) + slap * (0.55 + 0.4 * weight) + paper, 1.5)) * (0.35 + 0.65 * weight)


def tom(seed, midi, accent=1.0):
    d = 0.5
    t = np.arange(n_samples(d)) / SR
    f = hz(midi) * (1 + 0.5 * np.exp(-t / 0.03))
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.17)
    skin = bandpass(white(d, seed), 450, 1.0) * env_perc(d, 0.001, 0.06)
    return onset(drive(body * 0.9 + skin * 0.6, 1.8)) * 0.55 * accent


def snare(seed):
    d = 0.3
    body = sine(185, d) * env_perc(d, 0.001, 0.09) + 0.5 * sine(330, d) * env_perc(d, 0.001, 0.05)
    noise = highpass(white(d, seed), 1500) * env_perc(d, 0.001, 0.2)
    crack = bandpass(white(d, seed + 1), 4200, 1.0) * env_perc(d, 0.0005, 0.02)
    return onset(drive(0.55 * body + 0.6 * noise + 0.5 * crack, 1.6)) * 0.85


def hat(seed, open_=False):
    d = 0.18 if open_ else 0.04
    x = highpass(white(d, seed), 8000, 2)
    return onset(x * env_perc(d, 0.0005, d * 0.8)) * (0.4 if open_ else 0.3)


def bass_note(midi, length, seed):
    """A distorted bass stroke: two detuned saws and a sine, grinding."""
    f = hz(midi)
    d = length
    x = 0.5 * saw(f * 2 ** (0.1 / 12), d) + 0.5 * saw(f * 2 ** (-0.1 / 12), d) + 0.7 * sine(f, d)
    x = drive(x, 3.0)
    x = lowpass(x, 1300, 2)
    return x * env_adsr(d, 0.002, 0.05, 0.7, 0.02) * 0.3


def strings(midi, length, seed):
    """Low strings in short, hard strokes (spiccato): a bowed saw stack."""
    f = hz(midi)
    d = length
    r = rng(seed)
    x = np.zeros(n_samples(d))
    for v in range(5):
        x += saw(f * 2 ** (r.uniform(-0.09, 0.09) / 12), d)
    x = lowpass(x / 5, 3600, 2)
    x = peak_eq(x, 900, 4, 1.0)
    scrape = bandpass(white(d, seed), 2800, 1.5) * env_perc(d, 0.001, 0.02) * 0.5
    return (x + scrape) * env_adsr(d, 0.004, 0.06, 0.5, 0.03) * 0.85


def brass_hit(midis, seed):
    d = 0.42
    r = rng(seed)
    x = np.zeros(n_samples(d))
    for mm in midis:
        for v in range(4):
            x += saw(hz(mm) * 2 ** (r.uniform(-0.1, 0.1) / 12), d) * 0.25
    x = drive(x, 1.8)
    x = lowpass(x, 3600, 2)
    x = peak_eq(x, 1300, 5, 1.0)
    return x * env_adsr(d, 0.006, 0.12, 0.35, 0.18) * 0.62


def ring_bell(seed):
    d = 1.8
    t = np.arange(n_samples(d)) / SR
    tone = fm(1180, 1180 * 1.41, 3.0 * np.exp(-t / 0.25), d) * np.exp(-t / 0.6)
    tone += 0.4 * fm(2950, 2950 * 1.73, 1.5 * np.exp(-t / 0.15), d) * np.exp(-t / 0.35)
    strike = highpass(white(0.006, seed), 3000) * 0.5
    tone[:len(strike)] += strike
    return onset(tone) * 0.4


def riser(length, seed):
    x = sweep_bandpass(white(length, seed), 400, 6500, 2.5)
    u = np.linspace(0, 1, len(x))
    close = np.clip((len(x) - np.arange(len(x))) / n_samples(0.04), 0, 1)
    return x * u ** 2 * close * 0.4


def crowd(seed, accents):
    """The arena's crowd, exactly one loop long and periodic (it never seams): noise
    drawn in the frequency domain at N samples, shaped by the formants of a roaring
    crowd (no voices, no words), its level breathing slowly and swelling after each
    accent (wrapped modulo N)."""
    N = n_samples(LOOP)
    r = rng(seed)
    f = np.fft.rfftfreq(N, 1 / SR)
    spec = (r.standard_normal(len(f)) + 1j * r.standard_normal(len(f))) / np.sqrt(np.maximum(f, 20))
    shape = np.zeros(len(f))
    for center, width, gain in ((320, 0.7, 1.0), (850, 0.6, 0.8), (2300, 0.5, 0.45), (5200, 0.6, 0.15)):
        shape += gain * np.exp(-0.5 * (np.log2(np.maximum(f, 1) / center) / width) ** 2)
    roar = np.fft.irfft(spec * shape, N)
    roar /= np.max(np.abs(roar)) + 1e-12
    t = np.arange(N) / SR
    # Slow breathing: whole numbers of cycles over the loop.
    level = 0.55 + 0.12 * np.sin(2 * np.pi * 2 * t / LOOP) + 0.08 * np.sin(2 * np.pi * 5 * t / LOOP + 1.3)
    for t0, size in accents:
        dt = (t - t0) % LOOP
        level += size * (dt / 0.25) * np.exp(1 - dt / 0.25) * (dt < 3.0)
    return roar * level


# --------------------------------------------------------------------------
# The score

# The gloves' groove in each block, sixteenth by sixteenth: '.' none, 'g' a ghost
# punch, 'j' a jab, 'x' a cross, 'h' a hook, 'B' a body blow (the heaviest).
GLOVES = {
    0: "j.g.x..gj.g.B...",
    1: "j.gjx..gj.gjB.h.",
    2: "jgjgx.gjjgjgB.hx",
    3: "j.g.x..gj.g.B...",
}
WEIGHT = {"g": 0.3, "j": 0.55, "x": 0.75, "h": 0.85, "B": 1.0}
FLURRY = "jjxjjxhhjxjxhBBB"          # bar 16: the flurry into the bell

# The kick: a syncopated fighter's step, not four on the floor.
KICKS = {0: (0, 6, 10), 1: (0, 3, 6, 10, 14), 2: (0, 3, 6, 8, 10, 14), 3: (0, 10)}

# Bass and strings, one note a stroke (offsets from D in the Phrygian scale; '.' a
# rest, '-' the note held on): a severe ostinato, the flat second biting at the end
# of each two bars.
OSTINATO = [
    "0.0.0.03..0.0.5.",
    "0.0.0.03..0.7.1.",
]


def riff(bar):
    return OSTINATO[(bar - 1) % 2]


def brass_chord(bar):
    # D power chord; in the last bar of a block, E flat over D (the Phrygian bite).
    if bar % 4 == 0:
        return [D3 + EB, D3 + 7 + EB, D4 + EB]
    return [D3, D3 + 7, D4]


def render():
    total = LOOP + TAIL
    n = n_samples(total)
    L, R = np.zeros(n), np.zeros(n)
    send = np.zeros(n)
    kick_times, accents = [], []

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

    # The bell rings the round in.
    bell = ring_bell(SEED)
    stereo(at(1, 0), bell, 1.0, 0.0, 0.6)
    stereo(at(1, 3), bell, 0.85, 0.0, 0.6)
    accents.append((at(1, 0), 0.35))

    k = kick(SEED)
    for bar in range(1, BARS + 1):
        b = block(bar)
        for s in (KICKS[b] if bar not in (13, 14) else (0,)):
            kick_times.append(at(bar, s))
            stereo(at(bar, s), k, 1.0)

    # The gloves: the groove itself; the flurry at the end.
    for bar in range(1, BARS + 1):
        row = FLURRY if bar == 16 else GLOVES[block(bar)]
        for s, c in enumerate(row):
            if c == ".":
                continue
            w = WEIGHT[c]
            pan = {"j": -0.3, "x": 0.3, "h": 0.15 if s % 2 else -0.15, "B": 0.0, "g": -0.1}[c]
            stereo(at(bar, s), glove(SEED + bar * 16 + s, w), 1.0, pan, 0.25)
            if c == "B":
                accents.append((at(bar, s), 0.25))

    # War drums: low toms, eighths in the third block, fills at the end of each block.
    for bar in range(1, BARS + 1):
        b = block(bar)
        if b == 2 or bar in (13, 14):
            for s in range(0, 16, 2):
                stereo(at(bar, s), tom(SEED + bar * 8 + s, D2 if s % 4 else D2 - 5, 0.8 if s % 4 else 1.0), 1.0, -0.4 if s % 4 else 0.4, 0.3)
        if bar % 4 == 0 and bar != 16:
            for i, s in enumerate((12, 13, 14, 15)):
                stereo(at(bar, s), tom(SEED + 900 + bar * 4 + i, D2 + 7 - 2 * i), 1.0, 0.5 - 0.33 * i, 0.3)

    # Snare on 2 and 4 from the second block; the roll in the last bar.
    for bar in range(5, 13):
        for s in (4, 12):
            stereo(at(bar, s), snare(SEED + bar), 1.0, 0.0, 0.45)
    for s in range(16):
        g = 0.3 + 0.7 * s / 15
        stereo(at(16, s), snare(SEED + 600 + s), 0.75 * g, 0.05, 0.3)

    # Hats.
    for bar in range(5, 13):
        for s in range(16):
            stereo(at(bar, s), hat(SEED + bar * 31 + s), 1.0 if s % 2 else 0.55, 0.35)
            if block(bar) == 2 and s % 4 == 2:
                stereo(at(bar, s), hat(SEED + bar * 37 + s, True), 1.0, -0.35)

    # Bass and low strings: the ostinato (strings an octave up in the third block).
    bass = np.zeros(n)
    for bar in range(1, BARS + 1):
        if bar in (13, 14):
            continue
        row = riff(bar)
        for s, c in enumerate(row):
            if c in ".-":
                continue
            step = int(c)
            mm = D2 + step
            held = 1
            while s + held < 16 and row[s + held] == "-":
                held += 1
            length = STEP * (0.85 * held)
            put(bass, at(bar, s), bass_note(mm - 12, length, SEED + bar * 16 + s))
            octave = 12 if block(bar) == 2 else 0
            stereo(at(bar, s), strings(mm + octave, length, SEED + bar * 17 + s), 1.0, 0.2, 0.3)
    # The kick ducks the bass.
    t = np.arange(n) / SR
    duck = np.ones(n)
    for t0 in kick_times + [tk + LOOP for tk in kick_times[:3]]:
        i = int(t0 * SR)
        if i >= n:
            continue
        seg = t[i:min(n, i + n_samples(0.3))] - t0
        duck[i:i + len(seg)] = np.minimum(duck[i:i + len(seg)], 1 - 0.65 * np.exp(-seg / 0.08))
    bass *= duck
    L += bass
    R += bass

    # Brass hits on the accents of the second and third blocks.
    for bar in range(5, 13):
        hits = (0, 6, 10) if block(bar) == 1 else (0, 3, 6, 10, 14)
        for i, s in enumerate(hits):
            stereo(at(bar, s), brass_hit(brass_chord(bar), SEED + bar * 7 + i), 1.0, -0.2 if i % 2 else 0.2, 0.4)
        accents.append((at(bar, 0), 0.12))

    # The sweep up into the bell.
    stereo(at(15, 0), riser(2 * BAR, SEED), 1.0, 0.0, 0.35)

    # A big arena: a longer, brighter room than the tower's halls.
    wet = hall(send, wet=1.0, rt60=2.2, brightness=0.6)[:n]
    L += 0.45 * wet
    R += 0.45 * np.concatenate([np.zeros(n_samples(0.017)), wet])[:n]

    # Seamless: the tail past the end is folded onto the start.
    cut = n_samples(LOOP)
    for buf in (L, R):
        buf[:n - cut] += buf[cut:]
    L, R = L[:cut].copy(), R[:cut].copy()

    # The crowd, periodic by construction, a little wider than the ring.
    roar = crowd(SEED, accents)
    roar_b = np.roll(roar, n_samples(0.37))
    L += 0.11 * roar
    R += 0.11 * roar_b
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
