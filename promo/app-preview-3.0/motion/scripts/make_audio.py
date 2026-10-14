"""Original music and sound design for the App Store preview, synthesized from scratch (no samples,
nothing licensed). 120 BPM, the groove starts at 2.4 s so every cut lands on a beat; hits, whooshes,
taps and the typing clicks follow src/timeline.ts.

    python make_audio.py ru public/audio-ru.wav
"""
import re
import sys
from pathlib import Path

import numpy as np
from scipy import signal

SR = 48000
TOTAL = 29.0
T0 = 2.4          # first downbeat of the groove
BEAT = 0.5        # 120 BPM
N = int(SR * (TOTAL + 0.5))
rng = np.random.default_rng(7)

HERE = Path(__file__).resolve().parent
TIMELINE = (HERE.parent / 'src' / 'timeline.ts').read_text()


def parse(lang):
    block = re.search(r'export const TAPS[^{]*\{(.*?)\n\};', TIMELINE, re.S).group(1)
    part = re.search(lang + r': \[(.*?)\]', block, re.S).group(1)
    taps = [float(a) for a in re.findall(r'at: ([\d.]+)', part)]
    typing = re.search(r'export const TYPING[^{]*\{(.*?)\n\};', TIMELINE, re.S).group(1)
    line = re.search(lang + r': \[(.*?)\]', typing).group(1)
    nums = [eval(x) for x in line.split(',')]
    return taps, nums


# ---------------------------------------------------------------- helpers

def t_(n):
    return np.arange(n) / SR


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def env_adsr(n, a=0.005, d=0.1, s=0.0, r=0.05):
    e = np.zeros(n)
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    na = max(1, min(na, n))
    e[:na] = np.linspace(0, 1, na)
    k = min(n, na + nd)
    if k > na:
        e[na:k] = np.linspace(1, s, k - na)
    e[k:] = s
    if nr > 0 and s > 0:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


def saw(f, n, phase=0.0):
    ph = (phase + np.cumsum(np.full(n, f) if np.isscalar(f) else f) / SR) % 1.0
    return 2 * ph - 1


def svf(x, cutoff, q=0.7, mode='lp'):
    """Time-varying state-variable filter (cutoff may be an array)."""
    n = len(x)
    c = np.broadcast_to(np.asarray(cutoff, dtype=float), (n,))
    g = np.tan(np.pi * np.clip(c, 20, SR * 0.45) / SR)
    k = 1.0 / q
    a1 = 1 / (1 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    ic1 = ic2 = 0.0
    out = np.empty(n)
    for i in range(n):
        v3 = x[i] - ic2
        v1 = a1[i] * ic1 + a2[i] * v3
        v2 = ic2 + a2[i] * ic1 + a3[i] * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        out[i] = v2 if mode == 'lp' else (v1 if mode == 'bp' else x[i] - k * v1 - v2)
    return out


def butter(x, f, kind='low', order=2):
    sos = signal.butter(order, f, btype=kind, fs=SR, output='sos')
    return signal.sosfilt(sos, x)


class Bus:
    def __init__(self):
        self.l = np.zeros(N)
        self.r = np.zeros(N)

    def add(self, x, at, gain=1.0, pan=0.0):
        i = int(at * SR)
        if i >= N:
            return
        if i < 0:
            x = x[-i:]
            i = 0
        x = x[: N - i]
        gl = gain * np.cos((pan + 1) * np.pi / 4)
        gr = gain * np.sin((pan + 1) * np.pi / 4)
        self.l[i:i + len(x)] += x * gl
        self.r[i:i + len(x)] += x * gr

    def add_st(self, l, r, at, gain=1.0):
        i = int(at * SR)
        l, r = l[: N - i], r[: N - i]
        self.l[i:i + len(l)] += l * gain
        self.r[i:i + len(r)] += r * gain


def reverb(l, r, seconds=2.4, damp=5000, mix=1.0):
    n = int(seconds * SR)
    tt = t_(n)
    irs = []
    for s in (1, 2):
        noise = np.random.default_rng(s).standard_normal(n)
        ir = noise * np.exp(-tt * 6.9 / seconds)
        ir = butter(ir, damp, 'low')
        ir[: int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))
        irs.append(ir / np.sqrt(np.sum(ir ** 2)))
    wl = signal.fftconvolve(l, irs[0])[: len(l)]
    wr = signal.fftconvolve(r, irs[1])[: len(r)]
    return wl * mix, wr * mix


