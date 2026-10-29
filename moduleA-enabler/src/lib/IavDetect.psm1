#Requires -Version 5.1
<#
  IAVAT@R Neural Vice City - IavDetect
  Rilevamento di Steam, gioco (appid 1546990), GPU/driver, processo in esecuzione.
#>
Set-StrictMode -Version 2.0

$script:AppId = '1546990'

function Get-IavSteamRoot {
    $candidates = @()
    try {
        $reg = Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction Stop
        if ($reg.SteamPath) { $candidates += ($reg.SteamPath -replace '/', '\') }
    } catch { }
    if (${env:ProgramFiles(x86)}) { $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Steam') }
    foreach ($c in $candidates) { if (Test-Path -LiteralPath (Join-Path $c 'steamapps')) { return $c } }
    return $null
}

function Get-IavSteamLibraries {
    param([Parameter(Mandatory)][string]$SteamRoot)
    $libs = New-Object System.Collections.Generic.List[string]
    $libs.Add($SteamRoot)
    $vdf = Join-Path $SteamRoot 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        $text = [IO.File]::ReadAllText($vdf)
        foreach ($m in [regex]::Matches($text, '"path"\s+"([^"]+)"')) {
            $p = $m.Groups[1].Value -replace '\\\\', '\'
            if (-not $libs.Contains($p)) { $libs.Add($p) }
        }
    }
    return , $libs.ToArray()
}

function Read-IavAcfValue {
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$Key)
    $m = [regex]::Match($Text, ('"{0}"\s+"([^"]*)"' -f [regex]::Escape($Key)))
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Get-IavGameInfo {
    <#
      -GamePath forza la cartella del gioco; altrimenti ricerca nelle librerie Steam.
      -DocumentsPath serve ai test (default: cartella Documenti dell'utente).
    #>
    param([string]$GamePath, [string]$DocumentsPath)

    $root = $null; $buildId = $null; $acfPath = $null
    if ($GamePath) {
        $root = (Resolve-Path -LiteralPath $GamePath -ErrorAction Stop).ProviderPath
        $common = Split-Path -Parent $root
        $acf = Join-Path (Split-Path -Parent $common) ('appmanifest_{0}.acf' -f $script:AppId)
        if (Test-Path -LiteralPath $acf) { $acfPath = $acf }
    } else {
        $steam = Get-IavSteamRoot
        if (-not $steam) { throw 'Steam non trovato. Usa -GamePath per indicare la cartella del gioco.' }
        foreach ($lib in (Get-IavSteamLibraries -SteamRoot $steam)) {
            $acf = Join-Path $lib ('steamapps\appmanifest_{0}.acf' -f $script:AppId)
            if (Test-Path -LiteralPath $acf) {
                $txt = [IO.File]::ReadAllText($acf)
                $dir = Read-IavAcfValue -Text $txt -Key 'installdir'
                $cand = Join-Path $lib ('steamapps\common\{0}' -f $dir)
                if (Test-Path -LiteralPath $cand) { $root = $cand; $acfPath = $acf; break }
            }
        }
        if (-not $root) { throw 'GTA Vice City - The Definitive Edition (appid 1546990) non trovato nelle librerie Steam. Usa -GamePath.' }
    }
    if ($acfPath) { $buildId = Read-IavAcfValue -Text ([IO.File]::ReadAllText($acfPath)) -Key 'buildid' }

    $win64 = Join-Path $root 'Gameface\Binaries\Win64'
    $exe = Join-Path $win64 'ViceCity.exe'
    if (-not (Test-Path -LiteralPath $exe)) { throw ('ViceCity.exe non trovato in {0}: la cartella non sembra quella del gioco.' -f $win64) }

    if (-not $DocumentsPath) { $DocumentsPath = [Environment]::GetFolderPath('MyDocuments') }
    $userCfg = Join-Path $DocumentsPath 'Rockstar Games\GTA Vice City Definitive Edition\Config\WindowsNoEditor'
    $pe = Get-IavPeInfo -Path $exe

    [pscustomobject]@{
        Root            = $root
        Win64           = $win64
        Exe             = $exe
        ExeSha256       = (Get-IavSha256 -Path $exe)
        ExeVersion      = $(if ($pe -and $pe.FileVersion) { $pe.FileVersion.ToString() } else { $null })
        BuildId         = $buildId
        AppManifest     = $acfPath
        NgxOverrideDir  = (Join-Path $root 'Gameface\Binaries\ThirdParty\NVIDIA\NGX\Win64')
        NativeDlssDll   = (Join-Path $root 'Engine\Plugins\Runtime\Nvidia\DLSS\Binaries\ThirdParty\Win64\nvngx_dlss.dll')
        ModsDir         = (Join-Path $root 'Gameface\Content\Paks\~Mods')
        UserConfigDir   = $userCfg
        CustomSettings  = (Join-Path $userCfg 'CustomSettings.ini')
    }
}

function Get-IavGpuInfo {
    $name = $null; $driver = $null; $cc = $null; $vram = $null
    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($smi) {
        try {
            $out = & $smi.Source '--query-gpu=name,driver_version,compute_cap,memory.total' '--format=csv,noheader,nounits' 2>$null | Select-Object -First 1
            if ($out) {
                $parts = $out -split ',\s*'
                $name = $parts[0]; $driver = $parts[1]
                if ($parts.Count -ge 3) { $cc = $parts[2] }
                if ($parts.Count -ge 4) { $mb = 0; if ([int]::TryParse($parts[3].Trim(), [ref]$mb)) { $vram = $mb } }
            }
        } catch { }
    }
    if (-not $name -and (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
        try {
            $vc = Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -First 1
            if ($vc) { $name = $vc.Name }
        } catch { }
    }
    $isRtx50 = $false
    if ($cc) { $isRtx50 = ([double]::Parse($cc, [Globalization.CultureInfo]::InvariantCulture) -ge 12.0) }
    elseif ($name) { $isRtx50 = ($name -match 'RTX\s*50\d\d') }
    [pscustomobject]@{ Name = $name; DriverVersion = $driver; ComputeCapability = $cc; IsRtx50 = $isRtx50; VramMb = $vram }
}

function Test-IavGameRunning {
    $p = Get-Process -Name 'ViceCity', 'PlayGTAViceCity' -ErrorAction SilentlyContinue
    return [bool]$p
}

function Find-IavUserComponents {
    <#
      Cerca i file che l'utente deve procurarsi da fonti ufficiali (non ridistribuibili):
        - add-on RenoDX DLSS 5 (*.addon64) nella cartella Download o in C:\IAVATAR_input;
        - nvngx_dlssnr.dll e nvngx_dlss.dll di RTX Remix (installato con l'app NVIDIA).
      Restituisce solo percorsi: la validazione (firma NVIDIA, allowlist, versione) la fa il piano.
    #>
    param([string[]]$SearchDirs, [string]$RemixRoot)
    if (-not $SearchDirs) {
        $SearchDirs = @()
        if ($env:USERPROFILE) { $SearchDirs += (Join-Path $env:USERPROFILE 'Downloads') }
        $SearchDirs += 'C:\IAVATAR_input'
    }
    if (-not $RemixRoot -and $env:ProgramFiles) { $RemixRoot = Join-Path $env:ProgramFiles 'NVIDIA Corporation\RTX Remix' }
    $found = @{}
    $addons = @(foreach ($d in $SearchDirs) { if (Test-Path -LiteralPath $d) { Get-ChildItem -LiteralPath $d -Filter '*dlss5*.addon64' -File -ErrorAction SilentlyContinue } })
    if ($addons.Count) { $found.renodx = ($addons | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName }
    $remix = if ($RemixRoot) { Join-Path $RemixRoot 'deps\remix_runtime\runtime\.trex' } else { $null }
    foreach ($pair in @(@('dlssnr', 'nvngx_dlssnr.dll'), @('dlsssr', 'nvngx_dlss.dll'))) {
        $cands = @()
        foreach ($d in $SearchDirs) { $cands += (Join-Path $d $pair[1]) }
        if ($remix) { $cands += (Join-Path $remix $pair[1]) }
        $hit = $cands | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($hit) { $found[$pair[0]] = $hit }
    }
    return $found
}

Export-ModuleMember -Function Get-IavSteamRoot, Get-IavSteamLibraries, Get-IavGameInfo, Get-IavGpuInfo, Test-IavGameRunning, Find-IavUserComponents
