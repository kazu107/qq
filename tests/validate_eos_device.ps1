param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath,
    [Parameter(Mandatory = $true)]
    [string]$Root
)

$ErrorActionPreference = "Stop"
$resolvedGodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$runtimePath = Join-Path $resolvedRoot "addons\gd-eos\bin\windows\EOSSDK-Win64-Shipping.dll"
$credentialsPath = Join-Path $resolvedRoot "config\eos_credentials.local.cfg"
if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
    throw "EOS runtime is missing. Run tools\setup_eos.ps1 first."
}
if (-not (Test-Path -LiteralPath $credentialsPath -PathType Leaf)) {
    throw "EOS credentials are missing. Run tools\configure_eos_credentials.ps1 first."
}

$stamp = [Guid]::NewGuid().ToString("N")
$stdoutPath = Join-Path $env:TEMP "qq-eos-device-$stamp.out.log"
$stderrPath = Join-Path $env:TEMP "qq-eos-device-$stamp.err.log"
try {
    $arguments = @(
        "--no-header",
        "--headless",
        "--path", $resolvedRoot,
        "--scene", "res://tests/EosDeviceAuthSmoke.tscn"
    )
    $process = Start-Process `
        -FilePath $resolvedGodotPath `
        -ArgumentList $arguments `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -WindowStyle Hidden `
        -Wait `
        -PassThru
    $output = ((Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue) + "`n" +
        (Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue)).Trim()
    $exitCode = $process.ExitCode
    if ($exitCode -ne 0 -or $output -notmatch "EOS_DEVICE_AUTH_SMOKE_OK") {
        throw "EOS anonymous Device ID smoke failed.`n$output"
    }

    Write-Host $output
}
finally {
    Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
}
