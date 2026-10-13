"""Family `brute` -- the huge armoured brute (see SOUND_SPEC.md).

Iron plates, chains, a heavy cleaver, a skull mask. Slow, crushing, low.

The whole family is built from one body, so every action sounds like the
same creature while each action keeps its own shape:

  _stomp     an armoured footfall on stone: a sub mode that falls as the
             floor takes the weight, a chest mode, a lowpassed air/flesh
             puff, dense very short stone-floor modes, a 2-6 kHz grit scuff.
  _plate     his iron plates: thick strapped (so damped) inharmonic plate
             modes with split pairs that beat, base ~164 Hz. `decay` (as in
             dsp.modal) is a time constant: T60 ~ 6.9 x decay. Body-worn
             plates use 0.08-0.12 (T60 0.55-0.8 s): they knock, not ring;
             the one long metal ring is the death's falling cleaver.
  _rattle    the small iron pieces of the armour (lames, buckles, rivets).
  _chain     his chains: a bank of tiny link rings, shaken in clusters.
  _cleaver   the cleaver: a thick iron bar (free-free bar ratios plus
             torsional modes), base ~252 Hz; high partials die first.
  _growl     breath and growl behind the skull mask: a ~50 Hz raspy pulse
             with period doubling + pink breath, through dark moving
             formants and a hollow mask cavity (no voice, no words).
  _drag      his card's iron base dragged heavily over stone: chattering
             noise + grit through a band that follows the card's speed,
             with a faint papery edge (the game's paper signature).

Everything is dry and mono at SR; the build adds the stone hall.
"""
import math

import numpy as np

from dsp import *  # noqa: F401,F403
from dsp import SR, n_samples, rng, lowpass, highpass, bandpass, formant, modal, stft_filter, \
    crackle, pink, brown, place, mix, fade, convolve, random_times
from registry import sound

# The brute's fixed timbre (shared by every sound of the family).
_PLATE_BASE = 164.0
_PLATE_RATIOS = (1.0, 1.59, 2.21, 2.94, 3.68, 4.55, 5.62, 6.79, 8.13, 9.7, 11.6, 13.9)
_CLEAVER_BASE = 252.0
_CLEAVER_RATIOS = (1.0, 1.63, 2.756, 3.91, 5.404, 7.08, 8.933, 11.1, 13.34)
_RATTLE_RATIOS = (1.0, 1.47, 2.09, 2.56, 3.2)
_LINK_RATIOS = (1.0, 1.73, 2.61)
_MASK = (1150.0, 7.0)          # the hollow skull-mask cavity (Hz, q)
_DARK = ((300.0, 3.5, 1.0), (640.0, 4.0, 0.7), (2000.0, 5.0, 0.22))   # dark "o" tract


# --------------------------------------------------------------------------
# Small utilities

def _t(n):
    return np.arange(n) / SR


def _unit(x):
    m = float(np.max(np.abs(x))) if len(x) else 0.0
    return x / m if m > 0 else x


def _band(f, center, width_oct):
    """Log-gaussian band gain (the same shape as dsp.bandpass)."""
    return np.exp(-0.5 * (np.log2(np.maximum(f, 1e-3) / center) / (width_oct / 2.355)) ** 2)


def _lfnoise(n, cutoff, seed):
    """A smooth random control signal in -1..1."""
    return _unit(lowpass(rng(seed).standard_normal(n), cutoff, 2))


def _onset(n, attack):
    e = np.ones(n)
    a = min(n, max(1, n_samples(attack)))
    e[:a] = np.linspace(0, 1, a)
    return e


def _burst(seed, dur, tau, lo=None, hi=None):
    """A decaying noise burst (contact transients, grit, slaps)."""
    n = n_samples(dur)
    x = rng(seed).uniform(-1, 1, n) * np.exp(-_t(n) / tau)
    if hi:
        x = lowpass(x, hi, 2)
    if lo:
        x = highpass(x, lo, 2)
    return fade(_unit(x), 0, 0.2 * dur)


def _grains(duration, times, seed, length=(0.005, 0.02), band=(1500, 8000), gains=None, q=1.5):
    """Short band-passed noise grains with a sharp front and a fast fall
    (paper crinkle, stone chips, grit)."""
    n = n_samples(duration)
    out = np.zeros(n)
    r = rng(seed)
    lo, hi = band
    for i, t0 in enumerate(times):
        start = int(round(t0 * SR))
        if start < 0 or start >= n:
            continue
        g = n_samples(r.uniform(*length))
        tt = _t(g)
        env = (1 - np.exp(-tt / 0.0003)) * np.exp(-tt / (g / SR / 3.0)) * np.minimum(1.0, (g - np.arange(g)) / (0.2 * g))
        burst = r.uniform(-1, 1, g) * env
        burst = bandpass(burst, math.exp(r.uniform(math.log(lo), math.log(hi))), q)
        burst = _unit(burst) * (gains[i] if gains is not None else r.uniform(0.4, 1.0))
        end = min(n, start + g)
        out[start:end] += burst[:end - start]
    return out


