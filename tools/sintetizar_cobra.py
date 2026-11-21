#!/usr/bin/env python3
"""Sons da cobra (jararaca).

 - cobra_chiado: o chiado da cobra (ar saindo pela boca): ruído agudo e soprado, que
   cresce, segura e some; às vezes em duas soltadas de ar.
 - cobra_rabo: a ponta do rabo vibrando nas folhas secas do chão (a jararaca faz isso
   quando se sente acuada): um tremido seco e rápido de folha.
 - cobra_bote: o bote: um "fsst" curto e rápido (o corpo cortando o ar e as folhas) e o
   tapa surdo da boca.
Uso: python3 tools/sintetizar_cobra.py   (grava em sons/*.somog)
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


def chiado(seed):
    rng = np.random.default_rng(seed)
    partes = []
    for k in range(rng.integers(1, 3)):
        dur = rng.uniform(0.55, 1.1)
        n = int(dur * SR)
        t = np.arange(n) / SR
        env = np.clip(t / 0.12, 0, 1) ** 1.5 * np.clip((dur - t) / 0.3, 0, 1)
        env *= 1.0 + 0.15 * np.sin(2 * np.pi * rng.uniform(5, 9) * t)
        noise = rng.normal(0, 1, n)
        s = band(noise, 3200, 9500, 3) * 0.8 + band(noise, 1800, 3500) * 0.25
        partes.append(s * env)
        partes.append(np.zeros(int(rng.uniform(0.15, 0.3) * SR)))
    return np.concatenate(partes)


def rabo(seed, dur=1.1):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    env = np.clip(t / 0.05, 0, 1) * np.clip((dur - t) / 0.2, 0, 1)
    rate = rng.uniform(38, 55)
    trem = (0.5 + 0.5 * np.sin(2 * np.pi * rate * t)) ** 6       # batidinhas rápidas
    noise = rng.normal(0, 1, n)
    folha = band(noise, 1500, 6000, 2) * trem
    return folha * env


def bote(seed):
    rng = np.random.default_rng(seed)
    dur = 0.32
    n = int(dur * SR)
    t = np.arange(n) / SR
    noise = rng.normal(0, 1, n)
    swish_env = np.exp(-((t - 0.06) / 0.035) ** 2)
    swish = band(noise, 900, 5000) * swish_env
    tapa_env = np.exp(-np.clip(t - 0.11, 0, None) / 0.02) * (t > 0.11)
    tapa = band(noise, 150, 900) * tapa_env * 1.6
    return swish + tapa


if __name__ == '__main__':
    for k in range(3):
        save('cobra_chiado%d' % (k + 1), chiado(10 + k))
    for k in range(2):
        save('cobra_rabo%d' % (k + 1), rabo(20 + k))
    for k in range(2):
        save('cobra_bote%d' % (k + 1), bote(30 + k))
