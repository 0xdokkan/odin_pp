"""The Viandante (player): every sound of the pilgrim, made from code.

His identity, shared by every recipe below:
  - an ivory WOOL cloak: soft pink noise through a moving mid band (400 Hz -
    2 kHz) with uneven folds and a few fine fibre crackles; never bright;
  - LEATHER boots on stone: a sub-3 ms heel tick, a pitch-falling muffled body
    (100-130 Hz), a few dense stone modes and a short 2-6 kHz grit;
  - an IRON lantern: one fixed set of inharmonic frame modes (1.18 kHz and
    up) plus tiny chain-link clicks; its GLASS globe rings D6 + A6 (D
    Phrygian), the character's little signature chime;
  - a BLUE flame: a soft low whoomp and a clean gas hiss, no crackle;
  - his PAPER card on its iron base: a damped cardboard thump and a gritty
    stick-slip scrape (sparse stone ticks, catches) whose level and band
    follow the card's real travel curve (the runtime's back-out
    "shove"/"dash" easing), fading as the card comes to rest;
  - his BODY taking or giving a blow: an unpitched, band-limited noise mass
    (60-250 Hz) over a short sub, never a ringing tone;
  - his SHADOW (Movimento Ombra) is ink: dark, soft noise (brown and pink, no
    grit, no hiss) through a band that sinks, slips and swells up, thickened
    by a slow uneven swirl, as a viscous liquid moves.
Every action combines these differently, so they read as one person while each
move stays distinct. Recipes are dry; the build adds the stone hall.
"""
import math

import numpy as np

from dsp import *  # noqa: F401,F403
from dsp import (SR, bandpass, brown, convolve, crackle, env_points, env_swell, fade, formant, grains, highpass, lowpass,
                 n_samples, pad_to, phase_of, pink, place, random_times, rng, stft_filter, sweep_lowpass, time_axis,
                 triangle, white)
from registry import sound

# --------------------------------------------------------------------------
# Pitches (D Phrygian) and the character's fixed materials

_D4 = 293.66
_DEG = {"D": 0, "Eb": 1, "F": 3, "G": 5, "A": 7, "Bb": 8, "C": 10}


def _hz(name, octave=4):
    """A D-Phrygian pitch; `octave` counts from that octave's D (C of octave 4
    is the C a seventh above D4)."""
    return _D4 * 2 ** (_DEG[name] / 12.0 + (octave - 4))


_GLASS_NOTES = ((_hz("D", 6), 1.0), (_hz("A", 6), 0.55))     # the lantern globe
_GLASS_RATIOS = (1.0, 2.32, 4.25, 6.63)                       # a small glass shell
_FRAME = (1180.0, 1710.0, 2440.0, 3170.0, 3930.0, 4810.0)     # the iron lantern frame
_COIN_RATIOS = (1.0, 1.47, 2.03, 2.61, 3.27)                  # thin metal discs


# --------------------------------------------------------------------------
# Small building blocks

def _norm(x, p=1.0):
    m = float(np.max(np.abs(x))) if len(x) else 0.0
    return x * (p / m) if m > 1e-12 else x


def _env_ad(dur, attack, tau, hold=0.0):
    """Linear attack, optional hold, exponential decay (time constant tau)."""
    t = time_axis(dur)
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    return a * np.exp(-np.maximum(t - attack - hold, 0) / max(tau, 1e-5))


def _band(x, lo=None, hi=None, order=2):
    if lo:
        x = highpass(x, lo, order)
    if hi:
        x = lowpass(x, hi, order)
    return x


def _modes(dur, modes, attack=0.0004, seed=None):
    """Causal struck resonator: damped sines starting near zero phase, so the
    strike is the onset itself (no pre-ringing, unlike a narrow FFT band)."""
    t = time_axis(dur)
    out = np.zeros_like(t)
    r = rng(seed) if seed is not None else None
    for f, tau, amp in modes:
        if f >= 0.45 * SR:
            continue
        ph = 0.0 if r is None else r.uniform(-0.4, 0.4)
        out += amp * np.sin(2 * np.pi * f * t + ph) * np.exp(-t / max(tau, 1e-4))
    a = n_samples(attack)
    if a > 1:
        out[:a] *= np.linspace(0, 1, a)
    return out


def _track(x, centers, q=1.0):
    """Band-pass whose centre follows `centers` (Hz per sample)."""
    centers = np.asarray(centers, float)
    sig = (1.0 / max(q, 0.05)) / 2.355

    def gain(f, t):
        i = int(min(max(t * SR, 0), len(centers) - 1))
        return np.exp(-0.5 * (np.log2(np.maximum(f, 1.0) / centers[i]) / sig) ** 2)
    return stft_filter(x, gain, frame=1024, hop=256)


def _thump(dur, seed, hz, tau, drop=0.8, attack=0.0015, lp=300, sat=0.0):
    """Muffled low body blow: a pitch-falling sine plus low noise. `sat`
    rounds its peak (tanh), as flesh and wool do: less crest, more weight."""
    t = time_axis(dur)
    f = hz * (1 + drop * np.exp(-t / 0.009))
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * _env_ad(dur, attack, tau)
    nz = _band(pink(dur, seed), 40, lp) * _env_ad(dur, attack, tau * 0.8)
    x = _norm(s) + 0.6 * _norm(nz)
    return np.tanh(sat * _norm(x)) / math.tanh(sat) if sat > 0 else x


def _blow(dur, seed, hz, tau, lp=300, sat=2.4, attack=0.002):
    """An unpitched body blow (a lantern or a fist into wool and flesh): a
    brown/pink noise mass band-limited to 70 Hz-`lp` carries it (so its
    energy sits in 60-250 Hz, not in the sub), a short falling sub under it
    adds weight without ringing as a tone; tanh rounds the peak the way flesh
    and wool do. Dies to -40 dB in ~140-200 ms."""
    t = time_axis(dur)
    src = brown(dur, seed) + 1.2 * pink(dur, seed + 1)
    body = lowpass(highpass(src, 70, 3), lp, 3) * _env_ad(dur, attack, tau)
    sub = np.sin(2 * np.pi * np.cumsum(hz * (1 + 0.8 * np.exp(-t / 0.006))) / SR) * _env_ad(dur, 0.001, 0.4 * tau)
    x = _norm(body) + 0.3 * _norm(sub)
    return _dc_block(np.tanh(sat * _norm(x)) / math.tanh(sat), 40.0)


def _dc_block(x, fc=20.0):
    """Causal one-pole DC blocker (a truncated exponential kernel). The
    build's DC removal is zero-phase, so a burst carrying net DC (tanh, a
    sub's first half-cycle) would smear a low bump ahead of its onset; this
    removes that DC after the onset only."""
    tau = 1.0 / (2 * np.pi * fc)
    k = np.exp(-np.arange(n_samples(6 * tau)) / (tau * SR))
    lp = convolve(x, k / np.sum(k))[:len(x)]
    return x - lp


def _finish(x, dur, peak=0.85, tail=0.015):
    x = pad_to(np.asarray(x, float), dur)
    x = fade(x, 0.002, tail)
    return _norm(x, peak)


# --------------------------------------------------------------------------
# The Viandante's materials

def _boot(seed, body_hz=115.0, weight=1.0, grit=1.0, dur=0.3):
    """Leather boot on stone: heel tick < 3 ms, low body 80-400 Hz decaying in
    ~100 ms, dense stone modes, a short 2-6 kHz grit."""
    r = rng(seed)
    tick = _band(white(dur, seed), 1500, 9000) * _env_ad(dur, 0.0002, 0.0008)
    stone = _modes(dur, [(f, r.uniform(0.004, 0.011), r.uniform(0.4, 1.0)) for f in r.uniform(650, 3200, 8)])
    body = _thump(dur, seed + 1, body_hz, 0.026 * weight, drop=0.7, lp=380)
    leather = _band(white(dur, seed + 2), 500, 1800) * _env_ad(dur, 0.002, 0.012)
    gr = grains(dur, sorted(r.uniform(0.0, 0.035, 6)), 0.006, seed + 3, band=(2000, 6000), gain_jitter=0.6)
    return (0.32 * _norm(tick) + 0.22 * _norm(stone) + 1.0 * _norm(body) + 0.22 * _norm(leather)
            + 0.30 * grit * _norm(gr))


def _scuff(seed, length=0.06, dur=0.14, lo=1300, hi=3200, weight=0.5):
    """A boot pushing off / dragging on stone: friction rising in a band, grit,
    a small heel weight."""
    n = n_samples(dur)
    t = time_axis(dur)
    env = np.clip(t / 0.005, 0, 1) * np.exp(-np.maximum(t - length * 0.4, 0) / (length * 0.35))
    c = lo * (hi / lo) ** np.clip(t / length, 0, 1)
    fr = _track(white(dur, seed), c, 1.1) * env
    gr = _band(crackle(dur, 2500 * env + 1, seed + 1, decay=0.0003), 2000, 8000) * env
    hit = _thump(dur, seed + 2, 120, 0.02, drop=0.5)
    tick = _band(white(dur, seed + 3), 1500, 8000) * _env_ad(dur, 0.0002, 0.0007)
    return _norm(fr) + 0.35 * _norm(gr) + weight * _norm(hit) + 0.25 * _norm(tick)[:n]


