"""Family `arsenal`: the cannons, the black hole, the dinosaurs and the bleed
(SOUND_SPEC.md).

Four cards of the sixth batch and everything they put on the board. Every
recipe is dry and synthesized here (the build adds the stone hall); the family
reuses the `world` family's materials (iron, stone, blasts, fuse, dust puffs)
from sfx_world.py and the `cards_arms` family's paper flick and bone dice, and
adds a few of its own:

- the voice of the dinosaurs (_roar): never a recording and never a word. A
  glottal source (a bright pulse train of harmonics of a moving f0, a little
  jitter, an amplitude growl at 20-60 Hz that gives it the rattle of a big
  throat) goes through two sets of formants and crossfades from one to the
  other (the mouth opening and closing), with breath noise riding it. Small
  dinosaurs have a high f0 and high formants (the raptor's screech), the big
  ones a low f0 and low formants (the giant's roar: 50-120 Hz, so it is mostly
  chest and sub);
- the spiral (_spiral): a Shepard-style rising (or falling) glissando, four
  voices an octave apart, each fading in at the bottom and out at the top, so
  the pitch seems to climb forever, as matter circling a drain does;
- the energy of the laser: a charging whine (a glide in D, a sine with its
  harmonics and an FM shimmer), a mains-like hum under it (A2), sparks.

Tonal parts stay in D Phrygian (the whine climbs D3 -> D7, the spiral is built on
D). Every recipe keeps its peak at -1.5 dBFS or lower before the build's
ceiling, like the world family. The marks are the recipes' own key moments in
seconds; 0.0 is always the first sound.
"""
import math

import numpy as np

from dsp import *  # noqa: F401,F403
from registry import sound
from sfx_cards_arms import _clatter as _ca_clatter
from sfx_cards_arms import _die as _ca_die
from sfx_cards_arms import _flick as _ca_flick
from sfx_world import (_blast, _blub, _click, _creak, _finish, _fuse, _iron, _limit, _modes, _moving_band, _moving_lowpass, _norm,
                       _paper, _path, _pressure_thump, _puff, _scrape, _smooth, _snap, _sparks, _squash, _stone_chunk,
                       _stone_ticks, _t60, _thud, _wood)

_D1, _D2, _A2 = 36.71, 73.42, 110.0
_D3, _A3, _D4 = 146.83, 220.0, 293.66
_D5, _A5, _D6, _A6, _D7 = 587.33, 880.0, 1174.66, 1760.0, 2349.32


def _put(buf, t0, s, gain=1.0):
    """Adds `s` into `buf` at t0 (seconds), clipped to the buffer."""
    i = int(round(t0 * SR))
    if i >= len(buf):
        return
    e = min(len(buf), i + len(s))
    buf[i:e] += gain * s[:e - i]


def _curve(dur, points, log=False):
    """A per-sample curve through (t, value) points (linear, or in log)."""
    t = time_axis(dur)
    ts = [p[0] for p in points]
    vs = [math.log(p[1]) if log else p[1] for p in points]
    v = np.interp(t, ts, vs)
    return np.exp(v) if log else v


def _echo(x, taps, cutoff=2500.0):
    """The sound again, later and darker: taps [(delay_s, gain, cutoff_hz)], a
    little smeared (a cannon heard across a stone hall)."""
    out = x.copy()
    for d, g, c in taps:
        echo = lowpass(x, c, 2)
        echo = np.convolve(echo, np.hanning(n_samples(0.012)) / (n_samples(0.012) / 2), mode="same")
        _put(out, d, echo, g)
    return out


def _sc(points, k):
    """The same breakpoints with their times scaled by k (a call made shorter)."""
    return [(p[0] * k,) + tuple(p[1:]) for p in points]


def _decay(dur, t60, attack=0.002):
    t = time_axis(dur)
    return np.minimum(1.0, t / max(attack, 1e-4)) * _t60(t, t60)


def _tone(freq, dur, harmonics=(1.0, 0.5, 0.25), attack=0.004):
    """A tone through a (per-sample) frequency curve with a few harmonics."""
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n_samples(dur),))
    ph = np.cumsum(f) / SR
    x = np.zeros(len(f))
    for k, a in enumerate(harmonics, start=1):
        x += a * np.sin(2 * np.pi * k * ph) * (k * f < SR * 0.45)
    return x * np.minimum(1.0, time_axis(dur) / max(attack, 1e-4))


# --------------------------------------------------------------------------
# The voice of the dinosaurs

def _roar(dur, seed, f0_pts, form_a, form_b, mouth_pts, gain_pts, am=(30.0, 30.0), am_depth=0.5, breath=0.2, tilt=1.0,
          jitter=0.015, vib=(0.0, 0.0), harmonics=60, grit=0.0, hp=30.0):
    """A creature's call: harmonics of f0(t) (1/k^tilt, a jittered pulse), a
    growl (amplitude modulation sliding am[0] -> am[1] Hz with random depth),
    two formant sets crossfaded by `mouth` (0 = form_a, 1 = form_b), a breath
    of noise through the same formants and an overall gain curve. `grit`
    drives it into a rough, torn tone."""
    r = rng(seed)
    n = n_samples(dur)
    t = time_axis(dur)
    f0 = _curve(dur, f0_pts, log=True)
    if vib[0]:
        f0 = f0 * (1 + vib[1] * np.sin(2 * np.pi * vib[0] * t + r.uniform(0, 6.28)))
    f0 = f0 * (1 + jitter * _smooth(n, 60.0, seed + 1))
    ph = np.cumsum(f0) / SR
    src = np.zeros(n)
    for k in range(1, harmonics + 1):
        a = r.uniform(0.7, 1.0) / k ** tilt
        src += a * np.sin(2 * np.pi * k * ph + r.uniform(0, 6.28)) * (k * f0 < 16000)
    src = _norm(src)
    rate = _curve(dur, [(0, am[0]), (dur, am[1])], log=True)
    wob = np.sin(2 * np.pi * np.cumsum(rate) / SR + r.uniform(0, 6.28))
    depth = am_depth * (0.7 + 0.3 * _smooth(n, 8.0, seed + 2))
    src = src * (1 - depth * (0.5 + 0.5 * wob))
    nz = _norm(highpass(white(dur, seed + 3), 300, 1)) * breath
    mix = src + nz * _norm(np.abs(src))
    if grit:
        mix = drive(mix, 1 + 3 * grit)
    a = formant(mix, form_a)
    b = formant(mix, form_b)
    m = np.clip(_curve(dur, mouth_pts), 0, 1)
    y = (1 - m) * _norm(a) + m * _norm(b)
    y = highpass(y, hp, 2) * _curve(dur, gain_pts)
    return _norm(y)


# --------------------------------------------------------------------------
# The spiral

def _spiral(dur, rate_pts, f_lo=110.0, octaves=4, voices=4, up=True, seed=0):
    """Shepard glissando: `voices` partials an octave apart sliding through
    `octaves` octaves from f_lo, each fading in at the bottom and out at the
    top, at a speed of rate(t) octaves a second (rate_pts)."""
    rate = _curve(dur, rate_pts)
    u = np.cumsum(rate) / SR * (1 if up else -1)
    x = np.zeros(n_samples(dur))
    r = rng(seed)
    for j in range(voices):
        pos = np.mod(u + j * octaves / voices, octaves)
        f = f_lo * 2.0 ** pos
        amp = np.sin(np.pi * pos / octaves) ** 2
        ph = np.cumsum(f) / SR + r.uniform(0, 1)
        x += amp * (np.sin(2 * np.pi * ph) + 0.35 * np.sin(4 * np.pi * ph) * (f * 2 < 16000))
    return _norm(x)


