"""FIRST PERSON FENCER's sounds (docs/piano-prima-persona.md, Fase 5, passo 6),
made from code like the rest (SOUND_SPEC.md): the steel of a great sword with
the Neon style's hum and crackle, the user's choice.

    pilgrim_sword_draw         the zweihänder drawn as its view comes up: a long
                               steel scrape rising to a ring, the neon blade
                               humming up under it
    pilgrim_sword_whoosh       a swing: a heavy blade through the air, a band of
                               noise sweeping up with a low neon hum under it
                               (the lab plays it higher the faster the swing:
                               the centre of a swing's noise follows its speed,
                               Selfridge, Moffat and Reiss 2017)
    world_sword_cut            a cut landing: a crisp tear over a short thud, a
                               crackle of neon on top
    world_sword_cut_heavy      a heavy cut (a fendente, a strong blow): deeper,
                               a longer tear and more body
    world_sword_parry          a plain parry: a short dull clang of steel on
                               steel
    world_sword_parry_perfect  a perfect parry: a bright clang that rings out,
                               a shimmer round it (Sekiro's deflection rings
                               where its block thuds)
    world_sword_chain_throw    the grapple thrown: a chain rattling out over a
                               whip of air
    world_sword_chain_yank     the grapple caught: a hard metal snap, the chain
                               jerked taut, a thud
"""
import numpy as np

from dsp import *  # noqa: F401,F403
from registry import sound
from sfx_cards_arms import _norm, _out, _ramp, _thump


def _crackle(dur, seed, level, tau=0.04):
    """The neon: a short electric buzz above 1.8 kHz, dying in `tau`."""
    t = time_axis(dur)
    buzz = square(2400 + 300 * np.sin(2 * np.pi * 41 * t), dur) * 0.5
    buzz = buzz + _norm(white(dur, seed)) * 0.6
    return _norm(highpass(buzz, 1800, 2)) * np.exp(-t / tau) * level


def _clang(dur, seed, base, decay, brightness):
    """Steel struck on steel: inharmonic blade modes at `base`, their ring
    `decay` seconds, a hard tick on the front, `brightness` 0..1 lifting the
    upper partials."""
    modes = metal_modes(base, count=10, spread=1.0, decay=decay, seed=seed)
    modes = [(f, d, a * (1 + brightness * i * 0.25)) for i, (f, d, a) in enumerate(modes)]
    ring = modal(dur, modes, seed=seed)
    tick = _norm(highpass(white(0.008, seed + 1), 3500, 2)) * np.exp(-time_axis(0.008) / 0.0015)
    ring[:len(tick)] += tick * 0.8
    # Faded at its end, never cut off (a click).
    return fade(_ramp(_norm(ring), 0.0005), 0.0, min(0.08, dur * 0.25))


@sound("pilgrim_sword_draw", loudness=-21, wet=0.25, rt60=1.4, marks=(0.0, 0.32))
def pilgrim_sword_draw(seed):
    """Drawn: a scrape of steel (a narrow band of noise gliding up from 2.2 to
    5.5 kHz) over 0.32 s, then the blade rings free; a neon hum (a saw at
    110 Hz through a band rising to 900 Hz) swells under it."""
    dur = 1.2
    scrape_t = time_axis(0.34)
    scrape = sweep_bandpass(white(0.34, seed), 2200, 5500, 6.0)
    scrape = _norm(scrape) * np.clip(scrape_t / 0.04, 0, 1) * (0.6 + 0.4 * scrape_t / 0.34)
    t = time_axis(dur)
    hum = sweep_bandpass(saw(110, dur) + 0.5 * saw(165, dur), 250, 900, 2.0)
    hum = fade(_norm(hum) * np.clip(t / 0.35, 0, 1) ** 2 * np.exp(-np.clip(t - 0.4, 0, None) / 0.3), 0.0, 0.2)
    x = place(dur, [
        (0.0, _ramp(scrape, 0.002), 0.7),
        (0.0, hum, 0.35),
        (0.30, _clang(0.9, seed + 2, 1650, 0.6, 0.6), 0.55),
        (0.30, _crackle(0.2, seed + 3, 1.0, 0.06), 0.18),
    ])
    return _out(x, 0.15)


@sound("pilgrim_sword_whoosh", loudness=-23, wet=0.14, rt60=0.9, marks=(0.0, 0.11))
def pilgrim_sword_whoosh(seed):
    """A great blade through the air: noise in a band sweeping up from 260 Hz
    to 1.5 kHz as it swells to 0.11 s and dies by 0.3 s, broader than a fist's;
    a low neon hum (FM at 95 Hz) riding it."""
    dur = 0.32
    t = time_axis(dur)
    air = sweep_bandpass(white(dur, seed), 260, 1500, 1.3)
    env = np.clip(t / 0.11, 0, 1) ** 2 * np.exp(-np.clip(t - 0.11, 0, None) / 0.06)
    hum = fm(95, 190, 1.5, dur) * env
    return _out(_norm(_norm(air) * env + 0.18 * hum), 0.04)


