"""Batch 03. Independent background Blender; reuse the linked starter library.

Editable assembled parts remain in the source blend; runtime exports use copies.
Never rebuild or overwrite the starter library or an open Blender/MCP scene.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_starter_batch as shared

base, parts = shared.base, shared.parts
ROOT = shared.ROOT
SOURCE = ROOT / "art_src/blender/characters/qq_enemies_03.blend"
PARTS = {
    "guardian": ["BODY_HEAVY", "HEAD_FORTRESS", "OFFHAND_TOWER", "BACK_REACTOR"],
    "boss_timekeeper": ["BODY_ARCANE", "HEAD_HALO", "WEAPON_STAFF", "OFFHAND_ORB", "BACK_CHRONO"],
    "boss_paradox_core": ["BODY_MECH", "HEAD_ANTENNA", "WEAPON_STAFF", "OFFHAND_ORB"],
    "boss_axiom_breaker": ["BODY_ASSAULT", "HEAD_HORNS", "WEAPON_GREATSWORD", "OFFHAND_ORB"],
    "boss_eternity_zero": ["BODY_ARCANE", "HEAD_FORTRESS", "OFFHAND_ORB"],
}


def unique_parts(visual_id, kit):
    k = kit
    if visual_id == "guardian":
        # Match the established downward bind-pose grip; clips raise the cannon.
        k.box("SiegeHousing", (.50, .10, .72), (.44, .40, .50), "armor", "right_hand")
        for z, radius, depth, role in [(.36, .17, .45, "metal"), (.13, .20, .13, "edge"), (.055, .145, .015, "dark")]:
            k.cylinder("CannonBarrel", (.50, .10, z), radius, depth, role, "right_hand")
        for x in (.34, .66):
            k.box("CannonRail", (x, .34, .57), (.055, .04, .68), "trim", "right_hand")
        for side in (-1, 1):
            for index in range(3):
                k.box("FortressVent", (side*.36, .20, 1.73 + index*.065), (.15, .30, .035), "dark", "chest")
    else:
        # Crown silhouette is shared; each boss has distinct machinery below.
        for i in range(5):
            x = (i - 2) * .12
            k.panel("CrownBlade", [(x-.055, 2.25), (x, 2.52-abs(i-2)*.045), (x+.055, 2.25)], .13, .07, "trim", "head")
        if visual_id == "boss_timekeeper":
            k.ring("ClockDial", (0, -.24, 1.88), .69, .045, "trim")
            for i in range(12):
                angle = i * math.tau/12
                x, z = math.sin(angle)*.65, 1.88+math.cos(angle)*.65
                k.box("ClockHour", (x, -.20, z), (.045, .04, .105), "glow", "chest", rotation=(0, angle, 0))
            k.rod("ClockHand", (0, -.16, 1.88), (.34, -.16, 2.20), .028, "trim")
        elif visual_id == "boss_paradox_core":
            for side in (-1, 1):
                k.ring("ParadoxOrbit", (side*.76, -.17, 1.78), .40, .045, "edge", rotation=(math.pi/2, side*.4, 0))
                for i in range(3):
                    k.sphere("OrbitNode", (side*(.65+i*.13), -.16, 1.55+i*.25), (.12, .12, .12), "glow", "chest")
            k.sphere("ExposedCore", (0, .48, 1.66), (.32, .15, .34), "glow", "spine")
            k.ring("CoreContainment", (0, .51, 1.66), .23, .055, "metal", "spine")
        elif visual_id == "boss_axiom_breaker":
            for side in (-1, 1):
                for i in range(3):
                    x = side*(.40+i*.23)
                    k.panel("BrokenLawWing", [(x, 1.65), (x+side*.19, 2.30-i*.12), (x+side*.29, 1.47)], -.25, .12, "armor")
                    k.rod("WingEdge", (x, -.16, 1.65), (x+side*.19, -.16, 2.30-i*.12), .025, "trim")
            k.panel("JudgmentBreastplate", [(-.25, 1.83), (0, 1.42), (.25, 1.83)], .52, .065, "trim", "spine")
        else:
            k.rod("ZeroScytheShaft", (.50, 0, .20), (.50, 0, 2.5), .044, "metal", "right_hand")
            k.panel("ZeroScytheBlade", [(.50, 2.48), (.95, 2.56), (1.37, 2.31), (1.07, 2.43), (.50, 2.29)], 0, .075, "edge", "right_hand")
            for side in (-1, 1):
                for i in range(4):
                    x = side*(.35+i*.22)
                    k.panel("EternityShard", [(x, 1.50), (x+side*.15, 2.38-i*.1), (x+side*.24, 1.32-i*.1)], -.33, .07, "dark")
                    k.rod("EternityInlay", (x+side*.10, -.28, 1.55), (x+side*.15, -.28, 2.27-i*.1), .016, "glow")
            k.ring("ZeroHalo", (0, -.38, 2.00), .76, .025, "glow")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    SOURCE.parent.mkdir(parents=True, exist_ok=True)
    shared.INTERMEDIATE = ROOT / "tools/.local/enemy_batch"
    shared.INTERMEDIATE.mkdir(parents=True, exist_ok=True)
    required = sorted({"BODY_BASE", *(part for values in PARTS.values() for part in values)})
    with bpy.data.libraries.load(str(shared.LIBRARY), link=True) as (available, loaded):
        loaded.collections = required
    library = {collection.name: collection for collection in loaded.collections}
    links = base.make_collection("SOURCE_LINKS")
    links.hide_render = True
    links.hide_viewport = True
    for collection in library.values():
        instance = bpy.data.objects.new("Source_" + collection.name, None)
        instance.instance_type = "COLLECTION"
        instance.instance_collection = collection
        links.objects.link(instance)
    templates = {m["qq_role"]: m for m in bpy.data.materials if m.library and "qq_role" in m}
    models, entries = {}, []
    for visual_id, part_ids in PARTS.items():
        c = base.make_collection("ENEMY_" + visual_id)
        rig = base.create_armature(visual_id, c)
        materials = shared.palette(visual_id, templates)
        for part_id in ["BODY_BASE", *part_ids]:
            for source in library[part_id].objects:
                if source.type != "MESH" or (part_id == "BODY_BASE" and source.get("battle_bone") == "head"):
                    continue
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
                c.objects.link(obj)
        unique_parts(visual_id, parts.Kit(c, rig, materials))
        c["source_parts"] = json.dumps(part_ids)
        # Keep the source editable. Merge a disposable copy for the GLB only.
        export = base.make_collection("EXPORT_" + visual_id)
        export_rig = rig.copy()
        export_rig.data = rig.data.copy()
        export.objects.link(export_rig)
        for source in list(c.objects):
            if source.type != "MESH":
                continue
            obj = source.copy()
            obj.data = source.data.copy()
            obj.parent = export_rig
            for modifier in obj.modifiers:
                if modifier.type == "ARMATURE":
                    modifier.object = export_rig
            export.objects.link(obj)
        mesh = base.merge_character_meshes(export, export_rig, visual_id)
        bones = shared.validate_skin(mesh, export_rig)
        mesh.data.calc_loop_triangles()
        triangles = len(mesh.data.loop_triangles)
        if triangles > 50000:
            raise RuntimeError(f"Mesh budget exceeded: {visual_id} {triangles}")
        target = ROOT / f"assets/models/battle/{visual_id}.glb"
        base.export_character(export, target)
        for obj in list(export.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(export)
        for clip in shared.CATALOG["clips"]:
            shared.set_pose(rig, clip)
            if not all(math.isfinite(v) for b in rig.pose.bones for row in b.matrix for v in row):
                raise RuntimeError("Invalid pose: " + visual_id)
        models[visual_id] = (c, rig)
        entries.append({"id": visual_id, "parts": part_ids, "triangles": triangles, "bones": len(rig.data.bones), "weighted_bones": bones,
                        "model": str(target.relative_to(ROOT)).replace("\\", "/"), "model_sha256": base.file_sha256(target), "clips_checked": sorted(shared.CATALOG["clips"])})
    camera = shared.setup_render()
    for visual_id, (collection, rig) in models.items():
        for other, _ in models.values():
            other.hide_render = other != collection
        portrait = shared.render_portrait(visual_id, rig, camera)
        entry = next(e for e in entries if e["id"] == visual_id)
        entry.update(portrait=str(portrait.relative_to(ROOT)).replace("\\", "/"), portrait_sha256=base.file_sha256(portrait))
        print("ENEMY_RENDER_OK", visual_id, flush=True)
    for index, (visual_id, (collection, rig)) in enumerate(models.items()):
        collection.hide_render = False
        rig.location.x = (index - 2) * 2.8
        s = shared.PROFILES[visual_id]["body_scale"]
        rig.scale = (s[0], s[2], s[1])
        shared.set_pose(rig, "idle", 1)
    camera.location = (3, 22, 9)
    base.look_at(camera, Vector((0, 0, 1.5)))
    camera.data.ortho_scale = 16
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = 2400, 900
    scene.render.filepath = str(ROOT / "art_src/blender/previews/enemy_batch_03.png")
    for light in bpy.data.lights:
        light.energy *= 2
        light.size *= 2
    bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE), compress=True)
    for library in bpy.data.libraries:
        library.filepath = bpy.path.relpath(library.filepath).replace("\\", "/")
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE), compress=True)
    manifest = {"batch_id": "blender_enemies_03", "generator": "tools/blender/build_enemy_batch.py", "source": str(SOURCE.relative_to(ROOT)).replace("\\", "/"),
                "source_sha256": base.file_sha256(SOURCE), "library_sha256": base.file_sha256(shared.LIBRARY), "assets": entries}
    SOURCE.with_suffix(".manifest.json").write_text(json.dumps(manifest, indent=2)+"\n", encoding="utf-8")
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    assert not bpy.data.is_dirty and all(bpy.data.collections.get("ENEMY_"+name) for name in PARTS)
    assert len(bpy.data.libraries) == 1 and bpy.data.libraries[0].filepath.startswith("//")
    print("ENEMY_BATCH_OK: 5 exports, portraits, 18-bone clips, saved/cold-reloaded", flush=True)


if __name__ == "__main__":
    main()
