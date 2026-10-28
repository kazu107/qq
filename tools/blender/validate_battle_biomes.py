"""Cold-open editable sources and verify the manifest without changing files."""
import bpy
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent))
import build_environment_batch as kit

ROOT = Path(__file__).resolve().parents[2]
manifest = json.loads((ROOT / "art_src/blender/environment/biomes/manifest.json").read_text(encoding="utf-8"))
for item in manifest["fields"]:
    path = ROOT / item["source"]
    assert hashlib.sha256(path.read_bytes()).hexdigest() == item["source_sha256"]
    bpy.ops.wm.open_mainfile(filepath=str(path))
    assert not bpy.data.is_dirty
    source_meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    assert source_meshes and all(o.get("qq_editable_part") for o in source_meshes)
    kit.COUNTS = item["runtime"]["detail_counts"]
    actual = kit.inspect_glb(ROOT / "assets/models/environment/biomes" / (item["id"] + ".glb"))
    for metric in ("triangles", "surfaces", "bytes"):
        assert actual[metric] == item["runtime"][metric]
    assert actual["triangles"] < 150000 and actual["surfaces"] <= 80
for asset in manifest["assets"]:
    path = ROOT / asset["runtime_path"]
    assert hashlib.sha256(path.read_bytes()).hexdigest() == asset["export_sha256"]
    assert (ROOT / asset["source_path"]).exists()
print("BATTLE_BIOMES_COLD_SOURCE_OK", len(manifest["fields"]), "sources", len(manifest["assets"]), "assets", flush=True)
