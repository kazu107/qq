param(
    [string]$Root = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
}
$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$secureSecret = Read-Host "EOS Client Secret" -AsSecureString
$secretPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureSecret)
try {
    $plainSecret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($secretPointer)
    if ([string]::IsNullOrWhiteSpace($plainSecret)) {
        throw "Client Secret cannot be empty."
    }
    $escapedSecret = $plainSecret.Replace("\\", "\\\\").Replace('"', '\"')
    $target = Join-Path $resolvedRoot "config\eos_credentials.local.cfg"
    $contents = @(
        "[eos]"
        ""
        "client_secret=`"$escapedSecret`""
    ) -join "`n"
    [IO.File]::WriteAllText($target, $contents + "`n", [Text.UTF8Encoding]::new($false))
    Write-Host "Saved local EOS credentials to: $target"
} finally {
    if ($secretPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretPointer)
    }
    $plainSecret = $null
}
