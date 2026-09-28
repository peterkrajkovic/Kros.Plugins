#!/usr/bin/env pwsh
# The one place tips come from. Hooks must not read catalog files directly.

. (Join-Path $PSScriptRoot 'DevTips.Discovery.ps1')

function Merge-Tips([object[]]$Authored, [object[]]$Discovered)
{
    $byId = [ordered]@{}
    foreach ($tip in @($Discovered)) { if ($null -ne $tip) { $byId[$tip.id] = $tip } }
    foreach ($tip in @($Authored)) { if ($null -ne $tip) { $byId[$tip.id] = $tip } }

    # The comma is load-bearing: returning @() unrolls to nothing, and the caller's property
    # becomes $null instead of an empty array.
    return ,@($byId.Values)
}

function Get-TipCatalog([string]$StateDir, [string]$PluginRoot, [string]$PluginsRoot)
{
    if ([string]::IsNullOrWhiteSpace($PluginRoot)) { $PluginRoot = Get-PluginRoot }

    # Injectable so a test never reads the real profile; defaulted so hooks need not know the path.
    if ([string]::IsNullOrWhiteSpace($PluginsRoot))
    {
        $userHome = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
        $PluginsRoot = Join-Path $userHome '.claude/plugins'
    }

    $packaged = Read-JsonFile (Join-Path $PluginRoot 'catalog/tips.json')
    $tips = @()
    if ($null -ne $packaged -and $null -ne $packaged.tips) { $tips = @($packaged.tips) }

    $config = Read-JsonFile (Join-Path $PluginRoot 'catalog/config.json')
    if ($null -eq $config) { $config = [pscustomobject]@{} }

    $discovered = @()
    try { $discovered = Get-DiscoveredTips -StateDir $StateDir -PluginsRoot $PluginsRoot } catch { }

    return [pscustomobject]@{ tips = (Merge-Tips -Authored $tips -Discovered $discovered); config = $config }
}
