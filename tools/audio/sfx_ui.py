"""Family `ui`: time, criticals, defence, statuses, rewards (SOUND_SPEC.md).

Quiet, clear cues that must never mask the action. The family shares a small
set of voices so it reads as one instrument of the paper theatre:

- a small hardwood block (the beat tick, the thorn clicks, the slow's
  dragging escapement);
- a crystal goblet voice (critical, energy, the stun's tinkles): glass-bowl
  partials 1 : 2.32 : 4.25 : 6.63 with slow beating doublets;
- a bronze bell with a minor-third tierce (window end, defeat);
- a ward hum: detuned D-Phrygian partials with a shimmer (block, shield,
  stagger, the afterimage's ghost, the burn's ember, the slow's sinking);
- paper grains 1.5-8 kHz (blocked move, card draw, refocus, defeat, the
  burn's embers, the slow's sand);
- small bronze coins tuned to the mode (gold).

Every tonal element sits in D Phrygian (D Eb F G A Bb C). Recipes are dry;
the build adds the stone hall. All randomness comes from `seed`.
"""
import math

import numpy as np

from dsp import (SR, bandpass, brown, drive, env_points, fade, formant, highpass,
                 lowpass, mix, n_samples, phase_of, pink, place, resample, rng, saw, sine,
                 stft_filter, time_axis, white)
from registry import sound


# --------------------------------------------------------------------------
# Shared voices of the family

_SEMI = {"C": -9, "Db": -8, "D": -7, "Eb": -6, "E": -5, "F": -4, "Gb": -3,
         "G": -2, "Ab": -1, "A": 0, "Bb": 1, "B": 2}


def _hz(note):
    """'D3' -> 146.83 Hz (equal temperament, A4 = 440)."""
    return 440.0 * 2 ** ((_SEMI[note[:-1]] + 12 * (int(note[-1]) - 4)) / 12)


def _expdecay(dur, tau, attack=0.001):
    t = time_axis(dur)
    return np.clip(t / max(attack, 1e-6), 0, 1) * np.exp(-t / max(tau, 1e-6))


def _norm(x):
    return x / (np.max(np.abs(x)) + 1e-12)


def _modes(dur, modes, attack=0.0005):
    """Damped sinusoids [(freq, decay_s, amp)], all starting at phase 0 (no
    step at the onset) under a short attack ramp."""
    t = time_axis(dur)
    x = np.zeros_like(t)
    for f, tau, a in modes:
        if f < SR * 0.45:
            x += a * np.sin(2 * np.pi * f * t) * np.exp(-t / max(tau, 1e-5))
    if attack > 0:
        x *= np.clip(t / attack, 0, 1)
    return _tail(x)


def _tail(x, length=0.006):
    """Ends a layer on silence (a short raised-cosine fade), so a layer that
    stops while it still rings never leaves a click in the mix."""
    n = min(len(x) // 3, n_samples(length))
    if n > 1:
        x = x.copy()
        x[-n:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, n))
    return x


def _finish(x, fade_out=0.02, peak=0.8):
    """Common end of every recipe: fade the end, leave headroom (peak 0.8)."""
    return _norm(fade(x, 0, fade_out)) * peak


def _click(dur, seed, lo=1500.0, hi=None):
    """A sub-few-ms noise transient (contact, pallet, flick). Filtered inside
    a padded buffer (a short burst is shorter than the lows it must lose),
    then cut at its onset and faded."""
    pad = n_samples(0.006)
    x = np.concatenate([np.zeros(pad), white(dur, seed) * _expdecay(dur, dur / 4, 0.0002), np.zeros(pad)])
    x = highpass(x, lo, 2)
    if hi:
        x = lowpass(x, hi, 2)
    return _norm(_tail(fade(x[pad:], 0.00015, 0.0), 0.003))


def _thud(dur, f0, f1, tau, seed, sweep=0.035, noise_lp=300.0, noise_gain=0.4):
    """A soft low body blow: a sine whose pitch falls f0 -> f1, plus a short
    burst of lowpassed noise (the muffled contact)."""
    t = time_axis(dur)
    f = f1 + (f0 - f1) * np.exp(-t / sweep)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * _expdecay(dur, tau, 0.0015)
    nz = _norm(lowpass(pink(dur, seed), noise_lp, 2)) * _expdecay(dur, tau * 0.45, 0.001)
    return _tail(body + noise_gain * nz)


def _stone(dur, seed, lo=220.0, hi=1400.0, count=9, decay=0.02):
    """Dense, very short inharmonic modes: the stone answering a contact."""
    r = rng(seed)
    modes = []
    for i in range(count):
        f = math.exp(r.uniform(math.log(lo), math.log(hi)))
        modes.append((f, decay * r.uniform(0.5, 1.4), r.uniform(0.4, 1.0) / (1 + 0.15 * i)))
    return _modes(dur, modes, attack=0.0004)


# Crystal goblet: (ratio, amp, decay factor).
_GLASS = [(1.0, 1.0, 1.0), (2.32, 0.42, 0.55), (4.25, 0.22, 0.32), (6.63, 0.11, 0.2), (9.38, 0.05, 0.12)]


def _crystal(f, dur, tau, bright=1.0, attack=0.0006, beat=0.0012):
    """A struck crystal: bowl partials, each a doublet slightly mistuned so it
    shimmers (beats) as it rings; higher partials die first."""
    modes = []
    for i, (ratio, amp, dk) in enumerate(_GLASS):
        fr = f * ratio
        a = amp * (bright if i else 1.0)
        modes.append((fr, tau * dk, a))
        modes.append((fr * (1 + beat), tau * dk * 0.9, a * 0.45))
    return _modes(dur, modes, attack)


# Bronze bell, minor (tierce = minor third): (ratio to prime, amp, decay factor).
# The 2.52 'deciem' (a major third over the nominal, F# on a D bell: out of the
# mode and clashing with the minor tierce) is kept faint.
_BELL = [(0.5, 0.45, 1.0), (1.0, 0.6, 0.8), (1.1892, 0.5, 0.62), (1.5, 0.26, 0.45),
         (2.0, 1.0, 0.52), (2.52, 0.08, 0.32), (2.67, 0.24, 0.28), (3.01, 0.38, 0.25),
         (4.06, 0.26, 0.17), (5.42, 0.17, 0.12), (6.8, 0.11, 0.09), (8.3, 0.07, 0.07),
         (10.1, 0.045, 0.05), (12.4, 0.03, 0.04)]

# The big toll: the same bell with three more stretched partials (the
# clapper's bright strike on a large bell).
_TOLL = _BELL + [(14.9, 0.025, 0.03), (17.8, 0.02, 0.022), (21.1, 0.015, 0.016)]


