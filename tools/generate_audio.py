#!/usr/bin/env python3
"""Reproduce original C-style music + A-style effects approved in the auditions.
Requires NumPy and ffmpeg. No reference recording is sampled.
"""
from pathlib import Path
import math
import subprocess
import wave
import tempfile

import numpy as np

OUT = Path(__file__).resolve().parents[1] / 'audio'
SR = 44100
RNG = np.random.default_rng(260926)


def hz(note):
    return 440 * 2 ** ((note - 69) / 12)


def noise(seconds, lo, hi):
    n = int(SR * seconds)
    x = RNG.normal(size=n)
    spectrum = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    envelope = np.exp(-(f / hi) ** 6) * (1 - np.exp(-(f / lo) ** 4))
    x = np.fft.irfft(spectrum * envelope, n)
    return x / max(np.std(x), 0.001)


def normalize(x, peak=0.8):
    return x * peak / max(np.max(np.abs(x)), 0.001)


def tone(note, seconds=0.8, kind='pluck'):
    t = np.arange(int(seconds * SR)) / SR
    f = hz(note)
    x = np.zeros(len(t))
    if kind == 'pluck':
        for k in range(1, 13):
            x += (np.cos(2 * np.pi * f * k * t) + 0.16 * np.cos(2 * np.pi * f * k * 1.0012 * t)) * np.exp(-(3.0 + k * 0.63) * t) / k ** 1.45
        x += noise(seconds, 650, 3600) * 0.09 * np.exp(-t * 140)
        x *= 1 - np.exp(-t * 1100)
    elif kind == 'mallet':
        for ratio, amp, decay in [(1, 1, 4), (2.76, .34, 14), (5.4, .15, 24), (8.1, .05, 40)]:
            x += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t * decay)
        x *= 1 - np.exp(-t * 750)
    elif kind == 'soft':
        for ratio, amp, decay in [(1, 1, 2.8), (2, .23, 5), (3, .13, 7), (4, .035, 12)]:
            x += amp * np.sin(2 * np.pi * f * ratio * t + .14 * np.sin(2 * np.pi * f * t) * np.exp(-t * 5)) * np.exp(-t * decay)
        x *= 1 - np.exp(-t * 100)
    else:
        x = (np.sin(2 * np.pi * f * t) + .32 * np.sin(2 * np.pi * f * 2 * t) + .12 * np.sin(2 * np.pi * f * 3 * t)) * np.exp(-t * 4)
        x *= 1 - np.exp(-t * 180)
    x *= np.minimum(1, (seconds - t) / .04)
    return normalize(x)


def wood(pitch=1.0, bright=1.0):
    d = .18
    t = np.arange(int(SR * d)) / SR
    x = sum(a * np.sin(2 * np.pi * f * pitch * t) * np.exp(-t * r) for f, a, r in [(440, 1, 45), (1063, .65, 75), (2214, .22 * bright, 110)])
    x += noise(d, 1400, 6000) * .17 * bright * np.exp(-t * 200)
    x *= 1 - np.exp(-t * 2400)
    return normalize(x)


def ceramic(pitch=1.0, bright=1.0):
    d = .50
    t = np.arange(int(SR * d)) / SR
    x = sum(a * np.sin(2 * np.pi * f * pitch * t) * np.exp(-t * r) for f, a, r in [(760, 1, 17), (1288, .57, 23), (2057, .26 * bright, 32), (3130, .08 * bright, 50)])
    x += noise(d, 1800, 6500) * .12 * np.exp(-t * 180)
    x *= 1 - np.exp(-t * 1700)
    return normalize(x)


def swoosh(d=.22):
    t = np.arange(int(SR * d)) / SR
    return normalize(noise(d, 350, 3600) * np.sin(np.pi * t / d) ** 2.2, .65)


def sizzle(d=.43):
    t = np.arange(int(SR * d)) / SR
    env = (1 - np.exp(-t * 180)) * np.exp(-t * 11)
    flutter = .8 + .2 * np.sin(2 * np.pi * 47 * t) ** 2
    return normalize(noise(d, 1300, 7200) * env * flutter, .7)


def kick():
    t = np.arange(int(SR * .22)) / SR
    phase = 2 * np.pi * (58 * t + 28 * .02 * (1 - np.exp(-t / .02)))
    return normalize(np.sin(phase) * np.exp(-t * 24) * (1 - np.exp(-t * 1200)))


def shaker():
    d = .075
    t = np.arange(int(SR * d)) / SR
    return normalize(noise(d, 2800, 7500) * np.exp(-t * 60) * (1 - np.exp(-t * 1100)))


def place(bus, signal, when, gain=1, pan=0):
    start = round(when * SR)
    end = min(start + len(signal), len(bus))
    if end <= start:
        return
    gains = np.array([math.cos((pan + 1) * np.pi / 4), math.sin((pan + 1) * np.pi / 4)])
    bus[start:end] += signal[:end-start, None] * gains * gain


def room(bus, wet=.13):
    out = bus.copy()
    for delay, gain in [(.027, .75), (.053, .6), (.089, .38), (.151, .20), (.231, .10)]:
        n = int(delay * SR)
        out[n:] += bus[:-n, ::-1] * gain * wet
    return out


