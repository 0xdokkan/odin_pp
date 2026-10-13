"""Family `cards_arcana` - cards of storm, fire, poison and devices (SOUND_SPEC.md).

A card is played from the Viandante's hand, so every recipe opens the same
way: a short paper flick (~20 ms; its grains, band and snap differ per card)
and the arcana's signature, a faint glass sigil in D Phrygian (D6 + A6 with a
slow shimmer) as the card wakes. Then the effect, made of what it summons:

- storm (arc bolt, chain lightning, piercing ray, spark, storm crown, shock
  floor, tesla coil) share one electric voice: a buzz on A2 (110 Hz; the
  chain lightning climbs A2-D3-F3 as its leaps grow thinner and brighter, the
  tiny spark sits an octave up with no fundamental) with mains-like odd
  harmonics and a hum-locked sizzle, sparse 2-10 kHz crackle, sharp N-wave
  snaps with a short torn-air crackle and a low air thump; the ray's beam is
  burning air (a rough 1.8-10 kHz sear) over an FM chord whose index flares;
- fire (firebomb, spark forge): brown-noise roar under 400 Hz, crackle
  grains, a sputtering fuse;
- poison (toxic wave, venom needle, caustic bloom, twin venom): modelled
  bubbles (damped sines whose pitch rises as they close, after van den Doel;
  the big, low ones barely rise, or they turn into cartoon bloops) over wet,
  gurgling band-passed hiss; the needle's whistle is aeolian noise;
- glass and crystal (volatile study, prismatic barrage): doublet glass modes
  (the slow beating of a real glass) tuned to D Phrygian; a crystal shot is
  loosed with a rising zip, cracks off and splinters into a high glitter;
- devices: iron and steel modal bodies (plates, coils, an anvil).

No marks are listed for the cards in the spec; each recipe's own key moments
are kept in _EVENTS (used only by the review tooling).
Recipes are dry; the build adds the stone hall. _finish() levels the flick
(-9 dB) and sigil (-27 dB) against each effect, high-passes at 30 Hz, keeps
the crest factor under 16.5 dB (so the build's limiter stays idle at -19)
and returns an exactly zero-mean buffer (no DC for the hall tail to smear).
"""
import math

import numpy as np

from dsp import *  # noqa: F401,F403
from registry import sound

_LOUD = -19
_WET = 0.25

# D Phrygian (D Eb F G A Bb C)
_A2 = 110.0
_D3, _F3 = 146.83, 174.61
_A3 = 220.0
_D5, _A5 = 587.33, 880.0
_D6, _F6, _A6 = 1174.66, 1396.91, 1760.0
_D7, _F7 = 2349.32, 2793.83

# Key moments of each recipe (seconds), for the review only.
_EVENTS = {}


# --------------------------------------------------------------------------
# Small building blocks

