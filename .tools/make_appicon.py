#!/usr/bin/env python3
"""生成 NeonTune 风格的 1024×1024 App 图标。

设计：深紫径向雾底 → 霓虹网格 → 黑胶盘 + 紫青辉光 → 渐变播放键。
全部用 PIL 手绘，不依赖任何付费图像服务。
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "GlassMusicPlayer", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png",
)

HAZE = [(0x2B, 0x1A, 0x63), (0x12, 0x0A, 0x35), (0x07, 0x04, 0x1A), (0x03, 0x02, 0x0C)]
PURPLE = (0xA8, 0x55, 0xF7)
CYAN = (0x22, 0xD3, 0xEE)
ORCHID = (0xC0, 0x84, 0xFC)
INDIGO = (0x63, 0x66, 0xF1)
LAVENDER = (0xD8, 0xB4, 0xFE)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def haze_color(t):
    """把 0…1 映射到四档紫雾渐变上。"""
    stops = [0.0, 0.38, 0.72, 1.0]
    for i in range(len(stops) - 1):
        if t <= stops[i + 1]:
            span = stops[i + 1] - stops[i]
            local = 0.0 if span == 0 else (t - stops[i]) / span
            return lerp(HAZE[i], HAZE[i + 1], max(0.0, min(1.0, local)))
    return HAZE[-1]


def make_background():
    """先画小图再放大 —— 纯 Python 逐像素算 1024² 太慢，64² 足够且缩放后非常平滑。"""
    small = 64
    img = Image.new("RGB", (small, small))
    px = img.load()
    for y in range(small):
        for x in range(small):
            dx = (x + 0.5) / small - 0.5
            dy = (y + 0.5) / small - 0.02          # 渐变中心在画面上方
            # 椭圆化：纵向压扁，模拟 CSS 的 radial-gradient(120% 90% at 50% -10%)
            dist = math.hypot(dx / 1.35, dy / 0.95) * 1.45
            px[x, y] = haze_color(min(dist, 1.0))
    return img.resize((SIZE, SIZE), Image.BICUBIC)


def add_grid(base, cell=64, alpha=46):
    """霓虹网格：紫横 + 青纵。"""
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i in range(0, SIZE + cell, cell):
        d.line([(i, 0), (i, SIZE)], fill=CYAN + (int(alpha * 0.8),), width=1)
        d.line([(0, i), (SIZE, i)], fill=PURPLE + (alpha,), width=1)
    return Image.alpha_composite(base, layer)


def glow(shape_layer, radius, strength=1.0):
    """把图层模糊成辉光。"""
    blurred = shape_layer.filter(ImageFilter.GaussianBlur(radius))
    if strength != 1.0:
        alpha = blurred.split()[3].point(lambda v: int(v * strength))
        blurred.putalpha(alpha)
    return blurred


def build():
    base = make_background().convert("RGBA")
    base = add_grid(base)

    cx = cy = SIZE // 2

    # ---- 黑胶盘 ----------------------------------------------------------
    disc_r = 330
    disc = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    dd = ImageDraw.Draw(disc)
    dd.ellipse([cx - disc_r, cy - disc_r, cx + disc_r, cy + disc_r], fill=(0x17, 0x0D, 0x38, 255))

    # 唱片纹路
    r = 34
    while r < disc_r - 8:
        shade = 255 if (r // 14) % 2 == 0 else 0
        dd.ellipse([cx - r, cy - r, cx + r, cy + r],
                   outline=(shade, shade, shade, 44), width=3)
        r += 14

    # 盘面高光
    hl = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(hl).ellipse(
        [cx - disc_r * 0.78, cy - disc_r * 0.95, cx + disc_r * 0.28, cy - disc_r * 0.12],
        fill=(255, 255, 255, 46),
    )
    hl = hl.filter(ImageFilter.GaussianBlur(70))
    disc = Image.alpha_composite(disc, hl)

    # 盘外圈：紫 → 青的渐变环 + 辉光
    ring = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    for deg in range(0, 360, 2):
        t = math.sin(deg / 360 * 2 * math.pi) * 0.5 + 0.5
        rd.arc([cx - disc_r, cy - disc_r, cx + disc_r, cy + disc_r],
               deg, deg + 2, fill=lerp(PURPLE, CYAN, t) + (235,), width=6)

    base = Image.alpha_composite(base, glow(ring, 52, 1.0))
    base = Image.alpha_composite(base, disc)
    base = Image.alpha_composite(base, ring)

    # ---- 中心渐变播放键 ---------------------------------------------------
    btn_r = 150
    btn = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    bd = ImageDraw.Draw(btn)
    bd.ellipse([cx - btn_r, cy - btn_r, cx + btn_r, cy + btn_r], fill=ORCHID + (255,))

    # 用竖向渐变覆盖，做出 orchid → indigo
    grad = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gp = grad.load()
    top, bottom = cy - btn_r, cy + btn_r
    for y in range(top, bottom + 1):
        t = (y - top) / max(1, (bottom - top))
        color = lerp(ORCHID, INDIGO, t)
        for x in range(cx - btn_r, cx + btn_r + 1):
            gp[x, y] = color + (255,)
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).ellipse([cx - btn_r, cy - btn_r, cx + btn_r, cy + btn_r], fill=255)
    btn = Image.composite(grad, btn, mask)

    # 播放键辉光
    base = Image.alpha_composite(base, glow(btn, 80, 1.0))
    base = Image.alpha_composite(base, glow(btn, 34, 0.9))

    # 内壁高光
    inner = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(inner).ellipse(
        [cx - btn_r, cy - btn_r, cx + btn_r, cy + btn_r],
        outline=LAVENDER + (110,), width=16,
    )
    inner = inner.filter(ImageFilter.GaussianBlur(14))
    btn = Image.alpha_composite(btn, inner)

    base = Image.alpha_composite(base, btn)

    # ---- 播放三角 ---------------------------------------------------------
    tri = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    h = 128
    w = 112
    ox = 18
    ImageDraw.Draw(tri).polygon(
        [
            (cx - w // 2 + ox, cy - h // 2),
            (cx - w // 2 + ox, cy + h // 2),
            (cx + w // 2 + ox, cy),
        ],
        fill=(255, 255, 255, 255),
    )
    base = Image.alpha_composite(base, glow(tri, 26, 0.55))
    base = Image.alpha_composite(base, tri)

    base.convert("RGB").save(OUT, "PNG", optimize=True)
    print("saved", OUT, base.size)


if __name__ == "__main__":
    build()