def _cut(seed, weight):
    """A cut landing, `weight` 0 (light) .. 1 (heavy): the tear (high noise
    torn fast) lengthens, the thud deepens, the crackle on top."""
    dur = 0.36
    t = time_axis(dur)
    tear = _norm(highpass(bandpass(white(dur, seed), 3200 - 900 * weight, 0.9), 1200, 2))
    tear = tear * np.exp(-t / (0.018 + 0.025 * weight))
    thud = _thump(dur, seed + 1, f0=150 - 40 * weight, f1=80 - 25 * weight, drop=0.012, tau=0.03 + 0.04 * weight,
                  lp=1100 - 300 * weight, noise=0.5, ntau=0.014)
    body = _norm(lowpass(brown(dur, seed + 2), 300, 2)) * np.exp(-t / (0.04 + 0.06 * weight)) * (0.2 + 0.4 * weight)
    x = _norm(0.8 * tear + (0.6 + 0.3 * weight) * thud + body) + _crackle(dur, seed + 3, 0.08)
    return _ramp(x, 0.0004)


@sound("world_sword_cut", loudness=-20, wet=0.16, rt60=0.9, marks=(0.0,))
def world_sword_cut(seed):
    return _out(_cut(seed, 0.0), 0.06)


@sound("world_sword_cut_heavy", loudness=-18, wet=0.2, rt60=1.0, marks=(0.0,))
def world_sword_cut_heavy(seed):
    return _out(_cut(seed, 1.0), 0.07)


@sound("world_sword_parry", loudness=-19, wet=0.18, rt60=1.0, marks=(0.0,))
def world_sword_parry(seed):
    """A plain parry: a dull clang at 520 Hz whose ring dies in a fifth of a
    second, low passed: a block, not a deflection."""
    x = lowpass(_clang(0.45, seed, 520, 0.2, 0.0), 2600, 2)
    return _out(_norm(x), 0.08)


@sound("world_sword_parry_perfect", loudness=-16, wet=0.32, rt60=1.6, marks=(0.0, 0.02))
def world_sword_parry_perfect(seed):
    """A perfect parry: a bright clang at 1.24 kHz ringing out over a second,
    an FM shine over it and a shimmer of high grains."""
    dur = 1.3
    t = time_axis(1.1)
    shine = fm(2480, 2480 * 1.41, 2.0 * np.exp(-t / 0.1), 1.1) * np.exp(-t / 0.35)
    shimmer = grains(0.6, random_times(0.6, 45, seed + 5), 0.004, seed + 6, band=(5000, 11000))
    x = place(dur, [
        (0.0, _clang(1.2, seed, 1240, 0.9, 1.0), 0.9),
        (0.02, fade(_ramp(_norm(shine), 0.001), 0.0, 0.2), 0.4),
        (0.03, fade(_norm(shimmer) * np.exp(-time_axis(0.6) / 0.18), 0.0, 0.1), 0.15),
        (0.0, _crackle(0.2, seed + 7, 1.0, 0.05), 0.12),
    ])
    return _out(x, 0.12)


def _rattle(dur, seed, rate, band=(2800, 8000)):
    """A chain's links knocking: short metal grains at `rate` a second."""
    return _norm(grains(dur, random_times(dur, rate, seed), 0.006, seed + 1, band=band))


@sound("world_sword_chain_throw", loudness=-22, wet=0.15, rt60=0.9, marks=(0.0, 0.12))
def world_sword_chain_throw(seed):
    """The grapple thrown: a whip of air (a band sweeping 700 Hz to 3 kHz) and
    the chain rattling out after it over 0.15 s."""
    dur = 0.3
    t = time_axis(dur)
    whip = sweep_bandpass(white(dur, seed), 700, 3000, 1.8)
    whip = _norm(whip) * np.clip(t / 0.05, 0, 1) * np.exp(-np.clip(t - 0.05, 0, None) / 0.05)
    rattle = _rattle(0.2, seed + 2, 120) * np.exp(-time_axis(0.2) / 0.08)
    x = place(dur, [(0.0, whip, 0.7), (0.02, rattle, 0.6)])
    return _out(x, 0.05)


@sound("world_sword_chain_yank", loudness=-19, wet=0.18, rt60=1.0, marks=(0.0,))
def world_sword_chain_yank(seed):
    """Caught: a hard metal snap (a short clang at 900 Hz), the chain jerked
    taut (a dense rattle), a body thud under them."""
    dur = 0.4
    x = place(dur, [
        (0.0, _clang(0.3, seed, 900, 0.08, 0.4), 0.7),
        (0.0, _rattle(0.12, seed + 3, 260) * np.exp(-time_axis(0.12) / 0.04), 0.5),
        (0.01, _thump(0.3, seed + 4, f0=130, f1=70, drop=0.015, tau=0.05, lp=900, noise=0.5), 0.6),
    ])
    return _out(x, 0.06)
