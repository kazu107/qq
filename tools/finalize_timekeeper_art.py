"""Downsample and validate rendered Timekeeper assets, preserving source hashes."""
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "art_src/blender/cards/timekeeper_boss.manifest.json"
meta = json.loads(path.read_text(encoding="utf-8"))
for item in meta["assets"]:
    with Image.open(ROOT/item["render_path"]) as source:
        assert source.size == (1024,1024)
        output = source.convert("RGBA").resize((item["size"],item["size"]), Image.Resampling.LANCZOS)
        target = ROOT/item["runtime_path"]
        output.save(target, optimize=True)
        assert output.getchannel("A").getbbox() is not None
        if item["category"] == "status": assert output.getpixel((0,0))[3] == 0
        item["export_sha256"] = hashlib.sha256(target.read_bytes()).hexdigest()
path.write_text(json.dumps(meta, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
print("TIMEKEEPER_ART_FINALIZED_OK", len(meta["assets"]))
