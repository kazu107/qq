"""Card illustrations: six different moments, environments, and camera rigs.

All geometry is authored here using the shared art generator's modeling kit.
The returned collections own their scenery; no common display floor is used.
"""

import math
import random

import bpy
from mathutils import Vector


CAMERAS = {
    "quick_slash": ((0.3, -8.5, 2.4), (0.0, 0.0, 1.6), 4.0),
    "guard": ((2.2, -9.0, 2.8), (0.0, 0.0, 1.6), 3.9),
    "delay_step": ((0.1, -9.0, 2.8), (0.0, 0.0, 1.45), 4.2),
    "repair_burst": ((1.1, -9.0, 3.8), (0.0, 0.0, 1.35), 3.7),
    "auto_turret": ((3.8, -7.0, 3.0), (0.0, -0.2, 1.0), 3.6),
    "event_horizon": ((0.0, -10.0, 2.6), (0.0, 0.0, 1.6), 4.5),
}

LIGHT_COLORS = {
    "quick_slash": ((0.65, 0.84, 1.0), (1.0, 0.44, 0.17)),
    "guard": ((0.52, 0.76, 1.0), (0.24, 0.68, 1.0)),
    "delay_step": ((1.0, 0.79, 0.46), (0.55, 0.34, 1.0)),
    "repair_burst": ((0.72, 1.0, 0.78), (1.0, 0.71, 0.30)),
    "auto_turret": ((1.0, 0.78, 0.48), (1.0, 0.24, 0.07)),
    "event_horizon": ((0.55, 0.51, 1.0), (1.0, 0.45, 0.10)),
}


def backdrop(b, collection, name, dark, light, *, scale=2.2):
    material = b.make_material(name, (*dark, 1.0))
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    shader = nodes.new("ShaderNodeEmission")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 3.0
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.22
    ramp.color_ramp.elements[0].color = (*dark, 1.0)
    ramp.color_ramp.elements[1].position = 0.78
    ramp.color_ramp.elements[1].color = (*light, 1.0)
    links.new(noise.outputs["Fac"], ramp.inputs[0])
    links.new(ramp.outputs[0], shader.inputs["Color"])
    shader.inputs["Strength"].default_value = 0.8
    links.new(shader.outputs[0], nodes.get("Material Output").inputs["Surface"])
    b.add_box(collection, name, (0, 4.0, 2.2), (22, 0.2, 16), material, bevel=0)


def shard(b, collection, name, position, size, material, rng):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=size)
    obj = bpy.context.object
    obj.name = name
    obj.location = position
    obj.scale = (rng.uniform(0.6, 1.6), rng.uniform(0.3, 0.8), rng.uniform(0.7, 1.7))
    obj.rotation_euler = [rng.uniform(0, math.tau) for _ in range(3)]
    b.finish_object(obj, collection, material)
    return obj


def burst(b, collection, center, material, *, radius=0.6, count=9, seed=1):
    rng = random.Random(seed)
    for index in range(count):
        angle = rng.uniform(0, math.tau)
        start = Vector(center) + Vector((math.cos(angle), 0, math.sin(angle))) * 0.08
        end = Vector(center) + Vector((math.cos(angle), -0.08, math.sin(angle))) * rng.uniform(radius * 0.3, radius)
        obj = b.add_curve(collection, f"Impact_{seed}_{index}", [start, end], 0.018, material)
        obj.data.splines[0].bezier_points[-1].radius = 0.05


