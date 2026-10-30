"""FIRST PERSON ARCHER's sounds (docs/piano-prima-persona.md, Fase 7), made from
code like the rest (SOUND_SPEC.md): a compound bow with the Neon style's hum.

    pilgrim_bow_draw        the draw: the cams turning (a soft ratchet of clicks
                            slowing as they roll over) over a rising creak of the
                            limbs, half a second
    ui_bow_full             the draw full: the cams' let-off, a click and a low
                            neon hum
    pilgrim_bow_release     the arrow loosed: the string's twang (a plucked
                            string, Karplus-Strong), the limbs' thump, the arrow's
                            whistle off
    world_bow_bounce        a bounce: a short bright ping of metal (the lab plays
                            it a note higher at each bounce of the same arrow: it
                            flies faster each time)
    world_bow_pluck         with it, a plucked string, a harp's (the user's wish,
                            2026-10-29): A3, the lab playing it up A minor's
                            pentatonic scale a step a bounce, a fifth under the
                            ping (E pentatonic)
    world_bow_zone          a bounce on a critical zone: two bell strikes a fifth
                            apart, ringing
    world_bow_hit           an arrow into a card: a dry thunk of the head, the
                            shaft's buzz
    world_bow_poison        the venom's accent: bubbles
    world_bow_burn          the fire's: a whoosh catching
    world_bow_ice           the ice's: a crystal crackle and a glassy ring
    world_bow_stun          the stun's: two little dings, dazed
    world_bow_barbed        the barbs': a short wet tear
"""
import numpy as np

from dsp import *  # noqa: F401,F403
from registry import sound
from sfx_cards_arms import _norm, _out, _ramp, _thump


def _hum(dur, f0, level):
    """The neon: a low FM hum, swelling in and out."""
    t = time_axis(dur)
    return fm(f0, f0 * 2, 1.2, dur) * np.sin(np.pi * np.clip(t / dur, 0, 1)) * level


@sound("pilgrim_bow_draw", loudness=-25, wet=0.12, rt60=0.8, marks=(0.0, 0.45))
def pilgrim_bow_draw(seed):
    """The draw: eight clicks of the cams, closer together then rolling over
    (0.02 to 0.45 s), over a creak (a narrow band of noise rising 380 to
    1100 Hz) and the limbs' low groan."""
    dur = 0.6
    t = time_axis(dur)
    times = [0.02 + 0.43 * (k / 7) ** 0.8 for k in range(8)]
    clicks = grains(dur, times, 0.004, seed + 1, band=(2400, 6500))
    creak = sweep_bandpass(white(dur, seed + 2), 380, 1100, 7.0) * np.clip(t / 0.06, 0, 1) * np.exp(-np.clip(t - 0.45, 0, None) / 0.05)
    groan = lowpass(sweep_bandpass(brown(dur, seed + 3), 120, 220, 3.0), 400, 2) * np.clip(t / 0.1, 0, 1)
    x = _norm(clicks) * 0.6 + _norm(creak) * 0.55 + _norm(groan) * 0.25
    return _out(_ramp(x, 0.002), 0.06)


@sound("ui_bow_full", loudness=-27, wet=0.1, rt60=0.6, marks=(0.0,))
def ui_bow_full(seed):
    """Full: the cams' let-off (a firm click) and a low neon hum swelling a
    quarter of a second."""
    dur = 0.3
    t = time_axis(dur)
    click = _norm(highpass(white(dur, seed), 3000, 2)) * np.exp(-t / 0.002)
    knock = _norm(lowpass(white(dur, seed + 1), 900, 2)) * np.exp(-t / 0.01)
    x = click * 0.7 + knock * 0.4 + _norm(_hum(dur, 110, 1.0)) * 0.3
    return _out(_ramp(x, 0.0005), 0.05)


