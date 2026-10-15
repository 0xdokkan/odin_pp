"""Family `ambience` - the room of the mechanics lab (see SOUND_SPEC.md).

amb_crypt_loop is a 24 s seamless loop that plays under everything: a low wind
moaning through the stone halls, sparse water drips far away, a torch's soft
crackle and, rarely, a hanging chain that creaks. In the strongest gusts the
paper standees of the diorama tremble on their bases (the game's signature).

Seamless by construction, not patched afterwards: every layer is one period of
a periodic signal of exactly N = 24 s samples.
  - noise is drawn straight in the frequency domain at N samples;
  - filters are circular (an FFT of size N, or an STFT whose frames wrap
    around the end and whose hop divides N);
  - slow modulations (gusts, flame flutter) are periodic curves;
  - the wind's moaning tones complete a whole number of cycles over the loop;
  - every event (drip, crackle, creak, flap) is mixed in modulo N, and none starts
    so close to the end that its tail would run over the seam.
The build then folds the hall's reverb tail back onto the start.
"""
import math

import numpy as np

from dsp import *  # noqa: F401,F403
from registry import sound

_LOOP = 24.0
_N = n_samples(_LOOP)                 # 1 058 400 samples
_FREQS = np.fft.rfftfreq(_N, 1 / SR)
_CR = 200.0                           # control rate of the slow curves (Hz)
_HOP = 1050                           # circular STFT: N / hop = 1008 frames
_FRAME = 4 * _HOP
assert _N % _HOP == 0


# --------------------------------------------------------------------------
# Responses (magnitude over frequency) and circular building blocks

def _band(f, center, q):
    width = 1.0 / max(q, 0.05)
    return np.exp(-0.5 * (np.log2(np.maximum(f, 1e-3) / center) / (width / 2.355)) ** 2)


def _lp(f, cutoff, order=2):
    return 1 / np.sqrt(1 + (f / cutoff) ** (2 * order))


def _hp(f, cutoff, order=2):
    return 1 / np.sqrt(1 + (cutoff / np.maximum(f, 1e-3)) ** (2 * order))


def _tilt(f, exponent):
    """Amplitude slope of 1/f^exponent power noise (1 pink, 2 brown)."""
    return np.maximum(f, 20.0) ** (-exponent / 2)


def _noise(seed, response):
    """Periodic gaussian noise of the loop's length, coloured by `response`,
    at unit RMS."""
    r = rng(seed)
    m = len(_FREQS)
    spec = (r.standard_normal(m) + 1j * r.standard_normal(m)) * response(_FREQS)
    spec[0] = 0
    x = np.fft.irfft(spec, _N)
    return x / (np.sqrt(np.mean(x ** 2)) + 1e-12)


def _cfilter(x, response):
    """Circular (wrap-around) zero-phase filter over the whole loop."""
    return np.fft.irfft(np.fft.rfft(x) * response(_FREQS), _N)


def _curve(seed, cutoff):
    """A smooth periodic random curve (zero mean, unit std) with its energy
    below `cutoff` Hz. Returns a function of time in seconds."""
    m = int(round(_LOOP * _CR))
    spec = np.fft.rfft(rng(seed).standard_normal(m))
    f = np.fft.rfftfreq(m, 1 / _CR)
    spec *= np.exp(-0.5 * (f / cutoff) ** 2)
    spec[0] = 0
    c = np.fft.irfft(spec, m)
    c /= np.std(c) + 1e-12
    tc = np.arange(m + 1) / _CR
    cc = np.concatenate([c, c[:1]])
    return lambda t: np.interp(np.mod(t, _LOOP), tc, cc)


def _cstft(x, gain_fn):
    """Time-varying filter over the loop: Hann frames (75 % overlap) that wrap
    around the end, so the result is periodic too. gain_fn(freqs, times) gets
    1-D arrays and returns a (frames, bins) gain matrix."""
    k = _N // _HOP
    w = 0.5 - 0.5 * np.cos(2 * np.pi * np.arange(_FRAME) / _FRAME)
    idx = (np.arange(k)[:, None] * _HOP + np.arange(_FRAME)[None, :]) % _N
    spec = np.fft.rfft(x[idx] * w, axis=1)
    f = np.fft.rfftfreq(_FRAME, 1 / SR)
    t = ((np.arange(k) * _HOP + _FRAME / 2) % _N) / SR
    spec *= gain_fn(f, t)
    y = np.fft.irfft(spec, _FRAME, axis=1) * w
    out = np.bincount(idx.ravel(), weights=y.ravel(), minlength=_N)
    return out / 1.5   # a periodic Hann, squared, sums to 1.5 at 75 % overlap


