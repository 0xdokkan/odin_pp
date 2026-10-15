"""Family `cards_arms` -- cards of steel, guard and fortune (SOUND_SPEC.md).

Played when the Viandante plays the card. Every sound opens the same way, with
the card leaving his hand: a ~20 ms paper flick (thumb drag, the edge snapping
free, a flutter of the card), seeded per card so no two flicks are alike. Then
the card's effect, built from one shared palette so the family reads as one
hand and one kit:

  steel    whoosh (pink noise through a moving band, a faint whistle riding it,
           a lower body band under it) + crisp cut + the blade's inharmonic
           ring, tuned on D6 / A5
  guard    the ward bell: a Bb-major bell (Bb, D, F: all in D Phrygian) that
           blooms up into pitch, soft attack, detuned doublets and a tremolo
           shimmer; a wooden shield
  impact   pitch-dropping thumps (a body and a thud), wood, iron and stone
           modes, debris grains
  fortune  bone dice on wood, bright gold coins (disk modes) on stone
  time     a clear bell whose shimmer slows (Battle Focus) or comes to a
           standstill and hangs (Movimento Ombra)

Recipes are dry (the build adds the hall, wet 0.25) and end peaking at 0.85,
before the build's loudness normalisation (-19). The marks are the recipes'
own key events (the spec lists none for cards): 0.0 is always the flick.
"""
import math

import numpy as np

from dsp import *  # noqa: F401,F403
from registry import sound

LOUD = -19
WET = 0.25
FLICK = 0.5   # the flick's level against the effect (effect peaks ~0.8-1.0)

# D Phrygian: D, Eb, F, G, A, Bb, C.
D2, D3, A3, D4, A4, BB4 = 73.42, 146.83, 220.0, 293.66, 440.0, 466.16
D5, F5, A5, BB5 = 587.33, 698.46, 880.0, 932.33
D6, F6, A6, BB6, D7, F7 = 1174.66, 1396.91, 1760.0, 1864.66, 2349.32, 2793.83


# --------------------------------------------------------------------------
# Small tools

def _norm(x, peak=1.0):
    m = float(np.max(np.abs(x))) if len(x) else 0.0
    return x * (peak / m) if m > 0 else x


def _ramp(x, attack):
    """Linear onset over `attack` seconds (kills the step of random phases)."""
    k = min(len(x), n_samples(attack)) if attack > 0 else 0
    if k > 1:
        x = x.copy()
        x[:k] *= np.linspace(0, 1, k)
    return x


def _out(x, release=0.08):
    """The recipe's end: a raised-cosine damping over the last `release` s (a
    ring still sounding is stopped like a hand on the metal), then headroom:
    peak 0.85."""
    k = min(len(x), n_samples(release))
    if k > 1:
        x = x.copy()
        x[-k:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, k))
    return _norm(x, 0.85)


def _swell(dur, t_peak, a=1.0, b=2.0, t_end=None):
    """0 -> 1 (raised cosine, power a) at t_peak -> 0 at t_end (power b)."""
    t = time_axis(dur)
    t_end = dur if t_end is None else t_end
    up = np.clip(t / max(t_peak, 1e-4), 0, 1)
    up = (0.5 - 0.5 * np.cos(np.pi * up)) ** a
    down = np.clip((t_end - t) / max(t_end - t_peak, 1e-4), 0, 1) ** b
    return np.where(t < t_peak, up, down)


def _gate(dur, t0, t1, a=0.01, r=0.02):
    """1 between t0 and t1 with linear ramps (a in, r out)."""
    t = time_axis(dur)
    return np.clip((t - t0) / max(a, 1e-4), 0, 1) * np.clip((t1 - t) / max(r, 1e-4), 0, 1)


def _ring(dur, modes, seed, attack=0.0004, beat=0.0, bend=None, phase=None):
    """Damped partials [(freq, tau_s, amp)] (tau: exp time constant; -60 dB at
    ~6.9 tau). Each is split into a slightly detuned doublet (`beat` Hz) so
    metal and bells shimmer instead of sounding like test tones. `bend` is an
    optional per-sample frequency multiplier; `phase` 0 starts every partial
    at zero (a smooth onset for resonances excited by impulses)."""
    r = rng(seed)
    t = time_axis(dur)
    x = np.zeros_like(t)
    cyc = np.cumsum(bend) / SR if bend is not None else t
    for f, tau, amp in modes:
        if f >= SR * 0.45:
            continue
        env = amp * np.exp(-t / max(tau, 1e-4))
        p = r.uniform(0, 2 * np.pi) if phase is None else phase
        x += env * np.sin(2 * np.pi * f * cyc + p)
        if beat:
            b = beat * r.uniform(0.5, 1.5)
            p2 = r.uniform(0, 2 * np.pi) if phase is None else phase
            x += 0.6 * env * np.sin(2 * np.pi * (f * cyc + b * t) + p2)
    return _ramp(x, attack)


def _hits(dur, events, ir):
    """Impulses [(time_s, amp)] through one impulse response."""
    x = np.zeros(n_samples(dur))
    for t0, a in events:
        i = int(round(t0 * SR))
        if 0 <= i < len(x):
            x[i] += a
    if not np.any(x):
        return x
    return convolve(x, ir)[:len(x)]


def _clatter(dur, events, irs, seed):
    """Like _hits, each impulse sent to one of several bodies at random
    (several coins, links, dice: never the same object twice in a row)."""
    r = rng(seed)
    groups = [[] for _ in irs]
    last = -1
    for t0, a in events:
        k = int(r.integers(len(irs)))
        if k == last and len(irs) > 1:
            k = (k + 1) % len(irs)
        groups[k].append((t0, a))
        last = k
    out = np.zeros(n_samples(dur))
    for g, ir in zip(groups, irs):
        if g:
            out += _hits(dur, g, ir)
    return out


# --------------------------------------------------------------------------
# The shared palette

def _flick(seed, snap=1.0):
    """The card leaves the hand (~20 ms): the thumb drags across the paper,
    the edge snaps free, the card flutters, a puff of air. Seeded."""
    r = rng(seed)
    L = r.uniform(0.018, 0.024)
    t = time_axis(L)
    ts = r.uniform(0.0055, 0.0095)                    # the edge snaps free
    on = (t >= ts).astype(float)
    after = np.clip(t - ts, 0, None)
    drag = _norm(bandpass(white(L, seed + 1), r.uniform(2400, 4200), r.uniform(0.9, 1.4)))
    drag *= np.clip(t / ts, 0, 1) ** 2 * (t < ts) * r.uniform(0.22, 0.38)
    sn = np.zeros_like(t)
    for lo, hi, tlo, thi, a in ((1300, 2100, 0.0018, 0.0032, 1.0), (2600, 3700, 0.0014, 0.0024, 0.75),
                                (4300, 6200, 0.0009, 0.0016, 0.6), (7000, 9800, 0.0006, 0.0011, 0.45)):
        f, tau = r.uniform(lo, hi), r.uniform(tlo, thi)
        sn += a * np.exp(-after / tau) * np.cos(2 * np.pi * f * after + r.uniform(-0.5, 0.5)) * on
    click = _norm(highpass(white(L, seed + 2), 3000, 2)) * np.exp(-after / 0.0005) * on
    flutter = _norm(bandpass(white(L, seed + 3), r.uniform(1800, 3500), 1.0))
    flutter *= np.exp(-after / r.uniform(0.003, 0.006)) * on * (0.6 + 0.4 * np.sin(2 * np.pi * r.uniform(180, 320) * after))
    air = _norm(lowpass(white(L, seed + 4), 900, 2)) * np.exp(-((t - ts) / 0.004) ** 2)
    x = drag + snap * (0.55 * _norm(sn) + 0.45 * click) + 0.35 * flutter + 0.18 * air
    return fade(_norm(x), 0.0004, 0.004)


def _whoosh(dur, seed, f0, f1, f2, t_peak, q=1.4, a=1.0, b=2.0, whistle=0.0):
    """Air pushed aside: pink noise through a band that sweeps f0 -> f1 (at
    t_peak, the fastest moment of the swing) -> f2, level swelling with it;
    no hard attack. `whistle` adds a narrow band riding the same path (the
    edge's faint pitch movement)."""
    noise = pink(dur, seed) + 0.12 * white(dur, seed + 1)

    def centre(tt):
        if tt <= t_peak:
            u = 0.5 - 0.5 * math.cos(math.pi * max(tt, 0.0) / t_peak)
            return f0 * (f1 / f0) ** u
        u = min((tt - t_peak) / max(dur - t_peak, 1e-4), 1.0)
        return f1 * (f2 / f1) ** u

    w = (1.0 / q) / 2.355
    x = _norm(stft_filter(noise, lambda f, tt: np.exp(-0.5 * (np.log2(np.maximum(f, 1e-3) / centre(tt)) / w) ** 2)))
    if whistle:
        ww = 0.06 / 2.355
        s = stft_filter(pink(dur, seed + 2), lambda f, tt: np.exp(-0.5 * (np.log2(np.maximum(f, 1e-3) / centre(tt)) / ww) ** 2),
                        frame=2048, hop=256)
        x = x + whistle * _norm(s)
    return _norm(x * _swell(dur, t_peak, a, b))


