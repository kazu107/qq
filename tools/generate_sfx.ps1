param(
    [string]$GeneratorPath = "K:\audio\gen_se.cmd",
    [string]$CatalogPath = "",
    [string]$AudioRoot = "",
    [int]$Steps = 25,
    [string]$ModelIds = "",
    [switch]$Force,
    [switch]$SkipModelGeneration,
    [switch]$SkipShared,
    [switch]$SkipCards,
    [switch]$SkipRelics,
    [switch]$SkipNormalization
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
    $CatalogPath = Join-Path $repoRoot "data\sfx_catalog.json"
}
if ([string]::IsNullOrWhiteSpace($AudioRoot)) {
    $AudioRoot = Join-Path $repoRoot "assets\audio\sfx"
}

$cardsPath = Join-Path $repoRoot "data\cards.json"
$relicsPath = Join-Path $repoRoot "data\relics.json"
$ffmpeg = (Get-Command ffmpeg -ErrorAction Stop).Source
$culture = [System.Globalization.CultureInfo]::InvariantCulture

if (-not (Test-Path -LiteralPath $GeneratorPath)) {
    throw "SFX generator was not found: $GeneratorPath"
}
if (-not (Test-Path -LiteralPath $CatalogPath)) {
    throw "SFX catalog was not found: $CatalogPath"
}

New-Item -ItemType Directory -Force -Path $AudioRoot | Out-Null
$decodedCatalog = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$catalog = @()
foreach ($decodedEntry in $decodedCatalog) {
    $catalog += $decodedEntry
}
$catalogById = @{}
foreach ($entry in $catalog) {
    $catalogById[[string]$entry.id] = $entry
}
$modelIdSet = @{}
foreach ($modelId in $ModelIds.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries)) {
    $normalizedModelId = $modelId.Trim()
    if ($normalizedModelId -ne "") {
        $modelIdSet[$normalizedModelId] = $true
    }
}

function Get-AudioPath([string]$id) {
    return Join-Path $AudioRoot "$id.wav"
}

function Get-AudioRelativePath([string]$id) {
    return Join-Path "assets\audio\sfx" "$id.wav"
}

function Test-ShouldWrite([string]$path) {
    return $Force -or -not (Test-Path -LiteralPath $path)
}

function Format-Number([double]$value) {
    return $value.ToString("0.######", $culture)
}

function Get-StableBytes([string]$value) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($value))
    }
    finally {
        $sha.Dispose()
    }
}

