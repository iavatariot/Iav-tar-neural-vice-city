#Requires -Version 5.1
<#
  IAVAT@R Neural Vice City - IavCore
  Log, banner, utility, lettura PE (versione/architettura), hash, firma Authenticode.
  Compatibile Windows PowerShell 5.1 e PowerShell 7.
#>
Set-StrictMode -Version 2.0

$script:LogFile = $null
$script:SignatureProvider = $null   # iniettabile nei test: scriptblock { param($Path) ... }

function Get-IavBanner {
    @'
  ___    _    __     __    _    _____    ____   ____
 |_ _|  / \   \ \   / /   / \  |_   _|  / __ \ |  _ \
  | |  / _ \   \ \ / /   / _ \   | |   / / _` || |_) |
  | | / ___ \   \ V /   / ___ \  | |  | | (_| ||  _ <
 |___/_/   \_\   \_/   /_/   \_\ |_|   \ \__,_||_| \_\
                                        \____/
         N E U R A L   V I C E   C I T Y
'@
}

function Initialize-IavLog {
    param([Parameter(Mandatory)][string]$Directory)
    if (-not (Test-Path -LiteralPath $Directory)) { New-Item -ItemType Directory -Path $Directory -Force | Out-Null }
    $script:LogFile = Join-Path $Directory ('IAVATAR_NeuralViceCity_{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
    Write-IavLog -Level INFO -Message ('Log: {0}' -f $script:LogFile)
    return $script:LogFile
}

function Get-IavLogFile { $script:LogFile }

function Write-IavLog {
    param(
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'DEBUG', 'PLAN')][string]$Level = 'INFO',
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message
    )
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1,-5}] {2}' -f (Get-Date), $Level, $Message
    if ($script:LogFile) {
        try { [IO.File]::AppendAllText($script:LogFile, $line + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false))) } catch { }
    }
    if ($Level -eq 'DEBUG' -and $VerbosePreference -eq 'SilentlyContinue') { return }
    $color = switch ($Level) { 'OK' { 'Green' } 'WARN' { 'Yellow' } 'ERROR' { 'Red' } 'PLAN' { 'Cyan' } default { 'Gray' } }
    Write-Host $line -ForegroundColor $color
}

function Get-IavSha256 {
    param([Parameter(Mandatory)][string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-IavPeInfo {
    <#
      Legge un file PE senza caricarlo: architettura e VS_FIXEDFILEINFO (FileVersion).
      Restituisce $null se il file non e' un PE valido.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 0x40 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { return $null }
    $peOff = [BitConverter]::ToInt32($bytes, 0x3C)
    if ($peOff -lt 0 -or ($peOff + 26) -gt $bytes.Length) { return $null }
    if ($bytes[$peOff] -ne 0x50 -or $bytes[$peOff + 1] -ne 0x45 -or $bytes[$peOff + 2] -ne 0 -or $bytes[$peOff + 3] -ne 0) { return $null }
    $machine = [BitConverter]::ToUInt16($bytes, $peOff + 4)
    $arch = switch ($machine) { 0x8664 { 'x64' } 0x014C { 'x86' } 0xAA64 { 'arm64' } default { ('0x{0:X4}' -f $machine) } }

    $version = $null
    # Ricerca della firma VS_FIXEDFILEINFO 0xFEEF04BD (little-endian BD 04 EF FE).
    # [Array]::IndexOf e' nativo: necessario per DLL da 150+ MB.
    $i = 0
    while ($true) {
        $i = [Array]::IndexOf($bytes, [byte]0xBD, $i)
        if ($i -lt 0 -or $i -gt $bytes.Length - 16) { break }
        if ($bytes[$i + 1] -eq 0x04 -and $bytes[$i + 2] -eq 0xEF -and $bytes[$i + 3] -eq 0xFE) {
            $ms = [BitConverter]::ToUInt32($bytes, $i + 8)
            $ls = [BitConverter]::ToUInt32($bytes, $i + 12)
            $version = New-Object Version ([int]($ms -shr 16)), ([int]($ms -band 0xFFFF)), ([int]($ls -shr 16)), ([int]($ls -band 0xFFFF))
            break
        }
        $i++
    }
    [pscustomobject]@{ Path = $Path; Architecture = $arch; FileVersion = $version }
}

function Test-IavFileContainsText {
    <# Cerca una stringa (ASCII o UTF-16LE) nel file, es. il ProductName "ReShade". #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Text)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $latin = [Text.Encoding]::GetEncoding(28591).GetString($bytes)
    if ($latin.Contains($Text)) { return $true }
    $u16 = [Text.Encoding]::GetEncoding(28591).GetString([Text.Encoding]::Unicode.GetBytes($Text))
    return $latin.Contains($u16)
}

function Get-IavSignature {
    <#
      Firma Authenticode: Status (Valid/NotSigned/HashMismatch/...) e Subject del firmatario.
      Su Windows usa Get-AuthenticodeSignature; nei test si inietta $script:SignatureProvider.
    #>
    param([Parameter(Mandatory)][string]$Path)
    if ($script:SignatureProvider) { return (& $script:SignatureProvider $Path) }
    if (-not (Get-Command Get-AuthenticodeSignature -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Status = 'Unavailable'; Subject = $null }
    }
    $s = Get-AuthenticodeSignature -LiteralPath $Path
    $subject = $null
    if ($s.SignerCertificate) { $subject = $s.SignerCertificate.Subject }
    [pscustomobject]@{ Status = [string]$s.Status; Subject = $subject }
}

function Set-IavSignatureProvider {
    param([scriptblock]$Provider)
    $script:SignatureProvider = $Provider
}

function Test-IavNvidiaSigned {
    param([Parameter(Mandatory)][string]$Path)
    $s = Get-IavSignature -Path $Path
    [pscustomobject]@{
        Ok      = ($s.Status -eq 'Valid' -and $s.Subject -match 'O="?NVIDIA Corporation')
        Status  = $s.Status
        Subject = $s.Subject
    }
}

function Test-IavAdmin {
    if ($env:OS -ne 'Windows_NT') { return $true }
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-IavJson {
    param([Parameter(Mandatory)]$InputObject)
    $InputObject | ConvertTo-Json -Depth 12
}

function Write-IavTextFileAtomic {
    <# Scrittura atomica: file temporaneo nella stessa cartella e poi sostituzione. #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Content, [switch]$Bom)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tmp = $Path + '.iavtmp'
    [IO.File]::WriteAllText($tmp, $Content, (New-Object Text.UTF8Encoding([bool]$Bom)))
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

Export-ModuleMember -Function Get-IavBanner, Initialize-IavLog, Get-IavLogFile, Write-IavLog, Get-IavSha256, Get-IavPeInfo,
    Test-IavFileContainsText, Get-IavSignature, Set-IavSignatureProvider, Test-IavNvidiaSigned, Test-IavAdmin,
    ConvertTo-IavJson, Write-IavTextFileAtomic
