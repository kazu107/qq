"""Original mechanical reservation art; background factory startup only."""
from pathlib import Path
import sys
import json
import hashlib
import math
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
import build_art_vertical_slice as kit
import card_action_scenes
import recent_card_environments

LOCAL = ROOT / "tools/.local/reservations/art"
SOURCE = ROOT / "art_src/blender/cards/reservation_cards.blend"
catalog = [{"id": card["id"], "kind": card["effects"][0]["reservation"], "hostile": card["effects"][0]["target"] == "enemy"}
           for card in json.loads((ROOT / "data/cards.json").read_text(encoding="utf-8")) if card["id"].startswith("reserve_")]


def primitive(collection, name, shape, pos, scale, material, rotation=(0, 0, 0)):
    if shape == "ring":
        bpy.ops.mesh.primitive_torus_add(major_radius=1, minor_radius=.12, major_segments=36, minor_segments=8)
    elif shape == "ball":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12)
    elif shape == "cone":
        bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=1, radius2=0, depth=2)
    elif shape == "tube":
        bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=1, depth=2)
    else:
        bpy.ops.mesh.primitive_cube_add()
    obj = bpy.context.object
    obj.name = name; obj.location = pos; obj.scale = scale; obj.rotation_euler = rotation
    for old in list(obj.users_collection): old.objects.unlink(obj)
    collection.objects.link(obj); obj.data.materials.append(material)
    if shape not in ["ball", "ring"]:
        bevel = obj.modifiers.new("Machined edges", "BEVEL"); bevel.width = .045; bevel.segments = 3
        obj.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    return obj


def build(collection, kind, index, hostile):
    m = kit.MATERIALS
    metal = m["steel"]; dark = m["gunmetal"]; gold = m["brass_edge"]; accent = m["red"] if "red" in m and hostile else (gold if hostile else m["cyan"])
    def part(shape, x, y, z, a, b, c, mat=metal, rot=(0, 0, 0)):
        return primitive(collection, kind + shape, shape, (x,y,z), (a,b,c), mat, rot)
    facing = (math.pi / 2, 0, 0)
    if kind in ["focus", "weaken", "growth", "wear"]:
        kit.add_profile(collection, "Blade", [(-.20,0),(.20,0),(.14,1.6),(0,2),(-.14,1.6)], .16, metal, location=(0,0,.35), bevel=.035)
        part("box",0,0,.4,.65,.18,.09,gold); part("tube",0,0,.05,.12,.12,.3,dark)
        if kind == "focus":
            part("ring",0,-.3,1.4,.72,.72,.72,accent,facing)
            for s in [-1,1]: part("box",s*.8,-.35,1.4,.25,.06,.04,accent)
        elif kind == "weaken":
            for s in [-1,1]: part("box",s*.37,-.22,1.4,.35,.18,.1,dark, (0,s*.35,0))
            part("ring",0,-.2,1.4,.6,.6,.6,accent,facing)
        elif kind == "growth":
            for s in [-1,1]: part("cone",s*.45,-.1,1.5,.24,.2,.65,accent,(0,s*.4,0))
        else:
            for z in [.9,1.2,1.5]: part("box",.4,-.3,z,.55,.12,.06,gold,(0,.4,0))
    elif kind in ["shield", "shield_jam", "chain"]:
        kit.add_profile(collection, "Shield", [(-.8,1.1),(.8,1.1),(.7,0),(0,-.7),(-.7,0)], .22, metal, location=(0,0,1.2), bevel=.07)
        part("box",0,-.3,1.35,.1,.08,.55,accent)
        if kind == "shield":
            for x in [-.95,.95]: part("ring",x,.15,1.4,.45,.45,.45,m["cyan"],facing)
        elif kind == "shield_jam":
            for a in [-.65,.65]: part("box",0,-.4,1.4,.9,.1,.12,accent,(0,a,0))
        else:
            for i in range(5): part("ring",-.9+i*.44,-.4,.5+i*.34,.3,.22,.35,gold,(math.pi/2,0, (i%2)*math.pi/2))
    elif kind in ["reload", "recast_jam", "tempo", "time_mine"]:
        part("tube",0,0,1.3,.85,.23,.85,dark,facing)
        part("tube",0,-.25,1.3,.72,.06,.72,m["ceramic_light"],facing)
        part("ring",0,-.35,1.3,.8,.8,.8,gold,facing)
        part("box",.15,-.4,1.5,.3,.04,.055,accent,(0,-.7,0)); part("box",0,-.4,1.65,.05,.04,.35,accent)
        for i in range(12):
            a=i*math.tau/12; part("ball",math.sin(a)*.62,-.37,1.3+math.cos(a)*.62,.035,.03,.035,gold)
        if kind == "reload":
            for i in range(3): part("tube",-.6+i*.6,.1,.4,.16,.16,.4,metal)
        elif kind == "recast_jam":
            for i in range(4): part("ring",-.6+i*.4,-.45,.7+i*.36,.23,.2,.3,accent,facing)
        elif kind == "tempo":
            part("box",.8,-.3,.5,.85,.13,.07,accent,(0,-.6,0)); part("cone",1.25,-.3,.2,.18,.16,.28,accent,(0,1,0))
        else:
            for s in [-1,1]:
                part("cone",s*.9,.1,1.3,.22,.2,.6,accent,(0,s*math.pi/2,0))
                part("box",s*.6,0,.25,.25,.5,.1,dark)
    elif kind in ["siphon", "status", "heal_jam"]:
        for i in range(3 if kind == "status" else 1):
            x=(i-1)*.65 if kind=="status" else 0
            part("tube",x,0,1.25,.25,.25,.7,metal)
            part("tube",x,-.04,1.25,.19,.25,.45,accent)
            for z in [.55,1.95]: part("tube",x,0,z,.3,.3,.1,dark)
        if kind == "siphon":
            kit.add_curve(collection,"Hose",[(0,.1,1.7),(.8,0,2),(.9,0,.5),(.4,-.2,.3)],.1,gold)
            part("cone",.4,-.2,.3,.16,.14,.45,metal)
        if kind == "heal_jam":
            for a in [-.7,.7]: part("box",0,-.4,1.3,.9,.12,.12,accent,(0,a,0))
    elif kind in ["mirror", "heavy_commit"]:
        for i in range(3):
            part("box",(i-1)*.7, i*.16,1.1+i*.12,.32,.12,.9,metal if kind=="mirror" else dark,(0,(i-1)*.16,0))
            part("box",(i-1)*.7,-.16+i*.16,1.1+i*.12,.26,.03,.8,accent if kind=="heavy_commit" else m["ceramic_light"],(0,(i-1)*.16,0))
    elif kind == "recoil":
        for i in range(8): part("ring",0,0,.4+i*.18,.45,.45,.45,gold)
        part("cone",0,0,2.1,.4,.4,.6,metal)
        part("box",0,0,.25,.6,.45,.1,dark)
    elif kind == "swift_commit":
        for z in [.4,2]: part("tube",0,0,z,.5,.5,.08,gold)
        part("cone",0,0,1.5,.36,.36,.45,m["cyan"])
        part("cone",0,0,.9,.36,.36,.45,m["cyan"],(math.pi,0,0))
        for s in [-1,1]:
            for i in range(3): part("box",s*(.65+i*.22),0,1.4+i*.1,.5,.08,.1,metal,(0,s*.45,0))
    recent_card_environments.add_environment(kit, collection, "reserve_" + kind)


