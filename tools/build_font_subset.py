#!/usr/bin/env python3
"""Build the embedded Japanese font subset from localized display text."""

from __future__ import annotations

import argparse
import json
import shutil
import string
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

TEXT_RESOURCE_SUFFIXES = {".cfg", ".gd", ".godot", ".json", ".tres", ".tscn"}
DEFAULT_SCAN_ROOTS = (Path("data"), Path("src"), Path("scenes"))


def _collect_strings(value: object, characters: set[str]) -> None:
    if isinstance(value, str):
        characters.update(value)
    elif isinstance(value, dict):
        for nested_value in value.values():
            _collect_strings(nested_value, characters)
    elif isinstance(value, list):
        for nested_value in value:
            _collect_strings(nested_value, characters)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True, help="Full Noto Sans JP TTF")
    parser.add_argument(
        "--localization",
        type=Path,
        default=Path("data/localization/ja.json"),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("assets/fonts/NotoSansJP-GameSubset.ttf"),
    )
    parser.add_argument(
        "--scan-root",
        type=Path,
        action="append",
        help="Additional runtime text root. Defaults to data, src, and scenes.",
    )
    args = parser.parse_args()

    localized_data = json.loads(args.localization.read_text(encoding="utf-8"))
    characters = set(string.printable)
    _collect_strings(localized_data, characters)
    scan_roots = args.scan_root or list(DEFAULT_SCAN_ROOTS)
    for scan_root in scan_roots:
        if not scan_root.exists():
            continue
        for text_path in scan_root.rglob("*"):
            if text_path.is_file() and text_path.suffix.lower() in TEXT_RESOURCE_SUFFIXES:
                characters.update(text_path.read_text(encoding="utf-8"))

    options = subset.Options()
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.name_legacy = True
    options.name_languages = ["*"]
    options.notdef_glyph = True
    options.notdef_outline = True
    options.recommended_glyphs = True
    options.glyph_names = True

    font = TTFont(args.source)
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(text="".join(sorted(characters)))
    subsetter.subset(font)

    missing_characters = sorted(
        character
        for character in characters
        if not character.isspace() and ord(character) not in font.getBestCmap()
    )
    if missing_characters:
        missing_preview = "".join(missing_characters[:40])
        raise RuntimeError(f"Source font is missing required characters: {missing_preview}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary_output = args.output.with_suffix(".tmp.ttf")
    font.save(temporary_output)
    shutil.move(temporary_output, args.output)
    print(f"Wrote {args.output} with {len(font.getBestCmap())} mapped characters")


if __name__ == "__main__":
    main()
