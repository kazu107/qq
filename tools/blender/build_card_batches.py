"""Generate the 87 remaining cards + neutral fatigue, with verifiable resume.

Run with system Python/Pillow. Each 10-16 card batch uses an isolated background
Blender process, factory startup and four threads. Never connects to live MCP.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art_src/blender/cards"
LOCAL = ROOT / "tools/.local/blender_card_batches"
MANIFEST = SOURCE / "card_batches.manifest.json"
PROTECTED = {"quick_slash", "guard", "delay_step", "repair_burst", "auto_turret", "event_horizon"}
SAMPLE = "strike weak_shot quick_guard haste_focus reload brace_patch blood_chain crisis_drone_swarm quantum_exchange golden_ratio seraph_array atlas_protocol".split()
DEPENDENCIES = [
    "tools/blender/card_asset_scenes.py",
    "tools/blender/build_card_batches.py",
    "tools/blender/card_action_scenes.py",
    "tools/blender/build_art_vertical_slice.py",
]
SETTINGS = {"engine": "BLENDER_EEVEE", "source_size": 2048, "output_size": 512, "samples": 32, "threads": 4, "downsample": "Pillow_LANCZOS", "baked_text": False}


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1048576), b""):
            h.update(block)
    return h.hexdigest()


def canonical_hash(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()).hexdigest()


def relative(path):
    return Path(path).relative_to(ROOT).as_posix()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(temp, path)


def definitions():
    cards = json.loads((ROOT / "data/cards.json").read_text(encoding="utf-8-sig"))
    cards = {card["id"]: card for card in cards}
    if len(cards) != 93 or len(set(cards) - PROTECTED) != 87:
        raise RuntimeError("Card database changed; audit ownership before generating")
    cards["environment_fatigue"] = {
        "id": "environment_fatigue", "name": "Environment Fatigue",
        "description": "Neutral escalating fatigue hourglass threatens both sides; shielding and timeline effects still apply.",
        "rarity": "environment", "effects": [{"type": "environment_fatigue", "target": "both", "escalating": True}],
    }
    return {key: value for key, value in cards.items() if key not in PROTECTED}


def generator_hashes():
    return {name: digest(ROOT / name) for name in DEPENDENCIES}


def valid_entry(card, entry, dependencies):
    if not entry or entry.get("definition_sha256") != canonical_hash(card):
        return False
    if entry.get("generator_sha256") != canonical_hash(dependencies) or entry.get("render_settings") != SETTINGS:
        return False
    for path_key, hash_key in (("source_path", "source_sha256"), ("render_path", "render_sha256"), ("runtime_path", "export_sha256")):
        path = ROOT / entry.get(path_key, "missing")
        if not path.is_file() or digest(path) != entry.get(hash_key):
            return False
    return True


def load_entries():
    if not MANIFEST.is_file():
        return {}
    return {entry["id"]: entry for entry in json.loads(MANIFEST.read_text(encoding="utf-8"))["assets"]}


def aggregate(entries, protected_hashes):
    deps = generator_hashes()
    write_json(MANIFEST, {
        "batch_id": "blender_cards_C01_C13_completion",
        "generator": "tools/blender/build_card_batches.py",
        "generator_sha256": canonical_hash(deps), "generator_dependencies": deps,
        "blender_version": next((e["blender_version"] for e in entries.values()), "not_rendered"),
        "ordinary_count": sum(key != "environment_fatigue" for key in entries),
        "special_count": int("environment_fatigue" in entries),
        "protected_runtime_sha256": protected_hashes,
        "assets": sorted(entries.values(), key=lambda e: (e["family"], e["id"])),
    })


def finalize(entry):
    from PIL import Image
    source_render = ROOT / entry["render_path"]
    runtime = ROOT / entry["runtime_path"]
    with Image.open(source_render) as im:
        if im.size != (2048, 2048):
            raise RuntimeError("Expected actual 2048px Blender render: " + entry["id"])
        small = im.convert("RGBA").resize((512, 512), Image.Resampling.LANCZOS)
        temp = runtime.with_suffix(".tmp.png")
        small.save(temp, optimize=True)
        os.replace(temp, runtime)
    entry["export_sha256"] = digest(runtime)
    entry["size"] = [512, 512]
    entry["source_render_size"] = [2048, 2048]
    return entry


def protected_now():
    return {key: digest(ROOT / f"assets/icons/cards/{key}.png") for key in sorted(PROTECTED)}


def contact_sheet(ids, name, size=168, columns=4):
    from PIL import Image, ImageDraw, ImageFont
    ids = [cid for cid in ids if (ROOT / f"assets/icons/cards/{cid}.png").is_file()]
    margin, label, gap = 18, 28, 14
    rows = (len(ids) + columns - 1) // columns
    sheet = Image.new("RGB", (margin * 2 + columns * (size + gap) - gap, margin * 2 + rows * (size + label + gap) - gap), "#17232c")
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 12)
    except OSError:
        font = ImageFont.load_default()
    for i, cid in enumerate(ids):
        x, y = margin + i % columns * (size + gap), margin + i // columns * (size + label + gap)
        with Image.open(ROOT / f"assets/icons/cards/{cid}.png") as card:
            sheet.paste(card.convert("RGB").resize((size, size), Image.Resampling.LANCZOS), (x, y))
        draw.text((x + 2, y + size + 4), cid, fill="#dde6ed", font=font)
    path = SOURCE / "qa" / f"{name}.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path, optimize=True)
    print("QQ_CARD_QA", relative(path), flush=True)
    return path


def check_images(entries, cards, require_complete=False):
    from PIL import Image, ImageStat
    dependencies = generator_hashes()
    errors, hashes, checks = [], {}, []
    if require_complete and set(entries) != set(cards):
        errors.append("Incomplete IDs: " + ",".join(sorted(set(cards) - set(entries))))
    for cid, entry in entries.items():
        if cid not in cards or not valid_entry(cards[cid], entry, dependencies):
            errors.append("Source/generator/render/output hash invalid: " + cid)
            continue
        runtime = ROOT / entry["runtime_path"]
        with Image.open(runtime) as im:
            extrema = im.getextrema()
            if im.size != (512, 512) or im.mode != "RGBA" or extrema[3] != (255, 255):
                errors.append("Dimensions/format/opacity invalid: " + cid)
            stat = ImageStat.Stat(im.convert("RGB"))
            if max(stat.stddev) < 12 or max(stat.mean) < 12:
                errors.append("Blank or too dark: " + cid)
            thumb = im.convert("RGB").resize((32, 32))
            pixel_hash = hashlib.sha256(im.tobytes()).hexdigest()
            if pixel_hash in hashes:
                errors.append("Identical pixels: " + cid + " and " + hashes[pixel_hash])
            hashes[pixel_hash] = cid
            checks.append({"id": cid, "mean_rgb": stat.mean, "stddev_rgb": stat.stddev, "pixel_sha256": pixel_hash, "thumbnail_sha256": hashlib.sha256(thumb.tobytes()).hexdigest(), "blend_bytes": (ROOT / entry["source_path"]).stat().st_size})
        if (ROOT / entry["source_path"]).stat().st_size >= 100 * 1024 * 1024:
            errors.append("Blend exceeds GitHub per-file limit: " + cid)
    report = {"ordinary_count": sum(c["id"] != "environment_fatigue" for c in checks), "special_count": sum(c["id"] == "environment_fatigue" for c in checks), "expected_ordinary": 87, "expected_special": 1, "errors": errors, "assets": checks}
    write_json(SOURCE / "qa/validation.json", report)
    if errors:
        raise RuntimeError("Card validation failed: " + "; ".join(errors))
    print("QQ_CARD_VALIDATION_OK", report["ordinary_count"], report["special_count"], flush=True)
    return report


def worker(args):
    import bpy
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import card_asset_scenes as art
    cards = definitions()
    expected = set(cards)
    if set(art.RECIPES) != expected or set(cid for ids in art.FAMILIES.values() for cid in ids) != expected:
        raise RuntimeError("Every owned card must have one explicit semantic recipe")
    missing_backgrounds = {recipe[0] for recipe in art.RECIPES.values()} - set(art.ENV_COLORS)
    missing_frames = {recipe[2] for recipe in art.RECIPES.values()} - set(art.FRAMES)
    if missing_backgrounds or missing_frames:
        raise RuntimeError(f"Missing environment/frame presets: {missing_backgrounds} / {missing_frames}")
    deps = generator_hashes()
    if args.preflight:
        checks = []
        for cid in args.ids.split(","):
            kit = art.build(cards[cid])
            art.setup_rig(kit, SETTINGS["source_size"], SETTINGS["samples"])
            checks.append({"id": cid, "family": kit.family, "objects": len(kit.c.objects), "background": kit.recipe[0], "composition": kit.recipe[2]})
            print("QQ_CARD_BUILD_PREFLIGHT_OK", cid, len(kit.c.objects), flush=True)
        write_json(SOURCE / "qa/build_preflight.json", {"count": len(checks), "generator_sha256": canonical_hash(deps), "assets": checks})
        return
    if args.verify_sources:
        checks = []
        for cid in args.ids.split(","):
            blend = SOURCE / (cid + ".blend")
            bpy.ops.wm.open_mainfile(filepath=str(blend), load_ui=False)
            scene = bpy.context.scene
            collection = bpy.data.collections.get("CARD_" + cid)
            if collection is None or collection.get("card_id") != cid:
                raise RuntimeError("Wrong or missing editable source collection: " + cid)
            meshes = [obj for obj in collection.objects if obj.type == "MESH"]
            curves = [obj for obj in collection.objects if obj.type == "CURVE"]
            if len(meshes) < 10 or any(obj.type == "FONT" for obj in bpy.data.objects):
                raise RuntimeError("Missing actual editable 3D or unexpected baked text: " + cid)
            if scene.render.engine != "BLENDER_EEVEE" or (scene.render.resolution_x, scene.render.resolution_y) != (2048, 2048):
                raise RuntimeError("Source is not configured for 2048px EEVEE: " + cid)
            if not scene.camera or not all(obj.data.materials for obj in meshes):
                raise RuntimeError("Source camera or material is missing: " + cid)
            if any(mat.node_tree and any(node.type == "TEX_IMAGE" for node in mat.node_tree.nodes) for mat in bpy.data.materials):
                raise RuntimeError("Card scene must not paste old images onto geometry: " + cid)
            checks.append({"id": cid, "editable_meshes": len(meshes), "editable_curves": len(curves), "no_font_objects": True, "no_image_textures": True, "source_sha256": digest(blend)})
            print("QQ_CARD_SOURCE_REOPEN_OK", cid, len(meshes), len(curves), flush=True)
        write_json(SOURCE / "qa/source_reopen_validation.json", {"count": len(checks), "assets": checks})
        return
    for cid in args.ids.split(","):
        if cid not in cards:
            raise ValueError("Unowned ID: " + cid)
        start = time.perf_counter()
        print("QQ_CARD_BUILDING", cid, flush=True)
        kit = art.build(cards[cid])
        camera = art.setup_rig(kit, SETTINGS["source_size"], SETTINGS["samples"])
        blend = SOURCE / (cid + ".blend")
        render = LOCAL / "renders" / (cid + ".png")
        scene = bpy.context.scene
        scene.render.filepath = str(render)
        bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=True)
        bpy.ops.render.render(write_still=True)
        meshes = [obj for obj in kit.c.objects if obj.type == "MESH"]
        entry = {
            "id": cid, "visual_id": cid, "category": "card", "family": kit.family,
            "runtime_path": f"assets/icons/cards/{cid}.png",
            "source_path": relative(blend), "source_sha256": digest(blend),
            "render_path": relative(render), "render_sha256": digest(render),
            "generator": "tools/blender/build_card_batches.py",
            "generator_sha256": canonical_hash(deps), "generator_dependencies": deps,
            "definition_sha256": canonical_hash(cards[cid]),
            "blender_version": bpy.app.version_string, "render_settings": SETTINGS,
            "presentation": "unique_3d_card_action_illustration_no_pedestal_no_baked_text",
            "subject_action": kit.recipe[1], "background": kit.recipe[0], "composition": kit.recipe[2],
            "camera": camera, "shared_parts": sorted(kit.reused),
            "semantic_reuse_map": {"family": kit.family, "shared_parts": sorted(kit.reused), "unique_action": kit.recipe[1], "effects": cards[cid]["effects"]},
            "geometry": {"objects": len(kit.c.objects), "meshes": len(meshes), "vertices": sum(len(obj.data.vertices) for obj in meshes), "polygons": sum(len(obj.data.polygons) for obj in meshes)},
            "render_seconds": round(time.perf_counter() - start, 3),
        }
        write_json(LOCAL / "pending" / (cid + ".json"), entry)
        print("QQ_CARD_RENDERED", cid, entry["render_seconds"], flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blender", default="C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe")
    parser.add_argument("--sample", action="store_true")
    parser.add_argument("--ids", default="")
    parser.add_argument("--batch-size", type=int, default=12, choices=range(10, 17))
    parser.add_argument("--worker", action="store_true")
    parser.add_argument("--validate-only", action="store_true")
    parser.add_argument("--preview-only", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--verify-sources", action="store_true")
    parser.add_argument("--preflight", action="store_true")
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "bpy" in sys.modules and "--" in sys.argv else None)
    SOURCE.mkdir(parents=True, exist_ok=True)
    (LOCAL / "renders").mkdir(parents=True, exist_ok=True)
    (LOCAL / "pending").mkdir(parents=True, exist_ok=True)
    if args.worker:
        worker(args)
        return
    cards = definitions()
    entries = load_entries()
    protected = protected_now()
    if MANIFEST.is_file():
        previous = json.loads(MANIFEST.read_text(encoding="utf-8")).get("protected_runtime_sha256", {})
        if previous and previous != protected:
            raise RuntimeError("An approved first-six image changed; stop instead of silently accepting")
    selected = args.ids.split(",") if args.ids else SAMPLE if args.sample else list(cards)
    if set(selected) - set(cards):
        raise RuntimeError("Refusing to write non-owned card paths")
    if args.preview_only:
        contact_sheet(selected, "sample_12" if args.sample else "all_cards", columns=4 if args.sample else 8)
        return
    if args.preflight:
        cmd = [args.blender, "--background", "--factory-startup", "--threads", "4", "--python-exit-code", "1", "--python", str(Path(__file__).resolve()), "--", "--worker", "--preflight", "--ids", ",".join(selected)]
        subprocess.run(cmd, cwd=ROOT, check=True, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        return
    if args.verify_sources:
        check_images(entries, cards, args.require_complete)
        cmd = [args.blender, "--background", "--factory-startup", "--threads", "4", "--python-exit-code", "1", "--python", str(Path(__file__).resolve()), "--", "--worker", "--verify-sources", "--ids", ",".join(selected)]
        subprocess.run(cmd, cwd=ROOT, check=True, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        return
    if args.validate_only:
        check_images(entries, cards, args.require_complete)
        if protected_now() != protected:
            raise RuntimeError("Protected images changed")
        return
    dependencies = generator_hashes()
    remaining = [cid for cid in selected if args.force or not valid_entry(cards[cid], entries.get(cid), dependencies)]
    print("QQ_CARD_RESUME", "selected", len(selected), "hash_valid_skip", len(selected) - len(remaining), "render", len(remaining), flush=True)
    for batch_start in range(0, len(remaining), args.batch_size):
        ids = remaining[batch_start:batch_start + args.batch_size]
        logfile = LOCAL / f"batch_{batch_start // args.batch_size + 1}_{ids[0]}.log"
        cmd = [args.blender, "--background", "--factory-startup", "--threads", "4", "--python-exit-code", "1", "--python", str(Path(__file__).resolve()), "--", "--worker", "--ids", ",".join(ids)]
        print("QQ_CARD_BATCH", ids, "log", relative(logfile), flush=True)
        for cid in ids:
            (LOCAL / "pending" / (cid + ".json")).unlink(missing_ok=True)
        with logfile.open("w", encoding="utf-8") as stream:
            process = subprocess.Popen(cmd, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
            reported = set()
            while process.poll() is None:
                for cid in ids:
                    pending = LOCAL / "pending" / (cid + ".json")
                    if cid not in reported and pending.is_file():
                        provisional = json.loads(pending.read_text(encoding="utf-8"))
                        if provisional.get("generator_sha256") == canonical_hash(dependencies) and provisional.get("definition_sha256") == canonical_hash(cards[cid]) and digest(ROOT / provisional["source_path"]) == provisional["source_sha256"] and digest(ROOT / provisional["render_path"]) == provisional["render_sha256"]:
                            entries[cid] = finalize(provisional)
                            aggregate(entries, protected)
                            reported.add(cid)
                            print("QQ_CARD_INSTALLED", cid, "total", len(entries), flush=True)
                time.sleep(2)
        for cid in ids:
            if cid not in reported and (LOCAL / "pending" / (cid + ".json")).is_file():
                provisional = json.loads((LOCAL / "pending" / (cid + ".json")).read_text(encoding="utf-8"))
                if provisional.get("generator_sha256") == canonical_hash(dependencies):
                    entries[cid] = finalize(provisional)
                    aggregate(entries, protected)
                    reported.add(cid)
        if process.returncode:
            tail = logfile.read_text(encoding="utf-8", errors="replace")[-5000:]
            raise RuntimeError(f"Blender failed ({process.returncode}); completed files preserved.\n{tail}")
        if reported != set(ids):
            raise RuntimeError("Blender did not produce every requested card")
        contact_sheet(ids, "sample_12" if args.sample else f"batch_{batch_start // args.batch_size + 1:02d}_{ids[0]}")
        if protected_now() != protected:
            raise RuntimeError("Protected first-six images changed")
    aggregate(entries, protected)
    check_images(entries, cards, args.require_complete)
    if not args.sample and len(entries) == 88:
        contact_sheet(list(cards), "all_cards_168", columns=8)
        contact_sheet(list(cards), "all_cards_74", size=74, columns=8)
    print("QQ_CARD_BATCHES_DONE", len(entries), flush=True)


if __name__ == "__main__":
    main()
