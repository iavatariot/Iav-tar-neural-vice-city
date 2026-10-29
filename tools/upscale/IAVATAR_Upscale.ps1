#Requires -Version 5.1
<#
  IAVAT@R Neural Vice City - ingrandimento IA delle texture (strumento di sviluppo).
  Per gli utenti finali lo fa IAVATAR_Setup.ps1 / -Install -Textures. Questo script esegue solo il passo IA
  su work\upscale\in -> work\upscale\out, con la stessa logica (moduleA-enabler\src\lib\IavTextures.psm1)
  e gli stessi hash fissati (moduleB-assets\config\runtime.json).

  Uso (dalla radice della repo):
    powershell -ExecutionPolicy Bypass -File tools\upscale\IAVATAR_Upscale.ps1 -Zip C:\IAVATAR_input\realesrgan-ncnn-vulkan-20220424-windows.zip
#>
param(
    [string]$Zip,
    [string]$In,
    [string]$Out,
    [string]$ToolDir,
    [int]$Gpu = 0,
    [int]$Batch = 40,
    [switch]$Keep4x
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
# In Windows PowerShell 5.1 $PSScriptRoot puo' essere vuoto nei valori di default dei parametri: si risolve qui.
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$repo = (Resolve-Path -LiteralPath (Join-Path $here '..\..')).ProviderPath
if (-not $In) { $In = Join-Path $repo 'work\upscale\in' }
if (-not $Out) { $Out = Join-Path $repo 'work\upscale\out' }
if (-not $ToolDir) { $ToolDir = Join-Path $repo 'work\tools\realesrgan' }
foreach ($m in 'IavCore', 'IavTextures') { Import-Module (Join-Path $repo ('moduleA-enabler\src\lib\{0}.psm1' -f $m)) -Force -DisableNameChecking }

Write-Host 'IAVAT@R Neural Vice City - upscale IA (Real-ESRGAN)' -ForegroundColor Magenta
[void](Initialize-IavLog -Directory (Join-Path $repo 'work\logs'))
$runtime = Get-IavRuntimeConfig -RepoRoot $repo
$exe = Initialize-IavRealEsrgan -Runtime $runtime -ToolDir $ToolDir -Zip $Zip -DownloadDir (Join-Path $repo 'work\downloads')
[void](Invoke-IavUpscale -Exe $exe -Model $runtime.realesrgan.model -In $In -Out $Out -Gpu $Gpu -Batch $Batch -Keep4x:$Keep4x)
Write-Host 'Lo script si puo'' rilanciare: riprende da dove si e'' fermato.' -ForegroundColor Green