def _swirl(dur, seed, lo, hi, cycles, q=1.0, power=1.0):
    """Noise through a band that sweeps lo -> hi, `cycles` times (the matter
    wheeling round the drain), with a swell on each pass."""
    def centre(tt):
        u = (tt / dur * cycles) % 1.0
        return lo * (hi / lo) ** (u ** power)
    x = _moving_band(pink(dur, seed), centre, q)
    t = time_axis(dur)
    u = (t / dur * cycles) % 1.0
    return _norm(x) * (0.35 + 0.65 * np.sin(np.pi * u))


# ==========================================================================
# Cards

@sound("card_cannon", loudness=-19, wet=0.25, rt60=1.0, marks=(0.0, 0.18, 0.32, 0.5),
       note="the card flicks out; the cannon is set on its stand: a heavy iron clunk at 0.18 (a deep thud, low iron modes ringing "
            "on D2-ish, a stone chunk under it), the barrel seated in its cradle at 0.32 (a smaller knock, wood and iron), a flint "
            "struck at 0.5 and the fuse lit, hissing and spitting until 1.25")
def card_cannon(seed):
    D = 1.3
    t = time_axis(D)
    clunk_at, seat_at, light_at = 0.18, 0.32, 0.5
    flick = _ca_flick(seed)
    clunk = place(0.9, [
        (0.0, _norm(_thud(0.45, seed + 1, f0=64.0, t60=0.28, lp=420, drop=0.9)), 1.0),
        (0.0, _iron(0.9, 150.0, 0.6, seed + 2, count=9, dark=0.5), 0.55),
        (0.0, _stone_chunk(seed + 3, base=330.0, t60=0.05, length=0.25, low=0.4), 0.45),
        (0.0, _click(seed + 4, hp=900, tau=0.0007), 0.4),
    ])
    seat = place(0.5, [
        (0.0, _norm(_thud(0.25, seed + 5, f0=105.0, t60=0.12, lp=700, drop=0.6)), 0.8),
        (0.0, _iron(0.5, 330.0, 0.22, seed + 6, count=8, dark=0.6), 0.45),
        (0.0, _wood(0.2, 240.0, seed + 7, t60=0.08, contact=0.5), 0.4),
    ])
    # a flint struck on steel (a bright scratch and a spray of sparks), then the fuse
    scratch = _norm(highpass(white(0.05, seed + 8), 3000, 2)) * np.minimum(1, time_axis(0.05) / 0.01) * _t60(time_axis(0.05), 0.05)
    sparks = _sparks(0.2, seed + 9, 220.0, envelope=lambda u: (1 - u) ** 1.5, lo=3000, hi=9000)
    fuse_len = D - light_at - 0.02
    fuse = _fuse(fuse_len, seed + 10, spit_rate=9.0) * env_points(fuse_len, [(0, 0), (0.04, 1.0), (0.5, 0.9), (fuse_len, 0.0)])
    x = place(D, [
        (0.0, flick, 0.5),
        (clunk_at, clunk, 0.95),
        (seat_at, seat, 0.7),
        (light_at - 0.03, scratch, 0.35),
        (light_at, _norm(sparks), 0.35),
        (light_at, _norm(fuse), 0.32),
        (light_at, _puff(seed + 11, length=0.25, center=2500.0), 0.1),
    ])
    return _finish(_limit(x, 0.7), D, fade_out=0.12)


@sound("card_laser_cannon", loudness=-19, wet=0.2, rt60=0.8, marks=(0.0, 0.16, 1.0, 1.05),
       note="the card flicks out; the emitter is seated on its stand at 0.16 (a clank of steel on stone), then the charge-up: "
            "a whine climbing D3 -> D7 from 0.28 to 1.0 (sine and harmonics with an FM shimmer, a second voice a hair sharp, the "
            "mains hum A2 swelling under it, sparks thickening), a bright lock at 1.0 (a click and D6/A6 chimes) and a held "
            "high hum to 1.45")
def card_laser_cannon(seed):
    D = 1.5
    t = time_axis(D)
    n = len(t)
    t0, t1 = 0.28, 1.0
    u = np.clip((t - t0) / (t1 - t0), 0, 1)
    f = _D3 * (_D7 / _D3) ** (u ** 1.15)
    f = np.where(t < t0, _D3, f)
    f = np.where(t > t1, _D7 * 0.5, f)           # after the lock it settles an octave down: the held hum, D6
    ph = np.cumsum(f) / SR
    am = 1 + 0.25 * np.sin(2 * np.pi * np.cumsum(7 + 22 * u) / SR)
    whine = (np.sin(2 * np.pi * ph) + 0.45 * np.sin(4 * np.pi * ph) * (f * 2 < 14000) + 0.2 * np.sin(6 * np.pi * ph) * (f * 3 < 14000))
    shimmer = np.sin(2 * np.pi * ph * 1.007 + 1.3 * np.sin(2 * np.pi * ph * 1.5))
    swell = np.where(t < t1, 0.1 + 0.9 * u ** 1.3, 1.0)
    held = np.where(t < t1, 1.0, np.exp(-(t - t1) / 0.3))
    voice = _norm(0.7 * whine + 0.5 * shimmer) * am * swell * np.where(t >= t0, 1.0, 0.0) * held
    voice *= np.minimum(1, np.clip(t - t0, 0, None) / 0.03)
    hum = _hum_a2(D, seed) * env_points(D, [(0, 0), (t0, 0.1), (t1, 1.0), (D, 0.0)])
    spk = _sparks(D, seed + 2, 400.0, start=t0, end=t1 + 0.1, envelope=lambda uu: 0.15 + 0.85 * uu ** 2, lo=2500, hi=10000)
    seatd = place(0.5, [(0.0, _norm(_thud(0.25, seed + 3, f0=110.0, t60=0.1, lp=800, drop=0.5)), 0.8),
                        (0.0, _iron(0.5, 420.0, 0.3, seed + 4, count=8, dark=0.4), 0.5),
                        (0.0, _click(seed + 5, hp=1500, tau=0.0005), 0.4)])
    lock = place(0.6, [(0.0, _click(seed + 6, length=0.004, tau=0.0004, hp=2500), 0.8),
                       (0.0, _bell_ping(_D6, 0.5, 0.25), 0.55), (0.03, _bell_ping(_A6, 0.45, 0.2), 0.4)])
    x = place(D, [
        (0.0, _ca_flick(seed), 0.5),
        (0.16, seatd, 0.6),
        (0.0, voice, 0.7),
        (0.0, hum, 0.35),
        (0.0, _norm(spk), 0.18),
        (t1, lock, 0.6),
    ])
    return _finish(_limit(x, 0.7), D, fade_out=0.2)


def _hum_a2(dur, seed):
    """The mains hum of the energy devices: A2 with its harmonics."""
    n = n_samples(dur)
    r = rng(seed)
    t = time_axis(dur)
    x = np.zeros(n)
    for k in range(1, 12):
        x += r.uniform(0.7, 1.0) / k ** 0.9 * np.sin(2 * np.pi * _A2 * k * t * (1 + 0.002 * _smooth(n, 3.0, seed + 1)) + r.uniform(0, 6.28))
    return _norm(x)


def _bell_ping(freq, dur, t60):
    """A bright glassy ping: a sine and two inharmonic partials."""
    t = time_axis(dur)
    x = np.sin(2 * np.pi * freq * t) + 0.4 * np.sin(2 * np.pi * freq * 2.76 * t) * _t60(t, t60 * 0.4)
    return x * np.minimum(1, t / 0.0006) * _t60(t, t60)


@sound("card_black_hole", loudness=-19, wet=0.15, rt60=0.6, marks=(0.0, 0.5, 0.95, 1.15),
       note="the card flicks out and the void swells: a deep D2 sub drone sinking under a dark brown rumble (0.1-1.15), a spiral "
            "of voices rising forever (D3 upward, faster and faster, four octaves wide) over a band of noise wheeling round it, "
            "everything drawn inward from 0.95 (a suction falling 3 kHz -> 200 Hz) to a deep soft thump at 1.15 and a low breath "
            "of the void after it")
