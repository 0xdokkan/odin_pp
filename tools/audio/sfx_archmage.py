"""Family `archmage` - the demolitionist (see SOUND_SPEC.md).

A crowned archmage in black and red robes, a fire staff, a burning hand. He
floats: no footsteps, ever.

Family identity (heard in every sound):
  - the *ember chord*: the burning hand's furnace hum, detuned saws on D2, A2,
    D3 and a faint Eb3 (the Phrygian minor ninth, a little menace), plus a
    breathy noise buzz pulsed at the root's period, low-passed and flickering;
  - the *fire*: a roar of brown/pink turbulence under ~400-800 Hz with a slow
    lapping and a fast flutter;
  - the *embers*: sharp spark pops 2-9 kHz and a few woody snaps.
Each action then adds its own physical layers (robes, staff wood, body blow,
gilt crown, paper card, iron base). Everything is dry; the build adds the
stone hall.
"""
import math

import numpy as np

from dsp import *  # noqa: F401,F403
from dsp import (SR, bandpass, brown, convolve, drive, env_perc, env_points, fade, formant,
                 grains, highpass, lowpass, n_samples, pad_to, phase_of, pink, place,
                 random_times, rng, stft_filter, time_axis, white)
from registry import sound

# D Phrygian (D, Eb, F, G, A, Bb, C)
D2 = 73.42
D3 = 146.83
A3 = 220.0
D4 = 293.66
Eb4 = 311.13

# The ember chord: (ratio to the root, amplitude). D2 root -> A2, D3, Eb3, A3.
_EMBER_CHORD = ((1.0, 1.0), (1.4983, 0.5), (2.0, 0.42), (2.1189, 0.1), (3.0, 0.12))

# Flexural modes of a free thin ring (n = 2..7) relative to n = 2: the crown.
# A crown struck on its rim excites the middle modes most; highs die first.
_RING_RATIOS = (1.0, 2.83, 5.42, 8.77, 12.87, 17.71)
_CROWN_AMPS = (0.45, 1.0, 0.9, 0.7, 0.5, 0.38)
_CROWN_TAUS = (0.12, 0.095, 0.075, 0.055, 0.042, 0.032)


# --------------------------------------------------------------------------
# Small helpers

def _norm(x, peak=1.0):
    m = float(np.max(np.abs(x))) if len(x) else 0.0
    return x * (peak / m) if m > 1e-12 else x


def _finish(x, duration, peak=0.85):
    """Exact length, no click at either end, headroom."""
    x = pad_to(np.asarray(x, dtype=float), duration)
    x = fade(x, 0.002, 0.04)
    return _norm(x, peak)


def _path(points):
    """A log-interpolated frequency path through (t, Hz) points -> fn(t)."""
    ts = np.array([p[0] for p in points], dtype=float)
    fs = np.log(np.array([p[1] for p in points], dtype=float))
    return lambda t: float(np.exp(np.interp(t, ts, fs)))


def _swell(t, start, peak, end, rise=2.0, fall=1.5):
    """0 before `start`, rises to 1 at `peak`, falls to 0 at `end`."""
    up = np.clip((t - start) / max(peak - start, 1e-6), 0, 1) ** rise
    down = np.clip((end - t) / max(end - peak, 1e-6), 0, 1) ** fall
    return np.where(t < peak, up, down)


def _env_ad(duration, attack, tau, t0=0.0):
    """Linear attack from t0, then exponential decay (time constant tau)."""
    t = time_axis(duration) - t0
    up = np.clip(t / max(attack, 1e-5), 0, 1)
    down = np.exp(-np.maximum(t - attack, 0) / max(tau, 1e-5))
    return np.where(t < 0, 0.0, up * down)


def _flicker(duration, seed, rate=8.0, depth=0.5):
    """Smooth random modulation between 1-depth and 1 (flame lapping)."""
    n = n_samples(duration)
    m = lowpass(rng(seed).standard_normal(n), rate, 2)
    m = (m - m.min()) / (m.max() - m.min() + 1e-12)
    return 1.0 - depth + depth * m


def _moving_band(x, center_fn, q=1.0):
    s = (1.0 / max(q, 0.05)) / 2.355

    def gain(f, t):
        c = max(center_fn(max(t, 0.0)), 20.0)
        return np.exp(-0.5 * (np.log2(np.maximum(f, 1e-3) / c) / s) ** 2)
    return stft_filter(x, gain)


def _moving_lp(x, cutoff_fn, order=2):
    def gain(f, t):
        c = max(cutoff_fn(max(t, 0.0)), 20.0)
        return 1 / np.sqrt(1 + (f / c) ** (2 * order))
    return stft_filter(x, gain)


# --------------------------------------------------------------------------
# The family's materials

