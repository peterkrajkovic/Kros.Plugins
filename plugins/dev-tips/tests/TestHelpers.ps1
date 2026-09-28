function New-TempDir
{
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('devtips-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function New-FakePluginRoot([hashtable]$Tips, [hashtable]$Config)
{
    $root = New-TempDir
    New-Item -ItemType Directory -Path (Join-Path $root 'catalog') -Force | Out-Null
    $catalog = [pscustomobject]@{ version = 2; tips = @($Tips) }
    $catalog | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'catalog/tips.json') -Encoding UTF8
    ([pscustomobject]$Config) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'catalog/config.json') -Encoding UTF8
    return $root
}

function New-FakePluginsRoot
{
    # Builds ~/.claude/plugins with one installed plugin carrying one skill.
    $root = New-TempDir
    $installPath = Join-Path $root 'cache/kros-ai-dev-tools/kros-shared/abc123'
    New-Item -ItemType Directory -Path (Join-Path $installPath 'skills/git-diff') -Force | Out-Null

    @(
        '---'
        'name: git-diff'
        'description: Analyze git changes against master.'
        '---'
        ''
        'body text'
    ) | Set-Content -LiteralPath (Join-Path $installPath 'skills/git-diff/SKILL.md') -Encoding UTF8

    $installed = [pscustomobject]@{
        version = 2
        plugins = [pscustomobject]@{
            'kros-shared@kros-ai-dev-tools' = @(
                [pscustomobject]@{ scope = 'user'; installPath = $installPath; version = 'abc123' }
            )
        }
    }
    $installed | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'installed_plugins.json') -Encoding UTF8
    return $root
}

function New-FakeTranscripts
{
    # Two skill invocations and one line that is not one, in the layout Claude Code uses.
    $root = New-TempDir
    $project = Join-Path $root 'C--Users-someone-Projects-Invoicing'
    New-Item -ItemType Directory -Path $project -Force | Out-Null

    @(
        '{"type":"assistant","timestamp":"2026-09-01T10:00:00.000Z","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"kros-shared:git-diff"}}]}}'
        '{"type":"assistant","timestamp":"2026-09-02T10:00:00.000Z","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"kros-shared:git-diff"}}]}}'
        '{"type":"user","timestamp":"2026-09-02T10:01:00.000Z","message":{"content":"no skill here"}}'
    ) | Set-Content -LiteralPath (Join-Path $project 'session-1.jsonl') -Encoding UTF8

    return $root
}
