"""Family `bomber` - the bomber (see SOUND_SPEC.md).

Red-hooded, a sling of iron bombs, a smoking fuse. Hops; clinks; sizzles.

The character's shared timbre, used by every sound of the family:
- the bombs: cast-iron shells packed with powder, so a knock is a hard
  iron-on-iron tick and the dull knock of the filled mass, over a short,
  damped inharmonic ring (one mode set, _BOMB_RATIOS on A6 = 1760 Hz, the
  high modes dying first). In the leather sling they are well damped (a
  clank, not a chime); loose on stone they ring a little freer and lower,
  never as a sustained bell;
- the fuse: a black-powder sizzle (bursts of sharp spits that the hiss and
  the mid "fff" jet of the burning powder follow, powder-grain pops);
- light boots on stone (a short, dense contact, no drum-like body) and a
  thin red hood (cloth flutter);
- the paper standee on its small iron base (paper grains, base ticks, the
  gritty skid of the base on stone).
Recipes are dry: the build adds the stone hall. Every recipe goes through a
causal DC blocker (_finish), so the build's zero-phase DC removal has
nothing to smear ahead of the hits.
"""
import math

import numpy as np

from dsp import *  # noqa: F401,F403
from dsp import (SR, bandpass, brown, convolve, crackle, env_perc, fade, formant,
                 glide, grains, highpass, lowpass, n_samples, pad_to, peak_eq, pink,
                 place, random_times, rng, sine, stft_filter, time_axis, white)
from registry import sound


# --------------------------------------------------------------------------
# Small tools

def _pk(x, target=1.0):
    """Scales to a peak of `target` (silent input stays silent)."""
    p = float(np.max(np.abs(x))) if len(x) else 0.0
    return x * (target / p) if p > 1e-12 else x


def _ring(duration, modes, attack=0.0003):
    """Damped sinusoids [(freq, tau_s, amp)] starting from zero (no step)."""
    t = time_axis(duration)
    x = np.zeros_like(t)
    for f, tau, a in modes:
        if f < SR * 0.45:
            x += a * np.sin(2 * np.pi * f * t) * np.exp(-t / max(tau, 1e-4))
    if attack > 0:
        x *= np.minimum(1.0, t / attack)
    return x


def _seg(duration, t0, tp, t1, up=2.0, down=1.5):
    """Envelope: 0 before t0, rises to 1 at tp, falls back to 0 at t1."""
    t = time_axis(duration)
    e = np.zeros_like(t)
    a = (t >= t0) & (t < tp)
    e[a] = ((t[a] - t0) / max(tp - t0, 1e-6)) ** up
    b = (t >= tp) & (t < t1)
    e[b] = (1 - (t[b] - tp) / max(t1 - tp, 1e-6)) ** down
    return e


def _interp_log(t, points):
    ts = [p[0] for p in points]
    cs = [math.log(p[1]) for p in points]
    return math.exp(float(np.interp(t, ts, cs)))


def _band_path(x, points, q=1.5):
    """Band-pass whose centre follows [(t_s, hz)] (log interpolation)."""
    sig = (1.0 / max(q, 0.05)) / 2.355

    def gain(f, t):
        c = _interp_log(t, points)
        return np.exp(-0.5 * (np.log2(np.maximum(f, 1e-3) / c) / sig) ** 2)
    return stft_filter(x, gain)


def _hp_lp_path(x, hp_points, lp_points, order=2):
    """High-pass and low-pass corners that both move over time."""
    def gain(f, t):
        lo = _interp_log(t, hp_points)
        hi = _interp_log(t, lp_points)
        g_hp = 1 / np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
        g_lp = 1 / np.sqrt(1 + (f / hi) ** (2 * order))
        return g_hp * g_lp
    return stft_filter(x, gain)


def _smooth_noise(n, cutoff, seed):
    """Unit-std random control signal, band-limited to `cutoff` Hz."""
    v = lowpass(rng(seed).standard_normal(n), cutoff, 1)
    return v / (np.std(v) + 1e-12)


def _lowband(duration, seed, lo, hi, color="pink"):
    """Pink (or brown) noise kept between lo and hi: bodies and rumbles
    without the infrasonic weight of raw 1/f noise."""
    x = pink(duration, seed) if color == "pink" else brown(duration, seed)
    return highpass(lowpass(x, hi, 2), lo, 2)


