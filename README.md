```
  ___    _    __     __    _    _____    ____   ____
 |_ _|  / \   \ \   / /   / \  |_   _|  / __ \ |  _ \
  | |  / _ \   \ \ / /   / _ \   | |   / / _` || |_) |
  | | / ___ \   \ V /   / ___ \  | |  | | (_| ||  _ <
 |___/_/   \_\   \_/   /_/   \_\ |_|   \ \__,_||_| \_\
                                        \____/
         N E U R A L   V I C E   C I T Y
```

# IAVAT@R Neural Vice City

Mod **single-player e gratuita** per *Grand Theft Auto: Vice City – The Definitive Edition* (PC, Steam)
che porta il **neural rendering di DLSS 5** sul gioco e lo accompagna con un pacchetto di materiali e
texture pensati per dargli un input migliore.

> **Stato:** in sviluppo — Modulo A e Modulo B validati in gioco (2026-10-29). Nessuna release pubblica.

## Installazione
Un solo comando, da PowerShell come amministratore nella cartella della mod:
```powershell
powershell -ExecutionPolicy Bypass -File .\IAVATAR_Setup.ps1
```
Guida completa, requisiti e disinstallazione: **[docs/INSTALL.md](docs/INSTALL.md)**.

## Moduli
| Modulo | Cosa fa | Stato |
|---|---|---|
| **A – Neural Rendering Enabler** | Installer PowerShell transazionale (backup, install, verifica, rollback) che abilita DLSS 5 (ReShade + add-on RenoDX + runtime NVIDIA dell'utente) col preset IAVAT@R | funzionante |
| **B – Asset & Material Pack** | Texture costruite **in locale** dai file del gioco dell'utente: personaggi, ambiente, ambiente HD (IA 2x con Real-ESRGAN), installate in `~mods` con lo stesso motore transazionale | funzionante |

## Requisiti
- Windows 10/11, GTA Vice City – The Definitive Edition (Steam, appid 1546990)
- Neural rendering: **GPU NVIDIA RTX serie 50**, driver recente, RTX Remix (app NVIDIA) per `nvngx_dlssnr.dll`
  firmata NVIDIA (la mod **non** la include né la ridistribuisce), add-on `renodx-dlss5.addon64`
- Texture: qualunque GPU con Vulkan, ~30 GB liberi durante la costruzione

## Cosa questa mod NON contiene
- Nessun file originale o estratto del gioco, nessuna DLL NVIDIA o di terzi, nessuna texture già pronta:
  i pak vengono costruiti sul PC dell'utente dai suoi file del gioco.
- L'installer usa solo file già presenti sul PC dell'utente o scaricati dalle pagine ufficiali degli autori,
  con verifica di hash/firma e log.

## Struttura del repository
```
docs/                 RECON (Fase 0), ARCHITECTURE, opzioni di licenza
tools/recon/          script di ricognizione (sola lettura)
moduleA-enabler/      installer e preset (Modulo A)
moduleB-assets/       pipeline asset e progetto UE 4.26 di cook (Modulo B)
release/              script di packaging della release
tests/                test automatici
```

## Licenza
Codice: [MIT](LICENSE). Licenza degli asset del pak: da definire in Fase 3.

## Note legali
Progetto amatoriale non affiliato a Rockstar Games, Take-Two Interactive, Grove Street Games o NVIDIA.
*Grand Theft Auto* e i relativi marchi appartengono ai rispettivi titolari. DLSS è un marchio di NVIDIA.
Solo single-player; nessuna monetizzazione.

Firmato **IAVAT@R** — Simone Silvestro.
