param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$errors = New-Object System.Collections.Generic.List[string]

function Add-Error([string]$message) {
    $errors.Add($message)
}

function Resolve-GodotExecutable([string]$PathValue) {
    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $null
    }

    if (Test-Path $PathValue -PathType Leaf) {
        return (Resolve-Path $PathValue).Path
    }

    if (Test-Path $PathValue -PathType Container) {
        $consoleExe = Get-ChildItem $PathValue -Filter '*_console.exe' -File | Select-Object -First 1
        if ($consoleExe) {
            return $consoleExe.FullName
        }

        $editorExe = Get-ChildItem $PathValue -Filter 'Godot*.exe' -File | Select-Object -First 1
        if ($editorExe) {
            return $editorExe.FullName
        }
    }

    Add-Error "Godot executable not found from path: $PathValue"
    return $null
}

function Invoke-GodotCheck([string]$Label, [string]$ExePath, [string[]]$Arguments) {
    Write-Host $Label
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $outputLines = & $ExePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    $output = ($outputLines | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) {
            $_.Exception.Message
        }
        else {
            $_.ToString()
        }
    }) -join [Environment]::NewLine
    if ($exitCode -ne 0) {
        Add-Error "Godot command failed ($Label) with exit code $exitCode.`n$output"
        return
    }

    if ($output -match 'SCRIPT ERROR:' -or $output -match 'Parse Error:' -or $output -match 'Compile Error:') {
        Add-Error "Godot reported script issues during $Label.`n$output"
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($output)) {
        Write-Host $output.TrimEnd()
    }
}

Write-Host "[1/30] Validating JSON files"
$jsonFiles = Get-ChildItem -Path (Join-Path $root "data") -Filter *.json -File
foreach ($file in $jsonFiles) {
    try {
        $null = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Add-Error "Invalid JSON: $($file.FullName) :: $($_.Exception.Message)"
    }
}

Write-Host "[2/30] Validating scene script references"
$sceneFiles = Get-ChildItem -Path (Join-Path $root "scenes") -Filter *.tscn -Recurse -File
foreach ($scene in $sceneFiles) {
    $content = Get-Content $scene.FullName -Raw
    $matches = [regex]::Matches($content, 'path=\"res://([^\"]+)\"')
    foreach ($match in $matches) {
        $relative = $match.Groups[1].Value -replace '/', '\'
        $fullPath = Join-Path $root $relative
        if (-not (Test-Path $fullPath)) {
            Add-Error "Missing resource: $($scene.FullName) -> res://$($match.Groups[1].Value)"
        }
    }
}

Write-Host "[3/30] Scanning for likely Variant inference traps"
$gdFiles = Get-ChildItem -Path (Join-Path $root "src") -Filter *.gd -Recurse -File
$dangerPatterns = @(
    ':\=\s*[A-Za-z0-9_\.]+\s*\.get\(',
    ':\=\s*[A-Za-z0-9_\.]+\s*\.duplicate\(',
    ':\=\s*max\(',
    ':\=\s*min\(',
    ':\=\s*_parse_json_file\('
)
foreach ($gdFile in $gdFiles) {
    $lineNumber = 0
    foreach ($line in Get-Content $gdFile.FullName) {
        $lineNumber++
        foreach ($pattern in $dangerPatterns) {
            if ($line -match $pattern) {
                Add-Error "Potential Variant inference: $($gdFile.FullName):$lineNumber :: $($line.Trim())"
            }
        }
    }
}

