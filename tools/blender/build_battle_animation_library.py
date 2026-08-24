"""Build the shared 18-bone battle animation library without Blender MCP.

The JSON catalog is the source of truth for both Blender keyframes and Godot's
runtime AnimationTree. Running this script uses an isolated background Blender
process, so it does not change the scene controlled by Blender MCP.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_battle_vertical_slice import (
    BONE_DEFINITIONS,
    add_cube,
    clear_file,
    create_armature,
    make_collection,
    make_material,
    select_collection,
)


PROJECT_ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = PROJECT_ROOT / "data" / "battle_animations.json"
MODEL_PATH = PROJECT_ROOT / "assets" / "models" / "battle" / "battle_animation_library.glb"
SOURCE_PATH = PROJECT_ROOT / "art_src" / "blender" / "battle_animation_library.blend"
MANIFEST_PATH = PROJECT_ROOT / "assets" / "models" / "battle" / "battle_animation_library.manifest.json"

COORDINATE_BASIS = Matrix(
    (
        (1.0, 0.0, 0.0),
        (0.0, 0.0, -1.0),
        (0.0, 1.0, 0.0),
    )
)


def load_catalog() -> dict:
    with CATALOG_PATH.open("r", encoding="utf-8") as handle:
        catalog = json.load(handle)
    if not isinstance(catalog.get("clips"), dict) or not catalog["clips"]:
        raise RuntimeError("battle_animations.json has no clips")
    return catalog


def godot_vector(value: list[float] | tuple[float, float, float] | None) -> Vector:
    if not value or len(value) < 3:
        return Vector((0.0, 0.0, 0.0))
    return Vector((float(value[0]), -float(value[2]), float(value[1])))


def godot_rotation(value: list[float] | tuple[float, float, float] | None) -> Quaternion:
    if not value or len(value) < 3:
        return Quaternion()
    from mathutils import Euler

    godot_matrix = Euler(
        (float(value[0]), float(value[1]), float(value[2])),
        "XYZ",
    ).to_matrix()
    return (COORDINATE_BASIS @ godot_matrix @ COORDINATE_BASIS.inverted()).to_quaternion()


def animated_bones(clip_data: dict) -> set[str]:
    result: set[str] = set()
    for keyframe in clip_data.get("keyframes", []):
        result.update(str(name) for name in keyframe.get("rotations", {}).keys())
        result.update(str(name) for name in keyframe.get("positions", {}).keys())
    return result


def set_pose_key(
    armature: bpy.types.Object,
    clip_data: dict,
    keyframe: dict,
    frame: float,
    bone_names: set[str],
) -> None:
    rotations = keyframe.get("rotations", {})
    positions = keyframe.get("positions", {})
    for bone_name in bone_names:
        pose_bone = armature.pose.bones.get(bone_name)
        if pose_bone is None:
            raise RuntimeError(f"Animation references missing bone: {bone_name}")
        pose_bone.rotation_mode = "QUATERNION"
        pose_bone.rotation_quaternion = godot_rotation(rotations.get(bone_name))
        pose_bone.location = godot_vector(positions.get(bone_name))
        pose_bone.keyframe_insert("rotation_quaternion", frame=frame, group=bone_name)
        pose_bone.keyframe_insert("location", frame=frame, group=bone_name)

    armature.rotation_mode = "QUATERNION"
    armature.location = godot_vector(keyframe.get("motion_position"))
    armature.rotation_quaternion = godot_rotation(keyframe.get("motion_rotation"))
    armature.keyframe_insert("location", frame=frame, group="visual_motion_root")
    armature.keyframe_insert("rotation_quaternion", frame=frame, group="visual_motion_root")


def build_action(
    armature: bpy.types.Object,
    clip_id: str,
    clip_data: dict,
    fps: int,
    source_sha256: str,
) -> bpy.types.Action:
    action = bpy.data.actions.new(clip_id)
    action.use_fake_user = True
    action["battle_clip_id"] = clip_id
    action["duration"] = float(clip_data.get("duration", 0.62))
    action["loop"] = bool(clip_data.get("loop", False))
    action["events"] = json.dumps(clip_data.get("events", []), separators=(",", ":"))
    action["source_sha256"] = source_sha256
    armature.animation_data_create()
    armature.animation_data.action = action

    bone_names = animated_bones(clip_data)
    for keyframe in clip_data.get("keyframes", []):
        time_seconds = float(keyframe.get("time", 0.0))
        set_pose_key(armature, clip_data, keyframe, time_seconds * fps + 1.0, bone_names)

    if hasattr(action, "pose_markers"):
        for event_data in clip_data.get("events", []):
            marker = action.pose_markers.new(str(event_data.get("id", "event")))
            marker.frame = int(round(float(event_data.get("time", 0.0)) * fps + 1.0))
    armature.animation_data.action = None
    return action


def export_library(collection: bpy.types.Collection) -> None:
    select_collection(collection)
    bpy.ops.export_scene.gltf(
        filepath=str(MODEL_PATH),
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_frame_range=False,
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


def main() -> None:
    catalog = load_catalog()
    source_sha256 = hashlib.sha256(CATALOG_PATH.read_bytes()).hexdigest()
    fps = max(1, int(catalog.get("fps", 30)))
    clear_file()
    bpy.context.scene.name = "BattleAnimationLibrary"
    bpy.context.scene.render.fps = fps
    collection = make_collection("BATTLE_ANIMATION_LIBRARY")
    armature = create_armature("BattleAnimation", collection)
    armature["battle_animation_source"] = "data/battle_animations.json"
    armature["source_sha256"] = source_sha256

    marker_material = make_material(
        "AnimationLibraryMarker",
        (0.04, 0.55, 0.92, 1.0),
        metallic=0.2,
        roughness=0.45,
    )
    marker = add_cube(
        collection,
        armature,
        "AnimationLibraryMarkerMesh",
        (0.0, 0.0, 0.05),
        (0.08, 0.08, 0.08),
        marker_material,
        "root",
        bevel=0.008,
    )
    marker.hide_render = True

    actions: list[bpy.types.Action] = []
    for clip_id in sorted(catalog["clips"]):
        actions.append(build_action(armature, clip_id, catalog["clips"][clip_id], fps, source_sha256))

    export_library(collection)
    SOURCE_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_PATH), check_existing=False)
    manifest = {
        "format_version": int(catalog.get("format_version", 1)),
        "fps": fps,
        "source": "data/battle_animations.json",
        "source_sha256": source_sha256,
        "clips": [action.name for action in actions],
        "glb": "assets/models/battle/battle_animation_library.glb",
        "blend": "art_src/blender/battle_animation_library.blend",
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(
        "BATTLE_ANIMATION_LIBRARY_OK",
        {
            "clips": len(actions),
            "fps": fps,
            "source_sha256": source_sha256,
            "glb": str(MODEL_PATH),
            "blend": str(SOURCE_PATH),
        },
    )


if __name__ == "__main__":
    main()
