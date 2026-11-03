"""Family `queen`: the Regina (docs/piano-ia.md, Fase 11; SOUND_SPEC.md), for now her card alone, provisional until the
plan's Fase 12.

- `card_queen`, the card: the `cards_arms` family's paper flick, then a chess piece set down on stone, a dry wooden clack.

Every recipe keeps its peak at -1.5 dBFS or lower before the build's ceiling.
The marks are the recipe's own key moments in seconds; 0.0 is the first sound.
"""
from dsp import *  # noqa: F401,F403
from registry import sound
from sfx_cards_arms import _flick as _ca_flick
from sfx_world import _finish, _limit, _norm, _wood


@sound("card_queen", loudness=-20, wet=0.16, rt60=0.7, marks=(0.0, 0.16),
       note="provisional until Fase 12: the card flicks out, a chess piece set down at 0.16, a dry clack of wood on stone")
def card_queen(seed):
    D = 0.7
    x = place(D, [(0.0, _ca_flick(seed), 0.45), (0.16, _norm(_wood(0.2, 520.0, seed + 1, t60=0.08)), 0.6)])
    return _finish(_limit(x, 0.7), D, fade_out=0.1)