def main():
    kit.clear_file(); kit.build_materials(); kit.setup_render_scene()
    scene=bpy.context.scene; scene.render.threads_mode="FIXED"; scene.render.threads=4
    kit.CAMERA.data.dof.use_dof=False; kit.CAMERA.data.ortho_scale=3.8
    LOCAL.mkdir(parents=True,exist_ok=True); SOURCE.parent.mkdir(parents=True,exist_ok=True)
    collections=[]; assets=[]
    for index, row in enumerate(catalog):
        col=kit.make_collection(row["id"]); build(col,row["kind"],index,row["hostile"]); col.hide_render=True
        collections.append(col)
        assets.append({"asset_id":row["id"],"category":"card","runtime_path":"assets/icons/cards/"+row["id"]+".png","size":512})
    for hostile in [False,True]:
        name="reservation_hex" if hostile else "reservation_boost"
        col=kit.make_collection(name)
        mat=kit.MATERIALS["brass_edge"] if hostile else kit.MATERIALS["cyan"]
        for i in range(3): primitive(col,name,"box",((i-1)*.7,0,1.2),(.28,.15,.5),mat,(0,.35 if hostile else -.35,0))
        col.hide_render=True; collections.append(col)
        assets.append({"asset_id":name,"category":"status","runtime_path":"assets/icons/status/"+name+".png","size":96})
    collections[0].hide_render=False
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
    for index,(col,asset) in enumerate(zip(collections,assets)):
        if asset["category"] != "card" and "--cards-only" in sys.argv: continue
        for other in collections: other.hide_render=other!=col
        kit.CAMERA.location=(2.2+(index%3)*.5,-8,3.1+(index%2)*.7); kit.look_at(kit.CAMERA,Vector((0,0,1.2)))
        scene.render.film_transparent=asset["category"]=="status"
        scene.render.resolution_x=1024; scene.render.resolution_y=1024
        scene.render.filepath=str(LOCAL/(asset["asset_id"]+".png")); bpy.ops.render.render(write_still=True)
    manifest={"tool":"Blender "+bpy.app.version_string,"generator":"tools/blender/build_reservation_cards.py","source_path":SOURCE.relative_to(ROOT).as_posix(),"source_sha256":hashlib.sha256(SOURCE.read_bytes()).hexdigest(),"assets":assets}
    SOURCE.with_suffix(".manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    print("RESERVATION_ART_RENDER_OK",len(assets))


if __name__=="__main__": main()
