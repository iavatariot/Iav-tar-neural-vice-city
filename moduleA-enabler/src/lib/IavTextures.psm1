#Requires -Version 5.1
<#
  IAVAT@R Neural Vice City - IavTextures (Modulo B lato utente)

  Le texture NON vengono distribuite: si costruiscono sul PC dell'utente a partire dai file del SUO gioco.
  Questo modulo:
    1. prepara un Python privato (embeddable ufficiale + numpy + Pillow, hash fissati) nella cartella di stato;
    2. prepara Real-ESRGAN (release ufficiale GitHub, hash fissati) per l'ingrandimento IA sulla GPU;
    3. esegue la pipeline (moduleB-assets/pipeline) e produce i pak in work\build;
    4. prepara il piano di installazione dei pak in ~mods e del pool di streaming in CustomSettings.ini,
       eseguito con lo stesso motore transazionale del Modulo A (manifest, backup, verifica, rollback).
  Ogni download: solo URL ufficiale, SHA-256 verificato, registrato nel log.
#>
Set-StrictMode -Version 2.0

function Get-IavRuntimeConfig {
    param([Parameter(Mandatory)][string]$RepoRoot)
    [IO.File]::ReadAllText((Join-Path $RepoRoot 'moduleB-assets\config\runtime.json')) | ConvertFrom-Json
}

function Save-IavVerifiedDownload {
    <# Scarica da un URL ufficiale (https) e verifica lo SHA-256 fissato; se il file c'e' gia' ed e' integro, lo riusa. #>
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string]$Sha256, [Parameter(Mandatory)][string]$Directory)
    if ($Url -notmatch '^https://(www\.python\.org|files\.pythonhosted\.org|github\.com)/') { throw ('URL non ammesso: {0}' -f $Url) }
    if (-not (Test-Path -LiteralPath $Directory)) { New-Item -ItemType Directory -Path $Directory -Force | Out-Null }
    $file = Join-Path $Directory (Split-Path -Leaf $Url)
    if ((Test-Path -LiteralPath $file) -and (Get-IavSha256 -Path $file) -eq $Sha256.ToUpperInvariant()) {
        Write-IavLog -Level OK -Message ('Gia'' scaricato e verificato: {0}' -f (Split-Path -Leaf $file))
        return $file
    }
    Write-IavLog -Level INFO -Message ('Download ufficiale: {0}' -f $Url)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
    try { Invoke-WebRequest -Uri $Url -OutFile $file -UseBasicParsing -ErrorAction Stop } finally { $ProgressPreference = $old }
    $h = Get-IavSha256 -Path $file
    Write-IavLog -Level INFO -Message ('SHA-256 {0}: {1}' -f (Split-Path -Leaf $file), $h)
    if ($h -ne $Sha256.ToUpperInvariant()) {
        Remove-Item -LiteralPath $file -Force
        throw ('Hash di {0} diverso da quello atteso ({1}): file eliminato, interrotto.' -f (Split-Path -Leaf $Url), $Sha256)
    }
    Write-IavLog -Level OK -Message ('Verificato: {0}' -f (Split-Path -Leaf $file))
    return $file
}