def _add(buf, t0, s, gain=1.0):
    """Mixes a layer in at t0; its last 3 ms are faded so no layer can end
    on a step."""
    i = int(round(t0 * SR))
    if i >= len(buf) or not len(s):
        return
    e = min(len(buf), i + len(s))
    seg = gain * s[:e - i]
    k = min(n_samples(0.003), len(seg) // 4)
    if k > 1:
        seg[-k:] *= np.linspace(1, 0, k)
    buf[i:e] += seg


class _Bus:
    """A dry buffer to drop layers into at given times. The card's own
    opening (flick + sigil) is kept apart and levelled against the effect
    when the sound is finished, so it sits the same way on every card."""

    def __init__(self, dur):
        self.dur = dur
        self.x = silence(dur)
        self.flick = silence(dur)
        self.sigil = silence(dur)

    def add(self, t0, s, gain=1.0):
        _add(self.x, t0, s, gain)


def _norm(x, peak=1.0):
    m = float(np.max(np.abs(x))) if len(x) else 0.0
    return x * (peak / m) if m > 0 else x


def _peak_rms(x, ms=1.0):
    """Loudest short-window RMS (a transient's real weight, not one sample)."""
    w = n_samples(ms / 1000.0)
    m = len(x) // w
    if m < 1:
        return float(np.sqrt(np.mean(x ** 2)) + 1e-12)
    return float(np.sqrt(np.max(np.mean(x[:m * w].reshape(m, w) ** 2, axis=1))) + 1e-12)


_FLICK_DB = -9.0     # the flick's 1 ms peak, re the effect's
_SIGIL_DB = -27.0    # the sigil's 10 ms peak, re the effect's
_MAX_CREST = 16.5    # peak over the build's loudness (dB): keeps its limiter idle


def _soft_knee(x, k):
    """Leaves |x| < k untouched and bends what is above towards 1.15 k."""
    a = np.abs(x)
    m = 0.15 * k
    over = a > k
    y = x.copy()
    y[over] = np.sign(x[over]) * (k + m * np.tanh((a[over] - k) / m))
    return y


def _tame_crest(x, max_crest=_MAX_CREST):
    """A crack or a snap is a few needle-sharp samples over a short body; at
    the family's loudness the build would then squash the whole sound. Bend
    only those peaks (a short soft knee) until the crest factor fits."""
    p = float(np.max(np.abs(x)))
    if p <= 0 or db(p) - loudness_db(x) <= max_crest:
        return x
    lo, hi = 0.05, 1.0
    for _ in range(14):
        k = 0.5 * (lo + hi)
        y = _soft_knee(x, k * p)
        if db(np.max(np.abs(y))) - loudness_db(y) > max_crest:
            hi = k
        else:
            lo = k
    return _soft_knee(x, lo * p)


def _finish(bus, peak=0.8, release=0.04):
    """Levels the card's opening against the effect, keeps the crest factor
    in range and lets the end go over `release` seconds."""
    ref = _peak_rms(bus.x)
    ref10 = _peak_rms(bus.x, 10.0)
    x = bus.x.copy()
    if np.any(bus.flick):
        x += bus.flick * (ref * 10 ** (_FLICK_DB / 20) / _peak_rms(bus.flick))
    if np.any(bus.sigil):
        x += bus.sigil * (ref10 * 10 ** (_SIGIL_DB / 20) / _peak_rms(bus.sigil, 10.0))
    # nothing useful lives under 30 Hz; and an exactly zero mean, so the
    # build's DC removal has no offset to smear into the hall's tail
    x = highpass(pad_to(x, bus.dur), 30, 2)
    x = fade(_norm(_tame_crest(x), peak), 0.0006, release)
    w = np.hanning(len(x))
    return x - w * (np.sum(x) / np.sum(w))


def _ar(n, attack, tau, hold=0.0):
    """Linear attack, optional hold, exponential decay (tau s)."""
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    return a * np.exp(-np.maximum(t - attack - hold, 0) / max(tau, 1e-5))


def _band_gain(f, center, octaves):
    """Log-frequency gaussian band, `octaves` wide at half height."""
    return np.exp(-0.5 * (np.log2(np.maximum(f, 1e-3) / center) / (octaves / 2.355)) ** 2)


def _moving_band(x, c0, c1, oct0=1.5, oct1=None, curve=1.0, frame=1024, hop=256):
    """Band-pass whose centre glides c0 -> c1 (and width oct0 -> oct1)."""
    dur = len(x) / SR
    oct1 = oct0 if oct1 is None else oct1

    def gain(f, t):
        u = min(max(t / max(dur, 1e-6), 0), 1) ** curve
        return _band_gain(f, c0 * (c1 / c0) ** u, oct0 + (oct1 - oct0) * u)
    return stft_filter(x, gain, frame, hop)


def _modal(dur, modes, seed=0, attack=0.0003):
    """Damped sinusoids [(f, tau, amp)] with a tiny attack (no step) and a
    short fade where the buffer ends (a ring is never cut off)."""
    t = time_axis(dur)
    r = rng(seed)
    x = np.zeros_like(t)
    for f, d, a in modes:
        if f < SR * 0.45:
            x += a * np.sin(2 * np.pi * f * t + r.uniform(0, 2 * np.pi)) * np.exp(-t / max(d, 1e-4))
    return fade(x * np.clip(t / attack, 0, 1), 0.0, min(0.02, 0.15 * dur))


def _impulses(dur, density, seed, decay=0.0003, power=2.5):
    """Sparse impulses (per second, scalar or per sample) with a skewed level
    distribution: many tiny ticks, a few loud ones."""
    n = n_samples(dur)
    r = rng(seed)
    dens = np.broadcast_to(np.asarray(density, dtype=float), (n,))
    hits = r.random(n) < dens / SR
    x = np.zeros(n)
    k = int(hits.sum())
    if k:
        x[hits] = r.choice([-1.0, 1.0], k) * r.random(k) ** power
    kern = np.exp(-np.arange(n_samples(decay * 6)) / (decay * SR))
    return convolve(x, kern)[:n]


# --------------------------------------------------------------------------
# The card itself

def _flick(seed):
    """The card leaves the hand: a fast papery rub, a few fibre grains and the
    snap of the card stock springing free (~20 ms)."""
    r = rng(seed)
    length = r.uniform(0.017, 0.024)
    n = n_samples(length)
    t = np.arange(n) / SR
    rub = bandpass(r.uniform(-1, 1, n), r.uniform(2200, 3600), 0.8)
    rub *= (1 - np.exp(-t / 0.0007)) * np.exp(-t / (length * 0.4))
    times = np.sort(r.uniform(0.0, length * 0.65, int(r.integers(4, 8))))
    gr = grains(length + 0.01, times, r.uniform(0.003, 0.006), seed + 1, band=(1500, 8000))[:n]
    k0 = r.uniform(0.003, 0.008)
    after = t >= k0
    tt = np.maximum(t - k0, 0)
    snap = highpass(r.uniform(-1, 1, n), 1300, 2) * np.exp(-tt / 0.0011) * after
    body = bandpass(r.standard_normal(n), r.uniform(900, 1500), 2.0) * np.exp(-tt / 0.004) * after
    x = 0.45 * _norm(rub) + 0.6 * _norm(gr) + 0.8 * _norm(snap) + 0.25 * _norm(body)
    return fade(_norm(x), 0.0004, 0.003)


def _sigil(seed, dur=0.4, notes=(_D6, _A6), tau=0.1):
    """The arcana's signature: a faint glass partial pair that shimmers."""
    r = rng(seed)
    t = time_axis(dur)
    x = np.zeros_like(t)
    for i, f in enumerate(notes):
        det = 1 + r.uniform(0.0016, 0.0028)
        x += (np.sin(2 * np.pi * f * t) + 0.7 * np.sin(2 * np.pi * f * det * t + r.uniform(0, 6.28))) / (1 + 0.8 * i)
    return fade(_norm(x * (1 - np.exp(-t / 0.006)) * np.exp(-t / tau)), 0.0, 0.03)


def _intro(bus, seed, notes=(_D6, _A6)):
    _add(bus.flick, 0.0, _flick(seed))
    _add(bus.sigil, 0.012, _sigil(seed + 1, notes=notes))


# --------------------------------------------------------------------------
# Storm

def _buzz(dur, f0=_A2, seed=0, bright=1.0, flicker=0.6):
    """The electric voice: a mains-like buzz (odd harmonics strong), driven,
    flickering, with a sizzle that re-strikes on every half cycle."""
    n = n_samples(dur)
    r = rng(seed)
    wob = _norm(lowpass(r.standard_normal(n), 25, 1))
    ph = phase_of(f0 * (1 + 0.006 * wob), n=n)
    x = np.zeros(n)
    for k in range(1, int(min(40, 9000 / f0)) + 1):
        amp = (1.7 if k % 2 else 1.0) / k ** (1.1 - 0.3 * bright)
        x += amp * np.sin(2 * np.pi * k * ph + r.uniform(0, 2 * np.pi))
    x = drive(_norm(x), 2.0)
    fl = _norm(lowpass(r.standard_normal(n), 60, 1))
    x *= 1 - flicker * 0.5 * (1 + fl)
    gate = np.exp(-((2 * ph) % 1.0) / 0.12)
    sz = highpass(r.uniform(-1, 1, n), 2500, 2) * gate
    return _norm(x + 0.35 * bright * _norm(sz))


def _ecrackle(dur, density, seed, lo=2000, hi=10000, decay=0.00025, power=2.0):
    c = _impulses(dur, density, seed, decay, power)
    return _norm(lowpass(highpass(c, lo, 2), hi, 2))


def _snap(seed, size=1.0, bright=1.0, length=0.12):
    """An electric snap: two to four N-wave fronts within 3 ms, a bright
    burst of torn air and (for big ones) a little low body."""
    r = rng(seed)
    n = n_samples(length)
    t = np.arange(n) / SR
    x = np.zeros(n)
    offs = np.sort(r.uniform(0, 0.003, int(r.integers(2, 5))))
    offs[0] = 0.0003
    for i, o in enumerate(offs):
        i0 = int(o * SR)
        w = int(r.uniform(0.0002, 0.0006) * SR) + 2
        a = 1.0 if i == 0 else r.uniform(0.4, 0.9)
        x[i0:i0 + w] += a * np.linspace(1, -1, w)
    x = highpass(x, 400 + 600 * bright, 1)
    burst = highpass(r.uniform(-1, 1, n), 1500 + 1500 * bright, 2) * np.exp(-t / (0.006 + 0.01 * size))
    body = lowpass(r.standard_normal(n), 300, 2) * (1 - np.exp(-t / 0.0015)) * np.exp(-t / (0.015 + 0.03 * size))
    # the fronts saturate the air a little: squarer, less needle-like peaks
    # (keeps the crack sharp while lowering the crest factor)
    out = drive(_norm(_norm(x) + 0.55 * _norm(burst) + 0.5 * size * _norm(body)), 2.5)
    return fade(_norm(out), 0.0, 0.3 * length)


def _tear(dur, seed, c0=7000, c1=2500, density=6000, tau=0.03):
    """The ripping crackle of a lightning channel: dense impulses whose band
    falls as the bolt's energy spreads."""
    n = n_samples(dur)
    t = np.arange(n) / SR
    imp = _impulses(dur, density, seed, 0.00025, 1.5)
    x = _moving_band(imp, c0, c1, 1.8, 1.8, 1.0, 512, 128)
    return _norm(x * (1 - np.exp(-t / 0.001)) * np.exp(-t / tau))


def _thump(seed, f=75.0, tau=0.11, length=0.45, cutoff=180):
    """A low air thump: a falling sine and low noise."""
    r = rng(seed)
    n = n_samples(length)
    t = np.arange(n) / SR
    fr = f * (1 + 0.7 * np.exp(-t / 0.02))
    s = np.sin(2 * np.pi * np.cumsum(fr) / SR)
    nz = _norm(highpass(lowpass(r.standard_normal(n), cutoff, 2), 40, 2))
    return _norm((0.6 * s + 0.8 * nz) * (1 - np.exp(-t / 0.0015)) * np.exp(-t / tau))


def _thunder(dur, seed, rolls, cutoff=170):
    """Distant thunder: brown noise under ~200 Hz, swelling in rolls
    [(t0, rise, tau, amp)], with a slow ragged flutter and a little
    low-mid grain so it reads on small speakers."""
    r = rng(seed)
    n = n_samples(dur)
    t = np.arange(n) / SR
    low = _norm(highpass(lowpass(brown(dur, seed), cutoff, 2), 40, 2))
    grain = _norm(bandpass(pink(dur, seed + 1), 380, 0.9))
    env = np.zeros(n)
    for t0, rise, tau, a in rolls:
        u = np.clip((t - t0) / rise, 0, 1)
        env += a * u ** 2 * np.exp(-np.maximum(t - t0 - rise, 0) / tau) * (t >= t0)
    fl = 0.6 + 0.4 * _norm(lowpass(r.standard_normal(n), 14, 1))
    return (low + 0.25 * grain) * env * fl


def _arc(seed, f0=_A2, size=1.0, tail=0.25):
    """A full discharge: snap + torn crackle + buzz burst + air thump."""
    n = n_samples(0.12 + tail)
    out = np.zeros(n)
    s = _snap(seed, size, 1.0)
    out[:len(s)] += 1.0 * s
    tr = _tear(0.1, seed + 1, 7000, 2600, 6500, 0.028)
    out[:len(tr)] += 0.5 * tr
    m = n_samples(0.06 + tail * 0.8)
    out[:m] += 0.4 * _buzz(m / SR, f0, seed + 2) * _ar(m, 0.002, 0.06)
    th = _thump(seed + 3, 75, 0.1, 0.4)
    out[:min(n, len(th))] += 0.45 * size * th[:n]
    return out


# --------------------------------------------------------------------------
# Fire

def _roar(dur, seed, cutoff=380, flutter=0.5):
    r = rng(seed)
    n = n_samples(dur)
    x = _norm(highpass(lowpass(brown(dur, seed), cutoff, 2), 45, 2))
    fl = _norm(lowpass(r.standard_normal(n), 9, 1))
    return x * (1 - flutter * 0.5 * (1 + fl))


def _fire_crackle(dur, density, seed):
    """Crackle grains: bright ticks plus a few lower wood pops."""
    hi = _ecrackle(dur, density, seed, 1500, 7000, 0.0006, 2.0)
    pops = _ecrackle(dur, np.asarray(density) * 0.15, seed + 1, 400, 2500, 0.0015, 1.5)
    return _norm(hi + 0.6 * pops)


def _sizzle(dur, seed, lo=3000, hi=9500, spit_rate=60):
    """A burning fuse: uneven high hiss and spitting grains."""
    r = rng(seed)
    n = n_samples(dur)
    hiss = _norm(lowpass(highpass(r.uniform(-1, 1, n), lo, 2), hi, 2))
    am = _norm(np.abs(lowpass(r.standard_normal(n), 160, 1)))
    hiss *= 0.3 + am ** 1.5
    spits = _ecrackle(dur, spit_rate, seed + 2, 2500, 9000, 0.0006, 1.2)
    return _norm(hiss + 0.9 * spits)


# --------------------------------------------------------------------------
# Liquids and gas

def _bubble(f0, amp=1.0, xi=0.15, damp=1.0):
    """One bubble (van den Doel): a damped sine whose pitch rises as it
    closes. Bigger bubbles: lower, longer (`damp` > 1 for a viscous glop).
    It runs until it has died to -40 dB."""
    d = (0.043 * f0 + 0.0014 * f0 ** 1.5) * damp
    dur = min(0.3, 4.6 / d)
    n = n_samples(dur)
    t = np.arange(n) / SR
    f = f0 * (1 + xi * d * t)
    att = 0.5 - 0.5 * np.cos(np.pi * np.clip(t / 0.001, 0, 1))
    return fade(amp * np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-d * t) * att, 0.0, 0.2 * dur)


