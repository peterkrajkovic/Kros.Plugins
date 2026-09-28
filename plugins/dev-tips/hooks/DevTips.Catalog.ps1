#!/usr/bin/env pwsh
# The one place tips come from. Hooks must not read catalog files directly.

function Get-TipCatalog([string]$StateDir, [string]$PluginRoot)
{
    if ([string]::IsNullOrWhiteSpace($PluginRoot)) { $PluginRoot = Get-PluginRoot }

    $packaged = Read-JsonFile (Join-Path $PluginRoot 'catalog/tips.json')
    $tips = @()
    if ($null -ne $packaged -and $null -ne $packaged.tips) { $tips = @($packaged.tips) }

    $config = Read-JsonFile (Join-Path $PluginRoot 'catalog/config.json')
    if ($null -eq $config) { $config = [pscustomobject]@{} }

    return [pscustomobject]@{ tips = $tips; config = $config }
}
