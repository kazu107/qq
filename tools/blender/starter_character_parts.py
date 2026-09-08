"""Reusable rigid-skinned starter equipment in the established 18-bone space.

The library stores unmerged, editable parts. Export assemblies make local mesh
copies, apply their palette and merge surfaces without changing the source kit.
"""

import math

import bpy
from mathutils import Vector

import build_battle_vertical_slice as base


STARTER_PARTS = {
    "tempo": ("BODY_LIGHT", "HEAD_FIN", "WEAPON_RAPIER", "OFFHAND_BUCKLER", "BACK_THRUSTERS"),
    "fortress": ("BODY_HEAVY", "HEAD_FORTRESS", "WEAPON_HAMMER", "OFFHAND_TOWER", "BACK_REACTOR"),
    "vanguard": ("BODY_ASSAULT", "HEAD_HORNS", "WEAPON_GREATSWORD", "BACK_THRUSTERS"),
    "aegis": ("BODY_HEAVY", "HEAD_CREST", "WEAPON_HAMMER", "OFFHAND_AEGIS", "BACK_REACTOR"),
    "chrono": ("BODY_ARCANE", "HEAD_HALO", "WEAPON_STAFF", "OFFHAND_ORB", "BACK_CHRONO"),
    "turret": ("BODY_MECH", "HEAD_ANTENNA", "WEAPON_BLASTER", "OFFHAND_BUCKLER", "BACK_AMMO"),
}


class Kit:
    def __init__(self, collection, rig, materials):
        self.c, self.rig, self.m = collection, rig, materials

    def box(self, name, position, size, role="armor", bone="spine", bevel=0.025, rotation=(0, 0, 0)):
        return base.add_cube(self.c, self.rig, name, position, size, self.m[role], bone, rotation, bevel)

    def sphere(self, name, position, size, role="metal", bone="head", smooth=True):
        return base.add_ellipsoid(self.c, self.rig, name, position, size, self.m[role], bone, 2, smooth)

    def cylinder(self, name, position, radius, depth, role="metal", bone="spine", rotation=(0, 0, 0), vertices=24):
        return base.add_cylinder(self.c, self.rig, name, position, radius, depth, self.m[role], bone, 1.0, vertices, rotation)

    def panel(self, name, points, y, depth, role="armor", bone="spine", bevel=0.018):
        return base.add_prism(self.c, self.rig, name, points, y, depth, self.m[role], bone, bevel)

    def ring(self, name, position, radius, tube=0.025, role="trim", bone="chest", rotation=(math.pi / 2, 0, 0)):
        bpy.ops.mesh.primitive_torus_add(major_segments=40, minor_segments=8, location=position,
                                        major_radius=radius, minor_radius=tube, rotation=rotation)
        obj = bpy.context.object
        obj.name = name
        base.apply_object_transform(obj)
        base.set_mesh_shading(obj, True)
        base.assign_material(obj, self.m[role])
        base.move_to_collection(obj, self.c)
        return base.bind_to_bone(obj, self.rig, bone)

    def rod(self, name, start, end, radius=0.025, role="metal", bone="chest"):
        start, end = Vector(start), Vector(end)
        obj = self.cylinder(name, (start + end) / 2, radius, (end - start).length, role, bone)
        # Primitives have baked positions; rotate vertices around their center.
        center = (start + end) / 2
        rotation = Vector((0, 0, 1)).rotation_difference(end - start)
        for vertex in obj.data.vertices:
            vertex.co = center + rotation @ (vertex.co - center)
        return obj

    def rivets(self, name, positions, bone="spine"):
        for index, position in enumerate(positions):
            self.sphere(f"{name}_{index}", position, (0.043, 0.027, 0.043), "trim", bone)


