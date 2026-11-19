#!/usr/bin/env python3
"""Sons da serra de pedal.

 - serra_corte: uma passada da lâmina de pedra dentada na madeira (a cada descida do
   pedal): o raspar áspero dos dentes (zumbido de ruído pulsando na frequência dos
   dentes, ~180 a 260 por segundo), o corpo grave da tora vibrando e o serragem
   chiando no fim.
 - pedal_range: o pedal de tábua descendo no eixo de madeira: o rangido seco da
   dobradiça (chiado tonal subindo) e a batida surda da tábua no fim do curso.
Uso: python3 tools/sintetizar_serra_pedal.py
"""
import os
import subprocess
import tempfile
import wave

import numpy as np
from scipy.signal import butter, lfilter

SR = 32000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'sons')


def band(x, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), min(hi / (SR / 2), 0.99)], btype='band')
    return lfilter(b, a, x)


def low(x, hi, order=2):
    b, a = butter(order, hi / (SR / 2), btype='low')
    return lfilter(b, a, x)


def save(name, s, peak_db=-3.0):
    s = s / (np.abs(s).max() + 1e-9) * 10 ** (peak_db / 20)
    s = np.concatenate([s, np.zeros(int(0.03 * SR))])
    tmp = tempfile.NamedTemporaryFile(suffix='.wav', delete=False)
    with wave.open(tmp.name, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(s, -1, 1) * 32767).astype('<i2').tobytes())
    out = os.path.join(OUT, name + '.somog')
    subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-y', '-i', tmp.name, '-c:a', 'libvorbis', '-q:a', '4', '-f', 'ogg', out], check=True)
    os.unlink(tmp.name)
    print(name, os.path.getsize(out), 'bytes')


def corte(seed, dur=0.42):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    env = np.sin(np.clip(t / dur, 0, 1) * np.pi) ** 0.7
    tooth = rng.uniform(180, 260) * (1.0 + 0.15 * np.sin(t * 9.0))
    ph = np.cumsum(2 * np.pi * tooth / SR)
    pulse = (0.5 + 0.5 * np.sin(ph)) ** 4                      # cada dente pegando na fibra
    noise = rng.normal(0, 1, n)
    rasp = band(noise, 900, 4200) * (0.35 + pulse) + band(noise, 3000, 8000) * 0.25 * pulse
    body = band(rng.normal(0, 1, n), 120, 450) * (0.3 + 0.7 * pulse) * 0.6   # a tora vibrando
    dust = band(rng.normal(0, 1, n), 5000, 11000) * np.clip((t - dur * 0.5) / (dur * 0.5), 0, 1) * 0.25
    return (rasp + body + dust) * env


def pedal(seed):
    rng = np.random.default_rng(seed)
    L = int(0.32 * SR)
    t = np.arange(L) / SR
    f = np.linspace(rng.uniform(520, 700), rng.uniform(800, 1100), L)
    squeak = np.sin(np.cumsum(2 * np.pi * f / SR)) * (0.5 + 0.5 * band(rng.normal(0, 1, L), 20, 60) * 4)
    squeak = band(squeak, 400, 2500) * np.exp(-((t - 0.09) / 0.07) ** 2) * 0.5
    k = int(0.2 * SR)
    knock = np.zeros(L)
    tt = np.arange(L - k) / SR
    knock[k:] = (low(rng.normal(0, 1, L - k), 500) * 1.4 + np.sin(2 * np.pi * 95 * tt) * 0.8) * np.exp(-tt * 30)
    return squeak + knock


if __name__ == '__main__':
    for k in range(4):
        save('serra_corte%d' % (k + 1), corte(500 + k))
    for k in range(3):
        save('pedal_range%d' % (k + 1), pedal(600 + k), peak_db=-4.0)
