"""Register only the new conversion artwork and create a review sheet."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1];mp="art_src/blender/cards/damage_conversion.manifest.json"
m=json.loads((ROOT/mp).read_text(encoding="utf-8"))
def sha(path):return hashlib.sha256((ROOT/path).read_bytes()).hexdigest()
assert sha(m["source_path"])==m["source_sha256"]
deps={p:sha(p) for p in [m["generator"],"tools/blender/build_reservation_cards.py","tools/blender/build_art_vertical_slice.py","tools/blender/card_action_scenes.py"]}
path=ROOT/"data/art_provenance.json";data=json.loads(path.read_text(encoding="utf-8"));sheet=Image.new("RGB",(880,242),"#10232b");draw=ImageDraw.Draw(sheet)
for i,a in enumerate(m["assets"]):
    image=Image.open(ROOT/"tools/.local/conversion/art"/(a["asset_id"]+".png")).convert("RGBA")
    image.resize((a["size"],a["size"]),Image.Resampling.LANCZOS).save(ROOT/a["runtime_path"])
    entry=dict(a,source_path=m["source_path"],generator=m["generator"],export_sha256=sha(a["runtime_path"]),source_sha256=m["source_sha256"],generator_sha256=deps,manifest_path=mp,tool=m["tool"],replacement_status="implemented",batch_id="blender_conversion_12",author="QQ project",license="project-original",third_party_inputs=[])
    old=next((x for x in data["assets"] if x["runtime_path"]==a["runtime_path"]),None)
    if old:
        assert old["generator"]==m["generator"];old.clear();old.update(entry)
    else:data["assets"].append(entry)
    thumb=image.resize((220,220),Image.Resampling.LANCZOS);sheet.paste(thumb,(i*220,0),thumb);draw.text((i*220+4,222),a["asset_id"],fill="white")
if "blender_conversion_12" not in data["batch_ids"]:data["batch_ids"].append("blender_conversion_12")
data["updated_at"]="2026-10-26";path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
path=ROOT/"data/art_coverage.json";c=json.loads(path.read_text(encoding="utf-8"));c["updated_at"]="2026-10-26";c["registered_assets"]=len(data["assets"])
c["coverage"]["Cards"]["done"]=c["coverage"]["Cards"]["total"]=len(json.loads((ROOT/"data/cards.json").read_text(encoding="utf-8")))
c["coverage"]["Status"]["done"]=c["coverage"]["Status"]["total"]=len([a for a in data["assets"] if a["category"]=="status"])
path.write_text(json.dumps(c,ensure_ascii=False,indent=2)+"\n",encoding="utf-8");sheet.save(ROOT/"tools/.local/conversion/contact-sheet.png")
print("CONVERSION_ART_REGISTERED",len(m["assets"]))
