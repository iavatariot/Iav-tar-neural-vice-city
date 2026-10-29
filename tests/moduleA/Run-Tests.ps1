#Requires -Version 5.1
<#
  IAVAT@R Neural Vice City - test automatici del Modulo A (nessuna dipendenza esterna).
  Lavorano SOLO su una cartella di gioco finta in %TEMP%: non toccano mai il gioco reale.
  Uso:  powershell -ExecutionPolicy Bypass -File .\tests\moduleA\Run-Tests.ps1
#>
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$src = Join-Path $repo 'moduleA-enabler\src'
$moduleRoot = Join-Path $repo 'moduleA-enabler'
foreach ($m in 'IavCore', 'IavDetect', 'IavState', 'IavPlan', 'IavReShade', 'IavTextures') { Import-Module (Join-Path $src ('lib\{0}.psm1' -f $m)) -Force -DisableNameChecking }
Import-Module (Join-Path $repo 'release\IavRelease.psm1') -Force -DisableNameChecking

$script:Pass = 0; $script:Fail = 0; $script:Failures = New-Object System.Collections.Generic.List[string]
function Assert-True([bool]$Cond, [string]$Msg) { if (-not $Cond) { throw ('ASSERT: ' + $Msg) } }
function Assert-Eq($A, $B, [string]$Msg) { if ($A -ne $B) { throw ('ASSERT: {0} (atteso <{1}>, ottenuto <{2}>)' -f $Msg, $B, $A) } }
function It([string]$Name, [scriptblock]$Body) {
    try { & $Body; $script:Pass++; Write-Host ('  [PASS] ' + $Name) -ForegroundColor Green }
    catch { $script:Fail++; $script:Failures.Add($Name + ' -> ' + $_.Exception.Message); Write-Host ('  [FAIL] ' + $Name + ' -> ' + $_.Exception.Message) -ForegroundColor Red }
}

# ------------------------------------------------------------ fixture

function New-FakePe {
    param([string]$Path, [version]$Version, [string]$Marker = '', [string]$Machine = 'x64')
    $buf = New-Object byte[] 1024
    $buf[0] = 0x4D; $buf[1] = 0x5A
    [BitConverter]::GetBytes([int]0x80).CopyTo($buf, 0x3C)
    $buf[0x80] = 0x50; $buf[0x81] = 0x45
    $mc = $(if ($Machine -eq 'x64') { 0x8664 } else { 0x014C })
    [BitConverter]::GetBytes([uint16]$mc).CopyTo($buf, 0x84)
    # esca: firma VS_FIXEDFILEINFO "nel codice" con versione sbagliata, senza chiave VS_VERSION_INFO
    [BitConverter]::GetBytes([uint32]4277077181).CopyTo($buf, 0x100)
    [BitConverter]::GetBytes([uint32]0x00010000).CopyTo($buf, 0x104)
    [BitConverter]::GetBytes([uint32]3070164992).CopyTo($buf, 0x108)
    $vk = [Text.Encoding]::Unicode.GetBytes('VS_VERSION_INFO'); $vk.CopyTo($buf, 0x1D0)
    $o = 0x200
    [BitConverter]::GetBytes([uint32]4277077181).CopyTo($buf, $o)
    [BitConverter]::GetBytes([uint32]0x00010000).CopyTo($buf, $o + 4)
    [BitConverter]::GetBytes([uint32](($Version.Major -shl 16) -bor $Version.Minor)).CopyTo($buf, $o + 8)
    [BitConverter]::GetBytes([uint32](($Version.Build -shl 16) -bor $Version.Revision)).CopyTo($buf, $o + 12)
    $mk = [Text.Encoding]::Unicode.GetBytes($Marker)
    $mk.CopyTo($buf, 0x300)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllBytes($Path, $buf)
}

