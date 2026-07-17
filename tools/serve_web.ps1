param(
    [ValidateRange(1, 65535)]
    [int]$Port = 8060
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$IndexFile = Join-Path $ProjectRoot "build\web\index.html"

if (-not (Test-Path -LiteralPath $IndexFile -PathType Leaf)) {
    throw "Web build not found. Run tools\build_web.ps1 first."
}

$npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
if (-not $npm) {
    throw "npm.cmd was not found. Install Node.js 24 to run the Web game and signaling server."
}

Write-Host "Serving the game at http://127.0.0.1:$Port/"
Write-Host "WebRTC signaling endpoint: ws://127.0.0.1:$Port/signal"
Write-Host "Press Ctrl+C to stop the server."
$env:PORT = "$Port"
Push-Location $ProjectRoot
try {
    & $npm.Source start
}
finally {
    Pop-Location
}
