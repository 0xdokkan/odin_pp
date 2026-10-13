"""The custodian (bishop): red-and-black robes, a mitre, a gilded crozier.
He levitates and shields his allies. Holy, hushed, golden (SOUND_SPEC.md).

Every bishop sound is built from the same four materials, so the character
keeps one voice while each action stays its own:

- the robe: heavy wool and velvet, a slow pink-noise band in the low mids
  with a fibrous flutter and a thin silk grit on top (heavier and slower than
  the pilgrim's cloak);
- the crozier: a hardwood shaft (free-free bar modes, 230-1300 Hz, dead within
  ~150 ms) capped by a gilded brass crook (inharmonic metal modes) hung with
  small gilt pendants that rattle like chain links (short inharmonic pings on
  D-Phrygian roots, A6-A7, each with a tick of contact);
- the levitation: an airy breath over a hushed hum on D3 and A3 whose
  doublets beat slowly, with a faint high sheen of air;
- the holy bell: church-bell partials on D (hum, prime, minor-third tierce,
  fifth, nominal, eleventh, twelfth...), tuned equal-tempered so they agree
  with the choir; on D every partial is a note of D Phrygian, and each
  partial is a doublet that beats slowly from its maximum at the strike.

And the paper card under him: a light papery glide when he punts it, a
crumple when he is struck, a crease and a slap when he falls.

Recipes are dry; the build adds the stone hall.
"""
import math

import numpy as np

from dsp import *  # noqa: F401,F403
from registry import sound


# --------------------------------------------------------------------------
# Small utilities

def _rms_unit(x):
    return x / (np.sqrt(np.mean(x ** 2)) + 1e-12)


def _pk(x, p=1.0):
    m = float(np.max(np.abs(x))) if len(x) else 0.0
    return x * (p / m) if m > 0 else x


def _ease_in(x, ms):
    """Raised-cosine onset of `ms` milliseconds (no digital click)."""
    n = min(len(x), int(ms * SR / 1000))
    if n > 1:
        x = x.copy()
        x[:n] *= 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, n))
    return x


def _env(duration, points):
    """Smooth envelope: raised-cosine segments through (t, value) points."""
    t = time_axis(duration)
    ts = np.array([p[0] for p in points], float)
    vs = np.array([p[1] for p in points], float)
    if len(ts) == 1:
        return np.full(len(t), vs[0])
    idx = np.clip(np.searchsorted(ts, t, side="right") - 1, 0, len(ts) - 2)
    t0, t1 = ts[idx], ts[idx + 1]
    u = np.clip((t - t0) / np.maximum(t1 - t0, 1e-9), 0, 1)
    u = 0.5 - 0.5 * np.cos(np.pi * u)
    e = vs[idx] + (vs[idx + 1] - vs[idx]) * u
    e[t < ts[0]] = vs[0]
    e[t >= ts[-1]] = vs[-1]
    return e


def _smooth_noise(n, cutoff, seed):
    """Slow random wobble in -1..1 (fibres, turbulence, stick-slip)."""
    return _pk(lowpass(rng(seed).standard_normal(n), cutoff, 2))


def _moving_band(x, centers, q=1.0):
    """Band-pass whose centre follows (t, Hz) points (time-varying STFT)."""
    pts = np.array(centers, float)
    if len(pts) == 1:
        pts = np.array([pts[0], [1e3, pts[0][1]]])
    sig = (1.0 / max(q, 0.05)) / 2.355

    def gain(f, t):
        c = float(np.interp(t, pts[:, 0], pts[:, 1]))
        return np.exp(-0.5 * (np.log2(np.maximum(f, 1e-3) / c) / sig) ** 2)
    return stft_filter(x, gain)


def _moving_lowpass(x, cutoffs, order=2):
    pts = np.array(cutoffs, float)

    def gain(f, t):
        c = float(np.interp(t, pts[:, 0], pts[:, 1]))
        return 1 / np.sqrt(1 + (f / c) ** (2 * order))
    return stft_filter(x, gain)


def _modes(duration, modes, seed, attack_ms=0.5):
    """Damped sinusoids [(Hz, time constant s, amp)] with a soft onset."""
    t = time_axis(duration)
    r = rng(seed)
    x = np.zeros_like(t)
    for f, d, a in modes:
        if f <= 20 or f >= 0.45 * SR:
            continue
        x += a * np.sin(2 * np.pi * f * t + r.uniform(0, 2 * np.pi)) * np.exp(-t / max(d, 1e-4))
    return _ease_in(x, attack_ms)


