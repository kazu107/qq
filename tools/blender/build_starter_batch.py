"""Second art batch: linked starter kit, six GLBs, seven matching portraits.

Run with a separate background Blender. Nothing is sent to a running MCP scene.
The first batch's Balanced GLB and all Scout assets are intentionally untouched.
"""

from __future__ import annotations

import json
import math
import os
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_battle_vertical_slice as base
import starter_character_parts as parts
from build_battle_animation_library import godot_rotation, godot_vector


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art_src/blender/characters/qq_starters.blend"
LIBRARY = ROOT / "art_src/blender/library/qq_starter_parts.blend"
MANIFEST = SOURCE.with_suffix(".manifest.json")
PREVIEWS = ROOT / "art_src/blender/previews"
INTERMEDIATE = ROOT / "tools/.local/starter_batch"
IDS = ("balanced", *parts.STARTER_PARTS.keys())
PROFILES = json.loads((ROOT / "data/battle_visuals.json").read_text(encoding="utf-8"))
CATALOG = json.loads((ROOT / "data/battle_animations.json").read_text(encoding="utf-8"))
RENDER_SIZE = max(512, int(os.environ.get("QQ_STARTER_RENDER_SIZE", "1024")))


def rgba(hex_color):
    value = hex_color.lstrip("#")
    return tuple(int(value[index:index + 2], 16) / 255 for index in (0, 2, 4)) + (1.0,)


def palette(starter_id, templates):
    profile = PROFILES[starter_id]
    primary, dark, accent = (rgba(profile[key]) for key in ("primary", "secondary", "accent"))
    colors = {
        "armor": primary, "edge": tuple(min(1.0, v * 1.2 + 0.08) for v in primary[:3]) + (1.0,),
        "dark": dark, "glow": accent, "cloth_shadow": tuple(v * 0.4 + 0.02 for v in primary[:3]) + (1.0,),
    }
    if starter_id == "aegis":
        colors.update(armor=(0.76, 0.77, 0.69, 1), edge=(0.93, 0.9, 0.74, 1), trim=(0.65, 0.38, 0.07, 1), cloth=(0.10, 0.24, 0.22, 1))
    elif starter_id == "chrono":
        colors.update(cloth=(0.11, 0.07, 0.20, 1), trim=(0.54, 0.34, 0.10, 1), hair=(0.07, 0.065, 0.12, 1))
    elif starter_id == "vanguard":
        colors.update(cloth=(0.11, 0.07, 0.06, 1), trim=(0.3, 0.24, 0.18, 1))
    elif starter_id == "turret":
        colors.update(armor=(0.50, 0.29, 0.06, 1), edge=(0.76, 0.49, 0.11, 1), cloth=(0.12, 0.13, 0.12, 1))
    elif starter_id == "fortress":
        colors.update(cloth=(0.12, 0.17, 0.22, 1), trim=(0.38, 0.45, 0.5, 1))
    elif starter_id == "tempo":
        colors.update(cloth=(0.10, 0.18, 0.16, 1), skin=(0.58, 0.32, 0.19, 1), skin_light=(0.76, 0.47, 0.29, 1))
    result = {}
    for role, template in templates.items():
        material = template.copy()
        material.name = f"QQ_{starter_id}_{role}"
        if starter_id != "balanced" and role in colors:
            color = colors[role]
            material.diffuse_color = color
            shader = material.node_tree.nodes.get("Principled BSDF")
            shader.inputs["Base Color"].default_value = color
            if role == "glow":
                shader.inputs["Emission Color"].default_value = color
                shader.inputs["Emission Strength"].default_value = 0.85
        result[role] = material
    return result


def assemble(starter_id, library_collections, materials):
    collection = base.make_collection("STARTER_" + starter_id)
    rig = base.create_armature(starter_id, collection)
    part_ids = ["BODY_BASE", "BALANCED_EQUIPMENT"] if starter_id == "balanced" else ["BODY_BASE", *parts.STARTER_PARTS[starter_id]]
    for part_id in part_ids:
        for source in library_collections[part_id].objects:
            if source.type != "MESH":
                continue
            # Closed helmets replace the whole head so cheeks cannot poke through.
            if starter_id not in ("balanced", "tempo") and part_id == "BODY_BASE" and source.get("battle_bone") == "head":
                continue
            obj = source.copy()
            obj.data = source.data.copy()
            obj.name = f"{starter_id}_{source.name.removeprefix('Balanced_')}"
            obj.parent = rig
            obj.matrix_parent_inverse = rig.matrix_world.inverted()
            for modifier in obj.modifiers:
                if modifier.type == "ARMATURE":
                    modifier.object = rig
            for slot in obj.material_slots:
                slot.material = materials[slot.material["qq_role"]]
            collection.objects.link(obj)
    rig["source_parts"] = json.dumps(part_ids)
    rig["authored_detail_tier"] = "starter_batch_02"
    mesh = base.merge_character_meshes(collection, rig, starter_id)
    mesh.data.calc_loop_triangles()
    triangles = len(mesh.data.loop_triangles)
    if triangles > 35000 or len(rig.data.bones) != 18:
        raise RuntimeError(f"{starter_id} exceeds the character budget: {triangles} triangles")
    collection["visual_id"] = starter_id
    collection["source_parts"] = json.dumps(part_ids)
    return collection, rig, mesh, triangles


