#Requires -Version 5.1
<#
  IAVAT@R Neural Vice City - IavPlan
  Validazione dei componenti, piano, installazione transazionale, verifica, disinstallazione, rollback.

  Principio: la mod AGGIUNGE file e un blocco marcato in CustomSettings.ini; non sovrascrive mai file
  originali del gioco. Ogni operazione viene registrata nel manifest prima di essere applicata.
#>
Set-StrictMode -Version 2.0

# ---------------------------------------------------------------- configurazione

function Get-IavConfig {
    param([Parameter(Mandatory)][string]$Path)
    [IO.File]::ReadAllText($Path) | ConvertFrom-Json
}

function Resolve-IavTargetDir {
    param([Parameter(Mandatory)]$Game, [Parameter(Mandatory)][string]$Target)
    switch ($Target) {
        'Win64' { return $Game.Win64 }
        'NgxOverride' { return $Game.NgxOverrideDir }
        default { throw ('Target sconosciuto nel config: {0}' -f $Target) }
    }
}

# ---------------------------------------------------------------- validazione input

function Test-IavComponentFile {
    <#
      Valida un file fornito dall'utente secondo la regola del componente.
      Restituisce @{ Ok; Errors[]; Info } senza mai lanciare eccezioni.
    #>
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Rule, [string]$Path, [switch]$TrustNewHash)
    $errors = New-Object System.Collections.Generic.List[string]
    $info = [ordered]@{}
    if (-not $Path) { $errors.Add(('{0}: percorso non fornito.' -f $Name)); return [pscustomobject]@{ Ok = $false; Errors = $errors.ToArray(); Info = $info } }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { $errors.Add(('{0}: file non trovato: {1}' -f $Name, $Path)); return [pscustomobject]@{ Ok = $false; Errors = $errors.ToArray(); Info = $info } }

    $info.Sha256 = Get-IavSha256 -Path $Path
    $props = $Rule.PSObject.Properties.Name

    if ($props -contains 'extension' -and $Rule.extension) {
        if ([IO.Path]::GetExtension($Path) -ine $Rule.extension) { $errors.Add(('{0}: estensione attesa {1}.' -f $Name, $Rule.extension)) }
    }
    if ($props -contains 'fileName' -and $Rule.fileName -and ($props -notcontains 'keepSourceName' -or -not $Rule.keepSourceName)) {
        if ((Split-Path -Leaf $Path) -ine $Rule.fileName -and ($props -notcontains 'allowRename' -or -not $Rule.allowRename)) {
            $errors.Add(('{0}: nome file atteso {1}, trovato {2}.' -f $Name, $Rule.fileName, (Split-Path -Leaf $Path)))
        }
    }
    if ($props -contains 'pe' -and $Rule.pe) {
        $pe = Get-IavPeInfo -Path $Path
        if (-not $pe) { $errors.Add(('{0}: non e'' un file PE valido.' -f $Name)) }
        else {
            $info.Architecture = $pe.Architecture
            if ($pe.Architecture -ne 'x64') { $errors.Add(('{0}: architettura {1}, richiesta x64.' -f $Name, $pe.Architecture)) }
            if ($pe.FileVersion) { $info.FileVersion = $pe.FileVersion.ToString() }
            if ($props -contains 'minVersion' -and $Rule.minVersion) {
                if (-not $pe.FileVersion) { $errors.Add(('{0}: versione non leggibile.' -f $Name)) }
                elseif ($pe.FileVersion -lt [version]$Rule.minVersion) { $errors.Add(('{0}: versione {1} inferiore al minimo {2}.' -f $Name, $pe.FileVersion, $Rule.minVersion)) }
            }
        }
    }
    if ($props -contains 'productMarker' -and $Rule.productMarker) {
        if (-not (Test-IavFileContainsText -Path $Path -Text $Rule.productMarker)) { $errors.Add(('{0}: il file non contiene il marcatore "{1}".' -f $Name, $Rule.productMarker)) }
    }
    if ($props -contains 'signer' -and $Rule.signer) {
        $sig = Test-IavNvidiaSigned -Path $Path
        $info.Signature = $sig.Status
        $info.Signer = $sig.Subject
        if (-not $sig.Ok) { $errors.Add(('{0}: firma Authenticode non valida o non NVIDIA (stato: {1}; firmatario: {2}). File modificato o non ufficiale: rifiutato.' -f $Name, $sig.Status, $sig.Subject)) }
    }
    if ($props -contains 'allowedSha256') {
        $allowed = @($Rule.allowedSha256 | Where-Object { $_ } | ForEach-Object { $_.ToUpperInvariant() })
        if ($allowed.Count -gt 0 -and -not ($allowed -contains $info.Sha256)) {
            if ($TrustNewHash) { $info.TrustedOnFirstUse = $true }
            else { $errors.Add(('{0}: SHA-256 {1} non presente nella allowlist. Se il file viene dalla fonte ufficiale, rilancia con -TrustNewHash (verra'' registrato nel log).' -f $Name, $info.Sha256)) }
        } elseif ($allowed.Count -eq 0) {
            if ($TrustNewHash) { $info.TrustedOnFirstUse = $true }
            else { $errors.Add(('{0}: allowlist SHA-256 vuota. Verifica la provenienza del file e rilancia con -TrustNewHash: l''hash {1} verra'' registrato.' -f $Name, $info.Sha256)) }
        }
    }
    [pscustomobject]@{ Ok = ($errors.Count -eq 0); Errors = $errors.ToArray(); Info = $info }
}

