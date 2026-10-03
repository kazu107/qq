$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
[xml]$source = Get-Content -LiteralPath (Join-Path $root "assets\branding\queuequest-logo.svg") -Raw
$outputDirectory = Join-Path $root "assets\branding\loading"
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$parts = [ordered]@{
    "wordmark" = @("logo-word-queue", "logo-word-quest")
    "timeline" = @("logo-timeline")
    "card-back" = @("logo-card-back")
    "card-middle" = @("logo-card-middle")
    "card-front" = @("logo-card-front")
}

foreach ($entry in $parts.GetEnumerator()) {
    $document = New-Object System.Xml.XmlDocument
    $svg = $document.ImportNode($source.DocumentElement, $false)
    $svg.RemoveAttribute("aria-labelledby")
    $svg.RemoveAttribute("role")
    [void]$document.AppendChild($svg)
    $container = $svg
    if ($entry.Key -ne "wordmark") {
        $container = $document.ImportNode($source.SelectSingleNode('//*[@id="logo-mark"]'), $false)
        [void]$svg.AppendChild($container)
    }
    foreach ($id in $entry.Value) {
        $node = $source.SelectSingleNode('//*[@id="' + $id + '"]')
        if ($null -eq $node) { throw "Missing logo part: $id" }
        [void]$container.AppendChild($document.ImportNode($node, $true))
    }
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $settings.Indent = $true
    $settings.NewLineChars = "`n"
    $settings.OmitXmlDeclaration = $true
    $writer = [System.Xml.XmlWriter]::Create((Join-Path $outputDirectory ($entry.Key + ".svg")), $settings)
    try { $document.Save($writer) } finally { $writer.Dispose() }
}

# Inline the same SVG so the Web shell can animate its groups without fetching or duplicating artwork.
$logo = $source.DocumentElement.CloneNode($true)
$logo.SetAttribute("id", "status-logo-svg")
$shellPath = Join-Path $root "web\custom_shell.html"
$shell = [System.IO.File]::ReadAllText($shellPath).Replace("`r`n", "`n")
$pattern = '(?s)(<!-- QUEUEQUEST_LOADING_SVG_BEGIN -->).*?(<!-- QUEUEQUEST_LOADING_SVG_END -->)'
if (-not [regex]::IsMatch($shell, $pattern)) { throw "Loading SVG markers are missing from the Web shell" }
$replacement = '<!-- QUEUEQUEST_LOADING_SVG_BEGIN -->' + "`n" + $logo.OuterXml + "`n" + '<!-- QUEUEQUEST_LOADING_SVG_END -->'
$shell = [regex]::Replace($shell, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $replacement })
[System.IO.File]::WriteAllText($shellPath, $shell, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "LOADING_LOGO_ASSETS_OK"