def _cloak(dur, seed, env, lo=400, hi=2000, q=0.7, fibres=0.2):
    """Ivory wool: a soft band of pink noise that brightens as the cloth moves
    faster, uneven folds, a few fibre crackles."""
    n = n_samples(dur)
    e = pad_to(np.asarray(env, float), dur)
    en = e / (np.max(e) + 1e-9)
    src = pink(dur, seed) + 0.25 * white(dur, seed + 1)
    folds = 0.6 + 0.4 * _norm(lowpass(white(dur, seed + 2), 22, 2))
    body = _track(src, lo * (hi / lo) ** en, q) * folds
    fib = _band(crackle(dur, 40 + 700 * en, seed + 3, decay=0.0004), 2200, 6500)
    return (_norm(body) + fibres * _norm(fib))[:n] * en


def _flutter(dur, seed, rate0=20.0, rate1=9.0, tau=0.09, lo=450, hi=1500):
    """Cloak flapping after a landing: decaying flaps of wool."""
    t = time_axis(dur)
    ph = phase_of(rate0 * (rate1 / rate0) ** (t / dur), n=len(t))
    flaps = (0.5 - 0.5 * np.cos(2 * np.pi * ph)) ** 2
    env = _env_ad(dur, 0.004, tau) * (0.3 + 0.7 * flaps)
    return _cloak(dur, seed, env, lo, hi, q=0.8, fibres=0.25)


def _whoosh(dur, seed, f0, f1, f2, peak_at=0.45, q=1.1, power=2.0, tone=0.2):
    """Band-passed air: band and level swell then fall; a narrower band on
    top gives the faint pitch movement of an object through the air."""
    u = np.linspace(0, 1, n_samples(dur))
    env = env_swell(dur, peak_at, power)
    c = np.where(u < peak_at, f0 * (f1 / f0) ** (u / peak_at), f1 * (f2 / f1) ** ((u - peak_at) / (1 - peak_at)))
    wide = _track(pink(dur, seed) + 0.5 * white(dur, seed + 1), c, q)
    narrow = _track(white(dur, seed + 2), c, q * 4)
    return (_norm(wide) + tone * _norm(narrow)) * env


def _creak(dur, seed, f0=45, f1=75, center=760, q=2.0):
    """Leather (or cardboard) stick-slip creak: a jittered impulse train through
    two resonances, swelling and fading."""
    r = rng(seed)
    n = n_samples(dur)
    ph = phase_of(np.geomspace(f0, f1, n) * (1 + 0.15 * _norm(lowpass(white(dur, seed), 30))), n=n)
    imp = (np.diff(np.floor(ph), prepend=0) > 0).astype(float) * r.uniform(0.5, 1.0, n)
    x = bandpass(imp, center, q) + 0.5 * bandpass(imp, center * 2.3, q)
    return _norm(x) * env_swell(dur, 0.4, 1.5)


def _card_thump(seed, firm=0.0, dur=0.25):
    """The paper card struck: a damped cardboard panel (few low-mid modes),
    what strikes it (a wool shoulder, or a leather toe when firm), a dry paper
    slap and a few fibre crackles."""
    r = rng(seed)
    base = 210 - 70 * firm
    panel = _modes(dur, [(base, 0.022, 1.0), (base * 2.21, 0.014, 0.55), (base * 3.9, 0.009, 0.35),
                         (base * 6.3, 0.006, 0.2)], seed=seed)
    body = _thump(dur, seed + 1, 118 - 30 * firm, 0.03 + 0.014 * firm, drop=0.8 + 0.4 * firm,
                  attack=0.0016 - 0.0009 * firm, lp=420 - 120 * firm)
    slap = _band(white(dur, seed + 2), 1400, 9000) * _env_ad(dur, 0.0003, 0.004 - 0.0015 * firm)
    rust = grains(dur, sorted(r.uniform(0.003, 0.05, 6)), 0.009, seed + 3, band=(1800, 7000))
    toe = _band(white(dur, seed + 4), 600, 4500) * _env_ad(dur, 0.0002, 0.0012)
    return ((0.75 + 0.2 * firm) * _norm(body) + 0.5 * _norm(panel) + (0.34 + 0.1 * firm) * _norm(slap)
            + 0.16 * _norm(rust) + 0.38 * firm * _norm(toe))


def _travel_speed(u, c):
    """|d progress/du| of the runtime's back-out easing (shove c=1.2, dash
    c=0.9): fast start, rest at the overshoot, a small settle back."""
    v = np.clip(u, 0, 1) - 1
    return np.abs(3 * (c + 1) * v * v + 2 * c * v)


def _card_slide(dur, seed, speed=1.0, c=1.2, tail=0.1, stop=0.35):
    """The card's iron base dragged across stone for `dur` s: a gritty scrape
    through a band moving with the speed (1-5 kHz) that catches and releases
    (stick-slip), sparse loud stone grit ticks, a faint iron grind, papery
    flex grains, a light friction body, and a little knock when it settles.
    The drag follows the card's speed, so it fades out as the card reaches its
    overshoot rest and the knock marks the stop."""
    total = dur + tail
    n = n_samples(total)
    t = time_axis(total)
    u = np.clip(t / dur, 0, 1)
    sp = _travel_speed(u, c)
    sp = sp / sp.max()
    on = np.clip((dur - t) / 0.012, 0, 1) * np.clip(t / 0.004, 0, 1)
    lev = (0.03 + 0.97 * sp) ** 0.6 * on
    # Stick-slip catches of iron over grain: sparse sharp level kicks.
    catch = crackle(total, (200 + 500 * speed * sp) * on + 1, seed + 7, decay=0.0015)
    rough = 0.12 + 0.88 * _norm(np.abs(catch)) ** 1.3
    centre = np.clip((1100 + 2600 * sp) * speed ** 0.5, 900, 6000)
    core = _track(white(total, seed), centre, 1.0) * rough * lev
    # Stone grit: sparse enough to stay ticks, not another hiss.
    grit_raw = crackle(total, (120 + 700 * speed * sp) * on + 1, seed + 2, decay=0.0004)
    grit = _band(grit_raw, 1800, 9000) * lev
    iron_k = _modes(0.05, [(2350, 0.016, 1.0), (3460, 0.011, 0.7), (1580, 0.02, 0.5), (5120, 0.007, 0.4)])
    iron = convolve(grit_raw * lev, iron_k)[:n]
    low = _band(pink(total, seed + 3), 180, 420) * lev
    times = random_times(dur, 45 * speed, seed + 4, envelope=lambda q: 1 - 0.7 * q)
    paper = grains(total, times, 0.012, seed + 5, band=(2500, 7500), gain_jitter=0.6)
    knock = (_modes(0.1, [(820, 0.022, 1.0), (1290, 0.015, 0.6), (2010, 0.009, 0.4)])
             + 0.3 * _band(white(0.1, seed + 6), 1500, 8000) * _env_ad(0.1, 0.0002, 0.0008))
    x = (0.85 * _norm(core) + 0.9 * _norm(grit) + 0.18 * _norm(iron) + 0.12 * _norm(low)
         + 0.16 * _norm(paper))
    return x + place(total, [(dur - 0.004, _norm(knock), stop)])


def _glass(dur, notes=_GLASS_NOTES, tau=0.25, attack=0.0008, beat=1.6, seed=None):
    """The lantern's glass globe: glass-shell partials per note, each doubled a
    hair sharp so it shimmers; the high partials die first."""
    modes = []
    for f, a in notes:
        for k, rt in enumerate(_GLASS_RATIOS):
            fk = f * rt
            if fk > 16000:
                continue
            tk = tau / (1 + 1.3 * k)
            ak = a / (1 + 2.0 * k)
            modes.append((fk, tk, ak))
            modes.append((fk + beat * (1 + 0.6 * k), tk * 0.9, ak * 0.4))
    return _modes(dur, modes, attack, seed)


def _lantern(seed, hits, glass=0.0, dur=0.5, tau=0.07, links=1.0):
    """The iron lantern knocking on its handle and chain: each hit rings the
    frame's fixed modes (excited by a noise click, so no two hits match) and a
    few chain links tick right after. `glass` adds the globe's chime."""
    r = rng(seed)
    out = np.zeros(n_samples(dur))
    for i, (t0, g) in enumerate(hits):
        k = 1 + r.uniform(-0.012, 0.012)
        modes = [(f * k, tau / (1 + 0.4 * j), r.uniform(0.5, 1.0) / (1 + 0.45 * j)) for j, f in enumerate(_FRAME)]
        ring = _modes(0.3, modes, seed=seed + 10 + i)
        exc = white(0.0012, seed + 20 + i) * np.hanning(n_samples(0.0012))
        ring = _norm(convolve(exc, ring)[:len(ring)])
        ev = [(t0, ring, g)]
        for m in range(1 + int(round(2 * links * r.random()))):
            f = r.uniform(3800, 7200)
            click = _modes(0.04, [(f, 0.006, 1.0), (f * 1.53, 0.004, 0.6)])
            ev.append((t0 + r.uniform(0.004, 0.035), _norm(click), g * r.uniform(0.25, 0.5) * links))
        out += place(dur, ev)
    if glass > 0 and hits:
        out += place(dur, [(hits[0][0] + 0.002, _norm(_glass(0.5, tau=0.12)), glass * hits[0][1])])
    return out


