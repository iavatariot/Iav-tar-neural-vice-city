#Requires -Version 5.1
<#
  IAVAT@R Neural Vice City - IavReShade
  Download di ReShade SOLO dall'URL ufficiale configurato, verifica SHA-256, estrazione di ReShade64.dll
  dall'archivio incluso nel setup SENZA eseguire il setup.
#>
Set-StrictMode -Version 2.0

function Expand-IavEmbeddedZipEntry {
    <#
      Il setup di ReShade contiene un archivio ZIP accodato all'eseguibile. Individua l'End Of Central
      Directory, ricava l'inizio dello ZIP e ne estrae una voce. Non esegue alcun codice del setup.
    #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$EntryName, [Parameter(Mandatory)][string]$Destination)
    Add-Type -AssemblyName System.IO.Compression
    $bytes = [IO.File]::ReadAllBytes($Path)
    $eocd = -1
    for ($i = $bytes.Length - 22; $i -ge [Math]::Max(0, $bytes.Length - 65557); $i--) {
        if ($bytes[$i] -eq 0x50 -and $bytes[$i + 1] -eq 0x4B -and $bytes[$i + 2] -eq 0x05 -and $bytes[$i + 3] -eq 0x06) { $eocd = $i; break }
    }
    if ($eocd -lt 0) { throw ('Nessun archivio ZIP trovato in {0}' -f $Path) }
    $cdSize = [BitConverter]::ToUInt32($bytes, $eocd + 12)
    $cdOffset = [BitConverter]::ToUInt32($bytes, $eocd + 16)
    $zipStart = $eocd - $cdSize - $cdOffset
    if ($zipStart -lt 0) { throw 'Struttura ZIP non valida nel setup.' }
    $ms = New-Object IO.MemoryStream(, $bytes)
    [void]$ms.Seek($zipStart, 'Begin')
    $slice = New-Object IO.MemoryStream
    $ms.CopyTo($slice); [void]$slice.Seek(0, 'Begin')
    $zip = New-Object IO.Compression.ZipArchive($slice, [IO.Compression.ZipArchiveMode]::Read)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -ieq $EntryName -or $_.Name -ieq $EntryName } | Select-Object -First 1
        if (-not $entry) { throw ('{0} non presente nell''archivio. Voci: {1}' -f $EntryName, (($zip.Entries | ForEach-Object { $_.FullName }) -join ', ')) }
        $dir = Split-Path -Parent $Destination
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $in = $entry.Open(); $out = [IO.File]::Create($Destination)
        try { $in.CopyTo($out) } finally { $out.Dispose(); $in.Dispose() }
    } finally { $zip.Dispose(); $slice.Dispose(); $ms.Dispose() }
    return $Destination
}

function Get-IavReShadeFromOfficial {
    param(
        [Parameter(Mandatory)]$DownloadConfig,
        [Parameter(Mandatory)][string]$StateDir,
        [switch]$TrustNewHash
    )
    $url = $DownloadConfig.url
    if ($url -notmatch '^https://reshade\.me/downloads/') { throw ('URL non ufficiale rifiutato: {0}' -f $url) }
    $dlDir = Join-Path $StateDir 'downloads'
    if (-not (Test-Path -LiteralPath $dlDir)) { New-Item -ItemType Directory -Path $dlDir -Force | Out-Null }
    $file = Join-Path $dlDir (Split-Path -Leaf $url)

    Write-IavLog -Level INFO -Message ('Download ufficiale: {0}' -f $url)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
    try { Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing -ErrorAction Stop }
    finally { $ProgressPreference = $old }

    $sha = Get-IavSha256 -Path $file
    Write-IavLog -Level INFO -Message ('SHA-256 {0}: {1}' -f (Split-Path -Leaf $file), $sha)
    $pinned = $DownloadConfig.sha256
    if ($pinned) {
        if ($sha -ne $pinned.ToUpperInvariant()) { Remove-Item -LiteralPath $file -Force; throw ('Hash del setup ReShade diverso da quello atteso ({0}). File eliminato.' -f $pinned) }
        Write-IavLog -Level OK -Message 'Hash del setup ReShade verificato.'
    } elseif (-not $TrustNewHash) {
        throw ('Nessun hash di riferimento per {0}. Verifica il file e rilancia con -TrustNewHash; registra poi l''hash {1} in config/components.json.' -f $url, $sha)
    } else {
        Write-IavLog -Level WARN -Message ('Hash non ancora registrato nel config: accettato con -TrustNewHash. Registra {0} in components.json.' -f $sha)
    }

    $dll = Join-Path $dlDir $DownloadConfig.innerFile
    if (Test-Path -LiteralPath $dll) { Remove-Item -LiteralPath $dll -Force }
    [void](Expand-IavEmbeddedZipEntry -Path $file -EntryName $DownloadConfig.innerFile -Destination $dll)
    Write-IavLog -Level OK -Message ('Estratto {0} (sha256 {1}) senza eseguire il setup.' -f $dll, (Get-IavSha256 -Path $dll))
    return $dll
}

Export-ModuleMember -Function Expand-IavEmbeddedZipEntry, Get-IavReShadeFromOfficial
