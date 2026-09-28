BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    . (Join-Path $PSScriptRoot '../hooks/DevTips.Common.ps1')
    . (Join-Path $PSScriptRoot '../hooks/DevTips.Discovery.ps1')
}

Describe 'Read-SkillFrontmatter' {
    It 'reads name and description' {
        $pluginsRoot = New-FakePluginsRoot
        $skill = Get-ChildItem -Path $pluginsRoot -Filter 'SKILL.md' -Recurse | Select-Object -First 1

        $fm = Read-SkillFrontmatter $skill.FullName

        $fm.name | Should -Be 'git-diff'
        $fm.description | Should -Be 'Analyze git changes against master.'
    }

    It 'returns null for a file with no frontmatter' {
        $path = Join-Path (New-TempDir) 'SKILL.md'
        'no frontmatter here' | Set-Content -LiteralPath $path -Encoding UTF8

        Read-SkillFrontmatter $path | Should -BeNullOrEmpty
    }
}

Describe 'Get-DiscoveredTips' {
    It 'produces a tip for an installed but unused skill' {
        $tips = Get-DiscoveredTips -StateDir (New-TempDir) -PluginsRoot (New-FakePluginsRoot)

        $tips.Count | Should -Be 1
        $tips[0].id | Should -Be 'git-diff'
        $tips[0].ref | Should -Be '/git-diff'
        $tips[0].kind | Should -Be 'skill'
        $tips[0].install.plugin | Should -Be 'kros-shared'
        $tips[0].install.marketplace | Should -Be 'kros-ai-dev-tools'
        $tips[0].body | Should -Match 'Analyze git changes'
    }

    It 'skips a skill the developer has already used' {
        $stateDir = New-TempDir
        ([pscustomobject]@{ 'kros-shared:git-diff' = '2026-09-01T00:00:00Z' }) |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stateDir 'usage.json') -Encoding UTF8

        $tips = Get-DiscoveredTips -StateDir $stateDir -PluginsRoot (New-FakePluginsRoot)

        @($tips).Count | Should -Be 0
    }
}
