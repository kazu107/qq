"""Original recolored GLB busts and enemy-card scenes; isolated Blender only."""
from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
import build_starter_batch as actors
import build_art_vertical_slice as art
import recent_card_environments as environments
from build_reservation_cards import primitive

RECIPES = json.loads((ROOT / "data/infinite_enemy_variants.json").read_text(encoding="utf-8"))
PROFILES = json.loads((ROOT / "data/battle_visuals.json").read_text(encoding="utf-8"))
LOCAL = ROOT / "tools/.local/ascended-enemies/art"
BATCH = "blender_ascended_enemies_14"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return path.relative_to(ROOT).as_posix()


def save_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def role(name):
    clean = name.split(".")[0].lower()
    aliases = {"scout_olivecloth": "cloth", "scout_darkleather": "dark", "scout_tanleather": "trim",
        "scout_oliveedge": "edge", "scout_darksteel": "metal", "scout_amberlens": "glow",
        "scout_hood": "armor", "scout_redcloth": "cloth_shadow", "scout_rapieredge": "silver"}
    if clean in aliases:
        return aliases[clean]
    return next((key for key in ("cloth_shadow", "armor", "edge", "dark", "glow", "trim", "cloth", "metal", "silver") if clean.endswith("_" + key)), "")


def rgb(value):
    return tuple(int(value.lstrip("#")[i:i+2], 16) / 255 for i in (0, 2, 4))


def palette(entry):
    primary, secondary = rgb(entry["primary"]), rgb(entry["secondary"])
    return {"armor": primary, "edge": tuple(v + (1-v)*.25 for v in primary),
        "cloth": secondary, "cloth_shadow": tuple(v*.65 for v in secondary),
        "dark": tuple(v*.8 for v in secondary), "glow": rgb(entry["accent"]),
        "trim": rgb("f5c76c"), "metal": rgb("90a6b4"), "silver": rgb("dae5eb")}


def manifest(source, assets):
    data = {"format_version": 1, "batch_id": BATCH, "source": rel(source), "source_sha256": sha(source),
        "generator": rel(Path(__file__)), "generator_sha256": {rel(Path(__file__)): sha(Path(__file__)),
            "data/infinite_enemy_variants.json": sha(ROOT / "data/infinite_enemy_variants.json"),
            "data/battle_visuals.json": sha(ROOT / "data/battle_visuals.json")},
        "blender_version": bpy.app.version_string, "assets": assets, "third_party_inputs": [], "license": "project-original"}
    save_json(source.with_suffix(".manifest.json"), data)
    return data


