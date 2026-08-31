#!/usr/bin/env python3
"""Procedural audio generator for Trainer Manager (audio piece).

Synthesizes every sound in res://assets/audio/ from scratch — 100% original
procedural material, no samples, no copyrighted or Pokémon-imitating content.

    python3 tools/gen_audio.py            # (re)generate all WAVs
    python3 tools/gen_audio.py --analyze  # also write artifacts/audio/analysis.{txt,json}

Deterministic: fixed RNG seed, same output every run.
"""
import json
import math
import os
import sys
import wave

import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio")
ART = os.path.join(ROOT, "artifacts", "audio")
RNG = np.random.default_rng(20260830)

# ---------------------------------------------------------------- primitives


def t(dur):
    return np.arange(int(dur * SR)) / SR


def sine(freq, dur, phase=0.0):
    return np.sin(2 * np.pi * freq * t(dur) + phase)


def sweep(f0, f1, dur, curve=1.0):
    """Sine with exponential-ish pitch glide f0 -> f1."""
    tt = t(dur)
    k = (tt / dur) ** curve
    freq = f0 * (f1 / f0) ** k
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase)


def square(freq, dur, duty=0.5):
    tt = t(dur)
    return np.where((tt * freq) % 1.0 < duty, 1.0, -1.0) * 0.7


def saw(freq, dur):
    tt = t(dur)
    return ((tt * freq) % 1.0) * 2.0 - 1.0


def tri(freq, dur):
    tt = t(dur)
    return 2.0 * np.abs(2.0 * ((tt * freq) % 1.0) - 1.0) - 1.0


def noise(dur):
    return RNG.standard_normal(int(dur * SR)) * 0.5


def lowpass(x, cutoff):
    """One-pole lowpass (vectorized via scipy when present)."""
    a = 1.0 - math.exp(-2.0 * math.pi * cutoff / SR)
    try:
        from scipy.signal import lfilter

        return lfilter([a], [1.0, -(1.0 - a)], x)
    except ImportError:
        y = np.empty_like(x)
        acc = 0.0
        for i in range(len(x)):
            acc += a * (x[i] - acc)
            y[i] = acc
        return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bandpass(x, lo, hi):
    return lowpass(highpass(x, lo), hi)


def env_ad(x, attack, decay, curve=3.0):
    """Attack/decay envelope over the whole buffer."""
    n = len(x)
    e = np.ones(n)
    na = max(1, int(attack * SR))
    e[:na] = np.linspace(0, 1, na)
    nd = n - na
    if nd > 0:
        e[na:] = np.exp(-curve * np.linspace(0, 1, nd) * (n / SR) / max(decay, 1e-4))
    return x * e


def env_shape(x, points):
    """Piecewise-linear envelope: points = [(time_frac, gain), ...]."""
    n = len(x)
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    e = np.interp(np.linspace(0, 1, n), xs, ys)
    return x * e


def normalize(x, peak=0.9):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 1e-9 else x


def soft_clip(x, drive=1.0):
    return np.tanh(x * drive)


def write_wav(name, data, peak=0.85):
    """data: mono ndarray or (left, right) tuple. 16-bit PCM."""
    os.makedirs(OUT, exist_ok=True)
    if isinstance(data, tuple):
        l, r = data
        m = max(np.max(np.abs(l)), np.max(np.abs(r)), 1e-9)
        l, r = l * (peak / m), r * (peak / m)
        inter = np.empty(len(l) * 2)
        inter[0::2], inter[1::2] = l, r
        pcm, ch = (inter * 32767).astype(np.int16), 2
    else:
        pcm, ch = (normalize(data, peak) * 32767).astype(np.int16), 1
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("  wrote %-24s %5.2fs %s" % (name + ".wav", len(pcm) / ch / SR, "stereo" if ch == 2 else "mono"))


def pad(x, dur):
    """Zero-pad tail to at least dur seconds."""
    need = int(dur * SR) - len(x)
    return np.concatenate([x, np.zeros(need)]) if need > 0 else x


def mix(*parts):
    """Sum arrays of different lengths."""
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def delay_into(x, seconds, gain=1.0, total=None):
    off = int(seconds * SR)
    n = max(len(x) + off, int((total or 0) * SR))
    out = np.zeros(n)
    out[off : off + len(x)] += x * gain
    return out


