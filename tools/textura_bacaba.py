#!/usr/bin/env python3
"""Monta a textura da casca da bacaba a partir de uma foto de casca lisa e cinza.

Foto de base: "39 High-res bark texture photos" de bart (OpenGameArt, CC-BY 3.0),
arquivo 2010-09-04_13-26-24_2.jpg. Passos:
 1. recorta o meio da foto e tira a variação de luz (fica só o desenho da casca);
 2. deixa emendável dos lados e em cima/embaixo (dá a volta no tronco sem costura);
 3. desenha os anéis da bacaba (cicatrizes das folhas que caíram): risco escuro
    tortinho a cada 8 a 13 cm com a beirada clara, um ou outro falhado;
 4. gera o mapa de relevo (normal map) a partir disso.
A imagem cobre 0,75 m em volta do tronco (512 px) e 1,5 m de altura (1024 px).
Uso: python3 tools/textura_bacaba.py caminho/da/foto.jpg
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'texturas')
W, H = 512, 1024
rng = np.random.default_rng(73)


def seamless(a):
    """Emendável: mistura a imagem com ela mesma deslocada meia volta, com peso
    que some nas bordas."""
    h, w = a.shape[:2]
    sh = np.roll(np.roll(a, w // 2, axis=1), h // 2, axis=0)
    y = np.abs(np.linspace(-1, 1, h))[:, None]
    x = np.abs(np.linspace(-1, 1, w))[None, :]
    m = np.clip(np.maximum(x, y) * 1.6 - 0.6, 0, 1) ** 1.5
    if a.ndim == 3:
        m = m[..., None]
    return a * (1 - m) + sh * m


def main(src):
    im = Image.open(src).convert('RGB')
    w0, h0 = im.size
    # pedaço do meio, em pé (a foto vem deitada: gira)
    crop = im.crop((int(w0 * 0.18), int(h0 * 0.08), int(w0 * 0.82), int(h0 * 0.92))).rotate(90, expand=True)
    crop = crop.resize((W, H), Image.LANCZOS)
    a = np.asarray(crop).astype(np.float32) / 255.0
    # tira a luz da foto (sombra grande, sol de um lado)
    blur = np.asarray(crop.filter(ImageFilter.GaussianBlur(70))).astype(np.float32) / 255.0
    lum = a.mean(axis=2, keepdims=True)
    lb = blur.mean(axis=2, keepdims=True)
    a = a / np.maximum(lb, 0.05) * 0.5
    a = np.clip(a, 0, 1.4)
    a = seamless(a)
    # cor da bacaba: cinza-claro levemente esverdeado; o desenho da foto fica, mais suave
    g = a.mean(axis=2, keepdims=True)
    tint = np.array([0.60, 0.59, 0.54], np.float32)
    detail = (g - g.mean()) * 0.85
    col = tint + detail + (a - g) * 0.6
    # anéis: posições que fecham certinho em 1,5 m
    ys = []
    y = 0.0
    while True:
        y += rng.uniform(0.08, 0.13) * H / 1.5
        if y > H - 40:
            break
        ys.append(y)
    ys = np.array(ys) * (H / (ys[-1] + (ys[1] - ys[0])))
    height = np.zeros((H, W), np.float32)
    xx = np.arange(W)
    ring_dark = np.zeros((H, W), np.float32)
    ring_lip = np.zeros((H, W), np.float32)
    yy = np.arange(H)[:, None]
    for y0 in ys:
        ph = rng.uniform(0, 2 * np.pi, 3)
        wob = (np.sin(xx / W * 2 * np.pi + ph[0]) * 6 + np.sin(xx / W * 2 * np.pi * 3 + ph[1]) * 2.5
               + np.sin(xx / W * 2 * np.pi * 7 + ph[2]) * 1.2)
        yc = y0 + wob[None, :]
        d = (yy - yc)
        d = (d + H / 2) % H - H / 2                       # emenda em cima/embaixo
        strength = 0.6 + 0.4 * np.sin(xx / W * 2 * np.pi * rng.integers(1, 4) + rng.uniform(0, 6))[None, :]
        strength = np.clip(strength + rng.uniform(-0.2, 0.2), 0.15, 1.0)
        ring_dark += np.exp(-(d / 2.2) ** 2) * strength
        ring_lip += np.exp(-((d + 5.0) / 3.5) ** 2) * strength * 0.8
        # degrau: a casca de cima do anel fica um tiquinho mais saliente
        height += (np.clip(-d / 14.0, 0, 1) * np.exp(-np.clip(-d, 0, None) / 30.0)) * strength
    col = col * (1 - np.clip(ring_dark, 0, 1)[..., None] * 0.45) + np.clip(ring_lip, 0, 1)[..., None] * 0.06
    col = np.clip(col, 0, 1)
    # relevo: desenho fino da foto + anéis
    fine = (g[..., 0] - np.asarray(Image.fromarray((g[..., 0] * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3))).astype(np.float32) / 255.0)
    hmap = height * 0.6 - np.clip(ring_dark, 0, 1) * 0.5 + fine * 2.0
    gx = (np.roll(hmap, -1, axis=1) - np.roll(hmap, 1, axis=1)) * 2.0
    gy = (np.roll(hmap, -1, axis=0) - np.roll(hmap, 1, axis=0)) * 2.0
    n = np.dstack([-gx, gy, np.ones_like(gx)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    nimg = ((n * 0.5 + 0.5) * 255).astype(np.uint8)
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray((col * 255).astype(np.uint8)).save(os.path.join(OUT, 'bacaba_casca.jpg'), quality=88)
    Image.fromarray(nimg).save(os.path.join(OUT, 'bacaba_casca_n.jpg'), quality=92)
    for f in ['bacaba_casca.jpg', 'bacaba_casca_n.jpg']:
        p = os.path.join(OUT, f)
        os.replace(p, p[:-4] + '.imagem')
        print(f, os.path.getsize(p[:-4] + '.imagem'))


if __name__ == '__main__':
    main(sys.argv[1])
