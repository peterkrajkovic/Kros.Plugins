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