def build_portraits():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    camera = actors.setup_render()
    scene = bpy.context.scene
    scene.render.resolution_x = scene.render.resolution_y = 512
    source = ROOT / "art_src/blender/characters/qq_ascended_enemies.blend"
    source.parent.mkdir(parents=True, exist_ok=True)
    collections, assets = [], []
    for entry in RECIPES:
        before = set(bpy.data.objects)
        before_actions = set(bpy.data.actions)
        model = ROOT / PROFILES[entry["base_id"]]["model_scene"].removeprefix("res://")
        bpy.ops.import_scene.gltf(filepath=str(model))
        objects = set(bpy.data.objects) - before
        collection = bpy.data.collections.new(entry["id"])
        scene.collection.children.link(collection)
        collection.asset_mark()
        pivot = bpy.data.objects.new(entry["id"] + "_Presentation", None)
        collection.objects.link(pivot)
        scale = PROFILES[entry["base_id"]]["body_scale"]
        colors, materials = palette(entry), {}
        for obj in objects:
            for parent in list(obj.users_collection): parent.objects.unlink(obj)
            collection.objects.link(obj)
            if obj.parent not in objects:
                obj.parent = pivot
            if obj.type != "MESH": continue
            for slot in obj.material_slots:
                old = slot.material
                key = role(old.name) if old else ""
                if key not in colors: continue
                if old not in materials:
                    new = old.copy()
                    new.name = entry["id"] + "_" + key
                    new["base_material"] = old.name
                    new.diffuse_color = (*colors[key], 1)
                    shader = new.node_tree.nodes.get("Principled BSDF")
                    shader.inputs["Base Color"].default_value = (*colors[key], 1)
                    if key in ("armor", "edge", "trim"):
                        shader.inputs["Metallic"].default_value = max(.55, shader.inputs["Metallic"].default_value)
                    if key == "glow":
                        shader.inputs["Emission Color"].default_value = (*colors[key], 1)
                        shader.inputs["Emission Strength"].default_value = max(1, shader.inputs["Emission Strength"].default_value)
                    materials[old] = new
                slot.material = materials[old]
        pivot.scale = (scale[0], scale[2], scale[1])
        actions = list(set(bpy.data.actions) - before_actions)
        idle = next((action for action in actions if "idle" in action.name.lower()), None)
        for obj in objects:
            if obj.type == "ARMATURE" and obj.animation_data:
                for track in list(obj.animation_data.nla_tracks): obj.animation_data.nla_tracks.remove(track)
                obj.animation_data.action = idle
        scene.frame_set(1)
        bpy.context.view_layer.update()
        for previous in collections: previous.hide_render = True
        collection.hide_render = False
        camera.location = (3.2, 7, 3.5 * scale[1])
        actors.base.look_at(camera, Vector((0, .02, 1.91 * scale[1])))
        camera.data.ortho_scale = 2.02 * scale[1]
        target = ROOT / f"assets/portraits/{entry['id']}.png"
        scene.render.filepath = str(target)
        bpy.ops.render.render(write_still=True)
        assets.append({"asset_id": "portrait_" + entry["id"], "visual_id": entry["id"], "category": "portrait",
            "runtime_path": rel(target), "size": 512, "source_collection": collection.name,
            "source_model": rel(model), "source_model_sha256": sha(model), "presentation": "same_model_recolored_bust",
            "export_sha256": sha(target), "palette": {k: list(v) for k, v in colors.items()}})
        collections.append(collection)
        print("ASCENDED_PORTRAIT_OK " + entry["id"], flush=True)
    for col in collections:
        col.hide_render = col.hide_viewport = col != collections[0]
    bpy.ops.wm.save_as_mainfile(filepath=str(source), compress=True)
    return manifest(source, assets)


