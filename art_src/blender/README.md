# Battle character sources

`battle_vertical_slice.blend` contains the authored Balanced and Scout vertical
slice. Godot does not import this directory because `art_src/.gdignore` keeps
editable source files and preview renders out of the runtime PCK.

The game loads these generated files:

- `assets/models/battle/balanced.glb`
- `assets/models/battle/scout.glb`

Regenerate the Blend source, preview, and both GLBs with Blender 5.2 LTS:

```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe" `
  --background `
  --python tools\blender\build_battle_vertical_slice.py
```

The script recreates the file from an empty scene and is the source of truth for
this vertical slice. Manual changes made only in the Blend or generated GLBs are
overwritten on the next run.