def _dc_block(x, fc=35.0):
    """Causal DC blocker: x minus its causal exponential average (a one-pole
    high-pass). It takes out the net DC area that damped sine bodies leave,
    and being causal it puts nothing ahead of an onset."""
    a = 2 * np.pi * fc / SR
    k = a * np.exp(-a * np.arange(int(8 / a)))
    return x - convolve(x, k)[:len(x)]


def _burst_hit(duration, modes, seed, burst=0.004, cutoff=1500.0):
    """Modes struck by a short low-passed noise burst (not a bare sine
    onset): a dense, slightly irregular contact rather than a tuned note."""
    exc = lowpass(white(burst, seed), cutoff, 2) * np.hanning(n_samples(burst))
    return pad_to(convolve(exc, _ring(0.1, modes, 0)), duration)


# --------------------------------------------------------------------------
# The bombs: powder-filled cast-iron shells

_BOMB_BASE = 1760.0   # A6, the fifth of D: the family's one recurring pitch
_BOMB_RATIOS = (1.0, 1.43, 1.97, 2.58, 3.31, 4.07, 4.96)


def _bomb_modes(seed, base=_BOMB_BASE, damp=1.0, bright=1.0):
    """The shell's inharmonic modes; `damp` scales the ring (about 0.4 in the
    leather sling, 0.7 loose on stone: powder-filled iron never rings long),
    `bright` < 1 softens the high modes."""
    r = rng(seed)
    b = base * r.uniform(0.96, 1.04)
    modes = []
    for i, ratio in enumerate(_BOMB_RATIOS):
        f = b * ratio * (1 + r.uniform(-0.012, 0.012))
        tau = 0.09 * damp / (1 + 0.6 * i)
        amp = r.uniform(0.7, 1.0) * bright ** i / (1 + 0.45 * i)
        modes.append((f, tau, amp))
    return modes


def _clink(seed, hard=1.0, damp=1.0, base=_BOMB_BASE, duration=0.45):
    """Two bombs knock: an iron tick, the dull knock of the powder-filled
    mass, both shells ring briefly (damp ~0.4 in the sling: a clank, not a
    chime; ~0.7 for loose bombs on stone)."""
    t = time_axis(duration)
    r = rng(seed)
    bright = 0.6 + 0.3 * min(hard, 1.3)
    a = _ring(duration, _bomb_modes(seed, base, damp, bright))
    b = _ring(duration, _bomb_modes(seed + 1, base * r.uniform(1.07, 1.16), damp, bright))
    shells = _pk(a + r.uniform(0.45, 0.8) * b)
    tick = _pk(highpass(white(duration, seed + 2) * np.exp(-t / 0.00022), 3000, 2))
    knock = _pk(_ring(duration, [(r.uniform(430, 520), 0.011, 1.0),
                                 (r.uniform(800, 920), 0.007, 0.5)], 0.0002))
    return 0.5 * shells + 0.24 * hard * tick + (0.35 + 0.15 * hard) * knock


def _jostle(duration, seed, t0, count=3, gap=(0.022, 0.05), fall=0.55,
            hard=0.9, damp=0.4, base=_BOMB_BASE):
    """The sling's bombs knock together a few times after a jolt."""
    r = rng(seed)
    events, t, g = [], t0, 1.0
    for k in range(count):
        events.append((t, _clink(int(r.integers(1 << 30)), hard * (0.6 + 0.4 * g), damp, base), g))
        t += r.uniform(*gap) * (1 + 0.3 * k)
        g *= fall * r.uniform(0.8, 1.15)
    return place(duration, events)


def _bomb_drop(seed, hard=1.0, duration=0.7, damp=0.7):
    """A loose bomb hits stone: a dense stone contact and a short heavy
    thock (no wood-block tok), the shell rings a little freer (lower,
    longer) than in the sling, without a lingering bell line."""
    t = time_axis(duration)
    r = rng(seed)
    shell = _pk(_ring(duration, _bomb_modes(seed, _BOMB_BASE * 0.93, damp=damp, bright=0.85)))
    stone = _pk(lowpass(white(duration, seed + 1), 2600, 2) * np.exp(-t / 0.006))
    thock = _pk(_ring(duration, [(r.uniform(250, 300), 0.009, 1.0),
                                 (r.uniform(600, 690), 0.006, 0.55)], 0.0005))
    tick = _pk(highpass(white(duration, seed + 2) * np.exp(-t / 0.0003), 2500, 2))
    return 0.5 * shell + 0.55 * stone + 0.5 * thock + 0.25 * hard * tick