# ---------------------------------------------------------------- UI sounds


def build_ui():
    # click: tight noise tick + 1.6k ping, FM-crisp
    click = mix(
        env_ad(highpass(noise(0.03), 2500), 0.001, 0.012),
        env_ad(sine(1600, 0.05), 0.001, 0.02) * 0.5,
    )
    write_wav("ui_click", click, 0.55)

    # hover: barely-there soft tick
    hover = env_ad(lowpass(highpass(noise(0.025), 1800), 6000), 0.002, 0.010)
    write_wav("ui_hover", hover, 0.22)

    # confirm: two-note rising chime (E5 -> B5), gentle triangle body
    confirm = mix(
        env_ad(sine(659.3, 0.16) + 0.4 * sine(1318.5, 0.16), 0.002, 0.07),
        delay_into(env_ad(sine(987.8, 0.22) + 0.35 * sine(1975.5, 0.22), 0.002, 0.10), 0.085),
    )
    write_wav("ui_confirm", confirm, 0.5)

    # error: two-note falling buzz (A3 -> E3), softened square
    err = mix(
        env_ad(lowpass(square(220, 0.12), 1400), 0.003, 0.06),
        delay_into(env_ad(lowpass(square(164.8, 0.16), 1200), 0.003, 0.08), 0.10),
    )
    write_wav("ui_error", err, 0.5)

    # mail: bell ding — inharmonic partials, medium decay
    mail = env_ad(
        sine(1174.7, 0.5) + 0.5 * sine(1760, 0.5) + 0.3 * sine(2650, 0.5) + 0.2 * sine(880, 0.5),
        0.002,
        0.16,
    )
    write_wav("ui_mail", mail, 0.42)

    # continue: rising filtered-noise whoosh with a soft landing tick
    wl = 0.42
    wh = noise(wl)
    tt = np.linspace(0, 1, len(wh))
    swept = bandpass(wh, 300, 900) * (1 - tt) + bandpass(wh, 900, 4000) * tt
    whoosh = env_shape(swept, [(0, 0), (0.55, 1.0), (0.85, 0.5), (1, 0)])
    land = delay_into(env_ad(sine(880, 0.07), 0.001, 0.03) * 0.5, wl * 0.8)
    write_wav("ui_continue", mix(whoosh, land), 0.6)

    # back: single short low tick
    back = mix(
        env_ad(highpass(noise(0.03), 1500), 0.001, 0.012) * 0.8,
        env_ad(sine(740, 0.05), 0.001, 0.02) * 0.45,
    )
    write_wav("ui_back", back, 0.45)


# ---------------------------------------------------------------- match SFX