# A big bubble's pitch barely rises: with xi = 0.1 it climbs 23 % inside its
# top 20 dB (exp(-d t) = 0.1 at d t = 2.3), and the bloom's blorp (0.08) 18 %.
# Above ~0.15 a low bubble turns into a 1-1.5 octave cartoon "bloop".
_GLOP_XI = 0.1
_BLORP_XI = 0.08


def _glops(dur, times, fmin, fmax, seed):
    """Big, thick bubbles of a heavy liquid: low, quickly damped, barely
    rising, each with a short dark burst of the liquid giving way, so it
    reads as a thick 'blub' rather than a tone."""
    r = rng(seed)
    rb = rng(seed + 1)
    out = silence(dur)
    nb = n_samples(0.08)
    for t0 in times:
        f0 = math.exp(r.uniform(math.log(fmin), math.log(fmax)))
        amp = r.uniform(0.6, 1.0)
        _add(out, t0, _bubble(f0, amp, _GLOP_XI, 3.0))
        _add(out, t0, _norm(lowpass(rb.standard_normal(nb), 350, 2)) * _ar(nb, 0.002, 0.025), 0.5 * amp)
    return out


def _bubbles(dur, times, fmin, fmax, seed, xi=0.15, damp=1.0):
    """A swarm of bubbles at `times`, sizes log-uniform in fmin..fmax
    (`damp` > 1: a thicker, more viscous liquid)."""
    r = rng(seed)
    bus = _Bus(dur)
    for t0 in times:
        f0 = math.exp(r.uniform(math.log(fmin), math.log(fmax)))
        bus.add(t0, _bubble(f0, (fmin / f0) ** 0.4 * r.uniform(0.4, 1.0), xi * r.uniform(0.7, 1.4), damp))
    return bus.x


def _splash(seed, size=1.0, length=0.4):
    """Liquid flung on stone: a wet slap, a burst of bubbles, droplets."""
    r = rng(seed)
    n = n_samples(length)
    body = _norm(highpass(lowpass(pink(length, seed), 1800 + 1200 * size, 2), 160, 2)) * _ar(n, 0.002, 0.03 + 0.03 * size)
    slap = _norm(highpass(r.uniform(-1, 1, n), 1500, 2)) * _ar(n, 0.0005, 0.006)
    bt = 0.002 + np.sort(r.exponential(0.03, int(12 + 10 * size)))
    bub = _bubbles(length, bt[bt < length - 0.05], 450, 2600, seed + 1, 0.25)
    dt = np.sort(r.uniform(0.04, 0.3, int(6 + 6 * size)))
    drops = _bubbles(length, dt, 1500, 4200, seed + 2, 0.3)
    return _norm(0.8 * body + 0.5 * slap + 0.6 * _norm(bub) + 0.3 * _norm(drops))


