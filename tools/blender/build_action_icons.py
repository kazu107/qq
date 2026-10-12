"""Editable action pictograms; isolated Blender only, never the live MCP scene."""
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
SOURCE = ROOT / "art_src/blender/ui/qq_ui_actions.blend"
MANIFEST = SOURCE.with_suffix(".manifest.json")
RENDERS = ROOT / "tools/.local/blender_action_icons"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(icon):
    b, p, s, d, r, a = kit.box, kit.pipe, kit.shape, kit.disc, kit.ring, kit.arrow
    if icon in ("back", "next", "exit", "load", "export"):
        if icon == "exit":
            b("Door", -.43, 0, .78, 1.65, "steel", .1, .20)
            b("Opening", -.35, 0, .52, 1.35, "iron", -.06)
        elif icon in ("load", "export"):
            p("Tray", [(-.85, -.35), (-.85, -.72), (.85, -.72), (.85, -.35)], .09, "steel")
        a("Direction", .15 if icon == "exit" else 0, .1, 1.1, "cyan", "left" if icon == "back" else "right" if icon in ("next", "exit") else "down" if icon == "load" else "up", -.28)
    elif icon == "home":
        s("Roof", [(-1, .16), (0, 1), (1, .16), (.77, -.03), (0, .60), (-.77, -.03)], "gold")
        b("House", 0, -.26, 1.42, 1.02, "steel", .04, .23)
        b("Entrance", 0, -.45, .40, .67, "cyan", -.13)
    elif icon in ("play", "pause", "ready", "close"):
        if icon == "play": s("Play", [(-.57, -.85), (-.57, .85), (.90, 0)], "green", -.10, .23)
        elif icon == "pause":
            for x in (-.37, .37): b("Pause", x, 0, .40, 1.55, "gold")
        elif icon == "ready": p("Check", [(-.90, -.02), (-.30, -.64), (.85, .69)], .15, "green")
        else:
            p("Close_A", [(-.72, -.72), (.72, .72)], .13, "white")
            p("Close_B", [(-.72, .72), (.72, -.72)], .13, "white")
    elif icon == "restart":
        r("Cycle", 0, 0, .75, "cyan", start=-.3, end=5.15, thickness=.13)
        a("Reset_Arrow", -.67, .35, .50, "white", "down", -.25)
    elif icon == "reroll":
        b("Die", 0, 0, 1.46, 1.46, "steel", .04, .35, .10)
        for x, z in [(-.43, -.43), (.43, .43), (0, 0), (-.43, .43), (.43, -.43)]: d("Pip", x, z, .10, "gold", -.20, .05)
    elif icon in ("log", "info", "tutorial"):
        if icon == "tutorial":
            b("Left_Page", -.42, 0, .83, 1.56, "white", 0, .22)
            b("Right_Page", .42, 0, .83, 1.56, "cyan", .03, .22)
            b("Spine", 0, 0, .14, 1.70, "gold", -.16)
            for x in (-.43, .43):
                for z in (-.45, -.12, .23): b("Text_Rule", x, z, .47, .06, "iron", -.19, .04)
        elif icon == "log":
            b("Scroll", 0, 0, 1.28, 1.49, "white", 0, .10)
            for z in (-.82, .82): b("Rolled_End", 0, z, 1.59, .18, "gold", -.10, .24)
            for z in (-.43, -.10, .23): b("Written_Line", 0, z, .85, .09, "iron", -.15, .03)
        else:
            r("Info_Rim", 0, 0, .87, "cyan", thickness=.09)
            b("Info_Stem", 0, -.15, .18, .82, "white", -.12)
            d("Info_Dot", 0, .52, .13, "gold", -.14)
    elif icon in ("search", "spectator"):
        if icon == "search":
            r("Lens", -.22, .22, .58, "gold", thickness=.12)
            p("Handle", [(.19, -.20), (.81, -.82)], .14, "steel")
        else:
            p("Eye", [(-1, 0), (-.6, .49), (0, .65), (.6, .49), (1, 0), (.6, -.49), (0, -.65), (-.6, -.49), (-1, 0)], .10, "white")
            d("Iris", 0, 0, .36, "cyan", -.12)
            d("Pupil", 0, 0, .16, "iron", -.24)
    elif icon == "filter":
        s("Funnel", [(-.96, .79), (.96, .79), (.20, -.1), (.20, -.72), (-.20, -.9), (-.20, -.1)], "cyan", 0, .23)
        b("Funnel_Lip", 0, .85, 1.91, .13, "white", -.12)
    elif icon in ("equip", "unequip", "sell"):
        if icon == "sell": kit.coin(-.34, .25, .92)
        else: kit.card(-.31, .15, "cyan", scale=.84)
        a("Transfer", .15, -.53, 1.05, "green" if icon == "equip" else "amber", "left" if icon == "equip" else "right", -.32)
    elif icon == "upgrade":
        a("Improvement", 0, -.24, 1.12, "green", "up")
        s("Grade_Chevron", [(-.61, .56), (0, .93), (.61, .56), (.61, .31), (0, .66), (-.61, .31)], "gold", -.20)
    elif icon == "unlock":
        b("Key_Blade", .21, -.1, .92, .17, "gold")
        r("Key_Bow", -.61, -.1, .31, "gold", thickness=.09)
        for x in (.34, .61): b("Key_Tooth", x, -.27, .15, .34, "gold")
        p("Open_Shackle", [(-.30, .5), (-.30, .79), (.14, .94), (.44, .62)], .10, "white", .08)
    elif icon == "claim":
        b("Gift", 0, -.21, 1.46, 1.13, "cyan", 0, .35)
        b("Lid", 0, .34, 1.70, .21, "white", -.02, .36)
        b("Ribbon", 0, -.18, .20, 1.27, "gold", -.24)
        p("Bow", [(0, .47), (-.50, .93), (-.66, .57), (0, .47), (.50, .93), (.66, .57), (0, .47)], .085, "gold", -.09)
    elif icon == "save":
        b("Disk", 0, 0, 1.55, 1.65, "steel", 0, .23)
        b("Upper_Inlay", .06, .46, .95, .57, "iron", -.16)
        b("Read_Window", .29, .47, .22, .48, "cyan", -.23)
        b("Label", 0, -.44, 1.14, .53, "white", -.18)
    elif icon == "delete":
        b("Bin", 0, -.21, 1.15, 1.28, "steel", .02, .35)
        b("Lid", 0, .53, 1.49, .15, "red", -.04)
        p("Handle", [(-.24, .55), (-.24, .82), (.24, .82), (.24, .55)], .075, "gold")
        for x in (-.30, 0, .30): b("Groove", x, -.19, .06, .95, "iron", -.2)
    elif icon == "trophy":
        s("Cup", [(-.65, .82), (.65, .82), (.49, .12), (.22, -.12), (-.22, -.12), (-.49, .12)], "gold", 0, .25)
        p("Left_Handle", [(-.56, .67), (-.93, .60), (-.82, .16), (-.46, .06)], .09, "white", .04)
        p("Right_Handle", [(.56, .67), (.93, .60), (.82, .16), (.46, .06)], .09, "white", .04)
        b("Stem", 0, -.34, .21, .43, "gold")
        b("Foot", 0, -.69, .90, .20, "steel")
    elif icon == "defeat":
        kit.shield("red", broken=True)
    elif icon == "meta_points":
        s("Crystal", [(0, 1), (.83, .24), (.52, -.65), (0, -.98), (-.52, -.65), (-.83, .24)], "cyan", 0, .35)
        kit.star("Progress_Spark", 0, 0, .53, "gold", -.23, 4)
    elif icon == "arena":
        kit.blade("Sword_Left", -.65, "white", -.26, -.12, .78)
        kit.blade("Sword_Right", .65, "gold", .26, -.12, .78, -.18)
    elif icon == "online":
        for x in (-.62, .62):
            d("Player_Head", x, .53, .23, "white", -.08)
            b("Player_Body", x, -.15, .47, .72, "cyan", 0, .20)
        p("Connection", [(-.57, -.73), (0, -.87), (.57, -.73)], .085, "gold")
    elif icon == "waiting":
        for z in (-.86, .86): b("Hourglass_Frame", 0, z, 1.19, .14, "steel")
        s("Sand_Glass", [(-.51, .70), (.51, .70), (.10, .0), (.51, -.70), (-.51, -.70), (-.10, 0)], "cyan", 0, .20)
        s("Sand", [(-.33, -.58), (.33, -.58), (0, -.27)], "gold", -.15)
    elif icon == "bot":
        b("Robot_Head", 0, -.04, 1.56, 1.25, "steel", 0, .36, .1)
        for x in (-.37, .37): b("Eye", x, .14, .29, .25, "cyan", -.25)
        b("Mouth", 0, -.34, .63, .10, "gold", -.25)
        p("Antenna", [(0, .60), (0, .94)], .055, "white")
        d("Antenna_Tip", 0, 1, .1, "gold")
    elif icon == "infinity":
        p("Infinity", [(math.cos(t)*.94, math.sin(2*t)*.48) for t in [math.tau*i/128 for i in range(129)]], .12, "gold")
    elif icon == "sound":
        s("Speaker", [(-.90, -.30), (-.49, -.30), (.08, -.81), (.08, .81), (-.49, .30), (-.90, .30)], "white", 0, .28)
        for radius in (.48, .82):
            p("Sound_Wave", [(.18+math.cos(t)*radius, math.sin(t)*radius) for t in [(-.95+1.9*i/24) for i in range(25)]], .07, "cyan")
    elif icon == "display":
        b("Monitor", 0, .18, 1.88, 1.29, "steel", 0, .23)
        b("Screen", 0, .18, 1.57, .99, "cyan", -.17, .04)
        b("Stand", 0, -.60, .22, .33, "gold")
        b("Foot", 0, -.84, .83, .13, "steel")
    else:
        raise ValueError(icon)