def library_materials():
    palette = base.balanced_materials()
    roles = {"blue": "armor", "blue_light": "edge", "dark": "dark", "leather": "leather",
             "metal": "metal", "metal_light": "silver", "gold": "trim", "accent": "glow",
             "cloth": "cloth", "cloth_shadow": "cloth_shadow", "skin": "skin", "skin_light": "skin_light",
             "hair": "hair", "eye": "eye"}
    materials = {}
    for old_role, material in palette.items():
        role = roles[old_role]
        material.name = "QQ_Starter_" + role
        material["qq_role"] = role
        materials[role] = material
    return materials


def build_body(k, style):
    if style in ("HEAVY", "ASSAULT", "MECH"):
        k.box("LayeredBreastplate", (0, 0.33, 1.59), (0.75, 0.23, 0.49), bevel=0.065)
        for side in (-1, 1):
            bone = "left_upper_arm" if side < 0 else "right_upper_arm"
            width = 0.48 if style == "HEAVY" or side < 0 else 0.34
            for tier in range(3):
                k.box(f"ShoulderLamella_{side}_{tier}", (side * (0.53 + tier * 0.014), 0.01, 1.85 - tier * 0.065),
                      (width + tier * 0.025, 0.46, 0.105), "armor" if tier % 2 == 0 else "metal", bone, 0.035)
            foot = "left_foot" if side < 0 else "right_foot"
            k.box(f"ArmoredBoot_{side}", (side * 0.23, 0.10, 0.12), (0.35, 0.49, 0.22), "armor", foot, 0.045)
        for index in range(4):
            k.box(f"AbdomenSegment{index}", (0, 0.28, 1.14 + index * 0.068), (0.52, 0.12, 0.055), "metal", "spine", 0.012)
        k.rivets("ChestFastener", [(x, 0.457, z) for x in (-0.3, 0.3) for z in (1.43, 1.74)])
    if style == "LIGHT":
        for side in (-1, 1):
            bone = "left_lower_leg" if side < 0 else "right_lower_leg"
            x = side * 0.23
            k.panel(f"SpeedGreave{side}", [(x - 0.1, 0.17), (x + 0.1, 0.17), (x + 0.07, 0.51), (x, 0.57), (x - 0.07, 0.51)], 0.13, 0.07, "edge", bone)
            k.box(f"SpeedLamp{side}", (x, 0.18, 0.36), (0.035, 0.025, 0.24), "glow", bone, 0.008)
        k.panel("StreamlinedChest", [(-0.29, 1.68), (0, 1.80), (0.29, 1.68), (0.16, 1.36), (-0.16, 1.36)], 0.365, 0.045, "edge")
        k.panel("SpeedChevron", [(-0.16, 1.69), (0, 1.57), (0.16, 1.69), (0, 1.63)], 0.397, 0.018, "glow")
    elif style == "HEAVY":
        k.ring("ChestPowerRing", (0, 0.475, 1.6), 0.145, 0.025, "trim", "spine")
        k.sphere("ChestPowerCore", (0, 0.48, 1.6), (0.19, 0.045, 0.19), "glow", "spine")
        for side in (-1, 1):
            bone = "left_forearm" if side < 0 else "right_forearm"
            k.box(f"HeavyBracer{side}", (0.5 * side, 0.08, 1.19), (0.3, 0.32, 0.34), "armor", bone, 0.045)
    elif style == "ASSAULT":
        k.panel("AssaultChest", [(-0.34, 1.75), (0, 1.56), (0.34, 1.75), (0.23, 1.42), (0, 1.34), (-0.23, 1.42)], 0.47, 0.05, "edge")
        for side in (-1, 1):
            k.rod(f"AssaultConduit{side}", (side * 0.23, 0.51, 1.68), (side * 0.075, 0.51, 1.47), 0.014, "glow", "spine")
    elif style == "ARCANE":
        for side in (-1, 1):
            k.panel(f"RobeFront{side}", [(side * 0.06, 1.3), (side * 0.29, 1.34), (side * 0.45, 0.34), (side * 0.08, 0.42)], 0.16, 0.065, "armor", "hips")
            k.panel(f"RobeBack{side}", [(side * 0.04, 1.7), (side * 0.38, 1.76), (side * 0.48, 0.28), (side * 0.05, 0.36)], -0.30, 0.075, "cloth_shadow", "hips")
            k.rod(f"RobeInlay{side}", (side * 0.27, 0.20, 1.22), (side * 0.38, 0.20, 0.43), 0.018, "trim", "hips")
            k.panel(f"HighCollar{side}", [(side * 0.18, 1.83), (side * 0.31, 2.09), (side * 0.43, 1.82)], -0.06, 0.12, "armor", "chest")
    elif style == "MECH":
        k.ring("EngineerCoreRim", (0, 0.48, 1.58), 0.16, 0.027, "metal", "spine")
        k.sphere("EngineerCore", (0, 0.49, 1.58), (0.19, 0.05, 0.19), "glow", "spine")
        for i in range(4):
            k.cylinder(f"BeltShell{i}", (-0.18 + i * 0.12, 0.26, 1.04), 0.043, 0.2, "trim", "hips", vertices=12)
        k.box("ToolPouch", (0.34, 0.17, 0.91), (0.25, 0.22, 0.25), "dark", "hips")
        k.rod("SpannerHandle", (0.37, 0.3, 0.78), (0.37, 0.3, 1.01), 0.026, "silver", "hips")