def _bell(prime, dur, tau, attack=0.0012, beat=0.35, hum=1.0, bright=1.0, nominal=1.0, table=_BELL):
    """A bell: hum, prime, minor tierce, quint, nominal and the stretched
    upper partials, each a doublet beating at ~`beat` Hz (the warble).
    `hum` scales the hum (an octave under the prime), `nominal` the nominal
    (an octave over the prime), `bright` the partials above the faint
    deciem."""
    modes = []
    for i, (ratio, amp, dk) in enumerate(table):
        f = prime * ratio
        b = beat * (0.6 + 0.25 * i)
        amp = amp * (hum if i == 0 else nominal if i == 4 else bright if i >= 6 else 1.0)
        modes.append((f, tau * dk, amp))
        modes.append((f + b, tau * dk * 0.95, amp * 0.5))
    return _modes(dur, modes, attack)


def _ward(dur, freqs, amps, seed, detune=0.0035, trem_rate=6.0, trem_depth=0.15, bend=None):
    """The ward: D-Phrygian partials, each with a mistuned twin (slow beating)
    under a gentle tremolo. `bend` is an optional per-sample pitch ratio."""
    t = time_axis(dur)
    r = rng(seed)
    ratio = np.ones_like(t) if bend is None else bend
    x = np.zeros_like(t)
    for f, a in zip(freqs, amps):
        p = np.cumsum(f * ratio) / SR
        x += a * (np.sin(2 * np.pi * p) + 0.6 * np.sin(2 * np.pi * p * (1 + detune) + r.uniform(0, 6.28)))
    x *= 1 + trem_depth * np.sin(2 * np.pi * trem_rate * t + r.uniform(0, 6.28))
    return x / (1.6 * sum(amps))


def _paper(dur, times, seed, band=(1500.0, 8000.0), glen=(0.005, 0.02), gains=None, q=1.3):
    """Paper grains: short noise bursts (sharp onset, quick decay), each
    band-passed somewhere in `band`."""
    out = np.zeros(n_samples(dur))
    r = rng(seed)
    lo, hi = band
    pad = n_samples(0.003)
    for i, t0 in enumerate(times):
        length = r.uniform(*glen)
        g = n_samples(length)
        tt = np.arange(g) / SR
        env = np.clip(tt / 0.0004, 0, 1) * np.exp(-tt / (length / 3.5))
        env *= 0.5 + 0.5 * np.cos(np.pi * np.clip((tt / length - 0.7) / 0.3, 0, 1))
        burst = np.concatenate([np.zeros(pad), r.uniform(-1, 1, g) * env, np.zeros(pad)])
        burst = _norm(bandpass(burst, math.exp(r.uniform(math.log(lo), math.log(hi))), q))
        burst = _tail(fade(burst, 0.0005, 0.0))
        gain = (1.0 if gains is None else gains[i]) * r.uniform(0.55, 1.0)
        start = int(round(t0 * SR)) - pad
        a = max(0, start)
        if a < len(out):
            end = min(len(out), start + len(burst))
            out[a:end] += gain * burst[a - start:end - start]
    return out


def _moving_band(x, path, width_oct=1.2):
    """Band-pass whose centre follows `path` [(t, hz)] (log interpolation)."""
    ts = [p[0] for p in path]
    ls = [math.log(p[1]) for p in path]
    sigma = width_oct / 2.355

    def gain(f, t):
        c = math.exp(np.interp(t, ts, ls))
        return np.exp(-0.5 * (np.log2(np.maximum(f, 1e-3) / c) / sigma) ** 2)
    return stft_filter(x, gain)


def _grit(dur, seed, rate=220.0):
    """A rough amplitude texture (stick-slip): irregular bumps ~`rate`/s."""
    r = rng(seed)
    n = n_samples(dur)
    k = np.abs(lowpass(r.standard_normal(n), rate, 1))
    return _norm(k) ** 1.5


def _env(dur, points):
    return env_points(dur, points)


# --------------------------------------------------------------------------
# Time

@sound("ui_beat_tick", loudness=-32, wet=0.1)
def ui_beat_tick(seed):
    """A clock escapement in hardwood: a faint pallet contact, then the tooth
    drops 6 ms later on a small block tuned to A5 with a soft low 'tock' an
    octave under it (A4, in the mode with the critical sting)."""
    dur = 0.12
    pallet = _click(0.0012, seed, lo=2600)
    tooth = _click(0.0016, seed + 1, lo=1800)
    block = _modes(0.08, [(_hz("A5"), 0.014, 1.0), (1987.0, 0.008, 0.45),
                          (3290.0, 0.005, 0.25), (4710.0, 0.003, 0.12)], attack=0.0004)
    tock = _modes(0.06, [(_hz("A4"), 0.013, 1.0), (980.0, 0.006, 0.3)], attack=0.0008)
    x = place(dur, [(0.0, pallet, 0.12), (0.006, tooth, 0.3),
                    (0.006, block, 0.55), (0.006, tock, 0.18)])
    x = lowpass(x, 6500, 2)
    return _finish(x, 0.02)


@sound("ui_critical", loudness=-20, wet=0.35)
def ui_critical(seed):
    """Golden sting: a glint, a crystal A5 and its answer D6 55 ms later (a
    rising fourth), warm A4/D5 under it, a high detuned shimmer that swells
    after the ding, and a few sparkle grains."""
    dur = 0.7
    t = time_axis(dur)
    glint = _click(0.002, seed, lo=3500)
    # Decays short enough to die inside their buffers: the hall makes the shine.
    a5 = _crystal(_hz("A5"), 0.6, tau=0.18, bright=0.9)
    d6 = _crystal(_hz("D6"), 0.64, tau=0.22, bright=1.0)
    warm = (0.5 * sine(_hz("A4"), dur) + sine(_hz("D5"), dur)) * _expdecay(dur, 0.26, 0.012)
    d7, a7 = _hz("D7"), _hz("A7")
    sh = (sine(d7, dur) + 0.8 * sine(d7 * 1.003, dur)
          + 0.6 * (sine(a7, dur) + 0.8 * sine(a7 * 0.997, dur)))
    sh *= (0.6 + 0.4 * np.sin(2 * np.pi * 11 * t)) * _env(dur, [(0, 0), (0.06, 0), (0.16, 1), (0.65, 0)])
    r = rng(seed + 3)
    times = sorted(0.05 + 0.45 * r.random(14) ** 1.6)
    sparkle = _paper(dur, times, seed + 4, band=(6000, 12000), glen=(0.002, 0.005))
    x = place(dur, [(0.0, glint, 0.25), (0.0, a5, 0.55), (0.055, d6, 0.8),
                    (0.0, warm, 0.16), (0.0, sh, 0.06), (0.0, sparkle, 0.06)])
    return _finish(x, 0.15)


