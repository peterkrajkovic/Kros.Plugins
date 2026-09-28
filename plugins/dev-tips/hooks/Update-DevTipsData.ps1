#!/usr/bin/env pwsh
# The detached refresh. Not a hook: it may exit non-zero, and nothing waits for it.
#
# -StateDir is mandatory and has NO fallback. Guessing it would write to a directory SessionStart
# does not read, and the failure would be invisible: the log would report success.
#
# Each job guards itself with its own stamp, so one failing job never blocks another.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$StateDir,
    [string]$ProjectsRoot,
    [int]$HistoryWindowDays = 90,
    [int]$HistoryTtlHours = 24,
    [int]$LockStaleMinutes = 30
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'DevTips.Common.ps1')
. (Join-Path $PSScriptRoot 'DevTips.History.ps1')

if (-not (Test-Path -LiteralPath $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
Initialize-Log $StateDir

if ([string]::IsNullOrWhiteSpace($ProjectsRoot))
{
    $userHome = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
    $ProjectsRoot = Join-Path $userHome '.claude/projects'
}

$lock = Join-Path $StateDir 'refresh.lock'
if (Test-Path -LiteralPath $lock)
{
    $age = (Get-Date).ToUniversalTime() - (Get-Item -LiteralPath $lock).LastWriteTimeUtc
    if ($age.TotalMinutes -lt $LockStaleMinutes)
    {
        Write-Log ('refresh: lock held, {0:N1} min old' -f $age.TotalMinutes)
        exit 2
    }
    Write-Log ('refresh: breaking stale lock, {0:N1} min old' -f $age.TotalMinutes)
    Remove-Item -LiteralPath $lock -Force
}

try
{
    $PID | Set-Content -LiteralPath $lock -Encoding UTF8

    if (Test-StampStale -StateDir $StateDir -Name 'history' -Hours $HistoryTtlHours)
    {
        try
        {
            $since = (Get-Date).ToUniversalTime().AddDays(-$HistoryWindowDays)
            $found = Get-HistoricalSkillUse -ProjectsRoot $ProjectsRoot -Since $since
            Merge-UsageFile -StateDir $StateDir -Found $found | Out-Null
            Update-Stamp -StateDir $StateDir -Name 'history'
            Write-Log ('refresh: history scanned | names={0}' -f $found.Keys.Count)
        }
        catch
        {
            Write-Log ('refresh: history scan failed | {0}' -f $_.Exception.Message)
        }
    }
    else
    {
        Write-Log 'refresh: history stamp fresh, skipped'
    }

    exit 0
}
catch
{
    Write-Log ("refresh ERROR: {0} | at {1}:{2}" -f $_.Exception.Message,
        $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber)
    exit 3
}
finally
{
    Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue
}
