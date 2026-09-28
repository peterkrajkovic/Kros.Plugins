BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Script = Join-Path $PSScriptRoot '../hooks/Update-DevTipsData.ps1'
}

Describe 'Update-DevTipsData.ps1' {
    It 'backfills usage.json from the transcripts' {
        $stateDir = New-TempDir

        & pwsh -NoProfile -File $script:Script -StateDir $stateDir -ProjectsRoot (New-FakeTranscripts)
        $LASTEXITCODE | Should -Be 0

        $usage = Get-Content -LiteralPath (Join-Path $stateDir 'usage.json') -Raw | ConvertFrom-Json
        $usage.'git-diff' | Should -Not -BeNullOrEmpty
    }

    It 'refuses to guess the state directory' {
        & pwsh -NoProfile -File $script:Script -ProjectsRoot (New-FakeTranscripts)
        $LASTEXITCODE | Should -Be 1
    }

    It 'bails out when another run holds the lock' {
        $stateDir = New-TempDir
        'held' | Set-Content -LiteralPath (Join-Path $stateDir 'refresh.lock') -Encoding UTF8

        & pwsh -NoProfile -File $script:Script -StateDir $stateDir -ProjectsRoot (New-FakeTranscripts)
        $LASTEXITCODE | Should -Be 2
    }

    It 'breaks a stale lock' {
        $stateDir = New-TempDir
        $lock = Join-Path $stateDir 'refresh.lock'
        'held' | Set-Content -LiteralPath $lock -Encoding UTF8
        (Get-Item -LiteralPath $lock).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddHours(-2)

        & pwsh -NoProfile -File $script:Script -StateDir $stateDir -ProjectsRoot (New-FakeTranscripts)
        $LASTEXITCODE | Should -Be 0
    }

    It 'skips the scan when the history stamp is fresh' {
        $stateDir = New-TempDir
        (Get-Date).ToUniversalTime().ToString('o') |
            Set-Content -LiteralPath (Join-Path $stateDir 'history.stamp') -Encoding UTF8

        & pwsh -NoProfile -File $script:Script -StateDir $stateDir -ProjectsRoot (New-FakeTranscripts)
        $LASTEXITCODE | Should -Be 0
        Test-Path -LiteralPath (Join-Path $stateDir 'usage.json') | Should -BeFalse
    }
}