def _bank(seed, count, lo, hi, ratios, decay, dur):
    """A bank of small struck iron pieces (each a few short modes)."""
    r = rng(seed)
    out = []
    for k in range(count):
        b = math.exp(r.uniform(math.log(lo), math.log(hi)))
        d = decay * r.uniform(0.6, 1.4)
        modes = [(b * q * (1 + r.uniform(-0.03, 0.03)), d / (1 + 0.5 * i), 1.0 / (1 + 0.8 * i))
                 for i, q in enumerate(ratios)]
        x = modal(dur, modes, seed + 100 + k)
        # Faded over the last 30% of the buffer: a long-ringing piece is
        # never cut off with a tick.
        out.append(fade(_unit(x * _onset(len(x), 0.0002)), 0, 0.3 * dur))
    return out


def _rattle_bank(seed):
    return _bank(seed, 10, 480, 1500, _RATTLE_RATIOS, 0.06, 0.22)


def _link_bank(seed):
    return _bank(seed, 14, 1250, 3300, _LINK_RATIOS, 0.02, 0.09)


def _pebble_bank(seed):
    return _bank(seed, 8, 600, 1900, (1.0, 1.6, 2.33, 3.1), 0.007, 0.045)


def _cluster(seed, t0, length, rate, gain=1.0, env=None, burst=(1, 3), spacing=0.004):
    """Poisson events from t0 for `length` s. Density and gain follow
    env(u) (default: fading out); each event is 1-3 hits a few ms apart
    (pieces knocking into each other)."""
    if env is None:
        def env(u):
            return (1 - u) ** 1.5
    r = rng(seed)
    ev = []
    t = t0
    while True:
        u = (t - t0) / length
        lam = rate * env(min(max(u, 0.0), 1.0)) + 2.0
        t += r.exponential(1.0 / lam)
        u = (t - t0) / length
        if u >= 1:
            break
        g = gain * env(u) * r.uniform(0.35, 1.0)
        for k in range(int(r.integers(burst[0], burst[1] + 1))):
            ev.append((t + k * spacing * r.uniform(0.5, 1.5), g * 0.7 ** k))
    return ev


def _cluster_thin(seed, t0, length, rate, gain=1.0, env=None, burst=(1, 3), spacing=0.004):
    """Like _cluster, but a true inhomogeneous Poisson process (thinning):
    candidates are drawn at the envelope's peak rate and each is kept with
    probability rate(u)/peak. Use it when env starts near 0 (a swing, a
    lift), where _cluster's first gap would be drawn at the 2/s floor and
    the cluster could come out empty."""
    if env is None:
        def env(u):
            return (1 - u) ** 1.5
    r = rng(seed)
    lam_max = rate * max(env(u) for u in np.linspace(0, 1, 65)) + 2.0
    ev = []
    t = t0
    while True:
        t += r.exponential(1.0 / lam_max)
        u = (t - t0) / length
        if u >= 1:
            break
        if r.random() * lam_max > rate * env(u) + 2.0:
            continue
        g = gain * env(u) * r.uniform(0.35, 1.0)
        for k in range(int(r.integers(burst[0], burst[1] + 1))):
            ev.append((t + k * spacing * r.uniform(0.5, 1.5), g * 0.7 ** k))
    return ev


def _scatter(duration, events, bank, seed):
    """Places [(time, gain)] events, each one an element of `bank`."""
    r = rng(seed)
    return place(duration, [(t0, bank[int(r.integers(len(bank)))], g) for t0, g in events])


# --------------------------------------------------------------------------
# The brute's body

def _stomp(seed, weight=1.0, dur=0.7):
    """One armoured footfall on stone, contact at t=0 (attack < 3 ms).
    `weight` > 1 is heavier: deeper and longer."""
    n = n_samples(dur)
    t = _t(n)
    r = rng(seed)
    # The mass landing: a low mode that falls as the floor takes the weight,
    # the cuirass/torso mode (~110 Hz) and the belly (~180 Hz) over it, and
    # the air and flesh pushed out (a lowpassed puff). Driven a little: the
    # weight compresses the blow (and keeps the crest factor sane).
    f = (48.0 / weight ** 0.2) * (1 + 1.1 * np.exp(-t / 0.014))
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * (1 - np.exp(-t / 0.0006)) * np.exp(-t / (0.065 * weight))
    chest = np.sin(2.31 * ph + 1.1) * (1 - np.exp(-t / 0.0005)) * np.exp(-t / (0.05 * weight))
    belly = np.sin(3.72 * ph + 0.4) * (1 - np.exp(-t / 0.0006)) * np.exp(-t / (0.026 * weight))
    puff = _unit(lowpass(r.standard_normal(n) * (1 - np.exp(-t / 0.002)) * np.exp(-t / (0.05 * weight)), 380, 2))
    low = drive(_unit(0.75 * body + 0.7 * chest + 0.3 * belly + 0.75 * puff), 1.6)
    # The iron-shod sole on stone: a hard short contact...
    click = _burst(seed + 1, 0.01, 0.0007, lo=120, hi=5000)
    # ...ringing a few dense, very short stone-floor modes.
    stone_modes = [(fq * (1 + r.uniform(-0.04, 0.04)), d, a) for fq, d, a in (
        (148, 0.05, 1.0), (231, 0.04, 0.8), (347, 0.032, 0.7), (512, 0.024, 0.55),
        (745, 0.018, 0.4), (1090, 0.012, 0.3), (1610, 0.009, 0.22), (2380, 0.006, 0.15))]
    stone = _unit(modal(0.3, stone_modes, seed + 2, strike=click))
    # Stone grit: a short 2-6 kHz scuff and a few chips kicked up.
    grit = _burst(seed + 3, 0.09, 0.011, lo=1900, hi=6000)
    chip_t = [0.003 + 0.1 * r.random() ** 2 for _ in range(7)]
    chips = _grains(0.12, chip_t, seed + 4, (0.002, 0.006), (2200, 6500))
    return fade(mix(low, 0.55 * stone, 0.25 * click, 0.1 * grit, 0.06 * chips), 0, 0.2 * dur)


