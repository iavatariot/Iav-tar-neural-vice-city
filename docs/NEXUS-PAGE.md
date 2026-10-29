# Pagina Nexus Mods / ModDB — IAVAT@R Neural Vice City v0.2.0

Materiale pronto da incollare. Su **Nexus** la descrizione accetta BBCode (sezione "Description");
su **ModDB** incolla la versione Markdown/testo semplice (stesse sezioni, senza tag).

## Campi del modulo di caricamento
| Campo | Valore |
|---|---|
| Gioco su Nexus | **Grand Theft Auto: The Trilogy – The Definitive Edition** (`nexusmods.com/grandtheftautothetrilogy`): Nexus raggruppa i tre giochi in una sola pagina, quindi specifica "Vice City" nel nome e nel riassunto |
| Nome | IAVAT@R Neural Vice City (Vice City DE) |
| Versione | 0.2.0 |
| Categoria (Nexus) | Visuals and Graphics |
| Autore | IAVAT@R (Simone Silvestro) |
| Riassunto breve (max ~350 caratteri) | DLSS 5 neural rendering for Vice City DE plus AI-upscaled HD environment textures (2,700+), sharper characters and surfaces. One-command transactional installer with full uninstall. Textures are built locally from your own game files: nothing from the game is redistributed. RTX 50 needed for DLSS 5. |
| File principale | `IAVATAR_NeuralViceCity_v0.2.0.zip` (da `release\New-IavRelease.ps1`) + l'impronta `.sha256` nella descrizione del file |
| Requisiti (sezione Requirements) | ReShade 6.8+ (download automatico dal sito ufficiale), RenoDX DLSS 5 add-on (Discord RenoDX), RTX Remix dall'app NVIDIA (per `nvngx_dlssnr.dll`) |
| Tag | DLSS, ReShade, Textures, HD, Graphics, AI Upscale, Remaster |
| Permessi | Codice MIT. "Upload permission: you can upload this file to other sites but you must credit me as the creator of the file". Asset di altri autori inclusi: **nessuno** |
| Contenuto per adulti | No |

## Screenshot (ordine consigliato)
Tutti in `work\showcase\final\` (immagini 1920 px di larghezza, adatte a Nexus):
1. **`IAVATAR_compare_hd_muretto.jpg`** — immagine principale: 4 riquadri + zoom sulla pietra, la differenza più evidente.
2. `IAVATAR_compare_hd_hotel.jpg` — interno, pavimento a scacchi e luce.
3. `IAVATAR_compare_muro_cemento.jpg` — effetto del solo DLSS 5 sulle superfici (+27% di dettaglio misurato).
4. `IAVATAR_compare_tommy_camicia.jpg` — personaggi: tessuto della camicia.
5. `IAVATAR_hd_test.jpg` — tavola tecnica delle texture: originale 1024 px vs IAVAT@R 2048 px.
6. `IAVATAR_compare_hd_strada.jpg` — asfalto (inquadrature non identiche: tenerla per ultima).

Didascalia da usare sotto ogni immagine: *"Same spot, game time may differ. Zoom = same surface."*
Da **non** usare come screenshot: `IAVATAR_compare_muro_rosa*.jpg` (superficie a tinta unita: non mostra differenze).

---

## Descrizione (BBCode per Nexus)

```bbcode
[center][size=6][b]IAVAT@R Neural Vice City[/b][/size]
[size=3]DLSS 5 neural rendering + AI-upscaled HD textures for GTA Vice City – The Definitive Edition[/size][/center]

[size=4][b]What it does[/b][/size]
[list]
[*][b]DLSS 5 Neural Rendering[/b] on top of the game's own DLSS: more natural lighting, believable skin tones (no more orange pedestrians), richer materials and car paint. Tuned "IAVATAR" preset, toggle with F6, settings with F9.
[*][b]HD environment[/b]: 2,700+ environment textures upscaled 2x with Real-ESRGAN on your GPU (up to 2048 px, the engine limit), with normal maps rebuilt at the same resolution for real surface relief. Stone, asphalt, pavements, tiles and grass are the most visible gains.
[*][b]Characters[/b]: sharper skin, clothes and hair (same resolution, finer micro-detail).
[*][b]Texture streaming pool[/b] raised automatically according to your VRAM (the game reserves only 800 MB), so HD textures don't stay blurry.
[/list]

[size=4][b]Nothing from the game is redistributed[/b][/size]
This download contains only scripts and text configuration. The textures are [b]built on your PC from your own game files[/b] (2–4 hours the first time, resumable). The installer downloads only official tools, each verified by SHA-256: ReShade (reshade.me), Python 3.12 embeddable (python.org), numpy and Pillow (PyPI), Real-ESRGAN (GitHub). NVIDIA files are used from your own RTX Remix installation and never copied elsewhere.