def build_head(k, style):
    if style == "FIN":
        k.box("TempoVisor", (0, 0.245, 2.31), (0.41, 0.065, 0.11), "dark", "head", 0.035)
        k.box("TempoVisorSlit", (0, 0.283, 2.32), (0.34, 0.015, 0.025), "glow", "head", 0.01)
        for side in (-1, 1):
            k.panel(f"SweptFin{side}", [(side * 0.18, 2.33), (side * 0.29, 2.68), (side * 0.36, 2.48), (side * 0.27, 2.22)], -0.05, 0.08, "armor", "head")
        return
    k.sphere("HelmetShell", (0, -0.005, 2.30), (0.55, 0.46, 0.65), "armor", "head")
    k.panel("FacePlate", [(-0.21, 2.44), (0.21, 2.44), (0.18, 2.16), (0, 2.04), (-0.18, 2.16)], 0.25, 0.10, "dark", "head", 0.03)
    for side in (-1, 1):
        k.rod(f"EyeSlit{side}", (side * 0.035, 0.312, 2.26), (side * 0.17, 0.29, 2.33), 0.018, "glow", "head")
        k.cylinder(f"HelmetEar{side}", (side * 0.27, 0, 2.3), 0.105, 0.06, "metal", "head", (0, math.pi / 2, 0))
    if style == "FORTRESS":
        k.box("HelmetBrow", (0, 0.235, 2.46), (0.52, 0.14, 0.13), "metal", "head")
        for x in (-0.18, 0, 0.18):
            k.box(f"HelmetCrenel{x}", (x, -0.025, 2.61), (0.1, 0.24, 0.15), "armor", "head", 0.025)
    elif style == "HORNS":
        for side in (-1, 1):
            k.panel(f"AssaultHorn{side}", [(side * 0.17, 2.46), (side * 0.36, 2.70), (side * 0.32, 2.31)], -0.02, 0.11, "edge", "head")
        k.panel("AssaultForehead", [(-0.06, 2.53), (0.06, 2.53), (0, 2.25)], 0.284, 0.06, "armor", "head")
    elif style == "CREST":
        k.panel("AegisCrest", [(-0.04, 2.51), (0, 2.77), (0.065, 2.6), (0.04, 2.42)], -0.01, 0.23, "trim", "head")
        k.panel("AegisForehead", [(-0.11, 2.51), (0.11, 2.51), (0, 2.35)], 0.3, 0.045, "silver", "head")
    elif style == "HALO":
        k.ring("Halo", (0, -0.18, 2.45), 0.43, 0.036, "trim", "head")
        for index in range(8):
            a = index * math.tau / 8
            k.sphere(f"HaloIndex{index}", (math.sin(a) * 0.43, -0.16, 2.45 + math.cos(a) * 0.43), (0.052, 0.035, 0.052), "glow", "head")
    elif style == "ANTENNA":
        for side in (-1, 1):
            k.ring(f"GoggleRim{side}", (side * 0.115, 0.325, 2.34), 0.08, 0.021, "trim", "head")
            k.sphere(f"GoggleLens{side}", (side * 0.115, 0.33, 2.34), (0.12, 0.045, 0.12), "glow", "head")
        k.rod("RadioAntenna", (0.23, -0.06, 2.49), (0.30, -0.06, 2.82), 0.019, "metal", "head")
        k.sphere("RadioLight", (0.30, -0.06, 2.82), (0.06, 0.06, 0.06), "glow", "head")