def write_wav(path, x):
    peak = float(np.max(np.abs(x)))
    assert peak < 1.0, (path.name, peak)
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype('<i2').tobytes())


MELODIES = [
    [(0, 74), (.75, 78), (1.5, 81), (2.5, 78), (3.25, 76)],
    [(.25, 78), (1, 76), (2, 74), (3, 71)],
    [(0, 71), (.75, 74), (1.5, 78), (2.75, 81), (3.5, 78)],
    [(0, 76), (1.25, 74), (2, 71), (3, 69)],
    [(0, 74), (.5, 76), (1.5, 78), (2.5, 81), (3.25, 83)],
    [(.25, 81), (1, 78), (2.25, 76), (3, 74)],
    [(0, 71), (1, 74), (1.75, 76), (2.5, 78)],
    [(0, 76), (1, 71), (2, 74)],
]
CHORDS = [[50, 57, 62, 66], [47, 54, 59, 62], [43, 50, 55, 59], [45, 52, 57, 61]]


def render_music():
    # Render three identical cycles and retain the middle one, including room
    # tails across its boundary. No fade-to-silence gap at the looping seam.
    beat = 60 / 92
    frames = round(16 * 4 * beat * SR)
    cycle = np.zeros((frames, 2))
    for bar in range(16):
        base = bar * 4 * beat
        chord = CHORDS[bar % 4]
        for position, note in MELODIES[bar % 8]:
            place(cycle, tone(note - 5, 1.15, 'soft'), base + position * beat, .24 * RNG.uniform(.87, 1), -.19)
        for j, note in enumerate(chord[1:]):
            place(cycle, tone(note + 7, 1.6, 'soft'), base + j * .026, .075, .3)
            place(cycle, tone(note + 7, .75, 'pluck'), base + (2 + j * .25) * beat, .045, .4)
        for position, note in [(0, chord[0] - 17), (2, chord[0] - 10)]:
            place(cycle, tone(note, .7, 'bass'), base + position * beat, .18)
            place(cycle, kick(), base + position * beat, .075 * .55)
        for position in [1, 3]:
            place(cycle, wood(.53, .4), base + position * beat, .052 * .55, .13)
        for tick in range(8):
            place(cycle, shaker(), base + (tick * .5 + (.025 if tick % 2 else 0)) * beat,
                  (.02 if tick % 2 else .013) * .55, -.28 if tick % 2 else .28)
    # Last notes end before the bar line; only the room reflections cross it.
    loop = room(np.tile(cycle, (3, 1)), .19)[frames:frames * 2]
    loop *= .068 / np.sqrt(np.mean(loop ** 2))
    for when in [1.5, 4.6, 8.5, 12.2, 16.0, 22.5, 27.0, 32.1, 37.0]:
        place(loop, sizzle(), when, .014, .25)
    return loop


def clip(seconds, layers):
    bus = np.zeros((round(seconds * SR), 2))
    for signal, when, gain in layers:
        place(bus, signal, when, gain)
    return room(bus, .10)


def render_effects():
    # Match impact is a separate clip: gameplay schedules it at the plate pop.
    pitch, bright = .96, .85
    sounds = {
        'pick': clip(.24, [(wood(1.05 * pitch, bright), 0, .21)]),
        'move': clip(.21, [(swoosh(.16), 0, .08)]),
        'drop': clip(.24, [(wood(.77 * pitch, bright), 0, .24)]),
        'swap': clip(.28, [(wood(.77 * pitch, bright), 0, .18), (wood(.86 * pitch, bright), .04, .15)]),
        'cancel': clip(.24, [(wood(.64 * pitch, .5), 0, .15)]),
        'gather': clip(.29, [(swoosh(.24), 0, .14)]),
        'match': clip(.75, [(sizzle(), 0, .20), (wood(.47 * pitch, .5), 0, .16),
                              (ceramic(pitch, bright), .01, .39),
                              (tone(78, .34, 'mallet'), .06, .10), (tone(81, .34, 'mallet'), .115, .10)]),
        'refill': clip(.24, [(wood(.72 * pitch, .65), 0, .10)]),
        'combo': clip(1.0, [(tone(note, .65, 'mallet'), j * .075, .19)
                              for j, note in enumerate([74, 78, 81, 86])]),
        'warning': clip(.22, [(wood(1.2, .45), 0, .12)]),
        'win': clip(1.25, [(tone(note, .8, 'soft'), j * .095, .20)
                            for j, note in enumerate([69, 73, 76, 81])]),
        'fail': clip(.85, [(tone(64, .7, 'soft'), 0, .17), (tone(62, .65, 'soft'), .15, .15)]),
    }
    return sounds


def main():
    OUT.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='bbq-audio-') as temporary:
        source = Path(temporary) / 'source.wav'
        write_wav(source, render_music())
        subprocess.run(['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-i', str(source),
                        '-ar', '22050', '-c:a', 'libvorbis', '-q:a', '3', str(OUT / 'night_market.ogg')], check=True)
        for name, signal in render_effects().items():
            write_wav(source, signal)
            subprocess.run(['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-i', str(source),
                            '-ar', '22050', '-ac', '1', '-c:a', 'pcm_s16le', str(OUT / f'{name}.wav')], check=True)
    print('Generated 41.74-second looping music and 12 original effects in', OUT)


if __name__ == '__main__':
    main()
