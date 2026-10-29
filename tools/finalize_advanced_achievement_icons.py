"""Finalize this batch only, retaining all existing Blender icons and sources."""
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from finalize_achievement_icons import finalized, validate_png

ROOT=Path(__file__).resolve().parents[1]
PATH=ROOT/"art_src/blender/achievements/qq_advanced_achievements.manifest.json"


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def save(path,data): path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")


def main():
    meta=json.loads(PATH.read_text(encoding="utf-8"))
    assert sha(ROOT/meta["source"])==meta["source_sha256"]
    names=json.loads((ROOT/"data/localization/ja.json").read_text(encoding="utf-8"))
    expected={x["id"] for x in json.loads((ROOT/"data/achievements.json").read_text(encoding="utf-8")) if x.get("tracking_version")==1}
    assert expected=={x["visual_id"] for x in meta["assets"]}
    sheet=Image.new("RGB",(1440,660),"#101b25");draw=ImageDraw.Draw(sheet)
    font=ImageFont.truetype(str(ROOT/"tools/.local/NotoSansJP-full.ttf"),17)
    for index,entry in enumerate(meta["assets"]):
        source=ROOT/entry["render_path"];target=ROOT/entry["runtime_path"]
        image=finalized(source);image.save(target)
        entry["export_sha256"]=sha(target)
        entry["visible_pixels_at_48px"]=validate_png(target)
        x,y=index%6*240,index//6*220
        sheet.paste(image,(x+56,y+12),image)
        draw.text((x+12,y+155),names["achievement."+entry["visual_id"]+".name"],font=font,fill="#eff8ff")
    meta["dependencies"]={p:sha(ROOT/p) for p in ["tools/blender/build_achievement_icons.py","tools/blender/build_ui_batch.py"]}
    save(PATH,meta)
    sheet.save(ROOT/"art_src/blender/previews/advanced_achievement_icons.png")
    path=ROOT/"data/art_provenance.json";data=json.loads(path.read_text(encoding="utf-8"))
    owned={x["asset_id"] for x in meta["assets"]}
    data["assets"]=[x for x in data["assets"] if x["asset_id"] not in owned]
    for asset in meta["assets"]:
        entry={k:v for k,v in asset.items() if k!="render_path"}
        entry.update(generator=meta["generator"],source_sha256=meta["source_sha256"],batch_id=meta["batch_id"],replacement_status="approved",third_party_inputs=[],license="project-original",author="QQ project",tool="Blender "+meta["blender_version"])
        data["assets"].append(entry)
    data["updated_at"]="2026-10-30"
    if meta["batch_id"] not in data.setdefault("batch_ids",[]):data["batch_ids"].append(meta["batch_id"])
    save(path,data)
    path=ROOT/"data/art_coverage.json";coverage=json.loads(path.read_text(encoding="utf-8"))
    coverage["updated_at"]="2026-10-30";coverage["registered_assets"]=len(data["assets"])
    count=sum(e["category"]=="achievement" for e in data["assets"])
    coverage["coverage"]["Achievements"]={"done":count,"total":count,"remaining":[]}
    save(path,coverage)
    # Compatibility-only changes to legacy batch selection do not alter its art.
    legacy_path=ROOT/"art_src/blender/achievements/qq_achievements.manifest.json"
    legacy=json.loads(legacy_path.read_text(encoding="utf-8"))
    assert sha(ROOT/legacy["source"])==legacy["source_sha256"]
    for asset in legacy["assets"]:assert sha(ROOT/asset["runtime_path"])==asset["export_sha256"]
    for path in legacy["generator_sha256"]:legacy["generator_sha256"][path]=sha(ROOT/path)
    legacy["finalizer_sha256"]=sha(ROOT/"tools/finalize_achievement_icons.py")
    save(legacy_path,legacy)
    print("ADVANCED_ACHIEVEMENT_ART_OK",len(meta["assets"]),"new;",count,"total")

if __name__=="__main__":main()
