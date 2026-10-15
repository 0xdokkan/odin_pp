"""Family `world`: devices, bombs and the room's events (see SOUND_SPEC.md).

Every recipe is dry and synthesized here (the build adds the stone hall). The
family shares one set of materials, so the room sounds like one place:

- iron: one inharmonic iron series (_IRON) for the coil bases, the shock
  plate, the barrel hoops and the fittings, ringing darker as it decays;
- electricity: one mains-like hum on A2 (110 Hz, the fifth of D) with its
  harmonics, a corona sizzle gated at 110 Hz, crackle 2-10 kHz and snaps;
  the coils' chord is sung by the sparks themselves (_singing_arc: a spark
  fired once per cycle of each note, as a singing Tesla coil does);
- the fuse: one fizzing fuse (_fuse) for the armed bomb and its fizzle;
- fire: one fire bed (_fire_bed) for the burning cell and the barrel's oil;
- stone: stone thuds, fracture ticks and debris for the blasts and set-downs;
- paper: the diorama's card (a tap, a few flutters), always light.

Tonal parts sit in D Phrygian. The spec gives this family no marks, so the
key moments of each recipe are listed in _EVENTS (seconds), only to draw
review spectrograms of the dry recipe.

Loudness: short events reach their targets by filling the 400 ms loudness
window with dense, low-crest bodies (a held hum burst, a hollow box, glassy
rings, a slow rumble), so the hits stand above them and the in-recipe
limiters only shave the tips. Every sound keeps its peak at -1.5 dBFS or
lower before the build's ceiling (-1 dBFS), so the build limiter stays idle.
"""
import math

import numpy as np

from dsp import *  # noqa: F401,F403
from registry import sound

_D2 = 73.42
_A2 = 110.0
_D3 = 146.83
_A3 = 220.0
_D4 = 293.66
_F4 = 349.23
_D5 = 587.33
_MAINS = _A2

_IRON = (1.0, 1.594, 2.136, 2.653, 2.918, 3.598, 4.07, 4.61, 5.33, 6.21, 7.13, 8.25)
_WOOD = (1.0, 2.31, 3.86, 5.53)

_EVENTS = {}


def _events(name, *times):
    _EVENTS[name] = tuple(round(float(v), 4) for v in times)


# --------------------------------------------------------------------------
# Small tools

def _norm(x):
    m = float(np.max(np.abs(x))) if len(x) else 0.0
    return x / m if m > 0 else x


def _t60(t, t60):
    """Exponential decay reaching -60 dB at `t60` seconds."""
    return np.exp(-6.91 * t / max(t60, 1e-4))


def _smooth(n, cutoff, seed):
    """Smooth random motion in -1..1 (turbulence, flicker, drift)."""
    return _norm(lowpass(rng(seed).standard_normal(n), cutoff, 2))


def _band(f, center, q):
    width = 1.0 / max(q, 0.05)
    return np.exp(-0.5 * (np.log2(np.maximum(f, 1e-3) / center) / (width / 2.355)) ** 2)


def _path(points):
    """A function of time through (t, value) points, interpolated in log."""
    ts = [p[0] for p in points]
    vs = [math.log(p[1]) for p in points]
    return lambda tt: math.exp(float(np.interp(tt, ts, vs)))


def _moving_band(x, centers, q):
    """A band whose centre follows `centers` (a function of time in s)."""
    return stft_filter(x, lambda f, tt: _band(f, centers(tt), q))


def _moving_lowpass(x, cutoffs, order=2):
    return stft_filter(x, lambda f, tt: 1 / np.sqrt(1 + (f / cutoffs(tt)) ** (2 * order)))


def _squash(x, threshold=0.25, ratio=3.0, window=0.01, smooth=0.004):
    """A gentle look-ahead compressor: keeps a blast's crest inside what the
    build's loudness target allows, so its limiter does not crush it."""
    x = _norm(x)
    n = n_samples(window)
    c = np.cumsum(np.concatenate([[0.0], x ** 2]))
    rms = np.sqrt(np.maximum(c[n:] - c[:-n], 0) / n)
    rms = np.interp(np.arange(len(x)), np.arange(len(rms)) + n / 2, rms)
    gain = np.where(rms > threshold, (np.maximum(rms, 1e-9) / threshold) ** (1.0 / ratio - 1.0), 1.0)
    k = n_samples(smooth)
    gain = np.convolve(gain, np.ones(k) / k, mode="same")
    return x * gain


def _limit(x, threshold=0.6, hold=0.0025, smooth=0.004):
    """A look-ahead peak limiter: lowers only the sharpest peaks above
    `threshold` (of the peak), with a short smooth gain, so the build's own
    limiter has nothing left to crush and the loudness target is met."""
    from numpy.lib.stride_tricks import sliding_window_view
    x = _norm(x)
    h = n_samples(hold)
    a = np.concatenate([np.zeros(h), np.abs(x), np.zeros(h)])
    env = sliding_window_view(a, 2 * h + 1).max(axis=1)
    gain = np.minimum(1.0, threshold / np.maximum(env, 1e-9))
    k = max(1, n_samples(smooth))
    padded = np.concatenate([np.full(k, gain[0]), gain, np.full(k, gain[-1])])
    gain = np.convolve(padded, np.ones(k) / k, mode="same")[k:-k]
    return x * gain


def _dip(t, t0, width, depth):
    """A raised-cosine dip of `depth` over the `width` seconds that end at t0:
    a channel collapsing, or a bed drawing back, just before a strike."""
    u = (t - (t0 - width)) / width
    return 1 - depth * np.where((u > 0) & (u < 1), 0.5 - 0.5 * np.cos(2 * np.pi * u), 0.0)


def _sputter(duration, start, end, seed, rate=30.0, floor=0.3):
    """A failing contact: from `start` the gain drops to `floor` in random gaps
    that come more and more often towards `end` (3 ms edges, no clicks)."""
    n = n_samples(duration)
    r = rng(seed)
    g = np.ones(n)
    tt = start
    while tt < end:
        seg = r.exponential(1.0 / rate)
        if r.random() < 0.2 + 0.6 * (tt - start) / (end - start):
            g[int(tt * SR):int(min(end, tt + seg) * SR)] = floor
        tt += seg
    k = n_samples(0.003)
    return np.convolve(np.concatenate([g, np.full(k, g[-1])]), np.ones(k) / k, mode="full")[k - 1:k - 1 + n]


def _rms_norm(x):
    r = float(np.sqrt(np.mean(x ** 2))) if len(x) else 0.0
    return x / r if r > 0 else x


def _finish(x, duration, peak=0.8, fade_out=0.03):
    x = fade(pad_to(np.asarray(x, dtype=float), duration), 0.001, fade_out)
    return _norm(x) * peak


# --------------------------------------------------------------------------
# Materials: iron, wood, stone, paper

def _modes(duration, modes, attack=0.0003):
    """Struck modes [(freq, t60, amp)], starting from rest (no click)."""
    t = time_axis(duration)
    x = np.zeros_like(t)
    for f, t60, a in modes:
        if 20 < f < SR * 0.45:
            x += a * np.sin(2 * np.pi * f * t) * _t60(t, t60)
    return x * np.minimum(1.0, t / attack) if attack > 0 else x


def _iron_modes(base, t60, seed, count=10, dark=0.6, twin=0.003):
    """The family's iron: inharmonic partials, each with a near twin (slow
    beating); higher partials are weaker and die first (darker tail)."""
    r = rng(seed)
    modes = []
    for i, q in enumerate(_IRON[:count]):
        f = base * q * (1 + r.uniform(-0.012, 0.012))
        a = r.uniform(0.6, 1.0) / (1 + dark * i)
        d = t60 / (1 + 0.45 * i * dark)
        modes.append((f, d, a))
        modes.append((f * (1 + twin * r.uniform(0.4, 1.0)), d * 0.85, 0.45 * a))
    return modes


def _iron(duration, base, t60, seed, count=10, dark=0.6, lp=None):
    x = _modes(duration, _iron_modes(base, t60, seed, count, dark))
    if lp:
        x = lowpass(x, lp, 1)
    return _norm(x)


def _wood(duration, base, seed, t60=0.12, contact=0.5):
    """Wood: a few low modes dying fast, plus the knock of the contact."""
    r = rng(seed)
    modes = [(base * q * (1 + r.uniform(-0.03, 0.03)), t60 / (1 + 0.6 * i), r.uniform(0.7, 1.0) / (1 + 0.8 * i))
             for i, q in enumerate(_WOOD)]
    x = _norm(_modes(duration, modes))
    length = min(duration, 0.015)
    c = white(length, seed + 1) * np.exp(-time_axis(length) / 0.0012)
    c = _norm(bandpass(c, min(base * 7, 4000), 0.9))
    return x + contact * pad_to(c, duration)


def _click(seed, length=0.005, tau=0.0006, hp=700.0, lp=15000.0):
    """A sub-5 ms broadband contact transient."""
    t = time_axis(length)
    x = white(length, seed) * np.exp(-t / tau)
    return _norm(lowpass(highpass(x, hp, 2), lp, 2))


def _thud(duration, seed, f0=110.0, t60=0.12, lp=500.0, drop=0.5):
    """A low body blow on stone: a falling low tone and dark noise."""
    t = time_axis(duration)
    att = np.minimum(1.0, t / 0.0012)
    tone = sine(f0 * (1 + drop * np.exp(-t / 0.01)), n=len(t)) * _t60(t, t60)
    body = _norm(lowpass(white(duration, seed), lp, 2)) * _t60(t, 0.6 * t60)
    return (0.75 * tone + 0.6 * body) * att


def _grit(length, seed, center=3500.0, q=0.8, tau=0.01, density=1800):
    """A short burst of stone grit (2-6 kHz)."""
    t = time_axis(length)
    x = crackle(length, density, seed, decay=0.0003) * np.exp(-t / tau)
    return _norm(bandpass(x, center, q))