# ---------------------------------------------------------------- piano

function New-IavPlan {
    <#
      Costruisce l'elenco delle operazioni. Nessuna modifica al disco.
      $Inputs: hashtable nome-componente -> percorso file fornito dall'utente.
    #>
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$Game,
        [Parameter(Mandatory)][hashtable]$Inputs,
        [Parameter(Mandatory)][string]$ModuleRoot,
        [string[]]$CustomSettingsLines,
        [switch]$TrustNewHash
    )
    $ops = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[string]
    $notes = New-Object System.Collections.Generic.List[string]

    foreach ($p in $Config.components.PSObject.Properties) {
        $name = $p.Name; $rule = $p.Value
        $props = $rule.PSObject.Properties.Name
        $optional = ($props -contains 'optional' -and $rule.optional)
        $src = $null
        if ($props -contains 'bundled' -and $rule.bundled) {
            $src = Join-Path $ModuleRoot $rule.bundled
        } elseif ($Inputs.ContainsKey($name) -and $Inputs[$name]) {
            $src = $Inputs[$name]
        } elseif ($optional) {
            $notes.Add(('{0}: opzionale, non fornito -> saltato.' -f $name)); continue
        } else {
            $errors.Add(('{0}: obbligatorio, non fornito ({1}).' -f $name, $rule.description)); continue
        }

        $v = Test-IavComponentFile -Name $name -Rule $rule -Path $src -TrustNewHash:$TrustNewHash
        foreach ($e in $v.Errors) { $errors.Add($e) }
        if (-not $v.Ok) { continue }
        if ($v.Info.Contains('TrustedOnFirstUse')) { $notes.Add(('{0}: SHA-256 {1} accettato con -TrustNewHash (non in allowlist).' -f $name, $v.Info.Sha256)) }

        if ($props -contains 'keepSourceName' -and $rule.keepSourceName) { $leaf = Split-Path -Leaf $src }
        else { $leaf = $rule.fileName }
        $dstDir = Resolve-IavTargetDir -Game $Game -Target $rule.target
        $ops.Add([pscustomobject]@{
            Id          = ('{0:D2}-{1}' -f ($ops.Count + 1), $name)
            Type        = 'AddFile'
            Component   = $name
            Source      = $src
            Destination = (Join-Path $dstDir $leaf)
            Sha256      = $v.Info.Sha256
            Mutable     = [bool]($props -contains 'mutable' -and $rule.mutable)
            Info        = $v.Info
        })
    }

    if ($CustomSettingsLines -and $CustomSettingsLines.Count -gt 0) {
        $ops.Add([pscustomobject]@{
            Id          = ('{0:D2}-customsettings' -f ($ops.Count + 1))
            Type        = 'IniBlock'
            Component   = 'customsettings'
            Destination = $Game.CustomSettings
            Section     = 'CustomSettings'
            Lines       = $CustomSettingsLines
        })
    }

    # Conflitti: nessun file di destinazione deve esistere gia' (non sovrascriviamo nulla).
    foreach ($op in $ops) {
        if ($op.Type -eq 'AddFile' -and (Test-Path -LiteralPath $op.Destination)) {
            $errors.Add(('Conflitto: {0} esiste gia''. La mod non sovrascrive file esistenti: rimuovilo o disinstalla prima l''altra mod.' -f $op.Destination))
        }
    }
    [pscustomobject]@{ Operations = $ops.ToArray(); Errors = $errors.ToArray(); Notes = $notes.ToArray() }
}