def _cplace(events):
    """Mix [(time_s, sound, gain)] into the loop, wrapping around the end."""
    out = np.zeros(_N)
    for t0, snd, gain in events:
        start = int(round(t0 * SR)) % _N
        pos = 0
        while pos < len(snd):
            room = min(len(snd) - pos, _N - start)
            out[start:start + room] += gain * snd[pos:pos + room]
            pos += room
            start = 0
    return out


def _smoothstep(u):
    u = np.clip(u, 0, 1)
    return u * u * (3 - 2 * u)


def _burst(r, duration, center, q, decay, attack=0.0002):
    """A short band-passed noise burst (a crackle tick, a slip of iron)."""
    t = time_axis(duration)
    env = np.minimum(t / attack, 1.0) * np.exp(-t / decay)
    b = bandpass(r.standard_normal(len(t)) * env, center, q)
    return b / (np.max(np.abs(b)) + 1e-12)


# --------------------------------------------------------------------------
# The wind through the stone halls

def _gusts(seed):
    """The wind's speed over the loop (about 0.5..2): slow gusts plus a
    quicker unrest. Shared by the wind, its moaning and the torch flame."""
    slow = _curve(seed, 0.11)
    quick = _curve(seed + 1, 0.45)
    return lambda t: np.exp(0.36 * slow(t) + 0.15 * quick(t))


def _wind(seed, speed):
    """Pink-ish air noise through a broad band that climbs and opens as the
    gust strengthens, a constant low floor of moving air, and a faint torn
    edge (air on stone edges) that only shows in strong gusts."""
    src = _noise(seed, lambda f: _tilt(f, 1.0) * _hp(f, 48, 2))

    def gain(f, t):
        # _band() written out on log-frequency, so the (frames x bins)
        # matrix costs a few array operations only.
        ls = np.log2(speed(t))[:, None]
        lf = np.log2(np.maximum(f, 1e-3))[None, :]
        # The body climbs ~0.7 octave per doubling of speed and the level
        # rises 3 dB: gusts stay gusts, but the lulls do not vanish at game
        # volume (the ear is far less sensitive to the low lull band).
        body = np.exp(-0.5 * ((lf - math.log2(265) - 0.7 * ls) * (0.75 * 2.355)) ** 2)
        floor = 0.45 * _lp(f, 150, 2)[None, :]
        edge = np.exp(-0.5 * ((lf - math.log2(1300) - 0.5 * ls) * (1.1 * 2.355)) ** 2)
        edge *= 0.22 * np.clip(np.exp2(ls) - 0.8, 0, None) ** 1.5
        return np.exp2(0.5 * ls) * (body + floor) + edge
    return _cstft(src, gain)


def _moan(seed, f0, speed, onset, full, bw, lean, t):
    """A stone opening moaning as the gust passes, like air over a bottle:
    narrowband noise (complex low-pass noise shifted up to f0) that opens
    once the wind is fast enough and leans a little sharp with the speed.
    Its phase completes a whole number of cycles over the loop."""
    cr = 400.0
    m = int(round(_LOOP * cr))
    r = rng(seed)
    spec = r.standard_normal(m) + 1j * r.standard_normal(m)
    spec *= np.exp(-0.5 * (np.fft.fftfreq(m, 1 / cr) / bw) ** 2)
    z = np.fft.ifft(spec)
    z /= np.sqrt(np.mean(np.abs(z) ** 2)) + 1e-12
    tz = np.arange(m + 1) / cr
    zz = np.concatenate([z, z[:1]])
    zr = np.interp(t, tz, zz.real)
    zi = np.interp(t, tz, zz.imag)
    s = speed(t)
    inst = f0 * s ** lean
    total = np.sum(inst) / SR
    inst *= round(total) / total
    ph = 2 * np.pi * np.cumsum(inst) / SR
    tone = zr * np.cos(ph) - zi * np.sin(ph)
    return tone * _smoothstep((s - onset) / (full - onset))


# --------------------------------------------------------------------------
# Far water drips

