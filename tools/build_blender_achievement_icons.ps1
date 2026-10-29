param(
    [string]$BlenderPath = "C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe",
    [string]$PythonPath = "python"
)
$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Push-Location $projectRoot
try {
    & $BlenderPath --background --factory-startup --python-exit-code 1 -t 4 --python tools/blender/build_achievement_icons.py
    if ($LASTEXITCODE -ne 0) { throw "Achievement rendering failed" }
    & $PythonPath tools/finalize_achievement_icons.py
    if ($LASTEXITCODE -ne 0) { throw "Achievement finalization failed" }
    & $PythonPath tools/finalize_achievement_icons.py --validate-only
    if ($LASTEXITCODE -ne 0) { throw "Achievement PNG validation failed" }
    & $BlenderPath --background --factory-startup --python-exit-code 1 -t 4 --python tools/blender/build_achievement_icons.py -- --validate-only
    if ($LASTEXITCODE -ne 0) { throw "Achievement Blender source validation failed" }
    & $BlenderPath --background --factory-startup --python-exit-code 1 -t 4 --python tools/blender/build_advanced_achievement_icons.py
    if ($LASTEXITCODE -ne 0) { throw "Advanced achievement rendering failed" }
    & $PythonPath tools/finalize_advanced_achievement_icons.py
    if ($LASTEXITCODE -ne 0) { throw "Advanced achievement finalization failed" }
} finally {
    Pop-Location
}