def card_scene(col, id):
    m = art.MATERIALS
    gold, steel, dark, white, cyan = (m[key] for key in ("brass_edge", "steel", "gunmetal", "ceramic_light", "cyan"))
    def p(kind, pos, size, material=steel, rotation=(0, 0, 0)):
        return primitive(col, id + "_" + kind, kind, pos, size, material, rotation)
    def blade(x=0, z=.5, material=steel):
        art.add_profile(col, "Blade", [(-.16,0),(.16,0),(.12,1.2),(0,1.65),(-.12,1.2)], .12, material, location=(x,0,z), bevel=.03)
        p("box",(x,0,z-.12),(.12,.10,.32),dark)
        p("box",(x,0,z),(.42,.12,.07),gold)
    if id == "ascendant_edge":
        blade(-.1,.45); p("ring",(.45,.12,1.15),(.58,.58,.58),cyan,(math.pi/2,0,0))
    elif id == "ascendant_bulwark":
        art.add_profile(col,"Crest_Shield",[(-.8,.8),(.8,.8),(.7,0),(0,-.8),(-.7,0)],.22,white,location=(0,0,1.3),bevel=.06)
        p("box",(0,-.28,1.4),(.09,.06,.55),gold)
        for x in [-.5,.5]: p("ball",(x,-.23,1.7),(.12,.07,.12),cyan)
    elif id == "ascendant_brand":
        red = art.make_material("Crimson_Crystal",(.65,.035,.1,1),metallic=.25)
        blade(.55,.45,gold)
        p("ring",(-.3,-.03,1.1),(.58,.58,.58),red,(math.pi/2,0,0))
        p("cone",(-.3,-.2,1.25),(.20,.2,.43),red)
        for z in [.5,.8,1.1]: p("box",(-.3,-.26,z),(.36,.06,.045),gold)
    elif id == "ascendant_mend":
        jade = art.make_material("Reactor_Jade",(.08,.65,.32,1),metallic=.18)
        p("tube",(0,0,1.1),(.5,.5,.6),white)
        p("tube",(0,-.03,1.2),(.35,.48,.35),jade)
        p("box",(0,-.52,1.35),(.10,.05,.42),white); p("box",(0,-.52,1.35),(.42,.05,.10),white)
        for x in [-.65,.65]: p("ring",(x,0,1.3),(.3,.3,.3),gold,(0,math.pi/2,0))
    elif id == "ascendant_clock":
        p("ring",(-.22,0,1.3),(.8,.8,.8),gold,(math.pi/2,0,0))
        p("tube",(-.22,.05,1.3),(.68,.68,.1),dark,(math.pi/2,0,0))
        for i in range(12):
            a = i*math.tau/12
            p("box",(-.22+math.sin(a)*.62,-.14,1.3+math.cos(a)*.62),(.035,.03,.11),white,(0,a,0))
        p("box",(-.1,-.24,1.5),(.045,.03,.32),cyan,(0,-.5,0))
        for z in [.7,1.1,1.5,1.9]: p("cone",(.68,-.15,z),(.09,.06,.19),cyan,(0,-.5,0))
    elif id == "ascendant_echo":
        for x, y, material in [(-.38,.22,steel),(.32,-.1,cyan)]:
            art.add_profile(col,"Echo_Plate",[(-.45,-.5),(.45,-.5),(.45,.5),(-.45,.5)],.12,material,location=(x,y,1.3),bevel=.05)
            p("ring",(x,y-.16,1.3),(.3,.3,.3),gold,(math.pi/2,0,0))
    elif id == "ascendant_siege":
        p("box",(-.1,.22,.85),(.5,.45,.38),dark)
        p("tube",(0,-.1,1.2),(.35,.35,.7),gold,(math.pi/2,0,0))
        p("tube",(0,-.84,1.2),(.24,.24,.06),dark,(math.pi/2,0,0))
        for x in [-.62,.62]: p("box",(x,0,1.1),(.16,.55,.4),steel,(0,x*.6,0))
        p("cone",(.65,.05,.5),(.16,.16,.37),cyan)
    else:
        blade(0,.2,gold)
        p("ring",(0,.25,1.4),(.95,.95,.95),cyan,(math.pi/2,0,0))
        for x in [-.8,.8]: p("cone",(x,0,1.3),(.17,.12,.55),dark,(0,-x*.6,0))


def build_cards():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    art.clear_file(); art.build_materials(); art.setup_render_scene()
    scene = bpy.context.scene
    scene.cycles.samples = 24
    scene.render.threads_mode = "FIXED"; scene.render.threads = 4
    scene.render.resolution_x = scene.render.resolution_y = 512
    art.CAMERA.data.dof.use_dof = False
    art.CAMERA.data.ortho_scale = 3.7
    families = {"ascendant_edge":"courtyard", "ascendant_bulwark":"fortress", "ascendant_brand":"corrupted_lab", "ascendant_mend":"infirmary",
        "ascendant_clock":"time_vault", "ascendant_echo":"time_vault", "ascendant_siege":"workshop", "ascendant_verdict":"courtyard"}
    collections, assets = [], []
    for id, family in families.items():
        col = art.make_collection(id)
        card_scene(col, id)
        environments.FAMILIES[id] = family
        environments.add_environment(art, col, id)
        col.hide_render = True
        collections.append(col)
        assets.append({"asset_id":id, "category":"card", "runtime_path":f"assets/icons/cards/{id}.png", "size":512,
            "source_collection":col.name, "presentation":"enemy_card_action_illustration", "environment_family":family})
    for index, (col, asset) in enumerate(zip(collections, assets)):
        for other in collections: other.hide_render = other != col
        art.CAMERA.location = (2.2 if index % 2 == 0 else -2.1, -8, 3.3 + (index % 3)*.2)
        art.look_at(art.CAMERA, Vector((0,0,1.15)))
        scene.render.film_transparent = False
        scene.render.filepath = str(ROOT / asset["runtime_path"])
        bpy.ops.render.render(write_still=True)
        asset["export_sha256"] = sha(ROOT / asset["runtime_path"])
        print("ASCENDED_CARD_ART_OK " + asset["asset_id"], flush=True)
    source = ROOT / "art_src/blender/cards/ascended_enemy_cards.blend"
    for col in collections: col.hide_render = col.hide_viewport = col != collections[0]
    bpy.ops.wm.save_as_mainfile(filepath=str(source), compress=True)
    return manifest(source, assets)


