# Modulo B - Asset & Material Pack: pipeline

## Scelta architetturale: patch in-place degli asset cotti (niente editor, per ora)
Gli asset del gioco sono cotti con un UE 4.26 **custom** (GSG, `CL-0`, plugin proprietari). Ricuocere con
il 4.26 vanilla rischia incompatibilita'. Per le texture usiamo quindi una strada piu' sicura:

1. **estrazione selettiva** dal pak (`extract.py`, solo gli asset del manifest);
2. **decodifica** della Texture2D cotta (`iav_texture.py`: formato, mip, bulk data in .uexp/.ubulk);
3. **lavorazione** dell'immagine (`build.py`, operazioni dichiarate in una ricetta JSON);
4. **ricodifica** nello **stesso formato BC, stessa risoluzione, stessi mip**, e reiniezione dei byte
   negli stessi offset: .uasset invariato, .uexp/.ubulk con identica struttura e dimensione;
5. **pack** v11 non cifrato (`iav_pak.py`), con full directory index e path hash index
   (hash FNV-64 verificato su tutte le 263 voci di pakchunk1), nome `IAVATAR_NeuralViceCity_P.pak`;
6. **deploy** in `Gameface\Content\Paks\~mods\` (lo fara' l'installer del Modulo A).

L'editor UE 4.26 servira' solo se vorremo **aumentare la risoluzione** o cambiare materiali: e' la fase
successiva, da valutare dopo il pilota.

## Scoperte sul pilota (Tommy, pelle)
- `MI_tommy_skin` (Peds) -> parent `MI_Character_White_SkinOnly_P_Base`, parametri:
  BaseColor `T_CSplaySkin_BC` (DXT1 2048, 12 mip), Normal `T_CSplaySkin_N` (BC5 2048),
  PackedTexture `T_tommy_skin_P` (DXT1 1024, gruppo WorldSpecular), Detail `T_Detail_Skin_R`,
  NormalIntensity 1.5, Roughness 1.1.
- In questa build i parametri dei MaterialInstance (Scalar/Texture/VectorParameterValue) sono
  serializzati in **binario senza tag** (33/45 byte per elemento): gestito in `iav_uasset.py`.
- Package **unversioned** (UE4 version 0): servono i layout noti di 4.26.

## Oodle
- Windows: `oo2core_8_win64.dll` dalla cartella del gioco, via ctypes (mai copiata).
- Sviluppo su Linux: pacchetto opzionale `pyooz` (GPLv3), non incluso ne' ridistribuito.

## Ricette
- `recipes/smoketest-tommy.json`: tinta blu evidente sulla BaseColor. Serve SOLO a verificare che il gioco
  carichi il pak da `~mods` e che quella texture sia quella visibile. Va rimossa subito dopo il test.

## skin-realism-v2 (2026-10-28)
- `discover.py` legge tutti i 519 MaterialInstance dei personaggi: 948 texture uniche
  (parent piu' frequenti: Clothes 176, SkinOnly 152, Hair 92). Manifest: `assets-manifest/characters.json`.
- La ricetta `skin-realism-v2` usa **regole per ruolo** (BaseColor / Normal) sui MI con parent "pelle":
  346 texture candidate, 330 lavorate, 16 saltate perche' ridotte in cottura (mip 0 a 1024 o 8 px).
- `build.py` legge direttamente dal pak del gioco (`--game`), ha una cache per texture e un budget di
  tempo (`--time-budget`): si rilancia finche' non finisce. Pak compresso Zlib (blocchi da 64 KiB).
- Pak risultante: 840 MB (1,2 GB non compresso).
- Il preset di Tommy usa i MI in `Characters/Tommy/export_01` (letti da `SK_player`), non le copie in
  `Peds`/`Textures/Character`.

## Pak separati (2026-10-29)
- `IAVATAR_NeuralViceCity_Characters_P.pak` (ricetta `characters-v3`): pelle + vestiti + capelli,
  853 texture, 1,75 GB. Testato in gioco: stabile.
- `IAVATAR_NeuralViceCity_Environment_P.pak` (ricetta `environment-v1`): 4.379 MI ambiente letti,
  3.624 texture lavorate (BaseColor + Normal, >= 256 px, parent MI_Env_P_Base / Masked / Env_Base),
  60 saltate, 10.841 file, 1,09 GB.
- `PakWriter`: scrittura in streaming e riprendibile (`.part` + `.state.json`), memoria costante.
- Verifica: indice completo + campione riletto e confrontato con la cache.
- Texture ridotte in cottura: lavorate alla risoluzione del primo mip presente (`iav_texture.effective`).