def _roll(duration, seed, t0, t1, turns=16.0, base=_BOMB_BASE):
    """A bomb rolls across stone, slowing down: micro-impacts on the stone
    grain rattle through the shell's damped modes, a low rumble, and the
    fuse stub knocks once a turn (the turns slowing)."""
    n = n_samples(duration)
    t = time_axis(duration)
    r = rng(seed)
    u = np.clip((t - t0) / (t1 - t0), 0, 1)
    speed = np.where(t >= t0, (1 - u) ** 1.2, 0.0)
    exc = crackle(duration, 3000 * speed, seed + 1, decay=0.00015) * speed
    shell_ir = _ring(0.12, _bomb_modes(seed + 2, base, damp=0.12, bright=1.0))
    shell = convolve(exc, shell_ir)[:n]
    ph = np.cumsum(turns * speed) / SR
    grit = _band_path(white(duration, seed + 4) * (0.4 + 0.6 * _pk(np.abs(exc))), [(t0, 3200), (t1, 1500)], q=0.9)
    rumble = _lowband(duration, seed + 3, 90, 420)
    rumble *= speed * (0.65 + 0.35 * np.sin(2 * np.pi * ph))
    edges = np.nonzero(np.diff(np.floor(ph + r.uniform(0.2, 0.8))) > 0)[0]
    knocks = []
    for i in edges:
        g = float(speed[i])
        if g > 0.05:
            knocks.append((i / SR, _bomb_drop(int(r.integers(1 << 30)), hard=0.4 * g, duration=0.3, damp=0.6), g))
    kn = place(duration, knocks)
    return 0.28 * _pk(shell) + 0.26 * _pk(grit * speed) + 0.26 * _pk(rumble) + 0.5 * kn


# --------------------------------------------------------------------------
# The fuse

def _spit_bursts(duration, seed, burst_hz=6.0):
    """The fuse's sputter: a slow random control (0..2.5) that bunches the
    spits in bursts and, in a sputtering fuse, gates the hiss and the jet."""
    return np.clip(0.5 + 0.8 * _smooth_noise(n_samples(duration), burst_hz, seed + 8), 0.0, 2.5)


def _spits(duration, seed, rate, burst=None, top=9500.0):
    """Sharp fuse spits: sparse bright impulses, bunched in bursts."""
    if burst is None:
        burst = _spit_bursts(duration, seed)
    sp = crackle(duration, np.asarray(rate) * burst, seed + 2, decay=0.00035)
    return _pk(lowpass(highpass(sp, 2200, 2), top, 2))


def _sizzle(duration, seed, spit=60.0, pops=8.0, bright=1.0, sputter=False, hiss_gain=0.14):
    """A burning black-powder fuse. `spit` (spits/s) may be a per-sample
    array; `pops` is the rate of the bigger powder-grain pops.
    sputter=True is the fuse heard up close (PREPARA): darker, spit-led (the
    spits never stop, they thin to half rate between bursts), the hiss and
    the jet low and gated by the bursts, so it spits and sputters instead of
    hissing like steam. sputter=False is the steadier, brighter hiss the
    throw's distance filter is built on."""
    n = n_samples(duration)
    flicker = np.clip(0.75 + 0.3 * _smooth_noise(n, 14, seed), 0.25, 1.45)
    rough = np.clip(0.7 + 0.35 * _smooth_noise(n, 220, seed + 9), 0.1, 1.6)
    burst = _spit_bursts(duration, seed)
    hiss = highpass(white(duration, seed + 1), 1800 * bright, 2)
    if sputter:
        hiss = peak_eq(lowpass(hiss, 6500 * bright, 3), 3500 * bright, 4, 1.0)
    else:
        hiss = peak_eq(lowpass(hiss, 8000 * bright, 2), 4300 * bright, 4, 1.0)
    hiss = hiss / (np.std(hiss) + 1e-12) * flicker * rough
    if sputter:
        sp = _spits(duration, seed, spit, 0.5 + burst, top=7000.0)
    else:
        sp = _spits(duration, seed, spit, burst)
    times = random_times(duration, pops, seed + 3) if pops > 0 else []
    if sputter:
        pp = grains(duration, times, 0.004, seed + 4, band=(1500, 5000), gain_jitter=0.7) if times else np.zeros(n)
    else:
        pp = grains(duration, times, 0.005, seed + 4, band=(1200, 4000), gain_jitter=0.7) if times else np.zeros(n)
    pp = _pk(pp)
    jet = highpass(bandpass(pink(duration, seed + 5), 1600, 0.7), 700, 2)
    jet = jet / (np.std(jet) + 1e-12) * flicker * rough
    if sputter:
        gate = 0.3 + 0.7 * np.clip(burst / 1.3, 0.0, 1.2)
        return hiss_gain * hiss * gate + 1.0 * sp + 0.4 * pp + 0.06 * jet * gate
    return hiss_gain * hiss + 0.8 * sp + 0.45 * pp + 0.08 * jet


