"""Editable Blender pictograms, rendered in an isolated background process.

Only this batch's PNGs and source are written. The parent release integrates the
aggregate manifest into provenance; no live Blender/MCP session is touched.
"""

from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art_src/blender/ui/qq_small_icons.blend"
MANIFEST = SOURCE.with_suffix(".manifest.json")
INTERMEDIATE = ROOT / "tools/.local/blender_ui_batch"
RENDER_SIZE = 512
BATCH_ID = "blender_ui_icons_06"
UI_IDS = ["speed", "shield", "hp", "gold", "step", "time", "relic", "card_owned",
          "card_equipped", "settings", "version_history", "card"]
EFFECT_IDS = ["shield_spend", "delay", "haste", "recast", "interrupt", "cleanse",
              "empower", "auto_queue", "timeline_stop", "timeline_reverse", "status", "effect"]
MAP_IDS = ["normal_battle", "elite_battle", "boss", "shop", "forge", "heal", "event", "hazard", "lock"]
CONTROL_IDS = ["checkbox_on", "checkbox_off", "checkbox_on_disabled", "checkbox_off_disabled",
               "switch_on", "switch_off", "switch_on_disabled", "switch_off_disabled",
               "slider_grabber", "slider_grabber_highlight"]
MATERIALS = {}
CURRENT = None


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return path.relative_to(ROOT).as_posix()


def material(name, color, metallic=0.25, emission=0.0):
    mat = bpy.data.materials.new("QQ_UI_" + name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = 0.36
    shader.inputs["Emission Color"].default_value = (*color, 1)
    shader.inputs["Emission Strength"].default_value = emission
    return mat


def materials():
    colors = {
        "iron": (0.025, 0.048, 0.066), "steel": (0.37, 0.60, 0.69),
        "white": (0.82, 0.95, 1.0), "cyan": (0.12, 0.70, 0.93),
        "teal": (0.16, 0.68, 0.61), "amber": (1.0, 0.59, 0.10),
        "gold": (0.92, 0.69, 0.21), "red": (0.98, 0.13, 0.22),
        "green": (0.24, 0.89, 0.43), "violet": (0.64, 0.40, 0.93),
        "disabled": (0.22, 0.29, 0.32), "dim": (0.055, 0.088, 0.105),
    }
    for name, color in colors.items():
        MATERIALS[name] = material(name, color, 0.48 if name in ("steel", "gold", "iron") else 0.18,
                                   0.15 if name not in ("iron", "dim", "disabled") else 0)


def finish(obj, name, role, bevel=0):
    obj.name = CURRENT.name + "_" + name
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    CURRENT.objects.link(obj)
    obj.data.materials.append(MATERIALS[role])
    if bevel:
        mod = obj.modifiers.new("Machined_Edges", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        obj.modifiers.new("Weighted_Face_Normals", "WEIGHTED_NORMAL")
    return obj


def box(name, x, z, w, h, role, y=0, depth=0.15, bevel=0.035):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, z))
    obj = bpy.context.object
    obj.scale = (w, depth, h)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, role, min(bevel, w/4, h/4, depth/3))


def shape(name, points, role, y=0, depth=0.15, bevel=0.025):
    count = len(points)
    verts = [(x, y-depth/2, z) for x, z in points] + [(x, y+depth/2, z) for x, z in points]
    faces = [tuple(range(count-1, -1, -1)), tuple(range(count, 2*count))]
    faces += [(i, (i+1) % count, (i+1) % count+count, i+count) for i in range(count)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    CURRENT.objects.link(obj)
    return finish(obj, name, role, bevel)


def disc(name, x, z, radius, role, y=0, depth=0.12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=radius, depth=depth,
                                       location=(x, y, z), rotation=(math.pi/2, 0, 0))
    return finish(bpy.context.object, name, role, 0.018)


def sphere(name, x, z, radius, role, y=-0.1):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=radius,
                                       location=(x, y, z))
    obj = finish(bpy.context.object, name, role)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def pipe(name, points, radius, role, y=-0.15):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 4
    spline = curve.splines.new("POLY")
    spline.points.add(len(points)-1)
    for point, (x, z) in zip(spline.points, points):
        point.co = (x, y, z, 1)
    obj = bpy.data.objects.new(name, curve)
    CURRENT.objects.link(obj)
    return finish(obj, name, role)


