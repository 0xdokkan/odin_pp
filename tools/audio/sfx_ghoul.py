"""Family `ghoul` - the Chaser (see SOUND_SPEC.md).

A red, skinless, feral ghoul that runs on all fours on bone claws: wet,
ragged, fast. Every sound of the family is built from the same four
ingredients, so the character keeps one timbre across its actions while each
action stays its own:

- the ghoul's throat (`_throat`, `_mouth`, `_voice`): a pulse source with
  cycle-to-cycle jitter (no two periods alike), period doubling (the growl's
  subharmonic rasp), optional biphonation (a second fold at a non-integer
  ratio, as in animal screams) and breath noise gated by the pulses, through
  one moving formant model, from a closed guttural growl (mouth 0) to bared
  teeth (mouth ~0.8). Voices stay low (growl register) or mostly noise and
  chaos: no human vowels, no words;
- bone claws (`_bone_click`, `_claw_scratch`): bone is stiff and heavily
  damped, so a claw tip on stone is a tiny bright modal click (1.5-7 kHz,
  ~10 ms); a claw dragged on stone is a gritty band-passed scratch whose band
  moves with the stroke;
- wet flesh (`_flesh_hit`, `_bubble`, `_wet_click`, `_rip`): a low cavity
  thump with a falling pitch, meat noise, a broadband slap, a squelch band
  that falls, and short damped bubble pops (van den Doel's model with a small
  rise, so they read as wet ticks, not bloops); unpitched mouth clicks;
- paper (`_card_scrape`, `_paper_crumple`, `_paper_crease`, `_card_slap`):
  the standee card dragged over stone, crumpled by a blow, folded and dropped.

Each sound is built as named layers (`_<sound>_layers`), so a layer can be
measured on its own; the registered recipe sums them. Recipes are dry; the
build adds the stone hall.
"""
import math

import numpy as np

from dsp import *  # noqa: F401,F403
from dsp import (SR, bandpass, convolve, crackle, drive, env_perc, env_points, env_swell, fade, grains,
                 highpass, lowpass, modal, n_samples, phase_of, pink, place, random_times, rng, stft_filter,
                 sweep_bandpass, time_axis, white)
from registry import sound


# --------------------------------------------------------------------------
# Small utilities

def _norm(x, peak=1.0):
    m = float(np.max(np.abs(x))) if len(x) else 0.0
    return x * (peak / m) if m > 0 else x


def _dc_block(x, cutoff=35.0):
    """Causal first-order high-pass (the signal minus its one-pole low-pass,
    done as an FFT convolution with the causal exponential kernel). Removes
    the sub-bass offset of the thumps before the build's zero-phase DC filter,
    which would otherwise smear a faint ramp ahead of each hit."""
    tau = 1.0 / (2 * math.pi * cutoff)
    k = np.exp(-np.arange(n_samples(tau * 8)) / (tau * SR))
    return x - convolve(x, k / k.sum())[:len(x)]


def _finish(x, fade_out):
    """Every recipe ends here: causal DC block, no click at either end, and
    the dry peak at 0.85 (headroom; the build sets the loudness)."""
    return _norm(fade(_dc_block(x), 0.002, fade_out), 0.85)


def _mixdown(layers):
    """Sum of a recipe's named layers (all placed on the same timeline)."""
    return np.sum(np.array(list(layers.values())), axis=0)


def _wander(n, rate, seed):
    """A smooth random control signal (unit std) that moves about `rate` times a second."""
    w = lowpass(rng(seed).standard_normal(n), rate, 2)
    return w / (np.std(w) + 1e-12)


# --------------------------------------------------------------------------
# The ghoul's throat

def _mouth(o, hiss=0.0):
    """The ghoul's vocal tract as formants [(Hz, q, gain)] for a mouth opening
    `o` (0 = closed guttural growl, 1 = jaws wide). One model for the whole
    family: the ratios stay, only the opening moves them."""
    s = 2.0 ** o
    return [
        (230.0 * s ** 0.5, 1.4, 0.75),            # chest / pharynx
        (470.0 * s, 1.9, 1.0),                     # F1
        (1080.0 * s, 2.1, 0.55 + 0.35 * o),        # F2
        (2350.0 * s ** 0.8, 2.3, 0.25 + 0.35 * o),  # F3
        (4100.0 * s ** 0.4, 1.3, 0.05 + 0.45 * hiss),  # bared teeth, spit hiss
    ]