def _stone_chunk(seed, base=600.0, t60=0.05, length=0.2, low=0.5):
    """A stone chunk striking stone: dense, very short modes over a thud."""
    r = rng(seed)
    ratios = np.sort(r.uniform(1.0, 5.0, 8))
    modes = [(base * q, t60 * r.uniform(0.5, 1.0) / (1 + 0.3 * i), r.uniform(0.4, 1.0) / (1 + 0.25 * i))
             for i, q in enumerate(ratios)]
    ring = _norm(_modes(length, modes))
    return place(length, [(0, ring, 0.6), (0, _click(seed + 1, hp=1200, tau=0.0007), 0.5),
                          (0, _thud(length, seed + 2, f0=base * 0.28, t60=t60 * 1.5, lp=base * 1.2), low)])


def _stone_ticks(duration, times, seed, lo=1500.0, hi=7000.0, lmin=0.0015, lmax=0.006, power=1.6, fall=None):
    """Stone fragments and pebbles: sharp band-passed ticks with a short
    stone ring each. `fall(t)` scales them over time."""
    out = silence(duration)
    r = rng(seed)
    for t0 in times:
        length = r.uniform(lmin, lmax)
        g = n_samples(length * 5)
        tt = np.arange(g) / SR
        c = math.exp(r.uniform(math.log(lo), math.log(hi)))
        burst = _norm(bandpass(r.uniform(-1, 1, g) * np.exp(-tt / length), c, 1.6))
        ring = (np.sin(2 * np.pi * c * r.uniform(0.8, 1.0) * tt) + 0.6 * np.sin(2 * np.pi * c * r.uniform(1.3, 1.7) * tt))
        ring *= np.exp(-tt / (1.5 * length)) * np.minimum(1, tt / 0.0002)
        a = r.random() ** power * (fall(t0) if fall else 1.0)
        start = int(t0 * SR)
        if start >= len(out):
            continue
        end = min(len(out), start + g)
        out[start:end] += a * (burst + 0.35 * ring)[:end - start]
    return out


def _paper(duration, times, seed, lo=1500.0, hi=8000.0, lmin=0.005, lmax=0.03):
    """Paper grains: band-passed noise 1.5-8 kHz, 5-30 ms, crisp onsets and a
    crinkly micro-texture."""
    out = silence(duration)
    r = rng(seed)
    for k, t0 in enumerate(times):
        length = r.uniform(lmin, lmax)
        g = n_samples(length)
        tt = np.arange(g) / SR
        e = np.minimum(1, tt / 0.0012) * np.exp(-tt / (0.4 * length))
        crinkle = 0.45 + np.abs(crackle(length, 5000, seed + 100 + k, decay=0.0002))
        b = bandpass(r.uniform(-1, 1, g) * e * crinkle, math.exp(r.uniform(math.log(lo), math.log(hi))), 1.3)
        start = int(t0 * SR)
        if start >= len(out):
            continue
        end = min(len(out), start + g)
        out[start:end] += r.uniform(0.5, 1.0) * _norm(b)[:end - start]
    return out


def _card_tap(seed, length=0.07):
    """A paper card set down on stone: a soft cardboard thump, a dry slap and
    a crisp paper edge."""
    t = time_axis(length)
    att = np.minimum(1, t / 0.0008)
    thump = sine(240 * (1 + 0.3 * np.exp(-t / 0.004)), n=len(t)) * _t60(t, 0.035) * att
    slap = _norm(bandpass(white(length, seed) * np.exp(-t / 0.003), 1800, 0.7))
    crisp = _norm(_paper(length, [0.0015, 0.007], seed + 2, lo=2500, hi=7000, lmin=0.005, lmax=0.012))
    return 0.8 * thump + 0.5 * slap + 0.35 * crisp


def _scrape(length, seed, hi=4500.0, lo=1500.0):
    """A dense gritty scrape through a moving band (a card base settling)."""
    x = white(length, seed) * (0.4 + np.abs(crackle(length, 2500, seed + 1, decay=0.0003)))
    x = _moving_band(x, _path([(0, hi), (length, lo)]), 1.2)
    return _norm(x * env_points(length, [(0, 0), (0.004, 1), (length * 0.6, 0.6), (length, 0)]))


def _puff(seed, length=0.22, center=700.0):
    """A soft puff of dust or smoke: dark air with a soft onset and fine grains."""
    t = time_axis(length)
    env = np.minimum(1, t / 0.012) * _t60(t, length)
    air = _norm(bandpass(pink(length, seed), center, 0.6)) * env
    dust = _norm(_stone_ticks(length, random_times(length, 90, seed + 1, 0.01, length * 0.8), seed + 2,
                              lo=3000, hi=8000, lmin=0.0006, lmax=0.0015, power=2.0))
    return air + 0.12 * dust * env


# --------------------------------------------------------------------------
# Electricity

def _hum(duration, seed, f0=_MAINS, harmonics=24, slope=0.9, wobble=0.003):
    """Mains-like hum: harmonics of f0 (constant or per sample) with a small
    drift. Shared by every device of the family (A2 = 110 Hz)."""
    n = n_samples(duration)
    r = rng(seed)
    f0 = np.broadcast_to(np.asarray(f0, dtype=float), (n,))
    ph = np.cumsum(f0 * (1 + wobble * _smooth(n, 4.0, seed + 1))) / SR
    x = np.zeros(n)
    top = float(np.max(f0))
    for k in range(1, harmonics + 1):
        if k * top > 12000:
            break
        a = r.uniform(0.7, 1.0) / k ** slope
        x += a * np.sin(2 * np.pi * k * ph + r.uniform(0, 2 * np.pi))
    return _norm(x)


def _corona(duration, seed, f0=_MAINS, sharp=8.0, lo=2500.0, hi=10000.0):
    """Corona sizzle: high noise gated by the mains peaks (a buzzing hiss)."""
    t = time_axis(duration)
    gate = np.abs(np.sin(np.pi * f0 * t)) ** sharp
    noise = lowpass(highpass(white(duration, seed), lo, 2), hi, 2)
    return _norm(gate * noise)


def _sparks(duration, seed, rate, start=0.0, end=None, envelope=None, lo=2000.0, hi=10000.0, tau=0.0005, power=2.5):
    """Electric crackle: sparse sharp noise impulses 2-10 kHz, heavy-tailed
    amplitudes (mostly ticks, a few loud cracks)."""
    n = n_samples(duration)
    r = rng(seed + 7919)
    times = random_times(duration, rate, seed, start, end, envelope)
    train = np.zeros(n)
    if times:
        idx = np.minimum((np.array(times) * SR).astype(int), n - 1)
        np.add.at(train, idx, r.random(len(idx)) ** power)
    kernel = np.exp(-np.arange(n_samples(tau * 6)) / (tau * SR))
    env = convolve(train, kernel)[:n]
    return lowpass(highpass(env * white(duration, seed + 1), lo, 2), hi, 2)


def _snap(seed, size=1.0, length=0.09):
    """An arc's snap: an N-wave crack, a bright noise burst, a resonant tick
    and a small air thump."""
    t = time_axis(length)
    r = rng(seed)
    n = len(t)
    x = np.zeros(n)
    w = 2 + int(3 * size)
    x[1:1 + w] = 1.0
    x[1 + w:1 + 2 * w] = -0.85
    crack = _norm(highpass(white(length, seed) * np.exp(-t / (0.0012 + 0.001 * size)), 1500, 2))
    ring = _norm(bandpass(white(length, seed + 1) * np.exp(-t / 0.004), r.uniform(2800, 4200), 3.0))
    thump = sine(85 * (1 + 1.2 * np.exp(-t / 0.005)), n=n) * np.exp(-t / (0.015 + 0.015 * size))
    thump *= np.minimum(1, t / 0.0008)
    return 0.7 * x + 1.0 * crack + 0.35 * ring + 0.55 * size * thump


def _pressure_thump(length=0.08, f0=70.0, tau=0.018):
    """The air thump of a strike: a low pulse falling 175 -> 70 Hz (dense, so
    it gives a snap body without raising its peak)."""
    t = time_axis(length)
    f = f0 * (1 + 1.5 * np.exp(-t / 0.006))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / tau) * np.minimum(1, t / 0.001)


def _arc(duration, seed, rate=800.0, wander=0.5, lo=800.0, hi=7000.0, drop=0.25):
    """A chaotic discharge: a pulse train whose rate wanders (the 'zzzt')."""
    n = n_samples(duration)
    r = rng(seed)
    inst = rate * np.exp(1.5 * wander * _smooth(n, 30.0, seed + 1))
    ph = np.cumsum(inst) / SR
    idx = np.nonzero(np.diff(np.floor(ph)) > 0)[0] + 1
    idx = idx[r.random(len(idx)) > drop]
    train = np.zeros(n)
    train[idx] = r.uniform(0.3, 1.0, len(idx)) * np.where(r.random(len(idx)) < 0.5, -1.0, 1.0)
    k = n_samples(0.0015)
    kernel = white(0.0015, seed + 3) * np.exp(-np.arange(k) / (0.0003 * SR))
    x = convolve(train, kernel)[:n]
    return _norm(lowpass(highpass(x, lo, 2), hi, 2))


