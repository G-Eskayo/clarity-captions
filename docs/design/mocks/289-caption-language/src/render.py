"""#289 mock-ups: the caption language on the caption screen, drawn over real simulator screenshots. Mock-ups only."""
import sys
from PIL import Image, ImageDraw, ImageFont
S = sys.argv[1] if len(sys.argv) > 1 else __import__("os").path.dirname(__file__)
FONT = '/System/Library/Fonts/SFNS.ttf'
def font(px, weight=b'Medium'):
    f = ImageFont.truetype(FONT, px); f.set_variation_by_name(weight); return f

# Per screen: status box, where content below the top bar starts and ends, text sizes, colours.
DEV = {
 'iphone-paper': dict(file='base-iphone-paper.png', box=(509, 281, 697, 324), cut=345, end=2120, fs=42, sub=36, fg=(66,65,66), strong=(20,20,25), accent=(20,81,75), bg=(250,245,230)),
 'iphone-night': dict(file='base-iphone-night.png', box=(509, 281, 697, 324), cut=345, end=2120, fs=42, sub=36, fg=(192,189,181), strong=(233,227,213), accent=(201,214,242), bg=(29,37,54)),
 'ipad-paper':   dict(file='base-ipad-paper.png', box=(968, 128, 1094, 156), cut=175, end=2090, fs=32, sub=34, fg=(66,65,66), strong=(20,20,25), accent=(20,81,75), bg=(250,245,230)),
 'mac-light':    dict(file='05-mac-light.png', box=(408, 87, 566, 111), cut=124, end=800, xs=(60, 916), fs=26, sub=22, fg=(77,75,76), strong=(20,20,25), accent=(20,81,75), bg=(250,245,230)),
 'mac-dark':     dict(file='06-mac-dark.png', box=(408, 87, 566, 111), cut=124, end=800, xs=(60, 916), fs=26, sub=22, fg=(182,183,170), strong=(242,221,181), accent=(242,221,181), bg=(23,51,49)),
}

def shift(im, d, cut, end, by):
    """Move the captions down by `by` px into the empty space under them, as the real layout would."""
    x0, x1 = d.get('xs', (0, im.width))
    region = im.crop((x0, cut, x1, end))
    im.paste(Image.new('RGB', (x1 - x0, end - cut + by), d['bg']), (x0, cut))
    im.paste(region, (x0, cut + by))

def warn(dr, x, y, size, col, bg):
    """A warning triangle with '!': the mismatch is never shown by colour alone."""
    h = size
    dr.polygon([(x + h/2, y), (x + h, y + h*0.9), (x, y + h*0.9)], fill=col)
    f = font(int(h*0.62), b'Bold')
    tw = dr.textlength('!', font=f)
    dr.text((x + h/2 - tw/2, y + h*0.2), '!', font=f, fill=bg)

def runs_width(dr, runs):
    return sum(r[2] if r[0] == 'icon' else dr.textlength(r[1], font=r[2]) for r in runs)

def draw_runs(dr, runs, cx, y, d):
    """Centred line of text runs and icons: ('text', s, font, colour) / ('icon', colour, size)."""
    x = cx - runs_width(dr, runs) / 2
    for r in runs:
        if r[0] == 'icon':
            warn(dr, x, y + 2, r[2] * 0.85, r[1], d['bg']); x += r[2]
        else:
            dr.text((x, y), r[1], font=r[2], fill=r[3]); x += dr.textlength(r[1], font=r[2])

