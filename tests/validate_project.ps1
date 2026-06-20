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
    $output = & $ExePath @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Add-Error "Godot command failed ($Label) with exit code $LASTEXITCODE.`n$output"
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

Write-Host "[1/22] Validating JSON files"
$jsonFiles = Get-ChildItem -Path (Join-Path $root "data") -Filter *.json -File
foreach ($file in $jsonFiles) {
    try {
        $null = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Add-Error "Invalid JSON: $($file.FullName) :: $($_.Exception.Message)"
    }
}

Write-Host "[2/22] Validating scene script references"
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

Write-Host "[3/22] Scanning for likely Variant inference traps"
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
    Invoke-GodotCheck "[4/22] Loading project in headless editor mode" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--editor",
        "--quit"
    )
    Invoke-GodotCheck "[5/22] Running main scene startup smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--quit-after", "120"
    )
    Invoke-GodotCheck "[6/22] Running battle engine smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/BattleEngineSmoke.tscn"
    )
    Invoke-GodotCheck "[7/22] Running special card effects smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/SpecialCardEffectsSmoke.tscn"
    )
    Invoke-GodotCheck "[8/22] Running battle flow smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/FlowSmoke.tscn"
    )
    Invoke-GodotCheck "[9/22] Running card UI smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/CardUiSmoke.tscn"
    )
    Invoke-GodotCheck "[10/22] Running map/facility smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/MapFacilitySmoke.tscn"
    )
    Invoke-GodotCheck "[11/22] Running hazard flow smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/HazardFlowSmoke.tscn"
    )
    Invoke-GodotCheck "[12/22] Running save/continue smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/SaveContinueSmoke.tscn"
    )
    Invoke-GodotCheck "[13/22] Running developer mode smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/DeveloperModeSmoke.tscn"
    )
    Invoke-GodotCheck "[14/22] Running meta progress smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/MetaProgressSmoke.tscn"
    )
    Invoke-GodotCheck "[15/22] Running replay export smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/ReplayExportSmoke.tscn"
    )
    Invoke-GodotCheck "[16/22] Running reward progression smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/RewardProgressionSmoke.tscn"
    )
    Invoke-GodotCheck "[17/22] Running settings smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/SettingsSmoke.tscn"
    )
    Invoke-GodotCheck "[18/22] Running audio smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/AudioSmoke.tscn"
    )
    Invoke-GodotCheck "[19/22] Running event system smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/EventSystemSmoke.tscn"
    )
    Invoke-GodotCheck "[20/22] Running replay viewer smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/ReplayViewerSmoke.tscn"
    )
    Invoke-GodotCheck "[21/22] Running localization smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/LocalizationSmoke.tscn"
    )
    Invoke-GodotCheck "[22/22] Running run score smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/RunScoreSmoke.tscn"
    )
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 1
}

Write-Host "Validation passed."
