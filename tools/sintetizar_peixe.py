#!/usr/bin/env python3
"""Sons da pesca e do galope do gado.

A água "de verdade" é feita de bolhas: cada bolha que nasce quando a água é furada solta
um assobio curtinho cujo tom SOBE enquanto morre (a ressonância de Minnaert). Um respingo
é um monte dessas bolhas (grandes = grave, pequenas = agudo) mais o chiado das gotas.

 - peixe_pulo: o peixe pulando e caindo na água lá longe (o "tchibum" com as gotas).
 - boia_toc:   o peixe beliscando: a boia dá um tranquinho (um "plic" baixinho).
 - fisgada:    a boia afunda de vez: o "glup" grave e as bolhas subindo.
 - peixe_briga: o peixe se debatendo na linha: vários respingos fortes seguidos.
 - peixe_debate: o peixe fora da água: os tapas molhados do rabo e as gotas pingando.
 - casco:      a pisada do gado correndo na terra: os cascos batendo (dois juntos, no
               trote), o baque grave no chão e o capim/terra raspando.
Uso: python3 tools/sintetizar_peixe.py   (grava em sons/*.somog)
"""
import numpy as np
from sintetizar_cobra import SR, band, save


def bolha(n, t0, f0, amp, dec, subida=0.6):
    """Uma bolha: um tom que sobe um pouco enquanto some."""
    t = np.arange(n) / SR - t0
    m = t >= 0
    out = np.zeros(n)
    tt = t[m]
    f = f0 * (1.0 + subida * tt / dec)
    ph = 2 * np.pi * np.cumsum(f) / SR
    out[m] = np.sin(ph) * np.exp(-tt / dec) * amp * np.minimum(1.0, tt / 0.0008)
    return out


def chiado(n, t0, dur, amp, lo, hi, rng, ataque=0.002):
    t = np.arange(n) / SR - t0
    m = (t >= 0) & (t < dur * 3)
    out = np.zeros(n)
    tt = t[m]
    env = np.minimum(1.0, tt / ataque) * np.exp(-tt / dur)
    out[m] = band(rng.normal(0, 1, m.sum()), lo, hi) * env * amp
    return out


def respingo(n, t0, forca, rng, tam=1.0):
    """O impacto na água: o tapa, a bolha grande e a chuva de gotinhas."""
    out = np.zeros(n)
    out += chiado(n, t0, 0.025 * tam, 0.9 * forca, 300, 6000, rng, 0.001)
    out += chiado(n, t0 + 0.005, 0.12 * tam, 0.35 * forca, 800, 9000, rng)
    out += bolha(n, t0 + rng.uniform(0.003, 0.012), rng.uniform(180, 320) / tam, 0.7 * forca, 0.05 * tam, 0.8)
    for _ in range(int(rng.integers(8, 18) * tam)):
        tb = t0 + rng.exponential(0.06 * tam) + 0.01
        out += bolha(n, tb, rng.uniform(700, 3200), rng.uniform(0.05, 0.25) * forca, rng.uniform(0.006, 0.02))
    # as gotas que subiram caindo de volta
    for _ in range(int(rng.integers(6, 14) * tam)):
        tg = t0 + rng.uniform(0.12, 0.45) * tam
        out += bolha(n, tg, rng.uniform(1500, 4500), rng.uniform(0.03, 0.12) * forca, rng.uniform(0.004, 0.01))
        out += chiado(n, tg, 0.006, 0.05 * forca, 2000, 9000, rng, 0.0005)
    return out


def fade(s, fim=0.05):
    n = len(s)
    k = int(fim * SR)
    s[n - k:] *= np.linspace(1, 0, k)
    return s


def peixe_pulo(seed):
    rng = np.random.default_rng(seed)
    dur = 1.2
    n = int(dur * SR)
    out = np.zeros(n)
    tam = rng.uniform(0.7, 1.2)
    # às vezes se ouve o peixe saindo (um respingo pequeno) antes de cair
    if rng.random() < 0.5:
        out += respingo(n, 0.02, 0.35, rng, 0.5)
        t0 = rng.uniform(0.25, 0.4)
    else:
        t0 = 0.02
    out += respingo(n, t0, 1.0, rng, tam)
    return fade(band(out, 120, 10000))


