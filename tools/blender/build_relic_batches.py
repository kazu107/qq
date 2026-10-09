"""Render/validate the remaining 82 relics without touching shared registries.

Run with normal Python. It starts isolated background Blender processes in
10-16 item batches, writes a separately editable Blend per ID, and publishes
only 512px RGBA images. --preview renders 12 representative mechanisms.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "art_src/blender/relics"
LOCAL_DIR = ROOT / "tools/.local/blender_relic_batches"
MANIFEST = SOURCE_DIR / "relic_completion.manifest.json"
GENERATOR = Path(__file__).resolve()
KIT_GENERATOR = GENERATOR.with_name("relic_asset_kits.py")
HELPER = GENERATOR.with_name("build_art_vertical_slice.py")
DATA = ROOT / "data/relics.json"
PRESERVED = {"iron_plating", "auxiliary_core", "chrono_shard", "salvage_magnet"}
PREVIEW_IDS = [
    "tempered_edge", "reactive_barrier", "phase_capacitor", "chrono_metronome",
    "surge_gimbal", "bounty_drone", "blood_pump", "reserved_seat_tag",
    "compression_caliper", "four_symptom_seal", "solar_pinion", "loop_wear_wheel",
]
DEFAULT_BLENDER = Path("C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe")
RENDER_SIZE = 2048
OUTPUT_SIZE = 512


def sha(path):
    with Path(path).open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else hashlib.sha256(f.read()).hexdigest()


def relative(path):
    return Path(path).relative_to(ROOT).as_posix()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def load_items():
    items = json.loads(DATA.read_text(encoding="utf-8-sig"))
    if len(items) != 86 or len({x["id"] for x in items}) != 86:
        raise RuntimeError("Relic data must contain 86 unique IDs")
    return {x["id"]: x for x in items}


def dependency_hashes():
    return {relative(p): sha(p) for p in (GENERATOR, KIT_GENERATOR, HELPER)}


def data_hash(item):
    return hashlib.sha256(json.dumps(item, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()


def valid_existing(entry, item, dependencies):
    if not entry or entry.get("generator_sha256") != dependencies or entry.get("semantic_data_sha256") != data_hash(item):
        return False
    for path_key, hash_key in (("source_path", "source_sha256"), ("runtime_path", "export_sha256"),
                               ("source_render_path", "source_render_sha256")):
        path = ROOT / entry.get(path_key, "")
        if not path.is_file() or sha(path) != entry.get(hash_key):
            return False
    return entry.get("source_render_size") == 2048 and entry.get("size") == [512, 512]


def png_stats(path):
    from PIL import Image
    with Image.open(path) as opened:
        if opened.mode != "RGBA" or opened.size != (512, 512):
            raise RuntimeError(f"Bad runtime format: {path}: {opened.mode}, {opened.size}")
        im = opened.copy()
    alpha = im.getchannel("A")
    bbox = alpha.point(lambda v: 255 if v > 20 else 0).getbbox()
    if bbox is None:
        raise RuntimeError("Empty render: " + str(path))
    margin = min(bbox[0], bbox[1], 512-bbox[2], 512-bbox[3])
    coverage = sum(v > 20 for v in alpha.getdata()) / (512*512)
    opaque = sum(v >= 240 for v in alpha.getdata()) / (512*512)
    if margin < 22 or not .07 < coverage < .76 or opaque < .05:
        raise RuntimeError(f"Padding/transparency failure: {path.name}: margin={margin}, coverage={coverage}, opaque={opaque}")
    if any(alpha.getpixel(p) != 0 for p in ((0,0),(0,511),(511,0),(511,511))):
        raise RuntimeError("Nontransparent corner: " + path.name)
    small = im.resize((48,48), Image.Resampling.LANCZOS)
    small_coverage = sum(v > 40 for v in small.getchannel("A").getdata())/(48*48)
    if small_coverage < .05:
        raise RuntimeError("Unreadably small silhouette: " + path.name)
    return {"alpha_bbox": list(bbox), "minimum_padding_px": margin,
            "foreground_fraction": round(coverage,5), "opaque_fraction": round(opaque,5),
            "48px_foreground_fraction": round(small_coverage,5)}


def geometry_digest(collection):
    import bpy
    mesh_signatures=[]
    vertex_count=0
    polygon_count=0
    depsgraph=bpy.context.evaluated_depsgraph_get()
    for obj in collection.objects:
        if obj.type not in {"MESH", "CURVE"}:
            continue
        evaluated=obj.evaluated_get(depsgraph)
        mesh=evaluated.to_mesh()
        vertex_count += len(mesh.vertices)
        polygon_count += len(mesh.polygons)
        digest=hashlib.sha256()
        for vertex in mesh.vertices:
            p=obj.matrix_world @ vertex.co
            digest.update(struct.pack("<3f",*(round(v,5) for v in p)))
        for polygon in mesh.polygons:
            digest.update(struct.pack("<I",len(polygon.vertices)))
            for v in polygon.vertices:
                digest.update(struct.pack("<I",v))
        mesh_signatures.append(digest.hexdigest())
        evaluated.to_mesh_clear()
    return hashlib.sha256("|".join(sorted(mesh_signatures)).encode()).hexdigest(), vertex_count, polygon_count


def render_rig(collection):
    import bpy
    from mathutils import Vector
    import build_art_vertical_slice as h

    scene=bpy.context.scene
    scene.render.engine="BLENDER_EEVEE"
    scene.render.resolution_x=scene.render.resolution_y=RENDER_SIZE
    scene.render.resolution_percentage=100
    scene.render.film_transparent=True
    scene.render.image_settings.file_format="PNG"
    scene.render.image_settings.color_mode="RGBA"
    scene.render.image_settings.color_depth="8"
    scene.render.threads_mode="FIXED"
    scene.render.threads=4
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples=32
    scene.view_settings.view_transform="AgX"
    scene.view_settings.look="AgX - Medium High Contrast"
    world=bpy.data.worlds.new("Relic_Transparent_Studio")
    world.use_nodes=True
    world.node_tree.nodes["Background"].inputs["Color"].default_value=(.14,.17,.22,1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value=.45
    scene.world=world
    rig=h.make_collection("RELIC_RENDER_RIG")
    bpy.context.view_layer.update()
    points=[obj.matrix_world @ Vector(corner) for obj in collection.objects for corner in obj.bound_box]
    center=Vector(tuple((min(p[i] for p in points)+max(p[i] for p in points))*.5 for i in range(3)))
    camera_data=bpy.data.cameras.new("RelicIconCamera")
    camera_data.type="ORTHO"
    camera=bpy.data.objects.new("RelicIconCamera",camera_data)
    rig.objects.link(camera)
    camera.location=center+Vector((2.1,-9.0,2.4))
    h.look_at(camera,center)
    bpy.context.view_layer.update()
    inv=camera.matrix_world.inverted()
    projected=[inv @ p for p in points]
    width=max(p.x for p in projected)-min(p.x for p in projected)
    height=max(p.y for p in projected)-min(p.y for p in projected)
    # Fit the complete object in camera space; the reserved border is intentional.
    camera.data.ortho_scale=max(width,height)*1.26
    local_center=Vector(((max(p.x for p in projected)+min(p.x for p in projected))*.5,
                         (max(p.y for p in projected)+min(p.y for p in projected))*.5,0))
    camera.location += camera.rotation_euler.to_matrix() @ local_center
    scene.camera=camera
    for name,offset,energy,color,size in (
        ("Key",(-3.5,-4.5,5),950,(.90,.94,1),4.0),
        ("Fill",(4,-3,1.8),700,(.60,.79,1),3.5),
        ("GoldRim",(2,3,3.4),1150,(1,.72,.40),3.0),
        ("Top",(-1,.6,6),650,(1,.95,.82),3.0),
    ):
        h.add_area_light(rig,name,tuple(center+Vector(offset)),energy,color,size,tuple(center))
    return {"type":"orthographic", "ortho_scale":round(camera.data.ortho_scale,5),
            "transparent_background":True,"pedestal":False,"floor":False,
            "render_threads":4,"render_samples":32}


def blender_worker(ids):
    import bpy
    sys.path.insert(0,str(GENERATOR.parent))
    import build_art_vertical_slice as h
    import relic_asset_kits as kits
    items=load_items()
    expected=set(items)-PRESERVED
    if expected != set(kits.KIT_BY_ID):
        raise RuntimeError(f"Recipe coverage mismatch: {expected ^ set(kits.KIT_BY_ID)}")
    dependencies=dependency_hashes()
    for asset_id in ids:
        if asset_id not in expected:
            raise RuntimeError("Attempt to overwrite preserved or unknown relic: " + asset_id)
        started=time.monotonic()
        h.clear_file()
        kits.setup_materials()
        assembly=kits.build(asset_id)
        item=items[asset_id]
        scene=bpy.context.scene
        scene.name="Relic_"+asset_id
        scene["asset_name"]=item["name"]
        scene["actual_gameplay_description"]=item["description"]
        scene["actual_gameplay_effects"]=json.dumps(item.get("effects",[]),sort_keys=True)
        rig=render_rig(assembly.collection)
        bpy.context.view_layer.update()
        geometry_hash,vertices,polygons=geometry_digest(assembly.collection)
        source=SOURCE_DIR/(asset_id+".blend")
        render=LOCAL_DIR/"renders"/(asset_id+".png")
        render.parent.mkdir(parents=True,exist_ok=True)
        SOURCE_DIR.mkdir(parents=True,exist_ok=True)
        scene.render.filepath=str(render)
        bpy.context.preferences.filepaths.save_version=0
        bpy.ops.wm.save_as_mainfile(filepath=str(source),compress=True)
        bpy.ops.render.render(write_still=True)
        metadata={
            "id":asset_id,"category":"relic","runtime_path":f"assets/icons/relics/{asset_id}.png",
            "source_path":relative(source),"source_sha256":sha(source),
            "source_render_path":relative(render),"source_render_sha256":sha(render),
            "presentation":"transparent_object_no_pedestal","size":[512,512],"source_render_size":2048,
            "generator_sha256":dependencies,"semantic_data_sha256":data_hash(item),
            "blender_version":bpy.app.version_string,"render_engine":scene.render.engine,
            "kit":kits.KIT_BY_ID[asset_id],"kit_name":kits.KIT_NAMES[kits.KIT_BY_ID[asset_id]],
            "semantic_mapping":{"name":item["name"],"actual_description":item["description"],
                                "actual_effects":item.get("effects",[]),"reused_components":sorted(assembly.parts),
                                "unique_assembly_recipe":asset_id},
            "geometry_sha256":geometry_hash,"mesh_vertices":vertices,"mesh_polygons":polygons,
            "object_count":len(assembly.collection.objects),"camera":rig,
            "build_seconds":round(time.monotonic()-started,2),
        }
        write_json(LOCAL_DIR/"metadata"/(asset_id+".json"),metadata)
        print("RELIC_RENDERED",asset_id,metadata["build_seconds"],flush=True)


def sheets(entries,label):
    from PIL import Image,ImageDraw,ImageFont
    qa=SOURCE_DIR/"qa"
    qa.mkdir(parents=True,exist_ok=True)
    fonts=Path("C:/Windows/Fonts")
    font=ImageFont.truetype(str(fonts/"segoeui.ttf"),15)
    small_font=ImageFont.truetype(str(fonts/"segoeui.ttf"),12)
    def draw_sheet(size,cols,name):
        tile_w=240 if size==192 else 194
        tile_h=260 if size==192 else 112
        out=Image.new("RGB",(cols*tile_w,math.ceil(len(entries)/cols)*tile_h),(22,28,35))
        d=ImageDraw.Draw(out)
        for i,entry in enumerate(entries):
            x=(i%cols)*tile_w; y=(i//cols)*tile_h
            with Image.open(ROOT/entry["runtime_path"]) as im:
                icon=im.resize((size,size),Image.Resampling.LANCZOS)
                out.paste(icon,(x+(tile_w-size)//2,y+8),icon)
                if size==48:
                    # Compare real icons over both dark and pale UI surfaces.
                    patch=Image.new("RGBA",(48,48),(210,216,216,255))
                    patch.alpha_composite(icon)
                    out.paste(patch.convert("RGB"),(x+120,y+8))
            d.text((x+8,y+size+18),entry["id"],fill=(234,221,180),font=small_font)
            d.text((x+8,y+size+38),entry["kit"]+" | "+str(entry["object_count"])+" editable parts",fill=(139,173,194),font=small_font)
        path=qa/name
        out.save(path)
        return relative(path)
    return [draw_sheet(192,4,label+"_192px.png"),draw_sheet(48,4,label+"_48px.png")]


def validate(entries,full=False):
    items=load_items()
    dependencies=dependency_hashes()
    expected=set(items)-PRESERVED
    ids={e["id"] for e in entries}
    if len(ids)!=len(entries) or not ids <= expected or (full and ids!=expected):
        raise RuntimeError("Invalid manifest ID coverage")
    geometry=set(); image_hashes=set()
    for entry in entries:
        if not valid_existing(entry,items[entry["id"]],dependencies):
            raise RuntimeError("Stale/missing source, generator or output hash: " + entry["id"])
        if entry["source_render_size"]!=2048 or entry["category"]!="relic":
            raise RuntimeError("Incorrect render specification")
        if entry["geometry_sha256"] in geometry or entry["export_sha256"] in image_hashes:
            raise RuntimeError("Duplicate geometry or render: " + entry["id"])
        if (ROOT/entry["source_path"]).stat().st_size >= 100_000_000:
            raise RuntimeError("Blend exceeds GitHub file limit: " + entry["id"])
        stats=png_stats(ROOT/entry["runtime_path"])
        if stats!=entry["validation"]:
            raise RuntimeError("Validation metadata changed: " + entry["id"])
        geometry.add(entry["geometry_sha256"]); image_hashes.add(entry["export_sha256"])
    return {"count":len(entries),"full_coverage":full,"unique_geometry":len(geometry),
            "unique_exports":len(image_hashes),"render_size":2048,"runtime_size":512,
            "all_rgba":True,"all_transparent_padded":True,"all_hashes_valid":True,
            "all_sources_below_100mb":True}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blender",type=Path,default=DEFAULT_BLENDER)
    parser.add_argument("--preview",action="store_true")
    parser.add_argument("--ids",nargs="+")
    parser.add_argument("--batch-size",type=int,default=12)
    parser.add_argument("--validate-only",action="store_true")
    args=parser.parse_args()
    if not 10<=args.batch_size<=16:
        parser.error("batch size must be 10-16")
    items=load_items()
    dependencies=dependency_hashes()
    old=json.loads(MANIFEST.read_text(encoding="utf-8")) if MANIFEST.exists() else {}
    existing={e["id"]:e for e in old.get("assets",[])}
    preserved_hashes={asset_id:sha(ROOT/f"assets/icons/relics/{asset_id}.png") for asset_id in sorted(PRESERVED)}
    baseline=old.get("preserved_runtime_sha256",preserved_hashes)
    if preserved_hashes!=baseline:
        raise RuntimeError("A preserved first-batch relic changed")
    if args.validate_only:
        result=validate(list(existing.values()),full=True)
        print("RELIC_COMPLETION_VALIDATED",json.dumps(result),flush=True)
        return
    wanted=args.ids or (PREVIEW_IDS if args.preview else [x for x in items if x not in PRESERVED])
    if not set(wanted)<=(set(items)-PRESERVED):
        parser.error("Unknown/preserved relic requested")
    pending=[asset_id for asset_id in wanted if not valid_existing(existing.get(asset_id),items[asset_id],dependencies)]
    print("RELIC_BUILD_PLAN",json.dumps({"requested":len(wanted),"pending":len(pending),"batch_size":args.batch_size,"threads":4}),flush=True)
    from PIL import Image
    for start in range(0,len(pending),args.batch_size):
        batch=pending[start:start+args.batch_size]
        LOCAL_DIR.mkdir(parents=True,exist_ok=True)
        log=LOCAL_DIR/f"batch_{start//args.batch_size+1:02d}_{batch[0]}.log"
        cmd=[str(args.blender),"--background","--factory-startup","--threads","4",
             "--python-exit-code","1","--python",str(GENERATOR),"--","--blender-worker",*batch]
        started=time.monotonic()
        with log.open("w",encoding="utf-8") as handle:
            proc=subprocess.run(cmd,stdout=handle,stderr=subprocess.STDOUT,cwd=ROOT)
        if proc.returncode!=0:
            print(log.read_text(encoding="utf-8",errors="replace")[-8000:])
            raise RuntimeError("Blender batch failed: " + relative(log))
        completed=[]
        for asset_id in batch:
            entry=json.loads((LOCAL_DIR/"metadata"/(asset_id+".json")).read_text(encoding="utf-8"))
            target=ROOT/entry["runtime_path"]
            with Image.open(ROOT/entry["source_render_path"]) as raw:
                if raw.mode!="RGBA" or raw.size!=(2048,2048):
                    raise RuntimeError("Source render is not 2048 RGBA")
                raw.resize((512,512),Image.Resampling.LANCZOS).save(target,optimize=True)
            entry["export_sha256"]=sha(target)
            entry["validation"]=png_stats(target)
            existing[asset_id]=entry
            write_json(SOURCE_DIR/(asset_id+".manifest.json"),{
                "batch_id":"relic_completion_r01_r11","generator":relative(GENERATOR),
                "source":entry["source_path"],"source_sha256":entry["source_sha256"],
                "blender_version":entry["blender_version"],"assets":[entry],
            })
            completed.append(entry)
        ordered=[existing[x] for x in items if x in existing]
        all_valid=all(valid_existing(e,items[e["id"]],dependencies) for e in ordered)
        write_json(MANIFEST,{
            "format_version":1,"batch_id":"relic_completion_r01_r11","generator":relative(GENERATOR),
            "blender_version":completed[-1]["blender_version"],"generator_sha256":dependencies,
            "source":"art_src/blender/relics","source_per_asset":True,
            "expected_new_count":82,"completed_count":len(ordered),
            "preserved_runtime_sha256":baseline,"assets":ordered,
            "validation":validate(ordered,full=len(ordered)==82) if all_valid else {"stale_entries_require_rebuild":True},
            "qa_sheets":sheets(completed,f"batch_{start//args.batch_size+1:02d}_{batch[0]}"),
        })
        print("RELIC_BATCH_COMPLETE",len(completed),"total",len(ordered),"seconds",round(time.monotonic()-started,1),"log",relative(log),flush=True)
    ordered=[existing[x] for x in items if x in existing]
    if args.preview:
        preview=[existing[x] for x in wanted]
        print("RELIC_PREVIEW_SHEETS",json.dumps(sheets(preview,"preview_12_mechanisms")),flush=True)
    elif set(existing)==set(items)-PRESERVED:
        paths=sheets(ordered,"all_82_relics")
        final=json.loads(MANIFEST.read_text(encoding="utf-8"))
        final["qa_sheets"]=paths
        final["validation"]=validate(ordered,full=True)
        write_json(MANIFEST,final)
        write_json(SOURCE_DIR/"qa/validation.json",final["validation"])
        print("RELIC_COMPLETION_VALIDATED",json.dumps(final["validation"]),flush=True)
    final_preserved={asset_id:sha(ROOT/f"assets/icons/relics/{asset_id}.png") for asset_id in sorted(PRESERVED)}
    if final_preserved!=baseline:
        raise RuntimeError("First-batch artwork was not preserved")


if __name__=="__main__":
    if "--blender-worker" in sys.argv:
        blender_worker(sys.argv[sys.argv.index("--blender-worker")+1:])
    else:
        main()