def card_black_hole(seed):
    D = 1.65
    t = time_axis(D)
    sw = env_points(D, [(0, 0), (0.12, 0.1), (0.95, 1.0), (1.15, 0.9), (D, 0.0)])
    f_sub = _D2 * (1 - 0.25 * np.clip(t / 1.15, 0, 1))
    sub = (np.sin(2 * np.pi * np.cumsum(f_sub) / SR) + 0.3 * np.sin(4 * np.pi * np.cumsum(f_sub) / SR)) * sw
    rumble = _norm(lowpass(brown(D, seed), 200, 2)) * sw
    spiral = _spiral(1.15, [(0, 0.6), (0.7, 1.3), (1.15, 3.0)], f_lo=_D3, octaves=4, voices=4, up=True, seed=seed + 1)
    spiral = lowpass(spiral, 3500, 2) * env_points(1.15, [(0, 0), (0.25, 0.45), (0.85, 1.0), (1.15, 0.0)])
    swirl = _swirl(1.15, seed + 2, 300, 2600, 2.5, q=1.2) * env_points(1.15, [(0, 0), (0.3, 0.5), (0.95, 1.0), (1.15, 0.0)])
    pull_len = 0.3
    pull = _norm(_moving_band(pink(pull_len, seed + 3), _path([(0, 3000), (pull_len, 200)]), 0.8)) * env_points(
        pull_len, [(0, 0), (0.1, 1.0), (pull_len, 0.0)])
    thump = place(0.6, [(0.0, _norm(_thud(0.5, seed + 4, f0=52.0, t60=0.3, lp=240, drop=0.6)), 1.0)])
    breath = _norm(_moving_band(pink(0.5, seed + 5), _path([(0, 500), (0.5, 120)]), 0.7)) * env_points(0.5, [(0, 0), (0.08, 0.6), (0.5, 0.0)])
    x = place(D, [
        (0.0, _ca_flick(seed), 0.45),
        (0.0, _norm(sub), 0.8),
        (0.0, rumble, 0.5),
        (0.0, spiral, 0.55),
        (0.0, swirl, 0.28),
        (0.95, pull, 0.45),
        (1.15, thump, 1.0),
        (1.2, breath, 0.25),
    ])
    return _finish(_limit(x, 0.7), D, fade_out=0.25)


@sound("card_dinosaur", loudness=-19, wet=0.25, rt60=0.9, marks=(0.0, 0.05, 0.5, 0.68),
       note="the card flicks out and a bone d4 is rattled in a cupped hand (0.05-0.5: four shakes, tumbling over its points, "
            "settling in a few ticks at 0.5), then a roar sting at 0.68: a big throat opening (a growl on 80 -> 140 Hz rising "
            "into a bellow, the mouth opening from 0.68, a breath of air) and sinking away by 1.6")
def card_dinosaur(seed):
    D = 1.75
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
    roar = _roar(1.05, seed + 7,
                 f0_pts=[(0, 80), (0.1, 130), (0.35, 145), (0.7, 105), (1.05, 62)],
                 form_a=[(260, 3, 1.0), (720, 3, 0.8), (1500, 3, 0.4), (2700, 2, 0.2)],
                 form_b=[(190, 3, 1.0), (520, 3, 0.7), (1100, 2.5, 0.3)],
                 mouth_pts=[(0, 1), (0.13, 0.0), (0.5, 0.2), (1.05, 1.0)],
                 gain_pts=[(0, 0), (0.03, 1.0), (0.5, 0.9), (1.05, 0.0)],
                 am=(40, 26), am_depth=0.5, breath=0.25, tilt=1.0, grit=0.5, hp=45)
    sub = _tone(_curve(1.05, [(0, 55), (0.1, 62), (1.05, 40)], log=True), 1.05, harmonics=(1.0, 0.3)) * env_points(1.05, [(0, 0), (0.05, 1), (0.6, 0.7), (1.05, 0)])
    air = _norm(_moving_band(pink(0.8, seed + 8), _path([(0, 2500), (0.8, 700)]), 0.7)) * env_points(0.8, [(0, 0), (0.05, 1.0), (0.8, 0.0)])
    x = place(D, [
        (0.0, _ca_flick(seed), 0.5),
        (0.0, _norm(rattle), 0.5),
        (0.0, _norm(table), 0.28),
        (0.68, roar, 0.9),
        (0.68, _norm(sub), 0.3),
        (0.68, air, 0.12),
    ])
    return _finish(_limit(x, 0.7), D, fade_out=0.2)


# ==========================================================================
# The cannon

@sound("world_cannon_place", loudness=-18.5, wet=0.25, rt60=0.9, marks=(0.0,),
       note="the cannon's stand set down on stone at 0.0: a heavy thud (68 Hz falling), the iron of the stand ringing low and "
            "short, a stone chunk and a small puff of dust, ending by 0.45")
def world_cannon_place(seed):
    D = 0.5
    x = place(D, [
        (0.0, _norm(_thud(0.3, seed, f0=68.0, t60=0.18, lp=420, drop=0.9)), 1.0),
        (0.0, _iron(0.45, 160.0, 0.22, seed + 1, count=8, dark=0.7), 0.5),
        (0.0, _stone_chunk(seed + 2, base=300.0, t60=0.05, length=0.2, low=0.4), 0.5),
        (0.0, _click(seed + 3, hp=900, tau=0.0007), 0.35),
        (0.01, _puff(seed + 4, length=0.3, center=800.0), 0.3),
    ])
    return _finish(_limit(x, 0.7), D, fade_out=0.08)


@sound("world_cannon_fire", loudness=-18, wet=0.3, rt60=0.9, marks=(0.0, 0.3, 0.55),
       note="the shot at 0.0: a hard pressure front, a falling boom (110 -> 44 Hz), the barrel ringing on iron, a flame's whoof "
            "and a puff of smoke; its echo comes back off the walls at 0.3 and again, fainter and darker, at 0.55, gone by 0.95")
def world_cannon_fire(seed):
    D = 1.0
    t = time_axis(D)
    boom = _blast(0.7, seed, f_start=110.0, f_end=44.0, t60=0.55, sub=1.0, body=0.9, roar=0.9, front=0.7, boom_len=0.4,
                  rumble_hp=45.0, roar_center=340.0, punch=1.0, sustain=0.0)
    boom = _squash(boom, threshold=0.22, ratio=3.0, window=0.02)
    iron = _iron(0.6, 190.0, 0.45, seed + 1, count=8, dark=0.5)
    whoof = _norm(_moving_band(pink(0.4, seed + 2), _path([(0, 1400), (0.4, 300)]), 0.6)) * env_points(0.4, [(0, 1.0), (0.05, 0.8), (0.4, 0.0)])
    crack = _norm(highpass(white(0.02, seed + 3), 1500, 2)) * np.exp(-time_axis(0.02) / 0.003)
    shot = place(D, [(0.0, boom, 1.0), (0.0, _norm(iron), 0.22), (0.0, whoof, 0.3), (0.0, crack, 0.4),
                     (0.0, _puff(seed + 4, length=0.4, center=700.0), 0.2)])
    x = _echo(shot, [(0.3, 0.38, 1700.0), (0.55, 0.17, 900.0)])
    return _finish(_limit(x, 0.7), D, fade_out=0.1)


@sound("world_cannon_hit", loudness=-19, wet=0.2, rt60=0.6, marks=(0.0,),
       note="the iron ball strikes a body at 0.0: a dull crack (a hard click and a short wooden snap), a heavy muffled thud "
            "under it, the foe's card crumpled for a few grains to 0.06, a faint iron ring")
