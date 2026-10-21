"""Family `marley`: Bomb Marley and Inondazione (SOUND_SPEC.md).

Two cards of the fifth batch and everything they put on the board. Every recipe
is dry and synthesized here (the build adds the stone hall); the family reuses
the `world` family's materials (water drops, bubbles, blasts, stone ticks,
the fuse) from sfx_world.py and adds two of its own:

- the mirror ball (Bomb Marley): glints. A glint is a tiny ping (a soft sine
  with one inharmonic partial, a few tens of ms) on a note of D Phrygian, high
  up (D5-D8), with a tick of band-passed noise riding it, scattered in time
  like the light of a turning ball; a shimmer is several slightly detuned
  sines wobbling in amplitude. Rising glints = the ball arriving, falling =
  leaving.
- the reggae: one tempo, 60 BPM (a beat is exactly one second), one chord, D
  minor seventh (D F A C, all inside D Phrygian). The organ is additive
  (drawbars 1, 2, 3, 4, 6, 8 of each note, a key click, a Leslie wobble), the
  bass is a round sine with a little drive, the kick a short sine dive, the
  skank a muted guitar chop (Karplus-Strong, short) with an organ chop and a
  chk of noise, the rim a side-stick. `groove_a` is the bass and kick on the
  beat, `groove_b` the rim and the offbeat skank with a dub echo, so a, b, a, b
  is one-drop: bass-kick, rim + chop, bass-kick, rim + chop.
- the flood: moving bands of pink and brown noise for the swell, white noise
  for the foam, _drops and _blub for the bubbles and the rain of drops.

Loudness: the same recipe rules as the world family (peaks at -1.5 dBFS or
lower, dense low-crest bodies so the limiter stays idle). The grooves are made
to be played over and over: quiet, round and never harsh.
"""
import math

import numpy as np

from dsp import *  # noqa: F401,F403
from registry import sound
from sfx_world import (_blast, _blub, _click, _drops, _finish, _fuse, _limit, _moving_band, _moving_lowpass, _norm, _paper,
                       _path, _puff, _smooth, _squash, _stone_chunk, _stone_ticks, _t60, _thud)

# D minor seventh and friends (D Phrygian has no natural third: the F is the minor third)
_D2, _A2 = 73.42, 110.0
_D3, _F3, _A3, _C4 = 146.83, 174.61, 220.0, 261.63
_D4, _F4, _A4, _C5 = 293.66, 349.23, 440.0, 523.25
_D5, _A5, _D6, _A6, _D7 = 587.33, 880.0, 1174.66, 1760.0, 2349.32

# D Phrygian from D5 to C8: the notes the glints are struck on.
_GLINTS = sorted(_D5 * 2 ** (octave + k / 12) for octave in range(3) for k in (0, 1, 3, 5, 7, 8, 10))

_EVENTS = {}


def _put(buf, t0, s, gain=1.0):
    """Adds `s` into `buf` at t0 (seconds), clipped to the buffer."""
    i = int(round(t0 * SR))
    if i >= len(buf):
        return
    e = min(len(buf), i + len(s))
    buf[i:e] += gain * s[:e - i]


def _events(name, *times):
    _EVENTS[name] = tuple(round(float(v), 4) for v in times)


# --------------------------------------------------------------------------
# The mirror ball

def _ping(freq, length, t60, bright=1.0):
    """A tiny glass ping: a sine, one inharmonic partial and a thin high one,
    a 0.4 ms attack (never a click)."""
    t = time_axis(length)
    x = np.sin(2 * np.pi * freq * t)
    if freq * 2.76 < 18000:
        x += 0.45 * bright * np.sin(2 * np.pi * freq * 2.76 * t) * _t60(t, 0.4 * t60)
    if freq * 5.4 < 18000:
        x += 0.18 * bright * np.sin(2 * np.pi * freq * 5.4 * t) * _t60(t, 0.15 * t60)
    return x * np.minimum(1, t / 0.0004) * _t60(t, t60)


def _glitter(duration, times, pos, seed, t60=(0.03, 0.1), tick=0.35):
    """Glints at `times`. `pos(t)` in 0..1 picks the pitch of each (the notes
    of D Phrygian from D5 up to C8, a little scattered); every glint also has a
    tick of high noise riding it, like light snapping off a facet."""
    r = rng(seed)
    out = silence(duration)
    top = len(_GLINTS) - 1
    for t0 in times:
        k = int(round(min(1.0, max(0.0, pos(t0))) * top + r.normal(0, 1.6)))
        f = _GLINTS[min(top, max(0, k))]
        length = r.uniform(*t60)
        g = _ping(f, length * 4.5, length) * r.uniform(0.25, 1.0)
        tk = n_samples(0.006)
        tt = np.arange(tk) / SR
        c = bandpass(r.uniform(-1, 1, tk) * np.exp(-tt / 0.0012), r.uniform(5500, 11000), 1.5)
        c = _norm(c) * tick * r.uniform(0.3, 1.0) * np.max(np.abs(g))
        i = int(t0 * SR)
        if i >= len(out):
            continue
        e = min(len(out), i + len(g))
        out[i:e] += g[:e - i]
        e = min(len(out), i + len(c))
        out[i:e] += c[:e - i]
    return out


