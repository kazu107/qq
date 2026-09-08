param(
    [string]$BlenderPath = "C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe",
    [string]$PythonPath = "python",
    [ValidateRange(1024, 4096)]
    [int]$RenderSize = 2048
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$previousSize = $env:QQ_STARTER_RENDER_SIZE
Push-Location $projectRoot
try {
    $env:QQ_STARTER_RENDER_SIZE = [string]$RenderSize
    & $BlenderPath --background --factory-startup --python-exit-code 1 --python tools/blender/build_starter_batch.py
    if ($LASTEXITCODE -ne 0) { throw "Blender starter generation failed" }
    & $BlenderPath --background --factory-startup art_src/blender/characters/qq_starters.blend --python-exit-code 1 --python tools/blender/validate_starter_batch.py
    if ($LASTEXITCODE -ne 0) { throw "Blender starter cold-reload validation failed" }
    & $PythonPath tools/finalize_starter_batch.py
    if ($LASTEXITCODE -ne 0) { throw "Starter batch registration failed (Python with Pillow required)" }
}
finally {
    $env:QQ_STARTER_RENDER_SIZE = $previousSize
    Pop-Location
}
