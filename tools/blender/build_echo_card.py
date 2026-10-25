"""Author Echo assets in a factory-startup background process, never live MCP."""
from pathlib import Path
import hashlib
import json
import sys

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
import build_art_vertical_slice as kit

LOCAL = ROOT / "tools/.local/echo_art"
SOURCE = ROOT / "art_src/blender/cards/echo_cast.blend"


def card(collection, name, center, tilt, accent):
    root = kit.add_empty(collection, name, center, (0, tilt, 0))
    kit.add_box(collection, name + "Frame", (0, 0, 0), (1.3, 0.16, 1.86), kit.MATERIALS["gunmetal"], bevel=0.09, parent=root)
    kit.add_box(collection, name + "Face", (0, -0.105, 0), (1.12, 0.06, 1.66), kit.MATERIALS["ceramic_light"], bevel=0.065, parent=root)
    for side in [-1, 1]:
        kit.add_box(collection, name + "Edge", (side * 0.54, -0.15, 0), (0.055, 0.03, 1.58), accent, bevel=0.02, parent=root)
        kit.add_box(collection, name + "Cap", (0, -0.15, side * 0.78), (1.08, 0.03, 0.055), accent, bevel=0.02, parent=root)
    kit.add_profile(collection, name + "Blade", [(-0.1, -0.45), (0.1, -0.45), (0.1, 0.35), (0, 0.64), (-0.1, 0.35)], 0.05, kit.MATERIALS["steel"], location=(0, -0.17, 0.1), bevel=0.02, parent=root)
    kit.add_box(collection, name + "Guard", (0, -0.2, -0.25), (0.55, 0.07, 0.08), accent, bevel=0.025, parent=root)
    kit.add_box(collection, name + "Grip", (0, -0.19, -0.48), (0.1, 0.06, 0.3), kit.MATERIALS["leather"], bevel=0.025, parent=root)


def main():
    kit.clear_file(); kit.build_materials(); kit.setup_render_scene()
    scene = bpy.context.scene
    scene.render.threads_mode = "FIXED"; scene.render.threads = 4
    if hasattr(scene, "eevee"): scene.eevee.taa_render_samples = 32
    scene.render.film_transparent = False
    illustration = kit.make_collection("Echo_Illustration")
    card(illustration, "Original", (-0.6, -0.2, 1.3), -13, kit.MATERIALS["cyan"])
    card(illustration, "Echo", (0.7, 0.3, 1.9), 17, kit.MATERIALS["brass_edge"])
    import card_action_scenes
    card_action_scenes.backdrop(kit, illustration, "EchoBackdrop", (0.008, 0.025, 0.035), (0.05, 0.12, 0.16))
    for index in range(3):
        kit.add_curve(illustration, "Resonance", [(-0.1, -0.45, 2.1 + index * 0.14), (0.2, -0.5, 2.45 + index * 0.12), (0.6, -0.25, 2.5 + index * 0.08)], 0.025, kit.MATERIALS["cyan"])
    icon = kit.make_collection("Echo_Status_Icon")
    card(icon, "Back", (-0.38, 0.18, 1.2), -12, kit.MATERIALS["brass_edge"])
    card(icon, "Front", (0.32, -0.1, 0.85), 10, kit.MATERIALS["cyan"])
    icon.hide_render = True
    kit.CAMERA.location = (2.6, -8, 3.3); kit.look_at(kit.CAMERA, Vector((0, 0, 1.55)))
    kit.CAMERA.data.type = "ORTHO"; kit.CAMERA.data.ortho_scale = 3.9
    kit.CAMERA.data.dof.use_dof = False
    LOCAL.mkdir(parents=True, exist_ok=True); SOURCE.parent.mkdir(parents=True, exist_ok=True)
    scene.render.resolution_x = 2048; scene.render.resolution_y = 2048
    scene.render.filepath = str(LOCAL / "echo_cast.png")
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
    bpy.ops.render.render(write_still=True)
    illustration.hide_render = True; icon.hide_render = False
    kit.CAMERA.location = (0, -8, 1.15); kit.look_at(kit.CAMERA, Vector((0, 0, 1.15)))
    kit.CAMERA.data.ortho_scale = 3.5
    scene.render.film_transparent = True
    scene.render.resolution_x = 1024; scene.render.resolution_y = 1024
    scene.render.filepath = str(LOCAL / "echo_ready.png")
    bpy.ops.render.render(write_still=True)
    manifest = {"tool": "Blender " + bpy.app.version_string, "generator": "tools/blender/build_echo_card.py", "source_path": SOURCE.relative_to(ROOT).as_posix(),
                "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(), "assets": [
                    {"asset_id": "echo_cast", "category": "card", "runtime_path": "assets/icons/cards/echo_cast.png", "size": 512},
                    {"asset_id": "echo_ready", "category": "status", "runtime_path": "assets/icons/status/echo_ready.png", "size": 96}]}
    (SOURCE.with_suffix(".manifest.json")).write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("ECHO_ART_RENDER_OK", bpy.app.version_string)


if __name__ == "__main__": main()
