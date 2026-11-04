"""Family `flame`: the Lanciafiamme (docs/piano-ia.md, Fase 13; SOUND_SPEC.md), for now its card alone, provisional until the
plan's Fase 14.

- `card_flamethrower`, the card: the `cards_arms` family's paper flick, then a pilot light catching, a short rush of gas.

Every recipe keeps its peak at -1.5 dBFS or lower before the build's ceiling.
The marks are the recipe's own key moments in seconds; 0.0 is the first sound.
"""
from dsp import *  # noqa: F401,F403
from registry import sound
from sfx_cards_arms import _flick as _ca_flick
from sfx_world import _click, _finish, _limit, _norm


@sound("card_flamethrower", loudness=-20, wet=0.14, rt60=0.6, marks=(0.0, 0.16),
       note="provisional until Fase 14: the card flicks out, a click and a short rush of gas catching at 0.16")
def card_flamethrower(seed):
    D = 0.8
    rush_len = 0.45
    rush = sweep_bandpass(pink(rush_len, seed + 1), 400, 1400, q=0.9) * env_perc(rush_len, attack=0.03, decay=0.4, curve=2.0)
    x = place(D, [
        (0.0, _ca_flick(seed), 0.45),
        (0.16, _click(seed + 2, hp=1800, tau=0.0008), 0.3),
        (0.17, _norm(rush), 0.6),
    ])
    return _finish(_limit(x, 0.7), D, fade_out=0.1)
