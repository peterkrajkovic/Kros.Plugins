#!/usr/bin/env pwsh
# Channel A: tips about tools that are already on this machine. Needs no catalog and no network.

function Read-SkillFrontmatter([string]$Path)
{
    $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction SilentlyContinue)
    if ($lines.Count -eq 0 -or $lines[0].Trim() -ne '---') { return $null }

    $name = $null
    $description = $null
    for ($i = 1; $i -lt $lines.Count; $i++)
    {
        if ($lines[$i].Trim() -eq '---') { break }
        if ($lines[$i] -match '^name:\s*(.+)$') { $name = $Matches[1].Trim() }
        elseif ($lines[$i] -match '^description:\s*(.+)$') { $description = $Matches[1].Trim() }
    }

    if ([string]::IsNullOrWhiteSpace($name)) { return $null }
    return [pscustomobject]@{ name = $name; description = $description }
}

function Get-DiscoveredTips([string]$StateDir, [string]$PluginsRoot)
{
    $installed = Read-JsonFile (Join-Path $PluginsRoot 'installed_plugins.json')
    if ($null -eq $installed -or $null -eq $installed.plugins) { return @() }

    $tips = @()
    $seen = @{}

    foreach ($entry in $installed.plugins.PSObject.Properties)
    {
        $parts = $entry.Name -split '@', 2
        if ($parts.Count -ne 2) { continue }
        $pluginName = $parts[0]
        $marketplace = $parts[1]

        foreach ($install in @($entry.Value))
        {
            if ([string]::IsNullOrWhiteSpace($install.installPath)) { continue }
            $skillsDir = Join-Path $install.installPath 'skills'
            if (-not (Test-Path -LiteralPath $skillsDir)) { continue }

            foreach ($dir in Get-ChildItem -LiteralPath $skillsDir -Directory -ErrorAction SilentlyContinue)
            {
                $fm = Read-SkillFrontmatter (Join-Path $dir.FullName 'SKILL.md')
                if ($null -eq $fm) { continue }
                if ($seen.ContainsKey($fm.name)) { continue }
                $seen[$fm.name] = $true

                # What the developer types is the plugin-qualified form. The bare name is not
                # guaranteed to resolve, and telling somebody to run a command that does not exist
                # is worse than saying nothing. `id` and `suppressIfUsed` stay bare: ids are how
                # authored tips override discovered ones, and Test-AlreadyUsed matches either form.
                $qualified = "$pluginName`:$($fm.name)"

                $tip = [pscustomobject]@{
                    id             = $fm.name
                    kind           = 'skill'
                    title          = "/$qualified"
                    body           = $fm.description
                    ref            = "/$qualified"
                    repos          = @('*')
                    maxShows       = 3
                    suppressIfUsed = $fm.name
                    source         = 'discovered'
                    install        = [pscustomobject]@{ plugin = $pluginName; marketplace = $marketplace }
                }

                if (Test-AlreadyUsed $tip $StateDir) { continue }
                $tips += $tip
            }
        }
    }

    return $tips
}
