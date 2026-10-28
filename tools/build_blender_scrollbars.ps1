param([string]$BlenderPath = "C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    & $BlenderPath --background --factory-startup --python-exit-code 1 -t 4 --python tools/blender/build_scrollbar_skin.py
    if ($LASTEXITCODE -ne 0) { throw "Blender scrollbar generation failed" }
    $web = Join-Path $root "server/accounts/public/scrollbars"
    New-Item -ItemType Directory -Path $web -Force | Out-Null
    foreach ($orientation in @("v", "h")) {
        foreach ($state in @("track", "grabber", "highlight", "pressed")) {
            $file = "scrollbar_${orientation}_${state}.png"
            Copy-Item -LiteralPath (Join-Path $root "assets/icons/controls/$file") -Destination (Join-Path $web $file) -Force
        }
    }
} finally { Pop-Location }
