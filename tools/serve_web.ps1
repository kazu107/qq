param(
    [ValidateRange(1, 65535)]
    [int]$Port = 8060
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$WebDirectory = Join-Path $ProjectRoot "build\web"
$IndexFile = Join-Path $WebDirectory "index.html"

if (-not (Test-Path -LiteralPath $IndexFile -PathType Leaf)) {
    throw "Web build not found. Run tools\build_web.ps1 first."
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    $python = Get-Command py -ErrorAction SilentlyContinue
}
if (-not $python) {
    throw "Python was not found. Install Python or serve build\web with another static HTTP server."
}

Write-Host "Serving the game at http://127.0.0.1:$Port/"
Write-Host "Press Ctrl+C to stop the server."
& $python.Source -m http.server $Port --directory $WebDirectory
