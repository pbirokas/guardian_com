"""
Generates two Guardian App icon files:
  1. app_icon.png             - full icon with blue rounded bg  (iOS + legacy Android)
  2. app_icon_foreground.png  - shield+heart on transparent bg  (Android adaptive)

Run: python generate_icon.py
"""
import math
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
CX = CY = SIZE // 2

BLUE  = (21, 101, 192, 255)   # #1565C0
WHITE = (255, 255, 255, 255)


# ─── Quadratic Bezier ─────────────────────────────────────────────────────────
def bezier2(p0, p1, p2, steps=60):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        x = (1-t)**2 * p0[0] + 2*(1-t)*t * p1[0] + t**2 * p2[0]
        y = (1-t)**2 * p0[1] + 2*(1-t)*t * p1[1] + t**2 * p2[1]
        pts.append((x, y))
    return pts


# ─── Draw shield + heart centred at (cx, cy) with a given scale ───────────────
def draw_icon(canvas: Image.Image, cx: int, cy: int, scale: float):
    """
    scale = 1.0 means the design fills a 1024×1024 canvas.
    Use scale < 1 to shrink it (adaptive icon foreground safe zone).
    """

    def t(v, origin=512):
        """Translate a coordinate from the 1024-grid to the scaled canvas."""
        return cx + (v - origin) * scale

    def pt(x, y):
        return (t(x), t(y))

    draw = ImageDraw.Draw(canvas)

    # ── Shield outline ─────────────────────────────────────────────────────────
    # Five key coordinates (original 1024-space):
    SL, SR = 210, 814   # left / right
    ST     = 175        # top
    SM     = 580        # where straight side ends
    SBOT   = 870        # bottom tip

    shield_pts  = [pt(SL, ST), pt(SR, ST), pt(SR, SM)]
    shield_pts += bezier2(pt(SR, SM), pt(SR, 755), pt(512, SBOT))
    shield_pts += bezier2(pt(512, SBOT), pt(SL, 755), pt(SL, SM))

    # Soft drop-shadow
    shadow = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    sd     = ImageDraw.Draw(shadow)
    off    = 8 * scale
    spts   = [(x + off, y + off) for x, y in shield_pts]
    sd.polygon(spts, fill=(0, 0, 0, 60))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=max(1, int(16 * scale))))
    composite = Image.alpha_composite(canvas, shadow)
    canvas.paste(composite)
    draw = ImageDraw.Draw(canvas)

    draw.polygon(shield_pts, fill=WHITE)

    # ── Heart (parametric, correctly sized) ───────────────────────────────────
    # The parametric heart has natural units x ∈ [-16, 16], y ∈ [-17, ~5].
    # HSCALE = pixels per unit.  For a ~280 px wide heart: 280/(2*16) ≈ 8.75
    HSCALE = 8.8 * scale   # ~280 px wide at scale=1
    HCX    = cx
    HCY    = cy + int(30 * scale)   # move slightly below shield centre

    heart_pts = []
    for i in range(300):
        t_val = 2 * math.pi * i / 300 - math.pi
        x =  16 * math.sin(t_val) ** 3
        y = -(13 * math.cos(t_val)
              - 5 * math.cos(2 * t_val)
              - 2 * math.cos(3 * t_val)
              -     math.cos(4 * t_val))
        heart_pts.append((HCX + x * HSCALE, HCY + y * HSCALE))

    draw.polygon(heart_pts, fill=BLUE)


# ─── 1. Full icon (rounded blue background) ───────────────────────────────────
full = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
ImageDraw.Draw(full).rounded_rectangle(
    [0, 0, SIZE - 1, SIZE - 1], radius=224, fill=BLUE)
draw_icon(full, CX, CY, scale=1.0)
full.save('guardian_app/assets/icon/app_icon.png')
print('Saved: app_icon.png')

# ─── 2. Foreground-only (transparent bg) for Android adaptive icon ─────────────
# Safe zone = inner 66 % of canvas.  Use scale=0.60 to stay well within it.
fg = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
draw_icon(fg, CX, CY, scale=0.60)
fg.save('guardian_app/assets/icon/app_icon_foreground.png')
print('Saved: app_icon_foreground.png')