def _roar(duration, seed, cutoff=450.0, flutter=0.45, rate=9.0):
    """Fire roar: brown + pink turbulence low-passed (constant or moving
    cutoff), with a slow lapping and a fast flutter of the flame front."""
    x = 0.9 * brown(duration, seed) + 0.25 * pink(duration, seed + 1)
    x = highpass(x, 45, 2)
    x = _moving_lp(x, cutoff, 2) if callable(cutoff) else lowpass(x, cutoff, 2)
    lap = _flicker(duration, seed + 2, rate, flutter)
    flut = _flicker(duration, seed + 3, rate * 3.5, flutter * 0.5)
    return _norm(x * lap * flut)


def _pops(duration, times, seed, band=(1800, 8000), length=0.003, power=2.2, kinds=4, gain=None):
    """Fire crackle: instant-onset pops at `times`, each a tiny burst of
    band-passed decaying noise. Amplitudes follow a power law (many small,
    few loud), optionally scaled by gain(t). `kinds` pop colours are shared
    round-robin (one convolution each, so it stays fast)."""
    n = n_samples(duration)
    r = rng(seed)
    out = np.zeros(n)
    times = list(times)
    lo, hi = band
    for k in range(kinds):
        imp = np.zeros(n)
        for i in range(k, len(times), kinds):
            j = int(times[i] * SR)
            if 0 <= j < n:
                a = r.random() ** power
                if gain is not None:
                    a *= gain(times[i])
                imp[j] += a * (1 if r.random() < 0.5 else -1)
        if not imp.any():
            continue
        L = max(16, n_samples(length * r.uniform(0.6, 1.5)))
        tt = np.arange(L) / SR
        ker = r.uniform(-1, 1, L) * np.exp(-tt / (length * 0.3))
        ker = bandpass(ker, math.exp(r.uniform(math.log(lo), math.log(hi))), 1.0)
        ker[0] += 0.6 * np.max(np.abs(ker))
        out += convolve(imp, _norm(ker))[:n]
    return out


def _robe(duration, seed, rate=12.0, lo=300.0, hi=2800.0):
    """Heavy robe cloth fluttering: pink noise 300-2800 Hz, flapped by a
    jittered quasi-periodic gate (snappy peaks)."""
    n = n_samples(duration)
    x = highpass(lowpass(pink(duration, seed), hi, 2), lo, 2)
    jitter = _flicker(duration, seed + 1, 3.0, 1.0) - 0.5
    ph = phase_of(rate * (1 + 0.5 * jitter), n=n)
    am = (0.5 + 0.5 * np.sin(2 * np.pi * ph)) ** 3
    return _norm(x * (0.3 + 0.7 * am))


def _ember_drone(duration, seed, root=D2, pitch=None, cutoff=600.0, flicker=0.3):
    """The ember chord (see the module docstring). `pitch` is a per-sample
    ratio (drift, sinking), `cutoff` a constant or a fn(t)."""
    n = n_samples(duration)
    r = rng(seed)
    pitch = np.ones(n) if pitch is None else np.broadcast_to(np.asarray(pitch, dtype=float), (n,))
    tone = np.zeros(n)
    for ratio, amp in _EMBER_CHORD:
        for det in (-0.0045, 0.004):
            p = phase_of(root * ratio * (1 + det) * pitch, n=n, phase0=r.random())
            tone += amp * (2 * (p - np.floor(p)) - 1)
    pr = phase_of(root * pitch, n=n)
    buzz = lowpass(white(duration, seed + 1), 2500, 2) * (0.5 + 0.5 * np.cos(2 * np.pi * pr)) ** 6
    x = _norm(tone) + 0.55 * _norm(buzz)
    x = _moving_lp(x, cutoff, 2) if callable(cutoff) else lowpass(x, cutoff, 2)
    return _norm(x * _flicker(duration, seed + 2, 7.0, flicker))


def _arcane(duration, seed, notes, decay=0.5, index=2.5, ratio=2.0, bend=0.0, attack=0.003, trem=5.5):
    """Arcane flare: FM partials in D Phrygian, detuned pairs (shimmer),
    a tremolo, an index that falls (bright -> pure) and an optional sag."""
    n = n_samples(duration)
    t = time_axis(duration)
    r = rng(seed)
    out = np.zeros(n)
    sag = 1 - bend * (1 - np.exp(-t / 0.15))
    idx = index * np.exp(-t / (decay * 0.35)) + 0.2
    for k, (f, amp) in enumerate(notes):
        for det in (-0.003, 0.0032):
            fr = f * (1 + det) * sag
            pm = np.sin(2 * np.pi * phase_of(fr * ratio, n=n, phase0=r.random()))
            pc = phase_of(fr, n=n, phase0=r.random())
            out += amp * np.sin(2 * np.pi * pc + idx * pm) * np.exp(-t / (decay / (1 + 0.3 * k)))
    tremolo = 1 - 0.25 * (0.5 + 0.5 * np.sin(2 * np.pi * trem * t))
    return _norm(out * tremolo * np.clip(t / attack, 0, 1))