@sound("ui_window_end", loudness=-21, wet=0.45)
def ui_window_end(seed):
    """One low bronze toll: a big bell whose hum sits on D2 (prime D3, minor
    tierce F3, quint A3, nominal D4, the strongest line so small speakers
    still hear the toll; the hum is the longest-lived partial), struck by an
    iron clapper (a short clang of high inharmonic partials and the bell's
    stretched upper partials), the stone answering, and a low rumble of the
    hall's stone (35-140 Hz)."""
    dur = 1.4
    bell = _bell(_hz("D3"), dur, tau=1.2, hum=1.0, nominal=1.4, bright=3.5, table=_TOLL)
    clap = _norm(bandpass(white(0.03, seed + 1), 2500, 0.8)) * _expdecay(0.03, 0.005, 0.0003)
    clang = _modes(0.5, [(1580, 0.2, 0.5), (2210, 0.15, 0.42), (2930, 0.11, 0.32),
                         (3720, 0.08, 0.24), (4650, 0.05, 0.16)], attack=0.0005)
    stone = _stone(0.2, seed + 2, lo=160, hi=600, count=10, decay=0.06)
    # brown() is mostly sub-10 Hz drift: keep only the audible rumble.
    rumble = _norm(highpass(lowpass(brown(dur, seed + 3), 140, 2), 35, 2))
    rumble *= _env(dur, [(0, 0), (0.04, 1), (0.5, 0.35), (1.4, 0)])
    x = place(dur, [(0.0, bell, 0.7), (0.0, clap, 0.2), (0.0, clang, 0.45),
                    (0.0, stone, 0.2), (0.0, rumble, 0.06)])
    return _finish(x, 0.3)


@sound("ui_stun", loudness=-20, wet=0.4)
def ui_stun(seed):
    """A dull blow (falling low thump + muffled slap), then a whirling daze:
    thin high rings (D6, A6, D7) wobbling under a 2.3 Hz rotation, a noise
    whirr whose band circles with it, and crystal tinkles going round."""
    dur = 1.4
    t = time_axis(dur)
    blow = _thud(0.6, 150, 85, tau=0.085, seed=seed, noise_lp=700, noise_gain=0.6)
    slap = _norm(bandpass(white(0.012, seed + 1), 1600, 0.8)) * _expdecay(0.012, 0.0025, 0.0002)
    whirl = 2.3
    rot = 0.55 + 0.45 * np.sin(2 * np.pi * whirl * t)
    r1 = np.sin(2 * np.pi * phase_of(_hz("A6") * (1 + 0.006 * np.sin(2 * np.pi * 4.7 * t)), n=len(t)))
    r2 = np.sin(2 * np.pi * phase_of(_hz("D7") * (1 + 0.008 * np.sin(2 * np.pi * 3.1 * t + 1)), n=len(t)))
    r3 = np.sin(2 * np.pi * _hz("D6") * t)
    ring = (0.6 * r1 + 0.35 * r2 + 0.25 * r3) * rot * _env(dur, [(0, 0), (0.05, 0), (0.3, 1), (0.8, 0.6), (1.35, 0)])

    def circle(f, tt):
        c = 2400 * 1.6 ** math.sin(2 * math.pi * whirl * tt)
        return np.exp(-0.5 * (np.log2(np.maximum(f, 1e-3) / c) / 0.3) ** 2)
    whirr = lowpass(stft_filter(white(dur, seed + 2), circle), 8000, 2) * _env(dur, [(0, 0), (0.1, 0), (0.35, 1), (1.3, 0)])
    notes = [_hz("D7"), _hz("F7"), _hz("A7"), _hz("F7")]
    events = []
    for k in range(8):
        tk = 0.16 + k / (2 * whirl) * 0.9
        if tk > dur - 0.3:
            break  # a tinkle must have room to ring before the daze fades out
        g = (0.65 + 0.35 * math.cos(2 * math.pi * whirl * tk)) * math.exp(-k * 0.22)
        events.append((tk, _crystal(notes[k % 4], 0.4, tau=0.12, bright=0.5, attack=0.001), 0.22 * g))
    x = place(dur, [(0.0, blow, 0.9), (0.0, slap, 0.18), (0.0, ring, 0.12), (0.0, whirr, 0.05)] + events)
    return _finish(x, 0.15)


# --------------------------------------------------------------------------
# Defence

@sound("ui_defense_prompt", loudness=-20, wet=0.25)
def ui_defense_prompt(seed):
    """Tense sting: a low double pulse on D2 (lub at 0, dub at 0.15, driven
    so its harmonics carry), under a rising metallic shiver: inharmonic metal
    partials gliding D5 -> A5 with a 26 Hz flutter, and a rising hiss."""
    dur = 0.5
    t = time_axis(dur)

    def pulse(seed_k):
        tt = time_axis(0.2)
        f = _hz("D2") + 20 * np.exp(-tt / 0.02)
        return drive(np.sin(2 * np.pi * np.cumsum(f) / SR) * _expdecay(0.2, 0.05, 0.004), 1.8)
    base = _hz("D5") * (_hz("A5") / _hz("D5")) ** np.clip((t - 0.02) / 0.4, 0, 1)
    r = rng(seed)
    shiver = np.zeros_like(t)
    for i, ratio in enumerate([1.0, 1.47, 2.09, 2.56, 3.2]):
        p = np.cumsum(base * ratio) / SR
        flutter = 0.5 + 0.5 * np.sin(2 * np.pi * 26 * t + r.uniform(0, 6.28))
        shiver += np.sin(2 * np.pi * p) * flutter / (1 + 0.6 * i)
    env = _env(dur, [(0, 0), (0.03, 0.15), (0.38, 1), (0.47, 0)])
    shiver *= env
    hiss = _moving_band(white(dur, seed + 1), [(0, 2500), (0.45, 7000)], 0.9)
    hiss = _norm(hiss) * env * (0.5 + 0.5 * np.sin(2 * np.pi * 26 * t))
    x = place(dur, [(0.0, pulse(0), 0.75), (0.15, pulse(1), 0.5),
                    (0.0, shiver, 0.22), (0.0, hiss, 0.05)])
    return _finish(x, 0.03)


@sound("ui_block_absorb", loudness=-20, wet=0.25)
def ui_block_absorb(seed):
    """A ward-thud: a soft low blow muffled through the ward, and the ward's
    partials (D4, A4, D5) shiver at 9 Hz as they bend back from the impact."""
    dur = 0.5
    t = time_axis(dur)
    thud = _thud(0.3, 165, 82, tau=0.08, seed=seed, noise_lp=380, noise_gain=0.45)
    bend = 1 + 0.012 * np.exp(-t / 0.03)
    ward = _ward(dur, [_hz("D4"), _hz("A4"), _hz("D5")], [1.0, 0.7, 0.45], seed + 1,
                 trem_rate=9.0, trem_depth=0.35, bend=bend) * _expdecay(dur, 0.16, 0.006)
    glint = _crystal(_hz("D6"), 0.3, tau=0.12, bright=0.4, attack=0.004)
    whomp = _norm(lowpass(pink(0.15, seed + 2), 600, 2)) * _expdecay(0.15, 0.03, 0.004)
    x = place(dur, [(0.0, thud, 0.9), (0.0, ward, 0.6), (0.004, glint, 0.06), (0.0, whomp, 0.2)])
    return _finish(x, 0.04)


