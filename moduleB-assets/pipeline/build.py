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
import time

import numpy as np
from PIL import Image, ImageFilter, ImageOps

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import iav_pak  # noqa: E402
import iav_texture as T  # noqa: E402

ENCODE = {'PF_DXT1': 'DXT1', 'PF_DXT5': 'DXT5', 'PF_BC5': 'BC5'}
MIN_EFFECTIVE = 64


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


def op_unsharp(img, p, ctx):
    """Nitidezza fine (micro-contrasto) sull'albedo, senza toccare l'alpha."""
    rgb = img.convert('RGB').filter(ImageFilter.UnsharpMask(radius=p.get('radius', 1.6),
                                                             percent=p.get('percent', 60),
                                                             threshold=p.get('threshold', 2)))
    if img.mode == 'RGBA':
        rgb.putalpha(img.getchannel('A'))
    return rgb


def _decode_asset_image(asset, src):
    ue, ub = src.get(asset + '.uexp'), src.get(asset + '.ubulk')
    im = Image.open(io.BytesIO(T.to_dds(T.effective(T.parse(ue)), ue, ub)))
    im.load()
    return im


def op_normal_detail(img, p, ctx):
    """Aggiunge micro-dettaglio (pori, grana) alla normal map BC5.
    - dettaglio dall'albedo: gradiente dell'high-pass della luminanza (segue barba, rughe, peli);
    - grana procedurale: rumore fine a 2 scale (pori), con seed fisso per build riproducibili.
    Il risultato e' rinormalizzato; B viene ricostruito dal motore (BC5 = solo R,G)."""
    w, h = img.size
    n = np.asarray(img.convert('RGB'), dtype=np.float32)[..., :2] / 127.5 - 1.0
    nz = np.sqrt(np.clip(1.0 - (n ** 2).sum(-1), 0.0, 1.0))
    height = np.zeros((h, w), np.float32)
    if p.get('albedo'):
        alb = _decode_asset_image(p['albedo'], ctx['src']).convert('L').resize((w, h), Image.BICUBIC)
        lum = np.asarray(alb, np.float32) / 255.0
        blur = np.asarray(alb.filter(ImageFilter.GaussianBlur(p.get('albedo_radius', 3.0))), np.float32) / 255.0
        height += (lum - blur) * p.get('albedo_strength', 1.0)
    rng = np.random.default_rng(p.get('seed', 1986))
    for scale, amp in ((1, 1.0), (2, 0.6)):
        noise = rng.standard_normal((h // scale, w // scale)).astype(np.float32)
        n8 = Image.fromarray(np.clip(noise * 40 + 128, 0, 255).astype(np.uint8), 'L')
        ni = n8.resize((w, h), Image.BICUBIC).filter(ImageFilter.GaussianBlur(0.6 * scale))
        height += (np.asarray(ni, np.float32) - 128.0) / 40.0 * amp * p.get('pore_strength', 0.02)
    gy, gx = np.gradient(height)
    k = p.get('bump', 6.0)
    dx, dy = -gx * k, -gy * k
    # combinazione "whiteout": somma delle pendenze, z moltiplicato
    rx, ry, rz = n[..., 0] + dx, n[..., 1] + dy, nz
    l = np.sqrt(rx * rx + ry * ry + rz * rz)
    rx, ry = rx / l, ry / l
    out = np.zeros((h, w, 3), np.uint8)
    out[..., 0] = np.clip((rx + 1.0) * 127.5, 0, 255)
    out[..., 1] = np.clip((ry + 1.0) * 127.5, 0, 255)
    return Image.fromarray(out, 'RGB')


OPS = {'hue_tint': lambda img, p, ctx: op_hue_tint(img, p), 'unsharp': op_unsharp, 'normal_detail': op_normal_detail}


class Source:
    """Legge gli asset da una cartella estratta oppure direttamente dal pak del gioco (nessuna copia su disco)."""
    def __init__(self, extract_dir=None, game=None):
        self.dir = extract_dir
        self.pak = None
        if game:
            self.pak = iav_pak.PakReader(os.path.join(game, 'Gameface/Content/Paks/pakchunk0-WindowsNoEditor.pak'),
                                         iav_pak.OodleBackend(game))

    def get(self, rel):
        if self.pak is not None:
            return self.pak.read(rel) if rel in self.pak.index else None
        path = os.path.join(self.dir, *rel.split('/'))
        return open(path, 'rb').read() if os.path.exists(path) else None


def expand_rules(recipe, manifest_dir):
    """Trasforma le regole (per ruolo di texture nei MaterialInstance) in una lista di texture con operazioni."""
    items, seen = [], set()
    for rule in recipe.get('rules', []):
        man = json.load(open(os.path.join(manifest_dir, rule['manifest']), encoding='utf-8'))
        parents = set(rule.get('parents', []))
        for s_ in man['sets']:
            par = (s_.get('parent') or '').split('.')[-1]
            if parents and par not in parents:
                continue
            bc, nm = s_.get('basecolor', ''), s_.get('normal', '')
            if not bc.startswith('Gameface/Content/ViceCity/'):
                continue
            min_size = rule.get('min_size', 0)
            fmt_ok = lambda t: (man['texture_info'].get(t, {}).get('format') in ENCODE  # noqa: E731
                                and (man['texture_info'].get(t, {}).get('size') or 0) >= min_size)
            if rule.get('basecolor_ops') and bc not in seen and fmt_ok(bc):
                items.append({'asset': bc, 'ops': rule['basecolor_ops']}); seen.add(bc)
            if rule.get('normal_ops') and nm.startswith('Gameface/Content/ViceCity/') and nm not in seen and fmt_ok(nm):
                ops = [dict(o, albedo=bc) if o['op'] == 'normal_detail' else o for o in rule['normal_ops']]
                items.append({'asset': nm, 'ops': ops}); seen.add(nm)
    return items


def process_texture(asset: str, ops: list, src):
    ue, ub = src.get(asset + '.uexp'), src.get(asset + '.ubulk')
    if ue is None:
        raise FileNotFoundError(asset)
    info = T.effective(T.parse(ue))
    if not info.mips or info.width < MIN_EFFECTIVE:
        raise ValueError(f'texture troppo piccola o ridotta in cottura (mip 0 = {info.width}px): saltata')
    if info.pixel_format not in ENCODE:
        raise ValueError(f'{asset}: formato {info.pixel_format} non ancora supportato in scrittura')
    img = Image.open(io.BytesIO(T.to_dds(info, ue, ub)))
    img.load()
    for op in ops:
        img = OPS[op['op']](img, op, {'src': src})
    if img.size != (info.width, info.height):
        raise ValueError('la lavorazione ha cambiato la risoluzione: non consentito')
    mips = []
    for m in info.mips:
        w = max(4, m.width)
        h = max(4, m.height)
        level = img if (w, h) == img.size else img.resize((w, h), Image.BOX)
        mips.append(encode_mip(level, info.pixel_format, m.size))
    new_ue, new_ub = T.inject(info, ue, ub, mips)
    out = {asset + '.uasset': src.get(asset + '.uasset'), asset + '.uexp': new_ue}
    if new_ub is not None:
        out[asset + '.ubulk'] = new_ub
    return out, info


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--recipe', required=True)
    ap.add_argument('--extract', help='cartella con gli asset estratti')
    ap.add_argument('--game', help='cartella del gioco: legge direttamente dal pak (consigliato)')
    ap.add_argument('--out', required=True)
    ap.add_argument('--no-compress', action='store_true')
    ap.add_argument('--previews', type=int, default=6, help='quante anteprime PNG salvare')
    ap.add_argument('--time-budget', type=float, default=1e9,
                    help='secondi massimi per esecuzione: oltre, salva e termina con codice 3 (rilanciare per continuare)')
    ap.add_argument('--no-pak', action='store_true', help='lavora le texture senza scrivere il pak')
    ap.add_argument('--verify-sample', type=int, default=64, help='quanti file del pak rileggere e confrontare')
    a = ap.parse_args()
    if not (a.extract or a.game):
        ap.error('serve --extract oppure --game')
    recipe = json.load(open(a.recipe, encoding='utf-8'))
    src = Source(a.extract, a.game)
    items = list(recipe.get('textures', [])) + expand_rules(recipe, os.path.join(os.path.dirname(os.path.abspath(a.recipe)), '..', 'assets-manifest'))
    os.makedirs(a.out, exist_ok=True)
    t0 = time.time()
    over = lambda: time.time() - t0 > a.time_budget  # noqa: E731
    files: dict[str, str] = {}          # percorso nel pak -> file in cache (mai tutto in memoria)
    report = {'recipe': recipe['name'], 'assets': [], 'skipped': []}
    pending = 0
    # ---------------------------------------------------------------- 1. lavorazione (con cache)
    for n, item in enumerate(items, 1):
        key = hashlib.sha256(json.dumps(item, sort_keys=True).encode()).hexdigest()[:16]
        cdir = os.path.join(a.out, 'cache', key)
        done = os.path.join(cdir, 'done.json')
        if not os.path.isfile(done):
            if over():
                pending += 1
                continue
            try:
                out, info = process_texture(item['asset'], item['ops'], src)
            except (ValueError, FileNotFoundError, OSError) as e:
                print(f"[SALTATO] {item['asset']}: {e}")
                os.makedirs(cdir, exist_ok=True)
                json.dump({'skipped': str(e)}, open(done, 'w', encoding='utf-8'))
            else:
                os.makedirs(cdir, exist_ok=True)
                for rel, data in out.items():
                    open(os.path.join(cdir, os.path.basename(rel)), 'wb').write(data)
                meta_info = {'asset': item['asset'], 'format': info.pixel_format, 'size': [info.width, info.height], 'mips': info.num_mips}
                json.dump({'files': sorted(out), 'info': meta_info}, open(done, 'w', encoding='utf-8'))
                print(f"[{n}/{len(items)}] {item['asset']}  {info.pixel_format} {info.width}x{info.height}")
                if n <= a.previews:
                    ue = out[item['asset'] + '.uexp']
                    Image.open(io.BytesIO(T.to_dds(T.effective(T.parse(ue)), ue, out.get(item['asset'] + '.ubulk')))) \
                        .convert('RGB').resize((512, 512)).save(os.path.join(a.out, os.path.basename(item['asset']) + '_preview.png'))
        meta = json.load(open(done, encoding='utf-8'))
        if meta.get('skipped'):
            report['skipped'].append({'asset': item['asset'], 'reason': meta['skipped']})
            continue
        for rel in meta['files']:
            files[rel] = os.path.join(cdir, os.path.basename(rel))
        report['assets'].append(meta['info'])
    if pending:
        print(f'[PARZIALE] lavorazione: {pending} texture ancora da fare. Rilancia lo stesso comando.')
        return 3
    print(f"[OK] lavorazione completa: {len(report['assets'])} texture, {len(report['skipped'])} saltate")
    if a.no_pak:
        return 0
    # ---------------------------------------------------------------- 2. pak (streaming, riprendibile)
    pak_path = os.path.join(a.out, recipe.get('pak_name', 'IAVATAR_NeuralViceCity_P.pak'))
    w = iav_pak.PakWriter(pak_path, '../../../', compress=not a.no_compress)
    todo = [r for r in sorted(files) if r not in w.done]
    for k, rel in enumerate(todo):
        if over():
            w._save()
            print(f'[PARZIALE] pak: {len(w.done)}/{len(files)} file scritti. Rilancia lo stesso comando.')
            return 3
        w.add(rel, open(files[rel], 'rb').read(), save=(k % 25 == 0))
    info = w.finalize()
    # ---------------------------------------------------------------- 3. verifica a campione
    rd = iav_pak.PakReader(pak_path)
    if set(rd.index) != set(files):
        raise IOError('indice del pak diverso dai file attesi')
    import random
    sample = random.Random(1986).sample(sorted(files), min(a.verify_sample, len(files)))
    for rel in sample:
        if rd.read(rel) != open(files[rel], 'rb').read():
            raise IOError('verifica pak fallita su ' + rel)
    report['pak'] = {'path': pak_path, 'files': info['files'], 'bytes': info['bytes'],
                     'usize': info['usize'], 'csize': info['csize'], 'verified_sample': len(sample)}
    json.dump(report, open(os.path.join(a.out, 'build-report.json'), 'w', encoding='utf-8'), indent=2)
    print(f"[OK] pak {pak_path}: {len(report['assets'])} texture, {info['files']} file, "
          f"{info['bytes'] / 2**20:.1f} MB (non compresso {info['usize'] / 2**20:.1f} MB); indice completo, "
          f"{len(sample)} file riletti e identici")
    return 0


if __name__ == '__main__':
    sys.exit(main())
