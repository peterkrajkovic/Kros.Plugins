<#
.SYNOPSIS
Validates plugin assets and assembles an upload-ready plugin ZIP for the KROS plugin store.
Optionally POSTs the ZIP to a running /admin/plugins/validate endpoint.

.EXAMPLE
pwsh ./New-PluginPackage.ps1 -ManifestPath manifest.json -IconPath icon.png -OutputZip my-plugin.zip

.EXAMPLE
pwsh ./New-PluginPackage.ps1 -ManifestPath manifest.json -IconPath icon.png -MediaPaths a.png,b.png `
  -OutputZip my-plugin.zip -ValidateUrl https://localhost:5001 -Token $env:PLUGIN_TOKEN
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$IconPath,
    [string[]]$MediaPaths = @(),
    [Parameter(Mandatory)][string]$OutputZip,
    [string]$ValidateUrl,
    [string]$Token
)

$ErrorActionPreference = 'Stop'

# Limits mirror PackageStructuralRules / PackageLayoutRules / PackageContentRules.
$MaxEntries = 25
$MaxPerEntryBytes = 5MB
$MaxTotalBytes = 15MB
$MaxMedia = 10
$IconMin = 64; $IconMax = 1024
$MediaMinW = 320; $MediaMinH = 180; $MediaMaxW = 1920; $MediaMaxH = 1080
$IconExts  = @('.png', '.jpg', '.jpeg', '.webp', '.svg')
$MediaExts = @('.png', '.jpg', '.jpeg', '.webp')

function Get-ImageInfo {
    param([byte[]]$Bytes)
    # PNG
    if ($Bytes.Length -ge 24 -and $Bytes[0] -eq 0x89 -and $Bytes[1] -eq 0x50 -and $Bytes[2] -eq 0x4E -and $Bytes[3] -eq 0x47) {
        $w = ([int]$Bytes[16] -shl 24) -bor ([int]$Bytes[17] -shl 16) -bor ([int]$Bytes[18] -shl 8) -bor [int]$Bytes[19]
        $h = ([int]$Bytes[20] -shl 24) -bor ([int]$Bytes[21] -shl 16) -bor ([int]$Bytes[22] -shl 8) -bor [int]$Bytes[23]
        return @{ Mime = 'image/png'; Width = $w; Height = $h; DimsKnown = $true }
    }
    # JPEG
    if ($Bytes.Length -ge 4 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xD8) {
        $i = 2
        while ($i -lt $Bytes.Length - 8) {
            if ($Bytes[$i] -ne 0xFF) { $i++; continue }
            $marker = $Bytes[$i + 1]
            if ($marker -ge 0xC0 -and $marker -le 0xCF -and $marker -ne 0xC4 -and $marker -ne 0xC8 -and $marker -ne 0xCC) {
                $h = ([int]$Bytes[$i + 5] -shl 8) -bor [int]$Bytes[$i + 6]
                $w = ([int]$Bytes[$i + 7] -shl 8) -bor [int]$Bytes[$i + 8]
                return @{ Mime = 'image/jpeg'; Width = $w; Height = $h; DimsKnown = $true }
            }
            $len = ([int]$Bytes[$i + 2] -shl 8) -bor [int]$Bytes[$i + 3]
            if ($len -le 0) { break }
            $i += 2 + $len
        }
        return @{ Mime = 'image/jpeg'; Width = 0; Height = 0; DimsKnown = $false }
    }
    # WebP (RIFF....WEBP)
    if ($Bytes.Length -ge 30 -and $Bytes[0] -eq 0x52 -and $Bytes[1] -eq 0x49 -and $Bytes[2] -eq 0x46 -and $Bytes[3] -eq 0x46 `
            -and $Bytes[8] -eq 0x57 -and $Bytes[9] -eq 0x45 -and $Bytes[10] -eq 0x42 -and $Bytes[11] -eq 0x50) {
        $fourcc = [System.Text.Encoding]::ASCII.GetString($Bytes, 12, 4)
        if ($fourcc -eq 'VP8X') {
            $w = (([int]$Bytes[24] -bor ([int]$Bytes[25] -shl 8) -bor ([int]$Bytes[26] -shl 16)) + 1)
            $h = (([int]$Bytes[27] -bor ([int]$Bytes[28] -shl 8) -bor ([int]$Bytes[29] -shl 16)) + 1)
            return @{ Mime = 'image/webp'; Width = $w; Height = $h; DimsKnown = $true }
        }
        if ($fourcc -eq 'VP8 ') {
            $w = ([int]$Bytes[26] -bor ([int]$Bytes[27] -shl 8)) -band 0x3FFF
            $h = ([int]$Bytes[28] -bor ([int]$Bytes[29] -shl 8)) -band 0x3FFF
            return @{ Mime = 'image/webp'; Width = $w; Height = $h; DimsKnown = $true }
        }
        if ($fourcc -eq 'VP8L' -and $Bytes[20] -eq 0x2F) {
            $b0 = [int]$Bytes[21]; $b1 = [int]$Bytes[22]; $b2 = [int]$Bytes[23]; $b3 = [int]$Bytes[24]
            $w = ((($b1 -band 0x3F) -shl 8) -bor $b0) + 1
            $h = (((($b3 -band 0x0F) -shl 10) -bor ($b2 -shl 2) -bor (($b1 -band 0xC0) -shr 6))) + 1
            return @{ Mime = 'image/webp'; Width = $w; Height = $h; DimsKnown = $true }
        }
        return @{ Mime = 'image/webp'; Width = 0; Height = 0; DimsKnown = $false }
    }
    # SVG (text)
    $head = [System.Text.Encoding]::UTF8.GetString($Bytes, 0, [Math]::Min(1024, $Bytes.Length))
    if ($head -match '<svg') {
        return @{ Mime = 'image/svg+xml'; Width = 0; Height = 0; DimsKnown = $false }
    }
    return @{ Mime = $null; Width = 0; Height = 0; DimsKnown = $false }
}

