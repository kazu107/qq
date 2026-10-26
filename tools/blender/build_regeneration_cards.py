"""Original regeneration illustrations. Run in a separate factory-startup Blender."""
from pathlib import Path
import sys
import math
import hashlib
import json
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
import build_art_vertical_slice as kit
import card_action_scenes
import recent_card_environments
from build_reservation_cards import primitive

LOCAL = ROOT / "tools/.local/regeneration/art"
SOURCE = ROOT / "art_src/blender/cards/regeneration_cards.blend"
IDS = ["regen_patch", "regen_salve", "regen_barrier", "regen_emergency", "regen_bloodwrap", "regen_burst", "regen_spring", "regen_tank"]


def make_material(name, color, metallic=.35):
    material = bpy.data.materials.new(name); material.diffuse_color = (*color, 1); material.use_nodes = True
    node = material.node_tree.nodes.get("Principled BSDF")
    node.inputs["Base Color"].default_value = (*color, 1); node.inputs["Metallic"].default_value = metallic; node.inputs["Roughness"].default_value = .28
    return material


def build(col, id, green, fluid, red):
    m = kit.MATERIALS; metal = m["steel"]; dark = m["gunmetal"]; white = m["ceramic_light"]
    facing = (math.pi/2,0,0)
    def p(shape,x,y,z,a,b,c,mat=metal,rot=(0,0,0)):
        return primitive(col,id+shape,shape,(x,y,z),(a,b,c),mat,rot)
    def cross(x,y,z,scale=1):
        p("box",x,y,z,.12*scale,.04,.4*scale,green); p("box",x,y,z,.4*scale,.04,.12*scale,green)
    if id == "regen_patch":
        p("box",0,0,1.3,.85,.18,.55,white,(0,-.25,0)); cross(0,-.23,1.3)
        for s in [-1,1]:
            for i in range(3): p("ball",s*(.5+i*.12),-.22,1.3,.025,.025,.025,dark)
        p("ring",.5,-.35,1.7,.6,.6,.6,green,facing)
    elif id == "regen_salve":
        p("tube",0,0,.9,.55,.55,.5,white); p("tube",0,0,1.45,.62,.62,.08,dark)
        p("ball",0,0,1.65,.45,.45,.25,fluid); cross(0,-.57,.9,.7)
        p("box",.65,-.1,1.9,.45,.08,.08,metal,(0,-.5,0)); p("ball",1,-.1,2.05,.14,.1,.14,fluid)
    elif id == "regen_barrier":
        kit.add_profile(col,"Shield",[(-.8,1),(.8,1),(.7,0),(0,-.65),(-.7,0)],.2,white,location=(0,0,1.2),bevel=.08)
        cross(0,-.25,1.35)
        for s in [-1,1]:
            p("cone",s*.75,-.1,.8,.22,.12,.6,green,(0,s*.45,0))
            p("tube",s*.7,0,1.7,.14,.14,.35,dark)
    elif id == "regen_emergency":
        p("tube",0,0,1.3,.3,.3,.65,white,(0,.2,0)); p("tube",0,-.05,1.3,.2,.3,.4,fluid,(0,.2,0))
        p("cone",-.18,0,.4,.07,.07,.3,metal); p("box",.2,0,2.1,.55,.18,.08,dark)
        for s in [-1,1]: p("box",s*.6,-.2,1.4,.25,.1,.12,red,(0,s*.6,0))
    elif id == "regen_bloodwrap":
        p("tube",-.4,0,1.2,.35,.35,.65,dark); p("tube",-.4,-.05,1.2,.28,.35,.5,red)
        kit.add_profile(col,"Blade",[(-.12,0),(.12,0),(.1,1.1),(0,1.45),(-.1,1.1)],.12,metal,location=(.6,0,.75),bevel=.03)
        for z in [.7,.9,1.1]: p("box",.55,-.1,z,.3,.15,.06,white,(0,.3,0))
        kit.add_curve(col,"BloodHose",[(-.4,0,1.8),(0,-.4,2),(.6,-.25,1.4)],.07,red)
    elif id == "regen_burst":
        for i in range(3):
            angle=i*math.tau/3; x=math.sin(angle)*.65; z=1.3+math.cos(angle)*.65
            p("cone",x,0,z,.3,.28,.6,fluid,(0,-angle,0))
        p("ring",0,-.2,1.3,.9,.9,.9,green,facing); cross(0,-.35,1.3,.6)
    elif id == "regen_spring":
        p("tube",0,0,.45,.8,.8,.18,white); p("ring",0,0,.64,.7,.7,.7,green)
        p("tube",0,0,1.1,.12,.12,.5,metal)
        for i in range(5):
            angle=i*math.tau/5; x=math.sin(angle)*.55; y=math.cos(angle)*.55
            kit.add_curve(col,"Water",[(0,0,1.65),(x*.5,y*.5,2),(x,y,.75)],.04,fluid)
            p("ball",x,y,.8,.12,.12,.12,fluid)
    else:
        p("tube",0,0,1.2,.65,.65,.8,fluid)
        for z in [.35,2.05]: p("tube",0,0,z,.75,.75,.12,dark)
        for x in [-.7,.7]: p("tube",x,0,1.2,.08,.08,.9,metal)
        cross(0,-.68,1.3,.8)
        for i in range(5): p("box",.5,-.65,.6+i*.2,.08,.03,.025,white)