def _additive(freq, n, seed, max_hz=6000.0, rolloff=1.0):
    """Band-limited saw-like tone (harmonics 1/k**rolloff, random phases) on a
    per-sample frequency path: a clean source for the choir and the hum."""
    f = np.broadcast_to(np.asarray(freq, float), (n,))
    p = np.cumsum(f) / SR
    r = rng(seed)
    kmax = max(1, int(max_hz / max(float(np.max(f)), 1.0)))
    out = np.zeros(n)
    for k in range(1, kmax + 1):
        out += np.sin(2 * np.pi * (k * p + r.random())) / k ** rolloff
    return out


def _mixdown(duration, layers, peak=0.8):
    """Sums named layers [(name, full-length array, gain)] and sets the peak."""
    out = silence(duration)
    for _, x, g in layers:
        out[:min(len(out), len(x))] += g * x[:len(out)]
    return _pk(out, peak)


def _at(duration, t0, x):
    return place(duration, [(t0, x, 1.0)])


def _et(semitones):
    return 2 ** (semitones / 12)


# --------------------------------------------------------------------------
# The custodian's materials

_BAR = (1.0, 2.756, 5.404, 8.933)  # free-free bar: the staff

# D-Phrygian roots of the gilt pendants: A6 C7 D7 Eb7 F7 G7 A7.
_GILT_NOTES = (1760.0, 2093.0, 2349.3, 2489.0, 2793.8, 3136.0, 3520.0)

# A small cast gilt ornament: inharmonic partials (ratio, amp, decay factor),
# the upper ones dying first, so a ping is a short rattle, not a tuned note.
_PENDANT = ((1.0, 1.0, 1.0), (1.59, 0.6, 0.7), (2.14, 0.45, 0.5), (2.83, 0.3, 0.35))

# Church-bell partials relative to the prime, equal-tempered so the bell
# agrees with the choir: hum, prime, minor-third tierce, fifth, nominal,
# eleventh, twelfth, double octave, a fourth and a fifth above... On D they
# are D, D, F, A, D, G, A, D, G, A: all D Phrygian. (ratio, decay factor, amp)
_BELL = ((0.5, 1.0, 0.5), (1.0, 0.7, 0.75), (_et(3), 0.55, 0.55), (_et(7), 0.4, 0.3),
         (2.0, 0.45, 0.65), (_et(17), 0.26, 0.3), (_et(19), 0.22, 0.24), (4.0, 0.14, 0.16),
         (_et(29), 0.09, 0.1), (_et(31), 0.08, 0.07))

# Vowels (formant noise and voices; never words).
_AH = ((750, 3.2, 1.0), (1150, 3.2, 0.62), (2550, 3.8, 0.3), (3300, 4.0, 0.16), (230, 0.8, 0.2))
_HUM = ((260, 1.2, 1.0), (900, 2.0, 0.22), (2300, 3.0, 0.06))
_EXHALE = ((800, 2.0, 0.45), (1600, 2.5, 0.8), (2600, 3.0, 1.0), (3800, 2.5, 0.45))


def _robe(duration, seed, levels, centers=((0.0, 700.0),), q=1.0, silk=0.08):
    """The heavy red-and-black robe: pink noise in a slow low-mid band with a
    fibrous flutter, a thin silk grit on top (3.5-9 kHz)."""
    n = n_samples(duration)
    body = _rms_unit(_moving_band(pink(duration, seed), centers, q=q))
    grit = _rms_unit(lowpass(highpass(white(duration, seed + 1), 3500, 2), 9000, 2))
    fib = 1 + 0.4 * _smooth_noise(n, 25.0, seed + 2)
    return _env(duration, levels) * fib * (body + silk * grit)


def _robe_slap(duration, seed, tau=0.018, center=1100.0, flap=0.035):
    """The robe snapping on a blow: a quick band of cloth noise with a muffled
    low flap under it, then a smaller second flap of the hem."""
    t = time_axis(duration)
    x = lowpass(bandpass(white(duration, seed), center, 0.7), 5000, 2) * np.exp(-t / tau)
    low = lowpass(white(duration, seed + 1), 450, 2) * np.exp(-t / (tau * 1.5))
    y = _pk(_ease_in(x, 0.8)) + 0.6 * _pk(_ease_in(low, 1.5))
    return place(duration, [(0.0, y, 1.0), (flap, y, 0.35)])