def gauntlet(b, collection, name, wrist, elbow, *, pale=True):
    metal = b.MATERIALS["ceramic_light" if pale else "gunmetal"]
    b.add_rod_between(collection, name + "Sleeve", elbow, wrist, 0.27, b.MATERIALS["gunmetal"])
    start, end = Vector(elbow), Vector(wrist)
    for index in range(4):
        center = start.lerp(end, 0.2 + index * 0.2)
        obj = b.add_box(collection, f"{name}Plate{index}", center, (0.52, 0.42, 0.25), metal, bevel=0.07)
        obj.rotation_euler[1] = -0.55
        b.add_box(collection, f"{name}Rivet{index}", center + Vector((0.08, -0.23, 0)), (0.07, 0.045, 0.065), b.MATERIALS["brass"], bevel=0.012)
    b.add_box(collection, name + "Fist", wrist, (0.5, 0.38, 0.4), metal, rotation_degrees=(0, -35, 0), bevel=0.09)
    for index in range(4):
        b.add_box(collection, f"{name}Knuckle{index}", (wrist[0] - 0.18 + index * 0.12, wrist[1] - 0.22, wrist[2] + 0.08), (0.105, 0.12, 0.2), b.MATERIALS["steel"], bevel=0.03)


def quick_slash(b):
    c = b.new_asset_collection("card", "quick_slash")
    backdrop(b, c, "Slash_DustyPass", (0.015, 0.028, 0.055), (0.30, 0.12, 0.045))
    stone = b.make_material("Slash_RuinStone", (0.12, 0.10, 0.085, 1), roughness=0.95, bump_strength=0.25)
    for i in range(5):
        x = i * 1.45 - 2.9
        b.add_box(c, f"Slash_RuinedPillar{i}", (x, 2.8, 0.1 + i % 2 * 0.6), (0.42, 0.8, 3.0), stone, rotation_degrees=(0, -13 + i * 5, 0), bevel=0.09)
        b.add_box(c, f"Slash_PillarCapital{i}", (x + 0.12, 2.8, 1.6 + i % 2 * 0.6), (0.75, 0.9, 0.22), stone, bevel=0.05)
        for j in range(3):
            b.add_box(c, f"Slash_Masonry{i}_{j}", (x - 0.3, 3.0, -0.3 + j * 0.45), (1.2, 0.8, 0.42), stone, bevel=0.02)
    root = b.add_sword(c, "Slash", (-0.10, -0.45, 1.6), (0, 43, -8))
    root.scale = (1.8, 1.8, 1.8)
    blade = bpy.data.objects["Slash_Blade"]
    blade.data.materials[0] = b.make_material("Slash_BrightSilver", (0.55, 0.7, 0.8, 1), metallic=0.5, roughness=0.28)
    gauntlet(b, c, "Slash_Hand", (-0.80, -0.33, 0.82), (-1.65, 0.12, -0.25))
    # A tapered ribbon follows the cut; its open arc reads as motion, not a ring.
    pts = [(-2.25, -0.1, 1.25), (-1.25, -0.65, 1.75), (0.1, -0.80, 2.25), (1.2, -0.65, 2.60), (2.3, -0.10, 2.7)]
    ribbon = b.add_curve(c, "Slash_CuttingEdge", pts, 0.09, b.MATERIALS["cyan"])
    for point, width in zip(ribbon.data.splines[0].bezier_points, (0.03, 0.4, 1, 0.5, 0.02)):
        point.radius = width
    rng = random.Random(91)
    for i in range(18):
        shard(b, c, f"Slash_FlyingChip{i}", (rng.uniform(0.6, 2), rng.uniform(-0.4, 0.2), rng.uniform(0.6, 2.9)), rng.uniform(0.025, 0.1), b.MATERIALS["steel"], rng)
    burst(b, c, (1.15, -0.65, 2.1), b.MATERIALS["amber"], radius=0.8, seed=2)
    return c