def build_weapon(k, style):
    hand = "right_hand"
    if style in ("RAPIER", "GREATSWORD", "HAMMER", "STAFF"):
        k.cylinder("WeaponGrip", (0.5, 0, 0.89), 0.045, 0.26, "leather", hand)
        for i in range(5):
            k.ring(f"GripWrap{i}", (0.5, 0, 0.79 + i * 0.048), 0.045, 0.008, "trim", hand, (0, 0, 0))
    if style in ("RAPIER", "GREATSWORD"):
        wide = style == "GREATSWORD"
        w = 0.17 if wide else 0.032
        low = -0.14 if wide else -0.12
        k.panel("Blade", [(0.5 - w, 0.7), (0.5 + w, 0.7), (0.5 + w * 0.8, low + 0.19), (0.5, low), (0.5 - w * 0.8, low + 0.19)], 0, 0.08 if wide else 0.035, "silver", hand, 0.008)
        k.box("SwordGuard", (0.5, 0, 0.70), (0.58 if wide else 0.29, 0.12, 0.09), "trim", hand)
        k.box("BladeInlay", (0.5, 0.047, 0.31), (0.035 if wide else 0.015, 0.01, 0.7), "glow", hand, 0.003)
        if not wide:
            k.ring("RapierBasket", (0.5, 0.02, 0.83), 0.17, 0.018, "metal", hand)
    elif style == "HAMMER":
        k.cylinder("HammerShaft", (0.5, 0, 0.60), 0.045, 0.64, "metal", hand)
        k.box("HammerHead", (0.5, 0, 0.27), (0.59, 0.33, 0.30), "armor", hand, 0.045)
        for side in (-1, 1):
            k.box(f"HammerCap{side}", (0.5 + side * 0.3, 0, 0.27), (0.09, 0.38, 0.33), "silver", hand)
        k.box("HammerEnergy", (0.5, 0.17, 0.28), (0.12, 0.025, 0.21), "glow", hand)
    elif style == "STAFF":
        k.cylinder("StaffPole", (0.5, 0, 1.16), 0.035, 1.91, "metal", hand)
        k.ring("StaffClock", (0.5, 0, 2.18), 0.27, 0.032, "trim", hand)
        k.ring("StaffClockInner", (0.5, 0, 2.18), 0.2, 0.012, "silver", hand)
        k.sphere("StaffCore", (0.5, 0, 2.18), (0.13, 0.13, 0.13), "glow", hand)
        k.rod("StaffClockHand", (0.5, 0.03, 2.18), (0.59, 0.03, 2.36), 0.018, "silver", hand)
    elif style == "BLASTER":
        # Barrel follows local -Z in Blender, just like the existing sword tip.
        k.box("BlasterGrip", (0.5, 0, 0.91), (0.16, 0.15, 0.24), "dark", hand)
        k.box("BlasterHousing", (0.5, 0.10, 0.72), (0.36, 0.35, 0.33), "armor", hand, 0.045)
        k.cylinder("BlasterBarrel", (0.5, 0.12, 0.44), 0.095, 0.45, "metal", hand)
        k.cylinder("BlasterMuzzle", (0.5, 0.12, 0.21), 0.13, 0.075, "dark", hand)
        k.cylinder("BlasterBore", (0.5, 0.12, 0.168), 0.07, 0.012, "glow", hand)
        k.box("BlasterMagazine", (0.7, 0.08, 0.68), (0.17, 0.26, 0.28), "trim", hand)


