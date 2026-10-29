#Requires -Version 5.1
<#
.SYNOPSIS
  IAVAT@R Neural Vice City - crea il pacchetto da pubblicare (Nexus / ModDB).

.DESCRIPTION
  1. esegue i test automatici (salvo -SkipTests): se uno fallisce, niente pacchetto;
  2. raccoglie SOLO i file dell'allowlist (sorgenti e configurazione testuale; work\ e docs\recon esclusi);
  3. passa ogni file alla guardia: pak/asset Unreal, texture, DLL, eseguibili, archivi, immagini, file binari
     o troppo grandi bloccano tutto e vengono elencati;
  4. scrive release\dist\IAVATAR_NeuralViceCity_v<versione>.zip + .sha256, con RELEASE-MANIFEST.txt dentro.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\release\New-IavRelease.ps1
#>
param([switch]$SkipTests, [string]$OutDir)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$repo = (Resolve-Path -LiteralPath (Join-Path $here '..')).ProviderPath
if (-not $OutDir) { $OutDir = Join-Path $here 'dist' }
Import-Module (Join-Path $here 'IavRelease.psm1') -Force -DisableNameChecking

$cfg = [IO.File]::ReadAllText((Join-Path $repo 'moduleA-enabler/config/components.json')) | ConvertFrom-Json
$version = $cfg.version
Write-Host ('IAVAT@R Neural Vice City - release v{0}' -f $version) -ForegroundColor Magenta
if (-not ([IO.File]::ReadAllText((Join-Path $repo 'CHANGELOG.md'))).Contains(('## [{0}]' -f $version))) {
    throw ('CHANGELOG.md non ha una sezione "## [{0}]": aggiornala prima di pubblicare.' -f $version)
}

if (-not $SkipTests) {
    $exe = (Get-Process -Id $PID).Path
    & $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tests/moduleA/Run-Tests.ps1') | Out-Host
    if ($LASTEXITCODE -ne 0) { Write-Host 'Test falliti: pacchetto NON creato.' -ForegroundColor Red; exit 1 }
}

$r = New-IavReleasePackage -RepoRoot $repo -Version $version -OutDir $OutDir
if (-not $r.Ok) {
    Write-Host ('BLOCCATO: {0} file non ammessi nella release. Nessun pacchetto creato.' -f $r.Violations.Count) -ForegroundColor Red
    foreach ($v in $r.Violations) { Write-Host ('  - ' + $v) -ForegroundColor Red }
    exit 2
}
Write-Host ('[OK] {0} file, guardia superata.' -f $r.Files) -ForegroundColor Green
Write-Host ('     {0}' -f $r.Zip)
Write-Host ('     SHA-256 {0}' -f $r.Sha256)
exit 0