def _staff_knock(duration, seed, base=235.0, tau=0.03, tick=0.5, slope=0.7):
    """The crozier's hardwood shaft struck: free-free bar modes plus a cross
    mode, and the contact tick of the wood. Dead within ~150 ms. A lower
    `slope` keeps more of the upper modes (struck nearer the tip)."""
    r = rng(seed)
    modes = [(base * q * (1 + r.uniform(-0.02, 0.02)), tau / (1 + 0.8 * i), 1.0 / (1 + slope * i))
             for i, q in enumerate(_BAR)]
    modes.append((base * 3.6 * (1 + r.uniform(-0.03, 0.03)), tau * 0.35, 0.4))
    body = _pk(_modes(duration, modes, seed + 1, 0.3))
    t = time_axis(duration)
    click = lowpass(highpass(white(duration, seed + 2), 1500, 2), 7000, 2) * np.exp(-t / 0.0012)
    # Whatever the buffer length, it never stops on a step.
    return fade(body + tick * _pk(_ease_in(click, 0.1)), 0.0, min(0.04, 0.3 * duration))


def _gilt_ring(duration, seed, base=1760.0, decay=0.2, count=6):
    """The gilded brass crook: inharmonic metal modes, the high ones dying
    first (darker as it decays)."""
    return _pk(_modes(duration, metal_modes(base, count, 1.0, decay, seed), seed + 1, 0.3))


def _crook(duration, seed, decay=0.2, brass=0.6):
    """The gilded crook struck: the custodian's holy bell in miniature (bell
    partials on D6, so the crozier rings in D Phrygian) over inharmonic brass
    modes that give the clank; the highs die first."""
    bell = _bell(duration, 1174.66, seed, decay=decay, attack_ms=0.4, beat=(1.5, 4.0), clink=0.15)
    metal = _gilt_ring(duration, seed + 5, base=1650.0, decay=decay * 0.7, count=6)
    return _pk(_pk(bell) + brass * metal)


def _tinkle(duration, seed, times, level=1.0, decay=(0.025, 0.07), pairs=0.45):
    """The gilt pendants knocking together: each knock a tick of contact and a
    short inharmonic ping on a D-Phrygian root; some knocks come in pairs
    8-20 ms apart, like the links of a little chain."""
    r = rng(seed)
    events = []
    k = 0
    for t0 in times:
        hits = [(t0, 1.0)]
        if r.random() < pairs:
            hits.append((t0 + r.uniform(0.008, 0.02), r.uniform(0.4, 0.75)))
        for tt, rel in hits:
            k += 1
            if tt >= duration:
                continue
            f = _GILT_NOTES[int(r.integers(len(_GILT_NOTES)))] * (1 + r.uniform(-0.004, 0.004))
            d = r.uniform(*decay)
            length = min(6.9 * d + 0.01, max(0.01, duration - tt))
            modes = [(f * q * (1 + r.uniform(-0.01, 0.01)), d * dk, a) for q, a, dk in _PENDANT]
            ping = _pk(_modes(length, modes, seed + 20 + k, 0.35))
            # The tick: a ~1 ms burst filtered after its envelope (so it stays
            # in 5-9 kHz), started 0.5 ms in so the filter's onset is smooth.
            tl = time_axis(length) - 0.0005
            burst = white(length, seed + 400 + k) * np.where(tl >= 0, np.exp(-np.maximum(tl, 0) / 0.00035), 0.0)
            tick = bandpass(burst, 7000, 1.4)
            ping = fade(ping + 0.55 * _pk(tick), 0.0, min(0.004, 0.2 * length))
            events.append((tt, ping, level * rel * r.uniform(0.35, 1.0)))
    return place(duration, events)


def _bell(duration, prime, seed, decay=1.0, bright=1.0, attack_ms=1.5, beat=(0.7, 2.2), clink=0.3):
    """The custodian's holy bell (church-bell partials on `prime`), each
    partial a doublet that beats slowly. The two halves of a doublet share
    one phase, so every beat starts at its maximum on the strike; a clink of
    the clapper marks the contact."""
    r = rng(seed)
    t = time_axis(duration)
    x = np.zeros_like(t)
    for ratio, dk, amp in _BELL:
        f = prime * ratio * (1 + r.uniform(-0.0015, 0.0015))
        a = amp * bright ** math.log2(ratio)
        b = r.uniform(*beat)
        ph = r.uniform(0, 2 * np.pi)
        if f + b >= 0.45 * SR:
            continue
        tau = max(decay * dk, 1e-4)
        x += 0.55 * a * np.sin(2 * np.pi * (f - b / 2) * t + ph) * np.exp(-t / tau)
        x += 0.45 * a * np.sin(2 * np.pi * (f + b / 2) * t + ph) * np.exp(-t / (0.85 * tau))
    x = _pk(_ease_in(x, attack_ms))
    if clink <= 0:
        return x
    c = bandpass(white(duration, seed + 2), prime * 4, 0.8) * np.exp(-t / 0.002)
    return x + clink * _pk(_ease_in(c, 0.3))