def _flint(seed, duration=0.3):
    """Steel struck down a flint: a hard bite, a 40 ms bright scratch whose
    band falls, the steel striker's faint ring."""
    t = time_axis(duration)
    r = rng(seed)
    bite = _pk(lowpass(highpass(white(duration, seed) * np.exp(-t / 0.0003), 2200, 2), 11000, 2))
    sl = 0.042
    grit = crackle(sl, 7000, seed + 1, decay=0.00012)
    scr = 0.5 * white(sl, seed + 2) + 0.9 * _pk(grit)
    scr = _band_path(scr, [(0.0, 7000), (sl, 3200)], q=1.0)
    scr *= _seg(sl, 0.0, 0.002, sl, 1.0, 1.4)
    scr = _pk(np.concatenate([scr, np.zeros(n_samples(duration) - len(scr))])[:n_samples(duration)])
    ring = _pk(_ring(duration, [(r.uniform(3050, 3250), 0.05, 1.0), (r.uniform(4500, 4750), 0.04, 0.7),
                                (r.uniform(6250, 6500), 0.03, 0.5), (r.uniform(8700, 9050), 0.02, 0.35)]))
    return 0.5 * bite + 0.8 * scr + 0.18 * ring


# --------------------------------------------------------------------------
# Body, boots, cloth, breath, paper

def _boot(seed, weight=1.0, grit=1.0, duration=0.3):
    """A light boot on stone: sub-5 ms contact, a short heel-and-sole body
    struck by a noise burst (dense, no drum note), a leather sole slap and a
    few grains of grit (2-6 kHz)."""
    t = time_axis(duration)
    r = rng(seed)
    f0 = r.uniform(150, 190)
    modes = [(f0, 0.009, 1.0), (f0 * 1.87, 0.007, 0.55), (f0 * 3.05, 0.005, 0.3)]
    body = _pk(_burst_hit(duration, modes, seed + 5))
    thud = _pk(_lowband(duration, seed + 1, 75, 380) * env_perc(duration, 0.0012, 0.07))
    click = _pk(lowpass(highpass(white(duration, seed + 2) * np.exp(-t / 0.0005), 900, 2), 8000, 1))
    sole = _pk(bandpass(white(duration, seed + 3), 1400, 1.0) * env_perc(duration, 0.001, 0.035))
    times = sorted(r.uniform(0.0, 0.035, 7))
    gr = _pk(grains(duration, times, 0.007, seed + 4, band=(2000, 6000)))
    return weight * (0.35 * body + 0.7 * thud + 0.3 * click + 0.16 * sole + 0.16 * grit * gr)


def _scuff(seed, duration=0.06):
    """The boot pushes off: sole-on-stone friction (no modal body, no
    impact), with a few grains of grit."""
    r = rng(seed)
    sc = _pk(bandpass(pink(0.05, seed + 1), 900, 0.7)) * _seg(0.05, 0.0, 0.006, 0.05, 1.5, 1.5)
    times = sorted(r.uniform(0.0, 0.035, 7))
    gr = _pk(grains(duration, times, 0.007, seed + 4, band=(2000, 6000)))
    return pad_to(sc, duration) + 0.23 * gr


