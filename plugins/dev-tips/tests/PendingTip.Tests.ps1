BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    . (Join-Path $PSScriptRoot '../hooks/DevTips.Common.ps1')
    . (Join-Path $PSScriptRoot '../hooks/Write-PendingTip.ps1')
}

Describe 'Write-PendingTip' {
    It 'writes the fields the band draws, and nothing it cannot use' {
        $stateDir = New-TempDir
        $tip = [pscustomobject]@{
            id = 'az-pr'; kind = 'skill'; title = '/kros-shared:az-pr'
            body = 'Creates a pull request.'; ref = '/kros-shared:az-pr'; source = 'discovered'
        }

        Write-PendingTip -StateDir $stateDir -Tip $tip -InstallState 'installed'

        $pending = Get-Content -LiteralPath (Join-Path $stateDir 'pending.json') -Raw | ConvertFrom-Json
        $pending.id | Should -Be 'az-pr'
        $pending.ref | Should -Be '/kros-shared:az-pr'
        $pending.installState | Should -Be 'installed'
        $pending.source | Should -Be 'discovered'
        $pending.pickedAt | Should -Not -BeNullOrEmpty
        $pending.url | Should -BeNullOrEmpty
    }

    It 'carries a url when the tip has one' {
        $stateDir = New-TempDir
        $tip = [pscustomobject]@{
            id = 'pre-pr'; kind = 'rule'; title = 'T'; body = 'b'
            ref = 'docs/guidelines/pre-pr-verification.md'
            url = 'https://dev.azure.com/krossk/Esw/_git/Invoicing?path=/docs/guidelines/pre-pr-verification.md'
            source = 'repo'
        }

        Write-PendingTip -StateDir $stateDir -Tip $tip -InstallState 'n/a'

        $pending = Get-Content -LiteralPath (Join-Path $stateDir 'pending.json') -Raw | ConvertFrom-Json
        $pending.url | Should -Match '^https://'
        $pending.kind | Should -Be 'rule'
    }

    It 'defaults the fields an older tip may not carry' {
        $stateDir = New-TempDir

        Write-PendingTip -StateDir $stateDir -InstallState 'n/a' `
            -Tip ([pscustomobject]@{ id = 'x'; title = 't'; body = 'b' })

        $pending = Get-Content -LiteralPath (Join-Path $stateDir 'pending.json') -Raw | ConvertFrom-Json
        $pending.kind | Should -Be 'tip'
        $pending.source | Should -Be 'packaged'
    }

    It 'leaves no temp file behind' {
        $stateDir = New-TempDir

        Write-PendingTip -StateDir $stateDir -InstallState 'n/a' `
            -Tip ([pscustomobject]@{ id = 'x'; title = 't'; body = 'b' })

        @(Get-ChildItem -LiteralPath $stateDir -Filter '*.tmp').Count | Should -Be 0
    }
}
