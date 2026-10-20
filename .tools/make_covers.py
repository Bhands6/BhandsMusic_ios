#!/usr/bin/env python3
"""把参考稿的封面图裁成方形并写入 Assets.xcassets。"""
import json
import os
from PIL import Image

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "covers")
ASSETS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "GlassMusicPlayer", "Assets.xcassets")

# (源文件, 资源名, 输出边长)
ITEMS = [
    ("neon-tokyo",       "cover_neon_tokyo",      720),
    ("cyber-bloom",      "cover_cyber_bloom",     720),
    ("midnight-neon",    "cover_midnight_neon",   720),
    ("deep-space-love",  "cover_deep_space_love", 720),
    ("velvet-circuit",   "cover_velvet_circuit",  720),
    ("ink-rivers",       "cover_ink_rivers",      720),
    ("tokyo-rain",       "cover_tokyo_rain",      720),
    ("chrome-heart",     "cover_chrome_heart",    720),
    ("avatar",           "avatar_rider",          256),
]

CONTENTS = {
    "images": [{"filename": "img.png", "idiom": "universal", "scale": "1x"}],
    "info": {"author": "xcode", "version": 1},
}


def square(img, side):
    """中心裁剪成正方形再缩放。"""
    w, h = img.size
    edge = min(w, h)
    img = img.crop(((w - edge) // 2, (h - edge) // 2,
                    (w - edge) // 2 + edge, (h - edge) // 2 + edge))
    return img.resize((side, side), Image.LANCZOS)


def main():
    for src, name, side in ITEMS:
        path = os.path.join(SRC, src + ".jpg")
        if not os.path.exists(path):
            print("MISSING", path)
            continue

        folder = os.path.join(ASSETS, name + ".imageset")
        os.makedirs(folder, exist_ok=True)

        with Image.open(path) as im:
            im = im.convert("RGB")
            print("%-22s %s -> %dx%d" % (name, im.size, side, side))
            square(im, side).save(os.path.join(folder, "img.png"), "PNG", optimize=True)

        with open(os.path.join(folder, "Contents.json"), "w") as f:
            json.dump(CONTENTS, f, indent=2)

    print("done")


if __name__ == "__main__":
    main()
