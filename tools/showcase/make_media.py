"""IAVAT@R Neural Vice City - immagini per Nexus + video di presentazione (1920x1080, 30 fps)."""
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H, FPS = 1920, 1080, 30
SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'src')
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out')
os.makedirs(OUT, exist_ok=True)
MAG, CYAN, WHITE, INK = (255, 80, 200), (110, 230, 255), (255, 255, 255), (10, 10, 20)
FB = '/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf'
FM = '/usr/share/fonts/opentype/inter/Inter-Medium.otf'
FSB = '/usr/share/fonts/opentype/inter/Inter-SemiBold.otf'


def font(path, size):
    return ImageFont.truetype(path, size)


def img(name):
    return Image.open(os.path.join(SRC, name)).convert('RGB')


SCENES = [  # nome, titolo, vanilla, completo, zoom vanilla, zoom completo, etichetta completo
    ('muretto', 'Beach promenade · stone wall', 'muretto_v.jpg', 'muretto_h.jpg', (1000, 570, 360, 202), (480, 600, 360, 202), 'DLSS 5 + HD textures'),
    ('hotel', 'Ocean Beach hotel lobby', 'hotel_v.jpg', 'hotel_h.jpg', (1180, 770, 448, 252), (1180, 770, 448, 252), 'DLSS 5 + HD textures'),
    ('palma', 'Ocean Drive · Tommy', 'palma_v.jpg', 'palma_h.jpg', (640, 460, 480, 270), (600, 470, 480, 270), 'DLSS 5 + HD textures'),
    ('strada', 'Ocean Drive · asphalt', 'strada_v.jpg', 'strada_h.jpg', (1050, 860, 448, 252), (1120, 880, 448, 252), 'DLSS 5 + HD textures'),
    ('cemento', 'Concrete wall', 'cemento_v.jpg', 'cemento_h.jpg', (1180, 560, 480, 270), (1180, 560, 480, 270), 'DLSS 5 + textures'),
]
COVER_CROP = (400, 200, 1840, 1010)   # palma_h senza HUD


# ------------------------------------------------------------------ elementi grafici
def tag(draw, x, y, text, sub=None, accent=CYAN, size=34):
    f1, f2 = font(FB, size), font(FSB, int(size * 0.6))
    w = max(draw.textlength(text, font=f1), draw.textlength(sub, font=f2) if sub else 0) + 40
    h = size + (int(size * 0.6) + 10 if sub else 0) + 26
    draw.rounded_rectangle([x, y, x + w, y + h], radius=10, fill=(10, 10, 20, 205))
    draw.rectangle([x, y, x + 6, y + h], fill=accent + (255,))
    draw.text((x + 22, y + 10), text, font=f1, fill=WHITE)
    if sub:
        draw.text((x + 22, y + 16 + size), sub, font=f2, fill=accent)


def caption(draw, text, size=30):
    f = font(FSB, size)
    w = draw.textlength(text, font=f) + 48
    x, y = (W - w) / 2, H - 92
    draw.rounded_rectangle([x, y, x + w, y + size + 28], radius=12, fill=(10, 10, 20, 200))
    draw.text((x + 24, y + 12), text, font=f, fill=WHITE)


def brand(draw):
    f = font(FB, 26)
    t = 'IAVAT@R NEURAL VICE CITY'
    draw.text((W - draw.textlength(t, font=f) - 40, 34), t, font=f, fill=MAG + (235,))


def kenburns(im, t, z0=1.0, z1=1.04, cx=0.5, cy=0.5):
    """Ritaglio con zoom lento (t in 0..1) riportato a 1920x1080."""
    z = z0 + (z1 - z0) * t
    w, h = im.width / z, im.height / z
    x = (im.width - w) * cx
    y = (im.height - h) * cy
    return im.crop((int(x), int(y), int(x + w), int(y + h))).resize((W, H), Image.BICUBIC)