def guard(b):
    c = b.new_asset_collection("card", "guard")
    backdrop(b, c, "Guard_Storm", (0.008, 0.026, 0.055), (0.12, 0.25, 0.35))
    stone = b.make_material("Guard_WetStone", (0.028, 0.064, 0.095, 1), roughness=0.5)
    for x in (-2.2, 2.0):
        b.add_box(c, f"Guard_Wall{x}", (x, 2, 1), (1.2, 0.8, 6), stone, bevel=0.08)
    b.add_curve(c, "Guard_GothicArch", [(-1.8, 2, 2), (-1.4, 2, 3.6), (0, 2, 4.5), (1.4, 2, 3.6), (1.8, 2, 2)], 0.25, stone)
    gauntlet(b, c, "Guard_BracedArm", (0.4, 0.28, 1.4), (1.8, 0.8, 0.35), pale=False)
    b.add_shield(c, "Guard", (-0.18, -0.25, 1.5), 1.48)
    for radius in (0.18, 0.34, 0.55):
        b.add_torus(c, f"Guard_HitRipple{radius}", (-0.68, -0.61, 2), radius, 0.016, b.MATERIALS["cyan"], rotation_degrees=(90, 0, 0))
    burst(b, c, (-0.68, -0.7, 2), b.MATERIALS["amber"], radius=0.65, seed=9)
    for i in range(3):
        b.add_rod_between(c, f"Guard_DeflectedBolt{i}", (-2.2, -0.4, 2.8 + i * 0.3), (-0.75 - i * 0.23, -0.55, 2.04 + i * 0.35), 0.025, b.MATERIALS["amber"])
    for i in range(20):
        x, z = (i * 0.79) % 5 - 2.5, (i * 1.23) % 5
        b.add_curve(c, f"Guard_Rain{i}", [(x, 1.3, z), (x - 0.18, 1.3, z - 0.4)], 0.009, b.MATERIALS["cyan_soft"])
    return c


def delay_step(b):
    c = b.new_asset_collection("card", "delay_step")
    backdrop(b, c, "Delay_Twilight", (0.047, 0.015, 0.09), (0.30, 0.16, 0.28), scale=3.6)
    # A suspended spell catches a hostile blade in the face of a giant clock.
    b.add_clock_face(c, "Delay_SpellClock", (-0.35, 0.35, 1.75), 1.36, b.MATERIALS["amber"])
    for radius in (1.50, 1.58):
        b.add_torus(c, f"Delay_ClockTrace{radius}", (-0.35, 0.26, 1.75), radius, 0.017, b.MATERIALS["brass_edge"], rotation_degrees=(90, 0, 0))
    root = b.add_sword(c, "Delay_EnemyBlade", (0.6, -0.38, 1.25), (0, -60, 0), accent=b.MATERIALS["red"])
    root.scale = (1.35, 1.35, 1.35)
    for i in range(5):
        x = 0.0 + i * 0.26
        b.add_curve(c, f"Delay_Restraint{i}", [(x - 0.3, -0.45, 0.55), (x + 0.08, -0.6, 1.0), (x - 0.18, -0.5, 1.8)], 0.022, b.MATERIALS["amber"])
    rng = random.Random(12)
    for i in range(38):
        x, z = rng.uniform(-2, 2), rng.uniform(-0.3, 3.6)
        shard(b, c, f"Delay_SuspendedSand{i}", (x, -0.2, z), rng.uniform(0.012, 0.035), b.MATERIALS["brass_edge"], rng)
    for i in range(7):
        b.add_box(c, f"Delay_FracturedStep{i}", (i * 0.65 - 2.3, 1.9, -0.2 + i * 0.28), (0.48, 0.9, 0.17), b.MATERIALS["gunmetal"], rotation_degrees=(0, i * 3, -8), bevel=0.035)
    return c


