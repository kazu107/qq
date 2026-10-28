"""Build a review sheet from browser captures, not game artwork."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FIELDS = [
    ("clock_ruins", "苔むす時計遺跡"), ("brass_foundry", "真鍮の機械工房"),
    ("rift_gallery", "亀裂の浮遊回廊"), ("forgotten_sanctuary", "忘れられた時の聖域"),
    ("timekeeper_engine", "大時計塔の機関室"), ("paradox_reactor", "循環する中枢炉"),
    ("axiom_altar", "崩壊した法則の祭壇"), ("eternity_temple", "終刻の神殿"),
]
canvas = Image.new("RGB", (1600, 540), "#0b1119")
draw = ImageDraw.Draw(canvas)
font = ImageFont.truetype(str(ROOT / "assets/fonts/NotoSansJP-GameSubset.ttf"), 18)
for index, (key, title) in enumerate(FIELDS):
    image = Image.open(ROOT / "tools/.local/battle-biomes/browser" / (key + ".png")).convert("RGB")
    image = image.crop((0, 60, image.width, 585)).resize((392, 220), Image.Resampling.LANCZOS)
    x, y = index % 4 * 400 + 4, index // 4 * 270 + 4
    canvas.paste(image, (x, y))
    draw.text((x + 5, y + 226), title, fill="#d6e5ed", font=font)
target = ROOT / "art_src/blender/previews/battle_biomes.png"
target.parent.mkdir(parents=True, exist_ok=True)
canvas.save(target)
print(target)