def _slap(dur, seed, lo=900, hi=7000, tau=0.006):
    """Cloth slap: a short broadband burst plus a little flap body."""
    s = _band(white(dur, seed), lo, hi) * _env_ad(dur, 0.0004, tau)
    flap = _band(pink(dur, seed + 1), 500, 2200) * _env_ad(dur, 0.002, tau * 3)
    return _norm(s) + 0.4 * _norm(flap)


def _crumple(dur, seed, length=0.12, rate=220, lo=1500):
    """Paper crumpling: grains 1.5-8 kHz (5-30 ms), denser at the start, and
    the sharp crinkle clicks of folding fibres."""
    t1 = random_times(length, rate, seed, envelope=lambda u: (1 - u) ** 1.2)
    a = grains(dur, t1, 0.007, seed + 1, band=(lo, 8000), gain_jitter=0.7)
    t2 = random_times(length, rate * 0.35, seed + 2)
    b = grains(dur, t2, 0.022, seed + 3, band=(lo, 5000), gain_jitter=0.6)
    t = time_axis(dur)
    dens = 1800 * np.exp(-t / (length * 0.4)) * (t < length) + 1
    clicks = _band(crackle(dur, dens, seed + 4, decay=0.0003), 2500, 10000)
    return _norm(a) + 0.5 * _norm(b) + 0.35 * _norm(clicks)


def _breath(dur, seed, attack=0.015, hold=0.04, tau=0.11, form=1.0):
    """An exhale knocked out of him: unvoiced noise through mouth-like
    resonances, darkening as it fades. No voice."""
    x = 0.7 * white(dur, seed) + pink(dur, seed + 1)
    x = formant(x, [(640 * form, 3.0, 1.0), (1180 * form, 3.5, 0.7), (2550 * form, 4.0, 0.45),
                    (3800 * form, 3.0, 0.2)])
    x = sweep_lowpass(x, 6000, 1600)
    return _norm(x) * _env_ad(dur, attack, tau, hold)


def _flame(dur, seed, attack=0.018, tau=0.12, hiss=0.35):
    """The blue flame flaring: a soft low whoomp (brown noise 75-350 Hz, a
    small flame has no sub, with a closing lowpass) and a clean gas hiss; no
    crackle."""
    t = time_axis(dur)
    env = _env_ad(dur, attack, tau)
    low = _band(brown(dur, seed), 75, 340, order=3) * env
    body = sweep_lowpass(highpass(pink(dur, seed + 1), 90), 1400, 260) * env
    henv = np.clip(t / (attack * 0.7), 0, 1) * np.exp(-t / (tau * 0.7))
    gas = _band(white(dur, seed + 2), 900, 4200) * henv
    return _norm(low) + 0.6 * _norm(body) + hiss * _norm(gas)


def _coin(seed, base, tau=0.09, dur=0.35):
    """A coin: thin-disc inharmonic modes and a hard little tick."""
    r = rng(seed)
    modes = [(base * rt * (1 + r.uniform(-0.01, 0.01)), tau / (1 + 0.5 * k), r.uniform(0.6, 1.0) / (1 + 0.6 * k))
             for k, rt in enumerate(_COIN_RATIOS)]
    ring = _modes(dur, modes, seed=seed)
    tick = _band(white(dur, seed + 1), 3000, 12000) * _env_ad(dur, 0.0002, 0.0005)
    return _norm(ring) + 0.4 * _norm(tick)


def _path(dur, points):
    """A frequency path (Hz per sample) through (time_s, Hz) points, gliding
    evenly in pitch between them."""
    ts, fs = zip(*points)
    return np.exp(np.interp(time_axis(dur), ts, np.log(fs)))


def _ink(dur, seed, env, centers, q=0.8, swirl=0.4):
    """His shadow's ink: dark soft noise through a band whose centre follows
    `centers` (Hz per sample), its level following `env`, thickened by a slow,
    uneven swirl (a viscous liquid moving); never bright, never gritty."""
    n = n_samples(dur)
    e = pad_to(np.asarray(env, float), dur)
    src = brown(dur, seed) + 0.7 * pink(dur, seed + 1)
    turn = 1 - swirl * (0.5 + 0.5 * _norm(lowpass(white(dur, seed + 2), 9, 2)))
    body = _track(src, centers, q) * turn
    return _norm(body)[:n] * e / (np.max(e) + 1e-9)


def _ward(dur, notes, attack=0.012, tau=0.3, trem=6.0, depth=0.3, detune=1.4, seed=0):
    """A ward's soft partials: detuned sine pairs (D Phrygian) with a gentle
    tremolo; soft attack."""
    r = rng(seed)
    t = time_axis(dur)
    x = np.zeros_like(t)
    for f, a in notes:
        for d in (-detune, detune):
            x += a * np.sin(2 * np.pi * (f + d) * t + r.uniform(0, 2 * np.pi))
    tr = 1 - depth * (0.5 + 0.5 * np.sin(2 * np.pi * trem * t))
    return x * _env_ad(dur, attack, tau) * tr


# --------------------------------------------------------------------------
# Moves: shove, hop-shove, kick, dash

@sound("pilgrim_move_side", loudness=-21, wet=0.18, marks=(0.0, 0.275, 0.28, 0.495, 0.64))
def pilgrim_move_side(seed):
    """Coils back (wool rustle 0-0.24), shoulders the card at 0.275 (soft
    cardboard thump, the lantern knocks), the iron base scrapes the stone
    0.28-0.495 and knocks to rest, the boot lands at 0.64, two small steps."""
    D = 1.0
    ce = env_points(0.32, [(0, 0), (0.015, 0.3), (0.10, 0.5), (0.19, 1.0), (0.245, 0.75), (0.32, 0.0)])
    cloak = _cloak(0.32, seed, ce, lo=380, hi=1700)
    thump = _card_thump(seed + 2, firm=0.0)
    slide = _card_slide(0.215, seed + 3, speed=1.0)
    rattle = _lantern(seed + 4, [(0.0, 1.0), (0.03, 0.5), (0.075, 0.3)], glass=0.35)
    follow = _cloak(0.25, seed + 8, env_points(0.25, [(0, 0), (0.04, 1), (0.25, 0)]), lo=350, hi=1200)
    land = _boot(seed + 5, body_hz=110)
    st1 = _boot(seed + 6, body_hz=125, weight=0.6, grit=0.5)
    st2 = _boot(seed + 7, body_hz=130, weight=0.5, grit=0.4)
    x = place(D, [
        (0.0, cloak, 0.30),
        (0.275, thump, 0.75), (0.28, slide, 0.65), (0.279, rattle, 0.30),
        (0.45, follow, 0.12), (0.64, land, 0.75),
        (0.76, st1, 0.20), (0.87, st2, 0.15),
    ])
    return _finish(x, D)


@sound("pilgrim_move_up", loudness=-21, wet=0.18, marks=(0.205, 0.285, 0.29, 0.505, 0.5))
def pilgrim_move_up(seed):
    """A hop: crouch rustle, the boot pushes off with a scuff at 0.205, a
    leaping shoulder shoves the card at 0.285 (thump, slide to 0.505), he lands
    at 0.5 with a cloak flutter and a lantern knock."""
    D = 1.0
    crouch = _cloak(0.22, seed, env_points(0.22, [(0, 0), (0.1, 0.4), (0.2, 1.0), (0.22, 0.6)]), lo=380, hi=1300)
    push = _scuff(seed + 1, length=0.05, lo=1200, hi=2800, weight=0.7)
    leap = _whoosh(0.16, seed + 2, 350, 1100, 600, peak_at=0.5, q=0.9, tone=0.1)
    thump = _card_thump(seed + 3, firm=0.15)
    slide = _card_slide(0.215, seed + 4, speed=1.0)
    rattle = _lantern(seed + 5, [(0.0, 1.0), (0.035, 0.45), (0.215, 0.7), (0.24, 0.3)], glass=0.3, dur=0.5)
    land = _boot(seed + 6, body_hz=105, weight=1.25)
    flut = _flutter(0.24, seed + 7, rate0=22, rate1=10, tau=0.08)
    st1 = _boot(seed + 8, body_hz=125, weight=0.55, grit=0.5)
    st2 = _boot(seed + 9, body_hz=130, weight=0.5, grit=0.4)
    x = place(D, [
        (0.0, crouch, 0.20), (0.205, push, 0.45), (0.205, leap, 0.18),
        (0.285, thump, 0.75), (0.29, slide, 0.60), (0.289, rattle, 0.24),
        (0.5, land, 0.80), (0.505, flut, 0.28),
        (0.76, st1, 0.18), (0.88, st2, 0.13),
    ])
    return _finish(x, D)