# ---------------------------------------------------------------- instruments

def kick(strength=1.0):
    n = int(0.45 * SR)
    tt = t_(n)
    f = 46 + 110 * np.exp(-tt * 38)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 7.5)
    click = butter(rng.standard_normal(n) * np.exp(-tt * 300), 2500, 'high') * 0.25
    return np.tanh((body + click) * 1.6 * strength) * 0.9


def clap():
    n = int(0.35 * SR)
    tt = t_(n)
    noise = rng.standard_normal(n)
    e = np.zeros(n)
    for d in (0, 0.011, 0.022):
        i = int(d * SR)
        e[i:] += np.exp(-(tt[: n - i]) * 90)
    e += np.exp(-tt * 14) * 0.35
    return signal.sosfilt(signal.butter(2, [900, 3200], 'band', fs=SR, output='sos'), noise * e) * 1.4


def hat(open_=False):
    n = int((0.22 if open_ else 0.05) * SR)
    tt = t_(n)
    x = rng.standard_normal(n) * np.exp(-tt * (16 if open_ else 95))
    return butter(x, 7500, 'high') * 0.6


def pluck(m, dur=0.22, bright=1.0):
    n = int((dur + 0.1) * SR)
    tt = t_(n)
    f = midi(m)
    x = saw(f, n) + saw(f * 1.006, n, 0.3) * 0.7 + np.sin(2 * np.pi * f * 2 * tt) * 0.15
    cut = 600 + 5200 * bright * np.exp(-tt * 18)
    y = svf(x, cut, 1.4)
    return y * np.exp(-tt * 9) * env_adsr(n, 0.002, 0.05, 1, 0.0) * 0.32


def bell(m, dur=1.8):
    n = int(dur * SR)
    tt = t_(n)
    f = midi(m)
    mod = np.sin(2 * np.pi * f * 3.5 * tt) * 2.2 * np.exp(-tt * 4)
    x = np.sin(2 * np.pi * f * tt + mod) * np.exp(-tt * 2.6)
    x += np.sin(2 * np.pi * f * 2 * tt) * 0.2 * np.exp(-tt * 5)
    return x * env_adsr(n, 0.002, 0.01, 1, 0.0) * 0.25


def supersaw_chord(notes, dur, cutoff=2600, voices=7):
    n = int(dur * SR)
    l = np.zeros(n)
    r = np.zeros(n)
    for m in notes:
        f = midi(m)
        for v in range(voices):
            det = (v - (voices - 1) / 2) * 0.012
            x = saw(f * (1 + det * 0.5), n, rng.random())
            pan = (v / (voices - 1)) * 2 - 1
            l += x * np.cos((pan + 1) * np.pi / 4)
            r += x * np.sin((pan + 1) * np.pi / 4)
    sos = signal.butter(2, cutoff, 'low', fs=SR, output='sos')
    e = env_adsr(n, 0.02, 0.1, 0.85, 0.15)
    norm = 0.06 / np.sqrt(len(notes))
    return signal.sosfilt(sos, l) * e * norm, signal.sosfilt(sos, r) * e * norm


def pad(notes, dur, attack=1.2, cutoff=1800, sub=0.5):
    n = int(dur * SR)
    tt = t_(n)
    l = np.zeros(n)
    r = np.zeros(n)
    for m in notes:
        f = midi(m)
        for v, det in enumerate((-0.004, 0.0, 0.005)):
            x = saw(f * (1 + det), n, rng.random()) + sub * np.sin(2 * np.pi * f * 0.5 * tt)
            if v % 2:
                l += x
            else:
                r += x
    lfo = 1 + 0.25 * np.sin(2 * np.pi * 0.3 * tt)
    l = svf(l, cutoff * lfo, 0.8)
    r = svf(r, cutoff * lfo, 0.8)
    e = env_adsr(n, attack, 0.2, 1.0, min(1.5, dur * 0.4))
    norm = 0.05 / np.sqrt(len(notes))
    return l * e * norm, r * e * norm


