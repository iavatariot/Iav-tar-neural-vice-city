# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/it/1.1.0/) · Versioni: [SemVer](https://semver.org/lang/it/).

## [Unreleased]
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
- Lettura della versione PE: ora ancorata alla chiave `VS_VERSION_INFO`. Prima una sequenza
  `BD 04 EF FE` nel codice delle DLL NVIDIA restituiva versioni casuali (es. 46863.0.46863.4696).
- Checklist di test manuale `docs/TEST-FASE2.md`.
### Added
- Fase 0: ricognizione completa (`docs/RECON.md`), script di analisi in sola lettura (`tools/recon/`).
- Fase 1: struttura del repository, README, CREDITS, proposta di architettura e opzioni di licenza.
- Licenza MIT per il codice; nome definitivo "IAVAT@R Neural Vice City".