@sound("pilgrim_move_down", loudness=-21, wet=0.18, marks=(0.275, 0.28, 0.495, 0.57))
def pilgrim_move_down(seed):
    """A kick: leans back (wool), the leg swings (short low swish), the boot
    kicks the card at 0.275-0.28 (a firmer, lower thump than the shove), the
    card slides to 0.495, the boot comes down at 0.57."""
    D = 1.0
    lean = _cloak(0.22, seed, env_points(0.22, [(0, 0), (0.1, 0.5), (0.2, 1.0), (0.22, 0.5)]), lo=360, hi=1200)
    swing = _whoosh(0.085, seed + 2, 250, 750, 500, peak_at=0.8, q=1.0, tone=0.1)
    kick = _card_thump(seed + 3, firm=1.0)
    slide = _card_slide(0.215, seed + 4, speed=1.1)
    rattle = _lantern(seed + 5, [(0.0, 0.6), (0.05, 0.35)], glass=0.2)
    down = _boot(seed + 6, body_hz=112, weight=1.0)
    st = _boot(seed + 7, body_hz=128, weight=0.5, grit=0.4)
    x = place(D, [
        (0.06, lean, 0.20), (0.195, swing, 0.22),
        (0.275, kick, 0.90), (0.28, slide, 0.60), (0.285, rattle, 0.18),
        (0.57, down, 0.72), (0.84, st, 0.15),
    ])
    return _finish(x, D)


@sound("pilgrim_dodge", loudness=-20, wet=0.18, marks=(0.08, 0.12, 0.34, 0.31))
def pilgrim_dodge(seed):
    """Two-cell dash: a fast low cloak whoosh from 0.08 (the roll), the lantern
    jolts as he tucks at 0.12, the card shoots across stone 0.08-0.34 (fast,
    bright scrape), boots skid-stop at 0.31."""
    D = 1.0
    gather = _cloak(0.09, seed, env_points(0.09, [(0, 0), (0.07, 1.0), (0.09, 0.6)]), lo=400, hi=1100)
    push = _scuff(seed + 1, length=0.035, lo=1400, hi=3000, weight=0.55)
    roll = _whoosh(0.25, seed + 2, 260, 900, 380, peak_at=0.42, q=0.9, power=1.6, tone=0.25)
    slide = _card_slide(0.26, seed + 3, speed=1.6, c=0.9, stop=0.5)
    jolt = _lantern(seed + 4, [(0.0, 1.0), (0.02, 0.6), (0.055, 0.35)], glass=0.4, links=1.5)
    skid = _scuff(seed + 5, length=0.07, dur=0.16, lo=2600, hi=1100, weight=0.0)
    land = _boot(seed + 6, body_hz=108, weight=1.1, grit=1.4)
    settle = _cloak(0.2, seed + 7, env_points(0.2, [(0, 0), (0.03, 1), (0.2, 0)]), lo=350, hi=1000)
    x = place(D, [
        (0.0, gather, 0.16), (0.08, push, 0.40), (0.08, roll, 0.42), (0.08, slide, 0.50),
        (0.12, jolt, 0.20), (0.31, land, 0.70), (0.312, skid, 0.32), (0.4, settle, 0.10),
    ])
    return _finish(x, D)


# --------------------------------------------------------------------------
# Attack, cast

@sound("pilgrim_attack", loudness=-18, wet=0.2, marks=(0.07, 0.12, 0.125, 0.38, 0.61))
def pilgrim_attack(seed):
    """Swings the lantern on its chain: a wind-up, a whoosh from 0.07 that
    peaks into the blow, the leap's push at 0.12, the iron-and-glass blow at
    0.125 (blunt thud + heavy iron clank + a tiny glass chime, the chain
    rattling after), then the backflip: boots at 0.38, a swirling cloak flap,
    boots again at 0.61."""
    D = 1.0
    wind = _whoosh(0.07, seed, 300, 700, 400, peak_at=0.6, q=1.0, tone=0.1)
    swing = _whoosh(0.15, seed + 1, 380, 1500, 500, peak_at=0.33, q=1.1, power=1.8, tone=0.35)
    chain = _lantern(seed + 2, [(0.0, 0.5), (0.03, 0.4)], links=2.0, tau=0.04)
    push = _scuff(seed + 3, length=0.03, lo=1400, hi=2600, weight=0.5)
    thud = _blow(0.3, seed + 4, 92, 0.028, lp=320)
    slap = _slap(0.06, seed + 5, 700, 6000, tau=0.005)
    clank = _modes(0.6, [(520, 0.22, 0.8), (790, 0.17, 0.7)] +
                   [(f, 0.13 / (1 + 0.35 * j), 1 / (1 + 0.4 * j)) for j, f in enumerate(_FRAME)], seed=seed + 6)
    clank = _norm(convolve(white(0.0008, seed + 7) * np.hanning(n_samples(0.0008)), clank)[:len(clank)])
    chime = _glass(0.6, tau=0.14)
    rattle = _lantern(seed + 8, [(0.0, 0.7), (0.04, 0.5), (0.09, 0.35), (0.15, 0.2)], links=1.6)
    land1 = _boot(seed + 9, body_hz=106, weight=1.15)
    flip = _whoosh(0.2, seed + 10, 300, 900, 380, peak_at=0.55, q=0.8, tone=0.15)
    flap = _flutter(0.2, seed + 11, rate0=16, rate1=9, tau=0.12, lo=420, hi=1300)
    land2 = _boot(seed + 12, body_hz=100, weight=1.3, grit=1.2)
    x = place(D, [
        (0.0, wind, 0.10), (0.07, swing, 0.42), (0.07, chain, 0.10), (0.12, push, 0.22),
        (0.125, thud, 0.68), (0.125, slap, 0.30), (0.125, clank, 0.70), (0.126, chime, 0.06),
        (0.15, rattle, 0.20),
        (0.38, land1, 0.62), (0.41, flip, 0.26), (0.43, flap, 0.16), (0.61, land2, 0.70),
    ])
    return _finish(x, D)


@sound("pilgrim_cast", loudness=-24, wet=0.25, marks=(0.17, 0.25, 0.57))
def pilgrim_cast(seed):
    """Plays a card (light, under the card's own sound): a crouch, the cloak
    swishes as the hand rises (peak 0.17), the lantern flame flares at 0.25
    (soft blue whoomp + the globe's ring), settles at 0.57 (a soft foot
    settle, the flame breathing down)."""
    D = 0.8
    crouch = _cloak(0.12, seed, env_points(0.12, [(0, 0), (0.1, 1.0), (0.12, 0.6)]), lo=350, hi=900)
    swish = _whoosh(0.16, seed + 1, 450, 1700, 700, peak_at=0.5, q=1.0, tone=0.12)
    flare = _flame(0.4, seed + 2, attack=0.02, tau=0.1, hiss=0.4)
    ring = _glass(0.55, tau=0.16, attack=0.002)
    tick = _lantern(seed + 3, [(0.0, 1.0)], links=0.6, tau=0.05)
    breathe = _flame(0.25, seed + 4, attack=0.05, tau=0.07, hiss=0.25)
    settle = _boot(seed + 5, body_hz=120, weight=0.6, grit=0.4)
    rest = _cloak(0.15, seed + 6, env_points(0.15, [(0, 0), (0.03, 1), (0.15, 0)]), lo=350, hi=900)
    x = place(D, [
        (0.0, crouch, 0.10), (0.09, swish, 0.30), (0.232, flare, 0.70), (0.25, ring, 0.18),
        (0.25, tick, 0.08), (0.5, breathe, 0.18), (0.57, settle, 0.32), (0.575, rest, 0.08),
    ])
    return _finish(x, D, tail=0.06)


# --------------------------------------------------------------------------
# Reactions

def _hurt(seed, back):
    """Shared by hurt and hurt_back: the blow lands at 0.118 (an unpitched
    muffled body blow, no ringing), the slap, then the paper crumple."""
    D = 0.8
    p = 1.18 if back else 1.0
    blow = _blow(0.35, seed, 88 * p, 0.026 if back else 0.03, lp=260 * p)
    slap = _slap(0.06, seed + 1, 1500 if back else 850, 8000 if back else 6500, tau=0.004 if back else 0.006)
    crump = _crumple(0.25, seed + 2, length=0.11, rate=240, lo=1900 if back else 1500)
    rattle = _lantern(seed + 3, [(0.0, 1.0), (0.03, 0.6), (0.075, 0.45), (0.14, 0.25)], glass=0.25, links=1.4)
    thrown = _whoosh(0.16, seed + 4, 300 * p, 800 * p, 400 * p, peak_at=0.3, q=0.8, tone=0.05)
    breath = _breath(0.4, seed + 5, attack=0.012, hold=0.03, tau=0.085 if back else 0.1, form=1.12 if back else 1.0)
    rec = _cloak(0.2, seed + 6, env_points(0.2, [(0, 0), (0.05, 1), (0.2, 0)]), lo=350, hi=1000)
    shuffle = _boot(seed + 7, body_hz=125 * p, weight=0.5, grit=0.5)
    x = place(D, [
        (0.118, blow, 0.72), (0.118, slap, 0.42 if back else 0.32), (0.126, crump, 0.42 if back else 0.5),
        (0.121, rattle, 0.16), (0.125, thrown, 0.20), (0.14, breath, 0.30),
        # The recovery follows each clip: front plants at ~0.44, back at 0.36.
        (0.30 if back else 0.33, rec, 0.10), (0.36 if back else 0.44, shuffle, 0.18),
    ])
    return _finish(x, D)