function Write-IavPlan {
    param([Parameter(Mandatory)]$Plan)
    foreach ($op in $Plan.Operations) {
        if ($op.Type -eq 'AddFile') { Write-IavLog -Level PLAN -Message ('[{0}] AGGIUNGI {1}  (sha256 {2})' -f $op.Id, $op.Destination, $op.Sha256) }
        else { Write-IavLog -Level PLAN -Message ('[{0}] BLOCCO INI [{1}] in {2}: {3}' -f $op.Id, $op.Section, $op.Destination, ($op.Lines -join ' | ')) }
    }
    foreach ($n in $Plan.Notes) { Write-IavLog -Level INFO -Message $n }
    foreach ($e in $Plan.Errors) { Write-IavLog -Level ERROR -Message $e }
}

# ---------------------------------------------------------------- applicazione e annullamento

function Invoke-IavApplyOperation {
    <# Applica una singola operazione e restituisce il record da salvare nel manifest. #>
    param([Parameter(Mandatory)]$Op, [Parameter(Mandatory)][string]$BackupDir, [scriptblock]$FaultInjector)
    if ($FaultInjector) { & $FaultInjector $Op }

    if ($Op.Type -eq 'AddFile') {
        $created = New-Object System.Collections.Generic.List[string]
        $dir = Split-Path -Parent $Op.Destination
        $missing = New-Object System.Collections.Generic.List[string]
        $probe = $dir
        while ($probe -and -not (Test-Path -LiteralPath $probe)) { $missing.Insert(0, $probe); $probe = Split-Path -Parent $probe }
        foreach ($m in $missing) { New-Item -ItemType Directory -Path $m -Force | Out-Null; $created.Add($m) }
        Copy-Item -LiteralPath $Op.Source -Destination $Op.Destination -Force
        $after = Get-IavSha256 -Path $Op.Destination
        if ($after -ne $Op.Sha256) { throw ('Verifica copia fallita per {0}: atteso {1}, trovato {2}' -f $Op.Destination, $Op.Sha256, $after) }
        return [pscustomobject]@{ Id = $Op.Id; Type = 'AddFile'; Component = $Op.Component; Destination = $Op.Destination; Sha256After = $after; Mutable = $Op.Mutable; CreatedDirs = $created.ToArray() }
    }

    if ($Op.Type -eq 'IniBlock') {
        $existed = Test-Path -LiteralPath $Op.Destination
        $backup = $null; $before = $null; $text = ''
        if ($existed) {
            $before = Get-IavSha256 -Path $Op.Destination
            $backup = Join-Path $BackupDir ('{0}_{1}' -f $Op.Id, (Split-Path -Leaf $Op.Destination))
            Copy-Item -LiteralPath $Op.Destination -Destination $backup -Force
            if ((Get-IavSha256 -Path $backup) -ne $before) { throw ('Backup non verificato: {0}' -f $backup) }
            $text = [IO.File]::ReadAllText($Op.Destination)
        }
        $new = Add-IavIniBlockToText -Text $text -Section $Op.Section -Lines $Op.Lines
        Write-IavTextFileAtomic -Path $Op.Destination -Content $new
        return [pscustomobject]@{ Id = $Op.Id; Type = 'IniBlock'; Component = $Op.Component; Destination = $Op.Destination; ExistedBefore = $existed; Sha256Before = $before; BackupFile = $backup; Sha256After = (Get-IavSha256 -Path $Op.Destination); Section = $Op.Section }
    }
    throw ('Tipo di operazione sconosciuto: {0}' -f $Op.Type)
}