@sound("pilgrim_bow_release", loudness=-19, wet=0.16, rt60=0.9, marks=(0.0, 0.01))
def pilgrim_bow_release(seed):
    """Loosed: the string's twang (Karplus-Strong at 140 Hz, bright, dying in
    half a second), the limbs' thump under it, and the arrow's whistle off (a
    band falling 3.6 to 2.4 kHz)."""
    dur = 0.7
    # Faded at its end, never cut off (a click).
    twang = fade(karplus(140, 0.6, damping=0.993, brightness=0.75, seed=seed + 1), 0.0, 0.2)
    thump = _thump(0.2, seed + 2, f0=120, f1=70, drop=0.01, tau=0.04, lp=700, noise=0.4)
    t3 = time_axis(0.3)
    whistle = sweep_bandpass(white(0.3, seed + 3), 3600, 2400, 9.0) * np.clip(t3 / 0.02, 0, 1) * np.exp(-t3 / 0.09)
    x = place(dur, [
        (0.0, _ramp(_norm(twang), 0.0004), 0.8),
        (0.0, _norm(thump), 0.5),
        (0.01, _norm(whistle), 0.35),
    ])
    return _out(x, 0.06)


@sound("world_bow_bounce", loudness=-21, wet=0.2, rt60=1.0, marks=(0.0,))
def world_bow_bounce(seed):
    """A bounce: a ping of metal at 1.32 kHz (two inharmonic partials), a
    click on its front, ringing a quarter of a second."""
    dur = 0.4
    t = time_axis(dur)
    ping = fm(1320, 1320 * 1.41, 1.6 * np.exp(-t / 0.03), dur) * np.exp(-t / 0.11)
    ping = ping + 0.3 * sine(1320 * 2.76, dur) * np.exp(-t / 0.05)
    click = _norm(highpass(white(0.004, seed), 4000)) * 0.5
    ping[:len(click)] += click
    return _out(fade(_ramp(_norm(ping), 0.0004), 0.0, 0.12), 0.05)


@sound("world_bow_pluck", loudness=-20, wet=0.28, rt60=1.4, marks=(0.0,))
def world_bow_pluck(seed):
    """A bounce's string: a harp's pluck at A3 (220 Hz, Karplus-Strong, bright
    and long, dying in about a second), its octave a breath above it, the
    finger's soft snap on its front."""
    dur = 1.2
    t = time_axis(dur)
    string = karplus(220, dur, damping=0.9975, brightness=0.8, seed=seed + 1)
    octave = karplus(440, dur, damping=0.995, brightness=0.6, seed=seed + 2) * 0.25
    body = lowpass(string + octave, 5200, 2)
    snap = _norm(bandpass(white(0.006, seed + 3), 2500, 1.5)) * 0.25
    body[:len(snap)] += snap
    # Faded at its end, never cut off (a click).
    x = fade(_ramp(_norm(body), 0.0006), 0.0, 0.35) * np.clip(1.4 - t / dur, 0, 1)
    return _out(x, 0.06)


@sound("world_bow_zone", loudness=-18, wet=0.32, rt60=1.6, marks=(0.0, 0.07))
def world_bow_zone(seed):
    """A critical zone: two bell strikes a fifth apart (1.05 kHz, then
    1.57 kHz 70 ms on), the second ringing out over half a second."""
    def bell(f, length, tail):
        t = time_axis(length)
        b = fm(f, f * 1.41, 2.4 * np.exp(-t / 0.15), length) * np.exp(-t / tail)
        return fade(_ramp(_norm(b + 0.3 * sine(f * 2, length) * np.exp(-t / (tail * 0.5))), 0.0006), 0.0, length * 0.3)
    x = place(1.0, [(0.0, bell(1050, 0.5, 0.18), 0.7), (0.07, bell(1573, 0.9, 0.35), 0.9)])
    return _out(x, 0.1)


