"""Procedural sound design toolkit: numpy only, deterministic.

Every sound of the game is built from code here (no recordings, no
libraries): noise, oscillators, filters, resonators, a stone-hall reverb and
mastering. Run with Blender's bundled Python, which ships numpy:

    "C:/Program Files/Blender Foundation/Blender 3.5/3.5/python/bin/python.exe" tools/audio/build_sfx.py

All functions take and return float64 mono arrays at SR, nominally in -1..1.
Randomness always comes from an explicit seed, so a build is reproducible.
"""
import math
import os
import struct
import wave
import zlib

import numpy as np

SR = 44100


# --------------------------------------------------------------------------
# Time and randomness

def n_samples(duration):
    return max(1, int(round(duration * SR)))


def time_axis(duration):
    return np.arange(n_samples(duration)) / SR


def rng(seed):
    return np.random.default_rng(seed)


def silence(duration):
    return np.zeros(n_samples(duration))


# --------------------------------------------------------------------------
# Noise

def white(duration, seed):
    return rng(seed).uniform(-1, 1, n_samples(duration))


def _shaped_noise(duration, seed, exponent):
    n = n_samples(duration)
    spectrum = np.fft.rfft(rng(seed).standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = f[1] if len(f) > 1 else 1
    spectrum *= f ** (-exponent / 2)
    x = np.fft.irfft(spectrum, n)
    return x / (np.max(np.abs(x)) + 1e-12)


def pink(duration, seed):
    """1/f noise: fuller, more natural than white (wind, rumble, cloth)."""
    return _shaped_noise(duration, seed, 1.0)


def brown(duration, seed):
    """1/f^2 noise: deep rumble (explosion bodies, distant thunder)."""
    return _shaped_noise(duration, seed, 2.0)


def crackle(duration, density, seed, decay=0.002):
    """Sparse random impulses with tiny decays (fire, electricity, gravel).
    `density` is impulses per second (can be an array per sample)."""
    n = n_samples(duration)
    r = rng(seed)
    dens = np.broadcast_to(np.asarray(density, dtype=float), (n,))
    hits = r.random(n) < dens / SR
    x = np.zeros(n)
    x[hits] = r.uniform(-1, 1, hits.sum())
    if decay > 0:
        k = n_samples(decay * 5)
        kernel = np.exp(-np.arange(k) / (decay * SR))
        x = convolve(x, kernel)[:n]
    return x / (np.max(np.abs(x)) + 1e-12)


# --------------------------------------------------------------------------
# Oscillators

def _freq_array(freq, n):
    return np.broadcast_to(np.asarray(freq, dtype=float), (n,)).astype(float)


def phase_of(freq, duration=None, n=None, phase0=0.0):
    """Integrated phase (cycles) for a constant or per-sample frequency."""
    if n is None:
        n = n_samples(duration) if duration is not None else len(np.atleast_1d(freq))
    f = _freq_array(freq, n)
    return phase0 + np.cumsum(f) / SR


def sine(freq, duration=None, n=None, phase0=0.0):
    return np.sin(2 * np.pi * phase_of(freq, duration, n, phase0))


def saw(freq, duration=None, n=None):
    p = phase_of(freq, duration, n)
    return 2 * (p - np.floor(p)) - 1


def square(freq, duration=None, n=None, duty=0.5):
    p = phase_of(freq, duration, n)
    return np.where(p - np.floor(p) < duty, 1.0, -1.0)


def triangle(freq, duration=None, n=None):
    p = phase_of(freq, duration, n)
    return 4 * np.abs(p - np.floor(p) - 0.5) - 1


def glide(f0, f1, duration, curve="exp"):
    """A frequency path from f0 to f1 (Hz per sample), for oscillators."""
    u = np.linspace(0, 1, n_samples(duration))
    if curve == "exp":
        return f0 * (f1 / f0) ** u
    if curve == "out":
        u = 1 - (1 - u) ** 2
    elif curve == "in":
        u = u ** 2
    return f0 + (f1 - f0) * u


def fm(carrier, modulator, index, duration):
    """Two-operator FM: bells, gongs, metallic tones."""
    n = n_samples(duration)
    mod = np.sin(2 * np.pi * phase_of(modulator, n=n))
    idx = _freq_array(index, n)
    pc = phase_of(carrier, n=n)
    return np.sin(2 * np.pi * pc + idx * mod)


# --------------------------------------------------------------------------
# Envelopes

def env_points(duration, points, curve="linear"):
    """Piecewise envelope through (time_s, value) points; holds the ends."""
    t = time_axis(duration)
    ts = [p[0] for p in points]
    vs = [p[1] for p in points]
    e = np.interp(t, ts, vs)
    if curve == "smooth":
        # Raised-cosine smoothing between points.
        e = np.interp(t, ts, vs)
    return e


def env_perc(duration, attack=0.002, decay=0.2, curve=4.0):
    """Percussive: fast linear attack, exponential-ish decay of `decay` s
    (time to about -60 dB with curve 4)."""
    t = time_axis(duration)
    e = np.where(t < attack, t / max(attack, 1e-6), np.exp(-curve * 1.7 * (t - attack) / max(decay, 1e-6)))
    return e


def env_adsr(duration, attack, decay, sustain, release):
    t = time_axis(duration)
    hold_end = max(duration - release, attack + decay)
    e = np.piecewise(
        t,
        [t < attack, (t >= attack) & (t < attack + decay), (t >= attack + decay) & (t < hold_end), t >= hold_end],
        [lambda x: x / max(attack, 1e-6),
         lambda x: 1 - (1 - sustain) * (x - attack) / max(decay, 1e-6),
         lambda x: sustain + 0 * x,
         lambda x: sustain * np.clip(1 - (x - hold_end) / max(release, 1e-6), 0, 1)])
    return e


def env_swell(duration, peak_at=0.5, power=2.0):
    """Rises to 1 at peak_at (fraction), falls to 0 at the end."""
    u = np.linspace(0, 1, n_samples(duration))
    up = (u / peak_at) ** power
    down = ((1 - u) / (1 - peak_at)) ** power
    return np.where(u < peak_at, up, down)


# --------------------------------------------------------------------------
# Filters (FFT, zero phase). Responses are magnitude gains over frequency.

def fft_filter(x, response):
    n = len(x)
    size = 1 << int(math.ceil(math.log2(max(n, 2) * 2)))
    spectrum = np.fft.rfft(x, size)
    f = np.fft.rfftfreq(size, 1 / SR)
    spectrum *= response(f)
    return np.fft.irfft(spectrum, size)[:n]


def lowpass(x, cutoff, order=2):
    return fft_filter(x, lambda f: 1 / np.sqrt(1 + (f / cutoff) ** (2 * order)))


def highpass(x, cutoff, order=2):
    return fft_filter(x, lambda f: 1 / np.sqrt(1 + (cutoff / np.maximum(f, 1e-3)) ** (2 * order)))


def bandpass(x, center, q=1.0):
    """Resonant band around `center` (log-frequency gaussian, width ~ 1/q octaves)."""
    width = 1.0 / max(q, 0.05)
    return fft_filter(x, lambda f: np.exp(-0.5 * (np.log2(np.maximum(f, 1e-3) / center) / (width / 2.355)) ** 2))


def peak_eq(x, center, gain_db, q=1.0):
    width = 1.0 / max(q, 0.05)
    g = 10 ** (gain_db / 20) - 1
    return fft_filter(x, lambda f: 1 + g * np.exp(-0.5 * (np.log2(np.maximum(f, 1e-3) / center) / (width / 2.355)) ** 2))


def tilt(x, db_per_octave, pivot=1000.0):
    return fft_filter(x, lambda f: (np.maximum(f, 10) / pivot) ** (db_per_octave / 6.02))


def stft_filter(x, gain_fn, frame=1024, hop=256):
    """Time-varying filter: gain_fn(freqs, t_seconds) -> gains per frame."""
    n = len(x)
    window = np.hanning(frame)
    pad = np.concatenate([np.zeros(frame), x, np.zeros(frame)])
    out = np.zeros(len(pad))
    norm = np.zeros(len(pad))
    freqs = np.fft.rfftfreq(frame, 1 / SR)
    for start in range(0, len(pad) - frame, hop):
        seg = pad[start:start + frame] * window
        t = (start + frame / 2 - frame) / SR
        spec = np.fft.rfft(seg) * gain_fn(freqs, t)
        out[start:start + frame] += np.fft.irfft(spec, frame) * window
        norm[start:start + frame] += window ** 2
    out = out / np.maximum(norm, 1e-6)
    return out[frame:frame + n]


def sweep_lowpass(x, cutoff_start, cutoff_end, order=2):
    """Lowpass whose cutoff moves (exponentially) over the sound."""
    duration = len(x) / SR

    def gain(f, t):
        u = min(max(t / max(duration, 1e-6), 0), 1)
        c = cutoff_start * (cutoff_end / cutoff_start) ** u
        return 1 / np.sqrt(1 + (f / c) ** (2 * order))
    return stft_filter(x, gain)


def sweep_bandpass(x, center_start, center_end, q=2.0):
    duration = len(x) / SR
    width = 1.0 / max(q, 0.05)

    def gain(f, t):
        u = min(max(t / max(duration, 1e-6), 0), 1)
        c = center_start * (center_end / center_start) ** u
        return np.exp(-0.5 * (np.log2(np.maximum(f, 1e-3) / c) / (width / 2.355)) ** 2)
    return stft_filter(x, gain)


def formant(x, formants):
    """Vocal-tract-like shaping: sum of resonant bands [(freq, q, gain)].
    Used for creature growls and choir-like pads (never human words)."""
    def response(f):
        g = np.zeros_like(f)
        for center, q, gain in formants:
            width = 1.0 / max(q, 0.05)
            g += gain * np.exp(-0.5 * (np.log2(np.maximum(f, 1e-3) / center) / (width / 2.355)) ** 2)
        return g
    return fft_filter(x, response)


# --------------------------------------------------------------------------
# Resonators and physical-ish models

def modal(duration, modes, seed=None, strike=None):
    """Struck object: damped sinusoids [(freq, decay_s, amp)]. Metal: many
    inharmonic modes, long decays; wood: few low modes, short decays; stone:
    dense, very short. `strike` (an excitation array) is convolved in."""
    t = time_axis(duration)
    x = np.zeros_like(t)
    r = rng(seed if seed is not None else 0)
    for freq, decay, amp in modes:
        ph = r.uniform(0, 2 * np.pi)
        x += amp * np.sin(2 * np.pi * freq * t + ph) * np.exp(-t / max(decay, 1e-4))
    if strike is not None:
        x = convolve(strike, x)[:len(t)]
    return x


def metal_modes(base, count=8, spread=1.0, decay=0.8, seed=0):
    """Inharmonic partials of a metal plate or blade."""
    r = rng(seed)
    ratios = [1.0, 1.47, 2.09, 2.56, 3.2, 3.9, 4.7, 5.6, 6.6, 7.7, 8.9, 10.2]
    modes = []
    for i in range(min(count, len(ratios))):
        ratio = ratios[i] * (1 + spread * r.uniform(-0.02, 0.02))
        modes.append((base * ratio, decay / (1 + 0.45 * i), 1.0 / (1 + 0.6 * i)))
    return modes


def wood_modes(base, decay=0.08, seed=0):
    r = rng(seed)
    ratios = [1.0, 2.7, 4.1, 5.9]
    return [(base * q * (1 + r.uniform(-0.03, 0.03)), decay / (1 + i), 1.0 / (1 + i)) for i, q in enumerate(ratios)]


def karplus(freq, duration, damping=0.996, brightness=0.5, seed=0):
    """Plucked string (Karplus-Strong): bowstrings, lutes, wires."""
    n = n_samples(duration)
    period = max(2, int(round(SR / freq)))
    buf = rng(seed).uniform(-1, 1, period)
    buf = lowpass(buf, 400 + 9000 * brightness, 1) if period > 8 else buf
    out = np.zeros(n)
    idx = 0
    for i in range(n):
        out[i] = buf[idx]
        nxt = (idx + 1) % period
        buf[idx] = damping * 0.5 * (buf[idx] + buf[nxt])
        idx = nxt
    return out


def grains(duration, times, grain, seed, band=(800, 6000), gain_jitter=0.5):
    """Granular noise: short filtered bursts at `times` (seconds). Paper
    rustle, gravel, cloth, debris. `grain` is each burst's length."""
    n = n_samples(duration)
    out = np.zeros(n)
    r = rng(seed)
    g = n_samples(grain)
    env = np.hanning(g) if g > 2 else np.ones(g)
    lo, hi = band
    for i, t0 in enumerate(times):
        start = int(t0 * SR)
        if start >= n:
            continue
        burst = r.uniform(-1, 1, g) * env
        center = math.exp(r.uniform(math.log(lo), math.log(hi)))
        burst = bandpass(burst, center, 1.5)
        burst *= 1 - gain_jitter * r.random()
        end = min(n, start + g)
        out[start:end] += burst[:end - start]
    return out


def random_times(duration, rate, seed, start=0.0, end=None, envelope=None):
    """Poisson event times (per second), optionally shaped by an envelope fn(u)."""
    r = rng(seed)
    end = duration if end is None else end
    times = []
    t = start
    while t < end:
        t += r.exponential(1 / max(rate, 1e-6))
        if t < end and (envelope is None or r.random() < envelope((t - start) / max(end - start, 1e-6))):
            times.append(t)
    return times


# --------------------------------------------------------------------------
# Nonlinear, time and mixing

def drive(x, amount=2.0):
    return np.tanh(amount * x) / math.tanh(amount)


def resample(x, ratio):
    """Pitch/speed change by `ratio` (2 = an octave up, twice as fast)."""
    n = max(1, int(len(x) / ratio))
    return np.interp(np.arange(n) * ratio, np.arange(len(x)), x)


def delay(x, time, feedback=0.3, mix=0.3, repeats=4):
    d = n_samples(time)
    out = np.concatenate([x, np.zeros(d * repeats)])
    wet = np.zeros_like(out)
    g = 1.0
    for k in range(1, repeats + 1):
        g *= feedback
        wet[d * k:d * k + len(x)] += x * g
    return out + mix * wet


def place(duration, events):
    """Mix [(time_s, sound, gain)] into a buffer of `duration` seconds."""
    out = silence(duration)
    for t0, sound, gain in events:
        start = int(round(t0 * SR))
        if start >= len(out):
            continue
        end = min(len(out), start + len(sound))
        out[start:end] += gain * sound[:end - start]
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def pad_to(x, duration):
    n = n_samples(duration)
    return x[:n] if len(x) >= n else np.concatenate([x, np.zeros(n - len(x))])


def fade(x, fade_in=0.0, fade_out=0.01):
    x = x.copy()
    a = min(len(x), n_samples(fade_in)) if fade_in > 0 else 0
    b = min(len(x), n_samples(fade_out)) if fade_out > 0 else 0
    if a > 1:
        x[:a] *= np.linspace(0, 1, a)
    if b > 1:
        x[-b:] *= np.linspace(1, 0, b) ** 2
    return x


def convolve(a, b):
    n = len(a) + len(b) - 1
    size = 1 << int(math.ceil(math.log2(max(n, 2))))
    return np.fft.irfft(np.fft.rfft(a, size) * np.fft.rfft(b, size), size)[:n]


# --------------------------------------------------------------------------
# The environment: a stone hall of the tower

def room_ir(rt60=1.6, size=0.85, brightness=0.35, seed=7, predelay=0.012):
    """A synthetic impulse response: sparse early reflections off stone walls,
    then a dense tail that darkens as it decays."""
    duration = rt60 * 1.1 + predelay
    n = n_samples(duration)
    t = np.arange(n) / SR
    r = rng(seed)
    ir = np.zeros(n)
    # Early reflections: a dozen bounces in the first 80 ms.
    for k in range(12):
        d = predelay + size * r.uniform(0.006, 0.08)
        i = int(d * SR)
        if i < n:
            ir[i] += r.uniform(0.25, 0.6) * (1 if r.random() < 0.5 else -1) * math.exp(-d * 6)
    tail = r.standard_normal(n) * np.exp(-6.9 * t / rt60)
    tail[:int(predelay * SR)] = 0
    # Stone keeps the mids, the air takes the highs as the tail goes on.
    tail = stft_filter(tail, lambda f, tt: 1 / np.sqrt(1 + (f / (700 + 5000 * brightness * math.exp(-tt * 2.5))) ** 4))
    tail = highpass(tail, 90, 1)
    ir += 0.18 * tail / (np.max(np.abs(tail)) + 1e-12)
    return ir / (np.sqrt(np.sum(ir ** 2)) + 1e-12)


_IR_CACHE = {}


def hall(x, wet=0.22, rt60=1.6, brightness=0.35):
    """Places a dry sound in the tower's stone hall (dry + wet send)."""
    key = (round(rt60, 3), round(brightness, 3))
    if key not in _IR_CACHE:
        _IR_CACHE[key] = room_ir(rt60, brightness=brightness)
    ir = _IR_CACHE[key]
    wet_signal = convolve(x, ir)
    out = np.zeros(len(wet_signal))
    out[:len(x)] += x
    rms_dry = np.sqrt(np.mean(x ** 2)) + 1e-12
    rms_wet = np.sqrt(np.mean(wet_signal[:len(x)] ** 2)) + 1e-12
    out += wet * wet_signal * (rms_dry / rms_wet)
    return out


# --------------------------------------------------------------------------
# Mastering and measurement

def db(x):
    return 20 * math.log10(max(float(x), 1e-12))


def peak_db(x):
    return db(np.max(np.abs(x)) if len(x) else 0)


def loudness_db(x, window=0.4):
    """Short-term loudness proxy: the loudest 400 ms RMS (dBFS), after a gentle
    K-like weighting (less weight below 100 Hz, a lift around 2-4 kHz)."""
    w = fft_filter(x, lambda f: (1 / np.sqrt(1 + (60 / np.maximum(f, 1)) ** 4)) * (1 + 0.5 * np.exp(-0.5 * (np.log2(np.maximum(f, 1) / 3000) / 0.8) ** 2)))
    n = n_samples(window)
    if len(w) <= n:
        return db(np.sqrt(np.mean(w ** 2)))
    c = np.cumsum(np.concatenate([[0], w ** 2]))
    rms = np.sqrt((c[n:] - c[:-n]) / n)
    return db(np.max(rms))


def normalize_loudness(x, target_db, ceiling_db=-1.0):
    g = 10 ** ((target_db - loudness_db(x)) / 20)
    y = x * g
    p = np.max(np.abs(y))
    ceiling = 10 ** (ceiling_db / 20)
    if p > ceiling:
        # A soft limiter keeps transients from clipping without dulling the body.
        y = np.tanh(y / ceiling) * ceiling
    return y


def trim_tail(x, threshold_db=-54, keep=0.02):
    """Cuts the silent end (below threshold), keeping a short fade."""
    a = np.abs(x)
    above = np.nonzero(a > 10 ** (threshold_db / 20))[0]
    if not len(above):
        return x[:n_samples(keep)]
    end = min(len(x), above[-1] + n_samples(keep))
    return fade(x[:end], 0, keep)


def remove_dc(x):
    return highpass(x - np.mean(x), 25, 1)


def analyze(x):
    """Objective facts about a sound, for checking a recipe without ears."""
    a = np.abs(x)
    peak = float(np.max(a)) if len(a) else 0.0
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x)))) if len(x) > 8 else np.zeros(2)
    f = np.fft.rfftfreq(len(x), 1 / SR) if len(x) > 8 else np.zeros(2)
    centroid = float(np.sum(f * spec) / (np.sum(spec) + 1e-12))
    env = np.convolve(a, np.ones(64) / 64, mode="same")
    above = np.nonzero(env > peak * 10 ** (-40 / 20))[0] if peak > 0 else []
    bands = {}
    for name, lo, hi in (("sub<80", 20, 80), ("low80-300", 80, 300), ("mid300-2k", 300, 2000), ("high2k-8k", 2000, 8000), ("air>8k", 8000, 22050)):
        m = (f >= lo) & (f < hi)
        bands[name] = round(10 * math.log10((np.sum(spec[m] ** 2) + 1e-12) / (np.sum(spec ** 2) + 1e-12)), 1)
    return {
        "duration_ms": round(len(x) / SR * 1000),
        "peak_dbfs": round(db(peak), 1),
        "loudness_db": round(loudness_db(x), 1),
        "time_to_peak_ms": round(int(np.argmax(a)) / SR * 1000) if len(a) else 0,
        "audible_ms": round((above[-1] - above[0]) / SR * 1000) if len(above) else 0,
        "centroid_hz": round(centroid),
        "band_share_db": bands,
        "dc": round(float(np.mean(x)), 4),
        "clipped": int(np.sum(a >= 0.999)),
    }


