"""Family `spider_nest`: the Nido di ragni (docs/piano-ia.md, Fase 10; SOUND_SPEC.md).

Dry and synthesized here (the build adds the stone hall); the card reuses the `cards_arms` family's paper flick:

- `card_spider_nest`, the card: the flick, a thread of silk zipping out, a dry skitter of little legs;
- `world_spider_place`, the nest set down: silk pulled tight, a rising strained band of noise, and the soft weight of the
  eggs settling;
- `world_spider_hatch`, a spiderling leaves: a few dry ticks of legs, quiet, it comes every two seconds;
- `world_spider_bite`, the bite: a small snap with a tiny body behind it;
- `world_spider_tear`, a blow on the nest: a short rip of silk, its grains coming faster;
- `world_spider_close`, the nest's end: the air going out of it, a band sinking, and a soft flop.

Every recipe keeps its peak at -1.5 dBFS or lower before the build's ceiling.
The marks are the recipe's own key moments in seconds; 0.0 is the first sound.
"""
import numpy as np

from dsp import *  # noqa: F401,F403
from registry import sound
from sfx_cards_arms import _flick as _ca_flick
from sfx_world import _click, _finish, _limit, _norm, _thud


def _hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def _leg(midi, seed):
    """One dry tick of a little leg on stone."""
    length = 0.016
    tone = sine(_hz(midi), length) + 0.5 * sine(_hz(midi) * 1.41, length)
    return _norm(tone * env_perc(length, attack=0.0008, decay=0.013, curve=4.0))


def _legs(count, step, seed, top=92):
    """A skitter: `count` ticks `step` apart, a little uneven, each its own pitch; as (time, sound, gain) events."""
    rand = rng(seed)
    return [(k * step + float(rand.uniform(0, step * 0.35)), _leg(top + (k * 5) % 7, seed + k), 0.5 + 0.2 * float(rand.random()))
            for k in range(count)]


def _silk(length, low, high, seed, q=5.0):
    """A strained thread: noise in a narrow band moving from `low` to `high`, trembling a little."""
    x = sweep_bandpass(white(length, seed), low, high, q=q)
    t = time_axis(length)
    return _norm(x) * (0.75 + 0.25 * np.sin(2 * np.pi * 37 * t))


@sound("card_spider_nest", loudness=-20, wet=0.14, rt60=0.6, marks=(0.0, 0.1, 0.3),
       note="the card flicks out, a thread of silk zips up at 0.1 (a noise band 1.2 to 4.5 kHz), a dry skitter from 0.3")
def card_spider_nest(seed):
    D = 0.85
    zip_len = 0.2
    thread = _silk(zip_len, 1200, 4500, seed + 1) * env_perc(zip_len, attack=0.02, decay=0.17, curve=2.5)
    x = place(D, [(0.0, _ca_flick(seed), 0.45), (0.1, _norm(thread), 0.34)]
              + [(0.3 + at, leg, gain * 0.6) for at, leg, gain in _legs(8, 0.04, seed + 2)])
    return _finish(_limit(x, 0.7), D, fade_out=0.1)


@sound("world_spider_place", loudness=-21, wet=0.16, rt60=0.6, marks=(0.0, 0.34),
       note="silk pulled tight: a strained band of noise rising 500 Hz to 2.6 kHz over 0.34, then the eggs' soft weight "
            "settling, a low thud with a short tail")
def world_spider_place(seed):
    D = 0.72
    pull_len = 0.36
    pull = _silk(pull_len, 500, 2600, seed, q=6.0) * env_swell(pull_len, peak_at=0.9, power=1.8)
    x = place(D, [
        (0.0, _norm(pull), 0.5),
        (0.34, _norm(_thud(0.26, seed + 1, f0=120.0, t60=0.14, lp=520, drop=0.6)), 0.75),
        (0.34, _click(seed + 2, hp=1200, tau=0.0007), 0.12),
    ])
    return _finish(_limit(x, 0.7), D, fade_out=0.08)


@sound("world_spider_hatch", loudness=-31, wet=0.08, rt60=0.4, marks=(0.0,),
       note="a few dry ticks of little legs over 0.14, quiet: it comes back every two seconds")
def world_spider_hatch(seed):
    D = 0.24
    x = place(D, _legs(5, 0.028, seed))
    return _finish(_limit(x, 0.75), D, fade_out=0.02)


@sound("world_spider_bite", loudness=-23, wet=0.08, rt60=0.4, marks=(0.0,),
       note="a small snap: a click and a short pop falling 2.4 kHz to 900 Hz, a tiny body under it")
def world_spider_bite(seed):
    D = 0.16
    pop_len = 0.05
    pop = sine(glide(2400.0, 900.0, pop_len), pop_len) * env_perc(pop_len, attack=0.0008, decay=0.042, curve=3.5)
    x = place(D, [
        (0.0, _click(seed, hp=1800, tau=0.0006), 0.5),
        (0.0, _norm(pop), 0.5),
        (0.004, _norm(_thud(0.09, seed + 1, f0=170.0, t60=0.06, lp=700, drop=0.5)), 0.4),
    ])
    return _finish(_limit(x, 0.75), D, fade_out=0.02)


@sound("world_spider_tear", loudness=-22, wet=0.14, rt60=0.5, marks=(0.0, 0.26),
       note="a short rip of silk: dry grains of noise coming faster up to 0.26, a band 2 to 5 kHz, ending at once")
def world_spider_tear(seed):
    D = 0.42
    rip_len = 0.26
    count = 34
    gaps = np.maximum(0.0035, 0.026 * (1.0 - np.linspace(0, 1, count)) ** 1.6)
    times = np.cumsum(gaps)
    times = times / times[-1] * rip_len
    grain_len = 0.006
    events = []
    for k, at in enumerate(times):
        grain = white(grain_len, seed + k) * env_perc(grain_len, attack=0.0005, decay=0.005, curve=4.0)
        events.append((float(at), grain, 0.45 + 0.4 * k / count))
    x = bandpass(place(D, events), 3200, q=0.8)
    return _finish(_limit(_norm(x) * 0.8, 0.7), D, fade_out=0.08)


@sound("world_spider_close", loudness=-23, wet=0.2, rt60=0.7, marks=(0.0, 0.5),
       note="the air going out of the nest: soft noise sinking 1.5 kHz to 200 Hz over 0.55, then a soft flop of silk")
def world_spider_close(seed):
    D = 0.95
    sigh_len = 0.6
    sigh = sweep_bandpass(pink(sigh_len, seed), 1500, 200, q=1.2) * env_perc(sigh_len, attack=0.04, decay=0.55, curve=1.8)
    x = place(D, [
        (0.0, _norm(sigh), 0.55),
        (0.5, _norm(_thud(0.3, seed + 1, f0=90.0, t60=0.16, lp=380, drop=0.5)), 0.6),
    ])
    return _finish(_limit(x, 0.7), D, fade_out=0.12)