def _singing_arc(duration, f0, seed, jitter=0.015, lo=150.0, hi=9000.0, kernels=4, click=0.0008, tau=0.00025):
    """A singing Tesla coil: the spark itself is fired once per cycle of the
    note (the interrupter), each firing a tiny noisy crack (0.8 ms). The timing
    jitters by ~1.5% of a period and the strength varies, so the low harmonics
    carry a clear pitch while the top rasps like an arc. `f0`: Hz, constant or
    per sample. A few different crack shapes alternate (no fixed colour). Each
    coil fires at its own phase, so the voices of a chord interleave instead
    of stacking their sparks on the common period."""
    n = n_samples(duration)
    r = rng(seed)
    f = np.broadcast_to(np.asarray(f0, dtype=float), (n,))
    ph = r.uniform(0.0, 1.0) + np.cumsum(f) / SR
    idx = np.nonzero(np.diff(np.floor(ph)) > 0)[0] + 1
    idx = np.clip(idx + np.round(r.normal(0.0, jitter, len(idx)) * SR / f[idx]).astype(int), 0, n - 1)
    amps = r.uniform(0.6, 1.0, len(idx))
    shape = r.integers(0, kernels, len(idx))
    k = n_samples(click)
    decay = np.exp(-np.arange(k) / (tau * SR))
    x = np.zeros(n)
    for j in range(kernels):
        train = np.zeros(n)
        np.add.at(train, idx[shape == j], amps[shape == j])
        kernel = (0.35 + white(click, seed + 1 + j)) * decay   # a pressure bump with a noisy grain
        x += convolve(train, kernel)[:n]
    return _norm(lowpass(highpass(x, lo, 2), hi, 2))


# --------------------------------------------------------------------------
# Fuse and fire

def _fuse(duration, seed, spit_rate=7.0):
    """A burning fuse: a dense fizz of tiny pops (2-9 kHz) fluttering fast, a
    thin hiss, and spits (bright bursts with a tiny pop) at random."""
    n = n_samples(duration)
    t = time_axis(duration)
    r = rng(seed)
    fizz = lowpass(highpass(crackle(duration, 2600, seed, decay=0.0003), 1800, 2), 8000, 2)
    fizz = _norm(fizz) * (0.65 + 0.35 * _smooth(n, 28.0, seed + 1))
    hiss = _norm(lowpass(highpass(white(duration, seed + 2), 3000, 2), 7500, 2))
    hiss *= 0.6 + 0.4 * _smooth(n, 40.0, seed + 3)
    spit_env = np.zeros(n)
    pop_events = []
    for k, t0 in enumerate(random_times(duration, spit_rate, seed + 4)):
        a = np.clip(t - t0, 0, None)
        spit_env += r.uniform(0.5, 1.0) * (t >= t0) * np.minimum(1, a / 0.001) * np.exp(-a / r.uniform(0.012, 0.035))
        pop = _norm(bandpass(white(0.006, seed + 50 + k) * np.exp(-time_axis(0.006) / 0.0007), r.uniform(1400, 3200), 1.5))
        pop_events.append((t0, pop, r.uniform(0.3, 0.7)))
    spits = _norm(bandpass(crackle(duration, 9000, seed + 5, decay=0.0003), 4500, 0.8)) * spit_env
    pops = place(duration, pop_events)
    burn = _norm(lowpass(highpass(pink(duration, seed + 6), 150, 2), 900, 2)) * (0.6 + 0.4 * _smooth(n, 12.0, seed + 7))
    return 0.5 * fizz + 0.15 * hiss + 1.0 * spits + 0.35 * pops + 0.1 * burn


def _pops(duration, times, seed, lo=900.0, hi=6000.0, big=0.15, power=2.2):
    """Fire crackle: sharp pops 1-6 kHz; some are resin pockets bursting with
    a lower woody pop."""
    out = silence(duration)
    r = rng(seed)
    for t0 in times:
        length = r.uniform(0.002, 0.007)
        g = n_samples(length * 4)
        tt = np.arange(g) / SR
        b = _norm(bandpass(r.uniform(-1, 1, g) * np.exp(-tt / length), math.exp(r.uniform(math.log(lo), math.log(hi))), 1.2))
        a = r.random() ** power
        if r.random() < big:
            b = b + 0.7 * np.sin(2 * np.pi * r.uniform(350, 900) * tt) * np.exp(-tt / 0.006) * np.minimum(1, tt / 0.0003)
            a = max(a, 0.5)
        start = int(t0 * SR)
        if start >= len(out):
            continue
        end = min(len(out), start + g)
        out[start:end] += a * b[:end - start]
    return out


def _fire_bed(duration, seed, crack_rate=18.0, crack_env=None, roar=1.0, lap=0.5, crackle_gain=0.9, power=2.2, roar_hp=110.0):
    """Fire: a low turbulent roar (brown noise 110-400 Hz: a cell of flame on a
    tabletop, not a furnace), lapping flames (a flickering mid band), a little
    hiss and crackle grains."""
    n = n_samples(duration)
    roar_x = _norm(highpass(lowpass(brown(duration, seed), 380, 2), roar_hp, 2))
    roar_x *= 0.7 + 0.3 * _smooth(n, 6.0, seed + 1)
    lap_x = _norm(bandpass(pink(duration, seed + 2), 900, 0.7))
    lap_x *= np.clip(0.5 + 0.5 * _smooth(n, 14.0, seed + 3), 0, None) ** 1.5
    hiss_x = _norm(highpass(white(duration, seed + 4), 3000, 2)) * (0.5 + 0.5 * _smooth(n, 20.0, seed + 5))
    pops = _norm(_pops(duration, random_times(duration, crack_rate, seed + 6, envelope=crack_env), seed + 7, power=power))
    return _norm(roar * roar_x + lap * lap_x + 0.06 * hiss_x + crackle_gain * pops)


# --------------------------------------------------------------------------
# Blasts and ice

def _blast(duration, seed, f_start=90.0, f_end=40.0, t60=1.0, sub=1.0, body=1.0, roar=0.8, front=0.6, roar_center=500.0,
           punch=0.0, boom_len=0.7, rumble_hp=38.0, sustain=0.0):
    """A blast: a broadband pressure front, a falling sub boom, a long brown
    rumble, a low punch (around 140 Hz) and a turbulent low-mid roar."""
    t = time_axis(duration)
    n = len(t)
    att = np.minimum(1.0, t / 0.0015)
    fr = _norm(lowpass(white(duration, seed), 9000, 1)) * np.exp(-t / 0.007)
    f = f_end + (f_start - f_end) * np.exp(-t / 0.09)
    boom = sine(f, n=n) * _t60(t, boom_len * t60) * att
    rumble = _norm(highpass(lowpass(brown(duration, seed + 1), 240 + rumble_hp, 2), rumble_hp, 2))
    rumble *= att * (0.55 * _t60(t, t60) + 0.45 * _t60(t, 0.3 * t60) + sustain * _t60(t, 2.5 * t60))
    ro = _norm(bandpass(pink(duration, seed + 2), roar_center, 0.5))
    ro *= att * _t60(t, 0.45 * t60) * (0.8 + 0.2 * _smooth(n, 20.0, seed + 3))
    pu = _norm(bandpass(pink(duration, seed + 4), 140, 0.8)) * att * _t60(t, 0.5 * t60) if punch else 0.0
    return sub * boom + body * rumble + punch * pu + roar * ro + front * fr


def _creak(duration, seed, f_start, f_end, body=(780.0, 1540.0, 2650.0), jitter=0.3, t60=0.025):
    """Stick-slip creak: an irregular pulse train through a resonant body."""
    n = n_samples(duration)
    r = rng(seed)
    rate = glide(f_start, f_end, duration) * np.exp(jitter * _smooth(n, 25.0, seed + 1))
    ph = np.cumsum(rate) / SR
    idx = np.nonzero(np.diff(np.floor(ph)) > 0)[0] + 1
    train = np.zeros(n)
    train[idx] = r.uniform(0.3, 1.0, len(idx))
    ir = _modes(0.06, [(f * r.uniform(0.97, 1.03), t60 / (1 + 0.3 * i), 1.0 / (1 + 0.4 * i)) for i, f in enumerate(body)])
    return _norm(convolve(train, ir)[:n])


def _ice_crack(seed, size=1.0, length=0.32, ring_gain=0.4, ring_len=1.0):
    """One ice fracture: a very sharp crack, glassy high modes, the
    dispersive falling 'zing' of ice and a small thunk of the block."""
    r = rng(seed)
    t = time_axis(length)
    click = _click(seed, length=0.004, tau=0.00025, hp=2500, lp=18000)
    modes = [(r.uniform(1800, 9000), r.uniform(0.04, 0.2) * (0.6 + 0.4 * size) * ring_len, r.uniform(0.3, 1.0)) for _ in range(7)]
    ring = _norm(_modes(length, modes))
    cl = 0.03
    tc = time_axis(cl)
    f = r.uniform(6500, 8000) * (r.uniform(1300, 1800) / 7000.0) ** (tc / cl)
    chirp = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tc / 0.01) * np.minimum(1, tc / 0.0004)
    thunk = _norm(_thud(0.12, seed + 3, f0=r.uniform(230, 300), t60=0.05, lp=1200))
    return place(length, [(0, click, 1.0), (0, ring, ring_gain), (0.0004, chirp, 0.35), (0, thunk, 0.45 * size)])


# --------------------------------------------------------------------------
# The sounds

@sound("world_tesla_deploy", loudness=-19, wet=0.3,
       note="iron base lands 0.004 and rocks 0.075; the coil charges 0.17-0.92 (whine D5-D7 over the A2 hum)")