def _tract(x, mouth_keys, hiss=0.0):
    """Moving formant filter: `mouth_keys` [(t, opening)] over the sound."""
    kt = np.array([k[0] for k in mouth_keys], float)
    ko = np.array([k[1] for k in mouth_keys], float)

    def gain(f, t):
        o = float(np.interp(t, kt, ko))
        lf = np.log2(np.maximum(f, 1.0))
        g = np.zeros_like(f)
        for c, q, a in _mouth(o, hiss):
            w = (1.0 / q) / 2.355
            g += a * np.exp(-0.5 * ((lf - math.log2(c)) / w) ** 2)
        return g
    return stft_filter(x, gain, 1024, 256)


def _throat(duration, f0_keys, seed, voiced=0.7, breath=0.5, rasp=0.45, jitter=0.03, cycle=0.06):
    """Source of the ghoul's growls: a pulse train (a sharp closure each
    period) with a slow pitch wander (`jitter`), cycle-to-cycle jitter
    (`cycle`: each closure lands early or late by an independent amount, so
    the period std is about `cycle`; the growl roughens instead of warbling),
    random shimmer and period doubling (every other pulse weaker: the
    subharmonic rasp of a feral growl), plus breath noise gated by the same
    pulses (the aspirated rattle)."""
    n = n_samples(duration)
    t = time_axis(duration)
    kt = [k[0] for k in f0_keys]
    kf = [math.log(k[1]) for k in f0_keys]
    f0 = np.exp(np.interp(t, kt, kf)) * (1 + jitter * _wander(n, 14.0, seed))
    ph = np.cumsum(f0) / SR
    if cycle > 0:
        # Move each cycle boundary k to k + offset_k and remap the phase
        # through them (monotonic: offsets stay within +-0.4 of a cycle).
        kk = np.arange(-1, int(ph[-1]) + 3).astype(float)
        off = np.clip(rng(seed + 3).standard_normal(len(kk)) * cycle / math.sqrt(2), -0.4, 0.4)
        ph = np.interp(ph, kk + off, kk)
    ph = ph + 1.0  # keeps the cycle index positive
    frac = ph - np.floor(ph)
    idx = np.floor(ph).astype(int)
    r = rng(seed + 1)
    shimmer = (1 - rasp * r.random(int(idx[-1]) + 2))[idx]
    alt = np.where(idx % 2 == 0, 1.0, 1.0 - 0.6 * rasp)
    pulse = np.exp(-frac * 7.0)
    pulse = pulse - np.mean(pulse)
    voice = pulse * shimmer * alt
    gate = 0.3 + 0.7 * np.exp(-frac * 5.0)
    br = white(duration, seed + 2) * gate * (0.5 + 0.5 * shimmer)
    voice = voice / (np.std(voice) + 1e-12)
    br = br / (np.std(br) + 1e-12)
    return voiced * voice + breath * br


def _voice(duration, f0_keys, mouth_keys, env_keys, seed, voiced=0.7, breath=0.5, rasp=0.45,
           jitter=0.03, hiss=0.0, grit=1.6, cycle=0.06, biphon=0.0, bi_ratio=1.37, low_cut=0.0):
    """A ghoul growl / snarl / shriek: throat -> moving mouth -> level -> a
    little saturation (louder moments get rougher). `biphon` mixes in a
    second fold on the same pitch path times `bi_ratio` (non-integer, so the
    two never share a clean harmonic series: the chaotic double voice of an
    animal scream rather than a human cry). `low_cut` thins the chest out
    (a raised larynx in a scream), so the fundamental never leads."""
    src = _throat(duration, f0_keys, seed, voiced, breath, rasp, jitter, cycle)
    if biphon > 0:
        f1_keys = [(k[0], k[1] * bi_ratio) for k in f0_keys]
        src = src + biphon * _throat(duration, f1_keys, seed + 7, 1.0, 0.0, 0.9, 0.1, cycle * 1.5)
    y = _tract(src, mouth_keys, hiss)
    if low_cut > 0:
        y = highpass(y, low_cut, 2)
    y = _norm(y) * env_points(duration, env_keys)
    return drive(y, grit)


# --------------------------------------------------------------------------
# Wet flesh

def _bubble(f0, seed, xi=0.08, scale=1.0, amp_jitter=0.0):
    """A wet pop: a damped sine whose pitch rises a little as the bubble
    collapses (van den Doel's model: damping d grows with frequency, the rise
    is xi * d per second). With xi under 0.09 the pitch moves less than 20 %
    while the pop is within 20 dB of its peak, so it reads as a wet tick, not
    a cartoon bloop. `scale` > 1 lowers the damping (a longer ring)."""
    d = (0.13 * f0 + 0.0072 * f0 ** 1.5) / scale
    dur = min(0.12, 6.5 / d)
    t = time_axis(dur)
    f = f0 * (1 + xi * d * t)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR + rng(seed).uniform(0, 0.3))
    return s * np.exp(-d * t) * (1 - np.exp(-t / 0.0004))


