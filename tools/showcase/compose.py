#!/usr/bin/env python3
"""IAVAT@R Neural Vice City - composizione dei confronti prima/dopo.

Prende le catture F5 dell'add-on DLSS5 (coppia <base>.png = NR attivo, <base>_NR_OFF.png = NR spento)
di due sessioni (gioco vanilla e gioco con le mod texture) e compone:
  - un confronto 4 riquadri: Vanilla / Solo texture / Solo DLSS 5 / Completo
  - una fascia di ingrandimenti dello stesso punto nei 4 casi
Gli originali non vengono mai modificati: si leggono e basta.

Uso:  python compose.py scenes.json OUT_DIR
scenes.json: [{"name":..., "title":..., "vanilla":"<path base senza .png>", "mod":"<path base>",
               "crop":[x,y,w,h]}]   (crop in pixel della cattura 1920x1080)
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/lato/Lato-Bold.ttf",
    "/usr/share/fonts/truetype/lato/Lato-Medium.ttf",
    "C:/Windows/Fonts/segoeuib.ttf",
]


def font(size):
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default(size=size)


def label(img, text, sub=None, pos="tl"):
    d = ImageDraw.Draw(img, "RGBA")
    f1, f2 = font(max(18, img.height // 22)), font(max(13, img.height // 34))
    w = max(d.textlength(text, font=f1), d.textlength(sub, font=f2) if sub else 0) + 28
    h = f1.size + (f2.size + 8 if sub else 0) + 20
    x = 12 if pos == "tl" else img.width - w - 12
    d.rounded_rectangle([x, 12, x + w, 12 + h], radius=8, fill=(10, 10, 20, 190))
    d.text((x + 14, 20), text, font=f1, fill=(255, 255, 255, 255))
    if sub:
        d.text((x + 14, 20 + f1.size + 8), sub, font=f2, fill=(110, 230, 255, 255))
    return img


def load(base, nr):
    p = base + (".png" if nr else "_NR_OFF.png")
    return Image.open(p).convert("RGB")


CASES = [  # (sessione, NR, titolo, sottotitolo)
    ("vanilla", False, "VANILLA", "gioco originale"),
    ("mod", False, "SOLO TEXTURE", "IAVAT@R texture pak"),
    ("vanilla", True, "SOLO DLSS 5", "neural rendering"),
    ("mod", True, "COMPLETO", "texture + DLSS 5"),
]


def compose(scene, out_dir):
    imgs = [load(scene[s], nr) for s, nr, _, _ in CASES]
    W, H = 960, 540
    grid = Image.new("RGB", (W * 2, H * 2), (0, 0, 0))
    for i, (im, (_, _, t, st)) in enumerate(zip(imgs, CASES)):
        tile = label(im.resize((W, H), Image.LANCZOS), t, st)
        x, y, cw, ch = [v // 2 for v in scene["crop"]]   # riquadro dello zoom
        ImageDraw.Draw(tile).rectangle([x, y, x + cw, y + ch], outline=(255, 80, 200), width=2)
        grid.paste(tile, ((i % 2) * W, (i // 2) * H))
    d = ImageDraw.Draw(grid)
    d.line([(W, 0), (W, 2 * H)], fill=(255, 255, 255), width=3)
    d.line([(0, H), (2 * W, H)], fill=(255, 255, 255), width=3)

    x, y, cw, ch = scene["crop"]
    zw = (2 * W) // 4
    zh = int(zw * ch / cw)
    strip = Image.new("RGB", (2 * W, zh + 60), (12, 12, 22))
    for i, (im, (_, _, t, _)) in enumerate(zip(imgs, CASES)):
        z = im.crop((x, y, x + cw, y + ch)).resize((zw, zh), Image.LANCZOS)
        strip.paste(label(z, t), (i * zw, 60))
        if i:
            ImageDraw.Draw(strip).line([(i * zw, 60), (i * zw, zh + 60)], fill=(255, 255, 255), width=3)
    ds = ImageDraw.Draw(strip)
    ds.text((16, 14), "ZOOM %d%%  -  %s" % (round(100 * zw / cw), scene.get("zoom_note", "stesso punto nei 4 casi")),
            font=font(28), fill=(255, 255, 255))

    head = Image.new("RGB", (2 * W, 80), (12, 12, 22))
    dh = ImageDraw.Draw(head)
    dh.text((16, 12), "IAVAT@R NEURAL VICE CITY", font=font(40), fill=(255, 80, 200))
    dh.text((620, 24), scene["title"], font=font(28), fill=(255, 255, 255))

    sheet = Image.new("RGB", (2 * W, 80 + 2 * H + strip.height), (0, 0, 0))
    sheet.paste(head, (0, 0)); sheet.paste(grid, (0, 80)); sheet.paste(strip, (0, 80 + 2 * H))
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "IAVATAR_compare_%s.jpg" % scene["name"])
    sheet.save(out, quality=92)
    return out


def main():
    scenes = json.load(open(sys.argv[1], encoding="utf-8"))
    for s in scenes:
        print(compose(s, sys.argv[2]))


if __name__ == "__main__":
    main()
