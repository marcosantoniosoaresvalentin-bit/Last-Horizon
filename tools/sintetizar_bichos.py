#!/usr/bin/env python3
"""Gera os chamados da arara-canindé e do macaco-prego (sons sintetizados).

Não achei gravações livres (CC0) dessas espécies nos bancos liberados, então os sons
são montados a partir de como os chamados reais são:
 - Arara-canindé: grito rouco e alto ("raaah"), 0,3 a 0,7 s, voz cheia de harmônicos
   (fundamental 600-1100 Hz) com aspereza (a voz "falha" e treme), subindo e descendo.
   Variações: grito de voo (contato), grito curto de alarme, resmungo baixo pousada.
 - Macaco-prego: assobio agudo e curto ("piu", 3-5 kHz) de contato enquanto procura
   comida, trinado (piu-piu-piu rápido), latido rouco de alarme ("rã!") e guincho.
Uso: python3 tools/sintetizar_bichos.py  (grava em sons/*.somog)
"""
import os
import subprocess
import tempfile
import wave

import numpy as np
from scipy.signal import butter, lfilter

SR = 32000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'sons')
rng = np.random.default_rng(2026)


def env(n, a, r, curve=1.0):
    e = np.ones(n)
    na = max(1, min(int(a * SR), n // 3))
    nr = max(1, min(int(r * SR), n // 2))
    e[:na] = np.linspace(0, 1, na) ** 0.6
    e[-nr:] *= np.linspace(1, 0, nr) ** curve
    return e


def band(x, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), min(hi / (SR / 2), 0.99)], btype='band')
    return lfilter(b, a, x)


def pulse_train(f0, jitter, shimmer):
    """Voz rouca: um pulso por ciclo, com o período e a força tremendo um pouco."""
    n = len(f0)
    out = np.zeros(n)
    t = 0.0
    while t < n - 1:
        i = int(t)
        per = SR / max(f0[i], 50.0) * (1.0 + rng.normal(0, jitter))
        amp = 1.0 + rng.normal(0, shimmer)
        # pulso glotal (meia senoide curta e assimétrica)
        w = max(3, int(per * 0.45))
        k = np.arange(w)
        g = np.sin(np.pi * k / w) ** 2 * (1 - k / w)
        end = min(n, i + w)
        out[i:end] += amp * g[:end - i]
        t += max(per, 2.0)
    return out - np.mean(out)


def macaw(dur, f_start, f_peak, f_end, rough=0.08, loud=1.0, formants=(1300, 2600, 3900)):
    n = int(dur * SR)
    x = np.linspace(0, 1, n)
    # contorno: sobe rápido até o pico e desce devagar
    pk = 0.3
    f0 = np.where(x < pk, f_start + (f_peak - f_start) * np.sin(x / pk * np.pi / 2),
                  f_peak + (f_end - f_peak) * np.clip((x - pk) / (1 - pk), 0, 1) ** 1.3)
    f0 *= 1 + 0.03 * np.sin(2 * np.pi * 7 * x * dur)
    src = pulse_train(f0, rough, rough * 2)
    # aspereza: a voz "rasga" (modulação rápida) e tem chiado de ar
    am = 1 + 0.35 * np.sin(2 * np.pi * rng.uniform(35, 55) * np.arange(n) / SR + rng.uniform(0, 6))
    noise = rng.normal(0, 1, n)
    y = src * am
    voc = sum(band(y, f * 0.8, f * 1.25) * g for f, g in zip(formants, (1.0, 0.8, 0.45)))
    voc += 0.25 * band(y, 300, 900)
    hiss = band(noise, 1800, 6000) * 0.10
    s = (voc + hiss * np.abs(voc).mean() * 6) * env(n, 0.025, 0.12, 1.5)
    return s / (np.abs(s).max() + 1e-9) * loud


def growl(dur):
    """Resmungo baixinho de arara pousada (conversa do casal)."""
    n = int(dur * SR)
    x = np.linspace(0, 1, n)
    f0 = 380 + 120 * np.sin(np.pi * x) + rng.normal(0, 10, n).cumsum() * 0.02
    src = pulse_train(f0, 0.14, 0.3)
    y = band(src, 500, 1500) + 0.6 * band(src, 1800, 2800)
    y *= env(n, 0.02, 0.06)
    return y / (np.abs(y).max() + 1e-9) * 0.45


def whistle(dur, f_hi, f_lo, vib=0.0):
    """Assobio do macaco-prego: tom agudo que desce, com um pouco de 2ª harmônica."""
    n = int(dur * SR)
    x = np.linspace(0, 1, n)
    f = f_hi + (f_lo - f_hi) * x ** 0.8
    f *= 1 + vib * np.sin(2 * np.pi * 28 * x * dur)
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.sin(ph) + 0.18 * np.sin(2 * ph + 0.3) + 0.05 * np.sin(3 * ph)
    y += band(rng.normal(0, 1, n), 2500, 7000) * 0.04     # ar
    y *= env(n, 0.012, 0.05, 1.4)
    return y / (np.abs(y).max() + 1e-9)


def trill(notes, f0):
    parts = []
    for i in range(notes):
        d = rng.uniform(0.045, 0.065)
        f = f0 * (1 + 0.04 * i) * rng.uniform(0.97, 1.03)
        parts.append(whistle(d, f * 1.12, f * 0.9))
        parts.append(np.zeros(int(rng.uniform(0.025, 0.04) * SR)))
    return np.concatenate(parts) * 0.8


def bark(dur):
    """Latido de alarme ('rã!'): curto, rouco e forte."""
    n = int(dur * SR)
    x = np.linspace(0, 1, n)
    f0 = 520 + 260 * np.sin(np.pi * np.minimum(x * 1.6, 1))
    src = pulse_train(f0, 0.12, 0.25)
    y = band(src, 800, 2200) + 0.7 * band(src, 2400, 4200)
    y += band(rng.normal(0, 1, n), 1500, 5000) * 0.25 * np.abs(y).mean() * 4
    y *= env(n, 0.006, 0.05, 2.0)
    return y / (np.abs(y).max() + 1e-9)


def scream(dur):
    """Guincho (briga ou susto forte): agudo, tenso, tremido."""
    n = int(dur * SR)
    x = np.linspace(0, 1, n)
    f0 = 1500 + 500 * np.sin(np.pi * x) * (1 + 0.05 * np.sin(2 * np.pi * 18 * x * dur))
    src = pulse_train(f0, 0.05, 0.1)
    y = band(src, 1400, 3200) + 0.6 * band(src, 3200, 6500)
    y *= env(n, 0.02, 0.1)
    return y / (np.abs(y).max() + 1e-9)


def seq(*parts, gap=(0.06, 0.12)):
    out = []
    for p in parts:
        out.append(p)
        out.append(np.zeros(int(rng.uniform(*gap) * SR)))
    return np.concatenate(out[:-1])


def save(name, s, peak_db=-2.0):
    s = s / (np.abs(s).max() + 1e-9) * 10 ** (peak_db / 20)
    pad = np.zeros(int(0.03 * SR))
    s = np.concatenate([s, pad])
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


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    # (os sons da arara agora são gravações reais: ver sons/LEIA.md)
    # macaco-prego: assobios de contato
    save('macaco_assobio1', whistle(0.16, 4300, 3300))
    save('macaco_assobio2', seq(whistle(0.12, 4600, 3700), whistle(0.14, 4200, 3300), gap=(0.08, 0.14)))
    save('macaco_assobio3', whistle(0.22, 3900, 3000, vib=0.02))
    save('macaco_trinado1', trill(6, 3600))
    save('macaco_trinado2', trill(9, 3300))
    # macaco-prego: alarme (latidos) e guincho
    save('macaco_alarme1', seq(bark(0.09), bark(0.1), bark(0.085), gap=(0.09, 0.15)), -1)
    save('macaco_alarme2', seq(bark(0.11), bark(0.09), gap=(0.1, 0.16)), -1)
    save('macaco_guincho1', scream(0.42), -3)