def _wet_click(seed, d=0.012):
    """Tongue or saliva click: a sub-millisecond noise tick rung briefly by
    the mouth cavity (a narrow band somewhere in 1.2-2.8 kHz). Unpitched: it
    has no glide at all."""
    r = rng(seed)
    e = np.zeros(n_samples(d))
    m = n_samples(0.0004)
    e[:m] = r.uniform(-1, 1, m) * np.hanning(m)
    return _norm(bandpass(e, r.uniform(1200, 2800), 2.0) * env_perc(d, 0.0002, 0.005))


def _flesh_hit(seed, weight=1.0, wet=1.0, bright=1.0, duration=0.45, thump_gain=1.0, meat_gain=0.55, slap=0.4,
               slap_lp=9000.0):
    """A wet meaty blow: low cavity thump (pitch falling), lowpassed meat
    noise, a broadband slap (the sub-5 ms transient), a falling squelch band
    and a few short bubble pops. No ringing. `slap_lp` darkens the slap for
    soft pads (palms) rather than a whole body."""
    n = n_samples(duration)
    t = time_axis(duration)
    r = rng(seed)
    f_hi = 170.0 / weight ** 0.3
    f_lo = 64.0 / weight ** 0.15
    path = f_lo + (f_hi - f_lo) * np.exp(-t / 0.022)
    thump = np.sin(2 * np.pi * phase_of(path, n=n)) * env_perc(duration, 0.0012, 0.11 * weight)
    meat = _norm(lowpass(white(duration, seed + 1), 320, 2)) * env_perc(duration, 0.0008, 0.07 * weight)
    slap_x = _norm(lowpass(highpass(white(duration, seed + 2), 900, 2), slap_lp, 2)) * env_perc(duration, 0.0003, 0.02 * bright)
    sq_d = 0.06 + 0.04 * weight
    sq = _norm(sweep_bandpass(pink(sq_d, seed + 3), 1400 * bright ** 0.3, 320, q=2.2))
    sq = sq * env_points(sq_d, [(0, 0), (0.004, 1), (sq_d * 0.4, 0.5), (sq_d, 0)])
    count = int(round(3 + 3 * wet))
    bub_t = np.sort(r.uniform(0.003, 0.05 + 0.03 * weight, count))
    bubbles = place(duration, [(bt, _bubble(r.uniform(350, 1400), seed + 10 + i, 0.08, 1.5), r.uniform(0.4, 1.0))
                               for i, bt in enumerate(bub_t)])
    out = place(duration, [(0.0, thump, thump_gain), (0.0, meat, meat_gain), (0.0, slap_x, slap * bright),
                           (0.001, sq, 0.4 * wet)])
    return out + 0.25 * wet * _norm(bubbles)


def _smack(seed):
    """Wet lips peeling off the teeth: a tiny band-passed smack and a short pop."""
    d = 0.03
    s = _norm(bandpass(white(d, seed), 1800, 0.7)) * env_perc(d, 0.0003, 0.008)
    b = np.zeros(n_samples(d))
    p = _bubble(rng(seed).uniform(900, 1500), seed + 1, 0.08, 2.0)[:len(b)]
    b[:len(p)] = p
    return _norm(s + 0.6 * b)


def _rip(duration, seed):
    """Flesh torn by claws: a train of fibre snaps (dense, uneven crackle) in a
    wet low-mid band, with a fleshy smear under it."""
    n = n_samples(duration)
    u = np.linspace(0, 1, n)
    shape = np.clip(u / 0.12, 0, 1) * (1 - u) ** 1.3
    dens = 2600 * shape * np.clip(1 + 0.8 * _wander(n, 60, seed), 0.05, 3)
    snaps = crackle(duration, dens, seed + 1, decay=0.0004)
    snaps = 0.75 * bandpass(snaps, 1800, 0.8) + 0.5 * bandpass(snaps, 700, 1.2)
    smear = _norm(bandpass(pink(duration, seed + 2), 520, 1.0))
    env = env_points(duration, [(0, 0), (0.003, 1), (duration * 0.4, 0.55), (duration, 0)])
    return _norm(_norm(snaps) * (0.3 + 0.7 * shape / shape.max()) + 0.35 * smear * env)


# --------------------------------------------------------------------------
# Bone claws

_BONE = (1.0, 1.58, 2.37, 3.31)


