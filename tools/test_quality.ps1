param([string]$GodotPath = "$env:USERPROFILE\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$output = Join-Path $PSScriptRoot ".local\quality-tests"
New-Item -ItemType Directory -Force $output | Out-Null
$save = Join-Path $env:APPDATA "Godot\app_userdata\qq\save.json"
$backup = Join-Path $output "save-before-tests.json"
$existed = Test-Path -LiteralPath $save
if ($existed) { Copy-Item -LiteralPath $save -Destination $backup -Force }
try {
    foreach ($scene in @("QualityToolsSmoke", "FatigueSmoke", "LanMultiplayerSmoke", "ReplayExportSmoke", "ReplayViewerSmoke", "ArtProvenanceSmoke", "StarterArtSmoke", "BattleStage3DSmoke", "LocalizationSmoke", "HubVersionSmoke", "WebExportSmoke")) {
        $log = Join-Path $output "$scene.log"
		$ErrorActionPreference = "Continue"
        & $GodotPath --headless --path $root "res://tests/$scene.tscn" *> $log
        $code = $LASTEXITCODE
		$ErrorActionPreference = "Stop"
        $errors = Select-String -LiteralPath $log -Pattern "SCRIPT ERROR|Parse Error|Assertion failed|Smoke failed|smoke failed"
        if ($code -ne 0 -or $errors) { throw "$scene failed ($code). See $log" }
        Write-Host "$scene passed"
    }
} finally {
    if ($existed) {
        Copy-Item -LiteralPath $backup -Destination $save -Force
    } elseif (Test-Path -LiteralPath $save) {
        # This is only the exact save file created by the test run, never a directory.
        Remove-Item -LiteralPath $save
    }
}