function Initialize-IavPython {
    <# Python embeddable privato in <StateDir>\runtime\python, con numpy e Pillow installati dai wheel ufficiali. #>
    param([Parameter(Mandatory)]$Runtime, [Parameter(Mandatory)][string]$StateDir)
    $dl = Join-Path $StateDir 'downloads'
    $dir = Join-Path $StateDir 'runtime\python'
    $exe = Join-Path $dir 'python.exe'
    $stamp = Join-Path $dir '.iavatar_ok'
    $want = ($Runtime.python.sha256 + '|' + (($Runtime.wheels | ForEach-Object { $_.sha256 }) -join '|')).ToUpperInvariant()
    if ((Test-Path -LiteralPath $stamp) -and ([IO.File]::ReadAllText($stamp).Trim() -eq $want) -and (Test-Path -LiteralPath $exe)) {
        Write-IavLog -Level OK -Message ('Python privato pronto: {0}' -f $exe)
        return $exe
    }
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
    $zip = Save-IavVerifiedDownload -Url $Runtime.python.url -Sha256 $Runtime.python.sha256 -Directory $dl
    Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
    $site = Join-Path $dir 'Lib\site-packages'
    New-Item -ItemType Directory -Path $site -Force | Out-Null
    # L'embeddable ignora site-packages finche' non lo si aggiunge al file ._pth
    $pth = Join-Path $dir $Runtime.python.pth
    $lines = @([IO.File]::ReadAllLines($pth) | Where-Object { $_ -notmatch '^\s*#?\s*import site' })
    $lines += 'Lib\site-packages'
    $lines += 'import site'
    [IO.File]::WriteAllLines($pth, $lines)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    foreach ($w in $Runtime.wheels) {
        $whl = Save-IavVerifiedDownload -Url $w.url -Sha256 $w.sha256 -Directory $dl
        # un wheel e' uno zip: si estrae direttamente in site-packages (nessun pip, nessun codice eseguito)
        [IO.Compression.ZipFile]::ExtractToDirectory($whl, $site)
        Write-IavLog -Level OK -Message ('Installato {0}' -f $w.name)
    }
    $check = & $exe -I -c "import numpy, PIL; print(numpy.__version__, PIL.__version__)" 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('Python privato non funzionante: {0}' -f ($check -join ' ')) }
    Write-IavLog -Level OK -Message ('Python privato pronto (numpy, Pillow {0})' -f ($check -join ' '))
    [IO.File]::WriteAllText($stamp, $want)
    return $exe
}

function Initialize-IavRealEsrgan {
    param([Parameter(Mandatory)]$Runtime, [Parameter(Mandatory)][string]$ToolDir, [string]$Zip, [string]$DownloadDir)
    $r = $Runtime.realesrgan
    $exe = Join-Path $ToolDir 'realesrgan-ncnn-vulkan.exe'
    if (-not (Test-Path -LiteralPath $exe)) {
        if ($Zip) {
            if ((Get-IavSha256 -Path $Zip) -ne $r.sha256.ToUpperInvariant()) { throw ('{0}: hash diverso dall''archivio ufficiale Real-ESRGAN.' -f $Zip) }
        } else {
            if (-not $DownloadDir) { throw 'Serve -Zip oppure una cartella di download.' }
            $Zip = Save-IavVerifiedDownload -Url $r.url -Sha256 $r.sha256 -Directory $DownloadDir
        }
        New-Item -ItemType Directory -Path $ToolDir -Force | Out-Null
        Expand-Archive -LiteralPath $Zip -DestinationPath $ToolDir -Force
    }
    foreach ($pair in @(@($exe, $r.exeSha256), @((Join-Path $ToolDir "models\$($r.model).bin"), $r.modelBinSha256), @((Join-Path $ToolDir "models\$($r.model).param"), $r.modelParamSha256))) {
        $h = Get-IavSha256 -Path $pair[0]
        if ($h -ne $pair[1].ToUpperInvariant()) { throw ('{0}: SHA-256 {1} diverso da quello atteso. Interrotto.' -f $pair[0], $h) }
    }
    Write-IavLog -Level OK -Message 'Real-ESRGAN verificato (eseguibile e modello).'
    return $exe
}