function Invoke-ModelGeneration($entry) {
    $outputPath = Get-AudioPath ([string]$entry.id)
    if (-not (Test-ShouldWrite $outputPath)) {
        Write-Host "[shared skip] $($entry.id)"
        return
    }

    $seconds = [double]$entry.seconds
    $seed = [int]$entry.seed
    $prompt = "$([string]$entry.prompt), pure non-vocal sound design, no human or synthetic voice, no speech-like syllables"
    Write-Host "[shared model] $($entry.id)"
    & $GeneratorPath $prompt $outputPath `
        --seconds (Format-Number $seconds) `
        --steps $Steps `
        --seed $seed `
        --cfg-scale 4.2 `
        --negative "human voice, synthetic voice, speech, spoken words, whispering, chanting, vocals, breathing, crowd, music, melody, narration, long ambience, excessive reverb, clipping"
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputPath)) {
        throw "Model generation failed: $($entry.id)"
    }
}

function Invoke-DerivedGeneration($entry) {
    $outputPath = Get-AudioPath ([string]$entry.id)
    if (-not (Test-ShouldWrite $outputPath)) {
        Write-Host "[shared skip] $($entry.id)"
        return
    }

    $sourcePath = Get-AudioPath ([string]$entry.source)
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Derived SFX source is missing: $($entry.source)"
    }

    $pitch = [double]$entry.pitch
    if ($pitch -le 0.0) {
        $pitch = 1.0
    }
    $tempo = 1.0 / $pitch
    $seconds = [double]$entry.seconds
    $fadeStart = [Math]::Max(0.0, $seconds - 0.05)
    $filters = @()
    if ($entry.PSObject.Properties.Name -contains "reverse" -and [bool]$entry.reverse) {
        $filters += "areverse"
    }
    if ([Math]::Abs($pitch - 1.0) -gt 0.0001) {
        $filters += "asetrate=48000*$(Format-Number $pitch)"
        $filters += "aresample=48000"
        $filters += "atempo=$(Format-Number $tempo)"
    }
    $filters += "atrim=0:$(Format-Number $seconds)"
    $filters += "afade=t=out:st=$(Format-Number $fadeStart):d=0.05"
    $filters += "alimiter=limit=0.9"

    Write-Host "[shared derive] $($entry.id) <- $($entry.source)"
    $ffmpegExitCode = 0
    Push-Location $repoRoot
    try {
        & $ffmpeg -hide_banner -loglevel error -y -i (Get-AudioRelativePath ([string]$entry.source)) `
            -filter:a ($filters -join ",") `
            -ar 48000 -ac 1 -c:a pcm_s16le (Get-AudioRelativePath ([string]$entry.id))
        $ffmpegExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    if ($ffmpegExitCode -ne 0 -or -not (Test-Path -LiteralPath $outputPath)) {
        throw "Derived generation failed: $($entry.id)"
    }
}

function Get-CardSourceIds($card) {
    $sources = [System.Collections.Generic.List[string]]::new()
    foreach ($effect in @($card.effects)) {
        $type = [string]$effect.type
        switch ($type) {
            "interrupt_card" { $sources.Add("battle_interrupt") }
            "deal_damage" {
                if ([int]$effect.amount -ge 10) {
                    $sources.Add("battle_attack_heavy")
                }
                else {
                    $sources.Add("battle_attack")
                }
            }
            "consume_shield" { $sources.Add("battle_shield_spend") }
            "gain_shield" { $sources.Add("battle_guard") }
            "heal" {
                if ([int]$effect.amount -ge 10) {
                    $sources.Add("battle_heal_big")
                }
                else {
                    $sources.Add("battle_heal")
                }
            }
            "delay_enemy_active_card" { $sources.Add("timeline_delay") }
            "haste_own_active_card" { $sources.Add("timeline_haste") }
            "reduce_recast" { $sources.Add("timeline_haste") }
            "auto_queue_card" { $sources.Add("timeline_auto_queue") }
            "timeline_flow" {
                $mode = [string]$effect.mode
                if ($mode -eq "reverse") {
                    $sources.Add("timeline_reverse")
                }
                elseif ($mode -eq "stop") {
                    $sources.Add("timeline_stop")
                }
                else {
                    $sources.Add("battle_time")
                }
            }
            "apply_status" {
                $status = [string]$effect.status
                switch ($status) {
                    "bleed" { $sources.Add("status_bleed_apply") }
                    "slow" { $sources.Add("status_slow_apply") }
                    "weak" { $sources.Add("status_weak_apply") }
                    "vulnerable" { $sources.Add("status_vulnerable_apply") }
                    default { $sources.Add("battle_status") }
                }
            }
            "remove_status" { $sources.Add("status_cleanse") }
            "modify_attack" {
                if ([double]$effect.amount -ge 0.0) {
                    $sources.Add("battle_buff")
                }
                else {
                    $sources.Add("battle_debuff")
                }
            }
            "modify_speed" {
                if ([double]$effect.amount -ge 0.0) {
                    $sources.Add("battle_buff")
                }
                else {
                    $sources.Add("battle_debuff")
                }
            }
            "empower_card" { $sources.Add("battle_buff") }
        }
    }
    if ($sources.Count -eq 0) {
        $sources.Add("card_commit")
    }
    return @($sources | Select-Object -Unique | Select-Object -First 2)
}

function Invoke-UniqueVariant(
    [string]$id,
    [string[]]$sourceIds,
    [double]$seconds
) {
    $outputPath = Get-AudioPath $id
    if (-not (Test-ShouldWrite $outputPath)) {
        Write-Host "[unique skip] $id"
        return
    }
    if ($sourceIds.Count -eq 0) {
        $sourceIds = @("relic_proc")
    }

    $stable = Get-StableBytes $id
    $pitch = 0.9 + ([double]$stable[0] / 255.0) * 0.2
    $tempo = 1.0 / $pitch
    $delayMs = 30 + ([int]$stable[1] % 100)
    $fadeStart = [Math]::Max(0.0, $seconds - 0.05)
    $pitchText = Format-Number $pitch
    $tempoText = Format-Number $tempo
    $secondsText = Format-Number $seconds
    $fadeText = Format-Number $fadeStart

    $primaryPath = Get-AudioPath $sourceIds[0]
    if (-not (Test-Path -LiteralPath $primaryPath)) {
        throw "Unique SFX source is missing: $($sourceIds[0])"
    }

    Write-Host "[unique] $id <- $($sourceIds -join '+')"
    $ffmpegExitCode = 0
    Push-Location $repoRoot
    try {
        if ($sourceIds.Count -eq 1) {
            $filter = "asetrate=48000*$pitchText,aresample=48000,atempo=$tempoText,atrim=0:$secondsText,afade=t=out:st=$fadeText`:d=0.05,alimiter=limit=0.9"
            & $ffmpeg -hide_banner -loglevel error -y -i (Get-AudioRelativePath $sourceIds[0]) `
                -filter:a $filter `
                -ar 48000 -ac 1 -c:a pcm_s16le (Get-AudioRelativePath $id)
        }
        else {
            $secondaryPath = Get-AudioPath $sourceIds[1]
            if (-not (Test-Path -LiteralPath $secondaryPath)) {
                throw "Unique SFX source is missing: $($sourceIds[1])"
            }
            $filter = "[0:a]asetrate=48000*$pitchText,aresample=48000,atempo=$tempoText,volume=0.82[p];" +
                "[1:a]adelay=$delayMs,volume=0.46[s];" +
                "[p][s]amix=inputs=2:duration=longest:normalize=0,atrim=0:$secondsText," +
                "afade=t=out:st=$fadeText`:d=0.05,alimiter=limit=0.88[out]"
            & $ffmpeg -hide_banner -loglevel error -y `
                -i (Get-AudioRelativePath $sourceIds[0]) -i (Get-AudioRelativePath $sourceIds[1]) `
                -filter_complex $filter -map "[out]" `
                -ar 48000 -ac 1 -c:a pcm_s16le (Get-AudioRelativePath $id)
        }
        $ffmpegExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    if ($ffmpegExitCode -ne 0 -or -not (Test-Path -LiteralPath $outputPath)) {
        throw "Unique SFX generation failed: $id"
    }
}

function Get-RelicSourceIds($relic) {
    $description = ([string]$relic.description).ToLowerInvariant()
    $sources = [System.Collections.Generic.List[string]]::new()
    if ($description -match "shield|barrier|armor|armour") { $sources.Add("battle_guard") }
    if ($description -match "gold|shop|price|reward") { $sources.Add("gold_gain") }
    if ($description -match "heal|recover|health|hp") { $sources.Add("battle_heal") }
    if ($description -match "cast|time|cooldown|recast|timeline|delay|haste|speed") { $sources.Add("battle_time") }
    if ($description -match "attack|damage|bleed") { $sources.Add("battle_attack") }
    if ($description -match "status|weak|slow|vulnerable") { $sources.Add("battle_status") }
    if ($description -match "slot|loadout|card") { $sources.Add("loadout_equip") }
    if ($sources.Count -eq 0) { $sources.Add("relic_proc") }
    return @($sources | Select-Object -Unique | Select-Object -First 2)
}

if (-not $SkipShared) {
    if (-not $SkipModelGeneration) {
        foreach ($entry in @($catalog | Where-Object { -not $_.source })) {
            if ($modelIdSet.Count -gt 0 -and -not $modelIdSet.ContainsKey([string]$entry.id)) {
                continue
            }
            Invoke-ModelGeneration $entry
        }
    }
    foreach ($entry in @($catalog | Where-Object { $_.source })) {
        Invoke-DerivedGeneration $entry
    }
}

if (-not $SkipCards) {
    $decodedCards = Get-Content -LiteralPath $cardsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $cards = @()
    foreach ($decodedCard in $decodedCards) {
        $cards += $decodedCard
    }
    foreach ($card in $cards) {
        Invoke-UniqueVariant "card_$($card.id)" @(Get-CardSourceIds $card) 1.15
    }
}

if (-not $SkipRelics) {
    $decodedRelics = Get-Content -LiteralPath $relicsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $relics = @()
    foreach ($decodedRelic in $decodedRelics) {
        $relics += $decodedRelic
    }
    foreach ($relic in $relics) {
        Invoke-UniqueVariant "relic_$($relic.id)" @(Get-RelicSourceIds $relic) 1.0
    }
}

$wavCount = @(Get-ChildItem -LiteralPath $AudioRoot -Filter "*.wav" -File).Count
if (-not $SkipNormalization) {
    Write-Host "[normalize] Matching SFX loudness"
    & node (Join-Path $PSScriptRoot "normalize_sfx.mjs")
    if ($LASTEXITCODE -ne 0) {
        throw "SFX normalization failed."
    }
}
Write-Host "SFX generation complete: $wavCount WAV files"