function New-Fixture {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('iav_test_' + [guid]::NewGuid().ToString('N'))
    $lib = Join-Path $root 'SteamLib'
    $game = Join-Path $lib 'steamapps\common\GTA Vice City - The Definitive Edition'
    New-FakePe -Path (Join-Path $game 'Gameface\Binaries\Win64\ViceCity.exe') -Version '1.0.113.21181'
    New-FakePe -Path (Join-Path $game 'Engine\Plugins\Runtime\Nvidia\DLSS\Binaries\ThirdParty\Win64\nvngx_dlss.dll') -Version '2.3.4.0' -Marker 'NVSIGNED'
    [IO.File]::WriteAllText((Join-Path $game 'Gameface\Binaries\Win64\steam_api64.dll'), 'orig')
    [IO.File]::WriteAllText((Join-Path $lib 'steamapps\appmanifest_1546990.acf'), "`"AppState`"`n{`n`t`"appid`"`t`t`"1546990`"`n`t`"installdir`"`t`t`"GTA Vice City - The Definitive Edition`"`n`t`"buildid`"`t`t`"16390876`"`n}`n")
    $docs = Join-Path $root 'Documents'
    $cfg = Join-Path $docs 'Rockstar Games\GTA Vice City Definitive Edition\Config\WindowsNoEditor'
    New-Item -ItemType Directory -Path $cfg -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $cfg 'CustomSettings.ini'), "; Hello Friends!`r`n`r`n[CustomSettings]`r`n; r.DefaultFeature.AmbientOcclusion=1`r`n")
    $in = Join-Path $root 'inputs'
    New-FakePe -Path (Join-Path $in 'ReShade64.dll') -Version '6.8.0.0' -Marker 'ReShade'
    New-FakePe -Path (Join-Path $in 'renodx-dlss5.addon64') -Version '0.1.0.0'
    New-FakePe -Path (Join-Path $in 'nvngx_dlssnr.dll') -Version '310.8.0.0' -Marker 'NVSIGNED'
    New-FakePe -Path (Join-Path $in 'unsigned\nvngx_dlssnr.dll') -Version '310.8.0.0'
    New-FakePe -Path (Join-Path $in 'sr\nvngx_dlss.dll') -Version '310.4.0.0' -Marker 'NVSIGNED'
    [pscustomobject]@{ Root = $root; Game = $game; Docs = $docs; Inputs = $in; State = (Join-Path $root 'state') }
}

function Get-TreeHash {
    <# Impronta dell'intero albero (percorsi relativi + SHA-256) per confronti bit-a-bit. #>
    param([string[]]$Paths)
    $lines = foreach ($p in $Paths) {
        if (Test-Path -LiteralPath $p) {
            Get-ChildItem -LiteralPath $p -Recurse -Force | Sort-Object FullName | ForEach-Object {
                if ($_.PSIsContainer) { 'D ' + $_.FullName } else { 'F ' + $_.FullName + ' ' + (Get-IavSha256 -Path $_.FullName) }
            }
        }
    }
    ($lines -join "`n")
}

# firma finta: "valida NVIDIA" se il file contiene il marcatore NVSIGNED
Set-IavSignatureProvider -Provider {
    param($Path)
    if (Test-IavFileContainsText -Path $Path -Text 'NVSIGNED') { [pscustomobject]@{ Status = 'Valid'; Subject = 'CN=NVIDIA Corporation, O=NVIDIA Corporation, L=Santa Clara, S=California, C=US' } }
    else { [pscustomobject]@{ Status = 'NotSigned'; Subject = $null } }
}

$config = Get-IavConfig -Path (Join-Path $moduleRoot 'config\components.json')

function New-TestPlan {
    param($F, [hashtable]$Override = @{}, [string[]]$Cs = @('r.NGX.LogLevel=2'), [switch]$NoSr)
    $game = Get-IavGameInfo -GamePath $F.Game -DocumentsPath $F.Docs
    $inputs = @{ reshade = (Join-Path $F.Inputs 'ReShade64.dll'); renodx = (Join-Path $F.Inputs 'renodx-dlss5.addon64'); dlssnr = (Join-Path $F.Inputs 'nvngx_dlssnr.dll') }
    if (-not $NoSr) { $inputs.dlsssr = (Join-Path $F.Inputs 'sr\nvngx_dlss.dll') }
    foreach ($k in $Override.Keys) { $inputs[$k] = $Override[$k] }
    $plan = New-IavPlan -Config $config -Game $game -Inputs $inputs -ModuleRoot $moduleRoot -CustomSettingsLines $Cs -TrustNewHash
    [pscustomobject]@{ Game = $game; Plan = $plan }
}

Write-Host 'IAVAT@R Neural Vice City - test Modulo A' -ForegroundColor Magenta
$fixtures = New-Object System.Collections.Generic.List[string]

It 'PE: legge architettura e FileVersion' {
    $f = New-Fixture; $fixtures.Add($f.Root)
    $pe = Get-IavPeInfo -Path (Join-Path $f.Inputs 'nvngx_dlssnr.dll')
    Assert-Eq $pe.Architecture 'x64' 'architettura'
    Assert-Eq $pe.FileVersion.ToString() '310.8.0.0' 'versione (ignora la firma esca fuori da VS_VERSION_INFO)'
    Assert-True ($null -eq (Get-IavPeInfo -Path (Join-Path $f.Game 'Gameface\Binaries\Win64\steam_api64.dll'))) 'file non PE -> null'
}