def build_offhand(k, style):
    hand = "left_hand"
    if style == "BUCKLER":
        k.cylinder("BucklerBody", (-0.5, 0.18, 0.98), 0.26, 0.12, "armor", hand, (math.pi / 2, 0, 0), 32)
        k.ring("BucklerRim", (-0.5, 0.25, 0.98), 0.25, 0.03, "silver", hand)
        k.sphere("BucklerBoss", (-0.5, 0.27, 0.98), (0.19, 0.10, 0.19), "trim", hand)
    elif style in ("TOWER", "AEGIS"):
        x = -0.50
        points = [(x - 0.38, 1.5), (x + 0.38, 1.5), (x + 0.35, 0.40), (x, 0.26), (x - 0.35, 0.40)]
        k.panel("TowerShieldBorder", points, 0.22, 0.17, "trim" if style == "AEGIS" else "metal", hand, 0.04)
        inner = [(x + (px - x) * 0.81, 0.91 + (pz - 0.91) * 0.86) for px, pz in points]
        k.panel("TowerShieldFace", inner, 0.32, 0.075, "armor", hand, 0.025)
        k.box("TowerShieldSpine", (x, 0.38, 0.90), (0.055, 0.025, 0.95), "glow", hand, 0.01)
        if style == "AEGIS":
            k.ring("AegisShieldSeal", (x, 0.41, 1.00), 0.23, 0.026, "trim", hand)
            for dx, dz, w, h in [(0, 0, 0.10, 0.31), (0, 0.04, 0.29, 0.10)]:
                k.box(f"AegisEmblem{w}", (x + dx, 0.42, 1.0 + dz), (w, 0.04, h), "glow", hand, 0.01)
        else:
            for z in (0.58, 0.86, 1.16):
                k.box(f"ShieldCrossBrace{z}", (x, 0.38, z), (0.57, 0.04, 0.065), "metal", hand)
        k.rivets("ShieldBolts", [(x + dx, 0.405, z) for dx in (-0.27, 0.27) for z in (0.51, 1.36)], hand)
    elif style == "ORB":
        k.sphere("ChronoOrb", (-0.5, 0.15, 1.16), (0.32, 0.32, 0.32), "glow", hand)
        for index in range(2):
            k.ring(f"OrbGimbal{index}", (-0.5, 0.15, 1.16), 0.24, 0.017, "trim", hand, (math.pi / 2, index * 1.1, 0.45))