def main():
    if "--validate-only" in sys.argv:
        meta = json.loads(MANIFEST.read_text(encoding="utf-8"))
        bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
        assert sha(SOURCE) == meta["source_sha256"]
        for entry in meta["assets"]:
            collection = bpy.data.collections[entry["source_collection"]]
            assert len(collection.objects) == entry["objects"]
            assert any(obj.type in ("MESH", "CURVE") for obj in collection.objects)
            assert not any(obj.type == "FONT" for obj in collection.objects)
            assert sha(ROOT / entry["runtime_path"]) == entry["export_sha256"]
        print("ACTION_ICON_SOURCE_REOPEN_OK", len(meta["assets"]), flush=True)
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    SOURCE.parent.mkdir(parents=True, exist_ok=True)
    RENDERS.mkdir(parents=True, exist_ok=True)
    kit.materials()
    kit.render_rig()
    bpy.context.scene.render.resolution_x = bpy.context.scene.render.resolution_y = 1024
    bpy.context.scene.cycles.samples = 16
    ids = json.loads((ROOT / "data/ui_action_icons.json").read_text(encoding="utf-8"))
    entries, collections = [], []
    for icon in ids:
        kit.CURRENT = bpy.data.collections.new("action_" + icon)
        bpy.context.scene.collection.children.link(kit.CURRENT)
        kit.CURRENT["icon_id"] = icon
        build(icon)
        kit.CURRENT.asset_mark()
        collections.append(kit.CURRENT)
        entries.append({"id": "action_" + icon, "visual_id": icon, "category": "ui", "size": 64,
                        "runtime_path": f"assets/icons/ui/{icon}.png", "source_path": kit.rel(SOURCE),
                        "source_collection": kit.CURRENT.name, "source_render_size": [1024, 1024],
                        "presentation": "transparent_orthographic_3d_pictogram", "objects": len(kit.CURRENT.objects)})
    for entry, collection in zip(entries, collections):
        for other in collections: other.hide_render = other != collection
        path = RENDERS / (entry["visual_id"] + ".png")
        bpy.context.scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        entry["render_path"] = kit.rel(path)
        entry["render_sha256"] = sha(path)
        print("ACTION_ICON_RENDER_OK", entry["visual_id"], flush=True)
    for collection in collections:
        collection.hide_render = collection.hide_viewport = collection != collections[0]
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE), compress=True)
    dependencies = {kit.rel(Path(__file__)): sha(Path(__file__)), kit.rel(Path(kit.__file__)): sha(Path(kit.__file__))}
    manifest = {"batch_id": "blender_action_icons_07", "blender_version": bpy.app.version_string,
                "generator": kit.rel(Path(__file__)), "generator_sha256": dependencies,
                "source": kit.rel(SOURCE), "source_sha256": sha(SOURCE), "assets": entries}
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print("ACTION_ICONS_BUILD_OK", len(entries), flush=True)


if __name__ == "__main__":
    main()