def _levitate(duration, seed, levels, bend=((0.0, 0.0),), air=((0.0, 600.0),), tone=0.35,
              flutter=(0.25, 9.0)):
    """The levitation: an airy breath (pink noise in a soft moving band) over
    a hushed hum on D3 and A3 ('mm'-shaped, doublets beating slowly).
    `bend` is a pitch path in semitones; `flutter` (depth, Hz) the breath's
    unsteadiness."""
    n = n_samples(duration)
    t = time_axis(duration)
    bp = np.array(bend, float)
    ratio = 2 ** (np.interp(t, bp[:, 0], bp[:, 1]) / 12)
    hum = np.zeros(n)
    for i, (f, a, beat) in enumerate(((146.83, 1.0, 0.45), (220.0, 0.6, 0.6), (293.66, 0.2, 0.8))):
        hum += a * _additive(f * ratio, n, seed + 1 + i, max_hz=2000, rolloff=2.2)
        hum += a * _additive((f + beat) * ratio, n, seed + 11 + i, max_hz=2000, rolloff=2.2)
    hum = formant(hum, _HUM)
    breath = _rms_unit(_moving_band(pink(duration, seed + 5), air, q=0.8))
    fl = 1 + flutter[0] * _smooth_noise(n, flutter[1], seed + 6)
    return _env(duration, levels) * (tone * _rms_unit(hum) + breath * fl)


def _breath(duration, seed, levels, vowel=_EXHALE):
    """A breathy exhale-hiss (formant-shaped noise, no voice)."""
    n = n_samples(duration)
    x = _rms_unit(formant(white(duration, seed), vowel))
    turb = 1 + 0.3 * _smooth_noise(n, 35.0, seed + 1)
    return _env(duration, levels) * turb * x


def _thud(duration, seed, f_hi=160.0, f_lo=95.0, tau=0.025, slap=0.4, muffle=350.0,
          sine=0.45, mass=1.0, mass_tau=0.028, mass_center=120.0):
    """A blow on a robed body. The body is a muffled noise mass (band-passed
    and low-passed noise, 60-350 Hz, quick decay); a short falling sine gives
    it weight (`sine` keeps it under the mass, except for the magic ward,
    which is tuned); a slap under 3 ms. No ringing."""
    t = time_axis(duration)
    f = f_lo + (f_hi - f_lo) * np.exp(-t / 0.02)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / tau)
    m = lowpass(bandpass(white(duration, seed), mass_center, 0.7), muffle, 2) * np.exp(-t / mass_tau)
    m = _ease_in(m, 1.5)
    snap = lowpass(highpass(white(duration, seed + 1), 1000, 2), 6000, 2) * np.exp(-t / 0.0015)
    x = sine * _pk(_ease_in(body, 0.5)) + mass * _pk(m) + slap * _pk(_ease_in(snap, 0.1))
    return fade(x, 0.0, min(0.04, 0.3 * duration))


def _crumple(duration, seed, t0, t1, rate=200.0, grain=(0.01, 0.02), envelope=None, crease_at=None):
    """The paper card crumpling: grains of band-passed noise 1.5-8 kHz,
    10-25 ms each, plus one deeper crease. By default densest at the blow
    (t0) and thinning out; `envelope` (fn of 0..1) shapes the density."""
    env = envelope if envelope is not None else (lambda u: (1 - u) ** 1.5)
    times = random_times(duration, rate, seed, start=t0, end=t1, envelope=env)
    a = grains(duration, times[::2], grain[0], seed + 1, band=(2000, 7000))
    b = grains(duration, times[1::2], grain[1], seed + 2, band=(1500, 5000))
    c = grains(duration, [t0 + 0.001 if crease_at is None else crease_at], 0.024, seed + 3, band=(1500, 3500))
    return _pk(a + 0.8 * b + 0.7 * c)