def world_tesla_deploy(seed):
    D = 1.0
    land, rock = 0.004, 0.075
    c0, c1 = 0.17, 0.86
    t = time_axis(D)
    # 1. The heavy iron base set on stone: strike, low stone thud, dark iron
    #    ring; it rocks once on its edge (same iron, shorter ring).
    ring = _iron(0.9, 205.0, 0.6, seed, count=11, dark=0.7, lp=3200)
    rock_ring = _iron(0.5, 205.0, 0.3, seed, count=11, dark=0.7, lp=2600)
    settle = _iron(0.25, 205.0, 0.12, seed, count=11, dark=0.7, lp=2600)
    base = place(D, [
        (land, _click(seed + 1, hp=900, tau=0.0005), 0.5),
        (land, _thud(0.45, seed + 2, f0=78, t60=0.28, lp=380), 1.0),
        (land, _thud(0.2, seed + 10, f0=145, t60=0.09, lp=900), 0.45),
        (land, ring, 0.42),
        (land + 0.001, _grit(0.06, seed + 3, center=3800, tau=0.012), 0.2),
        (land + 0.002, _card_tap(seed + 4), 0.18),
        (rock, _click(seed + 5, hp=1600, tau=0.0004), 0.16),
        (rock, _thud(0.2, seed + 6, f0=118, t60=0.1, lp=600), 0.3),
        (rock, rock_ring, 0.16),
        (rock + 0.041, settle, 0.05),
    ])
    # 2. The coil charges: the hum rises, a capacitor whine climbs D5 -> D7
    #    (fast then slower, like a charging curve), corona and ticks grow.
    #    The whine is the core's magnetostriction: it buzzes at twice the
    #    mains and wavers a little. When the charge is full the charging
    #    current falls: the whine holds its pitch and settles to 40%, and the
    #    coil idles on into the hall instead of cutting off.
    charge = env_points(D, [(0, 0), (c0, 0), (0.45, 0.35), (c1, 1.0), (D, 1.0)])
    settle = env_points(D, [(0, 1.0), (0.9, 1.0), (0.97, 0.4), (D, 0.0)])
    idle = env_points(D, [(0, 1.0), (0.9, 1.0), (0.97, 0.5), (D, 0.0)])
    u = np.clip((t - c0) / (c1 - c0), 0, 1)
    shape = (1 - np.exp(-2.6 * u)) / (1 - np.exp(-2.6))
    fw = _D5 * 4.0 ** shape * (1 + 0.004 * np.sin(2 * np.pi * 9.0 * t) * u) * (1 + 0.002 * _smooth(len(t), 60.0, seed + 11))
    ph = np.cumsum(fw) / SR
    whine = (np.sin(2 * np.pi * ph) + 0.22 * np.sin(4 * np.pi * ph) + 0.08 * np.sin(6 * np.pi * ph))
    whine *= (1 + 0.25 * np.sin(2 * np.pi * 2 * _MAINS * t)) * charge ** 1.6 * settle
    hum = _hum(D, seed + 7, harmonics=22, slope=0.95) * charge * idle
    corona = _corona(D, seed + 8) * charge ** 2 * idle
    ticks = _norm(_sparks(D, seed + 9, 40, start=0.45, end=0.95, envelope=lambda v: v)) * charge * idle
    x = base + 0.3 * hum + 0.13 * whine + 0.14 * corona + 0.2 * ticks
    _events("world_tesla_deploy", land, rock, c0, c1, 0.9, 0.97)
    return _finish(x, D)


@sound("world_tesla_zap", loudness=-17, wet=0.3,
       note="leader 0.0-0.012; the strike at 0.012 (snap, air thump, the buzz rushing in) has 12 ms to itself; the arc fries and "
            "buzzes, holding to 0.2 and gone by 0.5; the channel collapses and re-strikes at 0.058, 0.118 and 0.196")
def world_tesla_zap(seed):
    D = 0.6
    s = 0.012
    c0 = s + 0.012                      # the crackle waits: the snap has 12 ms to itself
    restrikes = (0.058, 0.118, 0.196)   # return strokes, further apart each time
    t = time_axis(D)
    after = np.clip(t - s, 0, None)
    on = (t >= s).astype(float)
    # Before each re-strike the channel collapses for 15 ms: the frying stops
    # and the buzz sags, so the new snap lands as an event.
    collapse = np.ones_like(t)
    for t0 in restrikes:
        collapse *= _dip(t, t0, 0.015, 0.85)
    sag = 1 - 0.4 * (1 - collapse) / 0.85
    leader = _norm(_sparks(D, seed, 1400, start=0.0, end=s, envelope=lambda v: v ** 2))
    crack = _norm(_sparks(D, seed + 1, 2000, start=c0, end=0.36, envelope=lambda v: min(1.0, v / 0.08) * (1 - v) ** 1.5, power=1.2))
    crack = lowpass(crack, 8500, 3) * collapse
    arc_env = on * _t60(np.clip(after - 0.15, 0, None), 0.45) * np.minimum(1, np.clip(t - c0, 0, None) / 0.01)
    arc = _arc(D, seed + 2, rate=700, wander=0.6) * arc_env * collapse
    # The hum burst: the arc's first current rushes in at twice the level and
    # settles in 20 ms, holds 0.2 s, then dies. Driven, it is dense (low crest),
    # so it fills the loudness window and the snap stands above it unclamped.
    hum_env = on * np.minimum(1, after / 0.004) * _t60(np.clip(after - 0.2, 0, None), 0.3) * (1 + np.exp(-after / 0.02))
    hum = _norm(np.tanh(2.0 * _hum(D, seed + 3, harmonics=26, slope=0.85))) * hum_env * sag
    corona = _corona(D, seed + 4) * hum_env * collapse
    snaps = place(D, [(s, _snap(seed + 5, 1.3), 1.0), (s, _pressure_thump(), 0.6)]
                  + [(t0, _snap(seed + 6 + k, size), g) for k, (t0, size, g) in
                     enumerate(zip(restrikes, (0.8, 0.65, 0.5), (1.0, 0.8, 0.6)))])
    snaps = lowpass(snaps, 9000, 2)     # rounds the N-wave spike, keeps the crack
    x = snaps + 0.25 * leader + 0.7 * crack + 0.35 * arc + 0.35 * hum + 0.28 * corona
    _events("world_tesla_zap", s, c0, *restrikes)
    return _finish(_limit(x, 0.75), D)


@sound("world_tesla_ring", loudness=-15, wet=0.4,
       note="four singing coils link at 0.02, 0.2, 0.38, 0.56 (D3, A3, D4, F4 over the A2 mains, each with a snap after the bed "
            "draws back); the surge rises, crackling, to the big closing snap at 1.16; dies by 1.6")
def world_tesla_ring(seed):
    D = 1.6
    links = (0.02, 0.2, 0.38, 0.56)
    voices = (_D3, _A3, _D4, _F4)
    close = 1.16
    t = time_axis(D)
    surge = env_points(D, [(0, 0), (0.02, 0.45), (0.56, 0.7), (close, 1.0), (close + 0.05, 0.85), (D, 0.0)])
    trem_rate = np.interp(t, [0, 0.56, close, D], [4.0, 5.0, 14.0, 9.0])
    trem = 1 - 0.28 * (0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(trem_rate) / SR))
    # Each coil sings its note: its spark fires once per cycle (the spark is
    # the timbre), over its transformer's hum (which keeps the pitch clear).
    sing = np.zeros_like(t)
    hums = np.zeros_like(t)
    for i, (t0, f0) in enumerate(zip(links, voices)):
        a = np.clip(t - t0, 0, None)
        on = (t >= t0).astype(float)
        bend = 1 - 0.06 * np.exp(-a / 0.03)   # each voice surges up into its pitch
        v = _hum(D, seed + 10 + i, f0=f0 * bend, harmonics=18, slope=1.05)
        v += 0.6 * _hum(D, seed + 20 + i, f0=f0 * 1.0023 * bend, harmonics=14, slope=1.1)
        gate = on * np.minimum(1, a / 0.03) * (1 + 0.6 * np.exp(-a / 0.08)) * 0.33 / (1 + 0.15 * i)
        hums += gate * _rms_norm(v)
        sing += gate * _rms_norm(_singing_arc(D, f0 * bend, seed + 80 + i, click=0.002, tau=0.0007))
    # Rising: the octaves above (A4, D5) fade in as the surge climbs.
    lift = env_points(D, [(0, 0), (0.7, 0), (close, 1.0), (D, 0.3)]) * 0.45 * 0.33
    for i, f0 in enumerate((2 * _A3, 2 * _D4)):
        hums += lift * _rms_norm(_hum(D, seed + 70 + i, f0=f0, harmonics=10, slope=1.1))
        sing += lift * _rms_norm(_singing_arc(D, f0, seed + 90 + i, click=0.002, tau=0.0007))
    hums = _moving_lowpass(hums, _path([(0, 900), (0.56, 1400), (close, 6000), (D, 1500)]))
    sing = _moving_lowpass(sing, _path([(0, 2000), (0.56, 2600), (close, 5000), (D, 2200)]))
    chord = 0.6 * sing + 0.4 * hums
    mains = _hum(D, seed + 5, harmonics=26, slope=0.9) * (t >= links[0]) * np.minimum(1, np.clip(t - links[0], 0, None) / 0.02)
    sub = (np.sin(2 * np.pi * _D2 * t) + 0.3 * np.sin(4 * np.pi * _D2 * t)) * env_points(D, [(0, 0), (0.56, 0), (close, 1.0), (D, 0)])
    rise = np.interp(t, [0, 0.56, close, D], [0, 0, 1, 1])
    fw = _D5 * 2.0 ** rise
    whine = np.sin(2 * np.pi * np.cumsum(fw) / SR) * env_points(D, [(0, 0), (0.56, 0), (close, 1.0), (close + 0.2, 0.0)])
    sparks = _norm(_sparks(D, seed + 30, 320, start=0.02, end=1.5,
                           envelope=lambda v: float(np.interp(0.02 + v * 1.48, [0, 0.56, close, 1.5], [0.15, 0.35, 1.0, 0.1]))))
    corona = _corona(D, seed + 31) * surge ** 1.5
    # The bed draws back (-4 dB) in the 30 ms before each link and (-6 dB) in
    # the 50 ms before the close, so the snaps land as events.
    dips = _dip(t, close, 0.05, 0.5)
    for t0 in links[1:]:
        dips = dips * _dip(t, t0, 0.03, 0.37)
    bursts = [(t0 + 0.002, _norm(_sparks(0.07, seed + 40 + i, 1500, envelope=lambda v: (1 - v) ** 2)), 0.35) for i, t0 in enumerate(links)]
    snaps = place(D, [(t0, _snap(seed + 50 + i, 0.7 + 0.1 * i), 0.9 + 0.1 * i) for i, t0 in enumerate(links)]
                  + [(close, _snap(seed + 60, 1.6), 1.4), (close, _pressure_thump(0.12, 60.0, 0.03), 0.4)] + bursts
                  + [(close + 0.003, _norm(_sparks(0.2, seed + 61, 1800, envelope=lambda v: (1 - v) ** 2)), 0.8)])
    bed = (0.9 * chord + 0.25 * mains) * trem * surge * dips
    x = bed + 0.2 * sub + 0.1 * whine + (0.8 * sparks * surge + 0.3 * corona) * dips + 0.9 * snaps
    _events("world_tesla_ring", *links, close)
    return _finish(_limit(x, 0.7), D, fade_out=0.05)


