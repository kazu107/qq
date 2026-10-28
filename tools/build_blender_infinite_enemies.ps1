param([string]$BlenderPath = "C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe")
$ErrorActionPreference = "Stop"
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    & $BlenderPath --background --factory-startup --python-exit-code 1 -t 4 --python tools/blender/build_infinite_enemy_art.py
    if ($LASTEXITCODE -ne 0) { throw "Infinite enemy artwork build failed" }
} finally { Pop-Location }
