"""Build the first authored battle character pair and export Godot-ready GLBs.

Run from Blender or Blender MCP. The script deliberately uses only Blender's
built-in Python API so the source remains reproducible on another workstation.
"""

from __future__ import annotations

import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


PROJECT_ROOT = Path(__file__).resolve().parents[2]
MODEL_DIR = PROJECT_ROOT / "assets" / "models" / "battle"
SOURCE_PATH = PROJECT_ROOT / "art_src" / "blender" / "battle_vertical_slice.blend"
PREVIEW_PATH = PROJECT_ROOT / "art_src" / "blender" / "previews" / "battle_vertical_slice.png"

MODEL_DIR.mkdir(parents=True, exist_ok=True)
SOURCE_PATH.parent.mkdir(parents=True, exist_ok=True)
PREVIEW_PATH.parent.mkdir(parents=True, exist_ok=True)


# Godot's procedural combat rig uses identity-oriented bones with local offsets.
# Blender is Z-up, so Godot (x, y, z) maps to Blender (x, -z, y).
BONE_DEFINITIONS = [
    ("root", "", (0.0, 0.28, 0.0)),
    ("hips", "root", (0.0, 0.68, 0.0)),
    ("spine", "hips", (0.0, 0.22, 0.0)),
    ("chest", "spine", (0.0, 0.40, 0.0)),
    ("neck", "chest", (0.0, 0.35, 0.0)),
    ("head", "neck", (0.0, 0.22, 0.0)),
    ("left_upper_leg", "hips", (-0.23, -0.05, 0.0)),
    ("left_lower_leg", "left_upper_leg", (0.0, -0.43, 0.0)),
    ("left_foot", "left_lower_leg", (0.0, -0.40, -0.02)),
    ("right_upper_leg", "hips", (0.23, -0.05, 0.0)),
    ("right_lower_leg", "right_upper_leg", (0.0, -0.43, 0.0)),
    ("right_foot", "right_lower_leg", (0.0, -0.40, -0.02)),
    ("left_upper_arm", "chest", (-0.50, 0.22, 0.0)),
    ("left_forearm", "left_upper_arm", (0.0, -0.43, 0.0)),
    ("left_hand", "left_forearm", (0.0, -0.38, 0.0)),
    ("right_upper_arm", "chest", (0.50, 0.22, 0.0)),
    ("right_forearm", "right_upper_arm", (0.0, -0.43, 0.0)),
    ("right_hand", "right_forearm", (0.0, -0.38, 0.0)),
]


def godot_to_blender(value: tuple[float, float, float]) -> Vector:
    return Vector((value[0], -value[2], value[1]))


def clear_file() -> None:
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        bpy.data.collections.remove(collection)
    for datablocks in (bpy.data.meshes, bpy.data.armatures, bpy.data.cameras, bpy.data.lights, bpy.data.materials):
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