function Undo-IavOperation {
    <#
      Annulla un'operazione registrata. Restituisce $true se lo stato originale e' stato ripristinato.
      File AddFile modificati dopo l'installazione vengono rimossi solo se marcati Mutable (es. preset, ReShade.ini).
    #>
    param([Parameter(Mandatory)]$Record)
    $ok = $true
    if ($Record.Type -eq 'AddFile') {
        if (Test-Path -LiteralPath $Record.Destination) {
            $now = Get-IavSha256 -Path $Record.Destination
            if ($now -eq $Record.Sha256After -or $Record.Mutable) {
                Remove-Item -LiteralPath $Record.Destination -Force
                Write-IavLog -Level OK -Message ('Rimosso {0}' -f $Record.Destination)
            } else {
                Write-IavLog -Level WARN -Message ('{0} e'' stato modificato dopo l''installazione (sha256 {1}): NON rimosso. Verificalo a mano.' -f $Record.Destination, $now)
                $ok = $false
            }
        }
        $dirs = @($Record.CreatedDirs)
        [array]::Reverse($dirs)
        foreach ($d in $dirs) {
            if ($d -and (Test-Path -LiteralPath $d) -and -not (Get-ChildItem -LiteralPath $d -Force)) {
                Remove-Item -LiteralPath $d -Force
                Write-IavLog -Level OK -Message ('Rimossa cartella vuota {0}' -f $d)
            }
        }
        return $ok
    }
    if ($Record.Type -eq 'IniBlock') {
        if (-not (Test-Path -LiteralPath $Record.Destination)) { return $true }
        $now = Get-IavSha256 -Path $Record.Destination
        if ($now -eq $Record.Sha256After) {
            if ($Record.ExistedBefore) {
                Copy-Item -LiteralPath $Record.BackupFile -Destination $Record.Destination -Force
                if ((Get-IavSha256 -Path $Record.Destination) -ne $Record.Sha256Before) { throw ('Ripristino non verificato: {0}' -f $Record.Destination) }
                Write-IavLog -Level OK -Message ('Ripristinato dal backup {0}' -f $Record.Destination)
            } else {
                Remove-Item -LiteralPath $Record.Destination -Force
                Write-IavLog -Level OK -Message ('Rimosso {0} (non esisteva prima)' -f $Record.Destination)
            }
        } else {
            # Il file e' stato modificato da altri dopo l'installazione: togliamo solo il nostro blocco.
            $clean = Remove-IavIniBlockFromText -Text ([IO.File]::ReadAllText($Record.Destination))
            Write-IavTextFileAtomic -Path $Record.Destination -Content $clean
            Write-IavLog -Level WARN -Message ('{0} modificato dopo l''installazione: rimosso solo il blocco IAVATAR, il resto e'' stato conservato.' -f $Record.Destination)
            $ok = $false
        }
        return $ok
    }
    throw ('Tipo di record sconosciuto: {0}' -f $Record.Type)
}

# ---------------------------------------------------------------- comandi

