# IAVAT@R Neural Vice City — Fase 0: Ricognizione

Data: 2026-10-28 · Analisi statica in sola lettura (nessuna modifica alla cartella del gioco).
Script riproducibili in `tools/recon/`, output grezzi in `docs/recon/`.

> Nota: tutti i file del gioco hanno mtime 2026-10-28 ~16:21 → installazione/aggiornamento di oggi.
> Le evidenze valgono per questa build; ogni patch Rockstar va ri-verificata (`tools/recon`).

## 1. Versione Unreal Engine — RISOLTO
- `ViceCity.exe` (UTF-16): `++UE4+Release-4.26` / `++UE4+Release-4.26-CL-0`.
- `DLSS.uplugin` nel pak: `"EngineVersion": "4.26.0"`.
- `Gameface.uproject`: `"EngineAssociation": ""` + `CL-0` ⇒ **engine compilato da sorgente (fork GSG/Rockstar)**,
  non una build Launcher. Plugin custom: `GTABase`, `GTASupport`, `ViceCity`, `SanAndreas`, `rageunreal`.
- FileVersion PE di `ViceCity.exe`: **1.0.113.21181** (il valore 1.0.113.49697469 del recon precedente non è
  un campo PE valido: >65535). SHA-256 `114c68d6…f6a0f0`, firmato Authenticode.

**Editor per il cook: UE 4.26 (ultima patch 4.26.x dal Launcher).** Rischio: asset che referenziano classi dei
plugin custom (Blueprint, materiali con nodi/funzioni GSG) non sono cucinabili con il 4.26 vanilla. Texture e
material instance su master material dell'engine sono a basso rischio.

## 2. Formato di `pakchunk0` — RISOLTO, NESSUNA CIFRATURA
| | pakchunk0 | pakchunk1 |
|---|---|---|
| Magic `0x5A6F12E1` | a **204 byte** da EOF | a 204 byte da EOF |
| Versione pak | 11 | 11 |
| Indice cifrato | **no** (flag 0) | no |
| keyGuid | nullo | nullo |
| Entry cifrate | **0 / 108.492** | 0 / 263 |
| Compressione | Oodle 92.911, None 11.436, Zlib 4.145 | Oodle 243, Zlib 20 |
| Dimensione non compressa | 17,78 GB | 0,05 GB |
| Mount point | `../../../` | `../../../Gameface/Content/` |
| File `.sig` / IoStore (`.utoc/.ucas`) | assenti | assenti |

**Causa del falso negativo precedente:** il footer v11 è standard e sta negli ultimi 221 byte. Lo script
cercava quasi certamente i byte `5A 6F 12 E1` (big-endian); su disco sono `E1 12 6F 5A` (little-endian).

Implicazioni:
- Nessuna chiave AES necessaria → il vincolo "fermati se cifrato" non scatta.
- Tutti i `.uasset/.uexp` sono **Oodle**: l'estrazione richiede un decompressore Oodle. Il gioco include già
  `Engine\Binaries\ThirdParty\Oodle\Win64\oo2core_8_win64.dll`: la pipeline lo carica **dalla installazione
  dell'utente** (mai copiato/ridistribuito). Alternativa: tool community (FModel / repak / Unpaker) — da valutare.
