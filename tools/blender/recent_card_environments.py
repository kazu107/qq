"""Illustrated 3D environments for recent card art, not a display plinth."""
import hashlib
import math
import random
import bpy

FAMILIES = {
    "reserve_focus": "courtyard", "reserve_shield": "fortress", "reserve_siphon": "infirmary",
    "reserve_reload": "workshop", "reserve_status": "infirmary", "reserve_chain": "fortress",
    "reserve_growth": "greenhouse", "reserve_tempo": "time_vault", "reserve_weaken": "corrupted_lab",
    "reserve_shield_jam": "fortress", "reserve_heal_jam": "corrupted_lab", "reserve_recast_jam": "time_vault",
    "reserve_recoil": "workshop", "reserve_time_mine": "courtyard", "reserve_wear": "workshop",
    "reserve_mirror": "time_vault", "reserve_swift_commit": "time_vault", "reserve_heavy_commit": "workshop",
    "regen_patch": "infirmary", "regen_salve": "greenhouse", "regen_barrier": "fortress",
    "regen_emergency": "infirmary", "regen_bloodwrap": "corrupted_lab", "regen_burst": "time_vault",
    "regen_spring": "greenhouse", "regen_tank": "greenhouse",
    "life_conversion": "infirmary", "barrier_conversion": "fortress",
}


