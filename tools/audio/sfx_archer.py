"""Family `archer` - the crossbowman (see SOUND_SPEC.md).

Red-hooded, light leather, a heavy wooden crossbow with an iron prod and a
crank. Taut, mechanical, quick.

The character's shared timbre is the crossbow itself, built once here and
reused by every action:
  - the walnut stock: a handful of low wood modes (_STOCK) that knock dry;
  - the flat iron prod: free-bar partials (1 : 2.76 : 5.40 : 8.93 ...) on
    F4, each split into a slowly beating doublet (_prod);
  - the crank's ratchet: an iron pawl that ticks over the teeth (_pawl);
  - the string: a low Karplus-Strong pluck on A2 whose pitch sags as the
    first big swing dies (_twang), and a stick-slip creak under tension.
Around it: light leather (stick-slip creaks, slaps), the red wool hood
(soft band-passed rustle), a quiver of wooden bolts that rattles (_rattle)
and the paper card he stands on (dart scrape, crumple grains).

Every recipe is dry: the build adds the stone hall, fades, trims and sets
the loudness.
"""
import math

import numpy as np

from dsp import *  # noqa: F401,F403
from registry import sound


# --------------------------------------------------------------------------
# Materials of the crossbowman

# Walnut stock: few low modes, short decays (a dry knock, 80-200 ms).
# Decays are time constants (exp(-t/d)).
_STOCK = ((188.0, 0.045, 1.0), (437.0, 0.032, 0.80), (742.0, 0.022, 0.55),
          (1175.0, 0.015, 0.35), (1810.0, 0.010, 0.20))
# Flat iron prod: free-free bar ratios on F4 (in the game's D Phrygian).
_PROD_BASE = 349.2
_PROD_RATIOS = (1.0, 2.756, 5.404, 8.933, 13.34)
# A body under leather: muffled, heavily damped modes (90-470 Hz) that die
# within about 120 ms - a thump, not a boom; no ringing.
_BODY = ((92.0, 0.032, 1.0), (138.0, 0.026, 0.9), (205.0, 0.020, 0.7),
         (310.0, 0.013, 0.5), (470.0, 0.008, 0.3))
# A light leather boot heel on stone.
_HEEL = ((92.0, 0.050, 0.9), (156.0, 0.042, 1.0), (233.0, 0.032, 0.7),
         (347.0, 0.022, 0.45), (520.0, 0.014, 0.25))
# Resonances that colour stick-slip creaks.
_LEATHER = ((430.0, 0.011, 1.0), (980.0, 0.007, 0.6), (1900.0, 0.004, 0.35))
_SINEW = ((560.0, 0.014, 1.0), (1240.0, 0.009, 0.7), (2350.0, 0.005, 0.4))
# Breath through teeth: unvoiced formants (never a voice).
_BREATH = ((1250.0, 2.2, 0.35), (2650.0, 2.6, 1.0), (4300.0, 2.4, 0.8), (6800.0, 1.6, 0.35))


# --------------------------------------------------------------------------
# Small helpers (module-private)

def _peak(x, p=1.0):
    m = float(np.max(np.abs(x))) if len(x) else 0.0
    return x * (p / m) if m > 0 else x


