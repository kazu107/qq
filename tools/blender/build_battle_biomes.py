"""Original modular battle scenery. Independent Blender process, never live MCP.

Reuse the original field's coordinate contract and primitive/export library.
Editable .blend sources retain every part; runtime meshes are grouped by material.
"""
import bpy
import hashlib
import json
import math
from pathlib import Path
import random
import sys

sys.path.insert(0, str(Path(__file__).parent))
import build_environment_batch as kit

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art_src/blender/environment/biomes"
MODELS = ROOT / "assets/models/environment/biomes"
BACKGROUNDS = ROOT / "assets/backgrounds/biomes"
PREVIEWS = ROOT / "art_src/blender/previews/biomes"
GROUPS = ["BattleWorldGround", "BattleMeadow", "ArenaBase", "ArenaTiles",
          "ArenaBorders", "ArenaLaneLines", "Architecture", "Props", "Foliage",
          "Energy", "MovingGear", "MovingFloat"]
FIELDS = [
    ("clock_ruins", "Mossy Clock Ruins", "meadow"),
    ("brass_foundry", "Brass Foundry", "foundry"),
    ("rift_gallery", "Fractured Sky Gallery", "rift"),
    ("forgotten_sanctuary", "Forgotten Sanctuary", "sanctuary"),
    ("timekeeper_engine", "Great Clock Engine", "foundry"),
    ("paradox_reactor", "Recursive Core Reactor", "rift"),
    ("axiom_altar", "Broken Axiom Altar", "sanctuary"),
    ("eternity_temple", "Temple of the Final Hour", "sanctuary"),
]
REGIONS = ["clock_ruins", "brass_foundry", "rift_gallery", "forgotten_sanctuary"]
THEMES = {
    "meadow": {"stone": (.29,.36,.30), "tile_a": (.23,.29,.25), "tile_b": (.29,.34,.29),
               "world_ground": (.12,.21,.14), "meadow": (.20,.29,.16), "accent": (.22,.68,.62)},
    "foundry": {"stone": (.23,.25,.26), "tile_a": (.19,.22,.23), "tile_b": (.25,.27,.26),
                "world_ground": (.12,.14,.16), "meadow": (.16,.18,.19), "accent": (1,.32,.055)},
    "rift": {"stone": (.23,.30,.39), "tile_a": (.20,.26,.32), "tile_b": (.27,.31,.36),
             "world_ground": (.055,.10,.17), "meadow": (.10,.16,.24), "accent": (.14,.72,1)},
    "sanctuary": {"stone": (.47,.46,.39), "tile_a": (.31,.34,.34), "tile_b": (.38,.39,.37),
                  "world_ground": (.11,.15,.21), "meadow": (.20,.23,.28), "accent": (.61,.83,1)},
}
ASSETS = []
MANIFESTS = []


def rel(path):
    return path.relative_to(ROOT).as_posix()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def start(asset_id, theme):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    kit.MATERIALS.clear()
    kit.GROUPS.clear()
    kit.SOURCE_OBJECTS.clear()
    kit.RNG = random.Random(7127)
    kit.SOURCE = OUT / (asset_id + ".blend")
    kit.MODEL = MODELS / (asset_id + ".glb")
    kit.COUNTS = {"field": asset_id, "grid_columns": 7, "grid_rows": 5}
    kit.SEMANTIC_NODES = GROUPS[:]
    kit.SOURCE_COLLECTION = kit.collection("EDITABLE_" + asset_id)
    kit.RIG_COLLECTION = kit.collection("RENDER_RIG_NOT_EXPORTED")
    palette = dict(kit.PALETTE)
    for name, color in THEMES[theme].items():
        previous = palette.get(name, ((.5,.5,.5), .1, .6))
        palette[name] = ((*color,1), previous[1], previous[2])
    palette["accent"] = ((*THEMES[theme]["accent"],1), .35, .36)
    palette["water"] = ((.07,.32,.35,1), .35, .22)
    palette["crystal"] = ((.20,.62,.74,1), .45, .22)
    palette["fabric"] = ((.33,.22,.14,1), 0, .85)
    kit.PALETTE = palette
    for role in palette:
        item = kit.material(role)
        if role in ("accent", "crystal"):
            node = item.node_tree.nodes.get("Principled BSDF")
            node.inputs["Emission Color"].default_value = palette[role][0]
            node.inputs["Emission Strength"].default_value = .7
        kit.MATERIALS[role] = item
    for name in GROUPS:
        kit.GROUPS[name] = kit.empty(name, kit.SOURCE_COLLECTION)