function Test-MimeMatchesExt {
    param([string]$Ext, [string]$Mime, [bool]$AllowSvg)
    switch ($Ext) {
        '.png'  { return $Mime -eq 'image/png' }
        '.jpg'  { return $Mime -eq 'image/jpeg' }
        '.jpeg' { return $Mime -eq 'image/jpeg' }
        '.webp' { return $Mime -eq 'image/webp' }
        '.svg'  { return $AllowSvg -and $Mime -eq 'image/svg+xml' }
        default { return $false }
    }
}

$errors = [System.Collections.Generic.List[string]]::new()

if (-not (Test-Path $ManifestPath)) { throw "Manifest not found: $ManifestPath" }
if (-not (Test-Path $IconPath)) { throw "Icon not found: $IconPath" }

# --- icon ---
$iconExt = [System.IO.Path]::GetExtension($IconPath).ToLowerInvariant()
if ($iconExt -notin $IconExts) {
    $errors.Add("Icon extension '$iconExt' not allowed. Use one of: $($IconExts -join ', ').")
}
else {
    $iconBytes = [System.IO.File]::ReadAllBytes($IconPath)
    $info = Get-ImageInfo -Bytes $iconBytes
    if (-not (Test-MimeMatchesExt -Ext $iconExt -Mime $info.Mime -AllowSvg $true)) {
        $errors.Add("Icon content (sniffed '$($info.Mime)') does not match extension '$iconExt'.")
    }
    elseif ($iconExt -ne '.svg') {
        if (-not $info.DimsKnown) {
            Write-Warning "Could not read icon dimensions locally; rely on live /validate."
        }
        elseif ($info.Width -lt $IconMin -or $info.Width -gt $IconMax -or $info.Height -lt $IconMin -or $info.Height -gt $IconMax) {
            $errors.Add("Icon must be ${IconMin}-${IconMax}px; got $($info.Width)x$($info.Height).")
        }
        elseif ($info.Width -ne $info.Height) {
            $errors.Add("Icon must be square; got $($info.Width)x$($info.Height).")
        }
    }
}