def _blow(seed, weight=1.0, duration=0.4, f0=None):
    """A blow on the body: a muffled low thump (80-250 Hz) whose pitch drops
    as it lands and dies fast, led by the noise of the body's mass, a short
    broadband slap of the leather jerkin, a cloth puff. No ringing."""
    t = time_axis(duration)
    n = len(t)
    r = rng(seed)
    f0 = r.uniform(88, 98) if f0 is None else f0 * r.uniform(0.96, 1.04)
    path = np.concatenate([glide(f0 * 1.35, f0, 0.03), np.full(n - n_samples(0.03), f0)])
    # The flesh gives: the low layers swell over 8 ms while the slap takes
    # the edge on the mark. Together with the causal high-pass below, this
    # leaves the build's zero-phase DC filter nothing to smear before the hit.
    rise = np.where(t < 0.008, 0.5 - 0.5 * np.cos(np.pi * np.minimum(t / 0.008, 1.0)), 1.0)
    thump = np.zeros(n)
    for ratio, tau, amp in ((1.0, 0.016, 1.0), (1.75, 0.011, 0.65), (2.9, 0.007, 0.35)):
        thump += amp * sine(path * ratio, n=n) * np.exp(-t / tau)
    thump = _pk(thump * rise)
    mass = _pk(_lowband(duration, seed + 1, 55, 260) * np.exp(-6.8 * t / 0.1) * rise)
    low = _dc_block(_dc_block(0.35 * thump + 0.9 * mass, 50.0), 50.0)
    slap = lowpass(highpass(white(duration, seed + 2), 500, 1), 6500, 2) * np.exp(-t / 0.005)
    slap = _pk(slap * np.minimum(1, t / 0.0005))
    cloth = _pk(bandpass(_lowband(duration, seed + 3, 200, 4000), 900, 0.8) * env_perc(duration, 0.004, 0.08))
    return weight * low + 0.32 * slap + 0.26 * cloth


def _flutter(duration, seed, t0, tp, t1, f_lo=520.0, f_hi=1500.0, rate=17.0):
    """The thin hood and sling fabric flapping through the air."""
    t = time_axis(duration)
    r = rng(seed)
    x = _band_path(pink(duration, seed), [(t0, f_lo), (tp, f_hi), (t1, f_lo * 0.9)], q=1.0)
    flap = 0.55 + 0.45 * np.abs(np.sin(np.pi * rate * t + r.uniform(0, 3)))
    return _pk(x * flap * _seg(duration, t0, tp, t1, 1.6, 1.4))


def _hiss(duration, seed, t0, t1, peak=0.25, tremble=0.35):
    """A nervous breath hissed through the teeth (formant noise, no voice):
    smooth, 2-7 kHz, a little trembling - unlike the crackling fuse."""
    t = time_axis(duration)
    r = rng(seed)
    x = formant(white(duration, seed), [(2300, 2.5, 0.45), (3900, 2.2, 1.0), (6200, 1.8, 0.5)])
    x = lowpass(highpass(x, 1200, 2), 9000, 2)
    tr = 1 - tremble * (0.5 + 0.5 * np.sin(2 * np.pi * r.uniform(9, 12) * t))
    return _pk(x * tr * _seg(duration, t0, t0 + peak * (t1 - t0), t1, 1.4, 2.0))


def _paper(duration, seed, times, lengths=(0.006, 0.012, 0.024), band=(1500, 8000)):
    """Paper grains (5-30 ms bursts of band-passed noise) at `times`."""
    r = rng(seed)
    out = np.zeros(n_samples(duration))
    buckets = [[] for _ in lengths]
    for tt in times:
        buckets[int(r.integers(len(lengths)))].append(tt)
    for i, (length, b) in enumerate(zip(lengths, buckets)):
        if b:
            out += grains(duration, b, length, seed + 1 + i, band=band)
    return out


def _base_tick(seed, duration=0.1):
    """The standee's small iron base set down on stone: a dry tick."""
    t = time_axis(duration)
    r = rng(seed)
    ring = _pk(_ring(duration, [(r.uniform(2300, 2600), 0.011, 1.0), (r.uniform(3550, 3900), 0.008, 0.7),
                                (r.uniform(5300, 5900), 0.005, 0.45)], 0.0002))
    click = _pk(lowpass(highpass(white(duration, seed + 1) * np.exp(-t / 0.0004), 1500, 2), 10000, 2))
    stone = _pk(lowpass(white(duration, seed + 2), 1600, 2) * np.exp(-t / 0.005))
    return 0.45 * ring + 0.35 * click + 0.4 * stone


def _skid(duration, seed, f_start=4200.0, f_end=1600.0, density=3000.0):
    """The iron base skids on stone: dense grit through a falling band,
    with a stick-slip roughness."""
    n = n_samples(duration)
    grit = _pk(crackle(duration, density, seed, decay=0.00025))
    hiss = white(duration, seed + 1)
    stick = np.clip(0.6 + 0.5 * _smooth_noise(n, 90, seed + 2), 0.1, 1.5)
    x = (0.7 * grit + 0.35 * hiss) * stick
    x = _band_path(x, [(0.0, f_start), (duration, f_end)], q=1.3)
    return _pk(x * _seg(duration, 0.0, 0.003, duration, 1.0, 1.2))