# --------------------------------------------------------------------------
# Glass, metal, wood

_GLASS = ((1.0, 1.0, 1.0), (2.32, 0.6, 0.55), (4.25, 0.4, 0.3), (6.63, 0.25, 0.18), (9.38, 0.16, 0.1))


def _glass(f0, dur, decay, seed, bright=1.0):
    """A glass or crystal ping: doublet modes (they beat slowly)."""
    r = rng(seed)
    modes = []
    for ratio, dk, a in _GLASS:
        f = f0 * ratio * (1 + r.uniform(-0.004, 0.004))
        a2 = a * (bright if ratio > 1 else 1.0)
        modes.append((f, decay * dk, a2))
        modes.append((f * (1 + r.uniform(0.0012, 0.0025)), decay * dk * 0.9, a2 * 0.7))
    x = _modal(dur, modes, seed)
    n = len(x)
    tick = highpass(r.uniform(-1, 1, n), 4000, 2) * _ar(n, 0.0002, 0.0012)
    return _norm(_norm(x) + 0.35 * bright * _norm(tick))


def _clank(seed, base, decay, length=0.6, count=10, bright=1.0):
    """Iron struck or set down: inharmonic modes + a short strike noise."""
    r = rng(seed)
    x = _norm(_modal(length, metal_modes(base, count, 1.0, decay, seed), seed))
    n = len(x)
    strike = _norm(lowpass(highpass(r.uniform(-1, 1, n), 800, 2), 9000 * bright, 2)) * _ar(n, 0.0003, 0.003)
    return _norm(x + 0.7 * strike)


def _thud(seed, length=0.2, cutoff=260, tau=0.04):
    """Contact with stone: low muffled noise thump."""
    r = rng(seed)
    n = n_samples(length)
    x = _norm(highpass(lowpass(r.standard_normal(n), cutoff, 2), 50, 2))
    return _norm(x * _ar(n, 0.0015, tau))


def _whoosh(dur, seed, c0, c1, octaves=1.4, peak_at=0.5, power=2.0):
    x = _moving_band(pink(dur, seed), c0, c1, octaves)
    return _norm(x * env_swell(dur, peak_at, power))


def _whine(dur, f0, f1, seed, curve=1.0, jitter=0.0):
    """A capacitor/charge whine: a rising sine with weak harmonics. `jitter`
    lets its pitch wander a little (an unsteady charge, not an oscillator)."""
    t = time_axis(dur)
    u = t / max(dur, 1e-6)
    f = f0 * (f1 / f0) ** (u ** curve)
    f = f * (1 + 0.004 * np.sin(2 * np.pi * 9 * t))
    if jitter:
        f = f * (1 + jitter * _norm(lowpass(rng(seed).standard_normal(len(t)), 40, 1)))
    ph = np.cumsum(f) / SR
    return _norm(np.sin(2 * np.pi * ph) + 0.3 * np.sin(4 * np.pi * ph) + 0.1 * np.sin(6 * np.pi * ph))


# ==========================================================================
# Storm cards

@sound("card_arc_bolt", loudness=_LOUD, wet=_WET)
def card_arc_bolt(seed):
    """A sharp crack of lightning, a snap."""
    dur, T = 0.75, 0.09
    b = _Bus(dur)
    _intro(b, seed)
    # the air charges: sparks gather just before the strike
    pre_d = 0.055
    u = time_axis(pre_d) / pre_d
    b.add(T - pre_d, _ecrackle(pre_d, 300 + 4000 * u ** 2, seed + 3, 3000, 10000) * u, 0.22)
    # the crack: a main front, a second rip 14 ms later, the torn channel
    b.add(T, _snap(seed + 4, 0.5, 1.0), 0.8)
    b.add(T + 0.014, _snap(seed + 5, 0.3, 1.0, 0.06), 0.45)
    b.add(T, _tear(0.16, seed + 6, 7500, 2200, 8000, 0.045), 0.7)
    # the bolt's buzz on A2, a short burst
    m = n_samples(0.26)
    b.add(T, _buzz(0.26, _A2, seed + 7) * _ar(m, 0.002, 0.05), 0.3)
    # the air slams shut: a short, not too deep thump (lean: a quick bolt)
    b.add(T, _thump(seed + 8, 95, 0.04, 0.2, 260), 0.22)
    # leftover charge ticks away, quieter and sparser
    d = 0.32
    ta = time_axis(d)
    b.add(T + 0.08, _ecrackle(d, 160 * np.exp(-ta / 0.12), seed + 9) * np.exp(-ta / 0.1), 0.22)
    return _finish(b)


_EVENTS["card_arc_bolt"] = (0.0, 0.09)


@sound("card_chain_lightning", loudness=_LOUD, wet=_WET)
def card_chain_lightning(seed):
    """A crackling bolt that leaps three times, each jump higher."""
    dur = 0.9
    J = (0.09, 0.32, 0.55)
    F = (_A2, _D3, _F3)              # the buzz climbs A2-D3-F3 with each jump
    C = (2000, 3600, 6400)           # the torn air rises ~0.85 octave a jump
    SIZE = (0.8, 0.4, 0.15)          # each leap is a thinner arc...
    BRIGHT = (0.5, 1.0, 1.6)         # ...and a brighter one: its torn air
    AIR = (6000, 10000, 14000)       # reaches higher (the first, big crack is fuller)
    LEVEL = (1.0, 0.9, 0.8)          # and it carries a little less each time
    b = _Bus(dur)
    _intro(b, seed)
    for i, T in enumerate(J):
        # the same arc every time (one seed), so only the deliberate steps
        # change from jump to jump: smaller, brighter, thinner
        arc = lowpass(highpass(_snap(seed + 10, SIZE[i], BRIGHT[i]), 250 * 2 ** i, 2), AIR[i], 2)
        b.add(T, arc, 0.7 * LEVEL[i])
        b.add(T, _tear(0.1, seed + 20 + i, C[i] * 1.6, C[i] * 0.8, 6500, 0.03), 0.6 * LEVEL[i])
        m = n_samples(0.2)
        b.add(T, highpass(_buzz(0.2, F[i], seed + 30 + i), 100 * 2 ** i, 2) * _ar(m, 0.002, 0.05), 0.4 * LEVEL[i])
        if i < 2:
            # only the first strike slams the air (the second barely)
            b.add(T, _thump(seed + 40 + i, 85 + 20 * i, 0.06, 0.3, 260), (0.22, 0.07)[i])
    for i in range(2):
        a, z = J[i] + 0.03, J[i + 1]
        d = z - a
        u = time_axis(d) / d
        hi = min(C[i + 1] * 1.8, 12000)
        b.add(a, _ecrackle(d, 400 + 3000 * u ** 2, seed + 50 + i, C[i], hi) * (0.3 + 0.7 * u), 0.25)
    d = 0.3
    ta = time_axis(d)
    b.add(J[2] + 0.04, _ecrackle(d, 500 * np.exp(-ta / 0.08), seed + 60, 3000, 10000) * np.exp(-ta / 0.08), 0.25)
    return _finish(b)