def zoom_panel(v, h, cv, ch, title):
    bg = Image.new('RGB', (W, H), INK)
    d = ImageDraw.Draw(bg, 'RGBA')
    pw, ph = 900, 506
    for i, (im, c, lab, acc) in enumerate(((v, cv, 'VANILLA', CYAN), (h, ch, 'IAVAT@R', MAG))):
        x0 = 40 + i * (pw + 40)
        crop = im.crop((c[0], c[1], c[0] + c[2], c[1] + c[3])).resize((pw, ph), Image.LANCZOS)
        bg.paste(crop, (x0, 281))
        d.rectangle([x0 - 2, 279, x0 + pw + 1, 281 + ph + 1], outline=acc + (255,), width=3)
        tag(d, x0 + 16, 297, lab, accent=acc, size=30)
    f = font(FB, 52)
    d.text((40, 120), 'DETAIL', font=f, fill=MAG)
    d.text((40 + d.textlength('DETAIL  ', font=f), 132), title, font=font(FSB, 36), fill=WHITE)
    d.text((40, 830), 'Same surface, game time may differ between captures.', font=font(FM, 26), fill=(170, 170, 190))
    brand(d)
    return bg


def cover_base():
    im = img('palma_h.jpg').crop(COVER_CROP).resize((W, H), Image.LANCZOS)
    return im


def cover_overlay(im, alpha_title=1.0, alpha_sub=1.0):
    im = im.copy()
    ov = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    for y in range(0, 420):   # sfumatura scura in alto per il titolo
        a = int(200 * max(0.0, 1 - y / 420) ** 1.2)
        d.line([(0, y), (W, y)], fill=(10, 8, 25, a))
    im = Image.alpha_composite(im.convert('RGBA'), ov)
    d = ImageDraw.Draw(im)
    if alpha_title > 0:
        a = int(255 * alpha_title)
        d.text((90, 70), 'IAVAT@R', font=font(FB, 56), fill=MAG + (a,))
        d.text((86, 128), 'NEURAL VICE CITY', font=font(FB, 112), fill=WHITE + (a,))
    if alpha_sub > 0:
        a = int(255 * alpha_sub)
        d.rounded_rectangle([60, 830, 1380, 1030], radius=16, fill=(10, 8, 25, int(190 * alpha_sub)))
        d.text((92, 852), 'DLSS 5 Neural Rendering  ·  2,700+ AI-upscaled HD textures', font=font(FSB, 38), fill=CYAN + (a,))
        d.text((92, 912), 'Built from your own game files  ·  one-command install  ·  full uninstall', font=font(FM, 30), fill=WHITE + (int(a * 0.9),))
        d.text((92, 968), 'GTA Vice City – The Definitive Edition  ·  PC  ·  v0.2.0', font=font(FM, 26), fill=(200, 200, 215, int(a * 0.9)))
    return im.convert('RGB')


def end_card(t=1.0):
    bg = cover_base().filter(ImageFilter.GaussianBlur(14))
    bg = Image.blend(bg, Image.new('RGB', (W, H), INK), 0.72)
    d = ImageDraw.Draw(bg, 'RGBA')
    a = int(255 * t)
    d.text((W / 2, 170), 'IAVAT@R NEURAL VICE CITY', font=font(FB, 76), fill=MAG + (a,), anchor='mm')
    d.text((W / 2, 250), 'v0.2.0  ·  free  ·  single-player', font=font(FSB, 34), fill=WHITE + (a,), anchor='mm')
    rows = [('DLSS 5 neural rendering', 'NVIDIA RTX 50 series · RTX Remix · RenoDX DLSS 5 add-on'),
            ('HD environment + characters', 'any GPU with Vulkan · built locally in 1.5–4 h'),
            ('One command', 'powershell -File .\\IAVATAR_Setup.ps1   ·   -Uninstall restores everything'),
            ('Nothing redistributed', 'no game files, no NVIDIA DLLs: only official, hash-verified tools')]
    y = 360
    for k, v in rows:
        d.rounded_rectangle([300, y, 1620, y + 108], radius=14, fill=(255, 255, 255, int(18 * t)))
        d.text((340, y + 16), k, font=font(FB, 36), fill=CYAN + (a,))
        d.text((340, y + 62), v, font=font(FM, 28), fill=WHITE + (int(a * 0.9),))
        y += 128
    d.text((W / 2, 930), 'Download on Nexus Mods  ·  iavatar.info', font=font(FSB, 34), fill=WHITE + (a,), anchor='mm')
    d.text((W / 2, 1010), 'Fan project. Not affiliated with Rockstar Games, Take-Two Interactive, Grove Street Games or NVIDIA.',
           font=font(FM, 22), fill=(170, 170, 190, a), anchor='mm')
    return bg


def labelled(im, text, sub, accent, scene_title):
    im = im.copy()
    d = ImageDraw.Draw(im, 'RGBA')
    tag(d, 40, 40, text, sub, accent=accent, size=40)
    caption(d, scene_title)
    return im