def _swing(dur, seed, f0, f1, f2, t_peak, body=0.55, whistle=0.18):
    """A blade swing: the bright whoosh plus a body band two octaves lower
    (the arm and the flat of the blade moving air)."""
    hi = _whoosh(dur, seed, f0, f1, f2, t_peak, q=1.5, a=1.4, b=1.6, whistle=whistle)
    lo = _whoosh(dur, seed + 7, f0 / 3.2, f1 / 3.2, f2 / 3.2, t_peak, q=1.2, a=1.4, b=1.6)
    return _norm(hi + body * lo)


_STEEL = (1.0, 1.506, 2.171, 2.632, 3.345, 4.071, 4.836, 5.702, 6.62)


def _steel(dur, base, seed, tau=0.1, count=8, slope=0.5):
    """A blade's ring: inharmonic partials, the high ones dying first (it
    darkens as it decays)."""
    r = rng(seed)
    modes = [(base * q * (1 + r.uniform(-0.006, 0.006)), tau / (1 + 0.55 * i), 1 / (1 + slope * i))
             for i, q in enumerate(_STEEL[:count])]
    return _norm(_ring(dur, modes, seed + 1, beat=1.6))


def _iron(dur, base, seed, tau=0.08, count=7):
    """Thicker iron (a hammer head, a hook, a gauntlet plate): the same kind
    of inharmonic set, lower and duller, with a struck click."""
    t = time_axis(dur)
    ring = _norm(_ring(dur, metal_modes(base, count, 1.0, tau, seed), seed + 1, beat=2.0))
    click = _norm(bandpass(white(dur, seed + 2), base * 5, 0.7)) * np.exp(-t / 0.0012)
    return _norm(ring + 0.5 * click)


def _cut(seed, dur=0.08):
    """The edge biting through: a crisp burst (sub-ms attack, 2-8 kHz, the
    brightest part dying first), a mid body and a few torn fibres; gently
    saturated so the bite is dense rather than a bare spike."""
    r = rng(seed)
    t = time_axis(dur)
    burst = _norm(lowpass(bandpass(white(dur, seed), 4200, 0.55), 9000, 2)) * np.exp(-t / 0.01)
    body = _norm(bandpass(white(dur, seed + 1), r.uniform(1500, 2200), 1.0)) * np.exp(-t / 0.02)
    tear = grains(dur, sorted(r.uniform(0.003, 0.05, 8)), 0.006, seed + 2, band=(1500, 5000))
    x = _norm(burst + 0.55 * body + 0.4 * _norm(tear))
    return _ramp(_norm(drive(x, 1.8)), 0.0006)


def _thump(dur, seed, f0=120.0, f1=55.0, drop=0.03, tau=0.035, lp=500.0, noise=0.5, ntau=None):
    """A blunt body blow: a sine whose pitch drops f0 -> f1 plus low noise."""
    t = time_axis(dur)
    freq = f1 + (f0 - f1) * np.exp(-t / drop)
    tone = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t / tau)
    nz = _norm(lowpass(white(dur, seed), lp, 2)) * np.exp(-t / (ntau or tau * 0.6))
    return _ramp(_norm(tone + noise * nz), 0.0012)


def _wood(dur, base, seed, tau=0.03, click=0.3):
    """Wood: 4 low modes (2.6x, 4.1x, 5.9x) dying within ~0.2 s."""
    r = rng(seed)
    t = time_axis(dur)
    modes = [(base * q * (1 + r.uniform(-0.03, 0.03)), tau / (1 + 0.7 * i), 1 / (1 + 0.5 * i))
             for i, q in enumerate((1.0, 2.62, 4.13, 5.9))]
    k = _norm(_ring(dur, modes, seed + 1, attack=0.0003))
    c = _norm(bandpass(white(dur, seed + 2), base * 6, 0.8)) * np.exp(-t / 0.0015)
    return _norm(k + click * c)


def _stone(dur, seed, n=14, lo=250.0, hi=3500.0, tau=(0.005, 0.03)):
    """Stone: dense, very short modes."""
    r = rng(seed)
    modes = [(math.exp(r.uniform(math.log(lo), math.log(hi))), r.uniform(*tau), r.uniform(0.3, 1.0)) for _ in range(n)]
    return _norm(_ring(dur, modes, seed + 1, attack=0.0002))


# Bell partials. The ward bell is rooted on Bb with a major third (D) and a
# fifth (F): consonant and hopeful, every partial in D Phrygian. The D bell
# has the minor third (F) and fifth (A) of a real bell on D.
_WARD = ((0.5, 1.5, 0.22), (1.0, 1.0, 1.0), (1.26, 0.7, 0.3), (1.498, 0.6, 0.36), (2.0, 0.5, 0.4),
         (2.52, 0.36, 0.14), (3.0, 0.3, 0.12), (4.0, 0.22, 0.07))
_BELL_D = ((0.5, 1.5, 0.2), (1.0, 1.0, 1.0), (1.189, 0.7, 0.35), (1.498, 0.55, 0.28), (2.0, 0.5, 0.42),
           (2.378, 0.35, 0.16), (2.997, 0.28, 0.14), (4.0, 0.2, 0.07))
_BELL_CLEAR = ((0.5, 1.4, 0.18), (1.0, 1.0, 1.0), (2.0, 0.6, 0.35), (2.997, 0.45, 0.16), (4.0, 0.3, 0.07))


def _bell(dur, f, seed, partials, tau=0.3, attack=0.02, trem_rate=5.0, trem_depth=0.12, beat=1.0, bloom=0.0):
    """Bell / ward partials with a soft attack (`attack` = rise time constant)
    and a shimmer (detuned doublets + tremolo; trem_rate may be an array).
    `bloom` starts the partials that fraction flat and lets them rise into
    pitch over ~40 ms (a ward rising)."""
    t = time_axis(dur)
    bend = 1 - bloom * np.exp(-t / 0.035) if bloom else None
    x = _ring(dur, [(f * q, tau * dm, a) for q, dm, a in partials], seed, attack=0.0, beat=beat, bend=bend)
    x = x * (1 - np.exp(-t / max(attack, 1e-4)))
    trem = 1 + trem_depth * np.cos(2 * np.pi * phase_of(trem_rate, n=len(t)))   # starts at its crest
    return _norm(x * trem)


_COIN = ((1.0, 1.0, 1.0), (1.73, 0.75, 0.75), (2.33, 0.55, 0.6), (3.0, 0.4, 0.3), (3.91, 0.3, 0.35), (4.11, 0.28, 0.2))


def _coin(base, seed, tau=0.07, dur=0.3):
    """A gold coin struck: a thin disk's bright inharmonic modes + a tick."""
    r = rng(seed)
    t = time_axis(dur)
    modes = [(base * q * (1 + r.uniform(-0.01, 0.01)), tau * dm * r.uniform(0.8, 1.2), a * r.uniform(0.7, 1.0))
             for q, dm, a in _COIN]
    x = _norm(_ring(dur, modes, seed + 1, attack=0.0001, beat=3.0))
    tick = _norm(highpass(white(dur, seed + 2), 5000, 2)) * np.exp(-t / 0.0005)
    return _norm(x + 0.4 * tick)


def _die(seed, dur=0.14, table=True):
    """A bone die: stiff tiny modes (2.6-7.6 kHz, a few ms), a hard tick; on a
    wooden table the board answers low."""
    r = rng(seed)
    t = time_axis(dur)
    modes = [(r.uniform(2600, 3400), 0.006, 1.0), (r.uniform(4200, 5200), 0.004, 0.7), (r.uniform(6200, 7600), 0.003, 0.5)]
    x = _norm(_ring(dur, modes, seed + 1, attack=0.0001))
    x = x + 0.5 * _norm(highpass(white(dur, seed + 2), 2000, 2)) * np.exp(-t / 0.0008)
    if table:
        x = x + 0.9 * _wood(dur, r.uniform(200, 250), seed + 3, tau=0.028, click=0.0)
    return _norm(x)


def _links(seed, k=6, lo=1700.0, hi=4800.0, tau=0.02):
    """Several small iron chain links (one impulse response each)."""
    r = rng(seed)
    irs = []
    for j in range(k):
        base = r.uniform(lo, hi)
        modes = [(base * q * r.uniform(0.98, 1.02), tau * dm * r.uniform(0.7, 1.3), a)
                 for q, dm, a in ((1.0, 1.0, 1.0), (1.47, 0.7, 0.6), (2.09, 0.5, 0.5), (2.56, 0.4, 0.3), (3.2, 0.3, 0.2))]
        irs.append(_norm(_ring(0.12, modes, seed + 10 + j, attack=0.0001)))
    return irs


