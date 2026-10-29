# Installazione — IAVAT@R Neural Vice City

Guida per chi gioca. Un solo comando installa tutto; ogni passo chiede conferma prima di toccare la
cartella del gioco e si può annullare con un comando.

## Cosa ottieni
| Parte | Effetto | Requisito |
|---|---|---|
| **Neural rendering (DLSS 5)** | luce e pelle più naturali, materiali più credibili | GPU NVIDIA **RTX serie 50** |
| **Texture personaggi** | pelle, vestiti, capelli più definiti | qualunque GPU |
| **Texture ambiente** | nitidezza e micro-rilievo su muri, strade, superfici | qualunque GPU |
| **Ambiente HD** | ~2.700 texture ingrandite 2x con IA (Real-ESRGAN) + rilievo ricostruito | GPU con Vulkan, 2-4 ore la prima volta |

Le texture **non vengono scaricate**: vengono costruite sul tuo PC a partire dai file del **tuo** gioco
(la mod non contiene e non distribuisce file di Rockstar/GSG).

## Prima di iniziare (una volta sola)
1. **GTA Vice City – The Definitive Edition** installato da Steam e avviato almeno una volta.
2. **Driver NVIDIA** aggiornato.
3. Per il neural rendering (solo RTX 50):
   - **RTX Remix** installato dall'**app NVIDIA** (fornisce `nvngx_dlssnr.dll`, firmata NVIDIA:
     la mod la usa da lì, non la copia altrove né la ridistribuisce);
   - l'add-on **`renodx-dlss5.addon64`** scaricato dal Discord ufficiale di RenoDX, lasciato in
     **Download** oppure in `C:\IAVATAR_input`.
4. Circa **30 GB liberi** sul disco della mod (file temporanei della costruzione) e **~7 GB** per i pak finali.
5. Chiudi il gioco e il Rockstar Launcher.

## Installazione
Apri **PowerShell come amministratore** nella cartella della mod ed esegui:
```powershell
powershell -ExecutionPolicy Bypass -File .\IAVATAR_Setup.ps1
```
Cosa succede, in ordine:
1. **Neural rendering** — trova da solo l'add-on RenoDX e le DLL NVIDIA di RTX Remix, scarica ReShade dal
   sito ufficiale (ne estrae solo `ReShade64.dll`, senza eseguire il setup), installa il preset IAVAT@R.
2. **Texture** — scarica solo strumenti ufficiali con hash verificato
   (Python 3.12 embeddable da python.org, numpy e Pillow da PyPI, Real-ESRGAN da GitHub), costruisce i
   tre pak dai file del tuo gioco, li installa in `Gameface\Content\Paks\~mods\` e imposta il
   **pool di streaming delle texture** in base alla tua VRAM.
   La prima volta servono **2-4 ore** (soprattutto l'ingrandimento IA). Se interrompi, rilancia lo stesso
   comando: riprende da dove si era fermato.
3. Alla fine stampa il percorso del log completo.

Senza GPU RTX 50 installa solo le texture:
```powershell
powershell -ExecutionPolicy Bypass -File .\IAVATAR_Setup.ps1 -SkipNeural
```

### Ultimo passo consigliato (manuale, 1 minuto): anti-aliasing
Il gioco usa DLSS 2.3 "Qualità" (immagine calcolata a 1281x721 su 1080p): i bordi contro il cielo
restano seghettati. Non è modificabile dai file del gioco, si imposta dall'app NVIDIA:
**App NVIDIA → Grafica → GTA Vice City – The Definitive Edition → Override DLSS – Super Resolution:
`DLAA`**, **Preset del modello: `Più recente`**. Se vuoi ancora più nitidezza: Pannello di controllo
NVIDIA → Impostazioni 3D → **DSR – Fattori: DL 2.25x**, poi nel gioco scegli la risoluzione più alta.

## In gioco
| Tasto | Funzione |
|---|---|
| **F9** | pannello ReShade (impostazioni del neural rendering) |
| **F6** | neural rendering acceso/spento |
| **F5** | screenshot prima/dopo (cartella `Gameface\Binaries\Win64\DLSS5 Screenshots`) |

## Controllo e disinstallazione
```powershell
# stato e integrità
powershell -ExecutionPolicy Bypass -File .\moduleA-enabler\src\IAVATAR_NeuralViceCity.ps1 -Status
powershell -ExecutionPolicy Bypass -File .\moduleA-enabler\src\IAVATAR_NeuralViceCity.ps1 -Verify -Textures
# disinstallazione completa: il gioco torna esattamente com'era
powershell -ExecutionPolicy Bypass -File .\IAVATAR_Setup.ps1 -Uninstall
```

## Problemi comuni
| Sintomo | Causa / soluzione |
|---|---|
| "manca renodx-dlss5.addon64" | scaricalo dal Discord RenoDX e mettilo in Download o `C:\IAVATAR_input` |
| "nvngx_dlssnr.dll non trovata" | installa RTX Remix dall'app NVIDIA, poi rilancia |
| "Hash ... diverso da quello atteso" | download corrotto o file cambiato alla fonte: la mod si ferma per sicurezza; riprova più tardi |
| "Conflitto: ... esiste già" | un file con lo stesso nome è già in `~mods` (copia di prova o altra mod): rinominalo in `.off` |
| Real-ESRGAN termina con errore | aggiorna il driver (serve Vulkan); chiudi altri programmi che usano la GPU |
| Dopo un aggiornamento Steam qualcosa non va | `-Uninstall`, poi di nuovo l'installazione: le texture vengono ricostruite dalla nuova versione |
| Texture HD sfocate da vicino | VRAM al limite: rilancia l'installazione texture con `-StreamingPoolMb 2048` (dopo `-Uninstall -Textures`) |

## Dove finiscono i file
| Cosa | Dove |
|---|---|
| ReShade, add-on, preset | `…\GTA Vice City - The Definitive Edition\Gameface\Binaries\Win64\` |
| Pak delle texture | `…\Gameface\Content\Paks\~mods\IAVATAR_NeuralViceCity_*.pak` |
| Pool di streaming | blocco `IAVATAR` in `Documenti\Rockstar Games\GTA Vice City Definitive Edition\Config\WindowsNoEditor\CustomSettings.ini` |
| Strumenti, manifest, backup, log | `%LOCALAPPDATA%\IAVATAR\NeuralViceCity\` |
| File temporanei della costruzione | cartella `work\` della mod (cancellabile dopo l'installazione) |