def world_cannon_hit(seed):
    D = 0.4
    x = place(D, [
        (0.0, _click(seed, length=0.006, tau=0.0008, hp=900, lp=9000), 0.7),
        (0.0, _wood(0.2, 430.0, seed + 1, t60=0.05, contact=0.7), 0.7),
        (0.0, _norm(_thud(0.25, seed + 2, f0=125.0, t60=0.1, lp=650, drop=0.7)), 1.0),
        (0.0, _iron(0.3, 520.0, 0.08, seed + 3, count=6, dark=0.8), 0.18),
        (0.003, _norm(_paper(0.08, [0.0, 0.012, 0.03, 0.05], seed + 4, lo=1500, hi=6000, lmin=0.008, lmax=0.02)), 0.3),
    ])
    x = _squash(x, threshold=0.3, ratio=2.2, window=0.005, smooth=0.003)
    return _finish(_limit(x, 0.6), D, fade_out=0.06)


@sound("world_cannon_break", loudness=-16, wet=0.3, rt60=0.9, marks=(0.0, 0.12, 0.34, 0.52),
       note="the cannon falls apart: a sharp crack of overstrained iron at 0.0, its bands springing off in pings (0.03-0.2), the "
            "barrel tumbling off its stand in heavy clanks (0.12, 0.34, 0.52, each lower and softer), the stand crumbling "
            "with stone chunks and gravel to 1.0")
def world_cannon_break(seed):
    D = 1.1
    r = rng(seed)
    crack = _norm(highpass(white(0.025, seed), 1200, 2)) * np.exp(-time_axis(0.025) / 0.004)
    groan = _norm(_creak(0.12, seed + 1, 90, 200, body=(420.0, 900.0, 1700.0), jitter=0.3, t60=0.04)) * env_points(0.12, [(0, 0), (0.1, 1), (0.12, 0)])
    pings = silence(D)
    for k, t0 in enumerate((0.03, 0.07, 0.11, 0.16, 0.2)):
        _put(pings, t0, _iron(0.25, r.uniform(900, 2400), 0.12, seed + 10 + k, count=6, dark=0.5), r.uniform(0.3, 0.7))
    clanks = []
    for k, (t0, base, g) in enumerate(((0.12, 170.0, 1.0), (0.34, 140.0, 0.6), (0.52, 115.0, 0.35))):
        clank = place(0.6, [(0.0, _iron(0.6, base, 0.4, seed + 20 + k, count=9, dark=0.4), 0.7),
                            (0.0, _norm(_thud(0.3, seed + 30 + k, f0=base * 0.55, t60=0.14, lp=500, drop=0.7)), 0.9),
                            (0.0, _click(seed + 40 + k, hp=900, tau=0.0007), 0.35)])
        clanks.append((t0, clank, g))
    chunks = [(0.1 + 0.07 * k, _stone_chunk(seed + 50 + k, base=b, t60=0.05, length=0.2, low=0.5), g)
              for k, (b, g) in enumerate(((380, 0.7), (520, 0.5), (300, 0.5), (700, 0.35), (450, 0.3)))]
    grit = _stone_ticks(D, random_times(D, 70, seed + 60, 0.1, 1.0, envelope=lambda u: (1 - u) ** 1.5), seed + 61, lo=1400, hi=7000,
                        lmin=0.0015, lmax=0.006, power=1.8)
    dust = place(D, [(0.14, _puff(seed + 62, length=0.5, center=700.0), 0.5)])
    x = place(D, [(0.0, crack, 0.8), (0.0, groan, 0.35), (0.0, _norm(pings), 0.35)] + clanks + chunks +
              [(0.0, _norm(grit), 0.25), (0.0, dust, 0.5)])
    return _finish(_limit(x, 0.7), D, fade_out=0.15)


@sound("world_laser_fire", loudness=-17, wet=0.2, rt60=0.7, marks=(0.0, 0.1),
       note="the zap at 0.0: a hard electric crack and a pew falling 5.2 kHz -> 400 Hz in 0.28 s (a sine and its harmonics, an FM "
            "shimmer on it), a bright beam buzz (A2 hum bright with corona and crackle) held to 0.3 and fading by 0.45")
def world_laser_fire(seed):
    D = 0.5
    t = time_axis(D)
    f = 5200.0 * (400.0 / 5200.0) ** (np.clip(t / 0.28, 0, 1) ** 0.75)
    ph = np.cumsum(f) / SR
    pew = np.sin(2 * np.pi * ph) + 0.4 * np.sin(4 * np.pi * ph) * (f * 2 < 16000) + 0.4 * np.sin(2 * np.pi * ph * 1.01 + 1.4 * np.sin(2 * np.pi * ph * 2.0))
    pew = _norm(pew) * np.minimum(1, t / 0.0008) * np.where(t < 0.28, 1.0, np.exp(-(t - 0.28) / 0.04)) * (0.3 + 0.7 * np.exp(-t / 0.12))
    crack = _norm(_snap(seed, size=1.0, length=0.06))
    buzz_len = 0.42
    buzz = _hum_a2(buzz_len, seed + 1)
    buzz = highpass(drive(buzz, 3.0), 150, 2)
    buzz = _norm(buzz) * env_points(buzz_len, [(0, 0.0), (0.01, 1.0), (0.25, 0.7), (buzz_len, 0.0)])
    corona = _norm(_sparks(buzz_len, seed + 2, 1100.0, lo=2500, hi=10000)) * env_points(buzz_len, [(0, 1.0), (0.25, 0.5), (buzz_len, 0.0)])
    x = place(D, [(0.0, pew, 0.9), (0.0, crack, 0.6), (0.0, _norm(buzz), 0.45), (0.0, corona, 0.3),
                  (0.0, _pressure_thump(0.08, f0=95.0), 0.3)])
    return _finish(_limit(x, 0.7), D, fade_out=0.1)


# ==========================================================================
# The black hole

@sound("world_black_hole_open", loudness=-18, wet=0.15, rt60=0.6, marks=(0.0, 0.3, 0.6, 0.85),
       note="the floor tears open at 0.0: a ripping crackle falling 6 kHz -> 800 Hz (0.0-0.3), then the void swelling (a D2 sub "
            "and a dark rumble blooming by 0.6) with a spiral of voices rising round it (0.15-1.05, ever faster) and a band "
            "of noise wheeling; a last low settling hum at 0.85 as the hole stays open")
def world_black_hole_open(seed):
    D = 1.05
    t = time_axis(D)
    rip_len = 0.35
    rip = crackle(rip_len, _curve(rip_len, [(0, 2400), (0.22, 900), (rip_len, 200)]), seed, decay=0.0004)
    rip = _norm(_moving_band(rip, _path([(0, 6000), (0.28, 800), (rip_len, 500)]), 0.5)) * env_points(rip_len, [(0, 1.0), (0.28, 0.6), (rip_len, 0.0)])
    tear = _norm(_moving_band(white(0.28, seed + 1), _path([(0, 7000), (0.28, 900)]), 0.7)) * env_points(0.28, [(0, 0), (0.02, 1.0), (0.28, 0.0)])
    sw = env_points(D, [(0, 0), (0.12, 0.2), (0.55, 1.0), (0.85, 0.7), (D, 0.0)])
    sub = np.sin(2 * np.pi * np.cumsum(_D2 * (1 + 0.15 * np.exp(-t / 0.5))) / SR) * sw
    rumble = _norm(lowpass(brown(D, seed + 2), 220, 2)) * sw
    spiral = _spiral(0.9, [(0, 0.8), (0.5, 1.8), (0.9, 3.0)], f_lo=_D3, octaves=4, voices=4, up=True, seed=seed + 3)
    spiral = lowpass(spiral, 4000, 2) * env_points(0.9, [(0, 0), (0.2, 0.7), (0.65, 1.0), (0.9, 0.0)])
    swirl = _swirl(0.9, seed + 4, 400, 3000, 3.0, q=1.2) * env_points(0.9, [(0, 0), (0.25, 0.8), (0.7, 1.0), (0.9, 0.0)])
    settle = _tone(_curve(0.3, [(0, _D3), (0.3, _D2)], log=True), 0.3, harmonics=(1.0, 0.4)) * env_points(0.3, [(0, 0), (0.08, 1.0), (0.3, 0.0)])
    x = place(D, [
        (0.0, rip, 0.75), (0.0, tear, 0.4),
        (0.0, _norm(sub), 0.65), (0.0, rumble, 0.5),
        (0.15, spiral, 0.5), (0.15, swirl, 0.25),
        (0.8, _norm(settle), 0.25),
    ])
    return _finish(_limit(x, 0.7), D, fade_out=0.2)


