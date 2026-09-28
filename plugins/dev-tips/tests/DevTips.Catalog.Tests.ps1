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

        $result = Get-TipCatalog -StateDir $stateDir -PluginRoot $pluginRoot

        $result.tips.Count | Should -Be 1
        $result.tips[0].id | Should -Be 'alpha'
        $result.config.cooldownDays | Should -Be 2
    }

    It 'returns an empty tip list rather than null when the catalog is missing' {
        $result = Get-TipCatalog -StateDir (New-TempDir) -PluginRoot (New-TempDir)

        ($result.tips -is [array]) | Should -BeTrue -Because 'callers foreach over it without a null check'
        $result.tips.Count | Should -Be 0
    }
}