@sound("ui_miss", loudness=-22, wet=0.2)
def ui_miss(seed):
    """A swish through empty air: pink noise through a band that swells
    520 -> 1900 -> 850 Hz with its level, a thin leading air edge, no hit."""
    dur = 0.45
    body = _moving_band(pink(dur, seed), [(0, 520), (0.16, 1900), (0.42, 850)], 1.3)
    body = _norm(body) * _env(dur, [(0, 0), (0.05, 0.15), (0.15, 1), (0.27, 0.45), (0.42, 0)]) ** 1.4
    air = _norm(lowpass(highpass(white(dur, seed + 1), 3000, 2), 7000, 2))
    air *= _env(dur, [(0, 0), (0.06, 0.1), (0.13, 1), (0.25, 0)]) ** 2
    return _finish(body + 0.05 * air, 0.02)


@sound("ui_move_blocked", loudness=-22, wet=0.15)
def ui_move_blocked(seed):
    """A dull bump against stone (falling low thump, short stone modes and a
    pinch of grit), then the paper card flaps back (damped grains)."""
    dur = 0.35
    bump = _thud(0.2, 170, 92, tau=0.055, seed=seed, noise_lp=550, noise_gain=0.5)
    stone = _stone(0.08, seed + 1, lo=300, hi=1800, count=10, decay=0.012)
    grit = _norm(bandpass(white(0.02, seed + 2), 2600, 1.0)) * _expdecay(0.02, 0.004, 0.0003)
    flaps = [0.03, 0.052, 0.072, 0.09, 0.106, 0.12]
    paper = _paper(dur, flaps, seed + 3, band=(1400, 4500), glen=(0.008, 0.014),
                   gains=[1, 0.8, 0.6, 0.45, 0.32, 0.22])
    flap_low = _paper(dur, flaps[:3], seed + 4, band=(500, 900), glen=(0.012, 0.02), gains=[1, 0.6, 0.35])
    x = place(dur, [(0.0, bump, 0.85), (0.0, stone, 0.35), (0.0, grit, 0.14),
                    (0.0, paper, 0.22), (0.0, flap_low, 0.15)])
    return _finish(x, 0.03)


# --------------------------------------------------------------------------
# Cards

@sound("ui_card_draw", loudness=-27, wet=0.12)
def ui_card_draw(seed):
    """A card pulled off the deck: a dry gritty paper slide whose band rises
    1.8 -> 4.2 kHz for 150 ms, then a crisp flick at 0.155 s."""
    dur = 0.25
    slide = white(0.16, seed) * (0.4 + 0.6 * _grit(0.16, seed + 1, 260))
    slide = _norm(_moving_band(slide, [(0, 1800), (0.15, 4200)], 1.1))
    slide = lowpass(slide, 7000, 2) * _env(0.16, [(0, 0), (0.015, 0.7), (0.11, 1), (0.155, 0)])
    snap = _click(0.001, seed + 2, lo=2800)
    flick = _paper(dur, [0.155], seed + 3, band=(3000, 4500), glen=(0.008, 0.01))
    flap = _paper(dur, [0.158], seed + 4, band=(800, 1200), glen=(0.012, 0.015))
    x = place(dur, [(0.0, slide, 0.45), (0.155, snap, 0.12), (0.0, flick, 0.6), (0.0, flap, 0.25)])
    return _finish(x, 0.02)


@sound("ui_refocus", loudness=-23, wet=0.15)
def ui_refocus(seed):
    """A deck riffled (34 card flicks, a quick fall in rate and level, each a
    paper tick plus a tiny card-on-card tap), a short squaring push, and two
    dull taps of the deck's edge on the table (0.5 and 0.585 s)."""
    dur = 0.7
    r = rng(seed)
    count = 34
    times = [0.03 + 0.38 * (k / count) ** 0.85 + r.uniform(-0.002, 0.002) for k in range(count)]
    gains = [math.sin(math.pi * (0.15 + 0.85 * k / count)) ** 0.7 for k in range(count)]
    ticks = _paper(dur, times, seed + 1, band=(1800, 7000), glen=(0.003, 0.007), gains=gains)
    taps = _paper(dur, times, seed + 2, band=(700, 1300), glen=(0.003, 0.005), gains=gains)
    push = white(0.06, seed + 3) * (0.3 + 0.7 * _grit(0.06, seed + 4, 300))
    push = _norm(_moving_band(push, [(0, 2500), (0.06, 1600)], 1.2)) * _env(0.06, [(0, 0), (0.02, 1), (0.06, 0)])

    def edge(k):
        # A deck squared on the table: a dull cardboard 'tok' (the stack's
        # modes 380-1850 Hz over a short muffled knock), not a pitched kick.
        body = 0.35 * _thud(0.12, 220, 150, tau=0.014, seed=seed + 5 + k, noise_lp=1600, noise_gain=1.2)
        card = _modes(0.06, [(380, 0.012, 0.8), (720, 0.009, 0.6), (1150, 0.006, 0.45),
                             (1850, 0.004, 0.3)], attack=0.0004)
        grit = _paper(0.03, [0.004], seed + 7 + k, band=(2000, 5000), glen=(0.006, 0.01))
        return mix(body, card, 0.3 * grit)
    x = place(dur, [(0.0, ticks, 0.7), (0.0, taps, 0.3), (0.44, push, 0.22),
                    (0.5, edge(0), 0.42), (0.585, edge(1), 0.32)])
    return _finish(x, 0.03)


# --------------------------------------------------------------------------
# Rewards

def _coin(f, dur, seed):
    """A small bronze coin: circular-plate modes over a contact click. The
    decays are short: a coin landing in a pile is damped by the others."""
    r = rng(seed)
    ratios = [1.0, 1.594, 2.136, 2.296, 2.653, 2.918]
    modes = []
    for i, q in enumerate(ratios):
        fr = f * q * (1 + r.uniform(-0.004, 0.004))
        modes.append((fr, 0.12 / (1 + 0.8 * i), r.uniform(0.5, 1.0) / (1 + 0.4 * i)))
    return mix(_modes(dur, modes, attack=0.0003), 0.4 * _click(0.001, seed + 1, lo=4000))


