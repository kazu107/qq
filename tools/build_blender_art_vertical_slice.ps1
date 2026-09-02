param(
    [string]$BlenderPath = "C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe",
    [string]$GodotPath = "C:\Users\kazuu\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe",
    [ValidateRange(512, 4096)]
    [int]$RenderSize = 1024
)

$ErrorActionPreference = "Stop"

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$blenderScript = Join-Path $projectRoot "tools\blender\build_art_vertical_slice.py"
$buildRoot = Join-Path $projectRoot "tools\.local\blender_art_vertical_slice"
$cardManifest = Join-Path $buildRoot "card_manifest.json"
$relicManifest = Join-Path $buildRoot "relic_manifest.json"
$iconManifest = Join-Path $buildRoot "icon_manifest.json"
$previewRoot = Join-Path $projectRoot "art_src\blender\previews"

if (-not (Test-Path -LiteralPath $BlenderPath)) {
    throw "Blender executable was not found: $BlenderPath"
}
if (-not (Test-Path -LiteralPath $GodotPath)) {
    throw "Godot console executable was not found: $GodotPath"
}
if (-not (Test-Path -LiteralPath $blenderScript)) {
    throw "Blender art generator was not found: $blenderScript"
}

New-Item -ItemType Directory -Path $previewRoot -Force | Out-Null
$env:QQ_ART_RENDER_SIZE = [string]$RenderSize

try {
    & $BlenderPath --background --python $blenderScript
    if ($LASTEXITCODE -ne 0) {
        throw "Blender art generation failed with exit code $LASTEXITCODE"
    }

    & $GodotPath --headless --path $projectRoot --script res://tools/import_generated_card_art.gd -- --manifest=$cardManifest --allow-partial --contact-sheet=$(Join-Path $previewRoot "art_vertical_slice_cards.png")
    if ($LASTEXITCODE -ne 0) {
        throw "Card art import failed with exit code $LASTEXITCODE"
    }

    & $GodotPath --headless --path $projectRoot --script res://tools/import_generated_relic_art.gd -- --manifest=$relicManifest --allow-partial --contact-sheet=$(Join-Path $previewRoot "art_vertical_slice_relics.png")
    if ($LASTEXITCODE -ne 0) {
        throw "Relic art import failed with exit code $LASTEXITCODE"
    }

    & $GodotPath --headless --path $projectRoot --script res://tools/import_generated_icon_art.gd -- --manifest=$iconManifest --contact-sheet=$(Join-Path $previewRoot "art_vertical_slice_icons.png")
    if ($LASTEXITCODE -ne 0) {
        throw "Small icon art import failed with exit code $LASTEXITCODE"
    }
}
finally {
    Remove-Item Env:QQ_ART_RENDER_SIZE -ErrorAction SilentlyContinue
}

Write-Output "Blender art vertical slice imported successfully at ${RenderSize}px source resolution."