def _plate(seed, base=_PLATE_BASE, decay=0.3, bright=0.5, dur=0.9, hard=0.0012):
    """A thick iron armour plate struck: inharmonic modes, each with a split
    twin that beats; high modes die first and get quieter when `bright` is
    low (a dull clang)."""
    r = rng(seed)
    modes = []
    for i, q in enumerate(_PLATE_RATIOS):
        fq = base * q * (1 + r.uniform(-0.012, 0.012))
        d = decay / (1 + 0.5 * i)
        a = (0.5 + 0.45 * bright) ** (0.8 * i)
        modes.append((fq, d, a))
        modes.append((fq * (1.0035 + 0.002 * r.random()), 0.85 * d, 0.45 * a))
    strike = _burst(seed + 1, 0.012, hard, hi=1500 + 9000 * bright)
    return fade(_unit(modal(dur, modes, seed + 2, strike=strike)), 0, 0.2 * dur)


def _cleaver(seed, decay=0.6, bright=0.6, dur=1.0, hard=0.0006, base=_CLEAVER_BASE):
    """The heavy cleaver struck: a thick iron bar; bending modes stronger
    than the torsional ones; darker as it rings."""
    r = rng(seed)
    modes = []
    for i, q in enumerate(_CLEAVER_RATIOS):
        fq = base * q * (1 + r.uniform(-0.008, 0.008))
        d = decay / (1 + 0.6 * i)
        a = (0.5 + 0.45 * bright) ** i * (1.0 if i % 2 == 0 else 0.6)
        modes.append((fq, d, a))
        modes.append((fq * 1.0022, 0.9 * d, 0.3 * a))
    strike = _burst(seed + 1, 0.01, hard, hi=3000 + 12000 * bright)
    return fade(_unit(modal(dur, modes, seed + 2, strike=strike)), 0, 0.2 * dur)


def _growl(duration, seed, f0, amp, formants_a=_DARK, formants_b=None, breath=0.35, rasp=0.55, mask=0.3, chest=0.6,
           rough=0.0):
    """A creature growl behind the skull mask (no voice, no words). f0 and
    amp may be per-sample arrays; formants glide from a to b; `chest` lets
    the huge chest's low resonance (~105 Hz) through; `rough` adds a fast
    irregular pitch jitter (less periodic: a beast's throat, not a voice)."""
    n = n_samples(duration)
    f0 = np.broadcast_to(np.asarray(f0, float), (n,))
    amp = np.broadcast_to(np.asarray(amp, float), (n,))
    f = f0 * (1 + 0.045 * _lfnoise(n, 14, seed))
    if rough:
        f = f * (1 + rough * _lfnoise(n, 70, seed + 3))
    ph = np.cumsum(f) / SR
    frac = ph - np.floor(ph)
    pulse = np.exp(-6.0 * frac)
    pulse = pulse - np.mean(pulse)
    # Period doubling (every other cycle weaker) and an irregular flutter.
    sub = 0.55 + 0.45 * np.sin(np.pi * ph)
    flutter = np.abs(_lfnoise(n, 35, seed + 1))
    voiced = pulse * ((1 - rasp) + rasp * sub * (0.4 + 0.6 * flutter))
    noise = pink(duration, seed + 2) * (0.5 + 0.5 * flutter)
    exc = _unit(voiced) + breath * _unit(noise)
    fa = formants_a
    fb = formants_b or formants_a

    def gain(fr, tt):
        u = min(max(tt / duration, 0.0), 1.0)
        g = np.zeros_like(fr)
        for (ca, qa, ga), (cb, _qb, gb) in zip(fa, fb):
            g += (ga + (gb - ga) * u) * _band(fr, ca * (cb / ca) ** u, 1.0 / qa)
        return g + mask * _band(fr, _MASK[0], 1.0 / _MASK[1]) + chest * _band(fr, 105.0, 1.4)
    return fade(_unit(stft_filter(exc, gain)) * amp, 0, min(0.1, 0.2 * duration))


def _whoosh(duration, seed, level, center, width=1.1, air=0.0):
    """Band-passed pink noise whose band follows `center` (per sample);
    `air` adds a fainter band ~1.7 octaves above (the edge)."""
    n = n_samples(duration)
    t = _t(n)
    center = np.broadcast_to(np.asarray(center, float), (n,))

    def gain(f, tt):
        c = float(np.interp(tt, t, center))
        return _band(f, c, width) + air * _band(f, 3.2 * c, 1.3 * width)
    return stft_filter(pink(duration, seed), gain) * level