def repair_burst(b):
    c = b.new_asset_collection("card", "repair_burst")
    backdrop(b, c, "Repair_SunlitGrove", (0.009, 0.06, 0.04), (0.27, 0.33, 0.12), scale=4)
    bark = b.make_material("Repair_Bark", (0.04, 0.07, 0.035, 1), roughness=0.95)
    for i in range(8):
        b.add_cylinder(c, f"Repair_DistantTree{i}", (i * 0.8 - 3, 2.8, 2), 0.16 + i % 3 * 0.06, 8, bark, vertices=12, rotation_degrees=(0, i * 2 - 6, 0))
        b.add_curve(c, f"Repair_Branch{i}", [(i * 0.8 - 3, 2.6, 2.3), (i * 0.8 - 2.5, 2.6, 2.7), (i * 0.8 - 1.8, 2.6, 3.0)], 0.08, bark)
    leaves = b.make_material("Repair_LeafCanopy", (0.045, 0.11, 0.02, 1), roughness=1)
    rng = random.Random(52)
    for i in range(20):
        shard(b, c, f"Repair_Canopy{i}", (rng.uniform(-4, 4), 2.1, rng.uniform(2.9, 5.3)), rng.uniform(0.5, 1.2), leaves, rng)
    gauntlet(b, c, "Repair_Arm", (0.55, 0.0, 1.55), (-1.3, 0.15, 0.2))
    b.add_box(c, "Repair_ForearmPlate", (-0.33, -0.2, 1.0), (0.95, 0.18, 0.60), b.MATERIALS["ceramic_light"], rotation_degrees=(0, -38, 0), bevel=0.08)
    b.add_curve(c, "Repair_ClosingCrack", [(-0.62, -0.36, 0.66), (-0.5, -0.37, 1.0), (-0.24, -0.37, 1.1), (-0.23, -0.37, 1.3)], 0.028, b.MATERIALS["green"])
    rng = random.Random(4)
    for i in range(16):
        angle = math.tau * i / 16
        pos = (math.cos(angle) * 1.0 - 0.2, -0.15, math.sin(angle) * 0.85 + 1.25)
        shard(b, c, f"Repair_ReturningPlate{i}", pos, rng.uniform(0.04, 0.12), b.MATERIALS["ceramic_light"], rng)
    for i in range(3):
        pts = []
        for j in range(28):
            t = j / 27
            angle = t * math.tau * 1.4 + i * 1.2
            pts.append((-1.25 + t * 2.2, -0.1 + math.cos(angle) * 0.48, 0.4 + t * 1.4 + math.sin(angle) * 0.45))
        b.add_curve(c, f"Repair_NaniteFlow{i}", pts, 0.019, b.MATERIALS["green"])
    # Medical green crosses are part of the repair effect, with no baked text.
    for i, (x, z, s) in enumerate(((0.6, 2.3, 0.35), (-1.2, 1.9, 0.22), (1.15, 1.4, 0.17))):
        b.add_box(c, f"Repair_CrossVertical{i}", (x, -0.4, z), (s * 0.3, 0.07, s), b.MATERIALS["green"], bevel=0.02)
        b.add_box(c, f"Repair_CrossHorizontal{i}", (x, -0.41, z), (s, 0.07, s * 0.3), b.MATERIALS["green"], bevel=0.02)
    return c


