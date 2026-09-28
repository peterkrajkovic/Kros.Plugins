#!/usr/bin/env pwsh
# Shared helpers for the dev-tips hooks. Dot-sourced; defines no top-level side effects.

$script:LogPath = $null

function Get-PluginRoot
{
    if (-not [string]::IsNullOrWhiteSpace($env:CLAUDE_PLUGIN_ROOT)) { return $env:CLAUDE_PLUGIN_ROOT }
    return (Split-Path -Parent $PSScriptRoot)
}

function Get-StateDir
{
    if (-not [string]::IsNullOrWhiteSpace($env:CLAUDE_PLUGIN_DATA)) { $dir = $env:CLAUDE_PLUGIN_DATA }
    else
    {
        $userHome = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
        $dir = Join-Path $userHome '.claude/plugins/data/dev-tips-local'
    }
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Initialize-Log([string]$StateDir)
{
    $script:LogPath = Join-Path $StateDir 'debug.log'
}

function Write-Log([string]$Message)
{
    if (-not $script:LogPath) { return }
    try
    {
        if ((Test-Path -LiteralPath $script:LogPath) -and
            ((Get-Item -LiteralPath $script:LogPath).Length -gt 65536))
        {
            $keep = Get-Content -LiteralPath $script:LogPath -Tail 200 -Encoding UTF8
            Set-Content -LiteralPath $script:LogPath -Value $keep -Encoding UTF8
        }
        Add-Content -LiteralPath $script:LogPath -Encoding UTF8 -Value (
            '{0}  {1}' -f (Get-Date).ToUniversalTime().ToString('o'), $Message)
    }
    catch { }
}

function Read-JsonFile([string]$Path)
{
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return $raw | ConvertFrom-Json
}

function Write-JsonFile([string]$Path, $Value)
{
    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-SessionId($Payload)
{
    if ($null -ne $Payload -and -not [string]::IsNullOrWhiteSpace($Payload.session_id)) { return $Payload.session_id }
    if (-not [string]::IsNullOrWhiteSpace($env:CLAUDE_CODE_SESSION_ID)) { return $env:CLAUDE_CODE_SESSION_ID }
    return 'unknown'
}

function Get-RepoName
{
    $root = $env:CLAUDE_PROJECT_DIR
    if ([string]::IsNullOrWhiteSpace($root)) { $root = (Get-Location).Path }
    $top = & git -C $root rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($top)) { $root = $top.Trim() }
    return (Split-Path -Leaf $root)
}

function Test-RepoMatch($Tip, [string]$RepoName)
{
    foreach ($pattern in $Tip.repos)
    {
        if ($pattern -eq '*') { return $true }
        if ($RepoName -like "*$pattern*") { return $true }
    }
    return $false
}

function Get-InstallState($Tip)
{
    if ($null -eq $Tip.install) { return 'n/a' }

    $userHome = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
    $installed = Read-JsonFile (Join-Path $userHome '.claude/plugins/installed_plugins.json')
    $known = Read-JsonFile (Join-Path $userHome '.claude/plugins/known_marketplaces.json')

    $key = "$($Tip.install.plugin)@$($Tip.install.marketplace)"
    if ($null -ne $installed -and $null -ne $installed.plugins -and
        $null -ne $installed.plugins.PSObject.Properties[$key]) { return 'installed' }
    if ($null -ne $known -and $null -ne $known.PSObject.Properties[$Tip.install.marketplace]) { return 'marketplace-only' }
    return 'missing'
}

function Test-AlreadyUsed($Tip, [string]$StateDir)
{
    $key = $Tip.suppressIfUsed
    if ([string]::IsNullOrWhiteSpace($key)) { return $false }
    $usage = Read-JsonFile (Join-Path $StateDir 'usage.json')
    if ($null -eq $usage) { return $false }

    # A skill is invoked either bare ("git-diff") or plugin-qualified ("kros-shared:git-diff").
    foreach ($p in $usage.PSObject.Properties)
    {
        if ($p.Name -eq $key -or $p.Name -like "*:$key") { return $true }
    }
    return $false
}

function New-TipText($Tip, [string]$InstallState)
{
    $lines = @("💡 **$($Tip.title)** — $($Tip.body)")
    switch ($InstallState)
    {
        'installed' { if ($Tip.ref) { $lines += "Spúšťa sa cez ``$($Tip.ref)``." } }
        'marketplace-only' { $lines += "Nemáš ho nainštalovaný: ``/plugin install $($Tip.install.plugin)@$($Tip.install.marketplace)``" }
        'missing' { $lines += "Nemáš ani ten marketplace: ``/plugin marketplace add $($Tip.install.repo)``, potom ``/plugin install $($Tip.install.plugin)@$($Tip.install.marketplace)``" }
    }
    return ($lines -join "`n")
}

function New-Question($Tip, [string]$InstallState)
{
    switch ($InstallState)
    {
        'installed' { return 'Chceš, aby som ti ukázal, ako sa to používa?' }
        'marketplace-only' { return 'Mám ti ho pridať?' }
        'missing' { return 'Mám ti pridať marketplace aj plugin?' }
        default { return 'Chceš o tom vedieť viac?' }
    }
}

function New-ActionHint($Tip, [string]$InstallState)
{
    switch ($InstallState)
    {
        'installed' { return "vysvetli mu, na čo je ``$($Tip.ref)`` a ako sa používa" }
        'marketplace-only' { return "spusti ``claude plugin install $($Tip.install.plugin)@$($Tip.install.marketplace)``" }
        'missing' { return "spusti ``claude plugin marketplace add $($Tip.install.repo)`` a potom ``claude plugin install $($Tip.install.plugin)@$($Tip.install.marketplace)``" }
        default { return 'povedz mu k tomu viac' }
    }
}

function Test-IsDesktop
{
    return ($env:CLAUDE_CODE_ENTRYPOINT -eq 'claude-desktop') -or
        (-not [string]::IsNullOrWhiteSpace($env:CLAUDE_CODE_DESKTOP_APP_VERSION))
}

# Emits the hook JSON for one notice. The desktop app never renders `systemMessage`
# (see docs/desktop-systemmessage-not-rendered.md), so there the text has to travel
# through the model instead.
function Write-HookOutput([string]$EventName, [string]$UserMessage, [string]$Lead, [string]$ActionHint)
{
    if (Test-IsDesktop)
    {
        $context = @"
<dev-tip>
$Lead Vypíš nasledujúci blok DOSLOVA — bez preformulovania, bez úvodnej vety a bez komentára za ním.
Potom normálne pokračuj odpoveďou na to, čo používateľ napísal.

$UserMessage

Ak jeho správa odpovedá na tú otázku, vybav to: $ActionHint
Tip nesmie ovplyvniť tvoj postup pri jeho úlohe — nezačni kvôli nemu používať iný nástroj, ako by si
použil inak.
</dev-tip>
"@
        $output = [ordered]@{}
    }
    else
    {
        $context = @"
<dev-tip>
Používateľovi bol práve zobrazený tip ako systémová správa. NEOPAKUJ mu ho a nezačínaj ním odpoveď.
Ak jeho správa odpovedá na otázku v tom tipe, vybav to: $ActionHint
Inak ho úplne ignoruj. Nesmie ovplyvniť tvoj postup pri jeho úlohe.
</dev-tip>
"@
        $output = [ordered]@{ systemMessage = $UserMessage }
    }

    $output.hookSpecificOutput = [pscustomobject]@{
        hookEventName     = $EventName
        additionalContext = $context
    }
    [pscustomobject]$output | ConvertTo-Json -Depth 6 -Compress
}

function Test-StampStale([string]$StateDir, [string]$Name, [int]$Hours)
{
    $path = Join-Path $StateDir "$Name.stamp"
    if (-not (Test-Path -LiteralPath $path)) { return $true }
    $age = (Get-Date).ToUniversalTime() - (Get-Item -LiteralPath $path).LastWriteTimeUtc
    return ($age.TotalHours -ge $Hours)
}

function Update-Stamp([string]$StateDir, [string]$Name)
{
    (Get-Date).ToUniversalTime().ToString('o') |
        Set-Content -LiteralPath (Join-Path $StateDir "$Name.stamp") -Encoding UTF8
}

function Start-DataRefresh([string]$StateDir, [string]$HookRoot)
{
    # -WindowStyle Hidden, never -NoNewWindow: the child must not inherit the hook's stdout, which
    # Claude Code parses as JSON.
    Start-Process pwsh -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-File', (Join-Path $HookRoot 'Update-DevTipsData.ps1'),
        '-StateDir', $StateDir) | Out-Null
}
