#!/usr/bin/env python3
"""Vozes do gado (sintetizadas como voz de verdade: pregas vocais + boca).

A fonte é a vibração das pregas vocais (todos os harmônicos do tom, mais fracos quanto
mais agudos, com um tremor natural e um pouco de rouquidão); a boca e o focinho filtram
(os formantes): começa de boca fechada ("mmm", som pelo nariz), abre ("ôôô/ááá") e
fecha de novo, com o tom subindo, segurando e caindo no fim. Mais o ar do fôlego.

 - vaca_mugido: a vaca (tom ~110-150 Hz, 1,2 a 2 s).
 - touro_berro: o touro (bem grave ~70-95 Hz, rouco, mais comprido e forte).
 - bezerro: o bezerro chamando a mãe (agudo ~250-380 Hz, curto, "mééé").
 - vaca_bufo: o bufo de susto (o ar saindo forte pelo nariz).
Uso: python3 tools/sintetizar_vaca.py   (grava em sons/*.somog)
"""
import numpy as np
from sintetizar_cobra import SR, band, save


def suave(x, n):
    k = np.ones(n) / n
    return np.convolve(x, k, mode='same')


def voz(rng, dur, f0_pts, form_pts, rouco=0.0, sopro=0.06, tilt=1.25, nh=70):
    """f0_pts: [(t, Hz)], form_pts: [(t, [(F, B, ganho), ...])] (3 formantes)."""
    N = int(dur * SR)
    t = np.arange(N) / SR
    f0 = np.interp(t, [p[0] * dur for p in f0_pts], [p[1] for p in f0_pts])
    # tremor natural (jitter lento) e um vibrato leve
    jit = suave(rng.normal(0, 1, N), int(0.03 * SR))
    jit = jit / (np.abs(jit).max() + 1e-9)
    f0 = f0 * (1 + 0.012 * jit + 0.008 * np.sin(2 * np.pi * rng.uniform(4.5, 6.0) * t))
    ph = 2 * np.pi * np.cumsum(f0) / SR
    # os formantes ao longo do tempo
    tf = [p[0] * dur for p in form_pts]
    F = []
    for i in range(3):
        F.append((np.interp(t, tf, [p[1][i][0] for p in form_pts]),
                  np.interp(t, tf, [p[1][i][1] for p in form_pts]),
                  np.interp(t, tf, [p[1][i][2] for p in form_pts])))
    out = np.zeros(N)
    shimmer = 1 + 0.06 * suave(rng.normal(0, 1, N), int(0.01 * SR)) / 0.3
    for k in range(1, nh + 1):
        fk = k * f0
        if fk.min() > SR / 2 - 500:
            break
        amp = np.zeros(N)
        for (Fi, Bi, Gi) in F:
            amp += Gi / (1 + ((fk - Fi) / Bi) ** 2)
        amp = amp * (k ** -tilt) * (fk < SR / 2 - 500)
        out += amp * np.sin(k * ph + rng.uniform(0, 6.28))
    # rouquidão: sub-harmônico (as pregas batendo irregular)
    if rouco > 0:
        out *= 1 + rouco * np.sin(ph / 2) * (0.5 + 0.5 * suave(rng.normal(0, 1, N), 200) / 0.2)
    out *= shimmer
    # o ar do fôlego, passando pela mesma boca
    nz = rng.normal(0, 1, N)
    ar = np.zeros(N)
    for (Fi, Bi, Gi) in F:
        fc = float(np.median(Fi))
        ar += band(nz, max(80, fc - 2 * float(np.median(Bi))), fc + 2 * float(np.median(Bi))) * float(np.median(Gi))
    out = out / (np.abs(out).max() + 1e-9) + sopro * ar / (np.abs(ar).max() + 1e-9)
    return out, t


def env(t, dur, a=0.12, r=0.25):
    return np.minimum(1, t / a) * np.minimum(1, np.maximum(0, dur - t) / r)


