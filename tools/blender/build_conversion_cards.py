"""Original damage-conversion art, isolated from the user's live Blender file."""
from pathlib import Path
import sys
import math
import json
import hashlib
import bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).parent))
import build_art_vertical_slice as kit
import card_action_scenes
from build_reservation_cards import primitive
LOCAL=ROOT/"tools/.local/conversion/art";SOURCE=ROOT/"art_src/blender/cards/damage_conversion.blend"


def build(col,mode):
    m=kit.MATERIALS;accent=m["cyan"] if mode=="shield" else m["brass_edge"]
    def p(shape,pos,scale,mat,rot=(0,0,0)):return primitive(col,mode+shape,shape,pos,scale,mat,rot)
    p("ring",(0,0,1.25),(.95,.95,.95),accent,(math.pi/2,0,0))
    if mode=="heal":
        kit.add_profile(col,"Heart",[(-.65,.25),(-.65,.65),(-.35,.85),(0,.6),(.35,.85),(.65,.65),(.65,.25),(0,-.45)],.28,m["ceramic_light"],location=(0,0,.85),bevel=.08)
        p("box",(0,-.35,1.2),(.1,.05,.35),m["cyan"]);p("box",(0,-.35,1.2),(.35,.05,.1),m["cyan"])
    else:
        kit.add_profile(col,"Shield",[(-.7,.9),(.7,.9),(.6,0),(0,-.65),(-.6,0)],.24,m["ceramic_light"],location=(0,0,1.1),bevel=.07)
        for i in range(3):p("box",((i-1)*.27,-.3,1.2),(.09,.05,.35),accent)
    for side in [-1,1]:
        p("box",(side*1.05,-.1,1.2),(.4,.1,.055),m["steel"])
        p("cone",(side*.68,-.1,1.2),(.15,.15,.25),accent,(0,side*math.pi/2,0))
    for i in range(6):
        angle=i*math.tau/6;p("box",(math.sin(angle)*.96,-.08,1.25+math.cos(angle)*.96),(.09,.16,.12),m["gunmetal"],(0,angle,0))


def main():
    kit.clear_file();kit.build_materials();kit.setup_render_scene()
    scene=bpy.context.scene;scene.render.threads_mode="FIXED";scene.render.threads=4
    kit.CAMERA.data.dof.use_dof=False;kit.CAMERA.data.ortho_scale=3.7
    LOCAL.mkdir(parents=True,exist_ok=True);SOURCE.parent.mkdir(parents=True,exist_ok=True)
    collections=[];assets=[]
    for id,mode in [("life_conversion","heal"),("barrier_conversion","shield")]:
        col=kit.make_collection(id);build(col,mode)
        card_action_scenes.backdrop(kit,col,"Backdrop",(.02,.035,.045) if mode=="shield" else (.035,.025,.015),(.07,.16,.23) if mode=="shield" else (.2,.13,.05))
        col.hide_render=True;collections.append(col);assets.append({"asset_id":id,"category":"card","runtime_path":"assets/icons/cards/"+id+".png","size":512})
    for id in ["damage_conversion","conversion_lockout"]:
        col=kit.make_collection(id);build(col,"shield")
        if id=="conversion_lockout":primitive(col,"LockoutSlash","box",(0,-.5,1.2),(1.1,.08,.13),kit.MATERIALS["brass_edge"],(0,.7,0))
        col.hide_render=True;collections.append(col);assets.append({"asset_id":id,"category":"status","runtime_path":"assets/icons/status/"+id+".png","size":96})
    collections[0].hide_render=False;bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
    for i,(col,a) in enumerate(zip(collections,assets)):
        for other in collections:other.hide_render=other!=col
        kit.CAMERA.location=(2.4 if i%2==0 else -2.2,-8,3.4);kit.look_at(kit.CAMERA,Vector((0,0,1.2)))
        scene.render.film_transparent=a["category"]=="status";scene.render.resolution_x=1024;scene.render.resolution_y=1024
        scene.render.filepath=str(LOCAL/(a["asset_id"]+".png"));bpy.ops.render.render(write_still=True)
    manifest={"tool":"Blender "+bpy.app.version_string,"generator":"tools/blender/build_conversion_cards.py","source_path":SOURCE.relative_to(ROOT).as_posix(),"source_sha256":hashlib.sha256(SOURCE.read_bytes()).hexdigest(),"assets":assets}
    SOURCE.with_suffix(".manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    print("CONVERSION_ART_RENDER_OK",len(assets))


if __name__=="__main__":main()