def _bone_click(seed, base=2200.0, decay=0.009, tick_lp=9000.0):
    """A claw tip on stone: a few stiff, heavily damped bone modes struck by a
    sub-millisecond impulse, plus the impulse's own tick (lowpassed at
    `tick_lp`)."""
    r = rng(seed)
    modes = [(base * q * (1 + r.uniform(-0.05, 0.05)), decay / (1 + 0.35 * i), 1.0 / (1 + 0.5 * i))
             for i, q in enumerate(_BONE)]
    m = n_samples(0.0007)
    exc = r.uniform(-1, 1, m) * np.hanning(m + 2)[1:-1]
    body = _norm(modal(0.05, modes, seed, strike=exc))
    k = n_samples(0.0015)
    tick = np.zeros(len(body))
    tick[:k] = _norm(highpass(r.uniform(-1, 1, k), 3000, 2)) * np.hanning(k)
    return _norm(body + 0.45 * lowpass(tick, tick_lp, 2))


def _claw_scratch(duration, seed, f0=6000.0, f1=2600.0, q=1.4):
    """A bone claw dragged on stone: gritty noise (stick-slip micro impacts)
    in a band that moves from f0 to f1 with the stroke."""
    n = n_samples(duration)
    src = 0.5 * white(duration, seed) + crackle(duration, 3500, seed + 1, decay=0.0003)
    src = lowpass(sweep_bandpass(src, f0, f1, q), 9000, 2)
    chatter = np.clip(1 + 0.5 * _wander(n, 140, seed + 2), 0.1, 2.0)
    env = env_points(duration, [(0, 0), (0.0015, 1.0), (duration * 0.35, 0.65), (duration, 0.0)]) ** 1.4
    return _norm(src * chatter * env)


# --------------------------------------------------------------------------
# Paper and the standee card

def _card_scrape(duration, seed, level_keys, center=2300.0, spread=0.35):
    """The card's base dragged over stone: a dense gritty band (1-5 kHz) that
    wanders with the drag, stick-slip chatter, level following `level_keys`."""
    n = n_samples(duration)
    src = 0.45 * white(duration, seed + 1) + crackle(duration, 4000, seed, decay=0.00035)
    centers = center * 2 ** (spread * np.clip(_wander(n, 5.0, seed + 2), -2, 2))
    w = 1.1 / 2.355

    def gain(f, t):
        c = centers[min(max(int(t * SR), 0), n - 1)]
        lf = np.log2(np.maximum(f, 1.0))
        return np.exp(-0.5 * ((lf - math.log2(c)) / w) ** 2) + 0.12 * np.exp(-0.5 * ((lf - math.log2(c * 0.35)) / w) ** 2)
    src = lowpass(stft_filter(src, gain), 8000, 2)
    chatter = np.clip(1 + 0.35 * _wander(n, 45, seed + 3), 0.2, 2.0)
    return _norm(src) * chatter * env_points(duration, level_keys)


def _paper_crumple(duration, seed, rate=320.0):
    """A blow crumples the card a little: grains of band-passed noise
    (1.5-8 kHz, 6-20 ms), thinning out."""
    times = random_times(duration, rate, seed, 0.0, duration * 0.8, envelope=lambda u: (1 - u) ** 1.5)
    a = grains(duration, times[::2], 0.006, seed + 1, band=(1800, 8000))
    b = grains(duration, times[1::2], 0.02, seed + 2, band=(1500, 5000))
    return _norm(a + 0.6 * b)


def _paper_crease(seed):
    """The card bends and creases: a quick dense run of paper grains and the
    soft flap of the card bending."""
    d = 0.07
    times = random_times(d, 650, seed, 0.0, 0.04, envelope=lambda u: 1 - 0.7 * u)
    g = grains(d, times, 0.005, seed + 1, band=(2000, 7000))
    flap = _norm(bandpass(pink(d, seed + 2), 1100, 0.9)) * env_points(d, [(0, 0), (0.006, 1), (0.03, 0.4), (d, 0)])
    return _norm(_norm(g) + 0.4 * flap)


def _card_slap(seed):
    """The card topples flat on the stone: a broad flat smack, the puff of air
    pushed out from under it, a little paper rattle."""
    d = 0.08
    smack = _norm(bandpass(white(d, seed), 2400, 0.45)) * env_perc(d, 0.0004, 0.025)
    puff = _norm(bandpass(pink(d, seed + 1), 480, 1.2)) * env_perc(d, 0.002, 0.04)
    times = random_times(d, 300, seed + 2, 0.004, 0.05)
    rattle = grains(d, times, 0.006, seed + 3, band=(2500, 7000))
    return _norm(smack + 0.5 * puff + 0.3 * _norm(rattle))


# --------------------------------------------------------------------------
# Composite gestures

