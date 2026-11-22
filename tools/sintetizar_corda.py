#!/usr/bin/env python3
"""Som da corda arrebentando (o laço quebrando).

Uma corda de fibra não quebra de uma vez: primeiro uns fios vão estourando (estalinhos
secos, cada vez mais juntos), depois o resto arrebenta num estalo seco e forte, e as duas
pontas voltam chicoteando no ar (um "fuuup" de ar que desce de tom).
Uso: python3 tools/sintetizar_corda.py   (grava em sons/corda_arrebenta*.somog)
"""
import numpy as np
from sintetizar_cobra import SR, band, save


def estalinho(n, t0, forca, rng, dec=0.004, lo=1200, hi=7000):
    """Um fio estourando: um clique curto e seco, ruído com decaimento rápido."""
    i0 = int(t0 * SR)
    m = int(0.03 * SR)
    tt = np.arange(m) / SR
    s = rng.normal(0, 1, m) * np.exp(-tt / dec)
    s = band(s, lo, hi)
    out = np.zeros(n)
    k = min(m, n - i0)
    out[i0:i0 + k] = s[:k] * forca
    return out


def arrebenta(seed):
    rng = np.random.default_rng(seed)
    dur = 0.75
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    t_quebra = rng.uniform(0.16, 0.24)
    # os fios estourando antes (cada vez mais juntos e mais fortes)
    tt = rng.uniform(0.0, 0.03)
    while tt < t_quebra - 0.012:
        x = tt / t_quebra
        out += estalinho(n, tt, 0.12 + 0.35 * x * x * rng.uniform(0.6, 1.0), rng,
                         dec=rng.uniform(0.0015, 0.004), lo=1500, hi=8000)
        tt += rng.uniform(0.012, 0.05) * (1.0 - 0.7 * x)
    # o estalo principal: seco e forte, com um corpo médio-grave (a fibra soltando a tensão)
    out += estalinho(n, t_quebra, 1.0, rng, dec=0.006, lo=600, hi=9000)
    out += estalinho(n, t_quebra + 0.004, 0.6, rng, dec=0.012, lo=180, hi=1500)
    out += estalinho(n, t_quebra + rng.uniform(0.012, 0.02), 0.35, rng, dec=0.003, lo=2000, hi=8000)
    # as pontas voltando no ar: um sopro que desce de tom e some
    tw = t - t_quebra
    m = tw > 0
    sopro = np.zeros(n)
    ruido = rng.normal(0, 1, n)
    for lo, hi, peso, atraso in [(2200, 5000, 0.5, 0.0), (1100, 2600, 0.7, 0.03), (500, 1300, 0.6, 0.07)]:
        e = np.where(tw > atraso, (tw - atraso) / 0.02, 0)
        e = np.minimum(1, e) * np.exp(-np.maximum(tw - atraso, 0) / 0.07)
        sopro += band(ruido, lo, hi) * e * peso
    out += sopro * m * 0.45
    # a ponta batendo de leve na roupa/chão no fim
    out += estalinho(n, t_quebra + rng.uniform(0.22, 0.3), 0.18, rng, dec=0.01, lo=150, hi=1200)
    fade = np.minimum(1, (dur - t) / 0.08)
    return band(out * fade, 120, 10000)


if __name__ == '__main__':
    for k in range(3):
        save('corda_arrebenta%d' % (k + 1), arrebenta(70 + k), peak_db=-2.0)
