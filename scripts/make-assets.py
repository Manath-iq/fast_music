#!/usr/bin/env python3
"""Reproducible native brand icon + static glow. Requires Pillow; not a runtime dependency."""
import math
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

root = Path(__file__).resolve().parent.parent
assets = root / "assets"
assets.mkdir(exist_ok=True)
iconset = root / ".build/AppIcon.iconset"
iconset.mkdir(parents=True, exist_ok=True)
icon = Image.new("RGBA", (1024, 1024))
draw = ImageDraw.Draw(icon)
draw.rounded_rectangle((50, 50, 974, 974), radius=210, fill=(24, 23, 24), outline=(64, 62, 63), width=3)
center = (574, 468)
for ray in range(13):
    angle = ray * math.pi * 2 / 13
    tip = (512 + math.cos(angle) * 335, 512 + math.sin(angle) * 335)
    side = (center[0] + math.cos(angle + 0.9) * 64, center[1] + math.sin(angle + 0.9) * 64)
    draw.polygon([center, tip, side], fill=(255, 237, 0))
for size in [16, 32, 128, 256, 512]:
    for scale in [1, 2]:
        suffix = "@2x" if scale == 2 else ""
        icon.resize((size * scale, size * scale), Image.Resampling.LANCZOS).save(iconset / f"icon_{size}x{size}{suffix}.png")
subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(assets / "AppIcon.icns")], check=True)
glow = Image.new("RGBA", (660, 340))
draw = ImageDraw.Draw(glow)
draw.ellipse((80, 95, 490, 200), fill=(255, 222, 0, 115))
draw.ellipse((350, 180, 630, 245), fill=(220, 0, 130, 135))
glow.rotate(20, resample=Image.Resampling.BICUBIC).filter(ImageFilter.GaussianBlur(35)).save(assets / "track-glow.png")
Image.open(root / "ref.png").crop((575, 238, 688, 342)).resize((240, 240)).save(assets / "reference-cover.png")