def _tame(x, crest_db):
    """Soft-limits only the first milliseconds of a transient so the peak
    sits at most `crest_db` above the loudness: the build can then reach
    its loudness target without squashing the sound in its own limiter."""
    from dsp import loudness_db
    knee = 0.7
    for _ in range(6):
        ceiling = 10 ** ((loudness_db(x) + crest_db) / 20)
        if np.max(np.abs(x)) <= ceiling * 1.01:
            break
        a = np.abs(x)
        k = knee * ceiling
        over = a > k
        y = a.copy()
        y[over] = k + (ceiling - k) * np.tanh((a[over] - k) / (ceiling - k))
        x = np.sign(x) * y
    return x


def _finish(x, crest_db=None, target=0.85):
    x = _dc_block(_dc_block(x))
    if crest_db is not None:
        x = _tame(x, crest_db)
    return fade(_pk(x, target), 0.001, 0.02)


# --------------------------------------------------------------------------
# The sounds

@sound("bomber_move", loudness=-21, wet=0.18, marks=(0.12, 0.27, 0.44, 0.48))
def bomber_move(seed):
    """Two hops (0.12 push-off scuff, landings at 0.27 and 0.44), the bombs
    knock twice on each landing, the card hops 0.12-0.48 and settles on its
    base at 0.48 (a low card-on-stone contact, a paper flap, the base tick)
    in a gap the clinks leave clear. No fuse: it is lit only in PREPARA."""
    D = 0.85
    s = seed
    feet = place(D, [
        (0.12, _scuff(s + 10), 0.25),                       # push-off scuff
        (0.27, _boot(s + 20, 0.85), 1.0),                   # first landing
        (0.44, _boot(s + 30, 1.0), 1.0),                    # second landing
    ])
    tt = time_axis(0.05)
    contact = _pk(lowpass(white(0.05, s + 95), 1800, 2) * np.exp(-tt / 0.004))
    flap = _pk(bandpass(white(0.05, s + 96), 2600, 0.6) * np.exp(-tt / 0.008))
    card = place(D, [
        (0.12, _skid(0.03, s + 40, 3600, 2600), 0.22),      # base unsticks
        (0.271, _base_tick(s + 50), 0.4),
        (0.273, _skid(0.045, s + 60, 3800, 1800), 0.3),
        (0.441, _base_tick(s + 70), 0.45),
        (0.443, _skid(0.025, s + 80, 3600, 1700), 0.2),
        (0.48, contact, 0.6),                               # the card settles
        (0.48, flap, 0.3),
        (0.48, _base_tick(s + 90), 1.4),
        (0.481, _skid(0.022, s + 190, 3000, 1500), 0.3),   # a last short skid
        (0.506, _base_tick(s + 100), 0.25),                 # rocks once on its base
    ])
    r = rng(s + 110)
    ptimes = (list(0.12 + r.uniform(0, 0.035, 6)) + list(0.27 + r.uniform(0, 0.02, 3))
              + list(0.44 + r.uniform(0, 0.02, 3)) + list(0.48 + r.uniform(0, 0.03, 6)))
    paper = _paper(D, s + 120, sorted(ptimes))
    cloth = _flutter(D, s + 130, 0.12, 0.2, 0.29) + 0.85 * _flutter(D, s + 140, 0.28, 0.36, 0.45, rate=19)
    bombs = (_jostle(D, s + 150, 0.277, 2, fall=0.5)
             + 1.1 * _jostle(D, s + 160, 0.447, 2, gap=(0.075, 0.09), fall=0.4))
    x = feet + 0.5 * card + 0.22 * paper + 0.12 * cloth + 0.42 * bombs
    return _finish(x, crest_db=19.0)


