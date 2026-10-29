#Requires -Version 5.1
<#
  IAVAT@R Neural Vice City - ingrandimento IA delle texture con Real-ESRGAN (GPU, Vulkan).

  - Usa SOLO l'archivio ufficiale realesrgan-ncnn-vulkan-20220424-windows.zip
    (https://github.com/xinntao/Real-ESRGAN/releases/tag/v0.2.5.0, licenza BSD-3-Clause),
    verificato con SHA-256 prima di estrarlo; anche exe e modello vengono verificati prima dell'esecuzione.
  - Legge i PNG esportati da moduleB-assets/pipeline/upscale_export.py (work\upscale\in)
    e scrive i risultati in work\upscale\out. Nulla viene scritto nella cartella del gioco.

  Uso (dalla radice della repo):
    powershell -ExecutionPolicy Bypass -File tools\upscale\IAVATAR_Upscale.ps1 -Zip C:\IAVATAR_input\realesrgan-ncnn-vulkan-20220424-windows.zip
#>
param(
    [Parameter(Mandatory)][string]$Zip,
    [string]$In,
    [string]$Out,
    [string]$ToolDir,
    [ValidateSet('realesrgan-x4plus')][string]$Model = 'realesrgan-x4plus',
    [int]$Gpu = 0,
    [int]$Batch = 40,          # texture per giro: limita lo spazio su disco occupato dai PNG 4x
    [switch]$Keep4x            # di default ogni risultato 4x viene ridotto subito a 2x (meno spazio)
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
# In Windows PowerShell 5.1 $PSScriptRoot puo' essere vuoto nei valori di default dei parametri: si risolve qui.
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$repo = (Resolve-Path -LiteralPath (Join-Path $here '..\..')).ProviderPath
if (-not $In) { $In = Join-Path $repo 'work\upscale\in' }
if (-not $Out) { $Out = Join-Path $repo 'work\upscale\out' }
if (-not $ToolDir) { $ToolDir = Join-Path $repo 'work\tools\realesrgan' }

$Pinned = @{
    Zip   = 'ABC02804E17982A3BE33675E4D471E91EA374E65B70167ABC09E31ACB412802D'
    Exe   = '07E49F7CBB4EDE01AE4DD4C399D3A7E5846E3D2085C3128EFF881E55CB7B1A0C'
    Bin   = '713EE713B0353AFAA27976F0563A64A5043BD70B9BD8936C2E26E25EBCDBCDDF'
    Param = '35330ECECCEA33B6C397A72548E788D5D53BECEE4734C50B7FADA36E89F10A86'
}
function Hash([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToUpperInvariant() }
function Check([string]$p, [string]$exp, [string]$what) {
    $h = Hash $p
    if ($h -ne $exp) { throw ('{0}: SHA-256 {1} diverso da quello atteso {2}. Interrotto.' -f $what, $h, $exp) }
    Write-Host ('[OK] {0} verificato ({1}...)' -f $what, $h.Substring(0, 16)) -ForegroundColor Green
}

Write-Host 'IAVAT@R Neural Vice City - upscale IA (Real-ESRGAN)' -ForegroundColor Magenta
$exe = Join-Path $ToolDir 'realesrgan-ncnn-vulkan.exe'
if (-not (Test-Path -LiteralPath $exe)) {
    Check $Zip $Pinned.Zip 'archivio Real-ESRGAN'
    New-Item -ItemType Directory -Path $ToolDir -Force | Out-Null
    Expand-Archive -LiteralPath $Zip -DestinationPath $ToolDir -Force
}
Check $exe $Pinned.Exe 'realesrgan-ncnn-vulkan.exe'
Check (Join-Path $ToolDir "models\$Model.bin") $Pinned.Bin "modello $Model.bin"
Check (Join-Path $ToolDir "models\$Model.param") $Pinned.Param "modello $Model.param"

$In = (Resolve-Path -LiteralPath $In).ProviderPath
New-Item -ItemType Directory -Path $Out -Force | Out-Null
$Out = (Resolve-Path -LiteralPath $Out).ProviderPath

# Solo i file non ancora fatti: lavoriamo su una cartella temporanea con i mancanti (riprendibile).
$todo = @(Get-ChildItem -LiteralPath $In -Filter *.png | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Out $_.Name)) })
Write-Host ('Texture da ingrandire: {0} (gia'' fatte: {1})' -f $todo.Count, (@(Get-ChildItem -LiteralPath $Out -Filter *.png).Count))
if ($todo.Count -eq 0) { Write-Host '[OK] Niente da fare.' -ForegroundColor Green; exit 0 }
Add-Type -AssemblyName System.Drawing
function Reduce-Half([string]$path) {
    # 4x -> 2x con filtro bicubico di alta qualita'; bordi in "tile flip" per non scurire i margini
    $src = [Drawing.Image]::FromFile($path)
    try {
        $w = [int]($src.Width / 2); $h = [int]($src.Height / 2)
        $dst = New-Object Drawing.Bitmap $w, $h, ([Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $g = [Drawing.Graphics]::FromImage($dst)
        $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
        $attr = New-Object Drawing.Imaging.ImageAttributes
        $attr.SetWrapMode([Drawing.Drawing2D.WrapMode]::TileFlipXY)
        $g.DrawImage($src, (New-Object Drawing.Rectangle 0, 0, $w, $h), 0, 0, $src.Width, $src.Height, [Drawing.GraphicsUnit]::Pixel, $attr)
        $g.Dispose()
    } finally { $src.Dispose() }
    $tmp = $path + '.tmp.png'
    $dst.Save($tmp, [Drawing.Imaging.ImageFormat]::Png); $dst.Dispose()
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

$sw = [Diagnostics.Stopwatch]::StartNew()
$done = 0
for ($k = 0; $k -lt $todo.Count; $k += $Batch) {
    $chunk = $todo[$k..([Math]::Min($k + $Batch, $todo.Count) - 1)]
    $batchIn = Join-Path $env:TEMP ('iavatar_upscale_in_' + [guid]::NewGuid().ToString('N'))
    $batchOut = Join-Path $env:TEMP ('iavatar_upscale_out_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $batchIn, $batchOut | Out-Null
    try {
        foreach ($f in $chunk) { Copy-Item -LiteralPath $f.FullName -Destination $batchIn }
        # PS 5.1: lo stderr di un eseguibile nativo con ErrorActionPreference=Stop diventerebbe un errore bloccante
        $ErrorActionPreference = 'Continue'
        & $exe -i $batchIn -o $batchOut -n $Model -s 4 -f png -g $Gpu -m (Join-Path $ToolDir 'models') 2>&1 | Out-Null
        $code = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($code -ne 0) { throw ('Real-ESRGAN terminato con codice {0}' -f $code) }
        foreach ($f in $chunk) {
            $r = Join-Path $batchOut $f.Name
            if (-not (Test-Path -LiteralPath $r)) { Write-Host ('[MANCA] {0}' -f $f.Name) -ForegroundColor Yellow; continue }
            if (-not $Keep4x) { Reduce-Half $r }
            Move-Item -LiteralPath $r -Destination (Join-Path $Out $f.Name) -Force
            $done++
        }
    } finally {
        Remove-Item -LiteralPath $batchIn, $batchOut -Recurse -Force -ErrorAction SilentlyContinue
    }
    $eta = if ($done) { [TimeSpan]::FromSeconds($sw.Elapsed.TotalSeconds / $done * ($todo.Count - $done)) } else { [TimeSpan]::Zero }
    Write-Host ('[{0}/{1}] {2:hh\:mm\:ss} trascorsi, circa {3:hh\:mm\:ss} alla fine' -f $done, $todo.Count, $sw.Elapsed, $eta)
}
Write-Host ('[OK] {0} texture in {1:hh\:mm\:ss} -> {2}. Lo script si puo'' rilanciare: riprende da dove si e'' fermato.' -f $done, $sw.Elapsed, $Out) -ForegroundColor Green
