"""Cold-open the editable icon source and verify owned assets without writing."""
import bpy
import hashlib
import json
from pathlib import Path

root=Path(__file__).resolve().parents[2]
manifest=json.loads((root/"art_src/blender/achievements/qq_advanced_achievements.manifest.json").read_text(encoding="utf-8"))
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
assert sha(root/manifest["source"])==manifest["source_sha256"]
assert sha(root/manifest["generator"])==manifest["generator_sha256"]
for path,digest in manifest["dependencies"].items():assert sha(root/path)==digest
bpy.ops.wm.open_mainfile(filepath=str(root/manifest["source"]))
assert not bpy.data.is_dirty
for asset in manifest["assets"]:
    collection=bpy.data.collections[asset["source_collection"]]
    assert collection["achievement_id"]==asset["visual_id"]
    assert len(collection.objects)==asset["objects"]
    assert all(obj.type!="FONT" for obj in collection.objects)
    assert any(obj.type in ("MESH","CURVE") for obj in collection.objects)
    assert sha(root/asset["runtime_path"])==asset["export_sha256"]
print("ADVANCED_ACHIEVEMENT_SOURCE_OK",len(manifest["assets"]),"editable sculptures and PNG hashes",flush=True)
