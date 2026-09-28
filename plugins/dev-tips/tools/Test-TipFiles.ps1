#!/usr/bin/env pwsh
# Runs in CI on pull requests in Kros.AiDevTools. The check that earns its keep is the last one:
# a tip pointing at a renamed command is worse than no tip, and only people who do not know the
# tool ever read it, so nobody else would catch it.

[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$RepoRoot)

$problems = @()
$ids = @{}
$maxTitle = 80
$maxBody = 240

$files = @(Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'tip.json' -or $_.Name -like '*.tip.json' })

foreach ($file in $files)
{
    $relative = $file.FullName.Substring($RepoRoot.Length).TrimStart('\', '/') -replace '\\', '/'

    $tip = $null
    try { $tip = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { $problems += "$relative : not valid JSON"; continue }

    foreach ($field in @('title', 'body', 'repos'))
    {
        if ($null -eq $tip.$field) { $problems += "$relative : missing required field '$field'" }
    }
    if ($tip.title -and $tip.title.Length -gt $maxTitle) { $problems += "$relative : title over $maxTitle chars" }
    if ($tip.body -and $tip.body.Length -gt $maxBody) { $problems += "$relative : body over $maxBody chars" }

    if ($file.Name -eq 'tip.json')
    {
        $id = Split-Path -Leaf (Split-Path -Parent $file.FullName)
        $target = Join-Path (Split-Path -Parent $file.FullName) 'SKILL.md'
    }
    else
    {
        $id = $file.Name -replace '\.tip\.json$', ''
        $target = Join-Path (Split-Path -Parent $file.FullName) "$id.md"
    }

    if (-not (Test-Path -LiteralPath $target)) { $problems += "$relative : no tool at $id - renamed or deleted?" }
    if ($ids.ContainsKey($id)) { $problems += "$relative : duplicate id '$id', also in $($ids[$id])" }
    $ids[$id] = $relative
}

if ($problems.Count -gt 0)
{
    $problems | ForEach-Object { Write-Output $_ }
    exit 1
}

Write-Output "dev-tips: $($files.Count) tip file(s) valid"
exit 0