def _creak(dur, seed, rate0, rate1, bands, t0=0.0, t1=None, jitter=0.15, tau=0.006, lp=4500.0):
    """Stick-slip friction (green wood fibres, leather): a train of slips whose
    rate is the creak's pitch, each ringing the material's resonances (smooth
    onsets, so it creaks rather than clicks)."""
    r = rng(seed)
    t1 = dur if t1 is None else t1
    events = []
    t = t0
    while True:
        u = min(max((t - t0) / max(t1 - t0, 1e-4), 0.0), 1.0)
        rate = rate0 * (rate1 / rate0) ** u
        t += (1.0 / rate) * (1 + jitter * r.uniform(-1, 1))
        if t >= t1:
            break
        events.append((t, r.uniform(0.55, 1.0)))
    ir = _ring(0.06, [(f, tau * r.uniform(0.7, 1.3), a) for f, a in bands], seed + 1, attack=0.001, phase=0.0)
    return lowpass(_hits(dur, events, _norm(ir)), lp, 2)


def _cloth(dur, seed, t0, t1, rate=120.0, grain=0.022, band=(350, 3000)):
    """Cloth rustle: overlapping band-passed grains, swelling over t0..t1."""
    times = random_times(dur, rate, seed, start=t0, end=t1, envelope=lambda u: math.sin(math.pi * u) ** 0.7)
    return grains(dur, times, grain, seed + 1, band=band, gain_jitter=0.6)


def _paper(dur, seed, t0, t1, rate=150.0):
    """A little paper crumple: 6-18 ms grains 1.5-8 kHz (the game's signature)."""
    a = grains(dur, random_times(dur, rate, seed, start=t0, end=t1), 0.006, seed + 1, band=(1500, 8000), gain_jitter=0.7)
    b = grains(dur, random_times(dur, rate * 0.4, seed + 2, start=t0, end=t1), 0.018, seed + 3, band=(1500, 6000), gain_jitter=0.7)
    return a + 0.6 * b


def _blow(dur, seed, sub=(110.0, 50.0), thud=(230.0, 110.0), tau=0.06, sub_w=0.8):
    """A heavy blunt impact: a sub body (pitch drop), a 100-300 Hz thud that
    carries it on small speakers, and a crunchy midrange bite."""
    t = time_axis(dur)
    body = _thump(dur, seed, f0=sub[0], f1=sub[1], drop=0.025, tau=tau, lp=380, noise=0.6)
    thud_ = _thump(dur, seed + 1, f0=thud[0], f1=thud[1], drop=0.015, tau=tau * 0.45, lp=900, noise=0.8)
    crunch = _norm(bandpass(white(dur, seed + 2), 1500, 0.8)) * np.exp(-t / 0.008)
    # A soft saturation: a massive blow is dense, not a bare spike (and it
    # keeps the crest under the build's -1 dBFS ceiling).
    return _norm(drive(_norm(highpass(sub_w * body + 0.75 * thud_ + 0.3 * crunch, 38, 2)), 1.7))


def _guard_core(dur, seed):
    """The guard cards' ward: an airy rise into the ward bell (Bb4, blooming
    up into pitch) as the wooden shield is set with a thump at 0.11."""
    rise = _whoosh(0.1, seed + 5, 380, 2100, 1700, t_peak=0.088, q=1.2, a=1.6, b=1.0, whistle=0.25)
    bell = _bell(dur - 0.095, BB4, seed + 20, _WARD, tau=0.2, attack=0.016, trem_rate=5.5, trem_depth=0.14,
                 beat=1.2, bloom=0.025)
    return place(dur, [
        (0.022, rise, 0.4),
        (0.11, _wood(0.25, 165, seed + 10, tau=0.032, click=0.35), 0.42),
        (0.11, _thump(0.3, seed + 11, f0=150, f1=80, drop=0.02, tau=0.028, lp=700, noise=0.45), 0.42),
        (0.095, bell, 0.7),
    ])


# --------------------------------------------------------------------------
# Steel

@sound("card_strike", loudness=LOUD, wet=WET, marks=(0.0, 0.16))
def card_strike(seed):
    """A short blade slash: a fast whoosh (bright band + body band) peaking
    into a crisp cut at 0.16, a faint ring of the blade (D6)."""
    dur = 0.55
    x = place(dur, [
        (0.0, _flick(seed), FLICK),
        (0.04, _swing(0.22, seed + 10, 900, 3400, 1800, t_peak=0.12), 0.75),
        (0.16, _cut(seed + 20), 0.62),
        (0.16, _steel(0.39, D6, seed + 30, tau=0.07), 0.2),
    ])
    return _out(x, 0.08)


@sound("card_cross_slash", loudness=LOUD, wet=WET, marks=(0.0, 0.15, 0.37))
def card_cross_slash(seed):
    """Two crossing slashes: the first rises into a cut at 0.15 (ring D6), the
    second sweeps back the other way, lower, and lands at 0.37 (ring A5): the
    answer, a fourth below."""
    dur = 0.8
    x = place(dur, [
        (0.0, _flick(seed), FLICK),
        (0.04, _swing(0.19, seed + 10, 1000, 3800, 2400, t_peak=0.11), 0.65),
        (0.15, _cut(seed + 20), 0.55),
        (0.15, _steel(0.65, D6, seed + 30, tau=0.08), 0.15),
        (0.25, _swing(0.21, seed + 11, 2800, 2300, 900, t_peak=0.12, body=0.7), 0.72),
        (0.37, _cut(seed + 21), 0.65),
        (0.37, _steel(0.43, A5, seed + 31, tau=0.1), 0.2),
    ])
    return _out(x, 0.1)


@sound("card_heavy_blow", loudness=LOUD, wet=WET, marks=(0.0, 0.36))
def card_heavy_blow(seed):
    """A hammer wind-up (the leather grip tightens with a short creaking rasp,
    a slow low whoosh) and a massive blunt impact at 0.36 (sub body + thud +
    crunch, a dull iron clank), the card's paper crumpling just after the
    transient, then the stun: a thin beating ring (D6 over A6) that rises out
    of the hall's tail from 0.40, peaks at 0.55 and fades."""
    dur = 0.9
    # ~13 slips at 90-150 /s: they fuse into one creak instead of knocks.
    grip = _creak(dur, seed + 5, 90, 150, [(420, 1.0), (950, 0.6), (1900, 0.3)], t0=0.05, t1=0.17,
                  jitter=0.35, tau=0.005)
    grip *= _gate(dur, 0.05, 0.17, 0.03, 0.03)
    windup = _whoosh(0.32, seed + 10, 160, 700, 380, t_peak=0.29, q=1.1, a=1.8, b=3.0, whistle=0.12)
    dz = 0.5
    td = time_axis(dz)
    vib = 1 + 0.004 * np.sin(2 * np.pi * 4.2 * td)
    daze = sine(D6 * vib, n=len(td)) + 0.8 * sine(D6 * 1.0045 * vib, n=len(td)) + 0.3 * sine(A6 * vib, n=len(td))
    daze = _norm(daze) * _swell(dz, 0.15, a=1.0, b=1.2)
    # The crumple sits in 2-6 kHz, where the blow leaves room, for ~40 ms.
    crumple = _paper(0.06, seed + 23, 0.0, 0.04, 320)
    crumple = _norm(lowpass(highpass(crumple, 2000, 2), 6000, 2)) * _gate(0.06, 0.0, 0.05, 0.001, 0.012)
    x = place(dur, [
        (0.0, _flick(seed), FLICK),
        (0.0, _norm(grip), 0.22),
        (0.05, windup, 0.5),
        (0.36, _blow(0.5, seed + 20, sub=(105, 56), thud=(250, 115), tau=0.065, sub_w=0.5), 1.0),
        (0.36, _iron(0.45, 420, seed + 22, tau=0.09), 0.22),
        (0.365, crumple, 0.35),
        (0.40, daze, 0.17),
    ])
    return _out(x, 0.05)


