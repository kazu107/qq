"""Thirty editable achievement sculptures; isolated Blender, no live MCP state."""
from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_ui_batch as kit

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art_src/blender/achievements/qq_achievements.blend"
MANIFEST = SOURCE.with_suffix(".manifest.json")
RENDERS = ROOT / "tools/.local/blender_achievement_icons"
MOTIFS = {
    "victory_milestones": "Golden victory cup with cyan laurel leaves",
    "run_milestones": "Open doorway with an outward arrow",
    "normal_explorer": "Branching route with a compass marker",
    "arena_challenger": "Crossed arena swords over an octagonal ring",
    "infinite_pioneer": "Infinity-shaped portal and ascending steps",
    "deep_push": "Descending staircase inside a stone arch",
    "deck_expander": "Fanned collectible cards with an expansion star",
    "relic_archivist": "Relic display cabinet holding three crystals",
    "starter_collector": "Three differently colored armored helmets",
    "timekeeper_down": "Horned boss helmet split by a sword",
    "arena_victor": "Arena crown resting above crossed blades",
    "comeback_spirit": "A rising phoenix emerging from a broken shield",
    "card_shopper": "Purchased card and two gold coins",
    "relic_shopper": "Golden coin and a suspended faceted relic",
    "master_smith": "Forging hammer, anvil and a bright spark",
    "reward_collector": "Open reward chest with an upward star",
    "event_explorer": "Compass rose over an unfolding scroll",
    "facility_regular": "Workshop house with a gear and repair tool",
    "field_medic": "Medical bag, white cross and healing capsule",
    "card_merchant": "Merchant balance weighing a card against coins",
    "reward_reroller": "A card encircled by opposing reroll arrows",
    "shop_reroller": "Shop awning over a turning inventory carousel",
    "big_spender": "Open treasury with stacked gold coins flowing out",
    "rank_b_milestones": "Bronze B medallion with one blue gemstone",
    "rank_a_milestones": "Silver A medal with two teal gemstones",
    "rank_s_milestones": "Gold S laurel medal with three red gemstones",
    "infinite_score_collector": "Infinity loop, score crystal and three ascending bars",
    "timeline_delayer": "Hourglass and a leftward red time arrow",
    "timeline_accelerator": "Clock and two rightward green time chevrons",
    "cast_breaker": "A severed casting staff with two opposing interruption bolts",
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def crystal(x=0, z=0, scale=1, role="cyan", y=-.2):
    kit.shape("Crystal_Outline", [(x, z+.78*scale), (x+.43*scale, z+.20*scale),
              (x+.30*scale, z-.52*scale), (x, z-.76*scale),
              (x-.30*scale, z-.52*scale), (x-.43*scale, z+.20*scale)], role, y, .28*scale)
    kit.pipe("Crystal_Facet", [(x, z+.65*scale), (x-.12*scale, z+.15*scale),
             (x+.19*scale, z-.46*scale)], .035*scale, "white", y-.20*scale)


def laurel(role="teal", radius=.92, bottom=-.45):
    for side in (-1, 1):
        kit.pipe("Laurel_Stem", [(side*.1, bottom-.43), (side*.65, bottom-.13),
                 (side*.93, bottom+.45), (side*.85, bottom+1.02)], .035, "gold", .05)
        for index in range(4):
            z = bottom + index*.27
            x = side * (.42 + .12*index)
            kit.shape("Laurel_Leaf", [(x, z), (x+side*.33, z+.07),
                      (x+side*.21, z+.29), (x-side*.02, z+.14)], role, -.02, .07)


def infinity(x=0, z=0, scale=1, role="gold", y=-.28):
    kit.pipe("Infinity_Loop", [(x+math.cos(t)*.95*scale, z+math.sin(2*t)*.43*scale)
             for t in [math.tau*i/144 for i in range(145)]], .09*scale, role, y)


def chest(role="steel", open_lid=True):
    kit.box("Chest_Body", 0, -.39, 1.42, .83, role, .03, .55, .06)
    for x in (-.49, .49): kit.box("Chest_Band", x, -.39, .15, .86, "gold", -.29, .08)
    lid = kit.box("Raised_Chest_Lid", 0, .19 if open_lid else .05, 1.5, .33, role, .19, .65)
    if open_lid: lid.rotation_euler.x = -.65
    kit.box("Chest_Lock", 0, -.22, .23, .28, "gold", -.35, .11)


def helmet(x, z, scale, role, horns=False):
    kit.shape("Helmet_Shell", [(x-.51*scale, z-.39*scale), (x-.57*scale, z+.26*scale),
              (x-.30*scale, z+.60*scale), (x+.30*scale, z+.60*scale),
              (x+.57*scale, z+.26*scale), (x+.51*scale, z-.39*scale),
              (x, z-.61*scale)], role, 0, .35*scale)
    kit.box("Helmet_Visor", x, z+.12*scale, .81*scale, .18*scale, "iron", -.23*scale, .10*scale)
    for side in (-1, 1):
        kit.box("Glowing_Eye", x+side*.23*scale, z+.14*scale, .22*scale, .07*scale, "cyan", -.30*scale, .04)
        if horns:
            kit.shape("Boss_Horn", [(x+side*.4*scale, z+.35*scale), (x+side*.83*scale, z+.94*scale),
                      (x+side*.87*scale, z+.43*scale), (x+side*.55*scale, z+.05*scale)], "gold", .1, .15)


def rank_badge(letter):
    role = {"B": "bronze", "A": "silver", "S": "gold"}[letter]
    kit.disc("Medal_Recess", 0, .08, .79, "iron", .04, .22)
    kit.ring("Medal_Rim", 0, .08, .82, role, -.08, .105)
    for side in (-1, 1):
        kit.shape("Medal_Ribbon", [(side*.12, -.42), (side*.67, -.50), (side*.73, -1.05),
                  (side*.38, -.87), (side*.16, -1.07)], "cyan" if letter == "B" else "teal" if letter == "A" else "red", .15, .12)
    if letter == "B":
        kit.pipe("Rank_B", [(-.22, -.39), (-.22, .52), (.08, .52), (.31, .36),
                 (.20, .10), (-.20, .08), (.16, .08), (.34, -.15), (.19, -.38), (-.22, -.39)], .07, role, -.24)
    elif letter == "A":
        kit.pipe("Rank_A", [(-.36, -.38), (0, .54), (.36, -.38)], .075, role, -.24)
        kit.pipe("Rank_A_Bar", [(-.21, -.06), (.21, -.06)], .065, role, -.24)
    else:
        kit.pipe("Rank_S", [(.31, .40), (.10, .57), (-.22, .43), (-.30, .19),
                 (.23, -.02), (.31, -.25), (.13, -.43), (-.19, -.43), (-.34, -.27)], .075, role, -.24)
        laurel("gold", bottom=-.38)
    count = {"B": 1, "A": 2, "S": 3}[letter]
    for index in range(count):
        kit.disc("Rank_Gem", (index-(count-1)/2)*.30, .87, .09, "cyan" if letter == "B" else "teal" if letter == "A" else "red", -.15)


def build(icon):
    b, p, s, d, r, a = kit.box, kit.pipe, kit.shape, kit.disc, kit.ring, kit.arrow
    if icon == "victory_milestones":
        laurel()
        s("Cup", [(-.53,.83),(.53,.83),(.39,.11),(0,-.17),(-.39,.11)], "gold", -.12, .34)
        for side in (-1,1): p("Cup_Handle", [(side*.49,.66),(side*.83,.57),(side*.72,.13),(side*.37,.04)], .075,"gold",-.1)
        b("Stem",0,-.40,.18,.48,"gold")
        b("Cup_Foot",0,-.73,.75,.16,"steel")
        kit.star("Victory_Star",0,.39,.23,"white",-.34,5)
    elif icon == "run_milestones":
        b("Door_Frame",-.18,.0,1.34,1.96,"steel",.12,.30)
        b("Door_Opening",-.18,.02,1.02,1.66,"iron",-.08,.06)
        door=b("Open_Door",-.65,.02,.60,1.63,"gold",-.28,.16)
        door.rotation_euler.z=-.28
        a("Walk_Through",.32,-.15,1.04,"green","right",-.47)
    elif icon == "normal_explorer":
        p("Branching_Route",[(0,-.94),(0,-.15),(-.77,.40),(-.77,.77)],.09,"steel")
        p("Right_Route",[(0,-.15),(.77,.40),(.77,.77)],.09,"steel")
        for x,z in [(0,-.85),(-.77,.78),(.77,.78)]: d("Route_Node",x,z,.19,"cyan" if x else "gold",-.21)
        kit.star("Chosen_Direction",0,.14,.37,"white",-.35)
    elif icon == "arena_challenger":
        p("Arena_Ring",[(math.sin(t)*.93,math.cos(t)*.93) for t in [math.tau*i/8 for i in range(9)]],.065,"red",.16)
        kit.blade("Left_Blade",-.65,"white",-.16,0,.86,-.12)
        kit.blade("Right_Blade",.65,"steel",.16,0,.86,-.20)
    elif icon == "infinite_pioneer":
        infinity(z=.35,scale=.92,role="cyan")
        for index in range(3): b("Portal_Step",-.54+index*.54,-.82+index*.17,.51,.18+index*.14,"steel",.02,.4)
        kit.star("Portal_Destination",0,.35,.23,"white",-.42)
    elif icon == "deep_push":
        p("Dungeon_Arch",[(-.94,-.96),(-.94,.46),(-.55,.93),(.55,.93),(.94,.46),(.94,-.96)],.13,"steel",.15)
        for index in range(4): b("Descending_Step",-.51+index*.35,.32-index*.34,.47,.19,"gold",-.08-index*.025,.34)
        a("Descent",-.45,-.66,.48,"cyan","down",-.38)
    elif icon == "deck_expander":
        for index,role in enumerate(["steel","gold","cyan"]): kit.card((index-1)*.47,.12*(index%2),role,y=-index*.14,scale=.98)
        kit.star("Deck_Expansion",.57,.72,.32,"white",-.55,5)
    elif icon == "relic_archivist":
        b("Cabinet",0,0,1.80,1.89,"steel",.18,.33)
        b("Cabinet_Recess",0,0,1.57,1.63,"iron",-.03,.08)
        for x,z,role in [(-.43,.38,"cyan"),(.43,.38,"red"),(0,-.44,"gold")]: crystal(x,z,.46,role,-.19)
        b("Display_Shelf",0,-.03,1.57,.10,"gold",-.26,.17)
    elif icon == "starter_collector":
        for x,z,scale,role in [(-.65,-.21,.64,"steel"),(.65,-.21,.64,"gold"),(0,.32,.88,"cyan")]: helmet(x,z,scale,role)
    elif icon == "timekeeper_down":
        helmet(0,0,1.07,"red",True)
        kit.blade("Boss_Slayer",-.55,"white",0,-.13,1.03,-.43)
    elif icon == "arena_victor":
        kit.blade("Prize_Blade_Left",-.8,"steel",-.15,-.28,.66,.08)
        kit.blade("Prize_Blade_Right",.8,"white",.15,-.28,.66,.02)
        kit.crown()
    elif icon == "comeback_spirit":
        kit.shield("steel",True)
        s("Phoenix_Left_Wing",[(0,-.06),(-.98,.41),(-.62,.43),(-.88,.89),(-.31,.61),(0,.40)],"amber",-.31,.14)
        s("Phoenix_Right_Wing",[(0,-.06),(.98,.41),(.62,.43),(.88,.89),(.31,.61),(0,.40)],"gold",-.31,.14)
        p("Phoenix_Neck",[(0,-.15),(0,.47),(.18,.68),(.37,.61)],.10,"white",-.42)
    elif icon == "card_shopper":
        kit.card(-.28,.16,"cyan",scale=1.18)
        kit.coin(.57,-.43,.75,-.26)
        kit.coin(.68,.23,.48,-.12)
    elif icon == "relic_shopper":
        r("Relic_Cage",.22,.14,.75,"steel",.11,.045)
        crystal(.22,.21,.9,"teal")
        kit.coin(-.62,-.58,.70,-.38)
    elif icon == "master_smith":
        s("Anvil",[(-.95,-.22),(.63,-.22),(.99,-.40),(.50,-.57),(.31,-.57),(.42,-.91),(-.51,-.91),(-.41,-.57),(-.65,-.44)],"steel",.03,.45)
        p("Hammer_Handle",[(-.23,.14),(.57,.88)],.10,"gold",-.18)
        hammer=b("Hammer_Head",.53,.73,.79,.34,"iron",-.19,.37)
        hammer.rotation_euler.y=-.75
        kit.star("Forging_Spark",-.40,.33,.32,"amber",-.36)
    elif icon == "reward_collector":
        chest("cyan")
        kit.star("Reward_Star",0,.66,.58,"gold",-.30,5)
    elif icon == "event_explorer":
        b("Scroll_Page",0,-.09,1.51,1.66,"white",.08,.10)
        for z in (-.93,.74): b("Scroll_Roller",0,z,1.73,.16,"gold",-.04,.23)
        r("Compass_Rim",0,.02,.62,"steel",-.22,.06)
        s("Compass_North",[(0,.61),(.19,.03),(0,-.42),(-.19,.03)],"red",-.32)
        s("Compass_South",[(0,-.47),(.12,.01),(0,.22),(-.12,.01)],"cyan",-.43)
    elif icon == "facility_regular":
        s("Workshop_Roof",[(-1,.28),(0,.97),(1,.28),(.79,.09),(0,.64),(-.79,.09)],"gold",0,.22)
        b("Workshop_Wall",0,-.30,1.52,1.03,"steel",.08,.36)
        r("Repair_Gear",.2,-.26,.42,"cyan",-.22,.10)
        for index in range(8):
            angle=math.tau*index/8
            tooth=b("Gear_Tooth",.2+math.sin(angle)*.47,-.26+math.cos(angle)*.47,.16,.19,"cyan",-.22)
            tooth.rotation_euler.y=angle
        p("Repair_Spanner",[(-.68,-.67),(-.34,-.19)],.09,"white",-.45)
    elif icon == "field_medic":
        b("Medical_Bag",0,-.14,1.74,1.34,"teal",.02,.45,.12)
        p("Medical_Handle",[(-.39,.53),(-.39,.91),(.39,.91),(.39,.53)],.10,"steel",.03)
        b("Cross_Vertical",0,-.12,.22,.81,"white",-.29,.08)
        b("Cross_Horizontal",0,-.12,.81,.22,"white",-.29,.08)
        p("Healing_Capsule",[(.70,-.68),(.91,-.36)],.12,"red",-.31)
    elif icon == "card_merchant":
        b("Balance_Post",0,-.16,.16,1.57,"steel",.08,.26)
        b("Balance_Foot",0,-.92,1.25,.17,"gold",.04,.35)
        p("Balance_Beam",[(-.86,.53),(0,.67),(.86,.53)],.075,"gold",-.12)
        for side in (-1,1):
            p("Scale_Cords",[(side*.79,.52),(side*.99,-.27),(side*.44,-.27),(side*.79,.52)],.027,"white",-.14)
            b("Scale_Pan",side*.73,-.29,.65,.10,"steel",-.16,.24)
        kit.card(-.70,.02,"cyan",y=-.25,scale=.43)
        kit.coin(.71,.04,.43,-.24)
    elif icon == "reward_reroller":
        kit.card(0,0,"cyan",scale=1.09)
        for side in (-1,1):
            r("Reward_Cycle",0,0,.99,"gold",-.26,.07,start=.25+(math.pi if side<0 else 0),end=2.75+(math.pi if side<0 else 0))
            a("Reward_Cycle_Tip",side*.77,side*.54,.43,"white","down" if side>0 else "up",-.34)
    elif icon == "shop_reroller":
        b("Shop_Counter",0,-.42,1.48,.65,"steel",.14,.38)
        for index in range(5): b("Awning_Stripe",-.72+index*.36,.52,.35,.57,"red" if index%2==0 else "white",-.05,.25)
        r("Stock_Carousel",0,-.38,.55,"gold",-.26,.08,start=.3,end=5.6)
        a("Stock_Turn",-.44,-.70,.48,"green","up",-.40)
    elif icon == "big_spender":
        chest("gold")
        for x,z,scale,y in [(-.52,.20,.49,-.30),(.16,.31,.59,-.28),(.65,-.42,.64,-.43),(.38,-.80,.49,-.56)]: kit.coin(x,z,scale,y)
    elif icon.startswith("rank_"):
        rank_badge(icon[5].upper())
    elif icon == "infinite_score_collector":
        for index in range(3): b("Score_Column",-.62+index*.62,-.66+index*.17,.33,.38+index*.33,"steel",.13,.28)
        crystal(0,.17,.76,"cyan",-.15)
        infinity(z=.13,scale=.93,role="gold",y=-.45)
    elif icon == "timeline_delayer":
        for z in (-.86,.86): b("Hourglass_Brace",-.25,z,1.2,.15,"gold",.08,.28)
        s("Hourglass_Glass",[(-.77,.69),(.27,.69),(-.13,0),(.27,-.69),(-.77,-.69),(-.37,0)],"cyan",0,.22)
        s("Falling_Sand",[(-.59,-.56),(.09,-.56),(-.25,-.14)],"white",-.17,.07)
        a("Delay_Left",.40,-.06,.99,"red","left",-.36)
    elif icon == "timeline_accelerator":
        kit.clock(-.25,.12,.95)
        for z in (-.41,-.76): a("Advance_Right",.33,z,.92,"green","right",-.34)
    elif icon == "cast_breaker":
        p("Broken_Staff_Lower",[(-.53,-.95),(-.12,-.25)],.095,"steel",-.12)
        p("Broken_Staff_Upper",[(.15,.28),(.53,.95)],.095,"gold",-.12)
        crystal(.59,.83,.30,"cyan",-.16)
        for side in (-1,1):
            s("Interruption_Bolt",[(side*.98,side*.32),(side*.47,side*.22),(side*.70,side*.02),(side*.11,-side*.08),(side*.40,side*.34)],"red",-.32,.13)
        kit.star("Cast_Fracture",0,0,.29,"white",-.4)
    else:
        raise ValueError("No achievement sculpture: " + icon)


def validate_source():
    meta = json.loads(MANIFEST.read_text(encoding="utf-8"))
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    assert sha(SOURCE) == meta["source_sha256"]
    for entry in meta["assets"]:
        collection = bpy.data.collections[entry["source_collection"]]
        assert collection["achievement_id"] == entry["visual_id"]
        assert len(collection.objects) == entry["objects"]
        assert any(obj.type in ("MESH", "CURVE") for obj in collection.objects)
        assert not any(obj.type == "FONT" for obj in collection.objects)
    print("ACHIEVEMENT_ICON_SOURCE_REOPEN_OK", len(meta["assets"]), flush=True)


def main():
    if "--validate-only" in sys.argv:
        validate_source()
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    SOURCE.parent.mkdir(parents=True, exist_ok=True)
    RENDERS.mkdir(parents=True, exist_ok=True)
    kit.materials()
    for name,color in [("bronze",(.72,.36,.12)),("silver",(.70,.85,.95))]:
        mat=bpy.data.materials.new("QQ_Achievement_"+name)
        mat.use_nodes=True
        shader=next(node for node in mat.node_tree.nodes if node.type=="BSDF_PRINCIPLED")
        shader.inputs["Base Color"].default_value=(*color,1)
        shader.inputs["Metallic"].default_value=.7
        shader.inputs["Roughness"].default_value=.28
        kit.MATERIALS[name]=mat
    kit.render_rig()
    scene=bpy.context.scene
    scene.render.resolution_x=scene.render.resolution_y=1024
    scene.cycles.samples=24
    scene.camera.data.ortho_scale=2.78
    ids=[entry["id"] for entry in json.loads((ROOT/"data/achievements.json").read_text(encoding="utf-8")) if entry["id"] in MOTIFS]
    assert set(ids)==set(MOTIFS), "Update sculptures when adding an achievement"
    collections,entries=[],[]
    for icon in ids:
        kit.CURRENT=bpy.data.collections.new("achievement_"+icon)
        scene.collection.children.link(kit.CURRENT)
        kit.CURRENT["achievement_id"]=icon
        kit.CURRENT["motif"]=MOTIFS[icon]
        build(icon)
        kit.CURRENT.asset_mark()
        collections.append(kit.CURRENT)
        entries.append({"asset_id":"achievement_"+icon,"visual_id":icon,"category":"achievement",
                        "size":128,"runtime_path":f"assets/icons/achievements/{icon}.png",
                        "source_path":kit.rel(SOURCE),"source_collection":kit.CURRENT.name,
                        "source_render_size":[1024,1024],"presentation":"transparent_3d_sculpture",
                        "motif":MOTIFS[icon],"objects":len(kit.CURRENT.objects)})
    for entry,collection in zip(entries,collections):
        for other in collections: other.hide_render=other!=collection
        path=RENDERS/(entry["visual_id"]+".png")
        scene.render.filepath=str(path)
        bpy.ops.render.render(write_still=True)
        entry["render_path"],entry["render_sha256"]=kit.rel(path),sha(path)
        print("ACHIEVEMENT_ICON_RENDER_OK",entry["visual_id"],flush=True)
    for collection in collections:
        collection.hide_render=collection.hide_viewport=collection!=collections[0]
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE),compress=True)
    meta={"batch_id":"blender_achievement_icons_08","blender_version":bpy.app.version_string,
          "generator":kit.rel(Path(__file__)),"generator_sha256":{kit.rel(path):sha(path) for path in [Path(__file__),Path(kit.__file__)]},
          "source":kit.rel(SOURCE),"source_sha256":sha(SOURCE),"assets":entries}
    MANIFEST.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+"\n",encoding="utf-8",newline="\n")
    print("ACHIEVEMENT_ICONS_BUILD_OK",len(entries),flush=True)


if __name__=="__main__":
    main()