$godotExe = Resolve-GodotExecutable $GodotPath
if ($godotExe) {
    Invoke-GodotCheck "[4/30] Loading project in headless editor mode" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--editor",
        "--quit"
    )
    Invoke-GodotCheck "[5/30] Running main scene startup smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--quit-after", "120"
    )
    Invoke-GodotCheck "[6/30] Running battle engine smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/BattleEngineSmoke.tscn"
    )
    Invoke-GodotCheck "[7/30] Running special card effects smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/SpecialCardEffectsSmoke.tscn"
    )
    Invoke-GodotCheck "[8/30] Running battle flow smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/FlowSmoke.tscn"
    )
    Invoke-GodotCheck "[9/30] Running card UI smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/CardUiSmoke.tscn"
    )
    Invoke-GodotCheck "[10/30] Running map/facility smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/MapFacilitySmoke.tscn"
    )
    Invoke-GodotCheck "[11/30] Running arena flow smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/ArenaFlowSmoke.tscn"
    )
    Invoke-GodotCheck "[12/30] Running hazard flow smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/HazardFlowSmoke.tscn"
    )
    Invoke-GodotCheck "[13/30] Running save/continue smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/SaveContinueSmoke.tscn"
    )
    Invoke-GodotCheck "[14/30] Running developer mode smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/DeveloperModeSmoke.tscn"
    )
    Invoke-GodotCheck "[15/30] Running meta progress smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/MetaProgressSmoke.tscn"
    )
    Invoke-GodotCheck "[16/30] Running replay export smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/ReplayExportSmoke.tscn"
    )
    Invoke-GodotCheck "[17/30] Running reward progression smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/RewardProgressionSmoke.tscn"
    )
    Invoke-GodotCheck "[18/30] Running settings smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/SettingsSmoke.tscn"
    )
    Invoke-GodotCheck "[19/30] Running audio smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/AudioSmoke.tscn"
    )
    Invoke-GodotCheck "[20/30] Running event system smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/EventSystemSmoke.tscn"
    )
    Invoke-GodotCheck "[21/30] Running replay viewer smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/ReplayViewerSmoke.tscn"
    )
    Invoke-GodotCheck "[22/30] Running localization smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/LocalizationSmoke.tscn"
    )
    Invoke-GodotCheck "[23/30] Running run score smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/RunScoreSmoke.tscn"
    )
    Invoke-GodotCheck "[24/30] Running progression tier smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/ProgressionTierSmoke.tscn"
    )
    Invoke-GodotCheck "[25/30] Running startup cache smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/StartupCacheSmoke.tscn"
    )
    Invoke-GodotCheck "[26/30] Running generated card art smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/CardArtSmoke.tscn"
    )
    Invoke-GodotCheck "[27/30] Running legendary cards smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/LegendaryCardsSmoke.tscn"
    )
    Invoke-GodotCheck "[28/30] Running LAN multiplayer protocol smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/LanMultiplayerSmoke.tscn"
    )
    Invoke-GodotCheck "[28/30] Running online multiplayer protocol smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/OnlineMultiplayerSmoke.tscn"
    )
    Write-Host "[29/30] Running LAN two-peer ENet smoke"
    $lanValidationOutput = & (Join-Path $PSScriptRoot "validate_lan_network.ps1") -GodotPath $godotExe -Root $root 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Add-Error "LAN two-peer validation failed.`n$lanValidationOutput"
    }
    elseif (-not [string]::IsNullOrWhiteSpace($lanValidationOutput)) {
        Write-Host $lanValidationOutput.TrimEnd()
    }
    Write-Host "[29/30] Running online two-peer ENet smoke"
    $onlineValidationOutput = & (Join-Path $PSScriptRoot "validate_lan_network.ps1") -GodotPath $godotExe -Root $root -Scope online 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Add-Error "Online two-peer validation failed.`n$onlineValidationOutput"
    }
    elseif (-not [string]::IsNullOrWhiteSpace($onlineValidationOutput)) {
        Write-Host $onlineValidationOutput.TrimEnd()
    }
    Write-Host "[30/30] Running LAN sustained network soak"
    $lanSoakOutput = & (Join-Path $PSScriptRoot "validate_lan_network_soak.ps1") -GodotPath $godotExe -Root $root -DurationSeconds 8 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Add-Error "LAN sustained network soak failed.`n$lanSoakOutput"
    }
    elseif (-not [string]::IsNullOrWhiteSpace($lanSoakOutput)) {
        Write-Host $lanSoakOutput.TrimEnd()
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 1
}

Write-Host "Validation passed."
