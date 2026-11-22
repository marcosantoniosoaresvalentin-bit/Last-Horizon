#!/usr/bin/env python3
"""Sons da doença da água suja.

 - barriga_ronco: o ronco da barriga (borborigmo): bolhas de ar e líquido passando no
   intestino, um gorgolejo grave que sobe e desce de tom.
 - gases: a soltada de gases: um tremido grave (pulsos de 60 a 130 por segundo, com o
   tom e a força variando), abafado.
Uso: python3 tools/sintetizar_doenca.py   (grava em sons/*.somog)
"""
import numpy as np
from sintetizar_cobra import SR, band, save


def ronco(seed):
    rng = np.random.default_rng(seed)
    dur = rng.uniform(1.4, 2.4)
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    # o tom grave que desliza (o ar passando)
    f0 = 110 + 60 * np.sin(2 * np.pi * rng.uniform(0.4, 0.9) * t + rng.uniform(0, 6)) + 40 * t / dur
    ph = 2 * np.pi * np.cumsum(f0) / SR
    am = 0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(5, 11) * t) ** 2
    tom = (np.sin(ph) + 0.4 * np.sin(2 * ph) + 0.2 * np.sin(3 * ph)) * am
    env = np.minimum(1, t / 0.15) * np.minimum(1, (dur - t) / 0.4) * (0.6 + 0.4 * np.sin(np.pi * t / dur))
    out += tom * env * 0.6
    # as bolhas (estalinhos molhados)
    for _ in range(int(rng.uniform(10, 22))):
        t0 = rng.uniform(0.05, dur - 0.1)
        fb = rng.uniform(180, 420)
        tb = t - t0
        m = tb > 0
        out[m] += np.sin(2 * np.pi * fb * (1 + 2.5 * tb[m]) * tb[m]) * np.exp(-tb[m] / rng.uniform(0.02, 0.05)) * rng.uniform(0.3, 0.8)
    noise = rng.normal(0, 1, n)
    out += band(noise, 60, 400) * env * 0.25
    return band(out, 50, 900)


def gases(seed):
    rng = np.random.default_rng(seed)
    dur = rng.uniform(0.45, 1.1)
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 75 + 45 * np.sin(np.pi * t / dur * rng.uniform(0.8, 1.6)) + rng.normal(0, 6, n).cumsum() / np.sqrt(n) * 4
    f = np.clip(f, 50, 150)
    ph = np.cumsum(f) / SR
    puls = (np.mod(ph, 1.0) < 0.22).astype(float)          # pulsos (a "borda" vibrando)
    puls = puls * (0.8 + 0.4 * rng.random(n))
    noise = rng.normal(0, 1, n)
    s = band(puls, 60, 700) + band(noise, 100, 600) * 0.25
    flutter = 0.7 + 0.3 * np.sin(2 * np.pi * rng.uniform(6, 14) * t)
    env = np.minimum(1, t / 0.03) * np.minimum(1, (dur - t) / 0.15) * flutter
    return band(s * env, 50, 800)


if __name__ == '__main__':
    for k in range(3):
        save('barriga_ronco%d' % (k + 1), ronco(40 + k))
    for k in range(3):
        save('gases%d' % (k + 1), gases(50 + k), peak_db=-5.0)
