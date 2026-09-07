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
    & $BlenderPath --background --python-exit-code 1 --python $blenderScript
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

    $provenancePath = Join-Path $projectRoot "data\art_provenance.json"
    $provenance = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json
    $sourceManifest = Get-Content -LiteralPath (Join-Path $projectRoot "art_src\blender\art_vertical_slice.manifest.json") -Raw | ConvertFrom-Json
    foreach ($render in $sourceManifest.assets) {
        $entry = @($provenance.assets | Where-Object asset_id -eq $render.id)
        if ($entry.Count -ne 1 -or $entry[0].runtime_path -ne $render.target) {
            throw "Art provenance has no unique matching entry for $($render.id)"
        }
        $entry[0].export_sha256 = (Get-FileHash -LiteralPath (Join-Path $projectRoot $render.target) -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($render.category -in @("card", "relic")) {
            $entry[0] | Add-Member -NotePropertyName presentation -NotePropertyValue $render.presentation -Force
            $entry[0] | Add-Member -NotePropertyName art_revision -NotePropertyValue $sourceManifest.art_revision -Force
        }
    }
    $provenance.updated_at = Get-Date -Format "yyyy-MM-dd"
    $provenance | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $provenancePath -Encoding utf8
}
finally {
    Remove-Item Env:QQ_ART_RENDER_SIZE -ErrorAction SilentlyContinue
}

Write-Output "Blender art vertical slice imported successfully at ${RenderSize}px source resolution."