def _thud(seed, duration=0.3, f0=120.0, f1=55.0, decay=0.11, slap=0.4, grit=0.25, click=0.5):
    """Body blow through robes: a <2 ms click, a muffled low body (60-250 Hz,
    pitch dropping), a short cloth slap and a little grit; no ringing."""
    t = time_axis(duration)
    n = len(t)
    ck = _norm(highpass(white(duration, seed), 1500, 2)) * np.exp(-t / 0.0006)
    f = f1 + (f0 - f1) * np.exp(-t / 0.025)
    tone = np.sin(2 * np.pi * phase_of(f, n=n))
    lowk = _norm(lowpass(white(duration, seed + 1), 240, 4))
    body = (0.7 * tone + 0.5 * lowk) * env_perc(duration, 0.0012, decay)
    sl = _norm(bandpass(white(duration, seed + 2), 1600, 0.6)) * np.clip(t / 0.0008, 0, 1) * np.exp(-t / 0.011)
    gr = _norm(bandpass(white(duration, seed + 3), 3800, 1.3)) * np.exp(-t / 0.018)
    return body + click * ck + slap * sl + grit * gr


def _sub(seed, duration, f0, f1, tau, attack=0.004):
    """A low push of displaced air under a whoomp: low-passed noise (the air
    itself), with only a hint of a pitch-dropping tone to give it a centre -
    a gust, not a kick drum."""
    t = time_axis(duration)
    f = f1 + (f0 - f1) * np.exp(-t / (tau * 0.5))
    tone = np.sin(2 * np.pi * phase_of(f, n=len(t)))
    body = _norm(lowpass(white(duration, seed), 160, 4))
    env = np.clip(t / attack, 0, 1) * np.exp(-t / tau)
    return _norm((0.35 * tone + 1.0 * body) * env)


def _whoomp(seed, duration, peak=1600.0, end=300.0, attack=0.007, decay=0.3):
    """Ignition: a gas cloud catching - noise whose band leaps up to `peak`
    in a few ms, then sinks to `end` as the flame front cools; fluttering."""
    t = time_axis(duration)
    x = 0.65 * pink(duration, seed) + 0.35 * white(duration, seed + 1)
    band = _moving_band(x, _path([(0, 220), (attack * 4, peak), (duration, end)]), 0.55)
    env = np.clip(t / attack, 0, 1) * np.exp(-t / (decay / 3.0))
    return _norm(band * env * _flicker(duration, seed + 2, 30.0, 0.35))


def _ring(duration, modes, seed, attack=0.0004):
    """Struck resonator: damped sines starting from rest, [(freq, tau, amp)]."""
    t = time_axis(duration)
    r = rng(seed)
    x = np.zeros_like(t)
    for f, d, a in modes:
        if f >= SR * 0.45:
            continue
        x += a * np.sin(2 * np.pi * f * t + r.uniform(-0.3, 0.3)) * np.exp(-t / max(d, 1e-4))
    return x * np.clip(t / max(attack, 1e-5), 0, 1)


def _wood(base, decay, seed):
    """Staff wood: 4 low modes, short decays (time constants)."""
    r = rng(seed)
    ratios = [1.0, 2.7, 4.1, 5.9]
    return [(base * q * (1 + r.uniform(-0.03, 0.03)), decay / (1 + 0.6 * i), 1.0 / (1 + i)) for i, q in enumerate(ratios)]


def _iron_tick(seed, duration=0.12):
    """The card's small iron base touching stone: a few short high iron modes
    over a stone tick."""
    r = rng(seed)
    t = time_axis(duration)
    modes = [(f * r.uniform(0.98, 1.02), tau, a) for f, tau, a in
             ((1180, 0.03, 1.0), (2710, 0.02, 0.7), (4150, 0.014, 0.5), (5930, 0.01, 0.35))]
    ring = _ring(duration, modes, seed)
    stone = _norm(bandpass(white(duration, seed + 1), 900, 1.0)) * np.exp(-t / 0.004)
    return _norm(0.6 * ring + 0.6 * stone)


def _crumple(duration, t0, seed, count=10, spread=0.09, band=(1500, 7500)):
    """A little paper crumple: grains of band-passed noise, 6-12 ms."""
    r = rng(seed)
    times = sorted(t0 + spread * r.random(count) ** 1.8)
    a = grains(duration, times[::2], 0.012, seed + 1, band=band, gain_jitter=0.6)
    b = grains(duration, times[1::2], 0.006, seed + 2, band=band, gain_jitter=0.6)
    return a + b