@sound("bomber_prepare", loudness=-20, wet=0.2, marks=(0.1,))
def bomber_prepare(seed):
    """Draws a bomb (a soft clink), strikes flint on steel at 0.1, sparks fly,
    the fuse catches with a puff and sizzles."""
    D = 0.8
    s = seed
    t = time_axis(D)
    draw = _pk(bandpass(_lowband(D, s + 10, 250, 5000), 1100, 0.9)) * _seg(D, 0.0, 0.03, 0.09, 1.5, 1.5)
    lift = place(D, [(0.035, _clink(s + 20, 0.45, 0.45), 1.0)])
    strike = place(D, [(0.1, _flint(s + 30), 1.0)])
    st = random_times(D, 260, s + 40, start=0.1, end=0.36, envelope=lambda u: (1 - u) ** 2)
    sparks = _pk(lowpass(_paper(D, s + 50, st, lengths=(0.0015, 0.003), band=(4500, 11000)), 12000, 2))
    puff = _pk(bandpass(_lowband(D, s + 60, 200, 4000), 1300, 0.8)) * _seg(D, 0.15, 0.168, 0.27, 1.5, 2.0)
    spit = 250 + 300 * _seg(D, 0.15, 0.2, 0.4, 1.0, 1.0)
    fuse = _sizzle(D, s + 70, spit=spit, pops=22, sputter=True, hiss_gain=0.05)
    lvl = _seg(D, 0.145, 0.215, 0.8, 1.6, 0.6)
    lvl = np.where(t > 0.215, np.minimum(lvl, 1.0), lvl)
    lvl = lvl * (1 + 0.25 * _seg(D, 0.16, 0.215, 0.33, 1.0, 1.0))  # sputters as it catches
    lvl *= _seg(D, 0.0, 0.0001, 0.8, 1.0, 0.25)                    # slow fade to the end
    x = 0.12 * draw + 0.18 * lift + 0.85 * strike + 0.22 * sparks + 0.3 * puff + 0.45 * fuse * lvl
    return _finish(x, crest_db=18.0)


@sound("bomber_throw", loudness=-19, wet=0.22, marks=(0.08, 0.12))
def bomber_throw(seed):
    """Underarm throw: cloth whoosh peaking at 0.08, the bomb leaves the hand
    at 0.12 (palm flick, sling clink, the fuse flares), then its sizzle
    recedes: quieter, darker, the band sliding down, tumbling."""
    D = 0.6
    s = seed
    t = time_axis(D)
    sw = _band_path(pink(D, s + 10), [(0.0, 380), (0.085, 1250), (0.2, 700), (0.3, 520)], q=1.1)
    flap = 0.7 + 0.3 * np.abs(np.sin(np.pi * 21 * t))
    whoosh = _pk(sw * flap * _seg(D, 0.005, 0.085, 0.29, 2.2, 1.6))
    tt = time_axis(0.06)
    palm = (_pk(bandpass(white(0.06, s + 20), 2400, 0.8) * np.exp(-tt / 0.006))
            + 0.5 * _pk(_lowband(0.06, s + 30, 120, 500) * np.exp(-tt / 0.012)))
    release = place(D, [(0.12, palm, 1.0)])
    sling = place(D, [(0.128, _clink(s + 40, 0.6, 0.45), 1.0), (0.17, _clink(s + 50, 0.3, 0.4), 0.35)])
    fuse = _sizzle(D, s + 60, spit=70, pops=9)
    after = np.maximum(t - 0.12, 0)
    dist = np.where(t < 0.12, 0.3 + 0.47 * np.clip(t / 0.12, 0, 1) ** 2,
                    1.0 / (1 + after / 0.12) ** 1.1)
    flare = 0.5 * _seg(D, 0.1, 0.122, 0.2, 1.0, 1.5)
    spin = np.where(t < 0.12, 1.0, 0.75 + 0.25 * np.sin(2 * np.pi * 11 * after))
    fuse = fuse * (dist + flare) * spin * _seg(D, 0.0, 0.04, D, 1.5, 0.4)
    fuse = _hp_lp_path(fuse, [(0.0, 2000), (0.12, 2000), (0.55, 1200)],
                       [(0.0, 11000), (0.12, 12000), (0.55, 3400)])
    air = _band_path(pink(D, s + 70), [(0.12, 1800), (0.5, 700)], q=1.2)
    air = _pk(air) * np.where(t < 0.12, 0, 1.0 / (1 + after / 0.08) ** 1.4) * _seg(D, 0.11, 0.15, D, 1, 0.5)
    x = 0.45 * whoosh + 0.3 * release + 0.3 * sling + 0.8 * fuse + 0.1 * air
    return _finish(x, crest_db=17.0)


