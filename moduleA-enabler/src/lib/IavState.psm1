#Requires -Version 5.1
<#
  IAVAT@R Neural Vice City - IavState
  Manifest JSON, cartella di stato, blocchi marcati nei file .ini, snapshot delle cartelle.
#>
Set-StrictMode -Version 2.0

$script:BlockBegin = '; >>> IAVATAR_NeuralViceCity >>> (non modificare: gestito dall''installer)'
$script:BlockEnd = '; <<< IAVATAR_NeuralViceCity <<<'

function Get-IavStateDir {
    param([string]$Override)
    if ($Override) { return $Override }
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = Join-Path $HOME '.local/share' }
    return (Join-Path $base 'IAVATAR\NeuralViceCity')
}

function Get-IavManifestPath { param([Parameter(Mandatory)][string]$StateDir) Join-Path $StateDir 'manifest.json' }

function Read-IavManifest {
    param([Parameter(Mandatory)][string]$StateDir)
    $p = Get-IavManifestPath -StateDir $StateDir
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $m = [IO.File]::ReadAllText($p) | ConvertFrom-Json
    if ($m.schema -ne 1) { throw ('Manifest con schema {0} non supportato: {1}' -f $m.schema, $p) }
    return $m
}

function Save-IavManifest {
    param([Parameter(Mandatory)][string]$StateDir, [Parameter(Mandatory)]$Manifest)
    Write-IavTextFileAtomic -Path (Get-IavManifestPath -StateDir $StateDir) -Content (ConvertTo-IavJson -InputObject $Manifest)
}

function Remove-IavManifest {
    <# Il manifest non viene cancellato: viene archiviato in history\ per tracciabilita'. #>
    param([Parameter(Mandatory)][string]$StateDir, [string]$Suffix = 'uninstalled')
    $p = Get-IavManifestPath -StateDir $StateDir
    if (-not (Test-Path -LiteralPath $p)) { return }
    $hist = Join-Path $StateDir 'history'
    if (-not (Test-Path -LiteralPath $hist)) { New-Item -ItemType Directory -Path $hist -Force | Out-Null }
    Move-Item -LiteralPath $p -Destination (Join-Path $hist ('manifest_{0:yyyyMMdd-HHmmss}_{1}.json' -f (Get-Date), $Suffix)) -Force
}

function Get-IavIniBlockMarkers { [pscustomobject]@{ Begin = $script:BlockBegin; End = $script:BlockEnd } }

function Remove-IavIniBlockFromText {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $lines = $Text -split "`r?`n"
    $out = New-Object System.Collections.Generic.List[string]
    $inside = $false
    foreach ($l in $lines) {
        if ($l.StartsWith('; >>> IAVATAR_NeuralViceCity >>>')) { $inside = $true; continue }
        if ($inside -and $l.StartsWith($script:BlockEnd)) { $inside = $false; continue }
        if (-not $inside) { $out.Add($l) }
    }
    return ($out -join "`r`n")
}

function Add-IavIniBlockToText {
    <# Inserisce il blocco subito sotto l'intestazione di sezione (creandola se manca). Idempotente. #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string[]]$Lines
    )
    $clean = Remove-IavIniBlockFromText -Text $Text
    $block = @($script:BlockBegin) + $Lines + @($script:BlockEnd)
    $src = New-Object System.Collections.Generic.List[string]
    if ($clean.Length -gt 0) { foreach ($l in ($clean -split "`r?`n")) { $src.Add($l) } }
    $header = '[{0}]' -f $Section
    $idx = -1
    for ($i = 0; $i -lt $src.Count; $i++) { if ($src[$i].Trim() -ieq $header) { $idx = $i; break } }
    if ($idx -ge 0) {
        $src.InsertRange($idx + 1, [string[]]$block)
    } else {
        if ($src.Count -gt 0 -and $src[$src.Count - 1].Trim() -ne '') { $src.Add('') }
        $src.Add($header)
        $src.AddRange([string[]]$block)
    }
    $result = ($src -join "`r`n")
    if (-not $result.EndsWith("`r`n")) { $result += "`r`n" }
    return $result
}

function Test-IavIniHasBlock {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return ([IO.File]::ReadAllText($Path)).Contains('; >>> IAVATAR_NeuralViceCity >>>')
}

function Get-IavDirSnapshot {
    <# Elenco dei file (nomi, non ricorsivo) di una cartella: serve a trovare file nuovi creati a runtime. #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    return @(Get-ChildItem -LiteralPath $Path -File -Force | ForEach-Object { $_.Name } | Sort-Object)
}

Export-ModuleMember -Function Get-IavStateDir, Get-IavManifestPath, Read-IavManifest, Save-IavManifest, Remove-IavManifest,
    Get-IavIniBlockMarkers, Remove-IavIniBlockFromText, Add-IavIniBlockToText, Test-IavIniHasBlock, Get-IavDirSnapshot