@sound("card_sundering_blow", loudness=LOUD, wet=WET, marks=(0.0, 0.05, 0.36, 0.52))
def card_sundering_blow(seed):
    """Two dice rattled in a cupped hand (three shakes from 0.05, four bodies
    so no two contacts match), then a stone-cracking hit at 0.36: a sharp
    crack transient on the mark, a lighter blow into dense stone modes and a
    fracture crackle; a second crack runs through the stone (its density
    rising from 0.41) and snaps where it ends, at 0.52; a low grinding groan
    and falling grit and pebbles (four stones)."""
    dur = 0.85
    r = rng(seed + 1)
    shake = []
    for s0 in (0.05, 0.12, 0.19):
        for k in range(int(r.integers(5, 8))):
            shake.append((s0 + min(r.exponential(0.012), 0.04), r.uniform(0.35, 1.0)))
    dice = [lowpass(_die(seed + 40 + j, table=False), 7000, 2) for j in range(4)]
    rattle = _clatter(dur, sorted(shake), dice, seed + 2)
    cup = sum(place(dur, [(s0, _norm(bandpass(white(0.05, seed + 3 + i), 500, 0.8)) * np.exp(-time_axis(0.05) / 0.008), 1.0)])
              for i, s0 in enumerate((0.05, 0.12, 0.19)))
    hit = 0.36
    crack = _ramp(_norm(highpass(white(0.02, seed + 70), 1200, 2)) * np.exp(-time_axis(0.02) / 0.002), 0.0002)
    ct = time_axis(0.3)
    frac = crackle(0.3, 6000 * np.exp(-ct / 0.05), seed + 5, decay=0.0006)
    frac = _norm(bandpass(frac, 2500, 0.6))
    # The second crack: 0.41 -> 0.52, ever denser, and it snaps where it ends.
    rl = 0.11
    ct2 = time_axis(rl)
    run = crackle(rl, 500 + 3500 * (ct2 / rl) ** 2, seed + 6, decay=0.0005)
    run = _norm(bandpass(run, 1800, 0.7)) * np.clip((rl - ct2) / 0.008, 0, 1) * (0.4 + 0.6 * ct2 / rl)
    snap = _norm(bandpass(white(0.03, seed + 7), 2500, 0.5)) * np.exp(-time_axis(0.03) / 0.002)
    snap = _norm(_ramp(snap, 0.0002) + 0.6 * _stone(0.03, seed + 72, n=10, lo=1200, hi=6000, tau=(0.002, 0.009)))
    groan = _norm(bandpass(brown(0.3, seed + 8), 160, 0.9)) * _swell(0.3, 0.06, a=1.0, b=1.5)
    debris_t = random_times(dur, 140, seed + 9, start=hit + 0.04, end=0.8, envelope=lambda u: (1 - u) ** 2)
    debris = grains(dur, debris_t, 0.009, seed + 10, band=(1500, 6000), gain_jitter=0.7)
    stones = [_stone(0.05, seed + 60 + 2 * j, n=8, lo=900, hi=5000, tau=(0.002, 0.008)) for j in range(4)]
    pebbles = _clatter(dur, [(tt, r.uniform(0.2, 1.0)) for tt in debris_t[::3]], stones, seed + 13)
    x = place(dur, [
        (0.0, _flick(seed), FLICK),
        (0.0, _norm(rattle), 0.55),
        (0.0, cup, 0.1),
        (hit, crack, 0.8),
        (hit, _blow(0.45, seed + 20, sub=(105, 48), thud=(260, 120), tau=0.07, sub_w=0.5), 0.6),
        (hit, _stone(0.3, seed + 21, n=24, lo=200, hi=5000, tau=(0.006, 0.05)), 0.85),
        (hit, frac, 0.7),
        (hit + 0.05, run, 0.5),
        (hit + 0.16, snap, 0.7),
        (hit + 0.02, groan, 0.3),
        (0.0, _norm(debris), 0.22),
        (0.0, _norm(pebbles), 0.16),
    ])
    return _out(x, 0.06)


@sound("card_fate_strike", loudness=LOUD, wet=WET, marks=(0.0, 0.05, 0.265, 0.38))
def card_fate_strike(seed):
    """A single die rolled across wood (first bounce 0.05, bounces shrinking,
    tumbles over its edges, settles tock-tock at 0.265 and rests in the clear),
    then the fated strike at 0.38: a slash and a struck D bell that rings on.
    The die's faces (four bone bodies) and the board's knocks (three short
    wood bodies, no pitch) vary from contact to contact."""
    dur = 0.9
    r = rng(seed + 1)
    ev = [(0.05, 1.0), (0.104, 0.62), (0.146, 0.45), (0.18, 0.34), (0.205, 0.26)]
    tt = 0.222
    while tt < 0.255:
        ev.append((tt, r.uniform(0.08, 0.2) * (1 - (tt - 0.22) / 0.1)))
        tt += r.uniform(0.022, 0.034)
    ev += [(0.265, 0.3), (0.276, 0.1)]
    die = _clatter(dur, ev, [_die(seed + 40 + j, table=False) for j in range(4)], seed + 2)
    table = _clatter(dur, ev, [_wood(0.1, b, seed + 50 + j, tau=0.009, click=0.25) for j, b in enumerate((185, 225, 270))],
                     seed + 3)
    strike = 0.38
    bell = _bell(dur - strike, D5, seed + 30, _BELL_D, tau=0.13, attack=0.002, trem_rate=4.5, trem_depth=0.1)
    x = place(dur, [
        (0.0, _flick(seed), FLICK),
        (0.0, _norm(die), 0.5),
        (0.0, _norm(table), 0.3),
        (strike - 0.08, _swing(0.12, seed + 20, 1100, 3600, 2200, t_peak=0.08), 0.55),
        (strike, _cut(seed + 21), 0.55),
        (strike, _steel(0.5, D6, seed + 31, tau=0.08), 0.14),
        (strike, bell, 0.62),
    ])
    return _out(x, 0.12)


# --------------------------------------------------------------------------
# Guard

@sound("card_guard", loudness=LOUD, wet=WET, marks=(0.0, 0.11))
def card_guard(seed):
    """A ward rises (an airy rise with a faint whistle) into a solid, hopeful
    bell partial (the ward bell, Bb4 with D and F, blooming up into pitch)
    while a wooden shield is set with a thump at 0.11."""
    dur = 0.75
    x = _guard_core(dur, seed) + place(dur, [(0.0, _flick(seed), FLICK)])
    return _out(x, 0.15)


@sound("card_purifying_guard", loudness=LOUD, wet=WET, marks=(0.0, 0.11, 0.19))
def card_purifying_guard(seed):
    """The guard's ward plus a cleansing shimmer from 0.19: clean high pings
    rising through Bb major (D6 F6 Bb6 D7 F7) over a soft sparkle of air."""
    dur = 0.85
    pings = []
    for i, f in enumerate((D6, F6, BB6, D7, F7)):
        ping = _bell(0.42, f, seed + 50 + i, _BELL_CLEAR[1:4], tau=0.13, attack=0.006, trem_rate=7.0, trem_depth=0.2, beat=2.0)
        pings.append((0.19 + 0.045 * i, fade(ping, 0.0, 0.03), 0.22))
    wl = 0.5
    tw = time_axis(wl)
    wash = _norm(bandpass(pink(wl, seed + 60), 7500, 0.8)) * _swell(wl, 0.16, a=1.0, b=2.0) * (1 + 0.35 * np.sin(2 * np.pi * 11 * tw))
    x = _guard_core(dur, seed) + place(dur, [(0.0, _flick(seed), FLICK), (0.17, wash, 0.06)] + pings)
    return _out(x, 0.15)


@sound("card_thorn_coat", loudness=LOUD, wet=WET, marks=(0.0, 0.06, 0.52))
def card_thorn_coat(seed):
    """Bramble vines creak and tighten: two stick-slip pulls (pitch rising as
    they tighten), twig rustle, sharp thorny clicks thickening into a final
    squeeze at 0.52."""
    dur = 0.8
    r = rng(seed + 1)
    fibre = [(520, 1.0), (1150, 0.7), (2400, 0.45), (3900, 0.2)]
    c1 = _creak(dur, seed + 2, 38, 70, fibre, t0=0.06, t1=0.31) * _swell(dur, 0.2, a=1.0, b=1.0, t_end=0.31)
    c2 = _creak(dur, seed + 3, 60, 125, fibre, t0=0.29, t1=0.6, tau=0.005) * _gate(dur, 0.29, 0.6, 0.12, 0.06)
    squeeze = _creak(dur, seed + 4, 150, 190, [(700, 1.0), (1600, 0.6), (3200, 0.3)], t0=0.5, t1=0.6, tau=0.004)
    squeeze *= _gate(dur, 0.5, 0.6, 0.015, 0.04)
    rustle = grains(dur, random_times(dur, 70, seed + 5, start=0.06, end=0.56), 0.012, seed + 6, band=(900, 4000))
    clicks = random_times(dur, 30, seed + 8, start=0.08, end=0.49, envelope=lambda u: 0.35 + 0.65 * u)
    clicks += sorted(r.uniform(0.5, 0.6, 8))
    twigs = [lowpass(_wood(0.04, r.uniform(1700, 3200), seed + 20 + j, tau=0.004, click=0.0), 7000, 2)
             + 0.5 * _norm(bandpass(white(0.04, seed + 25 + j), 4500, 1.0)) * np.exp(-time_axis(0.04) / 0.0008) for j in range(4)]
    thorns = _clatter(dur, [(c, r.uniform(0.5, 1.0)) for c in clicks], twigs, seed + 7)
    x = place(dur, [
        (0.0, _flick(seed), FLICK),
        (0.0, _norm(c1), 0.6),
        (0.0, _norm(c2), 0.7),
        (0.0, _norm(squeeze), 0.4),
        (0.0, _norm(rustle), 0.18),
        (0.0, _norm(thorns), 0.75),
    ])
    return _out(x, 0.1)


@sound("card_afterimage", loudness=LOUD, wet=WET, marks=(0.0, 0.11, 0.24, 0.37, 0.48, 0.61))
def card_afterimage(seed):
    """A ghostly whoosh (peak 0.11, a breathy whistle riding it), then the same
    motion repeats four times every 0.13 s, each fainter, thinner (a touch
    higher, shorter) and darker."""
    dur = 0.75
    base = _whoosh(0.17, seed + 10, 520, 2300, 900, t_peak=0.08, q=1.2, a=1.3, b=1.6, whistle=0.45)
    events = [(0.0, _flick(seed), FLICK), (0.04, base, 0.85)]
    for k in range(1, 5):
        # A small speed-up (thinner, shorter) under a steep, falling lowpass:
        # echo centroids ~1.9 -> 1.7 -> 1.45 -> 1.25 kHz (each one darker).
        ghost = lowpass(resample(base, 1 + 0.015 * k), 4800 / 1.7 ** k, 3)
        events.append((0.04 + 0.13 * k, _norm(ghost), 0.85 * 0.52 ** k))
    return _out(place(dur, events), 0.04)