def ring(name, x, z, radius, role, y=-0.1, thickness=0.06, start=0, end=math.tau):
    return pipe(name, [(x+math.sin(a)*radius, z+math.cos(a)*radius)
                      for a in [start+(end-start)*i/96 for i in range(97)]], thickness, role, y)


def star(name, x, z, radius, role, y=-0.22, arms=4):
    points = []
    for i in range(arms*2):
        angle = math.pi/2 + i*math.pi/arms
        r = radius if i % 2 == 0 else radius*0.28
        points.append((x+math.cos(angle)*r, z+math.sin(angle)*r))
    return shape(name, points, role, y)


def arrow(name, x, z, scale, role, direction="right", y=-0.25):
    points = [(-.72, -.13), (.18, -.13), (.18, -.40), (.77, 0), (.18, .40), (.18, .13), (-.72, .13)]
    angle = {"right": 0, "up": math.pi/2, "left": math.pi, "down": -math.pi/2}[direction]
    return shape(name, [(x+(a*math.cos(angle)-b*math.sin(angle))*scale,
                         z+(a*math.sin(angle)+b*math.cos(angle))*scale) for a, b in points], role, y)


def bolts(radius=.83, role="steel", count=4):
    for i in range(count):
        a = math.tau*i/count+math.pi/4
        disc("Rim_Rivet", math.sin(a)*radius, math.cos(a)*radius, .035, role, -.13, .055)


def medal():
    disc("Medallion_Recess", 0, 0, .85, "iron", .06)
    ring("Silver_Rim", 0, 0, .89, "steel", 0, .06)
    ring("Inner_Inlay", 0, 0, .75, "cyan", -.045, .018)
    bolts()


def shield(role="cyan", broken=False):
    if broken:
        shape("Cracked_Left", [(-.70, .65), (-.07, .83), (.06, .30), (-.20, .04), (.02, -.28), (-.05, -.87), (-.52, -.38)], role, -.1)
        shape("Cracked_Right", [(.11, .83), (.71, .65), (.56, -.36), (.16, -.85), (.22, -.28), (-.04, .04), (.22, .32)], role, -.1)
    else:
        points = [(-.70, .64), (0, .87), (.70, .64), (.58, -.22), (0, -.88), (-.58, -.22)]
        shape("Shield_Beveled_Rim", points, "steel", .0, .20, .04)
        shape("Shield_Enamel", [(x*.86, z*.86) for x, z in points], role, -.13, .08)
        pipe("Shield_Ridge", [(0, .64), (0, -.62)], .035, "white", -.205)


def clock(x=0, z=0, scale=1, arrows=False):
    disc("Clock_Recess", x, z, .67*scale, "iron", .04)
    ring("Clock_Machined_Rim", x, z, .71*scale, "steel", -.06, .065*scale)
    for i in range(12):
        a = math.tau*i/12
        r = .59*scale
        pipe("Clock_Index", [(x+math.sin(a)*r, z+math.cos(a)*r),
                             (x+math.sin(a)*(r-.065*scale), z+math.cos(a)*(r-.065*scale))], .018*scale, "white", -.12)
    pipe("Minute_Hand", [(x, z-.06*scale), (x, z+.44*scale)], .039*scale, "white", -.16)
    pipe("Hour_Hand", [(x, z), (x+.30*scale, z-.1*scale)], .039*scale, "cyan", -.17)
    disc("Clock_Axle", x, z, .065*scale, "gold", -.22)
    if arrows:
        ring("Recast_Arc", x, z, .89*scale, "cyan", -.20, .057*scale, -.2, 4.9)
        arrow("Recast_Arrow", x-.85*scale, z+.13*scale, .34*scale, "cyan", "up", -.22)