@sound("pilgrim_hurt", loudness=-18, wet=0.18, marks=(0.118,))
def pilgrim_hurt(seed):
    """Thrown back: a muffled body blow at 0.118 + cloth slap + paper crumple +
    lantern rattle, a short unvoiced exhale, a recovering shuffle."""
    return _hurt(seed, back=False)


@sound("pilgrim_hurt_back", loudness=-18, wet=0.18, marks=(0.118,))
def pilgrim_hurt_back(seed):
    """Hit from behind, pitched forward: the same blow a little higher, a
    sharper, brighter slap, a shorter breath."""
    return _hurt(seed, back=True)


@sound("pilgrim_block", loudness=-19, wet=0.22, marks=(0.118,))
def pilgrim_block(seed):
    """The cloak closes in front of him, the ward takes the blow at 0.118: a
    dull, damped thud heard through soft shimmering D-Phrygian partials (D4,
    A4, D5, F5, struck as resonances of the ward), the lantern globe chimes."""
    D = 0.65
    close = _whoosh(0.11, seed, 380, 1000, 600, peak_at=0.6, q=0.8, tone=0.05)
    # Settles on D2, under the ward's D/A/F (faintly pitched, heavily damped).
    thud = _thump(0.3, seed + 1, _hz("D", 2), 0.035, drop=0.6, attack=0.003, lp=220)
    notes = [(_hz("D", 4), 1.0), (_hz("A", 4), 0.7), (_hz("D", 5), 0.55), (_hz("F", 5), 0.35), (_hz("A", 5), 0.2)]
    ward = _ward(0.53, notes, attack=0.01, tau=0.16, trem=6.5, depth=0.35, seed=seed + 2)
    struck = _modes(0.5, [(f * k, 0.05 / k, a / k) for f, a in notes for k in (1, 2)], attack=0.004)
    press = _band(pink(0.12, seed + 3), 200, 2500) * _env_ad(0.12, 0.004, 0.025)
    chime = _glass(0.5, tau=0.16, attack=0.003)
    rattle = _lantern(seed + 4, [(0.0, 0.6), (0.05, 0.3)], links=0.8)
    settle = _cloak(0.18, seed + 5, env_points(0.18, [(0, 0), (0.04, 1), (0.18, 0)]), lo=350, hi=900)
    x = place(D, [
        (0.0, close, 0.22), (0.118, thud, 0.85), (0.118, press, 0.5), (0.118, struck, 0.28),
        (0.12, ward, 0.40), (0.135, chime, 0.16), (0.125, rattle, 0.10), (0.3, settle, 0.16),
    ])
    return _finish(x, D, tail=0.06)


@sound("pilgrim_parry", loudness=-17, wet=0.3, marks=(0.05,))
def pilgrim_parry(seed):
    """Steel on iron at 0.05: a hard click, a bright steel blade's inharmonic
    lines (lowest A6, beating pairs) over the lantern frame's lower iron, a
    short shing of the edges sliding apart and a tiny weight thump; the ring
    darkens as it decays (high modes die first)."""
    D = 0.8
    pre = _whoosh(0.05, seed, 600, 1800, 1500, peak_at=0.85, q=1.2, tone=0.1)
    ratios = (1.0, 1.47, 2.09, 2.56, 3.2, 3.9, 4.7, 5.6)
    blade = []
    for j, rt in enumerate(ratios):
        f = _hz("A", 6) * rt
        tau = 0.38 / (1 + 0.35 * j)
        a = (1.0, 0.95, 0.9, 0.85, 0.75, 0.6, 0.5, 0.4)[j]
        blade += [(f, tau, a), (f + 2.2 + 0.9 * j, tau * 0.95, a * 0.35)]
    blade = _modes(0.75, blade, seed=seed + 1)
    iron = _modes(0.6, [(612, 0.22, 0.5), (905, 0.16, 0.45)] +
                  [(f, 0.08 / (1 + 0.3 * j), 0.6 / (1 + 0.4 * j)) for j, f in enumerate(_FRAME)], seed=seed + 2)
    exc = white(0.0012, seed + 3) * np.hanning(n_samples(0.0012))
    blade = _norm(convolve(exc, blade)[:len(blade)])
    iron = _norm(convolve(exc, iron)[:len(iron)])
    click = _band(white(0.02, seed + 4), 2000, 16000) * _env_ad(0.02, 0.0001, 0.0006)
    shing = _band(white(0.09, seed + 5), 4500, 12000) * _env_ad(0.09, 0.001, 0.018)
    weight = _thump(0.15, seed + 6, 160, 0.018, drop=0.5, attack=0.0008)
    chime = _glass(0.5, tau=0.1)
    x = place(D, [
        (0.0, pre, 0.15), (0.05, click, 0.22), (0.05, blade, 0.80), (0.05, iron, 0.42),
        (0.052, shing, 0.24), (0.05, weight, 0.18), (0.06, chime, 0.08),
    ])
    # Taper the ringing tail into the hall instead of cutting it.
    t = time_axis(D)
    x *= np.where(t > 0.55, np.cos(0.5 * np.pi * np.clip((t - 0.55) / 0.25, 0, 1)) ** 2, 1.0)
    return _finish(x, D, tail=0.02)


@sound("pilgrim_deflect", loudness=-18, wet=0.28, marks=(0.0,))
def pilgrim_deflect(seed):
    """RIFLESSO: the blow meets his ward at 0.0 and is turned: a hard click,
    a bright steel ring over the ward's partials (D5 A5 D6: a flash that dies
    fast), the lantern globe's chime, and the blow sent back: a bright whoosh
    leaving him and falling away (3.5 -> 0.8 kHz) with a faint whistle."""
    D = 0.7
    click = _band(white(0.02, seed), 2000, 16000) * _env_ad(0.02, 0.0001, 0.0006)
    ring = []
    for j, rt in enumerate((1.0, 1.47, 2.09, 2.56, 3.2, 3.9)):
        f = _hz("D", 6) * rt
        tau = 0.22 / (1 + 0.4 * j)
        ring += [(f, tau, 1.0 / (1 + 0.3 * j)), (f + 2.0 + j, tau * 0.9, 0.35 / (1 + 0.3 * j))]
    ring = _modes(0.6, ring, seed=seed + 1)
    exc = white(0.001, seed + 2) * np.hanning(n_samples(0.001))
    ring = _norm(convolve(exc, ring)[:len(ring)])
    ward = _ward(0.45, [(_hz("D", 5), 1.0), (_hz("A", 5), 0.6), (_hz("D", 6), 0.35)], attack=0.003, tau=0.1, trem=9.0,
                 depth=0.3, seed=seed + 3)
    chime = _glass(0.45, tau=0.12)
    away = _whoosh(0.28, seed + 4, 3500, 2600, 800, peak_at=0.15, q=1.4, power=1.6, tone=0.5)
    weight = _thump(0.15, seed + 5, 150, 0.016, drop=0.5, attack=0.0008)
    x = place(D, [
        (0.0, click, 0.24), (0.0, ring, 0.7), (0.0, ward, 0.3), (0.0, weight, 0.16),
        (0.008, chime, 0.1), (0.03, away, 0.42),
    ])
    t = time_axis(D)
    x *= np.where(t > 0.5, np.cos(0.5 * np.pi * np.clip((t - 0.5) / 0.2, 0, 1)) ** 2, 1.0)
    return _finish(x, D, tail=0.02)


@sound("pilgrim_shoot", loudness=-19, wet=0.2, marks=(0.03, 0.125, 0.3))
def pilgrim_shoot(seed):
    """FERETRO: an arrow loosed from his hand bow: the string drawn (a
    leather-and-wood creak from 0.03, tightening), released at 0.125 (the
    string's twang, a thrummed low pluck on D3, a dry wooden knock of the
    bow and a snap), the arrow's whistling whoosh leaving him, and the cloak
    settling at 0.30."""
    D = 0.7
    draw = _creak(0.09, seed, f0=30, f1=70, center=900, q=2.4)
    twang = karplus(_hz("D", 3), 0.4, damping=0.993, brightness=0.6, seed=seed + 1)
    twang = _band(twang, 90, 5000) * _env_ad(0.4, 0.001, 0.12)
    knock = _modes(0.1, [(420, 0.018, 1.0), (980, 0.01, 0.6), (1700, 0.006, 0.35)], seed=seed + 2)
    snap = _band(white(0.02, seed + 3), 1800, 9000) * _env_ad(0.02, 0.0002, 0.001)
    fly = _whoosh(0.22, seed + 4, 900, 3200, 1800, peak_at=0.25, q=1.3, power=1.6, tone=0.6)
    settle = _cloak(0.18, seed + 5, env_points(0.18, [(0, 0), (0.04, 1), (0.18, 0)]), lo=350, hi=900)
    x = place(D, [
        (0.03, draw, 0.22), (0.125, twang, 0.5), (0.125, knock, 0.4), (0.125, snap, 0.3),
        (0.13, fly, 0.45), (0.3, settle, 0.14),
    ])
    return _finish(x, D, tail=0.03)