def _frozen_bell(dur, f, seed, partials, tau=0.3, hold=0.08, still=0.05, stop=0.06, attack=0.003, trem_rate=6.0,
                 trem_depth=0.18, beat=1.2):
    """A bell whose time stops: struck, it rings on its own clock for `hold`
    s, then that clock slows (time constant `stop`) to `still` of its speed,
    and with it the decay, the tremolo and the beating of its doublets: the
    shimmer comes to a standstill and the ring hangs, unnaturally even, until
    the recipe lets it go."""
    r = rng(seed)
    t = time_axis(dur)
    rate = still + (1 - still) * np.exp(-np.maximum(t - hold, 0) / stop)
    clock = np.cumsum(rate) / SR
    x = np.zeros_like(t)
    for q, dm, a in partials:
        fq = f * q
        if fq >= SR * 0.45:
            continue
        env = a * np.exp(-clock / (tau * dm))
        b = beat * r.uniform(0.5, 1.5)
        x += env * np.sin(2 * np.pi * fq * t + r.uniform(0, 2 * np.pi))
        # The doublet's detune runs on the bell's clock: the beating stops too.
        x += 0.6 * env * np.sin(2 * np.pi * (fq * t + b * clock) + r.uniform(0, 2 * np.pi))
    x = x * (1 - np.exp(-t / max(attack, 1e-4)))
    trem = 1 + trem_depth * np.cos(2 * np.pi * trem_rate * clock)   # starts at its crest
    return _norm(x * trem)


@sound("card_shadow_step", loudness=LOUD, wet=WET, marks=(0.0, 0.03, 0.25))
def card_shadow_step(seed):
    """Movimento Ombra: the card leaves the hand, a dark whoosh sinks from
    0.03 (its band falling 2 kHz -> 170 Hz, a body band two octaves under it)
    over a low glide from D3 down to D2, and at 0.25, as the world's colours
    finish draining, a D bell is struck with a faint crystal frost on top
    (D7): their shimmer and beating slow to a standstill and the ring hangs,
    still (time stops), then lets go."""
    dur = 0.9
    sink = _whoosh(0.38, seed + 10, 2000, 800, 170, t_peak=0.09, q=1.1, a=1.3, b=1.3, whistle=0.15)
    body = _whoosh(0.4, seed + 11, 500, 230, 70, t_peak=0.1, q=0.9, a=1.3, b=1.3)
    lo = 0.6
    g = glide(D3, D2, lo)
    fall = lowpass(sine(g, n=n_samples(lo)) + 0.35 * sine(2 * g, n=n_samples(lo)), 500, 2)
    fall = _norm(fall) * _swell(lo, 0.12, a=1.0, b=1.6)
    ring = 0.25
    bell = _frozen_bell(dur - ring, D5, seed + 20, _BELL_D, tau=0.3, hold=0.08, still=0.05, stop=0.06, attack=0.003,
                        trem_rate=6.5, trem_depth=0.2, beat=1.4)
    frost = _frozen_bell(dur - ring, D7, seed + 21, _BELL_CLEAR[1:], tau=0.2, hold=0.08, still=0.05, stop=0.06,
                         attack=0.002, trem_rate=9.0, trem_depth=0.3, beat=2.5)
    x = place(dur, [
        (0.0, _flick(seed), FLICK),
        (0.03, sink, 0.75),
        (0.03, body, 0.3),
        (0.05, fall, 0.22),
        (ring, bell, 0.7),
        (ring, frost, 0.18),
    ])
    return _out(x, 0.2)


@sound("card_counter_rune", loudness=LOUD, wet=WET, marks=(0.0, 0.05, 0.15, 0.25, 0.37))
def card_counter_rune(seed):
    """A rune carved in stone: three scratching strokes of an iron point
    (0.05, 0.15, 0.25; a gritty band with stick-slip chatter, a stone tap on
    each bite; each stroke bites hard and lifts off, its band falling as the
    point drags), then it is lit at 0.37: a soft whoomp and a low glowing hum
    (D2 D3 A3 D4, slowly beating and breathing), dimming at the end."""
    dur = 0.85
    r = rng(seed + 1)
    events = [(0.0, _flick(seed), FLICK)]
    for i, (s0, L) in enumerate(((0.05, 0.075), (0.15, 0.065), (0.25, 0.085))):
        tl = time_axis(L)
        nz = _norm(white(L, seed + 10 + i))
        grit = crackle(L, 2600, seed + 20 + i, decay=0.0004)
        slip = r.uniform(45, 70)
        chatter = 0.5 + 0.5 * np.abs(np.sin(np.pi * phase_of(slip * (1 + 0.2 * np.sin(2 * np.pi * 7 * tl)), n=len(tl))))
        f_hi = r.uniform(3900, 4500)
        stroke = sweep_bandpass(0.6 * nz + grit, f_hi, f_hi * 0.62, q=0.9) * chatter
        # The point's pressure: a fast bite, then a long lift-off.
        press = np.clip(tl / 0.004, 0, 1) * (0.3 + 0.7 * (1 - tl / L) ** 1.5) * np.clip((L - tl) / 0.012, 0, 1)
        stroke = _norm(_norm(stroke) * press)
        events += [(s0, stroke, 0.9), (s0, _stone(0.06, seed + 30 + i, n=10, lo=400, hi=4000, tau=(0.003, 0.012)), 0.45)]
    lit = 0.37
    hd = dur - lit
    th = time_axis(hd)
    hum = np.zeros_like(th)
    for f, a in ((D2, 0.55), (D3, 1.0), (A3, 0.45), (D4, 0.32), (A4, 0.1)):
        for d in (-0.3, 0.35):
            hum += a * np.sin(2 * np.pi * f * (1 + d / 146.83) * th + r.uniform(0, 2 * np.pi))
    # A light drive only: harder, it grows F# harmonics (outside D Phrygian).
    hum = drive(_norm(hum) * 0.6, 1.2) * (1 + 0.12 * np.sin(2 * np.pi * 3.1 * th))
    hum = _norm(lowpass(hum, 1400, 2)) * np.clip(th / 0.09, 0, 1) ** 2 * np.clip((hd - th) / 0.25, 0, 1)
    whoomp = _norm(bandpass(pink(0.2, seed + 40), 260, 0.8)) * _swell(0.2, 0.03, a=1.0, b=2.0)
    events += [(lit, whoomp, 0.6), (lit, hum, 0.62)]
    return _out(place(dur, events), 0.02)


@sound("card_battle_focus", loudness=LOUD, wet=WET, marks=(0.0, 0.42))
def card_battle_focus(seed):
    """A deep slow breath of air (broad, unvoiced bands with the 3-8 kHz
    turbulence that makes noise read as air, darkening as it swells), a single
    clear D5 bell at 0.42 whose shimmer slows down (time slows), a low swell
    sinking under it."""
    dur = 0.9
    bd = 0.42
    br = pink(bd, seed + 10) + 0.35 * white(bd, seed + 11)
    # Wide bands off the vowel positions (no F1/F2 peaks: a breath, not "haa").
    br = formant(br, [(500, 0.7, 1.0), (1600, 0.8, 0.55), (3600, 0.8, 0.4)])
    br = _norm(br) + 0.35 * _norm(bandpass(white(bd, seed + 12), 5500, 0.5))
    br = sweep_lowpass(highpass(br, 150, 2), 9000, 3000)
    breath = _norm(br) * _swell(bd, 0.31, a=1.6, b=1.2)
    ring = 0.42
    bl = dur - ring
    bell = _bell(bl, D5, seed + 20, _BELL_CLEAR, tau=0.13, attack=0.002, trem_rate=glide(6.0, 1.2, bl), trem_depth=0.2, beat=0.8)
    lo = 0.48
    sink = sine(glide(D2, 64.0, lo), n=n_samples(lo)) + 0.4 * sine(glide(D3, 128.0, lo), n=n_samples(lo))
    sink = _norm(sink) * _swell(lo, 0.12, a=1.0, b=1.5)
    x = place(dur, [
        (0.0, _flick(seed), FLICK),
        (0.04, breath, 0.55),
        (ring, bell, 0.75),
        (0.38, sink, 0.14),
    ])
    return _out(x, 0.12)