def _drip(r, f0, rise, decay, far):
    """A drop into a pool, far away: a tiny impact tick, then the bubble's
    ringing whose pitch climbs as it closes (Minnaert); distance takes the
    highs and the cistern walls answer with dark early echoes, the later
    ones darker still, so it reads as a big cistern, not a close plink."""
    dur = 0.3
    t = time_axis(dur)
    f = f0 * (1 + rise * (1 - np.exp(-t / 0.011)))
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * (1 - np.exp(-t / 0.0006)) * np.exp(-t / decay)
    tick = bandpass(r.standard_normal(len(t)) * np.exp(-t / 0.0005), 2600, 0.8)
    tick /= np.max(np.abs(tick)) + 1e-12
    x = tone + 0.22 * tick
    x = lowpass(x, 5200 - 2400 * far, 2)
    echo = lowpass(x, 2300 - 700 * far, 1)
    echo2 = lowpass(x, 1500 - 400 * far, 1)
    x = place(dur + 0.2, [(0.0, x, 1.0),
                          (0.017 + 0.008 * far, echo, 0.30 + 0.12 * far),
                          (0.034 + 0.011 * far, echo, -0.20 - 0.08 * far),
                          (0.058 + 0.014 * far, echo, 0.12 + 0.06 * far),
                          (0.095 + 0.020 * far, echo2, 0.09 + 0.05 * far),
                          (0.140 + 0.030 * far, echo2, -0.06 - 0.04 * far)])
    x = fade(x, 0.0005, 0.02)   # the zero-phase filters leave no step at either end
    return x / (np.max(np.abs(x)) + 1e-12)


def _drips(seed, speed):
    """Two far sources: a cistern drip that falls about every 4.8 s on
    average (5 per loop, so the spacing holds across the seam) but unevenly
    (+-0.6 s) and at uneven strength, once with a small second drop, and a
    farther, deeper drip that falls now and then (3 per loop), never on top
    of a chain creak. Shape variations come from their own generator, so the
    schedule does not move when they change.
    Level against the bed is the distance cue, so each drop is ridden
    gently with the wind (speed ** 0.5, about half of the bed's own swing):
    one falling in a deep lull must not jump forward, one falling in a gust
    must not vanish."""
    r = rng(seed)
    rv = rng(seed + 1)
    events = []

    def ride(t0):
        return float(speed(np.array([t0]))[0]) ** 0.5
    for k in range(5):
        t0 = 1.25 + k * _LOOP / 5 + r.uniform(-0.6, 0.6)
        f0 = 1480 * (1 + r.uniform(-0.05, 0.05))
        far = rv.uniform(0.52, 0.68)
        drop = _drip(r, f0, rv.uniform(0.52, 0.68), rv.uniform(0.027, 0.037), far)
        events.append((t0, drop, (0.8 + 0.2 * r.random()) * ride(t0)))
        if k in (1, 3):
            # drawn for both, kept once: one second drop per loop
            dt = r.uniform(0.13, 0.19)
            second = _drip(r, f0 * 1.45, 0.5, 0.022, far)
            if k == 3:
                events.append((t0 + dt, second, 0.3 * ride(t0)))
    for t0 in (3.5, 12.9, 18.6):
        t0 += r.uniform(-0.35, 0.35)
        f0 = 1020 * (1 + r.uniform(-0.06, 0.06))
        events.append((t0, _drip(r, f0, 0.42, 0.05, 1.0), 0.5 * (0.8 + 0.2 * r.random()) * ride(t0)))
    return _cplace(events)


# --------------------------------------------------------------------------
# The torch

def _torch(seed, speed, t):
    """A torch burning a few metres away: a soft fluttering combustion breath
    (fanned by the same gusts as the wind) and sparse crackle - resin ticks,
    small pops with a woody body, now and then a bubbling cluster."""
    flutter = _curve(seed, 5.0)
    sway = _curve(seed + 1, 1.0)
    breath = _noise(seed + 2, lambda f: _tilt(f, 1.2) * _band(f, 430, 0.8))
    # Breathes and flares (about +-6 dB) but never gutters out.
    breath *= np.exp(0.2 * flutter(t) + 0.1 * sway(t) + 0.3 * (speed(t) - 1))

    r = rng(seed + 3)
    busy = _curve(seed + 4, 0.25)
    rate = 4.2
    events = []
    tt = 0.05
    while True:
        tt += r.exponential(1 / rate)
        if tt > _LOOP - 0.25:
            break
        if r.random() > 0.55 + 0.45 * _smoothstep(0.5 + 0.4 * busy(np.array([tt]))[0]):
            continue
        kind = r.random()
        if kind < 0.66:
            # resin tick
            g = _burst(r, 0.006, math.exp(r.uniform(math.log(2200), math.log(7000))), 1.2,
                       r.uniform(0.0006, 0.0012))
            events.append((tt, g, math.exp(r.uniform(math.log(0.12), math.log(0.45)))))
        else:
            # small pop: a woody body under a tick
            body = _burst(r, 0.018, math.exp(r.uniform(math.log(650), math.log(1500))), 1.4,
                          r.uniform(0.002, 0.0035))
            tick = _burst(r, 0.006, math.exp(r.uniform(math.log(2500), math.log(6000))), 1.2, 0.0008)
            amp_pop = r.uniform(0.45, 0.85)
            events.append((tt, body, amp_pop))
            events.append((tt, tick, amp_pop * 0.6))
            if kind > 0.93:
                # a bubbling cluster of resin after the pop
                tc = tt
                for j in range(int(r.integers(4, 9))):
                    tc += r.uniform(0.008, 0.03)
                    g = _burst(r, 0.005, math.exp(r.uniform(math.log(2500), math.log(7500))), 1.3, 0.0007)
                    events.append((tc, g, amp_pop * r.uniform(0.15, 0.4) * (1 - j / 10)))
    crackle = _cfilter(_cplace(events), lambda f: _lp(f, 7500, 2) * _hp(f, 300, 1))
    return breath, crackle


