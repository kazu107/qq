"""Eighteen original editable achievement icons, isolated from live Blender."""
import bpy
import hashlib
import json
import math
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).parent))
import build_ui_batch as kit
import build_achievement_icons as old

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/"art_src/blender/achievements/qq_advanced_achievements.blend"
RENDERS=ROOT/"tools/.local/advanced_achievement_icons"


def build(id):
    b,s,p,a=kit.box,kit.shape,kit.pipe,kit.arrow
    if id=="reservation_master":
        b("Sealed_Order",-.18,0,1.5,1.08,"steel",.05,.28)
        p("Envelope_Fold",[(-.9,.44),(-.18,-.14),(.54,.44)],.055,"gold",-.18)
        kit.clock(.56,-.45,.52)
    elif id=="echo_practitioner":
        for x,z in [(-.33,.22),(.32,-.23)]:
            s("Echo_Bell",[(x-.43,z-.40),(x-.30,z+.03),(x-.25,z+.40),(x+.25,z+.40),(x+.30,z+.03),(x+.43,z-.40)],"cyan",-.15 if x>0 else .1,.22)
            kit.disc("Bell_Clapper",x,z-.48,.1,"gold",-.26)
        p("Echo_Wave",[(.61,.65),(.89,.44),(.95,.12)],.055,"white",-.3)
    elif id=="combo_architect":
        for x,z,role in [(-.58,.43,"red"),(.58,.43,"green"),(0,-.56,"cyan")]:
            b("Command_Card",x,z,.52,.71,role,.0,.17)
            kit.star("Card_Seal",x,z,.13,"gold",-.17)
        p("Combo_Link",[(-.58,.43),(0,-.56),(.58,.43),(-.58,.43)],.045,"gold",.19)
    elif id=="regeneration_medic":
        for side in (-1,1):
            s("Regrowth_Leaf",[(0,-.6),(side*.82,-.08),(side*.65,.78),(side*.15,.39)],"green",.06,.20)
        b("Medical_Cross",0,.02,.27,1.09,"white",-.24,.16)
        b("Medical_Cross",0,.02,1.09,.27,"white",-.24,.16)
        old.crystal(0,-.69,.25,"cyan",-.25)
    elif id=="conversion_alchemist":
        old.crystal(-.47,.15,.67,"red")
        old.crystal(.49,.15,.67,"cyan")
        a("Conversion_Flow",0,-.58,1.2,"gold","right",-.34)
        kit.star("Converted_Spark",0,.57,.30,"white",-.38)
    elif id=="autonomous_arsenal":
        b("Turret_Chassis",0,-.55,1.31,.43,"steel",.08,.58)
        b("Turret_Head",0,.10,1.05,.63,"cyan",-.04,.37)
        for x in (-.28,.28): b("Twin_Barrel",x,.49,.20,.82,"iron",-.18,.3)
        kit.disc("Optic",0,.04,.18,"red",-.31)
        for side in (-1,1): p("Leg",[(side*.3,-.55),(side*.83,-.88)],.08,"gold",.0)
    elif id=="cleanse_specialist":
        s("Cleansing_Drop",[(0,.98),(.60,.08),(.46,-.62),(0,-.88),(-.46,-.62),(-.60,.08)],"cyan",.08,.30)
        kit.star("Clean_Spark",.17,.06,.48,"white",-.26)
        kit.star("Small_Spark",-.61,.61,.21,"gold",-.29)
    elif id=="cannon_strike":
        b("Cannon_Barrel",-.12,.05,1.35,.62,"iron",.03,.63)
        b("Cannon_Muzzle",.58,.05,.21,.8,"gold",-.08,.68)
        kit.disc("Cannon_Wheel",-.52,-.49,.32,"steel",-.35)
        kit.star("Cannon_Blast",.90,.18,.37,"red",-.44)
        kit.star("Cannon_Core",.88,.18,.18,"white",-.49)
    elif id=="flawless_fighter":
        kit.shield("cyan")
        old.laurel("green",bottom=-.40)
        kit.star("Unbroken_Star",0,.17,.38,"white",-.36)
    elif id=="comeback_victor":
        old.helmet(0,-.18,.8,"red")
        for side in (-1,1): s("Rising_Wing",[(side*.12,-.14),(side*1,.75),(side*.79,-.12),(side*.38,-.56)],"gold",.1,.17)
        a("Comeback_Rise",0,.38,.70,"white","up",-.40)
    elif id=="clutch_breaker":
        kit.clock(-.13,.12,.9)
        p("Last_Second_Blade",[(-.78,-.93),(.64,.74)],.075,"white",-.38)
        kit.star("Interrupt_Flash",.03,.02,.36,"red",-.46)
    elif id=="hazard_conqueror":
        for i in range(3):
            x=(i-1)*.64
            b("Cleared_Gate",x,-.2+i*.17,.42,1.13,"steel",i*.05,.25)
            kit.star("Gate_Clear",x,.48+i*.17,.20,"gold",-.22)
        p("Victory_Flagpole",[(.83,-.91),(.83,.96)],.04,"gold",-.32)
        s("Victory_Flag",[(.83,.96),(.22,.76),(.83,.49)],"green",-.33,.1)
    elif id=="damage_collector":
        for side in (-1,1): kit.blade("Strike_Blade",side*.44,"steel",side*.4,0,.94,-.06)
        s("Accumulated_Flame",[(0,.94),(.48,.22),(.30,-.49),(0,-.76),(-.46,-.24),(-.32,.37),(-.12,.05)],"red",-.36,.22)
        kit.star("Heat_Core",0,-.15,.25,"gold",-.51)
    elif id=="shield_sentinel":
        for x in (-.69,0,.69):
            b("Fortress_Tower",x,-.15,.45,1.42,"steel",.07,.4)
            b("Fortress_Battlement",x,.64,.59,.25,"gold",-.02,.42)
        kit.shield("cyan")
    elif id=="tactical_repertoire":
        for i,role in enumerate(["red","green","cyan","gold"]):
            x=(i-1.5)*.40
            b("Tactical_Card",x,abs(i-1.5)*.17,.52,1.17,role,-.1*i,.15)
            kit.star("Card_Mark",x,.13+abs(i-1.5)*.17,.14,"white",-.2-.1*i)
    elif id=="sevenfold_adventurer":
        for i in range(7):
            angle=math.tau*i/7
            old.helmet(math.sin(angle)*.70,math.cos(angle)*.65,.38,["cyan","red","green","gold"][i%4])
        kit.star("Sevenfold_Star",0,0,.35,"white",-.43)
    elif id=="infinite_climber":
        for i in range(4): b("Climbing_Step",-.73+i*.47,-.76+i*.32,.45,.27+i*.12,"steel",.12,.4)
        old.infinity(z=.47,scale=.72,role="gold",y=-.30)
        a("Ascending_Path",.61,.10,.68,"green","up",-.38)
    elif id=="arena_streaker":
        old.laurel("red",bottom=-.4)
        s("Streak_Crown",[(-.75,.14),(-.78,.85),(-.3,.48),(0,1),(.3,.48),(.78,.85),(.75,.14)],"gold",-.06,.30)
        for x in (-.42,0,.42): kit.disc("Streak_Gem",x,-.22,.17,"cyan",-.28)
        p("Unbroken_Chain",[(-.75,-.72),(0,-.50),(.75,-.72)],.075,"steel",-.08)
    else: raise ValueError(id)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    SOURCE.parent.mkdir(parents=True,exist_ok=True); RENDERS.mkdir(parents=True,exist_ok=True)
    kit.materials();kit.render_rig()
    scene=bpy.context.scene
    scene.cycles.samples=16
    scene.camera.data.ortho_scale=2.9
    scene.render.resolution_x=scene.render.resolution_y=1024
    entries=[]; collections=[]
    for data in json.loads((ROOT/"data/achievements.json").read_text(encoding="utf-8")):
        if data.get("tracking_version")!=1:continue
        id=data["id"]
        kit.CURRENT=bpy.data.collections.new("achievement_"+id)
        scene.collection.children.link(kit.CURRENT)
        kit.CURRENT["achievement_id"]=id
        build(id);collections.append(kit.CURRENT)
        entries.append({"asset_id":"achievement_"+id,"visual_id":id,"category":"achievement","size":128,
                        "runtime_path":f"assets/icons/achievements/{id}.png","source_path":kit.rel(SOURCE),
                        "source_collection":kit.CURRENT.name,"presentation":"transparent_3d_sculpture","objects":len(kit.CURRENT.objects)})
    for entry,collection in zip(entries,collections):
        for other in collections:other.hide_render=other!=collection
        path=RENDERS/(entry["visual_id"]+".png")
        scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)
        entry["render_path"]=kit.rel(path)
        print("ADVANCED_ACHIEVEMENT_RENDER_OK",entry["visual_id"],flush=True)
    for c in collections:c.hide_render=c.hide_viewport=c!=collections[0]
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE),compress=True)
    meta={"batch_id":"blender_advanced_achievements_01","source":kit.rel(SOURCE),"source_sha256":old.sha(SOURCE),
          "generator":kit.rel(Path(__file__)),"generator_sha256":old.sha(Path(__file__)),"blender_version":bpy.app.version_string,"assets":entries}
    SOURCE.with_suffix(".manifest.json").write_text(json.dumps(meta,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("ADVANCED_ACHIEVEMENT_ICONS_OK",len(entries),flush=True)

if __name__=="__main__":main()