def build_match_sfx():
    # physical hit: low thump + noise crack
    thump = env_ad(sweep(160, 55, 0.16, 0.7), 0.001, 0.07)
    crack = env_ad(bandpass(noise(0.06), 900, 5000), 0.001, 0.02)
    write_wav("hit_phys", mix(thump, crack * 0.8), 0.8)

    # special variants by type family
    zap = env_ad(soft_clip(saw(70, 0.22) * sine(2400, 0.22), 2.5) + 0.4 * bandpass(noise(0.22), 2000, 8000), 0.001, 0.09)
    write_wav("hit_zap", zap, 0.7)

    splash = mix(
        env_ad(bandpass(noise(0.30), 400, 2500), 0.004, 0.10),
        env_ad(bandpass(noise(0.30), 4000, 9000), 0.02, 0.14) * 0.5,
        env_ad(sweep(600, 200, 0.12), 0.002, 0.06) * 0.4,
    )
    write_wav("hit_splash", splash, 0.7)

    flame = env_shape(
        lowpass(noise(0.35), 1800) + 0.5 * lowpass(noise(0.35) ** 3 * 3, 400),
        [(0, 0), (0.12, 1), (0.7, 0.6), (1, 0)],
    )
    write_wav("hit_flame", flame, 0.7)

    wl = 0.26
    wh = bandpass(noise(wl), 700, 3500)
    swoosh = env_shape(wh, [(0, 0), (0.4, 1), (1, 0)])
    write_wav("hit_whoosh", mix(swoosh, env_ad(sine(520, 0.08), 0.001, 0.04) * 0.3), 0.7)

    burst = mix(
        env_ad(sweep(900, 250, 0.14, 0.8), 0.001, 0.06),
        env_ad(bandpass(noise(0.12), 1200, 6000), 0.001, 0.05) * 0.7,
    )
    write_wav("hit_burst", burst, 0.7)

    # super-effective crunch: heavier layered impact, slight distortion
    superhit = soft_clip(
        mix(
            env_ad(sweep(200, 40, 0.28, 0.6), 0.001, 0.12) * 1.4,
            env_ad(bandpass(noise(0.12), 500, 6000), 0.001, 0.04) * 1.2,
            delay_into(env_ad(bandpass(noise(0.08), 800, 5000), 0.001, 0.03), 0.05, 0.8),
        ),
        1.8,
    )
    write_wav("hit_super", superhit, 0.9)

    # not-very-effective: dull padded thud
    weak = env_ad(lowpass(mix(sweep(140, 70, 0.12), noise(0.06) * 0.4), 500), 0.002, 0.06)
    write_wav("hit_weak", weak, 0.55)

    # miss: airy whiff
    whiff = env_shape(bandpass(noise(0.22), 1500, 6000), [(0, 0), (0.35, 0.9), (1, 0)])
    write_wav("miss", whiff, 0.45)

    # faint: descending two-oscillator tone with vibrato
    dur = 0.7
    vib = 1.0 + 0.02 * sine(9, dur)
    base = sweep(540, 130, dur, 1.2)
    fifth = sweep(810, 195, dur, 1.2)
    faint = env_shape((base + 0.5 * fifth) * vib, [(0, 0), (0.06, 1), (0.8, 0.5), (1, 0)])
    write_wav("faint", lowpass(faint, 3000), 0.75)

    # switch: double swish (out then in)
    s1 = env_shape(bandpass(noise(0.16), 900, 5000), [(0, 0), (0.3, 1), (1, 0)])
    s2 = env_shape(bandpass(noise(0.16), 600, 3000), [(0, 0), (0.3, 1), (1, 0)])
    write_wav("switch", mix(s1, delay_into(s2, 0.13)), 0.6)

    # item pop: pitch-drop pop + sparkle
    pop = env_ad(sweep(950, 320, 0.08, 0.9), 0.001, 0.035)
    spark = delay_into(env_ad(sine(2093, 0.10) + 0.5 * sine(3136, 0.10), 0.001, 0.045) * 0.5, 0.06)
    write_wav("item", mix(pop, spark), 0.6)

    # status applied: queasy downward wobble
    dur = 0.30
    wob = sine(300, dur, 0) * (1 + 0.4 * sine(22, dur))
    write_wav("status", env_shape(lowpass(wob, 1500), [(0, 0), (0.15, 1), (1, 0)]), 0.55)

    # stat up / down: 3-note arpeggio blips
    def arp(freqs):
        parts = []
        for i, f in enumerate(freqs):
            parts.append(delay_into(env_ad(tri(f, 0.09) + 0.3 * sine(f * 2, 0.09), 0.002, 0.05), i * 0.055))
        return mix(*parts)

    write_wav("stat_up", arp([523.3, 659.3, 784.0]), 0.5)
    write_wav("stat_down", arp([784.0, 659.3, 523.3]), 0.5)

    # heal: soft ascending shimmer
    heal = mix(
        env_ad(sine(1046.5, 0.3), 0.02, 0.14) * 0.7,
        delay_into(env_ad(sine(1318.5, 0.3), 0.02, 0.16) * 0.6, 0.09),
        delay_into(env_ad(sine(1568.0, 0.32), 0.02, 0.18) * 0.5, 0.18),
    )
    write_wav("heal", heal, 0.5)

    # weather gust: broad wind swell
    g = lowpass(noise(1.1), 900)
    tt = t(1.1)
    g *= 1 + 0.35 * np.sin(2 * np.pi * 2.3 * tt)
    write_wav("weather", env_shape(g, [(0, 0), (0.3, 1), (0.75, 0.7), (1, 0)]), 0.55)