function Invoke-IavInstall {
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$Game,
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)][string]$StateDir,
        [switch]$DryRun,
        [scriptblock]$Confirm,
        [scriptblock]$FaultInjector
    )
    $existing = Read-IavManifest -StateDir $StateDir
    if ($existing) {
        $status = Get-IavStatus -StateDir $StateDir -Game $Game
        $samePlan = (@($existing.operations | Where-Object { $_.Type -eq 'AddFile' } | ForEach-Object { $_.Sha256After }) -join ',') -eq (@($Plan.Operations | Where-Object { $_.Type -eq 'AddFile' } | ForEach-Object { $_.Sha256 }) -join ',')
        if ($status.Healthy -and $samePlan) {
            Write-IavLog -Level OK -Message 'Gia'' installato e integro con gli stessi file: nessuna modifica (idempotente).'
            return [pscustomobject]@{ Result = 'AlreadyInstalled'; Manifest = $existing }
        }
        throw 'Esiste gia'' un''installazione diversa o non integra. Esegui prima -Uninstall (o -Verify per i dettagli).'
    }

    # I conflitti segnalati nel piano valgono solo se non c'e' un manifest.
    if ($Plan.Errors.Count -gt 0) {
        throw ('Piano non valido ({0} errori). Nessuna modifica effettuata.' -f $Plan.Errors.Count)
    }
    if ($DryRun) {
        Write-IavLog -Level OK -Message ('DRY-RUN: {0} operazioni pianificate, nessuna modifica effettuata.' -f $Plan.Operations.Count)
        return [pscustomobject]@{ Result = 'DryRun'; Manifest = $null }
    }
    if ($Confirm -and -not (& $Confirm $Plan)) {
        Write-IavLog -Level WARN -Message 'Annullato dall''utente. Nessuna modifica effettuata.'
        return [pscustomobject]@{ Result = 'Cancelled'; Manifest = $null }
    }

    $stamp = '{0:yyyyMMdd-HHmmss}' -f (Get-Date)
    $backupDir = Join-Path $StateDir ('backups\{0}' -f $stamp)
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    $manifest = [pscustomobject]@{
        schema         = 1
        product        = $Config.product
        productVersion = $Config.version
        status         = 'installing'
        installedAt    = (Get-Date).ToString('o')
        game           = [pscustomobject]@{ Root = $Game.Root; BuildId = $Game.BuildId; ExeSha256 = $Game.ExeSha256; ExeVersion = $Game.ExeVersion }
        backupDir      = $backupDir
        snapshots      = [pscustomobject]@{ Win64 = @(Get-IavDirSnapshot -Path $Game.Win64); NgxOverride = @(Get-IavDirSnapshot -Path $Game.NgxOverrideDir) }
        operations     = @()
    }
    Save-IavManifest -StateDir $StateDir -Manifest $manifest

    $applied = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($op in $Plan.Operations) {
            Write-IavLog -Level INFO -Message ('Applico {0} -> {1}' -f $op.Id, $op.Destination)
            $rec = Invoke-IavApplyOperation -Op $op -BackupDir $backupDir -FaultInjector $FaultInjector
            $applied.Add($rec)
            $manifest.operations = $applied.ToArray()
            Save-IavManifest -StateDir $StateDir -Manifest $manifest
        }
        $manifest.status = 'installed'
        Save-IavManifest -StateDir $StateDir -Manifest $manifest
        $status = Get-IavStatus -StateDir $StateDir -Game $Game
        if (-not $status.Healthy) { throw ('Verifica post-installazione fallita: {0}' -f ($status.Problems -join '; ')) }
        Write-IavLog -Level OK -Message ('Installazione completata e verificata ({0} operazioni).' -f $applied.Count)
        return [pscustomobject]@{ Result = 'Installed'; Manifest = $manifest }
    } catch {
        $err = $_
        Write-IavLog -Level ERROR -Message ('Errore durante l''installazione: {0}' -f $err.Exception.Message)
        Write-IavLog -Level WARN -Message 'Rollback in corso...'
        $recs = $applied.ToArray(); [array]::Reverse($recs)
        foreach ($r in $recs) { try { [void](Undo-IavOperation -Record $r) } catch { Write-IavLog -Level ERROR -Message ('Rollback di {0} fallito: {1}' -f $r.Id, $_.Exception.Message) } }
        Remove-IavManifest -StateDir $StateDir -Suffix 'rolledback'
        Write-IavLog -Level WARN -Message 'Rollback completato: stato iniziale ripristinato.'
        throw $err
    }
}

function Get-IavStatus {
    param([Parameter(Mandatory)][string]$StateDir, $Game)
    $m = Read-IavManifest -StateDir $StateDir
    $problems = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    if (-not $m) { return [pscustomobject]@{ Installed = $false; Healthy = $false; Problems = @(); Warnings = @(); Manifest = $null } }
    if ($m.status -ne 'installed') { $problems.Add(('Stato manifest: {0} (installazione interrotta?)' -f $m.status)) }
    foreach ($r in @($m.operations)) {
        if (-not (Test-Path -LiteralPath $r.Destination)) { $problems.Add(('Mancante: {0}' -f $r.Destination)); continue }
        if ($r.Type -eq 'AddFile') {
            $h = Get-IavSha256 -Path $r.Destination
            if ($h -ne $r.Sha256After) {
                if ($r.Mutable) { $warnings.Add(('Modificato (consentito, file di configurazione): {0}' -f $r.Destination)) }
                else { $problems.Add(('Hash diverso: {0}' -f $r.Destination)) }
            }
        } elseif ($r.Type -eq 'IniBlock') {
            if (-not (Test-IavIniHasBlock -Path $r.Destination)) { $problems.Add(('Blocco IAVATAR assente in {0}' -f $r.Destination)) }
        }
    }
    if ($Game) {
        if ($m.game.ExeSha256 -ne $Game.ExeSha256) { $warnings.Add('ViceCity.exe e'' cambiato dopo l''installazione (aggiornamento Steam?). Verifica in gioco e reinstalla se serve.') }
        if ($m.game.BuildId -and $Game.BuildId -and $m.game.BuildId -ne $Game.BuildId) { $warnings.Add(('BuildId Steam cambiato: {0} -> {1}.' -f $m.game.BuildId, $Game.BuildId)) }
    }
    [pscustomobject]@{ Installed = $true; Healthy = ($problems.Count -eq 0); Problems = $problems.ToArray(); Warnings = $warnings.ToArray(); Manifest = $m }
}