def _shimmer(duration, freqs, seed, rate=11.0, depth=0.5, detune=0.004):
    """A ball's shimmer: each note is three slightly detuned sines whose levels
    wobble out of step, so the sum glitters instead of ringing."""
    r = rng(seed)
    n = n_samples(duration)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f in freqs:
        farr = np.broadcast_to(np.asarray(f, dtype=float), (n,))
        for d in (-1, 0, 1):
            ph = r.uniform(0, 2 * np.pi)
            wob = 1 - depth * (0.5 + 0.5 * np.sin(2 * np.pi * rate * r.uniform(0.7, 1.3) * t + r.uniform(0, 6.28)))
            out += wob * np.sin(2 * np.pi * np.cumsum(farr * (1 + d * detune)) / SR + ph)
    return _norm(out)


def _bell(freq, length, t60, bright=1.0):
    """A soft glockenspiel strike: FM-ish partials 1, 2.76, 5.4, 8.9 dying
    faster the higher, a 3 ms attack so it chimes instead of clicking."""
    t = time_axis(length)
    x = np.zeros_like(t)
    for q, a, d in ((1.0, 1.0, 1.0), (2.76, 0.4, 0.5), (5.4, 0.16, 0.28), (8.9, 0.06, 0.15)):
        if freq * q < 18000:
            x += a * bright * np.sin(2 * np.pi * freq * q * t) * _t60(t, t60 * d)
    return x * np.minimum(1, t / 0.003)


# --------------------------------------------------------------------------
# The reggae kit: organ, bass, kick, rim, skank

def _organ(duration, notes, seed, t60=0.8, attack=0.006, leslie=6.2, depth=0.28, vib=0.0025, click=0.25):
    """A drawbar organ chord: harmonics 1, 2, 3, 4, 6 and 8 of every note, a
    Leslie wobble (amplitude and a touch of pitch at ~6 Hz, out of step per
    note) and a soft key click."""
    r = rng(seed)
    n = n_samples(duration)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f in notes:
        wob = r.uniform(0, 6.28)
        am = 1 + depth * np.sin(2 * np.pi * leslie * t + wob)
        fv = f * (1 + vib * np.sin(2 * np.pi * leslie * t + wob + 1.0))
        base = np.cumsum(fv) / SR
        for q, a in ((1, 1.0), (2, 0.75), (3, 0.45), (4, 0.3), (6, 0.18), (8, 0.1)):
            if f * q < 12000:
                out += a * am * np.sin(2 * np.pi * q * base + r.uniform(0, 6.28))
    out = _norm(out)
    env = np.minimum(1, t / attack) * _t60(t, t60)
    kc = n_samples(0.008)
    kk = np.zeros(n)
    kt = np.arange(kc) / SR
    kk[:kc] = bandpass(white(0.008, seed + 1) * np.exp(-kt / 0.0012), 2400, 1.0)
    return out * env + click * 0.3 * _norm(kk)


def _bass(duration, freq, t60, drop=0.06, drive_amt=1.7, attack=0.008):
    """A round dub bass: a sine with a little drive (so its 2nd and 3rd
    harmonics carry it on small speakers), a slight pitch settle on the attack."""
    t = time_axis(duration)
    f = freq * (1 + drop * np.exp(-t / 0.03))
    ph = np.cumsum(f) / SR
    x = np.sin(2 * np.pi * ph) + 0.22 * np.sin(4 * np.pi * ph)
    x = drive(x, drive_amt)
    return lowpass(x, 700, 2) * np.minimum(1, t / attack) * _t60(t, t60)


def _kick(length=0.3, f0=130.0, f1=46.0, tau=0.1, tone=0.03):
    """A soft kick: a sine diving f0 -> f1, a tick of low noise at the start."""
    t = time_axis(length)
    f = f1 + (f0 - f1) * np.exp(-t / tone)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / tau) * np.minimum(1, t / 0.002)
    tick = lowpass(white(length, 21) * np.exp(-t / 0.0025), 1800, 2) * 0.12
    return body + tick


def _rim(seed):
    """A side-stick: a dry wooden tock (two stiff modes near 1.7 and 2.6 kHz),
    a snap of noise and a small hollow body."""
    length = 0.09
    t = time_axis(length)
    snap = _norm(bandpass(white(length, seed) * np.exp(-t / 0.0011), 2300, 1.0))
    modes = np.sin(2 * np.pi * 1720 * t) * np.exp(-t / 0.011) + 0.55 * np.sin(2 * np.pi * 2650 * t) * np.exp(-t / 0.007)
    body = np.sin(2 * np.pi * 430 * t) * np.exp(-t / 0.02)
    return (0.55 * snap + 0.5 * modes + 0.35 * body) * np.minimum(1, t / 0.0004)