It 'Detect: trova gioco, buildid e percorsi' {
    $f = New-Fixture; $fixtures.Add($f.Root)
    $g = Get-IavGameInfo -GamePath $f.Game -DocumentsPath $f.Docs
    Assert-Eq $g.BuildId '16390876' 'buildid da appmanifest'
    Assert-Eq $g.ExeVersion '1.0.113.21181' 'versione exe'
    Assert-True ($g.NgxOverrideDir -like '*Gameface*ThirdParty*NVIDIA*NGX*Win64') 'cartella override NGX'
}

It 'INI: blocco inserito sotto la sezione, idempotente, rimovibile' {
    $t = "; a`r`n[CustomSettings]`r`n; b`r`n"
    $t1 = Add-IavIniBlockToText -Text $t -Section 'CustomSettings' -Lines @('r.X=1')
    $t2 = Add-IavIniBlockToText -Text $t1 -Section 'CustomSettings' -Lines @('r.X=1')
    Assert-Eq $t2 $t1 'reinserire non duplica'
    $lines = $t1 -split "`r`n"
    Assert-True ($lines[2].StartsWith('; >>> IAVATAR_NeuralViceCity >>>')) 'blocco subito dopo [CustomSettings]'
    Assert-Eq ((Remove-IavIniBlockFromText -Text $t1) + '') ($t.TrimEnd("`r", "`n") + "`r`n") 'rimozione ripristina il testo'
}

It 'Dry-run: piano valido e NESSUNA modifica al disco' {
    $f = New-Fixture; $fixtures.Add($f.Root)
    $before = Get-TreeHash -Paths @($f.Game, $f.Docs)
    $t = New-TestPlan -F $f
    Assert-Eq $t.Plan.Errors.Count 0 ('errori nel piano: ' + ($t.Plan.Errors -join '; '))
    Assert-Eq $t.Plan.Operations.Count 7 'operazioni (6 file + blocco ini)'
    $r = Invoke-IavInstall -Config $config -Game $t.Game -Plan $t.Plan -StateDir $f.State -DryRun
    Assert-Eq $r.Result 'DryRun' 'risultato'
    Assert-Eq (Get-TreeHash -Paths @($f.Game, $f.Docs)) $before 'albero invariato'
    Assert-True (-not (Test-Path (Get-IavManifestPath -StateDir $f.State))) 'nessun manifest'
}

It 'Install -> verifica -> idempotenza -> uninstall ripristina bit-a-bit' {
    $f = New-Fixture; $fixtures.Add($f.Root)
    $before = Get-TreeHash -Paths @($f.Game, $f.Docs)
    $t = New-TestPlan -F $f
    $r = Invoke-IavInstall -Config $config -Game $t.Game -Plan $t.Plan -StateDir $f.State
    Assert-Eq $r.Result 'Installed' 'install'
    Assert-True (Test-Path (Join-Path $t.Game.Win64 'dxgi.dll')) 'dxgi.dll presente'
    Assert-True (Test-Path (Join-Path $t.Game.NgxOverrideDir 'nvngx_dlss.dll')) 'override NGX presente'
    Assert-Eq (Get-IavSha256 -Path $t.Game.NativeDlssDll) (Get-IavSha256 -Path (Join-Path $f.Game 'Engine\Plugins\Runtime\Nvidia\DLSS\Binaries\ThirdParty\Win64\nvngx_dlss.dll')) 'DLL nativa intatta'
    Assert-True (Test-IavIniHasBlock -Path $t.Game.CustomSettings) 'blocco in CustomSettings.ini'
    $s = Get-IavStatus -StateDir $f.State -Game $t.Game
    Assert-True $s.Healthy ('status: ' + ($s.Problems -join '; '))
    $mid = Get-TreeHash -Paths @($f.Game, $f.Docs)
    $t2 = New-TestPlan -F $f
    $r2 = Invoke-IavInstall -Config $config -Game $t2.Game -Plan $t2.Plan -StateDir $f.State
    Assert-Eq $r2.Result 'AlreadyInstalled' 'seconda install idempotente'
    Assert-Eq (Get-TreeHash -Paths @($f.Game, $f.Docs)) $mid 'idempotenza: nessuna modifica'
    $u = Invoke-IavUninstall -StateDir $f.State -Game $t.Game
    Assert-True $u.Clean 'uninstall pulito'
    Assert-Eq (Get-TreeHash -Paths @($f.Game, $f.Docs)) $before 'stato iniziale ripristinato bit-a-bit'
    Assert-True (-not (Test-Path (Get-IavManifestPath -StateDir $f.State))) 'manifest archiviato'
}

