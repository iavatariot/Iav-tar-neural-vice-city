#Requires -Version 5.1
<#
.SYNOPSIS
  IAVAT@R Neural Vice City - Modulo A: Neural Rendering Enabler per GTA Vice City - The Definitive Edition.

.DESCRIPTION
  Installer transazionale: rileva gioco/GPU/driver, valida i file forniti dall'utente (firma NVIDIA, hash,
  versione), pianifica, salva un manifest, applica, verifica e in caso di errore esegue il rollback.
  Non sovrascrive mai file originali del gioco e non include/scarica DLL NVIDIA.

.EXAMPLE
  .\IAVATAR_NeuralViceCity.ps1 -Status
.EXAMPLE
  .\IAVATAR_NeuralViceCity.ps1 -Install -DryRun -ReShadeDll .\ReShade64.dll -RenoDxAddon .\renodx-dlss5.addon64 -DlssNrDll .\nvngx_dlssnr.dll
.EXAMPLE
  .\IAVATAR_NeuralViceCity.ps1 -Uninstall
#>
[CmdletBinding(DefaultParameterSetName = 'Status')]
param(
    [Parameter(ParameterSetName = 'Install', Mandatory)][switch]$Install,
    [Parameter(ParameterSetName = 'Uninstall', Mandatory)][switch]$Uninstall,
    [Parameter(ParameterSetName = 'Verify', Mandatory)][switch]$Verify,
    [Parameter(ParameterSetName = 'Status')][switch]$Status,

    [Parameter(ParameterSetName = 'Install')][Parameter(ParameterSetName = 'Uninstall')][switch]$DryRun,

    [Parameter(ParameterSetName = 'Install')][string]$ReShadeDll,
    [Parameter(ParameterSetName = 'Install')][switch]$DownloadReShade,
    [Parameter(ParameterSetName = 'Install')][string]$RenoDxAddon,
    [Parameter(ParameterSetName = 'Install')][string]$DlssNrDll,
    [Parameter(ParameterSetName = 'Install')][string]$DlssSrDll,
    [Parameter(ParameterSetName = 'Install')][switch]$NgxVerboseLog,
    [Parameter(ParameterSetName = 'Install')][switch]$TrustNewHash,
    [Parameter(ParameterSetName = 'Install')][switch]$SkipGpuCheck,

    [Parameter(ParameterSetName = 'Uninstall')][switch]$PurgeNewFiles,

    [Parameter(ParameterSetName = 'Install')][Parameter(ParameterSetName = 'Uninstall')][switch]$Yes,

    [string]$GamePath,
    [string]$StateDir,
    [string]$DocumentsPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$moduleRoot = Split-Path -Parent $here
foreach ($m in 'IavCore', 'IavDetect', 'IavState', 'IavPlan', 'IavReShade') {
    Import-Module (Join-Path $here ('lib\{0}.psm1' -f $m)) -Force -DisableNameChecking
}

$exitCode = 0
try {
    Write-Host (Get-IavBanner) -ForegroundColor Magenta
    $config = Get-IavConfig -Path (Join-Path $moduleRoot 'config\components.json')
    Write-Host ('  {0} v{1}  -  https://iavatar.info' -f $config.product, $config.version)
    Write-Host ''

    $state = Get-IavStateDir -Override $StateDir
    [void](Initialize-IavLog -Directory (Join-Path $state 'logs'))
    Write-IavLog -Level INFO -Message ('Azione: {0}{1}' -f $PSCmdlet.ParameterSetName, $(if ($DryRun) { ' (dry-run)' } else { '' }))
    Write-IavLog -Level INFO -Message ('PowerShell {0}, cartella di stato {1}' -f $PSVersionTable.PSVersion, $state)

    $game = Get-IavGameInfo -GamePath $GamePath -DocumentsPath $DocumentsPath
    Write-IavLog -Level OK -Message ('Gioco: {0}' -f $game.Root)
    Write-IavLog -Level INFO -Message ('BuildId {0}, ViceCity.exe {1}, sha256 {2}' -f $game.BuildId, $game.ExeVersion, $game.ExeSha256)
    $tested = @($config.game.testedBuilds | Where-Object { $_.exeSha256 -eq $game.ExeSha256 })
    if ($tested.Count -eq 0) { Write-IavLog -Level WARN -Message 'Questa build del gioco non e'' tra quelle testate: procedi solo dopo un test in-game.' }

    $confirm = $null
    if (-not $Yes) {
        $confirm = {
            param($plan)
            $ans = Read-Host 'Confermi le modifiche alla cartella del gioco? Digita SI per procedere'
            return ($ans -ceq 'SI')
        }
    }

    switch ($PSCmdlet.ParameterSetName) {
        'Status' {
            $s = Get-IavStatus -StateDir $state -Game $game
            if (-not $s.Installed) { Write-IavLog -Level INFO -Message 'Stato: NON installato.' }
            else {
                Write-IavLog -Level INFO -Message ('Stato: installato il {0}, versione {1}, {2} operazioni.' -f $s.Manifest.installedAt, $s.Manifest.productVersion, @($s.Manifest.operations).Count)
                foreach ($r in @($s.Manifest.operations)) { Write-IavLog -Level INFO -Message ('  {0} {1}' -f $r.Type, $r.Destination) }
            }
            foreach ($w in $s.Warnings) { Write-IavLog -Level WARN -Message $w }
            foreach ($p in $s.Problems) { Write-IavLog -Level ERROR -Message $p }
            $gpu = Get-IavGpuInfo
            Write-IavLog -Level INFO -Message ('GPU: {0}, driver {1}, compute capability {2}' -f $gpu.Name, $gpu.DriverVersion, $gpu.ComputeCapability)
            if ($s.Installed -and -not $s.Healthy) { $exitCode = 1 }
        }
        'Verify' {
            $s = Get-IavStatus -StateDir $state -Game $game
            if (-not $s.Installed) { Write-IavLog -Level WARN -Message 'Nulla da verificare: mod non installata.'; $exitCode = 1 }
            else {
                foreach ($w in $s.Warnings) { Write-IavLog -Level WARN -Message $w }
                foreach ($p in $s.Problems) { Write-IavLog -Level ERROR -Message $p }
                if ($s.Healthy) { Write-IavLog -Level OK -Message 'Verifica superata: tutti i file installati sono integri.' } else { $exitCode = 1 }
            }
        }
        'Install' {
            if (Test-IavGameRunning) { throw 'Il gioco o il suo launcher e'' in esecuzione: chiudili e riprova.' }

            $gpu = Get-IavGpuInfo
            Write-IavLog -Level INFO -Message ('GPU: {0}, driver {1}, compute capability {2}' -f $gpu.Name, $gpu.DriverVersion, $gpu.ComputeCapability)
            if (-not $gpu.IsRtx50) {
                if ($SkipGpuCheck) { Write-IavLog -Level WARN -Message 'GPU non RTX 50: il neural rendering ufficiale non si attivera''. Proseguo per -SkipGpuCheck.' }
                else { throw 'Serve una GPU NVIDIA RTX serie 50 (compute capability 12.0+). Usa -SkipGpuCheck solo per test.' }
            }
            if ($gpu.DriverVersion -and $config.driver.minVersion -and ([version]$gpu.DriverVersion -lt [version]$config.driver.minVersion)) {
                $msg = 'Driver {0} inferiore al consigliato {1}.' -f $gpu.DriverVersion, $config.driver.minVersion
                if ($config.driver.enforce) { throw $msg } else { Write-IavLog -Level WARN -Message $msg }
            }

            if ($DownloadReShade) {
                if ($ReShadeDll) { throw 'Usa -ReShadeDll oppure -DownloadReShade, non entrambi.' }
                if (-not $DryRun -and $confirm) {
                    $ans = Read-Host ('Scarico ReShade da {0}? (il setup NON viene eseguito, ne estraggo solo ReShade64.dll) Digita SI' -f $config.downloads.reshadeAddonSetup.url)
                    if ($ans -cne 'SI') { throw 'Download annullato.' }
                }
                $ReShadeDll = Get-IavReShadeFromOfficial -DownloadConfig $config.downloads.reshadeAddonSetup -StateDir $state -TrustNewHash:$TrustNewHash
            }

            $inputs = @{ reshade = $ReShadeDll; renodx = $RenoDxAddon; dlssnr = $DlssNrDll; dlsssr = $DlssSrDll }
            $csLines = @()
            if ($NgxVerboseLog) { $csLines = @('r.NGX.LogLevel=2') }
            $plan = New-IavPlan -Config $config -Game $game -Inputs $inputs -ModuleRoot $moduleRoot -CustomSettingsLines $csLines -TrustNewHash:$TrustNewHash
            Write-IavPlan -Plan $plan

            if (-not $DryRun) {
                $probe = Join-Path $game.Win64 ('.iav_write_test_{0}' -f [guid]::NewGuid().ToString('N'))
                try { [IO.File]::WriteAllText($probe, 'x'); Remove-Item -LiteralPath $probe -Force }
                catch { throw 'Permessi insufficienti sulla cartella del gioco: avvia PowerShell come amministratore.' }
            }
            $r = Invoke-IavInstall -Config $config -Game $game -Plan $plan -StateDir $state -DryRun:$DryRun -Confirm $confirm
            if ($r.Result -eq 'Cancelled') { $exitCode = 3 }
        }
        'Uninstall' {
            if (Test-IavGameRunning) { throw 'Il gioco o il suo launcher e'' in esecuzione: chiudili e riprova.' }
            $r = Invoke-IavUninstall -StateDir $state -Game $game -DryRun:$DryRun -PurgeNewFiles:$PurgeNewFiles -Confirm $confirm
            if ($r.Result -eq 'Cancelled') { $exitCode = 3 } elseif (-not $r.Clean) { $exitCode = 4 }
        }
    }
} catch {
    Write-IavLog -Level ERROR -Message $_.Exception.Message
    $exitCode = $(if ($_.Exception.Message -like 'Piano non valido*') { 2 } else { 1 })
}
if (Get-IavLogFile) { Write-Host ('Log completo: {0}' -f (Get-IavLogFile)) }
exit $exitCode