def _skank(seed, gain_organ=0.5):
    """The offbeat chop: a muted guitar chord (four Karplus-Strong strings of D
    minor, strummed in 5 ms, damped hard), an organ chop under it and the
    chk of the pick (noise 2-5 kHz). Short: ~0.13 s."""
    length = 0.15
    guitar = np.zeros(n_samples(length))
    for i, f in enumerate((_D4, _A4, _F4 * 2, _D5)):
        s = karplus(f, length, damping=0.975, brightness=0.45, seed=seed + i)
        k = int(i * 0.005 * SR)
        guitar[k:] += s[:len(guitar) - k] * (1.0 - 0.1 * i)
    guitar = _norm(lowpass(guitar, 3500, 1)) * np.exp(-time_axis(length) / 0.06)
    organ = _organ(length, (_D4, _F4, _A4, _C5), seed + 9, t60=0.07, attack=0.003, depth=0.1, click=0.2)
    t = time_axis(length)
    chk = _norm(bandpass(white(length, seed + 10) * np.exp(-t / 0.004), 3200, 0.8)) * np.minimum(1, t / 0.0004)
    return 0.8 * guitar + gain_organ * _norm(organ) + 0.3 * chk


# --------------------------------------------------------------------------
# Water

def _surge(duration, seed, lo, hi, peak_at=0.6, power=1.6):
    """A surge of water: pink noise through a wide band rising lo -> hi with a
    swell that peaks at `peak_at` of the length."""
    x = _moving_band(pink(duration, seed), _path([(0, lo), (duration * peak_at, hi), (duration, hi * 0.7)]), 0.5)
    return _norm(x) * env_swell(duration, peak_at, power)


def _hiss(duration, seed, c0, c1, q=0.6):
    """Steam: white noise through a band sliding c0 -> c1, with turbulence."""
    n = n_samples(duration)
    x = _moving_band(white(duration, seed), _path([(0, c0), (duration, c1)]), q)
    return _norm(x) * (0.6 + 0.4 * _smooth(n, 45.0, seed + 1))


# --------------------------------------------------------------------------
# Cards

@sound("card_bomb_marley", loudness=-19, wet=0.3, rt60=1.2, marks=(0.0, 0.8, 1.1),
       note="the card flicks out of the hand, a fuse spits low (0-0.8) while a mirror ball's glints rise (0.05-1.1, D5 -> D8) over "
            "a high shimmer; a reggae organ bubbles twice (0.8, 0.95: short stabs of D minor seventh) over the bass at 0.8, then "
            "the chord is held at 1.1 with its Leslie wobble until 1.95")
def card_bomb_marley(seed):
    D = 2.0
    t = time_axis(D)
    r = rng(seed)
    flick = _paper(0.05, [0.002, 0.012], seed + 1, lo=2500, hi=7000, lmin=0.006, lmax=0.014)
    fuse = _fuse(0.9, seed + 2) * env_points(0.9, [(0, 0), (0.1, 0.6), (0.8, 1.0), (0.9, 0)])
    dense = random_times(1.15, 55, seed + 4, 0.05, 1.15, envelope=lambda u: 0.25 + 0.75 * u ** 1.3)
    glints = _glitter(D, dense, lambda tt: min(1.0, tt / 1.1), seed + 5)
    shim = _shimmer(1.4, [_D6 * 1.0, _A6, _D7], seed + 6, rate=9.0)
    shim *= env_points(1.4, [(0, 0), (0.7, 0.5), (1.1, 1.0), (1.4, 0.0)])
    stab = lambda s, t60: _norm(_organ(0.5, (_D3, _F3, _A3, _C4, _D4), seed + s, t60=t60, depth=0.18))
    long_chord = _organ(0.9, (_D3, _F3, _A3, _C4, _D4 * 2), seed + 12, t60=0.55, attack=0.01)
    bass = _bass(1.1, _D2, 0.7)
    x = place(D, [(0.0, flick, 0.5), (0.0, fuse, 0.22), (0.0, glints, 0.9), (0.1, shim, 0.14), (0.8, stab(10, 0.09), 0.5),
                  (0.95, stab(11, 0.08), 0.42), (1.1, long_chord, 0.62), (0.8, bass, 0.75), (1.1, bass * 0.55, 0.55)])
    _events("card_bomb_marley", 0.0, 0.8, 0.95, 1.1)
    return _finish(_limit(x, 0.7), D, fade_out=0.12)


