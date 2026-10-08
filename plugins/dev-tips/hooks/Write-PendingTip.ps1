#!/usr/bin/env pwsh
# The selected tip as data for the band to draw. The band renders and takes the answer;
# it never decides which tip that is. Cooldown, maxShows, suppression and source ranking
# stay here, in one place, whichever surface ends up showing the result.

function Write-PendingTip([string]$StateDir, $Tip, [string]$InstallState)
{
    $pending = [pscustomobject]@{
        id           = $Tip.id
        kind         = if ($Tip.kind) { $Tip.kind } else { 'tip' }
        title        = $Tip.title
        body         = $Tip.body
        ref          = $Tip.ref
        url          = $Tip.url
        source       = if ($Tip.source) { $Tip.source } else { 'packaged' }
        installState = $InstallState
        pickedAt     = (Get-Date).ToUniversalTime().ToString('o')
    }

    # Temp plus move: the band may be reading this while SessionStart is still writing it.
    $final = Join-Path $StateDir 'pending.json'
    $temp = "$final.$PID.tmp"
    $pending | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $final -Force
}