@sound("pilgrim_stunned", loudness=-24, wet=0.3)
def pilgrim_stunned(seed):
    """Dazed: a thin high ringing near A7 led by a slow 0.62 Hz pitch wobble
    (about +-25 cents; a faint, slow 1.3 Hz beat under it), the lantern's
    globe ticking irregularly against its frame as it swings (its own D6/A6
    only, near then far), the cloak swaying with the stagger, a faint low
    D/Eb unease."""
    D = 1.6
    t = time_axis(D)
    n = len(t)
    wob = 1 + 0.015 * np.sin(2 * np.pi * 0.62 * t) + 0.002 * np.sin(2 * np.pi * 1.7 * t + 1.0)
    a7 = _hz("A", 7)
    ring = (np.sin(2 * np.pi * phase_of(a7 * wob, n=n)) + 0.3 * np.sin(2 * np.pi * phase_of((a7 + 1.3) * wob, n=n))
            + 0.25 * np.sin(2 * np.pi * phase_of(a7 / 2 * wob, n=n)))
    hiss = _track(white(D, seed), a7 * wob, 10.0)
    renv = (np.clip(t / 0.12, 0, 1) * (0.75 + 0.25 * np.sin(2 * np.pi * 0.6 * t + 0.5))
            * np.clip((D - t) / 0.45, 0, 1) ** 1.5)
    ringing = (_norm(ring) + 0.35 * _norm(hiss)) * renv
    # The lantern swinging as he sways: its globe ticks against the frame at
    # irregular moments, most often where the stagger stops and the lantern
    # swings on (0, 0.42, 0.84, 1.26 s), striking only its own two notes (D6,
    # A6), near then far.
    # A loose globe often rattles twice (a quick second tick, softer).
    r = rng(seed + 1)
    times = random_times(D, 5.5, seed + 1, start=0.06, end=D - 0.2,
                         envelope=lambda u: 0.3 + 0.7 * abs(math.cos(2 * np.pi * (0.06 + u * (D - 0.26)) / 0.84)))
    tinkles = np.zeros(n)
    for tt in times:
        near = 0.55 + 0.45 * math.cos(2 * np.pi * tt / 0.84)
        hits = [(tt, r.uniform(0.3, 1.0))]
        if r.random() < 0.4:
            hits.append((tt + r.uniform(0.018, 0.045), r.uniform(0.25, 0.55)))
        for th, strength in hits:
            f0 = (_GLASS_NOTES[0] if r.random() < 0.6 else _GLASS_NOTES[1])[0] * (1 + r.uniform(-0.003, 0.003))
            g = _glass(0.4, notes=((f0, 1.0),), tau=0.07 + 0.05 * near, attack=0.001)
            if near < 0.5:
                g = lowpass(g, 2500 + 6000 * near)
            tinkles += place(D, [(th, _norm(g), (0.3 + 0.7 * near) * strength)])
    # Cloak sways where the stagger moves fastest (0.21, 0.63, 1.05, 1.47 s).
    sways = place(D, [(pk - 0.15, _cloak(0.3, seed + 2 + k, env_swell(0.3, 0.5), lo=300, hi=800), 0.10)
                      for k, pk in enumerate((0.21, 0.63, 1.05, 1.47))])
    low = (np.sin(2 * np.pi * _hz("D", 2) * t) + 0.8 * np.sin(2 * np.pi * _hz("Eb", 2) * t)) \
        * env_swell(D, 0.45, 1.5)
    x = (0.55 * ringing + 0.28 * tinkles / (np.max(np.abs(tinkles)) + 1e-9) + 0.035 * low
         + sways)
    return _finish(x, D, tail=0.05)


# --------------------------------------------------------------------------
# Loot, heal, death

@sound("pilgrim_interact", loudness=-22, wet=0.2, marks=(0.28,))
def pilgrim_interact(seed):
    """Crouches (wool rustle), pockets the loot at 0.28: coins
    clink on coins, the later ones muffled as they drop into the leather pouch
    (a soft pouch thump and creak), then a small hop back and a light landing."""
    D = 0.7
    r = rng(seed)
    crouch = _cloak(0.3, seed, env_points(0.3, [(0, 0), (0.12, 0.7), (0.24, 1.0), (0.3, 0.3)]), lo=350, hi=1200)
    ev = []
    t0 = 0.28
    for k in range(5):
        base = r.uniform(2200, 3800)
        c = _coin(seed + 10 + k, base, tau=0.09 if k < 2 else 0.04)
        if k >= 2:
            c = lowpass(c, 3500 - 500 * k, 2)
        ev.append((t0, _norm(c), (1.0 if k == 0 else 0.75) * (0.8 ** k)))
        t0 += r.uniform(0.012, 0.03)
    pouch = _thump(0.2, seed + 2, 150, 0.025, drop=0.4, attack=0.003, lp=600)
    leather = _band(pink(0.12, seed + 3), 300, 1500) * _env_ad(0.12, 0.005, 0.03)
    pcreak = _creak(0.12, seed + 4, 50, 80, 900, q=2.0)
    hop = _whoosh(0.08, seed + 5, 300, 700, 400, peak_at=0.5, q=0.9, tone=0.05)
    land = _boot(seed + 6, body_hz=124, weight=0.6, grit=0.5)
    settle = _cloak(0.18, seed + 7, env_points(0.18, [(0, 0), (0.03, 1), (0.18, 0)]), lo=350, hi=900)
    x = place(D, [(0.0, crouch, 0.16), (0.3, pouch, 0.50), (0.3, leather, 0.25),
                  (0.33, pcreak, 0.30), (0.37, hop, 0.10), (0.45, land, 0.30), (0.46, settle, 0.08)]
              + [(tt, c, 0.6 * g) for tt, c, g in ev])
    return _finish(x, D, tail=0.04)


@sound("pilgrim_heal", loudness=-21, wet=0.35)
def pilgrim_heal(seed):
    """Comforting: a warm D3/A3 pad swelling as its lowpass opens, soft bell
    partials rising D4 - F4 - A4 - D5 (slow attacks, shimmering tremolo and a
    slight detune), a breath of air, two faint glints of the lantern glass."""
    D = 0.9
    t = time_axis(D)
    pad = (triangle(_hz("D", 3), D) + 0.6 * triangle(_hz("A", 3) * 1.002, D)
           + 0.4 * np.sin(2 * np.pi * _hz("D", 4) * 0.998 * t))
    pad = sweep_lowpass(pad, 280, 1500)
    pad *= env_points(D, [(0, 0), (0.12, 0.25), (0.5, 1.0), (0.7, 0.7), (0.9, 0.0)])
    bells = np.zeros(len(t))
    for k, (name, octv, t0) in enumerate((("D", 4, 0.05), ("F", 4, 0.17), ("A", 4, 0.29), ("D", 5, 0.41))):
        f = _hz(name, octv)
        dur = D - t0
        tt = time_axis(dur)
        b = np.zeros(len(tt))
        # Each partial: a main tone and a quieter twin a hair sharp, beating at
        # its own rate and phase (about +-3 dB, never a common null).
        for j, (rt, a, tau) in enumerate(((1.0, 1.0, 0.45), (2.0, 0.35, 0.25), (3.01, 0.15, 0.15),
                                          (4.17, 0.08, 0.1))):
            b += (a * np.sin(2 * np.pi * f * rt * tt) * np.exp(-tt / tau)
                  + 0.35 * a * np.sin(2 * np.pi * (f * rt + 0.7 + 0.5 * j) * tt + 1.1 * j) * np.exp(-tt / (0.9 * tau)))
        b *= np.clip(tt / 0.06, 0, 1) * (1 - 0.12 * (0.5 + 0.5 * np.sin(2 * np.pi * 5.5 * tt)))
        bells += place(D, [(t0, b, 0.5 + 0.17 * k)])
    air = _band(pink(D, seed), 900, 5000) * env_swell(D, 0.45, 2.0)
    glint = _glass(0.4, tau=0.08, attack=0.003)
    x = (0.45 * _norm(pad) + 0.55 * _norm(bells) + 0.22 * _norm(air)
         + place(D, [(0.48, _norm(glint), 0.06), (0.6, _norm(glint), 0.04)]))
    return _finish(x, D, tail=0.12)