@sound("world_black_hole_hum", loudness=-24, wet=0.02, rt60=0.3, marks=(0.0, 0.5),
       note="one beat of the hole's hum, exactly a second (it comes back every second, so it swells from silence and sinks to "
            "silence): a sub-bass D2 falling a little (73 -> 66 Hz) with its second harmonic, a slow rumble, and a whoosh of "
            "suction (a band 280 -> 1300 -> 320 Hz) cresting at 0.5; dry, so beats do not smear into each other")
def world_black_hole_hum(seed):
    D = 1.0
    t = time_axis(D)
    n = len(t)
    env = np.sin(np.pi * np.clip(t / D, 0, 1)) ** 1.5
    f = _D2 * (1 - 0.1 * t / D)
    ph = np.cumsum(f) / SR
    sub = (np.sin(2 * np.pi * ph) + 0.45 * np.sin(4 * np.pi * ph) + 0.15 * np.sin(6 * np.pi * ph)) * env
    rumble = _norm(lowpass(brown(D, seed), 180, 2)) * env
    suck = _norm(_moving_band(pink(D, seed + 1), _path([(0, 280), (0.5, 1300), (D, 320)]), 1.0)) * env ** 1.4
    air = _norm(highpass(white(D, seed + 2), 3000, 2)) * env ** 3 * (0.6 + 0.4 * _smooth(n, 14.0, seed + 3))
    x = 0.8 * _norm(sub) + 0.35 * rumble + 0.45 * suck + 0.05 * air
    return _finish(_limit(x, 0.7), D, fade_out=0.04)


@sound("world_black_hole_pull", loudness=-21, wet=0.15, rt60=0.5, marks=(0.0, 0.22),
       note="a foe is dragged toward the hole: a suction rising from 0.0 (a band 300 -> 2500 Hz, swelling), the card scraping "
            "across stone (a gritty drag 0.02-0.25), a soft whoosh falling away as it is taken, a small low tug at 0.22")
def world_black_hole_pull(seed):
    D = 0.38
    suck = _norm(_moving_band(pink(0.34, seed), _path([(0, 300), (0.24, 2500), (0.34, 1800)]), 1.0)) * env_points(
        0.34, [(0, 0), (0.22, 1.0), (0.34, 0.0)])
    scr = _scrape(0.22, seed + 1, hi=4500, lo=1600) * env_points(0.22, [(0, 0), (0.08, 1.0), (0.22, 0.5)])
    drag = _norm(bandpass(brown(0.28, seed + 2), 220, 0.8)) * env_points(0.28, [(0, 0.2), (0.2, 1.0), (0.28, 0.0)])
    tug = _norm(_thud(0.16, seed + 3, f0=90.0, t60=0.08, lp=350, drop=0.5))
    x = place(D, [(0.0, suck, 0.8), (0.02, scr, 0.35), (0.0, drag, 0.4), (0.22, tug, 0.55)])
    return _finish(_limit(x, 0.7), D, fade_out=0.06)


@sound("world_black_hole_swallow", loudness=-19, wet=0.2, rt60=0.6, marks=(0.0, 0.3),
       note="a foe is swallowed: an inward whoosh (a band falling 2.4 kHz -> 200 Hz, 0.0-0.3) and at 0.3 a pop "
            "(a bubble's plop falling 700 -> 90 Hz) closing with a soft low thump, a faint ring of the void after it")
def world_black_hole_swallow(seed):
    D = 0.62
    t = time_axis(D)
    whoosh = _norm(_moving_band(pink(0.34, seed), _path([(0, 2400), (0.3, 200), (0.34, 160)]), 0.9)) * env_points(
        0.34, [(0, 0), (0.1, 1.0), (0.3, 0.8), (0.34, 0.0)])
    pl = 0.2
    tp = time_axis(pl)
    pf = 90.0 + 610.0 * np.exp(-tp / 0.035)
    plop = np.sin(2 * np.pi * np.cumsum(pf) / SR) * np.minimum(1, tp / 0.0008) * np.exp(-tp / 0.045)
    pop = _click(seed + 1, length=0.004, tau=0.0004, hp=1200)
    thump = _norm(_thud(0.3, seed + 2, f0=60.0, t60=0.18, lp=260, drop=0.6))
    ring = _tone(_curve(0.4, [(0, _D3), (0.4, _D2)], log=True), 0.4, harmonics=(1.0, 0.3)) * _decay(0.4, 0.18, 0.02)
    x = place(D, [(0.0, whoosh, 0.7), (0.3, _norm(plop), 0.9), (0.3, pop, 0.35), (0.31, thump, 0.7), (0.32, _norm(ring), 0.22)])
    return _finish(_limit(x, 0.7), D, fade_out=0.1)


@sound("world_black_hole_close", loudness=-18, wet=0.25, rt60=0.8, marks=(0.0, 0.38, 0.6),
       note="the hole collapses: the spiral falling back down (0.0-0.55, slowing) over a sub that sinks, everything rushing into "
            "a point (a suction band falling 3.5 kHz -> 150 Hz, peaking 0.38), a sharp pop at 0.6 (a click and a dive "
            "1.1 kHz -> 150 Hz), a thin glassy ping falling away to 0.95")
def world_black_hole_close(seed):
    D = 0.95
    spiral = _spiral(0.6, [(0, 3.0), (0.35, 1.8), (0.6, 0.8)], f_lo=_D3, octaves=4, voices=4, up=False, seed=seed)
    spiral = lowpass(spiral, 4000, 2) * env_points(0.6, [(0, 0.0), (0.08, 1.0), (0.42, 0.8), (0.6, 0.0)])
    sub = _tone(_curve(0.65, [(0, _D2), (0.6, 45.0)], log=True), 0.65, harmonics=(1.0, 0.35)) * env_points(0.65, [(0, 0.2), (0.18, 1.0), (0.6, 0.8), (0.65, 0.0)])
    suck = _norm(_moving_band(pink(0.6, seed + 1), _path([(0, 3500), (0.38, 800), (0.6, 150)]), 0.8)) * env_points(
        0.6, [(0, 0), (0.2, 0.7), (0.38, 1.0), (0.6, 0.0)])
    swirl = _swirl(0.6, seed + 2, 3000, 300, 2.0, q=1.2) * env_points(0.6, [(0, 0.5), (0.34, 1.0), (0.6, 0.0)])
    pl = 0.22
    tp = time_axis(pl)
    pf = 150.0 + 950.0 * np.exp(-tp / 0.03)
    pop = np.sin(2 * np.pi * np.cumsum(pf) / SR) * np.minimum(1, tp / 0.0006) * np.exp(-tp / 0.05)
    ping = _bell_ping(_A6, 0.4, 0.25) * _decay(0.4, 0.25)
    x = place(D, [
        (0.0, spiral, 0.5), (0.0, _norm(sub), 0.7), (0.0, suck, 0.6), (0.0, swirl, 0.2),
        (0.6, _norm(pop), 0.9), (0.6, _click(seed + 3, length=0.005, tau=0.0005, hp=1500), 0.5),
        (0.6, _norm(_thud(0.22, seed + 4, f0=70.0, t60=0.1, lp=300, drop=0.6)), 0.5),
        (0.62, ping, 0.18),
    ])
    return _finish(_limit(x, 0.7), D, fade_out=0.2)