def tile(dev, option, mismatch):
    d = DEV[dev]
    im = Image.open(f"{S}/{d['file']}").convert('RGB')
    dr = ImageDraw.Draw(im)
    w = im.width; cx = (d['box'][0] + d['box'][2]) / 2 if dev.startswith('mac') else w / 2
    if dev.startswith('mac'): cx = w / 2 + 0  # the Mac pop-up's status is centred in the window
    mac = dev.startswith('mac')
    lang = 'Spanish' if mismatch and not mac else 'English'
    f1, f2 = font(d['fs']), font(d['sub'])
    status_bottom = d['box'][3]
    if option == 'A':   # the language under the status, as face to face already shows it
        gap = int(d['sub'] * 1.5)
        shift(im, d, d['cut'], d['end'], gap)
        y = status_bottom + int(d['sub'] * 0.35)
        if mismatch:
            draw_runs(dr, [('icon', d['strong'], d['sub']), ('text', '  ' + lang, font(d['sub'], b'Semibold'), d['strong']),
                           ('text', ' · not your phone’s language' if not dev.startswith('mac') else ' · not your Mac’s language', f2, d['strong'])], cx, y, d)
        else:
            draw_runs(dr, [('text', 'English', f2, d['fg'])], cx, y, d)
    elif option == 'B':  # nothing new when it matches; a note only when it doesn't
        if mismatch:
            pad = int(d['sub'] * 0.6); lh = int(d['sub'] * 1.35)
            l1 = f'Captions are in {lang}.'; l2 = ('Your phone is in English.' if not mac else 'Your Mac is in French.')
            fb = font(d['sub'], b'Semibold'); fr = font(d['sub'], b'Regular')
            boxh = pad * 2 + lh * 2
            shift(im, d, d['cut'], d['end'], boxh + pad)
            x0, x1 = int(w * 0.04) if not dev.startswith('mac') else 84, int(w * 0.96) if not dev.startswith('mac') else w - 84
            y0 = d['cut'] + int(pad * 0.3)
            dr.rounded_rectangle((x0, y0, x1, y0 + boxh), radius=int(d['sub'] * 0.5), outline=d['strong'], width=max(2, d['sub'] // 12))
            ix = x0 + pad; warn(dr, ix, y0 + pad + 4, d['sub'] * 0.9, d['strong'], d['bg'])
            tx = ix + d['sub'] * 1.4
            dr.text((tx, y0 + pad), l1, font=fb, fill=d['strong'])
            dr.text((tx, y0 + pad + lh), l2, font=fr, fill=d['strong'])
            ch = 'Change'; fc = font(d['sub'], b'Semibold'); cw = dr.textlength(ch, font=fc)
            dr.text((x1 - pad - cw, y0 + pad + lh // 2), ch, font=fc, fill=d['accent'])
            dr.line((x1 - pad - cw, y0 + pad + lh // 2 + d['sub'] * 1.15, x1 - pad, y0 + pad + lh // 2 + d['sub'] * 1.15), fill=d['accent'], width=max(2, d['sub'] // 14))
    elif option == 'C':  # one line: the status gains the language
        x0, y0, x1, y1 = d['box']
        crop = im.crop((x0 - 4, y0 - 6, x1 + 4, y1 + 6))
        dr.rectangle((x0 - 4, y0 - 6, x1 + 4, y1 + 6), fill=d['bg'])
        extra = [('text', ' · ', f1, d['fg']), ('text', lang, f1 if not mismatch else font(d['fs'], b'Semibold'), d['fg'] if not mismatch else d['strong'])]
        if mismatch: extra += [('text', ' ', f1, d['fg']), ('icon', d['strong'], d['fs'])]
        total = crop.width + runs_width(dr, extra)
        left = cx - total / 2
        im.paste(crop, (int(left), y0 - 6))
        x = left + crop.width
        ty = y0 - int(d['fs'] * 0.2) if not dev.startswith('mac') else y0 - 4
        for r in extra:
            if r[0] == 'icon': warn(dr, x, ty + 4, r[2] * 0.85, r[1], d['bg']); x += r[2]
            else: dr.text((x, ty), r[1], font=r[2], fill=r[3]); x += dr.textlength(r[1], font=r[2])
    return im

def sheet(name, title, tiles, h=1150):
    imgs = []
    for dev, opt, mm, label in tiles:
        t = tile(dev, opt, mm); t = t.resize((int(t.width * h / t.height), h), Image.LANCZOS); imgs.append((t, label))
    gap, top = 40, 150
    W = sum(i.width for i, _ in imgs) + gap * (len(imgs) + 1)
    out = Image.new('RGB', (W, h + top + gap), (236, 236, 236))
    dr = ImageDraw.Draw(out)
    dr.text((gap, 28), title, font=font(44, b'Semibold'), fill=(20, 20, 25))
    x = gap
    for i, label in imgs:
        dr.text((x, 96), label, font=font(30, b'Regular'), fill=(60, 60, 60))
        out.paste(i, (x, top)); x += i.width + gap
    out.save(f'{S}/{name}.png')

for opt, title in [('A', 'A: the language under "Listening", as face to face already shows it'),
                   ('B', 'B: nothing new when it matches; a note only when it doesn’t'),
                   ('C', 'C: one line, "Listening · English"')]:
    sheet(f'{opt}-paper', title, [('iphone-paper', opt, False, 'iPhone, matches'), ('iphone-paper', opt, True, 'iPhone, Spanish saved'),
                                  ('ipad-paper', opt, True, 'iPad, Spanish saved'), ('mac-light', opt, True, 'Mac set to French, captions in English')])
sheet('dark', 'Dark themes (Night on iPhone, Harbor on the Mac), language not the phone’s',
      [('iphone-night', 'A', True, 'A'), ('iphone-night', 'B', True, 'B'), ('iphone-night', 'C', True, 'C'),
       ('mac-dark', 'A', True, 'A, Mac'), ('mac-dark', 'B', True, 'B, Mac'), ('mac-dark', 'C', True, 'C, Mac')], h=900)
print('ok')
