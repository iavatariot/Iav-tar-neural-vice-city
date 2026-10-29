"""IAVAT@R Neural Vice City - esporta le texture da ingrandire con l'IA (Real-ESRGAN).

Per ogni texture della ricetta con l'operazione `ai_upscale` scrive un PNG (RGB) con un bordo di padding
nella cartella di input dell'upscaler. Le texture ripetute (Tilables) usano un bordo "wrap" per non creare
cuciture. Il PNG resta in work/ (gitignored): non va mai distribuito.

Uso:
  python upscale_export.py --recipe ../recipes/environment-hd-test.json --game "<cartella gioco>" --out ../../work/upscale/in
Poi sul PC (GPU): IAVATAR_Upscale.ps1, che produce ../../work/upscale/out
"""
import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build as B  # noqa: E402
import iav_texture as T  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--recipe', required=True)
    ap.add_argument('--game', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--time-budget', type=float, default=1e9)
    a = ap.parse_args()
    recipe = json.load(open(a.recipe, encoding='utf-8'))
    items = list(recipe.get('textures', [])) + B.expand_rules(
        recipe, os.path.join(os.path.dirname(os.path.abspath(a.recipe)), '..', 'assets-manifest'))
    src = B.Source(game=a.game)
    os.makedirs(a.out, exist_ok=True)
    t0, n, pending = time.time(), 0, 0
    for it in items:
        op = next((o for o in it['ops'] if o['op'] == 'ai_upscale'), None)
        if not op:
            continue
        dst = os.path.join(a.out, B.upscale_name(it['asset']))
        if os.path.isfile(dst):
            continue
        if time.time() - t0 > a.time_budget:
            pending += 1
            continue
        try:
            ue = src.get(it['asset'] + '.uexp')
            info = T.effective(T.parse(ue))
            if max(info.width, info.height) * op.get('scale', 2) > B.MAX_SIZE or info.width < B.MIN_EFFECTIVE:
                print('[SALTATO]', it['asset'], f'{info.width}x{info.height}px')
                continue
            img = B._decode_asset_image(it['asset'], src)
        except (ValueError, OSError, TypeError) as e:
            print('[SALTATO]', it['asset'], e)
            continue
        wrap = '/Tilables/' in it['asset']
        B.pad_for_upscale(img, op.get('pad', 16), wrap).save(dst + '.tmp.png')
        os.replace(dst + '.tmp.png', dst)
        n += 1
        print(f'[{n}] {it["asset"]} {img.width}x{img.height} wrap={wrap}')
    if pending:
        print(f'[PARZIALE] {pending} texture ancora da esportare. Rilancia.')
        return 3
    print(f'[OK] esportate {n} texture in {a.out}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
