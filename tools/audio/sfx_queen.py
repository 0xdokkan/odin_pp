"""Family `queen`: the Regina (docs/piano-ia.md, Fase 12; SOUND_SPEC.md).

Dry and synthesized here (the build adds the stone hall); the card reuses the `cards_arms` family's paper flick:

- `card_queen`, the card: the flick, then a chess piece set down, a dry wooden clack with a little felt under it;
- `world_queen_place`, she is set down: the same «toc», fuller, a piece on a board;
- `world_queen_run`, her run: a quick rising rush of air, the piece's felt on the floor under it;
- `world_queen_strike`, her blow: a dry snap of wood on wood, a capture;
- `world_queen_fall`, her end: the piece tips, knocks, rocks in faster knocks and lies still.

Every recipe keeps its peak at -1.5 dBFS or lower before the build's ceiling.
The marks are the recipe's own key moments in seconds; 0.0 is the first sound.
"""
from dsp import *  # noqa: F401,F403
from registry import sound
from sfx_cards_arms import _flick as _ca_flick
from sfx_world import _click, _finish, _limit, _norm, _thud, _wood


def _toc(seed, base=520.0, t60=0.08):
    """A chess piece on a board: the wood's few modes and the small knock of its foot."""
    return _norm(_wood(0.2, base, seed, t60=t60)) * 0.8 + pad_to(_click(seed + 1, hp=1400, tau=0.0007), 0.2) * 0.25


@sound("card_queen", loudness=-20, wet=0.16, rt60=0.7, marks=(0.0, 0.16),
       note="the card flicks out, a chess piece set down at 0.16, a dry clack of wood with a little felt under it")
def card_queen(seed):
    D = 0.7
    x = place(D, [
        (0.0, _ca_flick(seed), 0.45),
        (0.16, _toc(seed + 1), 0.6),
        (0.16, _norm(_thud(0.12, seed + 3, f0=150.0, t60=0.06, lp=600, drop=0.5)), 0.25),
    ])
    return _finish(_limit(x, 0.7), D, fade_out=0.1)


@sound("world_queen_place", loudness=-21, wet=0.2, rt60=0.8, marks=(0.0,),
       note="a heavy chess piece set down on a board: a full wooden «toc» at 420 Hz, the board answering low")
def world_queen_place(seed):
    D = 0.5
    x = place(D, [
        (0.0, _toc(seed, base=420.0, t60=0.1), 0.7),
        (0.0, _norm(_thud(0.22, seed + 3, f0=110.0, t60=0.1, lp=480, drop=0.5)), 0.45),
    ])
    return _finish(_limit(x, 0.7), D, fade_out=0.08)


@sound("world_queen_run", loudness=-23, wet=0.12, rt60=0.5, marks=(0.0, 0.26),
       note="her run: a rush of air rising 500 Hz to 3.6 kHz, cresting at 0.26 and cut short as she arrives")
def world_queen_run(seed):
    D = 0.42
    rush_len = 0.3
    rush = sweep_bandpass(white(rush_len, seed), 500, 3600, q=2.5) * env_swell(rush_len, peak_at=0.85, power=2.0)
    felt_len = 0.28
    felt = sweep_bandpass(pink(felt_len, seed + 1), 300, 900, q=1.5) * env_swell(felt_len, peak_at=0.7, power=1.4)
    x = place(D, [(0.0, _norm(rush), 0.6), (0.0, _norm(felt), 0.3)])
    return _finish(_limit(x, 0.7), D, fade_out=0.09)


@sound("world_queen_strike", loudness=-20, wet=0.14, rt60=0.6, marks=(0.0,),
       note="her blow: a dry snap of wood on wood, a piece taken, higher and harder than her «toc»")
def world_queen_strike(seed):
    D = 0.32
    x = place(D, [
        (0.0, _click(seed, hp=2200, tau=0.0008), 0.5),
        (0.0, _toc(seed + 1, base=900.0, t60=0.05), 0.8),
        (0.0, _norm(_thud(0.14, seed + 3, f0=140.0, t60=0.08, lp=620, drop=0.6)), 0.5),
    ])
    return _finish(_limit(x, 0.7), D, fade_out=0.05)


@sound("world_queen_fall", loudness=-22, wet=0.2, rt60=0.8, marks=(0.0, 0.2, 0.32, 0.41, 0.47),
       note="the piece tips and knocks at 0.0, then rocks on its side, knocks coming faster and softer, and lies still")
def world_queen_fall(seed):
    D = 0.85
    knocks = [(0.0, 1.0), (0.2, 0.7), (0.32, 0.5), (0.41, 0.36), (0.47, 0.26), (0.51, 0.18)]
    x = place(D, [(at, _toc(seed + 2 * k, base=460.0 + 25.0 * k, t60=0.07), 0.7 * gain) for k, (at, gain) in enumerate(knocks)])
    return _finish(_limit(x, 0.7), D, fade_out=0.15)