function Resize-IavImageHalf {
    <# 4x -> 2x con bicubica di alta qualita'; bordi in "tile flip" per non scurire i margini. #>
    param([Parameter(Mandatory)][string]$Path)
    Add-Type -AssemblyName System.Drawing
    $src = [Drawing.Image]::FromFile($Path)
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
    $tmp = $Path + '.tmp.png'
    $dst.Save($tmp, [Drawing.Imaging.ImageFormat]::Png); $dst.Dispose()
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Invoke-IavUpscale {
    <#
      Ingrandisce con Real-ESRGAN (x4) i PNG di $In e salva in $Out ridotti a 2x. A blocchi, riprendibile:
      i file gia' presenti in $Out vengono saltati.
    #>
    param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string]$Model, [Parameter(Mandatory)][string]$In,
          [Parameter(Mandatory)][string]$Out, [int]$Gpu = 0, [int]$Batch = 40, [switch]$Keep4x)
    New-Item -ItemType Directory -Path $Out -Force | Out-Null
    $todo = @(Get-ChildItem -LiteralPath $In -Filter *.png | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Out $_.Name)) })
    Write-IavLog -Level INFO -Message ('Ingrandimento IA: {0} texture da fare (gia'' fatte: {1})' -f $todo.Count, @(Get-ChildItem -LiteralPath $Out -Filter *.png).Count)
    if ($todo.Count -eq 0) { return 0 }
    $models = Join-Path (Split-Path -Parent $Exe) 'models'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $done = 0
    for ($k = 0; $k -lt $todo.Count; $k += $Batch) {
        $chunk = @($todo[$k..([Math]::Min($k + $Batch, $todo.Count) - 1)])
        $bin = Join-Path $env:TEMP ('iavatar_upscale_in_' + [guid]::NewGuid().ToString('N'))
        $bout = Join-Path $env:TEMP ('iavatar_upscale_out_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $bin, $bout | Out-Null
        try {
            foreach ($f in $chunk) { Copy-Item -LiteralPath $f.FullName -Destination $bin }
            # PS 5.1: lo stderr di un eseguibile nativo con ErrorActionPreference=Stop diventerebbe un errore bloccante
            $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            & $Exe -i $bin -o $bout -n $Model -s 4 -f png -g $Gpu -m $models 2>&1 | Out-Null
            $code = $LASTEXITCODE
            $ErrorActionPreference = $eap
            if ($code -ne 0) { throw ('Real-ESRGAN terminato con codice {0} (driver Vulkan aggiornato?)' -f $code) }
            foreach ($f in $chunk) {
                $r = Join-Path $bout $f.Name
                if (-not (Test-Path -LiteralPath $r)) { Write-IavLog -Level WARN -Message ('Non prodotto: {0}' -f $f.Name); continue }
                if (-not $Keep4x) { Resize-IavImageHalf -Path $r }
                Move-Item -LiteralPath $r -Destination (Join-Path $Out $f.Name) -Force
                $done++
            }
        } finally {
            Remove-Item -LiteralPath $bin, $bout -Recurse -Force -ErrorAction SilentlyContinue
        }
        $eta = if ($done) { [TimeSpan]::FromSeconds($sw.Elapsed.TotalSeconds / $done * ($todo.Count - $done)) } else { [TimeSpan]::Zero }
        Write-IavLog -Level INFO -Message ('[{0}/{1}] {2:hh\:mm\:ss} trascorsi, circa {3:hh\:mm\:ss} alla fine' -f $done, $todo.Count, $sw.Elapsed, $eta)
    }
    Write-IavLog -Level OK -Message ('Ingrandimento IA completato: {0} texture in {1:hh\:mm\:ss}.' -f $done, $sw.Elapsed)
    return $done
}

function Invoke-IavPython {
    param([Parameter(Mandatory)][string]$Python, [Parameter(Mandatory)][string]$WorkingDir, [Parameter(Mandatory)][string[]]$Arguments)
    Write-IavLog -Level INFO -Message ('python {0}' -f ($Arguments -join ' '))
    $env:PYTHONDONTWRITEBYTECODE = '1'
    $env:PYTHONIOENCODING = 'utf-8'
    Push-Location -LiteralPath $WorkingDir
    try {
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        & $Python -u @Arguments 2>&1 | ForEach-Object {
            $line = "$_"
            # solo le righe significative a schermo; tutto nel log
            $progress = ($line -match '^\[(\d+)/(\d+)\]') -and (([int]$Matches[1] % 250 -eq 0) -or ($Matches[1] -eq $Matches[2]))
            if ($progress -or $line -match '^\[(OK|PARZIALE|SALTATO|PAK)\]' -or $line -match 'Error|Traceback') { Write-IavLog -Level INFO -Message $line }
            else { Write-IavLog -Level DEBUG -Message $line }
        }
        $code = $LASTEXITCODE
        $ErrorActionPreference = $eap
    } finally { Pop-Location }
    return $code
}