def _creak(duration, seed, t0, t1, rate0, rate1, centers=(420, 950, 1900), q=3.5, tremble=0.0, jitter=0.3):
    """Leather under strain: stick-slip friction pulses (rate rising from
    rate0 to rate1 Hz) through the straps' resonances."""
    n = n_samples(duration)
    t = _t(n)
    r = rng(seed)
    u = np.clip((t - t0) / (t1 - t0), 0, 1)
    rate = rate0 * (rate1 / rate0) ** u * (1 + jitter * _lfnoise(n, 18, seed + 1))
    ph = np.cumsum(rate) / SR
    idx = np.nonzero(np.diff(np.floor(ph)))[0] + 1
    idx = idx[(t[idx] >= t0) & (t[idx] < t1)]
    imp = np.zeros(n)
    imp[idx] = r.uniform(0.4, 1.0, len(idx))
    k = n_samples(0.003)
    kern = r.uniform(-1, 1, k) * np.exp(-np.arange(k) / (0.0005 * SR))
    x = convolve(imp, kern)[:n]
    x = formant(x, [(c, q, 1.0 / (1 + 0.5 * i)) for i, c in enumerate(centers)])
    env = np.where((u > 0) & (u < 1), np.sin(np.pi * u) ** 0.6, 0.0)
    if tremble:
        env = env * (1 + tremble * np.sin(2 * np.pi * 8.5 * t))
    return _unit(x * env)


def _iron_scrape(duration, seed, t0, t1, base=120.0, tremble=0.0):
    """Iron edge grinding on iron: chattering noise and grit ringing the
    cleaver's own (narrow) modes, over a broad rasp band."""
    n = n_samples(duration)
    t = _t(n)
    r = rng(seed)
    rough = 0.3 + 0.7 * np.abs(_lfnoise(n, 55, seed + 1))
    src = r.standard_normal(n) * rough + 1.5 * crackle(duration, 1400, seed + 2, decay=0.0003)
    ring = formant(src, [(base * q, 14.0, 0.9 / (1 + 0.5 * i)) for i, q in enumerate(_CLEAVER_RATIOS[:7])])

    def moving(f, tt):
        # The contact point slides along the blade: the rasp band climbs.
        uu = min(max((tt - t0) / (t1 - t0), 0.0), 1.0)
        c = 600.0 * (1300.0 / 600.0) ** uu
        return _band(f, c, 1.1) + 0.3 * _band(f, 2.6 * c, 1.0)
    rasp = stft_filter(src, moving)
    u = np.clip((t - t0) / (t1 - t0), 0, 1)
    env = np.where((u > 0) & (u < 1), np.sin(np.pi * u) ** 0.8, 0.0)
    if tremble:
        env = env * (1 + tremble * np.sin(2 * np.pi * 8.5 * t + 0.4))
    return _unit((_unit(ring) + 0.45 * _unit(rasp)) * env)


def _drag(duration, seed, speed, lo=380.0, hi=1700.0, grind=0.45, paper=0.12):
    """The card's iron base dragged heavily over stone; `speed` (0..1 per
    sample) drives the level, the band and the grit density."""
    n = n_samples(duration)
    t = _t(n)
    r = rng(seed)
    speed = np.clip(np.asarray(speed, float), 0, 1)
    rough = 0.3 + 0.7 * np.abs(_lfnoise(n, 38, seed + 1))
    src = r.uniform(-1, 1, n) * rough + 1.3 * crackle(duration, 300 + 2400 * speed, seed + 2, decay=0.00035)

    def gain(f, tt):
        s = float(np.interp(tt, t, speed))
        return _band(f, lo * (hi / lo) ** s, 1.6) + grind * s * _band(f, 300.0, 0.9)
    y = _unit(stft_filter(src, gain) * speed ** 0.85)
    times = random_times(duration, 260, seed + 3, envelope=lambda u: float(np.interp(u * duration, t, speed)))
    edge = _grains(duration, times, seed + 4, (0.004, 0.014), (2000, 5500))
    return y + paper * edge


def _speed(t, surges, end, rise=0.025, tau=0.13):
    """A card's speed: surges [(time, gain)] that decay, brought to rest at `end`."""
    s = np.zeros_like(t)
    for t0, g in surges:
        dt = t - t0
        s += g * np.where(dt > 0, (1 - np.exp(-np.maximum(dt, 0) / rise)) * np.exp(-np.maximum(dt, 0) / tau), 0.0)
    s *= np.clip((end - t) / 0.03, 0, 1)
    return np.clip(s / (np.max(s) + 1e-12), 0, 1)


def _debris(duration, seed, t0, span=0.6, count=40, pebbles=6):
    """Stone chips falling after an impact: dense first, sparse later, plus
    a few heavier pebbles knocking."""
    r = rng(seed)
    times = np.sort(t0 + span * r.random(count) ** 2.2)
    gains = (1 - (times - t0) / span) ** 1.3 * r.uniform(0.3, 1.0, count)
    chips = _grains(duration, list(times), seed + 1, (0.002, 0.009), (1400, 7500), list(gains))
    pt = np.sort(t0 + 0.04 + (span - 0.04) * r.random(pebbles) ** 1.5)
    ev = [(float(x), float((1 - (x - t0) / span) * r.uniform(0.5, 1.0))) for x in pt]
    return chips + 0.8 * _scatter(duration, ev, _pebble_bank(seed + 2), seed + 3)


def _crumple(duration, seed, t0, length=0.05, count=14, gain=1.0):
    """A little paper crumple (the card takes the blow)."""
    r = rng(seed)
    times = list(t0 + length * r.random(count) ** 1.5)
    gains = list(gain * r.uniform(0.3, 1.0, count))
    return _grains(duration, times, seed + 1, (0.004, 0.02), (1500, 8000), gains)


def _finish(x, peak=0.8, fade_in=0.002, fade_out=0.03):
    return fade(_unit(x) * peak, fade_in, fade_out)


