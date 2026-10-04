param([string]$GodotPath = "$env:USERPROFILE\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$output = Join-Path $root "build\web-layout-review"
New-Item -ItemType Directory -Path $output -Force | Out-Null
& (Join-Path $PSScriptRoot "generate_loading_logo.ps1")
& $GodotPath --headless --path $root --export-release "Web Layout Review" (Join-Path $output "index.html")
if ($LASTEXITCODE -ne 0) { throw "Layout review export failed ($LASTEXITCODE)" }
foreach ($asset in @("queuequest-logo.svg", "queuequest-mark.svg")) {
    Copy-Item -LiteralPath (Join-Path $root "assets\branding\$asset") -Destination (Join-Path $output $asset) -Force
}
Write-Output "WEB_LAYOUT_BUILD_OK"