def card(x=0, z=0, role="cyan", y=0, scale=1, marked=False):
    box("Card_Steel_Edge", x, z, .92*scale, 1.26*scale, "steel", y, .12, .03)
    box("Card_Enamel", x, z, .80*scale, 1.13*scale, role, y-.08, .05, .02)
    star("Card_Emblem", x, z+.15*scale, .25*scale, "white", y-.16)
    box("Card_Caption", x, z-.36*scale, .50*scale, .055*scale, "white", y-.16, .035, .008)
    if marked:
        arrow("Equip_Mark", x+.32*scale, z-.18*scale, .50*scale, "green", "up", y-.25)


def blade(name, angle=0, role="white", x=0, z=0, scale=1, y=0, broken=False):
    def transform(points):
        return [(x+(a*math.cos(angle)-b*math.sin(angle))*scale,
                 z+(a*math.sin(angle)+b*math.cos(angle))*scale) for a, b in points]
    if broken:
        shape(name+"Broken_Blade", transform([(-.10, -.17), (.12, .02), (-.08, .22), (.12, .29), (.10, .78), (0, .96), (-.10, .78)]), role, y)
    else:
        shape(name+"Blade", transform([(-.105, -.2), (.105, -.2), (.105, .70), (0, .98), (-.105, .70)]), role, y)
        pipe(name+"Fuller", transform([(0, -.14), (0, .68)]), .018, "cyan", y-.1)
    shape(name+"Guard", transform([(-.33, -.20), (.33, -.20), (.29, -.34), (-.29, -.34)]), "gold", y-.06)
    pipe(name+"Grip", transform([(0, -.36), (0, -.79)]), .075, "iron", y)
    sphere(name+"Pommel", *transform([(0, -.86)])[0], .11*scale, "gold", y)


def coin(x=0, z=0, scale=1, y=0):
    disc("Coin_Milled_Edge", x, z, .59*scale, "gold", y, .18)
    ring("Coin_Bright_Rim", x, z, .48*scale, "amber", y-.12, .035*scale)
    shape("Coin_Diamond", [(x, z+.27*scale), (x+.19*scale, z), (x, z-.27*scale), (x-.19*scale, z)], "white", y-.14, .07)


def cross(role="red", scale=1):
    box("Medical_Vertical", 0, 0, .34*scale, 1.44*scale, role, -.11, .24)
    box("Medical_Horizontal", 0, 0, 1.44*scale, .34*scale, role, -.11, .24)


def crown():
    shape("Crown", [(-.90, .65), (-.47, .27), (0, .91), (.47, .27), (.90, .65), (.69, -.50), (-.69, -.50)], "gold", -.10, .22, .035)
    box("Crown_Band", 0, -.40, 1.48, .22, "amber", -.25, .10)
    shape("Crown_Ruby", [(0, .21), (.16, -.02), (0, -.24), (-.16, -.02)], "red", -.32, .12)
    for x in (-.53, .53):
        disc("Crown_Rivet", x, -.38, .045, "white", -.32)


def lock():
    # Open space inside the shackle and around the body is true transparent alpha.
    points = [(-.43, .03), (-.43, .46)]
    points += [(.43*math.cos(a), .46+.43*math.sin(a)) for a in [math.pi-i*math.pi/48 for i in range(49)]]
    points += [(.43, .03)]
    pipe("Solid_Steel_Shackle", points, .10, "white", -.03)
    box("Lock_Body", 0, -.34, 1.29, .82, "steel", -.03, .27, .08)
    disc("Keyhole_Round", 0, -.23, .105, "iron", -.19, .03)
    shape("Keyhole_Stem", [(-.055, -.25), (.055, -.25), (.085, -.52), (-.085, -.52)], "iron", -.205, .03, .005)
    for x in (-.46, .46):
        disc("Lock_Rivet", x, -.54, .035, "white", -.195, .035)