def _whoosh(duration, seed, centers, peak_at=0.5, q=1.1, power=2.0, fall=None):
    """Air pushed aside: pink noise in a band that moves through `centers`
    [(t, Hz)], swelling to its peak then falling (no hard attack). `fall`
    (a power, default `power`) makes the fall steeper than the rise."""
    src = pink(duration, seed)
    ct = np.array([c[0] for c in centers], float)
    cf = np.log2([c[1] for c in centers])
    w = (1.0 / q) / 2.355

    def gain(f, t):
        c = float(np.interp(t, ct, cf))
        return np.exp(-0.5 * ((np.log2(np.maximum(f, 1.0)) - c) / w) ** 2)
    env = env_swell(duration, peak_at, power)
    if fall is not None:
        u = np.linspace(0, 1, len(env))
        env = np.where(u < peak_at, env, ((1 - u) / (1 - peak_at)) ** fall)
    return _norm(stft_filter(src, gain) * env)


def _paw_land(seed, weight=1.0):
    """The front claws strike stone: palms slap (light, wet, soft pads: a
    darker slap), the bone claws click in a quick flam, then scrape as they
    grip."""
    d = 0.3
    r = rng(seed)
    ev = [(0.0, _flesh_hit(seed, 0.5 * weight, 0.7, 1.0, d, slap_lp=6000.0), 0.85)]
    tc = 0.0
    for i in range(3):
        ev.append((tc, _bone_click(seed + 20 + i, r.uniform(1500, 2200), tick_lp=7000.0), r.uniform(0.35, 0.6)))
        tc += r.uniform(0.0025, 0.005)
    ev.append((0.003, _claw_scratch(r.uniform(0.06, 0.085), seed + 30, r.uniform(4000, 5200), r.uniform(2400, 3000)), 0.38))
    return place(d, ev)


def _hind_pad(seed):
    """The hind feet coming down after the claws: a soft fleshy pat."""
    d = 0.2
    r = rng(seed)
    return place(d, [(0.0, _flesh_hit(seed, 0.4, 0.5, 0.8, d), 1.0),
                     (0.002, _bone_click(seed + 5, r.uniform(1800, 2300), 0.006), 0.25)])


def _rake(seed, sweep=(6500.0, 2300.0), claws=3, rip=1.0):
    """A claw rake: the bone tips bite (click), three claws drawn through
    (overlapping scratches, band moving with the stroke), the flesh rips."""
    d = 0.25
    r = rng(seed)
    ev = [(0.0, _bone_click(seed, r.uniform(2200, 2800), 0.008), 0.8)]
    t0 = 0.0
    for i in range(claws):
        dd = r.uniform(0.07, 0.1)
        f0 = sweep[0] * r.uniform(0.9, 1.1)
        f1 = sweep[1] * r.uniform(0.9, 1.1)
        ev.append((t0, _claw_scratch(dd, seed + 5 + i, f0, f1, 1.6), r.uniform(0.6, 0.9)))
        t0 += r.uniform(0.005, 0.009)
    ev.append((0.002, _rip(0.11, seed + 20), 0.75 * rip))
    ev.append((0.004, _flesh_hit(seed + 30, 0.45, 1.2, 0.7, d), 0.55 * rip))
    return place(d, ev)


def _flop(seed, weight=1.5, card=False):
    """The body collapses on stone: a heavy wet thump, a big squelch as the
    flesh spreads, claws and knees knocking the stone, and the card: creasing
    as it folds, or slapping flat as it topples (`card`)."""
    d = 0.55
    r = rng(seed)
    sd = 0.16
    sq = _norm(sweep_bandpass(pink(sd, seed + 1), 900, 220, q=1.8)) * env_points(sd, [(0, 0), (0.006, 1), (0.05, 0.55), (sd, 0)])
    # Heavy through its body and length rather than a sub peak: less thump,
    # more meat, a little saturation to keep the crest down.
    body = _flesh_hit(seed, weight, 1.5, 0.7, d, thump_gain=0.75, meat_gain=0.85)
    ev = [(0.0, body, 1.0), (0.002, sq, 0.4)]
    for i in range(4):
        ev.append((r.uniform(0.004, 0.06), _bone_click(seed + 10 + i, r.uniform(1700, 2600), 0.012), r.uniform(0.15, 0.32)))
    if card:
        ev.append((0.0, _card_slap(seed + 20), 0.45))
    else:
        ev.append((0.0, _paper_crease(seed + 20), 0.3))
    x = place(d, ev)
    return drive(x / np.max(np.abs(x)), 1.6)


def _gurgle(duration, seed, rate=28.0, scale=1.6):
    """Liquid in the throat: short, damped bubbles (350-1100 Hz, the pitch
    barely rising; `scale` 1.6 keeps each under ~40 ms to -20 dB, longer
    ones ring as flat 'boop' tones) thinning out over a soft lowpassed
    liquid wash, both coloured by the ghoul's nearly closed mouth."""
    r = rng(seed)
    times = random_times(duration, rate, seed + 1, 0.0, duration * 0.92, envelope=lambda u: (1 - u) ** 0.8)
    ev = []
    for i, tb in enumerate(times):
        u = tb / duration
        f = r.uniform(350, 1100) * (1 - 0.3 * u)
        ev.append((tb, _bubble(f, seed + 10 + i, r.uniform(0.05, 0.085), scale), r.uniform(0.3, 1.0) * (1 - 0.7 * u)))
    b = _norm(_tract(place(duration, ev), [(0, 0.25), (duration, 0.1)]))
    bed = lowpass(white(duration, seed + 9), 900, 2) * env_points(duration, [(0, 0), (0.02, 1), (duration, 0)])
    bed = _norm(_tract(bed, [(0, 0.2), (duration, 0.1)]))
    return _norm(b + 0.15 * bed)