# ------------------------------------------------------------------ immagini statiche per Nexus
def stills():
    cover_overlay(cover_base()).save(os.path.join(OUT, '01_IAVATAR_cover.jpg'), quality=93)
    for n, (key, title, fv, fh, cv, ch, lab) in enumerate(SCENES, 2):
        v, h = img(fv), img(fh)
        bg = Image.new('RGB', (W, H), INK)
        d = ImageDraw.Draw(bg, 'RGBA')
        for i, (im, c, t1, t2, acc) in enumerate(((v, cv, 'VANILLA', 'original game', CYAN), (h, ch, 'IAVAT@R', lab, MAG))):
            x0 = i * 960
            full = im.resize((956, 538), Image.LANCZOS)
            bg.paste(full, (x0 + (2 if i else 0), 0))
            z = im.crop((c[0], c[1], c[0] + c[2], c[1] + c[3])).resize((956, 538), Image.LANCZOS)
            bg.paste(z, (x0 + (2 if i else 0), 542))
            sub = ImageDraw.Draw(bg, 'RGBA')
            tag(sub, x0 + 20, 20, t1, t2, accent=acc, size=34)
            tag(sub, x0 + 20, 562, 'DETAIL', None, accent=acc, size=26)
            # riquadro del dettaglio sull'immagine intera
            s = 956 / 1920
            sub.rectangle([x0 + c[0] * s, c[1] * s, x0 + (c[0] + c[2]) * s, (c[1] + c[3]) * s], outline=acc + (255,), width=3)
        d = ImageDraw.Draw(bg, 'RGBA')
        caption(d, title + '  ·  IAVAT@R Neural Vice City', size=26)
        bg.save(os.path.join(OUT, '%02d_IAVATAR_%s.jpg' % (n, key)), quality=93)
    end_card().save(os.path.join(OUT, '%02d_IAVATAR_features.jpg' % (len(SCENES) + 2)), quality=93)
    sheet = img('IAVATAR_hd_test.jpg')
    sheet.save(os.path.join(OUT, '%02d_IAVATAR_texture_sheet.jpg' % (len(SCENES) + 3)), quality=93)


# ------------------------------------------------------------------ video
class Writer:
    def __init__(self, name):
        self.tmp = os.path.join(OUT, 'scene_%s.tmp.mp4' % name)
        self.final = os.path.join(OUT, 'scene_%s.mp4' % name)
        self.p = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24',
                                   '-s', '%dx%d' % (W, H), '-r', str(FPS), '-i', '-', '-c:v', 'libx264',
                                   '-preset', 'veryfast', '-crf', '18', '-pix_fmt', 'yuv420p', '-r', str(FPS), self.tmp],
                                  stdin=subprocess.PIPE)

    def put(self, im, n=1):
        b = im.tobytes()
        for _ in range(n):
            self.p.stdin.write(b)

    def close(self):
        self.p.stdin.close()
        if self.p.wait() != 0:
            raise RuntimeError('ffmpeg ' + self.final)
        os.replace(self.tmp, self.final)
        return self.final