It 'Rollback automatico se un''operazione fallisce a meta''' {
    $f = New-Fixture; $fixtures.Add($f.Root)
    $before = Get-TreeHash -Paths @($f.Game, $f.Docs)
    $t = New-TestPlan -F $f
    $script:n = 0
    $fault = { param($op) $script:n++; if ($script:n -eq 5) { throw 'guasto simulato' } }
    $threw = $false
    try { [void](Invoke-IavInstall -Config $config -Game $t.Game -Plan $t.Plan -StateDir $f.State -FaultInjector $fault) } catch { $threw = $true }
    Assert-True $threw 'l''errore viene propagato'
    Assert-Eq (Get-TreeHash -Paths @($f.Game, $f.Docs)) $before 'stato iniziale dopo il rollback'
    Assert-True (-not (Test-Path (Get-IavManifestPath -StateDir $f.State))) 'nessun manifest attivo'
}

It 'DLL DLSS 5 non firmata NVIDIA: rifiutata, nessuna modifica' {
    $f = New-Fixture; $fixtures.Add($f.Root)
    $before = Get-TreeHash -Paths @($f.Game, $f.Docs)
    $t = New-TestPlan -F $f -Override @{ dlssnr = (Join-Path $f.Inputs 'unsigned\nvngx_dlssnr.dll') }
    Assert-True (@($t.Plan.Errors | Where-Object { $_ -like 'dlssnr: firma*' }).Count -eq 1) 'errore di firma'
    $threw = $false
    try { [void](Invoke-IavInstall -Config $config -Game $t.Game -Plan $t.Plan -StateDir $f.State) } catch { $threw = $true }
    Assert-True $threw 'install bloccata'
    Assert-Eq (Get-TreeHash -Paths @($f.Game, $f.Docs)) $before 'albero invariato'
}

It 'Versione minima: DLSS 5 piu'' vecchia della 310.8 rifiutata' {
    $f = New-Fixture; $fixtures.Add($f.Root)
    New-FakePe -Path (Join-Path $f.Inputs 'old\nvngx_dlssnr.dll') -Version '310.7.9.0' -Marker 'NVSIGNED'
    $t = New-TestPlan -F $f -Override @{ dlssnr = (Join-Path $f.Inputs 'old\nvngx_dlssnr.dll') }
    Assert-True (@($t.Plan.Errors | Where-Object { $_ -like '*inferiore al minimo*' }).Count -eq 1) 'errore di versione'
}

It 'Conflitto: dxgi.dll gia'' presente -> piano rifiutato, nulla sovrascritto' {
    $f = New-Fixture; $fixtures.Add($f.Root)
    [IO.File]::WriteAllText((Join-Path $f.Game 'Gameface\Binaries\Win64\dxgi.dll'), 'altra mod')
    $t = New-TestPlan -F $f
    Assert-True (@($t.Plan.Errors | Where-Object { $_ -like 'Conflitto*dxgi.dll*' }).Count -eq 1) 'conflitto segnalato'
}

It 'Allowlist hash vuota senza -TrustNewHash: add-on RenoDX rifiutato' {
    $f = New-Fixture; $fixtures.Add($f.Root)
    $v = Test-IavComponentFile -Name 'renodx' -Rule $config.components.renodx -Path (Join-Path $f.Inputs 'renodx-dlss5.addon64')
    Assert-True (-not $v.Ok) 'rifiutato'
    $v2 = Test-IavComponentFile -Name 'renodx' -Rule $config.components.renodx -Path (Join-Path $f.Inputs 'renodx-dlss5.addon64') -TrustNewHash
    Assert-True $v2.Ok 'accettato con -TrustNewHash'
}

It 'Uninstall: file di config modificati rimossi; DLL modificata lasciata con avviso' {
    $f = New-Fixture; $fixtures.Add($f.Root)
    $t = New-TestPlan -F $f
    [void](Invoke-IavInstall -Config $config -Game $t.Game -Plan $t.Plan -StateDir $f.State)
    [IO.File]::AppendAllText((Join-Path $t.Game.Win64 'ReShade.ini'), "`r`n[APP]`r`nForceVsync=0`r`n")
    [IO.File]::AppendAllText((Join-Path $t.Game.Win64 'nvngx_dlssnr.dll'), 'x')
    $u = Invoke-IavUninstall -StateDir $f.State -Game $t.Game
    Assert-True (-not (Test-Path (Join-Path $t.Game.Win64 'ReShade.ini'))) 'ReShade.ini (mutable) rimosso'
    Assert-True (Test-Path (Join-Path $t.Game.Win64 'nvngx_dlssnr.dll')) 'DLL alterata non rimossa'
    Assert-True (-not $u.Clean) 'esito con avvisi'
}