# --------------------------------------------------------------------------
# The sounds

@sound("brute_move", loudness=-18, wet=0.22, marks=(0.2, 0.42, 0.64))
def brute_move(seed):
    """Two crushing armoured stomps (0.2, 0.42), plates jangle, the chain
    swings, the card drags heavily 0.2-0.64 and grinds to rest."""
    D = 1.0
    t = _t(n_samples(D))
    # Weight shifts onto one leg while the other lifts: the leg straps creak
    # (stick-slip through the leather's own, high and narrow, resonances).
    creak = _creak(D, seed + 1, 0.03, 0.195, 34, 72, centers=(700, 1600, 3200), q=6.0, jitter=0.5)
    creak2 = _creak(D, seed + 2, 0.27, 0.415, 38, 80, centers=(780, 1750, 3400), q=6.0, jitter=0.5)
    stomps = place(D, [(0.2, _stomp(seed + 3, 1.0), 1.0), (0.42, _stomp(seed + 4, 1.1), 1.05)])
    # Strapped, body-worn plates: damped (T60 ~0.55 s), they knock rather
    # than ring, so nothing hums on after the card has stopped.
    plates = place(D, [(0.206, _plate(seed + 5, decay=0.08, bright=0.4, dur=0.6), 1.0),
                       (0.427, _plate(seed + 6, base=_PLATE_BASE * 1.06, decay=0.085, bright=0.45, dur=0.6), 1.05)])
    rattle = _scatter(D, _cluster(seed + 7, 0.203, 0.16, 120) + _cluster(seed + 8, 0.423, 0.18, 130),
                      _rattle_bank(seed + 9), seed + 10)
    # The chain swings with each lifted leg: links clink at every turn of
    # the pendulum (the first swing before the first stomp, a lighter one
    # before the second), then they are shaken by the stomps.
    r = rng(seed + 11)
    swing = []
    for k in range(4):
        tk = 0.072 + 0.031 * k + 0.006 * r.random()
        gk = 0.6 * math.sin(math.pi * (k + 0.5) / 4)
        swing += [(tk, gk), (tk + 0.004 + 0.004 * r.random(), 0.6 * gk)]
    for k in range(3):
        tk = 0.302 + 0.033 * k + 0.006 * r.random()
        gk = 0.4 * math.sin(math.pi * (k + 0.5) / 3)
        swing += [(tk, gk), (tk + 0.004 + 0.004 * r.random(), 0.6 * gk)]
    chain = _scatter(D, swing + _cluster(seed + 12, 0.218, 0.2, 170) + _cluster(seed + 13, 0.44, 0.34, 180),
                     _link_bank(seed + 14), seed + 15)
    drag = _drag(D, seed + 16, _speed(t, [(0.2, 1.0), (0.42, 1.0)], 0.64))
    # The card grinds to rest on 0.64: a soft-fronted low grind.
    stop = _burst(seed + 17, 0.1, 0.014, lo=200, hi=1400) * _onset(n_samples(0.1), 0.003)
    x = mix(stomps, 0.28 * plates, 0.2 * rattle, 0.14 * chain, 0.46 * drag, 0.25 * creak, 0.22 * creak2,
            place(D, [(0.632, stop, 0.3)]))
    return _finish(x)


@sound("brute_charge", loudness=-17, wet=0.25, marks=(0.1, 0.3, 0.5, 0.7))
def brute_charge(seed):
    """Heavy running: four stomps that grow (and whose toe scuffs come ever
    closer to the footfall: the stride quickens), armour clatter, chains,
    a rushing low whoosh that builds."""
    D = 1.0
    n = n_samples(D)
    t = _t(n)
    marks = (0.1, 0.3, 0.5, 0.7)
    weights = (0.9, 0.95, 1.0, 1.05)
    gains = (0.72, 0.82, 0.92, 1.0)
    leads = (0.06, 0.045, 0.032, 0.022)
    ev = []
    scuff_env = _onset(n_samples(0.05), 0.004)
    for i, m in enumerate(marks):
        ev.append((m, _stomp(seed + 10 * i, weights[i], dur=0.45), gains[i]))
        # The same (damped, strapped) plates knocked by every stride.
        ev.append((m + 0.004, 0.26 * _plate(seed + 10 * i + 1, decay=0.09, bright=0.5, dur=0.45), gains[i]))
        # The toe scuffs the stone just before the heel lands (soft front).
        ev.append((m - leads[i], _burst(seed + 10 * i + 2, 0.05, 0.01, lo=900, hi=5000) * scuff_env, 0.26))
    body = place(D, ev)
    rat_ev = []
    for i, m in enumerate(marks):
        rat_ev += _cluster(seed + 50 + i, m + 0.003, 0.12, 150, gain=gains[i])
        rat_ev += _cluster(seed + 60 + i, m + 0.1, 0.06, 90, gain=0.5 * gains[i])
    rattle = _scatter(D, rat_ev, _rattle_bank(seed + 70), seed + 71)
    chain_ev = _cluster(seed + 72, 0.06, 0.82, 260, env=lambda u: (0.35 + 0.65 * u) * min(1.0, (1 - u) * 6))
    chain = _scatter(D, chain_ev, _link_bank(seed + 73), seed + 74)
    level = np.clip((t - 0.02) / 0.76, 0, 1) ** 1.6 * np.clip((1.0 - t) / 0.24, 0, 1)
    pump = np.zeros(n)
    for m in marks:
        pump += np.where(t > m, np.exp(-np.maximum(t - m, 0) / 0.07), 0.0)
    level = level * (0.8 + 0.25 * pump)
    whoosh = _whoosh(D, seed + 75, level, 130 * (380 / 130) ** np.clip(t / 0.8, 0, 1), width=1.3, air=0.3)
    scrape = _drag(D, seed + 76, np.clip((t - 0.1) / 0.1, 0, 1) * np.clip((0.75 - t) / 0.05, 0, 1), lo=600, hi=1900)
    x = mix(body, 0.2 * rattle, 0.12 * chain, 0.5 * _unit(whoosh), 0.08 * scrape)
    return _finish(x)