def box(name, p, s, role="stone", group="Architecture", **kwargs):
    return kit.box(name, p, s, role, group, **kwargs)


def cyl(name, p, r, h, role="brass", group="Architecture", **kwargs):
    return kit.cylinder(name, p, r, h, role, group, **kwargs)


def ring(name, p, r, t=.07, role="brass", group="Architecture", vertical=False):
    obj = kit.ring(name, p, r, t, role, group, segments=40, cross=6)
    if vertical:
        obj.rotation_euler.x = math.pi / 2
    return obj


def gear(name, p, radius, group="Architecture", vertical=True, teeth=18):
    owner = kit.empty(name, kit.SOURCE_COLLECTION, kit.GROUPS[group], p)
    ring(name + "Rim", (0,0,0), radius, .11, "brass", group, vertical).parent = owner
    for i in range(teeth):
        a = i * math.tau / teeth
        pos = (math.cos(a)*radius, math.sin(a)*radius, 0) if vertical else (math.cos(a)*radius,0,math.sin(a)*radius)
        obj = box(name + "Tooth", pos, (.20,.26,.20), "brass", group, parent=owner)
        obj.rotation_euler.y = a if vertical else 0
    for i in range(6):
        a = i*math.tau/6
        end = (math.cos(a)*radius*.84, math.sin(a)*radius*.84, 0) if vertical else (math.cos(a)*radius*.84,0,math.sin(a)*radius*.84)
        kit.rod(name+"Spoke", (0,0,0), end, .065, "iron", group, owner, 8)
    return owner


def clock(p, radius=1.3):
    ring("ClockRim", p, radius, .12, "brass", vertical=True)
    ring("ClockInner", p, radius*.79, .035, "accent", vertical=True)
    for i in range(12):
        a = i*math.tau/12
        obj = box("ClockIndex", (p[0]+math.cos(a)*radius*.91,p[1]+math.sin(a)*radius*.91,p[2]),
                  (.08,.17,.08), "ivory")
        obj.rotation_euler.y = -a + math.pi/2
    kit.rod("ClockHourHand", p, (p[0]-.45*radius,p[1]+.36*radius,p[2]+.04), .045,"brass","Architecture")
    kit.rod("ClockMinuteHand", p, (p[0]+.18*radius,p[1]+.72*radius,p[2]+.04), .025,"ivory","Architecture")


def column(x, z, h=3.0, stone="stone"):
    cyl("ColumnFoot", (x,.12,z), .58,.3, stone)
    cyl("FlutedColumn", (x,h*.5+.25,z), .28,h,stone,sides=10)
    cyl("ColumnCapital", (x,h+.25,z), .47,.25,"brass")
    for i in range(3):
        ring("ColumnBand", (x,.5+i*h*.34,z), .30,.035,"brass")


def crystal(x, z, h=1.5, group="Energy"):
    cyl("CrystalBase", (x,.05,z), .48,.19,"stone_dark",group,sides=8)
    for i in range(3):
        obj = cyl("CrystalShard", (x+(i-1)*.26,.28+h*.5,z+(i%2)*.22),.22,h*(1-i*.16),"crystal",group,sides=5,top=0)
        obj.rotation_euler.y = (i-1)*.22


def arches():
    for x in (-7.7,7.7):
        for z in (-5.5,-9.7):
            column(x,z,3.0 if z==-5.5 else 3.8)
        box("ColonnadeLintel", (x,3.5,-7.6),(.68,.40,4.9),"stone")
    for x in (-5.6,5.6):
        column(x,-12,4.3)
    box("BackLintel",(0,4.65,-12),(12.2,.55,.9),"stone")


