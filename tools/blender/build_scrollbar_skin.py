"""Render editable slim scroll rails in an isolated Blender process."""
from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_ui_batch as kit

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art_src/blender/ui/qq_scrollbars.blend"
MANIFEST = SOURCE.with_suffix(".manifest.json")
BATCH = "blender_scrollbars_13"
STATES = ("track", "grabber", "highlight", "pressed")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return path.relative_to(ROOT).as_posix()


def save_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def build(state):
    if state == "track":
        kit.box("Recessed_Rail", 0, 0, .36, 2.98, "iron", 0, .16, .05)
        kit.box("Rail_Channel", 0, 0, .25, 2.84, "dim", -.10, .06, .025)
        return
    face, line = {"grabber": ("steel", "teal"), "highlight": ("cyan", "white"), "pressed": ("gold", "amber")}[state]
    kit.box("Beveled_Thumb", 0, 0, .34, 2.98, "iron", 0, .16, .05)
    kit.box("Metal_Face", 0, 0, .27, 2.88, face, -.105, .07, .035)
    kit.box("Inlaid_Center", 0, 0, .055, 2.58, line, -.15, .035, .012)
    for z in (-1.27, 1.27):
        kit.box("End_Grip", 0, z, .19, .035, "gold" if state != "pressed" else "white", -.158, .025, .008)


def register(meta):
    path = ROOT / "data/art_provenance.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    owned = {asset["asset_id"] for asset in meta["assets"]}
    data["assets"] = [asset for asset in data["assets"] if asset["asset_id"] not in owned]
    for asset in meta["assets"]:
        data["assets"].append({**asset, "generator": rel(Path(__file__)), "source_path": rel(SOURCE),
            "source_sha256": meta["source_sha256"], "generator_sha256": meta["generator_sha256"],
            "manifest_path": rel(MANIFEST), "batch_id": BATCH, "replacement_status": "approved",
            "author": "QQ project", "license": "project-original", "third_party_inputs": [],
            "tool": "Blender " + bpy.app.version_string})
    assert len({asset["asset_id"] for asset in data["assets"]}) == len(data["assets"])
    assert len({asset["runtime_path"] for asset in data["assets"]}) == len(data["assets"])
    if BATCH not in data["batch_ids"]:
        data["batch_ids"].append(BATCH)
    data["updated_at"] = "2026-10-28"
    save_json(path, data)
    path = ROOT / "data/art_coverage.json"
    coverage = json.loads(path.read_text(encoding="utf-8"))
    coverage.update(updated_at="2026-10-28", registered_assets=len(data["assets"]))
    coverage["coverage"]["Scrollbars"] = {"done": 8, "total": 8, "remaining": []}
    save_json(path, coverage)


def validate():
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assert sha(SOURCE) == data["source_sha256"]
    for path, digest in data["generator_sha256"].items():
        assert sha(ROOT / path) == digest, "Stale generator: " + path
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    for asset in data["assets"]:
        assert bpy.data.collections.get(asset["source_collection"]) is not None
        path = ROOT / asset["runtime_path"]
        assert sha(path) == asset["export_sha256"]
        image = bpy.data.images.load(str(path), check_existing=False)
        assert list(image.size) == asset["size"]
        pixels = image.pixels
        w, h = image.size
        assert all(pixels[(y * w + x) * 4 + 3] < .01 for x, y in ((0, 0), (w-1, 0), (0, h-1), (w-1, h-1)))
        assert max(pixels[3::4]) > .9
        bpy.data.images.remove(image)
    print("BLENDER_SCROLLBAR_VALIDATION_OK 8 authored rails/thumbs", flush=True)


def main():
    if "--validate-only" in sys.argv:
        validate()
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    SOURCE.parent.mkdir(parents=True, exist_ok=True)
    output = ROOT / "assets/icons/controls"
    output.mkdir(parents=True, exist_ok=True)
    kit.materials()
    kit.render_rig()
    scene = bpy.context.scene
    scene.camera.location = (0, -7, 0)
    scene.camera.rotation_euler = (Vector((0, 0, 0)) - scene.camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera.data.ortho_scale = 3.2
    scene.render.resolution_percentage = 100
    collections, assets = [], []
    for orientation in ("v", "h"):
        for state in STATES:
            visual_id = f"scrollbar_{orientation}_{state}"
            collection = bpy.data.collections.new(visual_id)
            scene.collection.children.link(collection)
            collection.asset_mark()
            kit.CURRENT = collection
            build(state)
            if orientation == "h":
                rotation = Matrix.Rotation(math.pi / 2, 4, "Y")
                for obj in collection.objects:
                    obj.matrix_world = rotation @ obj.matrix_world
            size = [24, 160] if orientation == "v" else [160, 24]
            collections.append(collection)
            assets.append({"asset_id": "control_" + visual_id, "category": "control", "visual_id": visual_id,
                "runtime_path": f"assets/icons/controls/{visual_id}.png", "source_collection": collection.name,
                "size": size, "presentation": "transparent_orthographic_3d_nine_slice"})
    for collection, asset in zip(collections, assets):
        for other in collections:
            other.hide_render = other != collection
        w, h = asset["size"]
        scene.render.resolution_x, scene.render.resolution_y = w * 4, h * 4
        target = ROOT / asset["runtime_path"]
        render = ROOT / "tools/.local/scrollbar-skin" / target.name
        render.parent.mkdir(parents=True, exist_ok=True)
        scene.render.filepath = str(render)
        bpy.ops.render.render(write_still=True)
        image = bpy.data.images.load(str(render), check_existing=False)
        image.scale(w, h)
        image.filepath_raw = str(target)
        image.save()
        bpy.data.images.remove(image)
        asset["export_sha256"] = sha(target)
        print("SCROLLBAR_RENDER_OK " + asset["visual_id"], flush=True)
    for collection in collections:
        collection.hide_render = collection.hide_viewport = collection != collections[1]
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE), compress=True)
    data = {"format_version": 1, "batch_id": BATCH, "source": rel(SOURCE), "source_sha256": sha(SOURCE),
        "generator_sha256": {rel(Path(__file__)): sha(Path(__file__)), rel(Path(kit.__file__)): sha(Path(kit.__file__))},
        "blender_version": bpy.app.version_string, "render_engine": "Cycles CPU / 24 samples / 4 threads",
        "assets": assets, "third_party_inputs": [], "license": "project-original"}
    save_json(MANIFEST, data)
    register(data)
    validate()


if __name__ == "__main__":
    main()