# ==========================================================================
# The dinosaurs

@sound("world_dino_roar_raptor", loudness=-17, wet=0.2, rt60=0.6, marks=(0.0, 0.07),
       note="the raptor's screech: a short high call, f0 rising 900 -> 1700 Hz in 0.1 s then falling to 780 by 0.6, a fast "
            "vibrato, bright formants at 2.2 and 3.6 kHz, a raspy 70 Hz growl in it, breath on top; over by 0.75")
def world_dino_roar_raptor(seed):
    D = 0.6
    roar = _roar(D, seed,
                 f0_pts=[(0, 900), (0.04, 1500), (0.1, 1700), (0.28, 1250), (D, 780)],
                 form_a=[(1300, 3, 0.8), (2300, 3, 1.0), (3700, 3, 0.7), (5500, 2, 0.3)],
                 form_b=[(900, 3, 0.8), (1800, 3, 1.0), (3200, 3, 0.5)],
                 mouth_pts=[(0, 1), (0.07, 0.0), (0.35, 0.4), (D, 1.0)],
                 gain_pts=[(0, 0), (0.01, 1.0), (0.18, 0.9), (0.42, 0.55), (D, 0.0)],
                 am=(72, 55), am_depth=0.4, breath=0.4, tilt=0.7, jitter=0.02, vib=(22.0, 0.03), harmonics=24, grit=0.35, hp=300)
    air = _norm(_moving_band(white(0.35, seed + 1), _path([(0, 5500), (0.35, 3000)]), 0.8)) * env_points(0.35, [(0, 0), (0.01, 1.0), (0.35, 0.0)])
    x = place(D, [(0.0, roar, 0.9), (0.0, air, 0.12)])
    return _finish(_limit(x, 0.7), D, fade_out=0.12)


@sound("world_dino_roar_stego", loudness=-17, wet=0.22, rt60=0.7, marks=(0.0, 0.17),
       note="the stegosaurus's grunting bellow: a short grunt at 0.0 (f0 120 -> 150 -> 95 Hz) and a longer bellow at 0.17 "
            "(140 -> 210 -> 108 Hz, a slow 24 Hz growl, the mouth opening and closing), mid formants at 500 Hz and 1 kHz, a "
            "chesty body; over by 1.1")
def world_dino_roar_stego(seed):
    D = 0.9
    grunt = _roar(0.22, seed,
                  f0_pts=[(0, 120), (0.04, 150), (0.22, 95)],
                  form_a=[(450, 3, 1.0), (950, 3, 0.6), (2200, 2, 0.25)],
                  form_b=[(330, 3, 1.0), (700, 3, 0.5), (1800, 2, 0.2)],
                  mouth_pts=[(0, 1), (0.04, 0.0), (0.22, 0.8)],
                  gain_pts=[(0, 0), (0.01, 1.0), (0.1, 0.8), (0.22, 0.0)],
                  am=(30, 30), am_depth=0.35, breath=0.2, tilt=1.1, grit=0.4, hp=55)
    bellow = _roar(0.7, seed + 1,
                   f0_pts=[(0, 140), (0.1, 175), (0.28, 210), (0.56, 140), (0.7, 108)],
                   form_a=[(520, 3, 1.0), (1050, 3, 0.7), (2400, 2, 0.3)],
                   form_b=[(360, 3, 1.0), (760, 3, 0.5), (1700, 2, 0.2)],
                   mouth_pts=[(0, 1), (0.07, 0.1), (0.35, 0.0), (0.56, 0.5), (0.7, 1.0)],
                   gain_pts=[(0, 0), (0.02, 0.9), (0.14, 1.0), (0.46, 0.8), (0.7, 0.0)],
                   am=(24, 20), am_depth=0.5, breath=0.18, tilt=1.0, vib=(5.0, 0.012), grit=0.35, hp=55)
    chest = _tone(_curve(0.7, [(0, 70), (0.28, 105), (0.7, 55)], log=True), 0.7, harmonics=(1.0, 0.3)) * env_points(0.7, [(0, 0), (0.07, 1), (0.6, 0.6), (0.7, 0)])
    x = place(D, [(0.0, grunt, 0.8), (0.17, bellow, 1.0), (0.17, _norm(chest), 0.22)])
    return _finish(_limit(x, 0.7), D, fade_out=0.12)


@sound("world_dino_roar_dilo", loudness=-19, wet=0.2, rt60=0.6, marks=(0.0, 0.05, 0.26),
       note="the dilophosaurus's hissing chirp-rattle: a hiss swelling at 0.0 (noise 3-9 kHz), a chirp at 0.05 (a tone gliding "
            "1.6 -> 3.4 kHz and snapping back, an FM warble on it), then the frill's rattle at 0.26 (26 clicks a second through "
            "a 1.4 kHz resonance) over a trailing hiss; over by 0.8")
def world_dino_roar_dilo(seed):
    D = 0.7
    r = rng(seed)
    t = time_axis(D)
    hiss = _norm(_moving_band(white(D, seed), _path([(0, 4000), (0.26, 7500), (D, 3500)]), 0.5)) * env_points(
        D, [(0, 0), (0.05, 0.6), (0.18, 1.0), (0.35, 0.5), (0.55, 0.7), (D, 0.0)]) * (0.7 + 0.3 * _smooth(len(t), 30.0, seed + 1))
    cl = 0.25
    tc = time_axis(cl)
    cf = np.where(tc < 0.14, 1600.0 * (3400.0 / 1600.0) ** (tc / 0.14), 3400.0 * (1100.0 / 3400.0) ** np.clip((tc - 0.14) / 0.04, 0, 1))
    cph = np.cumsum(cf) / SR
    chirp = np.sin(2 * np.pi * cph + 1.2 * np.sin(2 * np.pi * cph * 0.5)) + 0.4 * np.sin(4 * np.pi * cph)
    chirp = chirp * np.minimum(1, tc / 0.006) * env_points(cl, [(0, 0), (0.01, 1.0), (0.14, 0.9), (0.18, 0.0), (cl, 0.0)])
    rattle = silence(D)
    k = 0
    tt = 0.26
    while tt < 0.62:
        ring = _norm(_modes(0.03, [(1400 * r.uniform(0.95, 1.05), 0.006, 1.0), (2700 * r.uniform(0.95, 1.05), 0.004, 0.6), (4300, 0.003, 0.4)]))
        _put(rattle, tt, ring, r.uniform(0.5, 1.0) * (1 - 0.6 * (tt - 0.26) / 0.36))
        _put(rattle, tt, pad_to(_click(seed + 10 + k, length=0.003, tau=0.0004, hp=2000), 0.03), 0.4)
        tt += 1 / 26.0 * r.uniform(0.9, 1.1)
        k += 1
    growl = _tone(_curve(0.4, [(0, 190), (0.4, 120)], log=True), 0.4, harmonics=(1.0, 0.6, 0.4, 0.3)) * env_points(0.4, [(0, 0), (0.05, 0.5), (0.4, 0.0)])
    x = place(D, [(0.0, hiss, 0.55), (0.05, _norm(chirp), 0.7), (0.26, _norm(rattle), 0.8), (0.26, _norm(growl), 0.18)])
    return _finish(_limit(x, 0.7), D, fade_out=0.1)


