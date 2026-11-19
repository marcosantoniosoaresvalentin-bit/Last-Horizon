#!/usr/bin/env python3
"""Gera o som da folha grande de palmeira (buriti) caindo e o do talo sendo cortado.

 - folha_cai: o farfalhar das lâminas secas/verdes batendo no ar enquanto a folha cai
   balançando (ruído filtrado de 1 a 7 kHz, com o "flap" de 6 a 11 vezes por segundo
   ficando mais forte), e no fim o baque abafado do talo no chão com o estalar das
   lâminas amassando (ruído grave curto + estalinhos que somem).
 - talo_corte: a lâmina de pedra entrando no talo verde e fibroso (batida seca curta
   com o ranger da fibra).
Uso: python3 tools/sintetizar_folha.py   (grava em sons/*.somog)
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


def save(name, s, peak_db=-2.0):
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


def folha(seed, dur=2.3):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    fall = 1.75 + rng.uniform(-0.2, 0.15)          # quando bate no chão
    nf = int(fall * SR)
    # farfalhar: as lâminas batendo no ar, o "flap" do balanço ficando mais forte
    noise = rng.normal(0, 1, n)
    rust = band(noise, 900, 7000) * 0.6 + band(noise, 2500, 9000) * 0.4
    flap_f = np.linspace(6.0, 11.0, n) + rng.uniform(-1, 1)
    flap = 0.55 + 0.45 * np.abs(np.sin(np.cumsum(2 * np.pi * flap_f / SR)))
    grow = np.clip(t / fall, 0, 1) ** 1.4
    e = grow * flap
    e[nf:] *= np.exp(-(t[nf:] - fall) * 6.0)
    # estalinhos das lâminas se tocando no caminho
    cr = np.zeros(n)
    for _ in range(int(40 * fall)):
        k = int(rng.uniform(0.2, fall) * SR)
        L = int(rng.uniform(0.002, 0.008) * SR)
        if k + L < n:
            cr[k:k + L] += rng.normal(0, 1, L) * np.hanning(L) * rng.uniform(0.3, 1.0)
    cr = band(cr, 2000, 8000)
    s = rust * e * 0.6 + cr * grow * 0.5
    # o baque do talo no chão (grave, abafado) e as lâminas amassando
    thud = np.zeros(n)
    L = int(0.18 * SR)
    th = np.arange(L) / SR
    thud[nf:nf + L] = low(rng.normal(0, 1, L), 260) * np.exp(-th * 22) * 3.0 + np.sin(2 * np.pi * 70 * th) * np.exp(-th * 30) * 1.2
    crash = np.zeros(n)
    L2 = int(0.45 * SR)
    t2 = np.arange(L2) / SR
    cz = band(rng.normal(0, 1, L2), 1200, 8500) * np.exp(-t2 * 7)
    for _ in range(60):
        k = int(rng.uniform(0, 0.35) * SR)
        Lc = int(rng.uniform(0.002, 0.006) * SR)
        if k + Lc < L2:
            cz[k:k + Lc] += rng.normal(0, 1, Lc) * np.hanning(Lc) * np.exp(-k / SR * 6) * 1.5
    crash[nf:nf + L2] = cz[:max(0, min(L2, n - nf))]
    s = s + thud + crash * 0.9
    return s


def talo(seed):
    rng = np.random.default_rng(seed)
    L = int(0.32 * SR)
    t = np.arange(L) / SR
    hit = low(rng.normal(0, 1, L), 1500) * np.exp(-t * 40) * 1.4
    fib = band(rng.normal(0, 1, L), 600, 3800) * np.exp(-t * 14) * (0.5 + 0.5 * np.sin(2 * np.pi * 55 * t))
    knock = np.sin(2 * np.pi * 180 * t) * np.exp(-t * 35) * 0.8
    return hit + fib * 0.7 + knock


if __name__ == '__main__':
    for k in range(3):
        save('folha_cai%d' % (k + 1), folha(100 + k))
    for k in range(3):
        save('talo_corte%d' % (k + 1), talo(200 + k), peak_db=-4.0)
