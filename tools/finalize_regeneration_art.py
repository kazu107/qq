"""Register only the new regeneration assets; preserve previous asset owners."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
mp="art_src/blender/cards/regeneration_cards.manifest.json"
m=json.loads((ROOT/mp).read_text(encoding="utf-8"))
def sha(path): return hashlib.sha256((ROOT/path).read_bytes()).hexdigest()
assert sha(m["source_path"])==m["source_sha256"]
deps={path:sha(path) for path in [m["generator"],"tools/blender/build_reservation_cards.py","tools/blender/build_art_vertical_slice.py","tools/blender/card_action_scenes.py"]}
pp=ROOT/"data/art_provenance.json"; p=json.loads(pp.read_text(encoding="utf-8"))
sheet=Image.new("RGB",(4*220,3*242),"#10261e"); draw=ImageDraw.Draw(sheet)
for i,a in enumerate(m["assets"]):
    image=Image.open(ROOT/"tools/.local/regeneration/art"/(a["asset_id"]+".png")).convert("RGBA")
    image.resize((a["size"],a["size"]),Image.Resampling.LANCZOS).save(ROOT/a["runtime_path"])
    entry=dict(a,source_path=m["source_path"],generator=m["generator"],export_sha256=sha(a["runtime_path"]),source_sha256=m["source_sha256"],generator_sha256=deps,manifest_path=mp,tool=m["tool"],replacement_status="implemented",batch_id="blender_regeneration_11",author="QQ project",license="project-original",third_party_inputs=[])
    old=next((x for x in p["assets"] if x["runtime_path"]==a["runtime_path"]),None)
    if old:
        assert old["generator"]==m["generator"]; old.clear(); old.update(entry)
    else: p["assets"].append(entry)
    thumb=image.resize((220,220),Image.Resampling.LANCZOS); x=i%4*220; y=i//4*242
    sheet.paste(thumb,(x,y),thumb); draw.text((x+4,y+222),a["asset_id"],fill="white")
if "blender_regeneration_11" not in p["batch_ids"]: p["batch_ids"].append("blender_regeneration_11")
p["updated_at"]="2026-10-26"; pp.write_text(json.dumps(p,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
cp=ROOT/"data/art_coverage.json"; c=json.loads(cp.read_text(encoding="utf-8")); c["updated_at"]="2026-10-26"; c["registered_assets"]=len(p["assets"])
c["coverage"]["Cards"]["done"]=c["coverage"]["Cards"]["total"]=len(json.loads((ROOT/"data/cards.json").read_text(encoding="utf-8")))
c["coverage"]["Status"]["done"]=c["coverage"]["Status"]["total"]=len([a for a in p["assets"] if a["category"]=="status"])
cp.write_text(json.dumps(c,ensure_ascii=False,indent=2)+"\n",encoding="utf-8"); sheet.save(ROOT/"tools/.local/regeneration/contact-sheet.png")
print("REGEN_ART_REGISTERED",len(m["assets"]))
