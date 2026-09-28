BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Validator = Join-Path $PSScriptRoot '../tools/Test-TipFiles.ps1'
}

Describe 'Test-TipFiles.ps1' {
    It 'passes a well-formed fixture repository' {
        & pwsh -NoProfile -File $script:Validator -RepoRoot (New-FixtureOriginRepo)
        $LASTEXITCODE | Should -Be 0
    }

    It 'fails when a tip points at a command that does not exist' {
        $repo = New-FixtureOriginRepo
        $orphan = Join-Path $repo 'plugins/kros-shared/commands'
        New-Item -ItemType Directory -Path $orphan -Force | Out-Null
        ([pscustomobject]@{ title = 'Gone'; body = 'b'; repos = @('*') }) |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $orphan 'vanished.tip.json') -Encoding UTF8

        $output = & pwsh -NoProfile -File $script:Validator -RepoRoot $repo
        $LASTEXITCODE | Should -Be 1
        ($output -join "`n") | Should -Match 'vanished'
    }

    It 'fails a tip whose body is too long to fit a two-line notice' {
        $repo = New-FixtureOriginRepo
        $path = Join-Path $repo 'plugins/kros-shared/skills/git-diff/tip.json'
        ([pscustomobject]@{ title = 'T'; body = ('x' * 400); repos = @('*') }) |
            ConvertTo-Json | Set-Content -LiteralPath $path -Encoding UTF8

        & pwsh -NoProfile -File $script:Validator -RepoRoot $repo
        $LASTEXITCODE | Should -Be 1
    }
}