@sound("ui_gold", loudness=-22, wet=0.2)
def ui_gold(seed):
    """A few bright coins tumbling in: five hits (coins tuned D7, A6, F7, C7,
    Bb6), each with a small chatter bounce 8-14 ms later."""
    dur = 0.5
    r = rng(seed)
    hits = [0.0, 0.055, 0.1, 0.17, 0.25]
    gains = [1.0, 0.75, 0.85, 0.55, 0.4]
    notes = ["D7", "A6", "F7", "C7", "Bb6"]
    events = []
    for k, (tk, g, nt) in enumerate(zip(hits, gains, notes)):
        c = _coin(_hz(nt), 0.4, seed + 10 * k)
        events.append((tk, c, 0.5 * g))
        events.append((tk + r.uniform(0.008, 0.014), c, 0.15 * g))
    x = place(dur, events)
    return _finish(x, 0.15)


@sound("ui_energy", loudness=-27, wet=0.25)
def ui_energy(seed):
    """A soft crystal ping on D5 (soft 3 ms attack) with a faint D6 shimmer."""
    dur = 0.35
    t = time_axis(dur)
    ping = _crystal(_hz("D5"), dur, tau=0.11, bright=0.6, attack=0.003)
    shimmer = sine(_hz("D6"), dur) * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * t)) * _expdecay(dur, 0.12, 0.02)
    x = 0.7 * ping + 0.06 * shimmer
    return _finish(x, 0.12)


@sound("ui_loot_drop", loudness=-22, wet=0.2)
def ui_loot_drop(seed):
    """A small trinket drops on stone: first impact at 25 ms, bounces that
    shorten geometrically (restitution 0.62), then it rolls and settles: a
    rotation-modulated rumble with faint ticks of the object's modes."""
    dur = 0.6
    obj = [(1430, 0.07, 1.0), (2380, 0.05, 0.6), (3720, 0.035, 0.45), (5150, 0.025, 0.3)]

    def impact(k, scale):
        body = _modes(0.15, obj, attack=0.0003)
        floor = _stone(0.05, seed + 20 + k, lo=300, hi=1800, count=7, decay=0.008)
        return mix(body, 0.6 * floor, 0.5 * _click(0.0012, seed + 40 + k, lo=2000))
    t0, gap, g = 0.025, 0.15, 1.0
    events = []
    k = 0
    while t0 < 0.39:
        events.append((t0, impact(k, g), 0.5 * g))
        t0 += gap
        gap *= 0.62
        g *= 0.6
        k += 1
    roll_start, roll_len = 0.34, 0.24
    tr = time_axis(roll_len)
    rate = 26 - 17 * tr / roll_len
    rot = np.abs(np.sin(np.pi * np.cumsum(rate) / SR)) ** 3
    roll = _norm(bandpass(white(roll_len, seed + 5), 1100, 0.8)) * rot * _env(roll_len, [(0, 0), (0.03, 1), (roll_len, 0)])
    rtimes = []
    ph = np.cumsum(rate) / SR
    for c in range(1, int(ph[-1]) + 1):
        i = int(np.searchsorted(ph, c))
        if i < len(tr):
            rtimes.append(tr[i])
    rticks = place(roll_len, [(tt, _modes(0.05, obj, attack=0.0003), 0.12 * (1 - tt / roll_len)) for tt in rtimes])
    x = place(dur, events + [(roll_start, roll, 0.1), (roll_start, rticks, 1.8)])
    return _finish(x, 0.03)


# --------------------------------------------------------------------------
# Statuses

@sound("ui_status_poison", loudness=-22, wet=0.2)
def ui_status_poison(seed):
    """Bubbling (Minnaert-like bubbles: damped sines, 350-1100 Hz, rising
    gently as they close, ~10% per decay time, not a cartoon 'bloip') over a
    sickly tone sliding A4 -> Eb4 (a tritone down):
    detuned filtered saws with a queasy vibrato."""
    dur = 0.6
    t = time_axis(dur)
    r = rng(seed)
    events = []
    times = sorted(0.5 * r.random(18) ** 1.3)
    for tk in times:
        f0 = math.exp(r.uniform(math.log(350), math.log(1100)))
        tau = r.uniform(0.008, 0.025)
        tb = time_axis(tau * 5)
        f = f0 * (1 + r.uniform(0.06, 0.12) * tb / tau)  # Minnaert rise, ~10%/tau
        bub = np.sin(2 * np.pi * np.cumsum(f) / SR) * _expdecay(tau * 5, tau, 0.0008)
        events.append((tk, bub, r.uniform(0.3, 0.8)))
    bubbles = lowpass(place(dur, events), 2500, 2)
    u = np.clip((t - 0.06) / 0.48, 0, 1)
    f = _hz("A4") * (_hz("Eb4") / _hz("A4")) ** (u ** 1.6)
    f *= 1 + 0.006 * np.sin(2 * np.pi * 5.5 * t)
    tone = np.zeros_like(t)
    for d in (-0.005, 0.0, 0.006):
        tone += saw(f * (1 + d), n=len(t))
    tone = lowpass(tone, 1100, 2)
    tone = bandpass(tone, 700, 0.5) + 0.3 * tone
    tone = _norm(tone) * _env(dur, [(0, 0), (0.05, 0.8), (0.4, 0.7), (0.58, 0)])
    x = 0.5 * _norm(bubbles) + 0.3 * tone
    return _finish(x, 0.03)


@sound("ui_status_shield", loudness=-22, wet=0.3)
def ui_status_shield(seed):
    """The ward hum rises and holds: D3 A3 under D4 A4 D5 (open fifths)
    with slowly beating twins, a brightness that grows with the swell (the
    upper layers come in later), a high sheen (D6/A6, D7) and a breath of
    air as it forms."""
    dur = 0.6
    env = _env(dur, [(0, 0), (0.22, 1), (0.48, 1), (0.6, 0)]) ** 1.3
    low = _ward(dur, [_hz("D3"), _hz("A3")], [1.0, 0.7], seed, trem_rate=5.0, trem_depth=0.12)
    high = _ward(dur, [_hz("D4"), _hz("A4"), _hz("D5")], [0.8, 0.55, 0.35], seed + 1, trem_rate=5.0, trem_depth=0.15)
    sheen = _ward(dur, [_hz("D6"), _hz("A6"), _hz("D7")], [1.0, 0.6, 0.3], seed + 2, detune=0.002,
                  trem_rate=7.0, trem_depth=0.4)
    air = _norm(bandpass(pink(dur, seed + 3), 900, 1.0)) * _env(dur, [(0, 0), (0.12, 1), (0.3, 0)])
    x = env * (0.45 * low + 0.6 * high * env + 0.18 * sheen * env ** 2) + 0.06 * air
    return _finish(x, 0.02)