@sound("world_bow_hit", loudness=-20, wet=0.14, rt60=0.8, marks=(0.0,))
def world_bow_hit(seed):
    """Into a card: a dry thunk (a short wooden knock over a paper thud) and
    the shaft's buzz after it (a 180 Hz buzz dying in 0.12 s)."""
    dur = 0.35
    t = time_axis(dur)
    thunk = _thump(dur, seed, f0=260, f1=140, drop=0.006, tau=0.018, lp=2200, noise=0.6, ntau=0.008)
    buzz = square(180, dur) * np.exp(-t / 0.12) * np.clip((t - 0.01) / 0.01, 0, 1)
    buzz = lowpass(buzz, 1500, 2)
    x = _norm(thunk) + 0.22 * _norm(buzz)
    return _out(_ramp(x, 0.0004), 0.05)


@sound("world_bow_poison", loudness=-25, wet=0.15, rt60=0.8, marks=(0.0,))
def world_bow_poison(seed):
    """The venom: five bubbles popping, each a short sine rising."""
    dur = 0.4
    parts = []
    r = rng(seed)
    for k in range(5):
        length = 0.05
        t = time_axis(length)
        f0 = r.uniform(380, 620)
        b = np.sin(2 * np.pi * np.cumsum(f0 * (1 + 2.5 * t / length)) / SR) * np.exp(-t / 0.015)
        parts.append((0.02 + 0.07 * k, _ramp(b, 0.001), 0.6))
    return _out(place(dur, parts), 0.04)


@sound("world_bow_burn", loudness=-23, wet=0.18, rt60=0.9, marks=(0.0,))
def world_bow_burn(seed):
    """The fire: a whoosh catching (noise swelling through a band rising 300 Hz
    to 2 kHz) and a crackle in it."""
    dur = 0.5
    t = time_axis(dur)
    whoosh = sweep_bandpass(white(dur, seed), 300, 2000, 1.4) * np.clip(t / 0.08, 0, 1) * np.exp(-np.clip(t - 0.12, 0, None) / 0.12)
    crack = crackle(dur, 40, seed + 1)
    return _out(_norm(_norm(whoosh) + 0.3 * _norm(crack)), 0.06)


@sound("world_bow_ice", loudness=-23, wet=0.24, rt60=1.2, marks=(0.0,))
def world_bow_ice(seed):
    """The ice: a crystal crackle (high grains) and a glassy ring (3.1 kHz)."""
    dur = 0.6
    t = time_axis(dur)
    crack = grains(0.2, random_times(0.2, 60, seed), 0.003, seed + 1, band=(4000, 10000))
    ring = fm(3100, 3100 * 2.01, 0.8 * np.exp(-t / 0.05), dur) * np.exp(-t / 0.2)
    x = place(dur, [(0.0, _norm(crack), 0.6), (0.01, _ramp(_norm(ring), 0.001), 0.45)])
    return _out(x, 0.06)


@sound("world_bow_stun", loudness=-24, wet=0.22, rt60=1.0, marks=(0.0, 0.09))
def world_bow_stun(seed):
    """The stun: two little dings a third apart, dazed (a slight wobble)."""
    def ding(f):
        t = time_axis(0.3)
        wobble = 1 + 0.01 * np.sin(2 * np.pi * 7 * t)
        return _ramp(np.sin(2 * np.pi * np.cumsum(f * wobble) / SR) * np.exp(-t / 0.08), 0.0008)
    x = place(0.45, [(0.0, ding(1760), 0.6), (0.09, ding(2217), 0.6)])
    return _out(x, 0.05)


@sound("world_bow_barbed", loudness=-23, wet=0.12, rt60=0.7, marks=(0.0,))
def world_bow_barbed(seed):
    """The barbs: a short wet tear (low noise torn, a squelch falling)."""
    dur = 0.3
    t = time_axis(dur)
    tear = sweep_bandpass(white(dur, seed), 1400, 500, 2.5) * np.exp(-t / 0.05)
    squelch = _thump(dur, seed + 1, f0=220, f1=90, drop=0.02, tau=0.04, lp=900, noise=0.7)
    return _out(_norm(_norm(tear) * 0.7 + _norm(squelch) * 0.5), 0.05)