def _card_flex(duration, t0, seed, count=6, spread=0.05, band=(1500, 6500)):
    """The paper standee flexing with a gesture (the game's signature touch
    of paper): a handful of dry crinkle grains, 1.5-6.5 kHz. Place it where
    nothing else is loud in that band, and never on the loudest peak."""
    return _crumple(duration, t0, seed, count=count, spread=spread, band=band)


def _tail(duration, length):
    """1, then a smooth fall to 0 over the last `length` s: a layer still
    sounding when the buffer ends recedes instead of being cut."""
    t = time_axis(duration)
    u = np.clip((duration - t) / max(length, 1e-6), 0, 1)
    return np.sin(0.5 * np.pi * u) ** 2


def _crown(duration, hits, seed, base=560.0):
    """A small gilt crown hitting stone. Each hit: a sharp contact click, a
    stone tick and the ring's flexural modes (split doublets that beat),
    plus the points' short high modes; softer hits excite fewer highs and
    ring shorter (darker, duller)."""
    n = n_samples(duration)
    r = rng(seed)
    out = np.zeros(n)
    modes = []
    for i, q in enumerate(_RING_RATIOS):
        f = base * q
        split = r.uniform(0.002, 0.006)
        modes.append((f * (1 - split), _CROWN_TAUS[i], _CROWN_AMPS[i], i))
        modes.append((f * (1 + split), _CROWN_TAUS[i] * 0.85, _CROWN_AMPS[i] * 0.7, i))
    for _ in range(5):
        modes.append((r.uniform(2800, 8500), r.uniform(0.02, 0.06), 0.35, 3))
    for t0, s in hits:
        start = int(round(t0 * SR))
        if start >= n:
            continue
        L = n - start
        tt = np.arange(L) / SR
        ms = [(f, tau * (0.5 + 0.5 * s), a * r.uniform(0.25, 1.0) * s ** (1 + 0.35 * i)) for f, tau, a, i in modes]
        ring = _ring(L / SR, ms, seed + 1 + start % 997)
        click = _norm(highpass(r.uniform(-1, 1, L), 2500, 2)) * np.exp(-tt / 0.00035) * s
        stone = _norm(bandpass(r.uniform(-1, 1, L), r.uniform(700, 1400), 1.0)) * np.exp(-tt / 0.004) * s
        # loose points and gems rattle a few ms after each contact
        rt = t0 + np.cumsum(r.uniform(0.004, 0.014, 3))
        rattle = grains(duration, rt, 0.003, seed + 7 + start % 991, band=(4000, 9500), gain_jitter=0.7)
        out[start:] += 0.6 * ring + 0.9 * click + 0.5 * stone
        out += 0.5 * s * _norm(rattle)
    return out


# --------------------------------------------------------------------------
# The sounds
#
# Each recipe builds a list of named layers (name, gain, signal); the
# registered function mixes and finishes them. Keeping the layers named lets
# a review script measure what each one contributes (see _LAYERS).

def _render(spec):
    dur, layers = spec
    return _finish(sum(g * x for _, g, x in layers), dur)


