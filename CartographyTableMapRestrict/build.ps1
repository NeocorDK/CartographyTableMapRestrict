<#
    Builds CartographyTableMapRestrict.dll without needing the .NET SDK.

    It looks for a C# compiler in this order:
      1. csc.exe passed via -Csc
      2. the Roslyn compiler shipped with Visual Studio / MSBuild, if present
      3. the legacy .NET Framework compiler (C# 5 only - the source stays within that subset)

    Usage:  powershell -ExecutionPolicy Bypass -File build.ps1 [-ValheimPath "G:\Steam\steamapps\common\Valheim"]
#>
param(
    [string]$ValheimPath = 'G:\Steam\steamapps\common\Valheim',
    [string]$Csc,
    [string]$BepInExCore,
    [string]$OutDir = (Join-Path $PSScriptRoot '..\dist')
)

$ErrorActionPreference = 'Stop'

$managed = Join-Path $ValheimPath 'valheim_Data\Managed'
$core    = if ($BepInExCore) { $BepInExCore } else { Join-Path $ValheimPath 'BepInEx\core' }
foreach ($d in @($managed, $core)) {
    if (-not (Test-Path $d)) { throw "Not found: $d  (pass -ValheimPath)" }
}

if (-not $Csc) {
    $candidates = @(
        (Get-ChildItem 'C:\Program Files\Microsoft Visual Studio\*\*\MSBuild\Current\Bin\Roslyn\csc.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName),
        'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    )
    $Csc = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $Csc) { throw 'No C# compiler found. Pass -Csc <path to csc.exe>.' }
Write-Host "Compiler: $Csc"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$out = Join-Path $OutDir 'CartographyTableMapRestrict.dll'

$refs = @(
    "$managed\mscorlib.dll", "$managed\netstandard.dll", "$managed\System.dll", "$managed\System.Core.dll",
    "$managed\UnityEngine.dll", "$managed\UnityEngine.CoreModule.dll",
    "$managed\assembly_valheim.dll",
    "$core\BepInEx.dll", "$core\0Harmony.dll"
) | ForEach-Object { "-r:$_" }

$args = @('-nologo', '-noconfig', '-target:library', '-optimize+', '-nostdlib+', "-out:$out") +
        $refs + @((Join-Path $PSScriptRoot 'BepInExPlugin.cs'))

& $Csc @args
if ($LASTEXITCODE -ne 0) { throw "Build failed ($LASTEXITCODE)" }
Write-Host "Built: $out"
