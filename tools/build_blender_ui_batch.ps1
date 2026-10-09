param(
    [string]$BlenderPath = "C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe",
    [string]$PythonPath = "python"
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not (Test-Path -LiteralPath $BlenderPath)) {
    throw "Blender executable was not found: $BlenderPath"
}
Push-Location $projectRoot
try {
    & $BlenderPath --background --factory-startup --python-exit-code 1 -t 4 --python tools/blender/build_ui_batch.py
    if ($LASTEXITCODE -ne 0) { throw "Blender UI rendering failed" }
    & $PythonPath tools/finalize_ui_batch.py
    if ($LASTEXITCODE -ne 0) { throw "Blender UI finalization failed" }
    & $PythonPath tools/finalize_ui_batch.py --validate-only
    if ($LASTEXITCODE -ne 0) { throw "Blender UI validation failed" }
    & $BlenderPath --background --factory-startup --python-exit-code 1 -t 4 --python tools/blender/validate_ui_batch.py
    if ($LASTEXITCODE -ne 0) { throw "Editable Blender UI source validation failed" }
}
finally {
    Pop-Location
}