@sound("card_calculated_risk", loudness=LOUD, wet=WET, marks=(0.0, 0.05, 0.45))
def card_calculated_risk(seed):
    """Cards riffled (0.05-0.36: ~45 paper flaps, fastest in the middle, a
    flutter of air, the halves meeting), then one flicked away at 0.45 with a
    light whoosh flying off."""
    dur = 0.7
    r = rng(seed + 1)
    times = []
    tt = 0.05
    while tt < 0.36:
        u = (tt - 0.05) / 0.31
        times.append(tt)
        tt += (1 / (95 + 85 * math.sin(math.pi * u))) * r.uniform(0.75, 1.25)
    flaps = grains(dur, times, 0.004, seed + 2, band=(1500, 7000), gain_jitter=0.5)
    slaps = [_norm(bandpass(white(0.006, seed + 3 + j), r.uniform(2200, 4200), 0.9)) * np.hanning(n_samples(0.006)) for j in range(3)]
    slaps = _clatter(dur, [(t0 + 0.0015, r.uniform(0.4, 1.0)) for t0 in times], slaps, seed + 6)
    flutter = _norm(bandpass(pink(dur, seed + 7), 900, 0.7)) * _gate(dur, 0.05, 0.37, 0.05, 0.05)
    meet = _norm(bandpass(white(0.06, seed + 8), 800, 0.8)) * np.exp(-time_axis(0.06) / 0.01)
    away = _whoosh(0.18, seed + 9, 4200, 3000, 1500, t_peak=0.03, q=1.6, a=1.0, b=1.5)
    x = place(dur, [
        (0.0, _flick(seed), FLICK),
        (0.0, _norm(flaps), 0.62),
        (0.0, _norm(slaps), 0.55),
        (0.0, flutter, 0.12),
        (0.365, meet, 0.3),
        (0.45, _flick(seed + 50, snap=1.2), 0.72),
        (0.465, away, 0.3),
    ])
    return _out(x, 0.05)


# --------------------------------------------------------------------------
# Body and iron

@sound("card_shove", loudness=LOUD, wet=WET, marks=(0.0, 0.17))
def card_shove(seed):
    """A firm two-handed shove: cloth gathers (0.04-0.17), both palms land at
    0.17 / 0.18 (a 10 ms flam of body thumps + muffled slaps, with
    flesh-and-cloth noise in each thump), the cloth compresses, a little
    paper crumple, a short push drag."""
    dur = 0.6
    gather = _cloth(dur, seed + 1, 0.04, 0.17, rate=130)
    swish = _norm(bandpass(pink(0.16, seed + 2), 500, 0.7)) * _swell(0.16, 0.11, a=1.5, b=1.0)
    slap = [_norm(bandpass(white(0.04, seed + 3 + j), 1400, 0.6)) * np.exp(-time_axis(0.04) / 0.005) for j in range(2)]
    press = _cloth(dur, seed + 5, 0.17, 0.25, rate=220, grain=0.015, band=(400, 2500))
    drag = _norm(bandpass(pink(0.2, seed + 6), 350, 0.8)) * _swell(0.2, 0.05, a=1.0, b=1.5)
    x = place(dur, [
        (0.0, _flick(seed), FLICK),
        (0.0, _norm(gather), 0.32),
        (0.04, swish, 0.3),
        (0.17, _thump(0.35, seed + 10, f0=150, f1=70, drop=0.02, tau=0.03, lp=700, noise=1.0, ntau=0.03), 0.85),
        (0.18, _thump(0.35, seed + 11, f0=140, f1=66, drop=0.02, tau=0.03, lp=700, noise=1.0, ntau=0.03), 0.7),
        (0.17, slap[0], 0.42),
        (0.18, slap[1], 0.34),
        (0.0, _norm(press), 0.24),
        (0.0, _norm(_paper(dur, seed + 7, 0.18, 0.26)), 0.15),
        (0.17, drag, 0.22),
    ])
    return _out(x, 0.05)


@sound("card_dash", loudness=LOUD, wet=WET, marks=(0.0, 0.05, 0.21))
def card_dash(seed):
    """Shield first: a ward click at 0.05 (a tick + a short ward-bell blip),
    then a fast rushing whoosh peaking at 0.21 with a low rush under it."""
    dur = 0.6
    tick = _norm(highpass(white(0.02, seed + 1), 3500, 2)) * np.exp(-time_axis(0.02) / 0.0007)
    blip = _bell(0.22, BB5, seed + 2, _WARD[1:6], tau=0.05, attack=0.001, trem_rate=9.0, trem_depth=0.1, beat=2.0)
    rush = _whoosh(0.36, seed + 10, 450, 2600, 700, t_peak=0.13, q=0.9, a=1.6, b=1.4, whistle=0.12)
    low = _whoosh(0.34, seed + 11, 120, 380, 150, t_peak=0.12, q=1.0, a=1.6, b=1.4)
    x = place(dur, [
        (0.0, _flick(seed), FLICK),
        (0.05, tick, 0.5),
        (0.05, blip, 0.32),
        (0.08, rush, 0.9),
        (0.085, low, 0.4),
    ])
    return _out(x, 0.06)


@sound("card_grappling_hook", loudness=LOUD, wet=WET, marks=(0.0, 0.05, 0.31, 0.58))
def card_grappling_hook(seed):
    """A chain flung (whirl whoosh + links rattling 0.05-0.30), the iron hook
    bites at 0.31 (iron ring + a crunching thump), slack links fall, the chain
    is hauled in (links clacking faster, the hook creaking) and snaps taut at
    0.58 (every link at once, a low iron ring, the foe's weight)."""
    dur = 0.9
    r = rng(seed + 1)
    links = _links(seed + 2)
    fly = []
    tt = 0.06
    while tt < 0.3:
        u = (tt - 0.06) / 0.24
        fly.append((tt, r.uniform(0.3, 1.0) * math.sin(math.pi * u) ** 0.6 * (0.7 + 0.3 * math.sin(2 * math.pi * 11 * tt))))
        tt += r.exponential(1 / 75)
    slack = [(0.33 + r.uniform(0, 0.09), r.uniform(0.15, 0.5)) for _ in range(6)]
    haul = []
    tt = 0.44
    while tt < 0.575:
        u = (tt - 0.44) / 0.135
        haul.append((tt, r.uniform(0.4, 0.9) * (0.5 + 0.5 * u)))
        tt += 1 / (25 * (110 / 25) ** u) * r.uniform(0.8, 1.2)
    chain = _clatter(dur, sorted(fly + slack + haul), links, seed + 3)
    taut = sum(_hits(dur, [(0.58 + 0.0015 * j, 1.0)], ir) for j, ir in enumerate(links))
    creak = _creak(dur, seed + 4, 70, 95, [(700, 1.0), (1500, 0.6), (3100, 0.3)], t0=0.45, t1=0.6, tau=0.006)
    creak *= _gate(dur, 0.45, 0.6, 0.04, 0.02)
    whirl = _whoosh(0.27, seed + 10, 600, 1900, 1200, t_peak=0.15, q=1.3, a=1.2, b=1.5, whistle=0.1)
    x = place(dur, [
        (0.0, _flick(seed), FLICK),
        (0.05, whirl, 0.45),
        (0.0, _norm(chain), 0.5),
        (0.31, _iron(0.4, 950, seed + 20, tau=0.06), 0.65),
        (0.31, _thump(0.25, seed + 21, f0=190, f1=95, drop=0.015, tau=0.02, lp=2500, noise=0.8), 0.55),
        (0.0, _norm(creak), 0.22),
        (0.0, _norm(taut), 0.6),
        (0.58, _iron(0.32, 330, seed + 22, tau=0.09), 0.35),
        (0.58, _thump(0.3, seed + 23, f0=130, f1=65, drop=0.02, tau=0.03, lp=600, noise=0.5), 0.45),
    ])
    return _out(x, 0.08)


@sound("card_titan_grip", loudness=LOUD, wet=WET, marks=(0.0, 0.2, 0.45))
def card_titan_grip(seed):
    """A gauntlet clenches: the leather creaks as it tightens (a stick-slip
    rasp rising 80 -> 160 /s over a dark friction bed), the iron finger plates
    click shut one by one and the fist closes with a clank at 0.20, a last
    tight squeeze of leather; then a heavy throw whoosh peaking around 0.45
    with a flap of cloth."""
    dur = 0.85
    r = rng(seed + 1)
    # ~18 slips: they fuse into a creak whose pitch rises as it tightens.
    leather = _creak(dur, seed + 2, 80, 160, [(380, 1.0), (820, 0.7), (1700, 0.35)], t0=0.05, t1=0.21,
                     jitter=0.35, tau=0.005, lp=3500)
    bed = _norm(bandpass(brown(dur, seed + 6), 800, 0.7)) * _gate(dur, 0.05, 0.21, 0.04, 0.02)
    leather = (_norm(leather) + 0.25 * bed) * _gate(dur, 0.05, 0.215, 0.04, 0.02)
    plates = [_iron(0.06, r.uniform(2000, 3200), seed + 10 + j, tau=0.012, count=5) for j in range(3)]
    fingers = _clatter(dur, [(c, r.uniform(0.5, 1.0)) for c in (0.075, 0.105, 0.13, 0.155, 0.177)], plates, seed + 3)
    squeeze = _creak(dur, seed + 4, 140, 220, [(450, 1.0), (1000, 0.6)], t0=0.2, t1=0.26, tau=0.004, lp=3000)
    squeeze *= _gate(dur, 0.2, 0.26, 0.005, 0.04)
    throw = _whoosh(0.48, seed + 30, 140, 620, 200, t_peak=0.2, q=1.0, a=1.6, b=1.6, whistle=0.12)
    flap = _cloth(dur, seed + 5, 0.36, 0.56, rate=90, grain=0.018)
    x = place(dur, [
        (0.0, _flick(seed), FLICK),
        (0.0, _norm(leather), 0.5),
        (0.0, _norm(fingers), 0.3),
        (0.2, _iron(0.3, 620, seed + 20, tau=0.06), 0.5),
        (0.2, _thump(0.2, seed + 21, f0=160, f1=90, drop=0.015, tau=0.015, lp=900, noise=0.6), 0.4),
        (0.0, _norm(squeeze), 0.25),
        (0.27, throw, 0.95),
        (0.0, _norm(flap), 0.15),
    ])
    return _out(x, 0.08)


