"""Family `napoli`: Benvenuti a Napoli (docs/piano-napoli.md, SOUND_SPEC.md).

Fase 0 of the plan gives the card a provisional sound of its own (every card
has one: render/lab_sounds_test.odin); the card's real sounds and its
tarantella are its Fase 6. The recipe is dry and synthesized here (the build
adds the stone hall); it reuses the `cards_arms` family's paper flick and bone
dice, as the Dinosauro's card does, and adds a mandolin:

- the mandolin (_mandolin): each note is a course of two steel strings tuned a
  few cents apart (Karplus-Strong, bright, short), picked in fast tremolo, the
  way a Neapolitan mandolin holds a note; a little body resonance at 450 Hz.

The sting is the Neapolitan cadence, the chord the city gave its name to:
B-flat major (the "Neapolitan sixth" of A minor), E major, A minor, three
tremolo chords and a last plucked one (Open Music Theory, "The Neapolitan
sixth"; the mandolin's tremolo on paired unison strings: Wikipedia,
"Mandolin"). Every recipe keeps its peak at -1.5 dBFS
or lower before the build's ceiling, like the world family. The marks are the
recipe's own key moments in seconds; 0.0 is always the first sound.
"""
import numpy as np

from dsp import *  # noqa: F401,F403
from registry import sound
from sfx_cards_arms import _clatter as _ca_clatter
from sfx_cards_arms import _die as _ca_die
from sfx_cards_arms import _flick as _ca_flick
from sfx_world import _finish, _limit, _norm, _wood


def _hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def _pluck(midi, length, seed, detune_cents=4.0):
    """One pick on a course of two strings, a few cents apart."""
    f = _hz(midi)
    a = karplus(f, length, damping=0.993, brightness=0.6, seed=seed)
    b = karplus(f * 2 ** (detune_cents / 1200), length, damping=0.993, brightness=0.55, seed=seed + 1)
    x = (a + 0.85 * b) * env_perc(length, attack=0.001, decay=length * 0.8, curve=3.0)
    return lowpass(peak_eq(x, 450, 4.0, q=1.2), 5200, 2)


def _mandolin(chord, duration, rate, seed, accent=1.0):
    """A chord (MIDI notes) held in tremolo: the pick goes up and down `rate`
    times a second, each stroke over the notes a hair apart, the first louder."""
    out = silence(duration + 0.4)
    r = rng(seed)
    t = 0.0
    k = 0
    while t < duration:
        for j, midi in enumerate(chord if k % 2 == 0 else chord[::-1]):
            at = t + j * 0.006 + r.uniform(0, 0.003)
            gain = (0.55 + 0.25 * r.random()) * (accent if k == 0 else 1.0)
            s = _pluck(midi, 0.22, seed + 10 * k + j)
            i = int(round(at * SR))
            e = min(len(out), i + len(s))
            out[i:e] += gain * s[:e - i]
        t += 1.0 / rate
        k += 1
    return out


@sound("card_napoli", loudness=-19, wet=0.22, rt60=0.9, marks=(0.0, 0.05, 0.5, 0.62, 0.86, 1.1, 1.36),
       note="the card flicks out and a bone d4 is rattled in a cupped hand (0.05-0.5: four shakes, settling in a few ticks at "
            "0.5), then a mandolin in tremolo plays the Neapolitan cadence: B-flat major at 0.62, E major at 0.86, A minor at "
            "1.1, and a last plucked A minor at 1.36 that rings out by 2.0")
def card_napoli(seed):
    D = 2.05
    r = rng(seed + 1)
    shake = []
    for s0 in (0.05, 0.14, 0.23, 0.32):
        for k in range(int(r.integers(5, 8))):
            shake.append((s0 + min(r.exponential(0.012), 0.04), r.uniform(0.35, 1.0)))
    for s0, a in ((0.4, 0.5), (0.43, 0.3), (0.46, 0.22), (0.5, 0.18), (0.52, 0.08)):
        shake.append((s0, a))
    dice = [lowpass(_ca_die(seed + 40 + j, table=False), 7000, 2) for j in range(4)]
    table = _ca_clatter(D, sorted(shake), [_wood(0.1, b, seed + 50 + j, t60=0.07, contact=0.25) for j, b in enumerate((190, 230, 270))], seed + 3)
    rattle = _ca_clatter(D, sorted(shake), dice, seed + 2)
    # B-flat major over D (the Neapolitan sixth), E major over G-sharp, A minor, A minor plucked.
    neapolitan = _mandolin((62, 65, 70, 74), 0.22, 16, seed + 100, accent=1.2)
    dominant = _mandolin((56, 64, 68, 71), 0.22, 16, seed + 200, accent=1.2)
    tonic = _mandolin((57, 64, 69, 72), 0.24, 16, seed + 300, accent=1.2)
    last = sum((_pluck(m, 0.7, seed + 400 + j) * (1.0 - 0.1 * j) for j, m in enumerate((45, 57, 64, 69, 72))), silence(0.7))
    x = place(D, [
        (0.0, _ca_flick(seed), 0.5),
        (0.0, _norm(rattle), 0.5),
        (0.0, _norm(table), 0.28),
        (0.62, _norm(neapolitan), 0.62),
        (0.86, _norm(dominant), 0.62),
        (1.1, _norm(tonic), 0.62),
        (1.36, _norm(last), 0.75),
    ])
    return _finish(_limit(x, 0.7), D, fade_out=0.3)