def _glide(duration, seed, t0, t1, top=3300.0, bottom=1400.0, grit=0.55, attack=0.004):
    """The paper card on its small iron base gliding across stone after the
    crozier's punt: a dense papery band (1-5 kHz) whose pitch and level follow
    the speed (fast at the punt, easing to a stop at t1), a stick-slip rasp and
    fine stone grit. `attack` is the time the card takes to get going."""
    t = time_axis(duration)
    n = len(t)
    u = np.clip((t - t0) / (t1 - t0), 0, 1)
    speed = 0.25 + 0.75 * (1 - u) ** 1.4
    gate = np.clip((t - t0) / attack, 0, 1) * np.clip((t1 - t) / 0.012, 0, 1)
    env = speed * gate
    ts = np.linspace(0, duration, 48)
    us = np.clip((ts - t0) / (t1 - t0), 0, 1)
    centers = list(zip(ts, bottom + (top - bottom) * (1 - us) ** 1.4))
    band = _rms_unit(_moving_band(white(duration, seed), centers, q=0.85))
    rasp = 1 + 0.45 * _smooth_noise(n, 70.0, seed + 1)
    g = crackle(duration, 300 + 3000 * env, seed + 2, decay=0.0003)
    g = _rms_unit(bandpass(g, 3500, 0.7))
    return env * (band * rasp + grit * g)


def _card_settle(duration, seed):
    """The card coming to rest: a soft paper tap and the small iron base's
    dull knock on stone (three short modes)."""
    t = time_axis(duration)
    tap = bandpass(white(duration, seed), 2400, 0.8) * np.exp(-t / 0.004)
    base = _modes(duration, [(175.0, 0.016, 1.0), (440.0, 0.008, 0.45), (1010.0, 0.004, 0.25)], seed + 1, 0.6)
    return 0.7 * _pk(_ease_in(tap, 0.3)) + 0.6 * _pk(base)


def _choir(duration, seed, voices, vowel=_AH, vibrato=0.0035, breath=0.3):
    """Choir-like pad: per voice three detuned band-limited saws, each with
    its own vibrato and drift, all through an 'ah' vowel; a breath of noise
    through the same vowel. voices: [(Hz or per-sample Hz array, amp)]."""
    n = n_samples(duration)
    t = time_axis(duration)
    r = rng(seed)
    src = np.zeros(n)
    for vi, (freq, amp) in enumerate(voices):
        base = np.broadcast_to(np.asarray(freq, float), (n,))
        for ci, cents in enumerate((-7.0, 0.0, 6.0)):
            vib = 1 + vibrato * np.sin(2 * np.pi * r.uniform(4.6, 5.8) * t + r.uniform(0, 2 * np.pi))
            drift = 1 + 0.0015 * _smooth_noise(n, 3.0, seed + 300 + vi * 3 + ci)
            f = base * 2 ** (cents / 1200) * vib * drift
            src += amp * _additive(f, n, seed + 100 + vi * 3 + ci, max_hz=6000, rolloff=1.0)
    voiced = _rms_unit(formant(src, vowel))
    air = _rms_unit(formant(white(duration, seed + 3), vowel))
    return voiced + breath * air


# --------------------------------------------------------------------------
# The sounds

@sound("bishop_move", loudness=-22, wet=0.3, marks=(0.26, 0.68))
def bishop_move(seed):
    """Rises on the levitation hum, punts the card with a faint crozier knock
    at 0.26, the card glides to a stop at 0.68 (a soft tap as it settles);
    robe swish on the push, the hem settles after. The layers keep to their
    own bands: the hum on D3/A3, the robe 450-1000 Hz, the glide 1.4-3.3 kHz,
    a faint sheen of air above 3 kHz."""
    D = 1.0
    # The levitation gathers, gives the punt a moment, then surges as the card
    # starts to glide.
    lv = [(0, 0), (0.06, 0.2), (0.22, 0.8), (0.26, 0.7), (0.34, 1.0), (0.55, 0.8), (0.72, 0.5), (0.96, 0)]
    hum = _levitate(D, seed, levels=lv, bend=[(0, -2.0), (0.26, 0.0), (D, 0.0)],
                    air=[(0, 320), (0.26, 850), (0.68, 650), (D, 480)], tone=0.9)
    sheen = _env(D, lv) * _rms_unit(bandpass(white(D, seed + 60), 5000, 0.6))
    # The swish follows the push: it gives way to the knock, crests as the card
    # gets going; the hem swings once more after the stop.
    robe = _robe(D, seed + 10, levels=[(0, 0), (0.12, 0.15), (0.22, 0.5), (0.26, 0.4), (0.32, 1.0), (0.48, 0.3),
                                       (0.62, 0.15), (0.68, 0.12), (0.78, 0.45), (0.94, 0)],
                 centers=[(0, 450), (0.28, 1000), (0.5, 650), (0.72, 900), (D, 600)])
    knock = _staff_knock(0.25, seed + 20, base=250.0, tau=0.024, tick=0.7, slope=0.35)
    jingle = _tinkle(D, seed + 30, [0.262, 0.28, 0.3, 0.69], decay=(0.03, 0.07))
    # The card takes ~18 ms to get going, so the knock's tick stands clear.
    glide = _glide(D, seed + 40, 0.26, 0.68, attack=0.018)
    settle = _card_settle(0.12, seed + 50)
    return _mixdown(D, [("hum", hum, 0.3), ("sheen", sheen, 0.07), ("robe", robe, 0.45),
                        ("glide", glide, 0.4), ("knock", _at(D, 0.26, knock), 1.5),
                        ("jingle", jingle, 0.16), ("settle", _at(D, 0.684, settle), 1.3)])