function Invoke-IavUninstall {
    param([Parameter(Mandatory)][string]$StateDir, [Parameter(Mandatory)]$Game, [switch]$DryRun, [switch]$PurgeNewFiles, [scriptblock]$Confirm)
    $m = Read-IavManifest -StateDir $StateDir
    if (-not $m) { Write-IavLog -Level OK -Message 'Nessuna installazione registrata: niente da disinstallare.'; return [pscustomobject]@{ Result = 'NotInstalled'; Clean = $true; NewFiles = @() } }

    $recs = @($m.operations); [array]::Reverse($recs)
    foreach ($r in $recs) { Write-IavLog -Level PLAN -Message ('[{0}] ANNULLA {1} {2}' -f $r.Id, $r.Type, $r.Destination) }

    # File creati a runtime (log di ReShade, cache degli add-on) che prima non c'erano.
    $ours = @($m.operations | ForEach-Object { Split-Path -Leaf $_.Destination })
    $newFiles = New-Object System.Collections.Generic.List[string]
    foreach ($pair in @(@('Win64', $Game.Win64), @('NgxOverride', $Game.NgxOverrideDir))) {
        $before = @($m.snapshots.($pair[0]))
        foreach ($f in (Get-IavDirSnapshot -Path $pair[1])) {
            if (-not ($before -contains $f) -and -not ($ours -contains $f)) { $newFiles.Add((Join-Path $pair[1] $f)) }
        }
    }
    foreach ($f in $newFiles) { Write-IavLog -Level PLAN -Message ('File nuovo creato dopo l''installazione: {0}{1}' -f $f, $(if ($PurgeNewFiles) { ' -> verra'' rimosso' } else { ' -> lasciato (usa -PurgeNewFiles)' })) }

    if ($DryRun) { Write-IavLog -Level OK -Message 'DRY-RUN: nessuna modifica effettuata.'; return [pscustomobject]@{ Result = 'DryRun'; Clean = $true; NewFiles = $newFiles.ToArray() } }
    if ($Confirm -and -not (& $Confirm $null)) { Write-IavLog -Level WARN -Message 'Annullato dall''utente.'; return [pscustomobject]@{ Result = 'Cancelled'; Clean = $false; NewFiles = $newFiles.ToArray() } }

    $clean = $true
    foreach ($r in $recs) { if (-not (Undo-IavOperation -Record $r)) { $clean = $false } }
    if ($PurgeNewFiles) { foreach ($f in $newFiles) { Remove-Item -LiteralPath $f -Force; Write-IavLog -Level OK -Message ('Rimosso file runtime {0}' -f $f) } }
    elseif ($newFiles.Count -gt 0) { $clean = $false }

    Remove-IavManifest -StateDir $StateDir -Suffix 'uninstalled'
    if ($clean) { Write-IavLog -Level OK -Message 'Disinstallazione completata: stato iniziale ripristinato.' }
    else { Write-IavLog -Level WARN -Message 'Disinstallazione completata con avvisi: controlla le righe WARN sopra.' }
    return [pscustomobject]@{ Result = 'Uninstalled'; Clean = $clean; NewFiles = $newFiles.ToArray() }
}

Export-ModuleMember -Function Get-IavConfig, Test-IavComponentFile, New-IavPlan, Write-IavPlan, Invoke-IavApplyOperation,
    Undo-IavOperation, Invoke-IavInstall, Get-IavStatus, Invoke-IavUninstall