def _tame(x, max_crest=15.0, block=32, attack=0.0015, release=0.02):
    """Transparent peak control: rides the gain down for the few ms of a
    transient that stands more than `max_crest` dB over the loudness, so the
    build never has to soft-clip it. Block-wise, look-ahead, no waveshaping."""
    thr = 10 ** ((loudness_db(x) + max_crest) / 20)
    a = np.abs(x)
    if not len(a) or a.max() <= thr:
        return x
    nb = -(-len(x) // block)
    buf = np.zeros(nb * block)
    buf[:len(x)] = a
    need = np.minimum(1.0, thr / np.maximum(buf.reshape(nb, block).max(axis=1), 1e-12))
    g = np.minimum(need, np.minimum(np.r_[need[1:], 1.0], np.r_[1.0, need[:-1]]))
    rel = math.exp(-block / (release * SR))
    att = math.exp(-block / (attack * SR))
    cur = 1.0
    for k in range(nb):  # release: recover towards unity after a peak
        cur = min(g[k], 1.0 - (1.0 - cur) * rel)
        g[k] = cur
    cur = 1.0
    for k in range(nb - 1, -1, -1):  # attack: already down when the peak arrives
        cur = min(g[k], 1.0 - (1.0 - cur) * att)
        g[k] = cur
    centres = (np.arange(nb) + 0.5) * block
    return x * np.interp(np.arange(len(x)), centres, g)


def _finish(x, duration, fade_out=0.02, peak=0.8, max_crest=15.0):
    """Exact length, a soft end, controlled transients, headroom."""
    x = fade(pad_to(x, duration), 0.0, fade_out)
    return _peak(_tame(_tame(x, max_crest), max_crest), peak)


def _wobble(n, seed, cutoff):
    """Slow random motion in -1..1 (roughness, flutter)."""
    w = lowpass(rng(seed).standard_normal(n), cutoff, 1)
    return w / (np.max(np.abs(w)) + 1e-12)


def _decay_env(n, attack, tau):
    t = np.arange(n) / SR
    a = max(attack, 1.0 / SR)
    return np.where(t < a, t / a, np.exp(-(t - a) / tau))


def _band_gain(f, center, width):
    """Log-frequency gaussian (FWHM `width` octaves), as dsp.bandpass."""
    return np.exp(-0.5 * (np.log2(np.maximum(f, 1.0) / center) / (width / 2.355)) ** 2)


def _strike(seed, length=0.003, cutoff=None):
    """Excitation for a struck body: a few ms of decaying noise."""
    n = n_samples(length)
    e = rng(seed).uniform(-1, 1, n) * (1 - np.arange(n) / n) ** 2
    if cutoff and n > 8:
        e = lowpass(e, cutoff, 2)
    return e


def _ring(duration, modes, seed, strike_len=0.002, cutoff=None):
    """A struck resonant object, peak-normalised."""
    return _peak(modal(duration, modes, seed=seed, strike=_strike(seed + 101, strike_len, cutoff)))


def _ir(modes, duration=0.05):
    """Zero-phase-start modal impulse response (for impulse trains)."""
    t = time_axis(duration)
    x = np.zeros_like(t)
    for f, d, a in modes:
        x += a * np.sin(2 * np.pi * f * t) * np.exp(-t / d)
    return x


# --------------------------------------------------------------------------
# The crossbow

def _stock(seed, scale=1.0, decay=1.0, bright=1.0, duration=0.3):
    """The walnut stock knocks: low wood modes + a dry contact tick."""
    r = rng(seed)
    modes = [(f * scale * (1 + r.uniform(-0.015, 0.015)), d * decay, a * bright ** i)
             for i, (f, d, a) in enumerate(_STOCK)]
    body = _ring(duration, modes, seed, strike_len=0.0025, cutoff=3500 * bright)
    m = n_samples(0.004)
    tick = bandpass(white(0.004, seed + 7), 3000, 0.6) * np.linspace(1, 0, m) ** 2
    return _peak(mix(body, 0.35 * bright * _peak(tick)))


def _prod(seed, decay=0.5, duration=1.0, count=5, base=_PROD_BASE, strike_len=0.0008):
    """The iron prod rings: inharmonic bar partials, each a beating doublet;
    high partials die first, so it darkens as it decays."""
    r = rng(seed)
    modes = []
    for i, ratio in enumerate(_PROD_RATIOS[:count]):
        f = base * ratio * (1 + r.uniform(-0.008, 0.008))
        d = decay / (1 + 0.55 * i)
        a = 1.0 / (1 + 0.35 * i)
        modes.append((f, d, a))
        modes.append((f * 1.0041, d * 0.9, 0.6 * a))
    return _ring(duration, modes, seed, strike_len=strike_len)


def _pawl(seed, pitch=1.0, body=0.45, duration=0.07):
    """One ratchet click: the iron pawl drops on a tooth (bright, short
    metal modes) and knocks the stock a little."""
    r = rng(seed)
    base = 1880.0 * pitch * (1 + r.uniform(-0.02, 0.02))
    ratios = (1.0, 1.58, 2.27, 3.11, 4.02)
    modes = [(base * q, 0.013 / (1 + 0.5 * i), 1.0 / (1 + 0.55 * i)) for i, q in enumerate(ratios)]
    tick = _ring(duration, modes, seed, strike_len=0.0005, cutoff=9000)
    knock = _stock(seed + 1, scale=1.25, decay=0.45, duration=duration)
    return _peak(tick + body * knock)


def _twang(duration, seed, freq=110.0, damping=0.955, brightness=0.55, bend=0.16, bend_time=0.03):
    """The heavy string, plucked (Karplus-Strong). It starts sharp and sags
    to pitch as its first wide swing dies (tension modulation)."""
    src = karplus(freq * (1 + bend), duration * (1 + bend) + 0.02, damping, brightness, seed)
    t = time_axis(duration)
    speed = (1 + bend * np.exp(-t / bend_time)) / (1 + bend)
    pos = np.cumsum(speed) - speed[0]
    return _peak(np.interp(pos, np.arange(len(src)), src))


def _creak(duration, seed, rate0, rate1, modes, jitter=0.3, curve=1.0):
    """Stick-slip creak: a jittery impulse train (rate0 -> rate1 per second)
    ringing small resonances (leather, sinew, wood under strain)."""
    n = n_samples(duration)
    r = rng(seed)
    u = np.linspace(0, 1, n)
    rate = rate0 * (rate1 / rate0) ** (u ** curve)
    phase = np.cumsum(rate * np.clip(1 + jitter * _wobble(n, seed + 1, 25), 0.2, None)) / SR
    idx = np.nonzero(np.diff(np.floor(phase)) > 0)[0] + 1
    imp = np.zeros(n)
    imp[idx] = r.uniform(0.35, 1.0, len(idx))
    x = convolve(imp, _ir(modes, 0.05))[:n]
    return _peak(highpass(x, 150, 1))


def _bolt_click(seed, duration=0.035):
    """Two ash bolts knock in the leather quiver (sometimes iron heads)."""
    r = rng(seed)
    base = r.uniform(1450.0, 2500.0)
    modes = [(base, 0.010, 1.0), (base * 2.71, 0.006, 0.55), (base * 4.3, 0.0035, 0.3)]
    if r.random() < 0.35:
        modes.append((r.uniform(5200.0, 7400.0), 0.006, 0.5))
    return _ring(duration, modes, seed, strike_len=0.0005)


def _rattle(duration, t0, t1, count, seed, front=1.6):
    """A burst of bolt clicks between t0 and t1, densest and loudest early."""
    r = rng(seed)
    times = np.sort(t0 + (t1 - t0) * r.random(count) ** front)
    span = max(t1 - t0, 1e-3)
    events = [(float(t), _bolt_click(seed + 10 + k), r.uniform(0.4, 1.0) * math.exp(-1.8 * (t - t0) / span))
              for k, t in enumerate(times)]
    return place(duration, events)


# --------------------------------------------------------------------------
# Body, leather, cloth, paper, stone

def _step(seed, weight=1.0, duration=0.2):
    """A light leather boot on stone: sub-5 ms slap, low heel body
    (90-500 Hz), a short grit of stone dust (2-6 kHz)."""
    r = rng(seed)
    lift = 1.0 + 0.25 * (1.0 - weight)
    modes = [(f * lift * (1 + r.uniform(-0.04, 0.04)), d * (0.6 + 0.4 * weight), a) for f, d, a in _HEEL]
    # The heel's ring ends under a fade, never on a cut edge.
    body = fade(_ring(duration, modes, seed, strike_len=0.003 + 0.003 * weight, cutoff=1400), 0.0, 0.04)
    n = n_samples(duration)
    grit = bandpass(white(duration, seed + 1), 3800, 0.7) * _decay_env(n, 0.0006, 0.012)
    grit = _peak(grit) + 0.6 * _peak(grains(duration, list(0.002 + 0.03 * r.random(5)), 0.004, seed + 2,
                                             band=(2000, 6000)))
    slap = bandpass(white(duration, seed + 3), 1050, 0.6) * _decay_env(n, 0.0004, 0.005)
    return _peak(body + 0.12 * _peak(grit) + 0.15 * _peak(slap))


def _skid(duration, seed, f0=2600.0, f1=900.0, tau=0.035):
    """A heel skids on stone: gritty noise through a sinking band."""
    n = n_samples(duration)
    src = 0.5 * white(duration, seed) + crackle(duration, 2200, seed + 1, 0.0005)
    src = src * np.clip(1 + 0.7 * _wobble(n, seed + 2, 120), 0.05, None)
    x = sweep_bandpass(src, f0, f1, q=0.8)
    return _peak(x * _decay_env(n, 0.004, tau))


def _brake(duration, seed, f0=2400.0, f1=700.0, tau=0.07, rate0=44.0, rate1=28.0, depth=0.5):
    """A heel braking on stone: a sustained skid whose friction judders
    (stick-slip, slowing from rate0 to rate1 per second as he stops), held
    for 60-80 ms and gone by about 150 ms."""
    t = time_axis(duration)
    rate = rate0 * (rate1 / rate0) ** (t / duration)
    judder = 1 + depth * np.sin(2 * np.pi * np.cumsum(rate) / SR)
    return _peak(fade(_skid(duration, seed, f0, f1, tau), 0.0, 0.05) * judder)


def _body_thud(seed, weight=1.0, duration=0.3, contact=0.007):
    """A blow into a body under leather: muffled, damped modes (90-470 Hz)
    and a lowpassed noise push; -40 dB within about 120 ms. No ringing.
    `contact` is how long the blow presses in (a soft, padded contact)."""
    r = rng(seed)
    k = 1.0 / (0.85 + 0.15 * weight)
    modes = [(f * k * (1 + r.uniform(-0.04, 0.04)), d * (0.8 + 0.2 * weight), a) for f, d, a in _BODY]
    body = _ring(duration, modes, seed, strike_len=contact, cutoff=600)
    n = n_samples(duration)
    push = lowpass(white(duration, seed + 1), 260, 2) * _decay_env(n, 0.001, 0.03)
    return fade(_peak(body + 0.5 * _peak(push)), 0.0, 0.05)


def _smack(seed, duration=0.08, center=650.0, q=0.7, tau=0.016, attack=0.0008):
    """The leather-and-flesh 'smack' of a blow: a short mid-band noise burst
    (300-1300 Hz) that fills the gap between the thump and the slap."""
    n = n_samples(duration)
    return _peak(bandpass(white(duration, seed), center, q) * _decay_env(n, attack, tau))


def _slap(seed, duration=0.06, center=1700.0, tau=0.007):
    """Leather slapped: a short broadband crack, no tone."""
    n = n_samples(duration)
    x = highpass(bandpass(white(duration, seed), center, 0.45), 250, 2)
    return _peak(x * _decay_env(n, 0.0003, tau))


def _snap(seed, duration=0.012, tau=0.0012, hp=600.0):
    """A sub-2 ms broadband contact (the hard edge of an impact)."""
    n = n_samples(duration)
    return _peak(highpass(white(duration, seed), hp, 1) * _decay_env(n, 0.0001, tau))


def _cloth(duration, seed, center=1400.0, q=0.7, flutter=18.0):
    """The red wool hood and cloak: soft band-passed rustle."""
    n = n_samples(duration)
    x = bandpass(pink(duration, seed), center, q)
    am = np.abs(_wobble(n, seed + 1, flutter))
    return _peak(x * (0.25 + am))


def _whoosh(duration, seed, f_lo, f_hi, peak_at=0.4, q=1.1, power=1.6):
    """Moving air: band and level swell together, then fall."""
    swell = env_swell(duration, peak_at, power)

    def gain(f, t):
        u = min(max(t / duration, 0.0), 1.0)
        e = float(np.interp(u, np.linspace(0, 1, len(swell)), swell))
        return _band_gain(f, f_lo * (f_hi / f_lo) ** e, 1.0 / q)
    return _peak(stft_filter(pink(duration, seed), gain) * swell)


def _dart(duration, seed, f_start, f_end, width=1.3):
    """The paper card darts across stone: dense gritty scrape through a
    moving band, loudest at the shove, easing out as it slows."""
    n = n_samples(duration)
    t = np.arange(n) / SR
    grit = crackle(duration, 3000, seed + 1, 0.0004)
    hiss = rng(seed).uniform(-1, 1, n)
    rough = np.clip(1 + 0.9 * _wobble(n, seed + 2, 140), 0.05, None)
    src = (0.5 * hiss + grit) * rough

    def gain(f, tt):
        u = min(max(tt / duration, 0.0), 1.0)
        c = f_start * (f_end / f_start) ** u
        return _band_gain(f, c, width) + 0.12 * _band_gain(f, 2.2 * c, 0.8)
    x = stft_filter(src, gain)
    u = t / duration
    env = np.minimum(t / 0.008, 1.0) * (1 - u) ** 0.7 * (0.75 + 0.25 * np.exp(-t / 0.05))
    return _peak(x * env)


def _flick(seed, duration=0.03, center=3800.0):
    """A paper card's edge flicks (one dry grain)."""
    n = n_samples(duration)
    return _peak(bandpass(white(duration, seed), center, 1.0) * _decay_env(n, 0.0008, 0.006))


def _crumple(duration, t0, t1, rate, seed, band=(1500, 8000)):
    """Paper crumpling: fine 7 ms grains plus a few coarser 20 ms ones."""
    fine = random_times(duration, rate, seed, start=t0, end=t1, envelope=lambda u: (1 - u) ** 1.5)
    coarse = random_times(duration, rate * 0.35, seed + 2, start=t0, end=t1, envelope=lambda u: (1 - u) ** 2)
    a = grains(duration, fine, 0.007, seed + 1, band=band, gain_jitter=0.7)
    b = grains(duration, coarse, 0.02, seed + 3, band=(band[0], min(band[1], 5000)), gain_jitter=0.6)
    return _peak(a + 0.6 * b)


def _hiss(duration, seed, attack=0.01, tau=0.08, shift=(1.0, 0.85), formants=_BREATH):
    """A sharp breath through teeth: unvoiced noise through formants that
    sink a little as the breath ends."""
    n = n_samples(duration)
    src = 0.6 * white(duration, seed) + 0.6 * pink(duration, seed + 1)
    s0, s1 = shift

    def gain(f, t):
        u = min(max(t / duration, 0.0), 1.0)
        k = s0 * (s1 / s0) ** u
        g = np.zeros_like(f)
        for c, q, a in formants:
            g += a * _band_gain(f, c * k, 1.0 / q)
        return g
    x = stft_filter(src, gain)
    t = np.arange(n) / SR
    env = np.where(t < attack, (t / attack) ** 1.5, np.exp(-(t - attack) / tau))
    return _peak(x * env * (1 + 0.25 * _wobble(n, seed + 2, 40)))


def _stone_tick(seed, duration=0.03):
    """Hard object meets stone: a dense, very short gritty contact."""
    r = rng(seed)
    modes = [(r.uniform(1100, 4200), r.uniform(0.003, 0.007), r.uniform(0.4, 1.0)) for _ in range(9)]
    dense = _ring(duration, modes, seed, strike_len=0.0006)
    return _peak(dense + 0.7 * _snap(seed + 1, duration, 0.0015, 900))


def _bolt_flight(duration, seed, f0=3300.0, f1=1350.0, q=6.0):
    """The bolt flies away: a narrow whistle of noise (fletching) whose
    pitch falls (doppler) and whose highs the air takes as it recedes; the
    spin adds a whirring flutter."""
    n = n_samples(duration)
    t = np.arange(n) / SR
    width = 1.0 / q

    def gain(f, tt):
        u = min(max(tt / duration, 0.0), 1.0)
        c = f0 * (f1 / f0) ** (u ** 0.6)
        air = 1 / np.sqrt(1 + (f / (9000.0 * 0.3 ** u)) ** 4)
        return (_band_gain(f, c, width) + 0.35 * _band_gain(f, 2 * c, width)
                + 0.12 * _band_gain(f, c, 1.2)) * air
    x = stft_filter(white(duration, seed), gain)
    rate = 68.0 * 0.55 ** (t / duration)
    am = 1 + 0.45 * np.sin(2 * np.pi * np.cumsum(rate) / SR)
    env = (1 - np.exp(-t / 0.004)) / (1 + (t / 0.06) ** 1.4)
    return _peak(x * am * env)


# --------------------------------------------------------------------------
# The sounds

@sound("archer_move", loudness=-22, wet=0.16, marks=(0.165, 0.17, 0.405, 0.42))
def archer_move(seed):
    """A low dash: he coils (leather creak, hood rustle), plants and pushes
    off in quick light steps, the card darts across the stone 0.165-0.405
    with a low body whoosh over it, the quiver rattles at the launch and the
    stop, and the heel plants at 0.42 and brakes him in a juddering skid
    on the stone (held about 70 ms, gone by 150 ms)."""
    D = 0.9
    s = seed
    crouch = _creak(0.15, s + 1, 48, 30, _LEATHER, jitter=0.35) * env_swell(0.15, 0.55, 1.5)
    hood = _cloth(0.2, s + 2, 1700, 0.8) * env_swell(0.2, 0.75, 1.6)
    plant = _step(s + 3, weight=0.45)
    push = _step(s + 4, weight=0.8)
    skip = _step(s + 5, weight=0.35)
    settle = _step(s + 6, weight=0.3)
    dart = _dart(0.405 - 0.165, s + 7, 4200, 1600)
    flick = _flick(s + 8)
    dash = _whoosh(0.22, s + 9, 320, 950, peak_at=0.35)
    rattle_go = _rattle(0.16, 0.0, 0.12, 6, s + 10)
    rattle_stop = _rattle(0.16, 0.0, 0.12, 7, s + 11)
    stop = _flick(s + 14, 0.03, 2600)
    heel = _step(s + 12, weight=1.0)
    skid = _brake(0.18, s + 13)
    x = place(D, [
        (0.0, crouch, 0.18), (0.0, hood, 0.12),
        (0.075, plant, 0.32), (0.165, push, 0.55), (0.29, skip, 0.22),
        (0.165, dart, 0.62), (0.165, flick, 0.3), (0.405, stop, 0.16),
        (0.17, dash, 0.22),
        (0.168, rattle_go, 0.22), (0.425, rattle_stop, 0.26),
        (0.42, heel, 0.7), (0.42, skid, 0.45),
        (0.63, settle, 0.14),
    ])
    return _finish(x, D)


@sound("archer_aim", loudness=-21, wet=0.2)
def archer_aim(seed):
    """He cranks the crossbow: ratchet clicks that speed up (each an iron
    pawl tick + a small stock knock, the tooth's dry grind rising between
    them), the string and stock creak as the tension climbs, the prod groans
    low, and the nut locks the string with a firm iron clack at 0.58."""
    D = 0.7
    s = seed
    r = rng(s)
    times = []
    t, gap = 0.04, 0.078
    while t < 0.54:
        times.append(t)
        t += gap
        gap = max(0.02, gap * 0.88)
    events = []
    for k, tk in enumerate(times):
        u = k / max(len(times) - 1, 1)
        click = _pawl(s + 20 + k, pitch=1.0 + 0.04 * (k % 2) + 0.06 * u, body=0.7)
        events.append((tk, click, (0.45 + 0.35 * u) * r.uniform(0.85, 1.0)))
    # Between clicks the tooth rides up under the pawl: a dry grind that grows.
    n = n_samples(D)
    tt = np.arange(n) / SR
    ride = np.zeros(n)
    for a, b in zip(times, times[1:] + [0.56]):
        m = (tt >= a) & (tt < b)
        ride[m] = ((tt[m] - a) / (b - a)) ** 2
    grind = bandpass(white(D, s + 2) + crackle(D, 1500, s + 3, 0.0004), 2600, 0.8)
    grind = _peak(grind) * ride
    tension = env_points(0.52, [(0.0, 0.0), (0.12, 0.35), (0.42, 1.0), (0.5, 0.6), (0.52, 0.0)])
    creak = _creak(0.52, s + 4, 22, 95, _SINEW, jitter=0.3, curve=0.8) * tension
    groan_modes = ((_PROD_BASE, 0.03, 1.0), (_PROD_BASE * _PROD_RATIOS[1], 0.015, 0.4))
    groan = _creak(0.48, s + 5, 16, 34, groan_modes, jitter=0.4) * env_swell(0.48, 0.7, 1.5)
    grip = _creak(0.1, s + 6, 60, 40, _LEATHER) * env_swell(0.1, 0.4, 1.5)
    # The lock: the nut catches the string (iron clack + stock knock + a
    # short prod shiver + the string seated with a tiny pluck).
    clack = _pawl(s + 7, pitch=0.78, body=0.9, duration=0.1)
    shiver = _prod(s + 8, decay=0.07, duration=0.12)
    seat = _twang(0.08, s + 9, freq=220.0, damping=0.9, brightness=0.35, bend=0.03) * _decay_env(
        n_samples(0.08), 0.001, 0.02)
    lock_snap = _snap(s + 10)
    x = place(D, events + [
        (0.0, grind, 0.2),
        (0.08, creak, 0.32), (0.06, groan, 0.16), (0.0, grip, 0.1),
        (0.58, lock_snap, 0.45), (0.58, clack, 0.95), (0.581, shiver, 0.16), (0.582, seat, 0.18),
    ])
    return _finish(x, D, fade_out=0.04)


@sound("archer_shoot", loudness=-18, wet=0.25, marks=(0.06, 0.064))
def archer_shoot(seed):
    """Release at 0.06: the tickler slips (tiny iron tick), the string slams
    the prod into the stock (hard snap + walnut knock + damped iron ring)
    and twangs low (Karplus on A2, sagging into pitch); the bolt hisses off
    the groove and whistles away, falling in pitch and dulling; the recoil
    kicks him back at 0.064 (body thump, boot scuff, quiver rattle)."""
    D = 0.75
    s = seed
    REL = 0.06
    trigger = _pawl(s + 1, pitch=1.15, body=0.2, duration=0.04)
    crack = _snap(s + 2, 0.015, 0.0015, 400)
    stock = _stock(s + 3, scale=0.92, decay=1.3, duration=0.4)
    # The prod is held by the stock and the string: a damped iron "tung"
    # felt inside the thunk, not a bell after it.
    prod = fade(_prod(s + 4, decay=0.07, duration=0.3), 0.0, 0.08)
    # A heavy, thick string: few harmonics from the start, and a lowpass
    # that closes as it rings (2.4 kHz -> 500 Hz), so it thrums, not plucks.
    tw_n = n_samples(0.5)
    twang = fade(sweep_lowpass(_twang(0.5, s + 5, freq=110.0, damping=0.95, brightness=0.15, bend=0.16),
                               2400, 500, 2) * _decay_env(tw_n, 0.0005, 0.14), 0.0, 0.1)
    groove = _peak(bandpass(white(0.03, s + 6), 6000, 0.9) * _decay_env(n_samples(0.03), 0.001, 0.006))
    flight = fade(_bolt_flight(0.55, s + 7), 0.0, 0.1)
    # The stock butting his shoulder. It and the string are separate
    # sources, so their polarity is free: flipped, its first low swing does
    # not stack on the string's and the release crack leads the transient.
    recoil = -_body_thud(s + 8, weight=0.8)
    scuff = _skid(0.08, s + 9, 2000, 800, 0.02)
    rattle = _rattle(0.2, 0.0, 0.14, 8, s + 10)
    x = place(D, [
        (0.045, trigger, 0.12),
        (REL, crack, 0.7), (REL, stock, 0.7), (REL, prod, 0.28), (REL, twang, 0.6),
        (REL + 0.001, groove, 0.22),
        (REL + 0.006, flight, 0.5),
        (0.064, recoil, 0.35), (0.07, scuff, 0.14),
        (0.075, rattle, 0.18),
    ])
    # A 16 dB crest still masters under the ceiling (peak about -2 dBFS).
    return _finish(x, D, fade_out=0.04, max_crest=16.0)


@sound("archer_hurt", loudness=-18, wet=0.18, marks=(0.118,))
def archer_hurt(seed):
    """Hit at 0.118: a short muffled body thud through the leather with a
    mid 'smack' of the jerkin, which slaps and creaks, the paper card
    crumples a little, the crossbow is
    flung and its stock knocks twice (iron fittings tick), the quiver
    rattles, and a sharp breath hisses through his teeth."""
    D = 0.75
    s = seed
    HIT = 0.118
    thud = _body_thud(s + 1, weight=1.0)
    slap = _slap(s + 2)
    smack = _smack(s + 10)
    creak = _creak(0.12, s + 3, 70, 35, _LEATHER) * env_swell(0.12, 0.3, 1.5)
    paper = _crumple(0.2, 0.0, 0.11, 260, s + 4)
    knock1 = _stock(s + 5, scale=1.05, decay=0.8, duration=0.25)
    knock2 = _stock(s + 6, scale=1.12, decay=0.6, bright=0.8, duration=0.25)
    fitting = _pawl(s + 7, pitch=1.3, body=0.0, duration=0.04)
    hiss = _hiss(0.34, s + 8, attack=0.01, tau=0.075)
    rattle = _rattle(0.2, 0.0, 0.15, 6, s + 9)
    x = place(D, [
        (HIT, thud, 0.6), (HIT, smack, 0.45), (HIT, slap, 0.5), (HIT + 0.004, paper, 0.22),
        (HIT + 0.03, creak, 0.1),
        (0.165, knock1, 0.4), (0.168, fitting, 0.12), (0.305, knock2, 0.2),
        (HIT + 0.012, hiss, 0.52),
        (HIT + 0.01, rattle, 0.15),
    ])
    # The thump is short, so its crest over a 400 ms loudness is high by
    # nature; 16 dB still masters under the ceiling (peak about -2 dBFS).
    return _finish(x, D, fade_out=0.04, max_crest=16.0)


@sound("archer_death", loudness=-18, wet=0.3, marks=(0.118, 0.69))
def archer_death(seed):
    """Hit at 0.118 (heavier than hurt: body thud, leather smack and slap,
    paper crumple, a long sinking gasp of breath); he slumps (hood and
    leather slide, a knee meets the stone, the card creases); at 0.69 the
    card topples flat onto the stone (a papery slap and crumple) as he lands,
    and the crossbow clatters - walnut knock, iron prod ringing darker and
    dying away, then bounces that come quicker and softer (0.765, 0.815,
    0.84) - while bolts spill from the quiver."""
    D = 1.2
    s = seed
    HIT = 0.118
    FALL = 0.69
    B1, B2, B3 = 0.765, 0.815, 0.84  # bounces: gaps 75, 50, 25 ms
    thud = _body_thud(s + 1, weight=1.25)
    smack = _smack(s + 21, duration=0.12, center=550, tau=0.026, attack=0.001)
    # The blow jolts the crossbow in his hands: the stock knocks once.
    jolt = _stock(s + 24, scale=1.04, decay=0.8, duration=0.25)
    jolt_tick = _pawl(s + 25, pitch=1.25, body=0.0, duration=0.04)
    slap = _slap(s + 2, center=1500, tau=0.009)
    paper = _crumple(0.25, 0.0, 0.14, 300, s + 3)
    gasp = _hiss(0.5, s + 4, attack=0.015, tau=0.13, shift=(1.0, 0.7))
    slump = _cloth(0.42, s + 5, 1100, 0.7) * env_swell(0.42, 0.7, 1.5)
    strain = _creak(0.3, s + 6, 40, 22, _LEATHER, jitter=0.4) * env_swell(0.3, 0.5, 1.5)
    knee = _step(s + 7, weight=0.6)
    crease = _crumple(0.14, 0.0, 0.1, 380, s + 8, band=(2000, 7000))
    land = _body_thud(s + 9, weight=0.9)
    smack2 = _smack(s + 22, duration=0.1, center=520, tau=0.018, attack=0.001)
    # The paper card falls flat on the stone: one papery slap, a crumple.
    card = _smack(s + 19, duration=0.06, center=1800, q=0.5, tau=0.012)
    card_crumple = _crumple(0.12, 0.0, 0.06, 300, s + 20)
    # The crossbow hits the stone: the first impact rings the prod fully,
    # each bounce re-strikes it softer; the iron dies away before the end.
    prod1 = fade(_prod(s + 10, decay=0.2, duration=D - FALL), 0.0, 0.2)
    prod2 = fade(_prod(s + 11, decay=0.14, duration=D - B1), 0.0, 0.15)
    stock1 = _stock(s + 12, scale=1.0, decay=1.1, duration=0.3)
    stock2 = _stock(s + 13, scale=1.08, decay=0.8, bright=0.85, duration=0.25)
    stock3 = _stock(s + 14, scale=1.15, decay=0.6, bright=0.7, duration=0.2)
    stone1 = _stone_tick(s + 15)
    stone2 = _stone_tick(s + 16)
    stone3 = _stone_tick(s + 23, 0.02)
    settle = _skid(0.09, s + 17, 1800, 700, 0.03)
    spill = _rattle(0.4, 0.0, 0.3, 11, s + 18, front=1.3)
    # The card (his body) comes down flat a hair before the crossbow strikes
    # the stone on the mark: a 15 ms flam that fuses into one heavy fall.
    LAND = FALL - 0.015
    x = place(D, [
        (HIT, thud, 0.76), (HIT, smack, 0.55), (HIT, slap, 0.5), (HIT + 0.004, paper, 0.25),
        (HIT + 0.015, gasp, 0.3),
        (0.158, jolt, 0.4), (0.16, jolt_tick, 0.1),
        (0.26, slump, 0.2), (0.3, strain, 0.12), (0.52, knee, 0.25), (0.47, crease, 0.22),
        (LAND - 0.004, card, 0.35), (LAND, card_crumple, 0.18),
        (LAND, land, 0.6), (LAND, smack2, 0.3),
        (FALL, stone1, 0.4), (FALL, stock1, 0.64), (FALL + 0.001, prod1, 0.38),
        (B1, stone2, 0.22), (B1, stock2, 0.4), (B1 + 0.001, prod2, 0.16),
        (B2, stock3, 0.18), (B2, settle, 0.1),
        (B3, stone3, 0.08),
        (FALL + 0.01, spill, 0.2),
    ])
    return _finish(x, D, fade_out=0.08, max_crest=16.0)