@sound("pilgrim_death", loudness=-18, wet=0.3, marks=(0.118, 0.68))
def pilgrim_death(seed):
    """Struck at 0.118 (a heavier blow, slap, crumple, lantern rattle, a last
    falling exhale); the card folds (cardboard creak + paper crease crackles
    thickening 0.3-0.62), topples (a breath of air) and slaps flat on stone at
    0.68 (its iron base clanks); the lantern hits the floor, its glass cracks
    and it rolls to a stop; the blue flame gutters out in failing puffs."""
    D = 1.2
    r = rng(seed)
    blow = _blow(0.4, seed, 80, 0.035, lp=240)
    slap = _slap(0.06, seed + 1, 800, 6500, tau=0.007)
    crump = _crumple(0.3, seed + 2, length=0.14, rate=260)
    rattle = _lantern(seed + 3, [(0.0, 1.0), (0.035, 0.6), (0.08, 0.4)], glass=0.25, links=1.4)
    breath = _breath(0.45, seed + 4, attack=0.015, hold=0.05, tau=0.14, form=0.92)
    # The card folds: a cardboard stick-slip creak and paper crease crackles.
    fold = _creak(0.32, seed + 5, 28, 85, 620, q=1.6)
    tf = time_axis(0.32)
    crease = _band(crackle(0.32, 150 + 2500 * (tf / 0.32) ** 2, seed + 6, decay=0.0003), 2200, 9000)
    crease *= np.clip(tf / 0.05, 0, 1) * np.clip((0.32 - tf) / 0.02, 0, 1)
    crease = crease + 0.5 * grains(0.32, random_times(0.32, 60, seed + 7, envelope=lambda u: u), 0.015, seed + 8,
                                   band=(1800, 6000))
    topple = _whoosh(0.12, seed + 9, 220, 700, 600, peak_at=0.9, q=0.8, tone=0.05)
    # Flat on stone: an air "pap", a low thump, the iron base clanks.
    pap = _band(white(0.08, seed + 10), 250, 4000) * _env_ad(0.08, 0.0003, 0.008)
    flat = _thump(0.25, seed + 11, 95, 0.03, drop=0.6, attack=0.001)
    base = _modes(0.3, [(820, 0.05, 1.0), (1290, 0.035, 0.6), (2010, 0.02, 0.4), (3100, 0.012, 0.25)])
    flutter = grains(0.1, sorted(r.uniform(0, 0.08, 7)), 0.01, seed + 12, band=(2000, 7000))
    # The lantern: hits the floor, the glass cracks, it rolls to a stop.
    hit = _lantern(seed + 13, [(0.0, 1.0)], tau=0.1, links=1.2)
    crack = (_band(white(0.1, seed + 14), 3000, 14000) * _env_ad(0.1, 0.0001, 0.003)
             + _modes(0.1, [(3120, 0.03, 1.0), (4710, 0.022, 0.8), (6930, 0.015, 0.6), (8840, 0.01, 0.4)]))
    shards = np.zeros(n_samples(0.3))
    for k, tt in enumerate(sorted(r.uniform(0.005, 0.16, 6))):
        fk = r.uniform(4200, 9000)
        shards += place(0.3, [(tt, _modes(0.05, [(fk, 0.012, 1.0), (fk * 1.41, 0.008, 0.5)]), r.uniform(0.2, 0.6))])
    roll = np.zeros(n_samples(0.42))
    tt, gap, g = 0.0, 0.045, 0.7
    while tt < 0.38 and g > 0.05:
        roll += place(0.42, [(tt, _norm(_lantern(seed + 30 + int(tt * 1000), [(0.0, 1.0)], tau=0.045, links=0.5,
                                                 dur=0.12)), g)])
        tt += gap
        gap *= 1.17
        g *= 0.78
    rumble = _band(pink(0.42, seed + 15), 60, 600) * np.exp(-time_axis(0.42) / 0.12)
    # The blue flame gutters: a flickering hiss and failing puffs.
    tg = time_axis(0.4)
    flick = np.clip(_norm(lowpass(white(0.4, seed + 16), 14, 2)) + 0.3, 0, 1) ** 1.5
    gutter = _band(white(0.4, seed + 17), 900, 3500) * flick * np.exp(-tg / 0.14) * np.clip(tg / 0.02, 0, 1)
    # The card bounces once (up at 0.78) and settles again at 0.90.
    resettle = _thump(0.15, seed + 21, 110, 0.015, drop=0.4, attack=0.001)
    rpaper = _norm(grains(0.08, sorted(r.uniform(0, 0.05, 4)), 0.01, seed + 22, band=(2000, 7000)))
    puffs = place(0.4, [(0.02, _flame(0.15, seed + 18, 0.01, 0.04, 0.3), 0.8),
                        (0.12, _flame(0.12, seed + 19, 0.01, 0.03, 0.3), 0.5),
                        (0.26, _flame(0.1, seed + 20, 0.008, 0.025, 0.4), 0.3)])
    x = place(D, [
        (0.118, blow, 0.7), (0.118, slap, 0.32), (0.12, crump, 0.26), (0.121, rattle, 0.22),
        (0.14, breath, 0.22),
        (0.30, fold, 0.30), (0.30, crease, 0.20), (0.565, topple, 0.20),
        (0.68, pap, 0.45), (0.68, flat, 0.70), (0.682, base, 0.18), (0.69, flutter, 0.10),
        (0.705, hit, 0.32), (0.735, crack, 0.20), (0.737, shards, 0.12),
        (0.78, roll, 0.16), (0.78, rumble, 0.10),
        (0.80, gutter, 0.8), (0.80, puffs, 0.18),
        (0.90, resettle, 0.15), (0.90, rpaper, 0.06),
    ])
    return _finish(x, D, tail=0.08)


# --------------------------------------------------------------------------
# His shadow (Movimento Ombra): he sinks into it, it steps, he rises

@sound("pilgrim_shadow_sink", loudness=-21, wet=0.3, marks=(0.0, 0.27))
def pilgrim_shadow_sink(seed):
    """He sinks into his shadow (the card's own cue takes 0.27 s): the wool
    gathers as he crouches into it, a soft inky down-swell (its band falling
    700 -> 110 Hz, peak 0.15) swallows him, the paper card folds as it goes
    under (a slow cardboard creak and a few crease crackles, heard through
    the ink), it closes flat at 0.27 and the ink closes over him with a soft
    low gulp; on the way down the lantern's globe chimes once, muffled."""
    D = 0.65
    env = env_points(D, [(0, 0), (0.05, 0.35), (0.15, 1.0), (0.3, 0.55), (0.5, 0.12), (D, 0)])
    down = _ink(D, seed, env, _path(D, [(0, 700), (0.15, 420), (0.5, 110)]), q=0.9)
    deep = env_points(D, [(0, 0), (0.12, 0.5), (0.27, 1.0), (0.45, 0.3), (D, 0)])
    low = _band(brown(D, seed + 1), 50, 200, order=3) * deep
    crouch = _cloak(0.2, seed + 2, env_points(0.2, [(0, 0), (0.08, 1.0), (0.2, 0)]), lo=350, hi=900)
    # Under the surface nothing above 1.8 kHz carries.
    fold = lowpass(_creak(0.16, seed + 3, 28, 55, 520, q=1.6), 1400, 2)
    crease = lowpass(_crumple(0.2, seed + 4, length=0.12, rate=120, lo=1500), 1800, 2)
    flap = lowpass(_slap(0.08, seed + 5, 300, 2500, tau=0.008), 1200, 2)
    gulp = _thump(0.2, seed + 6, 95, 0.035, drop=0.25, attack=0.008, lp=240)
    chime = lowpass(_glass(0.4, tau=0.1, attack=0.004), 2600, 2)
    x = place(D, [
        (0.0, crouch, 0.18), (0.0, down, 0.8), (0.0, low, 0.6),
        (0.12, fold, 0.9), (0.13, crease, 0.6), (0.255, flap, 0.5),
        (0.27, gulp, 0.25), (0.17, chime, 0.04),
    ])
    return _finish(x, D, tail=0.08)


@sound("pilgrim_shadow_step", loudness=-24, wet=0.2, marks=(0.0, 0.07))
def pilgrim_shadow_step(seed):
    """One step of his shadow (one every 0.4 s at most, so it must not tire):
    no boots and no card, only the ink slipping a cell along the floor, fast
    at first as the pool is (peak 0.07): a short, soft, airy swish over a dark
    smear of ink, with no attack, gone by 0.3."""
    D = 0.35
    swish = _whoosh(0.3, seed, 320, 950, 400, peak_at=0.24, q=0.9, power=1.5, tone=0.06)
    env = env_points(D, [(0, 0), (0.025, 0.6), (0.07, 1.0), (0.16, 0.4), (0.3, 0.0)])
    smear = _ink(D, seed + 1, env, _path(D, [(0, 380), (0.07, 520), (0.3, 170)]), q=0.8, swirl=0.3)
    air = _band(pink(D, seed + 2), 1500, 4500) * env_points(D, [(0, 0), (0.04, 1.0), (0.12, 0.2), (0.2, 0)])
    x = place(D, [(0.0, swish, 0.7), (0.0, smear, 0.5), (0.0, air, 0.3)])
    return _finish(x, D, tail=0.05)