def register(manifests):
    path = ROOT / "data/art_provenance.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    for meta in manifests:
        owned = {asset["asset_id"] for asset in meta["assets"]}
        data["assets"] = [asset for asset in data["assets"] if asset["asset_id"] not in owned]
        for asset in meta["assets"]:
            data["assets"].append({**asset, "source_path":meta["source"], "source_sha256":meta["source_sha256"],
                "generator":meta["generator"], "generator_sha256":meta["generator_sha256"],
                "manifest_path":str(Path(meta["source"]).with_suffix(".manifest.json")).replace("\\", "/"),
                "batch_id":BATCH, "replacement_status":"approved", "author":"QQ project", "license":"project-original", "third_party_inputs":[]})
    assert len({a["asset_id"] for a in data["assets"]}) == len(data["assets"])
    assert len({a["export_sha256"] for a in data["assets"]}) == len(data["assets"])
    if BATCH not in data["batch_ids"]: data["batch_ids"].append(BATCH)
    data["updated_at"] = "2026-10-28"
    save_json(path, data)
    path = ROOT / "data/art_coverage.json"
    coverage = json.loads(path.read_text(encoding="utf-8"))
    coverage.update(updated_at="2026-10-28", registered_assets=len(data["assets"]))
    coverage["coverage"]["Ascended enemy portraits"] = {"done":18, "total":18, "remaining":[]}
    coverage["coverage"]["Enemy-only cards"] = {"done":8, "total":8, "remaining":[]}
    save_json(path, coverage)


def main():
    LOCAL.mkdir(parents=True, exist_ok=True)
    if "--validate-only" in sys.argv:
        for file in (ROOT / "art_src/blender/characters/qq_ascended_enemies.manifest.json", ROOT / "art_src/blender/cards/ascended_enemy_cards.manifest.json"):
            meta = json.loads(file.read_text(encoding="utf-8"))
            assert sha(ROOT / meta["source"]) == meta["source_sha256"]
            for path, digest in meta["generator_sha256"].items(): assert sha(ROOT / path) == digest, path
            bpy.ops.wm.open_mainfile(filepath=str(ROOT / meta["source"]))
            for asset in meta["assets"]:
                assert bpy.data.collections.get(asset["source_collection"]) is not None
                assert sha(ROOT / asset["runtime_path"]) == asset["export_sha256"]
                if "source_model" in asset: assert sha(ROOT / asset["source_model"]) == asset["source_model_sha256"]
                image = bpy.data.images.load(str(ROOT / asset["runtime_path"]), check_existing=False)
                assert list(image.size) == [512, 512]
                bpy.data.images.remove(image)
        print("ASCENDED_ART_VALIDATION_OK 26 source-backed portraits and illustrations", flush=True)
        return
    manifests = []
    if "--cards-only" not in sys.argv: manifests.append(build_portraits())
    if "--portraits-only" not in sys.argv: manifests.append(build_cards())
    register(manifests)
    print("ASCENDED_ART_BUILD_OK", sum(len(m["assets"]) for m in manifests), flush=True)


if __name__ == "__main__": main()