def floor():
    # Original floor: same 7x5 tile centers and actor-safe level standing areas.
    kit.build_floor()


def meadow():
    rng = random.Random(601)
    for i in range(220):
        x,z=rng.uniform(-12,12),rng.uniform(-13,6)
        if abs(x)<6.6 and -4<z<4.2:
            x=math.copysign(rng.uniform(7,11),x)
        for j in range(5):
            obj=box("GrassBlade",(x+j*.06,.04,z),(.035,rng.uniform(.25,.60),.11),"grass","Foliage",bevel=0)
            obj.rotation_euler.y=rng.uniform(-.3,.3)
        if i%6==0:
            cyl("WildflowerStem",(x,.18,z),.012,.42,"grass","Foliage",sides=5)
            kit.ico("Wildflower",(x,.4,z),(.10,.035,.10),"petal_ivory" if i%12 else "petal","Foliage",subdivision=1)
    for side in (-1,1):
        for i in range(5):
            x,z=side*(7.5+i*.46),-5.5-i*.5
            box("BrokenWallBlock",(x,.35+i*.15,z),(.9,.7,.8),"stone",yaw=i*.12)
        column(side*7.3,-7,2.3 if side<0 else 3.2)
        for i in range(5):
            kit.ico("MossyRock",(side*(8.1+i*.9),-.1,-2-i*.9),(.8,.42,.7),"stone","Foliage",subdivision=1)
            kit.ico("RuinFern",(side*(7.4+i*.7),.2,-1-i*1.3),(.65,.43,.50),"leaf_light","Foliage",subdivision=1)
    box("ShallowBrook",(-11,-.12,-3),(1.5,.04,18),"water","Energy",bevel=.2,yaw=-.12)
    for i in range(4):
        box("BrookSteppingStone",(-11.5+i*.37,-.05,-4+i*.25),(.5,.14,.55),"stone")
    clock((0,2.2,-9.2),1.5)
    for side in (-1,1):
        column(side*2,-9.3,2.4)
        for j in range(5):
            kit.ico("DistantCanopy",(side*(9+j*2),2,-15-j), (2.2,2.5,2.2),"leaf","Foliage",subdivision=1)
    box("RuinCoping",(0,3.05,-9.5),(5,.5,.8),"stone")


def foundry(boss=False):
    for side in (-1,1):
        for i in range(4):
            x,z=side*8.2,-3-i*2.6
            box("RivetedPillar",(x,1.8,z),(.65,3.6,.65),"iron")
            for h in (.3,1.7,3.2):
                box("PillarCollar",(x,h,z),(.85,.17,.85),"brass")
            kit.rod("SteamMain",(x-.35,.7,z),(x-.35,2.8,z),.15,"brass","Props")
        box("CatwalkRail",(side*8.2,3.65,-7),(1,.14,10.5),"brass")
        box("HeatTrench",(side*7,.05,-.6),(.35,.06,8),"accent","Energy")
        for i in range(6):
            box("TrenchGrate",(side*7,.11,-4+i*1.3),(.55,.10,.12),"iron","Props")
    box("EngineBackWall",(0,2.4,-11.5),(17,5,.7),"stone_dark")
    for x in (-5,0,5):
        box("FurnaceOpening",(x,1.4,-11.05),(2.2,2,.12),"accent","Energy")
        for i in range(5):
            box("FurnaceBars",(x-.9+i*.45,1.4,-10.9),(.07,2.05,.10),"iron")
        gear("EngineGear",(x,3.6,-10.9),1.3 if x else 1.6,teeth=18)
    if boss:
        clock((0,2.4,-8.7),1.75)
        gear("LeftClockGear",(-4.4,2.6,-9.1),1.4,teeth=20)
        gear("RightClockGear",(4.4,2.6,-9.1),1.4,teeth=20)
        for x in (-2.7,2.7):
            kit.rod("PendulumRod",(x,5.5,-10),(x-.35,1.3,-10),.065,"brass","Props")
            cyl("PendulumWeight",(x-.35,1.3,-10),.5,.28,"brass","Props")
    else:
        for side in (-1,1):
            gear("SideWheel",(side*9,1.2,-2),1,"Props",teeth=14)


