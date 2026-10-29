# Credits

**IAVAT@R Neural Vice City** — ideazione e sviluppo: Simone Silvestro (IAVAT@R).

## Progetti upstream
Nessuno di questi componenti è incluso nel repository o nella release: l'installer li usa dalla macchina
dell'utente o li scarica dalle pagine ufficiali degli autori. Licenze da riconfermare in Fase 2 (*).

| Progetto | Autore | Ruolo nella mod | Licenza |
|---|---|---|---|
| [ReShade](https://reshade.me) | crosire e contributori | hook grafico + sistema di add-on | BSD-3-Clause (*) |
| RenoDX / add-on DLSS 5 | clshortfuse (Shortfuse) e community RenoDX | aggancio del neural rendering all'evaluate DLSS | da verificare (*) |
| [DLSS5-Feeder](https://github.com/jlrouzies-fr/DLSS5-Feeder) | jlrouzies-fr | solo fallback, se l'aggancio nativo fallisce | da verificare (*) |
| NVIDIA DLSS / DLSS Neural Rendering | NVIDIA Corporation | runtime fornito dall'utente | licenza NVIDIA (proprietaria) |
| Oodle | Epic Games / RAD | decompressione dei pak, dalla DLL già installata col gioco | proprietaria |
| [pyooz](https://pypi.org/project/pyooz/) / ooz | powzix e contributori | solo sviluppo su Linux: decompressione Oodle (opzionale, non ridistribuito) | GPLv3+ |
| [Pillow](https://pypi.org/project/pillow/) 11.3.0 | Alex Clark e contributori | decodifica/codifica DDS (BC1/BC5) nella pipeline (scaricato da PyPI sul PC dell'utente) | MIT-CMU |
| [NumPy](https://pypi.org/project/numpy/) 2.2.6 | NumPy Developers | calcolo delle normal map (scaricato da PyPI sul PC dell'utente) | BSD-3-Clause |
| [Python](https://www.python.org) 3.12.10 embeddable | Python Software Foundation | esecuzione della pipeline sul PC dell'utente (privato, nella cartella di stato) | PSF License |
| [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) ncnn-vulkan v0.2.5.0, modello x4plus | Xintao Wang e contributori | ingrandimento IA 2x delle texture dell'ambiente, sulla GPU dell'utente | BSD-3-Clause |
| Unreal Engine 4.26 | Epic Games | editor per il cook del Modulo B | EULA Unreal Engine |

## Gioco
*Grand Theft Auto: Vice City – The Definitive Edition* © Rockstar Games / Take-Two Interactive,
sviluppato da Grove Street Games. Questa mod non è affiliata né approvata da loro.