@sound("card_flood", loudness=-19, wet=0.25, rt60=0.9, marks=(0.0, 0.7),
       note="the card flicks out, then the water: a surge rises from 0.05 (a wide band climbing 200 -> 2.4 kHz over a swelling low "
            "rumble, bubbles ringing up through it), crests and crashes at 0.7 (a foam burst falling 6 -> 1.5 kHz) and drains "
            "away in froth and falling drops to 1.4")
def card_flood(seed):
    D = 1.4
    C = 0.7
    t = time_axis(D)
    flick = _paper(0.05, [0.002, 0.011], seed + 1, lo=2500, hi=7000, lmin=0.006, lmax=0.014)
    surge = place(D, [(0.05, _surge(0.7, seed + 2, 200, 2400, 0.9, 1.4), 1.0)])
    rumble = _norm(lowpass(brown(D, seed + 3), 220, 2)) * env_points(D, [(0, 0), (0.1, 0.1), (C, 1.0), (1.2, 0.15), (D, 0)])
    # the crash: a splash of white and pink, darkening fast
    cl = 0.7
    tc = time_axis(cl)
    crash = _moving_lowpass(highpass(white(cl, seed + 4) + pink(cl, seed + 5), 200, 2), _path([(0, 6500), (0.15, 2500), (cl, 1500)]))
    crash = _norm(crash) * np.minimum(1, tc / 0.004) * _t60(tc, 0.4)
    # bubbles ring up through the rising water, then drops fall back
    bubbles = silence(D)
    for k, t0 in enumerate(sorted(rng(seed + 6).uniform(0.12, 0.68, 10))):
        b = _blub(math.exp(rng(seed + 20 + k).uniform(math.log(260), math.log(900))), 0.07, 0.9)
        _put(bubbles, t0, b, 0.55)
    rain = _drops(D, 26, C, 0.6, seed + 7)
    froth = _hiss(0.7, seed + 8, 5200, 2200) * env_points(0.7, [(0, 0), (0.04, 1.0), (0.7, 0)])
    x = place(D, [(0.0, flick, 0.45), (0.0, surge, 0.8), (0.0, rumble, 0.55), (C, crash, 1.0), (0.0, bubbles, 0.45),
                  (0.0, _norm(rain), 0.3), (C + 0.03, froth, 0.14)])
    _events("card_flood", 0.0, 0.05, C, 1.0)
    return _finish(_limit(x, 0.7), D, fade_out=0.1)


# --------------------------------------------------------------------------
# The mirror ball's events

@sound("world_marley_ball", loudness=-21, wet=0.3, rt60=1.0, marks=(0.0, 1.6),
       note="the mirror ball comes down on its chain: a shimmer gliding down D7 -> D5 (0.0-1.45) swelling and settling, tiny metal "
            "ticks of the winch that slow from 14 to 3 a second, a soft wind falling, glints scattered over it, and at 1.5 the "
            "ball hangs: a lightly struck D6 chime")
def world_marley_ball(seed):
    D = 1.75
    t = time_axis(D)
    n = len(t)
    glide = _D7 * (_D5 / _D7) ** np.clip(t / 1.45, 0, 1) ** 0.8
    shim = _shimmer(D, [glide, glide * 1.5, glide * 2.0], seed, rate=12.0, depth=0.55)
    shim *= env_points(D, [(0, 0), (0.2, 0.7), (0.9, 1.0), (1.5, 0.35), (D, 0.0)])
    wind = _norm(_moving_band(pink(D, seed + 1), _path([(0, 2400), (1.0, 900), (D, 500)]), 0.6)) * env_swell(D, 0.4, 1.5)
    ticks = silence(D)
    r = rng(seed + 2)
    tt = 0.02
    while tt < 1.45:
        rate = 14.0 - 11.0 * (tt / 1.45)
        c = _click(seed + 100 + int(tt * 1000), length=0.006, tau=0.0007, hp=2500)
        ring = _ping(r.uniform(5200, 8200), 0.04, 0.012)
        _put(ticks, tt, c, r.uniform(0.5, 1.0) * 0.7)
        _put(ticks, tt, ring, r.uniform(0.2, 0.5))
        tt += 1.0 / rate * r.uniform(0.85, 1.15)
    glints = _glitter(D, random_times(D, 22, seed + 3, 0.05, 1.45, envelope=lambda u: 1 - 0.7 * u), lambda x: 1 - x / 1.7, seed + 4)
    hang = place(D, [(1.5, _bell(_D6, 0.25, 0.22), 1.0)])
    x = 0.6 * shim + 0.18 * wind + 0.4 * _norm(ticks) + 0.55 * _norm(glints) + 0.55 * hang
    _events("world_marley_ball", 0.0, 0.5, 0.9, 1.5)
    return _finish(_limit(x, 0.7), D, fade_out=0.1)