_EVENTS["card_chain_lightning"] = (0.0, 0.09, 0.32, 0.55)


@sound("card_piercing_ray", loudness=_LOUD, wet=_WET)
def card_piercing_ray(seed):
    """A charging whine, then a searing, sustained, bright beam."""
    dur, T = 0.9, 0.33
    b = _Bus(dur)
    _intro(b, seed)
    # the charge: air rushes into the gathering light (a rising noise band)
    # around an unsteady whine, the storm's buzz underneath
    d = T - 0.04
    m = n_samples(d)
    u = np.arange(m) / m
    b.add(0.04, _whine(d, _D5, _D6, seed + 3, 1.6, 0.01) * u ** 2, 0.25)
    b.add(0.04, _norm(_moving_band(pink(d, seed + 4), 700, 4500, 1.2)) * u ** 2.5, 0.3)
    b.add(0.04, _buzz(d, _A2, seed + 5, 0.6) * u ** 3, 0.15)
    # ignition
    b.add(T, _snap(seed + 6, 0.5, 1.0), 0.6)
    # the beam is burning air: a sear (a 1.8-10 kHz band peaking near 5 kHz,
    # rough and flickering like a flame, never a steady LFO) over a chord of
    # D5-A5-D6 whose FM index flares at random, so its timbre burns too
    d2 = dur - T
    m2 = n_samples(d2)
    r = rng(seed + 7)
    flame = 0.5 + 0.5 * _norm(lowpass(r.standard_normal(m2), 30, 2))
    chord = np.zeros(m2)
    for f, ratio, idx, g in ((_D5, 1.0, 2.0, 0.6), (_A5, 2.0, 1.0, 0.35), (_D6, 1.0, 1.5, 0.3)):
        burn = idx * (1 + 0.4 * _norm(lowpass(r.standard_normal(m2), 30, 1)))
        chord += g * (fm(f, f * ratio, burn, d2) + fm(f * 1.004, f * ratio * 1.004, burn, d2))
    chord *= 1 - 0.18 * flame
    sear = peak_eq(lowpass(highpass(r.uniform(-1, 1, m2), 1800, 2), 10000, 2), 5000, 6, 0.8)
    sear = _norm(sear) * (0.45 + 0.55 * _norm(np.abs(lowpass(r.standard_normal(m2), 80, 1))))
    sear *= 1 - 0.3 * flame
    env = env_points(d2, [(0, 0), (0.006, 1.0), (0.38, 0.85), (d2 - 0.02, 0.0)])
    b.add(T, (_norm(chord) * 0.45 + 0.85 * sear) * env, 0.8)
    b.add(T, _ecrackle(d2, 400, seed + 8, 4000, 10000) * env, 0.35)
    b.add(T, _buzz(d2, _A2, seed + 9) * env, 0.2)
    return _finish(b)


_EVENTS["card_piercing_ray"] = (0.0, 0.04, 0.33)


# Smaller than the other cards in level too (SOUND_SPEC.md).
@sound("card_spark", loudness=-23, wet=_WET)
def card_spark(seed):
    """A tiny spark snap."""
    dur, T = 0.5, 0.075
    b = _Bus(dur)
    _intro(b, seed)
    # one small spark jumping a gap: the snap, two after-ticks
    b.add(T, _snap(seed + 3, 0.2, 1.0, 0.05), 0.45)
    b.add(T + 0.009, _snap(seed + 4, 0.1, 1.0, 0.03), 0.22)
    b.add(T + 0.023, _snap(seed + 5, 0.05, 1.0, 0.03), 0.14)
    b.add(T + 0.0005, _tear(0.08, seed + 6, 8500, 4500, 4000, 0.025), 0.5)
    # its tiny buzz, an octave above the storm's A2 and thin (no fundamental:
    # a small spark has no body for the hall to boom with)
    m = n_samples(0.08)
    b.add(T, highpass(_buzz(0.08, _A3, seed + 7), 500, 2) * _ar(m, 0.001, 0.018), 0.15)
    # it fizzles out: a thin, bright hiss with a few spits
    d = 0.22
    b.add(T + 0.008, _sizzle(d, seed + 8, 4000, 11000, 150) * _ar(n_samples(d), 0.004, 0.06), 0.3)
    return _finish(b)


_EVENTS["card_spark"] = (0.0, 0.075)


def _hammer_anvil(seed, full=True):
    """A hammer on a small anvil: steel click, a bright inharmonic ring tuned
    near D6, the anvil's mass and the hammer's thump."""
    r = rng(seed)
    length = 0.8
    n = n_samples(length)
    k = 0.4 if full else 0.25
    ratios = (1.0, 1.52, 2.17, 2.79, 3.44, 4.31)
    decays = (0.75, 0.5, 0.38, 0.27, 0.18, 0.13)
    amps = (1.0, 0.7, 0.55, 0.4, 0.3, 0.2)
    modes = [(_D6 * q * (1 + r.uniform(-0.003, 0.003)), dk * k, a) for q, dk, a in zip(ratios, decays, amps)]
    modes.append((_D6 * 0.355, 0.12, 0.6))
    ring = _norm(_modal(length, modes, seed))
    click = _norm(highpass(r.uniform(-1, 1, n), 2000, 2)) * _ar(n, 0.0002, 0.0015)
    thump = _thud(seed + 1, length, 450, 0.025)
    return _norm(ring + 0.8 * click + 0.4 * thump)


@sound("card_spark_forge", loudness=_LOUD, wet=_WET)
def card_spark_forge(seed):
    """A small forge: hammer on anvil, sparks fly."""
    dur = 0.9
    H = (0.08, 0.26)             # early enough for the anvil to ring out
    b = _Bus(dur)
    _intro(b, seed)
    d = 0.8
    b.add(0.05, _roar(d, seed + 3, 300) * env_points(d, [(0, 0), (0.08, 1), (0.65, 0.8), (d, 0)]), 0.12)
    b.add(0.05, _fire_crackle(d, 25, seed + 4), 0.1)
    for i, T in enumerate(H):
        g = 0.6 if i == 0 else 1.0
        b.add(T, _hammer_anvil(seed + 10 + i, i == 1), g)
        ds = 0.3
        b.add(T + 0.003, _ecrackle(ds, 900 * (1 + i) * np.exp(-time_axis(ds) / 0.08), seed + 20 + i, 4000, 12000, 0.0002), 0.3 * g)
    return _finish(b, release=0.12)


_EVENTS["card_spark_forge"] = (0.0, 0.08, 0.26)