@sound("world_shock_floor", loudness=-18, wet=0.25,
       note="the plate buzzes up 0.002-0.02 (rattling at 110 Hz) and discharges with a snap at 0.02 (the game's discharge cue); "
            "it keeps buzzing, small snaps at 0.13 and 0.24, and sputters out 0.3-0.55")
def world_shock_floor(seed):
    D = 0.7
    snap_t = 0.02      # the cue is the discharge itself: the damage resolves on it
    t = time_axis(D)
    n = len(t)
    r = rng(seed)
    plate_ir = _modes(0.12, _iron_modes(410.0, 0.07, seed, count=12, dark=0.35))
    plate_ring = _iron(0.6, 410.0, 0.45, seed, count=12, dark=0.45)
    buzz_env = env_points(D, [(0, 0), (0.002, 0.5), (snap_t, 1.0), (0.032, 0.75), (0.22, 0.6), (0.4, 0.3), (0.55, 0.0), (D, 0)])
    buzz_env *= (0.75 + 0.25 * _smooth(n, 35.0, seed + 1)) * _sputter(D, 0.3, 0.55, seed + 9)
    times = np.arange(0.002, D, 1.0 / _MAINS)
    times = times + r.normal(0, 0.00012, len(times))
    idx = np.clip((times * SR).astype(int), 0, n - 1)
    amps = r.uniform(0.6, 1.0, len(idx))
    train = np.zeros(n)
    train[idx] = np.interp(times, t, buzz_env) * amps
    unit = np.zeros(n)
    unit[idx] = amps
    # Scaled by the plate's full-level rattle, so it follows buzz_env exactly
    # as the hum does (a peak normalisation would lift it as the buzz settles).
    rattle = convolve(train, plate_ir)[:n] / (np.max(np.abs(convolve(unit, plate_ir)[:n])) + 1e-12)
    hum = _hum(D, seed + 2, harmonics=24, slope=0.9) * buzz_env
    corona = _corona(D, seed + 3, sharp=10.0) * buzz_env
    sparks = _norm(_sparks(D, seed + 4, 140, start=0.03, end=0.45, envelope=lambda v: 1 - 0.7 * v))
    burst = _norm(_sparks(0.14, seed + 5, 1600, envelope=lambda v: (1 - v) ** 2))
    snaps = place(D, [(snap_t, _snap(seed + 8, 1.3), 1.35), (snap_t, plate_ring, 0.35), (snap_t + 0.002, burst, 0.5),
                      (0.13, _snap(seed + 6, 0.45), 0.32), (0.24, _snap(seed + 7, 0.35), 0.24)])
    x = 0.66 * rattle + 0.36 * hum + 0.22 * corona + 0.25 * sparks * buzz_env + snaps
    _events("world_shock_floor", 0.002, snap_t, 0.13, 0.24, 0.3, 0.55)
    return _finish(_limit(x, 0.58), D)


@sound("world_bomb_fuse", loudness=-22, wet=0.2,
       note="the fuse catches at 0.005 (a small flare), then fizzes and spits steadily to 1.4")
def world_bomb_fuse(seed):
    D = 1.4
    catch = 0.005
    lf = 0.1
    tf = time_axis(lf)
    flare = _norm(bandpass(pink(lf, seed), 2200, 0.7)) * np.minimum(1, tf / 0.004) * _t60(tf, 0.08)
    env = env_points(D, [(0, 0), (catch, 0), (0.03, 1.0), (D - 0.08, 1.0), (D, 0)])
    x = place(D, [(catch, flare, 0.5), (catch, _click(seed + 2, hp=2000), 0.25)]) + _fuse(D, seed + 1) * env
    _events("world_bomb_fuse", catch, 0.03)
    return _finish(x, D, fade_out=0.06)


@sound("world_explosion", loudness=-12, wet=0.45,
       note="blast 0.004 (front, falling boom, rumble to ~1 s); stone shatters 0.01-0.3; debris rains 0.3-1.9")
def world_explosion(seed):
    D = 2.0
    b = 0.004
    r = rng(seed)
    # 1. The deep blast: a falling boom and a long rumble, squashed and driven
    #    like overpressure (dense, so the body carries for about a second).
    #    The slow rumble carries the body past 0.3 s, so the loudness window is
    #    full and the blast keeps a safe margin under the build's ceiling.
    low = place(D, [(b, _blast(1.9, seed, f_start=95, f_end=50, t60=1.5, sub=0.4, body=1.0, roar=1.1, front=0.0, boom_len=0.45, rumble_hp=50.0,
                               roar_center=380, punch=1.2, sustain=0.35), 1.0)])
    low = drive(_squash(low, threshold=0.2, ratio=3.0, window=0.02), 1.8)
    # 2. The front: a short broadband crack.
    lf = 0.04
    tf = time_axis(lf)
    front = _norm(lowpass(white(lf, seed + 3), 7000, 1)) * np.minimum(1, tf / 0.0005) * np.exp(-tf / 0.006)
    # 3. Stone shatters: fracture ticks crowd the first 0.3 s, chunks crack.
    st = b + 0.004 + np.sort(r.exponential(0.06, 80))
    shatter = _stone_ticks(D, st[st < 0.45], seed + 1, lo=700, hi=5500, lmin=0.002, lmax=0.012, power=1.4)
    chunks = place(D, [(b + dt, _stone_chunk(seed + 2 + i, base), g) for i, (dt, base, g) in
                       enumerate([(0.012, 520, 1.0), (0.03, 760, 0.7), (0.055, 610, 0.6), (0.09, 900, 0.45), (0.14, 680, 0.35)])])
    core = _limit(low + place(D, [(b, front, 0.45)]) + 0.22 * _norm(shatter) + 0.3 * _norm(chunks), 0.7)
    # 4. Debris rains back: pebbles, a few bigger stones, a dust trickle and
    #    a few scraps of card fluttering down (the diorama).
    debris = _stone_ticks(D, random_times(D, 90, seed + 10, 0.28, 1.9, envelope=lambda u: (1 - u) ** 1.6), seed + 11,
                          lo=1400, hi=7500, lmin=0.0015, lmax=0.006, power=1.8)
    fallers = place(D, [(tt, _stone_chunk(seed + 20 + i, base, t60=0.06), g) for i, (tt, base, g) in
                        enumerate([(0.42, 480, 0.9), (0.57, 700, 0.6), (0.74, 560, 0.55), (0.98, 820, 0.4), (1.31, 640, 0.3), (1.62, 900, 0.18)])])
    sand = _norm(bandpass(pink(D, seed + 12), 3800, 0.8)) * env_points(D, [(0, 0), (0.25, 0), (0.5, 1.0), (1.9, 0.0)])
    scraps = _paper(D, [0.55, 0.71, 0.86, 1.04, 1.22, 1.45], seed + 30)
    x = core + 0.23 * _norm(debris) + 0.27 * _norm(fallers) + 0.04 * sand + 0.05 * scraps
    _events("world_explosion", b, 0.3, 0.42, 0.57, 0.74, 0.98, 1.31, 1.62)
    return _finish(_limit(x, 0.52), D, fade_out=0.08)


@sound("world_barrel_explosion", loudness=-12, wet=0.45,
       note="staves split 0.003; blast 0.012; oily fire whoosh 0.03-0.6 and burning to 2.0; staves clatter 0.21-1.4; a hoop rings 0.66")
