#Requires -Version 5.1
<#
  IAVAT@R Neural Vice City - IavRelease
  Costruzione del pacchetto da pubblicare (zip) con una GUARDIA che blocca qualunque file proprietario:
  file del gioco (pak, asset UE cotti, texture), DLL NVIDIA o di terzi, eseguibili, archivi, binari in genere.
  La release contiene SOLO sorgenti e configurazione testuale: tutto il resto si procura o si costruisce
  sul PC dell'utente (vedi docs/INSTALL.md).
#>
Set-StrictMode -Version 2.0

# Cosa entra nel pacchetto: elenco esplicito (allowlist). Tutto il resto, work\ compreso, resta fuori.
$script:Include = @(
    'IAVATAR_Setup.ps1', 'README.md', 'LICENSE', 'CREDITS.md', 'CHANGELOG.md',
    'docs/INSTALL.md', 'docs/ARCHITECTURE.md', 'docs/MODULO-B.md',
    'moduleA-enabler/config/*.json', 'moduleA-enabler/presets/*.ini',
    'moduleA-enabler/src/*.ps1', 'moduleA-enabler/src/lib/*.psm1',
    'moduleB-assets/config/*.json', 'moduleB-assets/pipeline/*.py',
    'moduleB-assets/recipes/characters-v3.json', 'moduleB-assets/recipes/environment-v2.json',
    'moduleB-assets/recipes/environment-hd-v1.json',
    'tests/moduleA/*.ps1', 'tests/moduleB/*.py',
    'release/*.ps1', 'release/*.psm1'
)
$script:AllowedExt = @('.ps1', '.psm1', '.psd1', '.py', '.json', '.ini', '.md', '')
$script:BlockedExt = @('.pak', '.utoc', '.ucas', '.uasset', '.uexp', '.ubulk', '.umap', '.dll', '.exe', '.sys',
    '.addon64', '.addon32', '.dds', '.png', '.jpg', '.jpeg', '.tga', '.bmp', '.bnk', '.wem', '.bik', '.zip', '.7z',
    '.rar', '.whl', '.pyd', '.so', '.bin', '.param', '.msi', '.cab')
$script:BlockedNames = @('nvngx*', 'oo2core*', 'ReShade64*', 'ReShade32*', 'dxgi*', 'd3d*', 'renodx*', 'realesrgan*', 'python*.zip')
$script:MaxBytes = 1MB

function Get-IavReleaseFiles {
    <# File candidati (percorsi relativi con '/') secondo l'allowlist. #>
    param([Parameter(Mandatory)][string]$RepoRoot)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($pat in $script:Include) {
        $dir = Join-Path $RepoRoot (Split-Path -Parent $pat)
        $leaf = Split-Path -Leaf $pat
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter $leaf -File -Force -ErrorAction SilentlyContinue)) {
            $rel = $f.FullName.Substring($RepoRoot.TrimEnd('\', '/').Length + 1) -replace '\\', '/'
            if (-not $out.Contains($rel)) { $out.Add($rel) }
        }
    }
    return @($out.ToArray() | Sort-Object)
}