# ---------------------------------------------------------------- crowd


def crowd_bed(dur, lo=180, hi=1200):
    """Murmuring-crowd texture: layered band noise with slow independent LFOs."""
    n = int(dur * SR)
    out = np.zeros(n)
    for i, (a, b) in enumerate([(lo, lo * 2.2), (lo * 1.8, hi * 0.7), (hi * 0.5, hi)]):
        layer = bandpass(RNG.standard_normal(n) * 0.5, a, b)
        lfo = 1 + 0.30 * np.sin(2 * np.pi * (0.13 + 0.11 * i) * t(dur) + i * 2.1)
        out += layer * lfo * (1.0 - 0.25 * i)
    return out


def build_crowd():
    # roar: big swell, wide band, ragged tail
    dur = 1.9
    roar = crowd_bed(dur, 250, 2600)
    roar += bandpass(noise(dur), 1200, 5000) * env_shape(np.ones(int(dur * SR)), [(0, 0.2), (0.35, 1), (1, 0.1)]) * 0.5
    write_wav("crowd_roar", env_shape(roar, [(0, 0.05), (0.22, 1.0), (0.6, 0.8), (1, 0)]), 0.8)

    # gasp: fast inhale-like swell, cut short
    dur = 0.85
    gasp = bandpass(noise(dur), 500, 3500)
    write_wav("crowd_gasp", env_shape(gasp, [(0, 0), (0.30, 1.0), (0.45, 0.35), (1, 0)]), 0.6)

    # cheer: roar + rhythmic clap transients
    dur = 2.3
    cheer = crowd_bed(dur, 300, 3000) * 0.9
    claps = np.zeros(int(dur * SR))
    for beat in np.arange(0.15, dur - 0.2, 0.145):
        for _ in range(5):
            off = int((beat + RNG.uniform(-0.03, 0.03)) * SR)
            c = env_ad(bandpass(RNG.standard_normal(int(0.03 * SR)) * 0.5, 1500, 6000), 0.001, 0.012)
            claps[off : off + len(c)] += c * RNG.uniform(0.4, 1.0)
    write_wav("crowd_cheer", env_shape(mix(cheer, claps * 0.8), [(0, 0.1), (0.2, 1), (0.85, 0.7), (1, 0)]), 0.8)

    # chant loop: rhythmic two-note crowd pulse, seamless 4-beat loop
    bpm, beats = 126.0, 8
    dur = beats * 60.0 / bpm
    n = int(dur * SR)
    chant = np.zeros(n)
    pattern = [392, 392, 330, 0, 392, 392, 330, 330]  # short original motif
    for b, f in enumerate(pattern):
        if f == 0:
            continue
        seg = env_ad(
            lowpass(saw(f, 0.30), 900) + lowpass(RNG.standard_normal(int(0.30 * SR)) * 0.35, 1200),
            0.03,
            0.22,
        )
        off = int(b * 60.0 / bpm * SR)
        chant[off : min(off + len(seg), n)] += seg[: n - off]
    chant += crowd_bed(dur, 200, 1400) * 0.35
    write_wav("crowd_chant", chant, 0.55)  # looped by AudioManager

    # ambient stadium bed: 8s seamless stereo murmur
    dur = 8.0
    left = crowd_bed(dur, 150, 1500)
    right = crowd_bed(dur, 150, 1500)
    # cross-blend ends for a seamless loop
    fade = int(0.5 * SR)
    for ch in (left, right):
        ch[:fade] = ch[:fade] * np.linspace(0, 1, fade) + ch[-fade:] * np.linspace(1, 0, fade)
    left, right = left[:-fade], right[:-fade]
    mid = (left + right) * 0.35
    write_wav("ambience_stadium", (left * 0.8 + mid, right * 0.8 + mid), 0.5)


# ---------------------------------------------------------------- music
# Tiny chiptune sequencer. All progressions/motifs written for this project.


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


def place(buf, off, seg):
    """Add seg into buf at off, wrapping past the end (seamless loops)."""
    n = len(buf)
    off %= n
    end = off + len(seg)
    if end <= n:
        buf[off:end] += seg
    else:
        buf[off:] += seg[: n - off]
        buf[: end - n] += seg[n - off :]


