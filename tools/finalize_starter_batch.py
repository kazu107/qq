"""Validate the completed Blender batch and register its runtime provenance."""

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE_MANIFEST = ROOT / "art_src/blender/characters/qq_starters.manifest.json"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    manifest = json.loads(SOURCE_MANIFEST.read_text(encoding="utf-8"))
    for field in ("source", "library", "generator", "parts_generator"):
        if digest(ROOT / manifest[field]) != manifest[field + "_sha256"]:
            raise RuntimeError(f"Stale batch {field}; regenerate it before importing")
    path = ROOT / "data/art_provenance.json"
    provenance = json.loads(path.read_text(encoding="utf-8-sig"))
    additions = []
    for asset in manifest["assets"]:
        for kind in ("model", "portrait"):
            runtime = ROOT / asset[kind]
            if digest(runtime) != asset[kind + "_sha256"]:
                raise RuntimeError(f"Stale output: {runtime}")
            if kind == "model" and asset["id"] == "balanced":
                continue
            additions.append({
                "asset_id": asset["id"] if kind == "model" else "portrait_" + asset["id"],
                "category": "character_3d" if kind == "model" else "portrait",
                "runtime_path": asset[kind], "source_path": manifest["source"],
                "generator": manifest["generator"], "source_library": manifest["library"],
                "export_sha256": asset[kind + "_sha256"], "replacement_status": "implemented",
                "batch_id": manifest["batch_id"], "presentation": "rigged_character" if kind == "model" else "same_model_portrait",
            })
    ids = {asset["asset_id"] for asset in additions}
    provenance["assets"] = [asset for asset in provenance["assets"] if asset["asset_id"] not in ids] + additions
    provenance["batch_ids"] = ["blender_vertical_slice_01", manifest["batch_id"]]
    provenance["updated_at"] = "2026-09-09"
    path.write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    # QA contact sheet only; the game images are rendered and resized by Blender.
    sheet = Image.new("RGB", (1792, 316), (12, 19, 26))
    draw = ImageDraw.Draw(sheet)
    font_path = ROOT / "assets/fonts/NotoSansJP-GameSubset.ttf"
    font = ImageFont.truetype(str(font_path), 18)
    for index, asset in enumerate(manifest["assets"]):
        image = Image.open(ROOT / asset["portrait"]).convert("RGB")
        if image.size != (1024, 1024):
            raise RuntimeError(f"Invalid portrait size: {asset['id']}")
        image.thumbnail((248, 248), Image.Resampling.LANCZOS)
        sheet.paste(image, (index * 256 + 4, 8))
        draw.text((index * 256 + 128, 278), asset["id"].upper(), anchor="mm", font=font, fill=(220, 232, 238))
    sheet.save(ROOT / "art_src/blender/previews/starter_batch_portraits.png")
    print(f"STARTER_BATCH_IMPORT_OK {len(additions)} runtime assets; {len(provenance['assets'])} authored assets total")


if __name__ == "__main__":
    main()