@sound("card_storm_crown", loudness=_LOUD, wet=_WET)
def card_storm_crown(seed):
    """Distant thunder rolls, a crackling halo builds overhead."""
    dur, K = 0.9, 0.65
    b = _Bus(dur)
    _intro(b, seed)
    # far thunder: three rolls (two with a ragged after-rumble), weakening
    rolls = [(0.0, 0.04, 0.1, 1.0), (0.07, 0.03, 0.08, 0.6), (0.2, 0.06, 0.14, 0.85),
             (0.3, 0.04, 0.1, 0.5), (0.42, 0.08, 0.18, 0.6)]
    b.add(0.03, _thunder(0.87, seed + 3, rolls, 200), 1.1)
    # the halo gathers overhead (0.2 -> K), then hangs and fades to the end
    d = dur - 0.2
    m = n_samples(d)
    t = np.arange(m) / SR
    tk = K - 0.2
    grow = np.clip(t / tk, 0, 1)
    env = np.where(t < tk, grow ** 2, np.exp(-(t - tk) / 0.05))
    dens = 30 + 2500 * grow ** 2 * np.where(t < tk, 1.0, np.exp(-(t - tk) / 0.04))
    b.add(0.2, _ecrackle(d, dens, seed + 4, 3000, 10000) * np.maximum(env, 0.15 * grow), 0.35)
    crown = np.zeros(m)
    r = rng(seed + 5)
    for i, f in enumerate((_D5, _A5, _D6)):
        crown += (np.sin(2 * np.pi * f * t) + 0.6 * np.sin(2 * np.pi * f * 1.003 * t + r.uniform(0, 6.28))) / (1 + i)
    crown *= 1 - 0.35 * (0.5 + 0.5 * np.sin(2 * np.pi * (6 + 5 * grow) * t))
    b.add(0.2, _norm(crown) * env, 0.28)
    b.add(0.2, sweep_lowpass(_buzz(d, _A2, seed + 6), 200, 3000) * env, 0.25)
    # the halo's sparks snap closer and closer; the crown closes at K, early
    # enough for its glass ring to die away before the end
    for j, (ts, s) in enumerate(((0.41, 0.12), (0.49, 0.15), (0.56, 0.2), (0.61, 0.22))):
        b.add(ts, _snap(seed + 10 + j, s, 1.0, 0.05), 0.22 + 0.08 * j)
    b.add(K, _snap(seed + 14, 0.35, 1.0, 0.08), 0.75)
    b.add(K, _glass(_D6, dur - K, 0.08, seed + 15, 0.7), 0.3)
    b.add(K, _glass(_A5, dur - K, 0.08, seed + 16, 0.5), 0.2)
    return _finish(b, release=0.1)


_EVENTS["card_storm_crown"] = (0.0, 0.03, 0.2, 0.65)


@sound("card_shock_floor", loudness=_LOUD, wet=_WET)
def card_shock_floor(seed):
    """A metal plate set down, then an electric hum spreads across it."""
    dur, P = 0.9, 0.1
    b = _Bus(dur)
    _intro(b, seed)
    base = 230.0
    b.add(P, _clank(seed + 3, base, 0.35, 0.6, 11), 0.7)
    b.add(P, _thud(seed + 4), 0.6)
    b.add(P + 0.032, _clank(seed + 3, base, 0.2, 0.4, 11), 0.2)
    d = 0.68
    m = n_samples(d)
    u = np.arange(m) / m
    env = np.clip(u / 0.25, 0, 1) ** 1.5 * np.clip((1 - u) / 0.3, 0, 1) ** 1.5
    # the hum opens up as it spreads; a second, slightly detuned buzz joins
    # from the far edge of the plate and the plate's own modes sing along
    hum = _norm(sweep_lowpass(_buzz(d, _A2, seed + 5), 250, 6000))
    far = _norm(sweep_lowpass(_buzz(d, _A2 * 1.006, seed + 7, 0.8), 200, 4000))
    far *= np.clip((u - 0.2) / 0.4, 0, 1)
    plate = [(f, 6.0, 1.0) for f, _, _ in metal_modes(base, 6, 1.0, 1.0, seed + 3)]
    sing = _norm(formant(hum, plate))
    b.add(0.2, (0.5 * hum + 0.3 * far + 0.25 * sing) * env, 1.0)
    # sparks run over the plate as the hum spreads: densest about 0.65 s,
    # then they thin out and fade with the hum (never switched off)
    dc = 0.6
    tc = time_axis(dc)
    dens = 20 + 480 * np.where(tc < 0.4, (tc / 0.4) ** 1.5, 1 - 0.6 * (tc - 0.4) / 0.2)
    b.add(0.25, _ecrackle(dc, dens, seed + 6) * np.clip((dc - tc) / 0.18, 0, 1) ** 1.5, 0.25)
    return _finish(b)


_EVENTS["card_shock_floor"] = (0.0, 0.1, 0.2)


@sound("card_tesla_coil", loudness=_LOUD, wet=_WET)
def card_tesla_coil(seed):
    """An iron coil set down with a clank, its capacitor whines up and arcs once."""
    dur, C, A = 0.9, 0.1, 0.62
    b = _Bus(dur)
    _intro(b, seed)
    # heavy iron base on stone (the stone damps it), the copper coil's
    # springy ring, a little settle
    b.add(C, _clank(seed + 3, 175, 0.3, 0.6, 10), 0.8)
    b.add(C, _clank(seed + 4, 820, 0.18, 0.4, 6), 0.25)
    b.add(C, _thud(seed + 5), 0.6)
    b.add(C + 0.028, _clank(seed + 3, 175, 0.15, 0.4, 10), 0.25)
    d = A - 0.2
    m = n_samples(d)
    u = np.arange(m) / m
    cut = np.clip((d - np.arange(m) / SR) / 0.003, 0, 1)
    b.add(0.2, _whine(d, 900, 5200, seed + 6) * u ** 1.6 * cut, 0.3)
    b.add(0.2, sweep_lowpass(_buzz(d, _A2, seed + 7), 300, 3000) * u ** 2 * cut, 0.2)
    b.add(A, _arc(seed + 8, _A2, 1.0, 0.25), 1.0)
    d = 0.26
    ta = time_axis(d)
    b.add(A + 0.04, _ecrackle(d, 300 * np.exp(-ta / 0.08), seed + 9) * np.exp(-ta / 0.09), 0.22)
    return _finish(b)


_EVENTS["card_tesla_coil"] = (0.0, 0.1, 0.2, 0.62)


# ==========================================================================
# Fire card

@sound("card_firebomb", loudness=_LOUD, wet=_WET)
def card_firebomb(seed):
    """A fuse lit and a bomb tossed (the explosion plays separately)."""
    dur, L, Tt = 0.85, 0.09, 0.42
    b = _Bus(dur)
    _intro(b, seed)
    d = 0.035
    m = n_samples(d)
    u = np.arange(m) / m
    r = rng(seed + 3)
    b.add(L - d, _moving_band(r.uniform(-1, 1, m), 2500, 5500, 1.2, 1.2, 1.0, 512, 128) * u, 0.35)
    n = n_samples(0.3)
    b.add(L, _norm(highpass(lowpass(pink(0.3, seed + 4), 700, 2), 60, 2)) * _ar(n, 0.008, 0.06), 0.45)
    b.add(L, _fire_crackle(0.3, 400 * np.exp(-time_axis(0.3) / 0.05), seed + 5), 0.3)
    b.add(L, _roar(0.3, seed + 6, 350) * _ar(n, 0.01, 0.08), 0.2)
    df = dur - L
    fz = _sizzle(df, seed + 7)
    rel = Tt - L

    def recede(f, t):
        v = max(t - rel, 0) / max(df - rel, 1e-6)
        c = 9000 * (1800 / 9000) ** min(v, 1)
        return (1 / np.sqrt(1 + (f / c) ** 4)) * (1 - 0.85 * min(v, 1))
    fz = stft_filter(fz, recede)
    fz *= np.clip(np.arange(len(fz)) / SR / 0.02, 0, 1)
    b.add(L, fz, 0.32)
    b.add(0.3, _whoosh(0.3, seed + 8, 350, 1100, 1.4, 0.45), 0.55)
    b.add(0.36, _modal(0.12, [(2100, 0.03, 1.0), (3400, 0.02, 0.6), (5000, 0.012, 0.4)], seed + 9), 0.2)
    return _finish(b)


