#!/usr/bin/env python3
"""Sons do machado nos ossos (tirando as patas e a cabeça da vaca pendurada).

 - machado_osso: a machadada: a lâmina de pedra entra na carne (um baque abafado e grave,
   meio molhado) e bate no osso (um estalo seco e duro, com uma trinca curtinha).
 - osso_quebra: o golpe que solta a parte: o osso parte de vez (vários estalos juntos, uma
   lasca), os tendões rasgando e o baque.
Uso: python3 tools/sintetizar_osso.py   (grava em sons/*.somog)
"""
import numpy as np
from sintetizar_cobra import SR, band, save


def _clique(n, t0, forca, rng, dec, lo, hi):
    i0 = int(t0 * SR)
    m = int(0.06 * SR)
    tt = np.arange(m) / SR
    s = band(rng.normal(0, 1, m) * np.exp(-tt / dec), lo, hi)
    out = np.zeros(n)
    k = max(0, min(m, n - i0))
    out[i0:i0 + k] = s[:k] * forca
    return out


def _baque(n, t0, f0, dec, forca, rng):
    """Batida grave e abafada (carne): um tom que cai rápido com ruído grave."""
    t = np.arange(n) / SR - t0
    m = t >= 0
    out = np.zeros(n)
    tt = t[m]
    f = f0 * (1.0 + 0.8 * np.exp(-tt / 0.015))
    ph = 2 * np.pi * np.cumsum(f) / SR
    out[m] = np.sin(ph) * np.exp(-tt / dec) * forca
    out[m] += band(rng.normal(0, 1, m.sum()), 60, 500) * np.exp(-tt / (dec * 0.7)) * forca * 0.6
    return out


def machadada(seed):
    rng = np.random.default_rng(seed)
    dur = 0.45
    n = int(dur * SR)
    out = np.zeros(n)
    t0 = 0.01
    # o tapa molhado da lâmina na carne
    out += _clique(n, t0, 0.55, rng, 0.012, 300, 2200)
    # o baque grave do corpo pendurado
    out += _baque(n, t0, rng.uniform(85, 120), 0.07, 0.9, rng)
    # o osso: estalo duro e seco, logo em seguida, com uma trinca
    to = t0 + rng.uniform(0.004, 0.012)
    out += _clique(n, to, 1.0, rng, 0.0035, 1500, 7500)
    out += _clique(n, to + 0.002, 0.5, rng, 0.009, 700, 2600)
    for _ in range(rng.integers(2, 5)):
        out += _clique(n, to + rng.uniform(0.006, 0.04), rng.uniform(0.1, 0.3), rng, 0.0015, 2500, 9000)
    # a madeira do cabo vibrando um pouco
    t = np.arange(n) / SR
    m = t > t0
    out[m] += np.sin(2 * np.pi * rng.uniform(380, 460) * (t[m] - t0)) * np.exp(-(t[m] - t0) / 0.05) * 0.08
    return band(out * np.minimum(1, (dur - t) / 0.06), 50, 10000)


def quebra(seed):
    rng = np.random.default_rng(seed)
    dur = 0.9
    n = int(dur * SR)
    out = np.zeros(n)
    t0 = 0.01
    out += _clique(n, t0, 0.6, rng, 0.014, 300, 2200)
    out += _baque(n, t0, rng.uniform(80, 105), 0.09, 1.0, rng)
    # o osso partindo: estalos fortes em seguida, uma lasca
    tq = t0 + 0.008
    for k in range(rng.integers(4, 7)):
        out += _clique(n, tq + k * rng.uniform(0.006, 0.016), rng.uniform(0.6, 1.0) * (1.0 - k * 0.1), rng, rng.uniform(0.002, 0.005), 1200, 8000)
    out += _clique(n, tq + 0.05, 0.45, rng, 0.02, 500, 2000)
    # os tendões e a pele rasgando (fibroso, descendo)
    t = np.arange(n) / SR
    tr = t - (tq + 0.06)
    m = (tr > 0) & (tr < 0.3)
    rasgo = np.zeros(n)
    nz = rng.normal(0, 1, n)
    puls = (np.sin(2 * np.pi * 38 * tr) > 0.3).astype(float)
    rasgo[m] = (band(nz, 800, 3500)[m] * (0.6 + 0.4 * puls[m])) * np.exp(-tr[m] / 0.1)
    out += rasgo * 0.35
    return band(out * np.minimum(1, (dur - t) / 0.1), 45, 10000)


if __name__ == '__main__':
    for k in range(3):
        save('machado_osso%d' % (k + 1), machadada(90 + k), peak_db=-2.0)
    for k in range(2):
        save('osso_quebra%d' % (k + 1), quebra(95 + k), peak_db=-1.5)