@sound("bishop_protect", loudness=-19, wet=0.4, marks=(0.5,))
def bishop_protect(seed):
    """An invocation: a choir-like 'ah' (D3-A3-D4-F4-A4; a Phrygian Eb4 sinks
    to D4) swells as he rises and holds its breath just before he plants the
    crozier at 0.5; the ward's bell (D, all partials in D Phrygian) rings out
    on the strike, then the choir blooms open under it."""
    D = 1.0
    land = 0.5
    t = time_axis(D)
    neigh = 293.66 * 2 ** (np.interp(t, [0, 0.42, 0.5, D], [1, 1, 0, 0]) / 12)
    voices = [(146.83, 1.0), (220.0, 0.75), (neigh, 0.6), (349.23, 0.5), (440.0, 0.35)]
    choir = _choir(D, seed, voices)
    # The bloom opens after the strike, so the bell owns the moment of contact.
    choir = _moving_lowpass(choir, [(0, 900), (0.45, 2000), (0.5, 1600), (0.6, 3000), (0.75, 2400), (D, 1800)])
    choir *= _env(D, [(0, 0), (0.12, 0.08), (0.32, 0.35), (0.44, 1.0), (0.5, 0.45), (0.62, 0.32), (0.8, 0.2),
                      (0.97, 0)])
    bell = _bell(D - land, 587.33, seed + 5, decay=0.7) * _env(D - land, [(0, 1), (0.34, 1), (0.5, 0)])
    plant = _staff_knock(0.25, seed + 6, base=205.0, tau=0.03, tick=0.3)
    ward = _thud(0.4, seed + 7, f_hi=150.0, f_lo=73.4, tau=0.07, slap=0.0, muffle=200.0,
                 sine=1.0, mass=0.6, mass_tau=0.042)
    jingle = _tinkle(D, seed + 8, [0.503, 0.512, 0.53, 0.56, 0.6], decay=(0.04, 0.09))
    robe = _robe(D, seed + 9, levels=[(0, 0), (0.1, 0.2), (0.25, 1.0), (0.42, 0.4), (0.52, 0.5), (0.7, 0)],
                 centers=[(0, 500), (0.28, 1100), (0.5, 700), (D, 600)])
    # The paper card flexes as the crozier is planted beside it.
    card = _pk(grains(D, [0.501, 0.507], 0.012, seed + 10, band=(1500, 4000)))
    return _mixdown(D, [("choir", choir, 0.3), ("bell", _at(D, land, bell), 0.95),
                        ("plant", _at(D, land, plant), 0.6), ("ward", _at(D, land, ward), 0.3),
                        ("jingle", jingle, 0.08), ("robe", robe, 0.1), ("card", card, 0.18)])


