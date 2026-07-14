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

Write-Host "[1/33] Validating JSON files"
$jsonFiles = Get-ChildItem -Path (Join-Path $root "data") -Filter *.json -File
foreach ($file in $jsonFiles) {
    try {
        $null = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Add-Error "Invalid JSON: $($file.FullName) :: $($_.Exception.Message)"
    }
}

Write-Host "[2/33] Validating scene script references"
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

Write-Host "[3/33] Scanning for likely Variant inference traps"
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
    Invoke-GodotCheck "[4/33] Loading project in headless editor mode" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--editor",
        "--quit"
    )
    Invoke-GodotCheck "[5/33] Running main scene startup smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--quit-after", "120"
    )
    Invoke-GodotCheck "[6/33] Running battle engine smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/BattleEngineSmoke.tscn"
    )
    Invoke-GodotCheck "[7/33] Running special card effects smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/SpecialCardEffectsSmoke.tscn"
    )
    Invoke-GodotCheck "[8/33] Running battle flow smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/FlowSmoke.tscn"
    )
    Invoke-GodotCheck "[9/33] Running card UI smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/CardUiSmoke.tscn"
    )
    Invoke-GodotCheck "[10/33] Running map/facility smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/MapFacilitySmoke.tscn"
    )
    Invoke-GodotCheck "[11/33] Running arena flow smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/ArenaFlowSmoke.tscn"
    )
    Invoke-GodotCheck "[12/33] Running hazard flow smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/HazardFlowSmoke.tscn"
    )
    Invoke-GodotCheck "[13/33] Running save/continue smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/SaveContinueSmoke.tscn"
    )
    Invoke-GodotCheck "[14/33] Running developer mode smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/DeveloperModeSmoke.tscn"
    )
    Invoke-GodotCheck "[15/33] Running meta progress smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/MetaProgressSmoke.tscn"
    )
    Invoke-GodotCheck "[16/33] Running replay export smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/ReplayExportSmoke.tscn"
    )
    Invoke-GodotCheck "[17/33] Running reward progression smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/RewardProgressionSmoke.tscn"
    )
    Invoke-GodotCheck "[18/33] Running settings smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/SettingsSmoke.tscn"
    )
    Invoke-GodotCheck "[19/33] Running audio smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/AudioSmoke.tscn"
    )
    Invoke-GodotCheck "[20/33] Running event system smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/EventSystemSmoke.tscn"
    )
    Invoke-GodotCheck "[21/33] Running replay viewer smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/ReplayViewerSmoke.tscn"
    )
    Invoke-GodotCheck "[22/33] Running localization smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/LocalizationSmoke.tscn"
    )
    Invoke-GodotCheck "[23/33] Running run score smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/RunScoreSmoke.tscn"
    )
    Invoke-GodotCheck "[24/33] Running progression tier smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/ProgressionTierSmoke.tscn"
    )
    Invoke-GodotCheck "[25/33] Running startup cache smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/StartupCacheSmoke.tscn"
    )
    Invoke-GodotCheck "[26/33] Running generated card art smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/CardArtSmoke.tscn"
    )
    Invoke-GodotCheck "[27/33] Running legendary cards smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/LegendaryCardsSmoke.tscn"
    )
    Invoke-GodotCheck "[28/33] Running LAN multiplayer protocol smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/LanMultiplayerSmoke.tscn"
    )
    Invoke-GodotCheck "[29/33] Running EOS API contract smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--script", "res://tests/eos_api_contract_smoke.gd"
    )
    Invoke-GodotCheck "[30/33] Running online multiplayer protocol smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/OnlineMultiplayerSmoke.tscn"
    )
    Write-Host "[31/33] Running LAN two-peer ENet smoke"
    $lanValidationOutput = & (Join-Path $PSScriptRoot "validate_lan_network.ps1") -GodotPath $godotExe -Root $root 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Add-Error "LAN two-peer validation failed.`n$lanValidationOutput"
    }
    elseif (-not [string]::IsNullOrWhiteSpace($lanValidationOutput)) {
        Write-Host $lanValidationOutput.TrimEnd()
    }
    Write-Host "[32/33] Running online flow loopback regression smoke"
    $onlineValidationOutput = & (Join-Path $PSScriptRoot "validate_lan_network.ps1") -GodotPath $godotExe -Root $root -Scope online 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Add-Error "Online two-peer validation failed.`n$onlineValidationOutput"
    }
    elseif (-not [string]::IsNullOrWhiteSpace($onlineValidationOutput)) {
        Write-Host $onlineValidationOutput.TrimEnd()
    }
    if ($env:QQ_EOS_RUN_DEVICE_TESTS -eq "1") {
        Write-Host "[LIVE] Running anonymous EOS Device ID smoke"
        $eosDeviceOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass `
            -File (Join-Path $PSScriptRoot "validate_eos_device.ps1") `
            -GodotPath $godotExe `
            -Root $root 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Add-Error "EOS anonymous Device ID validation failed.`n$eosDeviceOutput"
        }
        elseif (-not [string]::IsNullOrWhiteSpace($eosDeviceOutput)) {
            Write-Host $eosDeviceOutput.TrimEnd()
        }
    }
    Write-Host "[33/33] Running LAN sustained network soak"
    $lanSoakOutput = & (Join-Path $PSScriptRoot "validate_lan_network_soak.ps1") -GodotPath $godotExe -Root $root -DurationSeconds 8 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Add-Error "LAN sustained network soak failed.`n$lanSoakOutput"
    }
    elseif (-not [string]::IsNullOrWhiteSpace($lanSoakOutput)) {
        Write-Host $lanSoakOutput.TrimEnd()
    }
    if ($env:QQ_EOS_RUN_LIVE_TESTS -eq "1") {
        Write-Host "[LIVE] Running EOS Relay two-account smoke"
        $eosValidationOutput = & (Join-Path $PSScriptRoot "validate_eos_network.ps1") -GodotPath $godotExe -Root $root 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Add-Error "EOS Relay two-account validation failed.`n$eosValidationOutput"
        }
        elseif (-not [string]::IsNullOrWhiteSpace($eosValidationOutput)) {
            Write-Host $eosValidationOutput.TrimEnd()
        }
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 1
}

Write-Host "Validation passed."
