<#
.SYNOPSIS
    Mirrors the FellowshipLedger addon folder into the game's AddOns folders.

.DESCRIPTION
    Copies ONLY <repo>\FellowshipLedger into <AddOns>\FellowshipLedger using
    robocopy /MIR on that one folder. Other addons are never touched.
    Refuses to run unless each destination ends in \Interface\AddOns and exists.

.PARAMETER Target
    Forever, Retail or Both (default Both).

.PARAMETER DryRun
    Show what would change without copying anything.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\sync.ps1 -DryRun
    powershell -ExecutionPolicy Bypass -File tools\sync.ps1 -Target Forever
#>
[CmdletBinding()]
param(
    [ValidateSet('Forever', 'Retail', 'Both')]
    [string]$Target = 'Both',
    [switch]$DryRun,
    # Alternate config file (used to test the safety checks).
    [string]$ConfigPath = ''
)

$ErrorActionPreference = 'Stop'
# $PSScriptRoot is empty inside param() defaults on Windows PowerShell 5.1, so resolve here.
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ConfigPath) { $ConfigPath = Join-Path $scriptDir 'sync.config.json' }
$repoRoot = Split-Path -Parent $scriptDir
$config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json

$addonName = $config.addonFolderName
if ($addonName -ne 'FellowshipLedger') {
    throw "Refusing to run: addonFolderName in sync.config.json must be 'FellowshipLedger' (got '$addonName')."
}

$source = Join-Path $repoRoot $config.source
if (-not (Test-Path -LiteralPath (Join-Path $source 'FellowshipLedger_Forever.toc'))) {
    throw "Source folder '$source' does not look like the addon (no FellowshipLedger_Forever.toc)."
}

$targets = if ($Target -eq 'Both') { @('Forever', 'Retail') } else { @($Target) }
$failed = $false

foreach ($name in $targets) {
    $addOns = $config.destinations.$name
    Write-Host ''
    Write-Host "=== $name ===" -ForegroundColor Cyan

    if (-not $addOns) {
        Write-Host "No destination configured for $name in sync.config.json. Skipped." -ForegroundColor Yellow
        $failed = $true
        continue
    }

    # Safety: destination must be an existing ...\Interface\AddOns folder.
    $normalized = $addOns.TrimEnd('\', '/')
    if ($normalized -notmatch '\\Interface\\AddOns$') {
        Write-Host "Refusing: '$addOns' does not end in \Interface\AddOns." -ForegroundColor Red
        $failed = $true
        continue
    }
    if (-not (Test-Path -LiteralPath $normalized -PathType Container)) {
        Write-Host "Refusing: '$normalized' does not exist. Create it yourself (or ask Claude) if this client is installed." -ForegroundColor Red
        $failed = $true
        continue
    }

    $dest = Join-Path $normalized $addonName
    # Belt and braces: the folder we mirror into must be exactly <AddOns>\FellowshipLedger.
    if ((Split-Path -Leaf $dest) -ne 'FellowshipLedger' -or (Split-Path -Parent $dest) -ne $normalized) {
        throw "Internal safety check failed for destination '$dest'."
    }

    Write-Host "From: $source"
    Write-Host "To:   $dest"
    if ($DryRun) { Write-Host '(dry run: nothing will be copied)' -ForegroundColor Yellow }

    # /MIR  mirror (copies new/changed, deletes files in dest that are not in source)
    # /L    list only (dry run)
    # /NJH /NJS /NDL /NP  quieter output; /FP full paths; /XJ skip junctions
    $robocopyArgs = @($source, $dest, '/MIR', '/XJ', '/FP', '/NJH', '/NJS', '/NDL', '/NP', '/R:1', '/W:1')
    if ($DryRun) { $robocopyArgs += '/L' }

    $output = & robocopy @robocopyArgs
    $code = $LASTEXITCODE

    $new = @(); $changed = @(); $removed = @()
    foreach ($line in $output) {
        $t = $line.Trim()
        if ($t -match '^(New File|Newer|Older|Changed|\*EXTRA File|Tweaked)\s+(?:[\d\.]+\s*[kmg]?\s+)?(.+)$') {
            $kind = $Matches[1]; $file = $Matches[2].Trim()
            $rel = $file.Replace($source, '').Replace($dest, '').TrimStart('\')
            switch -Regex ($kind) {
                '^New File' { $new += $rel }
                '^\*EXTRA' { $removed += $rel }
                default { $changed += $rel }
            }
        }
    }

    $verb = if ($DryRun) { 'would be' } else { '' }
    Write-Host ("New files {0}:     {1}" -f $verb, $new.Count)
    $new | ForEach-Object { Write-Host "  + $_" -ForegroundColor Green }
    Write-Host ("Changed files {0}: {1}" -f $verb, $changed.Count)
    $changed | ForEach-Object { Write-Host "  ~ $_" -ForegroundColor Yellow }
    Write-Host ("Removed files {0}: {1}" -f $verb, $removed.Count)
    $removed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }

    # Robocopy: 0-7 = success (bit flags), 8+ = failure.
    if ($code -ge 8) {
        Write-Host "robocopy failed with exit code $code" -ForegroundColor Red
        $output | Select-Object -Last 20 | ForEach-Object { Write-Host "  $_" }
        $failed = $true
    } elseif ($new.Count + $changed.Count + $removed.Count -eq 0) {
        Write-Host 'Already up to date.'
    }
}

Write-Host ''
if ($failed) { exit 1 } else { exit 0 }
