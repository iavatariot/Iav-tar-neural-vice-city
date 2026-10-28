"""IAVAT@R Neural Vice City - estrazione selettiva degli asset elencati in un manifest.

Uso:  python extract.py --game "<cartella gioco>" --manifest ../assets-manifest/pilot-tommy.json --out ../../work/extract
Estrae solo i file .uasset/.uexp/.ubulk degli asset del manifest (mai il pak intero).
I file estratti sono asset Rockstar: restano in work/ (ignorata da git) e non vanno mai pubblicati.
"""
import argparse
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iav_pak import OodleBackend, PakReader  # noqa: E402

EXTS = ('.uasset', '.uexp', '.ubulk', '.ufont', '.umap')


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--game', required=True)
    ap.add_argument('--manifest', required=True)
    ap.add_argument('--out', required=True)
    a = ap.parse_args()

    man = json.load(open(a.manifest, encoding='utf-8'))
    oodle = OodleBackend(a.game)
    print(f'Oodle: {oodle.name or "NON disponibile"}')
    pak = PakReader(os.path.join(a.game, man['source_pak']), oodle)
    report = []
    for asset in man['assets']:
        found = [p for p in (asset + e for e in EXTS) if p in pak.index]
        if not found:
            print(f'[ERRORE] {asset}: non presente nel pak')
            return 2
        for rel in found:
            data = pak.read(rel)
            dst = os.path.join(a.out, *rel.split('/'))
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, 'wb') as fh:
                fh.write(data)
            sha = hashlib.sha256(data).hexdigest()
            report.append({'path': rel, 'bytes': len(data), 'sha256': sha, 'method': pak.entry(rel).method})
            print(f'[OK] {rel}  {len(data)} byte  sha256 {sha[:16]}')
    with open(os.path.join(a.out, man['name'] + '.extract.json'), 'w', encoding='utf-8') as fh:
        json.dump(report, fh, indent=2)
    return 0


if __name__ == '__main__':
    sys.exit(main())
