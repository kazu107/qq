param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath,
    [Parameter(Mandatory = $true)]
    [string]$Root
)

$ErrorActionPreference = "Stop"
$port = Get-Random -Minimum 37000 -Maximum 44000
$stamp = [Guid]::NewGuid().ToString("N")
$hostOut = Join-Path $env:TEMP "qq-lan-host-$stamp.out.log"
$hostErr = Join-Path $env:TEMP "qq-lan-host-$stamp.err.log"
$clientOut = Join-Path $env:TEMP "qq-lan-client-$stamp.out.log"
$clientErr = Join-Path $env:TEMP "qq-lan-client-$stamp.err.log"
$scene = "res://tests/LanNetworkPeerSmoke.tscn"
$baseArguments = @(
    "--no-header",
    "--headless",
    "--path", $Root,
    "--scene", $scene,
    "--"
)

$hostProcess = $null
$clientProcess = $null
try {
    $hostArguments = $baseArguments + @("--lan-smoke-role=host", "--lan-smoke-port=$port")
    $hostProcess = Start-Process -FilePath $GodotPath -ArgumentList $hostArguments -RedirectStandardOutput $hostOut -RedirectStandardError $hostErr -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 450
    $clientArguments = $baseArguments + @("--lan-smoke-role=client", "--lan-smoke-port=$port")
    $clientProcess = Start-Process -FilePath $GodotPath -ArgumentList $clientArguments -RedirectStandardOutput $clientOut -RedirectStandardError $clientErr -WindowStyle Hidden -PassThru

    $clientFinished = $clientProcess.WaitForExit(20000)
    $hostFinished = $hostProcess.WaitForExit(20000)
    if (-not $clientFinished -or -not $hostFinished) {
        throw "LAN peer smoke timed out (host=$hostFinished client=$clientFinished)."
    }
    $hostLog = ((Get-Content -LiteralPath $hostOut -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content -LiteralPath $hostErr -Raw -ErrorAction SilentlyContinue)).Trim()
    $clientLog = ((Get-Content -LiteralPath $clientOut -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content -LiteralPath $clientErr -Raw -ErrorAction SilentlyContinue)).Trim()
    if ($hostLog -notmatch "LAN_NETWORK_SMOKE_OK host" -or $hostLog -match "LAN_NETWORK_SMOKE_FAIL") {
        throw "LAN host peer failed.`n$hostLog"
    }
    if ($clientLog -notmatch "LAN_NETWORK_SMOKE_OK client" -or $clientLog -match "LAN_NETWORK_SMOKE_FAIL") {
        throw "LAN client peer failed.`n$clientLog"
    }
    if ($hostLog -match "SCRIPT ERROR:" -or $clientLog -match "SCRIPT ERROR:") {
        throw "LAN peer smoke reported a script error.`nHOST:`n$hostLog`nCLIENT:`n$clientLog"
    }
    Write-Host "LAN two-peer smoke passed on UDP port $port."
}
finally {
    if ($hostProcess -and -not $hostProcess.HasExited) {
        Stop-Process -Id $hostProcess.Id -Force
    }
    if ($clientProcess -and -not $clientProcess.HasExited) {
        Stop-Process -Id $clientProcess.Id -Force
    }
    foreach ($logPath in @($hostOut, $hostErr, $clientOut, $clientErr)) {
        if (Test-Path -LiteralPath $logPath) {
            Remove-Item -LiteralPath $logPath -Force
        }
    }
}