def validate_skin(mesh, rig):
    weighted_bones = set()
    for vertex in mesh.data.vertices:
        weights = [group for group in vertex.groups if group.weight > 0.0]
        if len(weights) != 1 or abs(weights[0].weight - 1.0) > 1e-5:
            raise RuntimeError(f"{mesh.name}: vertex {vertex.index} is not rigidly weighted")
        name = mesh.vertex_groups[weights[0].group].name
        if name not in rig.data.bones:
            raise RuntimeError(f"Missing skin bone {name}")
        weighted_bones.add(name)
    return sorted(weighted_bones)


def set_pose(rig, clip_id, key_index=1):
    for bone in rig.pose.bones:
        bone.rotation_mode = "QUATERNION"
        bone.rotation_quaternion.identity()
        bone.location = Vector((0, 0, 0))
    clip = CATALOG["clips"][clip_id]
    key = clip["keyframes"][min(key_index, len(clip["keyframes"]) - 1)]
    for name, rotation in key.get("rotations", {}).items():
        rig.pose.bones[name].rotation_quaternion = godot_rotation(rotation)
    for name, position in key.get("positions", {}).items():
        rig.pose.bones[name].location = godot_vector(position)
    bpy.context.view_layer.update()


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.render.resolution_percentage = 100
    scene.view_settings.look = "AgX - Medium High Contrast"
    world = bpy.data.worlds.new("StarterPortraitWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.028, 0.045, 0.06, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.45
    scene.world = world
    rig = base.make_collection("RENDER_RIG")
    for name, at, energy, color, size in [
        ("Key", (-3.2, 4.5, 5.4), 700, (0.84, 0.92, 1), 4.0),
        ("Fill", (3.2, 3.5, 3.4), 350, (0.75, 0.87, 1), 3.0),
        ("Rim", (2, -3, 4.2), 950, (1, 0.62, 0.28), 3.0),
    ]:
        data = bpy.data.lights.new("Starter" + name, "AREA")
        data.energy, data.color, data.size = energy, color, size
        obj = bpy.data.objects.new("Starter" + name, data)
        obj.location = at
        base.look_at(obj, Vector((0, 0, 1.6)))
        rig.objects.link(obj)
    camera = bpy.data.objects.new("StarterPortraitCamera", bpy.data.cameras.new("StarterPortraitCamera"))
    rig.objects.link(camera)
    scene.camera = camera
    camera.data.type = "ORTHO"
    camera.data.lens = 70
    return camera


def render_portrait(starter_id, rig, camera):
    scale = PROFILES[starter_id]["body_scale"]
    rig.scale = (scale[0], scale[2], scale[1])
    set_pose(rig, "idle", 1)
    camera.location = (3.2, 7.0, 3.5)
    base.look_at(camera, Vector((0, 0.02, 1.91 * scale[1])))
    camera.data.ortho_scale = 1.91 * scale[1]
    scene = bpy.context.scene
    scene.render.resolution_x = RENDER_SIZE
    scene.render.resolution_y = RENDER_SIZE
    scene.render.filepath = str(INTERMEDIATE / f"{starter_id}_portrait.png")
    bpy.ops.render.render(write_still=True)
    source_image = bpy.data.images.load(scene.render.filepath, check_existing=False)
    source_image.scale(1024, 1024)
    target = ROOT / f"assets/portraits/{starter_id}.png"
    source_image.filepath_raw = str(target)
    source_image.save()
    bpy.data.images.remove(source_image)
    rig.scale = (1, 1, 1)
    return target


def main():
    for directory in (SOURCE.parent, LIBRARY.parent, PREVIEWS, INTERMEDIATE):
        directory.mkdir(parents=True, exist_ok=True)
    part_ids = parts.build_library(LIBRARY)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with bpy.data.libraries.load(str(LIBRARY), link=True) as (available, loaded):
        loaded.collections = part_ids
    library_collections = {collection.name: collection for collection in loaded.collections}
    source_links = base.make_collection("SOURCE_LINKS")
    source_links.hide_render = True
    source_links.hide_viewport = True
    for collection in library_collections.values():
        instance = bpy.data.objects.new("Source_" + collection.name, None)
        instance.instance_type, instance.instance_collection = "COLLECTION", collection
        source_links.objects.link(instance)
    templates = {material["qq_role"]: material for material in bpy.data.materials if material.library and "qq_role" in material}
    models = {}
    entries = []
    for starter_id in IDS:
        collection, rig, mesh, triangles = assemble(starter_id, library_collections, palette(starter_id, templates))
        weighted_bones = validate_skin(mesh, rig)
        target = ROOT / f"assets/models/battle/{starter_id}.glb"
        if starter_id != "balanced":
            base.export_character(collection, target)
        for clip_id in CATALOG["clips"]:
            set_pose(rig, clip_id)
            for bone in rig.pose.bones:
                if not all(math.isfinite(value) for row in bone.matrix for value in row):
                    raise RuntimeError(f"Non-finite pose: {starter_id}/{clip_id}")
        set_pose(rig, "idle", 0)
        models[starter_id] = (collection, rig, mesh)
        entries.append({"id": starter_id, "model": str(target.relative_to(ROOT)).replace('\\', '/'),
                        "model_sha256": base.file_sha256(target), "parts": json.loads(collection["source_parts"]),
                        "vertices": len(mesh.data.vertices), "triangles": triangles,
                        "materials": len(mesh.data.materials), "bones": len(rig.data.bones),
                        "weighted_bones": weighted_bones, "clips_checked": sorted(CATALOG["clips"])})
    camera = setup_render()
    for starter_id, (collection, rig, _) in models.items():
        for other, _, _ in models.values():
            other.hide_render = other != collection
        portrait = render_portrait(starter_id, rig, camera)
        entry = next(entry for entry in entries if entry["id"] == starter_id)
        entry.update(portrait=str(portrait.relative_to(ROOT)).replace('\\', '/'), portrait_sha256=base.file_sha256(portrait))
        print("STARTER_RENDER_OK", starter_id, flush=True)
    # A reusable, posed full-body lineup for visual QA and the Blender opening view.
    for index, (starter_id, (collection, rig, _)) in enumerate(models.items()):
        collection.hide_render = False
        rig.location.x = (index - 3) * 1.72
        s = PROFILES[starter_id]["body_scale"]
        rig.scale = (s[0], s[2], s[1])
        set_pose(rig, "idle", 1)
    camera.location = (3.0, 20, 9)
    base.look_at(camera, Vector((0, 0, 1.25)))
    camera.data.ortho_scale = 14.0
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = 2240, 720
    scene.render.filepath = str(PREVIEWS / "starter_batch_lineup.png")
    # Wider lamps keep both ends of the lineup evenly lit.
    for light in bpy.data.lights:
        light.energy *= 1.7
        light.size *= 2
    bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE), check_existing=False, compress=True)
    # Make the dependency portable rather than retaining this checkout's absolute path.
    for library in bpy.data.libraries:
        library.filepath = bpy.path.relpath(library.filepath).replace("\\", "/")
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE), check_existing=False, compress=True)
    manifest = {"format_version": 1, "batch_id": "blender_starters_02", "blender_version": bpy.app.version_string,
                "generator": "tools/blender/build_starter_batch.py", "parts_generator": "tools/blender/starter_character_parts.py",
                "generator_sha256": base.file_sha256(Path(__file__)), "parts_generator_sha256": base.file_sha256(Path(parts.__file__)),
                "source": str(SOURCE.relative_to(ROOT)).replace('\\', '/'), "source_sha256": base.file_sha256(SOURCE),
                "library": str(LIBRARY.relative_to(ROOT)).replace('\\', '/'), "library_sha256": base.file_sha256(LIBRARY),
                "render_size": RENDER_SIZE, "portrait_size": 1024,
                "bone_names": [bone[0] for bone in base.BONE_DEFINITIONS], "assets": entries}
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("STARTER_BATCH_OK", len(entries), "starters; linked parts", len(part_ids), "saved", not bpy.data.is_dirty, flush=True)


if __name__ == "__main__":
    main()
