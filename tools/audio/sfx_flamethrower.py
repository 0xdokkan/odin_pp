"""Family `flamethrower`: the Lanciafiamme (docs/piano-ia.md, Fase 14; SOUND_SPEC.md).

Dry and synthesized here (the build adds the stone hall); the card reuses the `cards_arms` family's paper flick:

- `card_flamethrower`, the card: the flick, then a pilot light catching, a click and a short rush of gas;
- `world_flame_on`, the button pressed: the igniter's two clicks and the gas taking;
- `world_flame_roar`, its roar: filtered noise that breathes, a clip that comes back every half second, so it swells from
  silence and sinks to it and the clips overlap;
- `world_flame_off`, let go: the breath of the last gas, sinking;
- `world_flame_crackle`, a foe touched: dry crackling grains;
- `world_flame_catch`, a barrel or the floor taking fire: a dull soft thump and a small whoosh.

Every recipe keeps its peak at -1.5 dBFS or lower before the build's ceiling.
The marks are the recipe's own key moments in seconds; 0.0 is the first sound.
"""
import numpy as np

from dsp import *  # noqa: F401,F403
from registry import sound
from sfx_cards_arms import _flick as _ca_flick
from sfx_world import _click, _finish, _limit, _norm, _thud


def _gas(length, low, high, seed):
    """A rush of gas: pink noise in a wide band moving from `low` to `high`."""
    return sweep_bandpass(pink(length, seed), low, high, q=0.9)


@sound("card_flamethrower", loudness=-20, wet=0.14, rt60=0.6, marks=(0.0, 0.16),
       note="the card flicks out, a click and a short rush of gas catching at 0.16")
def card_flamethrower(seed):
    D = 0.8
    rush_len = 0.45
    rush = _gas(rush_len, 400, 1400, seed + 1) * env_perc(rush_len, attack=0.03, decay=0.4, curve=2.0)
    x = place(D, [
        (0.0, _ca_flick(seed), 0.45),
        (0.16, _click(seed + 2, hp=1800, tau=0.0008), 0.3),
        (0.17, _norm(rush), 0.6),
    ])
    return _finish(_limit(x, 0.7), D, fade_out=0.1)


@sound("world_flame_on", loudness=-22, wet=0.12, rt60=0.5, marks=(0.0, 0.05, 0.09),
       note="the igniter: two dry clicks 50 ms apart, then the gas takes with a soft rising whoomp from 0.09")
def world_flame_on(seed):
    D = 0.42
    take_len = 0.3
    take = _gas(take_len, 300, 1500, seed + 2) * env_perc(take_len, attack=0.05, decay=0.24, curve=1.6)
    x = place(D, [
        (0.0, _click(seed, hp=2200, tau=0.0006), 0.45),
        (0.05, _click(seed + 1, hp=2600, tau=0.0005), 0.4),
        (0.09, _norm(take), 0.75),
    ])
    return _finish(_limit(x, 0.7), D, fade_out=0.08)


@sound("world_flame_roar", loudness=-24, wet=0.03, rt60=0.3, marks=(0.0, 0.35),
       note="half a second of the roar and its overlap: low filtered noise breathing eight times a second, a hiss over it, "
            "swelling from silence and sinking to it; nearly dry, so the clips do not smear")
def world_flame_roar(seed):
    D = 0.7
    t = time_axis(D)
    env = np.sin(np.pi * np.clip(t / D, 0, 1)) ** 1.2
    breath = 0.72 + 0.28 * np.sin(2 * np.pi * 8.0 * t + 0.7) * np.sin(2 * np.pi * 3.1 * t + 0.2)
    low = lowpass(brown(D, seed), 620, 2)
    mid = bandpass(pink(D, seed + 1), 800, q=0.9)
    hiss = lowpass(highpass(white(D, seed + 2), 2200, 2), 5200, 2)
    x = (_norm(low) * 0.9 + _norm(mid) * 0.5 + _norm(hiss) * 0.02) * breath * env
    return _finish(_limit(_norm(x) * 0.8, 0.7), D, fade_out=0.04)


@sound("world_flame_off", loudness=-24, wet=0.16, rt60=0.6, marks=(0.0,),
       note="the button let go: the last gas sighing out, a band sinking 1.4 kHz to 300 Hz over 0.4 and a tiny pop of the flame")
def world_flame_off(seed):
    D = 0.55
    sigh_len = 0.42
    sigh = _gas(sigh_len, 1400, 300, seed) * env_perc(sigh_len, attack=0.01, decay=0.38, curve=2.2)
    x = place(D, [(0.0, _norm(sigh), 0.7), (0.02, _click(seed + 1, hp=900, tau=0.001), 0.12)])
    return _finish(_limit(x, 0.7), D, fade_out=0.08)


@sound("world_flame_crackle", loudness=-25, wet=0.08, rt60=0.4, marks=(0.0,),
       note="a foe touched: dry crackling grains over 0.3, thinning out")
def world_flame_crackle(seed):
    D = 0.36
    x = crackle(D, 60.0, seed, decay=0.0016)
    x = bandpass(x, 2600, q=0.7) * env_perc(D, attack=0.002, decay=0.3, curve=2.0)
    return _finish(_limit(_norm(x) * 0.8, 0.7), D, fade_out=0.04)


@sound("world_flame_catch", loudness=-21, wet=0.2, rt60=0.8, marks=(0.0,),
       note="a barrel or the floor taking fire: a dull soft thump and a small whoosh rising and gone by 0.5")
def world_flame_catch(seed):
    D = 0.6
    whoosh_len = 0.42
    whoosh = _gas(whoosh_len, 240, 1000, seed + 1) * env_perc(whoosh_len, attack=0.02, decay=0.38, curve=2.0)
    x = place(D, [
        (0.0, _norm(_thud(0.26, seed, f0=84.0, t60=0.14, lp=420, drop=0.7)), 0.8),
        (0.01, _norm(whoosh), 0.5),
    ])
    return _finish(_limit(x, 0.7), D, fade_out=0.1)
