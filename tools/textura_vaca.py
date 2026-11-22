#!/usr/bin/env python3
"""Gera a textura de pelo da vaca (texturas/pelo_vaca.imagem + _n.imagem).

Pelo curto, fino e liso de gado zebu: muitos fios curtinhos deitados no mesmo sentido
(eixo x da imagem), com pouca diferença de tom (o albedo é quase branco e multiplica a
cor de cada vaca: branca, cinza, vermelha, malhada). Algumas dobras de pele bem leves
(rugas largas) no mapa normal. A imagem repete sem emenda.

Uso: python3 tools/textura_vaca.py
"""
import os
import numpy as np
from PIL import Image, ImageFilter

N = 512
rng = np.random.default_rng(11)

height = np.zeros((N, N), np.float32)
shade = np.full((N, N), 0.82, np.float32)


def strand(x0, y0, length, ang, h, tone, width):
    steps = int(length * 1.6) + 2
    for i in range(steps):
        t = i / (steps - 1)
        x = x0 + np.cos(ang) * length * t
        y = y0 + np.sin(ang) * length * t
        w = width * (1.0 - 0.5 * t)
        for dy in range(-int(w), int(w) + 1):
            xi = int(x) % N
            yi = int(y + dy) % N
            k = 1.0 - abs(dy) / (w + 0.5)
            hh = h * k * (0.5 + 0.5 * (1 - t))
            if hh > height[yi, xi]:
                height[yi, xi] = hh
                shade[yi, xi] = tone * (0.9 + 0.1 * k)


for _ in range(42000):
    x0 = rng.uniform(0, N)
    y0 = rng.uniform(0, N)
    strand(x0, y0, rng.uniform(7, 15), rng.normal(0.0, 0.1), rng.uniform(0.4, 1.0),
           rng.uniform(0.82, 1.0) if rng.random() > 0.15 else rng.uniform(0.7, 0.8), rng.uniform(0.6, 1.3))

# rugas largas e suaves da pele (só no relevo)
yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
rug = 0.04 * np.sin((yy / N) * np.pi * 2 * 7 + np.sin((xx / N) * np.pi * 2 * 3) * 1.5)

alb = 0.78 + (np.clip(shade, 0, 1) - 0.78) * 0.9
img = Image.fromarray((np.clip(alb, 0, 1) * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(0.5))
rgb = Image.merge("RGB", [img, img, img])

hgt = np.array(Image.fromarray((np.clip(height * 0.8 + rug * 0.2 + 0.2, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)), np.float32) / 255.0
dx = (np.roll(hgt, -1, 1) - np.roll(hgt, 1, 1)) * 1.6
dy = (np.roll(hgt, -1, 0) - np.roll(hgt, 1, 0)) * 1.6
nz = np.ones_like(hgt)
L = np.sqrt(dx * dx + dy * dy + nz * nz)
nrm = np.stack([(-dx / L) * 0.5 + 0.5, (dy / L) * 0.5 + 0.5, (nz / L) * 0.5 + 0.5], -1)
nimg = Image.fromarray((nrm * 255).astype(np.uint8), "RGB")

out = os.path.join(os.path.dirname(__file__), "..", "texturas")
rgb.save(os.path.join(out, "pelo_vaca.imagem"), "JPEG", quality=88)
nimg.save(os.path.join(out, "pelo_vaca_n.imagem"), "JPEG", quality=90)
print("ok")