def ui_icon(icon_id):
    if icon_id == "shield":
        shield("teal")
    elif icon_id == "hp":
        points = []
        for i in range(96):
            a = math.tau*i/96
            points.append((16*math.sin(a)**3/18, (13*math.cos(a)-5*math.cos(2*a)-2*math.cos(3*a)-math.cos(4*a))/18))
        shape("Heart_Enamel", points, "red", -.03, .25, .035)
        pipe("Pulse", [(-.65, .03), (-.29, .03), (-.13, .28), (.03, -.29), (.19, .04), (.54, .04)], .045, "white", -.205)
    elif icon_id == "speed":
        for i in range(3):
            x = -.84+i*.55
            shape("Tempo_Chevron", [(x, -.67), (x+.40, 0), (x, .67), (x+.25, .67), (x+.66, 0), (x+.25, -.67)], "green" if i == 2 else "cyan", -.08-i*.035)
    elif icon_id == "gold":
        coin(-.20, -.05, .95, .04)
        coin(.37, .33, .7, .22)
    elif icon_id == "time":
        clock()
        box("Stopwatch_Button", 0, .85, .33, .15, "gold", .01)
    elif icon_id == "step":
        for i in range(3):
            box("Ascending_Step", -.61+i*.52, -.51+i*.39, .62, .27, "cyan", .0+i*.075, .36)
        arrow("Progress", -.55, .49, .63, "white", "right")
    elif icon_id == "relic":
        shape("Relic_Prism", [(0, .94), (.58, .12), (0, -.94), (-.58, .12)], "gold", -.02, .22)
        shape("Prism_Facet", [(0, .80), (.45, .12), (0, -.80)], "amber", -.16, .05)
        star("Prism_Glint", -.24, .26, .20, "white", -.26)
    elif icon_id in ("card", "card_owned", "card_equipped"):
        if icon_id == "card_owned":
            card(-.23, -.14, "iron", .17, .96)
            card(.16, .13, "cyan", -.04, .96)
        else:
            card(role="green" if icon_id == "card_equipped" else "cyan", marked=icon_id == "card_equipped")
    elif icon_id == "settings":
        ring("Gear_Hub", 0, 0, .46, "steel", 0, .16)
        ring("Gear_Inner", 0, 0, .24, "cyan", -.18, .035)
        for i in range(8):
            a = math.tau*i/8
            tooth = box("Gear_Tooth", math.sin(a)*.67, math.cos(a)*.67, .30, .39, "steel", 0, .26)
            tooth.rotation_euler.y = a
    else:
        box("Ledger_Cover", -.10, 0, 1.25, 1.57, "cyan", .02, .18)
        box("Ledger_Spine", -.63, 0, .13, 1.57, "gold", -.13, .10)
        for z in (.41, .12, -.17):
            box("Version_Line", -.06, z, .66, .075, "white", -.12, .045, .01)
        clock(.50, -.48, .56)


def status_icon(icon_id):
    medal()
    if icon_id == "slow":
        shape("Hourglass_Glass", [(-.38, .50), (.38, .50), (.12, .01), (.38, -.50), (-.38, -.50), (-.12, .01)], "amber", -.10, .13)
        for z in (-.54, .54):
            box("Hourglass_End", 0, z, .88, .14, "gold", -.17, .12)
        pipe("Hourglass_Neck", [(-.13, .0), (.13, .0)], .04, "white", -.20)
        shape("Fallen_Sand", [(-.29, -.43), (.29, -.43), (0, -.09)], "white", -.22, .035)
    elif icon_id == "vulnerable":
        shield("amber", True)
        for obj in list(CURRENT.objects):
            if "Cracked" in obj.name:
                obj.scale = (.64, 1, .64)
                obj.location.y = -.15
    else:
        blade("Broken", -.25, "red", -.11, .12, .70, -.16, True)
        arrow("Weakened", .40, -.31, .57, "red", "down", -.27)


