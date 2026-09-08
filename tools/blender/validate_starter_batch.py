"""Read-only cold-reload validation of the saved second-batch source."""

import json
import math
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_battle_vertical_slice as base


root = Path(__file__).resolve().parents[2]
path = root / "art_src/blender/characters/qq_starters.manifest.json"
manifest = json.loads(path.read_text(encoding="utf-8"))
assert Path(bpy.data.filepath).resolve() == (root / manifest["source"]).resolve()
assert not bpy.data.is_dirty
assert base.file_sha256(root / manifest["source"]) == manifest["source_sha256"]
assert base.file_sha256(root / manifest["library"]) == manifest["library_sha256"]
assert bpy.data.libraries and all(library.filepath.startswith("//") for library in bpy.data.libraries)
for entry in manifest["assets"]:
    collection = bpy.data.collections["STARTER_" + entry["id"]]
    meshes = [obj for obj in collection.objects if obj.type == "MESH"]
    rigs = [obj for obj in collection.objects if obj.type == "ARMATURE"]
    assert len(meshes) == len(rigs) == 1
    assert len(rigs[0].data.bones) == 18
    assert len(meshes[0].data.vertices) == entry["vertices"]
    assert meshes[0].parent == rigs[0]
    for part in entry["parts"]:
        link = bpy.data.objects["Source_" + part].instance_collection
        assert link is not None and link.library is not None
    for vertex in meshes[0].data.vertices:
        assert all(math.isfinite(value) for value in vertex.co)
    for kind in ("model", "portrait"):
        assert base.file_sha256(root / entry[kind]) == entry[kind + "_sha256"]
print("STARTER_BATCH_COLD_RELOAD_OK 7 rigs, linked libraries, source/output hashes; saved state clean")
