param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath,
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [ValidateSet("lan", "online")]
    [string]$Scope = "lan"
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
    $transportArguments = if ($Scope -eq "online") { @("--online-transport-test-enet") } else { @() }
    $hostArguments = $baseArguments + $transportArguments + @("--lan-smoke-role=host", "--lan-smoke-port=$port", "--network-scope=$Scope", "--online-room-code=TEST42")
    $hostProcess = Start-Process -FilePath $GodotPath -ArgumentList $hostArguments -RedirectStandardOutput $hostOut -RedirectStandardError $hostErr -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 450
    $clientArguments = $baseArguments + $transportArguments + @("--lan-smoke-role=client", "--lan-smoke-port=$port", "--network-scope=$Scope", "--online-room-code=TEST42")
    $clientProcess = Start-Process -FilePath $GodotPath -ArgumentList $clientArguments -RedirectStandardOutput $clientOut -RedirectStandardError $clientErr -WindowStyle Hidden -PassThru

    $hostLog = ""
    $clientLog = ""
    $deadline = [DateTime]::UtcNow.AddSeconds(35)
    do {
        Start-Sleep -Milliseconds 100
        $hostLog = ((Get-Content -LiteralPath $hostOut -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content -LiteralPath $hostErr -Raw -ErrorAction SilentlyContinue)).Trim()
        $clientLog = ((Get-Content -LiteralPath $clientOut -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content -LiteralPath $clientErr -Raw -ErrorAction SilentlyContinue)).Trim()
        $completed = $hostLog -match "LAN_NETWORK_SMOKE_OK host" -and $clientLog -match "LAN_NETWORK_SMOKE_OK client"
        $failed = $hostLog -match "LAN_NETWORK_SMOKE_FAIL|SCRIPT ERROR:" -or $clientLog -match "LAN_NETWORK_SMOKE_FAIL|SCRIPT ERROR:"
    } while (-not $completed -and -not $failed -and [DateTime]::UtcNow -lt $deadline)
    if (-not $completed) {
        throw "$Scope peer smoke did not complete (hostExited=$($hostProcess.HasExited) clientExited=$($clientProcess.HasExited)).`nHOST:`n$hostLog`nCLIENT:`n$clientLog"
    }
    if ($hostLog -notmatch "LAN_NETWORK_SMOKE_OK host" -or $hostLog -match "LAN_NETWORK_SMOKE_FAIL") {
        throw "$Scope host peer failed.`n$hostLog"
    }
    if ($clientLog -notmatch "LAN_NETWORK_SMOKE_OK client" -or $clientLog -match "LAN_NETWORK_SMOKE_FAIL") {
        throw "$Scope client peer failed.`n$clientLog"
    }
    if ($hostLog -match "SCRIPT ERROR:" -or $clientLog -match "SCRIPT ERROR:") {
        throw "$Scope peer smoke reported a script error.`nHOST:`n$hostLog`nCLIENT:`n$clientLog"
    }
    Write-Host "$Scope two-peer smoke passed on UDP port $port."
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

exit 0