# --------------------------------------------------------------------------
# The hanging chain

def _creak(r, duration, rates, base):
    """A hanging iron chain swaying: the links grab and slip (stick-slip),
    a pulse train whose rate rises and falls with the swing, exciting the
    links' inharmonic modes and the chain's heavier body, with a dry rasp of
    iron on iron."""
    n = n_samples(duration + 0.25)
    exc = np.zeros(n)
    t = 0.0
    while t < duration:
        u = t / duration
        rate = np.interp(u, [0.0, 0.45, 1.0], rates)
        a = math.sin(math.pi * u) ** 0.7 * (0.55 + 0.45 * r.random())
        i = int(t * SR)
        g = _burst(r, 0.0015, r.uniform(1800, 4200), 1.0, 0.0003)
        exc[i:i + len(g)] += a * g[:max(0, min(len(g), n - i))]
        t += (1 / rate) * (1 + r.uniform(-0.2, 0.2))
    # Small links coupled into a heavy chain: damped quickly, so the creak
    # is friction coloured by iron, not a ringing bell.
    ratios = (1.0, 1.43, 2.11, 2.86, 3.63, 4.87)
    modes = [(base * q * (1 + r.uniform(-0.015, 0.015)), 0.024 / (1 + 0.3 * i), 1.0 / (1 + 0.5 * i))
             for i, q in enumerate(ratios)]
    modes.append((base * 0.33, 0.04, 0.6))
    ir = modal(0.2, modes, seed=int(r.integers(1 << 30)))
    x = convolve(exc, ir)[:n]
    x /= np.max(np.abs(x)) + 1e-12
    rasp_env = np.convolve(np.abs(exc), np.hanning(n_samples(0.012)), mode="same")
    rasp_env /= np.max(rasp_env) + 1e-12
    rasp = bandpass(r.standard_normal(n), base * 2.6, 1.0) * rasp_env
    rasp /= np.max(np.abs(rasp)) + 1e-12
    return x + 0.35 * rasp


def _clink(r, base):
    """A link settling against the next: a tiny inharmonic ring, let ring
    out (the 0.22 s mode is ~-43 dB at 1.1 s) and closed under a fade."""
    strike = _burst(r, 0.002, 4000, 0.8, 0.0004)
    x = modal(1.1, metal_modes(base, count=6, decay=0.22, seed=int(r.integers(1 << 30))), strike=strike)
    x = fade(x, 0.0, 0.15)
    return x / (np.max(np.abs(x)) + 1e-12)


def _chains(seed):
    """Rare: one long creak, and later a swing there and back with the links
    settling."""
    r = rng(seed)
    events = [(6.8, _creak(r, 1.15, (24, 78, 30), 610), 1.0),
              (8.05, _clink(r, 2350), 0.32),
              (8.22, _clink(r, 2780), 0.2),
              (16.3, _creak(r, 0.6, (30, 66, 40), 565), 0.85),
              (17.3, _creak(r, 0.48, (52, 34, 20), 540), 0.7),
              (17.86, _clink(r, 2150), 0.28)]
    x = _cplace(events)
    return _cfilter(x, lambda f: _lp(f, 5200, 2) * _hp(f, 120, 1))


# --------------------------------------------------------------------------
# The paper standees

