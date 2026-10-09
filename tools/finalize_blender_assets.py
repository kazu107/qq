"""Validate completed Blender batches and atomically register runtime artwork.

This is an importer for generated manifests, not a replacement for rendering.
Only hashes matching existing source and output files are accepted.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PROVENANCE = ROOT / "data/art_provenance.json"
UI_IDS = "attack speed shield hp gold step time relic card_owned card_equipped settings version_history card".split()
EFFECT_IDS = "shield_spend delay haste recast interrupt cleanse empower auto_queue timeline_stop timeline_reverse status effect".split()
MAP_IDS = "normal_battle elite_battle boss shop forge heal event hazard lock".split()


def digest(path: Path) -> str:
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else hashlib.sha256(handle.read()).hexdigest()


def project_path(value: str) -> Path:
    path = Path(value.removeprefix("res://"))
    resolved = (path if path.is_absolute() else ROOT / path).resolve()
    resolved.relative_to(ROOT)
    return resolved


def relative(value: str | Path) -> str:
    return project_path(str(value)).relative_to(ROOT).as_posix()


def write_json(path: Path, value: object) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def check_image(path: Path, category: str, expected_size: object = None) -> None:
    with Image.open(path) as source:
        source.load()
        if expected_size:
            expected = tuple(expected_size) if isinstance(expected_size, list) else (int(expected_size),) * 2
            if source.size != expected:
                raise ValueError(f"Incorrect size {source.size}, expected {expected}: {path}")
        if category in {"card", "relic"} and source.size != (512, 512):
            raise ValueError(f"Not a 512px tile: {path}")
        if category == "portrait" and source.size != (1024, 1024):
            raise ValueError(f"Not a 1024px portrait: {path}")
        image = source.convert("RGBA")
        if image.convert("RGB").getextrema() == ((0, 0),) * 3:
            raise ValueError(f"Blank render: {path}")
        if category == "relic":
            alpha = image.getchannel("A")
            w, h = image.size
            edges = [alpha.crop((0, 0, w, 4)), alpha.crop((0, h - 4, w, h)),
                     alpha.crop((0, 0, 4, h)), alpha.crop((w - 4, 0, w, h))]
            if any(edge.getextrema()[1] > 3 for edge in edges):
                raise ValueError(f"Relic has no transparent outer padding: {path}")
            visible = sum(count for value, count in enumerate(alpha.histogram()) if value > 25)
            coverage = visible / (w * h)
            # Slender blades and open mechanisms occupy less area than armor.
            bounds = alpha.point(lambda value: 255 if value > 25 else 0).getbbox()
            if not 0.06 < coverage < 0.80 or bounds is None or max(bounds[2] - bounds[0], bounds[3] - bounds[1]) < w * 0.55:
                raise ValueError(f"Relic alpha coverage {coverage:.3f} is invalid: {path}")


def normalize_entries(manifest_path: Path) -> list[dict]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    source = manifest.get("source", manifest.get("source_path", ""))
    generator = manifest["generator"]
    generator_dependencies = manifest.get("generator_dependencies")
    if generator_dependencies:
        for dependency, expected_hash in generator_dependencies.items():
            if digest(project_path(dependency)) != expected_hash:
                raise ValueError(f"Stale dependency {dependency}: {manifest_path}")
        canonical = json.dumps(generator_dependencies, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
        if hashlib.sha256(canonical.encode()).hexdigest() != manifest.get("generator_sha256"):
            raise ValueError(f"Invalid generator dependency signature: {manifest_path}")
    for key, value in manifest.items():
        if key.endswith("_sha256") and key.removesuffix("_sha256") in manifest:
            if key == "generator_sha256" and generator_dependencies:
                continue
            if isinstance(value, dict):
                for dependency, expected_hash in value.items():
                    if digest(project_path(dependency)) != expected_hash:
                        raise ValueError(f"Stale dependency {dependency}: {manifest_path}")
                continue
            path_value = manifest[key.removesuffix("_sha256")]
            if isinstance(path_value, str) and path_value and digest(project_path(path_value)) != value:
                raise ValueError(f"Stale {key}: {manifest_path}")
    result = []
    for entry in manifest["assets"]:
        asset_source = entry.get("source_path", entry.get("source", source))
        if not asset_source or not project_path(asset_source).is_file():
            raise ValueError(f"No editable source: {entry}")
        if entry.get("source_sha256") and digest(project_path(asset_source)) != entry["source_sha256"]:
            raise ValueError(f"Stale source for {entry['id']}")
        asset_id = str(entry.get("id", entry.get("asset_id", "")))
        variants = [(entry.get("category", ""), asset_id, entry.get("runtime_path", entry.get("target", "")), entry.get("export_sha256", ""), entry.get("size"))]
        if "model" in entry:
            variants = []
            if entry.get("model") and entry.get("new_model", True):
                variants.append(("enemy_3d", asset_id, entry["model"], entry["model_sha256"], None))
            if entry.get("portrait"):
                variants.append(("portrait", "portrait_" + asset_id, entry["portrait"], entry["portrait_sha256"], 1024))
        for category, identifier, output, expected_hash, size in variants:
            path = project_path(output)
            if not category or not identifier or not expected_hash or not path.is_file() or digest(path) != expected_hash:
                raise ValueError(f"Missing or stale output: {identifier}: {output}")
            if path.suffix == ".png":
                check_image(path, category, size)
            item = {
                "asset_id": identifier, "category": category,
                "runtime_path": relative(path), "source_path": relative(asset_source),
                "generator": relative(generator), "export_sha256": expected_hash,
                "source_sha256": digest(project_path(asset_source)),
                "generator_sha256": manifest.get("generator_sha256", ""),
                "manifest_path": relative(manifest_path),
                "blender_version": manifest.get("blender_version", "5.2.2 LTS"),
                "replacement_status": "implemented", "batch_id": manifest["batch_id"],
            }
            for key in ("presentation", "visual_id", "kit", "recipe", "reuse", "source_render_size", "render_size", "size"):
                if key in entry:
                    item[key] = entry[key]
            result.append(item)
    return result


def expected_runtime_paths() -> dict[str, list[str]]:
    ids = {name: [entry["id"] for entry in json.loads((ROOT / f"data/{name}.json").read_text(encoding="utf-8"))]
           for name in ("cards", "relics", "starters", "enemies")}
    characters = ids["starters"] + ids["enemies"]
    return {
        "Cards": [f"assets/icons/cards/{x}.png" for x in ids["cards"]],

        "Fatigue": ["assets/icons/cards/environment_fatigue.png"],
        "Relics": [f"assets/icons/relics/{x}.png" for x in ids["relics"]],
        "Character models": [f"assets/models/battle/{x}.glb" for x in characters],
        "Portraits": [f"assets/portraits/{x}.png" for x in characters],
        "Status": [f"assets/icons/status/{x}.png" for x in ("bleed", "slow", "weak", "vulnerable")],
        "UI": [f"assets/icons/ui/{x}.png" for x in UI_IDS],
        "Effects": [f"assets/icons/effects/{x}.png" for x in EFFECT_IDS],
        "Map": [f"assets/icons/map/{x}.png" for x in MAP_IDS],
        "Controls": [f"assets/icons/controls/{x}.png" for x in (
            "checkbox_on", "checkbox_off", "checkbox_on_disabled", "checkbox_off_disabled",
            "switch_on", "switch_off", "switch_on_disabled", "switch_off_disabled",
            "slider_grabber", "slider_grabber_highlight")],
        "Backgrounds": ["assets/backgrounds/hub.png", "assets/backgrounds/run_result.png"],
        "Field": ["assets/models/environment/qq_battlefield.glb"],
        "Branding": ["assets/branding/queuequest-emblem-3d.png"],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifests", nargs="*", type=Path)
    parser.add_argument("--allow-partial", action="store_true")
    parser.add_argument("--date", default="2026-10-10")
    args = parser.parse_args()
    manifests = args.manifests or [*sorted((ROOT / "art_src/blender/characters").glob("qq_enemies_04.manifest.json")),
                                  *sorted((ROOT / "art_src/blender/relics").glob("*completion.manifest.json")),
                                  *sorted((ROOT / "art_src/blender/cards").glob("card_batches.manifest.json")),
                                  *sorted((ROOT / "art_src/blender/ui").glob("*.manifest.json")),
                                  *sorted((ROOT / "art_src/blender/environment").glob("*.manifest.json"))]
    provenance = json.loads(PROVENANCE.read_text(encoding="utf-8-sig"))
    registered = {entry["runtime_path"]: entry for entry in provenance["assets"]}
    batches = list(provenance.get("batch_ids", []))
    for path in manifests:
        path = project_path(str(path))
        for entry in normalize_entries(path):
            registered[entry["runtime_path"]] = entry
            if entry["batch_id"] not in batches:
                batches.append(entry["batch_id"])
    ids = [entry["asset_id"] for entry in registered.values()]
    if len(set(ids)) != len(ids):
        raise ValueError(f"Duplicate provenance IDs: {[x for x, n in Counter(ids).items() if n > 1]}")
    for entry in registered.values():
        path = project_path(entry["runtime_path"])
        if digest(path) != entry["export_sha256"] or not project_path(entry["source_path"]).is_file():
            raise ValueError(f"Stale provenance: {entry['asset_id']}")
    coverage = {name: {"done": sum(path in registered for path in paths), "total": len(paths),
                       "remaining": [path for path in paths if path not in registered]}
                for name, paths in expected_runtime_paths().items()}
    missing = [path for category in coverage.values() for path in category["remaining"]]
    if missing and not args.allow_partial:
        raise ValueError(f"Incomplete conversion: {len(missing)} missing: {missing[:12]}")
    visuals_path = ROOT / "data/battle_visuals.json"
    visuals = json.loads(visuals_path.read_text(encoding="utf-8"))
    for entry in registered.values():
        if entry["category"] in ("character_3d", "enemy_3d") and entry["asset_id"] in visuals:
            visuals[entry["asset_id"]]["model_scene"] = "res://" + entry["runtime_path"]
    provenance.update(assets=list(registered.values()), batch_ids=batches, updated_at=args.date,
                      tool="Blender (per-batch version recorded in manifests)")
    write_json(PROVENANCE, provenance)
    write_json(visuals_path, visuals)
    report = {"updated_at": args.date, "complete": not missing, "registered_assets": len(registered), "coverage": coverage}
    write_json(ROOT / "data/art_coverage.json", report)
    print("BLENDER_ASSET_IMPORT_OK", json.dumps(report, ensure_ascii=True))


if __name__ == "__main__":
    main()