def bass(m, dur):
    n = int(dur * SR)
    tt = t_(n)
    f = midi(m)
    x = saw(f, n) * 0.6 + np.sin(2 * np.pi * f * tt) * 0.8
    y = svf(x, 260 + 900 * np.exp(-tt * 14), 1.1)
    return y * env_adsr(n, 0.004, 0.08, 0.7, 0.03) * 0.55


def riser(dur, up=True):
    n = int(dur * SR)
    tt = t_(n)
    p = tt / dur
    noise = rng.standard_normal(n)
    cut = 400 + 9000 * (p ** 2 if up else (1 - p) ** 2)
    x = svf(noise, cut, 2.5, 'bp') * 0.9
    tone = saw(200 * 2 ** (2.5 * p), n) * 0.08
    x = x + svf(tone, cut, 1.0)
    return x * (p ** 1.8 if up else (1 - p) ** 1.5)


def whoosh(dur=0.45, f0=300, f1=4000, gain=1.0):
    n = int(dur * SR)
    tt = t_(n)
    p = tt / dur
    noise = rng.standard_normal(n)
    cut = f0 * (f1 / f0) ** p
    x = svf(noise, cut, 3.0, 'bp')
    e = np.sin(np.pi * np.clip(p, 0, 1)) ** 2
    return x * e * 0.8 * gain


def impact(gain=1.0, tail=2.2):
    n = int(tail * SR)
    tt = t_(n)
    f = 30 + 70 * np.exp(-tt * 6)
    boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 2.2) * 1.1
    crash = butter(rng.standard_normal(n), 3000, 'high') * np.exp(-tt * 3.0) * 0.35
    crash += butter(rng.standard_normal(n), 900, 'low') * np.exp(-tt * 9) * 0.6
    return np.tanh((boom + crash) * gain)


def blip(f=2400, dur=0.06, gain=1.0):
    n = int(dur * SR)
    tt = t_(n)
    x = np.sin(2 * np.pi * f * tt) * np.exp(-tt * 70) + np.sin(2 * np.pi * f * 1.5 * tt) * 0.3 * np.exp(-tt * 120)
    return x * 0.35 * gain


def key_click():
    n = int(0.03 * SR)
    tt = t_(n)
    x = butter(rng.standard_normal(n), 3000, 'high') * np.exp(-tt * 260)
    x += np.sin(2 * np.pi * (1600 + rng.random() * 500) * tt) * np.exp(-tt * 180) * 0.4
    return x * 0.3


# ---------------------------------------------------------------- arrangement

CHORDS = [  # one per bar (2 s) from T0: Am, F, C, G …
    (57, [57, 60, 64, 69]),   # Am
    (53, [53, 57, 60, 65]),   # F
    (48, [55, 60, 64, 67]),   # C
    (55, [55, 59, 62, 67]),   # G
]


