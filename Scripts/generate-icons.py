#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw
import subprocess

ROOT = Path(__file__).resolve().parent.parent
MASTER = Path.home() / ".codex/generated_images/019fce8b-e390-7ce0-96bb-bef5160824b3/exec-3ab866df-203b-4a5b-a0e9-2b917b61dc3d.png"
REFERENCE = Path.home() / "Downloads/70039be38d17c22d2ab80d17321788ed.png"
MENU_SVG = Path.home() / "Downloads/brand-dji-svgrepo-com.svg"
RESOURCES = ROOT / "Resources"
ICONSET = RESOURCES / "AppIcon.iconset"
ICONSET.mkdir(parents=True, exist_ok=True)

master = Image.open(MASTER).convert("RGBA").resize((1024, 1024), Image.Resampling.LANCZOS)
rounded_alpha = Image.new("L", (1024, 1024), 0)
ImageDraw.Draw(rounded_alpha).rounded_rectangle((18, 18, 1005, 1005), radius=185, fill=255)
master.putalpha(rounded_alpha)
master.save(RESOURCES / "AppIcon.png")
for points in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        pixels = points * scale
        suffix = "@2x" if scale == 2 else ""
        master.resize((pixels, pixels), Image.Resampling.LANCZOS).save(
            ICONSET / f"icon_{points}x{points}{suffix}.png"
        )

# Convert the supplied gray-on-black mark to a compact monochrome template.
source = Image.open(REFERENCE).convert("RGB")
mask = Image.new("L", source.size)
mask.putdata([255 if max(pixel) > 70 else 0 for pixel in source.get_flattened_data()])
bbox = mask.getbbox()
if not bbox:
    raise RuntimeError("DJI mark was not found in the reference image")
mark = mask.crop(bbox)
for scale in (1, 2):
    canvas_width, canvas_height = 24 * scale, 18 * scale
    max_width, max_height = 23 * scale, 13 * scale
    ratio = min(max_width / mark.width, max_height / mark.height)
    resized = mark.resize((round(mark.width * ratio), round(mark.height * ratio)), Image.Resampling.LANCZOS)
    alpha = Image.new("L", (canvas_width, canvas_height))
    alpha.paste(resized, ((canvas_width - resized.width) // 2, (canvas_height - resized.height) // 2))
    template = Image.new("RGBA", (canvas_width, canvas_height), (0, 0, 0, 0))
    template.putalpha(alpha)
    suffix = "@2x" if scale == 2 else ""
    template.save(RESOURCES / f"MenuBarIconTemplate{suffix}.png")

subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(RESOURCES / "AppIcon.icns")], check=True)

# Keep the menu mark vector-sharp and crop the source SVG's large vertical margins.
svg = MENU_SVG.read_text()
svg = svg.replace('width="800px" height="800px" viewBox="0 0 14 14"',
                  'width="24" height="14" viewBox="0.8 3.3 12.4 7.4"')
(RESOURCES / "MenuBarDJI.svg").write_text(svg)