@sound("world_marley_warn", loudness=-23, wet=0.1, rt60=0.5, marks=(0.0, 0.11),
       note="a column is warned: two dry woodblock ticks, A5 at 0.0 then D6 at 0.11, short and close to the ear")
def world_marley_warn(seed):
    D = 0.25
    def tick(f, s):
        t = time_axis(0.12)
        body = np.sin(2 * np.pi * f * t) * _t60(t, 0.07) + 0.35 * np.sin(2 * np.pi * f * 2.4 * t) * _t60(t, 0.03)
        body *= np.minimum(1, t / 0.0004)
        return body + 0.5 * _norm(bandpass(white(0.12, s) * np.exp(-t / 0.0015), f * 2.0, 1.2))
    x = place(D, [(0.0, tick(_A5, seed), 0.8), (0.11, tick(_D6, seed + 1), 1.0)])
    _events("world_marley_warn", 0.0, 0.11)
    return _finish(_limit(x, 0.7), D, fade_out=0.05)


@sound("world_marley_bomb", loudness=-19, wet=0.2, rt60=0.8, marks=(0.0, 0.62),
       note="a bomb is thrown down a column: a falling whistle (2.8 kHz -> 700 Hz, swelling, with a little air) from 0.0, and it "
            "lands at 0.62 in a dull iron-and-stone thud, a short rattle of fuse sparks and grit")
def world_marley_bomb(seed):
    D = 0.9
    L = 0.64
    t = time_axis(L)
    f = 2800.0 * (700.0 / 2800.0) ** (t / L) ** 0.9
    whistle = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.3 * np.sin(2 * np.pi * np.cumsum(f * 2.01) / SR)
    whistle *= (0.15 + 0.85 * (t / L) ** 1.3) * np.minimum(1, t / 0.02)
    air = _norm(_moving_band(pink(L, seed), _path([(0, 3500), (L, 1000)]), 0.8)) * (0.1 + 0.9 * (t / L) ** 1.5)
    fuse = _fuse(L, seed + 1) * (0.2 + 0.8 * (t / L))
    land = 0.62
    thud = _thud(0.3, seed + 2, f0=70.0, t60=0.3, lp=450.0, drop=0.8)
    chunk = _stone_chunk(seed + 3, base=420.0, t60=0.06, length=0.25, low=0.6)
    grit = _stone_ticks(0.3, [0.01 + k * 0.03 for k in range(8)], seed + 4, lo=1800, hi=6000, power=1.8)
    x = place(D, [(0.0, _norm(whistle), 0.5), (0.0, air, 0.2), (0.0, fuse, 0.16), (land, _norm(thud), 1.0), (land, chunk, 0.5),
                  (land, _norm(grit), 0.22)])
    _events("world_marley_bomb", 0.0, 0.4, land)
    return _finish(_limit(x, 0.7), D, fade_out=0.08)


@sound("world_marley_blast", loudness=-13, wet=0.35, rt60=1.1, marks=(0.004, 0.06),
       note="the bomb bursts at 0.004: a heavy blast (a pressure front, a falling boom, a stone shatter, debris to 1.3) and, in it, "
            "a dub bass drop: a round sine diving from 200 to D2 at 0.06 and holding, an octave of sub under it, ringing to 1.5")
def world_marley_blast(seed):
    D = 1.5
    b = 0.004
    r = rng(seed)
    low = place(D, [(b, _blast(1.3, seed, f_start=95, f_end=52, t60=1.1, sub=0.3, body=0.9, roar=1.0, front=0.0, boom_len=0.4,
                               rumble_hp=50.0, roar_center=380, punch=1.1, sustain=0.2), 1.0)])
    low = drive(_squash(low, threshold=0.2, ratio=3.0, window=0.02), 1.7)
    lf = 0.04
    tf = time_axis(lf)
    front = _norm(lowpass(white(lf, seed + 3), 7000, 1)) * np.minimum(1, tf / 0.0005) * np.exp(-tf / 0.006)
    st = b + 0.004 + np.sort(r.exponential(0.05, 60))
    shatter = _stone_ticks(D, st[st < 0.4], seed + 1, lo=700, hi=5500, lmin=0.002, lmax=0.012, power=1.4)
    chunks = place(D, [(b + dt, _stone_chunk(seed + 2 + i, base), g) for i, (dt, base, g) in
                       enumerate([(0.012, 520, 1.0), (0.03, 760, 0.7), (0.06, 610, 0.5), (0.1, 900, 0.4)])])
    debris = _stone_ticks(D, random_times(D, 70, seed + 10, 0.25, 1.4, envelope=lambda u: (1 - u) ** 1.6), seed + 11,
                          lo=1400, hi=7500, lmin=0.0015, lmax=0.006, power=1.8)
    # the dub drop: the bass dives onto D2 and rings, an octave of sub under it
    bl = 1.45
    tb = time_axis(bl)
    fb = _D2 + (200.0 - _D2) * np.exp(-tb / 0.05)
    phb = np.cumsum(fb) / SR
    bass = drive(np.sin(2 * np.pi * phb) + 0.25 * np.sin(4 * np.pi * phb), 1.6) * np.minimum(1, tb / 0.004) * _t60(tb, 1.4)
    sub = np.sin(2 * np.pi * np.cumsum(fb * 0.5) / SR) * np.minimum(1, tb / 0.01) * _t60(tb, 1.0)
    bass = lowpass(bass + 0.55 * sub, 600, 2)
    core = _limit(low + place(D, [(b, front, 0.4)]) + 0.2 * _norm(shatter) + 0.25 * _norm(chunks) + place(D, [(0.06, _norm(bass), 0.9)]), 0.7)
    x = core + 0.2 * _norm(debris)
    _events("world_marley_blast", b, 0.06, 0.3, 1.0)
    return _finish(_limit(x, 0.55), D, fade_out=0.1)