# --------------------------------------------------------------------------
# Fortune: gold coins (Scopa)

def _spill(dur, seed, starts, bounces=(2, 4), tau=0.06, base=(2700, 4100)):
    """Coins dropped on stone: each lands (a coin ring + a small stone tick
    with a lower contact knock under it, so the stone has some weight), then
    bounces with shrinking gaps and level."""
    r = rng(seed)
    out = np.zeros(n_samples(dur))
    bases = np.linspace(base[0], base[1], len(starts))
    r.shuffle(bases)
    for i, (t0, a) in enumerate(starts):
        ev = [(t0, a)]
        gap, amp, tt = r.uniform(0.03, 0.055), a, t0
        for _ in range(int(r.integers(bounces[0], bounces[1] + 1))):
            tt += gap
            amp *= r.uniform(0.35, 0.55)
            gap *= r.uniform(0.55, 0.75)
            ev.append((tt, amp))
        out += _hits(dur, ev, _coin(bases[i], seed + 10 + i, tau=tau))
        tick = _norm(bandpass(white(0.02, seed + 30 + i), 2200, 0.8)) * np.exp(-time_axis(0.02) / 0.0012)
        knock = _ramp(_norm(bandpass(white(0.02, seed + 50 + i), r.uniform(850, 1150), 1.0)) * np.exp(-time_axis(0.02) / 0.002), 0.0003)
        out += place(dur, [(t0, tick, 0.3 * a), (t0, knock, 0.45 * a)])
    return out


@sound("card_sei_denari", loudness=LOUD, wet=WET, marks=(0.0, 0.06))
def card_sei_denari(seed):
    """Six gold coins spilled on stone from 0.06: bright clinks, bounces,
    coin-on-coin chinks and a short settling chatter."""
    dur = 0.7
    r = rng(seed + 1)
    starts = [(0.06, 1.0), (0.074, 0.8), (0.09, 0.9), (0.107, 0.7), (0.126, 0.8), (0.152, 0.65)]
    coins = _spill(dur, seed + 2, starts)
    chinks = _clatter(dur, [(r.uniform(0.07, 0.22), r.uniform(0.15, 0.4)) for _ in range(8)],
                      [_coin(f, seed + 40 + j, tau=0.03) for j, f in enumerate((3300, 4400, 5200))], seed + 3)
    settle = []
    tt = 0.27
    while tt < 0.45:
        settle.append((tt, 0.2 * (0.45 - tt) / 0.18 + 0.03))
        tt += 1 / (25 + 60 * (tt - 0.27) / 0.18)
    settle = _clatter(dur, settle, [_coin(f, seed + 70 + 3 * j, tau=0.04) for j, f in enumerate((3400, 3750, 4100))], seed + 4)
    x = place(dur, [(0.0, _flick(seed), FLICK), (0.0, _norm(coins), 0.85), (0.0, chinks, 0.25), (0.0, settle, 0.3)])
    return _out(x, 0.1)


@sound("card_sette_denari", loudness=LOUD, wet=WET, marks=(0.0, 0.06, 0.7))
def card_sette_denari(seed):
    """A bigger handful: seven coins spilled from 0.06 (more bounces, denser),
    then the flourish: one coin spins down on its edge, its chatter speeding
    up, and settles with a last bright ring at 0.70."""
    dur = 0.85
    r = rng(seed + 1)
    starts = [(0.06, 1.0), (0.07, 0.85), (0.083, 0.9), (0.097, 0.75), (0.112, 0.85), (0.13, 0.7), (0.155, 0.8)]
    coins = _spill(dur, seed + 2, starts, bounces=(3, 5))
    chinks = _clatter(dur, [(r.uniform(0.07, 0.26), r.uniform(0.15, 0.45)) for _ in range(12)],
                      [_coin(f, seed + 40 + j, tau=0.03) for j, f in enumerate((3300, 4400, 5200, 6100))], seed + 3)
    spin = []
    tt = 0.31
    while tt < 0.688:
        u = (tt - 0.31) / 0.378
        spin.append((tt, (0.35 + 0.4 * math.sin(math.pi * min(u * 1.3, 1.0))) * (1 - 0.6 * u)))
        tt += 1 / (14 * (75 / 14) ** u)
    spinner = _hits(dur, spin, _coin(3900, seed + 60, tau=0.05))
    last = _coin(3900, seed + 61, tau=0.045, dur=0.15)
    x = place(dur, [(0.0, _flick(seed), FLICK), (0.0, _norm(coins), 0.85), (0.0, chinks, 0.25),
                    (0.0, _norm(spinner), 0.32), (0.7, last, 0.42)])
    return _out(x, 0.04)


# --------------------------------------------------------------------------
# The player's charges (Phase 2)

@sound("card_deflect", loudness=LOUD, wet=WET, marks=(0.0, 0.12, 0.27))
def card_deflect(seed):
    """Deflect: the buckler snapped up (an airy rise peaking at 0.11), its
    iron rings as it is set at 0.12 (a low clank and thump, a steel shimmer
    on A5), then at 0.27 the glance it will give: a crisp ping (D6) and a
    bright whoosh that turns away and falls (3.4 -> 0.9 kHz), the blow sent
    back."""
    dur = 0.75
    rise = _whoosh(0.1, seed + 10, 420, 2000, 1500, t_peak=0.088, q=1.2, a=1.6, b=1.0, whistle=0.2)
    away = _whoosh(0.24, seed + 40, 3400, 2800, 900, t_peak=0.035, q=1.6, a=1.0, b=1.3, whistle=0.45)
    x = place(dur, [
        (0.0, _flick(seed), FLICK),
        (0.02, rise, 0.42),
        (0.12, _iron(0.5, 610, seed + 20, tau=0.12), 0.5),
        (0.12, _thump(0.25, seed + 21, f0=170, f1=90, drop=0.02, tau=0.025, lp=700, noise=0.4), 0.3),
        (0.12, _steel(0.5, A5, seed + 22, tau=0.1, count=6), 0.22),
        (0.27, _cut(seed + 30, dur=0.05), 0.3),
        (0.27, _steel(0.45, D6, seed + 31, tau=0.07), 0.42),
        (0.28, away, 0.5),
    ])
    return _out(x, 0.12)


@sound("card_coffin", loudness=LOUD, wet=WET, marks=(0.0, 0.06, 0.3, 0.42, 0.5, 0.58))
def card_coffin(seed):
    """Feretro: a coffin lid of old wood creaks open from 0.06 (stick-slip
    friction slowing down through the plank's resonances) and drops back on
    its hinge at 0.30 (a hollow knock, a low thump), then three arrows are
    drawn out of it, at 0.42, 0.50 and 0.58: each the dry knock of its shaft
    on the rim, its iron head's tick and the hiss of its fletching."""
    dur = 0.85
    creak = _creak(0.26, seed + 10, 38, 22, [(310, 1.0), (720, 0.6), (1650, 0.35)], t0=0.0, t1=0.24, jitter=0.2, tau=0.008)
    creak = _norm(creak) * _swell(0.26, 0.08, a=1.0, b=1.2)
    events = [(0.0, _flick(seed), FLICK), (0.06, creak, 0.55),
              (0.30, _wood(0.35, 128, seed + 20, tau=0.06, click=0.4), 0.7),
              (0.30, _thump(0.3, seed + 21, f0=140, f1=70, drop=0.02, tau=0.04, lp=500, noise=0.5), 0.45)]
    r = rng(seed + 2)
    for k, t0 in enumerate((0.42, 0.50, 0.58)):
        shaft = _wood(0.12, r.uniform(520, 640), seed + 30 + k, tau=0.012, click=0.5)
        tick = _iron(0.12, r.uniform(2400, 2900), seed + 40 + k, tau=0.02, count=4)
        hiss = _norm(bandpass(white(0.07, seed + 50 + k), 5200, 0.9)) * _swell(0.07, 0.015, a=1.0, b=1.5)
        events += [(t0, shaft, 0.4), (t0 + 0.004, tick, 0.18), (t0 - 0.02, hiss, 0.16)]
    return _out(place(dur, events), 0.06)