def ease(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def scene_title(w):
    base = cover_base()
    n = int(4.5 * FPS)
    for i in range(n):
        t = i / (n - 1)
        frame = kenburns(base, t, 1.0, 1.06, 0.6, 0.4)
        w.put(cover_overlay(frame, ease((t * 4.5 - 0.4) / 0.8), ease((t * 4.5 - 1.3) / 0.8)))


def scene_compare(w, sc):
    key, title, fv, fh, cv, ch, lab = sc
    v, h = img(fv), img(fh)
    panel = zoom_panel(v, h, cv, ch, title)
    T = 9.0
    n = int(T * FPS)
    for i in range(n):
        s = i / FPS
        zv = kenburns(v, min(s / 3.6, 1), 1.0, 1.03)
        zh = kenburns(h, min(max(s - 3.0, 0) / 3.6, 1), 1.0, 1.03)
        lv = labelled(zv, 'VANILLA', 'original game', CYAN, title)
        lh = labelled(zh, 'IAVAT@R', lab, MAG, title)
        if s < 3.0:
            fr = lv
        elif s < 3.6:
            fr = Image.blend(lv, lh, ease((s - 3.0) / 0.6))
        elif s < 6.2:
            fr = lh
        elif s < 6.6:
            fr = Image.blend(lh, panel, ease((s - 6.2) / 0.4))
        else:
            fr = panel
        w.put(fr)


def scene_details(w):
    items = [('erba_h.jpg', (980, 600, 1720, 1018), 'Grass: AI-upscaled 2x, relief rebuilt from the new albedo'),
             ('granito_h.jpg', (300, 560, 1040, 976), 'Granite and marble: 2,700+ environment textures upscaled with Real-ESRGAN')]
    for f, box, txt in items:
        im = img(f)
        n = int(4.0 * FPS)
        for i in range(n):
            t = ease(i / (n - 1))
            x0 = 0 + (box[0] - 0) * t
            y0 = 0 + (box[1] - 0) * t
            x1 = W + (box[2] - W) * t
            y1 = H + (box[3] - H) * t
            fr = im.crop((int(x0), int(y0), int(x1), int(y1))).resize((W, H), Image.BICUBIC)
            d = ImageDraw.Draw(fr, 'RGBA')
            tag(d, 40, 40, 'IAVAT@R HD', 'texture detail', accent=MAG, size=40)
            caption(d, txt)
            w.put(fr)


def scene_sheet(w):
    sheet = img('IAVATAR_hd_test.jpg')
    sw = 1180
    sh = int(sheet.height * sw / sheet.width)
    sheet = sheet.resize((sw, sh), Image.LANCZOS)
    n = int(7.0 * FPS)
    for i in range(n):
        t = ease(i / (n - 1))
        y = int((sh - H + 120) * t)
        fr = Image.new('RGB', (W, H), INK)
        fr.paste(sheet.crop((0, y, sw, min(sh, y + H))), (W - sw - 40, 0))
        d = ImageDraw.Draw(fr, 'RGBA')
        d.text((60, 300), 'TEXTURES', font=font(FB, 64), fill=MAG)
        d.text((60, 380), 'original 1024 px', font=font(FSB, 38), fill=CYAN)
        d.text((60, 430), 'vs IAVAT@R 2048 px', font=font(FSB, 38), fill=WHITE)
        d.text((60, 520), 'Grazing light shows the', font=font(FM, 28), fill=(200, 200, 215))
        d.text((60, 558), 'rebuilt surface relief.', font=font(FM, 28), fill=(200, 200, 215))
        w.put(fr)


def scene_end(w):
    n = int(6.0 * FPS)
    full = None
    for i in range(n):
        t = ease(i / (0.8 * FPS))
        if t >= 1 and full is None:
            full = end_card(1.0)
        w.put(full if t >= 1 else end_card(t))


def video():
    parts = []
    w = Writer('00_title'); scene_title(w); parts.append(w.close())
    for k, sc in enumerate(SCENES, 1):
        w = Writer('%02d_%s' % (k, sc[0])); scene_compare(w, sc); parts.append(w.close())
    w = Writer('06_details'); scene_details(w); parts.append(w.close())
    w = Writer('07_sheet'); scene_sheet(w); parts.append(w.close())
    w = Writer('08_end'); scene_end(w); parts.append(w.close())
    lst = os.path.join(OUT, 'concat.txt')
    with open(lst, 'w') as f:
        for p in parts:
            f.write("file '%s'\n" % p)
    joined = os.path.join(OUT, 'joined.tmp.mp4')
    subprocess.check_call(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', lst, '-c', 'copy', joined])
    final = os.path.join(OUT, 'IAVATAR_NeuralViceCity_trailer.mp4')
    subprocess.check_call(['ffmpeg', '-y', '-loglevel', 'error', '-i', joined, '-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo',
                           '-c:v', 'copy', '-c:a', 'aac', '-b:a', '128k', '-shortest', '-movflags', '+faststart', final + '.tmp.mp4'])
    os.replace(final + '.tmp.mp4', final)
    os.remove(joined)
    return final


if __name__ == '__main__':
    what = sys.argv[1] if len(sys.argv) > 1 else 'all'
    if what in ('stills', 'all'):
        stills()
    if what == 'preview':
        cover_overlay(cover_base()).save('/tmp/p_cover.jpg', quality=85)
        sc = SCENES[0]
        labelled(img(sc[2]), 'VANILLA', 'original game', CYAN, sc[1]).save('/tmp/p_v.jpg', quality=85)
        zoom_panel(img(sc[2]), img(sc[3]), sc[4], sc[5], sc[1]).save('/tmp/p_panel.jpg', quality=85)
        end_card().save('/tmp/p_end.jpg', quality=85)
    if what in ('video', 'all'):
        print(video())
