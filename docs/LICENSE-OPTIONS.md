# Opzioni di licenza (decisione aperta)

Vincoli: gratuita, nessuna monetizzazione, nessun file del gioco o NVIDIA ridistribuito, rischio takedown
Take-Two. Una licenza copre **solo il nostro lavoro originale**: non può concedere diritti su asset
derivati da file Rockstar (texture rielaborate, materiali). Per quelli valgono le policy di Take-Two
sulle mod e i permessi della pagina Nexus.

| Opzione | Codice (installer, pipeline) | Asset del pak | Pro | Contro |
|---|---|---|---|---|
| **1 – Consigliata** | **MIT** | **CC BY-NC-SA 4.0** sul solo contributo originale + disclaimer | codice riusabile dalla community; il non-commerciale protegge il pak da rivendite | due licenze da spiegare |
| 2 | GPL-3.0 | CC BY-NC-SA 4.0 | chi modifica l'installer deve ripubblicare i sorgenti | più restrittiva per chi vuole integrare l'installer altrove |
| 3 | MIT | "All rights reserved" + permessi Nexus (no re-upload) | controllo massimo sul pak | meno aperta; dipende dalle impostazioni Nexus |
| 4 | Apache-2.0 | CC BY-NC-SA 4.0 | concessione esplicita di brevetti, NOTICE file | più verbosa di MIT, vantaggio pratico minimo qui |

Nota: la clausola NC (non commerciale) **non si applica al codice** con licenze OSI (MIT/GPL/Apache non
la ammettono). Se vuoi vietare l'uso commerciale anche dell'installer, l'unica via è una licenza non-OSI
(es. PolyForm Noncommercial): sconsigliata, scoraggia i contributi.

Per ogni opzione: `LICENSE` (codice) + `LICENSE-ASSETS` + sezione "Permissions" sulla pagina Nexus/ModDB.