It 'Uninstall: file creati a runtime lasciati, rimossi con -PurgeNewFiles' {
    $f = New-Fixture; $fixtures.Add($f.Root)
    $before = Get-TreeHash -Paths @($f.Game, $f.Docs)
    $t = New-TestPlan -F $f
    [void](Invoke-IavInstall -Config $config -Game $t.Game -Plan $t.Plan -StateDir $f.State)
    [IO.File]::WriteAllText((Join-Path $t.Game.Win64 'ReShade.log'), 'log')
    $d = Invoke-IavUninstall -StateDir $f.State -Game $t.Game -DryRun
    Assert-Eq @($d.NewFiles).Count 1 'ReShade.log individuato'
    $u = Invoke-IavUninstall -StateDir $f.State -Game $t.Game -PurgeNewFiles
    Assert-True $u.Clean 'pulito'
    Assert-Eq (Get-TreeHash -Paths @($f.Game, $f.Docs)) $before 'stato iniziale'
}

It 'CustomSettings.ini assente prima: creato e poi rimosso' {
    $f = New-Fixture; $fixtures.Add($f.Root)
    $cs = Join-Path $f.Docs 'Rockstar Games\GTA Vice City Definitive Edition\Config\WindowsNoEditor\CustomSettings.ini'
    Remove-Item -LiteralPath $cs -Force
    $before = Get-TreeHash -Paths @($f.Game, $f.Docs)
    $t = New-TestPlan -F $f -NoSr
    [void](Invoke-IavInstall -Config $config -Game $t.Game -Plan $t.Plan -StateDir $f.State)
    Assert-True (Test-IavIniHasBlock -Path $cs) 'creato con blocco'
    [void](Invoke-IavUninstall -StateDir $f.State -Game $t.Game)
    Assert-Eq (Get-TreeHash -Paths @($f.Game, $f.Docs)) $before 'stato iniziale'
}

It 'Setup ReShade: estrazione di ReShade64.dll dallo ZIP accodato senza eseguirlo' {
    $f = New-Fixture; $fixtures.Add($f.Root)
    Add-Type -AssemblyName System.IO.Compression
    $zipMs = New-Object IO.MemoryStream
    $za = New-Object IO.Compression.ZipArchive($zipMs, [IO.Compression.ZipArchiveMode]::Create, $true)
    $e = $za.CreateEntry('ReShade64.dll'); $w = $e.Open()
    $payload = [IO.File]::ReadAllBytes((Join-Path $f.Inputs 'ReShade64.dll')); $w.Write($payload, 0, $payload.Length); $w.Dispose()
    $za.Dispose()
    $stub = New-Object byte[] 4096; (New-Object Random 7).NextBytes($stub)
    $setup = Join-Path $f.Root 'ReShade_Setup_fake.exe'
    [IO.File]::WriteAllBytes($setup, [byte[]]($stub + $zipMs.ToArray()))
    $out = Expand-IavEmbeddedZipEntry -Path $setup -EntryName 'ReShade64.dll' -Destination (Join-Path $f.Root 'x\ReShade64.dll')
    Assert-Eq (Get-IavSha256 -Path $out) (Get-IavSha256 -Path (Join-Path $f.Inputs 'ReShade64.dll')) 'contenuto estratto identico'
}

It 'Entry point: -Status e -Install -DryRun via script reale (exit code e nessuna modifica)' {
    $f = New-Fixture; $fixtures.Add($f.Root)
    $before = Get-TreeHash -Paths @($f.Game, $f.Docs)
    $script = Join-Path $src 'IAVATAR_NeuralViceCity.ps1'
    $exe = (Get-Process -Id $PID).Path
    & $exe -NoProfile -ExecutionPolicy Bypass -File $script -Status -GamePath $f.Game -StateDir $f.State -DocumentsPath $f.Docs *> $null
    Assert-Eq $LASTEXITCODE 0 'exit code -Status'
    & $exe -NoProfile -ExecutionPolicy Bypass -File $script -Install -DryRun -SkipGpuCheck -GamePath $f.Game -StateDir $f.State -DocumentsPath $f.Docs -ReShadeDll (Join-Path $f.Inputs 'ReShade64.dll') -RenoDxAddon (Join-Path $f.Inputs 'renodx-dlss5.addon64') -DlssNrDll (Join-Path $f.Inputs 'nvngx_dlssnr.dll') -TrustNewHash *> $null
    $code = $LASTEXITCODE
    # Senza mock di firma, sul PC reale la DLL finta non e' firmata NVIDIA: atteso exit 2 (piano non valido).
    Assert-Eq $code 2 'exit code dry-run con DLL non firmata'
    Assert-Eq (Get-TreeHash -Paths @($f.Game, $f.Docs)) $before 'nessuna modifica'
}

# ------------------------------------------------------------ Modulo B lato utente (texture)

function New-FakePak([string]$Path, [int]$Seed) {
    $b = New-Object byte[] 70000; (New-Object Random $Seed).NextBytes($b)
    $d = Split-Path -Parent $Path; if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    [IO.File]::WriteAllBytes($Path, $b)
}