def effect_icon(icon_id):
    if icon_id == "shield_spend":
        shield()
        box("Spend_Minus", 0, 0, 1.18, .25, "red", -.27, .12)
    elif icon_id in ("delay", "haste"):
        clock(-.10, .10, .88)
        arrow("Time_Change", .04, -.51, 1.07, "amber" if icon_id == "delay" else "green",
              "right" if icon_id == "delay" else "left", -.29)
    elif icon_id == "recast":
        clock(arrows=True)
    elif icon_id == "interrupt":
        shape("Discharge_Bolt", [(.26, .96), (-.56, .0), (-.04, .0), (-.25, -.88), (.61, .20), (.05, .20)], "amber", -.03, .22)
        box("Interrupt_Cut", 0, -.0, 1.45, .16, "red", -.23, .08)
    elif icon_id == "cleanse":
        star("Purifying_Spark", 0, 0, .90, "green")
        star("Clean_Glint", .62, .59, .28, "white", -.1)
        star("Clean_Glint", -.66, -.48, .19, "white", -.1)
    elif icon_id == "empower":
        arrow("Power_Rise", 0, -.20, 1.16, "gold", "up")
        shape("Upper_Chevron", [(-.50, .53), (0, .90), (.50, .53), (.50, .31), (0, .68), (-.50, .31)], "amber", -.28)
    elif icon_id == "auto_queue":
        card(-.18, .16, "cyan", 0, .95)
        arrow("Automatic_Entry", .15, -.57, .97, "green", "right", -.30)
    elif icon_id in ("timeline_stop", "timeline_reverse"):
        box("Timeline_Rail", 0, -.43, 1.83, .12, "cyan", .04)
        for x in (-.75, -.25, .25, .75):
            box("Timeline_Tick", x, -.43, .055, .32, "white", -.07, .05)
        if icon_id == "timeline_stop":
            for x in (-.28, .28):
                box("Pause_Gate", x, .32, .25, .89, "amber", -.16, .18)
        else:
            arrow("Reverse_Time", 0, .31, 1.17, "amber", "left")
    elif icon_id == "status":
        ring("Status_Aura", 0, 0, .76, "gold", .03, .10)
        star("Status_Sigil", 0, 0, .70, "amber", -.10, 6)
        disc("Status_Center", 0, 0, .19, "iron", -.21)
    else:
        ring("Effect_Outer", 0, 0, .78, "cyan", .06, .08)
        ring("Effect_Middle", 0, 0, .51, "steel", -.06, .065)
        sphere("Effect_Core", 0, 0, .23, "white", -.14)


def map_icon(icon_id):
    if icon_id == "lock":
        lock()
        return
    # The map set shares a slim circular footing, not an opaque image background.
    disc("Map_Footing", 0, -.72, .51, "iron", .18, .14)
    ring("Footing_Inlay", 0, -.72, .46, "steel", .08, .024)
    if icon_id in ("normal_battle", "elite_battle"):
        blade("Left", -.61, "red" if icon_id == "elite_battle" else "white", -.10, .09, .86, -.01)
        blade("Right", .61, "white", .10, .09, .86, -.15)
        if icon_id == "elite_battle":
            star("Elite_Star", 0, .56, .28, "gold", -.29, 5)
    elif icon_id == "boss":
        crown()
    elif icon_id == "shop":
        box("Stall_Body", 0, -.22, 1.42, .89, "teal", .10, .28)
        for x in (-.61, .61):
            box("Stall_Post", x, .29, .08, 1.0, "steel", -.15, .09)
        for i in range(5):
            x = -.60+i*.30
            box("Awning_Stripe", x, .57, .31, .35, "white" if i % 2 == 0 else "teal", -.17, .35)
        box("Counter", 0, -.29, 1.51, .12, "gold", -.23, .16)
        coin(.17, -.24, .46, -.31)
    elif icon_id == "forge":
        shape("Anvil", [(-.81, .10), (.86, .10), (.63, -.16), (.13, -.22), (.18, -.58), (.57, -.70), (-.56, -.70), (-.26, -.55), (-.29, -.21), (-.75, -.13)], "steel", -.08, .32, .04)
        obj = box("Hammer_Handle", -.10, .50, .12, .83, "gold", .03, .13)
        obj.rotation_euler.y = -.48
        obj = box("Hammer_Head", .05, .77, .74, .27, "steel", -.04, .33)
        obj.rotation_euler.y = -.48
        star("Forge_Spark", .58, .38, .18, "amber", -.25)
    elif icon_id == "heal":
        box("Aid_Case", 0, -.10, 1.40, 1.07, "white", .0, .28, .07)
        pipe("Case_Handle", [(-.25, .45), (-.25, .73), (.25, .73), (.25, .45)], .07, "steel", .0)
        cross("green", .65)
        for obj in list(CURRENT.objects):
            if "Medical" in obj.name:
                obj.location.y = -.24
    elif icon_id == "event":
        points = [(-.37, .48), (-.35, .63), (-.20, .79), (.07, .84), (.35, .68), (.38, .42), (.29, .27), (.06, .11), (.0, -.14)]
        pipe("Unknown_Signal", points, .12, "gold", -.11)
        sphere("Question_Dot", 0, -.47, .135, "amber", -.11)
    elif icon_id == "hazard":
        pipe("Warning_Triangle", [(-.86, -.61), (0, .91), (.86, -.61), (-.86, -.61)], .085, "amber", -.09)
        box("Warning_Stroke", 0, .20, .16, .60, "red", -.13, .14)
        disc("Warning_Dot", 0, -.34, .10, "red", -.13)


