"""Build the first high-detail Blender-authored UI art vertical slice.

The editable Blend and this script are the source of truth. High-resolution
intermediate renders stay under tools/.local and Godot imports only the final
runtime PNGs, so detailed source geometry never enters the Web PCK.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path
from typing import Callable

import bpy
from mathutils import Vector


PROJECT_ROOT = Path(__file__).resolve().parents[2]
BUILD_ROOT = PROJECT_ROOT / "tools" / ".local" / "blender_art_vertical_slice"
CARD_RENDER_DIR = BUILD_ROOT / "cards"
RELIC_RENDER_DIR = BUILD_ROOT / "relics"
ICON_RENDER_DIR = BUILD_ROOT / "icons"
SOURCE_PATH = PROJECT_ROOT / "art_src" / "blender" / "art_vertical_slice.blend"
SOURCE_MANIFEST_PATH = PROJECT_ROOT / "art_src" / "blender" / "art_vertical_slice.manifest.json"
CARD_MANIFEST_PATH = BUILD_ROOT / "card_manifest.json"
RELIC_MANIFEST_PATH = BUILD_ROOT / "relic_manifest.json"
ICON_MANIFEST_PATH = BUILD_ROOT / "icon_manifest.json"

RENDER_SIZE = max(512, int(os.environ.get("QQ_ART_RENDER_SIZE", "1024")))

CARD_IDS = (
    "quick_slash",
    "guard",
    "delay_step",
    "repair_burst",
    "auto_turret",
    "event_horizon",
)
RELIC_IDS = (
    "iron_plating",
    "auxiliary_core",
    "chrono_shard",
    "salvage_magnet",
)
ICON_SPECS = {
    "bleed": {
        "target": "res://assets/icons/status/bleed.png",
        "size": 96,
    },
    "attack": {
        "target": "res://assets/icons/ui/attack.png",
        "size": 64,
    },
}

MATERIALS: dict[str, bpy.types.Material] = {}
ASSET_COLLECTIONS: list[bpy.types.Collection] = []
LIGHT_COLLECTION: bpy.types.Collection | None = None
BACKDROP_COLLECTION: bpy.types.Collection | None = None
CAMERA: bpy.types.Object | None = None


def clear_file() -> None:
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        bpy.data.collections.remove(collection)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.cameras,
        bpy.data.lights,
        bpy.data.materials,
    ):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def make_collection(name: str) -> bpy.types.Collection:
    collection = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)
    return collection


def move_to_collection(obj: bpy.types.Object, collection: bpy.types.Collection) -> None:
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    collection.objects.link(obj)


def set_material_input(shader: bpy.types.Node, input_name: str, value: object) -> None:
    socket = shader.inputs.get(input_name)
    if socket is not None:
        socket.default_value = value


def make_material(
    name: str,
    color: tuple[float, float, float, float],
    *,
    metallic: float = 0.0,
    roughness: float = 0.5,
    emission: tuple[float, float, float, float] | None = None,
    emission_strength: float = 0.0,
    bump_strength: float = 0.0,
    bump_scale: float = 8.0,
) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.metallic = metallic
    material.roughness = roughness
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    shader = nodes.get("Principled BSDF")
    if shader is None:
        return material
    set_material_input(shader, "Base Color", color)
    set_material_input(shader, "Metallic", metallic)
    set_material_input(shader, "Roughness", roughness)
    if emission is not None:
        set_material_input(shader, "Emission Color", emission)
        set_material_input(shader, "Emission Strength", emission_strength)
    if bump_strength > 0.0:
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = bump_scale
        noise.inputs["Detail"].default_value = 4.0
        noise.inputs["Roughness"].default_value = 0.72
        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = bump_strength
        bump.inputs["Distance"].default_value = 0.08
        links.new(noise.outputs["Fac"], bump.inputs["Height"])
        links.new(bump.outputs["Normal"], shader.inputs["Normal"])
    return material


def build_materials() -> None:
    MATERIALS.update(
        {
            "black": make_material("QQ_Black", (0.006, 0.009, 0.014, 1.0), roughness=0.34),
            "floor": make_material(
                "QQ_Floor",
                (0.018, 0.026, 0.038, 1.0),
                metallic=0.62,
                roughness=0.43,
                bump_strength=0.16,
                bump_scale=18.0,
            ),
            "gunmetal": make_material(
                "QQ_Gunmetal",
                (0.055, 0.075, 0.098, 1.0),
                metallic=0.86,
                roughness=0.31,
                bump_strength=0.12,
                bump_scale=25.0,
            ),
            "steel": make_material(
                "QQ_Steel",
                (0.32, 0.40, 0.48, 1.0),
                metallic=0.94,
                roughness=0.20,
                bump_strength=0.05,
                bump_scale=32.0,
            ),
            "steel_edge": make_material(
                "QQ_SteelEdge",
                (0.70, 0.82, 0.90, 1.0),
                metallic=0.96,
                roughness=0.12,
            ),
            "brass": make_material(
                "QQ_Brass",
                (0.46, 0.25, 0.055, 1.0),
                metallic=0.88,
                roughness=0.25,
                bump_strength=0.08,
                bump_scale=20.0,
            ),
            "brass_edge": make_material(
                "QQ_BrassEdge",
                (0.88, 0.58, 0.14, 1.0),
                metallic=0.92,
                roughness=0.18,
            ),
            "ceramic": make_material(
                "QQ_Ceramic",
                (0.34, 0.43, 0.49, 1.0),
                metallic=0.28,
                roughness=0.34,
                bump_strength=0.07,
                bump_scale=36.0,
            ),
            "ceramic_light": make_material(
                "QQ_CeramicLight",
                (0.68, 0.76, 0.79, 1.0),
                metallic=0.18,
                roughness=0.26,
                bump_strength=0.035,
                bump_scale=42.0,
            ),
            "leather": make_material(
                "QQ_Leather",
                (0.12, 0.055, 0.025, 1.0),
                roughness=0.78,
                bump_strength=0.23,
                bump_scale=12.0,
            ),
            "cyan": make_material(
                "QQ_CyanGlow",
                (0.025, 0.43, 0.68, 1.0),
                metallic=0.24,
                roughness=0.20,
                emission=(0.04, 0.70, 1.0, 1.0),
                emission_strength=2.4,
            ),
            "cyan_soft": make_material(
                "QQ_CyanSoft",
                (0.12, 0.62, 0.78, 1.0),
                metallic=0.18,
                roughness=0.23,
                emission=(0.03, 0.38, 0.72, 1.0),
                emission_strength=0.75,
            ),
            "crystal": make_material(
                "QQ_ChronoCrystal",
                (0.035, 0.28, 0.48, 1.0),
                metallic=0.08,
                roughness=0.16,
                emission=(0.03, 0.40, 0.74, 1.0),
                emission_strength=1.35,
            ),
            "amber": make_material(
                "QQ_AmberGlow",
                (0.72, 0.29, 0.025, 1.0),
                metallic=0.28,
                roughness=0.20,
                emission=(1.0, 0.35, 0.025, 1.0),
                emission_strength=2.15,
            ),
            "red": make_material(
                "QQ_RedGlow",
                (0.56, 0.018, 0.035, 1.0),
                metallic=0.20,
                roughness=0.22,
                emission=(1.0, 0.025, 0.055, 1.0),
                emission_strength=2.30,
            ),
            "green": make_material(
                "QQ_GreenGlow",
                (0.025, 0.50, 0.27, 1.0),
                metallic=0.18,
                roughness=0.22,
                emission=(0.06, 1.0, 0.48, 1.0),
                emission_strength=2.15,
            ),
            "purple": make_material(
                "QQ_PurpleGlow",
                (0.34, 0.03, 0.50, 1.0),
                metallic=0.26,
                roughness=0.18,
                emission=(0.70, 0.08, 1.0, 1.0),
                emission_strength=2.05,
            ),
        }
    )


def finish_object(
    obj: bpy.types.Object,
    collection: bpy.types.Collection,
    material: bpy.types.Material,
    *,
    bevel: float = 0.0,
    smooth: bool = False,
) -> bpy.types.Object:
    if obj.type == "MESH":
        obj.data.materials.append(material)
        for polygon in obj.data.polygons:
            polygon.use_smooth = smooth
    move_to_collection(obj, collection)
    if bevel > 0.0 and obj.type == "MESH":
        modifier = obj.modifiers.new("QQ_HighDetailBevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = 3
        modifier.limit_method = "ANGLE"
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)
    return obj


def apply_scale(obj: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)


def add_empty(
    collection: bpy.types.Collection,
    name: str,
    location: tuple[float, float, float] = (0.0, 0.0, 0.0),
    rotation_degrees: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    obj = bpy.data.objects.new(name, None)
    collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = tuple(math.radians(value) for value in rotation_degrees)
    return obj


def add_box(
    collection: bpy.types.Collection,
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    material: bpy.types.Material,
    *,
    rotation_degrees: tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel: float = 0.05,
    parent: bpy.types.Object | None = None,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add()
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    apply_scale(obj)
    finish_object(obj, collection, material, bevel=bevel)
    obj.parent = parent
    obj.location = location
    obj.rotation_euler = tuple(math.radians(value) for value in rotation_degrees)
    return obj


def add_cylinder(
    collection: bpy.types.Collection,
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    material: bpy.types.Material,
    *,
    vertices: int = 48,
    rotation_degrees: tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel: float = 0.025,
    parent: bpy.types.Object | None = None,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth)
    obj = bpy.context.object
    obj.name = name
    finish_object(obj, collection, material, bevel=bevel, smooth=True)
    obj.parent = parent
    obj.location = location
    obj.rotation_euler = tuple(math.radians(value) for value in rotation_degrees)
    return obj


def add_cone(
    collection: bpy.types.Collection,
    name: str,
    location: tuple[float, float, float],
    radius_bottom: float,
    radius_top: float,
    depth: float,
    material: bpy.types.Material,
    *,
    vertices: int = 32,
    rotation_degrees: tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel: float = 0.015,
    parent: bpy.types.Object | None = None,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius_bottom,
        radius2=radius_top,
        depth=depth,
    )
    obj = bpy.context.object
    obj.name = name
    finish_object(obj, collection, material, bevel=bevel, smooth=True)
    obj.parent = parent
    obj.location = location
    obj.rotation_euler = tuple(math.radians(value) for value in rotation_degrees)
    return obj


def add_sphere(
    collection: bpy.types.Collection,
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    material: bpy.types.Material,
    *,
    parent: bpy.types.Object | None = None,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=0.5)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    apply_scale(obj)
    finish_object(obj, collection, material, smooth=True)
    obj.parent = parent
    obj.location = location
    return obj


def add_torus(
    collection: bpy.types.Collection,
    name: str,
    location: tuple[float, float, float],
    major_radius: float,
    minor_radius: float,
    material: bpy.types.Material,
    *,
    rotation_degrees: tuple[float, float, float] = (0.0, 0.0, 0.0),
    parent: bpy.types.Object | None = None,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=64,
        minor_segments=16,
    )
    obj = bpy.context.object
    obj.name = name
    finish_object(obj, collection, material, smooth=True)
    obj.parent = parent
    obj.location = location
    obj.rotation_euler = tuple(math.radians(value) for value in rotation_degrees)
    return obj


def add_profile(
    collection: bpy.types.Collection,
    name: str,
    points_xz: list[tuple[float, float]],
    thickness: float,
    material: bpy.types.Material,
    *,
    location: tuple[float, float, float] = (0.0, 0.0, 0.0),
    rotation_degrees: tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel: float = 0.035,
    parent: bpy.types.Object | None = None,
) -> bpy.types.Object:
    half = thickness * 0.5
    count = len(points_xz)
    vertices = [(x, -half, z) for x, z in points_xz] + [(x, half, z) for x, z in points_xz]
    faces: list[tuple[int, ...]] = []
    faces.append(tuple(range(count)))
    faces.append(tuple(range(count, count * 2))[::-1])
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((index, nxt, count + nxt, count + index))
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.data.materials.append(material)
    if bevel > 0.0:
        modifier = obj.modifiers.new("QQ_ProfileBevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = 3
        modifier.limit_method = "ANGLE"
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)
    obj.parent = parent
    obj.location = location
    obj.rotation_euler = tuple(math.radians(value) for value in rotation_degrees)
    return obj


def add_curve(
    collection: bpy.types.Collection,
    name: str,
    points: list[tuple[float, float, float]],
    radius: float,
    material: bpy.types.Material,
    *,
    cyclic: bool = False,
) -> bpy.types.Object:
    curve = bpy.data.curves.new(f"{name}Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 10
    curve.bevel_depth = radius
    curve.bevel_resolution = 4
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, coordinate in zip(spline.bezier_points, points):
        point.co = coordinate
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    spline.use_cyclic_u = cyclic
    obj = bpy.data.objects.new(name, curve)
    collection.objects.link(obj)
    obj.data.materials.append(material)
    return obj


def add_rod_between(
    collection: bpy.types.Collection,
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radius: float,
    material: bpy.types.Material,
    *,
    vertices: int = 32,
) -> bpy.types.Object:
    start_vector = Vector(start)
    end_vector = Vector(end)
    direction = end_vector - start_vector
    obj = add_cylinder(
        collection,
        name,
        tuple((start_vector + end_vector) * 0.5),
        radius,
        direction.length,
        material,
        vertices=vertices,
        bevel=min(radius * 0.32, 0.025),
    )
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    return obj


def add_radial_bolts(
    collection: bpy.types.Collection,
    prefix: str,
    center: tuple[float, float, float],
    radius: float,
    count: int,
    material: bpy.types.Material,
    *,
    bolt_radius: float = 0.045,
) -> None:
    for index in range(count):
        angle = math.tau * float(index) / float(count)
        add_cylinder(
            collection,
            f"{prefix}_Bolt{index:02d}",
            (
                center[0] + math.cos(angle) * radius,
                center[1],
                center[2] + math.sin(angle) * radius,
            ),
            bolt_radius,
            0.08,
            material,
            vertices=16,
            rotation_degrees=(90.0, 0.0, 0.0),
            bevel=0.01,
        )


def add_platform(collection: bpy.types.Collection, prefix: str, accent: bpy.types.Material) -> None:
    add_box(collection, f"{prefix}_Base", (0.0, 0.15, 0.06), (3.65, 2.55, 0.18), MATERIALS["gunmetal"], bevel=0.10)
    add_box(collection, f"{prefix}_Inset", (0.0, -0.02, 0.17), (3.20, 2.12, 0.10), MATERIALS["floor"], bevel=0.06)
    add_box(collection, f"{prefix}_FrontTrim", (0.0, -1.08, 0.20), (2.78, 0.055, 0.055), accent, bevel=0.02)
    add_box(collection, f"{prefix}_FrontRail", (0.0, -1.01, 0.245), (3.18, 0.035, 0.035), MATERIALS["steel_edge"], bevel=0.012)
    for x in (-1.53, 1.53):
        add_box(collection, f"{prefix}_SideRail_{x}", (x, -0.02, 0.235), (0.045, 1.78, 0.045), MATERIALS["steel"], bevel=0.012)
    for x in (-0.82, 0.82):
        add_box(collection, f"{prefix}_PanelSeam_{x}", (x, 0.12, 0.235), (0.022, 1.58, 0.018), MATERIALS["black"], bevel=0.004)
    for index in range(4):
        add_box(
            collection,
            f"{prefix}_Vent{index}",
            (1.18 + index * 0.10, 0.70, 0.245),
            (0.045, 0.34, 0.025),
            MATERIALS["black"],
            rotation_degrees=(0.0, 0.0, -12.0),
            bevel=0.006,
        )
    for x in (-1.48, 1.48):
        for y in (-0.82, 0.82):
            add_cylinder(collection, f"{prefix}_DeckBolt_{x}_{y}", (x, y, 0.25), 0.055, 0.045, MATERIALS["brass_edge"], vertices=16, bevel=0.01)
    for x in (-1.67, 1.67):
        for y in (-1.05, 1.05):
            add_box(collection, f"{prefix}_Corner_{x}_{y}", (x, y, 0.17), (0.18, 0.18, 0.16), MATERIALS["steel"], bevel=0.035)


def add_pedestal(collection: bpy.types.Collection, prefix: str) -> None:
    add_cylinder(collection, f"{prefix}_Foot", (0.0, 0.0, 0.08), 1.18, 0.16, MATERIALS["black"], vertices=64, bevel=0.05)
    add_cylinder(collection, f"{prefix}_Base", (0.0, 0.0, 0.20), 1.02, 0.18, MATERIALS["gunmetal"], vertices=64, bevel=0.045)
    add_cylinder(collection, f"{prefix}_BrassRing", (0.0, 0.0, 0.31), 0.86, 0.10, MATERIALS["brass"], vertices=64, bevel=0.025)
    add_cylinder(collection, f"{prefix}_Top", (0.0, 0.0, 0.39), 0.76, 0.10, MATERIALS["floor"], vertices=64, bevel=0.025)
    add_torus(collection, f"{prefix}_TopInset", (0.0, 0.0, 0.455), 0.62, 0.025, MATERIALS["steel_edge"])
    add_box(collection, f"{prefix}_FrontBadge", (0.0, -0.79, 0.22), (0.34, 0.08, 0.18), MATERIALS["brass"], bevel=0.035)
    for index in range(8):
        angle = math.tau * float(index) / 8.0
        add_cylinder(
            collection,
            f"{prefix}_PedestalBolt{index:02d}",
            (math.cos(angle) * 0.91, math.sin(angle) * 0.91, 0.34),
            0.035,
            0.055,
            MATERIALS["brass_edge"],
            vertices=16,
            bevel=0.008,
        )


def add_target_plate(collection: bpy.types.Collection, prefix: str, location: tuple[float, float, float]) -> None:
    add_profile(
        collection,
        f"{prefix}_Target",
        [(-0.52, 0.78), (0.52, 0.78), (0.62, 0.58), (0.52, -0.70), (0.0, -0.88), (-0.52, -0.70), (-0.62, 0.58)],
        0.16,
        MATERIALS["steel"],
        location=location,
        bevel=0.065,
    )
    add_profile(
        collection,
        f"{prefix}_TargetInset",
        [(-0.40, 0.62), (0.40, 0.62), (0.47, 0.46), (0.39, -0.53), (0.0, -0.68), (-0.39, -0.53), (-0.47, 0.46)],
        0.19,
        MATERIALS["ceramic"],
        location=(location[0], location[1] - 0.10, location[2]),
        bevel=0.045,
    )
    add_box(collection, f"{prefix}_TargetSpine", (location[0], location[1] - 0.11, location[2] + 0.02), (0.11, 0.08, 1.25), MATERIALS["gunmetal"], bevel=0.025)
    for x_offset in (-0.33, 0.33):
        for z_offset in (-0.45, 0.45):
            add_cylinder(collection, f"{prefix}_TargetBolt_{x_offset}_{z_offset}", (location[0] + x_offset, location[1] - 0.20, location[2] + z_offset), 0.055, 0.07, MATERIALS["brass_edge"], vertices=20, rotation_degrees=(90.0, 0.0, 0.0), bevel=0.01)


def add_sword(
    collection: bpy.types.Collection,
    prefix: str,
    location: tuple[float, float, float],
    rotation_degrees: tuple[float, float, float],
    *,
    accent: bpy.types.Material | None = None,
) -> bpy.types.Object:
    root = add_empty(collection, f"{prefix}_SwordRoot", location, rotation_degrees)
    add_cylinder(collection, f"{prefix}_Grip", (0.0, 0.0, -0.58), 0.075, 0.48, MATERIALS["leather"], vertices=24, bevel=0.02, parent=root)
    add_box(collection, f"{prefix}_Guard", (0.0, 0.0, -0.31), (0.58, 0.14, 0.11), MATERIALS["brass"], bevel=0.045, parent=root)
    add_profile(
        collection,
        f"{prefix}_Blade",
        [(-0.12, -0.29), (0.12, -0.29), (0.085, 0.94), (0.0, 1.14), (-0.085, 0.94)],
        0.095,
        MATERIALS["steel_edge"],
        parent=root,
        bevel=0.025,
    )
    add_box(collection, f"{prefix}_Fuller", (0.0, -0.055, 0.32), (0.035, 0.018, 1.04), accent or MATERIALS["cyan"], bevel=0.01, parent=root)
    add_sphere(collection, f"{prefix}_Pommel", (0.0, 0.0, -0.87), (0.12, 0.12, 0.12), MATERIALS["brass_edge"], parent=root)
    return root


def add_shield(
    collection: bpy.types.Collection,
    prefix: str,
    location: tuple[float, float, float],
    scale: float = 1.0,
) -> None:
    outline = [
        (-0.90 * scale, 0.72 * scale),
        (0.90 * scale, 0.72 * scale),
        (0.78 * scale, -0.38 * scale),
        (0.0, -0.92 * scale),
        (-0.78 * scale, -0.38 * scale),
    ]
    inner = [(x * 0.77, z * 0.77) for x, z in outline]
    add_profile(collection, f"{prefix}_ShieldOuter", outline, 0.16, MATERIALS["steel"], location=location, bevel=0.075)
    add_profile(collection, f"{prefix}_ShieldInner", inner, 0.19, MATERIALS["cyan_soft"], location=(location[0], location[1] - 0.10, location[2]), bevel=0.05)
    add_box(collection, f"{prefix}_ShieldVertical", (location[0], location[1] - 0.22, location[2] + 0.03), (0.12 * scale, 0.07, 1.24 * scale), MATERIALS["cyan"], bevel=0.03)
    add_box(collection, f"{prefix}_ShieldHorizontal", (location[0], location[1] - 0.23, location[2] + 0.16), (1.20 * scale, 0.07, 0.11 * scale), MATERIALS["cyan"], bevel=0.03)
    for angle in (-145.0, -35.0, 35.0, 145.0):
        radians = math.radians(angle)
        add_cylinder(
            collection,
            f"{prefix}_ShieldRivet_{angle}",
            (location[0] + math.cos(radians) * 0.63 * scale, location[1] - 0.23, location[2] + math.sin(radians) * 0.50 * scale),
            0.055 * scale,
            0.06,
            MATERIALS["brass_edge"],
            vertices=16,
            rotation_degrees=(90.0, 0.0, 0.0),
            bevel=0.01,
        )


def add_clock_face(
    collection: bpy.types.Collection,
    prefix: str,
    location: tuple[float, float, float],
    radius: float,
    accent: bpy.types.Material,
) -> None:
    add_cylinder(collection, f"{prefix}_ClockBack", location, radius * 0.88, 0.12, MATERIALS["black"], vertices=64, rotation_degrees=(90.0, 0.0, 0.0), bevel=0.035)
    add_torus(collection, f"{prefix}_ClockRing", (location[0], location[1] - 0.08, location[2]), radius, radius * 0.075, MATERIALS["brass"], rotation_degrees=(90.0, 0.0, 0.0))
    for index in range(12):
        angle = math.tau * float(index) / 12.0
        x = location[0] + math.sin(angle) * radius * 0.75
        z = location[2] + math.cos(angle) * radius * 0.75
        add_box(collection, f"{prefix}_Tick{index:02d}", (x, location[1] - 0.16, z), (0.035, 0.035, 0.12 if index % 3 == 0 else 0.075), MATERIALS["brass_edge"], rotation_degrees=(0.0, 0.0, -math.degrees(angle)), bevel=0.008)
    add_rod_between(collection, f"{prefix}_HourHand", (location[0], location[1] - 0.19, location[2]), (location[0] - radius * 0.32, location[1] - 0.19, location[2] + radius * 0.18), radius * 0.035, accent, vertices=16)
    add_rod_between(collection, f"{prefix}_MinuteHand", (location[0], location[1] - 0.20, location[2]), (location[0] + radius * 0.12, location[1] - 0.20, location[2] + radius * 0.55), radius * 0.025, MATERIALS["steel_edge"], vertices=16)
    add_sphere(collection, f"{prefix}_ClockHub", (location[0], location[1] - 0.22, location[2]), (radius * 0.11,) * 3, accent)


def add_robot_arm(
    collection: bpy.types.Collection,
    prefix: str,
    base: tuple[float, float, float],
    elbow: tuple[float, float, float],
    hand: tuple[float, float, float],
    accent: bpy.types.Material,
) -> None:
    add_cylinder(collection, f"{prefix}_Base", base, 0.22, 0.20, MATERIALS["gunmetal"], vertices=36, bevel=0.035)
    add_rod_between(collection, f"{prefix}_Upper", (base[0], base[1], base[2] + 0.12), elbow, 0.10, MATERIALS["steel"], vertices=24)
    add_sphere(collection, f"{prefix}_Elbow", elbow, (0.18, 0.18, 0.18), accent)
    add_rod_between(collection, f"{prefix}_Fore", elbow, hand, 0.085, MATERIALS["steel"], vertices=24)
    add_sphere(collection, f"{prefix}_Wrist", hand, (0.13, 0.13, 0.13), MATERIALS["brass_edge"])
    for side in (-1.0, 1.0):
        add_rod_between(collection, f"{prefix}_Finger_{side}", hand, (hand[0] + side * 0.14, hand[1] - 0.05, hand[2] - 0.14), 0.032, MATERIALS["steel_edge"], vertices=12)


def new_asset_collection(category: str, asset_id: str) -> bpy.types.Collection:
    collection = make_collection(f"ASSET_{category.upper()}_{asset_id}")
    collection["asset_category"] = category
    collection["asset_id"] = asset_id
    collection.hide_render = True
    collection.hide_viewport = True
    ASSET_COLLECTIONS.append(collection)
    return collection


def build_quick_slash() -> bpy.types.Collection:
    collection = new_asset_collection("card", "quick_slash")
    add_platform(collection, "QuickSlash", MATERIALS["cyan"])
    add_target_plate(collection, "QuickSlash", (0.72, 0.50, 1.20))
    add_sword(collection, "QuickSlash", (-0.55, -0.24, 1.14), (0.0, -42.0, -7.0))
    arc_points = []
    for index in range(9):
        angle = math.radians(212.0 - index * 21.0)
        arc_points.append((math.cos(angle) * 1.35 - 0.05, -0.42, math.sin(angle) * 1.15 + 1.18))
    add_curve(collection, "QuickSlash_Arc", arc_points, 0.045, MATERIALS["cyan"])
    add_curve(collection, "QuickSlash_Cut", [(0.35, 0.38, 0.68), (0.68, 0.34, 1.20), (1.02, 0.38, 1.67)], 0.032, MATERIALS["amber"])
    for index, (x, z, rotation) in enumerate(((0.38, 0.92, -24.0), (0.92, 1.41, 31.0), (1.04, 0.92, 58.0))):
        add_box(
            collection,
            f"QuickSlash_CutFragment{index}",
            (x, 0.18, z),
            (0.16, 0.12, 0.26),
            MATERIALS["ceramic_light"],
            rotation_degrees=(rotation, rotation * 0.4, rotation * 0.7),
            bevel=0.025,
        )
    add_curve(collection, "QuickSlash_BladeWake", [(-0.86, -0.22, 0.52), (-0.42, -0.30, 1.04), (0.10, -0.32, 1.55)], 0.018, MATERIALS["steel_edge"])
    for index, offset in enumerate(((-0.22, -0.02), (0.04, 0.16), (0.24, -0.18), (0.38, 0.06))):
        add_cone(collection, f"QuickSlash_Spark{index}", (0.72 + offset[0], 0.18, 1.20 + offset[1]), 0.055, 0.0, 0.28, MATERIALS["amber"], vertices=12, rotation_degrees=(0.0, 75.0 + index * 28.0, 0.0))
    return collection


def build_guard() -> bpy.types.Collection:
    collection = new_asset_collection("card", "guard")
    add_platform(collection, "Guard", MATERIALS["cyan"])
    add_cylinder(collection, "Guard_EmitterBase", (0.0, 0.38, 0.50), 0.72, 0.22, MATERIALS["gunmetal"], vertices=64, bevel=0.05)
    add_torus(collection, "Guard_EmitterRing", (0.0, 0.36, 0.62), 0.62, 0.085, MATERIALS["cyan"], rotation_degrees=(0.0, 0.0, 0.0))
    add_torus(collection, "Guard_FieldOuter", (0.0, -0.34, 1.42), 1.16, 0.028, MATERIALS["cyan"], rotation_degrees=(90.0, 0.0, 0.0))
    add_torus(collection, "Guard_FieldInner", (0.0, -0.35, 1.42), 0.88, 0.018, MATERIALS["cyan_soft"], rotation_degrees=(90.0, 0.0, 0.0))
    add_shield(collection, "Guard", (0.0, -0.16, 1.42), 1.05)
    for index in range(8):
        angle = math.tau * float(index) / 8.0
        start = (math.cos(angle) * 0.67, -0.38, 1.42 + math.sin(angle) * 0.67)
        end = (math.cos(angle) * 0.84, -0.38, 1.42 + math.sin(angle) * 0.84)
        add_rod_between(collection, f"Guard_FieldSpoke{index:02d}", start, end, 0.018, MATERIALS["cyan_soft"], vertices=12)
    for x in (-1.14, 1.14):
        add_box(collection, f"Guard_Pylon_{x}", (x, 0.40, 0.75), (0.24, 0.30, 1.08), MATERIALS["gunmetal"], bevel=0.07)
        add_sphere(collection, f"Guard_PylonCore_{x}", (x, 0.20, 1.08), (0.12, 0.10, 0.12), MATERIALS["cyan"])
        add_curve(collection, f"Guard_PylonCable_{x}", [(x, 0.35, 0.70), (x * 0.72, 0.10, 0.42), (x * 0.34, -0.05, 0.46)], 0.035, MATERIALS["brass"])
    return collection


def build_delay_step() -> bpy.types.Collection:
    collection = new_asset_collection("card", "delay_step")
    add_platform(collection, "DelayStep", MATERIALS["amber"])
    for y in (-0.38, 0.34):
        add_box(collection, f"DelayStep_Rail_{y}", (0.18, y, 0.36), (2.70, 0.11, 0.11), MATERIALS["steel"], bevel=0.035)
    for index in range(9):
        x = -1.10 + index * 0.28
        add_box(collection, f"DelayStep_Tick{index}", (x, -0.62, 0.39), (0.035, 0.18, 0.16 if index % 2 == 0 else 0.10), MATERIALS["brass_edge"], bevel=0.008)
    add_box(collection, "DelayStep_CardCarriage", (0.50, -0.03, 0.62), (0.72, 0.82, 0.16), MATERIALS["ceramic"], rotation_degrees=(0.0, 0.0, -8.0), bevel=0.08)
    add_box(collection, "DelayStep_CardInset", (0.50, -0.12, 0.72), (0.44, 0.52, 0.055), MATERIALS["red"], rotation_degrees=(0.0, 0.0, -8.0), bevel=0.035)
    for x in (0.24, 0.76):
        for y in (-0.42, 0.34):
            add_cylinder(collection, f"DelayStep_CarriageWheel_{x}_{y}", (x, y, 0.49), 0.105, 0.07, MATERIALS["brass"], vertices=24, rotation_degrees=(90.0, 0.0, 0.0), bevel=0.018)
    for index in range(3):
        add_box(collection, f"DelayStep_CarriageVent{index}", (0.37 + index * 0.13, -0.45, 0.72), (0.055, 0.025, 0.22), MATERIALS["black"], rotation_degrees=(0.0, 0.0, -8.0), bevel=0.005)
    add_clock_face(collection, "DelayStep", (-0.98, 0.42, 1.46), 0.62, MATERIALS["amber"])
    add_cylinder(collection, "DelayStep_Weight", (1.28, 0.38, 1.17), 0.30, 0.56, MATERIALS["gunmetal"], vertices=48, bevel=0.045)
    add_torus(collection, "DelayStep_WeightBand", (1.28, 0.38, 1.17), 0.30, 0.055, MATERIALS["red"])
    add_curve(collection, "DelayStep_PullCable", [(0.78, 0.23, 0.68), (1.08, 0.34, 0.82), (1.28, 0.38, 0.92)], 0.035, MATERIALS["brass"])
    return collection


def build_repair_burst() -> bpy.types.Collection:
    collection = new_asset_collection("card", "repair_burst")
    add_platform(collection, "RepairBurst", MATERIALS["green"])
    add_profile(collection, "RepairBurst_BrokenPlate", [(-0.70, 0.76), (0.70, 0.76), (0.82, -0.35), (0.0, -0.86), (-0.82, -0.35)], 0.15, MATERIALS["ceramic"], location=(0.0, 0.38, 1.22), bevel=0.055)
    add_curve(collection, "RepairBurst_CrackA", [(-0.06, 0.25, 1.88), (0.12, 0.24, 1.52), (-0.08, 0.23, 1.19), (0.13, 0.22, 0.76)], 0.028, MATERIALS["black"])
    add_curve(collection, "RepairBurst_CrackB", [(0.10, 0.23, 1.50), (0.42, 0.23, 1.34), (0.57, 0.23, 1.12)], 0.022, MATERIALS["black"])
    add_profile(collection, "RepairBurst_Patch", [(-0.24, 0.18), (0.22, 0.26), (0.30, -0.16), (-0.17, -0.24)], 0.20, MATERIALS["steel"], location=(0.20, 0.12, 1.38), rotation_degrees=(0.0, 0.0, 8.0), bevel=0.035)
    for index, angle in enumerate((-52.0, -22.0, 18.0, 48.0)):
        radians = math.radians(angle)
        add_rod_between(
            collection,
            f"RepairBurst_WeldSpark{index}",
            (0.06, -0.30, 1.43),
            (0.06 + math.sin(radians) * 0.42, -0.34, 1.43 + math.cos(radians) * 0.42),
            0.018,
            MATERIALS["amber"],
            vertices=10,
        )
    add_robot_arm(collection, "RepairBurst_LeftArm", (-1.25, 0.24, 0.42), (-0.90, 0.05, 1.14), (-0.42, -0.02, 1.34), MATERIALS["green"])
    add_robot_arm(collection, "RepairBurst_RightArm", (1.25, 0.24, 0.42), (0.93, 0.04, 1.08), (0.44, -0.03, 1.34), MATERIALS["cyan"])
    add_torus(collection, "RepairBurst_FieldRing", (0.0, 0.14, 1.22), 1.02, 0.045, MATERIALS["green"], rotation_degrees=(90.0, 0.0, 0.0))
    add_cylinder(collection, "RepairBurst_Vial", (-1.26, -0.58, 0.64), 0.14, 0.62, MATERIALS["green"], vertices=32, bevel=0.035)
    add_cylinder(collection, "RepairBurst_VialCap", (-1.26, -0.58, 0.98), 0.19, 0.12, MATERIALS["brass"], vertices=32, bevel=0.025)
    return collection


def build_auto_turret() -> bpy.types.Collection:
    collection = new_asset_collection("card", "auto_turret")
    add_platform(collection, "AutoTurret", MATERIALS["amber"])
    add_cylinder(collection, "AutoTurret_PivotBase", (0.0, 0.20, 0.46), 0.72, 0.34, MATERIALS["gunmetal"], vertices=64, bevel=0.06)
    add_torus(collection, "AutoTurret_PivotRing", (0.0, 0.20, 0.64), 0.58, 0.07, MATERIALS["amber"])
    add_box(collection, "AutoTurret_Body", (0.0, 0.10, 1.18), (1.18, 0.82, 0.72), MATERIALS["steel"], rotation_degrees=(0.0, 0.0, -4.0), bevel=0.12)
    add_box(collection, "AutoTurret_Armor", (0.0, -0.37, 1.28), (0.82, 0.10, 0.43), MATERIALS["gunmetal"], bevel=0.06)
    for side in (-1.0, 1.0):
        add_profile(
            collection,
            f"AutoTurret_SideArmor_{side}",
            [(-0.34, 0.34), (0.34, 0.24), (0.28, -0.34), (-0.28, -0.34)],
            0.10,
            MATERIALS["steel"],
            location=(0.65 * side, 0.06, 1.24),
            rotation_degrees=(90.0, 0.0, 90.0),
            bevel=0.045,
        )
        add_cylinder(collection, f"AutoTurret_ShoulderBolt_{side}", (0.65 * side, -0.08, 1.28), 0.095, 0.08, MATERIALS["brass_edge"], vertices=24, rotation_degrees=(0.0, 90.0, 0.0), bevel=0.018)
    for side in (-1.0, 1.0):
        add_cylinder(collection, f"AutoTurret_Barrel_{side}", (0.24 * side, -0.92, 1.34), 0.12, 1.15, MATERIALS["gunmetal"], vertices=36, rotation_degrees=(90.0, 0.0, 0.0), bevel=0.03)
        add_cylinder(collection, f"AutoTurret_Muzzle_{side}", (0.24 * side, -1.50, 1.34), 0.18, 0.16, MATERIALS["steel_edge"], vertices=36, rotation_degrees=(90.0, 0.0, 0.0), bevel=0.025)
        add_sphere(collection, f"AutoTurret_MuzzleGlow_{side}", (0.24 * side, -1.60, 1.34), (0.09, 0.05, 0.09), MATERIALS["amber"])
        for band_index in range(3):
            add_torus(collection, f"AutoTurret_BarrelBand_{side}_{band_index}", (0.24 * side, -0.77 - band_index * 0.28, 1.34), 0.13, 0.024, MATERIALS["brass"], rotation_degrees=(90.0, 0.0, 0.0))
    add_sphere(collection, "AutoTurret_Eye", (0.0, -0.46, 1.42), (0.18, 0.08, 0.15), MATERIALS["red"])
    add_cylinder(collection, "AutoTurret_AmmoDrum", (0.72, 0.20, 1.12), 0.32, 0.44, MATERIALS["brass"], vertices=40, rotation_degrees=(0.0, 90.0, 0.0), bevel=0.04)
    for index in range(7):
        add_box(collection, f"AutoTurret_Ammo{index}", (0.76 + index * 0.12, 0.52 + index * 0.04, 0.90 - index * 0.05), (0.09, 0.18, 0.16), MATERIALS["brass_edge"], rotation_degrees=(0.0, 0.0, -14.0), bevel=0.025)
    return collection


def build_event_horizon() -> bpy.types.Collection:
    collection = new_asset_collection("card", "event_horizon")
    add_platform(collection, "EventHorizon", MATERIALS["purple"])
    ring_materials = (MATERIALS["gunmetal"], MATERIALS["cyan_soft"], MATERIALS["purple"])
    for index, radius in enumerate((1.22, 0.94, 0.70)):
        add_torus(collection, f"EventHorizon_Ring{index}", (0.0, 0.20 + index * 0.05, 1.32), radius, 0.075 - index * 0.012, ring_materials[index], rotation_degrees=(90.0, 0.0, index * 24.0))
    add_torus(collection, "EventHorizon_OuterGlow", (0.0, 0.15, 1.32), 1.23, 0.018, MATERIALS["purple"], rotation_degrees=(90.0, 0.0, 0.0))
    add_sphere(collection, "EventHorizon_Core", (0.0, 0.02, 1.32), (0.68, 0.48, 0.68), MATERIALS["black"])
    add_torus(collection, "EventHorizon_Accretion", (0.0, -0.28, 1.32), 0.76, 0.075, MATERIALS["amber"], rotation_degrees=(72.0, 0.0, 18.0))
    for index in range(8):
        angle = math.tau * float(index) / 8.0
        add_box(
            collection,
            f"EventHorizon_RingClamp{index:02d}",
            (math.cos(angle) * 1.22, -0.02, 1.32 + math.sin(angle) * 1.22),
            (0.16, 0.13, 0.09),
            MATERIALS["brass"],
            rotation_degrees=(0.0, 0.0, -math.degrees(angle)),
            bevel=0.025,
        )
    for lane in (-0.72, 0.72):
        add_curve(collection, f"EventHorizon_Rail_{lane}", [(lane * 1.9, 0.58, 0.48), (lane * 1.25, 0.42, 0.68), (lane * 0.62, 0.26, 1.02), (lane * 0.20, 0.10, 1.28)], 0.055, MATERIALS["steel"])
    for index in range(11):
        angle = math.tau * float(index) / 11.0
        radius = 1.52 + (index % 3) * 0.13
        add_box(collection, f"EventHorizon_Debris{index:02d}", (math.cos(angle) * radius, 0.05 + 0.12 * math.sin(angle * 2.0), 1.32 + math.sin(angle) * radius * 0.72), (0.12, 0.08, 0.22), MATERIALS["ceramic_light"] if index % 3 == 0 else MATERIALS["steel"], rotation_degrees=(index * 29.0, index * 41.0, index * 17.0), bevel=0.025)
    return collection


def build_iron_plating() -> bpy.types.Collection:
    collection = new_asset_collection("relic", "iron_plating")
    add_pedestal(collection, "IronPlating")
    add_profile(collection, "IronPlating_Chest", [(-0.92, 0.76), (-0.55, 1.02), (0.0, 0.83), (0.55, 1.02), (0.92, 0.76), (0.72, -0.62), (0.0, -0.94), (-0.72, -0.62)], 0.30, MATERIALS["steel"], location=(0.0, 0.0, 1.42), bevel=0.09)
    add_profile(collection, "IronPlating_Inset", [(-0.63, 0.59), (0.0, 0.38), (0.63, 0.59), (0.51, -0.42), (0.0, -0.67), (-0.51, -0.42)], 0.34, MATERIALS["gunmetal"], location=(0.0, -0.18, 1.42), bevel=0.06)
    add_box(collection, "IronPlating_Spine", (0.0, -0.35, 1.42), (0.13, 0.07, 1.34), MATERIALS["brass"], bevel=0.025)
    add_profile(collection, "IronPlating_LeftFlange", [(-0.94, 0.66), (-0.56, 0.92), (-0.50, 0.42), (-0.78, 0.10), (-1.03, 0.28)], 0.26, MATERIALS["steel_edge"], location=(-0.08, 0.08, 1.43), bevel=0.05)
    add_profile(collection, "IronPlating_RightFlange", [(0.56, 0.92), (0.94, 0.66), (1.03, 0.28), (0.78, 0.10), (0.50, 0.42)], 0.26, MATERIALS["steel_edge"], location=(0.08, 0.08, 1.43), bevel=0.05)
    for z in (1.10, 1.36, 1.62):
        add_box(collection, f"IronPlating_Rib_{z}", (0.0, -0.38, z), (0.82, 0.055, 0.045), MATERIALS["brass"], bevel=0.012)
    add_torus(collection, "IronPlating_Collar", (0.0, 0.02, 2.11), 0.34, 0.075, MATERIALS["gunmetal"], rotation_degrees=(90.0, 0.0, 0.0))
    for x in (-0.67, 0.67):
        for z in (1.00, 1.78):
            add_cylinder(collection, f"IronPlating_Rivet_{x}_{z}", (x, -0.36, z), 0.08, 0.08, MATERIALS["brass_edge"], vertices=20, rotation_degrees=(90.0, 0.0, 0.0), bevel=0.012)
    return collection


def build_auxiliary_core() -> bpy.types.Collection:
    collection = new_asset_collection("relic", "auxiliary_core")
    add_pedestal(collection, "AuxiliaryCore")
    add_cylinder(collection, "AuxiliaryCore_Back", (0.0, 0.08, 1.44), 0.92, 0.26, MATERIALS["gunmetal"], vertices=64, rotation_degrees=(90.0, 0.0, 0.0), bevel=0.06)
    add_torus(collection, "AuxiliaryCore_Outer", (0.0, -0.10, 1.44), 0.92, 0.12, MATERIALS["brass"], rotation_degrees=(90.0, 0.0, 0.0))
    add_torus(collection, "AuxiliaryCore_Inner", (0.0, -0.22, 1.44), 0.56, 0.075, MATERIALS["steel_edge"], rotation_degrees=(90.0, 0.0, 0.0))
    add_sphere(collection, "AuxiliaryCore_CellHousing", (0.0, -0.29, 1.44), (0.51, 0.24, 0.51), MATERIALS["gunmetal"])
    add_sphere(collection, "AuxiliaryCore_Cell", (0.0, -0.43, 1.44), (0.34, 0.18, 0.34), MATERIALS["cyan"])
    frame_points: list[tuple[float, float, float]] = []
    for index in range(8):
        angle = math.tau * float(index) / 8.0 + math.pi / 8.0
        frame_points.append((math.cos(angle) * 1.10, -0.14, 1.44 + math.sin(angle) * 1.10))
    for index, start in enumerate(frame_points):
        add_rod_between(collection, f"AuxiliaryCore_Frame{index:02d}", start, frame_points[(index + 1) % len(frame_points)], 0.075, MATERIALS["steel"], vertices=20)
    for index in range(8):
        angle = math.tau * float(index) / 8.0
        start = (math.cos(angle) * 0.58, -0.28, 1.44 + math.sin(angle) * 0.58)
        end = (math.cos(angle) * 0.84, -0.24, 1.44 + math.sin(angle) * 0.84)
        add_rod_between(collection, f"AuxiliaryCore_Spoke{index:02d}", start, end, 0.055, MATERIALS["brass_edge"], vertices=16)
    add_radial_bolts(collection, "AuxiliaryCore", (0.0, -0.34, 1.44), 0.74, 8, MATERIALS["steel_edge"], bolt_radius=0.045)
    for side in (-1.0, 1.0):
        add_cylinder(collection, f"AuxiliaryCore_Capacitor_{side}", (0.74 * side, 0.04, 0.73), 0.14, 0.46, MATERIALS["gunmetal"], vertices=36, bevel=0.035)
        add_torus(collection, f"AuxiliaryCore_CapBand_{side}", (0.74 * side, 0.04, 0.73), 0.145, 0.025, MATERIALS["brass"])
        add_curve(collection, f"AuxiliaryCore_Conduit_{side}", [(0.70 * side, 0.02, 0.94), (0.82 * side, -0.04, 1.13), (0.72 * side, -0.16, 1.36)], 0.035, MATERIALS["cyan_soft"])
    return collection


def build_chrono_shard() -> bpy.types.Collection:
    collection = new_asset_collection("relic", "chrono_shard")
    add_pedestal(collection, "ChronoShard")
    add_clock_face(collection, "ChronoShard", (0.0, 0.12, 1.42), 0.92, MATERIALS["cyan"])
    shard_root = add_empty(collection, "ChronoShard_CrystalRoot", (0.0, -0.38, 1.40), (0.0, 0.0, -13.0))
    add_profile(collection, "ChronoShard_Crystal", [(-0.27, -0.84), (0.35, -0.50), (0.24, 0.78), (0.0, 1.05), (-0.32, 0.55)], 0.26, MATERIALS["crystal"], parent=shard_root, bevel=0.045)
    add_profile(collection, "ChronoShard_Core", [(-0.07, -0.70), (0.12, -0.35), (0.06, 0.74), (-0.08, 0.48)], 0.30, MATERIALS["cyan"], parent=shard_root, bevel=0.025)
    add_profile(collection, "ChronoShard_Facet", [(-0.24, -0.72), (-0.04, -0.52), (-0.02, 0.74), (-0.19, 0.52)], 0.31, MATERIALS["cyan_soft"], parent=shard_root, bevel=0.015)
    for index, (x, z, tilt) in enumerate(((-0.61, 0.93, -20.0), (0.62, 1.04, 24.0), (-0.47, 1.70, 18.0))):
        crystal_root = add_empty(collection, f"ChronoShard_FragmentRoot{index}", (x, -0.24, z), (0.0, 0.0, tilt))
        add_profile(collection, f"ChronoShard_Fragment{index}", [(-0.10, -0.24), (0.12, -0.14), (0.05, 0.28), (-0.06, 0.20)], 0.12, MATERIALS["crystal"], parent=crystal_root, bevel=0.018)
    for index in range(3):
        add_torus(collection, f"ChronoShard_Orbit{index}", (0.0, -0.18 - index * 0.04, 1.42), 0.55 + index * 0.13, 0.022, MATERIALS["brass_edge"], rotation_degrees=(90.0, index * 17.0, index * 31.0))
    return collection


def build_salvage_magnet() -> bpy.types.Collection:
    collection = new_asset_collection("relic", "salvage_magnet")
    add_pedestal(collection, "SalvageMagnet")
    add_curve(collection, "SalvageMagnet_Horseshoe", [(-0.72, 0.0, 1.75), (-0.78, 0.0, 1.15), (-0.55, 0.0, 0.78), (0.0, 0.0, 0.62), (0.55, 0.0, 0.78), (0.78, 0.0, 1.15), (0.72, 0.0, 1.75)], 0.22, MATERIALS["gunmetal"])
    add_box(collection, "SalvageMagnet_LeftPole", (-0.70, -0.02, 1.83), (0.46, 0.42, 0.48), MATERIALS["gunmetal"], bevel=0.08)
    add_box(collection, "SalvageMagnet_RightPole", (0.70, -0.02, 1.83), (0.46, 0.42, 0.48), MATERIALS["gunmetal"], bevel=0.08)
    add_box(collection, "SalvageMagnet_LeftPoleFace", (-0.70, -0.25, 1.83), (0.33, 0.055, 0.31), MATERIALS["red"], bevel=0.045)
    add_box(collection, "SalvageMagnet_RightPoleFace", (0.70, -0.25, 1.83), (0.33, 0.055, 0.31), MATERIALS["cyan"], bevel=0.045)
    add_box(collection, "SalvageMagnet_LeftCap", (-0.70, -0.10, 2.08), (0.54, 0.50, 0.12), MATERIALS["steel_edge"], bevel=0.035)
    add_box(collection, "SalvageMagnet_RightCap", (0.70, -0.10, 2.08), (0.54, 0.50, 0.12), MATERIALS["steel_edge"], bevel=0.035)
    for side in (-1.0, 1.0):
        for index in range(5):
            angle = math.radians(-35.0 + index * 18.0)
            add_torus(collection, f"SalvageMagnet_Coil_{side}_{index}", (side * (0.58 + 0.09 * math.cos(angle)), 0.0, 1.08 + 0.35 * math.sin(angle)), 0.24, 0.035, MATERIALS["brass"], rotation_degrees=(90.0, 0.0, 0.0))
    scrap_specs = [(-0.38, -0.42, 1.54, 0.14), (-0.18, -0.50, 1.30, 0.10), (0.10, -0.48, 1.38, 0.10), (0.34, -0.38, 1.65, 0.12), (-0.02, -0.54, 1.73, 0.08), (0.48, -0.45, 1.30, 0.09), (-0.46, -0.41, 1.82, 0.07)]
    for index, (x, y, z, size) in enumerate(scrap_specs):
        add_box(collection, f"SalvageMagnet_Scrap{index}", (x, y, z), (size, size * 0.65, size * 1.45), MATERIALS["brass_edge"] if index % 2 else MATERIALS["steel"], rotation_degrees=(index * 23.0, index * 37.0, index * 51.0), bevel=0.025)
        add_curve(collection, f"SalvageMagnet_Field{index}", [(x, y + 0.08, z), (x * 1.45, y + 0.12, z + 0.22), ((-0.62 if x < 0.0 else 0.62), -0.18, 1.78)], 0.018, MATERIALS["cyan"] if x > 0.0 else MATERIALS["red"])
    return collection


def build_bleed_icon() -> bpy.types.Collection:
    collection = new_asset_collection("icon", "bleed")
    add_cylinder(collection, "Bleed_Medallion", (0.0, 0.08, 0.82), 1.05, 0.20, MATERIALS["black"], vertices=64, rotation_degrees=(90.0, 0.0, 0.0), bevel=0.05)
    add_torus(collection, "Bleed_OuterRing", (0.0, -0.06, 0.82), 0.98, 0.085, MATERIALS["steel"], rotation_degrees=(90.0, 0.0, 0.0))
    add_torus(collection, "Bleed_InnerRing", (0.0, -0.13, 0.82), 0.78, 0.035, MATERIALS["red"], rotation_degrees=(90.0, 0.0, 0.0))
    add_profile(collection, "Bleed_Drop", [(0.0, 0.82), (0.43, 0.18), (0.37, -0.30), (0.0, -0.62), (-0.37, -0.30), (-0.43, 0.18)], 0.24, MATERIALS["red"], location=(0.0, -0.24, 0.82), bevel=0.08)
    add_profile(collection, "Bleed_Highlight", [(-0.12, 0.42), (0.02, 0.55), (-0.02, 0.02), (-0.17, -0.16)], 0.27, MATERIALS["steel_edge"], location=(0.0, -0.36, 0.82), bevel=0.025)
    return collection


def build_attack_icon() -> bpy.types.Collection:
    collection = new_asset_collection("icon", "attack")
    add_cylinder(collection, "Attack_Medallion", (0.0, 0.10, 0.92), 1.03, 0.18, MATERIALS["black"], vertices=64, rotation_degrees=(90.0, 0.0, 0.0), bevel=0.05)
    add_torus(collection, "Attack_MedallionRing", (0.0, -0.04, 0.92), 0.96, 0.075, MATERIALS["brass"], rotation_degrees=(90.0, 0.0, 0.0))
    root = add_empty(collection, "Attack_SwordRoot", (0.0, -0.12, 0.92), (0.0, -42.0, 0.0))
    add_cylinder(collection, "Attack_Grip", (0.0, -0.14, -0.67), 0.11, 0.46, MATERIALS["leather"], vertices=24, bevel=0.025, parent=root)
    add_box(collection, "Attack_Guard", (0.0, 0.0, -0.40), (0.72, 0.18, 0.12), MATERIALS["brass_edge"], bevel=0.05, parent=root)
    add_profile(collection, "Attack_Blade", [(-0.18, -0.37), (0.18, -0.37), (0.13, 0.88), (0.0, 1.18), (-0.13, 0.88)], 0.16, MATERIALS["ceramic_light"], parent=root, bevel=0.035)
    add_box(collection, "Attack_BladeGlow", (0.0, -0.08, 0.28), (0.045, 0.025, 1.00), MATERIALS["amber"], bevel=0.012, parent=root)
    for index in range(8):
        angle = math.tau * float(index) / 8.0
        start = (math.cos(angle) * 0.44, 0.08, 0.92 + math.sin(angle) * 0.44)
        end = (math.cos(angle) * 0.83, 0.06, 0.92 + math.sin(angle) * 0.83)
        add_rod_between(collection, f"Attack_Burst{index}", start, end, 0.045, MATERIALS["amber"], vertices=12)
    return collection


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def add_area_light(
    collection: bpy.types.Collection,
    name: str,
    location: tuple[float, float, float],
    energy: float,
    color: tuple[float, float, float],
    size: float,
    target: tuple[float, float, float],
) -> None:
    light_data = bpy.data.lights.new(name, "AREA")
    light_data.energy = energy
    light_data.color = color
    light_data.shape = "DISK"
    light_data.size = size
    light = bpy.data.objects.new(name, light_data)
    light.location = location
    look_at(light, Vector(target))
    collection.objects.link(light)


def setup_render_scene() -> None:
    global LIGHT_COLLECTION, BACKDROP_COLLECTION, CAMERA
    scene = bpy.context.scene
    scene.name = "QQArtVerticalSlice"
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x = RENDER_SIZE
    scene.render.resolution_y = RENDER_SIZE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.film_transparent = False
    scene.render.use_file_extension = True
    scene.view_settings.look = "AgX - Medium High Contrast"

    world = bpy.data.worlds.new("QQArtWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.004, 0.008, 0.016, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.20
    scene.world = world

    BACKDROP_COLLECTION = make_collection("RENDER_BACKDROP")
    add_box(BACKDROP_COLLECTION, "BackdropFloor", (0.0, 0.0, -0.20), (12.0, 12.0, 0.30), MATERIALS["floor"], bevel=0.12)
    add_box(BACKDROP_COLLECTION, "BackdropWall", (0.0, 3.20, 3.20), (12.0, 0.30, 6.4), MATERIALS["black"], bevel=0.15)
    for x in (-3.8, -1.9, 0.0, 1.9, 3.8):
        add_box(BACKDROP_COLLECTION, f"BackdropLine_{x}", (x, 3.01, 1.65), (0.028, 0.025, 3.30), MATERIALS["gunmetal"], bevel=0.008)

    LIGHT_COLLECTION = make_collection("RENDER_LIGHTS")
    add_area_light(LIGHT_COLLECTION, "KeyLight", (-3.8, -4.5, 6.8), 1080.0, (0.62, 0.80, 1.0), 4.0, (0.0, 0.0, 1.1))
    add_area_light(LIGHT_COLLECTION, "FillLight", (4.4, -2.2, 3.8), 720.0, (0.38, 0.74, 1.0), 3.4, (0.0, 0.0, 1.0))
    add_area_light(LIGHT_COLLECTION, "RimLight", (2.2, 3.6, 5.0), 1180.0, (1.0, 0.30, 0.08), 3.0, (0.0, 0.0, 1.35))
    add_area_light(LIGHT_COLLECTION, "TopLight", (0.0, 0.5, 7.2), 760.0, (0.72, 0.90, 1.0), 3.2, (0.0, 0.0, 0.0))

    camera_data = bpy.data.cameras.new("QQArtCamera")
    camera_data.type = "ORTHO"
    camera_data.lens = 70.0
    CAMERA = bpy.data.objects.new("QQArtCamera", camera_data)
    LIGHT_COLLECTION.objects.link(CAMERA)
    scene.camera = CAMERA


def set_collection_visibility(collection: bpy.types.Collection, visible: bool) -> None:
    collection.hide_render = not visible
    collection.hide_viewport = not visible


def render_asset(
    asset_id: str,
    category: str,
    collection: bpy.types.Collection,
    *,
    ortho_scale: float,
    camera_mode: str = "iso",
    transparent: bool = False,
) -> Path:
    if CAMERA is None or BACKDROP_COLLECTION is None:
        raise RuntimeError("Render rig has not been initialized")
    for asset_collection in ASSET_COLLECTIONS:
        set_collection_visibility(asset_collection, asset_collection == collection)
    set_collection_visibility(BACKDROP_COLLECTION, not transparent)

    if camera_mode == "front":
        CAMERA.location = (0.0, -8.4, 0.92)
        look_at(CAMERA, Vector((0.0, 0.0, 0.92)))
    else:
        CAMERA.location = (4.55, -7.30, 4.25)
        look_at(CAMERA, Vector((0.0, 0.0, 1.10)))
    CAMERA.data.ortho_scale = ortho_scale

    output_dir = {"card": CARD_RENDER_DIR, "relic": RELIC_RENDER_DIR, "icon": ICON_RENDER_DIR}[category]
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"{asset_id}.png"
    scene = bpy.context.scene
    scene.render.film_transparent = transparent
    scene.render.filepath = str(output_path)
    bpy.ops.render.render(write_still=True)
    print("QQ_ART_RENDERED", category, asset_id, output_path)
    return output_path


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_manifests(outputs: dict[str, dict[str, Path]]) -> None:
    BUILD_ROOT.mkdir(parents=True, exist_ok=True)
    card_manifest = {asset_id: str(path.resolve()) for asset_id, path in outputs["card"].items()}
    relic_manifest = {asset_id: str(path.resolve()) for asset_id, path in outputs["relic"].items()}
    icon_manifest = {
        asset_id: {
            "source": str(outputs["icon"][asset_id].resolve()),
            "target": spec["target"],
            "size": spec["size"],
        }
        for asset_id, spec in ICON_SPECS.items()
    }
    CARD_MANIFEST_PATH.write_text(json.dumps(card_manifest, indent=2) + "\n", encoding="utf-8")
    RELIC_MANIFEST_PATH.write_text(json.dumps(relic_manifest, indent=2) + "\n", encoding="utf-8")
    ICON_MANIFEST_PATH.write_text(json.dumps(icon_manifest, indent=2) + "\n", encoding="utf-8")

    asset_entries = []
    for category, category_outputs in outputs.items():
        for asset_id, output_path in category_outputs.items():
            target = (
                f"assets/icons/cards/{asset_id}.png"
                if category == "card"
                else f"assets/icons/relics/{asset_id}.png"
                if category == "relic"
                else ICON_SPECS[asset_id]["target"].replace("res://", "")
            )
            asset_entries.append(
                {
                    "id": asset_id,
                    "category": category,
                    "target": target,
                    "render_sha256": sha256_file(output_path),
                }
            )
    source_manifest = {
        "format_version": 1,
        "generator": "tools/blender/build_art_vertical_slice.py",
        "blender_version": bpy.app.version_string,
        "render_engine": bpy.context.scene.render.engine,
        "render_size": RENDER_SIZE,
        "blend": "art_src/blender/art_vertical_slice.blend",
        "intermediate_root": "tools/.local/blender_art_vertical_slice",
        "assets": sorted(asset_entries, key=lambda entry: (entry["category"], entry["id"])),
    }
    SOURCE_MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    SOURCE_MANIFEST_PATH.write_text(json.dumps(source_manifest, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    for directory in (BUILD_ROOT, CARD_RENDER_DIR, RELIC_RENDER_DIR, ICON_RENDER_DIR, SOURCE_PATH.parent):
        directory.mkdir(parents=True, exist_ok=True)
    clear_file()
    build_materials()
    setup_render_scene()

    card_builders: dict[str, Callable[[], bpy.types.Collection]] = {
        "quick_slash": build_quick_slash,
        "guard": build_guard,
        "delay_step": build_delay_step,
        "repair_burst": build_repair_burst,
        "auto_turret": build_auto_turret,
        "event_horizon": build_event_horizon,
    }
    relic_builders: dict[str, Callable[[], bpy.types.Collection]] = {
        "iron_plating": build_iron_plating,
        "auxiliary_core": build_auxiliary_core,
        "chrono_shard": build_chrono_shard,
        "salvage_magnet": build_salvage_magnet,
    }
    icon_builders: dict[str, Callable[[], bpy.types.Collection]] = {
        "bleed": build_bleed_icon,
        "attack": build_attack_icon,
    }

    collections: dict[str, dict[str, bpy.types.Collection]] = {"card": {}, "relic": {}, "icon": {}}
    for asset_id in CARD_IDS:
        collections["card"][asset_id] = card_builders[asset_id]()
    for asset_id in RELIC_IDS:
        collections["relic"][asset_id] = relic_builders[asset_id]()
    for asset_id in ICON_SPECS:
        collections["icon"][asset_id] = icon_builders[asset_id]()

    outputs: dict[str, dict[str, Path]] = {"card": {}, "relic": {}, "icon": {}}
    for asset_id in CARD_IDS:
        outputs["card"][asset_id] = render_asset(asset_id, "card", collections["card"][asset_id], ortho_scale=4.65)
    for asset_id in RELIC_IDS:
        outputs["relic"][asset_id] = render_asset(asset_id, "relic", collections["relic"][asset_id], ortho_scale=3.65)
    outputs["icon"]["bleed"] = render_asset("bleed", "icon", collections["icon"]["bleed"], ortho_scale=2.65, camera_mode="front", transparent=True)
    outputs["icon"]["attack"] = render_asset("attack", "icon", collections["icon"]["attack"], ortho_scale=2.65, camera_mode="front", transparent=True)

    write_manifests(outputs)
    for asset_collection in ASSET_COLLECTIONS:
        set_collection_visibility(asset_collection, False)
    set_collection_visibility(collections["card"]["quick_slash"], True)
    if BACKDROP_COLLECTION is not None:
        set_collection_visibility(BACKDROP_COLLECTION, True)
    bpy.context.scene.render.film_transparent = False
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_PATH), check_existing=False)

    print(
        "QQ_ART_VERTICAL_SLICE_OK",
        {
            "cards": len(outputs["card"]),
            "relics": len(outputs["relic"]),
            "icons": len(outputs["icon"]),
            "render_size": RENDER_SIZE,
            "blend": str(SOURCE_PATH),
            "manifest": str(SOURCE_MANIFEST_PATH),
        },
    )


if __name__ == "__main__":
    main()
