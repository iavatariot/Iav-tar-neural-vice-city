# Fase 2 - Checklist di test manuale (Modulo A v0.1.0)

Tutti i comandi da **PowerShell (Windows PowerShell 5.1)** nella cartella del repo:
`cd "$env:USERPROFILE\Documents\GitHub\Iav@tar neural vice city"` (le virgolette servono: il nome contiene spazi)

Usa sempre `-ExecutionPolicy Bypass` come negli esempi: evita blocchi della execution policy senza cambiarla a livello di sistema.

## Test 1 - Test automatici sul tuo PowerShell 5.1 (nessun rischio)
```powershell
powershell -ExecutionPolicy Bypass -File .\tests\moduleA\Run-Tests.ps1
```
Atteso: `Risultato: 15 superati, 0 falliti`. Lavorano solo in `%TEMP%` su un gioco finto.
Riportami: l'ultima riga, e le eventuali righe `[FAIL]`.

## Test 2 - Stato sul gioco reale (sola lettura)
```powershell
powershell -ExecutionPolicy Bypass -File .\moduleA-enabler\src\IAVATAR_NeuralViceCity.ps1 -Status
```
Atteso: banner, percorso del gioco trovato da solo, BuildId `16390876`, `Stato: NON installato`,
GPU RTX 5060 Ti con driver 621.01 e compute capability 12.0. Nessun avviso "build non testata".
Riportami: tutto l'output (o il file indicato in "Log completo").

## Test 3 - Dry-run sul gioco reale (sola lettura)
Prepara in una cartella di appoggio, es. `C:\IAVATAR_input\`:
- `ReShade64.dll` dal setup **ReShade 6.8.0 con full add-on support** (reshade.me). In alternativa
  lascia fare all'installer con `-DownloadReShade` (vedi test 4).
- `renodx-dlss5.addon64` (add-on RenoDX DLSS 5)
- `nvngx_dlssnr.dll` firmato NVIDIA (versione 310.8 o successiva)

```powershell
powershell -ExecutionPolicy Bypass -File .\moduleA-enabler\src\IAVATAR_NeuralViceCity.ps1 -Install -DryRun `
  -ReShadeDll C:\IAVATAR_input\ReShade64.dll -RenoDxAddon C:\IAVATAR_input\renodx-dlss5.addon64 `
  -DlssNrDll C:\IAVATAR_input\nvngx_dlssnr.dll -TrustNewHash -NgxVerboseLog
```
Atteso: righe `[PLAN]` con 6 operazioni, `DRY-RUN: ... nessuna modifica effettuata`, exit senza errori.
Se la DLL di DLSS 5 non e' firmata NVIDIA vedrai un errore esplicito di firma: e' il comportamento voluto.
Riportami: l'output completo, in particolare righe `ERROR`/`WARN` e lo SHA-256 dell'add-on RenoDX.

## Test 4 (opzionale) - Download ufficiale di ReShade
Stesso comando del test 3 sostituendo `-ReShadeDll ...` con `-DownloadReShade`.
Il setup viene scaricato da reshade.me in `%LOCALAPPDATA%\IAVATAR\NeuralViceCity\downloads\`
e **non viene eseguito**: ne viene estratto solo `ReShade64.dll`. Chiede conferma (digita `SI`).
Riportami: la riga con lo SHA-256 del setup (lo registro nel config come hash di riferimento).

## NON ancora
Non lanciare `-Install` senza `-DryRun` finche' non abbiamo visto insieme gli output dei test 2-3.
Il primo install reale lo facciamo insieme con la checklist in-game della prossima build.