@sound("brute_windup", loudness=-20, wet=0.22)
def brute_windup(seed):
    """Raises the cleaver: straps creak under the strain, the chain drags,
    the blade grinds low along a plate, a masked growl swells (menace);
    it ends trembling with the effort."""
    D = 0.8
    n = n_samples(D)
    t = _t(n)
    # 0-0.36 the lift: the arm strap creaks (slow slips that quicken, through
    # the leather's high, narrow resonances: friction, not a throat) and the
    # chain is lifted off the floor link by link from the start.
    creak = _creak(D, seed + 1, 0.02, 0.36, 28, 85, centers=(700, 1600, 3200), q=6.0, jitter=0.5)
    lift = _cluster_thin(seed + 3, 0.03, 0.34, 120, env=lambda u: 0.15 + 0.85 * math.sin(math.pi * u) ** 0.8,
                         burst=(1, 2), spacing=0.006)
    # 0.4-0.8 held high: the animation sways on a 480 ms loop (arm highest at
    # 0.24 + 0.48k). A second strap strains on each turn of the sway (0.48,
    # 0.72) with a fine muscle shiver over it, and the chain shivers there.
    sway = 0.3 + np.exp(-0.5 * ((t - 0.48) / 0.045) ** 2) + np.exp(-0.5 * ((t - 0.72) / 0.045) ** 2)
    creak2 = _unit(_creak(D, seed + 2, 0.4, 0.8, 55, 70, centers=(780, 1750, 3400), q=6.0, tremble=0.25,
                          jitter=0.5) * sway)
    shiver = []
    for k, s0 in enumerate((0.455, 0.695)):
        shiver += _cluster(seed + 10 + k, s0 + 0.01 * rng(seed + 9 + k).random(), 0.08, 110, gain=0.5, burst=(1, 2))
    chain = _scatter(D, lift + shiver, _link_bank(seed + 4), seed + 5)
    chain_drag = _drag(D, seed + 6, 0.6 * np.sin(np.pi * np.clip((t - 0.05) / 0.3, 0, 1)), lo=900, hi=2200,
                       grind=0.0, paper=0.0)
    # 0.14-0.76 the cleaver's back grinds up along the shoulder plate: its own
    # narrow modes ring under a chattering rasp, shivering with the strain.
    scrape = _iron_scrape(D, seed + 7, 0.14, 0.76, base=118.0, tremble=0.35)
    # Menace: a slow intake that turns into a growl behind the mask (a huge
    # throat: formants lower than a man's, rough and breathy), and the
    # weight settling (a faint sub swell).
    amp = np.clip((t - 0.03) / 0.55, 0, 1) ** 1.2 * np.clip((D - t) / 0.12, 0, 1)
    growl = _growl(D, seed + 8, 42 * (50 / 42) ** (t / D), amp,
                   ((240.0, 3.0, 1.0), (520.0, 3.5, 0.7), (1500.0, 4.5, 0.2)),
                   ((265.0, 3.0, 1.0), (570.0, 3.5, 0.75), (1600.0, 4.5, 0.2)),
                   breath=0.9, rasp=0.75, chest=0.9, rough=0.08)
    sub = _unit(lowpass(brown(D, seed + 11), 110, 2)) * np.clip((t - 0.1) / 0.5, 0, 1) * np.clip((D - t) / 0.15, 0, 1)
    x = mix(0.32 * creak, 0.26 * creak2, 0.17 * chain, 0.3 * chain_drag, 0.4 * scrape, 0.75 * growl, 0.3 * sub)
    return _finish(x, fade_in=0.01, fade_out=0.06)