def make_material(
    name: str,
    color: tuple[float, float, float, float],
    metallic: float = 0.0,
    roughness: float = 0.72,
    emission: tuple[float, float, float, float] | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.metallic = metallic
    material.roughness = roughness
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    if shader:
        shader.inputs["Base Color"].default_value = color
        shader.inputs["Metallic"].default_value = metallic
        shader.inputs["Roughness"].default_value = roughness
        if emission and "Emission Color" in shader.inputs:
            shader.inputs["Emission Color"].default_value = emission
            shader.inputs["Emission Strength"].default_value = emission_strength
    return material


def assign_material(obj: bpy.types.Object, material: bpy.types.Material) -> None:
    obj.data.materials.append(material)


def apply_object_transform(obj: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.select_set(False)


def apply_bevel(obj: bpy.types.Object, width: float, segments: int = 1) -> None:
    if width <= 0.0:
        return
    modifier = obj.modifiers.new("SoftLowPolyEdges", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


def set_mesh_shading(obj: bpy.types.Object, smooth: bool) -> None:
    for polygon in obj.data.polygons:
        polygon.use_smooth = smooth


def bind_to_bone(obj: bpy.types.Object, armature: bpy.types.Object, bone_name: str) -> bpy.types.Object:
    obj.parent = armature
    obj.matrix_parent_inverse = armature.matrix_world.inverted()
    vertex_group = obj.vertex_groups.new(name=bone_name)
    vertex_group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    modifier = obj.modifiers.new("BattleRig", "ARMATURE")
    modifier.object = armature
    modifier.use_deform_preserve_volume = False
    obj["battle_bone"] = bone_name
    return obj


def add_cube(
    collection: bpy.types.Collection,
    armature: bpy.types.Object,
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    material: bpy.types.Material,
    bone: str,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel: float = 0.025,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    apply_object_transform(obj)
    apply_bevel(obj, bevel, 1)
    assign_material(obj, material)
    move_to_collection(obj, collection)
    return bind_to_bone(obj, armature, bone)


def add_ellipsoid(
    collection: bpy.types.Collection,
    armature: bpy.types.Object,
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    material: bpy.types.Material,
    bone: str,
    subdivisions: int = 2,
    smooth: bool = False,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=0.5, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    apply_object_transform(obj)
    set_mesh_shading(obj, smooth)
    assign_material(obj, material)
    move_to_collection(obj, collection)
    return bind_to_bone(obj, armature, bone)


def add_cone(
    collection: bpy.types.Collection,
    armature: bpy.types.Object,
    name: str,
    location: tuple[float, float, float],
    radius_bottom: float,
    radius_top: float,
    depth: float,
    material: bpy.types.Material,
    bone: str,
    radial_scale_y: float = 1.0,
    vertices: int = 8,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    smooth: bool = False,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius_bottom,
        radius2=radius_top,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale.y = radial_scale_y
    apply_object_transform(obj)
    set_mesh_shading(obj, smooth)
    assign_material(obj, material)
    move_to_collection(obj, collection)
    return bind_to_bone(obj, armature, bone)


def add_cylinder(
    collection: bpy.types.Collection,
    armature: bpy.types.Object,
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    material: bpy.types.Material,
    bone: str,
    radial_scale_y: float = 1.0,
    vertices: int = 8,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    return add_cone(
        collection,
        armature,
        name,
        location,
        radius,
        radius,
        depth,
        material,
        bone,
        radial_scale_y,
        vertices,
        rotation,
    )


def add_prism(
    collection: bpy.types.Collection,
    armature: bpy.types.Object,
    name: str,
    points_xz: list[tuple[float, float]],
    center_y: float,
    depth: float,
    material: bpy.types.Material,
    bone: str,
    bevel: float = 0.0,
) -> bpy.types.Object:
    half_depth = depth * 0.5
    vertices = [(x, center_y + half_depth, z) for x, z in points_xz]
    vertices += [(x, center_y - half_depth, z) for x, z in points_xz]
    count = len(points_xz)
    faces = [tuple(range(count)), tuple(range(count, count * 2))[::-1]]
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((index, nxt, count + nxt, count + index))
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate(verbose=False)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    assign_material(obj, material)
    apply_bevel(obj, bevel, 1)
    return bind_to_bone(obj, armature, bone)


def create_armature(name: str, collection: bpy.types.Collection) -> bpy.types.Object:
    armature_data = bpy.data.armatures.new(f"{name}Rig")
    armature = bpy.data.objects.new(f"{name}Armature", armature_data)
    collection.objects.link(armature)
    armature.show_in_front = True
    armature_data.display_type = "OCTAHEDRAL"
    armature["battle_visual_id"] = name.lower()

    world_positions: dict[str, Vector] = {}
    parents: dict[str, str] = {}
    local_positions: dict[str, Vector] = {}
    for bone_name, parent_name, local_position in BONE_DEFINITIONS:
        parents[bone_name] = parent_name
        local_positions[bone_name] = godot_to_blender(local_position)
        world_positions[bone_name] = local_positions[bone_name] + (
            world_positions[parent_name] if parent_name else Vector((0.0, 0.0, 0.0))
        )

    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    edit_bones: dict[str, bpy.types.EditBone] = {}
    for bone_name, parent_name, _ in BONE_DEFINITIONS:
        bone = armature_data.edit_bones.new(bone_name)
        bone.head = world_positions[bone_name]
        bone.tail = world_positions[bone_name] + Vector((0.0, 0.0, 0.12))
        bone.use_connect = False
        if parent_name:
            bone.parent = edit_bones[parent_name]
        edit_bones[bone_name] = bone
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.select_set(False)
    return armature


def balanced_materials() -> dict[str, bpy.types.Material]:
    return {
        "skin": make_material("Balanced_Skin", (0.73, 0.48, 0.34, 1.0), roughness=0.82),
        "skin_light": make_material("Balanced_SkinLight", (0.93, 0.70, 0.50, 1.0), roughness=0.82),
        "hair": make_material("Balanced_Hair", (0.025, 0.035, 0.055, 1.0), roughness=0.92),
        "cloth": make_material("Balanced_CreamCloth", (0.74, 0.70, 0.58, 1.0), roughness=0.95),
        "blue": make_material("Balanced_BlueArmor", (0.035, 0.24, 0.52, 1.0), metallic=0.32, roughness=0.48),
        "blue_light": make_material("Balanced_BlueEdge", (0.08, 0.48, 0.82, 1.0), metallic=0.42, roughness=0.40),
        "dark": make_material("Balanced_DarkLeather", (0.025, 0.045, 0.075, 1.0), metallic=0.08, roughness=0.78),
        "leather": make_material("Balanced_BrownLeather", (0.22, 0.10, 0.045, 1.0), roughness=0.88),
        "metal": make_material("Balanced_Steel", (0.34, 0.43, 0.50, 1.0), metallic=0.88, roughness=0.26),
        "metal_light": make_material("Balanced_BladeEdge", (0.72, 0.84, 0.90, 1.0), metallic=0.92, roughness=0.18),
        "accent": make_material(
            "Balanced_CyanRune",
            (0.05, 0.72, 0.88, 1.0),
            metallic=0.25,
            roughness=0.30,
            emission=(0.05, 0.72, 0.88, 1.0),
            emission_strength=2.2,
        ),
        "eye": make_material("Balanced_Eye", (0.015, 0.022, 0.03, 1.0), roughness=0.45),
    }


def scout_materials() -> dict[str, bpy.types.Material]:
    return {
        "skin": make_material("Scout_Skin", (0.54, 0.31, 0.20, 1.0), roughness=0.84),
        "skin_light": make_material("Scout_SkinLight", (0.73, 0.46, 0.30, 1.0), roughness=0.84),
        "hood": make_material("Scout_Hood", (0.20, 0.035, 0.025, 1.0), roughness=0.96),
        "red": make_material("Scout_RedCloth", (0.43, 0.055, 0.035, 1.0), roughness=0.88),
        "olive": make_material("Scout_OliveCloth", (0.19, 0.22, 0.11, 1.0), roughness=0.96),
        "dark": make_material("Scout_DarkLeather", (0.035, 0.028, 0.023, 1.0), roughness=0.86),
        "leather": make_material("Scout_TanLeather", (0.29, 0.13, 0.055, 1.0), roughness=0.88),
        "metal": make_material("Scout_DarkSteel", (0.22, 0.25, 0.25, 1.0), metallic=0.82, roughness=0.34),
        "metal_light": make_material("Scout_RapierEdge", (0.68, 0.71, 0.68, 1.0), metallic=0.94, roughness=0.20),
        "accent": make_material(
            "Scout_AmberLens",
            (0.95, 0.30, 0.035, 1.0),
            metallic=0.18,
            roughness=0.28,
            emission=(0.95, 0.16, 0.015, 1.0),
            emission_strength=1.8,
        ),
        "wrap": make_material("Scout_Bandage", (0.58, 0.48, 0.34, 1.0), roughness=0.97),
    }


def build_balanced(collection: bpy.types.Collection) -> bpy.types.Object:
    materials = balanced_materials()
    armature = create_armature("Balanced", collection)

    # Core silhouette: broad blue chest, cream sleeves, fitted trousers and heavy boots.
    add_cone(collection, armature, "Balanced_TorsoCloth", (0.0, 0.0, 1.47), 0.29, 0.37, 0.62, materials["cloth"], "spine", 0.72, 10)
    add_cone(collection, armature, "Balanced_WaistArmor", (0.0, 0.0, 1.08), 0.27, 0.31, 0.28, materials["blue"], "hips", 0.72, 10)
    add_cube(collection, armature, "Balanced_ChestPlate", (0.0, 0.235, 1.55), (0.62, 0.16, 0.38), materials["blue"], "spine", bevel=0.065)
    add_prism(collection, armature, "Balanced_ChestV", [(-0.18, 1.68), (0.0, 1.48), (0.18, 1.68), (0.0, 1.61)], 0.33, 0.045, materials["blue_light"], "spine", 0.01)
    add_prism(collection, armature, "Balanced_ChestRune", [(0.0, 1.64), (-0.075, 1.55), (0.0, 1.46), (0.075, 1.55)], 0.366, 0.035, materials["accent"], "spine", 0.008)
    add_cube(collection, armature, "Balanced_Belt", (0.0, 0.0, 1.02), (0.60, 0.36, 0.105), materials["leather"], "hips", bevel=0.025)
    add_cube(collection, armature, "Balanced_BeltBuckle", (0.0, 0.205, 1.02), (0.13, 0.055, 0.13), materials["metal"], "hips", bevel=0.02)
    add_cube(collection, armature, "Balanced_LeftPouch", (-0.30, 0.02, 0.95), (0.17, 0.19, 0.22), materials["leather"], "hips", rotation=(0.0, 0.12, -0.08), bevel=0.035)
    add_cube(collection, armature, "Balanced_RightPouch", (0.31, 0.01, 0.97), (0.15, 0.18, 0.18), materials["leather"], "hips", rotation=(0.0, -0.10, 0.08), bevel=0.03)

    add_cylinder(collection, armature, "Balanced_Neck", (0.0, 0.0, 1.99), 0.115, 0.20, materials["skin"], "neck", 0.88, 8)
    add_ellipsoid(collection, armature, "Balanced_Head", (0.0, 0.018, 2.24), (0.46, 0.40, 0.57), materials["skin_light"], "head", 2, True)
    add_prism(collection, armature, "Balanced_Nose", [(-0.045, 2.29), (0.0, 2.19), (0.055, 2.29)], 0.235, 0.13, materials["skin"], "head", 0.008)
    add_ellipsoid(collection, armature, "Balanced_LeftEye", (-0.105, 0.218, 2.31), (0.074, 0.035, 0.050), materials["eye"], "head", 1, True)
    add_ellipsoid(collection, armature, "Balanced_RightEye", (0.105, 0.218, 2.31), (0.074, 0.035, 0.050), materials["eye"], "head", 1, True)
    add_cube(collection, armature, "Balanced_LeftBrow", (-0.11, 0.225, 2.365), (0.13, 0.025, 0.025), materials["hair"], "head", rotation=(0.08, 0.0, -0.10), bevel=0.008)
    add_cube(collection, armature, "Balanced_RightBrow", (0.11, 0.225, 2.365), (0.13, 0.025, 0.025), materials["hair"], "head", rotation=(-0.08, 0.0, 0.10), bevel=0.008)

    add_ellipsoid(collection, armature, "Balanced_HairCap", (0.0, -0.005, 2.43), (0.51, 0.43, 0.34), materials["hair"], "head", 2, False)
    hair_specs = [
        (-0.20, 0.14, 2.43, 0.12, 0.31, -0.34),
        (-0.08, 0.18, 2.47, 0.13, 0.36, -0.14),
        (0.06, 0.18, 2.46, 0.14, 0.38, 0.08),
        (0.19, 0.13, 2.42, 0.12, 0.30, 0.28),
        (-0.24, -0.02, 2.34, 0.10, 0.27, -0.16),
        (0.24, -0.02, 2.34, 0.10, 0.27, 0.16),
    ]
    for index, (x, y, z, radius, depth, tilt) in enumerate(hair_specs):
        add_cone(collection, armature, f"Balanced_HairLock{index}", (x, y, z), radius, 0.025, depth, materials["hair"], "head", 0.72, 5, (0.0, tilt, 0.0))

    for side, sign in (("Left", -1.0), ("Right", 1.0)):
        upper_bone = f"{side.lower()}_upper_arm"
        forearm_bone = f"{side.lower()}_forearm"
        hand_bone = f"{side.lower()}_hand"
        add_cone(collection, armature, f"Balanced_{side}Sleeve", (0.50 * sign, 0.0, 1.59), 0.12, 0.16, 0.40, materials["cloth"], upper_bone, 0.82, 8)
        add_ellipsoid(collection, armature, f"Balanced_{side}Pauldron", (0.50 * sign, 0.0, 1.80), (0.32, 0.31, 0.24), materials["blue"], upper_bone, 1, False)
        add_prism(collection, armature, f"Balanced_{side}PauldronEdge", [(-0.12 + 0.50 * sign, 1.86), (0.12 + 0.50 * sign, 1.86), (0.10 + 0.50 * sign, 1.78), (-0.10 + 0.50 * sign, 1.78)], 0.17, 0.055, materials["blue_light"], upper_bone, 0.008)
        add_cone(collection, armature, f"Balanced_{side}Bracer", (0.50 * sign, 0.0, 1.18), 0.105, 0.13, 0.35, materials["blue"], forearm_bone, 0.80, 8)
        add_cube(collection, armature, f"Balanced_{side}BracerStripe", (0.50 * sign, 0.095, 1.25), (0.17, 0.055, 0.08), materials["accent"], forearm_bone, bevel=0.012)
        add_ellipsoid(collection, armature, f"Balanced_{side}Hand", (0.50 * sign, 0.0, 0.91), (0.19, 0.17, 0.20), materials["skin"], hand_bone, 1, True)

    for side, sign in (("Left", -1.0), ("Right", 1.0)):
        upper_bone = f"{side.lower()}_upper_leg"
        lower_bone = f"{side.lower()}_lower_leg"
        foot_bone = f"{side.lower()}_foot"
        add_cone(collection, armature, f"Balanced_{side}Thigh", (0.23 * sign, 0.0, 0.69), 0.13, 0.155, 0.42, materials["dark"], upper_bone, 0.82, 8)
        add_ellipsoid(collection, armature, f"Balanced_{side}Knee", (0.23 * sign, 0.105, 0.48), (0.25, 0.17, 0.20), materials["blue"], lower_bone, 1, False)
        add_cone(collection, armature, f"Balanced_{side}Shin", (0.23 * sign, 0.0, 0.28), 0.105, 0.13, 0.37, materials["leather"], lower_bone, 0.86, 8)
        add_cube(collection, armature, f"Balanced_{side}Boot", (0.23 * sign, 0.075, 0.10), (0.29, 0.43, 0.21), materials["dark"], foot_bone, bevel=0.045)
        add_cube(collection, armature, f"Balanced_{side}BootCuff", (0.23 * sign, 0.0, 0.22), (0.27, 0.29, 0.12), materials["blue"], lower_bone, bevel=0.025)

    # Back mantle and two cloth tails provide a readable silhouette from the isometric camera.
    add_cube(collection, armature, "Balanced_BackMantle", (0.0, -0.205, 1.59), (0.58, 0.10, 0.30), materials["blue"], "spine", bevel=0.055)
    add_prism(collection, armature, "Balanced_LeftCoatTail", [(-0.27, 1.34), (-0.04, 1.30), (-0.08, 0.82), (-0.31, 0.93)], -0.19, 0.055, materials["blue"], "hips", 0.01)
    add_prism(collection, armature, "Balanced_RightCoatTail", [(0.04, 1.30), (0.27, 1.34), (0.31, 0.93), (0.08, 0.82)], -0.19, 0.055, materials["blue_light"], "hips", 0.01)

    # Sword is rigidly weighted to the right hand and follows the runtime attack pose.
    add_cylinder(collection, armature, "Balanced_SwordGrip", (0.50, 0.0, 0.82), 0.042, 0.25, materials["leather"], "right_hand", 1.0, 8)
    add_cylinder(collection, armature, "Balanced_SwordPommel", (0.50, 0.0, 0.94), 0.072, 0.10, materials["accent"], "right_hand", 1.0, 6)
    add_cube(collection, armature, "Balanced_SwordGuard", (0.50, 0.0, 0.69), (0.42, 0.09, 0.075), materials["metal"], "right_hand", bevel=0.028)
    add_prism(collection, armature, "Balanced_SwordBlade", [(0.43, 0.69), (0.57, 0.69), (0.60, 0.18), (0.50, -0.02), (0.40, 0.18)], 0.0, 0.065, materials["metal_light"], "right_hand", 0.012)
    add_prism(collection, armature, "Balanced_SwordFuller", [(0.485, 0.65), (0.515, 0.65), (0.52, 0.18), (0.50, 0.11), (0.48, 0.18)], 0.038, 0.018, materials["accent"], "right_hand", 0.004)

    shield_points = [(-0.50, 1.26), (-0.79, 1.10), (-0.76, 0.68), (-0.50, 0.43), (-0.24, 0.68), (-0.21, 1.10)]
    add_prism(collection, armature, "Balanced_ShieldCore", shield_points, 0.16, 0.12, materials["blue"], "left_hand", 0.035)
    inner_points = [(-0.50, 1.16), (-0.70, 1.04), (-0.68, 0.73), (-0.50, 0.55), (-0.32, 0.73), (-0.30, 1.04)]
    add_prism(collection, armature, "Balanced_ShieldInset", inner_points, 0.235, 0.045, materials["dark"], "left_hand", 0.018)
    add_prism(collection, armature, "Balanced_ShieldRune", [(-0.50, 1.08), (-0.59, 0.87), (-0.50, 0.66), (-0.41, 0.87)], 0.268, 0.026, materials["accent"], "left_hand", 0.009)
    add_cube(collection, armature, "Balanced_ShieldSpine", (-0.50, 0.282, 0.87), (0.075, 0.035, 0.55), materials["metal"], "left_hand", bevel=0.015)

    return armature


def build_scout(collection: bpy.types.Collection) -> bpy.types.Object:
    materials = scout_materials()
    armature = create_armature("Scout", collection)

    add_cone(collection, armature, "Scout_Torso", (0.0, 0.0, 1.47), 0.25, 0.31, 0.61, materials["olive"], "spine", 0.68, 9)
    add_cone(collection, armature, "Scout_Hips", (0.0, 0.0, 1.07), 0.24, 0.27, 0.27, materials["dark"], "hips", 0.68, 9)
    add_prism(collection, armature, "Scout_LeatherVest", [(-0.25, 1.72), (0.25, 1.72), (0.20, 1.27), (0.0, 1.17), (-0.20, 1.27)], 0.225, 0.12, materials["leather"], "spine", 0.03)
    add_cube(collection, armature, "Scout_CrossStrap", (0.0, 0.30, 1.52), (0.13, 0.055, 0.57), materials["dark"], "spine", rotation=(0.0, -0.55, 0.0), bevel=0.018)
    add_cube(collection, armature, "Scout_Belt", (0.0, 0.0, 1.02), (0.53, 0.31, 0.09), materials["leather"], "hips", bevel=0.022)
    add_cube(collection, armature, "Scout_Buckle", (0.0, 0.185, 1.02), (0.11, 0.045, 0.11), materials["metal"], "hips", bevel=0.015)
    add_cube(collection, armature, "Scout_MapCase", (0.28, -0.01, 0.96), (0.16, 0.18, 0.25), materials["leather"], "hips", rotation=(0.0, -0.10, 0.08), bevel=0.03)
    add_cube(collection, armature, "Scout_LeftPouch", (-0.27, 0.0, 0.98), (0.14, 0.17, 0.17), materials["dark"], "hips", bevel=0.025)

    add_cylinder(collection, armature, "Scout_Neck", (0.0, 0.0, 1.98), 0.105, 0.18, materials["skin"], "neck", 0.84, 7)
    add_ellipsoid(collection, armature, "Scout_Head", (0.0, 0.015, 2.23), (0.43, 0.38, 0.54), materials["skin_light"], "head", 2, True)
    add_ellipsoid(collection, armature, "Scout_Hood", (0.0, -0.025, 2.32), (0.55, 0.48, 0.64), materials["hood"], "head", 2, False)
    add_prism(collection, armature, "Scout_FaceOpening", [(-0.18, 2.39), (0.18, 2.39), (0.16, 2.18), (0.0, 2.11), (-0.16, 2.18)], 0.245, 0.055, materials["skin_light"], "head", 0.012)
    add_cube(collection, armature, "Scout_FaceMask", (0.0, 0.284, 2.18), (0.36, 0.06, 0.17), materials["red"], "head", bevel=0.028)
    add_cube(collection, armature, "Scout_EyeBand", (0.0, 0.292, 2.33), (0.37, 0.052, 0.095), materials["dark"], "head", bevel=0.018)
    add_ellipsoid(collection, armature, "Scout_LeftLens", (-0.105, 0.327, 2.34), (0.095, 0.035, 0.068), materials["accent"], "head", 1, True)
    add_ellipsoid(collection, armature, "Scout_RightLens", (0.105, 0.327, 2.34), (0.095, 0.035, 0.068), materials["accent"], "head", 1, True)
    add_cone(collection, armature, "Scout_HoodTip", (-0.13, -0.07, 2.53), 0.15, 0.015, 0.36, materials["hood"], "head", 0.78, 6, (0.10, -0.34, -0.20))
    add_cylinder(collection, armature, "Scout_ScarfCollar", (0.0, 0.0, 1.98), 0.21, 0.18, materials["red"], "neck", 0.78, 9)
    add_prism(collection, armature, "Scout_ScarfTailLong", [(-0.16, 1.93), (0.02, 1.93), (-0.02, 1.20), (-0.21, 1.38)], -0.21, 0.055, materials["red"], "chest", 0.012)
    add_prism(collection, armature, "Scout_ScarfTailShort", [(0.03, 1.93), (0.18, 1.91), (0.25, 1.48), (0.08, 1.38)], -0.205, 0.055, materials["hood"], "chest", 0.012)

    for side, sign in (("Left", -1.0), ("Right", 1.0)):
        upper_bone = f"{side.lower()}_upper_arm"
        forearm_bone = f"{side.lower()}_forearm"
        hand_bone = f"{side.lower()}_hand"
        add_cone(collection, armature, f"Scout_{side}Sleeve", (0.50 * sign, 0.0, 1.59), 0.105, 0.135, 0.40, materials["olive"], upper_bone, 0.72, 7)
        if side == "Right":
            add_ellipsoid(collection, armature, "Scout_RightPauldron", (0.50, 0.0, 1.80), (0.29, 0.27, 0.21), materials["metal"], upper_bone, 1, False)
            add_prism(collection, armature, "Scout_RightPauldronMark", [(0.41, 1.85), (0.59, 1.85), (0.56, 1.77), (0.44, 1.77)], 0.15, 0.05, materials["red"], upper_bone, 0.006)
        else:
            add_cube(collection, armature, "Scout_LeftShoulderWrap", (-0.50, 0.0, 1.79), (0.25, 0.25, 0.13), materials["wrap"], upper_bone, bevel=0.035)
        add_cone(collection, armature, f"Scout_{side}Forearm", (0.50 * sign, 0.0, 1.18), 0.09, 0.115, 0.35, materials["wrap"], forearm_bone, 0.72, 7)
        for stripe in range(3):
            add_cube(collection, armature, f"Scout_{side}Wrap{stripe}", (0.50 * sign, 0.075, 1.09 + stripe * 0.10), (0.15, 0.045, 0.035), materials["leather"], forearm_bone, bevel=0.006)
        add_ellipsoid(collection, armature, f"Scout_{side}Glove", (0.50 * sign, 0.0, 0.91), (0.17, 0.15, 0.19), materials["dark"], hand_bone, 1, True)

    for side, sign in (("Left", -1.0), ("Right", 1.0)):
        upper_bone = f"{side.lower()}_upper_leg"
        lower_bone = f"{side.lower()}_lower_leg"
        foot_bone = f"{side.lower()}_foot"
        add_cone(collection, armature, f"Scout_{side}Thigh", (0.23 * sign, 0.0, 0.69), 0.115, 0.14, 0.42, materials["olive"], upper_bone, 0.72, 7)
        add_ellipsoid(collection, armature, f"Scout_{side}Knee", (0.23 * sign, 0.095, 0.48), (0.21, 0.15, 0.17), materials["leather"], lower_bone, 1, False)
        add_cone(collection, armature, f"Scout_{side}Shin", (0.23 * sign, 0.0, 0.28), 0.09, 0.115, 0.37, materials["dark"], lower_bone, 0.74, 7)
        add_cube(collection, armature, f"Scout_{side}Boot", (0.23 * sign, 0.09, 0.10), (0.25, 0.42, 0.20), materials["dark"], foot_bone, bevel=0.035)
        add_cube(collection, armature, f"Scout_{side}BootStrap", (0.23 * sign, 0.105, 0.24), (0.22, 0.055, 0.065), materials["red"], lower_bone, bevel=0.008)

    # Asymmetric short cloak and quiver distinguish the enemy at timeline camera distance.
    add_prism(collection, armature, "Scout_Cloak", [(-0.30, 1.72), (0.28, 1.70), (0.23, 0.96), (-0.06, 0.79), (-0.31, 1.03)], -0.20, 0.06, materials["hood"], "spine", 0.012)
    add_cylinder(collection, armature, "Scout_Quiver", (-0.25, -0.26, 1.45), 0.105, 0.52, materials["leather"], "chest", 0.82, 8, (0.0, -0.32, -0.18))
    for index in range(3):
        x = -0.31 + index * 0.055
        add_cylinder(collection, armature, f"Scout_Arrow{index}", (x, -0.25, 1.72 + index * 0.025), 0.018, 0.58, materials["metal_light"], "chest", 1.0, 6, (0.0, -0.30, -0.18))
        add_cone(collection, armature, f"Scout_ArrowHead{index}", (x - 0.03, -0.24, 2.00 + index * 0.025), 0.045, 0.0, 0.13, materials["metal"], "chest", 0.72, 5, (0.0, -0.30, -0.18))

    # Rapier with a faceted basket guard.
    add_cylinder(collection, armature, "Scout_RapierGrip", (0.50, 0.0, 0.83), 0.036, 0.24, materials["leather"], "right_hand", 1.0, 7)
    add_cylinder(collection, armature, "Scout_RapierPommel", (0.50, 0.0, 0.95), 0.055, 0.08, materials["accent"], "right_hand", 1.0, 6)
    add_cylinder(collection, armature, "Scout_RapierGuard", (0.50, 0.0, 0.70), 0.16, 0.055, materials["metal"], "right_hand", 0.30, 10)
    add_prism(collection, armature, "Scout_RapierBlade", [(0.472, 0.70), (0.528, 0.70), (0.515, -0.08), (0.50, -0.17), (0.485, -0.08)], 0.0, 0.036, materials["metal_light"], "right_hand", 0.005)
    for side in (-1.0, 1.0):
        add_prism(collection, armature, f"Scout_Basket{int(side)}", [(0.50, 0.84), (0.50 + 0.15 * side, 0.76), (0.50 + 0.12 * side, 0.66), (0.50, 0.70)], 0.0, 0.028, materials["metal"], "right_hand", 0.004)

    buckler_points = [(-0.50, 1.15), (-0.72, 1.03), (-0.72, 0.77), (-0.50, 0.65), (-0.28, 0.77), (-0.28, 1.03)]
    add_prism(collection, armature, "Scout_Buckler", buckler_points, 0.13, 0.10, materials["metal"], "left_hand", 0.025)
    add_prism(collection, armature, "Scout_BucklerLeather", [(-0.50, 1.08), (-0.64, 0.99), (-0.64, 0.81), (-0.50, 0.72), (-0.36, 0.81), (-0.36, 0.99)], 0.195, 0.045, materials["leather"], "left_hand", 0.012)
    add_ellipsoid(collection, armature, "Scout_BucklerBoss", (-0.50, 0.238, 0.90), (0.16, 0.075, 0.16), materials["accent"], "left_hand", 1, False)

    return armature


def merge_character_meshes(
    collection: bpy.types.Collection,
    armature: bpy.types.Object,
    character_name: str,
) -> bpy.types.Object:
    mesh_objects = [obj for obj in collection.all_objects if obj.type == "MESH"]
    if not mesh_objects:
        raise RuntimeError(f"{character_name} has no meshes to merge")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in mesh_objects:
        obj.select_set(True)
    joined = mesh_objects[0]
    bpy.context.view_layer.objects.active = joined
    bpy.ops.object.join()
    joined.name = f"{character_name}CharacterMesh"

    # Joining preserves vertex groups. Collapse duplicate material slots so the
    # GLB has one skin node and only one surface per authored material.
    old_materials = list(joined.data.materials)
    polygon_materials = [old_materials[polygon.material_index] for polygon in joined.data.polygons]
    unique_materials: list[bpy.types.Material] = []
    material_indices: dict[bpy.types.Material, int] = {}
    for material in polygon_materials:
        if material not in material_indices:
            material_indices[material] = len(unique_materials)
            unique_materials.append(material)
    joined.data.materials.clear()
    for material in unique_materials:
        joined.data.materials.append(material)
    for polygon, material in zip(joined.data.polygons, polygon_materials):
        polygon.material_index = material_indices[material]

    joined.parent = armature
    joined.matrix_parent_inverse = armature.matrix_world.inverted()
    armature_modifiers = [modifier for modifier in joined.modifiers if modifier.type == "ARMATURE"]
    for modifier in armature_modifiers[1:]:
        joined.modifiers.remove(modifier)
    if armature_modifiers:
        armature_modifiers[0].object = armature
    else:
        modifier = joined.modifiers.new("BattleRig", "ARMATURE")
        modifier.object = armature
    joined["authored_piece_count"] = len(mesh_objects)
    joined["authored_material_count"] = len(unique_materials)
    bpy.ops.object.select_all(action="DESELECT")
    return joined


def select_collection(collection: bpy.types.Collection) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in collection.all_objects:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    armatures = [obj for obj in collection.all_objects if obj.type == "ARMATURE"]
    if armatures:
        bpy.context.view_layer.objects.active = armatures[0]


def export_character(collection: bpy.types.Collection, destination: Path) -> None:
    select_collection(collection)
    bpy.ops.export_scene.gltf(
        filepath=str(destination),
        export_format="GLB",
        use_selection=True,
        export_animations=False,
        export_skins=True,
        export_def_bones=True,
        export_rest_position_armature=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_yup=True,
        export_apply=False,
        export_extras=True,
        export_normals=True,
        export_tangents=False,
        export_texcoords=False,
        export_attributes=False,
        export_armature_object_remove=False,
        check_existing=False,
    )
    bpy.ops.object.select_all(action="DESELECT")


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    direction = target - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def add_preview_scene(
    balanced_armature: bpy.types.Object,
    scout_armature: bpy.types.Object,
) -> bpy.types.Collection:
    preview = make_collection("PREVIEW_ONLY")
    balanced_armature.location.x = -1.18
    scout_armature.location.x = 1.18
    scout_armature.rotation_euler.z = -0.12
    balanced_armature.rotation_euler.z = 0.10

    floor_material = make_material("Preview_Grass", (0.08, 0.16, 0.075, 1.0), roughness=0.98)
    tile_material = make_material("Preview_Tile", (0.19, 0.16, 0.12, 1.0), roughness=0.93)
    line_material = make_material("Preview_TileLine", (0.50, 0.43, 0.27, 1.0), roughness=0.88)
    bpy.ops.mesh.primitive_plane_add(size=14.0, location=(0.0, 0.0, -0.025))
    floor = bpy.context.object
    floor.name = "PreviewGround"
    assign_material(floor, floor_material)
    move_to_collection(floor, preview)
    for x in (-1.2, 0.0, 1.2):
        for y in (-0.6, 0.6):
            bpy.ops.mesh.primitive_cube_add(location=(x, y, 0.005))
            tile = bpy.context.object
            tile.name = f"PreviewTile_{x}_{y}"
            tile.dimensions = (1.08, 1.08, 0.06)
            apply_object_transform(tile)
            apply_bevel(tile, 0.025, 1)
            assign_material(tile, tile_material)
            move_to_collection(tile, preview)
    for x in (-1.8, -0.6, 0.6, 1.8):
        bpy.ops.mesh.primitive_cube_add(location=(x, 0.0, 0.045))
        line = bpy.context.object
        line.name = f"PreviewGridX_{x}"
        line.dimensions = (0.035, 2.36, 0.025)
        apply_object_transform(line)
        assign_material(line, line_material)
        move_to_collection(line, preview)

    world = bpy.context.scene.world or bpy.data.worlds.new("BattlePreviewWorld")
    bpy.context.scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.025, 0.045, 0.07, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.28

    key_data = bpy.data.lights.new("PreviewKey", "AREA")
    key_data.energy = 1150.0
    key_data.shape = "DISK"
    key_data.size = 5.0
    key_data.color = (0.70, 0.84, 1.0)
    key = bpy.data.objects.new("PreviewKey", key_data)
    key.location = (-3.8, 4.5, 6.2)
    look_at(key, Vector((0.0, 0.0, 1.2)))
    preview.objects.link(key)

    rim_data = bpy.data.lights.new("PreviewRim", "AREA")
    rim_data.energy = 900.0
    rim_data.size = 4.0
    rim_data.color = (1.0, 0.30, 0.12)
    rim = bpy.data.objects.new("PreviewRim", rim_data)
    rim.location = (3.5, -3.5, 4.5)
    look_at(rim, Vector((0.0, 0.0, 1.3)))
    preview.objects.link(rim)

    fill_data = bpy.data.lights.new("PreviewFill", "AREA")
    fill_data.energy = 560.0
    fill_data.size = 3.0
    fill_data.color = (0.35, 1.0, 0.70)
    fill = bpy.data.objects.new("PreviewFill", fill_data)
    fill.location = (0.0, -1.5, 5.5)
    look_at(fill, Vector((0.0, 0.0, 1.0)))
    preview.objects.link(fill)

    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    camera.location = (4.8, 7.4, 3.7)
    camera_data.lens = 64.0
    look_at(camera, Vector((0.0, 0.0, 1.18)))
    preview.objects.link(camera)
    bpy.context.scene.camera = camera
    return preview


def render_preview() -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(PREVIEW_PATH)
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.render.render(write_still=True)


def main() -> None:
    clear_file()
    bpy.context.scene.name = "BattleVerticalSlice"
    balanced_collection = make_collection("BALANCED_MODEL")
    scout_collection = make_collection("SCOUT_MODEL")
    balanced_armature = build_balanced(balanced_collection)
    scout_armature = build_scout(scout_collection)
    balanced_mesh = merge_character_meshes(balanced_collection, balanced_armature, "Balanced")
    scout_mesh = merge_character_meshes(scout_collection, scout_armature, "Scout")

    export_character(balanced_collection, MODEL_DIR / "balanced.glb")
    export_character(scout_collection, MODEL_DIR / "scout.glb")

    add_preview_scene(balanced_armature, scout_armature)
    render_preview()
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_PATH), check_existing=False)

    print(
        "BATTLE_VERTICAL_SLICE_OK",
        {
            "balanced_objects": len(balanced_collection.all_objects),
            "scout_objects": len(scout_collection.all_objects),
            "balanced_vertices": len(balanced_mesh.data.vertices),
            "scout_vertices": len(scout_mesh.data.vertices),
            "balanced_materials": len(balanced_mesh.data.materials),
            "scout_materials": len(scout_mesh.data.materials),
            "balanced_glb": str(MODEL_DIR / "balanced.glb"),
            "scout_glb": str(MODEL_DIR / "scout.glb"),
            "source": str(SOURCE_PATH),
            "preview": str(PREVIEW_PATH),
        },
    )


if __name__ == "__main__":
    main()