- Il nostro pak mod può usare **Zlib o nessuna compressione** (il motore supporta Zlib: è nell'elenco metodi).
- Nessun `.sig` ⇒ pak signing non attivo; il caricamento da `Content\Paks\~Mods\*_P.pak` è il percorso standard.
- Asset pilota individuati (Tommy): `ViceCity/Characters/Peds/SK_player*.uasset`, `MI_tommy_skin`,
  `ViceCity/Textures/Character/T_tommy_skin_P`, `T_tommy_accessories_P`, varianti cutscene in
  `ViceCity/Characters/Tommy/export_01/MI_CStommy*_{Skin,Clothes}`. La lista completa è in
  `docs/recon/pakchunk0-filelist.txt` (solo nomi, **non va pubblicata**: è in `.gitignore`).

## 3. RHI — PARZIALE (serve un test runtime)
Fatti statici:
- L'exe include `D3D11RHI`, `D3D12RHI`, `Vulkan`, `-d3d12/-dx12` e il meccanismo UE4.26
  `[D3DRHIPreference] bPreferD3D12InGame` (in GameUserSettings).
- `DefaultEngine.ini` (nel pak) **non** imposta `DefaultGraphicsRHI` ⇒ default UE 4.26 = **DX11** se non c'è
  `-dx12` né `bPreferD3D12InGame`.
- Il tuo `GameUserSettings.ini` (Documents) non contiene `[D3DRHIPreference]`; contiene `Renderer=0`.
- Ipotesi: `Renderer` è il menu del gioco (0 = DX11, 1 = DX12) mappato su `bPreferD3D12InGame`. **Da confermare.**
- **I log UE non vengono scritti** (build Shipping: `Saved\Logs` vuoto anche dopo il lancio delle 17:36).
  Quindi niente `D3D12RHI` nei log: la verifica si fa sui **moduli caricati** e sui **log NGX**.
- Attenzione: `-applaunch … -dx12` passa da `PlayGTAViceCity.exe` → Rockstar Launcher: l'argomento può
  andare perso. Lo script verifica la command line reale del processo.

### Runtime test 1 (2026-10-28 17:53, `runtime-20261028-175323.txt`)
- Lancio con `-dx12`, `Renderer=0`: l'argomento **arriva** all'exe passando dal Rockstar Launcher
  (command line reale: `… -dx12 @args.txt -useSteam -fromRGL …`).
- Caricati `D3D12Core.dll` e **`SocialClubD3D12Renderer.dll`** ⇒ **RHI attivo = D3D12** (l'overlay Social
  Club sceglie il renderer in base all'API del gioco). `d3d11.dll` è presente ma è normale anche in DX12.
- DLSS SR attivo: `nvngx_dlss.dll` caricata dalla cartella del plugin (nessun override presente).
  Il driver carica anche `nvngx_dlssd.dll` (ngx-builtins) e `nvngx_dlssg.dll`.
- `Renderer=0` **non impedisce** DX12 quando c'è `-dx12`. Significato ancora aperto → test 2 senza `-dx12`.
- Log NGX non generati: `-NGXLogFileEnable` assente dalla command line → da ripetere.
- Overlay Social Club **in D3D12** dentro il processo: conflitto potenziale con ReShade, da testare in Fase 2.

### Runtime test 2 (2026-10-28 17:58, `runtime-20261028-175841.txt`)
- Lanciato con `-applaunch 1546990 -NGXLogFileEnable` (senza `-dx12`), Renderer invariato (`Renderer=0`).
- Command line reale **identica** al test 1: `-dx12` presente, `-NGXLogFileEnable` **assente**.
- **Conclusione:** gli argomenti passati da Steam (`-applaunch … <args>`) **non arrivano** al gioco. È
  `PlayGTAViceCity.exe` → Rockstar Launcher a costruire la command line (con `-dx12` e un response file
  `@args.txt` che non sta nella cartella del gioco). Con la configurazione attuale il gioco gira **sempre in D3D12**.
- Impatto sul progetto:
  - Modulo A non può contare su argomenti di lancio: ogni cvar va in `CustomSettings.ini` (o ini utente).
  - Target RHI: **D3D12** (D3 chiusa, salvo che il menu Renderer offra DX11: verifica opzionale).
  - I log NGX si abilitano via ini (`r.NGX.LogLevel` + cvar di file-log del plugin), in Fase 2.

## 4. Plugin DLSS — RISOLTO
- Plugin NVIDIA UE4 **2.3.0** (`Version 7`), compilato nell'exe (moduli `DLSS`, `DLSSUtility`, `NGXD3D11RHI`,
  `NGXD3D12RHI`, `NGXVulkanRHI`) ⇒ **DLSS nativo su DX11 e DX12**.
- Runtime: `Engine\Plugins\Runtime\Nvidia\DLSS\Binaries\ThirdParty\Win64\nvngx_dlss.dll` **2.3.4.0**, firmato,
  SHA-256 `1782b605…bc22a5c`.
- Input passati a NGX: colore, depth, **motion vectors combinati** (`DLSSCombinedVelocity`,
  `VelocityCombine.usf`: velocity degli oggetti + camera, `r.NGX.DLSS.DilateMotionVectors` default 1), exposure
  dal motore. Nota: `r.BasePassOutputsVelocity=False`, `r.UsePreExposure=False`, auto-exposure off.
  ⇒ Buffer reali di qualità: l'aggancio di DLSS 5 al DLSS nativo è preferibile al Feeder (MV stimati).
- **Scoperta utile — override senza toccare file originali:** `r.NGX.BinarySearchOrder=0` (default) carica
  prima `$(ProjectDir)/Binaries/ThirdParty/NVIDIA/NGX/Win64/` e solo dopo la cartella del plugin. Quindi un
  `nvngx_dlss.dll` più recente si **aggiunge** in `Gameface\Binaries\ThirdParty\NVIDIA\NGX\Win64\` e il
  rollback è la rimozione di un file. Va verificato in-game che la build Shipping lo onori.
- **Scoperta utile — cvar ufficiali:** `Documents\…\Config\WindowsNoEditor\CustomSettings.ini` è il file
  previsto da GSG per forzare cvar (`[CustomSettings]`). Lo useremo per `r.NGX.LogLevel`, ecc. (con backup).
- Log NGX: `-NGXLogFileEnable` / `r.NGX.LogLevel`; cartella `Documents\…\Logs\NGX\` (oggi vuota).

## 5. Stack DLSS 5 community — PARZIALE
- Nessuna segnalazione pubblica trovata di DLSS 5 su GTA Trilogy DE (ricerca del 2026-10-28).
- Percorsi possibili, in ordine di preferenza:
  1. **RenoDX DLSS 5 add-on** agganciato all'evaluate DLSS nativo (MV/depth reali). Probabile requisito:
     `nvngx_dlss.dll` ≥ 3.1.13 (altri progetti dello stack lo richiedono) ⇒ override via cartella NGX del punto 4.
  2. **DLSS5-Feeder** (MV stimati via ReShade): solo fallback.
- ReShade: con full add-on support, proxy `dxgi.dll` (eventuale ripiego `d3d12.dll`) in `Gameface\Binaries\Win64`.
  La cartella oggi non contiene `dxgi.dll`/`d3d12.dll` → nessun conflitto di nomi.
- Overlay Rockstar Launcher / Social Club si agganciano alla stessa swapchain: da testare.
- **Fonte DLL DLSS 5:** nessuna distribuzione NVIDIA pubblica; circola via Discord RenoDX o copia da
  software licenziato (NBA 2K27). ⇒ proposta "bring your own DLL" con verifica firma NVIDIA + versione.
  Decisione aperta (D1).

## 6. Editor UE4 e spazio disco — PARZIALE
- `LauncherInstalled.dat`: installati **UE 5.5.4** e **UE 5.7.4** (+ Fab, Quixel Bridge, un plugin
  marketplace). **Nessuna voce 4.x** nel Launcher. La voce "4.0" è la chiave di registro
  `HKLM\SOFTWARE\EpicGames\Unreal Engine\4.0` → `C:\Program Files\Epic Games\4.0\`, cartella **inesistente**:
  residuo orfano, innocuo, non utilizzabile per il cook.
- Dimensioni reali: UE_5.5 **36,8 GB**, UE_5.7 **28,2 GB**, Launcher 1,1 GB. Unico disco: C: (53,8 GB liberi).
- Disco C: 931 GB, **55 GB liberi** (95% usato).
- Budget stimato Fase 3 (da misurare): editor 4.26 minimale (solo Win64, niente simboli/starter content) +
  DDC + progetto di cook + estrazione **selettiva** (il pilota Tommy è nell'ordine delle decine di MB; il pak
  intero sarebbe 17,8 GB espanso → mai estrarlo tutto). Disinstallare 5.5/5.7 libera molto spazio (dimensioni
  reali dallo script).

## Decisioni aperte
- **D1** Fonte della DLL DLSS 5 (BYO + verifica firma? da quale software licenziato?).
- **D2** Workspace e editor: altro disco disponibile? Disinstallare UE 5.5/5.7?
- ~~D3~~ Chiusa: target D3D12 (il launcher passa sempre `-dx12`).

## Test manuali (da fare tu)
1. Avvia Steam, poi da PowerShell:
   `& "C:\Program Files (x86)\Steam\steam.exe" -applaunch 1546990 -dx12 -NGXLogFileEnable`
2. Entra in gioco (non solo il menu), lascia girare 1 minuto con DLSS attivo.
3. Con il gioco aperto: `powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Documents\GitHub\Iav@tar neural vice city\tools\recon\Get-RuntimeRecon.ps1"`
4. Chiudi il gioco. Nel menu grafico cambia **Renderer** sull'altra opzione, salva, esci.
   Rilancia **senza** `-dx12` ma con `-NGXLogFileEnable`, ripeti punti 2–3.
5. Riportami i due file `docs\recon\runtime-*.txt` e dimmi quale etichetta mostra il menu per Renderer
   in ciascun test.
