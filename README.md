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

Mod **single-player e gratuita** per *Grand Theft Auto: Vice City – The Definitive Edition* (PC, Steam):
**neural rendering di DLSS 5** sul DLSS nativo del gioco e **oltre 2.700 texture dell'ambiente ingrandite
2x con l'IA**, con normal map ricostruite e personaggi più definiti.

> **Versione 0.2.0** — validata in gioco su RTX 5060 Ti (2026-10-29). Download: Nexus Mods / ModDB
> (pacchetto creato con `release/New-IavRelease.ps1`).

*English: free single-player mod for GTA Vice City – The Definitive Edition. DLSS 5 neural rendering plus
2,700+ AI-upscaled HD environment textures, built locally from your own game files by a one-command,
fully reversible installer. Nothing from the game is redistributed. See [docs/INSTALL.md](docs/INSTALL.md).*

## Cosa fa
| Parte | Effetto | Requisito |
|---|---|---|
| **DLSS 5 neural rendering** | luce più naturale, pelle credibile, materiali e vernici più ricchi; preset "IAVATAR" | GPU NVIDIA **RTX serie 50** |
| **Texture personaggi** | pelle, vestiti e capelli più definiti | qualunque GPU |
| **Texture ambiente** | nitidezza e micro-rilievo sulle superfici | qualunque GPU |
| **Ambiente HD** | 2.700+ texture ingrandite 2x con Real-ESRGAN (fino a 2048 px), normal map alla stessa risoluzione | GPU con Vulkan |
| **Streaming texture** | memoria per le texture adeguata alla VRAM (il gioco ne riserva 800 MB) | — |

## Installazione
Chiudi il gioco, estrai il pacchetto fuori dalla cartella del gioco e, da **PowerShell come amministratore**
nella cartella della mod:
```powershell
powershell -ExecutionPolicy Bypass -File .\IAVATAR_Setup.ps1
```
Senza RTX 50 (solo texture): `.\IAVATAR_Setup.ps1 -SkipNeural`. Disinstallazione completa: `.\IAVATAR_Setup.ps1 -Uninstall`.

La prima volta le texture vengono costruite sul tuo PC (1,5-4 ore, riprendibile). Requisiti, tasti,
anti-aliasing con DLDSR e soluzione dei problemi: **[docs/INSTALL.md](docs/INSTALL.md)**.

## Requisiti
- Windows 10/11, GTA Vice City – The Definitive Edition (Steam, appid 1546990), driver NVIDIA aggiornato
- DLSS 5: GPU **RTX serie 50**, **RTX Remix** installato dall'app NVIDIA (fornisce `nvngx_dlssnr.dll` firmata
  NVIDIA, usata da lì), add-on **`renodx-dlss5.addon64`** dal Discord RenoDX
- Texture: qualunque GPU con Vulkan, ~30 GB liberi durante la costruzione, ~7 GB per i file finali

## Cosa questa mod NON contiene
- Nessun file originale o estratto del gioco, nessuna texture già pronta: i pak vengono costruiti sul PC
  dell'utente a partire dai **suoi** file del gioco.
- Nessuna DLL NVIDIA o di terzi, nessun eseguibile: l'installer usa file già presenti sul PC dell'utente o
  scaricati dalle pagine ufficiali degli autori (ReShade, Python, numpy, Pillow, Real-ESRGAN), sempre con
  verifica SHA-256 e log. Il pacchetto di release è controllato da una guardia automatica che blocca
  qualunque file binario o proprietario.

## Come funziona (in breve)
- **Modulo A** (`moduleA-enabler/`): installer PowerShell 5.1 transazionale — rileva gioco, GPU e file
  dell'utente, pianifica, salva un manifest, applica con backup, verifica e in caso di errore fa rollback.
- **Modulo B** (`moduleB-assets/`): pipeline Python senza editor — legge i pak del gioco (Oodle dalla DLL del
  gioco), decodifica le Texture2D cotte, le lavora o le ingrandisce, le riscrive (anche a risoluzione
  maggiore) e produce pak v11 caricati da `Gameface\Content\Paks\~mods`. Dettagli tecnici in
  [docs/MODULO-B.md](docs/MODULO-B.md) e [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Struttura del repository
```
IAVATAR_Setup.ps1     installazione completa in un comando
moduleA-enabler/      installer, moduli PowerShell, preset ReShade, configurazione
moduleB-assets/       pipeline texture (Python), ricette, configurazione degli strumenti (hash fissati)
release/              creazione del pacchetto con guardia anti-file proprietari
tests/                test automatici (PowerShell, Python sui file reali del gioco)
tools/                ricognizione, upscale e tavole di confronto (sviluppo)
docs/                 guida utente, architettura, ricognizione, pagina Nexus
```

## Sviluppo
```powershell
powershell -ExecutionPolicy Bypass -File .\tests\moduleA\Run-Tests.ps1      # test automatici
powershell -ExecutionPolicy Bypass -File .\release\New-IavRelease.ps1      # test + pacchetto in release\dist
```

## Licenza e crediti
Codice: [MIT](LICENSE). La mod non contiene asset: le texture sono generate sul PC di ciascun utente dai
file del suo gioco e non vengono distribuite. Componenti di terzi e relative licenze in [CREDITS.md](CREDITS.md).

## Note legali
Progetto amatoriale, gratuito e solo single-player, non affiliato a Rockstar Games, Take-Two Interactive,
Grove Street Games o NVIDIA. *Grand Theft Auto* e i relativi marchi appartengono ai rispettivi titolari.
DLSS è un marchio di NVIDIA. Nessuna monetizzazione.

Firmato **IAVAT@R** — Simone Silvestro · [iavatar.info](https://iavatar.info)