def _layers_move(seed):
    dur, t_lift, t_land = 1.0, 0.14, 0.64
    t = time_axis(dur)
    mid = 0.5 * (t_lift + t_land)

    # Drone: the ember chord lifts with him and drifts (a faint doppler-like
    # rise and fall of pitch and brightness through the glide).
    pitch = 1 + 0.018 * np.exp(-0.5 * ((t - mid) / 0.16) ** 2)
    cutoff = _path([(0, 240), (t_lift, 380), (mid, 760), (t_land, 430), (dur, 250)])
    drone = _ember_drone(dur, seed, D2, pitch=pitch, cutoff=cutoff)
    drone *= env_points(dur, [(0, 0), (t_lift, 0.3), (mid, 0.85), (t_land, 0.6), (0.85, 0.15), (dur, 0)])

    # The glide: soft air through a moving band, no hard attack.
    air = _moving_band(pink(dur, seed + 1), _path([(0, 260), (t_lift, 300), (mid, 950), (t_land, 420), (dur, 300)]), 0.8)
    air = _norm(air) * _swell(t, t_lift - 0.01, mid - 0.05, t_land + 0.06, rise=1.6)

    # Lift-off at 0.14: the robes catch the air (a cloth whuff), a low push of
    # air under him, the paper card ticks as it leaves the stone.
    whuff = _norm(bandpass(pink(dur, seed + 2), 900, 0.6)) * _env_ad(dur, 0.006, 0.05, t0=t_lift - 0.004)
    push = _norm(lowpass(pink(dur, seed + 3), 300, 2)) * _env_ad(dur, 0.01, 0.06, t0=t_lift - 0.006)
    lift_tick = grains(dur, [t_lift - 0.004, t_lift + 0.003], 0.007, seed + 4, band=(2500, 6500), gain_jitter=0.2)

    # Robes flutter through the glide, catching again as he stops.
    robe = _robe(dur, seed + 5, rate=11.0)
    robe *= env_points(dur, [(0, 0), (t_lift - 0.02, 0), (t_lift + 0.02, 0.7), (0.3, 0.35), (0.5, 0.35),
                             (t_land - 0.03, 0.25), (t_land + 0.012, 0.85), (0.8, 0.15), (0.92, 0)])

    # Paper: the hem and card skim the stone (a faint papery hiss) 0.14-0.64.
    r = rng(seed + 6)
    base_t = np.arange(t_lift, t_land, 1 / 900.0)
    bed = grains(dur, base_t + r.uniform(0, 1 / 900.0, len(base_t)), 0.004, seed + 7, band=(1800, 5200), gain_jitter=0.8)
    bed *= env_points(dur, [(0, 0), (t_lift, 0), (t_lift + 0.015, 1), (mid, 0.7), (t_land - 0.02, 0.8), (t_land, 0), (dur, 0)])

    # Settle at 0.64: the iron base taps the stone and a soft low touch - a
    # float coming to rest, not a landing (the touch stays under the ticks).
    settle = place(dur, [(t_land, _iron_tick(seed + 8), 0.5),
                         (t_land, _thud(seed + 9, 0.25, f0=180, f1=95, decay=0.06, slap=0.4, grit=0.2, click=0.3), 0.6)])
    land_tick = grains(dur, [t_land - 0.002, t_land + 0.007], 0.009, seed + 10, band=(1800, 5000), gain_jitter=0.2)

    # Embers off the burning hand, a little livelier mid-glide.
    et = random_times(dur, 55, seed + 11, 0.02, 0.96,
                      envelope=lambda u: 0.35 + 0.65 * math.exp(-0.5 * ((u - 0.4) / 0.25) ** 2))
    et = [e for e in et if not (t_lift - 0.07 < e < t_lift + 0.025 or t_land - 0.045 < e < t_land + 0.025)]  # clean marks
    embers = _pops(dur, et, seed + 12, (2400, 9000), 0.002, power=3.0,
                   gain=lambda tt: 0.3 + 0.7 * float(_swell(np.array([tt]), 0.05, 0.4, 0.95)[0]))
    snaps = _pops(dur, [0.29, 0.47, 0.83], seed + 13, (1000, 2800), 0.007, power=0.4, kinds=3)

    return dur, [("drone", 0.35, drone), ("air", 0.4, air), ("whuff", 0.35, whuff), ("push", 0.3, push),
                 ("lift_tick", 0.3, lift_tick), ("robe", 0.25, robe), ("paper_skim", 0.1, _norm(bed)),
                 ("settle", 0.5, settle), ("land_tick", 0.35, land_tick), ("embers", 0.25, embers),
                 ("snaps", 0.15, snaps)]


@sound("archmage_move", loudness=-22, wet=0.3, marks=(0.14, 0.64))
def archmage_move(seed):
    return _render(_layers_move(seed))