@sound("brute_attack", loudness=-15, wet=0.3, marks=(0.08, 0.143, 0.26))
def brute_attack(seed):
    """Cleaves: a huge low whoosh from 0.08, the cleaver chops into stone at
    0.143 (crack, a massive low body, stone crunch, the blade's ring, the
    armour jolts, debris), the chains settle from 0.26."""
    D = 1.0
    n = n_samples(D)
    t = _t(n)
    T = 0.143
    r = rng(seed)
    # A faint pull-back as the cleaver is hauled higher (0-0.08), then the
    # down-stroke from 0.08: loudest at the blade's top speed just before
    # contact, cut by the blow.
    u = np.clip((t - 0.075) / (T - 0.008 - 0.075), 0, 1)
    pull = 0.2 * np.sin(np.pi * np.clip(t / 0.09, 0, 1)) ** 2
    level = (pull + u ** 2.2) * np.clip((T + 0.003 - t) / 0.011, 0, 1)
    whoosh = _whoosh(D, seed + 1, level, 105 * (560 / 105) ** u, width=1.2, air=0.25)
    crack = _burst(seed + 2, 0.02, 0.0008, lo=200)
    thump = _stomp(seed + 3, weight=1.5, dur=0.85)
    crunch_t = list(T + 0.045 * r.random(40) ** 1.6)
    crunch = _grains(D, crunch_t, seed + 4, (0.0015, 0.007), (700, 6500))
    breaking = _burst(seed + 5, 0.2, 0.022, lo=350, hi=4200)
    # The blade bites into the stone: the stone damps it (T60 ~1.2 s, its
    # high partials die in a few hundred ms) and the buried contact strikes
    # it softer than metal on metal. The long ring is the death's.
    blade = _cleaver(seed + 6, decay=0.18, bright=0.75, dur=0.85, hard=0.0012)
    jolt = _plate(seed + 7, decay=0.09, bright=0.5, dur=0.6)
    debris = _debris(D, seed + 8, T + 0.025, span=0.7, count=55)
    # The card crumples a little under the blow (just after the crack, so
    # the crack does not mask it).
    paper = _crumple(D, seed + 9, T + 0.014, 0.09, 14)
    links = _link_bank(seed + 10)
    chain = _scatter(D, _cluster(seed + 11, T + 0.01, 0.1, 120, gain=0.6) + _cluster(seed + 12, 0.26, 0.45, 200),
                     links, seed + 13)
    rattle = _scatter(D, _cluster(seed + 14, 0.262, 0.2, 100, gain=0.7), _rattle_bank(seed + 15), seed + 16)
    hn = n_samples(0.32)
    ht = _t(hn)
    huff = _growl(0.32, seed + 17, 58 * (46 / 58) ** (ht / 0.32),
                  np.clip(ht / 0.03, 0, 1) * np.exp(-ht / 0.09), breath=0.7, rasp=0.5)
    # The blow itself is saturated as one mass (crack + body + breaking stone):
    # heavier, and a sane crest factor; the blade's ring stays clean on top.
    # The slab shudders and the rubble shifts under the blade (80-400 Hz).
    rn = n_samples(0.6)
    rt = _t(rn)
    rubble = brown(0.6, seed + 18) * (0.5 + 0.5 * np.abs(_lfnoise(rn, 30, seed + 19)))
    rubble = fade(_unit(bandpass(rubble, 170.0, 0.65) * (1 - np.exp(-rt / 0.004)) * np.exp(-rt / 0.13)), 0, 0.1)
    blow = drive(_unit(mix(place(D, [(T, crack, 0.4), (T, thump, 0.85), (T, breaking, 0.45), (T + 0.003, rubble, 0.6)]),
                           0.5 * crunch)), 2.8)
    x = mix(0.42 * _unit(whoosh), blow, place(D, [(T + 0.002, blade, -0.4), (T + 0.01, jolt, 0.16), (0.1, huff, 0.18)]),
            0.14 * debris, 0.3 * paper, 0.26 * chain, 0.17 * rattle)
    return _finish(x)


@sound("brute_hurt", loudness=-17, wet=0.2, marks=(0.118,))
def brute_hurt(seed):
    """A blow on his iron plate at 0.118: a dull heavy clang over a body
    thump, the armour rattles, the chain shakes, a deep grunt-like growl."""
    D = 0.7
    T = 0.118
    # A dull clang: the struck plate is strapped to his body, which damps it
    # (T60 ~0.75 s): it dies out before the grunt does, no hum under it.
    blow = _plate(seed + 1, base=_PLATE_BASE * 0.92, decay=0.11, bright=0.25, dur=0.5, hard=0.0025)
    strike = _burst(seed + 2, 0.02, 0.0015, hi=3500)
    tn = n_samples(0.4)
    tt = _t(tn)
    f = 72 * (1 + 0.6 * np.exp(-tt / 0.012))
    thump = np.sin(2 * np.pi * np.cumsum(f) / SR) * (1 - np.exp(-tt / 0.001)) * np.exp(-tt / 0.045)
    puff = _unit(lowpass(rng(seed + 3).standard_normal(tn) * np.exp(-tt / 0.03), 260, 2))
    rattle = _scatter(D, _cluster(seed + 4, T + 0.006, 0.3, 140), _rattle_bank(seed + 5), seed + 6)
    chain = _scatter(D, _cluster(seed + 7, T + 0.02, 0.4, 150), _link_bank(seed + 8), seed + 9)
    gn = n_samples(0.5)
    gt = _t(gn)
    amp = np.clip(gt / 0.025, 0, 1) * np.exp(-np.maximum(gt - 0.06, 0) / 0.12)
    grunt = _growl(0.5, seed + 10, 62 * (44 / 62) ** (gt / 0.5), amp,
                   ((360.0, 3.5, 1.0), (780.0, 4.0, 0.7), (2300.0, 5.0, 0.25)), _DARK, breath=0.35, rasp=0.65)
    paper = _crumple(D, seed + 11, T + 0.005, 0.07, 12)
    x = mix(place(D, [(T, blow, 0.55), (T, strike, 0.35), (T, thump, 0.7), (T, puff, 0.45), (T + 0.03, grunt, 0.75)]),
            0.18 * rattle, 0.1 * chain, 0.15 * paper)
    return _finish(x)


