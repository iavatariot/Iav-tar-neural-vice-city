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

Aggiornamento 2026-10-29: la **risoluzione si aumenta senza editor** (`iav_texture.rebuild`, vedi sotto).
L'editor UE servirebbe solo per cambiare materiali/shader. Sul PC c'e' solo UE 5.5/5.7, che non cuoce per 4.26.

## Texture a risoluzione maggiore (senza editor)
Layout cotto UE 4.26 di questa build (verificato):
```
FName PixelFormat | int64 SkipOffset (assoluto = inizio del FName 'None' finale)
| SizeX SizeY Packed | FString PF_xxx | FirstMip NumMips | mip[] | bIsVirtual | FName None | tag 9E2A83C1
mip = bCooked(i32) BulkFlags(u32) Count(i32) Size(i32) Offset(i64) [dati se inline] SizeX SizeY SizeZ
```
- Offset dei mip **inline** = posizione assoluta nel file virtuale uasset+uexp; dei mip **separati** = posizione nel .ubulk.
- Nel .uasset cambiano solo `SerialSize` dell'export (= len(uexp)-4) e `BulkDataStartOffset` (= len(uasset)+len(uexp)-4).
- Politica: gli ultimi K mip restano inline come nell'originale, i maggiori vanno nel .ubulk; flag copiati dall'originale.
- Limite: `MaxLODSize=2048` per i gruppi World/WorldNormalMap/Character nel profilo Windows
  (`DefaultDeviceProfiles.ini`): oltre, il motore scarta i mip. Il profilo fissa anche `r.Streaming.PoolSize=800`:
  con l'ambiente HD l'installer lo porta a 2-4 GB in `CustomSettings.ini` in base alla VRAM.
- Priorita' dei pak: il suffisso `_9_P` fa prevalere il pak HD su `IAVATAR_NeuralViceCity_Environment_P.pak`.

## Ingrandimento IA (Real-ESRGAN)
1. `upscale_export.py`: PNG RGB con 16 px di bordo (`wrap` per `Tilables/`, `edge` altrove) in `work/upscale/in`.
2. Real-ESRGAN `realesrgan-x4plus` sulla GPU (Vulkan), poi riduzione 4x -> 2x (bicubica, PowerShell/System.Drawing)
   in `work/upscale/out`, a blocchi da 40, riprendibile. ~3,7 s per texture 1024 su RTX 5060 Ti.
3. `build.py`: `ai_upscale` toglie il bordo e porta l'albedo a 2x; le normal map vengono portate alla stessa
   risoluzione (`resize_normal`) e ricevono il micro-rilievo ricavato dall'albedo IA (`normal_detail`).

## Costruzione sul PC dell'utente
I pak contengono texture derivate dai file del gioco, quindi **non si distribuiscono**: l'installer
(`-Install -Textures`, `IavTextures.psm1`) prepara un Python privato e Real-ESRGAN (hash fissati in
`moduleB-assets/config/runtime.json`), rigenera i manifest dei materiali (`discover.py`) e costruisce
i tre pak dai file del gioco dell'utente. Su Windows Oodle arriva dalla DLL del gioco.

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
