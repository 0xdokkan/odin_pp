"""FIRST PERSON BRAWLER's sounds (docs/piano-prima-persona.md, Fase 3, passo 6),
made from code like the rest (SOUND_SPEC.md): real gloves with a touch of the
Neon style the user chose.

    pilgrim_fists_whoosh   a punch leaving: air torn past the glove (the lab
                           plays it higher for a jab, lower for a hook)
    world_fists_hit_jab    a landed jab: a light leather smack over a short
                           thud, a little electric crackle on top (the neon)
    world_fists_hit_cross  a landed cross: the same, heavier
    world_fists_hit_hook   a landed hook: the heaviest, with more body
    world_fists_crit       a critical: a hook's blow under a bright ding that
                           rings out, like the gold star, with a shimmer
    ui_fists_mark          a mark lighting: a light, bright tick (the lab
                           plays it at the pitch of its punch)
    world_ring_bell        the ring's bell as the gloves come up: two strikes,
                           the second ringing out
"""
import numpy as np

from dsp import *  # noqa: F401,F403
from registry import sound
from sfx_cards_arms import _norm, _out, _ramp, _thump


def _crackle(dur, seed, level):
    """The neon: a short electric buzz, a square at 2.2 kHz torn by noise,
    dying in 40 ms, above 1.8 kHz only."""
    t = time_axis(dur)
    buzz = square(2200 + 260 * np.sin(2 * np.pi * 37 * t), dur) * 0.5
    buzz = buzz + _norm(white(dur, seed)) * 0.6
    return _norm(highpass(buzz, 1800, 2)) * np.exp(-t / 0.04) * level


def _blow(seed, weight):
    """A glove landing, `weight` 0 (a jab) .. 1 (a hook): the thud deepens and
    lasts, the leather smack stays sharp, the crackle sits on top."""
    dur = 0.32
    t = time_axis(dur)
    thud = _thump(dur, seed, f0=170 - 50 * weight, f1=92 - 36 * weight, drop=0.012 + 0.008 * weight,
                  tau=0.028 + 0.035 * weight, lp=1300 - 500 * weight, noise=0.55, ntau=0.012)
    smack = _norm(lowpass(bandpass(white(dur, seed + 1), 850 - 200 * weight, 1.4), 2500, 2)) * np.exp(-t / (0.008 + 0.004 * weight))
    body = _norm(lowpass(brown(dur, seed + 2), 260, 2)) * np.exp(-t / (0.05 + 0.06 * weight)) * (0.25 + 0.45 * weight)
    x = _norm(thud + (0.55 - 0.15 * weight) * smack + body) + _crackle(dur, seed + 3, 0.06)
    return _ramp(x, 0.0005)


@sound("pilgrim_fists_whoosh", loudness=-25, wet=0.12, rt60=0.8, marks=(0.0, 0.06))
def pilgrim_fists_whoosh(seed):
    """Air torn past the glove: a band of noise sweeping up from 500 Hz to
    2.6 kHz as it swells to 0.06 s and dies by 0.16 s."""
    dur = 0.18
    t = time_axis(dur)
    air = sweep_bandpass(white(dur, seed), 500, 2600, 1.6)
    env = np.clip(t / 0.06, 0, 1) ** 2 * np.exp(-np.clip(t - 0.06, 0, None) / 0.035)
    return _out(_norm(air) * env, 0.03)


@sound("world_fists_hit_jab", loudness=-20, wet=0.16, rt60=0.9, marks=(0.0,))
def world_fists_hit_jab(seed):
    return _out(_blow(seed, 0.0), 0.06)


@sound("world_fists_hit_cross", loudness=-19, wet=0.17, rt60=0.9, marks=(0.0,))
def world_fists_hit_cross(seed):
    return _out(_blow(seed, 0.45), 0.06)


@sound("world_fists_hit_hook", loudness=-18, wet=0.18, rt60=1.0, marks=(0.0,))
def world_fists_hit_hook(seed):
    return _out(_blow(seed, 1.0), 0.06)


@sound("world_fists_crit", loudness=-17, wet=0.3, rt60=1.4, marks=(0.0, 0.02))
def world_fists_crit(seed):
    """A critical: a hook's blow, and 20 ms on a bright ding (FM at 2.1 kHz,
    an inharmonic partial over it) ringing out in half a second, a shimmer of
    high grains around it."""
    dur = 0.8
    t = time_axis(0.7)
    ding = fm(2100, 2100 * 1.41, 2.4 * np.exp(-t / 0.08), 0.7) * np.exp(-t / 0.28)
    ding = ding + 0.35 * fm(4700, 4700 * 1.73, 1.2 * np.exp(-t / 0.05), 0.7) * np.exp(-t / 0.14)
    shimmer = grains(0.5, random_times(0.5, 40, seed + 5), 0.004, seed + 6, band=(5000, 10000))
    x = place(dur, [
        (0.0, _blow(seed, 1.0), 0.9),
        (0.02, _ramp(_norm(ding), 0.001), 0.55),
        (0.04, _norm(shimmer) * np.exp(-time_axis(0.5) / 0.15), 0.18),
    ])
    return _out(x, 0.1)


@sound("ui_fists_mark", loudness=-29, wet=0.1, rt60=0.6, marks=(0.0,))
def ui_fists_mark(seed):
    """A light, bright tick: a 1.8 kHz blip over 30 ms with a click on its
    front."""
    dur = 0.05
    t = time_axis(dur)
    blip = sine(1800, dur) * np.exp(-t / 0.012)
    click = _norm(highpass(white(dur, seed), 4000, 2)) * np.exp(-t / 0.0008) * 0.4
    return _out(_ramp(_norm(blip + click), 0.0004), 0.015)


@sound("world_ring_bell", loudness=-18, wet=0.35, rt60=1.8, marks=(0.0, 0.22))
def world_ring_bell(seed):
    """The ring's bell: struck at 0 and at 0.22 s (a bright metal ding over
    a ringing body, a hammer's tick on each), the second ringing out over a
    second."""
    def strike(s, length, tail):
        t = time_axis(length)
        bell = fm(1180, 1180 * 1.41, 3.0 * np.exp(-t / 0.2), length) * np.exp(-t / tail)
        bell = bell + 0.45 * fm(2950, 2950 * 1.73, 1.5 * np.exp(-t / 0.12), length) * np.exp(-t / (tail * 0.55))
        bell = bell + 0.3 * sine(590, length) * np.exp(-t / (tail * 1.4))
        tick = _norm(highpass(white(0.006, s), 3000)) * 0.5
        bell[:len(tick)] += tick
        return _ramp(_norm(bell), 0.001)
    x = place(1.5, [
        (0.0, strike(seed, 0.4, 0.16), 0.8),
        (0.22, strike(seed + 1, 1.25, 0.45), 1.0),
    ])
    return _out(x, 0.12)
