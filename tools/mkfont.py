#!/usr/bin/env python3
"""Rasterise a TTF/OTF into a Connect IQ bitmap font (BMFont text .fnt + PNG).

usage: mkfont.py <font.ttf> <pixel-size> <chars> <out-basename> [--tracking N] [--axes a,b]

Writes <out-basename>.fnt and <out-basename>.png next to each other. The PNG is
8-bit greyscale, white glyphs on black, which the Connect IQ resource compiler
turns into an anti-aliased one-colour font tinted at draw time.
"""
import sys
from PIL import Image, ImageDraw, ImageFont


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = sys.argv[1:]
    ttf, size, chars, out = args[0], int(args[1]), args[2], args[3]
    tracking = int(opts[opts.index("--tracking") + 1]) if "--tracking" in opts else 0
    font = ImageFont.truetype(ttf, size)
    if "--axes" in opts:
        font.set_variation_by_axes([float(v) for v in opts[opts.index("--axes") + 1].split(",")])
    ascent, descent = font.getmetrics()
    line_h = ascent + descent
    chars = "".join(sorted(set(chars)))

    glyphs = []
    for ch in chars:
        adv = int(round(font.getlength(ch))) + tracking
        box = font.getbbox(ch)  # relative to origin at (0, ascent-top)
        if box is None or box[2] <= box[0] or box[3] <= box[1]:
            glyphs.append((ch, adv, None, 0, 0, 0, 0))
            continue
        x0, y0, x1, y1 = box
        w, h = x1 - x0, y1 - y0
        img = Image.new("L", (w + 2, h + 2), 0)
        ImageDraw.Draw(img).text((1 - x0, 1 - y0), ch, font=font, fill=255)
        glyphs.append((ch, adv, img, x0 - 1, y0 - 1, w + 2, h + 2))

    # simple shelf packing
    max_w = 1024 if size > 60 else 512
    x = y = shelf = 0
    places = []
    for ch, adv, img, xo, yo, w, h in glyphs:
        if img is None:
            places.append((0, 0))
            continue
        if x + w > max_w:
            x, y, shelf = 0, y + shelf + 1, 0
        places.append((x, y))
        x += w + 1
        shelf = max(shelf, h)
    sheet_h = y + shelf + 1
    sheet_w = max_w if y > 0 else x
    sheet = Image.new("L", (sheet_w, sheet_h), 0)
    for (ch, adv, img, xo, yo, w, h), (px, py) in zip(glyphs, places):
        if img is not None:
            sheet.paste(img, (px, py))
    png = out + ".png"
    sheet.save(png)

    base = png.split("/")[-1]
    with open(out + ".fnt", "w") as f:
        f.write(f'info face="{base}" size={size} bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1\n')
        f.write(f"common lineHeight={line_h} base={ascent} scaleW={sheet_w} scaleH={sheet_h} pages=1 packed=0\n")
        f.write(f'page id=0 file="{base}"\n')
        f.write(f"chars count={len(glyphs)}\n")
        for (ch, adv, img, xo, yo, w, h), (px, py) in zip(glyphs, places):
            f.write(f"char id={ord(ch)} x={px} y={py} width={w} height={h} xoffset={xo} yoffset={yo} xadvance={adv} page=0 chnl=15\n")
    print(f"{out}: {len(glyphs)} glyphs, sheet {sheet_w}x{sheet_h}, lineHeight {line_h}, base {ascent}")


if __name__ == "__main__":
    main()