def _layers_cast(seed):
    dur, T = 0.9, 0.25
    t = time_axis(dur)
    pre = np.clip(t / T, 0, 1)
    # Swells into the throw, breaks a hair before it (the gasp before the
    # release makes the whoomp land), then is cut off by it.
    top = T - 0.025
    rise = np.where(t < top, np.clip(t / top, 0, 1) ** 2.4,
                    np.where(t < T, 1 - 0.65 * (t - top) / (T - top), 0.35 * np.exp(-(t - T) / 0.01)))

    # Inhale: air sucked into the hand's fire, a band climbing 240 -> 1700 Hz,
    # the fire's own roar drawing in under it; embers quicken.
    inhale = _moving_band(0.6 * pink(dur, seed) + 0.4 * white(dur, seed + 1),
                          _path([(0, 240), (T, 1700), (dur, 1700)]), 0.9)
    inhale = _norm(inhale) * rise
    draw = _roar(dur, seed + 2, cutoff=_path([(0, 170), (T, 650), (dur, 650)]), flutter=0.35) * rise
    it = random_times(T, 160, seed + 3, 0.0, T - 0.03, envelope=lambda u: u ** 1.5)
    quick = _pops(dur, it, seed + 4, (2000, 8000), 0.002, power=2.5)

    # The paper card flexes as the arm draws back to throw: just before the
    # gasp (the last ~20 ms before the crack stay clear, so the release still
    # leaps out), a little above the inhale's band so the two do not merge.
    card = _card_flex(dur, T - 0.05, seed + 13, count=6, spread=0.025, band=(2000, 7000))

    # Drone: the ember chord settles into place under the inhale (a slight
    # rise, not a charge-up) and flares briefly with the throw.
    pitch = np.where(t < T, 0.94 + 0.06 * pre ** 1.5, 1.0)
    dr = _ember_drone(dur, seed + 5, D2, pitch=pitch,
                      cutoff=_path([(0, 200), (T, 1300), (T + 0.25, 500), (dur, 250)]))
    flare = (0.5 + 0.25 * np.clip((t - T) / 0.012, 0, 1)) * np.exp(-(t - T) / 0.15)
    dr *= np.where(t < T, 0.08 + 0.42 * pre ** 2, flare) * _tail(dur, 0.3)

    # Release at T: an air crack, the whoomp, a low push of air, then the
    # fireball's roar flying away (its band closing), sparks thrown, embers
    # trailing.
    tc = time_axis(0.012)
    crack = place(dur, [(T, _norm(highpass(white(0.012, seed + 6), 1500, 2)) * np.exp(-tc / 0.0012), 1.0)])
    whoomp = place(dur, [(T, _whoomp(seed + 7, dur - T, peak=1800, end=280, attack=0.004, decay=0.38), 1.0)])
    sub = place(dur, [(T, _sub(seed + 8, 0.45, 120, 55, 0.12), 1.0)])
    away = _roar(dur - T, seed + 9, cutoff=_path([(0, 1000), (dur - T, 200)]), flutter=0.6, rate=12)
    away = place(dur, [(T, away * _env_ad(dur - T, 0.012, 0.2), 1.0)]) * _tail(dur, 0.3)
    st = random_times(dur, 420, seed + 10, T, dur - 0.05, envelope=lambda u: math.exp(-u * 5))
    sparks = _pops(dur, st, seed + 11, (1800, 9000), 0.0025, power=2.6, gain=lambda tt: math.exp(-(tt - T) / 0.25))
    snaps = _pops(dur, [T + 0.004, T + 0.05, T + 0.13, T + 0.31], seed + 12, (900, 2600), 0.008, power=0.3)

    return dur, [("inhale", 0.35, inhale), ("draw", 0.45, draw), ("quick", 0.15, quick), ("card", 0.65, card),
                 ("drone", 0.35, dr), ("crack", 0.6, crack), ("whoomp", 0.7, whoomp), ("sub", 0.32, sub),
                 ("away", 0.55, away), ("sparks", 0.3, sparks), ("snaps", 0.3, snaps)]


@sound("archmage_cast", loudness=-18, wet=0.35, marks=(0.25,))
def archmage_cast(seed):
    return _render(_layers_cast(seed))


def _layers_attack(seed):
    dur, T = 0.9, 0.125
    t = time_axis(dur)

    # Swing: a thick staff cuts the air (a low "whoom", band rising 250 ->
    # 1100 Hz into the blow), its burning head flutters and drags a flame rush.
    sw = _moving_band(pink(dur, seed), _path([(0, 250), (T, 1100), (T + 0.15, 450), (dur, 380)]), 1.0)
    # peaks 12 ms before the contact and dips into it, so the blow's click
    # stands out of the whoosh; the contact then cuts the swing off
    top = T - 0.012
    sw_env = np.where(t < top, np.clip(t / top, 0, 1) ** 1.6,
                      np.where(t < T, 1 - 0.55 * (t - top) / (T - top), 0.45 * np.exp(-(t - T) / 0.02)))
    swing = _norm(sw) * sw_env * _flicker(dur, seed + 1, 40, 0.4)
    trail = _roar(dur, seed + 2, cutoff=700, flutter=0.6, rate=14) * sw_env

    # The paper card flexes into the swing (before contact: at or after it,
    # it would sit on the loudest peak).
    card = _card_flex(dur, T - 0.05, seed + 14, count=6, spread=0.04)

    # The blow: arcane fire bursts on contact - body thud, the staff's wood,
    # an ignition burst, the roar carrying the tail, a short FM flare in D
    # Phrygian (a flash, not a held chord), the ember chord flaring, sparks.
    blow = drive(_norm(_thud(seed + 3, 0.4, f0=150, f1=48, decay=0.14, slap=0.25, grit=0.3)), 1.6)
    thud = place(dur, [(T, blow, 1.0)])
    wood = place(dur, [(T, _ring(0.3, _wood(196, 0.035, seed + 4), seed + 4), 1.0)])
    tk = time_axis(0.02)
    knock = _norm(bandpass(white(0.02, seed + 12), 2400, 0.7)) * np.exp(-tk / 0.0016)
    knock = place(dur, [(T, knock, 1.0)])
    burst = place(dur, [(T, _whoomp(seed + 5, dur - T, peak=1300, end=300, attack=0.004, decay=0.26), 1.0)])
    roar = _roar(dur - T, seed + 6, cutoff=_path([(0, 800), (0.6, 220)]), flutter=0.5)
    roar = place(dur, [(T, roar * _env_ad(dur - T, 0.006, 0.22), 1.0)])
    flare = place(dur, [(T, _arcane(dur - T, seed + 7, [(D3, 1.0), (A3, 0.6), (D4, 0.5), (Eb4, 0.15)],
                                    decay=0.12, index=2.4, bend=0.025, attack=0.003, trem=0.0), 1.0)])
    dr = _ember_drone(dur, seed + 8, D2, cutoff=_path([(0, 1200), (T, 1200), (0.5, 300), (dur, 250)]))
    dr *= _env_ad(dur, 0.004, 0.12, t0=T)
    st = random_times(dur, 380, seed + 9, T, dur - 0.04, envelope=lambda u: math.exp(-u * 6))
    sparks = _pops(dur, st, seed + 10, (2000, 9000), 0.0022, power=2.6, gain=lambda tt: math.exp(-(tt - T) / 0.2))
    snaps = _pops(dur, [T + 0.003, T + 0.06, T + 0.2], seed + 11, (900, 2600), 0.008, power=0.3, kinds=3)

    return dur, [("swing", 0.7, swing), ("trail", 0.35, trail), ("card", 0.3, card), ("thud", 0.72, thud),
                 ("wood", 0.35, wood), ("knock", 0.6, knock), ("burst", 0.45, burst), ("roar", 0.5, roar),
                 ("flare", 0.34, flare), ("drone", 0.25, dr), ("sparks", 0.25, sparks), ("snaps", 0.25, snaps)]