@sound("ui_status_thorns", loudness=-22, wet=0.2)
def ui_status_thorns(seed):
    """Brambles tighten: a woody stick-slip creak (impulses 40 -> 90 /s
    through stem resonances) under accelerating thorn clicks (tiny hard-wood
    snaps), a double click as it cinches at 0.38 s."""
    dur = 0.5
    t = time_axis(0.34)
    rate = 40 + 50 * t / 0.34
    ph = np.cumsum(rate) / SR
    imp = np.zeros_like(t)
    r = rng(seed)
    for c in range(1, int(ph[-1]) + 1):
        i = int(np.searchsorted(ph, c))
        if i < len(t):
            imp[i] = r.uniform(0.4, 1.0)
    stem = _modes(0.03, [(420, 0.007, 1.0), (980, 0.005, 0.7), (1650, 0.004, 0.5), (2700, 0.003, 0.3)], attack=0.0002)
    creak = highpass(np.convolve(imp, stem)[:len(t)], 250, 2) * _env(0.34, [(0, 0), (0.05, 1), (0.28, 0.8), (0.34, 0)])
    clicks = []
    ctimes = [0.03, 0.09, 0.135, 0.18, 0.215, 0.25, 0.28, 0.31, 0.34, 0.38, 0.392]
    for k, tk in enumerate(ctimes):
        f0 = r.uniform(2200, 3400)
        snap = _modes(0.02, [(f0, 0.006, 1.0), (f0 * 1.71, 0.004, 0.6), (f0 * 2.43, 0.003, 0.35)], attack=0.0002)
        snap = mix(snap, 0.6 * _click(0.0008, seed + 30 + k, lo=2000))
        clicks.append((tk, snap, r.uniform(0.5, 1.0) * (1.4 if tk >= 0.38 else 1.0)))
    x = place(dur, [(0.0, creak, 0.35)] + [(tk, s, 0.4 * g) for tk, s, g in clicks])
    x = lowpass(x, 10000, 2)
    return _finish(x, 0.03)


@sound("ui_status_stagger", loudness=-21, wet=0.25)
def ui_status_stagger(seed):
    """A jolt (low thump + snap), then the paper standee wobbles on its iron
    base: base-on-stone rattle clicks every 55 ms dying away, and a low ward
    tone (D3, A3) wobbling in pitch and level at the same rate."""
    dur = 0.6
    t = time_axis(dur)
    jolt = _thud(0.3, 170, 88, tau=0.065, seed=seed, noise_lp=550, noise_gain=0.45)
    snap = _norm(bandpass(white(0.004, seed + 1), 2000, 0.8)) * _expdecay(0.004, 0.001, 0.0002)
    rock = 1 / 0.11
    depth = np.exp(-t / 0.18)
    bend = 1 + 0.03 * depth * np.sin(2 * np.pi * rock * t)
    tone = _ward(dur, [_hz("D3"), _hz("A3"), _hz("D4")], [1.0, 0.6, 0.35], seed + 2, trem_depth=0.0, bend=bend)
    tone *= (1 - 0.5 * depth * (0.5 + 0.5 * np.sin(2 * np.pi * rock * t))) * _env(dur, [(0, 0), (0.02, 1), (0.55, 0)]) ** 1.5
    events = []
    for k in range(9):
        tk = 0.035 + k * 0.055
        c = _modes(0.03, [(1850, 0.008, 1.0), (2930, 0.006, 0.6), (4100, 0.004, 0.4)], attack=0.0002)
        c = mix(c, 0.5 * _stone(0.02, seed + 10 + k, lo=400, hi=2000, count=5, decay=0.004))
        events.append((tk, c, 0.3 * 0.7 ** k))
    x = place(dur, [(0.0, jolt, 0.85), (0.0, snap, 0.2), (0.0, tone, 0.3)] + events)
    return _finish(x, 0.03)


@sound("ui_status_afterimage", loudness=-23, wet=0.35)
def ui_status_afterimage(seed):
    """A ghostly breath echo: an airy breath (pink noise, soft 1.2/2.6/4.5 kHz
    bands, no voice) that repeats three times 120 ms apart, each echo fainter,
    darker and a touch lower; a faint beating D5/A5 ghost under it."""
    dur = 0.6
    breath = formant(pink(0.14, seed), [(1200, 1.2, 1.0), (2600, 1.5, 0.7), (4500, 1.5, 0.4)])
    breath = _norm(breath) * _env(0.14, [(0, 0), (0.035, 1), (0.13, 0)]) ** 1.5
    events = [(0.0, breath, 1.0)]
    for k, (cut, g) in enumerate([(4500, 0.5), (2800, 0.3), (1700, 0.17)], start=1):
        echo = lowpass(resample(breath, 0.97 ** k), cut, 2)
        events.append((0.13 * k, _tail(echo), g))
    ghost = _ward(dur, [_hz("D5"), _hz("A5")], [1.0, 0.6], seed + 1, detune=0.004, trem_rate=6.0, trem_depth=0.3)
    ghost *= _env(dur, [(0, 0), (0.1, 1), (0.4, 0.6), (0.58, 0)])
    x = place(dur, events + [(0.0, ghost, 0.035)])
    return _finish(x, 0.03)


@sound("ui_status_burn", loudness=-22, wet=0.2)
def ui_status_burn(seed):
    """The paper catches fire: a dry match-strike scratch (gritty noise whose
    band drops 5.2 -> 2.6 kHz in 30 ms), a small ignition whoomph (pink noise
    through a band rising 200 -> 1100 Hz, peak at 0.08 s), then the edge
    smoulders: ember pops (1.8-6 kHz, thinning out) and singeing paper grains
    over a low roar (130-380 Hz, a flame on a card, not a furnace), and a
    faint ember tone (the ward's D4/A4/D5 under a 10 Hz flame flicker,
    warming up a touch)."""
    dur = 0.6
    t = time_axis(dur)
    r = rng(seed)
    strike = white(0.03, seed) * (0.35 + 0.65 * _grit(0.03, seed + 1, 900))
    strike = _norm(_moving_band(strike, [(0, 5200), (0.03, 2600)], 1.0))
    strike = _tail(strike * _env(0.03, [(0, 0), (0.002, 1), (0.03, 0.2)]))
    whoomph = _moving_band(pink(0.3, seed + 2), [(0, 200), (0.07, 600), (0.25, 1100)], 0.9)
    whoomph = _norm(whoomph) * _env(0.3, [(0, 0), (0.08, 1), (0.18, 0.35), (0.3, 0)]) ** 1.4
    # brown() is mostly sub-10 Hz drift: keep only the flame's low roar.
    roar = _norm(highpass(lowpass(brown(dur, seed + 3), 380, 2), 130, 3))
    roar *= _env(dur, [(0, 0), (0.05, 0.4), (0.12, 1), (0.4, 0.55), (0.58, 0)])
    times = sorted(0.04 + 0.5 * r.random(16) ** 1.5)
    gains = [1.0 - 0.6 * (tk - 0.04) / 0.5 for tk in times]
    pops = _paper(dur, times, seed + 4, band=(1800, 6000), glen=(0.0015, 0.004), gains=gains, q=1.6)
    singe = _paper(dur, sorted(0.03 + 0.45 * r.random(26)), seed + 5, band=(2500, 8000), glen=(0.006, 0.018))
    singe *= _env(dur, [(0, 0), (0.05, 1), (0.3, 0.6), (0.5, 0)])
    warm = 1 + 0.012 * np.clip((t - 0.05) / 0.4, 0, 1)
    ember = _ward(dur, [_hz("D4"), _hz("A4"), _hz("D5")], [1.0, 0.6, 0.3], seed + 6,
                  trem_rate=10.0, trem_depth=0.45, bend=warm)
    ember *= _env(dur, [(0, 0), (0.06, 0), (0.2, 1), (0.42, 0.6), (0.58, 0)])
    x = place(dur, [(0.0, strike, 0.35), (0.012, whoomph, 0.7), (0.0, roar, 0.16),
                    (0.0, pops, 0.42), (0.0, singe, 0.1), (0.0, ember, 0.12)])
    return _finish(x, 0.03)