@sound("pilgrim_shadow_rise", loudness=-20, wet=0.3, marks=(0.0, 0.13, 0.34))
def pilgrim_shadow_rise(seed):
    """He climbs back out of his shadow (the card's own cue: out of the floor
    at 0.13, a small spring, down on its base at 0.34): an inky up-swell (its
    band rising 120 -> 900 Hz, peak 0.12) lets him go, the paper card unfolds
    as it comes up (a cardboard flex creak rising, a few crisp grains, the
    card springing straight at 0.17), then the light thud of the card set
    down on stone at 0.34 (its iron base knocks, the lantern jingles once),
    the cloak settles and the ink stills."""
    D = 0.8
    r = rng(seed)
    env = env_points(D, [(0, 0), (0.06, 0.45), (0.12, 1.0), (0.2, 0.3), (0.32, 0.05), (D, 0)])
    up = _ink(D, seed, env, _path(D, [(0, 120), (0.12, 520), (0.25, 900)]), q=0.9)
    air = _whoosh(0.22, seed + 1, 260, 900, 700, peak_at=0.55, q=0.9, tone=0.05)
    unfold = _creak(0.1, seed + 2, 55, 110, 780, q=2.0)
    flex = grains(0.12, sorted(r.uniform(0, 0.09, 7)), 0.01, seed + 3, band=(1800, 6500))
    spring = _slap(0.06, seed + 4, 900, 6000, tau=0.004)
    thud = _thump(0.2, seed + 5, 115, 0.02, drop=0.5, attack=0.001, lp=380)
    knock = _modes(0.12, [(820, 0.022, 1.0), (1290, 0.015, 0.6), (2010, 0.009, 0.4)])
    tick = _band(white(0.02, seed + 6), 1500, 8000) * _env_ad(0.02, 0.0002, 0.0008)
    jingle = _lantern(seed + 7, [(0.0, 0.6), (0.03, 0.25)], glass=0.3, links=0.6, dur=0.4)
    settle = _cloak(0.2, seed + 8, env_points(0.2, [(0, 0), (0.03, 1), (0.2, 0)]), lo=350, hi=900)
    still = _ink(0.3, seed + 9, env_points(0.3, [(0, 0), (0.05, 1.0), (0.3, 0)]), _path(0.3, [(0, 300), (0.3, 140)]))
    x = place(D, [
        (0.0, up, 0.75), (0.02, air, 0.2),
        (0.1, unfold, 0.6), (0.11, flex, 0.5), (0.17, spring, 0.3),
        (0.34, thud, 0.3), (0.34, knock, 0.13), (0.34, tick, 0.1), (0.345, jingle, 0.16),
        (0.36, settle, 0.1), (0.36, still, 0.12),
    ])
    return _finish(x, D, tail=0.08)


# --------------------------------------------------------------------------
# The rope and the rod (Phase 3): hemp running through his glove, water

def _rope(dur, seed, env, centre=1500.0, q=0.6, rate=260.0):
    """Hemp rope running through his glove: a fibrous rasp (noise through a
    mid band) roughened by stick-slip catches, following `env`, with a few
    fibre ticks."""
    n = n_samples(dur)
    e = pad_to(np.asarray(env, float), dur)
    en = e / (np.max(e) + 1e-9)
    catches = np.abs(lowpass(np.abs(crackle(dur, rate * en + 1, seed, decay=0.0015)), 900, 1))
    texture = 0.25 + 0.75 * _norm(catches) ** 0.7
    body = bandpass(pink(dur, seed + 1) + 0.5 * white(dur, seed + 2), centre, q)
    fib = _band(crackle(dur, 30 + 400 * en, seed + 3, decay=0.0004), 2000, 6000)
    return (_norm(body) * texture + 0.15 * _norm(fib))[:n] * en


def _plip(f0, length, rise=0.6):
    """A drop's tight plip, or a small bubble closing: a short damped sine
    whose pitch rises as it decays (a sharp onset)."""
    t = time_axis(length)
    f = f0 * (1 + rise * t / length)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.clip(t / 0.0008, 0, 1) * np.exp(-t / (length * 0.25))


def _splash(dur, seed, size=1.0, drops=14, spread=0.4):
    """Water broken: a wet burst (noise 250 Hz-6 kHz, its brightest part dying
    first), a few bubbles closing, and drops raining back for `spread` s."""
    r = rng(seed)
    burst = _band(white(dur, seed) + pink(dur, seed + 1), 250, 6000) * _env_ad(dur, 0.002, 0.03 * size)
    burst = sweep_lowpass(burst, 7000, 1500)
    events = []
    for _ in range(drops):
        t0 = 0.02 + spread * r.random() ** 1.6
        drop = _plip(r.uniform(1400, 3800), r.uniform(0.012, 0.025), r.uniform(0.3, 0.9))
        events.append((t0, drop, r.uniform(0.15, 0.45) * (1 - 0.6 * (t0 - 0.02) / spread)))
    for k in range(3):
        events.append((0.008 + 0.03 * k, _plip(r.uniform(380, 900), 0.06, 0.5), 0.5 / (1 + k)))
    return _norm(burst) + place(dur, events)


@sound("pilgrim_lasso_throw", loudness=-19, wet=0.22, marks=(0.0, 0.04, 0.53))
def pilgrim_lasso_throw(seed):
    """LAZZO thrown: his arm lets the loop go at 0.0 in a full round whoosh
    peaking at 0.04 (the cloak flicks with it, the lantern knocks once on its
    chain), then the rope pays out through his glove: a fibrous hemp rasp,
    fast at first and slowing as the loop flies, under the loop's own whistle
    falling away (doppler down, darker as it goes) until it drops over the foe
    at 0.53 (world_lasso_wrap)."""
    D = 0.62
    arm = _whoosh(0.24, seed, 320, 1500, 650, peak_at=0.17, q=1.0, power=1.6, tone=0.25)
    flick = _cloak(0.2, seed + 1, env_points(0.2, [(0, 0), (0.03, 1.0), (0.2, 0)]), lo=400, hi=1400)
    pay = env_points(D, [(0, 0), (0.03, 0.0), (0.06, 1.0), (0.3, 0.55), (0.5, 0.2), (0.56, 0.0), (D, 0.0)])
    rope = _rope(D, seed + 2, pay, centre=1600, q=0.6, rate=320)
    loop = sweep_lowpass(_whoosh(0.5, seed + 3, 2200, 1900, 650, peak_at=0.12, q=1.8, power=1.4, tone=0.55), 9000, 1800)
    lantern = _lantern(seed + 4, [(0.03, 0.6)], glass=0.15, dur=0.3)
    x = place(D, [(0.0, arm, 0.7), (0.0, flick, 0.18), (0.0, rope, 0.4), (0.04, loop, 0.32), (0.0, lantern, 0.12)])
    return _finish(x, D, tail=0.03)


@sound("pilgrim_reel", loudness=-20, wet=0.22, marks=(0.0, 0.1, 0.45))
def pilgrim_reel(seed):
    """CANNA DA PESCA reeled in: he cranks the reel hard, its pawl clicking
    about 26 times a second over the gears' dry whirr (0.0-0.45), the cane
    creaking under the load; the catch breaks the water at 0.10 (a heavy wet
    burst and a gush of drops raining back down to 0.5), the taut line
    singing thin."""
    D = 0.7
    r = rng(seed)
    t = time_axis(D)
    events = []
    tt, k = 0.0, 0
    while tt < 0.45:
        f = r.uniform(2900, 3500)
        click = _modes(0.03, [(f, 0.004, 1.0), (f * 1.53, 0.003, 0.6), (f * 2.4, 0.002, 0.35)], seed=seed + 10 + k)
        events.append((tt, _norm(click), r.uniform(0.55, 1.0)))
        tt += r.uniform(0.034, 0.042)
        k += 1
    pawl = place(D, events)
    turning = env_points(D, [(0, 0), (0.02, 1.0), (0.42, 0.8), (0.47, 0.0), (D, 0.0)])
    gears = _band(white(D, seed + 2), 900, 3200) * (0.5 + 0.5 * np.sin(2 * np.pi * 26 * t) ** 2) * turning
    cane = _creak(0.42, seed + 3, f0=38, f1=62, center=820, q=2.2)
    splash = _splash(0.6, seed + 4, size=1.3, drops=18, spread=0.38)
    sing = _band(white(0.3, seed + 5), 5000, 9000) * _env_ad(0.3, 0.01, 0.08)
    x = place(D, [(0.0, pawl, 0.32), (0.0, _norm(gears), 0.12), (0.02, cane, 0.18), (0.1, splash, 0.75),
                  (0.0, sing, 0.06)])
    return _finish(x, D, tail=0.04)


@sound("pilgrim_catch", loudness=-21, wet=0.2, marks=(0.0,))
def pilgrim_catch(seed):
    """CANNA DA PESCA: the catch lands in his hand at 0.0: a soft wet slap on
    the leather glove (a muffled body under a little splat), a few drops
    falling off it onto the stone, his cloak settling."""
    D = 0.45
    r = rng(seed + 3)
    slap = _slap(0.1, seed, lo=600, hi=5000, tau=0.007)
    body = _thump(0.18, seed + 1, 150, 0.022, drop=0.5, attack=0.001, lp=600, sat=1.5)
    glove = _band(pink(0.1, seed + 2), 400, 1600) * _env_ad(0.1, 0.002, 0.02)
    drops = [(0.05 + 0.25 * r.random() ** 1.3, _plip(r.uniform(1500, 3200), r.uniform(0.012, 0.02), 0.5),
              r.uniform(0.1, 0.3)) for _ in range(6)]
    settle = _cloak(0.2, seed + 4, env_points(0.2, [(0, 0), (0.04, 1), (0.2, 0)]), lo=350, hi=900)
    x = place(D, [(0.0, slap, 0.45), (0.0, body, 0.6), (0.0, glove, 0.25), (0.06, settle, 0.08)] + drops)
    return _finish(x, D, tail=0.03)
