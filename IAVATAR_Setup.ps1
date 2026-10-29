#Requires -Version 5.1
<#
.SYNOPSIS
  IAVAT@R Neural Vice City - installazione completa in un solo comando.

.DESCRIPTION
  1. Modulo A (DLSS 5 neural rendering): ReShade dal sito ufficiale, add-on RenoDX e DLL NVIDIA trovati
     sul tuo PC (cartella Download, C:\IAVATAR_input, RTX Remix), preset IAVAT@R.
  2. Modulo B (texture): costruite IN LOCALE dai file del tuo gioco (personaggi, ambiente, ambiente HD con
     ingrandimento IA sulla GPU), installate in ~mods, pool di streaming adeguato alla tua VRAM.
  Ogni passo e' transazionale (manifest, backup, verifica, rollback) e chiede conferma prima di toccare
  la cartella del gioco. Rilanciabile: cio' che e' gia' fatto viene saltato.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\IAVATAR_Setup.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\IAVATAR_Setup.ps1 -Uninstall
#>
param(
    [switch]$Uninstall,
    [switch]$SkipNeural,
    [switch]$SkipTextures,
    [string]$GamePath
)
$ErrorActionPreference = 'Stop'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$main = Join-Path $here 'moduleA-enabler\src\IAVATAR_NeuralViceCity.ps1'
$common = @()
if ($GamePath) { $common += @('-GamePath', $GamePath) }

function Run([string[]]$ArgList) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $main @ArgList @common | Out-Host
    return $LASTEXITCODE
}

if ($Uninstall) {
    $a = if ($SkipTextures) { 0 } else { Run @('-Uninstall', '-Textures') }
    $b = if ($SkipNeural) { 0 } else { Run @('-Uninstall') }
    if ($a -ne 0 -or $b -ne 0) { Write-Host 'Disinstallazione con avvisi: leggi il log indicato sopra.' -ForegroundColor Yellow; exit 4 }
    Write-Host 'IAVAT@R Neural Vice City disinstallata: gioco riportato allo stato originale.' -ForegroundColor Green
    exit 0
}

if (-not $SkipNeural) {
    $code = Run @('-Install', '-Auto')
    if ($code -ne 0) {
        Write-Host ''
        Write-Host 'Modulo A non installato. Cause tipiche (dettagli nel log):' -ForegroundColor Yellow
        Write-Host '  - manca renodx-dlss5.addon64: scaricalo dal Discord ufficiale RenoDX e mettilo in Download o in C:\IAVATAR_input'
        Write-Host '  - manca nvngx_dlssnr.dll: installa RTX Remix dall''app NVIDIA (resta sul tuo PC, non viene copiato altrove)'
        Write-Host '  - serve una GPU NVIDIA RTX serie 50'
        Write-Host 'Puoi installare solo le texture con:  .\IAVATAR_Setup.ps1 -SkipNeural'
        exit $code
    }
}
if (-not $SkipTextures) {
    $code = Run @('-Install', '-Textures')
    if ($code -ne 0) { Write-Host 'Texture non installate: leggi il log indicato sopra. Rilanciando, la costruzione riprende da dove si e'' fermata.' -ForegroundColor Yellow; exit $code }
}
Write-Host ''
Write-Host 'Fatto. Ultimo passo consigliato (non automatizzabile) contro i bordi seghettati:' -ForegroundColor Green
Write-Host '  Pannello di controllo NVIDIA > DSR - Fattori: DL 2,25x, poi nel gioco risoluzione 2880x1620 (su 1080p).' -ForegroundColor Green
Write-Host '  L''override DLSS dell''app NVIDIA non e'' supportato per questo gioco. Dettagli in docs\INSTALL.md.' -ForegroundColor Green
exit 0