_EVENTS["card_firebomb"] = (0.0, 0.09, 0.36, 0.42)


# ==========================================================================
# Poison cards

@sound("card_toxic_wave", loudness=_LOUD, wet=_WET)
def card_toxic_wave(seed):
    """A wave of noxious gas: a low wet hiss spreading, bubbles."""
    dur, S = 0.9, 0.06
    b = _Bus(dur)
    _intro(b, seed)
    d = dur - S
    m = n_samples(d)
    r = rng(seed + 3)
    env = env_swell(d, 0.45, 1.5)
    gurgle = 0.65 + 0.35 * _norm(lowpass(r.standard_normal(m), 30, 1))
    gas = _norm(_moving_band(pink(d, seed + 4), 350, 1600, 1.2, 3.0)) * gurgle
    b.add(S, gas * env, 0.7)
    b.add(S, _norm(highpass(lowpass(brown(d, seed + 5), 180, 2), 45, 2)) * env, 0.2)
    # the wet hiss at the wave's front: a 2.2-6 kHz band (no spray-can air
    # on top) that gurgles with the gas
    hiss = _norm(lowpass(highpass(r.uniform(-1, 1, m), 2200, 2), 6000, 2))
    b.add(S, hiss * gurgle * env_swell(d, 0.2, 1.5), 0.12)
    times = random_times(dur, 70, seed + 6, 0.12, 0.85, lambda v: math.sin(math.pi * min(v * 1.2, 1)) ** 0.7)
    b.add(0.0, _norm(_bubbles(dur, times, 280, 1200, seed + 7, 0.2, 1.6)), 0.35)
    gt = np.sort(r.uniform(0.25, 0.7, 4))
    b.add(0.0, _norm(_glops(dur, gt, 130, 220, seed + 8)), 0.4)
    return _finish(b)


_EVENTS["card_toxic_wave"] = (0.0, 0.06, 0.44)


@sound("card_venom_needle", loudness=_LOUD, wet=_WET)
def card_venom_needle(seed):
    """A needle flicked (thin whistle), a tiny wet prick."""
    dur, F, P = 0.6, 0.05, 0.3
    b = _Bus(dur)
    _intro(b, seed)
    b.add(F, _modal(0.08, [(6800, 0.02, 1.0), (9100, 0.012, 0.6)], seed + 3), 0.15)
    # the thin whistle of the needle in flight: aeolian noise (a 0.5-octave
    # band) carries it, with only a faint, unsteady edge tone in it; its
    # pitch drops a little as it flies away (Doppler)
    d = P - F - 0.01
    m = n_samples(d)
    t = np.arange(m) / SR
    f = 6000 * (5000 / 6000) ** (t / d)
    f = f * (1 + 0.012 * _norm(lowpass(rng(seed + 8).standard_normal(m), 80, 1)))
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR)
    air = _moving_band(rng(seed + 4).uniform(-1, 1, m), 6000, 5000, 0.5, 0.5, 1.0, 512, 128)
    env = env_swell(d, 0.35, 1.5)
    b.add(F + 0.01, (0.035 * tone + 0.6 * _norm(air)) * env, 0.25)
    # the prick: a tiny tick, a wet squelch (the loudest moment), droplets
    r = rng(seed + 5)
    n = n_samples(0.05)
    tick = _norm(highpass(r.uniform(-1, 1, n), 5000, 2)) * _ar(n, 0.0002, 0.0015)
    b.add(P, tick, 0.6)
    b.add(P, _norm(bandpass(r.standard_normal(n), 900, 1.0)) * _ar(n, 0.001, 0.008), 0.55)
    b.add(P, _norm(_bubbles(0.1, [0.002, 0.009, 0.02], 1200, 2600, seed + 6, 0.3)), 0.3)
    d2 = 0.22
    b.add(P + 0.01, _sizzle(d2, seed + 7, 3000, 8000, 40) * _ar(n_samples(d2), 0.02, 0.07), 0.08)
    return _finish(b)


_EVENTS["card_venom_needle"] = (0.0, 0.05, 0.3)


@sound("card_caustic_bloom", loudness=_LOUD, wet=_WET)
def card_caustic_bloom(seed):
    """An acid flower bursts open: bubbling bloom, sizzle."""
    dur, B = 0.9, 0.28
    b = _Bus(dur)
    _intro(b, seed)
    times = random_times(B, 120, seed + 3, 0.05, B - 0.01, lambda v: v)
    b.add(0.0, _norm(_bubbles(B + 0.1, times, 500, 1600, seed + 4, 0.15, 1.3)), 0.35)
    d = B - 0.05
    m = n_samples(d)
    b.add(0.05, _norm(bandpass(pink(d, seed + 5), 650, 1.0)) * (np.arange(m) / m) ** 2, 0.15)
    # the bud bursts: the splash leads, over one big, barely rising blorp
    # with a low plop of liquid body, and the petals unfolding
    b.add(B, _bubble(150, 1.0, _BLORP_XI, 2.2), 0.38)
    nb = n_samples(0.12)
    b.add(B, _norm(lowpass(pink(0.12, seed + 11), 500, 2)) * _ar(nb, 0.002, 0.03), 0.5)
    b.add(B, _splash(seed + 6, 1.2), 0.7)
    b.add(B, _whoosh(0.15, seed + 7, 500, 3000, 1.4, 0.3), 0.3)
    # the bloom: dense bubbling, acid sizzle, both dying away by the end
    d = dur - B - 0.01
    m = n_samples(d)
    u = np.arange(m) / m
    bt = random_times(d, 130, seed + 8, 0.0, d, lambda v: 1 - 0.7 * v)
    b.add(B + 0.01, _norm(_bubbles(d, bt, 350, 1600, seed + 9, 0.15, 1.3)) * (1 - u) ** 0.8, 0.6)
    sz_env = (1 - np.exp(-np.arange(m) / SR / 0.03)) * (1 - u) ** 1.2
    b.add(B + 0.01, _sizzle(d, seed + 10, 3000, 9000, 120) * sz_env, 0.5)
    return _finish(b)


_EVENTS["card_caustic_bloom"] = (0.0, 0.05, 0.28)


