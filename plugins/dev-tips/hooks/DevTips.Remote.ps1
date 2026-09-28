#!/usr/bin/env pwsh
# Channel C: the authored tip files, read out of a shallow bare mirror. Nothing here is generated
# upstream - the source files are what the machine reads.

function Invoke-Git([string[]]$GitArgs)
{
    # Prompting must be impossible: a hidden process with no console would hang forever holding the
    # lock, and debug.log would never get a line because the script never reached one.
    $env:GIT_TERMINAL_PROMPT = '0'
    $out = & git -c credential.interactive=false -c core.askPass= @GitArgs 2>&1
    return [pscustomobject]@{ ok = ($LASTEXITCODE -eq 0); output = ($out -join "`n") }
}

function Invoke-MirrorFetch([string]$MirrorPath, [string]$Origin, [string]$Branch)
{
    if (-not (Test-Path -LiteralPath (Join-Path $MirrorPath 'HEAD')))
    {
        New-Item -ItemType Directory -Path $MirrorPath -Force | Out-Null
        $init = Invoke-Git @('-C', $MirrorPath, 'init', '--bare', '--quiet')
        if (-not $init.ok) { return $false }
        Invoke-Git @('-C', $MirrorPath, 'remote', 'add', 'origin', $Origin) | Out-Null
    }

    $fetch = Invoke-Git @('-C', $MirrorPath, 'fetch', '--depth', '1', 'origin', $Branch)
    return $fetch.ok
}

function Get-RemoteTipFiles([string]$MirrorPath)
{
    $list = Invoke-Git @('-C', $MirrorPath, 'ls-tree', '-r', '--name-only', 'FETCH_HEAD')
    if (-not $list.ok) { return @() }

    $wanted = @($list.output -split "`n" | Where-Object {
        $_ -match 'tip\.json$' -or $_ -match 'dev-tips/(manual|config)\.json$'
    })

    $files = @()
    foreach ($path in $wanted)
    {
        $clean = $path.Trim()
        $blob = Invoke-Git @('-C', $MirrorPath, 'show', "FETCH_HEAD:$clean")
        if (-not $blob.ok) { continue }
        $json = $null
        try { $json = $blob.output | ConvertFrom-Json } catch { continue }
        $files += [pscustomobject]@{ path = $clean; json = $json }
    }
    return $files
}

function ConvertTo-Tip([string]$Path, $Json, $Marketplace)
{
    $parts = $Path -split '/'
    $plugin = if ($parts.Length -gt 1 -and $parts[0] -eq 'plugins') { $parts[1] } else { $null }

    $name = if ($Path -match 'skills/([^/]+)/tip\.json$') { $Matches[1] }
            elseif ($Path -match 'commands/([^/]+)\.tip\.json$') { $Matches[1] }
            else { [System.IO.Path]::GetFileNameWithoutExtension($Path) }

    $tip = $Json | Select-Object *
    $tip | Add-Member -NotePropertyName id -NotePropertyValue $name -Force
    $tip | Add-Member -NotePropertyName ref -NotePropertyValue "/$name" -Force
    $tip | Add-Member -NotePropertyName source -NotePropertyValue 'remote' -Force
    if ($plugin)
    {
        $tip | Add-Member -NotePropertyName install `
                          -NotePropertyValue ([pscustomobject]@{ plugin = $plugin; marketplace = $Marketplace }) -Force
    }
    return $tip
}

function Write-RemoteSnapshot([string]$StateDir, [object[]]$Tips, $Config)
{
    $snapshot = [pscustomobject]@{
        fetchedAt = (Get-Date).ToUniversalTime().ToString('o')
        config    = $Config
        tips      = @($Tips)
    }

    # Temp file plus Move-Item: a direct write lets a SessionStart in another window read half a file.
    $final = Join-Path $StateDir 'remote-tips.json'
    $temp = "$final.$PID.tmp"
    $snapshot | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $final -Force
}

function Test-SnapshotStale([string]$StateDir, [int]$TtlHours)
{
    $path = Join-Path $StateDir 'remote-tips.json'
    if (-not (Test-Path -LiteralPath $path)) { return $true }
    $age = (Get-Date).ToUniversalTime() - (Get-Item -LiteralPath $path).LastWriteTimeUtc
    return ($age.TotalHours -ge $TtlHours)
}