@sound("archmage_attack", loudness=-18, wet=0.28, marks=(0.125,))
def archmage_attack(seed):
    return _render(_layers_attack(seed))


def _layers_hurt(seed):
    dur, T = 0.75, 0.118
    t = time_axis(dur)

    # The blow through the robes; the paper card crumples a little, just
    # after the slap (not buried inside it) and before the hiss swells.
    blow = drive(_norm(_thud(seed, 0.35, f0=165, f1=70, decay=0.12, slap=0.6, grit=0.3, click=0.3)), 2.2)
    thud = place(dur, [(T, blow, 1.0)])
    crumple = _crumple(dur, T + 0.008, seed + 1, count=12, spread=0.08)

    # Embers scatter: a dense burst of sparks thinning out, a few snaps.
    st = random_times(dur, 520, seed + 3, T + 0.003, 0.6, envelope=lambda u: math.exp(-u * 4.5))
    scatter = _pops(dur, st, seed + 4, (2000, 8000), 0.0018, power=3.0, gain=lambda tt: math.exp(-(tt - T) / 0.15))
    big = _pops(dur, [T + 0.008, T + 0.03, T + 0.07, T + 0.16], seed + 5, (1100, 3000), 0.007, power=0.8)

    # A hiss: the hand's flame, fanned by the blow, flares and hisses a
    # moment later (breath-like, no voice).
    h = formant(white(dur, seed + 6), [(2600, 2.0, 0.6), (4200, 1.6, 1.0), (6500, 1.4, 0.4)])
    hiss = _norm(h) * _env_ad(dur, 0.035, 0.15, t0=T + 0.03) * _flicker(dur, seed + 7, 25, 0.4)

    # The flame gutters (a sputtering low puff) and the ember chord dips.
    puff = highpass(_roar(dur, seed + 8, cutoff=650, flutter=0.7, rate=16), 130, 2)
    puff = _norm(puff) * _env_ad(dur, 0.025, 0.13, t0=T + 0.01)
    tt = t - T
    pitch = 1 - 0.035 * np.exp(-np.maximum(tt, 0) / 0.1) * (tt > 0)
    dr = _ember_drone(dur, seed + 9, D2, pitch=pitch, cutoff=_path([(0, 400), (T, 900), (0.5, 300), (dur, 250)]))
    dr *= env_points(dur, [(0, 0.15), (T - 0.005, 0.15), (T + 0.01, 1.0), (0.3, 0.3), (0.5, 0.07), (dur, 0)])

    return dur, [("thud", 0.65, thud), ("crumple", 0.7, crumple), ("scatter", 0.28, scatter), ("big", 0.18, big),
                 ("hiss", 0.35, hiss), ("puff", 0.55, puff), ("drone", 0.22, dr)]


@sound("archmage_hurt", loudness=-18, wet=0.2, marks=(0.118,))
def archmage_hurt(seed):
    return _render(_layers_hurt(seed))


