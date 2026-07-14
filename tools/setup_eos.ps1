param(
    [Parameter(Mandatory = $true)]
    [string]$SdkPath,

    [string]$Root = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
}
$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$resolvedSdk = (Resolve-Path -LiteralPath $SdkPath).Path
$sdkDirectory = if ((Split-Path -Leaf $resolvedSdk) -eq "SDK") {
    $resolvedSdk
} else {
    Join-Path $resolvedSdk "SDK"
}

$runtimeSource = Join-Path $sdkDirectory "Bin\EOSSDK-Win64-Shipping.dll"
$xaudioSource = Join-Path $sdkDirectory "Bin\x64\xaudio2_9redist.dll"
if (-not (Test-Path -LiteralPath $runtimeSource)) {
    throw "EOSSDK-Win64-Shipping.dll was not found under '$sdkDirectory'."
}
if (-not (Test-Path -LiteralPath $xaudioSource)) {
    throw "xaudio2_9redist.dll was not found under '$sdkDirectory'."
}

$pluginDirectory = Join-Path $resolvedRoot "addons\gd-eos"
$windowsDirectory = Join-Path $pluginDirectory "bin\windows"
$xaudioDirectory = Join-Path $windowsDirectory "x64"
$extensionPath = Join-Path $pluginDirectory "gd-eos.gdextension"
$debugLibrary = Join-Path $windowsDirectory "libgdeos.windows.template_debug.x86_64.dll"
$releaseLibrary = Join-Path $windowsDirectory "libgdeos.windows.template_release.x86_64.dll"

foreach ($requiredPath in @($extensionPath, $debugLibrary, $releaseLibrary)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "The committed GD-EOS plugin is incomplete: '$requiredPath' is missing."
    }
}

New-Item -ItemType Directory -Path $xaudioDirectory -Force | Out-Null
Copy-Item -LiteralPath $runtimeSource -Destination (Join-Path $windowsDirectory "EOSSDK-Win64-Shipping.dll") -Force
Copy-Item -LiteralPath $xaudioSource -Destination (Join-Path $xaudioDirectory "xaudio2_9redist.dll") -Force

Write-Host "EOS runtime installed from: $sdkDirectory"
Write-Host "Next: run tools/configure_eos_credentials.ps1 and enter the client secret."