@sound("world_dino_roar_giga", loudness=-14, wet=0.2, rt60=0.7, marks=(0.0, 0.07, 0.62),
       note="the giant's roar: a huge deep call, f0 85 -> 125 -> 44 Hz (a bellow cracking open at 0.08, the mouth wide to 0.7 and "
            "closing), a 38 -> 24 Hz growl tearing at it, formants at 250, 700 and 1.4 kHz, a sub of the chest under it and "
            "a rumble of brown noise; the call sinks away to 1.9")
def world_dino_roar_giga(seed):
    D = 1.5
    k = D / 1.7
    roar = _roar(D, seed,
                 f0_pts=_sc([(0, 85), (0.08, 125), (0.4, 108), (0.85, 80), (1.3, 56), (1.7, 44)], k),
                 form_a=[(250, 3, 1.0), (700, 3, 0.85), (1400, 3, 0.4), (2600, 2, 0.2)],
                 form_b=[(180, 3, 1.0), (470, 3, 0.7), (1000, 2.5, 0.3)],
                 mouth_pts=_sc([(0, 1), (0.1, 0.0), (0.7, 0.1), (1.15, 0.7), (1.7, 1.0)], k),
                 gain_pts=_sc([(0, 0), (0.02, 1.0), (0.45, 0.95), (1.0, 0.75), (1.4, 0.35), (1.7, 0.0)], k),
                 am=(38, 24), am_depth=0.55, breath=0.3, tilt=0.95, jitter=0.02, grit=0.6, hp=40)
    f_sub = _curve(D, _sc([(0, 45), (0.08, 62), (0.85, 42), (1.7, 30)], k), log=True)
    sub = np.sin(2 * np.pi * np.cumsum(f_sub) / SR) * env_points(D, _sc([(0, 0), (0.05, 1), (1.1, 0.7), (1.7, 0)], k))
    rumble = _norm(lowpass(brown(D, seed + 1), 160, 2)) * env_points(D, _sc([(0, 0), (0.08, 1.0), (0.9, 0.6), (1.7, 0.0)], k))
    air = _norm(_moving_band(pink(D, seed + 2), _path(_sc([(0, 2500), (0.4, 1500), (1.7, 400)], k)), 0.6)) * env_points(
        D, _sc([(0, 0), (0.04, 0.8), (0.8, 0.5), (1.7, 0.0)], k))
    x = place(D, [(0.0, roar, 0.9), (0.0, _norm(sub), 0.35), (0.0, rumble, 0.35), (0.0, air, 0.12)])
    x = _squash(x, threshold=0.28, ratio=2.5, window=0.02)
    return _finish(_limit(x, 0.7), D, fade_out=0.22)


@sound("world_dino_step_small", loudness=-26, wet=0.05, rt60=0.3, marks=(0.0, 0.065, 0.1, 0.165),
       note="a small dinosaur trots: six light claw taps in two runs of three (0.0, 0.035, 0.065 and 0.1, 0.13, 0.165), each a "
            "dry tick of claw on stone (2.5-5 kHz, 6 ms) over a tiny paper-light pad; quiet and fast, it must not tire")
def world_dino_step_small(seed):
    D = 0.2
    r = rng(seed)
    x = silence(D)
    for k, (t0, g) in enumerate(((0.0, 0.8), (0.035, 1.0), (0.065, 0.7), (0.1, 0.8), (0.13, 1.0), (0.165, 0.65))):
        tap = _norm(_modes(0.02, [(r.uniform(2400, 3200), 0.003, 1.0), (r.uniform(4000, 5200), 0.002, 0.6)]))
        tick = pad_to(_click(seed + 10 + k, length=0.004, tau=0.0004, hp=2000), 0.02)
        pad = pad_to(_norm(_thud(0.03, seed + 20 + k, f0=r.uniform(260, 340), t60=0.012, lp=1500, drop=0.3)), 0.02)
        _put(x, t0, 0.7 * tap + 0.6 * tick + 0.35 * pad, g)
    return _finish(_limit(x, 0.7), D, fade_out=0.02)


@sound("world_dino_step_heavy", loudness=-19, wet=0.25, rt60=0.8, marks=(0.0,),
       note="a heavy stomp at 0.0: a deep thud (58 Hz falling), a stone chunk, a drag of claws settling on the stone (0.02-0.1) "
            "and a puff of dust; over by 0.5")
def world_dino_step_heavy(seed):
    D = 0.5
    x = place(D, [
        (0.0, _norm(_thud(0.35, seed, f0=58.0, t60=0.22, lp=330, drop=0.9)), 1.0),
        (0.0, _stone_chunk(seed + 1, base=240.0, t60=0.06, length=0.25, low=0.5), 0.55),
        (0.0, _click(seed + 2, hp=700, tau=0.0008), 0.3),
        (0.02, _scrape(0.09, seed + 3, hi=3500, lo=1200), 0.25),
        (0.0, _pressure_thump(0.09, f0=60.0), 0.25),
        (0.01, _puff(seed + 4, length=0.3, center=650.0), 0.3),
    ])
    return _finish(_limit(x, 0.7), D, fade_out=0.08)


@sound("world_dino_stomp", loudness=-20, wet=0.1, rt60=0.25, marks=(0.0, 0.05, 0.2),
       note="the giant's crushing stomp at 0.0: a pressure thump, a deep boom (84 -> 36 Hz), the stone shattering under the foot "
            "(ticks and chunks 0.0-0.3), a rumble of the ground shaking to 0.4, grit and pebbles falling to 0.5")
def world_dino_stomp(seed):
    D = 0.55
    r = rng(seed)
    boom = _blast(0.45, seed, f_start=84.0, f_end=36.0, t60=0.32, sub=1.0, body=1.0, roar=0.45, front=0.3, boom_len=0.4,
                  rumble_hp=32.0, roar_center=240.0, punch=1.0, sustain=0.2)
    boom = _squash(boom, threshold=0.22, ratio=3.0, window=0.02)
    st = 0.004 + np.sort(r.exponential(0.05, 50))
    shatter = _stone_ticks(D, st[st < 0.3], seed + 1, lo=600, hi=5500, lmin=0.002, lmax=0.012, power=1.4)
    chunks = place(D, [(0.004 + dt, _stone_chunk(seed + 2 + i, base=b), g) for i, (dt, b, g) in
                       enumerate([(0.0, 300, 1.0), (0.03, 450, 0.7), (0.07, 380, 0.5), (0.13, 620, 0.4)])])
    grit = _stone_ticks(D, random_times(D, 80, seed + 10, 0.15, 0.5, envelope=lambda u: (1 - u) ** 1.6), seed + 11, lo=1400, hi=7500,
                        lmin=0.0015, lmax=0.006, power=1.8)
    shake = _norm(lowpass(brown(D, seed + 12), 120, 2)) * env_points(D, [(0, 0), (0.03, 1.0), (0.35, 0.4), (D, 0.0)])
    x = place(D, [(0.0, boom, 1.0), (0.0, _pressure_thump(0.09, f0=55.0), 0.3), (0.0, _norm(shatter), 0.22), (0.0, _norm(chunks), 0.3),
                  (0.0, _norm(grit), 0.16), (0.0, shake, 0.4), (0.02, _puff(seed + 13, length=0.4, center=550.0), 0.3)])
    return _finish(_limit(x, 0.7), D, fade_out=0.1)


@sound("world_dino_bite", loudness=-17, wet=0.2, rt60=0.6, marks=(0.0, 0.03, 0.09),
       note="the bite: the jaws slam shut at 0.0 (a hard bone-on-bone clack and a wet smack), the bones crunching 0.03-0.2 (a "
            "dense grain of 800-4000 Hz fragments thinning out), a low chomp of the jaw muscle at 0.09 and a short growl "
            "in the throat; over by 0.5")
