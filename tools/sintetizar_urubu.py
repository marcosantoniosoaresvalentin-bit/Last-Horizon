#!/usr/bin/env python3
"""Sons da carniça: as moscas e o urubu.

 - moscas: o zumbido de muitas moscas em volta da carcaça (cada mosca um zumbido de
   asa de ~180-260 Hz que vai e vem, chegando perto e se afastando). Feito para tocar em
   repetição (as pontas se emendam).
 - urubu_asas: o urubu levantando voo: umas batidas de asa pesadas e abafadas (o ar
   empurrado pelas penas largas), cada uma um "fuuf" grave.
 - urubu_chiado: o urubu não canta: ele chia (um sopro rouco) e dá um grunhido curto
   quando briga pela carne.
Uso: python3 tools/sintetizar_urubu.py   (grava em sons/*.somog)
"""
import numpy as np
from sintetizar_cobra import SR, band, save


def moscas(seed, dur=3.0, n=9):
    rng = np.random.default_rng(seed)
    N = int(dur * SR)
    t = np.arange(N) / SR
    out = np.zeros(N)
    for _ in range(n):
        f0 = rng.uniform(170, 270)
        # a frequência varia (a mosca muda de direção) - periódica para emendar
        k1 = rng.integers(1, 4)
        k2 = rng.integers(2, 7)
        f = f0 * (1 + 0.06 * np.sin(2 * np.pi * k1 * t / dur + rng.uniform(0, 6)) + 0.03 * np.sin(2 * np.pi * k2 * t / dur))
        ph = 2 * np.pi * np.cumsum(f) / SR
        # a asa: onda cheia de harmônicos (dente de serra suave)
        s = np.sin(ph) + 0.5 * np.sin(2 * ph + 0.3) + 0.3 * np.sin(3 * ph + 1.1) + 0.15 * np.sin(5 * ph)
        # chegando perto e longe (volume), também periódico
        k3 = rng.integers(1, 3)
        amp = 0.35 + 0.65 * (0.5 + 0.5 * np.sin(2 * np.pi * k3 * t / dur + rng.uniform(0, 6))) ** 2
        out += s * amp * rng.uniform(0.5, 1.0)
    out = band(out, 120, 4000)
    # emenda as pontas
    fade = int(0.15 * SR)
    out[:fade] = out[:fade] * np.linspace(0, 1, fade) + out[-fade:] * np.linspace(1, 0, fade)
    return out[:-fade]


def asas(seed):
    rng = np.random.default_rng(seed)
    dur = 1.4
    N = int(dur * SR)
    t = np.arange(N) / SR
    out = np.zeros(N)
    nz = rng.normal(0, 1, N)
    tb = 0.02
    for k in range(rng.integers(4, 6)):
        per = rng.uniform(0.2, 0.26) * (1 + k * 0.08)
        tt = t - tb
        m = (tt > 0) & (tt < per)
        env = np.zeros(N)
        env[m] = np.sin(np.pi * tt[m] / per) ** 1.5 * np.exp(-tt[m] / (per * 0.7))
        out += band(nz, 90, 900) * env * (1.0 - k * 0.12)
        out += band(nz, 900, 2600) * env * 0.12
        tb += per * rng.uniform(0.95, 1.1)
    return band(out * np.minimum(1, (dur - t) / 0.1), 60, 5000)


def chiado(seed):
    rng = np.random.default_rng(seed)
    dur = rng.uniform(0.7, 1.0)
    N = int(dur * SR)
    t = np.arange(N) / SR
    nz = rng.normal(0, 1, N)
    env = np.minimum(1, t / 0.08) * np.exp(-np.maximum(t - 0.25, 0) / 0.22)
    # o sopro rouco: ruído na faixa média com um "rasgado" (modulação rápida)
    rouco = 0.6 + 0.4 * np.sin(2 * np.pi * rng.uniform(28, 40) * t)
    out = band(nz, 900, 3800) * env * rouco
    # um grunhido curto no começo (às vezes)
    if rng.random() < 0.7:
        g = np.sin(2 * np.pi * np.cumsum(rng.uniform(95, 130) * (1 - 0.3 * t)) / SR)
        gm = np.exp(-t / 0.07) * (t < 0.2)
        out += band(g * (1 + 0.5 * nz), 80, 900) * gm * 0.8
    return out


if __name__ == '__main__':
    for k in range(2):
        save('moscas%d' % (k + 1), moscas(300 + k), peak_db=-6.0)
    for k in range(2):
        save('urubu_asas%d' % (k + 1), asas(310 + k), peak_db=-3.0)
    for k in range(3):
        save('urubu_chiado%d' % (k + 1), chiado(320 + k), peak_db=-4.0)