MMM = [(250, 80, 1.0), (1100, 200, 0.08), (2400, 300, 0.03)]       # boca fechada (nariz)
OOO = [(520, 110, 1.0), (950, 140, 0.55), (2450, 260, 0.12)]       # "ôô"
AAA = [(700, 130, 1.0), (1180, 150, 0.6), (2500, 280, 0.15)]       # "áá" (boca bem aberta)


def mugido(seed):
    rng = np.random.default_rng(seed)
    dur = rng.uniform(1.3, 2.1)
    b = rng.uniform(105, 125)
    f0 = [(0, b * 0.92), (0.18, b * 1.12), (0.35, b * 1.22), (0.7, b * 1.15), (0.9, b * 0.95), (1.0, b * 0.82)]
    aberta = AAA if rng.random() < 0.5 else OOO
    form = [(0, MMM), (0.15, MMM), (0.35, aberta), (0.75, aberta), (0.92, OOO), (1.0, MMM)]
    s, t = voz(rng, dur, f0, form, rouco=0.12, sopro=0.08)
    s *= env(t, dur, 0.15, 0.3) * (0.55 + 0.45 * np.minimum(1, t / (0.35 * dur)))
    return band(s, 60, 7000)


def berro(seed):
    rng = np.random.default_rng(seed)
    dur = rng.uniform(1.8, 2.6)
    b = rng.uniform(72, 88)
    f0 = [(0, b * 0.9), (0.2, b * 1.15), (0.45, b * 1.3), (0.75, b * 1.2), (1.0, b * 0.8)]
    form = [(0, MMM), (0.12, MMM), (0.3, AAA), (0.8, AAA), (1.0, OOO)]
    s, t = voz(rng, dur, f0, form, rouco=0.45, sopro=0.14, tilt=1.05)
    s *= env(t, dur, 0.18, 0.35)
    # um ronco grave por baixo (o peito grande)
    s += 0.25 * np.sin(2 * np.pi * np.cumsum(np.full(len(t), b * 0.5)) / SR) * env(t, dur, 0.3, 0.4)
    return band(s, 40, 6500)


def bezerro(seed):
    rng = np.random.default_rng(seed)
    dur = rng.uniform(0.55, 0.9)
    b = rng.uniform(250, 300)
    f0 = [(0, b), (0.25, b * 1.25), (0.6, b * 1.2), (1.0, b * 0.9)]
    EEE = [(650, 120, 1.0), (1700, 180, 0.6), (2900, 300, 0.18)]
    form = [(0, [(350, 90, 1.0), (1500, 200, 0.1), (2800, 300, 0.04)]), (0.2, EEE), (0.85, EEE), (1.0, OOO)]
    s, t = voz(rng, dur, f0, form, rouco=0.05, sopro=0.1, tilt=1.15)
    s *= env(t, dur, 0.06, 0.15)
    return band(s, 120, 8000)


def bufo(seed):
    rng = np.random.default_rng(seed)
    dur = rng.uniform(0.35, 0.55)
    N = int(dur * SR)
    t = np.arange(N) / SR
    nz = rng.normal(0, 1, N)
    e = np.minimum(1, t / 0.02) * np.exp(-t / (dur * 0.35))
    # o ar forte pelas narinas: chiado grave, com o focinho batendo (vibra)
    s = band(nz, 150, 1200) * e + 0.4 * band(nz, 1200, 4000) * e
    s *= 1 + 0.5 * np.sin(2 * np.pi * rng.uniform(25, 40) * t)
    return s


if __name__ == '__main__':
    for k in range(4):
        save('vaca_mugido%d' % (k + 1), mugido(400 + k), peak_db=-2.0)
    for k in range(2):
        save('touro_berro%d' % (k + 1), berro(410 + k), peak_db=-1.5)
    for k in range(3):
        save('bezerro%d' % (k + 1), bezerro(420 + k), peak_db=-3.0)
    for k in range(2):
        save('vaca_bufo%d' % (k + 1), bufo(430 + k), peak_db=-4.0)
