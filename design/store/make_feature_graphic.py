"""Google Play's feature graphic, 1024 x 500, from the app icon's photo.

Run from the repo root:

    python3 -I design/store/make_feature_graphic.py app_home_pic_chicks.jpg

The photo stays out of git (it carries its GPS location); the PNG made from
it doesn't. The chicks sit right of centre, with the name on a dark fade at
the left.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = Image.open(sys.argv[1]).convert("RGB")
W, H = 1024, 500
CX, CY = 2230, 1430                       # the chicks' centre, as in make_icons.py
CUT_W = 3300                              # photo pixels across the graphic
CHICKS_AT = 0.68                          # how far across the chicks sit
FONT = "/System/Library/Fonts/Avenir Next.ttc"
BOLD, MEDIUM = 0, 5                       # faces in that collection

# Cut to the graphic's shape, with the chicks right of centre.
cut_h = CUT_W * H / W
left = min(max(CX - CHICKS_AT * CUT_W, 0), SRC.width - CUT_W)
top = min(max(CY - cut_h / 2, 0), SRC.height - cut_h)
img = SRC.crop((left, top, left + CUT_W, top + cut_h)).resize((W, H), Image.LANCZOS)

# Dark fade from the left, so white text reads on any photo.
fade = Image.new("L", (W, 1))
for x in range(W):
    fade.putpixel((x, 0), int(200 * max(0.0, 1 - x / (W * 0.62)) ** 1.4))
img = Image.composite(Image.new("RGB", (W, H)), img, fade.resize((W, H)))

draw = ImageDraw.Draw(img)
draw.text((48, 168), "Bill's Bay Area", font=ImageFont.truetype(FONT, 54, index=BOLD), fill="white")
draw.text((50, 238), "Fun Activities", font=ImageFont.truetype(FONT, 36, index=MEDIUM), fill="white")
draw.text((50, 298), "Hikes · Museums · Historic sites", font=ImageFont.truetype(FONT, 22, index=MEDIUM), fill=(225, 235, 225))

img.save(os.path.join(HERE, "feature-graphic-1024x500.png"))