def pad_note(root, dur):
    """Soft detuned pad voice."""
    v = (
        lowpass(saw(midi(root), dur) + saw(midi(root) * 1.003, dur), 1100)
        + 0.6 * tri(midi(root + 12), dur)
    )
    return env_shape(v, [(0, 0), (0.08, 1), (0.85, 0.8), (1, 0)])


def pluck(note, dur):
    v = square(midi(note), dur, 0.35) + 0.4 * sine(midi(note) * 2, dur)
    return env_ad(lowpass(v, 3200), 0.003, dur * 0.5)


def bass_note(note, dur):
    return env_ad(tri(midi(note), dur) + 0.5 * sine(midi(note), dur), 0.004, dur * 0.8)


def hat(dur=0.05):
    return env_ad(highpass(RNG.standard_normal(int(dur * SR)) * 0.5, 6000), 0.001, 0.018)


def kick():
    return env_ad(sweep(120, 45, 0.12, 0.7), 0.001, 0.06)


def render_track(name, bpm, bars, chords, melody, drums=False, pad_gain=0.5, mel_gain=0.4):
    """chords: list of (root_midi, [intervals]) one per bar (cycled).
    melody: list of (bar, beat, note_midi, beats_len) events, cycled over the loop."""
    beat = 60.0 / bpm
    dur = bars * 4 * beat
    n = int(dur * SR)
    L, R = np.zeros(n), np.zeros(n)
    for bar in range(bars):
        root, ivs = chords[bar % len(chords)]
        off = int(bar * 4 * beat * SR)
        for k, iv in enumerate(ivs):
            v = pad_note(root + iv, 4 * beat) * pad_gain * (0.9 if k else 1.0)
            place(L if k % 2 == 0 else R, off, v)
            place(R if k % 2 == 0 else L, off, v * 0.55)
        # bass: root on 1 and 3, fifth on 4-and
        for bt, nt in [(0, root - 12), (2, root - 12), (3.5, root - 5)]:
            b = bass_note(nt, beat * 0.9) * 0.6
            place(L, off + int(bt * beat * SR), b)
            place(R, off + int(bt * beat * SR), b)
        if drums:
            for bt in [0, 2]:
                d = kick() * 0.7
                place(L, off + int(bt * beat * SR), d)
                place(R, off + int(bt * beat * SR), d)
            for h8 in range(8):
                hh = hat() * (0.30 if h8 % 2 else 0.16)
                place(L, off + int(h8 * 0.5 * beat * SR), hh)
                place(R, off + int((h8 * 0.5 + 0.02) * beat * SR), hh)
    for bar, bt, nt, ln in melody:
        seg = pluck(nt, ln * beat) * mel_gain
        off = int((bar * 4 + bt) * beat * SR)
        place(L, off, seg * 0.8)
        place(R, off + int(0.012 * SR), seg * 0.6)
    L, R = soft_clip(L, 0.9), soft_clip(R, 0.9)
    write_wav(name, (L, R), 0.55)