@sound("bishop_attack", loudness=-18, wet=0.25, marks=(0.125,))
def bishop_attack(seed):
    """A short crozier swing (rising whoosh that crests early and dips before
    contact), a wooden-and-gilt knock at 0.125 (shaft modes + the crook's
    small metal ring) on the front of the card, the card crumples a little,
    the pendants jangle; the robe follows the arm."""
    D = 0.9
    hit = 0.125
    swing = _rms_unit(lowpass(_moving_band(pink(D, seed), [(0, 380), (0.06, 520), (0.1, 1500), (0.14, 1100),
                                                            (0.3, 600)], q=1.3), 6000, 2))
    swing *= _env(D, [(0, 0), (0.03, 0.04), (0.075, 0.5), (0.1, 1.0), (0.118, 0.35), (0.125, 0.1), (0.2, 0.04),
                      (0.32, 0)])
    n_imp = D - hit
    knock = _staff_knock(0.35, seed + 1, base=225.0, tau=0.055, tick=0.45)
    # The crook rings up through the shaft over ~3 ms (the shaft's tick
    # carries the contact itself).
    ring = _ease_in(_crook(n_imp, seed + 2, decay=0.3), 3.0)
    body = _thud(0.3, seed + 3, f_hi=180.0, f_lo=95.0, tau=0.025, slap=0.2)
    crumple = _crumple(D, seed + 4, hit, hit + 0.05, rate=260.0)
    # The robe follows the arm, gives way at contact, then flaps through.
    robe = _robe(D, seed + 5, levels=[(0, 0), (0.04, 0.35), (0.1, 0.7), (0.125, 0.3), (0.165, 0.65), (0.3, 0.2),
                                      (0.44, 0.35), (0.62, 0)],
                 centers=[(0, 600), (0.12, 1100), (0.3, 700), (0.45, 900), (D, 600)])
    jingle = _tinkle(D, seed + 6, [0.07, 0.128, 0.14, 0.17, 0.205, 0.45], decay=(0.03, 0.08))
    # Shaft and card hit together; a soft saturation rounds their shared peak.
    # The crook rings on top, clean (no intermodulation with the knock), and
    # the whole impact fades out before its buffer ends.
    impact = drive(_pk(place(n_imp, [(0.0, knock, 0.7), (0.0, body, 0.25)])), 2.2) + 0.6 * pad_to(ring, n_imp)
    impact = fade(impact, 0.0, 0.06)
    return _mixdown(D, [("swing", swing, 0.13), ("impact", _at(D, hit, impact), 0.95),
                        ("crumple", crumple, 0.28), ("robe", robe, 0.18), ("jingle", jingle, 0.1)])


@sound("bishop_hurt", loudness=-18, wet=0.2, marks=(0.118,))
def bishop_hurt(seed):
    """Thud at 0.118 (a muffled body under the robe), the robes slap, the
    paper card crumples, the crozier's pendants rattle, a breathy exhale-hiss
    (no voice). The first 30 ms after the blow belong to the slap and the
    crumple; the hiss and the pendants come in after."""
    D = 0.75
    hit = 0.118
    # A soft saturation rounds the noise mass's random peak (keeps the crest
    # low enough for the loudness target without the limiter).
    thud = drive(_pk(_thud(0.35, seed, f_hi=155.0, f_lo=90.0, tau=0.025, slap=0.35)), 2.2)
    slap = _robe_slap(0.2, seed + 1)
    crumple = _crumple(D, seed + 2, hit + 0.004, hit + 0.074, rate=200.0)
    times = [hit + 0.03] + random_times(D, 26.0, seed + 3, start=hit + 0.035, end=0.5,
                                        envelope=lambda u: (1 - u) ** 1.2)
    jingle = _tinkle(D, seed + 4, times)
    hiss = _breath(D, seed + 5, levels=[(0, 0), (0.16, 0), (0.19, 1.0), (0.27, 0.55), (0.44, 0.12), (0.58, 0)])
    robe = _robe(D, seed + 6, levels=[(0, 0), (0.11, 0), (0.14, 0.4), (0.19, 0.7), (0.3, 0.25), (0.37, 0.4),
                                      (0.5, 0.1), (0.64, 0)],
                 centers=[(0, 800), (0.13, 1000), (0.36, 700), (D, 550)])
    # The robe snaps a hair after the body takes the blow (keeps the two
    # transients from stacking into one peak).
    return _mixdown(D, [("thud", _at(D, hit, thud), 0.65), ("slap", _at(D, hit + 0.003, slap), 0.42),
                        ("crumple", crumple, 0.4), ("jingle", jingle, 0.1), ("hiss", hiss, 0.12),
                        ("robe", robe, 0.13)])