[size=4][b]Requirements[/b][/size]
[list]
[*]GTA Vice City – The Definitive Edition, [b]Steam[/b] version, launched at least once
[*]Windows 10/11, up-to-date NVIDIA driver
[*][b]DLSS 5 part: NVIDIA RTX 50 series GPU[/b], [b]RTX Remix[/b] installed from the NVIDIA app, [b]renodx-dlss5.addon64[/b] from the RenoDX Discord (put it in Downloads or C:\IAVATAR_input)
[*]Texture part: any GPU with Vulkan; ~30 GB free disk space during the build, ~7 GB for the final files
[/list]

[size=4][b]Installation[/b][/size]
[list=1]
[*]Close the game and the Rockstar Launcher.
[*]Extract the zip anywhere (not inside the game folder).
[*]Open [b]PowerShell as administrator[/b] in the extracted folder and run:
[code]powershell -ExecutionPolicy Bypass -File .\IAVATAR_Setup.ps1[/code]
[*]Answer SI (yes) when asked. Every change to the game folder is shown first, logged and reversible.
[/list]
No RTX 50? Install only the textures: [code]powershell -ExecutionPolicy Bypass -File .\IAVATAR_Setup.ps1 -SkipNeural[/code]

[b]Recommended against jagged edges:[/b] NVIDIA Control Panel > Manage 3D settings > DSR - Factors: [b]DL 2.25x[/b], then set 2880x1620 in-game (1080p monitor). The NVIDIA app DLSS override is not supported for this game. Costs roughly 30–40% fps.

[size=4][b]Uninstall[/b][/size]
[code]powershell -ExecutionPolicy Bypass -File .\IAVATAR_Setup.ps1 -Uninstall[/code]
The game folder and your config files return exactly to how they were.

[size=4][b]Keys in game[/b][/size]
F9 ReShade panel · F6 neural rendering on/off · F5 before/after screenshot pair

[size=4][b]Known limitations[/b][/size]
[list]
[*]DLSS 5 neural rendering costs about 3.5–5 ms per frame at 1080p (RTX 5060 Ti: ~105 fps with it on).
[*]A few dozen tiny or non-square textures are skipped by the HD pass and keep the standard IAVAT@R version.
[*]After a Steam update of the game: uninstall, then install again (textures are rebuilt from the new files).
[*]Single-player only. Do not use it with any online or multiplayer service.
[/list]

[size=4][b]Credits[/b][/size]
ReShade by Patrick Mours (crosire) – BSD-3-Clause · RenoDX by Carlos Lopez Jr. (clshortfuse) and the RenoDX community – the DLSS 5 add-on is downloaded by you from the RenoDX Discord and is not included here · Real-ESRGAN by Xintao Wang et al. – BSD-3-Clause · NVIDIA DLSS / Neural Rendering © NVIDIA · Python, numpy, Pillow – respective authors. Full list in CREDITS.md.

[size=2]Free, non-commercial, single-player fan project. Not affiliated with or endorsed by Rockstar Games, Take-Two Interactive, Grove Street Games or NVIDIA. Grand Theft Auto and DLSS are trademarks of their respective owners. Code: MIT license.[/size]

[center][b]IAVAT@R[/b] — iavatar.info[/center]
```

---

## Versione italiana (per ModDB o sezione aggiuntiva)

**IAVAT@R Neural Vice City** porta il **neural rendering di DLSS 5** su GTA Vice City – The Definitive
Edition e lo accompagna con **oltre 2.700 texture dell'ambiente ingrandite 2x con l'IA** (Real-ESRGAN,
sulla tua GPU), normal map ricostruite e personaggi più definiti.

**Nessun file del gioco viene distribuito**: il download contiene solo script e configurazione. Le texture
si costruiscono sul tuo PC dai file del tuo gioco (2-4 ore la prima volta, riprendibile). L'installer
scarica solo strumenti ufficiali con impronta SHA-256 verificata.

**Requisiti:** GTA Vice City DE (Steam), Windows 10/11. Per DLSS 5: GPU RTX serie 50, RTX Remix dall'app
NVIDIA, add-on `renodx-dlss5.addon64` dal Discord RenoDX. Per le texture: qualunque GPU con Vulkan,
~30 GB liberi durante la costruzione.

**Installazione:** chiudi il gioco, estrai lo zip, PowerShell come amministratore nella cartella e
`powershell -ExecutionPolicy Bypass -File .\IAVATAR_Setup.ps1`. Disinstallazione completa con `-Uninstall`.
Guida dettagliata: `docs/INSTALL.md`.

---

## Avvertenze prima di pubblicare (checklist)
- [ ] Creare il pacchetto con `release\New-IavRelease.ps1` (esegue i test e la guardia): mai zippare la cartella a mano.
- [ ] Riportare nella descrizione del file l'impronta SHA-256 stampata dallo script.
- [ ] Avvisare gli autori sul Discord RenoDX che la mod cita e richiede l'add-on DLSS 5 (cortesia; il file non è incluso).
- [ ] Non caricare screenshot con interfacce di altri programmi o dati personali (nome account, notifiche).
- [ ] Nexus: nella sezione "Permissions" spuntare "This mod does not contain assets from other authors".
- [ ] Rileggere i requisiti: RTX 50 solo per la parte DLSS 5, le texture vanno su qualunque GPU con Vulkan.
