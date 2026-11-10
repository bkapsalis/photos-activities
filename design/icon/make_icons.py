"""Cut every app icon, for every platform and flavor, from one photo.

Run from the repo root:

    python3 -I design/icon/make_icons.py app_home_pic_chicks.jpg

The photo stays out of git: the original carries its GPS location, and the
icons cut from it don't. To use another photo, change CX, CY and SIDE below
to the square you want, in the photo's own pixels, and run it again. The
Android adaptive layer needs 1.5 times that square, so leave room around it.
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = Image.open(sys.argv[1]).convert("RGB")
CX, CY, SIDE = 2230, 1430, 1620       # the three chicks: centre and side
LZ = Image.LANCZOS
FONT = "/System/Library/Fonts/Supplemental/Arial Black.ttf"
BADGES = {"dev": ("DEV", (230, 81, 0)), "staging": ("STAGING", (21, 101, 192))}


def crop(side, out):
    h = side / 2
    return SRC.crop((CX - h, CY - h, CX + h, CY + h)).resize((out, out), LZ)


SQUARE = crop(SIDE, 1024)                 # what shows on the home screen
LAYER = crop(SIDE * 1.5, 1536)            # Android adaptive layer: 108dp, 72dp shown


def font_for(size):
    """One font size for every badge, fitted to the longest word."""
    band = 0.16 * size
    fs = int(band * 0.85)
    while True:
        f = ImageFont.truetype(FONT, fs)
        l, t, r, b = f.getbbox("STAGING")
        if r - l <= 0.55 * size and b - t <= 0.6 * band:
            return f
        fs -= 2


def badge(img, which, box):
    """A coloured band across the lower part of the visible square `box`."""
    text, color = BADGES[which]
    x0, y0, size = box
    im = img.copy()
    d = ImageDraw.Draw(im, "RGBA")
    top, bottom = y0 + 0.72 * size, y0 + 0.88 * size
    d.rectangle([0, top, im.width, bottom], fill=color + (240,))
    f = font_for(size)
    l, t, r, b = f.getbbox(text)
    x = x0 + (size - (r - l)) / 2 - l
    y = top + (bottom - top - (b - t)) / 2 - t
    d.text((x, y), text, font=f, fill="white")
    return im


def rounded(img, out):
    """Rounded-square with transparent corners, for launch screens and web."""
    big = img.resize((out * 4, out * 4), LZ).convert("RGBA")
    mask = Image.new("L", big.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, big.width - 1, big.height - 1], radius=int(big.width * 0.2237), fill=255)
    big.putalpha(mask)
    return big.resize((out, out), LZ)


def save(img, *parts, **kw):
    path = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, **kw)


variants = {
    "prod": (SQUARE, LAYER),
    "dev": (badge(SQUARE, "dev", (0, 0, 1024)), badge(LAYER, "dev", (256, 256, 1024))),
    "staging": (badge(SQUARE, "staging", (0, 0, 1024)),
                badge(LAYER, "staging", (256, 256, 1024))),
}

# ── Android ─────────────────────────────────────────────
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
for flavor, (square, layer) in variants.items():
    srcset = "main" if flavor == "prod" else flavor
    for dens, k in DENSITIES.items():
        res = ("android", "app", "src", srcset, "res", f"mipmap-{dens}")
        save(square.resize((round(48 * k),) * 2, LZ), *res, "ic_launcher.png", optimize=True)
        save(layer.resize((round(108 * k),) * 2, LZ), *res, "ic_launcher_background.webp",
             quality=90, method=6)
save(rounded(SQUARE, 480), "android", "app", "src", "main", "res", "drawable-xxxhdpi",
     "launch_icon.png", optimize=True)

# ── iOS ─────────────────────────────────────────────────
for flavor, (square, _) in variants.items():
    name = "AppIcon" if flavor == "prod" else f"AppIcon-{flavor}"
    folder = ("ios", "Runner", "Assets.xcassets", f"{name}.appiconset")
    save(square, *folder, "Icon-1024.png", optimize=True)
    with open(os.path.join(ROOT, *folder, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": "Icon-1024.png", "idiom": "universal",
                               "platform": "ios", "size": "1024x1024"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")
for scale in (1, 2, 3):
    suffix = "" if scale == 1 else f"@{scale}x"
    save(rounded(SQUARE, 160 * scale), "ios", "Runner", "Assets.xcassets",
         "LaunchImage.imageset", f"LaunchImage{suffix}.png", optimize=True)

# ── Web ─────────────────────────────────────────────────
save(rounded(SQUARE, 64), "web", "favicon.png", optimize=True)
for px in (192, 512):
    save(rounded(SQUARE, px), "web", "icons", f"Icon-{px}.png", optimize=True)
    save(LAYER.resize((px, px), LZ), "web", "icons", f"Icon-maskable-{px}.png", optimize=True)

# ── Store listings and the source of truth ──────────────
save(SQUARE, "design", "icon", "icon-1024.png", optimize=True)
save(SQUARE.resize((512, 512), LZ), "design", "icon", "play-store-icon-512.png", optimize=True)
save(LAYER, "design", "icon", "adaptive-background-1536.jpg", quality=92)
print("done")