@sound("bishop_death", loudness=-18, wet=0.35, marks=(0.118, 0.62))
def bishop_death(seed):
    """Struck at 0.118, the levitation fails (the hum sinks a little and dies
    in an unsteady breath), he drops to his knees at 0.3 and falls at 0.62:
    the card creases more and more and slaps the stone, the crozier clatters
    and its gilt crook rings, the body settles at 0.84, a last bell-like
    overtone fades."""
    D = 1.2
    hit = 0.118
    fall = 0.62
    sink = _levitate(D, seed, levels=[(0, 0), (0.04, 0.3), (0.118, 0.3), (0.18, 0.55), (0.42, 0.3), (0.62, 0)],
                     bend=[(0, 0.0), (0.14, 0.0), (0.62, -3.0)],
                     air=[(0, 700), (0.14, 800), (0.62, 260)], tone=0.6, flutter=(0.5, 18.0))
    sink = _moving_lowpass(sink, [(0, 3000), (0.14, 3000), (0.62, 500), (D, 500)])
    blow = _thud(0.35, seed + 1, f_hi=150.0, f_lo=90.0, tau=0.025, slap=0.35)
    slap = _robe_slap(0.2, seed + 2)
    crumple = _crumple(D, seed + 3, hit, hit + 0.08, rate=220.0)
    gasp = _breath(D, seed + 4, levels=[(0, 0), (0.15, 0), (0.18, 1.0), (0.26, 0.4), (0.38, 0)])
    knees = _thud(0.25, seed + 5, f_hi=130.0, f_lo=88.0, tau=0.022, slap=0.1, muffle=300.0)
    robe = _robe(D, seed + 6, levels=[(0, 0), (0.12, 0.5), (0.22, 0.8), (0.32, 0.6), (0.45, 0.2), (0.56, 0.45),
                                      (0.62, 0.3), (0.7, 0.4), (0.82, 0.1), (0.95, 0)],
                 centers=[(0, 800), (0.3, 650), (0.62, 900), (D, 500)])
    # The fall: the card creases ever faster as it folds, slaps the stone with
    # the body, the crozier clatters.
    body = _thud(0.4, seed + 7, f_hi=130.0, f_lo=88.0, tau=0.03, slap=0.25, muffle=320.0, mass_tau=0.035)
    card = _crumple(D, seed + 8, 0.55, fall + 0.004, rate=650.0, grain=(0.01, 0.025),
                    envelope=lambda u: u ** 1.5, crease_at=fall - 0.024)
    card *= _env(D, [(0, 0.35), (0.55, 0.35), (fall, 1.0), (D, 1.0)])
    card_slap = _robe_slap(0.15, seed + 9, tau=0.008, center=2000.0, flap=0.02)
    clatter = (_at(D, fall, _staff_knock(0.3, seed + 10, base=240.0, tau=0.03, tick=0.8))
               + 0.48 * _at(D, fall + 0.085, _staff_knock(0.25, seed + 11, base=252.0, tau=0.022, tick=0.6))
               + 0.2 * _at(D, fall + 0.145, _staff_knock(0.2, seed + 12, base=246.0, tau=0.018, tick=0.5)))
    crook = _crook(D - fall, seed + 13, decay=0.32, brass=0.8)
    crook *= _env(D - fall, [(0, 1), (0.26, 1), (0.44, 0)])  # lying on stone, it is damped
    jingle = _tinkle(D, seed + 14, [hit + 0.03, hit + 0.05, 0.3, fall + 0.03, fall + 0.088, fall + 0.1,
                                    fall + 0.15], decay=(0.035, 0.09))
    # The last overtone: the family's bell, struck softly by the fall, heard
    # only through its fifth and nominal (A5, D6); it only decays.
    t_ot = 0.64
    ot = _bell(D - t_ot, 587.33, seed + 15, decay=1.2, bright=0.5, attack_ms=40, clink=0.0)
    ot = _pk(bandpass(ot, 1020.0, 1.2)) * _env(D - t_ot, [(0, 1.0), (0.3, 0.85), (D - t_ot, 0)])
    # The body settles once more as it comes to rest (death_forward, 840 ms).
    rest = _card_settle(0.12, seed + 16)
    return _mixdown(D, [("sink", sink, 0.12), ("blow", _at(D, hit, blow), 0.55), ("slap", _at(D, hit, slap), 0.36),
                        ("crumple", crumple, 0.3), ("gasp", gasp, 0.06), ("knees", _at(D, 0.3, knees), 0.2),
                        ("robe", robe, 0.12), ("body", _at(D, fall, body), 0.3), ("card", card, 0.25),
                        ("card_slap", _at(D, fall, card_slap), 0.4), ("clatter", clatter, 0.65),
                        ("crook", _at(D, fall, crook), 0.26), ("jingle", jingle, 0.08),
                        ("overtone", _at(D, t_ot, ot), 0.15), ("rest", _at(D, 0.84, rest), 0.2)])
