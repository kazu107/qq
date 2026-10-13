"""Author isolated Blender card scenes and a transparent charge pictogram."""
import hashlib
import importlib.util
import json
import math
import sys
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("ui_kit", ROOT / "tools/blender/build_ui_batch.py")
kit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(kit)
SOURCE = ROOT / "art_src/blender/cards/timekeeper_boss.blend"
MANIFEST = SOURCE.with_suffix(".manifest.json")
LOCAL = ROOT / "tools/.local/timekeeper-art"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def clock(x, z, radius, y=0, accent="gold"):
    kit.disc("Rim", x, z, radius, accent, y, .14)
    kit.disc("Face", x, z, radius*.86, "iron", y-.10, .04)
    for index in range(12):
        angle = math.tau*index/12
        kit.pipe("Tick", [(x+math.sin(angle)*radius*.66, z+math.cos(angle)*radius*.66),
                          (x+math.sin(angle)*radius*.77, z+math.cos(angle)*radius*.77)], .025, "white", y-.14)
    kit.pipe("Long_Hand", [(x, z), (x+radius*.17, z+radius*.56)], .045, "white", y-.19)
    kit.pipe("Short_Hand", [(x, z), (x-radius*.39, z-radius*.15)], .045, accent, y-.21)
    kit.sphere("Axle", x, z, .065, accent, y-.24)


def build(id):
    if id != "attack_charge":
        kit.box("Backdrop", 0, 0, 2.55, 2.55, "dim", .66, .08, .02)
    if id == "timekeeper_final_strike":
        for x in (-.94, -.47, 0, .47, .94):
            kit.box("Stone_Tile", x, -.79, .42, .39, "iron", .42, .08)
        clock(.25, .29, .88, .19)
        kit.shape("Falling_Pendulum_Blade", [(-.91,.90),(-.65,.96),(.05,-.53),(-.14,-.98),(-.43,-.61)], "steel", -.28, .16)
        kit.pipe("Cutting_Edge", [(-.64,.89),(.05,-.53),(-.14,-.98)], .035, "white", -.40)
        kit.pipe("Impact_Crack", [(-.13,-.96),(.33,-.82),(.56,-1.03),(.94,-.78)], .038, "amber", -.30)
    elif id == "timekeeper_amplify":
        clock(-.53, .25, .50, .1, "gold")
        clock(.53, .25, .50, .1, "cyan")
        kit.pipe("Link", [(-.30,.40),(0,.69),(.30,.40)], .08, "gold", -.22)
        for x in (-.29, .29):
            kit.shape("Amplified_Blade", [(x-.09,-.99),(x+.09,-.99),(x+.09,-.35),(x,-.13),(x-.09,-.35)], "white", -.26, .13)
            kit.box("Hilt", x, -.81, .35, .08, "gold", -.4)
        kit.pipe("Power_Arch", [(-.99,-.54),(-.83,-.2),(-.5,-.06),(0,.01),(.5,-.06),(.83,-.2),(.99,-.54)], .055, "cyan", -.32)
    elif id == "timekeeper_time_mark":
        kit.box("Scroll", 0, -.14, 1.43, 1.98, "steel", .20, .06)
        for z in (-1.05,.78): kit.box("Scroll_Roller", 0, z, 1.64, .13, "gold", -.05, .19)
        clock(0, .28, .62, -.08)
        kit.shape("Cracked_Seal", [(-.38,-.38),(.38,-.38),(.29,-.76),(0,-1.0),(-.29,-.76)], "red", -.35, .12)
        kit.pipe("Weak_Point", [(.07,-.42),(-.08,-.62),(.05,-.78),(-.05,-.94)], .05, "white", -.49)
    elif id == "attack_charge":
        for x in (-.37,.37):
            kit.shape("Charged_Blade", [(x-.10,-.57),(x+.10,-.57),(x+.10,.62),(x,.91),(x-.10,.62)], "white", -.15, .16)
            kit.box("Guard", x, -.42, .58, .10, "gold", -.3)
            kit.box("Grip", x, -.76, .13, .31, "cyan", -.12)
        kit.pipe("Charge_Link", [(-.94,-.19),(-.66,.06),(0,.20),(.66,.06),(.94,-.19)], .07, "gold", -.32)
    else:
        raise ValueError(id)


def main():
    if "--validate-only" in sys.argv:
        meta = json.loads(MANIFEST.read_text(encoding="utf-8"))
        assert sha(SOURCE) == meta["source_sha256"]
        bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
        for item in meta["assets"]:
            group = bpy.data.collections[item["source_collection"]]
            assert len(group.objects) == item["objects"]
            assert any(obj.type in ("MESH", "CURVE") for obj in group.objects)
            assert not any(obj.type == "FONT" for obj in group.objects)
            assert sha(ROOT/item["runtime_path"]) == item["export_sha256"]
        print("TIMEKEEPER_SOURCE_REOPEN_OK", len(meta["assets"]), flush=True)
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    SOURCE.parent.mkdir(parents=True, exist_ok=True)
    LOCAL.mkdir(parents=True, exist_ok=True)
    kit.materials()
    kit.render_rig()
    bpy.context.scene.cycles.samples = 16
    bpy.context.scene.render.resolution_x = bpy.context.scene.render.resolution_y = 1024
    ids = [item["id"] for item in json.loads((ROOT/"data/boss_cards.json").read_text(encoding="utf-8"))] + ["attack_charge"]
    groups, entries = [], []
    for id in ids:
        kit.CURRENT = bpy.data.collections.new("boss_"+id)
        bpy.context.scene.collection.children.link(kit.CURRENT)
        build(id)
        kit.CURRENT.asset_mark()
        groups.append(kit.CURRENT)
        category = "status" if id == "attack_charge" else "card"
        entries.append({"id": id, "visual_id": id, "category": category,
                        "runtime_path": f"assets/icons/{'status' if category == 'status' else 'cards'}/{id}.png",
                        "source_path": kit.rel(SOURCE), "source_collection": kit.CURRENT.name,
                        "size": 96 if category == "status" else 512, "source_render_size": [1024,1024], "objects": len(kit.CURRENT.objects)})
    for item, group in zip(entries, groups):
        for other in groups: other.hide_render = other != group
        bpy.context.scene.render.filepath = str(LOCAL/(item["id"]+".png"))
        bpy.ops.render.render(write_still=True)
        item["render_path"] = kit.rel(LOCAL/(item["id"]+".png"))
        item["render_sha256"] = sha(ROOT/item["render_path"])
        print("TIMEKEEPER_RENDER_OK", item["id"], flush=True)
    for group in groups: group.hide_render = group.hide_viewport = group != groups[0]
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE), compress=True)
    dependencies = {kit.rel(Path(__file__)): sha(Path(__file__)), kit.rel(Path(kit.__file__)): sha(Path(kit.__file__))}
    meta = {"batch_id": "timekeeper_boss_rework", "blender_version": bpy.app.version_string,
            "generator": kit.rel(Path(__file__)), "generator_sha256": dependencies,
            "source": kit.rel(SOURCE), "source_sha256": sha(SOURCE), "assets": entries}
    MANIFEST.write_text(json.dumps(meta, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")


if __name__ == "__main__": main()
