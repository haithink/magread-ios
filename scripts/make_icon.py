"""Generate the original MagRead icon using simple geometric artwork."""
from pathlib import Path
import json
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1] / 'Resources' / 'Assets.xcassets'
folder = root / 'AppIcon.appiconset'
folder.mkdir(parents=True, exist_ok=True)
scale = 3
size = 1024
image = Image.new('RGB', (size * scale, size * scale), '#143c47')
draw = ImageDraw.Draw(image)

def polygon(points, fill):
    draw.polygon([(round(x * scale), round(y * scale)) for x, y in points], fill=fill)

def line(points, fill, width):
    draw.line([(round(x * scale), round(y * scale)) for x, y in points], fill=fill, width=width * scale)

polygon([(170, 265), (450, 300), (512, 350), (575, 300), (854, 265), (854, 750), (580, 782), (512, 830), (445, 782), (170, 750)], '#92b4b4')
polygon([(170, 220), (438, 253), (500, 305), (500, 763), (438, 721), (170, 687)], '#fff5df')
polygon([(524, 305), (586, 253), (854, 220), (854, 687), (586, 721), (524, 763)], '#f3e7ce')
for y in [375, 455, 535, 615]:
    line([(230, y), (421, y + 25)], '#87a4a4', 13)
for y in [375, 455, 535]:
    line([(602, y + 25), (795, y)], '#87a4a4', 13)
polygon([(693, 205), (768, 196), (768, 418), (731, 389), (693, 428)], '#e6a84d')
image.resize((size, size), Image.Resampling.LANCZOS).save(folder / 'AppIcon.png')
(root / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}, indent=2))
(folder / 'Contents.json').write_text(json.dumps({'images': [{'filename': 'AppIcon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}], 'info': {'author': 'xcode', 'version': 1}}, indent=2))
