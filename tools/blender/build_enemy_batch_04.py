"""Complete the enemy cast in an isolated Blender process, never via live MCP.

The starter library is read-only. Assemblies retain editable component meshes;
only disposable export copies are merged. Scout is rendered from its old GLB.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_starter_batch as shared

base, parts = shared.base, shared.parts
ROOT = shared.ROOT
SOURCE = ROOT / "art_src/blender/characters/qq_enemies_04.blend"
MANIFEST = SOURCE.with_suffix(".manifest.json")
PREVIEWS = ROOT / "art_src/blender/previews"
INTERMEDIATE = ROOT / "tools/.local/enemy_batch_04"
RENDER_SIZE = int(os.environ.get("QQ_ENEMY_RENDER_SIZE", "2048"))
PARTS = {
    "brute": ("BODY_HEAVY", "HEAD_HORNS", "WEAPON_HAMMER"),
    "disruptor": ("BODY_ARCANE", "HEAD_ANTENNA", "WEAPON_STAFF", "OFFHAND_ORB", "BACK_REACTOR"),
    "raider": ("BODY_ASSAULT", "HEAD_HORNS", "WEAPON_GREATSWORD", "BACK_THRUSTERS"),
    "medic_drone": ("WEAPON_BLASTER", "OFFHAND_ORB"),
    "chronoguard": ("BODY_HEAVY", "HEAD_HALO", "WEAPON_STAFF", "OFFHAND_BUCKLER", "BACK_CHRONO"),
    "phase_stalker": ("BODY_LIGHT", "HEAD_HORNS", "BACK_THRUSTERS"),
    "void_bastion": ("BODY_HEAVY", "HEAD_FORTRESS", "OFFHAND_TOWER", "BACK_REACTOR"),
    "echo_revenant": ("BODY_ARCANE", "HEAD_HORNS", "OFFHAND_ORB"),
    "rift_predator": ("BODY_LIGHT",),
    "entropy_colossus": ("BODY_HEAVY", "HEAD_FORTRESS", "WEAPON_HAMMER", "OFFHAND_TOWER", "BACK_REACTOR"),
    "omega_seraph": ("BODY_ARCANE", "HEAD_HALO", "OFFHAND_ORB"),
    "grave_architect": ("BODY_ARCANE", "HEAD_ANTENNA", "OFFHAND_ORB"),
}
SOCKETS = {
    "left_hand": ("left_hand", "LeftHandSocket"),
    "right_hand": ("right_hand", "RightHandSocket"),
    "chest": ("chest", "ChestSocket"),
    "head": ("head", "HeadSocket"),
    "back": ("chest", "BackSocket"),
}
DESIGNS = {
    "brute": "Exposed muscular arms, welded chest plates, damaged rust-red iron, hammer and power pack",
    "disruptor": "Asymmetric induction coils, interference antenna mast, violet armor and yellow signal lamps",
    "raider": "Scratched red assault armor, wrapped shoulders, loot belt and a second hand blade",
    "medic_drone": "Floating medical torso, optic head, three repair arms, ampoules and hovering thrusters",
    "chronoguard": "Clock-knight helmet, dial shield, hour-marked shoulders and brass chrono machinery",
    "phase_stalker": "Split dark plates, exposed phase gaps, swept horns and long paired hooked claws",
    "void_bastion": "Integrated hollow shield wall, void containment ring, cracks and heavy hand cannon",
    "echo_revenant": "Exposed rib cage, torn cloak plates, echo rings, back spikes and a crescent scythe",
    "rift_predator": "Predator jaw and teeth, digitigrade-looking leg armor, rift fins and serrated claws",
    "entropy_colossus": "Crumbled boulder armor, heat-discolored joints, magma seams and impact hammer",
    "omega_seraph": "White ceramic, gold joints, six individual mechanical wings and a ceremonial spear",
    "grave_architect": "Shoulder mausoleums, tomb panels, drafting projector, back spires and survey scythe",
}


def relative(path):
    return str(path.relative_to(ROOT)).replace("\\", "/")


def protected_hashes():
    paths = list((ROOT / "assets/models/battle").glob("*.glb"))
    paths += [p for p in (ROOT / "assets/portraits").glob("*.png") if p.stem not in (*PARTS, "scout")]
    paths += list((ROOT / "art_src/blender/characters").glob("*.blend"))
    paths += [shared.LIBRARY, ROOT / "art_src/blender/battle_vertical_slice.blend",
              ROOT / "art_src/blender/battle_animation_library.blend"]
    return {relative(p): base.file_sha256(p) for p in paths
            if p.exists() and p != SOURCE and p.stem not in PARTS}


def tint(material, color, metal=None):
    material.diffuse_color = color
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    if metal is not None:
        shader.inputs["Metallic"].default_value = metal
        material.metallic = metal


def palette(visual_id, templates):
    materials = shared.palette(visual_id, templates)
    primary = shared.rgba(shared.PROFILES[visual_id]["primary"])
    for role in ("cloth", "cloth_shadow"):
        tint(materials[role], tuple(c * .23 + .02 for c in primary[:3]) + (1,))
    if visual_id == "brute":
        tint(materials["skin"], (.42, .24, .14, 1))
        tint(materials["skin_light"], (.65, .40, .24, 1))
        tint(materials["trim"], (.28, .17, .09, 1), .75)
    elif visual_id in ("medic_drone", "omega_seraph"):
        tint(materials["armor"], (.75, .79, .76, 1), .22)
        tint(materials["edge"], (.95, .96, .89, 1), .15)
        tint(materials["trim"], (.50, .32, .075, 1), .8)
        tint(materials["cloth"], (.14, .19, .18, 1))
    elif visual_id == "entropy_colossus":
        tint(materials["armor"], (.21, .17, .13, 1), .3)
        tint(materials["edge"], (.40, .32, .22, 1), .4)
        tint(materials["trim"], (.38, .16, .065, 1), .6)
    elif visual_id == "void_bastion":
        tint(materials["armor"], (.055, .035, .095, 1), .65)
        tint(materials["edge"], (.12, .10, .18, 1), .75)
    elif visual_id == "echo_revenant":
        tint(materials["silver"], (.48, .49, .43, 1), .5)
    return materials


def copy_library_mesh(source, rig, collection, materials, visual_id):
    obj = source.copy()
    obj.data = source.data.copy()
    obj.name = visual_id + "_" + source.name
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()
    for modifier in obj.modifiers:
        if modifier.type == "ARMATURE":
            modifier.object = rig
    for slot in obj.material_slots:
        slot.material = materials[slot.material["qq_role"]]
    collection.objects.link(obj)
    return obj


def keep_base(visual_id, source):
    bone = source.get("battle_bone", "")
    name = source.name
    if bone == "head":
        return False
    if visual_id == "medic_drone":
        return bone in ("left_hand", "right_hand", "left_forearm", "right_forearm")
    if visual_id == "brute" and bone in ("left_upper_arm", "right_upper_arm", "left_forearm", "right_forearm"):
        return False
    if visual_id == "echo_revenant" and bone in ("spine", "chest"):
        return False
    if any(token in name for token in ("Tabbard", "ChestV", "ChestRune", "TabbardStitch")):
        return False
    return True


def dagger(k, side=-1):
    x, hand = side * .50, "left_hand" if side < 0 else "right_hand"
    k.cylinder("SecondBladeGrip", (x, 0, .9), .04, .24, "leather", hand)
    k.box("SecondBladeGuard", (x, 0, .75), (.30, .09, .055), "trim", hand)
    k.panel("SecondBlade", [(x-.06, .73), (x+.06, .73), (x+.035, .24), (x, .15), (x-.035, .24)], 0, .055, "silver", hand)


def claws(k, beast=False):
    for side in (-1, 1):
        x, hand = side * .50, "left_hand" if side < 0 else "right_hand"
        k.box("ClawGauntlet", (x, .10, .96), (.27, .23, .22), "dark", hand)
        for i in range(3):
            start = x + (i-1)*.085
            k.panel("PredatorClaw" if beast else "PhaseHook", [(start-.025, .89), (start+.025, .89),
                    (start+.03, .38), (start+.09, .20), (start+.065, .43), (start-.035, .50)],
                    .20, .045, "silver", hand, .006)
            k.rod("ClawConduit", (start, .225, .88), (start, .225, .49), .012, "glow", hand)


def scythe(k, angular=False):
    k.rod("ScytheShaft", (.50, 0, .22), (.50, 0, 2.54), .035, "metal", "right_hand")
    points = [(.43, 2.48), (.83, 2.61), (1.21, 2.42), (1.40, 2.02), (1.08, 2.27), (.68, 2.37), (.43, 2.31)]
    if angular:
        points = [(.43, 2.51), (1.22, 2.51), (1.39, 2.12), (1.06, 2.35), (.43, 2.35)]
    k.panel("SurveyScythe" if angular else "EchoScythe", points, 0, .06, "silver", "right_hand", .006)
    k.ring("ScytheAxle", (.53, .045, 2.40), .11, .02, "trim", "right_hand")


def spikes(k, count=5):
    for i in range(count):
        x = (i-(count-1)/2)*.19
        k.panel("BackSpire", [(x-.045, 1.63), (x, 2.18+(.12 if i%2 else 0)), (x+.065, 1.46)], -.39, .065, "edge", "chest")


def cannon(k):
    k.box("VoidCannonHousing", (.50, .10, .73), (.46, .44, .47), "armor", "right_hand")
    for z, r, d, role in ((.37, .18, .45, "metal"), (.13, .21, .12, "edge"), (.06, .13, .018, "dark")):
        k.cylinder("VoidCannonBarrel", (.50, .10, z), r, d, role, "right_hand")
    for x in (.30, .70):
        k.rod("CannonSupport", (x, .22, 1), (x, .22, .28), .035, "trim", "right_hand")


def add_unique(visual_id, k):
    if visual_id == "brute":
        for side in (-1, 1):
            upper = "left_upper_arm" if side < 0 else "right_upper_arm"
            lower = "left_forearm" if side < 0 else "right_forearm"
            k.sphere("ExposedBiceps", (side*.50, 0, 1.57), (.42, .37, .47), "skin_light", upper)
            k.sphere("ExposedForearm", (side*.50, 0, 1.19), (.33, .32, .42), "skin", lower)
            k.ring("WeldedWrist", (side*.50, 0, 1.06), .17, .026, "metal", lower, (0, 0, 0))
            k.box("WeldPatch", (side*.19, .49, 1.55), (.22, .035, .23), "metal", "spine", rotation=(0, side*.17, 0))
            for i in range(4):
                k.box("WeldBead", (side*.29, .52, 1.47+i*.05), (.038, .02, .022), "silver", "spine", .005)
        k.box("PowerPack", (0, -.41, 1.57), (.52, .33, .63), "dark", "chest")
        for x in (-.18, .18):
            k.cylinder("ExhaustStack", (x, -.49, 1.95), .07, .35, "metal", "chest")
        for i in range(5):
            k.box("ChestDamage", (-.23+i*.085, .52, 1.76-i*.045), (.08, .024, .018), "dark", "spine", .003, rotation=(0, .37, 0))
    elif visual_id == "disruptor":
        for i in range(5):
            k.ring("LeftInductionCoil", (-.78, -.13, 1.62+i*.055), .25, .018, "trim", "chest", (0, 0, 0))
        k.rod("CoilMast", (-.78, -.13, 1.48), (-.78, -.13, 2.2), .035, "metal")
        k.ring("InterferenceDish", (-.78, -.13, 2.2), .33, .025, "edge", "chest")
        k.ring("SignalDish", (.49, -.25, 2.13), .23, .025, "trim", "chest", (math.pi/2, .6, 0))
        k.rod("TallInterferenceAntenna", (.49, -.25, 1.95), (.62, -.25, 2.9), .021, "metal")
        for i in range(3):
            k.rod("AntennaCrossbar", (.43, -.25, 2.4+i*.16), (.76, -.25, 2.4+i*.16), .017, "silver")
        k.box("SignalControlPanel", (0, .47, 1.64), (.43, .09, .23), "dark")
        for x in (-.13, 0, .13):
            k.sphere("SignalLamp", (x, .525, 1.68), (.047, .025, .047), "glow", "spine")
    elif visual_id == "raider":
        dagger(k)
        for i in range(4):
            k.box("WrapBand", (-.5, .25, 1.72+i*.04), (.46, .028, .026), "cloth", "left_upper_arm", .004)
            k.cylinder("LootCartridge", (-.23+i*.15, .27, 1.04), .044, .19, "trim", "hips", vertices=12)
            k.box("ArmorScratch", (.09+i*.055, .56, 1.64-i*.045), (.095, .018, .011), "silver", "spine", .002, rotation=(0, .5, 0))
        k.box("LootSatchel", (.33, -.03, .88), (.31, .24, .30), "leather", "hips")
        k.panel("TornWaistCloth", [(-.24, 1.02), (.07, 1.02), (.03, .59), (-.09, .69), (-.18, .51), (-.27, .67)], -.27, .035, "cloth", "hips")
    elif visual_id == "medic_drone":
        k.sphere("FloatingMedicalBody", (0, 0, 1.58), (.87, .55, .75), "armor", "spine")
        k.ring("HoverBodyRim", (0, 0, 1.33), .41, .025, "metal", "spine", (0, 0, 0))
        k.box("MedicalCrossVertical", (0, .29, 1.62), (.095, .04, .30), "glow")
        k.box("MedicalCrossHorizontal", (0, .30, 1.62), (.29, .04, .095), "glow")
        k.sphere("DroneOpticHead", (0, .01, 2.13), (.48, .40, .35), "armor", "head")
        k.ring("MedicalOpticRim", (0, .225, 2.15), .115, .022, "trim", "head")
        k.sphere("MedicalOptic", (0, .23, 2.15), (.18, .06, .18), "glow", "head")
        k.ring("MedicalHalo", (0, -.13, 2.26), .31, .02, "trim", "head")
        for side in (-1, 1):
            upper = "left_upper_arm" if side < 0 else "right_upper_arm"
            k.rod("MainMedicalArm", (side*.36, 0, 1.72), (side*.50, 0, 1.46), .065, "metal", upper)
            k.cylinder("HoverThruster", (side*.24, -.13, 1.18), .13, .26, "metal", "hips")
            k.cylinder("HoverNozzle", (side*.24, -.13, 1.04), .10, .025, "glow", "hips")
        for i in range(3):
            x = (i-1)*.45
            start, elbow, tip = (x*.65, -.28, 1.7), (x*1.7, -.30, 1.93+(i%2)*.18), (x*1.85, .05, 1.78+(i%2)*.18)
            k.rod("RepairArmBase", start, elbow, .034, "metal", "chest")
            k.sphere("RepairArmJoint", elbow, (.10, .10, .10), "trim", "chest")
            k.rod("RepairArmTip", elbow, tip, .026, "silver", "chest")
            k.sphere("RepairToolLight", tip, (.07, .07, .07), "glow", "chest")
        k.box("MedicalPowerPack", (0, -.37, 1.60), (.45, .22, .43), "dark", "chest")
        for x in (-.18, 0, .18):
            k.cylinder("MedicalAmpoule", (x, -.50, 1.68), .055, .29, "glow", "chest")
    elif visual_id == "chronoguard":
        k.ring("DialShield", (-.50, .30, 1.02), .37, .03, "trim", "left_hand")
        for i in range(12):
            angle = i*math.tau/12
            k.box("ShieldHour", (-.5+math.sin(angle)*.32, .325, 1.02+math.cos(angle)*.32), (.025, .02, .065), "silver", "left_hand", .003, (0, angle, 0))
        k.rod("ShieldClockHand", (-.50, .34, 1.02), (-.34, .34, 1.22), .022, "glow", "left_hand")
        k.panel("ClockKnightVisor", [(-.23, 2.44), (.23, 2.44), (.18, 2.24), (0, 2.12), (-.18, 2.24)], .34, .06, "trim", "head")
        for side in (-1, 1):
            bone = "left_upper_arm" if side < 0 else "right_upper_arm"
            k.ring("ClockShoulder", (side*.5, .26, 1.85), .23, .026, "trim", bone)
            for i in range(4):
                a = i*math.pi/2
                k.sphere("ShoulderHour", (side*.5+math.sin(a)*.23, .27, 1.85+math.cos(a)*.23), (.04, .026, .04), "glow", bone)
    elif visual_id == "phase_stalker":
        claws(k)
        for side in (-1, 1):
            for i in range(4):
                x = side*(.12+i*.047)
                k.panel("SplitPhaseChest", [(x-.035, 1.39), (x+.025, 1.38), (x+.04, 1.81), (x-.025, 1.76)], .46, .03, "dark", "spine", .005)
                k.rod("PhaseGap", (x, .49, 1.48), (x+.006, .49, 1.75), .01, "glow", "spine")
            k.panel("SweptPhaseHorn", [(side*.2, 2.40), (side*.49, 2.86), (side*.37, 2.45)], -.06, .065, "dark", "head")
        k.box("PhaseMaskSlit", (0, .36, 2.33), (.25, .02, .025), "glow", "head", .005)
    elif visual_id == "void_bastion":
        cannon(k)
        k.ring("HollowVoidCore", (0, .54, 1.64), .27, .05, "metal", "spine")
        k.sphere("VoidCoreInterior", (0, .51, 1.64), (.40, .06, .40), "dark", "spine")
        k.ring("VoidContainment", (0, .555, 1.64), .18, .013, "glow", "spine")
        for side in (-1, 1):
            bone = "left_upper_arm" if side < 0 else "right_upper_arm"
            k.panel("IntegratedWall", [(side*.28, 1.51), (side*.79, 1.50), (side*.88, 2.07), (side*.36, 2.00)], .04, .46, "armor", bone)
        for i in range(4):
            k.rod("ShieldCrack", (-.78+i*.13, .43, .52+i*.22), (-.59+i*.08, .44, .73+i*.20), .014, "glow", "left_hand")
        k.box("VoidBrowSlit", (0, .35, 2.36), (.32, .02, .04), "glow", "head", .005)
    elif visual_id == "echo_revenant":
        scythe(k)
        spikes(k)
        k.rod("ExposedSternum", (0, .18, 1.30), (0, .18, 1.81), .045, "silver", "spine")
        for side in (-1, 1):
            for i in range(4):
                k.rod("EchoRib", (side*.02, .18, 1.41+i*.105), (side*(.22+i*.027), .13, 1.35+i*.105), .027, "silver", "spine")
            for i in range(3):
                x = side*(.08+i*.13)
                k.panel("TornCloak", [(x-.045, 1.35), (x+.06, 1.31), (x+.1, .35+i*.11), (x+.015, .51+i*.08), (x-.035, .30+i*.1)], -.38, .035, "cloth_shadow", "hips", .004)
        for radius, y in ((.45, -.34), (.59, -.39)):
            k.ring("EchoResonanceRing", (0, y, 1.96), radius, .018, "glow", "chest")
        k.panel("SkullFace", [(-.17, 2.40), (.17, 2.40), (.13, 2.17), (0, 2.10), (-.13, 2.17)], .36, .045, "silver", "head")
        for x in (-.085, .085):
            k.sphere("SkullSocket", (x, .393, 2.32), (.10, .022, .08), "dark", "head")
    elif visual_id == "rift_predator":
        claws(k, True)
        dagger(k)
        spikes(k, 7)
        k.sphere("PredatorSkull", (0, .03, 2.30), (.53, .49, .57), "armor", "head", False)
        k.box("PredatorSnout", (0, .35, 2.25), (.40, .41, .22), "edge", "head", .07)
        k.box("PredatorJaw", (0, .32, 2.08), (.35, .35, .14), "dark", "head", .04)
        for side in (-1, 1):
            k.panel("PredatorEarHorn", [(side*.17, 2.45), (side*.37, 2.87), (side*.33, 2.41)], -.08, .10, "edge", "head")
            k.rod("PredatorEye", (side*.055, .38, 2.43), (side*.19, .35, 2.48), .019, "glow", "head")
            for i in range(3):
                x = side*(.06+i*.055)
                k.panel("PredatorFang", [(x-.02, 2.19), (x+.02, 2.19), (x, 2.10)], .55, .035, "silver", "head", .003)
            leg = "left_lower_leg" if side < 0 else "right_lower_leg"
            k.rod("RaisedHock", (side*.23, -.15, .51), (side*.23, -.24, .23), .08, "edge", leg)
            k.panel("RiftMembrane", [(side*.31, 1.52), (side*.8, 1.91), (side*.66, 1.3), (side*.43, 1.11)], -.2, .035, "cloth_shadow", "chest", .004)
            k.rod("RiftFinEdge", (side*.35, -.16, 1.5), (side*.8, -.16, 1.91), .018, "glow", "chest")
    elif visual_id == "entropy_colossus":
        for side in (-1, 1):
            bone = "left_upper_arm" if side < 0 else "right_upper_arm"
            k.sphere("BoulderShoulder", (side*.57, -.015, 1.89), (.70, .56, .43), "edge", bone, False)
            for i in range(3):
                k.box("CrumbledArmorBlock", (side*(.14+i*.09), .52, 1.42+i*.12), (.22, .18, .20), "armor", "spine", .015, (0, side*.28, i*.19))
                k.rod("MagmaJoint", (side*(.13+i*.09), .62, 1.42+i*.12), (side*(.2+i*.09), .62, 1.50+i*.12), .014, "glow", "spine")
            lower = "left_lower_leg" if side < 0 else "right_lower_leg"
            k.box("BoulderGreave", (side*.23, .12, .30), (.32, .33, .38), "armor", lower, .025, (0, side*.11, 0))
        for i in range(4):
            k.panel("ShieldCrumbledSlab", [(-.84+i*.16, 1.41), (-.74+i*.16, 1.5), (-.70+i*.16, .42), (-.85+i*.16, .37)], .445, .09, "edge", "left_hand", .007)
        for x in (-.18, 0, .18):
            k.rod("ColossusHeatVent", (x, -.57, 1.3), (x, -.57, 2.1), .043, "metal", "chest")
            k.sphere("VentHeat", (x, -.57, 2.1), (.08, .08, .08), "glow", "chest")
    elif visual_id == "omega_seraph":
        k.rod("CeremonialSpear", (.50, 0, -.05), (.50, 0, 2.53), .034, "trim", "right_hand")
        k.panel("SpearTip", [(.50, 2.89), (.38, 2.55), (.50, 2.44), (.62, 2.55)], 0, .055, "silver", "right_hand")
        for side in (-1, 1):
            for i in range(3):
                x, top = side*(.48+i*.14), 2.92-i*.49
                tip = side*(1.30+i*.13)
                k.panel("SeraphWing", [(side*.30, 1.83-i*.12), (x, top), (tip, top+.14), (tip-side*.13, top-.24), (side*.61, 1.59-i*.12)], -.35-i*.045, .055, "edge", "chest", .009)
                k.rod("WingGoldSpar", (side*.31, -.29-i*.045, 1.81-i*.12), (tip, -.29-i*.045, top+.10), .018, "trim", "chest")
                for j in range(3):
                    k.rod("WingFeatherJoint", (x+side*j*.12, -.31-i*.045, top-.17-j*.03), (x+side*(j+.6)*.12, -.31-i*.045, top-.25-j*.05), .013, "trim", "chest")
        k.panel("SeraphCeramicBreast", [(-.26, 1.82), (.26, 1.82), (.18, 1.42), (0, 1.35), (-.18, 1.42)], .47, .06, "edge")
        k.ring("SeraphSeal", (0, .515, 1.63), .13, .024, "trim", "spine")
    elif visual_id == "grave_architect":
        scythe(k, True)
        spikes(k)
        for side in (-1, 1):
            bone = "left_upper_arm" if side < 0 else "right_upper_arm"
            k.box("MausoleumShoulder", (side*.57, -.02, 1.98), (.34, .39, .48), "armor", bone, .015)
            for dx in (-.11, .11):
                k.rod("MausoleumColumn", (side*.57+dx, .22, 1.76), (side*.57+dx, .22, 2.22), .025, "silver", bone)
            k.panel("ShoulderPediment", [(side*.57-.22, 2.19), (side*.57, 2.38), (side*.57+.22, 2.19)], .06, .38, "edge", bone, .01)
            k.box("TombPanel", (side*.18, .26, .98), (.23, .11, .48), "metal", "hips", .024)
            for i in range(3):
                k.box("TombInlay", (side*.18, .33, .84+i*.09), (.12, .015, .018), "glow", "hips", .003)
        k.ring("DraftingProjector", (-.50, .33, 1.16), .28, .02, "trim", "left_hand")
        for x in (-.68, -.32):
            k.rod("BlueprintColumn", (x, .34, 1.30), (x, .34, 1.65), .008, "glow", "left_hand")
        for z in (1.30, 1.65):
            k.rod("BlueprintBeam", (-.68, .34, z), (-.32, .34, z), .008, "glow", "left_hand")


def add_sockets(collection, rig):
    for socket_id, (bone, name) in SOCKETS.items():
        obj = bpy.data.objects.new(name, None)
        obj.empty_display_size = .08
        obj.parent, obj.parent_type, obj.parent_bone = rig, "BONE", bone
        obj.location = (0, -.12, 0)
        obj["socket_id"], obj["socket_bone"] = socket_id, bone
        collection.objects.link(obj)


def verify_rig(rig):
    expected = {name: parent for name, parent, _ in base.BONE_DEFINITIONS}
    assert {bone.name for bone in rig.data.bones} == set(expected)
    for bone in rig.data.bones:
        assert (bone.parent.name if bone.parent else "") == expected[bone.name]
    for clip_id, clip in shared.CATALOG["clips"].items():
        for index in range(len(clip["keyframes"])):
            shared.set_pose(rig, clip_id, index)
            for bone in rig.pose.bones:
                assert all(math.isfinite(v) for row in bone.matrix for v in row), (rig.name, clip_id)
    reset_rig(rig)


def reset_rig(rig):
    rig.location = (0, 0, 0)
    rig.rotation_euler = (0, 0, 0)
    rig.scale = (1, 1, 1)
    for bone in rig.pose.bones:
        bone.rotation_mode = "QUATERNION"
        bone.rotation_quaternion.identity()
        bone.location = (0, 0, 0)
        bone.scale = (1, 1, 1)
    bpy.context.view_layer.update()


def export_copy(visual_id, source_collection, rig):
    reset_rig(rig)
    export = base.make_collection("EXPORT_" + visual_id)
    clone = rig.copy()
    clone.data = rig.data.copy()
    export.objects.link(clone)
    for source in source_collection.objects:
        if source.type != "MESH":
            continue
        obj = source.copy()
        obj.data = source.data.copy()
        obj.parent = clone
        for modifier in obj.modifiers:
            if modifier.type == "ARMATURE":
                modifier.object = clone
        export.objects.link(obj)
    mesh = base.merge_character_meshes(export, clone, visual_id)
    weighted = shared.validate_skin(mesh, clone)
    mesh.data.calc_loop_triangles()
    triangles = len(mesh.data.loop_triangles)
    assert 0 < triangles <= 35000, (visual_id, triangles)
    assert all(math.isfinite(v) for vertex in mesh.data.vertices for v in vertex.co)
    add_sockets(export, clone)
    target = ROOT / f"assets/models/battle/{visual_id}.glb"
    base.export_character(export, target)
    entry = {"id": visual_id, "kind": "enemy", "new_model": True, "design": DESIGNS[visual_id],
             "parts": ["BODY_BASE", *PARTS[visual_id]], "editable_meshes": len([o for o in source_collection.objects if o.type == "MESH"]),
             "vertices": len(mesh.data.vertices), "triangles": triangles, "materials": len(mesh.data.materials),
             "bones": 18, "weighted_bones": weighted, "sockets": SOCKETS,
             "clips_checked": sorted(shared.CATALOG["clips"]), "all_keyframes_checked": True,
             "model": relative(target), "model_sha256": base.file_sha256(target), "model_bytes": target.stat().st_size}
    for obj in list(export.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(export)
    return entry


def import_scout():
    before = set(bpy.data.objects)
    target = ROOT / "assets/models/battle/scout.glb"
    bpy.ops.import_scene.gltf(filepath=str(target), bone_heuristic="BLENDER")
    objects = set(bpy.data.objects) - before
    collection = base.make_collection("ENEMY_scout")
    rigs = [obj for obj in objects if obj.type == "ARMATURE"]
    assert len(rigs) == 1
    rig = rigs[0]
    for obj in objects:
        base.move_to_collection(obj, collection)
    rig.name = "scoutArmature"
    reset_rig(rig)
    assert len(rig.data.bones) == 18
    entry = {"id": "scout", "kind": "enemy", "new_model": False,
             "design": "Portrait rendered from the unchanged first-batch scout.glb",
             "parts": ["existing_scout_glb"], "model": relative(target),
             "model_sha256": base.file_sha256(target), "model_bytes": target.stat().st_size,
             "bones": 18, "sockets": SOCKETS, "clips_checked": sorted(shared.CATALOG["clips"])}
    return collection, rig, entry


def render_one(visual_id, rig, camera, preview=False):
    profile = shared.PROFILES[visual_id]
    scale = profile["body_scale"]
    reset_rig(rig)
    rig.scale = (scale[0], scale[2], scale[1])
    if visual_id != "scout":
        shared.set_pose(rig, "idle", 1)
    camera.location = (3.2, 7, 3.5)
    target_height = 1.91*scale[1]
    if visual_id == "medic_drone":
        target_height = 1.69*scale[1]
    base.look_at(camera, Vector((0, .02, target_height)))
    camera.data.ortho_scale = (2.08 if visual_id in ("omega_seraph", "disruptor") else 1.94)*scale[1]
    scene = bpy.context.scene
    scene.render.resolution_x = scene.render.resolution_y = 1024 if preview else RENDER_SIZE
    scene.render.filepath = str(INTERMEDIATE / f"{visual_id}_portrait.png")
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(scene.render.filepath, check_existing=False)
    img.scale(1024, 1024)
    path = ROOT / f"assets/portraits/{visual_id}.png"
    img.filepath_raw = str(path)
    img.save()
    bpy.data.images.remove(img)
    print("ENEMY_04_PORTRAIT_OK", visual_id, flush=True)
    return {"portrait": relative(path), "portrait_sha256": base.file_sha256(path),
            "portrait_bytes": path.stat().st_size, "portrait_size": [1024, 1024]}


def render_lineups(models, camera):
    paths = []
    lights = list(bpy.data.lights)
    for light in lights:
        light.energy *= 1.8
        light.size *= 1.6
    for page in range(3):
        ids = list(models)[page*5:(page+1)*5]
        for name, (collection, rig) in models.items():
            collection.hide_render = name not in ids
            reset_rig(rig)
            if name in ids:
                i = ids.index(name)
                rig.location.x = (i-(len(ids)-1)/2)*3.30
                s = shared.PROFILES[name]["body_scale"]
                rig.scale = (s[0], s[2], s[1])
        camera.location = (1.3, 22, 8)
        base.look_at(camera, Vector((0, 0, 1.5)))
        # Ortho scale is horizontal for this wide frame: retain full height on
        # the three-character page too, including the Seraph's tallest wings.
        camera.data.ortho_scale = 17.5
        scene = bpy.context.scene
        scene.render.resolution_x, scene.render.resolution_y = 2400, 700
        path = PREVIEWS / f"enemy_batch_04_lineup_{page+1}.png"
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        paths.append({"path": relative(path), "sha256": base.file_sha256(path), "ids": ids})
    for light in lights:
        light.energy /= 1.8
        light.size /= 1.6
    return paths


def cold_validate():
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assert Path(bpy.data.filepath).resolve() == SOURCE.resolve()
    assert not bpy.data.is_dirty
    for kind in ("source", "generator", "library"):
        assert base.file_sha256(ROOT / manifest[kind]) == manifest[kind + "_sha256"], kind
    assert manifest["completeness"]["new_models"] == 12
    assert manifest["completeness"]["portraits"] == 13
    assert {e["id"] for e in manifest["assets"]} == {*PARTS, "scout"}
    assert len(bpy.data.libraries) == 1
    assert bpy.data.libraries[0].filepath.startswith("//")
    for entry in manifest["assets"]:
        collection = bpy.data.collections["ENEMY_" + entry["id"]]
        rig = next(o for o in collection.objects if o.type == "ARMATURE")
        assert len(rig.data.bones) == 18
        assert all(math.isfinite(v) for o in collection.objects if o.type == "MESH" for vertex in o.data.vertices for v in vertex.co)
        if entry["new_model"]:
            verify_rig(rig)
            assert len([o for o in collection.objects if o.type == "MESH"]) == entry["editable_meshes"]
        for kind in ("model", "portrait"):
            path = ROOT / entry[kind]
            assert base.file_sha256(path) == entry[kind + "_sha256"], path
        with (ROOT / entry["portrait"]).open("rb") as f:
            header = f.read(24)
        assert header[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(">II", header[16:24]) == (1024, 1024)
    for path, digest in manifest["protected_assets"].items():
        assert base.file_sha256(ROOT / path) == digest, "Protected asset changed: " + path
    print("ENEMY_04_COLD_RELOAD_OK 12 editable models, 13 portraits, linked library, hashes, protected prior assets", flush=True)


def refresh_previews():
    """Repair framing without touching model or portrait bytes already integrated."""
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assert Path(bpy.data.filepath).resolve() == SOURCE.resolve()
    for entry in manifest["assets"]:
        for kind in ("model", "portrait"):
            assert base.file_sha256(ROOT / entry[kind]) == entry[kind + "_sha256"]
    models = {}
    for visual_id in (*PARTS, "scout"):
        collection = bpy.data.collections["ENEMY_" + visual_id]
        rig = next(obj for obj in collection.objects if obj.type == "ARMATURE")
        models[visual_id] = (collection, rig)
    camera = bpy.context.scene.camera
    manifest["previews"] = render_lineups(models, camera)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE), check_existing=False, compress=True)
    manifest["source_sha256"] = base.file_sha256(SOURCE)
    manifest["generator_sha256"] = base.file_sha256(Path(__file__))
    manifest["preview_framing_revision"] = 2
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    cold_validate()
    print("ENEMY_04_PREVIEW_REFRESH_OK runtime GLB/portrait bytes unchanged", flush=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.threads_mode = "FIXED"
    bpy.context.scene.render.threads = 4
    for folder in (SOURCE.parent, PREVIEWS, INTERMEDIATE):
        folder.mkdir(parents=True, exist_ok=True)
    protected = protected_hashes()
    required = sorted({"BODY_BASE", *(part for values in PARTS.values() for part in values)})
    with bpy.data.libraries.load(str(shared.LIBRARY), link=True) as (available, loaded):
        assert set(required) <= set(available.collections)
        loaded.collections = required
    library = {c.name: c for c in loaded.collections}
    links = base.make_collection("SOURCE_LINKS")
    links.hide_render = links.hide_viewport = True
    for collection in library.values():
        obj = bpy.data.objects.new("Source_" + collection.name, None)
        obj.instance_type, obj.instance_collection = "COLLECTION", collection
        links.objects.link(obj)
    templates = {m["qq_role"]: m for m in bpy.data.materials if m.library and "qq_role" in m}
    models, entries = {}, []
    for visual_id, part_ids in PARTS.items():
        collection = base.make_collection("ENEMY_" + visual_id)
        rig = base.create_armature(visual_id, collection)
        materials = palette(visual_id, templates)
        for part_id in ("BODY_BASE", *part_ids):
            for obj in library[part_id].objects:
                if obj.type == "MESH" and (part_id != "BODY_BASE" or keep_base(visual_id, obj)):
                    copy_library_mesh(obj, rig, collection, materials, visual_id)
        add_unique(visual_id, parts.Kit(collection, rig, materials))
        add_sockets(collection, rig)
        collection["source_parts"] = json.dumps(part_ids)
        collection["design"] = DESIGNS[visual_id]
        rig["authored_detail_tier"] = "enemy_batch_04"
        verify_rig(rig)
        entry = export_copy(visual_id, collection, rig)
        entries.append(entry)
        models[visual_id] = (collection, rig)
        print("ENEMY_04_MODEL_OK", visual_id, entry["triangles"], "triangles", flush=True)
    collection, rig, entry = import_scout()
    models["scout"] = (collection, rig)
    entries.append(entry)
    camera = shared.setup_render()
    for visual_id, (collection, rig) in models.items():
        for other, _ in models.values():
            other.hide_render = other != collection
        next(e for e in entries if e["id"] == visual_id).update(render_one(visual_id, rig, camera))
    previews = render_lineups(models, camera)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE), check_existing=False, compress=True)
    for library_block in bpy.data.libraries:
        library_block.filepath = bpy.path.relpath(library_block.filepath).replace("\\", "/")
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE), check_existing=False, compress=True)
    manifest = {"format_version": 1, "batch_id": "blender_enemies_04", "created_utc": datetime.now(timezone.utc).isoformat(),
                "blender_version": bpy.app.version_string, "generator": relative(Path(__file__)),
                "generator_sha256": base.file_sha256(Path(__file__)), "source": relative(SOURCE),
                "source_sha256": base.file_sha256(SOURCE), "library": relative(shared.LIBRARY),
                "library_sha256": base.file_sha256(shared.LIBRARY),
                "dependencies": [{"path": relative(Path(m.__file__)), "sha256": base.file_sha256(Path(m.__file__))}
                                 for m in (shared, parts, base)],
                "animation_catalog": "data/battle_animations.json",
                "animation_catalog_sha256": base.file_sha256(ROOT / "data/battle_animations.json"),
                "render_size": RENDER_SIZE, "portrait_size": 1024, "render_engine": "BLENDER_EEVEE", "cpu_threads": 4,
                "bone_names": [name for name, _, _ in base.BONE_DEFINITIONS], "socket_definitions": SOCKETS,
                "completeness": {"new_models": 12, "portraits": 13, "preserved_scout_model": True,
                                 "expected_ids": [*PARTS, "scout"], "all_requested_ids_present": True},
                "protected_assets": protected, "previews": previews, "assets": entries,
                "integration": "Parent must register new model_scene mappings and provenance from this manifest"}
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    cold_validate()
    print("ENEMY_BATCH_04_OK 12 new GLBs, 13 matching portraits including unchanged-GLB Scout", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--validate", action="store_true")
    parser.add_argument("--refresh-previews", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    if args.validate:
        cold_validate()
    elif args.refresh_previews:
        refresh_previews()
    else:
        main()