def build_back(k, style):
    if style == "THRUSTERS":
        for side in (-1, 1):
            k.cylinder(f"ThrusterTank{side}", (side * 0.25, -0.36, 1.59), 0.12, 0.58, "metal", "chest")
            k.cylinder(f"ThrusterNozzle{side}", (side * 0.25, -0.36, 1.28), 0.14, 0.1, "dark", "chest")
            k.cylinder(f"ThrusterEnergy{side}", (side * 0.25, -0.36, 1.22), 0.085, 0.02, "glow", "chest")
            k.box(f"ThrusterArmor{side}", (side * 0.25, -0.47, 1.62), (0.18, 0.06, 0.35), "armor", "chest")
    elif style == "REACTOR":
        k.box("ReactorPack", (0, -0.39, 1.55), (0.65, 0.35, 0.58), "dark", "chest", 0.06)
        k.ring("ReactorRing", (0, -0.58, 1.57), 0.23, 0.035, "trim", "chest")
        k.sphere("ReactorCore", (0, -0.58, 1.57), (0.33, 0.07, 0.33), "glow", "chest")
        for x in (-0.28, 0.28):
            for z in (1.38, 1.51, 1.64, 1.77):
                k.box(f"ReactorVent{x}_{z}", (x, -0.6, z), (0.11, 0.05, 0.055), "silver", "chest", 0.008)
    elif style == "CHRONO":
        k.ring("ChronoBackRing", (0, -0.43, 1.80), 0.66, 0.05, "trim")
        k.ring("ChronoInnerRing", (0, -0.44, 1.80), 0.53, 0.017, "glow")
        for index in range(12):
            a = math.tau * index / 12
            start = (math.sin(a) * 0.56, -0.43, 1.80 + math.cos(a) * 0.56)
            end = (math.sin(a) * 0.64, -0.43, 1.80 + math.cos(a) * 0.64)
            k.rod(f"ChronoTick{index}", start, end, 0.018, "silver")
    elif style == "AMMO":
        k.box("AmmoPack", (0, -0.37, 1.55), (0.66, 0.34, 0.63), "armor", "chest", 0.045)
        for i in range(5):
            k.cylinder(f"AmmoShell{i}", (-0.24 + i * 0.12, -0.58, 1.59), 0.043, 0.37, "trim", "chest", vertices=12)
        k.rod("ShoulderTurretMount", (-0.32, -0.32, 1.64), (-0.44, -0.27, 2.03), 0.047)
        k.box("ShoulderTurret", (-0.44, -0.12, 2.1), (0.36, 0.40, 0.26), "armor", "chest", 0.03)
        k.cylinder("ShoulderTurretBarrel", (-0.44, 0.14, 2.1), 0.057, 0.26, "metal", "chest", (math.pi / 2, 0, 0))
        k.sphere("ShoulderTurretSight", (-0.33, 0.085, 2.14), (0.06, 0.035, 0.06), "glow", "chest")


def build_library(path):
    base.clear_file()
    body = base.make_collection("BODY_BASE")
    rig = base.build_balanced(body)
    materials = library_materials()
    role_by_name = {
        "Skin": "skin", "SkinLight": "skin_light", "Hair": "hair", "CreamCloth": "cloth",
        "ClothShadow": "cloth_shadow", "BlueArmor": "armor", "BlueEdge": "edge", "DarkLeather": "dark",
        "BrownLeather": "leather", "Steel": "metal", "BladeEdge": "silver", "WarmBrass": "trim",
        "CyanRune": "glow", "Eye": "eye",
    }
    balanced_equipment = base.make_collection("BALANCED_EQUIPMENT")
    for obj in list(body.objects):
        if obj.type != "MESH":
            continue
        for slot in obj.material_slots:
            role = role_by_name[slot.material.name.removeprefix("Balanced_")]
            slot.material = materials[role]
        if "Sword" in obj.name or "Shield" in obj.name:
            base.move_to_collection(obj, balanced_equipment)
    parts = {"BODY_BASE": body, "BALANCED_EQUIPMENT": balanced_equipment}
    required = sorted({part for entries in STARTER_PARTS.values() for part in entries})
    builders = {"BODY": build_body, "HEAD": build_head, "WEAPON": build_weapon, "OFFHAND": build_offhand, "BACK": build_back}
    for part in required:
        collection = base.make_collection(part)
        kind, style = part.split("_", 1)
        builders[kind](Kit(collection, rig, materials), style)
        collection.asset_mark()
        collection.asset_data.description = f"QQ shared {part.lower()} in the 18-bone rest space"
        parts[part] = collection
    for part_id, collection in parts.items():
        collection["qq_part_id"] = part_id
        for obj in collection.objects:
            if obj.type == "MESH":
                obj["qq_part_id"] = part_id
    # Only the base body is visible when the library is opened for editing.
    for part_id, collection in parts.items():
        collection.hide_render = part_id != "BODY_BASE"
        collection.hide_viewport = part_id != "BODY_BASE"
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(path), check_existing=False, compress=True)
    return sorted(parts)
