BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    . (Join-Path $PSScriptRoot '../hooks/DevTips.Common.ps1')
    . (Join-Path $PSScriptRoot '../hooks/DevTips.Catalog.ps1')
}

Describe 'Get-TipCatalog' {
    It 'returns the packaged tips and config' {
        $pluginRoot = New-FakePluginRoot -Tips @{ id = 'alpha'; title = 'A'; body = 'b'; repos = @('*') } `
                                        -Config @{ cooldownDays = 2 }
        $stateDir = New-TempDir

        $result = Get-TipCatalog -StateDir $stateDir -PluginRoot $pluginRoot -PluginsRoot (New-TempDir)

        $result.tips.Count | Should -Be 1
        $result.tips[0].id | Should -Be 'alpha'
        $result.config.cooldownDays | Should -Be 2
    }

    It 'returns an empty tip list rather than null when the catalog is missing' {
        $result = Get-TipCatalog -StateDir (New-TempDir) -PluginRoot (New-TempDir) -PluginsRoot (New-TempDir)

        ($result.tips -is [array]) | Should -BeTrue -Because 'callers foreach over it without a null check'
        $result.tips.Count | Should -Be 0
    }
}

Describe 'Merge-Tips' {
    It 'lets an authored tip override discovered copy for the same id' {
        $discovered = @([pscustomobject]@{ id = 'git-diff'; title = '/git-diff'; body = 'generated'; source = 'discovered' })
        $authored = @([pscustomobject]@{ id = 'git-diff'; title = 'Better title'; body = 'written by a human' })

        $merged = Merge-Tips -Authored $authored -Discovered $discovered

        @($merged).Count | Should -Be 1
        $merged[0].title | Should -Be 'Better title'
        $merged[0].body | Should -Be 'written by a human'
    }

    It 'keeps discovered tips that nobody has written copy for' {
        $discovered = @([pscustomobject]@{ id = 'teapie'; title = '/teapie'; body = 'generated' })
        $authored = @([pscustomobject]@{ id = 'commit'; title = '/commit'; body = 'written' })

        $merged = Merge-Tips -Authored $authored -Discovered $discovered

        @($merged).Count | Should -Be 2
        ($merged | Where-Object id -eq 'teapie').body | Should -Be 'generated'
    }
}