def _cork(seed, pitch=1.0):
    """A cork twisted out of a vial: a short friction squeak, then the pop
    (a Helmholtz resonance of the neck)."""
    r = rng(seed)
    length = 0.14
    n = n_samples(length)
    out = np.zeros(n)
    sq = 0.025
    m = n_samples(sq)
    t = np.arange(m) / SR
    # stick-slip friction: a sawtooth-like wave, rich in harmonics, whose
    # period never settles, through the vial's broad resonance
    f = 1500 * pitch * (2300 / 1500) ** (t / sq)
    f = f * (1 + 0.03 * _norm(lowpass(rng(seed + 1).standard_normal(m), 400, 1)))
    rub = _norm(bandpass(saw(f, n=m), 2600 * pitch, 0.9))
    squeak = rub * (0.6 + 0.4 * _norm(lowpass(r.standard_normal(m), 300, 1)))
    squeak += 0.4 * _norm(bandpass(r.uniform(-1, 1, m), 2000 * pitch, 2))
    out[:m] += 0.4 * squeak * env_swell(sq, 0.6, 1.5)
    k = m
    p = n - k
    tp = np.arange(p) / SR
    fp = 520 * pitch * (1 + 0.25 * np.exp(-tp / 0.006))
    pop = np.sin(2 * np.pi * np.cumsum(fp) / SR) * _ar(p, 0.0004, 0.014)
    click = _norm(highpass(r.uniform(-1, 1, p), 1200, 2)) * _ar(p, 0.0002, 0.0015)
    out[k:] += pop + 0.5 * click
    return _norm(out)


def _dice(dur, start, seed, dice=2):
    """Bone dice tumbling on stone: bounces that come faster and softer,
    a few die-on-die ticks, a last settle."""
    r = rng(seed)
    bus = _Bus(dur)
    for _ in range(dice):
        t = start + r.uniform(0, 0.02)
        gap = r.uniform(0.06, 0.08)
        a = 1.0
        while t < dur - 0.05 and a > 0.08:
            modes = [(r.uniform(2200, 2900), 0.012, 1.0), (r.uniform(3600, 4500), 0.008, 0.7),
                     (r.uniform(5200, 6600), 0.005, 0.5), (r.uniform(700, 1000), 0.01, 0.6)]
            click = _modal(0.05, modes, int(r.integers(1 << 30)), 0.0001)
            bus.add(t, _norm(click), a * r.uniform(0.7, 1.0))
            t += gap * r.uniform(0.8, 1.2)
            gap *= 0.72
            a *= 0.8
    for _ in range(3):
        modes = [(r.uniform(3000, 4200), 0.006, 1.0), (r.uniform(5500, 7000), 0.004, 0.6)]
        bus.add(start + r.uniform(0.03, 0.2), _norm(_modal(0.03, modes, int(r.integers(1 << 30)), 0.0001)), 0.35)
    return bus.x


@sound("card_twin_venom", loudness=_LOUD, wet=_WET)
def card_twin_venom(seed):
    """Two vials uncorked and splashed, the dice rattle."""
    dur = 0.9
    b = _Bus(dur)
    _intro(b, seed)
    b.add(0.07, _cork(seed + 3, 1.0), 0.7)
    b.add(0.17, _cork(seed + 4, 1.12), 0.7)
    b.add(0.3, _splash(seed + 5, 0.8), 0.75)
    b.add(0.4, _splash(seed + 6, 0.9), 0.75)
    b.add(0.0, _dice(dur, 0.52, seed + 7), 0.6)
    return _finish(b)


_EVENTS["card_twin_venom"] = (0.0, 0.095, 0.195, 0.3, 0.4, 0.52)


# ==========================================================================
# Glass and crystal cards

@sound("card_volatile_study", loudness=_LOUD, wet=_WET)
def card_volatile_study(seed):
    """Glassware clinks, a volatile mixture fizzes and pops."""
    dur = 0.9
    b = _Bus(dur)
    _intro(b, seed)
    b.add(0.08, _glass(_D7, 0.6, 0.35, seed + 3), 0.55)
    b.add(0.15, _glass(_F7, 0.6, 0.3, seed + 4), 0.45)
    d = 0.7
    m = n_samples(d)
    u = np.arange(m) / m
    fizz = _ecrackle(d, 800 + 2700 * u ** 0.7, seed + 5, 3000, 11000, 0.00015, 1.5)
    bt = random_times(d, 120, seed + 6, 0.0, d)
    micro = _norm(_bubbles(d, bt, 2000, 5000, seed + 7, 0.3))
    env = np.clip(u / 0.3, 0, 1) * np.clip((1 - u) / 0.2, 0, 1)
    b.add(0.18, (fizz + 0.6 * micro) * env, 0.28)
    # the mixture pops, harder each time; every pop throws a little spark
    for j, (tp, s) in enumerate(((0.42, 0.5), (0.57, 0.7), (0.71, 1.0))):
        r = rng(seed + 10 + j)
        n = n_samples(0.08)
        burst = _norm(bandpass(r.uniform(-1, 1, n), r.uniform(1300, 2800), 1.5)) * _ar(n, 0.0005, 0.004)
        b.add(tp, burst, 0.5 * s)
        pop = _bubble(r.uniform(330, 420), 1.0, 0.35)
        b.add(tp, pop * _ar(len(pop), 0.0004, 0.02), 0.45 * s)
        b.add(tp, _thud(seed + 30 + j, 0.1, 500, 0.012), 0.25 * s)
        b.add(tp + 0.002, _snap(seed + 20 + j, 0.15, 1.0, 0.05), 0.35 * s)
    return _finish(b)


_EVENTS["card_volatile_study"] = (0.0, 0.08, 0.15, 0.42, 0.57, 0.71)


@sound("card_prismatic_barrage", loudness=_LOUD, wet=_WET)
def card_prismatic_barrage(seed):
    """Three crystalline shots: glassy pings in D Phrygian, rising."""
    dur = 0.9
    S = (0.09, 0.25, 0.41)
    N = (_D6, _F6, _A6)
    b = _Bus(dur)
    _intro(b, seed)
    for i, T in enumerate(S):
        # each shot is loosed with a quick rising zip of air...
        dz = 0.04
        m = n_samples(dz)
        u = np.arange(m) / m
        b.add(T - dz, _norm(_moving_band(pink(dz, seed + 10 + i), 3000, 9000, 1.0, 1.0, 1.0, 512, 128)) * u ** 2, 0.5)
        # ...cracks off as a glassy snap...
        n = n_samples(0.02)
        crack = _norm(highpass(rng(seed + 50 + i).uniform(-1, 1, n), 5000, 2)) * _ar(n, 0.0002, 0.003)
        b.add(T, crack, 0.5)
        # ...and rings short, so the three shots stay apart (the higher, smaller
        # crystals ring purer: their upper partials would sit on the glitter)
        b.add(T, _glass(N[i], dur - T, 0.15 + 0.02 * i, seed + 20 + i, 1.0 - 0.12 * i), 0.7)
        b.add(T, _glass(N[i] / 2, min(0.6, dur - T), 0.1, seed + 30 + i, 0.5), 0.25)
        # the crystal splinters as it flies: a short high glitter, finer and
        # longer for each smaller shot
        dg = 0.09
        splinter = _ecrackle(dg, 2500 * np.exp(-time_axis(dg) / (0.025 + 0.008 * i)), seed + 40 + i, 6000, 14000, 0.0003)
        b.add(T + 0.002, splinter, 0.45 + 0.15 * i)
    return _finish(b, release=0.15)


_EVENTS["card_prismatic_barrage"] = (0.0, 0.09, 0.25, 0.41)
