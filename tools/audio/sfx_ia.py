"""Family `ia`: the IA card (docs/piano-ia.md, Fase 8; SOUND_SPEC.md), and for now the Nido di ragni's card
(`card_spider_nest`, provisional until the plan's Fase 10).

The card's four sounds, dry and synthesized here (the build adds the stone hall); `card_ia` reuses the `cards_arms`
family's paper flick and adds an electronic power-on:

- `card_ia`, the power-on: a hum that rises (two detuned sines gliding up an octave, a little square edge for the
  circuit's buzz), two short beeps a fifth apart, a clean chord (C major added ninth, soft sines) that rings out;
- `ia_tick`, the advice changes: one very light tick, high and short, to be heard often without tiring;
- `ia_warn`, the warning: two short notes falling a minor third, a touch of square edge so that it cuts through;
- `ia_off`, the power-off: the chord's two top notes falling away and a hum sinking an octave.

Every recipe keeps its peak at -1.5 dBFS or lower before the build's ceiling.
The marks are the recipe's own key moments in seconds; 0.0 is the first sound.
"""
import numpy as np

from dsp import *  # noqa: F401,F403
from registry import sound
from sfx_cards_arms import _flick as _ca_flick
from sfx_world import _finish, _limit, _norm


def _hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def _beep(midi, length):
    """A short sine beep with a soft click of attack."""
    tone = sine(_hz(midi), length) + 0.25 * sine(_hz(midi) * 2, length)
    return tone * env_perc(length, attack=0.004, decay=length * 0.8, curve=3.0)


@sound("card_ia", loudness=-19, wet=0.18, rt60=0.8, marks=(0.0, 0.08, 0.5, 0.62, 0.76),
       note="the card flicks out, a hum rises an octave (0.08-0.5) as a circuit wakes, two beeps a fifth apart "
            "(0.5, 0.62), then a clean C major added-ninth chord at 0.76 rings out by 1.6")
def card_ia(seed):
    D = 1.7
    rise = 0.42
    path = glide(110.0, 220.0, rise)
    hum = sine(path, rise) + 0.6 * sine(path * 1.004, rise) + 0.12 * square(path * 2, rise)
    hum = lowpass(hum, 2400, 2) * env_swell(rise, peak_at=0.85, power=1.6)
    chord_len = 0.9
    chord = sum((sine(_hz(m), chord_len) * (1.0 - 0.12 * j) for j, m in enumerate((60, 64, 67, 74))), silence(chord_len))
    chord = chord * env_perc(chord_len, attack=0.01, decay=0.75, curve=2.5)
    x = place(D, [
        (0.0, _ca_flick(seed), 0.45),
        (0.08, _norm(hum), 0.42),
        (0.5, _norm(_beep(84, 0.09)), 0.5),
        (0.62, _norm(_beep(91, 0.09)), 0.5),
        (0.76, _norm(chord), 0.6),
    ])
    return _finish(_limit(x, 0.7), D, fade_out=0.25)


@sound("ia_tick", loudness=-30, wet=0.1, rt60=0.4, marks=(0.0,),
       note="one light high tick of a circuit, 35 ms and a little air: the advice has changed")
def ia_tick(seed):
    D = 0.12
    length = 0.035
    tick = sine(_hz(100), length) + 0.4 * sine(_hz(107), length)
    tick = tick * env_perc(length, attack=0.001, decay=0.03, curve=4.0)
    return _finish(_limit(place(D, [(0.0, _norm(tick), 0.6)]), 0.8), D, fade_out=0.02)


@sound("ia_warn", loudness=-22, wet=0.12, rt60=0.5, marks=(0.0, 0.13),
       note="two short notes falling a minor third (E6 to C#6), a little square edge: a move that costs life")
def ia_warn(seed):
    D = 0.42

    def note(midi):
        length = 0.11
        tone = sine(_hz(midi), length) + 0.22 * square(_hz(midi), length) + 0.2 * sine(_hz(midi) * 2, length)
        return _norm(lowpass(tone, 5200, 2) * env_perc(length, attack=0.003, decay=0.095, curve=2.2))

    return _finish(_limit(place(D, [(0.0, note(88), 0.6), (0.13, note(85), 0.6)]), 0.75), D, fade_out=0.08)


@sound("ia_off", loudness=-24, wet=0.2, rt60=0.9, marks=(0.0, 0.14, 0.3),
       note="the power-on undone: two beeps falling a fifth (0, 0.14), then a hum sinking an octave and dying by 0.9")
def ia_off(seed):
    D = 1.05
    fall = 0.62
    path = glide(220.0, 110.0, fall)
    hum = sine(path, fall) + 0.6 * sine(path * 0.996, fall) + 0.1 * square(path * 2, fall)
    hum = lowpass(hum, 1800, 2) * env_perc(fall, attack=0.02, decay=0.6, curve=2.2)
    x = place(D, [
        (0.0, _norm(_beep(91, 0.09)), 0.42),
        (0.14, _norm(_beep(84, 0.09)), 0.42),
        (0.3, _norm(hum), 0.42),
    ])
    return _finish(_limit(x, 0.7), D, fade_out=0.2)


@sound("card_spider_nest", loudness=-20, wet=0.14, rt60=0.6, marks=(0.0, 0.12),
       note="provisional until Fase 10: the card flicks out, a dry skitter of little legs from 0.12")
def card_spider_nest(seed):
    D = 0.8
    legs = []
    for k in range(9):
        length = 0.018
        tick = sine(_hz(92 + (k * 5) % 7), length) * env_perc(length, attack=0.001, decay=0.015, curve=4.0)
        legs.append((0.12 + k * 0.045, _norm(tick), 0.32 + 0.04 * (k % 3)))
    x = place(D, [(0.0, _ca_flick(seed), 0.45)] + legs)
    return _finish(_limit(x, 0.7), D, fade_out=0.1)
