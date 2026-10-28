# Fase 2 - Primo install reale e test in gioco (Modulo A v0.1.0)

Prerequisito: dry-run pulito (7 operazioni, nessun ERROR). Fatto il 2026-10-28.

## 1. Install
Chiudi gioco, Rockstar Games Launcher e Social Club (anche dalla tray). Poi:
```powershell
cd "$env:USERPROFILE\Documents\GitHub\Iav@tar neural vice city"
$trex = "C:\Program Files\NVIDIA Corporation\RTX Remix\deps\remix_runtime\runtime\.trex"
powershell -ExecutionPolicy Bypass -File .\moduleA-enabler\src\IAVATAR_NeuralViceCity.ps1 -Install -NgxVerboseLog `
  -ReShadeDll "$env:LOCALAPPDATA\IAVATAR\NeuralViceCity\downloads\ReShade64.dll" `
  -RenoDxAddon C:\IAVATAR_input\renodx-dlss5.addon64 `
  -DlssNrDll "$trex\nvngx_dlssnr.dll" -DlssSrDll "$trex\nvngx_dlss.dll"
```
Conferma digitando `SI`. Atteso: `Installazione completata e verificata (7 operazioni)`.
Se dice "Permessi insufficienti": riapri PowerShell come amministratore e rilancia.
Poi: `... IAVATAR_NeuralViceCity.ps1 -Verify` -> `Verifica superata`.

## 2. In gioco (annota ogni punto: OK / KO + note)
1. Avvia da Steam come sempre. Il gioco arriva al menu? (se crasha: vai al punto 4)
2. In alto compare la barra di ReShade? Premi **Home**: si apre l'overlay?
3. Overlay Social Club (Home di Rockstar / notifiche) ancora funzionante?
4. Carica una partita. In Impostazioni grafiche: DLSS attivo, modalita' **Qualita'**.
5. Overlay ReShade > scheda **Add-ons** > RenoDX DLSS 5: compare? Che stato mostra
   (runtime trovato/firmato, versione 310.9.16)? Il neural rendering parte **spento**: attivalo.
6. Stessa inquadratura (es. Ocean Beach, giorno e notte con neon), screenshot con NR **spento** e **acceso**
   (tasto PrtScn di ReShade o Win+Alt+PrtScn). FPS indicativi in entrambi i casi.
7. Artefatti? (volti, insegne al neon, testo HUD/minimappa, acqua, scie in movimento).
8. Gioca 10 minuti guidando: stabilita', stutter, crash.

## 3. Cosa riportarmi
- Le annotazioni del punto 2.
- `Gameface\Binaries\Win64\ReShade.log` (cartella del gioco).
- Eventuali file `*.json` / report creati dall'add-on in `Gameface\Binaries\Win64\`.
- La cartella `Documents\Rockstar Games\GTA Vice City Definitive Edition\Logs\NGX\` se non e' vuota.
- 2-4 screenshot NR off/on.

## 4. Se qualcosa va storto
```powershell
powershell -ExecutionPolicy Bypass -File .\moduleA-enabler\src\IAVATAR_NeuralViceCity.ps1 -Uninstall -PurgeNewFiles
```
Prima di `-PurgeNewFiles` copia altrove `ReShade.log` e gli eventuali report: servono a me.
L'uninstall riporta la cartella del gioco e CustomSettings.ini esattamente allo stato iniziale.
