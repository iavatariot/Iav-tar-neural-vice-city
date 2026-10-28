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