def boia_toc(seed):
    rng = np.random.default_rng(seed)
    dur = 0.35
    n = int(dur * SR)
    out = np.zeros(n)
    out += bolha(n, 0.01, rng.uniform(900, 1400), 0.6, 0.012, 1.2)
    out += chiado(n, 0.01, 0.01, 0.15, 1000, 6000, rng, 0.0008)
    for _ in range(rng.integers(1, 4)):
        out += bolha(n, 0.02 + rng.uniform(0, 0.08), rng.uniform(1600, 3200), rng.uniform(0.08, 0.2), 0.006)
    return fade(band(out, 300, 9000), 0.03)


def fisgada(seed):
    rng = np.random.default_rng(seed)
    dur = 0.9
    n = int(dur * SR)
    out = np.zeros(n)
    # o "glup": a boia puxada para baixo carrega uma bolha grande (grave)
    out += bolha(n, 0.01, rng.uniform(140, 200), 1.0, 0.07, 0.9)
    out += chiado(n, 0.01, 0.03, 0.4, 200, 3000, rng, 0.002)
    # as bolhas subindo depois
    for _ in range(rng.integers(6, 12)):
        out += bolha(n, rng.uniform(0.08, 0.6), rng.uniform(500, 1800), rng.uniform(0.08, 0.25), rng.uniform(0.01, 0.025))
    return fade(band(out, 80, 9000))


def peixe_briga(seed):
    rng = np.random.default_rng(seed)
    dur = 1.6
    n = int(dur * SR)
    out = np.zeros(n)
    t = 0.02
    while t < dur - 0.3:
        out += respingo(n, t, rng.uniform(0.5, 1.0), rng, rng.uniform(0.5, 0.9))
        # o rabo batendo de lado (tapa na superfície)
        out += chiado(n, t + 0.04, 0.012, 0.5, 400, 4000, rng, 0.0008)
        t += rng.uniform(0.12, 0.3)
    return fade(band(out, 100, 10000))


def peixe_debate(seed):
    rng = np.random.default_rng(seed)
    dur = 1.1
    n = int(dur * SR)
    out = np.zeros(n)
    t = 0.01
    while t < dur - 0.2:
        # o tapa molhado: um estalo curto e um baquezinho do corpo
        out += chiado(n, t, 0.006, 1.0, 600, 7000, rng, 0.0004)
        out += bolha(n, t, rng.uniform(150, 260), 0.35, 0.02, 0.3)
        for _ in range(rng.integers(1, 4)):
            out += bolha(n, t + rng.uniform(0.02, 0.12), rng.uniform(2000, 5000), rng.uniform(0.04, 0.1), 0.004)
        t += rng.uniform(0.07, 0.17)
    return fade(band(out, 120, 10000))


def casco(seed):
    rng = np.random.default_rng(seed)
    dur = 0.32
    n = int(dur * SR)
    out = np.zeros(n)
    t = np.arange(n) / SR
    for k in range(2):                       # o trote: duas patas quase juntas
        t0 = 0.01 + k * rng.uniform(0.03, 0.06)
        f0 = rng.uniform(55, 85)
        m = t >= t0
        tt = t[m] - t0
        f = f0 * (1.0 + 1.5 * np.exp(-tt / 0.01))
        ph = 2 * np.pi * np.cumsum(f) / SR
        forca = 1.0 if k == 0 else rng.uniform(0.6, 0.85)
        out[m] += np.sin(ph) * np.exp(-tt / 0.045) * forca
        # o casco duro batendo (um "toc" seco) e a terra
        out += chiado(n, t0, 0.008, 0.45 * forca, 400, 2500, rng, 0.0005)
        out += chiado(n, t0 + 0.004, 0.05, 0.18 * forca, 1500, 7000, rng, 0.004)
    return fade(band(out, 35, 8000), 0.04)


if __name__ == '__main__':
    for i in range(4):
        save('peixe_pulo%d' % (i + 1), peixe_pulo(100 + i), -4.0)
    for i in range(3):
        save('boia_toc%d' % (i + 1), boia_toc(200 + i), -6.0)
    for i in range(3):
        save('fisgada%d' % (i + 1), fisgada(300 + i), -3.0)
    for i in range(3):
        save('peixe_briga%d' % (i + 1), peixe_briga(400 + i), -3.0)
    for i in range(3):
        save('peixe_debate%d' % (i + 1), peixe_debate(500 + i), -4.0)
    for i in range(6):
        save('casco%d' % (i + 1), casco(600 + i), -3.0)
