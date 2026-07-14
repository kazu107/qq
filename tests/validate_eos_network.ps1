param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath,
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [string]$DevAuthUrl = "localhost:8081",
    [string]$HostCredential = "Player1",
    [string]$ClientCredential = "Player2",
    [int]$TimeoutSeconds = 90
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
if ($HostCredential -eq $ClientCredential) {
    throw "HostCredential and ClientCredential must use different Epic accounts."
}

$roomCode = "EOS" + (Get-Random -Minimum 100000 -Maximum 999999)
$stamp = [Guid]::NewGuid().ToString("N")
$hostOut = Join-Path $env:TEMP "qq-eos-host-$stamp.out.log"
$hostErr = Join-Path $env:TEMP "qq-eos-host-$stamp.err.log"
$clientOut = Join-Path $env:TEMP "qq-eos-client-$stamp.out.log"
$clientErr = Join-Path $env:TEMP "qq-eos-client-$stamp.err.log"
$scene = "res://tests/LanNetworkPeerSmoke.tscn"
$baseArguments = @(
    "--no-header",
    "--headless",
    "--path", $resolvedRoot,
    "--scene", $scene,
    "--"
)
$sharedArguments = @(
    "--network-scope=online",
    "--online-room-code=$roomCode",
    "--network-smoke-timeout=$TimeoutSeconds",
    "--eos-dev-auth-url=$DevAuthUrl"
)

$hostProcess = $null
$clientProcess = $null
try {
    $hostArguments = $baseArguments + $sharedArguments + @(
        "--lan-smoke-role=host",
        "--eos-dev-auth-token=$HostCredential"
    )
    $hostProcess = Start-Process -FilePath $resolvedGodotPath -ArgumentList $hostArguments -RedirectStandardOutput $hostOut -RedirectStandardError $hostErr -WindowStyle Hidden -PassThru

    $hostReadyDeadline = [DateTime]::UtcNow.AddSeconds([Math]::Min(45, $TimeoutSeconds))
    do {
        Start-Sleep -Milliseconds 200
        $hostLog = ((Get-Content -LiteralPath $hostOut -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content -LiteralPath $hostErr -Raw -ErrorAction SilentlyContinue)).Trim()
        $hostReady = $hostLog -match "EOS Relay lobby created"
        $hostFailed = $hostLog -match "LAN_NETWORK_SMOKE_FAIL|SCRIPT ERROR:|Epic account sign-in failed|EOS lobby operation failed"
    } while (-not $hostReady -and -not $hostFailed -and -not $hostProcess.HasExited -and [DateTime]::UtcNow -lt $hostReadyDeadline)
    if (-not $hostReady) {
        throw "EOS host lobby was not created. Confirm DevAuthTool is running and '$HostCredential' is signed in.`nHOST:`n$hostLog"
    }

    $clientArguments = $baseArguments + $sharedArguments + @(
        "--lan-smoke-role=client",
        "--eos-dev-auth-token=$ClientCredential"
    )
    $clientProcess = Start-Process -FilePath $resolvedGodotPath -ArgumentList $clientArguments -RedirectStandardOutput $clientOut -RedirectStandardError $clientErr -WindowStyle Hidden -PassThru

    $hostLog = ""
    $clientLog = ""
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 200
        $hostLog = ((Get-Content -LiteralPath $hostOut -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content -LiteralPath $hostErr -Raw -ErrorAction SilentlyContinue)).Trim()
        $clientLog = ((Get-Content -LiteralPath $clientOut -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content -LiteralPath $clientErr -Raw -ErrorAction SilentlyContinue)).Trim()
        $completed = $hostLog -match "LAN_NETWORK_SMOKE_OK host" -and $clientLog -match "LAN_NETWORK_SMOKE_OK client"
        $failed = $hostLog -match "LAN_NETWORK_SMOKE_FAIL|SCRIPT ERROR:" -or $clientLog -match "LAN_NETWORK_SMOKE_FAIL|SCRIPT ERROR:"
    } while (-not $completed -and -not $failed -and [DateTime]::UtcNow -lt $deadline)

    if (-not $completed) {
        throw "EOS Relay peer smoke did not complete (hostExited=$($hostProcess.HasExited) clientExited=$($clientProcess.HasExited)).`nHOST:`n$hostLog`nCLIENT:`n$clientLog"
    }
    Write-Host "EOS Relay two-peer smoke passed with two Epic accounts."
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
            Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
        }
    }
}

exit 0