def main():
    kit.clear_file(); kit.build_materials(); kit.setup_render_scene()
    green=make_material("Regen jade",(.08,.65,.32)); fluid=make_material("Medical fluid",(.14,.8,.58),.1); red=make_material("Blood crimson",(.6,.06,.12))
    scene=bpy.context.scene; scene.render.threads_mode="FIXED"; scene.render.threads=4
    kit.CAMERA.data.dof.use_dof=False; kit.CAMERA.data.ortho_scale=3.6
    LOCAL.mkdir(parents=True,exist_ok=True); SOURCE.parent.mkdir(parents=True,exist_ok=True)
    collections=[]; assets=[]
    for index,id in enumerate(IDS):
        col=kit.make_collection(id); build(col,id,green,fluid,red)
        recent_card_environments.add_environment(kit,col,id)
        col.hide_render=True; collections.append(col)
        assets.append({"asset_id":id,"category":"card","runtime_path":"assets/icons/cards/"+id+".png","size":512})
    col=kit.make_collection("regen_status")
    primitive(col,"HealingCross","box",(0,0,1.2),(.2,.15,.75),green)
    primitive(col,"HealingCross","box",(0,0,1.2),(.75,.15,.2),green)
    primitive(col,"RegenLoop","ring",(0,.1,1.2),(.95,.95,.95),fluid,(math.pi/2,0,0))
    col.hide_render=True; collections.append(col); assets.append({"asset_id":"regen","category":"status","runtime_path":"assets/icons/status/regen.png","size":96})
    collections[0].hide_render=False; bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
    for index,(col,asset) in enumerate(zip(collections,assets)):
        if asset["category"] != "card" and "--cards-only" in sys.argv: continue
        for other in collections: other.hide_render=other!=col
        kit.CAMERA.location=(2.2+(index%3)*.35,-8,3.2+(index%2)*.7); kit.look_at(kit.CAMERA,Vector((0,0,1.2)))
        scene.render.film_transparent=asset["category"]=="status"; scene.render.resolution_x=1024; scene.render.resolution_y=1024
        scene.render.filepath=str(LOCAL/(asset["asset_id"]+".png")); bpy.ops.render.render(write_still=True)
    manifest={"tool":"Blender "+bpy.app.version_string,"generator":"tools/blender/build_regeneration_cards.py","source_path":SOURCE.relative_to(ROOT).as_posix(),"source_sha256":hashlib.sha256(SOURCE.read_bytes()).hexdigest(),"assets":assets}
    SOURCE.with_suffix(".manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    print("REGEN_ART_RENDER_OK",len(assets))


if __name__=="__main__": main()