# --------------------------------------------------------------------------
# The sounds

def _move_layers(seed):
    D = 0.95
    L = {}
    scrape = _card_scrape(D, seed, [(0, 0), (0.09, 0), (0.11, 0.55), (0.235, 0.4), (0.25, 1.0), (0.3, 0.7),
                                    (0.385, 0.45), (0.4, 1.0), (0.45, 0.7), (0.535, 0.5), (0.55, 0.95),
                                    (0.59, 0.8), (0.605, 0.55), (0.615, 0.0), (D, 0)])
    L["scrape"] = place(D, [(0.0, scrape, 0.4)])
    paws, hind = [], []
    for k, (tm, w) in enumerate(((0.24, 1.0), (0.39, 0.95), (0.54, 1.05))):
        paws.append((tm, _paw_land(seed + 10 + 7 * k, w), 1.0))
        hind.append((tm + 0.05, _hind_pad(seed + 40 + 5 * k), 0.35))
    L["paws"] = place(D, paws)
    L["hind"] = place(D, hind)
    # The card catches on the stone as it starts to move, and stops at 0.61
    # with a short skid of the claws.
    L["catch_skid"] = place(D, [(0.09, _claw_scratch(0.03, seed + 60, 3200, 2200, 1.2), 0.15),
                                (0.61, _claw_scratch(0.05, seed + 61, 4200, 2600, 1.4), 0.25)])
    # Ragged panting under the bounds: a breathy, low exhale pushed out by
    # each landing (each one a little different), a rasping intake between,
    # a small huff after the stop.
    r = rng(seed + 100)
    pants = []
    for k, tm in enumerate((0.25, 0.4, 0.55, 0.63)):
        j = r.uniform(0.9, 1.12)
        dd = r.uniform(0.10, 0.15) if k < 3 else 0.18
        v = _voice(dd, [(0, 82 * j), (dd, 64 * j)], [(0, 0.3), (0.03, 0.45), (dd, 0.25)],
                   [(0, 0), (0.02, 1), (0.055, 0.7), (dd, 0)], seed + 70 + k,
                   voiced=0.3, breath=1.0, rasp=0.7, jitter=0.05, hiss=0.15, grit=2.0)
        pants.append((tm, v, 0.32 if k < 3 else 0.2))
    L["pants"] = place(D, pants)
    intakes = []
    for k, tm in enumerate((0.165, 0.32, 0.47)):
        v = _voice(0.06, [(0, 150), (0.06, 170)], [(0, 0.8), (0.06, 0.9)], [(0, 0), (0.045, 1), (0.06, 0)],
                   seed + 80 + k, voiced=0.08, breath=1.0, rasp=0.5, hiss=0.5, grit=1.2)
        intakes.append((tm, v, 0.18))
    L["intakes"] = place(D, intakes)
    growl = _voice(D, [(0, 64), (0.5, 70), (D, 58)], [(0, 0.12), (D, 0.18)],
                   [(0, 0), (0.08, 0.5), (0.6, 0.6), (0.85, 0.3), (D, 0)], seed + 90,
                   voiced=0.85, breath=0.35, rasp=0.6, jitter=0.04, grit=1.5)
    L["growl"] = place(D, [(0.0, growl, 0.14)])
    return L


@sound("ghoul_move", loudness=-21, wet=0.16, marks=(0.09, 0.24, 0.39, 0.54, 0.61))
def ghoul_move(seed):
    """Three bounds on all fours: claws slap and scrape the stone at each
    landing (hind feet patter after), a ragged panting snarl under it, the
    card dragged over stone 0.09-0.61 in surges with each bound."""
    return _finish(_mixdown(_move_layers(seed)), 0.03)


