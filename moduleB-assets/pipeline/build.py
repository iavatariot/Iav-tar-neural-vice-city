"""IAVAT@R Neural Vice City - Modulo B: lavorazione texture + pack + (opzionale) deploy.

Uso:
  python build.py --recipe ../recipes/smoketest-tommy.json --extract ../../work/extract --out ../../work/build
Produce:  work/build/IAVATAR_NeuralViceCity_P.pak  +  build-report.json
Il deploy nel gioco lo fa l'installer (Modulo A) o deploy.ps1, mai questo script.

Vincoli: stessa risoluzione, stesso formato BC e stesso numero di mip dell'originale (vedi iav_texture).
"""
import argparse
import hashlib
import io
import json
import os
import sys

from PIL import Image, ImageOps

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import iav_pak  # noqa: E402
import iav_texture as T  # noqa: E402

ENCODE = {'PF_DXT1': 'DXT1', 'PF_DXT5': 'DXT5', 'PF_BC5': 'BC5'}


def encode_mip(img: Image.Image, fmt: str, expected: int) -> bytes:
    b = io.BytesIO()
    src = img.convert('RGBA' if fmt == 'PF_DXT5' else 'RGB')
    src.save(b, 'DDS', pixel_format=ENCODE[fmt])
    raw = b.getvalue()
    hdr = 128 + (20 if raw[84:88] == b'DX10' else 0)
    data = raw[hdr:hdr + expected]
    if len(data) != expected:
        raise ValueError(f'encoder: {len(data)} byte, attesi {expected}')
    return data


# ------------------------------------------------------------------------------- operazioni
def op_hue_tint(img, p):
    """Smoke test: tinta evidente per verificare che il gioco carichi il nostro pak."""
    rgb = img.convert('RGB')
    gray = ImageOps.grayscale(rgb)
    tint = ImageOps.colorize(gray, black=(0, 0, 40), white=tuple(p.get('color', [90, 160, 255])))
    out = Image.blend(rgb, tint, p.get('amount', 0.85))
    if img.mode == 'RGBA':
        out.putalpha(img.getchannel('A'))
    return out


OPS = {'hue_tint': op_hue_tint}


def process_texture(asset: str, ops: list, src_dir: str):
    base = os.path.join(src_dir, *asset.split('/'))
    ue = open(base + '.uexp', 'rb').read()
    ub = open(base + '.ubulk', 'rb').read() if os.path.exists(base + '.ubulk') else None
    info = T.parse(ue)
    if info.pixel_format not in ENCODE:
        raise ValueError(f'{asset}: formato {info.pixel_format} non ancora supportato in scrittura')
    img = Image.open(io.BytesIO(T.to_dds(info, ue, ub)))
    img.load()
    for op in ops:
        img = OPS[op['op']](img, op)
    if img.size != (info.width, info.height):
        raise ValueError('la lavorazione ha cambiato la risoluzione: non consentito')
    mips = []
    for m in info.mips:
        w = max(4, m.width)
        h = max(4, m.height)
        level = img if (w, h) == img.size else img.resize((w, h), Image.BOX)
        mips.append(encode_mip(level, info.pixel_format, m.size))
    new_ue, new_ub = T.inject(info, ue, ub, mips)
    out = {asset + '.uasset': open(base + '.uasset', 'rb').read(), asset + '.uexp': new_ue}
    if new_ub is not None:
        out[asset + '.ubulk'] = new_ub
    return out, info


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--recipe', required=True)
    ap.add_argument('--extract', required=True)
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    recipe = json.load(open(a.recipe, encoding='utf-8'))
    os.makedirs(a.out, exist_ok=True)
    files = {}
    report = {'recipe': recipe['name'], 'assets': []}
    for item in recipe['textures']:
        out, info = process_texture(item['asset'], item['ops'], a.extract)
        files.update(out)
        report['assets'].append({'asset': item['asset'], 'format': info.pixel_format,
                                 'size': [info.width, info.height], 'mips': info.num_mips})
        print(f"[OK] {item['asset']}  {info.pixel_format} {info.width}x{info.height} mip {info.num_mips}")
        prev = os.path.join(a.out, os.path.basename(item['asset']) + '_preview.png')
        Image.open(io.BytesIO(T.to_dds(T.parse(out[item['asset'] + '.uexp']), out[item['asset'] + '.uexp'],
                                       out.get(item['asset'] + '.ubulk')))).convert('RGB').resize((512, 512)).save(prev)
    pak_path = os.path.join(a.out, recipe.get('pak_name', 'IAVATAR_NeuralViceCity_P.pak'))
    info = iav_pak.write_pak(pak_path, files, mount='../../../')
    rd = iav_pak.PakReader(pak_path)
    for rel, data in files.items():
        if rd.read(rel) != data:
            raise IOError('verifica pak fallita su ' + rel)
    report['pak'] = {'path': pak_path, 'files': sorted(files), 'bytes': info['bytes'],
                     'sha256': hashlib.sha256(open(pak_path, 'rb').read()).hexdigest()}
    json.dump(report, open(os.path.join(a.out, 'build-report.json'), 'w', encoding='utf-8'), indent=2)
    print(f"[OK] pak {pak_path}  {info['files']} file  {info['bytes']} byte  (riletto e verificato)")
    return 0


if __name__ == '__main__':
    sys.exit(main())