@sound("ui_status_slow", loudness=-23, wet=0.3)
def ui_status_slow(seed):
    """The clock drags: the beat tick's hardwood escapement ticks five times,
    each later than the one before (gaps 90 -> 165 ms), its tooth dropping
    later after the pallet (6 -> 14 ms) and each block a step lower down the
    mode (A5 G5 F5 Eb5 D5, the tock an octave under), over the ward's octave
    sinking a fourth (D4/D5 -> A3/A4) as its shimmer slows from 7 to 2 Hz,
    and a faint trickle of sand (the hourglass) that thins out."""
    dur = 0.7
    t = time_axis(dur)
    r = rng(seed)
    events = []
    for k, (tk, note) in enumerate(zip([0.0, 0.09, 0.2, 0.335, 0.5], ["A5", "G5", "F5", "Eb5", "D5"])):
        f = _hz(note)
        drop = tk + 0.006 + 0.002 * k
        pallet = _click(0.0012, seed + 10 + 4 * k, lo=2600)
        tooth = _click(0.0016, seed + 11 + 4 * k, lo=1800)
        block = _modes(0.08, [(f, 0.014 + 0.002 * k, 1.0), (f * 2.258, 0.008, 0.45),
                              (f * 3.739, 0.005, 0.25), (f * 5.352, 0.003, 0.12)], attack=0.0004)
        tock = _modes(0.07, [(f / 2, 0.013 + 0.003 * k, 1.0), (f * 1.114, 0.006, 0.3)], attack=0.0008)
        g = 0.92 ** k
        events += [(tk, pallet, 0.12 * g), (drop, tooth, 0.3 * g), (drop, block, 0.55 * g), (drop, tock, 0.2 * g)]
    u = np.clip((t - 0.08) / 0.52, 0, 1)
    sink = 2 ** (-5 / 12 * u * u * (3 - 2 * u))
    ward = _ward(dur, [_hz("D4"), _hz("D5")], [1.0, 0.45], seed + 1, trem_depth=0.0, bend=sink)
    rate = 7 - 5 * np.clip(t / 0.6, 0, 1)
    ward *= 1 + 0.3 * np.sin(2 * np.pi * np.cumsum(rate) / SR + r.uniform(0, 6.28))
    ward *= _env(dur, [(0, 0), (0.08, 1), (0.45, 0.8), (0.68, 0)])
    times = sorted(0.03 + 0.6 * r.random(90) ** 1.4)
    gains = [1.0 - 0.8 * (tk - 0.03) / 0.6 for tk in times]
    sand = _paper(dur, times, seed + 2, band=(3500, 9000), glen=(0.0008, 0.002), gains=gains, q=1.0)
    x = place(dur, events + [(0.0, ward, 0.22), (0.0, sand, 0.05)])
    x = lowpass(x, 9000, 2)
    return _finish(x, 0.03)


# The player's charges (Phase 2)

@sound("ui_status_deflect", loudness=-23, wet=0.3)
def ui_status_deflect(seed):
    """RIFLESSO ready: a polished buckler catches the light, two crystal
    glints (D6, then A6 70 ms later, bright and short) over the ward's thin
    open fifth (D5/A5) swelling and turning away, a breath of air."""
    dur = 0.5
    g1 = _crystal(_hz("D6"), 0.4, 0.09)
    g2 = _crystal(_hz("A6"), 0.33, 0.07)
    ward = _ward(dur, [_hz("D5"), _hz("A5")], [1.0, 0.6], seed, trem_rate=8.0, trem_depth=0.25)
    ward = ward * _env(dur, [(0, 0), (0.08, 1), (0.25, 0.5), (0.48, 0)])
    air = _norm(bandpass(pink(0.12, seed + 1), 5200, 1.0)) * _env(0.12, [(0, 0), (0.02, 1), (0.12, 0)])
    x = place(dur, [(0.0, air, 0.1), (0.01, g1, 0.55), (0.08, g2, 0.45), (0.0, ward, 0.16)])
    return _finish(x, 0.03)


@sound("ui_status_arrows", loudness=-22, wet=0.2)
def ui_status_arrows(seed):
    """FRECCE in the quiver: three arrows slid home one after the other
    (0.0, 0.08, 0.15): the swish of each fletching (soft paper grains,
    4-8 kHz), the knock of its wooden shaft on the quiver's bottom (hardwood
    modes, a little lower each time) and a tick of its iron head."""
    dur = 0.45
    r = rng(seed)
    events = []
    for k, t0 in enumerate((0.0, 0.08, 0.15)):
        swish = _paper(0.06, sorted(0.04 * r.random(8)), seed + 10 + k, band=(4000, 8000), glen=(0.004, 0.012))
        f = 610 * 0.93 ** k
        knock = _modes(0.08, [(f, 0.012, 1.0), (f * 2.4, 0.007, 0.5), (f * 3.9, 0.004, 0.3)], attack=0.0003)
        tick = _modes(0.03, [(r.uniform(3000, 3600), 0.005, 1.0), (r.uniform(4600, 5300), 0.003, 0.5)], attack=0.0002)
        events += [(t0, swish, 0.25), (t0 + 0.035, knock, 0.6), (t0 + 0.036, tick, 0.18),
                   (t0 + 0.035, _click(0.001, seed + 30 + k, lo=1800), 0.12)]
    return _finish(place(dur, events), 0.03)


