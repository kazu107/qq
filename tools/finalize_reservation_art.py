"""Downsample original Blender renders and register their provenance."""
from pathlib import Path
import hashlib
import json
import sys
from PIL import Image, ImageDraw
from asset_image_io import save_png_atomic

ROOT = Path(__file__).resolve().parents[1]
manifest_path = "art_src/blender/cards/reservation_cards.manifest.json"
manifest = json.loads((ROOT / manifest_path).read_text(encoding="utf-8"))
def sha(path): return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
assert sha(manifest["source_path"]) == manifest["source_sha256"]
deps = {path: sha(path) for path in [manifest["generator"], "tools/blender/build_art_vertical_slice.py", "tools/blender/card_action_scenes.py", "tools/blender/recent_card_environments.py"]}
provenance_path = ROOT / "data/art_provenance.json"
provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
sheet = Image.new("RGB", (6 * 192, 4 * 214), "#101a24")
draw = ImageDraw.Draw(sheet)
for index, asset in enumerate(manifest["assets"]):
    if asset["category"] == "card" or "--cards-only" not in sys.argv:
        image = Image.open(ROOT / "tools/.local/reservations/art" / (asset["asset_id"] + ".png")).convert("RGBA")
        save_png_atomic(image.resize((asset["size"], asset["size"]), Image.Resampling.LANCZOS), ROOT / asset["runtime_path"])
    else:
        image = Image.open(ROOT / asset["runtime_path"]).convert("RGBA")
    entry = dict(asset, source_path=manifest["source_path"], generator=manifest["generator"], export_sha256=sha(asset["runtime_path"]), source_sha256=manifest["source_sha256"], generator_sha256=deps, manifest_path=manifest_path, tool=manifest["tool"], replacement_status="implemented", batch_id="blender_reservations_10", author="QQ project", license="project-original", third_party_inputs=[])
    old = next((a for a in provenance["assets"] if a["runtime_path"] == entry["runtime_path"]), None)
    if old:
        assert old["generator"] == manifest["generator"], "Refusing to replace another asset owner"
        old.clear(); old.update(entry)
    else: provenance["assets"].append(entry)
    x, y = index % 6 * 192, index // 6 * 214
    sheet.paste(image.resize((192, 192), Image.Resampling.LANCZOS), (x, y), image.resize((192, 192), Image.Resampling.LANCZOS))
    draw.text((x + 4, y + 194), asset["asset_id"].replace("reserve_", ""), fill="white")
if "blender_reservations_10" not in provenance["batch_ids"]: provenance["batch_ids"].append("blender_reservations_10")
provenance["updated_at"] = "2026-10-26"
provenance_path.write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
coverage_path = ROOT / "data/art_coverage.json"
coverage = json.loads(coverage_path.read_text(encoding="utf-8")); coverage["updated_at"] = "2026-10-26"
coverage["registered_assets"] = len(provenance["assets"])
coverage["coverage"]["Cards"]["done"] = coverage["coverage"]["Cards"]["total"] = len(json.loads((ROOT / "data/cards.json").read_text(encoding="utf-8")))
coverage["coverage"]["Status"]["done"] = coverage["coverage"]["Status"]["total"] = len([a for a in provenance["assets"] if a["category"] == "status"])
coverage_path.write_text(json.dumps(coverage, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
sheet.save(ROOT / "tools/.local/reservations/contact-sheet.png")
print("RESERVATION_ART_REGISTERED", len(manifest["assets"]))
