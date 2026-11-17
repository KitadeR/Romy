#!/usr/bin/env python3
"""QA overview; the individual screenshots stay unchanged."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[2]
files = sorted((root / 'output/fenrir/screenshots').glob('*.png'))
thumb_width = 330
thumb_height = 717
margin = 26
label_height = 38
canvas = Image.new('RGB', (margin + 4 * (thumb_width + margin), margin + 2 * (thumb_height + label_height + margin)), '#eeece9')
draw = ImageDraw.Draw(canvas)
font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 18)
for index, file in enumerate(files):
    column, row = index % 4, index // 4
    x = margin + column * (thumb_width + margin)
    y = margin + row * (thumb_height + label_height + margin)
    draw.text((x, y), file.stem, fill='#222222', font=font)
    screenshot = Image.open(file).convert('RGB')
    assert screenshot.size == (1320, 2868), (file.name, screenshot.size)
    screenshot.thumbnail((thumb_width, thumb_height), Image.Resampling.LANCZOS)
    canvas.paste(screenshot, (x, y + label_height))
canvas.save(root / 'output/fenrir/overview.png')
print(root / 'output/fenrir/overview.png')