def control_icon(icon_id):
    disabled = icon_id.endswith("disabled")
    on = "_on" in icon_id
    edge = "disabled" if disabled else "steel"
    active = "disabled" if disabled else "cyan"
    knob = "disabled" if disabled else "gold"
    if icon_id.startswith("checkbox"):
        box("Checkbox_Frame", 0, 0, 1.6, 1.6, edge, 0, .16, .08)
        box("Checkbox_Recess", 0, 0, 1.32, 1.32, "dim", -.12, .05, .035)
        if on:
            pipe("Selected_Check", [(-.43, -.02), (-.10, -.34), (.49, .39)], .10, knob, -.19)
    elif icon_id.startswith("switch"):
        box("Switch_Bezel", 0, 0, 2.08, .84, edge, 0, .16, .075)
        box("Switch_Track", 0, 0, 1.88, .64, active if on else "dim", -.11, .045, .05)
        box("Sliding_Knob", .52 if on else -.52, 0, .63, .56, knob, -.19, .15, .07)
        for z in (-.13, .0, .13):
            box("Knob_Grip", .52 if on else -.52, z, .30, .035, edge, -.28, .025, .005)
    else:
        role = "amber" if icon_id.endswith("highlight") else "gold"
        box("Slider_Grip", 0, 0, .89, 1.48, role, 0, .24, .06)
        for x in (-.19, 0, .19):
            box("Slider_Ridge", x, 0, .035, .74, "white", -.155, .06, .012)


def specs():
    entries = []
    for visual_id in ("slow", "vulnerable", "weak"):
        entries.append((visual_id, "status", visual_id, [96, 96], status_icon))
    for category, ids, prefix, builder, size in [
        ("ui", UI_IDS, "ui_", ui_icon, 64), ("effect", EFFECT_IDS, "effect_", effect_icon, 64),
        ("map", MAP_IDS, "map_", map_icon, 96),
    ]:
        for visual_id in ids:
            entries.append((prefix+visual_id, category, visual_id, [size, size], builder))
    for visual_id in CONTROL_IDS:
        size = [48, 26] if visual_id.startswith("switch") else [24, 24] if visual_id.startswith("checkbox") else [22, 22]
        entries.append(("control_"+visual_id, "control", visual_id, size, control_icon))
    return entries