def chord_at(t):
    bar = int((t - T0) // 2.0)
    return CHORDS[bar % 4]


def build(lang, out):
    taps, typing = parse(lang)
    drums, music, fx, verb_send = Bus(), Bus(), Bus(), Bus()

    # Sidechain: the music ducks on every kick.
    duck = np.ones(N)

    def beats(a, b, step=BEAT, offset=0.0):
        t = T0 + offset
        while t < b - 1e-6:
            if t >= a - 1e-6:
                yield round(t, 4)
            t += step

    # --- intro (0–2.4): the constellation, the logo
    l, r = pad([57, 64, 69, 71, 76], 3.2, attack=1.0, cutoff=1400, sub=0.2)
    music.add_st(l, r, 0.0, 1.0)
    for i, (tt, m) in enumerate([(0.32, 88), (0.45, 83), (0.55, 91), (0.66, 86), (0.74, 95), (0.86, 88), (0.95, 93),
                                 (1.05, 81), (1.12, 90), (1.2, 86)]):
        verb_send.add(bell(m, 1.2), tt, 0.35, pan=(i % 5 - 2) / 2.5)
        music.add(bell(m, 1.2), tt, 0.18, pan=(i % 5 - 2) / 2.5)
    verb_send.add(bell(69, 2.5), 1.35, 0.5)
    verb_send.add(bell(76, 2.5), 1.38, 0.35)
    music.add(bell(81, 2.5), 1.4, 0.2)
    fx.add(riser(1.6), 0.8, 0.5)
    fx.add(whoosh(0.5, 200, 3000), 2.05, 0.6)

    # --- big hits on the important cuts
    for at, g in [(2.4, 0.9), (6.9, 1.2), (10.9, 1.0), (22.9, 1.0), (24.9, 1.25)]:
        fx.add(impact(g), at, 0.75)
        verb_send.add(impact(g * 0.6, 1.0), at, 0.25)

    # --- drums
    groove_end = 24.65
    for t in beats(T0, groove_end):
        if 6.15 <= t < 6.9:      # the build before the map: kick drops out
            continue
        if 22.4 <= t < 22.9:
            continue
        drums.add(kick(1.0), t, 0.95)
        i = int(t * SR)
        k = min(N - i, int(0.32 * SR))
        duck[i:i + k] = np.minimum(duck[i:i + k], 1 - 0.55 * np.exp(-t_(k) * 9))
    for t in beats(T0, groove_end, BEAT / 2):
        on = abs(((t - T0) / BEAT) % 1) < 1e-3
        if not on:
            drums.add(hat(True) if t > 6.9 else hat(), t, 0.22 if t > 6.9 else 0.16, pan=0.25)
    for t in beats(6.9, groove_end, BEAT / 4):
        drums.add(hat(), t, 0.07 + 0.05 * (abs(((t - T0) / (BEAT / 2)) % 1) < 1e-3), pan=-0.3)
    for t in beats(6.9, groove_end, BEAT * 2, BEAT):
        if 22.4 <= t < 22.9:
            continue
        drums.add(clap(), t, 0.42)
        verb_send.add(clap(), t, 0.12)
    # snare rolls into the drops
    for start, end in [(5.9, 6.9), (21.9, 22.9)]:
        t = start
        step = 0.125
        while t < end - 0.01:
            p = (t - start) / (end - start)
            drums.add(clap(), t, 0.12 + 0.3 * p)
            t += step if p < 0.5 else step / 2
        fx.add(riser(end - start + 0.05), start, 0.55)
    fx.add(riser(1.0), 9.9, 0.4)
    fx.add(riser(0.9), 24.0, 0.6)

    # --- bass: offbeat 8ths, root of the bar's chord
    for t in beats(T0, groove_end, BEAT / 2):
        on = abs(((t - T0) / BEAT) % 1) < 1e-3
        if on or 6.15 <= t < 6.9 or 22.4 <= t < 22.9:
            continue
        root, _ = chord_at(t)
        music.add(bass(root - 12, 0.22), t, 0.9)

    # --- plucked arpeggio, 16ths, brighter after the map appears
    pattern = [0, 1, 2, 3, 2, 1, 3, 2]
    for j, t in enumerate(beats(T0, groove_end, BEAT / 4)):
        _, notes = chord_at(t)
        idx = pattern[j % 8]
        m = notes[idx] + (12 if (j // 8) % 2 and t > 6.9 else 0)
        bright = 0.5 if t < 6.9 else 1.0
        if 5.4 <= t < 6.9:      # the AI "thinking": faster and higher
            m += 12
        g = 0.55 if t < 6.9 else 0.7
        note = pluck(m, 0.2, bright)
        music.add(note, t, g, pan=0.35 if j % 2 else -0.35)
        verb_send.add(note, t, 0.18)

    # --- wide chords from the map onward, one per bar
    t = 6.4
    while t < 24.4:
        root, notes = chord_at(t + 0.01)
        a = max(t, 6.9)
        dur = (t + 2.0) - a
        if 22.4 <= a < 22.9:
            a, dur = 22.9, 1.5
        l, r = supersaw_chord([n + 12 for n in notes[1:]] + [notes[0]], dur + 0.1, cutoff=3000 if a > 10.9 else 2200)
        music.add_st(l, r, a, 0.9)
        verb_send.add_st(l, r, a, 0.25)
        t += 2.0

    # --- the ending: a resolving chord, bells, a long tail
    l, r = supersaw_chord([60, 64, 67, 72, 76], 4.0, cutoff=2400)
    music.add_st(l * np.linspace(1, 0, len(l)) ** 1.5, r * np.linspace(1, 0, len(r)) ** 1.5, 24.9, 1.0)
    l, r = pad([55, 60, 64, 67, 72], 4.1, attack=0.05, cutoff=2400, sub=0.1)
    music.add_st(l, r, 24.9, 1.2)
    verb_send.add_st(l, r, 24.9, 0.4)
    for i, m in enumerate([72, 76, 79, 84, 88, 91]):
        verb_send.add(bell(m, 2.5), 25.0 + i * 0.09, 0.45, pan=(i - 2.5) / 3)
        music.add(bell(m, 2.5), 25.0 + i * 0.09, 0.2, pan=(i - 2.5) / 3)
    music.add(bass(36, 1.6) * np.exp(-t_(int(1.6 * SR)) * 2.0), 24.9, 0.55)

    # --- interface sounds
    for at in taps:
        fx.add(blip(2300, gain=1.0), at, 0.5)
    start, end, chars = typing
    for i in range(int(chars)):
        at = start + (end - start) * i / max(1, chars - 1)
        fx.add(key_click(), at, 0.55 + 0.25 * rng.random(), pan=rng.uniform(-0.3, 0.3))
    # success chimes: the task done, the card graded
    for at in (taps[5] + 0.05, taps[7] + 0.05):
        music.add(bell(88, 1.2), at, 0.5)
        music.add(bell(95, 1.2), at + 0.08, 0.4)
        verb_send.add(bell(95, 1.2), at + 0.08, 0.3)
    # whooshes on the camera moves
    for at, f0, f1, d, g in [(10.9, 300, 6000, 0.55, 1.0), (13.3, 6000, 400, 0.6, 0.9), (14.72, 400, 5000, 0.4, 0.8),
                             (17.2, 500, 6000, 0.45, 0.9), (19.72, 400, 5000, 0.4, 0.8), (22.7, 300, 5000, 0.5, 0.8),
                             (9.38, 2000, 600, 0.3, 0.4)]:
        fx.add(whoosh(d, f0, f1, g), at, 0.6, pan=0.0)
    for i in range(8):
        fx.add(whoosh(0.25, 800, 7000, 0.5), 10.95 + i * 0.07, 0.35, pan=(i % 2) * 1.2 - 0.6)

    # --- mix
    music.l *= duck
    music.r *= duck
    wl, wr = reverb(verb_send.l, verb_send.r, 2.6)
    L = drums.l * 1.0 + music.l * 1.0 + fx.l * 1.0 + wl * 0.5
    R = drums.r * 1.0 + music.r * 1.0 + fx.r * 1.0 + wr * 0.5
    # tame the low end mud, gentle glue
    L = butter(L, 28, 'high')
    R = butter(R, 28, 'high')
    st = np.stack([L, R], 1)
    st /= np.max(np.abs(st)) + 1e-9
    st = np.tanh(st * 1.6) / np.tanh(1.6)
    # fades
    n_in = int(0.02 * SR)
    st[:n_in] *= np.linspace(0, 1, n_in)[:, None]
    fade_from = int(27.6 * SR)
    fade_to = int(TOTAL * SR)
    st[fade_from:fade_to] *= np.linspace(1, 0, fade_to - fade_from)[:, None] ** 1.3
    st[fade_to:] = 0
    st = st[: int(TOTAL * SR)]
    st *= 0.89
    pcm = (st * 32767).astype(np.int16)
    import wave
    with wave.open(str(out), 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


if __name__ == '__main__':
    build(sys.argv[1], Path(sys.argv[2]))