@sound("world_marley_safe", loudness=-22, wet=0.25, rt60=0.8, marks=(0.0,),
       note="a character in the light survives the bomb: a bright soft chime at 0.0 (a glockenspiel D6 with A6 a breath later, "
            "ringing 0.5 s) and a few glints")
def world_marley_safe(seed):
    D = 0.45
    x = place(D, [(0.0, _bell(_D6, 0.45, 0.3), 0.9), (0.045, _bell(_A6, 0.4, 0.24), 0.55), (0.0, _bell(_D7, 0.3, 0.12), 0.15),
                  (0.06, _glitter(0.5, [0.0, 0.07, 0.13, 0.2], lambda tt: 0.8, seed), 0.25)])
    _events("world_marley_safe", 0.0, 0.045)
    return _finish(_limit(x, 0.7), D, fade_out=0.08)


@sound("world_marley_lights", loudness=-22, wet=0.25, rt60=0.8, marks=(0.0, 0.5),
       note="the lights swap: a sparkle sweep (glints rising D5 -> D8 from 0.0 to 0.5, a thin band sliding 2.5 -> 10 kHz under "
            "them) and a tiny ping at 0.5")
def world_marley_lights(seed):
    D = 0.65
    times = random_times(0.5, 70, seed, 0.0, 0.5, envelope=lambda u: 0.5 + 0.5 * u)
    glints = _glitter(D, times, lambda tt: min(1.0, tt / 0.5), seed + 1, t60=(0.02, 0.06))
    sweep = _norm(_moving_band(white(D, seed + 2), _path([(0, 2500), (0.5, 10000), (D, 10000)]), 0.8))
    sweep *= env_points(D, [(0, 0), (0.05, 0.5), (0.5, 1.0), (0.6, 0.0), (D, 0.0)])
    x = 0.8 * _norm(glints) + 0.12 * sweep + place(D, [(0.5, _bell(_A6, 0.28, 0.12), 0.35)])
    _events("world_marley_lights", 0.0, 0.5)
    return _finish(_limit(x, 0.7), D, fade_out=0.08)


@sound("world_marley_bonus", loudness=-21, wet=0.15, rt60=0.6, marks=(0.0, 0.075),
       note="+5 seconds: a coin's ding, two bright metal strikes a fifth apart (D6 at 0.0, A6 at 0.075) ringing to 0.4")
def world_marley_bonus(seed):
    D = 0.4
    def coin(f, s):
        r = rng(s)
        t = time_axis(0.4)
        x = np.zeros_like(t)
        for q, a, d in ((1.0, 1.0, 1.0), (2.01, 0.5, 0.55), (3.2, 0.25, 0.3), (4.9, 0.12, 0.18)):
            x += a * np.sin(2 * np.pi * f * q * t + r.uniform(0, 1)) * _t60(t, 0.32 * d)
        return x * np.minimum(1, t / 0.0006) + 0.25 * pad_to(_click(s + 1, length=0.004, tau=0.0004, hp=3500), 0.4)
    x = place(D, [(0.0, coin(_D6, seed), 0.7), (0.075, coin(_A6, seed + 2), 1.0)])
    _events("world_marley_bonus", 0.0, 0.075)
    return _finish(_limit(x, 0.7), D, fade_out=0.06)


@sound("world_marley_end", loudness=-20, wet=0.3, rt60=1.0, marks=(0.0, 0.18, 0.95),
       note="the party ends: the ball is hauled up (a soft up-swish, chain ticks) as a descending sparkle falls over a chord that "
            "slows like a stopped record (D minor, speed 1 -> 0 from 0.18 to 0.93, darkening, a few vinyl crackles) and a last "
            "low thump at 0.95")
