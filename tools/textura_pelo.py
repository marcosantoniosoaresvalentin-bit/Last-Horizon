#!/usr/bin/env python3
"""Gera a textura de pelo do tamanduá (texturas/pelo_tamandua.imagem + _n.imagem).

Pelo grosso e áspero: milhares de fios curtos, quase todos deitados no mesmo sentido
(ao longo do corpo, eixo x da imagem), alguns mais claros (pontas grisalhas) e outros
escuros. A imagem repete sem emenda (os fios que passam da borda continuam do outro
lado). O albedo é quase branco com variação (multiplica a cor de cada parte do bicho);
o mapa normal sai da altura dos fios.

Uso: python3 tools/textura_pelo.py
"""
import os
import numpy as np
from PIL import Image, ImageFilter

N = 512
rng = np.random.default_rng(7)

height = np.zeros((N, N), np.float32)
shade = np.full((N, N), 0.3, np.float32)       # o fundo (entre os fios) é escuro
cover = np.zeros((N, N), np.float32)


def strand(x0, y0, length, ang, h, tone, width):
    steps = int(length * 1.5) + 2
    curve = rng.uniform(-0.004, 0.004)
    for i in range(steps):
        t = i / (steps - 1)
        a = ang + curve * i
        x = x0 + np.cos(a) * length * t
        y = y0 + np.sin(a) * length * t
        # o fio afina e fica mais claro na ponta (grisalho)
        w = width * (1.0 - 0.6 * t)
        tt = tone + 0.25 * t * (tone > 0.6)
        for dy in range(-int(w), int(w) + 1):
            xi = int(x) % N
            yi = int(y + dy) % N
            k = 1.0 - abs(dy) / (w + 0.5)
            hh = h * k * (0.6 + 0.4 * (1 - t))
            if hh > height[yi, xi]:
                height[yi, xi] = hh
                shade[yi, xi] = tt * (0.85 + 0.15 * k)
            cover[yi, xi] = 1.0


for _ in range(14000):
    x0 = rng.uniform(0, N)
    y0 = rng.uniform(0, N)
    length = rng.uniform(22, 48)
    ang = rng.normal(0.0, 0.16)          # quase todos no mesmo sentido
    r = rng.random()
    tone = rng.uniform(0.25, 0.45) if r < 0.35 else (rng.uniform(0.95, 1.15) if r > 0.85 else rng.uniform(0.6, 0.85))
    strand(x0, y0, length, ang, rng.uniform(0.5, 1.0), tone, rng.uniform(0.9, 2.0))

alb = np.clip(shade, 0, 1.2) / 1.2
alb = 0.3 + alb * 0.85
img = Image.fromarray((np.clip(alb, 0, 1) * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(0.6))
rgb = Image.merge("RGB", [img, img, img])

# mapa normal a partir da altura (com a borda dando a volta)
hgt = np.array(Image.fromarray((height * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0)), np.float32) / 255.0
dx = (np.roll(hgt, -1, 1) - np.roll(hgt, 1, 1)) * 2.5
dy = (np.roll(hgt, -1, 0) - np.roll(hgt, 1, 0)) * 2.5
nz = np.ones_like(hgt)
L = np.sqrt(dx * dx + dy * dy + nz * nz)
nrm = np.stack([(-dx / L) * 0.5 + 0.5, (dy / L) * 0.5 + 0.5, (nz / L) * 0.5 + 0.5], -1)
nimg = Image.fromarray((nrm * 255).astype(np.uint8), "RGB")

out = os.path.join(os.path.dirname(__file__), "..", "texturas")
rgb.save(os.path.join(out, "pelo_tamandua.imagem"), "JPEG", quality=88)
nimg.save(os.path.join(out, "pelo_tamandua_n.imagem"), "JPEG", quality=90)
print("ok")
