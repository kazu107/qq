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
    $previousAppData = [Environment]::GetEnvironmentVariable("APPDATA", "Process")
    try {
        [Environment]::SetEnvironmentVariable("APPDATA", $script:TestAppData, "Process")
        $ErrorActionPreference = "Continue"
        $outputLines = & $ExePath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        [Environment]::SetEnvironmentVariable("APPDATA", $previousAppData, "Process")
    }
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

Write-Host "[1/31] Validating JSON files"
$jsonFiles = Get-ChildItem -Path (Join-Path $root "data") -Filter *.json -File
foreach ($file in $jsonFiles) {
    try {
        $null = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Add-Error "Invalid JSON: $($file.FullName) :: $($_.Exception.Message)"
    }
}

Write-Host "[2/31] Validating scene script references"
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

Write-Host "[3/31] Scanning for likely Variant inference traps"
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

$systemTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$script:TestAppData = [IO.Path]::GetFullPath(
    [IO.Path]::Combine($systemTempRoot, "qq-godot-validation-$([Guid]::NewGuid().ToString('N'))")
)
[IO.Directory]::CreateDirectory($script:TestAppData) | Out-Null
Write-Host "Using isolated Godot user data: $script:TestAppData"

$godotExe = Resolve-GodotExecutable $GodotPath
if ($godotExe) {
    Invoke-GodotCheck "[4/31] Loading project in headless editor mode" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--editor",
        "--quit"
    )
    Invoke-GodotCheck "[5/31] Running main scene startup smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--quit-after", "120"
    )
    Invoke-GodotCheck "[6/31] Running battle engine smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/BattleEngineSmoke.tscn"
    )
    Invoke-GodotCheck "[7/31] Running special card effects smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/SpecialCardEffectsSmoke.tscn"
    )
    Invoke-GodotCheck "[8/31] Running battle flow smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/FlowSmoke.tscn"
    )
    Invoke-GodotCheck "[9/31] Running card UI smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/CardUiSmoke.tscn"
    )
    Invoke-GodotCheck "[9a/31] Running 3D battle stage smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/BattleStage3DSmoke.tscn"
    )
    Invoke-GodotCheck "[9b/31] Running common 3D battle humanoid smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/CommonBattleHumanoidSmoke.tscn"
    )
    Invoke-GodotCheck "[9c/31] Running 3D battle visual profiles smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/BattleVisualProfilesSmoke.tscn"
    )
    Invoke-GodotCheck "[9d/31] Running authored 3D battle models smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/AuthoredBattleModelsSmoke.tscn"
    )
    Invoke-GodotCheck "[10/31] Running map/facility smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/MapFacilitySmoke.tscn"
    )
    Invoke-GodotCheck "[11/31] Running arena flow smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/ArenaFlowSmoke.tscn"
    )
    Invoke-GodotCheck "[11a/31] Running multiplayer tournament smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/ArenaTournamentSmoke.tscn"
    )
    Invoke-GodotCheck "[11b/31] Running spectator battle smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/SpectatorBattleSmoke.tscn"
    )
    Invoke-GodotCheck "[12/31] Running hazard flow smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/HazardFlowSmoke.tscn"
    )
    Invoke-GodotCheck "[13/31] Running save/continue smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/SaveContinueSmoke.tscn"
    )
    Invoke-GodotCheck "[14/31] Running developer mode smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/DeveloperModeSmoke.tscn"
    )
    Invoke-GodotCheck "[15/31] Running meta progress smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/MetaProgressSmoke.tscn"
    )
    Invoke-GodotCheck "[16/31] Running replay export smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/ReplayExportSmoke.tscn"
    )
    Invoke-GodotCheck "[17/31] Running reward progression smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/RewardProgressionSmoke.tscn"
    )
    Invoke-GodotCheck "[18/31] Running settings smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/SettingsSmoke.tscn"
    )
    Invoke-GodotCheck "[18a/31] Running Hub version UI smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/HubVersionSmoke.tscn"
    )
    Invoke-GodotCheck "[19/31] Running audio smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/AudioSmoke.tscn"
    )
    Invoke-GodotCheck "[19a/31] Running SFX lab smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/SfxLabSmoke.tscn"
    )
    Write-Host "[19b/31] Validating normalized SFX assets"
    $nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($null -eq $nodeCommand) {
        Add-Error "node.exe was not found; SFX asset validation could not run."
    }
    else {
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $sfxOutputLines = & $nodeCommand.Source (Join-Path $root "tools\validate_sfx.mjs") 2>&1
        $sfxExitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorActionPreference
        $sfxOutput = ($sfxOutputLines | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $_.Exception.Message
            }
            else {
                $_.ToString()
            }
        }) -join [Environment]::NewLine
        if ($sfxExitCode -ne 0) {
            Add-Error "SFX asset validation failed.`n$sfxOutput"
        }
        elseif (-not [string]::IsNullOrWhiteSpace($sfxOutput)) {
            Write-Host $sfxOutput.TrimEnd()
        }
    }
    Invoke-GodotCheck "[20/31] Running event system smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/EventSystemSmoke.tscn"
    )
    Invoke-GodotCheck "[21/31] Running replay viewer smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/ReplayViewerSmoke.tscn"
    )
    Invoke-GodotCheck "[22/31] Running localization smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/LocalizationSmoke.tscn"
    )
    Invoke-GodotCheck "[23/31] Running run score smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/RunScoreSmoke.tscn"
    )
    Invoke-GodotCheck "[24/31] Running progression tier smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/ProgressionTierSmoke.tscn"
    )
    Invoke-GodotCheck "[25/31] Running startup cache smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/StartupCacheSmoke.tscn"
    )
    Invoke-GodotCheck "[26/31] Running generated card art smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/CardArtSmoke.tscn"
    )
    Invoke-GodotCheck "[27/31] Running legendary cards smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/LegendaryCardsSmoke.tscn"
    )
    Invoke-GodotCheck "[28/31] Running Web multiplayer protocol smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/LanMultiplayerSmoke.tscn"
    )
    Invoke-GodotCheck "[29/31] Running Web multiplayer configuration smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/WebMultiplayerSmoke.tscn"
    )
    Invoke-GodotCheck "[30/31] Running Web export configuration smoke" $godotExe @(
        "--no-header",
        "--headless",
        "--path", $root,
        "--scene", "res://tests/WebExportSmoke.tscn"
    )
	Write-Host "[31/31] Running Heroku signaling server tests"
	$npmCommand = Get-Command npm.cmd -ErrorAction SilentlyContinue
	if ($null -eq $npmCommand) {
		Add-Error "npm.cmd was not found; Node signaling tests could not run."
	}
	else {
		$previousErrorActionPreference = $ErrorActionPreference
		$ErrorActionPreference = "Continue"
		$nodeOutputLines = & $npmCommand.Source test 2>&1
		$nodeExitCode = $LASTEXITCODE
		$ErrorActionPreference = $previousErrorActionPreference
		$nodeOutput = ($nodeOutputLines | ForEach-Object {
			if ($_ -is [System.Management.Automation.ErrorRecord]) {
				$_.Exception.Message
			}
			else {
				$_.ToString()
			}
		}) -join [Environment]::NewLine
		if ($nodeExitCode -ne 0) {
			Add-Error "Heroku signaling server tests failed.`n$nodeOutput"
		}
		elseif (-not [string]::IsNullOrWhiteSpace($nodeOutput)) {
			Write-Host $nodeOutput.TrimEnd()
		}
	}
}

if (
    $script:TestAppData.StartsWith($systemTempRoot, [StringComparison]::OrdinalIgnoreCase) -and
    [IO.Directory]::Exists($script:TestAppData)
) {
    [IO.Directory]::Delete($script:TestAppData, $true)
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 1
}

Write-Host "Validation passed."