def world_barrel_explosion(seed):
    D = 2.0
    s, b = 0.003, 0.012
    r = rng(seed)
    split = place(0.12, [(0, _click(seed, hp=600, tau=0.0008), 0.7), (0, _wood(0.12, 470, seed + 1, t60=0.07), 0.8),
                         (0.004, _wood(0.12, 610, seed + 2, t60=0.05), 0.5)])
    splinters = _pops(D, list(s + np.sort(r.exponential(0.025, 40))), seed + 3, lo=1200, hi=6000, big=0.0)
    # The blast of a barrel: less sub than the bomb, more wooden low-mid.
    low = place(D, [(b, _blast(1.7, seed + 4, f_start=120, f_end=50, t60=1.0, sub=0.55, body=1.0, roar=0.9, front=0.0,
                               roar_center=520), 1.0)])
    low = drive(_squash(low, threshold=0.2, ratio=3.0, window=0.02), 1.7)
    # The oily fire whoosh: a fireball rolls up (band rises, then sinks).
    whoosh = _moving_band(pink(D, seed + 5), _path([(0, 220), (0.04, 260), (0.22, 1300), (0.6, 700), (1.2, 450), (D, 400)]), 0.9)
    whoosh = _norm(whoosh) * env_points(D, [(0, 0), (0.03, 0), (0.2, 1.0), (0.45, 0.6), (1.0, 0.25), (D, 0)])
    core = _limit(low + place(D, [(s, split, 0.7)]) + 0.45 * _norm(splinters) + 0.5 * whoosh, 0.7)
    fire = _fire_bed(D, seed + 6, crack_rate=20, power=1.8) * env_points(D, [(0, 0), (0.12, 0), (0.45, 0.55), (1.0, 1.0), (1.3, 0.75), (D, 0)])
    knocks = [(0.21, 300, 0.7), (0.27, 380, 0.5), (0.36, 250, 0.65), (0.47, 420, 0.5), (0.58, 330, 0.55),
              (0.77, 270, 0.5), (0.93, 360, 0.42), (1.15, 300, 0.32), (1.4, 340, 0.22)]
    # A plank lands with a dull contact (no pebble tick), and some bounce once
    # 25-45 ms later, so the staves clatter.
    bounces = ((0, 0.032), (2, 0.041), (5, 0.027))
    staves = place(D, [(tt, _wood(0.25, f, seed + 40 + i, t60=0.1), g) for i, (tt, f, g) in enumerate(knocks)]
                   + [(tt, lowpass(_click(seed + 70 + i, hp=1500, tau=0.0004), 6000, 2), 0.5 * g) for i, (tt, f, g) in enumerate(knocks)]
                   + [(knocks[i][0] + dt, _wood(0.2, knocks[i][1] * 1.04, seed + 80 + i, t60=0.08), 0.3 * knocks[i][2]) for i, dt in bounces]
                   + [(knocks[i][0] + dt, lowpass(_click(seed + 90 + i, hp=1500, tau=0.0004), 6000, 2), 0.15 * knocks[i][2])
                      for i, dt in bounces])
    hoop = place(D, [(0.66, _iron(0.9, 330, 0.7, seed + 60, count=10, dark=0.5), 0.5), (0.66, _click(seed + 61, hp=1500), 0.2),
                     (0.84, _iron(0.6, 330, 0.35, seed + 60, count=10, dark=0.5), 0.22),
                     (0.95, _iron(0.4, 330, 0.2, seed + 60, count=10, dark=0.5), 0.1)])
    x = core + 0.35 * fire + 0.7 * _norm(staves) + 0.25 * hoop
    _events("world_barrel_explosion", s, b, 0.2, *[k[0] for k in knocks], 0.66)
    return _finish(_limit(x, 0.8), D, fade_out=0.1)


@sound("world_fire", loudness=-20, wet=0.3,
       note="the flames catch 0.0-0.25 (a soft whoomp peaking at 0.11, kindling pops), then roar and crackle to 1.2")
def world_fire(seed):
    D = 1.2
    r = rng(seed)
    whoomp = _moving_band(pink(D, seed), _path([(0, 160), (0.02, 180), (0.22, 900), (D, 900)]), 0.8)
    whoomp = _norm(whoomp) * env_points(D, [(0, 0), (0.015, 0), (0.1, 1.0), (0.3, 0.25), (0.5, 0.0)])
    # One burning cell, heard often: the crackle leads, the roar stays above
    # 120 Hz (no furnace rumble under the board).
    bed = _fire_bed(D, seed + 1, crack_rate=34, crack_env=lambda u: min(1.0, 0.3 + 2.0 * u), lap=0.7, crackle_gain=1.6, power=1.6)
    bed = highpass(bed, 120, 2) * env_points(D, [(0, 0), (0.05, 0), (0.3, 1.0), (1.02, 1.0), (D, 0)])
    kindling = _pops(D, list(0.05 + np.sort(r.uniform(0, 0.17, 9))), seed + 2, lo=1500, hi=5000, big=0.3, power=1.2)
    x = 0.9 * whoomp + 0.75 * bed + 0.35 * _norm(kindling)
    _events("world_fire", 0.02, 0.11, 0.3)
    return _finish(x, D, fade_out=0.08)


@sound("world_fire_spread", loudness=-20, wet=0.3,
       note="the floor's fires grow a cell at a new window: a rush of flame swelling to 0.15, crackle running along to 0.8")
def world_fire_spread(seed):
    D = 0.9
    rush = _moving_band(pink(D, seed), _path([(0, 220), (0.15, 1200), (0.5, 700), (D, 500)]), 0.8)
    rush = _norm(rush) * env_points(D, [(0, 0), (0.02, 0.2), (0.15, 1.0), (0.45, 0.35), (D, 0.0)])
    bed = _fire_bed(D, seed + 1, crack_rate=44, crack_env=lambda u: max(0.0, 1.0 - u), lap=0.8, crackle_gain=1.5, power=1.5)
    bed = highpass(bed, 120, 2) * env_points(D, [(0, 0), (0.06, 0.4), (0.2, 1.0), (0.75, 0.5), (D, 0)])
    x = 0.85 * rush + 0.7 * bed
    _events("world_fire_spread", 0.0, 0.15, 0.45)
    return _finish(x, D, fade_out=0.08)


@sound("world_fire_out", loudness=-22, wet=0.3,
       note="a floor fire goes out at its fifth window: the flames gutter and sink 0.0-0.45 (the bed darkening, its "
            "crackle thinning), a last ember pops at 0.38, smoke hisses with a soft puff from 0.32, gone by 0.8")
def world_fire_out(seed):
    D = 0.85
    # The burning cell's own bed (world_fire), sinking: darker, thinner.
    bed = _fire_bed(D, seed, crack_rate=30, crack_env=lambda u: max(0.0, 1.0 - 2.2 * u), lap=0.6, crackle_gain=1.3, power=1.7)
    bed = _moving_lowpass(highpass(bed, 120, 2), _path([(0, 6000), (0.45, 900), (D, 600)]))
    bed = _norm(bed) * env_points(D, [(0, 0), (0.03, 1.0), (0.18, 0.8), (0.45, 0.15), (0.6, 0.0), (D, 0.0)])
    # The flame's last breath, falling.
    sink = _moving_band(pink(D, seed + 1), _path([(0, 900), (0.4, 260), (D, 200)]), 0.9)
    sink = _norm(sink) * env_points(D, [(0, 0), (0.02, 0.5), (0.12, 1.0), (0.45, 0.2), (0.6, 0.0), (D, 0.0)])
    # Smoke where it stood: a soft hiss falling away (the fuse's fizzle,
    # gentler), a puff, and one last ember.
    t = time_axis(D)
    after = np.clip(t - 0.32, 0, None)
    hiss = _moving_band(white(D, seed + 2), _path([(0, 4500), (0.32, 4500), (0.7, 1800), (D, 1800)]), 0.8)
    hiss = _norm(hiss) * (t >= 0.32) * np.minimum(1, after / 0.03) * _t60(after, 0.4)
    ember = _norm(_pops(D, [0.38], seed + 3, lo=1200, hi=3500, big=1.0, power=1.0))
    puff = place(D, [(0.32, _puff(seed + 4, length=0.3, center=600.0), 1.0)])
    x = 0.7 * bed + 0.55 * sink + 0.25 * hiss + 0.45 * puff + 0.5 * ember
    _events("world_fire_out", 0.0, 0.12, 0.32, 0.38, 0.45)
    return _finish(_limit(x, 0.7), D, fade_out=0.08)


def _blub(f0, length, rise=0.15):
    """A bubble breaking the skin of a thick pool: a short damped sine whose
    pitch rises a little as it closes."""
    t = time_axis(length)
    f = f0 * (1 + rise * t / length)
    return sine(f, n=len(t)) * np.minimum(1, t / 0.001) * np.exp(-t / (length * 0.3))


@sound("world_pool_splash", loudness=-20, wet=0.25,
       note="a card steps into a pool of poison: a wet slap at 0.0, the pool sucks at its base 0.02-0.16, bubbles to 0.45")
def world_pool_splash(seed):
    D = 0.55
    r = rng(seed)
    t = time_axis(D)
    n = len(t)
    slap = _norm(highpass(lowpass(pink(D, seed), 2400, 2), 180, 2)) * np.minimum(1, t / 0.002) * _t60(t, 0.12)
    crisp = _norm(highpass(white(D, seed + 1), 2500, 2)) * np.minimum(1, t / 0.0005) * _t60(t, 0.03)
    suck = _moving_band(pink(D, seed + 2), _path([(0, 900), (0.12, 350), (D, 300)]), 1.2)
    suck = _norm(suck) * env_points(D, [(0, 0), (0.02, 0), (0.06, 1), (0.16, 0), (D, 0)])
    blubs = silence(D)
    for t0 in sorted(r.uniform(0.05, 0.42, 6)):
        b = _blub(math.exp(r.uniform(math.log(220), math.log(800))), 0.06, 0.35)
        k = int(t0 * SR)
        e = min(n, k + len(b))
        blubs[k:e] += r.uniform(0.4, 1.0) * b[:e - k]
    x = 0.8 * slap + 0.25 * crisp + 0.5 * suck + 0.35 * _norm(blubs)
    _events("world_pool_splash", 0.0, 0.06, 0.2)
    return _finish(_limit(x, 0.7), D, fade_out=0.05)


@sound("world_ice_crack", loudness=-19, wet=0.3,
       note="a creak 0.0-0.1, the main crack 0.1, the fracture runs 0.142-0.338, a last creak 0.4-0.53, shards tinkle 0.47-0.72")