def rift(boss=False):
    rng=random.Random(502)
    for i in range(22):
        side=-1 if i%2 else 1
        x,z=side*rng.uniform(7.2,16),rng.uniform(-17,3)
        kit.ico("FloatingIsland",(x,rng.uniform(-1.4,.1),z),(rng.uniform(.7,1.8),.6,rng.uniform(.8,1.9)),"stone","Architecture",subdivision=1)
        if i%3==0:
            crystal(x,z,rng.uniform(.5,1.8))
    for side in (-1,1):
        column(side*7.2,-6,2.7)
        box("BrokenGalleryBeam",(side*6.4,3,-6),(2.2,.4,.55),"stone",yaw=side*.25)
    for i in range(7):
        x=(i-3)*2
        obj=box("LevitationShard",(x,3.1+abs(i-3)*.28,-11),(.6,.75,.5),"stone_light","MovingFloat",yaw=i*.31)
        obj["qq_motion"]="float"
    if boss:
        for r in (1.15,1.65,2.1):
            ring("ReactorOrbit",(0,2.2,-9.7),r,.08,"brass",vertical=True)
        crystal(0,-9.7,3.2)
        for side in (-1,1):
            for i in range(3):
                crystal(side*(3.6+i*.9),-9.7-i*.8,2-i*.2)
    else:
        ring("RiftPortal",(0,3,-11),2.4,.13,"stone_light",vertical=True)
        ring("RiftInner",(0,3,-10.95),2.15,.045,"accent","Energy",vertical=True)


def sanctuary(kind="normal"):
    arches()
    for side in (-1,1):
        for i in range(3):
            cyl("CeremonialBowl",(side*(7.2+i*.6),.55,-3-i*2),.42,.2,"brass","Props",top=.56)
            crystal(side*(7.2+i*.6),-3-i*2,.55)
    for i in range(4):
        box("DaisStep",(0,-.02+i*.16,-8.6-i*.55),(8.4-i*.6,.18,2.8-i*.35),"stone")
    if kind=="axiom":
        for side in (-1,1):
            for i in range(4):
                x,z=side*(1.7+i*.9),-10-i*.32
                obj=box("BrokenLawTablet",(x,2.3+i*.25,z),(.65,2,.35),"stone_light","MovingFloat",yaw=side*(.25+i*.14))
                for j in range(3):
                    box("TabletRunes",(x,1.9+i*.25+j*.3,z+.2),(.34,.035,.04),"accent","Energy")
        ring("ShatteredLawHalo",(0,2.3,-10),1.6,.13,"brass",vertical=True)
    elif kind=="eternity":
        for x in (-3.5,3.5):
            column(x,-10.5,5.5)
        clock((0,2.6,-9.5),1.75)
        ring("FinalHourInnerHalo",(0,2.6,-9.45),1.18,.055,"accent","Energy",vertical=True)
        for i in range(7):
            box("TempleCrown",((i-3)*1.1,6.2-abs(i-3)*.35,-11.6),(.6,1,.75),"brass")
    else:
        clock((0,3,-11.2),1.6)
        for i in range(3):
            ring("TimeSeal",(0,.65,-9.5),1+i*.55,.025,"accent","Energy")


def overlay(region):
    rng=random.Random(873)
    for side in (-1,1):
        for i in range(5):
            x,z=side*(7.1+i*.72),-3-i*1.7
            if region=="brass_foundry":
                cyl("PressureVent",(x,.3,z),.28,.6,"iron","Props")
                ring("HotVentMouth",(x,.62,z),.21,.035,"accent","Energy")
                for j in range(3):
                    ring("SteamWisp",(x+.07*j,.9+j*.24,z),.17+j*.06,.018,"stone_light","MovingFloat")
            elif region=="rift_gallery":
                kit.ico("DriftingDebris",(x,.8+i*.14,z),(.35,.42,.3),"stone_light","MovingFloat",subdivision=1)
            elif region=="forgotten_sanctuary":
                ring("NightRune",(x,.14,z),.45,.025,"accent","Energy")
                crystal(x,z,.65)
            else:
                crystal(x,z,rng.uniform(.7,1.4))