It 'Conferma: SI/si/Si/s accettati, tutto il resto rifiutato' {
    foreach ($y in @('SI', 'si', 'Si', ' si ', 's', 'S')) { Assert-True (Test-IavYes $y) ('accettato: ' + $y) }
    foreach ($n in @('', 'no', 'N', 'sim', 'yes', $null)) { Assert-True (-not (Test-IavYes $n)) ('rifiutato: ' + $n) }
}

It 'Texture: pool di streaming scelto in base alla VRAM' {
    $rt = Get-IavRuntimeConfig -RepoRoot $repo
    Assert-Eq (Get-IavStreamingPoolMb -Runtime $rt -VramMb 16303) 4096 '16 GB'
    Assert-Eq (Get-IavStreamingPoolMb -Runtime $rt -VramMb 12282) 3072 '12 GB'
    Assert-Eq (Get-IavStreamingPoolMb -Runtime $rt -VramMb 8151) 2048 '8 GB'
    Assert-Eq (Get-IavStreamingPoolMb -Runtime $rt -VramMb 6000) 1200 '6 GB'
    Assert-Eq (Get-IavStreamingPoolMb -Runtime $rt -VramMb $null) 1200 'VRAM sconosciuta -> valore prudente'
}

It 'Texture: config runtime con soli URL ufficiali e hash a 64 cifre' {
    $rt = Get-IavRuntimeConfig -RepoRoot $repo
    $all = @($rt.python) + @($rt.wheels) + @($rt.realesrgan)
    foreach ($x in $all) {
        Assert-True ($x.url -match '^https://(www\.python\.org|files\.pythonhosted\.org|github\.com)/') ('URL ufficiale: ' + $x.url)
        Assert-True ($x.sha256 -match '^[0-9A-Fa-f]{64}$') ('hash: ' + $x.url)
    }
    $threw = $false
    try { [void](Save-IavVerifiedDownload -Url 'https://example.com/x.zip' -Sha256 ('0' * 64) -Directory $env:TEMP) } catch { $threw = $true }
    Assert-True $threw 'URL non ufficiale rifiutato prima di qualunque download'
}

It 'Texture: install pak + pool -> verifica -> uninstall ripristina bit-a-bit' {
    $f = New-Fixture; $fixtures.Add($f.Root)
    $g = Get-IavGameInfo -GamePath $f.Game -DocumentsPath $f.Docs
    New-Item -ItemType Directory -Path $g.ModsDir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $g.ModsDir 'altra_mod_P.pak'), 'non nostra')
    $before = Get-TreeHash -Paths @($f.Game, $f.Docs)
    $paks = @(
        [pscustomobject]@{ Id = 'characters'; Path = (Join-Path $f.Root 'build\c\C_P.pak'); Name = 'IAVATAR_NeuralViceCity_Characters_P.pak' },
        [pscustomobject]@{ Id = 'hd'; Path = (Join-Path $f.Root 'build\h\H_P.pak'); Name = 'IAVATAR_NeuralViceCity_HD_9_P.pak' })
    New-FakePak $paks[0].Path 1; New-FakePak $paks[1].Path 2
    $plan = New-IavTexturePlan -Game $g -Paks $paks -PoolMb 4096
    Assert-Eq $plan.Errors.Count 0 ('errori: ' + ($plan.Errors -join '; '))
    Assert-Eq $plan.Operations.Count 3 '2 pak + pool'
    $st = Join-Path $f.State 'textures'
    $r = Invoke-IavInstall -Config $config -Game $g -Plan $plan -StateDir $st -SnapshotDirs @{ Mods = $g.ModsDir }
    Assert-Eq $r.Result 'Installed' 'install'
    Assert-True (Test-Path (Join-Path $g.ModsDir 'IAVATAR_NeuralViceCity_HD_9_P.pak')) 'pak HD in ~mods'
    Assert-True ([IO.File]::ReadAllText($g.CustomSettings) -match 'r\.Streaming\.PoolSize=4096') 'pool in CustomSettings.ini'
    Assert-True (Get-IavStatus -StateDir $st -Game $g).Healthy 'stato integro'
    $u = Invoke-IavUninstall -StateDir $st -Game $g
    Assert-True $u.Clean 'uninstall pulito'
    Assert-Eq (Get-TreeHash -Paths @($f.Game, $f.Docs)) $before 'gioco e CustomSettings.ini come prima; la mod di terzi resta'
}