def render_rig():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x = scene.render.resolution_y = RENDER_SIZE
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 4
    if scene.world is None:
        scene.world = bpy.data.worlds.new("UI_Ambient_World")
    scene.world.color = (.08, .08, .08)
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0
    for name, location, energy, size in [
        ("Key_Softbox", (-3, -4, 5), 480, 4),
        ("Fill_Softbox", (4, -3, 1), 280, 3),
        ("Edge_Softbox", (0, 2, 4), 380, 3),
    ]:
        light = bpy.data.lights.new(name, "AREA")
        light.energy, light.shape, light.size = energy, "DISK", size
        obj = bpy.data.objects.new(name, light)
        scene.collection.objects.link(obj)
        obj.location = location
        obj.rotation_euler = (Vector((0, 0, 0))-obj.location).to_track_quat("-Z", "Y").to_euler()
    cam = bpy.data.cameras.new("UI_Orthographic_Camera")
    cam.type, cam.ortho_scale = "ORTHO", 2.60
    camera = bpy.data.objects.new("UI_Orthographic_Camera", cam)
    scene.collection.objects.link(camera)
    camera.location = (0, -7, .48)
    camera.rotation_euler = (-camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera


def main():
    global CURRENT
    bpy.ops.wm.read_factory_settings(use_empty=True)
    SOURCE.parent.mkdir(parents=True, exist_ok=True)
    INTERMEDIATE.mkdir(parents=True, exist_ok=True)
    materials()
    render_rig()
    collections, entries = [], []
    for asset_id, category, visual_id, size, builder in specs():
        CURRENT = bpy.data.collections.new(asset_id)
        bpy.context.scene.collection.children.link(CURRENT)
        CURRENT["asset_id"], CURRENT["category"] = asset_id, category
        CURRENT["visual_id"] = visual_id
        builder(visual_id)
        CURRENT.asset_mark()
        collections.append(CURRENT)
        folder = {"status": "status", "ui": "ui", "effect": "effects", "map": "map", "control": "controls"}[category]
        entries.append({
            "id": asset_id, "asset_id": asset_id, "visual_id": visual_id, "category": category,
            "runtime_path": f"assets/icons/{folder}/{visual_id}.png", "source_path": rel(SOURCE),
            "source_collection": CURRENT.name, "generator": rel(Path(__file__)),
            "presentation": "transparent_orthographic_3d_pictogram", "size": size,
            "source_render_size": [RENDER_SIZE, RENDER_SIZE],
            "render_path": rel(INTERMEDIATE / (asset_id+".png")),
            "objects": len(CURRENT.objects),
            "mesh_vertices": sum(len(obj.data.vertices) for obj in CURRENT.objects if obj.type == "MESH"),
            "shared_parts": ["beveled_extrusions", "metal_rims", "enamel_inlays", "orthographic_render_rig"],
        })
    for index, (collection, entry) in enumerate(zip(collections, entries)):
        for other in collections:
            other.hide_render = other != collection
        bpy.context.scene.render.filepath = str(ROOT / entry["render_path"])
        bpy.ops.render.render(write_still=True)
        entry["render_sha256"] = sha(ROOT / entry["render_path"])
        print(f"UI_RENDER_OK {index+1}/{len(entries)} {entry['id']}", flush=True)
    for collection in collections:
        collection.hide_render = collection.name != "ui_hp"
        collection.hide_viewport = collection.name != "ui_hp"
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE), compress=True)
    manifest = {
        "format_version": 1, "batch_id": BATCH_ID, "generator": rel(Path(__file__)),
        "generator_sha256": sha(Path(__file__)), "source": rel(SOURCE), "source_sha256": sha(SOURCE),
        "blender_version": bpy.app.version_string, "render_engine": "Cycles CPU 24 samples, 4 threads",
        "assets": entries, "third_party_inputs": [], "license": "project-original",
        "preserved_assets": {path: sha(ROOT / path) for path in (
            "assets/icons/status/bleed.png", "assets/icons/ui/attack.png")},
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2)+"\n", encoding="utf-8")
    print(f"BLENDER_UI_BUILD_OK {len(entries)} editable assets", flush=True)


if __name__ == "__main__":
    main()
