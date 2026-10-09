"""Author the QueueQuest meadow, background renders, and optional 3D emblem.

Run in a separate factory-startup Blender process, never through live MCP.
The editable originals are saved before disposable runtime mesh consolidation.
No project, runtime code, SVG, or central provenance files are changed here.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import struct
import sys
from collections import defaultdict
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art_src/blender/environment/qq_battlefield.blend"
MANIFEST = SOURCE.with_suffix(".manifest.json")
MODEL = ROOT / "assets/models/environment/qq_battlefield.glb"
PREVIEW = ROOT / "art_src/blender/previews/environment_batch.png"
EMBLEM_PREVIEW = ROOT / "art_src/blender/previews/environment_emblem_sizes.png"
INTERMEDIATE = ROOT / "tools/.local/blender_environment_batch"
COUNTS = {
    "grass": 112, "rocks": 18, "flowers": 16, "ruin_clusters": 2,
    "barrels": 2, "crates": 4, "distant_hills": 5,
    "distant_trees": 18, "distant_ruins": 2,
}
SEMANTIC_NODES = (
    "BattleWorldGround", "BattleMeadow", "ArenaBase", "ArenaTiles",
    "ArenaBorders", "ArenaLaneLines", "ArenaCrates", "ArenaBarrels",
    "BattleGrass", "BattleRocks", "BattleFlowers",
    "BattleRuinClusterLeft", "BattleRuinClusterRight", "BattleDistantHills",
    "BattleDistantRidges", "BattleDistantTreeTrunks", "BattleDistantTreeCanopies",
    "BattleDistantRuinLeft", "BattleDistantRuinRight",
)
PALETTE = {
    "world_ground": ((.045, .100, .060, 1), 0, .92),
    "meadow": ((.075, .170, .052, 1), 0, .94),
    "earth": ((.075, .084, .055, 1), 0, .92),
    "tile_a": ((.265, .252, .195, 1), 0, .83),
    "tile_b": ((.205, .216, .160, 1), 0, .86),
    "stone": ((.260, .290, .234, 1), 0, .89),
    "stone_dark": ((.105, .132, .103, 1), 0, .91),
    "stone_light": ((.395, .400, .297, 1), 0, .81),
    "moss": ((.115, .235, .047, 1), 0, .97),
    "brass": ((.430, .285, .092, 1), .62, .47),
    "iron": ((.140, .178, .155, 1), .66, .53),
    "wood": ((.220, .101, .030, 1), 0, .87),
    "wood_light": ((.330, .172, .060, 1), 0, .83),
    "grass": ((.110, .270, .045, 1), 0, .93),
    "grass_light": ((.230, .385, .073, 1), 0, .93),
    "grass_dry": ((.315, .325, .093, 1), 0, .94),
    "hill": ((.070, .182, .115, 1), 0, 1),
    "hill_light": ((.120, .245, .105, 1), 0, 1),
    "leaf": ((.055, .170, .084, 1), 0, .98),
    "leaf_light": ((.110, .250, .090, 1), 0, .98),
    "petal": ((.830, .435, .090, 1), 0, .72),
    "petal_ivory": ((.780, .730, .440, 1), 0, .74),
    "flower_core": ((.210, .092, .028, 1), 0, .9),
    "cyan": ((.025, .410, .640, 1), .15, .43),
    "red": ((.620, .060, .025, 1), .1, .48),
    "ivory": ((.680, .650, .530, 1), .1, .48),
    "gold": ((.800, .485, .140, 1), .7, .37),
    "navy": ((.005, .013, .021, 1), .10, .85),
}
MATERIALS = {}
GROUPS = {}
SOURCE_OBJECTS = []
SOURCE_COLLECTION = None
EMBLEM_COLLECTION = None
RIG_COLLECTION = None
RNG = random.Random(0x51425A)


def relative(path):
    return str(path.relative_to(ROOT)).replace("\\", "/")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def g(value):
    """Godot Y-up coordinates become Blender Z-up; glTF restores Y-up."""
    return Vector((value[0], -value[2], value[1]))


def collection(name):
    result = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(result)
    return result


def empty(name, owner, parent=None, location=(0, 0, 0)):
    result = bpy.data.objects.new(name, None)
    owner.objects.link(result)
    result.parent = parent
    result.location = g(location)
    return result


def material(role):
    color, metallic, roughness = PALETTE[role]
    result = bpy.data.materials.new("QQ_Environment_" + role)
    result.diffuse_color = color
    result.use_nodes = True
    result.use_backface_culling = role not in ("grass", "grass_light", "grass_dry")
    shader = result.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    if role in ("cyan", "red"):
        shader.inputs["Emission Color"].default_value = color
        shader.inputs["Emission Strength"].default_value = .55
    result["qq_role"] = role
    return result


def mesh_object(name, vertices, faces, role, group, parent=None, smooth=False):
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    SOURCE_COLLECTION.objects.link(obj)
    obj.parent = parent or GROUPS[group]
    obj["qq_group"] = group
    obj["qq_editable_part"] = True
    roles = role if isinstance(role, (tuple, list)) else [role]
    for item in roles:
        mesh.materials.append(MATERIALS[item])
    for polygon in mesh.polygons:
        polygon.use_smooth = smooth
    SOURCE_OBJECTS.append(obj)
    return obj


def box(name, position, size, role, group, parent=None, bevel=.015, yaw=0):
    x, y, z = size[0] / 2, size[2] / 2, size[1] / 2
    vertices = [(-x,-y,-z), (x,-y,-z), (x,y,-z), (-x,y,-z),
                (-x,-y,z), (x,-y,z), (x,y,z), (-x,y,z)]
    faces = [(3,2,1,0), (4,5,6,7), (0,1,5,4), (1,2,6,5), (2,3,7,6), (3,0,4,7)]
    obj = mesh_object(name, vertices, faces, role, group, parent)
    obj.location = g(position)
    obj.rotation_euler.z = yaw
    if bevel > 0:
        modifier = obj.modifiers.new("Editable_edge_bevel", "BEVEL")
        modifier.width = min(bevel, min(size) * .24)
        modifier.segments = 2
    return obj


def cylinder(name, position, radius, height, role, group, parent=None, sides=12, top=None):
    top = radius if top is None else top
    vertices = []
    for r, z in ((radius, -height/2), (top, height/2)):
        vertices += [(math.cos(i*math.tau/sides)*r, math.sin(i*math.tau/sides)*r, z) for i in range(sides)]
    faces = [tuple(range(sides-1, -1, -1)), tuple(range(sides, sides*2))]
    faces += [(i, (i+1)%sides, (i+1)%sides+sides, i+sides) for i in range(sides)]
    obj = mesh_object(name, vertices, faces, role, group, parent)
    obj.location = g(position)
    return obj


def rod(name, start, end, radius, role, group, parent=None, sides=8, top=None):
    a, b = g(start), g(end)
    obj = cylinder(name, (0,0,0), radius, (a-b).length, role, group, parent, sides, top)
    obj.location = (a+b)/2
    obj.rotation_euler = (b-a).to_track_quat("Z", "Y").to_euler()
    return obj


def ring(name, position, radius, tube, role, group, parent=None, segments=32, cross=6):
    vertices, faces = [], []
    for i in range(segments):
        a = math.tau*i/segments
        for j in range(cross):
            b = math.tau*j/cross
            r = radius + tube*math.cos(b)
            vertices.append((r*math.cos(a), r*math.sin(a), tube*math.sin(b)))
    for i in range(segments):
        for j in range(cross):
            faces.append((i*cross+j, ((i+1)%segments)*cross+j,
                          ((i+1)%segments)*cross+(j+1)%cross, i*cross+(j+1)%cross))
    obj = mesh_object(name, vertices, faces, role, group, parent, smooth=True)
    obj.location = g(position)
    return obj


def ico(name, position, scale, role, group, parent=None, subdivision=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivision, radius=1)
    obj = bpy.context.object
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    SOURCE_COLLECTION.objects.link(obj)
    obj.name = name
    obj.parent = parent or GROUPS[group]
    obj.location = g(position)
    obj.scale = (scale[0], scale[2], scale[1])
    obj.data.materials.append(MATERIALS[role])
    obj["qq_group"] = group
    obj["qq_editable_part"] = True
    SOURCE_OBJECTS.append(obj)
    return obj


def instance(name, kind, group, position, yaw=0, scale=1):
    obj = empty(name, SOURCE_COLLECTION, GROUPS[group], position)
    obj.rotation_euler.z = yaw
    obj.scale = (scale,) * 3
    obj["qq_detail_kind"] = kind
    obj["qq_group"] = group
    return obj


def grass_clump(index, x, z):
    group = "BattleGrass"
    root = instance(f"GrassClump_{index:03}", "grass", group, (x,-.13,z),
                    RNG.uniform(-math.pi, math.pi), RNG.uniform(.8,1.25))
    vertices, faces, roles = [], [], []
    for blade in range(22):
        a = RNG.uniform(0,math.tau)
        x0,z0 = RNG.uniform(-.16,.16),RNG.uniform(-.16,.16)
        h,w = RNG.uniform(.23,.58), RNG.uniform(.018,.036)
        lean = RNG.uniform(.065,.16)
        dx,dz = math.cos(a),math.sin(a)
        wx,wz = -dz*w,dx*w
        points = [(x0-wx,0,z0-wz),(x0+wx,0,z0+wz),
                  (x0+lean*.30-wx*.55,h*.58,z0+lean*.30-wz*.55),
                  (x0+lean*.30+wx*.55,h*.58,z0+lean*.30+wz*.55),
                  (x0+dx*lean,h,z0+dz*lean)]
        offset = len(vertices)
        vertices += [tuple(g(p)) for p in points]
        front = [(0,1,3,2),(2,3,4)]
        for face in front:
            faces.append(tuple(offset+i for i in face))
            roles.append(blade%3)
    obj = mesh_object("GrassBlades", vertices, faces, ("grass","grass_light","grass_dry"),group,root)
    for polygon, role in zip(obj.data.polygons, roles):
        polygon.material_index = role


def flower(index, x, z):
    group = "BattleFlowers"
    root = instance(f"Wildflower_{index:02}","flowers",group,(x,-.12,z), RNG.uniform(0,math.tau))
    height = RNG.uniform(.25,.40)
    rod("FlowerStem", (0,0,0), (.025,height,0), .012,"grass",group,root,6)
    ico("FlowerLeaf",(.075,height*.45,0),(.115,.020,.036),"grass",group,root,1)
    for petal in range(5):
        a = math.tau*petal/5
        obj=ico("FlowerPetal",(.025+math.cos(a)*.065,height,math.sin(a)*.065),
                (.068,.020,.038),"petal" if index%3 else "petal_ivory",group,root,1)
        obj.rotation_euler.z=-a
    ico("FlowerPollen",(.025,height+.018,0),(.028,.026,.028),"flower_core",group,root,1)


def build_floor():
    box("WorldGround",(0,-.66,-8),(42,.55,38),"world_ground","BattleWorldGround",bevel=0)
    box("MeadowTop",(0,-.38,-.1),(17.8,.42,11.8),"meadow","BattleMeadow",bevel=.08)
    box("Foundation",(0,-.16,0),(13.5,.22,8.5),"earth","ArenaBase",bevel=.075)
    for row in range(5):
        for col in range(7):
            x,z=(col-3)*1.76,(row-2)*1.44
            top=.006+((col*3+row)%3)*.007
            tile=box(f"ArenaTile_{col}_{row}",(x,top,z),(1.61,.105,1.29),
                     "tile_a" if (col+row)%2==0 else "tile_b","ArenaTiles",bevel=.025,
                     yaw=((col*5+row*3)%5-2)*.004)
            tile["grid_column"],tile["grid_row"]=col,row
            # Thin recessed-looking dark seams and engraved corner marks avoid
            # geometry on the actors' flat standing areas.
            if (row+col)%4==0:
                for seam in range(2):
                    box("TileHairline",(x-.55+seam*.29,top+.053,z+.21-seam*.12),
                        (.33,.002,.009),"stone_dark","ArenaTiles",bevel=0,yaw=.42-seam*.65)
            if col in (0,6) and row in (0,4):
                ornament=ring("CornerRune",(x,top+.057,z),.245,.009,"brass","ArenaTiles",segments=24,cross=4)
                ornament["qq_carving"]="chronometer corner seal"
                for tick in range(8):
                    a=tick*math.tau/8
                    box("CornerRuneTick",(x+math.cos(a)*.245,top+.058,z+math.sin(a)*.245),
                        (.04,.003,.013),"brass","ArenaTiles",bevel=0,yaw=-a)
    for side in (-1,1):
        box("ArenaBorderLong",(0,.10,side*3.58),(13.25,.055,.085),"brass","ArenaBorders",bevel=.013)
        box("ArenaBorderShort",(side*6.2,.10,0),(.085,.055,7.12),"brass","ArenaBorders",bevel=.013)
        box("EdgeMoss",(0,.115,side*3.45),(12.9,.035,.15),"moss","ArenaBorders",bevel=.006)
    box("PlayerLaneGlow",(.88,.08,0),(.075,.025,6.92),"cyan","ArenaLaneLines",bevel=.009)
    box("EnemyLaneGlow",(-.88,.08,0),(.075,.025,6.92),"red","ArenaLaneLines",bevel=.009)
    box("CenterDivider",(0,.085,0),(10.62,.028,.055),"ivory","ArenaLaneLines",bevel=.006)


def build_crate(index, position, size, yaw):
    group="ArenaCrates"
    root=instance(f"Crate_{index:02}","crates",group,position,yaw)
    w,h,d=size
    box("CrateShell",(0,0,0),(w,h,d),"wood",group,root,bevel=.012)
    for side in (-1,1):
        for plank in range(5):
            box("CrateFacePlank",((plank-2)*w/5,0,side*d*.505),
                (w/5-.012,h*.87,.027),"wood_light" if plank%2 else "wood",group,root,bevel=.004)
        for rail in (-1,1):
            box("CrateFrameRail",(0,rail*h*.40,side*d*.535),(w*.96,.085,.044),"wood_light",group,root,bevel=.009)
            box("CrateUpright",(rail*w*.42,0,side*d*.535),(.074,h*.95,.044),"wood_light",group,root,bevel=.008)
        rod("CrateDiagonal",(-w*.35,-h*.32,side*d*.55),(w*.35,h*.32,side*d*.55),.034,"wood_light",group,root,4)
        for x in (-w*.41,w*.41):
            for y in (-h*.40,h*.40):
                rivet=cylinder("CrateNail",(x,y,side*d*.563),.017,.011,"iron",group,root,8)
                rivet.rotation_euler.x=math.pi/2
        box("CrateCornerIron",(side*w*.46,0,0),(.032,h*.99,d*.99),"iron",group,root,bevel=.004)
    for plank in range(5):
        box("CrateLidPlank",((plank-2)*w/5,h*.506,0),(w/5-.012,.022,d*.96),"wood_light" if plank%2 else "wood",group,root,bevel=.003)


def build_barrel(index, position):
    group="ArenaBarrels"
    root=instance(f"Barrel_{index:02}","barrels",group,position)
    sides=14
    for stave in range(sides):
        a=math.tau*stave/sides
        half=math.pi/sides*.94
        vertices=[]
        for height,radius in ((-.41,.30),(-.27,.345),(0,.373),(.27,.345),(.41,.30)):
            for offset in (-half,half):
                vertices.append((math.cos(a+offset)*radius, math.sin(a+offset)*radius,height))
        faces=[(i*2,i*2+1,i*2+3,i*2+2) for i in range(4)]
        obj=mesh_object("BarrelCurvedStave",vertices,faces,"wood_light" if stave%3 else "wood",group,root)
        obj["construction"]="separate tapered stave"
    cylinder("BarrelLid",(0,.408,0),.292,.027,"wood_light",group,root,14)
    for strip in (-1,0,1):
        box("BarrelLidSeam",(0,.423,strip*.105),(.54,.001,.008),"wood",group,root,bevel=0)
    cylinder("BarrelBung",(.11,.433,.04),.045,.022,"wood",group,root,10)
    for y,r in ((-.27,.350),(.27,.350)):
        ring("BarrelIronHoop",(0,y,0),r,.026,"iron",group,root,segments=28,cross=4)
        for bolt in range(7):
            a=bolt*math.tau/7
            ico("HoopRivet",(math.cos(a)*(r+.021),y,math.sin(a)*(r+.021)),(.015,.015,.015),"iron",group,root,1)


def chrono_dial(root, group, location, radius, distant=False, facing=1):
    disk=cylinder("ChronoDialBacking",location,radius,.045,"stone_dark",group,root,24)
    disk.rotation_euler.x=math.pi/2
    frame=ring("ChronoDialBrass",(location[0],location[1],location[2]+facing*.034),radius,.019,"brass",group,root,32,5)
    frame.rotation_euler.x=math.pi/2
    for tick in range(12):
        a=tick*math.tau/12
        mark=box("ChronoCarvedTick",(location[0]+math.cos(a)*radius*.81,
                 location[1]+math.sin(a)*radius*.81,location[2]+facing*.050),
                 (.028,.086,.011),"brass",group,root,bevel=.003)
        mark.rotation_euler.y=-a+math.pi/2
    role="cyan" if not distant else "brass"
    rod("ChronoHourHand",(location[0],location[1],location[2]+facing*.060),
        (location[0]+radius*.45,location[1]+radius*.35,location[2]+facing*.060),.013,role,group,root,6)
    rod("ChronoMinuteHand",(location[0],location[1],location[2]+facing*.062),
        (location[0]-.08,location[1]+radius*.67,location[2]+facing*.062),.012,role,group,root,6)


def ruin(side, distant=False):
    group=("BattleDistantRuin" if distant else "BattleRuinCluster")+("Left" if side<0 else "Right")
    position=(side*10.2,-.10,-13.5 if side<0 else -13.8) if distant else (side*6.035,0,-3.835)
    root=instance(group+"_Assembly","distant_ruins" if distant else "ruin_clusters",group,position,
                  side*.06 if distant else (-.12 if side<0 else math.pi+.10))
    if distant:
        for column in (-1,1):
            for course in range(6):
                box("GateMasonry",(column*1.18, .20+course*.42,0),(.72,.39,.73),
                    "stone" if course%2 else "stone_light",group,root,bevel=.029,
                    yaw=(course%2)*.015)
            box("GateFoot",(column*1.18,.07,0),(.90,.14,.92),"stone_dark",group,root,bevel=.028)
            for ring_y in (.51,1.44,2.25):
                box("GateCourseTrim",(column*1.18,ring_y,0),(.78,.075,.78),"stone_dark",group,root,bevel=.011)
        for segment in range(7):
            box("BrokenGateLintel",((segment-3)*.42,2.65+(segment%3)*.018,0),(.43,.44,.77),
                "stone_light",group,root,bevel=.025,yaw=(segment%3-1)*.014)
        chrono_dial(root,group,(0,2.61,.43),.31,True)
        for block in range(5):
            box("GateFallenBlock",(RNG.uniform(-1.8,1.8),.03,RNG.uniform(-.7,.7)),
                (.38,.23,.35),"stone_dark",group,root,bevel=.03,yaw=RNG.uniform(-.5,.5))
    else:
        for course in range(3):
            for brick in range(5-course//2):
                x=-.9+brick*.44+(course%2)*.06
                box("RuinMasonryBlock",(x,.18+course*.34,0),(.43,.32,.36),
                    "stone" if (brick+course)%2 else "stone_light",group,root,bevel=.027,
                    yaw=(brick%3-1)*.015)
        for course in range(5):
            cylinder("RuinPillarDrum",(-1.05,.17+course*.295,-.04),.255,.281,
                "stone",group,root,12,top=.245)
            for flute in range(8):
                a=math.tau*flute/8
                rod("PillarFluting",(-1.05+math.cos(a)*.245,.06+course*.295,-.04+math.sin(a)*.245),
                    (-1.05+math.cos(a)*.245,.28+course*.295,-.04+math.sin(a)*.245),.010,"stone_dark",group,root,4)
        for cap_y in (.02,1.53):
            box("RuinColumnCapital",(-1.05,cap_y,-.04),(.69,.15,.66),"stone_light",group,root,bevel=.025)
            box("PillarCapitalInset",(-1.05,cap_y+.072,-.04),(.57,.039,.54),"stone_dark",group,root,bevel=.008)
        chrono_dial(root,group,(.15,.65,.195),.265)
        chrono_dial(root,group,(.15,.65,-.195),.265,facing=-1)
        for stone in range(5):
            obj=box("RuinBrokenFragment",(.91+stone*.12,.09+stone%2*.10,.20+stone*.08),
                    (.35,.23,.37),"stone_dark",group,root,bevel=.036,yaw=stone*.3)
            obj.rotation_euler.y=stone*.10
        for moss in range(5):
            ico("RuinMossPatch",(-.85+moss*.34,1.04 if moss%2 else .14,-.20),
                (.16,.023,.064),"moss",group,root,1)
        for cut in range(3):
            rod("MasonryHairline",(-.7+cut*.48,.68,-.185),(-.59+cut*.48,.94,-.185),.007,"stone_dark",group,root,4)


def build_tree(index):
    scale=.56+((index*7)%5)*.055
    x,z=-12.75+index*1.50,-10-(index%3)*1.40
    root=instance(f"DistantTree_{index:02}","distant_trees","BattleDistantTreeTrunks",(x,-.11,z),
                  (index*11%13)*.11,scale)
    cylinder("TreeTrunk",(0,.72,0),.17,1.65,"wood","BattleDistantTreeTrunks",root,9,top=.085)
    for bark in range(5):
        a=bark*math.tau/5
        rod("TrunkBarkRidge",(math.cos(a)*.16,.04,math.sin(a)*.16),
            (math.cos(a+.09)*.086,1.42,math.sin(a+.09)*.086),.014,"wood_light","BattleDistantTreeTrunks",root,5)
        rod("TreeExposedRoot",(math.cos(a)*.05,.18,math.sin(a)*.05),
            (math.cos(a)*.42,0,math.sin(a)*.42),.08,"wood","BattleDistantTreeTrunks",root,7,top=.012)
    for branch in range(3):
        a=branch*math.tau/3+index*.1
        rod("TreeBranch",(0,.8+branch*.12,0),(.50*math.cos(a),1.42+branch*.14,.5*math.sin(a)),
            .067,"wood","BattleDistantTreeTrunks",root,7,top=.028)
    for leaf in range(4):
        a=leaf*math.tau/3
        pos=(x+math.cos(a)*.30*scale,(-.11+(1.66+leaf*.22)*scale),z+math.sin(a)*.30*scale)
        canopy=ico("TreeCanopy",pos,(.78*scale,.67*scale,.73*scale),
                   "leaf" if leaf%2 else "leaf_light","BattleDistantTreeCanopies",subdivision=2)
        canopy["tree_id"]=index


def build_scenery():
    for index in range(112):
        side=index%4
        x,z=RNG.uniform(-8.45,8.45),RNG.uniform(-5.35,5.25)
        if side==0: x=RNG.uniform(-8.45,-6.42)
        elif side==1: x=RNG.uniform(6.42,8.45)
        elif side==2: z=RNG.uniform(-5.35,-3.66)
        else: z=RNG.uniform(3.66,5.25)
        grass_clump(index,x,z)
    for index in range(18):
        x=(-1 if index%2==0 else 1)*RNG.uniform(6.48,8.05)
        z=RNG.uniform(-4.85,4.72)
        root=instance(f"MeadowRock_{index:02}","rocks","BattleRocks",(x,-.03,z),RNG.uniform(0,math.tau))
        sx,sy,sz=RNG.uniform(.28,.58),RNG.uniform(.17,.37),RNG.uniform(.30,.57)
        ico("WeatheredRock",(0,0,0),(sx,sy,sz),"stone_dark","BattleRocks",root,2)
        ico("RockMoss",(.07,sy*.72,.03),(sx*.73,.035,sz*.64),"moss","BattleRocks",root,1)
    for index in range(16):
        flower(index,(-1 if index%2==0 else 1)*RNG.uniform(6.55,8.12),RNG.uniform(-4.72,4.55))
    hill_positions=[(-13,.42,-15.8),(-6.8,.28,-14.5),(0,.50,-17.2),(7,.32,-14.8),(13,.44,-16.2)]
    hill_sizes=[(7,2.35,3.8),(5.2,1.85,3.2),(7.6,2.65,4.2),(5.7,1.95,3.3),(6.8,2.4,3.9)]
    for i,(pos,scale) in enumerate(zip(hill_positions,hill_sizes)):
        root=instance(f"DistantHill_{i:02}","distant_hills","BattleDistantHills",pos)
        ico("MeadowHill",(0,0,0),scale,"hill","BattleDistantHills",root,3)
    for i,(pos,scale) in enumerate([((-9.5,.18,-12.2),(4.8,1.45,2.9)),((9.8,.16,-12.4),(4.4,1.35,2.7))]):
        ico(f"DistantRidge_{i}",pos,scale,"hill_light","BattleDistantRidges",subdivision=2)
    for i in range(18): build_tree(i)
    for side in (-1,1):
        ruin(side)
        ruin(side,True)
    crates=[((-5.55,.43,-4.05),(.92,.86,.78)),((-4.72,.31,-4.28),(.62,.58,.56)),
            ((5.48,.42,-4.08),(.84,.84,.72)),((4.70,.29,-4.32),(.58,.54,.52))]
    for i,(position,size) in enumerate(crates):
        build_crate(i,position,size,-.18+i*.21)
    build_barrel(0,(-6.58,.43,-2.74))
    build_barrel(1,(6.50,.43,-2.58))


def build_emblem():
    global SOURCE_COLLECTION
    battlefield_collection=SOURCE_COLLECTION
    SOURCE_COLLECTION=EMBLEM_COLLECTION
    GROUPS["Emblem"]=empty("QueueQuestEmblem",EMBLEM_COLLECTION,location=(100,0,0))
    for i,(position,yaw,role) in enumerate([((.37,0,.30),-.16,"cyan"),((.06,.02,.10),-.075,"ivory"),((-.30,.05,-.16),.075,"gold")]):
        root=empty(f"QueueCard_{i}",EMBLEM_COLLECTION,GROUPS["Emblem"],position)
        root.rotation_euler.z=yaw
        if i==2:
            root.scale=(1.45,)*3
        box("QueueCardMetal",(0,0,0),(.85,.13,1.12),role,"Emblem",root,bevel=.070)
        box("QueueCardInset",(0,.073,0),(.69,.035,.96),"navy","Emblem",root,bevel=.050)
        if i==2:
            symbol=ring("QSymbol",(0,.101,0),.27,.045,"gold","Emblem",root,segments=48,cross=8)
            symbol.scale.y=1.25
            rod("QTail",(.14,.105,.20),(.29,.105,.36),.04,"gold","Emblem",root,10)
        else:
            for mark in (-1,1):
                box("CardCornerNotch",(mark*.215,.095,-.32),(.105,.016,.021),role,"Emblem",root,bevel=.008)
    rod("TimelineRail",(-.95,.04,.98),(1.0,.04,.98),.028,"cyan","Emblem",sides=10)
    for tick in range(3):
        rod("TimelineTick",(.45+tick*.19,.04,.90),(.45+tick*.19,.04,1.06),.016,"ivory","Emblem",sides=8)
    ico("TimelineNow",(-.82,.04,.98),(.080,.045,.080),"gold","Emblem",subdivision=3)
    for obj in EMBLEM_COLLECTION.objects:
        if obj.type=="MESH":
            SOURCE_OBJECTS.remove(obj)
    SOURCE_COLLECTION=battlefield_collection


def look_at(camera, target):
    camera.rotation_euler=(g(target)-camera.location).to_track_quat("-Z","Y").to_euler()


def camera(name, position, target, lens=42, orthographic=None):
    data=bpy.data.cameras.new(name)
    obj=bpy.data.objects.new(name,data)
    RIG_COLLECTION.objects.link(obj)
    obj.location=g(position)
    look_at(obj,target)
    data.lens=lens
    data.clip_end=250
    if orthographic:
        data.type="ORTHO"
        data.ortho_scale=orthographic
    return obj


def light(name, position, target, energy, color, size=8):
    data=bpy.data.lights.new(name,"AREA")
    data.energy=energy
    data.color=color
    data.shape="DISK"
    data.size=size
    obj=bpy.data.objects.new(name,data)
    RIG_COLLECTION.objects.link(obj)
    obj.location=g(position)
    look_at(obj,target)
    return obj


def setup_render():
    scene=bpy.context.scene
    scene.render.engine="CYCLES"
    scene.cycles.device="CPU"
    scene.cycles.samples=24
    scene.cycles.use_denoising=True
    scene.render.threads_mode="FIXED"
    scene.render.threads=4
    scene.render.image_settings.file_format="PNG"
    scene.render.image_settings.color_mode="RGBA"
    scene.render.image_settings.color_depth="8"
    scene.render.resolution_percentage=100
    scene.view_settings.view_transform="AgX"
    scene.view_settings.look="AgX - Medium High Contrast"
    scene.world=bpy.data.worlds.new("MeadowSky")
    scene.world.use_nodes=True
    world=scene.world.node_tree.nodes.get("Background")
    world.inputs["Color"].default_value=(.25,.36,.32,1)
    world.inputs["Strength"].default_value=.65
    sun_data=bpy.data.lights.new("MeadowSun","SUN")
    sun_data.energy=2.0
    sun_data.angle=.16
    sun=bpy.data.objects.new("MeadowSun",sun_data)
    RIG_COLLECTION.objects.link(sun)
    sun.location=g((-6,12,8))
    look_at(sun,(0,0,-2))
    sun.data.color=(1,.87,.66)
    fill=light("SkyFill",(6,10,-5),(0,0,0),1100,(.60,.79,1),14)
    warm=light("RuinWarmRim",(-8,6,-5),(0,0,-3),600,(1,.68,.35),7)
    emblem_key=light("EmblemKey",(97,5,-3),(100,0,0),380,(1,.87,.66),4)
    emblem_fill=light("EmblemFill",(103,3,1),(100,0,0),250,(.40,.79,1),3)
    cameras={
        "battle":camera("Camera_Battle_ExistingLayout",(0,6.75,10.35),(0,.78,-.42),
                        lens=24/(2*math.tan(math.radians(40)/2))),
        "overview":camera("Camera_EnvironmentOverview",(14,14,19),(0,0,-4),lens=38),
        "hub":camera("Camera_HubBackground",(0,5.2,10.8),(0,.42,-3.0),lens=32),
        "run_result":camera("Camera_ResultBackground",(-1,4.8,11.6),(0,.6,-2.8),lens=32),
        "emblem":camera("Camera_Emblem",(100,5.4,1.8),(100,.03,.04),orthographic=2.45),
    }
    cameras["battle"].data.sensor_fit="VERTICAL"
    cameras["battle"].data.sensor_height=24
    for name,item in cameras.items():
        item["qq_render_preset"]=name
    scene.camera=cameras["battle"]
    scene.render.resolution_x,scene.render.resolution_y=1920,1080
    return cameras,{"sun":sun,"fill":fill,"warm":warm,"emblem_key":emblem_key,"emblem_fill":emblem_fill}


def save_originals():
    scene=bpy.context.scene
    scene["qq_batch_id"]="blender_environment_07"
    scene["detail_counts"]=json.dumps(COUNTS,sort_keys=True)
    scene["qq_coordinate_contract"]="Godot(x,y,z) -> Blender(x,-z,y); glTF Y-up"
    scene["qq_runtime_path"]=relative(MODEL)
    scene["qq_generator"]=relative(Path(__file__))
    scene["qq_source_modularity"]="19 semantic groups; individually editable parts and instances"
    scene["qq_preserved_svg_identity"]="assets/branding/queuequest-logo.svg and queuequest-mark.svg"
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE),compress=True)


def export_model():
    """One disposable mesh per semantic group, one surface per used material."""
    owner=collection("RUNTIME_EXPORT_DISPOSABLE")
    root=empty("QueueQuestBattlefield",owner)
    root["detail_counts"]=COUNTS
    root["source_path"]=relative(SOURCE)
    root["generator"]=relative(Path(__file__))
    group_stats=[]
    depsgraph=bpy.context.evaluated_depsgraph_get()
    bpy.context.view_layer.update()
    by_group=defaultdict(list)
    for obj in SOURCE_OBJECTS:
        by_group[obj["qq_group"]].append(obj)
    # Blender globally uniquifies object names. Temporarily free the semantic
    # names so the exported nodes do not acquire a '.001' suffix.
    for name in SEMANTIC_NODES:
        GROUPS[name].name="EDITABLE_SOURCE_"+name
    for name in SEMANTIC_NODES:
        vertices,faces,indices,smooth=[],[],[],[]
        used=[]
        for source in by_group[name]:
            evaluated=source.evaluated_get(depsgraph)
            mesh=evaluated.to_mesh()
            offset=len(vertices)
            vertices.extend(tuple(source.matrix_world @ vertex.co) for vertex in mesh.vertices)
            material_indices=[]
            for item in mesh.materials:
                if item not in used: used.append(item)
                material_indices.append(used.index(item))
            for polygon in mesh.polygons:
                faces.append(tuple(offset+v for v in polygon.vertices))
                indices.append(material_indices[polygon.material_index])
                smooth.append(polygon.use_smooth)
            evaluated.to_mesh_clear()
        data=bpy.data.meshes.new(name+"_RuntimeMesh")
        data.from_pydata(vertices,[],faces)
        data.update()
        for item in used: data.materials.append(item)
        for polygon,index,is_smooth in zip(data.polygons,indices,smooth):
            polygon.material_index=index
            polygon.use_smooth=is_smooth
        obj=bpy.data.objects.new(name,data)
        owner.objects.link(obj)
        obj.parent=root
        obj["qq_semantic_group"]=name
        data.calc_loop_triangles()
        group_stats.append({"name":name,"source_parts":len(by_group[name]),
                            "triangles":len(data.loop_triangles),"surfaces":len(used),
                            "materials":[item["qq_role"] for item in used]})
    bpy.ops.object.select_all(action="DESELECT")
    for obj in owner.objects: obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(MODEL),export_format="GLB",use_selection=True,
                              export_yup=True,export_apply=False,export_animations=False,
                              export_extras=True,export_cameras=False,export_lights=False,
                              export_materials="EXPORT")
    stats=inspect_glb(MODEL)
    assert stats["triangles"]<150000,stats
    assert stats["surfaces"]<=80,stats
    assert set(SEMANTIC_NODES).issubset(stats["node_names"]),stats
    for obj in list(owner.objects):
        bpy.data.objects.remove(obj,do_unlink=True)
    bpy.data.collections.remove(owner)
    for name in SEMANTIC_NODES:
        GROUPS[name].name=name
    stats["groups"]=group_stats
    print("ENVIRONMENT_EXPORT_OK",json.dumps({k:v for k,v in stats.items() if k not in ("groups","node_names")}),flush=True)
    return stats


def inspect_glb(path):
    raw=path.read_bytes()
    magic,version,length=struct.unpack_from("<4sII",raw)
    assert magic==b"glTF" and version==2 and length==len(raw)
    chunk_length,chunk_type=struct.unpack_from("<II",raw,12)
    assert chunk_type==0x4e4f534a
    data=json.loads(raw[20:20+chunk_length])
    triangle_count=sum(data["accessors"][p["indices"]]["count"]//3
                       for m in data.get("meshes",[]) for p in m["primitives"])
    surfaces=sum(len(m["primitives"]) for m in data.get("meshes",[]))
    root=next(node for node in data["nodes"] if node.get("name")=="QueueQuestBattlefield")
    assert root["extras"]["detail_counts"]==COUNTS
    assert not data.get("cameras") and not data.get("animations") and not data.get("images")
    assert not data.get("extensionsUsed"),"Runtime must need no optional glTF extensions"
    return {"triangles":triangle_count,"surfaces":surfaces,"mesh_nodes":len(data["meshes"]),
            "materials":len(data["materials"]),"bytes":len(raw),
            "node_names":[n.get("name","") for n in data["nodes"]],
            "detail_counts":root["extras"]["detail_counts"]}


def render_png(camera_obj,path,size,transparent=False):
    scene=bpy.context.scene
    scene.camera=camera_obj
    scene.render.film_transparent=transparent
    scene.render.resolution_x,scene.render.resolution_y=size
    scene.render.filepath=str(path)
    bpy.ops.render.render(write_still=True)
    print("ENVIRONMENT_RENDER_OK",relative(path),flush=True)


def runtime_png(source_path,target,size,darken=0):
    image=bpy.data.images.load(str(source_path),check_existing=False)
    if darken:
        # Color-managed source pixels are adjusted in linear space, retaining
        # the authored scene instead of adding a photographic background.
        import numpy as np
        pixels=np.empty(len(image.pixels),dtype=np.float32)
        image.pixels.foreach_get(pixels)
        rgba=pixels.reshape((image.size[1],image.size[0],4))
        height,width=rgba.shape[:2]
        yy,xx=np.mgrid[0:height,0:width]
        center=np.exp(-(((xx/width-.5)/.40)**2+((yy/height-.53)/.65)**2))
        factor=(1-darken*.48)-(darken*.45)*center
        rgba[:,:,:3]*=factor[:,:,None]
        image.pixels.foreach_set(pixels)
    image.scale(*size)
    image.filepath_raw=str(target)
    image.file_format="PNG"
    image.save()
    result={"size":list(image.size),"channels":image.channels}
    if target.name=="queuequest-emblem-3d.png":
        alphas=list(image.pixels)[3::4]
        assert min(alphas)==0 and max(alphas)>.99
        result["transparent_background"]=True
    bpy.data.images.remove(image)
    return result


def render_assets(cameras,lights,source_hash):
    scene=bpy.context.scene
    assets=[]
    source_size=(2560,1440)
    for preset,darken in (("hub",.57),("run_result",.63)):
        if preset=="run_result":
            lights["sun"].data.energy=.80
            lights["sun"].data.color=(1,.48,.18)
            lights["fill"].data.energy=380
            lights["warm"].data.energy=850
            scene.world.node_tree.nodes.get("Background").inputs["Color"].default_value=(.085,.14,.23,1)
            scene.world.node_tree.nodes.get("Background").inputs["Strength"].default_value=.38
        high=INTERMEDIATE/(preset+"_2560.png")
        render_png(cameras[preset],high,source_size)
        target=ROOT/f"assets/backgrounds/{preset}.png"
        info=runtime_png(high,target,(1920,1080),darken)
        assets.append({"id":"background_"+preset,"visual_id":preset,"category":"background",
                       "runtime_path":relative(target),"export_sha256":sha256(target),
                       "source_path":relative(SOURCE),"source_sha256":source_hash,
                       "source_render_path":relative(high),"source_render_sha256":sha256(high),
                       "source_render_size":list(source_size),"presentation":"3D meadow render; darkened UI-safe center",
                       "reuse":{"scene":"QueueQuestBattlefield","camera":"Camera_"+("HubBackground" if preset=="hub" else "ResultBackground"),
                                "lighting":"daylight" if preset=="hub" else "amber dusk"},**info})
    lights["sun"].data.energy=2
    lights["sun"].data.color=(1,.87,.66)
    lights["fill"].data.energy=1100
    lights["warm"].data.energy=600
    scene.world.node_tree.nodes.get("Background").inputs["Color"].default_value=(.25,.36,.32,1)
    scene.world.node_tree.nodes.get("Background").inputs["Strength"].default_value=.65
    render_png(cameras["overview"],PREVIEW,(1920,1080))
    render_png(cameras["battle"],ROOT/"art_src/blender/previews/environment_battle_camera.png",(1920,1080))
    assets.append(render_emblem(cameras,source_hash))
    return assets


def render_emblem(cameras,source_hash):
    scene=bpy.context.scene
    SOURCE_COLLECTION.hide_render=True
    EMBLEM_COLLECTION.hide_render=False
    high=INTERMEDIATE/"queuequest_emblem_1024.png"
    render_png(cameras["emblem"],high,(1024,1024),True)
    target=ROOT/"assets/branding/queuequest-emblem-3d.png"
    info=runtime_png(high,target,(256,256))
    asset={"id":"branding_queuequest_emblem_3d","visual_id":"queuequest-emblem-3d","category":"branding",
                   "runtime_path":relative(target),"export_sha256":sha256(target),
                   "source_path":relative(SOURCE),"source_sha256":source_hash,
                   "source_render_path":relative(high),"source_render_sha256":sha256(high),
                   "source_render_size":[1024,1024],"presentation":"transparent 3D queue-card emblem; optional companion to preserved SVG",
                   "reuse":{"palette":"QueueQuest ivory, gold, cyan, navy","identity":"three queued cards and timeline Q",
                            "small_icon_geometry":"1.45x front card, thick Q, dark inset; no floor"},**info}
    SOURCE_COLLECTION.hide_render=False
    EMBLEM_COLLECTION.hide_render=True
    scene.render.film_transparent=False
    scene.camera=cameras["battle"]
    make_emblem_review()
    return asset


def make_emblem_review():
    import numpy as np
    target=ROOT/"assets/branding/queuequest-emblem-3d.png"
    before=sha256(target)
    strips=[]
    for size in (16,32,64):
        image=bpy.data.images.load(str(target),check_existing=False)
        image.scale(size,size)
        pixels=np.empty(size*size*4,dtype=np.float32)
        image.pixels.foreach_get(pixels)
        rgba=pixels.reshape((size,size,4))
        assert rgba[:,:,3].min()==0 and rgba[:,:,3].max()>.9
        assert np.count_nonzero(rgba[:,:,3]>.25)>size*size*.25
        expanded=np.repeat(np.repeat(rgba,256//size,axis=0),256//size,axis=1)
        yy,xx=np.mgrid[0:256,0:256]
        checker=np.where((xx//16+yy//16)%2==0,.03,.06)
        rgb=expanded[:,:,:3]*expanded[:,:,3:4]+checker[:,:,None]*(1-expanded[:,:,3:4])
        strips.append(np.concatenate((rgb,np.ones((256,256,1))),axis=2))
        bpy.data.images.remove(image)
        print("EMBLEM_SMALL_SIZE_OK",size,flush=True)
    combined=np.concatenate(strips,axis=1).astype(np.float32)
    contact=bpy.data.images.new("Emblem16_32_64NearestPreview",width=768,height=256,alpha=False)
    contact.pixels.foreach_set(combined.ravel())
    contact.filepath_raw=str(EMBLEM_PREVIEW)
    contact.file_format="PNG"
    contact.save()
    bpy.data.images.remove(contact)
    assert sha256(target)==before


def refresh_emblem():
    """Revise only the emblem; preserve completed field/background output bytes."""
    manifest=json.loads(MANIFEST.read_text(encoding="utf-8"))
    assert sha256(SOURCE)==manifest["source_sha256"]
    for asset in manifest["assets"]:
        assert sha256(ROOT/asset["runtime_path"])==asset["export_sha256"]
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    global SOURCE_COLLECTION,EMBLEM_COLLECTION,RIG_COLLECTION
    SOURCE_COLLECTION=bpy.data.collections["FIELD_EDITABLE_MODULES"]
    EMBLEM_COLLECTION=bpy.data.collections["BRANDING_OPTIONAL_3D_EMBLEM"]
    RIG_COLLECTION=bpy.data.collections["RENDER_RIGS_NOT_EXPORTED"]
    for obj in list(EMBLEM_COLLECTION.objects):
        data=obj.data
        bpy.data.objects.remove(obj,do_unlink=True)
        if isinstance(data,bpy.types.Mesh) and data.users==0:
            bpy.data.meshes.remove(data)
    for name in SEMANTIC_NODES: GROUPS[name]=bpy.data.objects[name]
    SOURCE_OBJECTS.extend(obj for obj in SOURCE_COLLECTION.objects if obj.type=="MESH")
    for role in PALETTE: MATERIALS[role]=bpy.data.materials["QQ_Environment_"+role]
    navy=MATERIALS["navy"]
    color,metallic,roughness=PALETTE["navy"]
    navy.diffuse_color=color
    shader=navy.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value=color
    shader.inputs["Metallic"].default_value=metallic
    shader.inputs["Roughness"].default_value=roughness
    build_emblem()
    cameras={key:bpy.data.objects[name] for key,name in {
        "battle":"Camera_Battle_ExistingLayout","emblem":"Camera_Emblem"}.items()}
    bpy.context.scene.camera=cameras["battle"]
    save_originals()
    source_hash=sha256(SOURCE)
    emblem=render_emblem(cameras,source_hash)
    manifest["source_sha256"]=source_hash
    manifest["generator_sha256"]=sha256(Path(__file__))
    manifest["assets"]=[emblem if asset["category"]=="branding" else asset for asset in manifest["assets"]]
    for asset in manifest["assets"]: asset["source_sha256"]=source_hash
    manifest["previews"]=[entry for entry in manifest["previews"] if entry["path"]!=relative(EMBLEM_PREVIEW)]
    manifest["previews"].append({"path":relative(EMBLEM_PREVIEW),"sha256":sha256(EMBLEM_PREVIEW)})
    manifest["validation"]["emblem_sizes_checked"]=[16,32,64,256]
    MANIFEST.write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    validate_source(manifest)
    print("ENVIRONMENT_EMBLEM_REFRESH_OK: field/background/previews unchanged",flush=True)


def validate_source(manifest=None):
    scene=bpy.context.scene
    actual={kind:0 for kind in COUNTS}
    for obj in bpy.data.objects:
        kind=obj.get("qq_detail_kind")
        if kind in actual: actual[kind]+=1
    assert actual==COUNTS,(actual,COUNTS)
    assert json.loads(scene["detail_counts"])==COUNTS
    assert all(bpy.data.objects.get(name) for name in SEMANTIC_NODES)
    assert not bpy.data.collections.get("RUNTIME_EXPORT_DISPOSABLE")
    tiles=[obj for obj in bpy.data.objects if "grid_column" in obj]
    assert len(tiles)==35
    for tile in tiles:
        assert abs(tile.location.x-(tile["grid_column"]-3)*1.76)<1e-5
        assert abs(tile.location.y+(tile["grid_row"]-2)*1.44)<1e-5
    assert len([obj for obj in bpy.data.objects if obj.get("qq_editable_part")])>1000
    for item in bpy.data.materials:
        if item.name.startswith("QQ_Environment_"):
            assert set(node.type for node in item.node_tree.nodes)=={"BSDF_PRINCIPLED","OUTPUT_MATERIAL"}
    if manifest:
        assert sha256(SOURCE)==manifest["source_sha256"]
        assert sha256(ROOT/manifest["generator"])==manifest["generator_sha256"]
        for asset in manifest["assets"]:
            path=ROOT/asset["runtime_path"]
            assert sha256(path)==asset["export_sha256"],asset["id"]
            if path.suffix==".png":
                image=bpy.data.images.load(str(path),check_existing=False)
                assert list(image.size)==asset["size"],asset
                if asset.get("transparent_background"):
                    alphas=list(image.pixels)[3::4]
                    assert min(alphas)==0 and max(alphas)>.99
                bpy.data.images.remove(image)
        stats=inspect_glb(MODEL)
        assert stats["triangles"]==manifest["runtime"]["triangles"]
        assert stats["surfaces"]==manifest["runtime"]["surfaces"]
        for preview in manifest["previews"]:
            assert sha256(ROOT/preview["path"])==preview["sha256"]
    print("ENVIRONMENT_SOURCE_VALIDATION_OK",json.dumps(actual),flush=True)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--validate-only",action="store_true")
    parser.add_argument("--emblem-only",action="store_true")
    parser.add_argument("--review-only",action="store_true")
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if args.review_only:
        manifest=json.loads(MANIFEST.read_text(encoding="utf-8"))
        assert sha256(SOURCE)==manifest["source_sha256"]
        for asset in manifest["assets"]:
            assert sha256(ROOT/asset["runtime_path"])==asset["export_sha256"]
        make_emblem_review()
        manifest["generator_sha256"]=sha256(Path(__file__))
        manifest["previews"]=[entry for entry in manifest["previews"] if entry["path"]!=relative(EMBLEM_PREVIEW)]
        manifest["previews"].append({"path":relative(EMBLEM_PREVIEW),"sha256":sha256(EMBLEM_PREVIEW)})
        manifest["validation"]["emblem_sizes_checked"]=[16,32,64,256]
        MANIFEST.write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
        print("ENVIRONMENT_REVIEW_ONLY_OK: runtime/source bytes unchanged",flush=True)
        return
    if args.emblem_only:
        refresh_emblem()
        return
    if args.validate_only:
        bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
        assert not bpy.data.is_dirty
        validate_source(json.loads(MANIFEST.read_text(encoding="utf-8")))
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(MODEL))
        root=bpy.data.objects.get("QueueQuestBattlefield")
        assert root and dict(root["detail_counts"])==COUNTS
        assert all(bpy.data.objects.get(name) for name in SEMANTIC_NODES)
        ground=bpy.data.objects["BattleWorldGround"]
        points=[ground.matrix_world @ Vector(corner) for corner in ground.bound_box]
        bounds=[[min(p[i] for p in points),max(p[i] for p in points)] for i in range(3)]
        for actual,expected in zip(bounds,((-21,21),(-11,27),(-.935,-.385))):
            assert all(abs(a-b)<1e-4 for a,b in zip(actual,expected)),bounds
        assert len([obj for obj in bpy.data.objects if obj.type=="MESH"])==19
        print("ENVIRONMENT_GLB_COLD_IMPORT_OK",json.dumps(bounds),flush=True)
        print("ENVIRONMENT_COLD_RELOAD_OK",flush=True)
        return
    for path in (SOURCE.parent,MODEL.parent,PREVIEW.parent,INTERMEDIATE,
                 ROOT/"assets/backgrounds",ROOT/"assets/branding"):
        path.mkdir(parents=True,exist_ok=True)
    global SOURCE_COLLECTION,EMBLEM_COLLECTION,RIG_COLLECTION
    SOURCE_COLLECTION=collection("FIELD_EDITABLE_MODULES")
    EMBLEM_COLLECTION=collection("BRANDING_OPTIONAL_3D_EMBLEM")
    RIG_COLLECTION=collection("RENDER_RIGS_NOT_EXPORTED")
    for role in PALETTE: MATERIALS[role]=material(role)
    for name in SEMANTIC_NODES: GROUPS[name]=empty(name,SOURCE_COLLECTION)
    build_floor()
    build_scenery()
    build_emblem()
    EMBLEM_COLLECTION.hide_render=True
    EMBLEM_COLLECTION.hide_viewport=True
    cameras,lights=setup_render()
    save_originals()
    validate_source()
    source_hash=sha256(SOURCE)
    runtime=export_model()
    assets=[{"id":"environment_field","visual_id":"qq_battlefield","category":"environment",
             "runtime_path":relative(MODEL),"export_sha256":sha256(MODEL),
             "source_path":relative(SOURCE),"source_sha256":source_hash,
             "presentation":"editable modular meadow ruins; consolidated static geometry; glTF Y-up",
             "detail_counts":COUNTS,"triangles":runtime["triangles"],"surfaces":runtime["surfaces"],
             "reuse":{"grid":[7,5],"tile_size":[1.61,.105,1.29],"tile_spacing":[1.76,1.44],
                      "foreground_size":[17.8,.42,11.8],"world_size":[42,.55,38],"world_center":[0,-.66,-8]}}]
    assets+=render_assets(cameras,lights,source_hash)
    manifest={"batch_id":"blender_environment_07","generator":relative(Path(__file__)),
              "generator_sha256":sha256(Path(__file__)),"source":relative(SOURCE),
              "source_sha256":source_hash,"blender_version":bpy.app.version_string,
              "source_editable_meshes":len(SOURCE_OBJECTS),"semantic_nodes":list(SEMANTIC_NODES),
              "detail_counts":COUNTS,"runtime":runtime,"assets":assets,
              "previews":[{"path":relative(path),"sha256":sha256(path)} for path in
                          (PREVIEW,ROOT/"art_src/blender/previews/environment_battle_camera.png",EMBLEM_PREVIEW)],
              "preserved_files":["assets/branding/queuequest-logo.svg","assets/branding/queuequest-mark.svg"],
              "validation":{"source_counts":True,"grid_contract":True,"materials_basic_principled":True,
                            "triangle_budget":150000,"surface_budget":80,"isolated_threads":4,
                            "emblem_sizes_checked":[16,32,64,256]}}
    MANIFEST.write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    validate_source(manifest)
    print("ENVIRONMENT_BATCH_OK: field, hub/result backgrounds, transparent companion emblem",flush=True)


if __name__=="__main__":
    main()
