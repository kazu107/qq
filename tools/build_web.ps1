param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$OutputDirectory = Join-Path $ProjectRoot "build\web"
$OutputFile = Join-Path $OutputDirectory "index.html"

function Resolve-GodotExecutable {
    param([string]$RequestedPath)

    $candidates = @()
    if ($RequestedPath) {
        $candidates += $RequestedPath
        if (Test-Path -LiteralPath $RequestedPath -PathType Container) {
            $candidates += Get-ChildItem -LiteralPath $RequestedPath -Filter "*_console.exe" -File -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty FullName
        }
    }

    $candidates += @(
        (Join-Path $env:USERPROFILE "Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe"),
        (Join-Path $env:USERPROFILE "Downloads\Godot_v4.6.2-stable_win64_console.exe")
    )

    foreach ($commandName in @("godot4", "godot")) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command) {
            $candidates += $command.Source
        }
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "Godot 4.6.2 executable was not found. Pass -GodotPath with the executable or extracted Godot folder."
}

$GodotExecutable = Resolve-GodotExecutable -RequestedPath $GodotPath
$TemplateDirectory = Join-Path $env:APPDATA "Godot\export_templates\4.6.2.stable"
$RequiredTemplates = @(
    (Join-Path $TemplateDirectory "web_nothreads_debug.zip"),
    (Join-Path $TemplateDirectory "web_nothreads_release.zip")
)
foreach ($template in $RequiredTemplates) {
    if (-not (Test-Path -LiteralPath $template -PathType Leaf)) {
        throw "Godot 4.6.2 Web export templates are missing. Install them from Editor > Manage Export Templates."
    }
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

Write-Host "Exporting Web build with $GodotExecutable"
& $GodotExecutable --headless --path $ProjectRoot --export-release "Web" $OutputFile
if ($LASTEXITCODE -ne 0) {
    throw "Web export failed. Review the Godot errors above and run this script again after correcting the project or preset configuration."
}

Write-Host "Web build created: $OutputFile"