def auto_turret(b):
    c = b.build_auto_turret()
    backdrop(b, c, "Turret_EmberSky", (0.09, 0.025, 0.008), (0.42, 0.19, 0.06), scale=3.0)
    earth = b.make_material("Turret_ScorchedEarth", (0.095, 0.055, 0.028, 1), roughness=0.95, bump_strength=0.35)
    b.add_box(c, "Turret_Battlefield", (0, 0, -0.18), (22, 22, 0.3), earth, bevel=0)
    for i, x in enumerate((-2.5, 1.8, 3.4)):
        b.add_box(c, f"Turret_RuinedBunker{i}", (x, 4.2, 0.1), (1.5, 1.1, 1.1 + i * 0.5), earth, rotation_degrees=(0, i * 9 - 5, 0), bevel=0.09)
        for j in range(3):
            b.add_box(c, f"Turret_Parapet{i}_{j}", (x - 0.5 + j * 0.5, 4.2, 0.8 + i * 0.25), (0.3, 1.1, 0.35), earth, bevel=0.04)
    for i in range(3):
        angle = i * math.tau / 3
        foot = (math.cos(angle) * 1.05, 0.2 + math.sin(angle) * 1.05, 0.05)
        b.add_rod_between(c, f"Turret_Tripod{i}", (0, 0.2, 0.47), foot, 0.12, b.MATERIALS["steel"])
        b.add_box(c, f"Turret_TripodFoot{i}", foot, (0.4, 0.35, 0.12), b.MATERIALS["gunmetal"], bevel=0.04)
    b.add_cone(c, "Turret_MuzzleFlash", (-0.24, -1.9, 1.34), 0.25, 0.02, 0.65, b.MATERIALS["amber"], vertices=7, rotation_degrees=(90, 0, 0))
    burst(b, c, (-0.24, -1.8, 1.34), b.MATERIALS["amber"], radius=0.45, seed=18)
    rng = random.Random(72)
    for i in range(7):
        b.add_cylinder(c, f"Turret_EjectedCasing{i}", (0.95 + i * 0.13, -0.1 + i * 0.07, 1.15 + math.sin(i * 0.6) * 0.55), 0.04, 0.16, b.MATERIALS["brass_edge"], vertices=16, rotation_degrees=(i * 18, i * 34, 0))
    for i in range(25):
        shard(b, c, f"Turret_Rubble{i}", (rng.uniform(-3, 3), rng.uniform(-1.5, 3), 0.04), rng.uniform(0.07, 0.23), earth, rng)
    return c


def event_horizon(b):
    c = b.new_asset_collection("card", "event_horizon")
    backdrop(b, c, "Horizon_Nebula", (0.005, 0.002, 0.022), (0.12, 0.045, 0.23), scale=5.0)
    void = b.make_material("Horizon_AbsoluteVoid", (0, 0, 0, 1), roughness=1)
    void.node_tree.nodes.get("Principled BSDF").inputs["Specular IOR Level"].default_value = 0
    center = Vector((0.3, 0.0, 1.85))
    b.add_sphere(c, "Horizon_BlackHole", center, (1.9, 1.0, 1.9), void)
    for i in range(4):
        b.add_torus(c, f"Horizon_LensedLight{i}", center + Vector((0, 0.1 + i * 0.03, 0)), 0.95 + i * 0.075, 0.026 if i else 0.045, b.MATERIALS["amber" if i < 2 else "purple"], rotation_degrees=(90, 0, 0))
    for i in range(7):
        pts = []
        for j in range(70):
            t = j / 69
            angle = t * math.tau * 1.1 + i * 0.45
            radius = 1.0 + t * 1.8
            pts.append((center.x + math.cos(angle) * radius, -0.3 + math.sin(angle) * 0.28, center.z + math.sin(angle) * radius * 0.31 + math.cos(angle) * 0.3))
        curve = b.add_curve(c, f"Horizon_AccretionStream{i}", pts, 0.015 + i % 2 * 0.008, b.MATERIALS["amber" if i < 4 else "purple"])
        curve.data.splines[0].bezier_points[-1].radius = 0.02
    rng = random.Random(105)
    for i in range(75):
        pos = (rng.uniform(-4, 4), 2.5, rng.uniform(-1, 5))
        shard(b, c, f"Horizon_Star{i}", pos, rng.uniform(0.007, 0.020), b.MATERIALS["cyan_soft"], rng)
    for i in range(17):
        angle = rng.uniform(0, math.tau)
        radius = rng.uniform(1.35, 2.6)
        shard(b, c, f"Horizon_CapturedArmor{i}", (0.3 + math.cos(angle) * radius, -0.1, 1.85 + math.sin(angle) * radius * 0.6), rng.uniform(0.05, 0.14), b.MATERIALS["steel"], rng)
    return c


BUILDERS = {builder.__name__: builder for builder in (
    quick_slash, guard, delay_step, repair_burst, auto_turret, event_horizon,
)}
