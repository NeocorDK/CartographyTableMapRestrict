<#
    Builds the mod and wraps it into a Thunderstore-format zip that r2modman /
    Thunderstore Mod Manager can install through "Import local mod".

    Usage:  powershell -ExecutionPolicy Bypass -File package.ps1 [-ValheimPath ...] [-BepInExCore ...]
#>
param(
    [string]$ValheimPath = 'G:\Steam\steamapps\common\Valheim',
    [string]$BepInExCore,
    [string]$Csc
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root  = Resolve-Path (Join-Path $PSScriptRoot '..')
$stage = Join-Path $root 'package\stage'
$dist  = Join-Path $root 'dist'

# 1. compile
$buildArgs = @{ ValheimPath = $ValheimPath; OutDir = $dist }
if ($BepInExCore) { $buildArgs.BepInExCore = $BepInExCore }
if ($Csc)         { $buildArgs.Csc         = $Csc }
& (Join-Path $PSScriptRoot 'build.ps1') @buildArgs

# 2. refresh the staged payload (icon.png and manifest.json are kept as-is)
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'plugins') | Out-Null
Copy-Item (Join-Path $dist 'CartographyTableMapRestrict.dll') (Join-Path $stage 'plugins') -Force
Copy-Item (Join-Path $root 'README.md') $stage -Force

$manifest = Get-Content (Join-Path $stage 'manifest.json') -Raw | ConvertFrom-Json
$version  = $manifest.version_number

# The BepInPlugin version is what BepInEx logs and what mod managers compare against,
# so a manifest that disagrees with the compiled plugin is always a packaging mistake.
$src = Get-Content (Join-Path $PSScriptRoot 'BepInExPlugin.cs') -Raw
if ($src -match 'pluginVersion\s*=\s*"([^"]+)"') {
    if ($Matches[1] -ne $version) {
        throw "Version mismatch: manifest.json says $version, BepInExPlugin.cs says $($Matches[1])."
    }
} else { throw 'Could not read pluginVersion from BepInExPlugin.cs' }

$zip = Join-Path $dist ("{0}-{1}-{2}.zip" -f $manifest.namespace, $manifest.name, $version)
if ([System.IO.File]::Exists($zip)) { [System.IO.File]::Delete($zip) }

# Compress-Archive on Windows PowerShell 5.1 writes backslash separators, which
# Node-based mod managers mis-extract. Build the archive with forward slashes.
$sep = [System.IO.Path]::DirectorySeparatorChar
$fs = [System.IO.File]::Open($zip, [System.IO.FileMode]::CreateNew)
$ar = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem $stage -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($stage.Length + 1).Replace($sep, [char]47)
        $entry  = $ar.CreateEntry($rel, [System.IO.Compression.CompressionLevel]::Optimal)
        $stream = $entry.Open()
        $bytes  = [System.IO.File]::ReadAllBytes($_.FullName)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Dispose()
    }
} finally { $ar.Dispose(); $fs.Dispose() }

Write-Host "Packaged: $zip"
