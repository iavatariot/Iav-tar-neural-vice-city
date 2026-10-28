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

> **Stato:** in sviluppo — Fase 1 (architettura). Nessuna release pubblica.

## Moduli
| Modulo | Cosa fa | Stato |
|---|---|---|
| **A – Neural Rendering Enabler** | Installer PowerShell transazionale (backup, install, verifica, rollback) che abilita DLSS 5 sfruttando il DLSS nativo del gioco | progettazione |
| **B – Asset & Material Pack** | Pak `IAVATAR_NeuralViceCity_P.pak` in `Content\Paks\~Mods` con personaggi, pelle, superfici bagnate, neon | progettazione |

## Requisiti (previsti)
- Windows 10/11, GTA Vice City – The Definitive Edition (Steam, appid 1546990)
- **GPU NVIDIA RTX serie 50** (il neural rendering ufficiale gira solo su RTX 50) e driver recente
- Una copia **legittima e firmata NVIDIA** di `nvngx_dlssnr.dll` fornita dall'utente (la mod **non** la include né la scarica)

## Cosa questa mod NON contiene
- Nessun file originale o estratto del gioco, nessuna DLL NVIDIA o di terzi.
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
