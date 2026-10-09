"""Read-only validation of the actual editable Blender icon source."""

import json
from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "art_src/blender/ui/qq_small_icons.manifest.json"


def main():
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / manifest["source"]))
    scene = bpy.context.scene
    if scene.camera.data.type != "ORTHO" or not scene.render.film_transparent:
        raise RuntimeError("Source must render orthographic transparent icons")
    if scene.render.resolution_x != 512 or scene.render.resolution_y != 512:
        raise RuntimeError("Source render resolution changed")
    total_meshes, total_curves = 0, 0
    for entry in manifest["assets"]:
        collection = bpy.data.collections.get(entry["source_collection"])
        if collection is None or collection.get("asset_id") != entry["id"]:
            raise RuntimeError("Missing editable collection: " + entry["id"])
        objects = list(collection.objects)
        if len(objects) != entry["objects"]:
            raise RuntimeError("Source object count changed: " + entry["id"])
        meshes = [obj for obj in objects if obj.type == "MESH"]
        curves = [obj for obj in objects if obj.type == "CURVE"]
        if not meshes or any(obj.type not in ("MESH", "CURVE") for obj in objects):
            raise RuntimeError("Pictogram is not editable 3D geometry: " + entry["id"])
        vertices = sum(len(obj.data.vertices) for obj in meshes)
        if vertices != entry["mesh_vertices"]:
            raise RuntimeError("Source mesh vertices changed: " + entry["id"])
        for obj in meshes:
            if len(obj.data.vertices) < 6 or obj.dimensions.y < .01:
                raise RuntimeError("Flat/invalid geometry: " + obj.name)
        for obj in curves:
            if obj.data.bevel_depth <= 0:
                raise RuntimeError("Curve has no 3D thickness: " + obj.name)
        total_meshes += len(meshes)
        total_curves += len(curves)
    for mat in bpy.data.materials:
        if mat.node_tree is not None and any(node.type == "TEX_IMAGE" for node in mat.node_tree.nodes):
            raise RuntimeError("An imported picture was used as a sticker: " + mat.name)
    print(f"BLENDER_UI_SCENE_VALID_OK {len(manifest['assets'])} collections; {total_meshes} meshes; {total_curves} 3D curves")


if __name__ == "__main__":
    main()