def build_music():
    # menu A — wistful, Am F C G at 88 BPM (8 bars ~ 21.8s)
    Am, F, C, G = (57, [0, 3, 7]), (53, [0, 4, 7]), (48, [0, 4, 7, 12]), (55, [0, 4, 7])
    mel_a = [
        (0, 0, 76, 1.5), (0, 2, 72, 1.0), (1, 0, 74, 2.0), (1, 3, 69, 1.0),
        (2, 0, 72, 1.5), (2, 2, 76, 1.0), (3, 0, 74, 3.0),
        (4, 0, 77, 1.5), (4, 2, 76, 1.0), (5, 0, 72, 2.0), (5, 3, 74, 1.0),
        (6, 0, 76, 1.0), (6, 1.5, 74, 1.0), (6, 3, 72, 1.0), (7, 0, 71, 3.0),
    ]
    render_track("music_menu_a", 88, 8, [Am, F, C, G, Am, F, G, G], mel_a)

    # menu B — warmer, Dm Bb F C at 82 BPM, sparser melody
    Dm, Bb, F2, C2 = (50, [0, 3, 7]), (46, [0, 4, 7]), (53, [0, 4, 7]), (48, [0, 4, 7])
    mel_b = [
        (0, 1, 74, 2.0), (1, 0, 77, 1.5), (1, 2.5, 74, 1.0), (2, 0, 72, 2.5),
        (3, 0, 69, 1.0), (3, 2, 72, 1.5), (4, 1, 74, 2.0), (5, 0, 70, 2.0),
        (6, 0, 72, 1.5), (6, 2, 76, 1.5), (7, 0, 72, 3.5),
    ]
    render_track("music_menu_b", 82, 8, [Dm, Bb, F2, C2, Dm, Bb, C2, C2], mel_b, mel_gain=0.34)

    # matchday — driving, Em C G D at 112 BPM with drums
    Em, C3, G3, D3 = (52, [0, 3, 7]), (48, [0, 4, 7]), (55, [0, 4, 7]), (50, [0, 4, 7]),
    mel_m = [
        (0, 0, 79, 0.75), (0, 1, 79, 0.75), (0, 2, 83, 1.5),
        (1, 0, 84, 1.0), (1, 2, 83, 1.0), (1, 3, 79, 1.0),
        (2, 0, 81, 1.5), (2, 2, 79, 1.0), (3, 0, 78, 2.5),
        (4, 0, 79, 0.75), (4, 1, 83, 0.75), (4, 2, 86, 1.5),
        (5, 0, 84, 1.0), (5, 2, 83, 1.0), (6, 0, 81, 1.5), (6, 2, 84, 1.0),
        (7, 0, 79, 3.0),
    ]
    render_track("music_matchday", 112, 8, [Em, C3, G3, D3, Em, C3, D3, D3], mel_m,
                 drums=True, pad_gain=0.42, mel_gain=0.38)


# ---------------------------------------------------------------- analysis


def analyze():
    os.makedirs(ART, exist_ok=True)
    rows = []
    for fn in sorted(os.listdir(OUT)):
        if not fn.endswith(".wav"):
            continue
        with wave.open(os.path.join(OUT, fn), "rb") as w:
            ch, sr, nf = w.getnchannels(), w.getframerate(), w.getnframes()
            data = np.frombuffer(w.readframes(nf), dtype=np.int16).astype(np.float64) / 32767.0
        dur = nf / sr
        peak = float(np.max(np.abs(data))) if len(data) else 0.0
        rms = float(np.sqrt(np.mean(data**2))) if len(data) else 0.0
        # non-silence: fraction of 50ms windows above -60 dBFS RMS
        win = int(0.05 * sr) * ch
        wins = [data[i : i + win] for i in range(0, len(data) - win + 1, win)] or [data]
        active = sum(1 for wd in wins if np.sqrt(np.mean(wd**2)) > 10 ** (-60 / 20)) / len(wins)
        rows.append({
            "file": fn, "channels": ch, "sample_rate": sr, "duration_s": round(dur, 3),
            "peak_dbfs": round(20 * math.log10(max(peak, 1e-9)), 1),
            "rms_dbfs": round(20 * math.log10(max(rms, 1e-9)), 1),
            "nonsilent_frac": round(active, 3),
        })
    with open(os.path.join(ART, "analysis.json"), "w") as f:
        json.dump(rows, f, indent=1)
    lines = ["%-24s %2sch %6ss  peak %7s dB  rms %7s dB  active %5s" % (
        r["file"], r["channels"], r["duration_s"], r["peak_dbfs"], r["rms_dbfs"], r["nonsilent_frac"]) for r in rows]
    ok = all(r["nonsilent_frac"] > 0.5 and -40 < r["peak_dbfs"] <= 0 for r in rows)
    lines.append("")
    lines.append("ALL FILES NON-SILENT, SANE LEVELS: %s" % ("YES" if ok else "NO"))
    with open(os.path.join(ART, "analysis.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    return ok


def main():
    print("Generating procedural audio -> %s" % OUT)
    build_ui()
    build_match_sfx()
    build_crowd()
    build_music()
    if "--analyze" in sys.argv:
        if not analyze():
            sys.exit(1)
    print("GEN AUDIO OK")


if __name__ == "__main__":
    main()