def world_marley_end(seed):
    D = 1.3
    t = time_axis(D)
    n = len(t)
    t0, T = 0.18, 0.75
    speed = np.where(t < t0, 1.0, np.clip(1 - (t - t0) / T, 0, 1) ** 1.8)
    ph = np.cumsum(speed) / SR
    chord = np.zeros(n)
    for f, a in ((_D3, 1.0), (_A3, 0.8), (_D4, 0.7), (_F4, 0.5), (_C5, 0.35)):
        for q, h in ((1, 1.0), (2, 0.5), (3, 0.3)):
            chord += a * h * np.sin(2 * np.pi * f * q * ph)
    chord = _norm(chord) * np.minimum(1, t / 0.01) * (np.clip(1 - (t - t0) / T, 0, 1) ** 0.6 * (t >= t0) + (t < t0))
    sp = lambda tt: 1.0 if tt < t0 else max(0.0, 1 - (tt - t0) / T) ** 1.8
    chord = _norm(_moving_lowpass(chord, lambda tt: 500 + 6500 * sp(tt), 2))
    chain = silence(D)
    r = rng(seed)
    tt = 0.02
    while tt < 0.8:
        c = _click(seed + 200 + int(tt * 1000), length=0.006, tau=0.0007, hp=2500)
        _put(chain, tt, c, r.uniform(0.4, 0.9))
        tt += 1 / 11.0 * r.uniform(0.85, 1.15)
    spark = _glitter(D, random_times(D, 50, seed + 1, 0.0, 1.0, envelope=lambda u: 1 - 0.8 * u), lambda x: 1 - x / 1.0, seed + 2)
    up = _norm(_moving_band(pink(D, seed + 3), _path([(0, 400), (0.7, 2200), (D, 2200)]), 0.7)) * env_points(
        D, [(0, 0), (0.3, 0.5), (0.7, 0.0), (D, 0)])
    crack = _norm(crackle(D, 90, seed + 4, decay=0.0004)) * env_points(D, [(0, 0.4), (0.18, 1.0), (0.95, 0.2), (1.1, 0)])
    thump = place(D, [(0.95, _thud(0.3, seed + 5, f0=65.0, t60=0.22, lp=350.0, drop=0.6), 1.0)])
    x = 0.55 * chord + 0.1 * _norm(chain) + 0.55 * _norm(spark) + 0.14 * up + 0.04 * crack + 0.3 * _norm(thump)
    _events("world_marley_end", 0.0, 0.18, 0.6, 0.95)
    return _finish(_limit(x, 0.7), D, fade_out=0.1)


# --------------------------------------------------------------------------
# The groove: one beat each, 60 BPM

@sound("world_marley_groove_a", loudness=-22, wet=0.1, rt60=0.5, marks=(0.0, 0.72),
       note="beat A of the one-drop, exactly one second (60 BPM): a deep round bass note on D2 at 0.0 with a soft kick under it, "
            "ringing on (a dub bass), and a quiet pickup on A2 at 0.72")
def world_marley_groove_a(seed):
    D = 1.0
    bass = _bass(1.0, _D2, 1.5, drop=0.05, drive_amt=2.6)
    pick = _bass(0.28, _A2, 0.2, drop=0.03)
    kick = _kick()
    x = place(D, [(0.0, bass, 0.8), (0.0, kick, 0.75), (0.72, pick, 0.4)])
    _events("world_marley_groove_a", 0.0, 0.72)
    return _finish(_limit(x, 0.8), D, fade_out=0.03)


@sound("world_marley_groove_b", loudness=-23, wet=0.12, rt60=0.3, marks=(0.0, 0.5, 0.73),
       note="beat B of the one-drop, exactly one second: a dry rim click at 0.0 and the offbeat skank at 0.5 (a muted guitar chop "
            "over an organ chop and the pick's chk), its dub echoes falling away at 0.73 and 0.96")
def world_marley_groove_b(seed):
    D = 1.0
    rim = _rim(seed)
    skank = _skank(seed + 1)
    echo1 = lowpass(skank, 3200, 1)
    echo2 = lowpass(skank, 1800, 1)
    x = place(D, [(0.0, rim, 0.9), (0.5, skank, 1.0), (0.73, echo1, 0.34), (0.96, echo2, 0.12)])
    _events("world_marley_groove_b", 0.0, 0.5, 0.73, 0.96)
    return _finish(_limit(x, 0.8), D, fade_out=0.02)


# --------------------------------------------------------------------------
# Inondazione

@sound("world_flood_wave", loudness=-16, wet=0.25, rt60=0.8, marks=(0.0, 1.25),
       note="the wave sweeps across the room: a long swell of filtered noise (pink, a wide band 180 -> 700 -> 260 Hz, a low brown "
            "roll under it, a foam hiss 2.5 -> 5.5 -> 2.5 kHz) breathing slowly, cresting at 1.25, a few bubbles and drops in the "
            "wake, gone by 2.4")
