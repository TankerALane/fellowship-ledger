<#
.SYNOPSIS
    Runs the pure-Lua unit tests in tests/ with Lua 5.1 or LuaJIT (WoW uses Lua 5.1).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

# Interpreters that speak Lua 5.1 semantics (setfenv, unpack). Lua 5.2+ will not work.
$candidates = @('luajit', 'lua5.1', 'lua51', 'lua')
$lua = $null
foreach ($name in $candidates) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if (-not $cmd) { continue }
    $versionText = (& $cmd.Source -v 2>&1 | Out-String).Trim()
    if ($versionText -match 'LuaJIT' -or $versionText -match 'Lua 5\.1') {
        $lua = $cmd.Source
        Write-Host "Using $versionText ($lua)"
        break
    }
    Write-Host "Skipping $name ($versionText): need Lua 5.1 or LuaJIT."
}

if (-not $lua) {
    Write-Host 'No Lua 5.1 or LuaJIT interpreter found on PATH.' -ForegroundColor Red
    Write-Host 'Install one, for example: winget install --id DEVCOM.LuaJIT'
    exit 2
}

Push-Location $repoRoot
try {
    & $lua 'tests/run_all.lua'
    $code = $LASTEXITCODE
} finally {
    Pop-Location
}
exit $code