def world_dino_bite(seed):
    D = 0.4
    r = rng(seed)
    clack = _norm(_modes(0.05, [(r.uniform(900, 1300), 0.012, 1.0), (r.uniform(1900, 2500), 0.008, 0.7), (r.uniform(3400, 4200), 0.005, 0.5)]))
    clack = clack + 0.5 * pad_to(_click(seed + 1, length=0.006, tau=0.0007, hp=1200), 0.05)
    smack = _norm(bandpass(white(0.04, seed + 2), 1300, 0.8)) * np.exp(-time_axis(0.04) / 0.006)
    ct = random_times(0.2, 190, seed + 3, 0.0, 0.2, envelope=lambda u: (1 - u) ** 1.2)
    crunch = _stone_ticks(0.2, ct, seed + 4, lo=800, hi=4000, lmin=0.002, lmax=0.009, power=1.3)
    wet = _norm(_moving_band(pink(0.12, seed + 5), _path([(0, 1500), (0.12, 500)]), 0.8)) * env_points(0.12, [(0, 1.0), (0.12, 0.0)])
    chomp = _norm(_thud(0.18, seed + 6, f0=100.0, t60=0.08, lp=500, drop=0.6))
    growl = _roar(0.28, seed + 7, f0_pts=[(0, 100), (0.1, 125), (0.28, 80)], form_a=[(420, 3, 1.0), (900, 3, 0.5)],
                  form_b=[(300, 3, 1.0), (700, 3, 0.4)], mouth_pts=[(0, 0.5), (0.28, 1.0)],
                  gain_pts=[(0, 0), (0.04, 1.0), (0.28, 0.0)], am=(34, 28), am_depth=0.5, breath=0.25, grit=0.5, hp=60)
    x = place(D, [(0.0, _norm(clack), 0.75), (0.0, smack, 0.35), (0.03, _norm(crunch), 0.55), (0.03, wet, 0.25),
                  (0.0, chomp, 0.5), (0.09, _thud(0.12, seed + 8, f0=140.0, t60=0.05, lp=600, drop=0.4), 0.3), (0.12, _norm(growl), 0.3)])
    x = _squash(x, threshold=0.3, ratio=2.2, window=0.005, smooth=0.003)
    return _finish(_limit(x, 0.7), D, fade_out=0.1)


@sound("world_dino_dismount", loudness=-20, wet=0.3, rt60=0.8, marks=(0.0, 0.05, 0.15),
       note="the dinosaur leaves the rider: a puff of smoke and paper at 0.0 (dark air and a few crinkles), a soft low thump of its "
            "going, and its call fading away at 0.05-0.65 (a bellow falling 190 -> 90 Hz, darkening as it goes: the "
            "formants and a lowpass sinking 3 kHz -> 450 Hz, thinning to nothing)")
def world_dino_dismount(seed):
    D = 0.65
    call = _roar(0.6, seed,
                 f0_pts=[(0, 190), (0.1, 215), (0.6, 90)],
                 form_a=[(520, 3, 1.0), (1100, 3, 0.7), (2500, 2, 0.3)],
                 form_b=[(380, 3, 1.0), (800, 3, 0.5), (1800, 2, 0.2)],
                 mouth_pts=[(0, 0.8), (0.08, 0.0), (0.35, 0.2), (0.6, 1.0)],
                 gain_pts=[(0, 0), (0.03, 1.0), (0.2, 0.6), (0.6, 0.0)],
                 am=(26, 20), am_depth=0.4, breath=0.2, grit=0.3, hp=60)
    call = _moving_lowpass(call, _path([(0, 3000), (0.2, 1400), (0.6, 450)]), order=2) * env_points(0.6, [(0, 1.0), (0.2, 0.6), (0.6, 0.0)])
    puff = _puff(seed + 1, length=0.3, center=900.0)
    paper = _norm(_paper(0.15, [0.0, 0.015, 0.035, 0.06, 0.09], seed + 2, lo=1500, hi=6000, lmin=0.008, lmax=0.025))
    thump = _norm(_thud(0.2, seed + 3, f0=70.0, t60=0.1, lp=300, drop=0.5))
    x = place(D, [(0.0, puff, 0.9), (0.0, paper, 0.25), (0.02, thump, 0.5), (0.05, _norm(call), 0.8)])
    return _finish(_limit(x, 0.7), D, fade_out=0.1)


# ==========================================================================
# The bleed

def _drip(freq, length, drop=0.45):
    """A drop of blood: a short plip, a sine falling a little then closing."""
    t = time_axis(length)
    f = freq * (1 - drop * (1 - np.exp(-t / (length * 0.25))))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.minimum(1, t / 0.0008) * np.exp(-t / (length * 0.3))


def _slice(length, seed, lo=2500.0, hi=7500.0):
    """A thin wet slice: a bright band sliding down, a hard edge on the start."""
    s = _norm(_moving_band(white(length, seed), _path([(0, hi), (length, lo)]), 1.0))
    return s * np.minimum(1, time_axis(length) / 0.0008) * env_points(length, [(0, 1.0), (length * 0.4, 0.7), (length, 0.0)])


@sound("ui_status_bleed", loudness=-22, wet=0.15, rt60=0.5, marks=(0.0, 0.04, 0.18),
       note="Sanguinamento applied: a thin wet slice at 0.0 (a band sliding 7.5 -> 2.5 kHz in 0.06 s, a bright tick on it), a "
            "drop of blood plipping at 0.04 (800 Hz falling) and a smaller one at 0.18 with a wet cling after, over by 0.4")
def ui_status_bleed(seed):
    D = 0.3
    cling = _norm(_moving_band(pink(0.1, seed + 3), _path([(0, 1800), (0.1, 700)]), 1.0)) * env_points(0.1, [(0, 0), (0.01, 1.0), (0.1, 0.0)])
    x = place(D, [
        (0.0, _slice(0.07, seed), 0.8),
        (0.0, pad_to(_click(seed + 1, length=0.004, tau=0.0004, hp=3000), 0.07), 0.5),
        (0.04, _norm(_drip(800.0, 0.1, 0.5)), 0.75),
        (0.042, _norm(_blub(420.0, 0.08, 0.3)), 0.25),
        (0.18, _norm(_drip(1050.0, 0.07, 0.4)), 0.45),
        (0.195, cling, 0.2),
    ])
    return _finish(_limit(x, 0.7), D, fade_out=0.06)


@sound("world_bleed_tick", loudness=-21, wet=0.15, rt60=0.5, marks=(0.0, 0.02),
       note="the bleed's extra damage: a sharper wet slash at 0.0 (a hard bright cut 2.5-9 kHz sliding down in 0.04 s, a "
            "burst of edge), a wet squelch of the wound under it at 0.02 (a band 1.6 kHz -> 500 Hz) and two drops falling; "
            "over by 0.3")
def world_bleed_tick(seed):
    D = 0.2
    cut = _norm(_moving_band(white(0.05, seed), _path([(0, 9000), (0.05, 2500)]), 0.7)) * env_points(0.05, [(0, 1.0), (0.015, 0.8), (0.05, 0.0)])
    edge = _norm(highpass(white(0.012, seed + 1), 2500, 2)) * np.exp(-time_axis(0.012) / 0.002)
    squelch = _norm(_moving_band(pink(0.1, seed + 2), _path([(0, 1600), (0.1, 500)]), 1.0)) * env_points(0.1, [(0, 0), (0.008, 1.0), (0.1, 0.0)])
    body = _norm(_thud(0.1, seed + 3, f0=150.0, t60=0.04, lp=700, drop=0.5))
    x = place(D, [
        (0.0, cut, 0.85), (0.0, pad_to(edge, 0.05), 0.55), (0.0, body, 0.35), (0.02, squelch, 0.5),
        (0.05, _norm(_drip(900.0, 0.06, 0.5)), 0.4), (0.09, _norm(_drip(700.0, 0.05, 0.4)), 0.25),
    ])
    return _finish(_limit(x, 0.7), D, fade_out=0.05)