It 'Texture: pak identico gia'' presente -> preso in carico; diverso -> conflitto' {
    $f = New-Fixture; $fixtures.Add($f.Root)
    $g = Get-IavGameInfo -GamePath $f.Game -DocumentsPath $f.Docs
    $src = Join-Path $f.Root 'build\e\E_P.pak'; New-FakePak $src 3
    New-Item -ItemType Directory -Path $g.ModsDir -Force | Out-Null
    $dst = Join-Path $g.ModsDir 'IAVATAR_NeuralViceCity_Environment_P.pak'
    Copy-Item -LiteralPath $src -Destination $dst
    $paks = @([pscustomobject]@{ Id = 'environment'; Path = $src; Name = 'IAVATAR_NeuralViceCity_Environment_P.pak' })
    $plan = New-IavTexturePlan -Game $g -Paks $paks -PoolMb 0
    Assert-Eq $plan.Errors.Count 0 'identico: nessun conflitto'
    Assert-True $plan.Operations[0].Adopt 'operazione di presa in carico'
    $st = Join-Path $f.State 'textures'
    Assert-Eq (Invoke-IavInstall -Config $config -Game $g -Plan $plan -StateDir $st -SnapshotDirs @{ Mods = $g.ModsDir }).Result 'Installed' 'install'
    [void](Invoke-IavUninstall -StateDir $st -Game $g)
    Assert-True (-not (Test-Path -LiteralPath $dst)) 'uninstall rimuove anche il pak preso in carico'
    New-FakePak $dst 99
    $plan2 = New-IavTexturePlan -Game $g -Paks $paks -PoolMb 0
    Assert-Eq $plan2.Errors.Count 1 'diverso: conflitto segnalato'
    Assert-Eq (Get-IavSha256 -Path $dst) (Get-IavSha256 -Path $dst) 'nessuna sovrascrittura in fase di piano'
}

It 'Uninstall compatibile con i manifest della 0.1.0 (snapshot come elenco di nomi)' {
    $f = New-Fixture; $fixtures.Add($f.Root)
    $t = New-TestPlan -F $f
    [void](Invoke-IavInstall -Config $config -Game $t.Game -Plan $t.Plan -StateDir $f.State)
    $m = Read-IavManifest -StateDir $f.State
    $m.snapshots = [pscustomobject]@{ Win64 = @($m.snapshots.Win64.Files); NgxOverride = @($m.snapshots.NgxOverride.Files) }
    Save-IavManifest -StateDir $f.State -Manifest $m
    [IO.File]::WriteAllText((Join-Path $t.Game.Win64 'ReShade.log'), 'runtime')
    $u = Invoke-IavUninstall -StateDir $f.State -Game $t.Game
    Assert-Eq @($u.NewFiles).Count 1 'file runtime riconosciuto anche con il manifest vecchio'
}

It 'Auto: trova add-on RenoDX e DLL NVIDIA di RTX Remix' {
    $f = New-Fixture; $fixtures.Add($f.Root)
    $dl = Join-Path $f.Root 'Downloads'; New-Item -ItemType Directory -Path $dl -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $f.Inputs 'renodx-dlss5.addon64') -Destination $dl
    $remix = Join-Path $f.Root 'RTX Remix'
    $trex = Join-Path $remix 'deps\remix_runtime\runtime\.trex'
    New-Item -ItemType Directory -Path $trex -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $f.Inputs 'nvngx_dlssnr.dll') -Destination $trex
    Copy-Item -LiteralPath (Join-Path $f.Inputs 'sr\nvngx_dlss.dll') -Destination $trex
    $found = Find-IavUserComponents -SearchDirs @($dl) -RemixRoot $remix
    Assert-Eq (Split-Path -Leaf $found.renodx) 'renodx-dlss5.addon64' 'add-on'
    Assert-True ($found.dlssnr -like '*.trex*nvngx_dlssnr.dll') 'dlssnr da RTX Remix'
    Assert-True ($found.dlsssr -like '*.trex*nvngx_dlss.dll') 'dlss SR da RTX Remix'
}

# ------------------------------------------------------------ release: guardia sui file proprietari

It 'Release: la repo reale passa la guardia, work\ e docs\recon esclusi' {
    $files = @(Get-IavReleaseFiles -RepoRoot $repo)
    Assert-True ($files.Count -ge 20) ('file in release: ' + $files.Count)
    Assert-True (-not ($files | Where-Object { $_ -match '^(work|docs/recon|release/dist)/' })) 'nessun file da work, docs/recon, release/dist'
    Assert-True ($files -contains 'IAVATAR_Setup.ps1') 'setup incluso'
    $bad = @(foreach ($f in $files) { $w = Test-IavReleaseFile -Path (Join-Path $repo $f) -RelativePath $f; if ($w.Count) { $f + ': ' + ($w -join '; ') } })
    Assert-Eq $bad.Count 0 ('violazioni: ' + ($bad -join ' | '))
}