def _paper(seed, speed):
    """The game's signature, kept for the strongest gusts only: the paper
    standees tremble on their iron bases. Two cards, a nearer one and a
    farther, darker one. Each flaps at 15-25 Hz (faster as the gust grows) in
    short runs - a card caught by the draught keeps fluttering for a few
    flaps, "brrrt", then settles - so it reads as paper trembling, not as the
    torch's random crackle. A flap is a dry paper grain (1.5-6 kHz, ~12 ms,
    a soft 1 ms attack, softer and longer than a resin tick) whose colour
    stays close to its run's. Gust strength p (0 under speed 1.5, 1 near the
    loop's strongest gust) sets how often a run starts and how long it
    lasts: scattered flaps as a gust builds, a flutter at its height."""
    events = []
    for j, (rate, onset, far) in enumerate(((16.0, 1.5, 0.0), (22.0, 1.58, 1.0))):
        r = rng(seed + j)
        tt = 0.1
        run = False
        centre = 3000.0
        while True:
            s = speed(np.array([tt]))[0]
            tt += (1 + r.uniform(-0.2, 0.2)) / (rate * (0.75 + 0.25 * s))
            if tt > _LOOP - 0.1:
                break
            p = float(_smoothstep((speed(np.array([tt]))[0] - onset) / 0.35))
            if run:
                run = r.random() < 0.72 + 0.22 * p
            elif r.random() < 0.3 * p:
                run = True
                centre = math.exp(r.uniform(math.log(1900), math.log(5600 - 2000 * far)))
            if not run or p <= 0:
                continue
            c = centre * math.exp(r.uniform(-0.18, 0.18))
            g = _burst(r, 0.012, c, 1.5, r.uniform(0.002, 0.005), attack=0.001)
            events.append((tt, fade(g, 0.0, 0.003), p * r.uniform(0.45, 1.0) * (1 - 0.45 * far)))
    return _cfilter(_cplace(events), lambda f: _lp(f, 7000, 2) * _hp(f, 1200, 2))


# --------------------------------------------------------------------------
# The loop

_MIX_DB = {          # level of each layer (dB, relative to the wind's RMS)
    "wind": 0.0,
    "floor": -10.5,    # deep room tone under the wind
    "moan_low": -16.0,   # critical-band tone-to-noise peaks ~+3 dB (D3), ~-1 dB
    "moan_fifth": -18.0,  # (A3): a breathy howl, never a synth pad
    "air": -30.0,
    "torch": -19.0,
    "crackle": -5.0,   # crackle, drips, chains and paper: scaled by their peaks
    "drips": -9.0,     # far: under the torch crackle's peaks (A-weighted)
    "chains": -7.0,
    "paper": -11.0,
}
_PEAK_SCALED = ("crackle", "drips", "chains", "paper")


def _layers(seed):
    t = np.arange(_N) / SR
    speed = _gusts(seed)
    layers = {}
    layers["wind"] = _wind(seed + 10, speed)
    floor = _noise(seed + 20, lambda f: _tilt(f, 2.0) * _hp(f, 30, 3) * _lp(f, 95, 2))
    layers["floor"] = floor * (1 + 0.12 * _curve(seed + 21, 0.08)(t))
    layers["moan_low"] = _moan(seed + 30, 146.83, speed, 0.95, 1.8, 4.0, 0.045, t)
    layers["moan_fifth"] = _moan(seed + 31, 220.0, speed, 1.1, 1.95, 5.5, 0.05, t)
    air = _noise(seed + 40, lambda f: _band(f, 3600, 0.6))
    layers["air"] = air * np.clip(speed(t) - 0.7, 0, None) ** 2
    breath, crackle = _torch(seed + 50, speed, t)
    layers["torch"] = breath
    layers["crackle"] = crackle
    layers["drips"] = _drips(seed + 60, speed)
    layers["chains"] = _chains(seed + 70)
    layers["paper"] = _paper(seed + 80, speed)
    ref = np.sqrt(np.mean(layers["wind"] ** 2)) + 1e-12
    for name, x in layers.items():
        if name in _PEAK_SCALED:
            scale = ref * 4.0 / (np.max(np.abs(x)) + 1e-12)
        else:
            scale = ref / (np.sqrt(np.mean(x ** 2)) + 1e-12)
        layers[name] = x * scale * 10 ** (_MIX_DB[name] / 20)
    return layers


@sound("amb_crypt_loop", loudness=-34, wet=0.25, loop=True,
       note="24 s seamless loop: low wind in stone halls, far drips, torch crackle, rare chain creaks, "
            "paper standees trembling in the strongest gusts")
def amb_crypt_loop(seed):
    layers = _layers(seed)
    x = sum(layers.values())
    return x * (0.6 / (np.max(np.abs(x)) + 1e-12))
