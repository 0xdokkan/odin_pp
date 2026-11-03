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
import os

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


# --------------------------------------------------------------------------
# Fase 6 (the user's choices of 2026-11-03): the card's own sounds. Where a CC0
# recording was found (Freesound, each sound's page checked: Creative Commons 0)
# the recipe starts from a cut of it, kept in tools/audio/cc0 (its source and
# licence: assets/audio/LICENZE.md); the rest is made here. The build
# masters them all alike (loudness, the stone hall).

CC0_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cc0")


def _cc0(name):
    """A CC0 cut (tools/audio/cc0/<name>.wav), mono at dsp.SR."""
    return read_wav(os.path.join(CC0_DIR, name + ".wav"))


@sound("napoli_club_hit", loudness=-14, wet=0.18, rt60=0.8, marks=(0.0,),
       note="the ace of clubs comes down on a foe: a wooden stick's whack on something soft (CC0, bmacphail) over a low "
            "thud of its weight")
def napoli_club_hit(seed):
    whack = _norm(_cc0("napoli_whack"))
    D = max(0.7, len(whack) / SR)
    thud = sine(68, D) * env_perc(D, attack=0.002, decay=0.16, curve=3.0)
    return _finish(_limit(place(D, [(0.0, whack, 0.9), (0.0, thud, 0.45)]), 0.75), D)


@sound("napoli_club_floor", loudness=-21, wet=0.2, rt60=0.9, marks=(0.0,),
       note="the club on the floor: the same whack, lower and duller, and a puff of dust")
def napoli_club_floor(seed):
    whack = lowpass(resample(_norm(_cc0("napoli_whack")), 0.78), 2200, 2)
    D = max(0.75, len(whack) / SR)
    dust = bandpass(white(0.3, seed), 1800, 0.8) * env_perc(0.3, attack=0.01, decay=0.12, curve=2.0)
    return _finish(place(D, [(0.0, _norm(whack), 0.85), (0.01, _norm(dust), 0.25)]), D)


@sound("napoli_boing", loudness=-17, wet=0.12, rt60=0.7, marks=(0.0,),
       note="the struck card squashes and springs back: a jaw harp's boing (CC0, magnuswaker)")
def napoli_boing(seed):
    x = _norm(_cc0("napoli_boing"))
    return _finish(x, len(x) / SR, fade_out=0.05)


@sound("napoli_swing", loudness=-24, wet=0.1, rt60=0.6, marks=(0.0, 0.25),
       note="the club raised and brought down: a short whoosh rising to the blow at 0.25")
def napoli_swing(seed):
    D = 0.34
    air = sweep_bandpass(white(D, seed), 380, 1700, q=1.6) * env_swell(D, peak_at=0.72, power=2.5)
    return _finish(air, D, fade_out=0.04)


@sound("napoli_stars", loudness=-24, wet=0.3, rt60=1.2, marks=(0.0, 0.07, 0.14),
       note="the stars round a staggered foe's head: three little bells, C, E, G two octaves up")
def napoli_stars(seed):
    D = 0.8
    parts = []
    for j, f in enumerate((2093.0, 2637.0, 3136.0)):
        tone = sine(f, D) + 0.35 * sine(f * 2.76, D) + 0.12 * sine(f * 5.4, D)
        parts.append((j * 0.07, tone * env_perc(D, attack=0.001, decay=0.28, curve=3.0), 0.5))
    return _finish(place(D, parts), D, fade_out=0.1)


@sound("napoli_pocket", loudness=-22, wet=0.15, rt60=0.8, marks=(0.0, 0.84, 1.2),
       note="the grandpa's giant club comes out of his pocket: cloth rustles, and a slide whistle climbs as it grows "
            "longer and longer, then a pop as it is out at 1.2")
def napoli_pocket(seed):
    D = 1.3
    rustle = grains(D, random_times(D, 30, seed, end=0.9), 0.03, seed + 1, band=(600, 4000))
    t = time_axis(1.0)
    pitch = 320 * (1200 / 320) ** (t / 1.0) * (1 + 0.012 * np.sin(2 * np.pi * 6.0 * t))
    whistle = sine(pitch, 1.0) * env_adsr(1.0, 0.05, 0.1, 0.8, 0.15)
    pop = sine(900, 0.08) * env_perc(0.08, attack=0.001, decay=0.03)
    return _finish(place(D, [(0.0, _norm(rustle), 0.35), (0.12, _norm(whistle), 0.4), (1.17, _norm(pop), 0.5)]), D)


@sound("napoli_feast", loudness=-19, wet=0.15, rt60=0.8, marks=(0.0,),
       note="sat down at the grandpa's table: cutlery on a plate (CC0, Closetwalrus)")
def napoli_feast(seed):
    x = _norm(_cc0("napoli_plate"))
    return _finish(x, len(x) / SR, fade_out=0.05)


@sound("napoli_coins", loudness=-18, wet=0.15, rt60=0.8, marks=(0.0,),
       note="the grandpa's purse, and his E: a pouch of coins shaken (CC0, cupido-1)")
def napoli_coins(seed):
    x = _norm(_cc0("napoli_purse"))
    return _finish(x, len(x) / SR, fade_out=0.08)


@sound("napoli_step_a", loudness=-27, wet=0.1, rt60=0.6, marks=(0.0,),
       note="the grandpa's step in his sandals (CC0, brumxyz), the left")
def napoli_step_a(seed):
    x = _norm(_cc0("napoli_step_a"))
    return _finish(x, len(x) / SR, fade_out=0.04)


@sound("napoli_step_b", loudness=-27, wet=0.1, rt60=0.6, marks=(0.0,),
       note="the grandpa's step in his sandals (CC0, brumxyz), the right")
def napoli_step_b(seed):
    x = _norm(_cc0("napoli_step_b"))
    return _finish(x, len(x) / SR, fade_out=0.04)


@sound("napoli_laugh", loudness=-17, wet=0.15, rt60=0.8, marks=(0.0,),
       note="the grandpa laughs (CC0, Cavernstones): his Q, and as he goes")
def napoli_laugh(seed):
    x = _norm(_cc0("napoli_laugh"))
    return _finish(x, len(x) / SR, fade_out=0.08)