function Invoke-IavTextureBuild {
    <#
      Costruisce i pak del livello IAVAT@R dai file del gioco dell'utente. Riprendibile: la pipeline ha una cache
      per texture e il pak e' scritto in streaming; rilanciare continua da dove si era fermata.
      Restituisce l'elenco dei pak prodotti (percorso + nome di destinazione).
    #>
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)]$Game,
        [Parameter(Mandatory)]$Runtime,
        [Parameter(Mandatory)][string]$Python,
        [string]$RealEsrgan,
        [string[]]$Only
    )
    $pipeline = Join-Path $RepoRoot 'moduleB-assets\pipeline'
    $work = Join-Path $RepoRoot 'work'
    $paks = New-Object System.Collections.Generic.List[object]
    foreach ($mf in $Runtime.build.manifests) {
        $mpath = Join-Path $RepoRoot ('moduleB-assets\assets-manifest\{0}' -f $mf.file)
        if (Test-Path -LiteralPath $mpath) { continue }
        $mdir = Split-Path -Parent $mpath
        if (-not (Test-Path -LiteralPath $mdir)) { New-Item -ItemType Directory -Path $mdir -Force | Out-Null }
        Write-IavLog -Level INFO -Message ('Analisi dei materiali del gioco: {0}...' -f $mf.file)
        $code = Invoke-IavPython -Python $Python -WorkingDir $pipeline -Arguments @('discover.py', '--game', $Game.Root, '--root', $mf.root, '--out', $mpath)
        if ($code -ne 0 -or -not (Test-Path -LiteralPath $mpath)) { throw ('Analisi materiali fallita ({0}, codice {1}).' -f $mf.file, $code) }
    }
    foreach ($s in $Runtime.build.steps) {
        if ($Only -and -not ($Only -contains $s.id)) { continue }
        $recipe = Join-Path $RepoRoot ('moduleB-assets\recipes\{0}' -f $s.recipe)
        $out = Join-Path $work ('build\{0}' -f $s.out)
        $pak = Join-Path $out $s.pak
        $report = Join-Path $out 'build-report.json'
        if ((Test-Path -LiteralPath $pak) -and (Test-Path -LiteralPath $report) -and
            ((Get-Item -LiteralPath $report).LastWriteTimeUtc -ge (Get-Item -LiteralPath $recipe).LastWriteTimeUtc)) {
            Write-IavLog -Level OK -Message ('{0}: pak gia'' costruito e verificato ({1}).' -f $s.id, $s.pak)
            $paks.Add([pscustomobject]@{ Id = $s.id; Path = $pak; Name = $s.pak }); continue
        }
        if ($s.PSObject.Properties.Name -contains 'upscale' -and $s.upscale) {
            if (-not $RealEsrgan) { throw 'Real-ESRGAN non preparato.' }
            $in = Join-Path $work 'upscale\in'
            $code = Invoke-IavPython -Python $Python -WorkingDir $pipeline -Arguments @('upscale_export.py', '--recipe', $recipe, '--game', $Game.Root, '--out', $in)
            if ($code -ne 0) { throw ('{0}: esportazione per l''IA fallita (codice {1}). Dettagli nel log.' -f $s.id, $code) }
            [void](Invoke-IavUpscale -Exe $RealEsrgan -Model $Runtime.realesrgan.model -In $in -Out (Join-Path $work 'upscale\out'))
        }
        Write-IavLog -Level INFO -Message ('{0}: costruzione {1} (puo'' richiedere decine di minuti)...' -f $s.id, $s.pak)
        $code = Invoke-IavPython -Python $Python -WorkingDir $pipeline -Arguments @('build.py', '--recipe', $recipe, '--game', $Game.Root, '--out', $out, '--previews', '0')
        if ($code -ne 0 -or -not (Test-Path -LiteralPath $pak)) { throw ('{0}: costruzione fallita (codice {1}). Rilancia: riprende da dove si e'' fermata. Dettagli nel log.' -f $s.id, $code) }
        Write-IavLog -Level OK -Message ('{0}: {1} pronto ({2:n0} MB).' -f $s.id, $s.pak, ((Get-Item -LiteralPath $pak).Length / 1MB))
        $paks.Add([pscustomobject]@{ Id = $s.id; Path = $pak; Name = $s.pak })
    }
    return , $paks.ToArray()
}