@sound("ui_status_fate", loudness=-23, wet=0.3)
def ui_status_fate(seed):
    """DESTINO loaded: a bone die ticks twice in the hand (tiny stiff modes),
    then a low bell of fate is touched (D4, minor tierce, soft attack) under a
    violet shimmer of the ward (A5/D6, slowly beating), fading."""
    dur = 0.6
    r = rng(seed)
    events = []
    for k, t0 in enumerate((0.0, 0.055)):
        die = _modes(0.04, [(r.uniform(2600, 3300), 0.006, 1.0), (r.uniform(4300, 5100), 0.004, 0.7),
                            (r.uniform(6300, 7400), 0.003, 0.45)], attack=0.0001)
        events += [(t0, die, 0.45 * (1 - 0.3 * k)), (t0, _click(0.0008, seed + 10 + k, lo=2500), 0.15)]
    bell = _bell(_hz("D4"), 0.52, 0.22, attack=0.01, beat=0.3, hum=0.6, bright=0.5)
    shimmer = _ward(0.5, [_hz("A5"), _hz("D6")], [1.0, 0.5], seed + 1, trem_rate=4.0, trem_depth=0.35)
    shimmer = shimmer * _env(0.5, [(0, 0), (0.12, 1), (0.3, 0.6), (0.5, 0)])
    events += [(0.09, bell, 0.5), (0.1, shimmer, 0.14)]
    return _finish(place(dur, events), 0.04)


def _bubble(f0, rise, tau):
    """A small bubble closing (Minnaert-like): a damped sine whose pitch
    rises as it decays."""
    tb = time_axis(tau * 5)
    f = f0 * (1 + rise * tb / tau)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * _expdecay(tau * 5, tau, 0.0008)


@sound("ui_status_venom_blade", loudness=-22, wet=0.2)
def ui_status_venom_blade(seed):
    """LAMA poisoned: a blade's thin ting (a short steel ring on Eb6) and the
    venom slicking it: a drop's plip and two small bubbles closing over a
    sickly tone falling A5 -> Eb5."""
    dur = 0.5
    t = time_axis(dur)
    f = _hz("Eb6")
    ting = _modes(0.35, [(f, 0.08, 1.0), (f * 1.506, 0.05, 0.5), (f * 2.17, 0.03, 0.3), (f * 2.63, 0.02, 0.2)], attack=0.0002)
    u = np.clip((t - 0.12) / 0.3, 0, 1)
    sick = sine(_hz("A5") * (_hz("Eb5") / _hz("A5")) ** u, n=len(t)) * _env(dur, [(0, 0), (0.12, 0), (0.18, 1), (0.45, 0)])
    events = [(0.0, ting, 0.4), (0.0, _click(0.0008, seed, lo=3000), 0.12), (0.12, _bubble(950, 0.9, 0.011), 0.45),
              (0.22, _bubble(640, 0.1, 0.014), 0.3), (0.28, _bubble(780, 0.1, 0.012), 0.24), (0.0, sick, 0.05)]
    return _finish(place(dur, events), 0.03)


@sound("ui_fate_die", loudness=-22, wet=0.25)
def ui_fate_die(seed):
    """The Dado del Destino rolled at a bump: a bone die bounces on stone
    (bright stiff modes, each bounce lower and quieter, the stone answering)
    and lands with a soft crystal ping of the mode (D6)."""
    dur = 0.4
    r = rng(seed)
    events = []
    for k, (t0, g) in enumerate(((0.0, 1.0), (0.055, 0.6), (0.095, 0.38), (0.12, 0.22))):
        die = _modes(0.04, [(r.uniform(2700, 3300) * 0.97 ** k, 0.005, 1.0), (r.uniform(4400, 5200), 0.0035, 0.6)],
                     attack=0.0001)
        events += [(t0, die, 0.5 * g), (t0, _stone(0.03, seed + 10 + k, lo=500, hi=2600, count=6, decay=0.004), 0.25 * g)]
    events.append((0.15, _crystal(_hz("D6"), 0.25, 0.06), 0.2))
    return _finish(place(dur, events), 0.03)


@sound("ui_status_expired", loudness=-28, wet=0.2)
def ui_status_expired(seed):
    """A soft fading puff: pink noise whose lowpass closes 3 kHz -> 500 Hz as
    it decays, with a faint crystal D6 bending down as it goes out."""
    dur = 0.4
    t = time_axis(dur)
    puff = highpass(pink(dur, seed), 180, 2)

    def closing(f, tt):
        c = 3000 * (500 / 3000) ** min(max(tt / 0.3, 0), 1)
        return 1 / np.sqrt(1 + (f / c) ** 4)
    puff = _norm(stft_filter(puff, closing)) * _expdecay(dur, 0.08, 0.01)
    f = _hz("D6") * (1 - 0.03 * np.clip(t / 0.25, 0, 1))
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * _expdecay(dur, 0.1, 0.006)
    x = 0.6 * puff + 0.08 * tone
    return _finish(x, 0.03)


@sound("ui_defeat", loudness=-18, wet=0.5)
def ui_defeat(seed):
    """Defeat: a low drone (D3, D2, D4, F4 in detuned saws behind a closing
    lowpass) sinks a fourth to A2; paper crumples in irregular clusters
    (0.2-0.95 s); a distant bell (the toll's voice, smaller: prime D4, highs
    lost to distance, soft attack) rings out above the drone at 1.0 s."""
    dur = 2.0
    t = time_axis(dur)
    u = np.clip((t - 0.25) / 1.35, 0, 1)
    sink = 2 ** (-5 / 12 * u * u * (3 - 2 * u))
    drone = np.zeros_like(t)
    for note, amp in (("D3", 1.0), ("D2", 0.7), ("D4", 0.3), ("F4", 0.18)):
        for d in (-0.0025, 0.0, 0.0028):
            drone += amp * saw(_hz(note) * (1 + d) * sink, n=len(t))

    def closing(f, tt):
        c = 1400 * (260 / 1400) ** min(max(tt / 1.8, 0), 1)
        return 1 / np.sqrt(1 + (f / c) ** 4)
    drone = _norm(stft_filter(drone, closing)) * _env(dur, [(0, 0), (0.12, 0.8), (0.4, 1), (1.3, 0.75), (1.95, 0)])
    # brown() is mostly sub-10 Hz drift: keep only the audible low wind.
    wind = _norm(highpass(lowpass(brown(dur, seed), 250, 2), 40, 2)) * _env(dur, [(0, 0), (0.3, 1), (1.9, 0)])
    r = rng(seed + 1)
    times, gains = [], []
    for c in sorted(0.2 + 0.75 * r.random(14)):
        for _ in range(r.integers(3, 8)):
            tk = c + r.uniform(0, 0.035)
            times.append(tk)
            gains.append(math.sin(math.pi * min(max((tk - 0.18) / 0.8, 0), 1)) ** 0.8)
    crumple = _paper(dur, times, seed + 2, band=(1500, 8000), glen=(0.003, 0.015), gains=gains)
    bell = _norm(lowpass(_bell(_hz("D4"), 1.0, tau=0.75, attack=0.006), 2200, 2))
    x = place(dur, [(0.0, drone, 0.45), (0.0, wind, 0.08), (0.0, crumple, 0.22), (1.0, bell, 0.22)])
    return _finish(x, 0.05)