def world_flood_wave(seed):
    D = 2.3
    t = time_axis(D)
    n = len(t)
    swell = env_swell(D, 0.52, 1.7)
    body = _norm(_moving_band(pink(D, seed), _path([(0, 180), (1.25, 700), (D, 260)]), 0.45)) * swell
    roll = _norm(lowpass(brown(D, seed + 1), 220, 2)) * env_swell(D, 0.5, 1.4)
    foam = _norm(_moving_band(white(D, seed + 2), _path([(0, 2500), (1.35, 5500), (D, 2500)]), 0.5))
    foam *= swell ** 2 * (0.55 + 0.45 * _smooth(n, 12.0, seed + 3))
    breath = 0.8 + 0.2 * np.sin(2 * np.pi * 0.85 * t)
    rain = _drops(D, 40, 1.35, 1.0, seed + 4)
    bubbles = silence(D)
    r = rng(seed + 5)
    for t0 in sorted(r.uniform(1.3, 2.0, 8)):
        b = _blub(math.exp(r.uniform(math.log(200), math.log(700))), 0.08, 0.8)
        _put(bubbles, t0, b, 0.5)
    x = (0.85 * body + 0.5 * roll + 0.3 * foam) * breath + 0.25 * _norm(rain) + 0.3 * bubbles
    _events("world_flood_wave", 0.0, 0.7, 1.25, 1.9)
    return _finish(_limit(x, 0.7), D, fade_out=0.3)


@sound("world_flood_splash", loudness=-19, wet=0.2, rt60=0.8, marks=(0.0,),
       note="the wave hits an enemy at 0.0: a heavy wet slap (pink and white through a band falling 6 -> 1.4 kHz, a low whump under "
            "it, the soaked card's paper flap), bubbles bursting and a rain of drops to 0.5")
def world_flood_splash(seed):
    D = 0.55
    t = time_axis(D)
    slap = _moving_lowpass(highpass(white(D, seed) + pink(D, seed + 1), 250, 2), _path([(0, 6000), (0.12, 2000), (D, 1400)]))
    slap = _norm(slap) * np.minimum(1, t / 0.002) * _t60(t, 0.22)
    whump = _norm(_thud(0.25, seed + 2, f0=95.0, t60=0.14, lp=350.0, drop=0.7))
    flap = _norm(_paper(0.12, [0.0, 0.025, 0.06], seed + 3, lo=1500, hi=5000, lmin=0.01, lmax=0.03))
    bubbles = silence(D)
    r = rng(seed + 4)
    for t0 in sorted(r.uniform(0.03, 0.4, 7)):
        b = _blub(math.exp(r.uniform(math.log(280), math.log(1100))), 0.05, 0.8)
        _put(bubbles, t0, b, r.uniform(0.3, 0.7))
    rain = _drops(D, 22, 0.05, 0.45, seed + 5)
    x = place(D, [(0.0, slap, 0.8), (0.0, whump, 0.55), (0.0, flap, 0.2), (0.0, bubbles, 0.4), (0.0, _norm(rain), 0.3)])
    _events("world_flood_splash", 0.0, 0.1, 0.3)
    return _finish(_limit(x, 0.7), D, fade_out=0.08)


@sound("world_flood_steam", loudness=-21, wet=0.2, rt60=0.8, marks=(0.0, 0.03),
       note="a fire is put out: the water hits the embers at 0.0 (a short wet gulp and a dense sizzle of crackle thinning out to "
            "0.5), then a long hiss of steam (a band 7 -> 3 kHz, turbulent) swells at 0.03 and fades by 0.75, a soft puff with it")
def world_flood_steam(seed):
    D = 0.75
    t = time_axis(D)
    hiss = _hiss(D, seed, 7000, 3000) * env_points(D, [(0, 0), (0.03, 0.8), (0.18, 1.0), (0.45, 0.45), (D, 0)])
    sizzle = _norm(highpass(crackle(D, 1400, seed + 1, decay=0.0004), 2500, 2)) * env_points(D, [(0, 1.0), (0.1, 0.8), (0.5, 0.0), (D, 0)])
    gulp = place(D, [(0.0, _blub(190, 0.09, 0.6), 0.8), (0.04, _blub(300, 0.06, 0.8), 0.4)])
    low = _norm(_moving_band(pink(D, seed + 2), _path([(0, 600), (D, 250)]), 0.7)) * env_points(D, [(0, 0), (0.05, 1.0), (0.5, 0.2), (D, 0)])
    puff = place(D, [(0.02, _puff(seed + 3, length=0.4, center=800.0), 1.0)])
    x = 0.55 * hiss + 0.3 * sizzle + 0.45 * gulp + 0.3 * low + 0.35 * puff
    _events("world_flood_steam", 0.0, 0.03, 0.3)
    return _finish(_limit(x, 0.7), D, fade_out=0.1)