def world_ice_crack(seed):
    D = 0.8
    main = 0.1
    c1 = _creak(0.11, seed, 70, 150) * env_points(0.11, [(0, 0), (0.07, 0.6), (0.1, 1.0), (0.11, 0.0)])
    c2 = _creak(0.13, seed + 1, 120, 60, body=(650.0, 1320.0, 2300.0)) * env_points(0.13, [(0, 0), (0.03, 1.0), (0.13, 0.0)])
    # The main fracture leads; the run after it is smaller (below the limiter,
    # so the main crack is the loudest moment), and every crack rings glassy
    # for longer, which carries the loudness instead of the clicks.
    cracks = [(main, 1.0), (0.142, 0.38), (0.188, 0.3), (0.255, 0.24), (0.338, 0.17)]
    events = [(tt, _ice_crack(seed + 10 + i, size=g, ring_gain=0.7, ring_len=1.5), g) for i, (tt, g) in enumerate(cracks)]
    shards = []
    rr = rng(seed + 30)
    for i, tt in enumerate((0.47, 0.53, 0.61, 0.72)):
        modes = [(rr.uniform(3000, 8000), rr.uniform(0.03, 0.08), rr.uniform(0.4, 1.0)) for _ in range(4)]
        ping = _norm(_modes(0.12, modes)) + 0.3 * pad_to(_click(seed + 40 + i, length=0.003, tau=0.0002, hp=3000), 0.12)
        shards.append((tt, ping, 0.12 * (1 - 0.15 * i)))
    x = place(D, [(0.0, c1, 0.5), (0.4, c2, 0.25)] + events + shards)
    _events("world_ice_crack", main, 0.142, 0.188, 0.255, 0.338, 0.4, 0.47)
    return _finish(_limit(x, 0.6), D)


@sound("world_bomb_fizzle", loudness=-21, wet=0.2,
       note="the fuse fizzes 0.0-0.1; pinched at 0.1: the fizz chokes, a hiss dies by 0.42; a little puff at 0.36")
def world_bomb_fizzle(seed):
    D = 0.7
    p = 0.1
    t = time_axis(D)
    after = np.clip(t - p, 0, None)
    fz = _fuse(D, seed)
    choke = np.where(t < p, 1.0, (0.25 + 0.75 * np.exp(-after / 0.012)) * _t60(after, 0.22))
    fz = fz * choke * np.minimum(1, t / 0.01)
    fz = _moving_lowpass(fz, _path([(0, 9000), (p, 9000), (0.3, 2500), (D, 2500)]))
    hiss = _moving_band(white(D, seed + 1), _path([(0, 5500), (p, 5500), (0.42, 2500), (D, 2500)]), 0.8)
    hiss = _norm(hiss) * (t >= p) * np.minimum(1, after / 0.008) * _t60(after, 0.3)
    pinch = _thud(0.08, seed + 2, f0=180, t60=0.04, lp=900, drop=0.2)
    last = [(0.13, _norm(bandpass(white(0.006, seed + 3) * np.exp(-time_axis(0.006) / 0.0007), 2400, 1.5)), 0.2),
            (0.17, _norm(bandpass(white(0.006, seed + 4) * np.exp(-time_axis(0.006) / 0.0007), 1800, 1.5)), 0.12)]
    x = 0.8 * _norm(fz) + 0.45 * hiss + place(D, [(p, pinch, 0.18), (0.36, _puff(seed + 5, 0.22, 650), 0.3)] + last)
    _events("world_bomb_fizzle", p, 0.36, 0.42)
    return _finish(x, D)


@sound("world_object_hit", loudness=-19, wet=0.22,
       note="strike at 0.003: a wood body knock (F3 modes over a short hollow box) and the small iron fittings clinking high and "
            "short (D6); loose fittings rattle at 0.019, 0.034 and 0.057")
def world_object_hit(seed):
    D = 0.5
    s = 0.003
    fit = 1174.66      # D6: small fittings ring high and short, in key (the sound repeats often)
    x = place(D, [
        (s, _click(seed + 2, hp=800, tau=0.0005), 0.4),
        (s, _wood(0.3, 175, seed, t60=0.18, contact=0.6), 1.0),
        (s, _iron(0.3, fit, 0.26, seed + 1, count=10, dark=0.3), 0.42),
        (s, _modes(0.4, [(118.0, 0.18, 1.0), (243.0, 0.09, 0.3)]), 0.33),
        (s, _thud(0.25, seed + 3, f0=120, t60=0.08, lp=700), 0.4),
        (0.019, _iron(0.12, fit, 0.05, seed + 5, count=10, dark=0.3), 0.14),
        (0.034, _iron(0.2, fit, 0.06, seed + 1, count=10, dark=0.3), 0.12),
        (0.034, _click(seed + 4, hp=2500, tau=0.0003), 0.06),
        (0.057, _iron(0.15, fit, 0.05, seed + 1, count=10, dark=0.3), 0.07),
    ])
    # A short knock is all onset: a gentle look-ahead squash (about 2 dB on the
    # first 25 ms) lets the hollow body carry the loudness window.
    x = _squash(x, threshold=0.28, ratio=2.0, window=0.005, smooth=0.003)
    _events("world_object_hit", s, 0.019, 0.034, 0.057)
    return _finish(_limit(x, 0.5), D)


@sound("world_spawn", loudness=-21, wet=0.4, marks=(0.02,),
       note="the card is set down on stone at 0.02, the moment the enemy shows (its iron base thuds, dust puff 0.03-0.25); "
            "the dark it came from swells behind it and sinks back 0.02-0.9 (a grainy D2 drone and a 70-160 Hz rumble under "
            "a band falling from 650 Hz). The game sees an arrival only once it stands there, so nothing comes before")
def world_spawn(seed):
    D = 0.9
    down, top = 0.02, 0.17
    t = time_axis(D)
    n = len(t)
    rise = np.clip((t - down) / (top - down), 0, 1) ** 1.6
    swell = rise * np.exp(-np.maximum(t - top, 0) / 0.2)
    noise = _norm(_moving_band(pink(D, seed), _path([(0, 650), (top, 650), (D, 90)]), 1.1)) * swell
    air = _norm(highpass(white(D, seed + 1), 2500, 2)) * swell ** 2
    # The dark core: a rough D2 drone whose harmonics (D3, A3, D4) carry it on
    # small speakers, and a brown rumble 70-160 Hz rising with it.
    core = lowpass(_hum(D, seed + 9, f0=_D2, harmonics=6, slope=0.9), 300, 2)
    core = _norm(highpass(core, 110, 1)) * (1 + 0.3 * _smooth(n, 25.0, seed + 11))
    rumble = _norm(highpass(lowpass(brown(D, seed + 10), 160, 2), 70, 2))
    card = place(D, [(down, _card_tap(seed + 3), 1.6), (down + 0.001, _click(seed + 4, hp=2500, tau=0.0003), 0.35),
                     (down, _iron(0.25, 900, 0.1, seed + 5, count=8, dark=0.8), 0.18),
                     (down, _thud(0.2, seed + 8, f0=150, t60=0.07, lp=900, drop=0.3), 0.7),   # the iron base on stone
                     (down + 0.006, _scrape(0.045, seed + 6), 0.35), (down + 0.008, _puff(seed + 7, 0.25, 900), 0.45)])
    x = 0.35 * noise + 0.04 * air + 0.32 * core * swell ** 1.3 + 0.35 * rumble * swell ** 1.5 + card
    _events("world_spawn", top, down)
    return _finish(_limit(x, 0.5), D)


# --------------------------------------------------------------------------
# The Lazzo's rope (Phase 3): hemp, the swung card, its blows

def _rasp(duration, seed, env, centres, q=0.7, rate=280.0):
    """Hemp rope running through its knot or over a card: a fibrous rasp
    (noise through a band following `centres`, a function of time) roughened
    by stick-slip catches, shaped by `env` (per sample)."""
    catches = np.abs(lowpass(np.abs(crackle(duration, rate * env + 1.0, seed, decay=0.0015)), 900, 1))
    texture = 0.25 + 0.75 * _norm(catches) ** 0.7
    body = _moving_band(pink(duration, seed + 1) + 0.5 * white(duration, seed + 2), centres, q)
    return _norm(body) * texture * env


def _thrum(duration, f0, seed, t60=0.25):
    """A hemp rope jerked taut: a dull string quickly damped (Karplus-Strong,
    dark), no ring of metal."""
    s = karplus(f0, duration, damping=0.985, brightness=0.2, seed=seed)
    return _norm(lowpass(s, 1400, 2) * _t60(time_axis(duration), t60))


@sound("world_lasso_wrap", loudness=-20, wet=0.25, marks=(0.0, 0.12, 0.3),
       note="the loop drops over the foe's card at 0.0 (a soft slap of rope on paper), runs tight through its knot 0.01-0.12 "
            "(a rising fibrous zip), cinches at 0.12 with a creak of hemp and the card's paper squeezed, and the rope jerks "
            "taut at 0.3 as the card is lifted (a dull thrum on D2, the soft knock of its base leaving the stone)")
def world_lasso_wrap(seed):
    D = 0.65
    zip_env = env_points(D, [(0, 0), (0.01, 0.3), (0.11, 1.0), (0.125, 0.0), (D, 0.0)])
    zipped = _rasp(D, seed, zip_env, _path([(0, 700), (0.12, 2600), (D, 2600)]), q=0.8, rate=420)
    cinch = _creak(0.12, seed + 1, 95, 60, body=(620.0, 1300.0, 2500.0))
    cinch *= env_points(0.12, [(0, 0), (0.015, 1.0), (0.12, 0.0)])
    squeeze = _paper(D, [0.122, 0.13, 0.142, 0.156, 0.175], seed + 2, lo=1800, hi=6500, lmin=0.006, lmax=0.02)
    x = place(D, [(0.0, _card_tap(seed + 3, 0.06), 0.45), (0.0, zipped, 0.5), (0.12, cinch, 0.4), (0.0, _norm(squeeze), 0.2),
                  (0.3, _thrum(0.35, _D2, seed + 4, t60=0.3), 0.55),
                  (0.3, _thud(0.15, seed + 5, f0=180, t60=0.05, lp=900, drop=0.2), 0.35),
                  (0.302, _scrape(0.04, seed + 6), 0.18)])
    _events("world_lasso_wrap", 0.0, 0.12, 0.3)
    return _finish(_limit(x, 0.7), D)


