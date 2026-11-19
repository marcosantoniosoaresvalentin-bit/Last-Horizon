#!/usr/bin/env python3
"""Sons da desfibradeira (talo de buriti nas lâminas de faca de pedra).

 - fibra_puxa: o talo sendo puxado por cima das lâminas: o rasgado áspero da fibra
   abrindo no fio da pedra (ruído médio-agudo com "dentes" irregulares), os estalinhos
   das fibras que arrebentam e um chiado úmido do miolo verde, que somem no fim do puxão.
 - fibra_bate: o talo batendo em cima das lâminas: o baque surdo e molhado do talo e o
   corte seco do fio entrando.
Uso: python3 tools/sintetizar_fibra.py   (grava em sons/*.somog)
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


def puxa(seed, dur=0.42):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    # envelope do puxão: entra rápido, segura e solta
    env = np.clip(t / 0.03, 0, 1) * np.clip((dur - t) / 0.12, 0, 1)
    noise = rng.normal(0, 1, n)
    # o rasgado: ruído médio-agudo modulado por "dentes" irregulares (a fibra prendendo e
    # soltando no fio da pedra, ~60 a 110 vezes por segundo)
    rate = rng.uniform(60, 110) + np.cumsum(rng.normal(0, 40, n)) / SR
    teeth = 0.45 + 0.55 * np.abs(np.sin(np.cumsum(2 * np.pi * rate / SR))) ** 3
    rip = (band(noise, 1400, 5200) * 0.7 + band(noise, 3500, 9000) * 0.35) * teeth
    # o chiado úmido do miolo verde (mais grave, liso)
    wet = band(rng.normal(0, 1, n), 500, 1600) * 0.35
    # estalinhos das fibras arrebentando
    cr = np.zeros(n)
    for _ in range(int(rng.uniform(18, 30))):
        k = int(rng.uniform(0.02, dur - 0.05) * SR)
        L = int(rng.uniform(0.0015, 0.005) * SR)
        cr[k:k + L] += rng.normal(0, 1, L) * np.hanning(L) * rng.uniform(0.6, 1.6)
    cr = band(cr, 2500, 10000)
    return (rip + wet + cr * 1.2) * env


def bate(seed):
    rng = np.random.default_rng(seed)
    L = int(0.3 * SR)
    t = np.arange(L) / SR
    thud = low(rng.normal(0, 1, L), 700) * np.exp(-t * 35) * 1.6          # o talo grosso batendo
    body = np.sin(2 * np.pi * 140 * t) * np.exp(-t * 28) * 0.7
    cut = band(rng.normal(0, 1, L), 2000, 7000) * np.exp(-t * 60) * 0.9   # o fio entrando
    wet = band(rng.normal(0, 1, L), 600, 2000) * np.exp(-t * 18) * 0.35
    return thud + body + cut + wet


if __name__ == '__main__':
    for k in range(4):
        save('fibra_puxa%d' % (k + 1), puxa(300 + k))
    for k in range(3):
        save('fibra_bate%d' % (k + 1), bate(400 + k), peak_db=-2.0)
