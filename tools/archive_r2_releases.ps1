param(
    [Parameter(Mandatory = $true)]
    [string]$ArchiveRoot,
    [string]$BucketName = $env:R2_BUCKET_NAME,
    [string]$Endpoint = $env:R2_ENDPOINT,
    [string]$AccountId = $env:R2_ACCOUNT_ID,
    [string]$Profile = "",
    [ValidateRange(1, 100)]
    [int]$Keep = 3,
    [switch]$Prune,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if ($Prune -and $DryRun) {
    throw "-Prune and -DryRun cannot be used together."
}
if ([string]::IsNullOrWhiteSpace($BucketName)) {
    throw "Set R2_BUCKET_NAME or pass -BucketName."
}
if ([string]::IsNullOrWhiteSpace($Endpoint)) {
    if ([string]::IsNullOrWhiteSpace($AccountId)) {
        throw "Set R2_ENDPOINT/R2_ACCOUNT_ID or pass -Endpoint."
    }
    $Endpoint = "https://$AccountId.r2.cloudflarestorage.com"
}
if ($Prune -and $Keep -ne 3) {
    Write-Warning "Pruning with Keep=$Keep. The normal production policy is Keep=3."
}

$node = Get-Command node -ErrorAction Stop
$null = Get-Command aws -ErrorAction Stop
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$scriptPath = Join-Path $projectRoot "tools\archive_r2_releases.mjs"
$resolvedArchiveRoot = [IO.Path]::GetFullPath($ArchiveRoot)

$arguments = @(
    $scriptPath,
    "--bucket", $BucketName,
    "--endpoint", $Endpoint,
    "--archive-root", $resolvedArchiveRoot,
    "--keep", $Keep.ToString()
)
if (-not [string]::IsNullOrWhiteSpace($Profile)) {
    $arguments += @("--profile", $Profile)
}
if ($Prune) {
    $arguments += "--prune"
}
if ($DryRun) {
    $arguments += "--dry-run"
}

Write-Host "R2 archive root: $resolvedArchiveRoot"
Write-Host "R2 retention: latest $Keep releases"
Write-Host ("Mode: " + $(if ($DryRun) { "dry-run" } elseif ($Prune) { "archive and prune" } else { "archive only" }))
& $node.Source @arguments
if ($LASTEXITCODE -ne 0) {
    throw "R2 archive command failed with exit code $LASTEXITCODE."
}
