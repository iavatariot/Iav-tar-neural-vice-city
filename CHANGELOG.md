# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/it/1.1.0/) · Versioni: [SemVer](https://semver.org/lang/it/).

## [Unreleased]
### Added (Installazione completa per l'utente)
- `IAVATAR_Setup.ps1`: un solo comando per Modulo A + texture; `-Uninstall`, `-SkipNeural`, `-SkipTextures`.
- Modulo A `-Auto`: trova l'add-on RenoDX (Download, `C:\IAVATAR_input`) e le DLL NVIDIA di RTX Remix,
  scarica ReShade dal sito ufficiale.
- Modulo A `-Textures` (`IavTextures.psm1`): costruzione in locale dei pak dai file del gioco dell'utente
  (Python 3.12 embeddable + numpy + Pillow + Real-ESRGAN, solo URL ufficiali con SHA-256 fissati in
  `moduleB-assets/config/runtime.json`), installazione in `~mods` con manifest separato, backup, verifica,
  rollback; pak identici gia' presenti presi in carico; pool di streaming `r.Streaming.PoolSize` in
  `CustomSettings.ini` in base alla VRAM (il gioco ne fissa 800 MB).
- `docs/INSTALL.md`: guida utente (requisiti, installazione, DLAA dall'app NVIDIA, tasti, problemi comuni).
- Test: 21 test PowerShell (6 nuovi: pool, URL/hash, install/uninstall pak, presa in carico, manifest 0.1.0,
  auto-rilevamento); `tests/moduleB/test_texture_rebuild.py` sui file reali del gioco.
### Added (Modulo B - texture HD)
- `iav_texture.rebuild`: riscrittura di una Texture2D a risoluzione diversa (header, catena mip completa,
  offset assoluti dei mip inline, SkipOffset, ImportedSize, SerialSize e BulkDataStartOffset nel .uasset).
  Round-trip alla stessa risoluzione identico byte per byte; validato in gioco a 2x (marciapiedi Ocean Beach).
- Operazioni `ai_upscale` (Real-ESRGAN x4 ridotto a 2x, padding "wrap" per le texture ripetute) e
  `resize_normal` (normal map alla risoluzione dell'albedo, max 2048 = MaxLODSize del profilo Windows).
- `upscale_export.py`, ricette `hd-test` e `environment-hd-v1` (2.665 albedo 128-1024 px + normal),
  pak `IAVATAR_NeuralViceCity_HD_9_P.pak` con priorita' sul pak Environment.
### Added (Showcase)
- `tools/showcase/compose.py`: confronti 4 riquadri Vanilla / Solo texture / Solo DLSS 5 / Completo
  dalle catture F5, con fascia di zoom sullo stesso punto. Gli screenshot originali non vengono toccati.
- `tools/showcase/texture_sheet.py`: tavole "originale vs IAVAT@R" con il materiale illuminato da luce
  radente (BaseColor x normal map), lette dal pak del gioco e dalla cache della build.
### Changed (Modulo B)
- Ricetta `environment-v2`: micro-rilievo piu' fine e meno intenso (la v1 risultava granulosa sui muri
  lisci, amplificata dal neural rendering). Pak Environment 1.061,7 MB.
### Added (Modulo B)
- Pak separati Characters (853 texture: pelle, vestiti, capelli) e Environment (3.624 texture).
- PakWriter in streaming e riprendibile; build con budget di tempo e cache.
- Pipeline texture senza editor: estrazione selettiva (Oodle), parser Texture2D cotte, ricodifica
  in-place stesso formato/risoluzione/mip, writer pak v11 con path hash index verificato.
- Lettura parametri dei MaterialInstance (formato binario di questa build).
- Ricetta smoke test su Tommy (validata in gioco: pak caricato da ~mods).
- `discover.py`: manifest automatico dei 519 MaterialInstance dei personaggi.
- Ricetta `skin-realism-v2`: pelle di Tommy e di tutti i pedoni (330 texture), pak Zlib da 840 MB.
### Changed
- Preset ufficiale "IAVATAR" in `presets/ReShade.ini`, tarato in gioco: 1 passata, stile naturale,
  maschera personaggi, stabilizzazione del look (~3,5 ms GPU a 1080p su RTX 5060 Ti).
  Pannello ReShade su F9.
### Added
- Modulo A v0.1.0: installer `moduleA-enabler/src/IAVATAR_NeuralViceCity.ps1` (PowerShell 5.1)
  con `-Status`, `-Verify`, `-Install`, `-Uninstall`, `-DryRun`.
  - Detection di gioco (librerie Steam + appmanifest), BuildId, hash exe, GPU/driver (RTX 50).
  - Validazione dei file forniti dall'utente: firma Authenticode NVIDIA, versione PE minima,
    architettura x64, allowlist SHA-256 (con `-TrustNewHash` esplicito e registrato nel log).
  - Download facoltativo di ReShade solo da reshade.me, con estrazione di ReShade64.dll senza
    eseguire il setup.
  - Transazioni con manifest, backup verificati, rollback automatico, uninstall bit-a-bit,
    rilevamento dei file creati a runtime (`-PurgeNewFiles`).
- Test automatici `tests/moduleA/Run-Tests.ps1` (15 casi, gioco finto in %TEMP%).
### Fixed
- Pak compressi: rimosso il block size esplicito (0x3F + uint32) nelle voci codificate. UE 4.26 non lo
  prevede e lo interpretava come offset, causando il crash del gioco al caricamento delle texture.
  Il lettore ora segue esattamente `FPakFile::DecodePakEntry` di 4.26.
- Lettura della versione PE: ora ancorata alla chiave `VS_VERSION_INFO`. Prima una sequenza
  `BD 04 EF FE` nel codice delle DLL NVIDIA restituiva versioni casuali (es. 46863.0.46863.4696).
- Checklist di test manuale `docs/TEST-FASE2.md`.
### Added
- Fase 0: ricognizione completa (`docs/RECON.md`), script di analisi in sola lettura (`tools/recon/`).
- Fase 1: struttura del repository, README, CREDITS, proposta di architettura e opzioni di licenza.
- Licenza MIT per il codice; nome definitivo "IAVAT@R Neural Vice City".