@sound("bomber_hurt", loudness=-18, wet=0.18, marks=(0.118,))
def bomber_hurt(seed):
    """Thud at 0.118 (body blow + jerkin slap + paper crumple), the bombs
    clank in the sling, a nervous stuttered hiss of breath."""
    D = 0.75
    s = seed
    hit = place(D, [(0.118, _blow(s + 10, 1.0), 1.0)])
    r = rng(s + 20)
    pt = 0.118 + np.sort(r.exponential(0.022, 12))
    crumple = _paper(D, s + 30, list(pt[pt < 0.25]))
    clank = _jostle(D, s + 40, 0.124, 4, gap=(0.018, 0.04), fall=0.6, hard=1.2, damp=0.5, base=_BOMB_BASE * 0.92)
    breath = 0.85 * _hiss(D, s + 50, 0.165, 0.27, 0.2) + 0.3 * _hiss(D, s + 60, 0.29, 0.48, 0.15)
    x = hit + 0.3 * crumple + 0.38 * clank + 0.22 * breath
    return _finish(x, crest_db=17.0)


@sound("bomber_death", loudness=-18, wet=0.3, marks=(0.118, 0.69))
def bomber_death(seed):
    """Struck at 0.118, staggers, the card folds and topples (creasing
    grains, three crisp crease cracks, the fold, the air of the fall: kept
    about 19 dB under the hit so it reads in a mix), slaps on stone at 0.69
    and the bombs spill: they hit the stone and roll away, slowing, knocking
    and clinking."""
    D = 1.2
    s = seed
    t = time_axis(D)
    r = rng(s + 10)
    hit = place(D, [(0.118, _blow(s + 20, 1.15), 1.0)])
    pt = 0.118 + np.sort(r.exponential(0.03, 14))
    crumple = _paper(D, s + 30, list(pt[pt < 0.3]))
    clank = _jostle(D, s + 40, 0.124, 3, gap=(0.02, 0.045), fall=0.55, hard=1.1, damp=0.5, base=_BOMB_BASE * 0.92)
    gasp = _hiss(D, s + 50, 0.16, 0.36, 0.15, tremble=0.2)
    stagger = _flutter(D, s + 60, 0.15, 0.3, 0.46, 450, 1100, rate=13)
    ct = random_times(D, 90, s + 70, start=0.36, end=0.66, envelope=lambda u: 0.3 + 0.7 * u)
    crease = _paper(D, s + 80, ct, lengths=(0.008, 0.016, 0.03), band=(1500, 7000))
    fold = _paper(D, s + 90, [0.47, 0.478, 0.49], lengths=(0.02, 0.03), band=(2200, 5500))
    cracks = _paper(D, s + 91, [0.40, 0.52, 0.60], lengths=(0.012,), band=(1800, 5000))
    topple = _pk(_band_path(pink(D, s + 100), [(0.45, 280), (0.69, 950)], q=1.0)) * _seg(D, 0.45, 0.685, 0.72, 2.5, 1.0)
    tt = time_axis(0.08)
    flap = _pk(bandpass(white(0.08, s + 110), 2600, 0.5) * np.exp(-tt / 0.011))
    land = place(D, [
        (0.69, _blow(s + 120, 0.9, f0=75.0), 0.85),         # the body on stone
        (0.69, flap, 0.45),
        (0.691, _base_tick(s + 130), 0.5),
        (0.694, _bomb_drop(s + 140, 1.0), 0.7),
        (0.713, _bomb_drop(s + 150, 0.8), 0.5),
        (0.738, _bomb_drop(s + 160, 0.6), 0.35),
    ])
    rolls = (_roll(D, s + 170, 0.70, 1.17, turns=16)
             + 0.75 * _roll(D, s + 180, 0.72, 1.12, turns=19, base=_BOMB_BASE * 1.09))
    clinks = place(D, [(0.82, _clink(s + 190, 0.8, 0.7), 0.6), (0.965, _clink(s + 200, 0.6, 0.7), 0.42),
                       (1.07, _clink(s + 210, 0.4, 0.7), 0.25)])
    x = (hit + 0.28 * crumple + 0.4 * clank + 0.12 * gasp + 0.1 * stagger + 0.3 * crease + 0.25 * fold
         + 0.3 * cracks + 0.25 * topple + land + 0.55 * rolls + 0.45 * clinks)
    x *= np.where(t > 1.1, np.clip((1.2 - t) / 0.1, 0, 1), 1.0)
    return _finish(x, crest_db=16.2)