def _windup_layers(seed):
    D = 0.6
    L = {}
    L["growl"] = _voice(D, [(0, 50), (0.15, 58), (0.45, 86), (D, 96)],
                        [(0, 0.05), (0.3, 0.25), (0.5, 0.55), (D, 0.6)],
                        [(0, 0), (0.08, 0.18), (0.3, 0.5), (0.5, 1.0), (0.56, 0.95), (D, 0)],
                        seed, voiced=0.85, breath=0.45, rasp=0.55, jitter=0.04, hiss=0.15, grit=2.2)
    r = rng(seed + 1)
    times = random_times(D, 45, seed + 2, 0.04, 0.58, envelope=lambda u: 0.3 + 0.7 * u)
    ev = []
    for i, tc in enumerate(times):
        p = r.random()
        grow = 0.45 + 0.55 * tc / D  # the clicks thicken with the growl
        if p < 0.55:    # saliva pops: short, barely rising
            ev.append((tc, _bubble(r.uniform(700, 1600), seed + 10 + i, 0.08, 2.0), r.uniform(0.4, 1.0) * grow))
        elif p < 0.85:  # tongue clicks: unpitched cavity ticks
            ev.append((tc, _wet_click(seed + 10 + i), r.uniform(0.5, 1.0) * grow))
        else:           # lips peeling off the teeth
            ev.append((tc, _smack(seed + 10 + i), r.uniform(0.4, 0.8) * grow))
    L["clicks"] = 0.5 * _norm(place(D, ev))
    flex = place(D, [(tf, _bone_click(seed + 60 + k, 2400 + 150 * k), 0.5)
                     for k, tf in enumerate((0.09, 0.18, 0.27, 0.36, 0.45))])
    L["flex"] = 0.25 * flex
    return L


@sound("ghoul_windup", loudness=-21, wet=0.2)
def ghoul_windup(seed):
    """Coiled to pounce: a guttural growl rising in pitch and opening up,
    wet clicks of saliva and tongue thickening, the claws flexing on the
    stone with the quiver of the pose (every 90 ms)."""
    return _finish(_mixdown(_windup_layers(seed)), 0.02)


def _attack_layers(seed):
    D = 0.9
    L = {}
    # The body's lunge: a low band that rises and falls, cresting before the
    # first rake so the snarl has the low mids to itself at the bite.
    lunge = _whoosh(0.22, seed, [(0.0, 240), (0.04, 650), (0.22, 330)], peak_at=0.15, q=1.0, fall=5.0)
    L["lunge"] = place(D, [(0.06, lunge, 0.34)])
    # Each claw cuts the air just before it bites (swells into the mark).
    swish1 = _whoosh(0.05, seed + 1, [(0, 2600), (0.05, 5000)], peak_at=0.95, q=1.2)
    swish2 = _whoosh(0.05, seed + 2, [(0, 2400), (0.05, 4600)], peak_at=0.95, q=1.2)
    L["swishes"] = place(D, [(0.118 - 0.05, swish1, 0.2), (0.243 - 0.05, swish2, 0.2)])
    L["rake1"] = place(D, [(0.118, _rake(seed + 10, (6800, 2200), 3, 1.0), 1.1)])   # down-stroke: band falls
    L["rake2"] = place(D, [(0.243, _rake(seed + 30, (2400, 6400), 3, 1.15), 1.05)])  # back-stroke: band rises
    L["land"] = place(D, [(0.33, _paw_land(seed + 50, 1.3), 0.7), (0.375, _hind_pad(seed + 55), 0.3)])
    # The card lands with the ghoul: a light slap and a short skid on the stone.
    skid = _card_scrape(0.08, seed + 71, [(0, 0), (0.004, 1.0), (0.035, 0.6), (0.08, 0)], center=2600)
    L["card"] = place(D, [(0.33, _card_slap(seed + 70), 0.18), (0.332, skid, 0.2)])
    # The snarl crests just after the first bite (the click still leads).
    snarl = _voice(0.55, [(0, 100), (0.05, 130), (0.08, 138), (0.25, 102), (0.55, 80)],
                   [(0, 0.35), (0.05, 0.78), (0.09, 0.85), (0.25, 0.45), (0.55, 0.2)],
                   [(0, 0), (0.04, 0.4), (0.085, 1.0), (0.11, 0.85), (0.22, 0.4), (0.38, 0.12), (0.55, 0)],
                   seed + 60, voiced=0.4, breath=0.8, rasp=0.7, jitter=0.05, hiss=0.25, grit=1.8, biphon=0.25)
    L["snarl"] = place(D, [(0.05, snarl, 0.75)])
    return L


@sound("ghoul_attack", loudness=-18, wet=0.18, marks=(0.06, 0.118, 0.243, 0.33))
def ghoul_attack(seed):
    """Pounce: a lunge whoosh from 0.06, two claw rakes (0.118 down-stroke,
    0.243 back-stroke: bone bite + scratches + flesh rip), lands on all
    fours at 0.33 with the card slapping down; a snarl peaks with the first
    rake."""
    return _finish(_mixdown(_attack_layers(seed)), 0.03)