def facility(kind):
    # Facility kit sits behind the center options, with readable side silhouettes.
    if kind=="shop":
        for x in (-4.5,4.5):
            box("MarketPost",(x,1.7,-5.9),(.16,3.4,.16),"wood","Props")
        box("MarketCanopy",(0,3.3,-6.4),(9.5,.13,3.6),"fabric","Props")
        box("MerchantCounter",(0,.85,-5.7),(8.8,.22,1.25),"wood","Props")
        for i in range(7):
            cyl("MerchantJar",(-3.5+i*1.1,1.15,-5.7),.22,.4,"brass","Props")
        for side in (-1,1):
            box("SupplyCrate",(side*5,.4,-4.9),(.9,.8,.9),"wood","Props")
    elif kind=="forge":
        box("ForgeHearth",(-4,1,-6),(2.1,2,1.8),"stone_dark","Props")
        box("ForgeFire",(-4,1,-4.99),(1.4,.7,.08),"accent","Energy")
        box("ForgeChimney",(-4,2.9,-6),(.9,2.3,.9),"iron","Props")
        cyl("AnvilStump",(3.3,.42,-5),.65,.85,"wood","Props")
        box("AnvilBody",(3.3,1,-5),(1.4,.35,.65),"iron","Props")
        kit.ico("AnvilHorn",(4.1,1.08,-5),(.65,.18,.24),"iron","Props",subdivision=1)
        gear("ForgeWheel",(0,1.4,-7),1,"Props",teeth=16)
    else:
        for x in (-4.4,4.4):
            column(x,-6.7,2.6)
        cyl("HealingBasinFoot",(0,.3,-6),1.5,.5,"stone","Props")
        cyl("HealingBasinRim",(0,.65,-6),1.7,.25,"ivory","Props")
        cyl("HealingWater",(0,.79,-6),1.45,.04,"water","Energy")
        crystal(0,-6,1.7)
        for side in (-1,1):
            box("RestBench",(side*4,.4,-4),(2.1,.25,.7),"wood","Props")


def setup_rig(theme):
    scene=bpy.context.scene
    scene.render.engine="CYCLES"
    scene.cycles.samples=12
    scene.cycles.use_denoising=True
    scene.render.threads_mode="FIXED"
    scene.render.threads=4
    scene.render.image_settings.file_format="PNG"
    scene.render.image_settings.color_mode="RGB"
    scene.view_settings.view_transform="AgX"
    scene.world=bpy.data.worlds.new("BiomeSky")
    scene.world.use_nodes=True
    bg=scene.world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value=(.16,.23,.30,1)
    bg.inputs["Strength"].default_value=.6
    kit.light("SoftSky",(-4,12,6),(0,0,-4),2100,(.82,.91,1),12)
    kit.light("WarmArchitecture",(4,7,-9),(0,1,-3),1500,(1,.63,.3) if theme=="foundry" else (.48,.77,1),8)
    sun_data=bpy.data.lights.new("Daylight","SUN")
    sun_data.energy=1.8
    sun_data.angle=.2
    sun=bpy.data.objects.new("Daylight",sun_data)
    kit.RIG_COLLECTION.objects.link(sun)
    sun.rotation_euler=(.5,-.5,-.6)
    return kit.camera("BattleCamera",(0,6.75,10.35),(0,.78,-.42),lens=32), kit.camera("FacilityCamera",(0,4.6,8.9),(0,1,-5),lens=31)


def register(asset_id, category, runtime, source, **extra):
    entry={"asset_id":asset_id,"category":category,"runtime_path":rel(runtime),
           "source_path":rel(source),"generator":rel(Path(__file__)),
           "export_sha256":sha(runtime),"replacement_status":"approved", **extra}
    ASSETS.append(entry)