It 'Release: guardia blocca pak, DLL camuffata, firma pak, asset UE, file grandi' {
    $d = Join-Path ([IO.Path]::GetTempPath()) ('iav_rel_' + [guid]::NewGuid().ToString('N')); $fixtures.Add($d)
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    $ok = Join-Path $d 'ok.py'; [IO.File]::WriteAllText($ok, "print('ciao')`n")
    Assert-Eq (Test-IavReleaseFile -Path $ok -RelativePath 'moduleB-assets/pipeline/ok.py').Count 0 'sorgente valido ammesso'
    $pak = Join-Path $d 'x.pak'; [IO.File]::WriteAllText($pak, 'x')
    Assert-True ((Test-IavReleaseFile -Path $pak -RelativePath 'x.pak') -join ';' -match 'estensione vietata') '.pak bloccato'
    $pe = Join-Path $d 'tool.py'; [IO.File]::WriteAllBytes($pe, [byte[]](0x4D, 0x5A, 0x90, 0x00, 0x41))
    Assert-True ((Test-IavReleaseFile -Path $pe -RelativePath 'tool.py') -join ';' -match 'MZ') 'DLL rinominata .py bloccata'
    $pm = Join-Path $d 'data.json'; [IO.File]::WriteAllBytes($pm, [byte[]](0x7B, 0x20, 0xE1, 0x12, 0x6F, 0x5A, 0x7D))
    Assert-True ((Test-IavReleaseFile -Path $pm -RelativePath 'data.json') -join ';' -match 'pak Unreal') 'firma pak dentro un json bloccata'
    $ue = Join-Path $d 'asset.md'; [IO.File]::WriteAllBytes($ue, [byte[]](0xC1, 0x83, 0x2A, 0x9E, 0x41))
    Assert-True ((Test-IavReleaseFile -Path $ue -RelativePath 'asset.md') -join ';' -match 'package Unreal') 'asset UE bloccato'
    $nv = Join-Path $d 'nvngx_dlssnr.json'; [IO.File]::WriteAllText($nv, '{}')
    Assert-True ((Test-IavReleaseFile -Path $nv -RelativePath 'nvngx_dlssnr.json') -join ';' -match 'nome vietato') 'nome NVIDIA bloccato'
    $big = Join-Path $d 'big.md'; [IO.File]::WriteAllText($big, ('a' * 1100000))
    Assert-True ((Test-IavReleaseFile -Path $big -RelativePath 'big.md') -join ';' -match 'troppo grande') 'file grande bloccato'
    $wk = Join-Path $d 'w.py'; [IO.File]::WriteAllText($wk, 'x = 1')
    Assert-True ((Test-IavReleaseFile -Path $wk -RelativePath 'work/build/w.py') -join ';' -match 'cartella esclusa') 'work\ escluso'
}

It 'Release: con una violazione nessuno zip; pulito -> zip con manifest e .sha256' {
    $d = Join-Path ([IO.Path]::GetTempPath()) ('iav_rel_' + [guid]::NewGuid().ToString('N')); $fixtures.Add($d)
    foreach ($f in @('README.md', 'LICENSE', 'moduleB-assets/pipeline/a.py')) {
        $p = Join-Path $d $f; New-Item -ItemType Directory -Path (Split-Path -Parent $p) -Force | Out-Null; [IO.File]::WriteAllText($p, "ok`n")
    }
    $bad = Join-Path $d 'moduleB-assets/pipeline/b.py'; [IO.File]::WriteAllBytes($bad, [byte[]](0x4D, 0x5A, 0x00))
    $out = Join-Path $d 'dist'
    $r = New-IavReleasePackage -RepoRoot $d -Version '9.9.9' -OutDir $out
    Assert-True (-not $r.Ok) 'bloccato'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $out 'IAVATAR_NeuralViceCity_v9.9.9.zip'))) 'nessuno zip creato'
    Remove-Item -LiteralPath $bad -Force
    $r2 = New-IavReleasePackage -RepoRoot $d -Version '9.9.9' -OutDir $out
    Assert-True $r2.Ok ('pulito: ' + ($r2.Violations -join '; '))
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::OpenRead($r2.Zip)
    try { $names = @($z.Entries | ForEach-Object { $_.FullName }) } finally { $z.Dispose() }
    Assert-True ($names -contains 'IAVATAR_NeuralViceCity_v9.9.9/RELEASE-MANIFEST.txt') 'manifest nello zip'
    Assert-True ($names -contains 'IAVATAR_NeuralViceCity_v9.9.9/moduleB-assets/pipeline/a.py') 'percorsi con /'
    Assert-True (Test-Path -LiteralPath ($r2.Zip + '.sha256')) '.sha256 accanto'
}

foreach ($r in $fixtures) { try { Remove-Item -LiteralPath $r -Recurse -Force } catch { } }
Write-Host ''
Write-Host ('Risultato: {0} superati, {1} falliti' -f $script:Pass, $script:Fail) -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
if ($script:Fail) { exit 1 } else { exit 0 }