function Get-IavStreamingPoolMb {
    param([Parameter(Mandatory)]$Runtime, $VramMb)
    if (-not $VramMb) { return ($Runtime.streaming.poolByVramGb | Sort-Object minGb | Select-Object -First 1).poolMb }
    $gb = [double]$VramMb / 1024
    foreach ($row in ($Runtime.streaming.poolByVramGb | Sort-Object minGb -Descending)) { if ($gb -ge $row.minGb) { return [int]$row.poolMb } }
    return 1200
}

function New-IavTexturePlan {
    <# Piano per il motore transazionale del Modulo A: pak in ~mods (AddFile) + pool di streaming (IniBlock). #>
    param([Parameter(Mandatory)]$Game, [Parameter(Mandatory)][object[]]$Paks, [int]$PoolMb)
    $ops = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[string]
    $notes = New-Object System.Collections.Generic.List[string]
    foreach ($p in $Paks) {
        $dst = Join-Path $Game.ModsDir $p.Name
        Write-IavLog -Level INFO -Message ('Calcolo SHA-256 di {0}...' -f $p.Name)
        $sha = Get-IavSha256 -Path $p.Path
        $adopt = $false
        if (Test-Path -LiteralPath $dst) {
            if ((Get-IavSha256 -Path $dst) -eq $sha) {
                $adopt = $true
                $notes.Add(('{0} e'' gia'' presente ed e'' identico: viene preso in carico (registrato nel manifest, non ricopiato).' -f $dst))
            } else {
                $errors.Add(('Conflitto: {0} esiste gia'' ed e'' diverso. Se e'' una copia di prova messa a mano, rinominala in .off o rimuovila.' -f $dst))
            }
        }
        $ops.Add([pscustomobject]@{
            Id = ('{0:D2}-pak-{1}' -f ($ops.Count + 1), $p.Id); Type = 'AddFile'; Component = ('pak-' + $p.Id)
            Source = $p.Path; Destination = $dst; Sha256 = $sha; Mutable = $false; Info = @{}; Adopt = $adopt
        })
    }
    if ($PoolMb -gt 0) {
        $ops.Add([pscustomobject]@{
            Id = ('{0:D2}-streaming' -f ($ops.Count + 1)); Type = 'IniBlock'; Component = 'streaming'
            Destination = $Game.CustomSettings; Section = 'CustomSettings'
            Lines = @(('r.Streaming.PoolSize={0}' -f $PoolMb))
        })
        $notes.Add(('Pool di streaming texture: {0} MB (il gioco ne riserva 800).' -f $PoolMb))
    }
    [pscustomobject]@{ Operations = $ops.ToArray(); Errors = $errors.ToArray(); Notes = $notes.ToArray() }
}

Export-ModuleMember -Function Get-IavRuntimeConfig, Save-IavVerifiedDownload, Initialize-IavPython, Initialize-IavRealEsrgan,
    Resize-IavImageHalf, Invoke-IavUpscale, Invoke-IavPython, Invoke-IavTextureBuild, Get-IavStreamingPoolMb, New-IavTexturePlan