def save_export(asset_id, category="environment"):
    kit.SEMANTIC_NODES=[name for name in GROUPS if any(o["qq_group"]==name for o in kit.SOURCE_OBJECTS)]
    bpy.context.scene["qq_generator"]=rel(Path(__file__))
    bpy.context.scene["qq_coordinate_contract"]="Godot(x,y,z) -> Blender(x,-z,y)"
    bpy.context.scene["qq_visual_only"]=True
    bpy.ops.wm.save_as_mainfile(filepath=str(kit.SOURCE),compress=True)
    stats=kit.export_model()
    register(asset_id,category,kit.MODEL,kit.SOURCE,triangles=stats["triangles"],surfaces=stats["surfaces"])
    MANIFESTS.append({"id":asset_id,"source":rel(kit.SOURCE),"source_sha256":sha(kit.SOURCE),"runtime":stats})


def render(cam, path):
    kit.render_png(cam,path,(1024,576))


def main():
    for directory in (OUT,MODELS,BACKGROUNDS,PREVIEWS): directory.mkdir(parents=True,exist_ok=True)
    for asset_id,title,theme in FIELDS:
        start(asset_id,theme)
        floor()
        if asset_id=="clock_ruins": meadow()
        elif asset_id in ("brass_foundry","timekeeper_engine"): foundry(asset_id=="timekeeper_engine")
        elif asset_id in ("rift_gallery","paradox_reactor"): rift(asset_id=="paradox_reactor")
        else: sanctuary({"axiom_altar":"axiom","eternity_temple":"eternity"}.get(asset_id,"normal"))
        battle_cam,facility_cam=setup_rig(theme)
        save_export(asset_id)
        target=BACKGROUNDS/(asset_id+".png")
        render(battle_cam,target)
        register(asset_id+"_background","background",target,kit.SOURCE)
        if asset_id in REGIONS:
            base_objects=set(kit.SOURCE_OBJECTS)
            for kind in ("shop","forge","heal"):
                facility(kind)
                target=BACKGROUNDS/(asset_id+"_"+kind+".png")
                render(facility_cam,target)
                register(asset_id+"_"+kind,"background",target,OUT/("facility_"+kind+".blend"),region_source=rel(kit.SOURCE))
                for obj in list(kit.SOURCE_OBJECTS):
                    if obj not in base_objects:
                        kit.SOURCE_OBJECTS.remove(obj)
                        bpy.data.objects.remove(obj,do_unlink=True)
        print("BIOME_COMPLETE",asset_id,flush=True)
    for region in REGIONS:
        theme=next(t for i,_,t in FIELDS if i==region)
        asset_id=region+"_infinite"
        start(asset_id,theme)
        overlay(region)
        save_export(asset_id,"environment_overlay")
    for kind in ("shop","forge","heal"):
        start("facility_"+kind,"foundry" if kind=="forge" else "meadow")
        facility(kind)
        save_export("facility_"+kind,"facility_3d")
    manifest={"batch_id":"blender_battle_biomes_01","blender":bpy.app.version_string,
              "generator":rel(Path(__file__)),"generator_sha256":sha(Path(__file__)),
              "fields":MANIFESTS,"assets":ASSETS,"third_party_inputs":[],
              "coordinate_contract":"Shared 7x5 floor and original actor/camera/UI positions",
              "runtime_bytes":sum((ROOT/e["runtime_path"]).stat().st_size for e in ASSETS)}
    (OUT/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    path=ROOT/"data/art_provenance.json"
    data=json.loads(path.read_text(encoding="utf-8"))
    paths={e["runtime_path"] for e in ASSETS}
    data["assets"]=[e for e in data["assets"] if e["runtime_path"] not in paths]+ASSETS
    data["updated_at"]="2026-10-29"
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("BATTLE_BIOMES_OK",len(ASSETS),manifest["runtime_bytes"],flush=True)


if __name__=="__main__":
    main()
