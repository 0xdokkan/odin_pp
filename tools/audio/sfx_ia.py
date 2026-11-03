"""Family `ia`: the IA card (docs/piano-ia.md, SOUND_SPEC.md).

Fase 0 of the plan gives the card a provisional sound of its own (every card
has one: render/lab_sounds_test.odin); its real sounds are its Fase 8. The
recipe is dry and synthesized here (the build adds the stone hall); it reuses
the `cards_arms` family's paper flick and adds an electronic power-on:

- a hum that rises (two detuned sines gliding up an octave, a little square
  edge for the circuit's buzz);
- two short beeps a fifth apart;
- a clean chord (C major added ninth, soft sines) that rings out.

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