def add_environment(b, collection, asset_id):
    family = FAMILIES[asset_id]
    collection["environment_family"] = family
    rng = random.Random(int(hashlib.sha256(asset_id.encode()).hexdigest()[:8], 16))
    prefix = "Env_" + asset_id
    stone = b.make_material(prefix + "Stone", (.075,.105,.12,1), roughness=.85)
    dark = b.make_material(prefix + "Iron", (.035,.055,.07,1), metallic=.55, roughness=.45)
    wood = b.make_material(prefix + "Wood", (.14,.075,.035,1), roughness=.8)
    pale = b.make_material(prefix + "Tile", (.22,.30,.28,1), roughness=.7)
    plant = b.make_material(prefix + "Leaves", (.045,.22,.09,1), roughness=.85)
    gold = b.make_material(prefix + "Copper", (.28,.16,.065,1), metallic=.6, roughness=.4)
    colors = {
        "courtyard": ((.035,.055,.08),(.20,.27,.31)), "fortress": ((.018,.04,.065),(.09,.16,.23)),
        "workshop": ((.025,.035,.045),(.18,.12,.06)), "infirmary": ((.025,.07,.065),(.12,.27,.23)),
        "greenhouse": ((.045,.085,.035),(.19,.29,.12)), "time_vault": ((.035,.035,.065),(.14,.12,.20)),
        "corrupted_lab": ((.035,.015,.025),(.20,.065,.075)),
    }
    import card_action_scenes
    card_action_scenes.backdrop(b, collection, prefix + "Distance", *colors[family])

    def box(name, pos, size, mat=stone, rot=(0,0,0)):
        return b.add_box(collection, prefix+name, pos, size, mat, rotation_degrees=rot, bevel=.035)
    def tube(name, pos, radius, depth, mat=dark, rot=(0,0,0)):
        return b.add_cylinder(collection, prefix+name, pos, radius, depth, mat, rotation_degrees=rot, vertices=24)
    def leaf(name, pos, scale, angle):
        obj=b.add_cone(collection,prefix+name,pos,.17,0,.65,plant,vertices=6,rotation_degrees=(angle,0,angle*.35))
        obj.scale=scale

    # Continue the ground beyond the image so paving never reads as a display base.
    box("ContinuousGround",(0,2,-.48),(18,18,.14),wood if family=="greenhouse" else stone)
    for row in range(4):
        for column in range(5):
            x=(column-2)*1.05; y=.75+row*1.05
            box(f"Floor{row}_{column}",(x,y,-.38+rng.uniform(-.025,.025)),(.98,.98,.14),wood if family=="greenhouse" else stone)

    if family in ["courtyard","fortress"]:
        for side in [-1,1]:
            x=side*1.85
            for level in range(6):
                box(f"Pillar{side}_{level}",(x,2.7,level*.52-.1),(.62,.8,.47),stone,rot=(0,0,rng.uniform(-3,3)))
            box(f"Capital{side}",(x,2.7,2.9),(.86,1,.2),dark)
        if family=="fortress":
            for row in range(5):
                for column in range(5):
                    box(f"Wall{row}_{column}",((column-2)*1.0+(row%2)*.24,3.8,.0+row*.55),(.95,.45,.5),stone)
            for side in [-1,1]:
                box(f"ArrowSlit{side}",(side*1.4,3.49,1.6),(.13,.05,.8),dark)
            box("GateLintel",(0,3.2,2.8),(2.8,.45,.28),gold)
        else:
            for x in [-1.4,.9,1.6]:
                box("PracticePost",(x,2.1,.65),(.17,.17,1.8),wood,rot=(0,rng.uniform(-10,10),0))
                box("PracticeCrossbar",(x,2.1,1.15),(.65,.18,.12),wood)
            for i in range(14):
                box(f"Rubble{i}",(rng.uniform(-2.6,2.6),rng.uniform(1,3.8),-.12),(.18,.25,.25),stone,rot=(rng.uniform(-30,30),rng.uniform(-30,30),rng.uniform(0,180)))

    elif family in ["workshop","corrupted_lab"]:
        box("RearWall",(0,3.85,1.2),(5.6,.2,3.6),dark)
        for x in [-2,-1,0,1,2]: box("WallBrace",(x,3.68,1.2),(.055,.13,3.6),stone)
        for side in [-1,1]:
            box(f"Cabinet{side}",(side*1.8,2.7,.8),(.95,.7,2.35),dark)
            for level in range(4):
                box(f"Drawer{side}_{level}",(side*1.8,2.3,.1+level*.46),(.83,.08,.38),wood if family=="workshop" else stone)
                box(f"Handle{side}_{level}",(side*1.8,2.22,.1+level*.46),(.25,.08,.055),gold)
        box("Bench",(0,2.8,.15),(3.4,1.1,.18),wood)
        for x in [-1.25,1.25]: box("BenchLeg",(x,2.7,-.1),(.16,.7,.65),dark)
        for x in [-2.4,2.2]:
            tube("Pipe",(x,3,1.1),.13,3.2,gold)
            b.add_torus(collection,prefix+"Valve",(x,2.8,1.8),.25,.04,dark,rotation_degrees=(90,0,0))
        for i in range(6):
            x=-1.3+i*.48
            tube("BenchJar",(x,2.4,.55),.12,.5,pale if family=="workshop" else gold)
        if family=="corrupted_lab":
            warning=b.make_material(prefix+"Warning",(.35,.035,.055,1),metallic=.1,roughness=.6)
            for i in range(4): box("HazardStripe",(-1.5+i,3.05,2.45),(.42,.08,.12),warning,rot=(0,-30,0))
            for i in range(5): box("BrokenGlass",(rng.uniform(-1.4,1.4),3.1,rng.uniform(.8,2.3)),(.2,.07,.5),pale,rot=(0,rng.uniform(-35,35),0))
        else:
            for i in range(5):
                x=-1.5+i*.75
                b.add_torus(collection,prefix+"HangingGear",(x,3.5,1.7+(i%2)*.4),.26,.08,gold,rotation_degrees=(90,0,0))
        b.add_area_light(collection,prefix+"WarmLamp",(-1,1.8,3.5),110,(1,.6,.25),2,(0,0,1.2))

    elif family=="infirmary":
        clinical=b.make_material(prefix+"ClinicalWall",(.045,.14,.13,1),roughness=.85)
        box("ClinicalWall",(0,3.85,1.2),(5.6,.2,3.6),clinical)
        box("ClinicWindow",(.25,3.66,1.95),(1.8,.1,1.25),stone)
        for x in [-.65,.25,1.15]: box("WindowBar",(x,3.59,1.95),(.045,.1,1.25),gold)
        box("WindowCrossbar",(.25,3.58,1.95),(1.8,.1,.045),gold)
        for side in [-1,1]:
            box(f"WallFrame{side}",(side*1.9,3.1,1.1),(.15,.25,3.1),dark)
            box(f"Curtain{side}",(side*2.1,3.4,1.2),(.85,.12,3.2),pale)
            for i in range(4): box(f"CurtainFold{side}_{i}",(side*2.1-.3+i*.2,3.3,1.2),(.06,.06,3),stone)
        box("CotFrame",(.1,2.5,.1),(2.8,1,.18),dark)
        box("CotLinen",(.1,2.5,.25),(2.6,.9,.2),pale)
        box("Pillow",(-.85,2.5,.4),(.55,.65,.18),wood)
        for x in [-1.2,1.3]:tube("CotLeg",(x,2.5,-.1),.07,.6,dark)
        for side in [-1,1]:
            tube("InfusionStand",(side*1.45,2,1.1),.04,2.6,dark)
            box("MedicinePack",(side*1.45,2,2.1),(.35,.16,.6),pale)
            b.add_curve(collection,prefix+"InfusionHose",[(side*1.45,1.95,1.8),(side*1.7,1.9,1.2),(side*1.5,1.7,.5)],.018,gold)
        box("CeilingRail",(0,3,2.7),(3.8,.18,.1),gold)
        b.add_area_light(collection,prefix+"ClinicalLight",(0,2,3.2),110,(.5,1,.8),2.5,(0,0,1.2))

    elif family=="greenhouse":
        for i in range(6): leaf(f"RearFoliage{i}",(-2+i*.8,3.9,1.3+(i%2)*.35),(2.0,.7,2.8),rng.uniform(-30,30))
        for depth in [2.1,3.5]:
            for side in [-1,1]:
                box("TrellisPost",(side*1.95,depth,1.2),(.12,.15,3.2),wood)
                box("RoofBrace",(side*1.0,depth,2.75),(2.2,.16,.12),wood,rot=(0,side*18,0))
        for side in [-1,1]:
            box("Planter",(side*1.6,2.7,.25),(.65,2,.45),wood)
            for i in range(7):
                x=side*(1.45+rng.uniform(0,.35));y=1.9+i*.25
                leaf(f"Plant{side}_{i}",(x,y,.8+rng.uniform(0,.35)),(1.2,.5,1.7),rng.uniform(-25,25))
        for i in range(3): box("SunlitSlat",(-1.5+i*1.5,3.8,1.25),(.1,.1,3.3),pale)
        b.add_area_light(collection,prefix+"GardenSun",(-2,2.7,4),150,(1,.85,.5),3,(0,0,1.2))

    elif family=="time_vault":
        for x in [-1.7,1.5]:
            box("ArchivePillar",(x,3.25,1.1),(.5,.7,3.4),dark)
            b.add_torus(collection,prefix+"ArchiveDial",(x,2.8,1.7),.7,.08,gold,rotation_degrees=(90,0,0))
            for i in range(12):
                a=i*math.tau/12;box("DialTooth",(x+math.sin(a)*.72,2.77,1.7+math.cos(a)*.72),(.16,.15,.18),gold,rot=(0,i*30,0))
            b.add_curve(collection,prefix+"Pendulum",[(x,2.7,1.6),(x+.25,2.7,.4)],.025,gold)
            tube("PendulumWeight",(x+.25,2.7,.4),.2,.08,gold,rot=(90,0,0))
        box("VaultDoor",(0,3.8,1.25),(2,.25,3.1),stone)
        for i in range(5):box("VaultRib",(-.8+i*.4,3.6,1.25),(.06,.12,2.8),gold)
        b.add_area_light(collection,prefix+"ArchiveLight",(1,2,3.4),100,(.6,.7,1),2.5,(0,0,1.3))
    return family
