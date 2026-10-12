"""Downsample actual Blender renders and validate miniature action artwork."""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "art_src/blender/ui/qq_ui_actions.manifest.json"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    meta = json.loads(MANIFEST.read_text(encoding="utf-8"))
    expected = set(json.loads((ROOT / "data/ui_action_icons.json").read_text(encoding="utf-8")))
    assert {entry["visual_id"] for entry in meta["assets"]} == expected
    assert sha(ROOT / meta["source"]) == meta["source_sha256"]
    for path, digest in meta["generator_sha256"].items():
        assert sha(ROOT / path) == digest, f"Stale generator: {path}"
    hashes = set()
    sheet = Image.new("RGB", (720, ((len(expected) + 5) // 6) * 135), "#14202a")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype(str(ROOT / "assets/fonts/NotoSansJP-GameSubset.ttf"), 11)
    for index, entry in enumerate(meta["assets"]):
        path = ROOT / entry["runtime_path"]
        if not args.validate_only:
            with Image.open(ROOT / entry["render_path"]) as source:
                assert source.size == (1024, 1024)
                source.convert("RGBA").resize((64, 64), Image.Resampling.LANCZOS).save(path)
            entry["export_sha256"] = sha(path)
        assert sha(path) == entry["export_sha256"]
        assert entry["export_sha256"] not in hashes, f"Duplicate icon: {entry['visual_id']}"
        hashes.add(entry["export_sha256"])
        with Image.open(path) as image:
            assert image.size == (64, 64) and image.mode == "RGBA"
            alpha = image.getchannel("A")
            for corner in [(0, 0), (63, 0), (0, 63), (63, 63)]: assert alpha.getpixel(corner) == 0
            miniature = image.resize((24, 24), Image.Resampling.LANCZOS)
            # Bare arrows and crossed blades use less area than solid badges.
            assert sum(count for value, count in enumerate(miniature.getchannel("A").histogram()) if value > 80) >= 48, entry["visual_id"]
            x, y = (index % 6) * 120, (index // 6) * 135
            sheet.paste(image, (x + 25, y + 7), image)
            sheet.paste(miniature, (x + 17, y + 83), miniature)
            draw.rectangle((x + 62, y + 80, x + 108, y + 112), fill="#ece8dc")
            sheet.paste(miniature, (x + 72, y + 84), miniature)
            draw.text((x + 4, y + 115), entry["visual_id"], font=font, fill="#dfe6e9")
    if not args.validate_only:
        MANIFEST.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
        sheet.save(ROOT / "art_src/blender/previews/action_icons_24px.png")
    print("ACTION_ICON_VALIDATION_OK", len(expected), "unique 64px icons with 24px silhouettes")


if __name__ == "__main__":
    main()