@sound("card_fate_dice", loudness=LOUD, wet=WET, marks=(0.0, 0.05, 0.27, 0.34))
def card_fate_dice(seed):
    """Dado del Destino: one bone die rolled across wood (first bounce 0.05,
    bounces shrinking, tumbling, settling at 0.27), then fate is sealed at
    0.34: a low D bell (D4, a bell's minor third) struck softly and a crystal
    shimmer (A6) rising over it, beating slowly as it hangs."""
    dur = 1.0
    r = rng(seed + 1)
    ev = [(0.05, 1.0), (0.1, 0.6), (0.14, 0.44), (0.172, 0.32), (0.198, 0.24)]
    tt = 0.215
    while tt < 0.255:
        ev.append((tt, r.uniform(0.08, 0.18) * (1 - (tt - 0.21) / 0.1)))
        tt += r.uniform(0.02, 0.032)
    ev += [(0.27, 0.28), (0.281, 0.09)]
    die = _clatter(dur, ev, [_die(seed + 40 + j, table=False) for j in range(4)], seed + 2)
    table = _clatter(dur, ev, [_wood(0.1, b, seed + 50 + j, tau=0.009, click=0.25) for j, b in enumerate((180, 220, 265))],
                     seed + 3)
    seal = 0.34
    bell = _bell(dur - seal, D4, seed + 30, _BELL_D, tau=0.32, attack=0.012, trem_rate=3.5, trem_depth=0.12, beat=0.8)
    shimmer = _bell(dur - seal - 0.04, A6, seed + 31, _BELL_CLEAR[1:3], tau=0.22, attack=0.03, trem_rate=6.0,
                    trem_depth=0.3, beat=2.0)
    x = place(dur, [
        (0.0, _flick(seed), FLICK),
        (0.0, _norm(die), 0.5),
        (0.0, _norm(table), 0.3),
        (seal, bell, 0.62),
        (seal + 0.04, shimmer, 0.14),
    ])
    return _out(x, 0.15)


def _drop(dur, f0, rise, tau):
    """A drop's tight plip, or a small bubble closing: a damped sine whose
    pitch rises as it decays (sharp onset)."""
    t = time_axis(dur)
    f = f0 * (1 + rise * t / tau)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / tau) * np.clip(t / 0.0008, 0, 1)


@sound("card_venom_blade", loudness=LOUD, wet=WET, marks=(0.0, 0.07, 0.26, 0.36))
def card_venom_blade(seed):
    """Lama Velenosa: a dagger drawn from its leather sheath (a short bright
    scrape from 0.07, the blade ringing free on D6), then poison runs down its
    edge: a drip at 0.26 (a tight liquid plip) and a faint sizzle as the venom
    bites the steel, two small bubbles closing from 0.36."""
    dur = 0.75
    draw_l = 0.14
    draw = _norm(sweep_bandpass(white(draw_l, seed + 10), 2600, 5200, q=1.4)) * _swell(draw_l, 0.1, a=1.2, b=1.0)
    leather = _norm(bandpass(pink(draw_l, seed + 11), 900, 0.9)) * _swell(draw_l, 0.04, a=1.0, b=2.0)
    sizzle_l = 0.32
    ts = time_axis(sizzle_l)
    sizzle = crackle(sizzle_l, 900 * np.exp(-ts / 0.1) + 20, seed + 30, decay=0.0004)
    sizzle = _norm(bandpass(sizzle, 4800, 0.8)) * _swell(sizzle_l, 0.03, a=1.0, b=1.6)
    x = place(dur, [
        (0.0, _flick(seed), FLICK),
        (0.07, draw, 0.32),
        (0.07, leather, 0.2),
        (0.2, _steel(0.5, D6, seed + 20, tau=0.08), 0.36),
        (0.26, _drop(0.08, 900, 0.9, 0.012), 0.42),
        (0.27, sizzle, 0.14),
        (0.36, _drop(0.06, 620, 0.12, 0.014), 0.2),
        (0.41, _drop(0.06, 760, 0.12, 0.011), 0.16),
    ])
    return _out(x, 0.08)


# --------------------------------------------------------------------------
# The rope and the rod (Phase 3)

def _hemp(dur, seed, t0, t1, rate=260.0, centre=1500.0, q=0.6, rough=0.75):
    """Hemp rope running over itself or through a glove between t0 and t1: a
    fibrous rasp (pink and white noise through a mid band, roughened by
    stick-slip catches about `rate` a second), swelling in and fading out,
    with a few fibre ticks."""
    env = _gate(dur, t0, t1, a=max(0.004, (t1 - t0) * 0.25), r=max(0.006, (t1 - t0) * 0.45))
    catches = np.abs(lowpass(np.abs(crackle(dur, rate * env + 1.0, seed, decay=0.0015)), 900, 1))
    texture = (1 - rough) + rough * _norm(catches) ** 0.7
    body = _norm(bandpass(pink(dur, seed + 1) + 0.5 * white(dur, seed + 2), centre, q))
    ticks = grains(dur, random_times(dur, rate * 0.2, seed + 3, start=t0, end=t1), 0.004, seed + 4, band=(1800, 5500))
    return _norm(body * texture * env) + 0.25 * _norm(ticks)


def _pawl(seed, base):
    """A reel's pawl ticking over its gear: a small stiff steel tick."""
    modes = [(base, 0.004, 1.0), (base * 1.53, 0.003, 0.6), (base * 2.41, 0.002, 0.35)]
    return _norm(_ring(0.03, modes, seed, attack=0.0001))


@sound("card_lasso", loudness=LOUD, wet=WET, marks=(0.0, 0.04, 0.16, 0.22))
def card_lasso(seed):
    """Lazzo: the coil of hemp shaken loose off his shoulder (a fibrous rasp
    from 0.03, the coils slapping softly against each other at 0.04 and
    0.09), the loop opened with a creak of its knot at 0.16, then whirled once
    overhead: a round swish peaking at 0.22 (a band rising 240 -> 760 Hz and
    falling, the rope's thin whistle riding it, a darker body under it), which
    hands on to the throw (pilgrim_lasso_throw) as the loop flies."""
    dur = 0.6
    coil = _hemp(dur, seed + 10, 0.03, 0.15, rate=300, centre=2000, q=0.55)
    knot = _creak(dur, seed + 30, 70, 120, [(560, 1.0), (1250, 0.6), (2600, 0.3)], t0=0.15, t1=0.2, jitter=0.25, tau=0.006)
    knot *= _gate(dur, 0.15, 0.2, 0.01, 0.015)
    whirl = _whoosh(0.34, seed + 20, 240, 760, 360, t_peak=0.14, q=1.0, a=1.6, b=1.4, whistle=0.3)
    body = _whoosh(0.34, seed + 21, 110, 260, 130, t_peak=0.14, q=0.9, a=1.6, b=1.4)
    x = place(dur, [
        (0.0, _flick(seed), FLICK),
        (0.0, coil, 0.55),
        (0.04, _thump(0.12, seed + 11, f0=260, f1=150, drop=0.01, tau=0.012, lp=1800, noise=1.0, ntau=0.01), 0.3),
        (0.09, _thump(0.12, seed + 12, f0=240, f1=140, drop=0.01, tau=0.012, lp=1800, noise=1.0, ntau=0.01), 0.22),
        (0.0, _norm(knot), 0.2),
        (0.08, whirl, 0.75),
        (0.08, body, 0.35),
    ])
    return _out(x, 0.1)


@sound("card_fishing_rod", loudness=LOUD, wet=WET, marks=(0.0, 0.19, 0.27, 0.32))
def card_fishing_rod(seed):
    """Canna da Pesca, as it is cast (it is never played from the hand): the
    card leaves its slot, the rod is drawn back over his shoulder (a dry creak
    of the cane and a soft swish, 0.04-0.19), whipped forward (a thin fast
    swish peaking at 0.27, its tip whistling) and the line let go at 0.32: the
    reel's pawl spinning out, a purring click train slowing from 70 to 20 a
    second as the bobber flies, the line hissing off the spool, until the
    bobber is down at 0.62 (world_bobber_plop)."""
    dur = 0.75
    r = rng(seed + 1)
    back = _whoosh(0.2, seed + 10, 260, 900, 520, t_peak=0.13, q=1.1, a=1.4, b=1.6, whistle=0.1)
    cane = _creak(dur, seed + 11, 55, 95, [(820, 1.0), (1750, 0.55), (3400, 0.25)], t0=0.05, t1=0.19, jitter=0.3, tau=0.005)
    cane *= _gate(dur, 0.05, 0.19, 0.04, 0.02)
    whip = _whoosh(0.2, seed + 20, 1100, 4200, 2000, t_peak=0.075, q=1.7, a=1.3, b=1.8, whistle=0.55)
    clicks = []
    tt = 0.32
    while tt < 0.64:
        u = (tt - 0.32) / 0.32
        clicks.append((tt, r.uniform(0.6, 1.0) * (1 - 0.55 * u)))
        tt += 1 / (70 * (20 / 70) ** u)
    reel = _clatter(dur, clicks, [_pawl(seed + 40 + j, f) for j, f in enumerate((2900, 3300, 3700))], seed + 2)
    spool = _clatter(dur, clicks, [_wood(0.04, b, seed + 50 + j, tau=0.006, click=0.2) for j, b in enumerate((520, 610))],
                     seed + 3)
    hiss_l = 0.32
    hiss = _norm(bandpass(white(hiss_l, seed + 4), 6200, 0.9)) * _swell(hiss_l, 0.02, a=1.0, b=1.4)
    x = place(dur, [
        (0.0, _flick(seed), FLICK),
        (0.04, back, 0.35),
        (0.0, _norm(cane), 0.22),
        (0.19, whip, 0.7),
        (0.0, _norm(reel), 0.45),
        (0.0, _norm(spool), 0.2),
        (0.32, hiss, 0.14),
    ])
    return _out(x, 0.06)
