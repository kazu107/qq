param([string]$GodotPath = "$env:USERPROFILE\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$output = Join-Path $PSScriptRoot ".local\quality-tests"
New-Item -ItemType Directory -Force $output | Out-Null
$previousAppData = $env:APPDATA
$env:APPDATA = Join-Path $output "appdata"
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
try {
    foreach ($scene in @("QualityToolsSmoke", "FatigueSmoke", "LanMultiplayerSmoke", "ReplayExportSmoke", "ReplayViewerSmoke", "ArtProvenanceSmoke", "StarterArtSmoke", "StartupCacheSmoke", "BattleStageCacheSmoke", "BattleStage3DSmoke", "FlowSmoke", "ArenaFlowSmoke", "LocalizationSmoke", "HubVersionSmoke", "WebExportSmoke")) {
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
    $env:APPDATA = $previousAppData
}
