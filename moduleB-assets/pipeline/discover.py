"""IAVAT@R Neural Vice City - scoperta automatica dei set di texture dei personaggi.

Legge tutti i MaterialInstance sotto le cartelle indicate, ne estrae i parametri texture
(BaseColor / Normal / PackedTexture) e scrive un manifest + una ricetta generata.

Uso: python discover.py --game "<gioco>" --root Gameface/Content/ViceCity/Characters --out ../assets-manifest/characters.json
"""
import argparse
import json
import os
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iav_pak import OodleBackend, PakReader  # noqa: E402
import iav_texture as T  # noqa: E402
import iav_uasset as U  # noqa: E402


def game_path_to_pak(obj_path: str) -> str:
    # /Game/ViceCity/X/T_foo.T_foo -> Gameface/Content/ViceCity/X/T_foo
    p = obj_path.split('.')[0]
    if not p.startswith('/Game/'):
        return ''
    return 'Gameface/Content/' + p[len('/Game/'):]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--game', required=True)
    ap.add_argument('--root', action='append', required=True)
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    pak = PakReader(os.path.join(a.game, 'Gameface/Content/Paks/pakchunk0-WindowsNoEditor.pak'), OodleBackend(a.game))
    mis = sorted(p[:-7] for p in pak.index if p.endswith('.uasset') and '/MI_' in p and any(p.startswith(r + '/') for r in a.root))
    sets, parents, errors = [], Counter(), []
    tex_info = {}
    for mi in mis:
        try:
            prm = U.material_parameters(pak.read(mi + '.uasset'), pak.read(mi + '.uexp'))
        except Exception as e:  # noqa: BLE001
            errors.append({'mi': mi, 'error': str(e)})
            continue
        parents[str(prm['parent']).split('.')[-1]] += 1
        tx = {k: game_path_to_pak(v) for k, v in prm['textures'].items() if isinstance(v, str)}
        entry = {'mi': mi, 'parent': prm['parent'], 'basecolor': tx.get('BaseColor', ''), 'normal': tx.get('Normal', ''),
                 'packed': tx.get('PackedTexture', '')}
        for role in ('basecolor', 'normal'):
            t = entry[role]
            if t and t not in tex_info and t + '.uexp' in pak.index:
                try:
                    i = T.parse(pak.read(t + '.uexp'))
                    tex_info[t] = {'format': i.pixel_format, 'size': i.width, 'mips': i.num_mips}
                except Exception as e:  # noqa: BLE001
                    tex_info[t] = {'error': str(e)}
        sets.append(entry)
    textures = sorted({s[r] for s in sets for r in ('basecolor', 'normal') if s[r].startswith('Gameface/Content/ViceCity/')})
    out = {'name': 'characters', 'source_pak': 'Gameface/Content/Paks/pakchunk0-WindowsNoEditor.pak',
           'material_instances': len(mis), 'parents': parents.most_common(), 'sets': sets,
           'texture_info': tex_info, 'errors': errors,
           'assets': textures}
    json.dump(out, open(a.out, 'w', encoding='utf-8'), indent=1)
    fmt = Counter((tex_info.get(t, {}).get('format'), tex_info.get(t, {}).get('size')) for t in textures)
    print(f'MI: {len(mis)}  errori: {len(errors)}  texture uniche (ViceCity): {len(textures)}')
    print('parent piu frequenti:', parents.most_common(6))
    print('formati:', fmt.most_common(8))
    return 0


if __name__ == '__main__':
    sys.exit(main())
