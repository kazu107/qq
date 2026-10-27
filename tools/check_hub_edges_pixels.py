"""Check rendered Hub edge shading using a uniform source texture."""
import json
from pathlib import Path

from PIL import Image


root = Path(__file__).resolve().parent / ".local" / "hub-edges" / "browser"
report = json.loads((root / "report.json").read_text(encoding="utf-8"))
for sample in report["samples"]:
    image = Image.open(root / sample["file"]).convert("RGB")
    width, height = image.size
    y = round(height * 0.17)
    xs = [round(width * value) for value in (0.015, 0.06, 0.12, 0.5, 0.88, 0.94, 0.985)]
    pixels = [image.getpixel((x, y)) for x in xs]
    delta = max(max(pixel[channel] for pixel in pixels) - min(pixel[channel] for pixel in pixels) for channel in range(3))
    assert delta <= 1, f"Hub edge band remains: {width}x{height} {pixels}"
    print(f"HUB_EDGE_PIXELS_OK {width}x{height} max_rgb_delta={delta} color={pixels[0]}")