def _hurt_layers(seed):
    D = 0.75
    L = {}
    # Less sine thump, more meat and slap: a muffled body, not a kick drum.
    hit = _flesh_hit(seed, 1.0, 1.3, 0.9, 0.5, thump_gain=0.8, meat_gain=0.75, slap=1.0)
    L["hit"] = place(D, [(0.118, hit, 1.0)])
    L["crumple"] = place(D, [(0.118, _paper_crumple(0.09, seed + 1), 0.65)])
    # The shriek answers 30 ms later (the hit and the paper get the clear):
    # mostly breath and rasp, two folds at a non-integer ratio, a falling
    # pitch that stays out of the human cry's clean glide.
    shriek = _voice(0.3, [(0, 220), (0.02, 290), (0.07, 260), (0.18, 170), (0.3, 120)],
                    [(0, 0.6), (0.0225, 0.8), (0.105, 0.64), (0.21, 0.36), (0.3, 0.24)],
                    [(0, 0), (0.006, 1.0), (0.045, 0.8), (0.1125, 0.42), (0.21, 0.12), (0.3, 0)],
                    seed + 2, voiced=0.35, breath=1.0, rasp=0.85, jitter=0.08, hiss=0.4, grit=2.4,
                    cycle=0.08, biphon=0.4, low_cut=450.0)
    L["shriek"] = place(D, [(0.15, shriek, 0.75)])
    r = rng(seed + 3)
    spit = place(0.15, [(r.uniform(0, 0.12), _bubble(r.uniform(400, 1200), seed + 10 + i, 0.08, 1.5), r.uniform(0.4, 1))
                        for i in range(5)])
    L["spit"] = place(D, [(0.5, _norm(spit), 0.05)])
    return L


@sound("ghoul_hurt", loudness=-18, wet=0.18, marks=(0.118,))
def ghoul_hurt(seed):
    """Struck: a wet meaty thud at 0.118 (thump + meat + slap + squelch +
    pops), the card crumples, and a sharp, ragged shriek-like snarl answers."""
    return _finish(_mixdown(_hurt_layers(seed)), 0.03)


def _death_layers(seed):
    D = 1.1
    L = {}
    L["hit"] = place(D, [(0.118, _flesh_hit(seed, 0.95, 1.1, 1.2, 0.45, thump_gain=0.85, meat_gain=0.7, slap=0.8), 1.0)])
    L["crumple"] = place(D, [(0.12, _paper_crumple(0.08, seed + 1), 0.4)])
    # A choked, breathy snarl in the growl register.
    choke = _voice(0.26, [(0, 150), (0.04, 185), (0.26, 80)], [(0, 0.4), (0.04, 0.55), (0.26, 0.2)],
                   [(0, 0), (0.01, 1), (0.07, 0.55), (0.18, 0.2), (0.26, 0)], seed + 2,
                   voiced=0.3, breath=1.0, rasp=0.85, jitter=0.07, hiss=0.5, grit=2.6)
    L["choke"] = place(D, [(0.125, choke, 0.5)])
    L["flop1"] = place(D, [(0.3, _flop(seed + 10, 1.5, card=False), 1.0)])
    L["flop2"] = place(D, [(0.62, _flop(seed + 30, 1.9, card=True), 1.15), (0.71, _flesh_hit(seed + 50, 0.6, 0.8, 0.5, 0.3), 0.3)])
    # Two rattling breaths (the second after the face-down fall), slowing.
    rattle = _voice(0.7, [(0, 46), (0.7, 32)], [(0, 0.3), (0.7, 0.12)],
                    [(0, 0), (0.04, 0.7), (0.2, 0.5), (0.26, 0.08), (0.34, 0.05), (0.4, 0.6), (0.55, 0.35), (0.7, 0)],
                    seed + 60, voiced=0.45, breath=0.7, rasp=0.95, jitter=0.1, grit=2.0)
    L["rattle"] = place(D, [(0.38, rattle, 0.3)])
    # Liquid in the throat: a hint as it drops to its knees, then the gurgle
    # proper once it lies face down, densest just after the fall, thinning out.
    L["gurgle"] = place(D, [(0.33, _gurgle(0.2, seed + 75, rate=40.0), 0.12),
                            (0.64, _gurgle(0.44, seed + 70, rate=100.0), 0.35)])
    return L


@sound("ghoul_death", loudness=-18, wet=0.3, marks=(0.118, 0.3, 0.62))
def ghoul_death(seed):
    """Struck at 0.118 (wet thud, a choked snarl, the card crumples), drops to
    its knees in a heavy wet flop at 0.3 (the card creases), falls on its face
    at 0.62 (heavier flop, the card slaps flat on the stone, a small bounce),
    and a gurgling death rattle fades out."""
    return _finish(_mixdown(_death_layers(seed)), 0.04)
