"""Finalize only this Blender batch; validate hashes, alpha and 48px legibility."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "art_src/blender/achievements/qq_achievements.manifest.json"
PREVIEW = ROOT / "art_src/blender/previews/achievement_icons.png"
DATE = "2026-10-17"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def finalized(source):
    image = Image.open(source).convert("RGBA")
    assert image.size == (1024, 1024)
    bbox = image.getchannel("A").point(lambda a: 255 if a > 20 else 0).getbbox()
    assert bbox and min(bbox[:2]) >= 8 and max(bbox[2:]) <= 1016, f"Empty/clipped render: {source}"
    bounds = (bbox[0]-5, bbox[1]-5, bbox[2]+5, bbox[3]+5)
    image = image.crop(bounds)
    image.thumbnail((120, 120), Image.Resampling.LANCZOS)
    result = Image.new("RGBA", (128, 128))
    result.paste(image, ((128-image.width)//2, (128-image.height)//2))
    return result


def validate_png(path):
    with Image.open(path) as image:
        assert image.size == (128, 128) and image.mode == "RGBA", path
        alpha = image.getchannel("A")
        assert alpha.getextrema() == (0, 255), path
        assert all(alpha.getpixel(point) == 0 for point in [(0,0), (127,0), (0,127), (127,127)]), path
        small = image.resize((48, 48), Image.Resampling.LANCZOS)
        visible = sum(count for value, count in enumerate(small.getchannel("A").histogram()) if value > 80)
        assert visible >= 180, f"48px silhouette is too faint: {path} ({visible})"
        return visible


def register(meta):
    path = ROOT / "data/art_provenance.json"
    provenance = json.loads(path.read_text(encoding="utf-8"))
    owned = {entry["asset_id"] for entry in meta["assets"]}
    entries = [entry for entry in provenance["assets"] if entry["asset_id"] not in owned]
    for asset in meta["assets"]:
        entry = {key: value for key, value in asset.items() if key not in ("render_path", "render_sha256")}
        entry.update(generator=meta["generator"], source_sha256=meta["source_sha256"],
                     batch_id=meta["batch_id"], replacement_status="approved", author="QQ project",
                     tool="Blender " + meta["blender_version"], third_party_inputs=[], license="project-original")
        entries.append(entry)
    assert len({entry["asset_id"] for entry in entries}) == len(entries)
    assert len({entry["runtime_path"] for entry in entries}) == len(entries)
    provenance["assets"] = entries
    provenance["updated_at"] = DATE
    if meta["batch_id"] not in provenance["batch_ids"]: provenance["batch_ids"].append(meta["batch_id"])
    save_json(path, provenance)
    path = ROOT / "data/art_coverage.json"
    coverage = json.loads(path.read_text(encoding="utf-8"))
    coverage["updated_at"], coverage["registered_assets"] = DATE, len(entries)
    all_ids = {e["id"] for e in json.loads((ROOT/"data/achievements.json").read_text(encoding="utf-8"))}
    registered = {e["visual_id"] for e in entries if e.get("category") == "achievement"}
    coverage["coverage"]["Achievements"] = {"done": len(registered), "total": len(all_ids), "remaining": sorted(all_ids-registered)}
    save_json(path, coverage)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    meta = json.loads(MANIFEST.read_text(encoding="utf-8"))
    expected = {entry["id"] for entry in json.loads((ROOT / "data/achievements.json").read_text(encoding="utf-8")) if entry.get("tracking_version") != 1}
    assert {entry["visual_id"] for entry in meta["assets"]} == expected
    assert sha(ROOT / meta["source"]) == meta["source_sha256"]
    for path, digest in meta["generator_sha256"].items(): assert sha(ROOT / path) == digest, path
    if args.validate_only: assert sha(Path(__file__)) == meta["finalizer_sha256"]
    names = json.loads((ROOT / "data/localization/ja.json").read_text(encoding="utf-8"))
    font_path = str(ROOT / "assets/fonts/NotoSansJP-GameSubset.ttf")
    font, small_font = ImageFont.truetype(font_path, 15), ImageFont.truetype(font_path, 10)
    sheet = Image.new("RGB", (1440, 1050), "#101b25")
    draw = ImageDraw.Draw(sheet)
    seen = set()
    for index, entry in enumerate(meta["assets"]):
        path = (ROOT / entry["runtime_path"]).resolve()
        assert path.is_relative_to((ROOT / "assets/icons/achievements").resolve()), path
        if not args.validate_only:
            source = ROOT / entry["render_path"]
            assert sha(source) == entry["render_sha256"]
            path.parent.mkdir(parents=True, exist_ok=True)
            finalized(source).save(path)
            entry["export_sha256"] = sha(path)
        assert sha(path) == entry["export_sha256"]
        assert entry["export_sha256"] not in seen, f"Duplicate artwork: {entry['visual_id']}"
        seen.add(entry["export_sha256"])
        entry["visible_pixels_at_48px"] = validate_png(path)
        with Image.open(path) as icon:
            x, y = index % 6 * 240, index // 6 * 210
            sheet.paste(icon, (x+8, y+4), icon)
            small = icon.resize((48, 48), Image.Resampling.LANCZOS)
            for xx, color in [(x+151, "#070d13"), (x+151, "#e7e4da")]:
                yy = y+9 if color == "#070d13" else y+73
                draw.rounded_rectangle((xx, yy, xx+60, yy+60), radius=6, fill=color)
                sheet.paste(small, (xx+6, yy+6), small)
            label = names.get("achievement."+entry["visual_id"]+".name", entry["visual_id"])
            draw.text((x+9, y+146), label, font=font, fill="#f2d295")
            draw.text((x+9, y+174), entry["visual_id"], font=small_font, fill="#acbec8")
    if not args.validate_only:
        meta["finalizer_sha256"] = sha(Path(__file__))
        save_json(MANIFEST, meta)
        PREVIEW.parent.mkdir(parents=True, exist_ok=True)
        sheet.save(PREVIEW)
        register(meta)
    else:
        provenance = json.loads((ROOT / "data/art_provenance.json").read_text(encoding="utf-8"))
        registered = {entry["asset_id"]: entry for entry in provenance["assets"]}
        for entry in meta["assets"]: assert registered[entry["asset_id"]]["export_sha256"] == entry["export_sha256"]
    print("ACHIEVEMENT_ICON_VALIDATION_OK", len(expected), "unique 128px transparent icons with 48px silhouettes")


if __name__ == "__main__":
    main()
