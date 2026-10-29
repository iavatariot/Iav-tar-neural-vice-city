#!/usr/bin/env python3
"""IAVAT@R Neural Vice City - tavole "texture originale vs IAVAT@R".

Per ogni materiale (coppia BaseColor + Normal) scelto con --match, decodifica:
  - la texture originale direttamente dal pak del gioco (in memoria, nulla viene salvato su disco
    tranne l'immagine di confronto, che e' un'anteprima ridotta/ritagliata);
  - la texture lavorata dalla cache della build (work/<build>/cache).
Rende il materiale illuminato con luce radente (BaseColor x shading dalla normal map), che e' il
modo in cui il rilievo si vede in gioco, e affianca originale e versione IAVAT@R.

Uso:
  python texture_sheet.py --recipe ../../moduleB-assets/recipes/environment-v2.json --build ../../work/build_env2 \
      --game "<cartella gioco>" --match "Concrete|Wall|Plaster" --limit 6 --out ../../work/showcase/final
"""
import argparse
import hashlib
import io
import json
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'moduleB-assets', 'pipeline'))
sys.path.insert(0, HERE)
import build as B  # noqa: E402
import iav_texture as T  # noqa: E402
from compose import font, label  # noqa: E402


def decode(ue, ub):
    im = Image.open(io.BytesIO(T.to_dds(T.effective(T.parse(ue)), ue, ub)))
    im.load()
    return im


def from_cache(build, item):
    key = hashlib.sha256(json.dumps(item, sort_keys=True).encode()).hexdigest()[:16]
    cdir = os.path.join(build, 'cache', key)
    done = json.load(open(os.path.join(cdir, 'done.json'), encoding='utf-8'))
    if done.get('skipped'):
        return None
    rd = lambda ext: (open(os.path.join(cdir, os.path.basename(item['asset'] + ext)), 'rb').read()  # noqa: E731
                      if os.path.exists(os.path.join(cdir, os.path.basename(item['asset'] + ext))) else None)
    return decode(rd('.uexp'), rd('.ubulk'))


def shade(base, normal, light=(-0.55, 0.45, 0.70)):
    """BaseColor x (ambiente + diffusa) con luce radente; la normal BC5 ha solo R,G: Z ricostruita."""
    w, h = base.size
    n = np.asarray(normal.convert('RGB').resize((w, h), Image.BICUBIC), np.float32)[..., :2] / 127.5 - 1.0
    nz = np.sqrt(np.clip(1.0 - (n ** 2).sum(-1), 0.0, 1.0))
    L = np.array(light, np.float32); L /= np.linalg.norm(L)
    ndl = np.clip(n[..., 0] * L[0] + n[..., 1] * L[1] + nz * L[2], 0.0, 1.0)
    s = 0.25 + 0.95 * ndl
    rgb = np.asarray(base.convert('RGB'), np.float32) / 255.0
    return Image.fromarray(np.clip(rgb * s[..., None] * 255.0, 0, 255).astype(np.uint8), 'RGB')


def crop_center(im, size):
    w, h = im.size
    c = min(size, w, h)
    x, y = (w - c) // 2, (h - c) // 2
    return im.crop((x, y, x + c, y + c))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--recipe', required=True)
    ap.add_argument('--build', required=True)
    ap.add_argument('--game', required=True)
    ap.add_argument('--match', default='.')
    ap.add_argument('--limit', type=int, default=6)
    ap.add_argument('--crop', type=int, default=384, help='lato del ritaglio (pixel della texture)')
    ap.add_argument('--tile', type=int, default=640, help='lato del riquadro nella tavola')
    ap.add_argument('--out', required=True)
    ap.add_argument('--name', default='textures')
    a = ap.parse_args()

    recipe = json.load(open(a.recipe, encoding='utf-8'))
    items = B.expand_rules(recipe, os.path.join(os.path.dirname(os.path.abspath(a.recipe)), '..', 'assets-manifest'))
    by_asset = {i['asset']: i for i in items}
    src = B.Source(game=a.game)
    rx = re.compile(a.match, re.I)

    pairs = []
    for it in items:
        o = next((op for op in it['ops'] if op['op'] == 'normal_detail'), None)
        if not o or not rx.search(it['asset']) or o['albedo'] not in by_asset:
            continue
        pairs.append((by_asset[o['albedo']], it))
        if len(pairs) >= a.limit:
            break
    if not pairs:
        sys.exit('nessun materiale corrisponde a --match')

    T_ = a.tile
    rows = []
    for bc_item, nm_item in pairs:
        try:
            bo = B._decode_asset_image(bc_item['asset'], src)
            no = B._decode_asset_image(nm_item['asset'], src)
            bm, nmod = from_cache(a.build, bc_item), from_cache(a.build, nm_item)
        except (OSError, ValueError, KeyError, FileNotFoundError) as e:
            print('[SALTATO]', nm_item['asset'], e)
            continue
        if bm is None or nmod is None:
            continue
        orig = crop_center(shade(bo, no), a.crop).resize((T_, T_), Image.LANCZOS)
        mod = crop_center(shade(bm, nmod), a.crop).resize((T_, T_), Image.LANCZOS)
        row = Image.new('RGB', (2 * T_ + 6, T_ + 44), (12, 12, 22))
        row.paste(label(orig, 'ORIGINALE'), (0, 44)); row.paste(label(mod, 'IAVAT@R'), (T_ + 6, 44))
        ImageDraw.Draw(row).text((12, 8), '%s   (%dx%d, ritaglio %dpx, luce radente)' % (
            os.path.basename(nm_item['asset']).replace('_N', ''), bo.width, bo.height, a.crop),
            font=font(24), fill=(255, 255, 255))
        rows.append(row)
        print('[OK]', nm_item['asset'])
    head = Image.new('RGB', (2 * T_ + 6, 70), (12, 12, 22))
    dh = ImageDraw.Draw(head)
    dh.text((14, 12), 'IAVAT@R NEURAL VICE CITY', font=font(36), fill=(255, 80, 200))
    dh.text((560, 22), 'Texture: originale vs IAVAT@R', font=font(26), fill=(255, 255, 255))
    sheet = Image.new('RGB', (head.width, head.height + sum(r.height for r in rows)), (0, 0, 0))
    sheet.paste(head, (0, 0)); y = head.height
    for r in rows:
        sheet.paste(r, (0, y)); y += r.height
    os.makedirs(a.out, exist_ok=True)
    out = os.path.join(a.out, 'IAVATAR_%s.jpg' % a.name)
    sheet.save(out, quality=90)
    print(out)


if __name__ == '__main__':
    main()
