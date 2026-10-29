"""IAVAT@R Neural Vice City - test della riscrittura delle Texture2D (iav_texture.rebuild).

Usa i file del gioco installato (letti in memoria, nulla viene salvato):
  1. round-trip: riscrivere una texture con la stessa risoluzione e gli stessi mip deve dare
     .uasset/.uexp/.ubulk IDENTICI byte per byte all'originale;
  2. 2x: la texture ingrandita si rilegge (header, catena mip, offset) e si decodifica alla nuova risoluzione.

Uso:  python tests/moduleB/test_texture_rebuild.py --game "<cartella del gioco>" [--sample 40]
"""
import argparse
import io
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'moduleB-assets', 'pipeline'))
from PIL import Image  # noqa: E402

import build as B  # noqa: E402
import iav_texture as T  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--game', required=True)
    ap.add_argument('--sample', type=int, default=40)
    ap.add_argument('--root', default='Gameface/Content/ViceCity/Textures/')
    a = ap.parse_args()
    src = B.Source(game=a.game)
    cands = sorted(p[:-5] for p in src.pak.index if p.endswith('.uexp') and p.startswith(a.root)
                   and (p.endswith('_BC.uexp') or p.endswith('_N.uexp')))
    rng = random.Random(1986)
    sample = rng.sample(cands, min(a.sample, len(cands)))
    ok = fail = skipped = 0
    for asset in sample:
        ua, ue, ub = src.get(asset + '.uasset'), src.get(asset + '.uexp'), src.get(asset + '.ubulk')
        try:
            info = T.parse(ue)
            if info.pixel_format not in B.ENCODE or info.first_mip != 0 or info.mips[0].width != info.width \
                    or info.width * 2 > B.MAX_SIZE or info.width < B.MIN_EFFECTIVE:
                skipped += 1
                continue
            mips = [T.mip_data(info, ue, ub, m) for m in info.mips]
            a2, e2, b2 = T.rebuild(info, ua, ue, ub, info.width, info.height, mips)
            assert (a2, e2, b2) == (ua, ue, ub), 'round-trip non identico'
            img = Image.open(io.BytesIO(T.to_dds(info, ue, ub))); img.load()
            W, H = info.width * 2, info.height * 2
            big = img.resize((W, H), Image.BICUBIC)
            new, w, h = [], W, H
            while True:
                lvl = big if (w, h) == big.size else big.resize((max(4, w), max(4, h)), Image.BOX)
                new.append(B.encode_mip(lvl, info.pixel_format, T.mip_bytes(info.pixel_format, w, h)))
                if w == 1 and h == 1:
                    break
                w, h = max(1, w // 2), max(1, h // 2)
            a3, e3, b3 = T.rebuild(info, ua, ue, ub, W, H, new)
            i3 = T.parse(e3)
            assert (i3.width, i3.height, i3.num_mips) == (W, H, info.num_mips + 1), 'header 2x'
            assert len(a3) == len(ua), 'uasset: stessa dimensione'
            dec = Image.open(io.BytesIO(T.to_dds(i3, e3, b3))); dec.load()
            assert dec.size == (W, H), 'decodifica 2x'
            ok += 1
        except AssertionError as e:
            fail += 1
            print('[FAIL]', asset, e)
    print(f'Risultato: {ok} superati, {fail} falliti, {skipped} saltati (formato/dimensione non applicabile)')
    return 1 if fail else 0


if __name__ == '__main__':
    sys.exit(main())