# --- media ---
if ($MediaPaths.Count -gt $MaxMedia) {
    $errors.Add("Too many media files: $($MediaPaths.Count) (max $MaxMedia).")
}
foreach ($m in $MediaPaths) {
    if (-not (Test-Path $m)) { $errors.Add("Media not found: $m"); continue }
    $mext = [System.IO.Path]::GetExtension($m).ToLowerInvariant()
    if ($mext -notin $MediaExts) {
        $errors.Add("Media '$m' extension '$mext' not allowed. Use: $($MediaExts -join ', ').")
        continue
    }
    $mb = [System.IO.File]::ReadAllBytes($m)
    $minfo = Get-ImageInfo -Bytes $mb
    if (-not (Test-MimeMatchesExt -Ext $mext -Mime $minfo.Mime -AllowSvg $false)) {
        $errors.Add("Media '$m' content (sniffed '$($minfo.Mime)') does not match extension '$mext'.")
    }
    elseif (-not $minfo.DimsKnown) {
        Write-Warning "Could not read dimensions of '$m' locally; rely on live /validate."
    }
    elseif ($minfo.Width -lt $MediaMinW -or $minfo.Height -lt $MediaMinH -or $minfo.Width -gt $MediaMaxW -or $minfo.Height -gt $MediaMaxH) {
        $errors.Add("Media '$m' must be ${MediaMinW}x${MediaMinH}..${MediaMaxW}x${MediaMaxH}; got $($minfo.Width)x$($minfo.Height).")
    }
}

# --- size & entry-count pre-checks ---
$entryFiles = @($ManifestPath, $IconPath) + $MediaPaths
$entryCount = $entryFiles.Count
if ($entryCount -gt $MaxEntries) { $errors.Add("Too many entries: $entryCount (max $MaxEntries).") }
$total = 0L
foreach ($f in $entryFiles) {
    if (Test-Path $f) {
        $size = (Get-Item $f).Length
        $total += $size
        if ($size -gt $MaxPerEntryBytes) { $errors.Add("Entry '$f' is $size bytes (max $MaxPerEntryBytes).") }
    }
}
if ($total -gt $MaxTotalBytes) { $errors.Add("Total uncompressed size $total bytes exceeds $MaxTotalBytes.") }

if ($errors.Count -gt 0) {
    Write-Host "ASSET VALIDATION FAILED:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

# --- assemble zip with exact layout ---
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path $OutputZip) { Remove-Item $OutputZip -Force }

$fs = [System.IO.File]::Open($OutputZip, [System.IO.FileMode]::Create)
try {
    $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        function Add-ZipEntry {
            param($Archive, [string]$SrcPath, [string]$EntryName)
            $entry = $Archive.CreateEntry($EntryName, [System.IO.Compression.CompressionLevel]::Optimal)
            $es = $entry.Open()
            try {
                $data = [System.IO.File]::ReadAllBytes($SrcPath)
                $es.Write($data, 0, $data.Length)
            }
            finally { $es.Dispose() }
        }
        Add-ZipEntry -Archive $zip -SrcPath $ManifestPath -EntryName 'manifest.json'
        Add-ZipEntry -Archive $zip -SrcPath $IconPath -EntryName "icon$iconExt"
        # Prefix each media file with a zero-padded ordinal so entry names are unique
        # (two source files can share a base name and would otherwise collide) and
        # match the documented `media/NN-*` layout.
        $ordinal = 0
        foreach ($m in $MediaPaths) {
            $ordinal++
            $name = [System.IO.Path]::GetFileName($m)
            $entryName = 'media/{0:D2}-{1}' -f $ordinal, $name
            Add-ZipEntry -Archive $zip -SrcPath $m -EntryName $entryName
        }
    }
    finally { $zip.Dispose() }
}
finally { $fs.Dispose() }

Write-Host "Package built: $OutputZip ($entryCount entries, $([math]::Round($total/1KB,1)) KB uncompressed)" -ForegroundColor Green

# --- optional live validation (ValidateUrl is the GATEWAY root, e.g. https://localhost:5001) ---
if ($ValidateUrl) {
    $base = $ValidateUrl.TrimEnd('/')
    # Gateway exposes the admin API under the /api prefix (Ocelot).
    $endpoint = if ($base -match '/admin/plugins/validate$') { $base } else { "$base/api/admin/plugins/validate" }
    Write-Host "POST $endpoint" -ForegroundColor Cyan
    $headers = @{}
    if ($Token) { $headers['Authorization'] = "Bearer $Token" }
    try {
        $resp = Invoke-RestMethod -Uri $endpoint -Method Post -InFile $OutputZip `
            -ContentType 'application/zip' -Headers $headers
        if ($resp.valid) {
            Write-Host "LIVE VALIDATION: valid" -ForegroundColor Green
        }
        else {
            Write-Host "LIVE VALIDATION: invalid" -ForegroundColor Red
            $resp.errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
            exit 2
        }
    }
    catch {
        Write-Host "LIVE VALIDATION request failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 3
    }
}