function Test-IavReleaseFile {
    <#
      Guardia su un singolo file. Restituisce l'elenco dei motivi di blocco (vuoto = consentito).
      Controlla: percorso (work\, docs\recon), estensione, nome, dimensione, firma binaria (PE "MZ",
      package UE 9E2A83C1, pak UE E1126F5A, DDS, ZIP, PNG), testo UTF-8 valido senza byte nulli.
    #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$RelativePath)
    $why = New-Object System.Collections.Generic.List[string]
    $rel = $RelativePath -replace '\\', '/'
    if ($rel -match '(^|/)(work|\.git|docs/recon|release/dist|__pycache__)(/|$)') { $why.Add('cartella esclusa') }
    $name = [IO.Path]::GetFileName($Path)
    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($script:BlockedExt -contains $ext) { $why.Add(('estensione vietata {0}' -f $ext)) }
    elseif (-not ($script:AllowedExt -contains $ext)) { $why.Add(('estensione non in allowlist {0}' -f $ext)) }
    foreach ($n in $script:BlockedNames) { if ($name -like $n) { $why.Add(('nome vietato ({0})' -f $n)) } }
    $len = (Get-Item -LiteralPath $Path).Length
    if ($len -gt $script:MaxBytes) { $why.Add(('troppo grande ({0:n0} byte)' -f $len)) }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 4) {
        $b0 = $bytes[0]; $b1 = $bytes[1]; $b2 = $bytes[2]; $b3 = $bytes[3]
        if ($b0 -eq 0x4D -and $b1 -eq 0x5A) { $why.Add('eseguibile/DLL (firma MZ)') }
        if ($b0 -eq 0xC1 -and $b1 -eq 0x83 -and $b2 -eq 0x2A -and $b3 -eq 0x9E) { $why.Add('package Unreal (9E2A83C1)') }
        if ($b0 -eq 0x44 -and $b1 -eq 0x44 -and $b2 -eq 0x53 -and $b3 -eq 0x20) { $why.Add('texture DDS') }
        if ($b0 -eq 0x50 -and $b1 -eq 0x4B -and $b2 -eq 0x03 -and $b3 -eq 0x04) { $why.Add('archivio ZIP') }
        if ($b0 -eq 0x89 -and $b1 -eq 0x50 -and $b2 -eq 0x4E -and $b3 -eq 0x47) { $why.Add('immagine PNG') }
    }
    # magic del pak UE (0x5A6F12E1, little-endian E1 12 6F 5A) ovunque nel file
    $latin = [Text.Encoding]::GetEncoding(28591).GetString($bytes)
    if ($latin.IndexOf([string]([char]0xE1) + [char]0x12 + [char]0x6F + [char]0x5A, [StringComparison]::Ordinal) -ge 0) { $why.Add('contiene la firma di un pak Unreal') }
    if ([Array]::IndexOf($bytes, [byte]0) -ge 0) { $why.Add('contiene byte nulli: non e'' testo') }
    else {
        try { [void](New-Object Text.UTF8Encoding($false, $true)).GetString($bytes) } catch { $why.Add('non e'' testo UTF-8 valido') }
    }
    return , $why.ToArray()
}

function New-IavReleasePackage {
    <#
      Crea <OutDir>\IAVATAR_NeuralViceCity_v<Version>.zip (cartella radice con lo stesso nome), con
      RELEASE-MANIFEST.txt (SHA-256 di ogni file) dentro lo zip e lo SHA-256 dello zip accanto.
      Se la guardia trova anche un solo file vietato, NON crea nulla e restituisce le violazioni.
    #>
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$Version, [Parameter(Mandatory)][string]$OutDir,
          [string[]]$ExtraFiles)
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
    $files = @(@(Get-IavReleaseFiles -RepoRoot $RepoRoot) + @($ExtraFiles) | Where-Object { $_ })
    $violations = New-Object System.Collections.Generic.List[string]
    $manifest = New-Object System.Collections.Generic.List[string]
    foreach ($rel in $files) {
        $p = Join-Path $RepoRoot $rel
        $why = Test-IavReleaseFile -Path $p -RelativePath $rel
        if ($why.Count) { $violations.Add(('{0}: {1}' -f $rel, ($why -join '; '))) }
        else { $manifest.Add(('{0}  {1}' -f (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToUpperInvariant(), $rel)) }
    }
    $name = 'IAVATAR_NeuralViceCity_v{0}' -f $Version
    $zip = Join-Path $OutDir ($name + '.zip')
    if ($violations.Count) {
        return [pscustomobject]@{ Ok = $false; Zip = $null; Files = $files.Count; Violations = $violations.ToArray() }
    }
    if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $fs = [IO.File]::Open($zip, [IO.FileMode]::CreateNew)
    $za = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($rel in $files) {
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($za, (Join-Path $RepoRoot $rel), ($name + '/' + $rel), [IO.Compression.CompressionLevel]::Optimal)
        }
        $header = @('IAVAT@R Neural Vice City v' + $Version, 'SHA-256 di ogni file del pacchetto. Nessun file del gioco, nessuna DLL, nessun binario.', '')
        $e = $za.CreateEntry($name + '/RELEASE-MANIFEST.txt')
        $w = New-Object IO.StreamWriter($e.Open(), (New-Object Text.UTF8Encoding($false)))
        try { foreach ($l in ($header + $manifest)) { $w.Write($l + "`r`n") } } finally { $w.Dispose() }
    } finally { $za.Dispose(); $fs.Dispose() }
    $sha = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToUpperInvariant()
    [IO.File]::WriteAllText($zip + '.sha256', ('{0}  {1}' -f $sha, (Split-Path -Leaf $zip)) + "`r`n")
    return [pscustomobject]@{ Ok = $true; Zip = $zip; Sha256 = $sha; Files = $files.Count; Violations = @() }
}

Export-ModuleMember -Function Get-IavReleaseFiles, Test-IavReleaseFile, New-IavReleasePackage
