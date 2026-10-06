#!/usr/bin/env python3
"""Packar sprites från sprite_lab (PNG + meta_*.json) till en atlas + json.
Användning: python3 tools/pack_atlas.py <mapp_med_png> <ut_mapp>
"""
import glob, json, os, sys
from PIL import Image, ImageDraw, ImageFilter

src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
meta = {}
for f in glob.glob(os.path.join(src, "meta_*.json")):
    meta.update(json.load(open(f)))

items = []
for name, m in meta.items():
    path = os.path.join(src, name + ".png")
    if not os.path.exists(path):
        continue
    im = Image.open(path).convert("RGBA")
    bb = im.getbbox()
    if not bb:
        continue
    crop = im.crop(bb)
    items.append({"name": name, "img": crop, "ax": m["ax"] - bb[0], "ay": m["ay"] - bb[1], "ppm": m["ppm"], "len": m.get("len", 0.0)})

# mjuk skugga (ellips) som delas av alla objekt
sh = Image.new("RGBA", (160, 80), (0, 0, 0, 0))
d = ImageDraw.Draw(sh)
d.ellipse((20, 12, 140, 68), fill=(0, 0, 0, 120))
sh = sh.filter(ImageFilter.GaussianBlur(9))
items.append({"name": "shadow", "img": sh, "ax": 80, "ay": 40, "ppm": 1.0, "len": 0.0})

PAD = 2
items.sort(key=lambda i: -i["img"].height)
W = 4096
x = y = rowh = 0
placed = []
for it in items:
    w, h = it["img"].size
    if x + w + PAD * 2 > W:
        x = 0
        y += rowh + PAD * 2
        rowh = 0
    it["x"], it["y"] = x + PAD, y + PAD
    x += w + PAD * 2
    rowh = max(rowh, h)
H = y + rowh + PAD * 2
atlas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
data = {}
for it in items:
    atlas.paste(it["img"], (it["x"], it["y"]))
    data[it["name"]] = {"x": it["x"], "y": it["y"], "w": it["img"].width, "h": it["img"].height,
                        "ax": it["ax"], "ay": it["ay"], "ppm": it["ppm"], "len": it["len"]}
atlas.save(os.path.join(out, "atlas.png"), optimize=True)
json.dump({"atlas": "atlas.png", "w": W, "h": H, "sprites": data}, open(os.path.join(out, "atlas.json"), "w"))
print("atlas", W, H, len(data), "sprites;", os.path.getsize(os.path.join(out, "atlas.png")) // 1024, "KB")
