"""Resize Blender renders, make QA sheets, and validate the local UI manifest.

Does not write shared provenance, release metadata, or any other batch's assets.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "art_src/blender/ui/qq_small_icons.manifest.json"
PREVIEWS = ROOT / "art_src/blender/previews"
EXPECTED = {
    "status": {"slow", "vulnerable", "weak"},
    "ui": {"speed", "shield", "hp", "gold", "step", "time", "relic", "card_owned",
           "card_equipped", "settings", "version_history", "card"},
    "effect": {"shield_spend", "delay", "haste", "recast", "interrupt", "cleanse", "empower",
               "auto_queue", "timeline_stop", "timeline_reverse", "status", "effect"},
    "map": {"normal_battle", "elite_battle", "boss", "shop", "forge", "heal", "event", "hazard", "lock"},
    "control": {"checkbox_on", "checkbox_off", "checkbox_on_disabled", "checkbox_off_disabled",
                "switch_on", "switch_off", "switch_on_disabled", "switch_off_disabled",
                "slider_grabber", "slider_grabber_highlight"},
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def safe_target(relative):
    path = (ROOT / relative).resolve()
    if not path.is_relative_to(ROOT / "assets/icons"):
        raise RuntimeError("Output escaped the owned icon directory: " + relative)
    return path


def resized(source, target_size):
    image = Image.open(source).convert("RGBA")
    if image.size != (512, 512):
        raise RuntimeError("UI source render must be 512px: " + str(source))
    alpha = image.getchannel("A")
    bbox = alpha.point(lambda a: 255 if a > 16 else 0).getbbox()
    if bbox is None or min(bbox[:2]) < 2 or max(bbox[2:]) > 510:
        raise RuntimeError("Empty or clipped source pictogram: " + str(source))
    image = image.crop((max(0, bbox[0]-5), max(0, bbox[1]-5), min(512, bbox[2]+5), min(512, bbox[3]+5)))
    margin = 2 if min(target_size) >= 64 else 1
    image.thumbnail((target_size[0]-margin*2, target_size[1]-margin*2), Image.Resampling.LANCZOS)
    output = Image.new("RGBA", target_size)
    output.paste(image, ((target_size[0]-image.width)//2, (target_size[1]-image.height)//2))
    return output


def validate_image(path, size):
    image = Image.open(path)
    if image.mode != "RGBA" or list(image.size) != size:
        raise RuntimeError("Wrong PNG format/size: " + str(path))
    alpha = image.getchannel("A")
    if any(alpha.getpixel(corner) > 0 for corner in ((0, 0), (image.width-1, 0), (0, image.height-1), (image.width-1, image.height-1))):
        raise RuntimeError("Opaque background/corner: " + str(path))
    if not alpha.getbbox() or alpha.getextrema() != (0, 255):
        raise RuntimeError("Empty or translucent-only pictogram: " + str(path))
    small = image.copy()
    small.thumbnail((24, 24), Image.Resampling.LANCZOS)
    visible = sum(a > 80 for a in small.getchannel("A").getdata())
    if visible < 32:
        raise RuntimeError("Silhouette disappears at 24px: " + str(path))
    return {"alpha_visible_pixels_at_24px": visible, "alpha_corners": [0, 0, 0, 0]}


def contact_sheets(assets):
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    font_path = ROOT / "assets/fonts/NotoSansJP-GameSubset.ttf"
    font = ImageFont.truetype(str(font_path), 13)
    title_font = ImageFont.truetype(str(font_path), 20)
    for category in EXPECTED:
        group = [entry for entry in assets if entry["category"] == category]
        cols, tile_w, tile_h = 4, 264, 154
        rows = (len(group)+cols-1)//cols
        sheet = Image.new("RGB", (cols*tile_w, rows*tile_h+48), (12, 20, 28))
        draw = ImageDraw.Draw(sheet)
        draw.text((18, 12), f"BLENDER {category.upper()} / 96px + 24px on dark/light", font=title_font, fill=(222, 235, 241))
        for i, entry in enumerate(group):
            x, y = (i % cols)*tile_w, (i//cols)*tile_h+48
            image = Image.open(ROOT / entry["runtime_path"]).convert("RGBA")
            large = image.copy()
            large.thumbnail((96, 96), Image.Resampling.LANCZOS)
            sheet.paste(large, (x+12+(96-large.width)//2, y+4+(96-large.height)//2), large)
            small = image.copy()
            small.thumbnail((24, 24), Image.Resampling.LANCZOS)
            for bg_x, bg_color in ((x+136, (7, 15, 23)), (x+190, (228, 234, 238))):
                draw.rounded_rectangle((bg_x, y+27, bg_x+42, y+69), radius=5, fill=bg_color)
                sheet.paste(small, (bg_x+(42-small.width)//2, y+27+(42-small.height)//2), small)
            draw.text((x+12, y+113), entry["visual_id"], font=font, fill=(218, 232, 239))
            draw.text((x+12, y+134), "x".join(map(str, entry["size"]))+" RGBA / editable 3D", font=font, fill=(125, 151, 167))
        sheet.save(PREVIEWS / f"ui_batch_{category}.png")
    # One source-state atlas makes the on/off/disabled controls reviewable together.
    controls = [entry for entry in assets if entry["category"] == "control"]
    atlas = Image.new("RGBA", (256, 128))
    regions = {}
    for i, entry in enumerate(controls):
        x, y = (i % 4)*64, (i//4)*40
        image = Image.open(ROOT / entry["runtime_path"]).convert("RGBA")
        atlas.paste(image, (x, y))
        regions[entry["visual_id"]] = [x, y, image.width, image.height]
    atlas_path = ROOT / "art_src/blender/ui/control_states.atlas.png"
    atlas.save(atlas_path)
    return {"path": atlas_path.relative_to(ROOT).as_posix(), "sha256": sha(atlas_path), "regions": regions}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if args.validate_only and sha(Path(__file__)) != manifest.get("finalizer_sha256"):
        raise RuntimeError("Finalizer changed; rerun finalization to refresh its hash")
    for field in ("source", "generator"):
        if sha(ROOT / manifest[field]) != manifest[field+"_sha256"]:
            raise RuntimeError("Source hash is stale: " + manifest[field])
    for path, digest in manifest["preserved_assets"].items():
        if sha(ROOT / path) != digest:
            raise RuntimeError("Existing first-batch asset changed: " + path)
    assets = manifest["assets"]
    ids = [entry["id"] for entry in assets]
    paths = [entry["runtime_path"] for entry in assets]
    if len(ids) != len(set(ids)) or len(paths) != len(set(paths)):
        raise RuntimeError("Duplicate batch IDs or target paths")
    for category, expected in EXPECTED.items():
        actual = {entry["visual_id"] for entry in assets if entry["category"] == category}
        if actual != expected:
            raise RuntimeError(f"Incomplete {category}: missing {expected-actual}; extra {actual-expected}")
    for entry in assets:
        target = safe_target(entry["runtime_path"])
        if not args.validate_only:
            render = ROOT / entry["render_path"]
            if sha(render) != entry["render_sha256"]:
                raise RuntimeError("Stale source render: " + entry["id"])
            target.parent.mkdir(parents=True, exist_ok=True)
            resized(render, tuple(entry["size"])).save(target, optimize=True)
            entry["export_sha256"] = sha(target)
            entry["source_sha256"] = manifest["source_sha256"]
            entry["replacement_status"] = "implemented"
        if sha(target) != entry["export_sha256"]:
            raise RuntimeError("Stale runtime output: " + entry["id"])
        entry["validation"] = validate_image(target, entry["size"])
    # Pause/reverse and delay/haste must not accidentally share the same picture.
    if len({entry["export_sha256"] for entry in assets}) != len(assets):
        raise RuntimeError("Two icons have identical exports")
    lock_entry = next(entry for entry in assets if entry["id"] == "map_lock")
    lock_image = Image.open(ROOT / lock_entry["runtime_path"]).convert("RGBA")
    if lock_image.getchannel("A").getpixel((lock_image.width//2, lock_image.height//4)) > 32:
        raise RuntimeError("The lock shackle hole is not transparent")
    if not args.validate_only:
        manifest["control_state_atlas"] = contact_sheets(assets)
        manifest["category_counts"] = dict(Counter(entry["category"] for entry in assets))
        manifest["finalizer"] = "tools/finalize_ui_batch.py"
        manifest["finalizer_sha256"] = sha(Path(__file__))
        MANIFEST.write_text(json.dumps(manifest, indent=2)+"\n", encoding="utf-8")
    else:
        atlas = manifest["control_state_atlas"]
        if sha(ROOT / atlas["path"]) != atlas["sha256"]:
            raise RuntimeError("Control state atlas changed")
        if set(atlas["regions"]) != EXPECTED["control"]:
            raise RuntimeError("Control state atlas is incomplete")
    print("BLENDER_UI_BATCH_OK", len(assets), dict(Counter(entry["category"] for entry in assets)))


if __name__ == "__main__":
    main()