@sound("world_lasso_whirr", loudness=-24, wet=0.15, rt60=1.0, marks=(0.07,),
       note="one full turn of the swung card: a round swish swelling to 0.07 and falling away by 0.3 (a band 380 -> 1250 -> "
            "420 Hz, a dark rope hum under it), the card's paper fluttering in the wind; quiet and dry (a short hall): it "
            "comes back every turn, up to eight a second, played higher as the spin speeds up")
def world_lasso_whirr(seed):
    D = 0.32
    t = time_axis(D)
    env = env_points(D, [(0, 0), (0.07, 1.0), (0.18, 0.35), (D, 0.0)]) ** 1.3
    air = _moving_band(pink(D, seed) + 0.3 * white(D, seed + 1), _path([(0, 380), (0.07, 1250), (D, 420)]), 1.1)
    hum = _moving_band(brown(D, seed + 2), _path([(0, 120), (0.07, 190), (D, 110)]), 1.4)
    flutter = _moving_band(white(D, seed + 3), _path([(0, 2200), (D, 1800)]), 1.2) * (0.5 + 0.5 * np.sin(2 * np.pi * 34 * t) ** 2)
    x = (_norm(air) + 0.3 * _norm(hum) + 0.18 * _norm(flutter)) * env
    _events("world_lasso_whirr", 0.07)
    return _finish(x, D, fade_out=0.04)


@sound("world_lasso_hit", loudness=-19, wet=0.25, marks=(0.0,),
       note="the swung card slams into another at 0.0: two cardboard bodies struck together (a heavy flam, 6 ms), a body "
            "thud under them, their iron bases knocking, the paper crumpling 0.0-0.09 and the rope jolted (a dull thrum)")
def world_lasso_hit(seed):
    D = 0.5
    r = rng(seed)
    crumple = _paper(D, sorted(0.002 + 0.09 * r.random(12) ** 1.4), seed + 1, lo=1600, hi=7000, lmin=0.005, lmax=0.022)
    x = place(D, [
        (0.0, _click(seed + 2, hp=900, tau=0.0006), 0.35),
        (0.0, _card_tap(seed + 3), 1.0),
        (0.006, _card_tap(seed + 4), 0.8),
        (0.0, _thud(0.35, seed + 5, f0=105, t60=0.16, lp=700, drop=0.6), 0.9),
        (0.003, _iron(0.25, 760, 0.14, seed + 6, count=8, dark=0.7), 0.16),
        (0.0, _norm(crumple), 0.3),
        (0.004, _thrum(0.3, _A2, seed + 7, t60=0.22), 0.3),
    ])
    # All onset: a gentle squash lets the bodies carry the loudness window.
    x = _squash(x, threshold=0.26, ratio=2.5, window=0.005, smooth=0.003)
    _events("world_lasso_hit", 0.0, 0.006)
    return _finish(_limit(x, 0.55), D)


@sound("world_lasso_smash", loudness=-16, wet=0.35, marks=(0.0,),
       note="the swung card smashed into stone at 0.0: a heavy stone thud and chunk, the card's paper crushed, its iron base "
            "clanking, grit and pebbles falling 0.02-0.6, a puff of dust from 0.02, the rope jolted")
def world_lasso_smash(seed):
    D = 0.8
    r = rng(seed)
    grit_t = random_times(D, 160, seed + 1, start=0.02, end=0.6, envelope=lambda u: (1 - u) ** 2)
    pebbles = _stone_ticks(D, grit_t, seed + 2, lo=1400, hi=6500, lmin=0.0015, lmax=0.006, power=1.7,
                           fall=lambda tt: max(0.0, 1 - tt / 0.6))
    crush = _paper(D, sorted(0.002 + 0.07 * r.random(10) ** 1.5), seed + 3, lo=1500, hi=6500, lmin=0.006, lmax=0.025)
    x = place(D, [
        (0.0, _click(seed + 4, hp=700, tau=0.0008), 0.4),
        (0.0, _stone_chunk(seed + 5, base=420, t60=0.08, length=0.35, low=0.9), 1.0),
        (0.0, _thud(0.5, seed + 6, f0=75, t60=0.3, lp=600, drop=0.7), 1.0),
        (0.002, _card_tap(seed + 7), 0.6),
        (0.004, _iron(0.3, 640, 0.18, seed + 8, count=8, dark=0.7), 0.15),
        (0.0, _norm(crush), 0.3),
        (0.0, _norm(pebbles), 0.35),
        (0.02, _puff(seed + 9, 0.4, 650), 0.5),
        (0.004, _thrum(0.3, _D2 * 1.335, seed + 10, t60=0.2), 0.25),
    ])
    x = _squash(x, threshold=0.3, ratio=2.5, window=0.006, smooth=0.004)
    _events("world_lasso_smash", 0.0, 0.02, 0.6)
    return _finish(_limit(x, 0.5), D)


@sound("world_lasso_release", loudness=-21, wet=0.25, marks=(0.0, 0.28),
       note="the rope let go at 0.0: its tension goes in a soft falling swish of hemp (1.5 kHz -> 400 Hz) and loose coils flop "
            "(0.05, 0.12); the card drops back onto the stone at 0.28 (a cardboard thump, its iron base, a short scrape, dust)")
def world_lasso_release(seed):
    D = 0.6
    slack_env = env_points(D, [(0, 0), (0.015, 1.0), (0.2, 0.25), (0.3, 0.0), (D, 0.0)])
    slack = _rasp(D, seed, slack_env, _path([(0, 1500), (0.25, 400), (D, 400)]), q=0.7, rate=220)
    x = 0.45 * slack + place(D, [
        (0.05, _thud(0.1, seed + 1, f0=230, t60=0.05, lp=1500, drop=0.2), 0.3),
        (0.12, _thud(0.1, seed + 2, f0=210, t60=0.05, lp=1500, drop=0.2), 0.22),
        (0.28, _card_tap(seed + 3), 1.0),
        (0.28, _thud(0.2, seed + 4, f0=150, t60=0.08, lp=900, drop=0.3), 0.6),
        (0.283, _scrape(0.05, seed + 5), 0.3),
        (0.285, _puff(seed + 6, 0.22, 900), 0.3),
    ])
    _events("world_lasso_release", 0.0, 0.05, 0.12, 0.28)
    return _finish(_limit(x, 0.6), D)


# --------------------------------------------------------------------------
# The Canna da Pesca's water (Phase 3)

def _drops(duration, count, start, spread, seed, lo=1300.0, hi=3800.0):
    """Drops raining back onto water: tiny bubbles closing (_blub), fewer and
    softer as they go."""
    r = rng(seed)
    out = silence(duration)
    for _ in range(count):
        t0 = start + spread * r.random() ** 1.5
        b = _blub(math.exp(r.uniform(math.log(lo), math.log(hi))), r.uniform(0.012, 0.024), r.uniform(0.3, 0.9))
        i = int(t0 * SR)
        if i >= len(out):
            continue
        e = min(len(out), i + len(b))
        out[i:e] += r.uniform(0.2, 0.6) * (1 - 0.5 * (t0 - start) / spread) * b[:e - i]
    return out


@sound("world_bobber_plop", loudness=-22, wet=0.25, marks=(0.0,),
       note="the cork bobber lands on the water at 0.0: a small round plop (a bubble ringing up from 480 Hz), a light slap of "
            "water and a spray of fine drops falling back 0.02-0.2, then the ripples lapping softly away to 0.45")
def world_bobber_plop(seed):
    D = 0.5
    t = time_axis(D)
    slap = _norm(highpass(lowpass(white(D, seed), 3500, 2), 300, 2)) * np.minimum(1, t / 0.0008) * _t60(t, 0.04)
    lap = _norm(_moving_band(pink(D, seed + 1), _path([(0, 500), (D, 260)]), 1.0))
    lap *= env_points(D, [(0, 0), (0.04, 0.0), (0.12, 1.0), (D, 0.0)]) * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * t))
    x = place(D, [(0.0, _blub(480, 0.09, rise=0.9), 0.9)]) + 0.3 * slap + 0.3 * _norm(_drops(D, 9, 0.02, 0.18, seed + 2)) \
        + 0.12 * lap
    _events("world_bobber_plop", 0.0, 0.02, 0.2)
    return _finish(_limit(x, 0.7), D)


@sound("world_fish_bite", loudness=-19, wet=0.25, marks=(0.0,),
       note="a fish takes the bait at 0.0: the bobber yanked under (a deep gulp ringing up from 240 Hz, a second smaller one), "
            "a splash thrown up with drops raining back to 0.35, the taut line plucked high (A5) and the rod's tip bending "
            "with a short creak")
def world_fish_bite(seed):
    D = 0.6
    t = time_axis(D)
    splash = _moving_lowpass(highpass(white(D, seed) + pink(D, seed + 1), 250, 2), _path([(0, 7000), (0.1, 1800), (D, 1500)]))
    splash = _norm(splash) * np.minimum(1, t / 0.002) * _t60(t, 0.12)
    line = _norm(karplus(880.0, 0.25, damping=0.992, brightness=0.6, seed=seed + 2) * _t60(time_axis(0.25), 0.2))
    rod = _creak(0.1, seed + 3, 110, 70, body=(900.0, 1900.0, 3400.0)) * env_points(0.1, [(0, 0), (0.02, 1.0), (0.1, 0.0)])
    x = place(D, [(0.0, _blub(240, 0.12, rise=0.7), 0.8), (0.03, _blub(380, 0.07, rise=0.9), 0.35), (0.0, splash, 0.55),
                  (0.0, _norm(_drops(D, 14, 0.03, 0.32, seed + 4)), 0.35), (0.005, line, 0.12), (0.01, rod, 0.25)])
    _events("world_fish_bite", 0.0, 0.03, 0.35)
    return _finish(_limit(x, 0.65), D)
