param(
    [Parameter(Mandatory = $true)]
    [string]$SdkPath,
    [string]$Root = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
}
$Root = (Resolve-Path -LiteralPath $Root).Path
$resolvedSdkPath = (Resolve-Path -LiteralPath $SdkPath).Path
$sdkDirectory = if (Test-Path -LiteralPath (Join-Path $resolvedSdkPath "SDK") -PathType Container) {
    Join-Path $resolvedSdkPath "SDK"
}
else {
    $resolvedSdkPath
}

$archivePath = Join-Path $sdkDirectory "Tools\EOS_DevAuthTool-win32-x64-1.2.1.zip"
if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    throw "EOS DevAuthTool archive was not found: $archivePath"
}

$installDirectory = Join-Path $Root "tools\.local\eos-dev-auth-1.2.1"
$executablePath = Join-Path $installDirectory "EOS_DevAuthTool.exe"
if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
    New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
    Expand-Archive -LiteralPath $archivePath -DestinationPath $installDirectory -Force
}
if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
    throw "EOS DevAuthTool could not be extracted: $executablePath"
}

Start-Process -FilePath $executablePath -WorkingDirectory $installDirectory
Write-Host "EOS DevAuthTool started."
Write-Host "Set the port to 8081, then create credentials named Player1 and Player2."
Write-Host "Each credential must sign in with a different Epic account before running tests\validate_eos_network.ps1."