def _layers_death(seed):
    dur, T, C = 1.2, 0.118, 0.62
    t = time_axis(dur)
    r = rng(seed + 50)

    # The hit.
    thud = place(dur, [(T, _thud(seed, 0.4, f0=115, f1=48, decay=0.15, slap=0.45, grit=0.3, click=0.4), 1.0)])
    crumple = _crumple(dur, T, seed + 1, count=8, spread=0.06)

    # The fire flares, then collapses: level falls, the band closes
    # 1800 -> 90 Hz and the flutter turns into a sputter.
    cut = _path([(0, 600), (T, 600), (T + 0.05, 1800), (0.3, 1200), (0.6, 400), (0.9, 130), (dur, 90)])
    fire = _roar(dur, seed + 2, cutoff=cut, flutter=0.5, rate=10)
    depth = np.clip((t - 0.3) / 0.5, 0, 1) * 0.85
    gate = _flicker(dur, seed + 3, 14.0, 1.0) ** 3
    fire *= (1 - depth * (1 - gate))
    fire *= env_points(dur, [(0, 0.15), (T, 0.15), (T + 0.04, 1.0), (0.3, 0.85), (0.55, 0.4), (0.8, 0.12), (0.95, 0.03), (dur, 0)])
    fall = _moving_band(pink(dur, seed + 4), _path([(0, 1500), (0.15, 1500), (0.85, 200), (dur, 150)]), 0.9)
    fall = _norm(fall) * _swell(t, T, 0.2, 0.9, rise=1.0, fall=1.6)

    # The ember chord sags a fourth and settles on A1 (the mode's fifth) as
    # it darkens - a furnace losing its draught, not a machine winding down.
    sink = np.where(t < 0.2, 1.0, 0.749 + 0.251 * np.exp(-(t - 0.2) / 0.2))
    dr = _ember_drone(dur, seed + 5, D2, pitch=sink, cutoff=_path([(0, 500), (T, 900), (0.6, 300), (1.0, 110)]))
    dr *= env_points(dur, [(0, 0.2), (T, 0.2), (T + 0.03, 1.0), (0.5, 0.45), (0.9, 0.08), (dur, 0)])

    # Smoke hiss and the last dying crackles.
    smoke = _norm(bandpass(white(dur, seed + 6), 5200, 0.8)) * _swell(t, 0.45, 0.75, dur, rise=1.5, fall=1.2)
    ct = random_times(dur, 260, seed + 7, T, 1.1, envelope=lambda u: math.exp(-u * 3))
    ct = [c for c in ct if not (C - 0.04 < c < C + 0.01)]  # nothing smears the crown's first contact
    crack = _pops(dur, ct, seed + 8, (1800, 9000), 0.0022, power=2.6, gain=lambda tt: math.exp(-(tt - T) / 0.35))

    # Robes billow as he sinks; the card folds (paper creases) and flops.
    robe = _robe(dur, seed + 9, rate=9.0) * _swell(t, 0.12, 0.3, 0.6, rise=1.5, fall=1.5)
    ft = sorted(0.3 + 0.24 * (1 - r.random(12) ** 0.6))
    crease = grains(dur, ft, 0.01, seed + 10, band=(1500, 6500), gain_jitter=0.5)
    flop = place(dur, [(0.585, _thud(seed + 11, 0.2, f0=160, f1=90, decay=0.05, slap=0.9, grit=0.4), 1.0)])

    # The crown clatters at C: falls, bounces closer and closer, wobbles on
    # its rim (accelerating faint ticks) and lies still (contact damping).
    hits = [(C, 1.0)]
    tk, gap, s = C, 0.088, 1.0
    for _ in range(7):
        tk += gap * r.uniform(0.85, 1.15)
        s *= 0.68
        gap *= 0.7
        hits.append((tk, s))
    g = 0.02
    while g > 0.005 and tk < 1.06:
        tk += g
        g *= 0.86
        hits.append((tk, 0.1 * (g / 0.02) ** 0.5))
    # a crown lands on its points and rim in quick succession: each bounce
    # is a little flam of 2-3 contacts (that is what makes it a clatter)
    flams = []
    for t0, s0 in hits[:8]:
        for k in range(1 + int(r.random() < 0.5)):
            flams.append((t0 + r.uniform(0.004, 0.013) * (k + 1), s0 * r.uniform(0.25, 0.55)))
    crown = _crown(dur, hits + flams, seed + 12)
    crown *= np.where(t < tk + 0.01, 1.0, np.exp(-(t - tk - 0.01) / 0.03))

    return dur, [("thud", 0.85, thud), ("crumple", 0.5, crumple), ("fire", 0.7, fire), ("fall", 0.45, fall),
                 ("drone", 0.25, dr), ("smoke", 0.1, smoke), ("crack", 0.25, crack), ("robe", 0.25, robe),
                 ("crease", 0.35, crease), ("flop", 0.25, flop), ("crown", 0.4, crown)]


@sound("archmage_death", loudness=-17, wet=0.35, marks=(0.118, 0.62))
def archmage_death(seed):
    return _render(_layers_death(seed))


# For review scripts: sound name -> fn(seed) -> (duration, [(layer, gain, signal)]).
_LAYERS = {"archmage_move": _layers_move, "archmage_cast": _layers_cast, "archmage_attack": _layers_attack,
           "archmage_hurt": _layers_hurt, "archmage_death": _layers_death}