@sound("brute_death", loudness=-16, wet=0.35, marks=(0.118, 0.3, 0.62))
def brute_death(seed):
    """Struck at 0.118 (dull plate clang, a falling groan); drops to his
    knees at 0.3 (armour crashes, the card folds); falls on his face at 0.62
    (a huge body slam, the cleaver hits stone and rings, bounces at 0.71,
    the card slaps down); the chains slither and a last breath fades."""
    D = 1.2
    n = n_samples(D)
    t = _t(n)
    T1, T2, T3 = 0.118, 0.3, 0.62
    rb = _rattle_bank(seed + 1)
    lb = _link_bank(seed + 2)
    # The blow (the same dull, body-damped clang as brute_hurt). Every plate
    # here is strapped and damped: the cleaver at 0.62 is the one long ring.
    hit = place(D, [(T1, _plate(seed + 3, base=_PLATE_BASE * 0.92, decay=0.12, bright=0.35, dur=0.5, hard=0.002), 0.5),
                    (T1, _burst(seed + 4, 0.02, 0.0015, hi=3500), 0.3),
                    (T1, _stomp(seed + 5, 0.8, dur=0.3), 0.45)])
    gn = n_samples(0.5)
    gt = _t(gn)
    groan = _growl(0.5, seed + 6, 56 * (36 / 56) ** (gt / 0.5),
                   np.clip(gt / 0.03, 0, 1) * np.exp(-np.maximum(gt - 0.08, 0) / 0.14),
                   ((350.0, 3.5, 1.0), (740.0, 4.0, 0.7), (2200.0, 5.0, 0.25)),
                   ((260.0, 3.5, 1.0), (540.0, 4.0, 0.6), (1700.0, 5.0, 0.18)), breath=0.4, rasp=0.7)
    # Down on his knees: two heavy knocks, the armour crashes, the card folds.
    knees = place(D, [(T2, _stomp(seed + 7, 1.2, dur=0.5), 0.85), (T2 + 0.022, _stomp(seed + 8, 1.1, dur=0.5), 0.6),
                      (T2 + 0.002, _plate(seed + 9, decay=0.12, bright=0.55, dur=0.5), 0.3),
                      (T2 + 0.018, _plate(seed + 10, base=_PLATE_BASE * 1.12, decay=0.11, bright=0.5, dur=0.5), 0.24),
                      (T2 + 0.041, _plate(seed + 11, base=_PLATE_BASE * 0.88, decay=0.1, bright=0.45, dur=0.5), 0.18)])
    crash = _scatter(D, _cluster(seed + 12, T2, 0.26, 260), rb, seed + 13)
    # The card creases as he buckles: a crumple that outlasts the knocks.
    fold = _crumple(D, seed + 14, T2 + 0.018, 0.14, 22, 0.6)
    # Then it topples: the falling card pushes air (a short rising flap and a
    # flutter of paper) just before it slaps flat on the stone at 0.62.
    tu = np.clip((t - 0.5) / (T3 - 0.5), 0, 1)
    topple = _whoosh(D, seed + 29, np.where(t < T3, tu ** 2.5, 0.0), 700 * (1900 / 700) ** tu, width=1.3, air=0.35)
    flutter = _grains(D, list(0.53 + 0.085 * rng(seed + 30).random(9) ** 0.6), seed + 31, (0.004, 0.012), (1600, 6000))
    # Face down: the body slams, the cleaver hits stone and rings, bounces.
    slam = place(D, [(T3, _stomp(seed + 15, 1.6, dur=0.58), 1.0),
                     (T3 + 0.003, _plate(seed + 16, decay=0.12, bright=0.55, dur=0.5), 0.3),
                     (T3 + 0.024, _plate(seed + 17, base=_PLATE_BASE * 1.09, decay=0.1, bright=0.5, dur=0.5), 0.2),
                     (T3, _cleaver(seed + 18, decay=0.32, bright=0.85, dur=0.58), 0.5),
                     (0.712, _cleaver(seed + 19, decay=0.25, bright=0.6, dur=0.48), 0.22),
                     (T3 + 0.004, _burst(seed + 20, 0.12, 0.006, lo=250, hi=5000), 0.18)])
    crash2 = _scatter(D, _cluster(seed + 21, T3, 0.3, 240, gain=0.9), rb, seed + 22)
    slither_ev = _cluster(seed + 23, T3 + 0.02, 0.56, 160, env=lambda u: (1 - u) ** 1.2, burst=(1, 2), spacing=0.007)
    slither = _scatter(D, _cluster(seed + 24, T2 + 0.01, 0.25, 150) + slither_ev, lb, seed + 25)
    sl_speed = np.clip((t - T3) / 0.03, 0, 1) * np.clip(1 - (t - T3) / 0.55, 0, 1) ** 1.5
    slide = _drag(D, seed + 26, sl_speed, lo=1800, hi=3800, grind=0.0, paper=0.0)
    debris = _debris(D, seed + 27, T3 + 0.01, span=0.45, count=25, pebbles=3)
    bn = n_samples(0.32)
    bt = _t(bn)
    breath = _growl(0.32, seed + 28, 40.0, np.sin(np.pi * bt / 0.32) ** 1.5, breath=1.4, rasp=0.8)
    x = mix(hit, place(D, [(T1 + 0.012, groan, 0.55), (0.84, breath, 0.1)]), knees, 0.2 * crash, 0.3 * fold,
            0.12 * _unit(topple), 0.12 * flutter, slam, 0.16 * crash2, 0.2 * slither, 0.1 * slide, 0.08 * debris)
    return _finish(x, fade_out=0.09)
