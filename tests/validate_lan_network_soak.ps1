param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath,
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [int]$DurationSeconds = 35
)

$ErrorActionPreference = "Stop"
$duration = [Math]::Max(5, $DurationSeconds)
$timeoutMilliseconds = ($duration + 20) * 1000
$port = Get-Random -Minimum 44001 -Maximum 51000
$stamp = [Guid]::NewGuid().ToString("N")
$hostOut = Join-Path $env:TEMP "qq-lan-soak-host-$stamp.out.log"
$hostErr = Join-Path $env:TEMP "qq-lan-soak-host-$stamp.err.log"
$clientOut = Join-Path $env:TEMP "qq-lan-soak-client-$stamp.out.log"
$clientErr = Join-Path $env:TEMP "qq-lan-soak-client-$stamp.err.log"
$scene = "res://tests/LanNetworkSoakPeer.tscn"
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
    $hostArguments = $baseArguments + @(
        "--lan-soak-role=host",
        "--lan-soak-port=$port",
        "--lan-soak-seconds=$duration"
    )
    $hostProcess = Start-Process -FilePath $GodotPath -ArgumentList $hostArguments -RedirectStandardOutput $hostOut -RedirectStandardError $hostErr -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 1000
    $clientArguments = $baseArguments + @(
        "--lan-soak-role=client",
        "--lan-soak-port=$port",
        "--lan-soak-seconds=$duration"
    )
    $clientProcess = Start-Process -FilePath $GodotPath -ArgumentList $clientArguments -RedirectStandardOutput $clientOut -RedirectStandardError $clientErr -WindowStyle Hidden -PassThru

    $hostLog = ""
    $clientLog = ""
    $deadline = [DateTime]::UtcNow.AddMilliseconds($timeoutMilliseconds)
    do {
        Start-Sleep -Milliseconds 100
        $hostLog = ((Get-Content -LiteralPath $hostOut -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content -LiteralPath $hostErr -Raw -ErrorAction SilentlyContinue)).Trim()
        $clientLog = ((Get-Content -LiteralPath $clientOut -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content -LiteralPath $clientErr -Raw -ErrorAction SilentlyContinue)).Trim()
        $completed = $hostLog -match "LAN_NETWORK_SOAK_OK host" -and $clientLog -match "LAN_NETWORK_SOAK_OK client"
        $failed = $hostLog -match "LAN_NETWORK_SOAK_FAIL|SCRIPT ERROR:" -or $clientLog -match "LAN_NETWORK_SOAK_FAIL|SCRIPT ERROR:"
    } while (-not $completed -and -not $failed -and [DateTime]::UtcNow -lt $deadline)
    if (-not $completed) {
        throw "LAN network soak did not complete (hostExited=$($hostProcess.HasExited) clientExited=$($clientProcess.HasExited) duration=${duration}s).`nHOST:`n$hostLog`nCLIENT:`n$clientLog"
    }
    if ($hostLog -notmatch "LAN_NETWORK_SOAK_OK host" -or $hostLog -match "LAN_NETWORK_SOAK_FAIL") {
        throw "LAN soak host failed.`n$hostLog"
    }
    if ($clientLog -notmatch "LAN_NETWORK_SOAK_OK client" -or $clientLog -match "LAN_NETWORK_SOAK_FAIL") {
        throw "LAN soak client failed.`n$clientLog"
    }
    if ($hostLog -match "SCRIPT ERROR:" -or $clientLog -match "SCRIPT ERROR:") {
        throw "LAN soak reported a script error.`nHOST:`n$hostLog`nCLIENT:`n$clientLog"
    }
    Write-Host "LAN sustained network soak passed for ${duration}s on UDP port $port."
    Write-Host ($hostLog -split "`n" | Where-Object { $_ -match "LAN_NETWORK_SOAK_OK host" })
    Write-Host ($clientLog -split "`n" | Where-Object { $_ -match "LAN_NETWORK_SOAK_OK client" })
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
            for ($attempt = 0; $attempt -lt 10; $attempt++) {
                try {
                    Remove-Item -LiteralPath $logPath -Force -ErrorAction Stop
                    break
                }
                catch {
                    if ($attempt -eq 9) {
                        throw
                    }
                    Start-Sleep -Milliseconds 100
                }
            }
        }
    }
}
