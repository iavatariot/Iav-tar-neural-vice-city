# Architettura — proposta (da approvare)

Base: evidenze di `docs/RECON.md` (UE 4.26 custom, D3D12 imposto dal launcher, DLSS 2.3 nativo,
pak v11 non cifrati con asset Oodle, argomenti di lancio non inoltrati).

## Principi
1. **Aggiungere, non sostituire.** Ogni file della mod è *nuovo* nella cartella del gioco; nessun file
   originale viene sovrascritto (DLSS SR via cartella di override NGX, pak in `~Mods`, cvar in
   `CustomSettings.ini`). Uninstall = rimozione dei nostri file + ripristino dei due ini utente.
2. **Transazioni con manifest.** Ogni operazione è registrata *prima* di essere eseguita.
3. **Bring your own binaries.** Le DLL NVIDIA e l'add-on RenoDX arrivano dall'utente; noi verifichiamo.
4. **Niente argomenti di lancio.** Tutto passa da file di configurazione (il launcher li scarta).
5. **Stato del gioco legato alla build.** Il manifest registra `buildid` Steam e hash dell'exe: se una patch
   cambia il gioco, l'installer lo rileva e chiede di reinstallare.

## Modulo A — Neural Rendering Enabler (PowerShell 5.1)

```
moduleA-enabler/
  src/IAVATAR_NeuralViceCity.ps1   entry point: banner, parametri, orchestrazione, exit code
  src/lib/IavCore.psm1             log, PE (versione/arch), SHA-256, firma Authenticode, scrittura atomica
  src/lib/IavDetect.psm1           Steam/librerie/appmanifest, gioco, GPU/driver, processo in esecuzione
  src/lib/IavState.psm1            manifest JSON, blocchi marcati negli .ini, snapshot cartelle
  src/lib/IavPlan.psm1             validazione, piano, apply/verify, rollback, uninstall, status
  src/lib/IavReShade.psm1          download ufficiale + estrazione ReShade64.dll senza eseguire il setup
  config/components.json           componenti, regole di validazione, URL ufficiali, build testate
  presets/                         IAVATAR_NeuralViceCity.ini, ReShade.ini
```
Exit code: 0 ok, 1 errore, 2 piano non valido (input rifiutati), 3 annullato, 4 uninstall con avvisi.

Comandi:
`-Install` · `-Uninstall` · `-Verify` · `-Status` · `-DryRun` (con qualsiasi azione) ·
parametri `-DlssNrDll <path>`, `-RenoDxAddon <path>`, `-DlssSrDll <path>` (opzionale), `-GamePath` (override).

Flusso `-Install`:
1. **Detect:** gioco + `buildid`, exe e hash; GPU RTX 50 (compute capability ≥ 12.0); driver; spazio.
2. **Validate input:** `nvngx_dlssnr.dll` firma Authenticode valida **intestata a NVIDIA** + versione minima;
   add-on RenoDX: SHA-256 in allowlist; ReShade: download da `reshade.me` + hash pinnato.
3. **Plan:** elenco operazioni (add file / modify ini) con hash attesi; in `-DryRun` si stampa e si esce.
4. **Backup:** copia degli ini toccati in `%LOCALAPPDATA%\IAVATAR\NeuralViceCity\backups\<timestamp>\`.
5. **Apply:** copia file, blocco `; >>> IAVATAR_NeuralViceCity >>>` in `CustomSettings.ini`.
6. **Verify:** hash post-install di ogni file; scrittura manifest; in caso di errore → rollback.
7. **Idempotenza:** se manifest e hash coincidono, nessuna operazione.

Destinazioni previste (da confermare in Fase 2 con i test):
| File | Dove | Note |
|---|---|---|
| ReShade (`dxgi.dll`, ripiego `d3d12.dll`) + `ReShade.ini` | `Gameface\Binaries\Win64\` | full add-on support |
| `renodx-dlss5.addon64` | `Gameface\Binaries\Win64\` | BYO |
| `nvngx_dlssnr.dll` | `Gameface\Binaries\Win64\` | BYO, firma NVIDIA |
| `nvngx_dlss.dll` recente (se l'add-on lo richiede) | `Gameface\Binaries\ThirdParty\NVIDIA\NGX\Win64\` | override senza sovrascrivere |
| cvar NGX (log, ecc.) | `Documents\…\Config\WindowsNoEditor\CustomSettings.ini` | blocco marcato |
| preset `IAVATAR_NeuralViceCity.ini` | `Gameface\Binaries\Win64\` | nostro |

Rischi da validare in Fase 2: overlay Social Club D3D12 + ReShade; aggancio RenoDX su DLSS 2.3.4 vs
DLSS SR aggiornato; rispetto dell'override NGX nella build Shipping.

## Modulo B — Asset & Material Pack (Python + UE 4.26)

```
moduleB-assets/
  pipeline/extract.py        estrazione selettiva da pakchunk0 (parser v11 di tools/recon +
                             Oodle via ctypes dalla oo2core_8_win64.dll del gioco, mai copiata)
  pipeline/export.py         uasset texture → PNG/TGA (CUE4Parse/FModel CLI o UModel: scelta in Fase 3)
  pipeline/process.py        lavorazione (upscale, rifinitura pelle/roughness/emissive neon)
  pipeline/cook.ps1          UE4Editor-Cmd -run=cook (WindowsNoEditor) sul progetto di cook
  pipeline/pack.py           UnrealPak 4.26: v11, NON cifrato, Zlib, mount ../../../Gameface/Content/
  pipeline/deploy.ps1        → Gameface\Content\Paks\~Mods\IAVATAR_NeuralViceCity_P.pak (stesso manifest del Modulo A)
  pipeline/validate.py       riparsa il pak prodotto: versione, cifratura, elenco asset atteso
  assets-manifest/*.json     elenco asset per batch (pilota: Tommy)
  ue-cook-project/           progetto UE 4.26 "IAVATAR_Cook" con gli stessi path /Game/ViceCity/...
```
Area di lavoro locale **fuori dal versionamento**: `work/` (estratti, intermedi, texture lavorate:
sono derivati di asset Rockstar e non vanno su git né in un repo pubblico).

Pilota: `T_tommy_skin_P` + `MI_tommy_skin` (+ `T_tommy_accessories_P`). Prima solo texture (rischio
basso), poi material instance. Asset che dipendono dai plugin custom GSG sono fuori scope finché il pilota
non dimostra che il cook vanilla 4.26 viene caricato dal gioco.

## Release (Fase 4)
`release/Build-Release.ps1`: zip con installer, preset, pak e documentazione; **guardia** che blocca il
packaging se trova `.dll` non nostre, file con hash del gioco o estensioni vietate; pubblica SHA-256.

## Test
- `tests/moduleA`: Pester (incluso in Windows 5.1, v3+) su una **cartella di gioco finta**: dry-run,
  install, idempotenza, uninstall bit-a-bit, rollback su errore simulato, firma non valida rifiutata.
- `tests/moduleB`: pytest sul parser pak (round-trip su un pak di test generato da noi).
- In-game: checklist manuale per ogni build.