# --------------------------------------------------------------------------
# Files

def write_wav(path, x, sr=SR):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data)


def read_wav(path):
    with wave.open(path, "rb") as w:
        data = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2")
    return data.astype(float) / 32767


def _png(path, rgb):
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[y].astype(np.uint8).tobytes() for y in range(h))

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def spectrogram_png(path, x, width=640, height=240, marks=()):
    """Waveform strip over a log-frequency spectrogram (30 Hz-20 kHz, 80 dB
    range), for reviewing a sound by eye. `marks` draws vertical ticks at
    times in seconds (animation keys to sync with)."""
    duration = max(len(x) / SR, 1e-3)
    frame = 2048
    hop = max(64, int(len(x) / width)) if len(x) > frame else 64
    pad = np.concatenate([x, np.zeros(frame)])
    cols = []
    for start in range(0, max(1, len(x)), hop):
        seg = pad[start:start + frame] * np.hanning(frame)
        cols.append(np.abs(np.fft.rfft(seg)))
    spec = np.array(cols).T  # bins x frames
    f = np.fft.rfftfreq(frame, 1 / SR)
    rows = np.geomspace(30, 20000, height)
    img_spec = np.array([np.interp(rows, f, spec[:, c]) for c in range(spec.shape[1])]).T[::-1]
    img_db = 20 * np.log10(img_spec + 1e-9)
    img_db = np.clip((img_db - (img_db.max() - 80)) / 80, 0, 1)
    img_db = np.array([np.interp(np.linspace(0, img_db.shape[1] - 1, width), np.arange(img_db.shape[1]), r) for r in img_db])
    # Colour: dark blue -> violet -> orange -> pale yellow.
    stops = np.array([[8, 10, 24], [70, 20, 110], [200, 60, 60], [250, 170, 40], [255, 250, 210]], float)
    pos = img_db * (len(stops) - 1)
    lo = np.floor(pos).astype(int).clip(0, len(stops) - 2)
    frac = (pos - lo)[..., None]
    rgb = stops[lo] * (1 - frac) + stops[lo + 1] * frac
    wave_h = 60
    strip = np.full((wave_h, width, 3), 18.0)
    xs = np.linspace(0, len(x) - 1, width).astype(int) if len(x) else np.zeros(width, int)
    blocks = np.array_split(np.abs(x), width) if len(x) >= width else [np.abs(x)] * width
    for col, b in enumerate(blocks):
        a = float(np.max(b)) if len(b) else 0.0
        hpx = int(a * (wave_h / 2 - 2))
        strip[wave_h // 2 - hpx:wave_h // 2 + hpx + 1, col] = [140, 200, 230]
    img = np.concatenate([strip, rgb], 0)
    for m in marks:
        col = int(m / duration * (width - 1))
        if 0 <= col < width:
            img[:, col] = [120, 255, 120]
    # Frequency guides at 100 Hz, 1 kHz, 10 kHz.
    for g in (100, 1000, 10000):
        row = wave_h + int((1 - math.log(g / 30) / math.log(20000 / 30)) * (height - 1))
        img[row, ::4] = [90, 90, 90]
    _png(path, img)
