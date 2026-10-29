# Credits

**IAVAT@R Neural Vice City** — ideazione e sviluppo: Simone Silvestro (IAVAT@R).

## Progetti upstream
Nessuno di questi componenti è incluso nel repository o nella release: l'installer li usa dalla macchina
dell'utente o li scarica dalle pagine ufficiali degli autori. Licenze verificate il 2026-10-29 sulle fonti
ufficiali (file LICENSE dei repository).

| Progetto | Autore | Ruolo nella mod | Licenza |
|---|---|---|---|
| [ReShade](https://reshade.me) | Patrick Mours (crosire) e contributori | hook grafico + sistema di add-on; scaricato da reshade.me sul PC dell'utente | BSD-3-Clause |
| [RenoDX](https://github.com/clshortfuse/renodx) | Carlos Lopez Jr. (clshortfuse) e contributori | framework di add-on per ReShade | MIT (repository) |
| Add-on DLSS 5 Neural Rendering (`renodx-dlss5.addon64`) | community RenoDX ([Discord](https://discord.gg/F6AUTeWJHM)) | aggancio del neural rendering all'evaluate DLSS del gioco | nessuna licenza dichiarata, sorgente non pubblico: vedi nota |
| NVIDIA DLSS / DLSS Neural Rendering | NVIDIA Corporation | runtime fornito dall'utente | licenza NVIDIA (proprietaria) |
| Oodle | Epic Games / RAD | decompressione dei pak, dalla DLL già installata col gioco | proprietaria |
| [pyooz](https://pypi.org/project/pyooz/) / ooz | powzix e contributori | solo sviluppo su Linux: decompressione Oodle (opzionale, non ridistribuito) | GPLv3+ |
| [Pillow](https://pypi.org/project/pillow/) 11.3.0 | Alex Clark e contributori | decodifica/codifica DDS (BC1/BC5) nella pipeline (scaricato da PyPI sul PC dell'utente) | MIT-CMU |
| [NumPy](https://pypi.org/project/numpy/) 2.2.6 | NumPy Developers | calcolo delle normal map (scaricato da PyPI sul PC dell'utente) | BSD-3-Clause |
| [Python](https://www.python.org) 3.12.10 embeddable | Python Software Foundation | esecuzione della pipeline sul PC dell'utente (privato, nella cartella di stato) | PSF License |
| [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) ncnn-vulkan v0.2.5.0, modello x4plus | Xintao Wang e contributori | ingrandimento IA 2x delle texture dell'ambiente, sulla GPU dell'utente | BSD-3-Clause |

### Nota sull'add-on DLSS 5
Il sorgente dell'add-on non è nel repository pubblico RenoDX (verificato il 2026-10-29) e il binario è
distribuito solo dal Discord RenoDX, senza una licenza dichiarata. Lo trattiamo quindi come
"tutti i diritti riservati": la mod **non lo include e non lo ridistribuisce**, lo cita col suo nome,
rimanda al Discord ufficiale per scaricarlo e ne verifica l'impronta SHA-256 (`moduleA-enabler/config/components.json`).
Citare un'opera e linkare la sua fonte ufficiale non richiede una licenza; prima della pubblicazione
è comunque buona norma avvisare gli autori sul Discord RenoDX e chiedere se gradiscono un credito diverso.

## Gioco
*Grand Theft Auto: Vice City – The Definitive Edition* © Rockstar Games / Take-Two Interactive,
sviluppato da Grove Street Games. Questa mod non è affiliata né approvata da loro.
