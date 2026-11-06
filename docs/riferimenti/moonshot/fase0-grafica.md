# Fase 0 — Misure grafiche native, ripetibilità e limiti

4 novembre 2026. **MISURA:** 12 corse complete e un timeout; 80 finestre di stage complete,
56.280 righe CSV comprendenti il warmup. Tutte le medie delle finestre completate sono sotto 16,67 ms,
ma diversi p95/p99 e singoli frame superano il budget. Questa prova non certifica 60 FPS stabili.
La scala 4× è incompleta; la scala 8× termina nelle tre repliche. Il percorso lungo dello stage 25
ha una coda immobile: non equivale a venti secondi di attraversamento continuo.

## Provenienza e condizioni

Queste tabelle usano esclusivamente i log della sessione
[`build/moonshot-fase0-native`](../../../build/moonshot-fase0-native/results.json), driver **v1**.
Il [manifest](../../../build/moonshot-fase0-native/manifest.json) identifica la base
`ddc6b186942d4c78597dc0f3f06c1a73483b716e`, i sorgenti congelati con gli strumenti Fase 0,
Odin `dev-2026-10:84bc3fc21`, macOS 26.6.2 arm64 e seed 42. È una build strumentata dalla base,
non l'eseguibile storico immutato di quel commit. La [macchina registrata](../../../build/moonshot-fase0-native/machine.json)
è un MacBookAir10,1, Apple M1, 8.589.934.592 byte di RAM, alimentato dalla rete al rilevamento.
Non ci sono misure Windows/RTX 3060.

La [nota di sessione](../../../build/moonshot-fase0-native/session.json) separa il precedente tentativo
in sandbox, fermato per l'accesso negato a `kern.clockrate` da `/usr/bin/time -l`: quei log sono conservati,
ma esclusi. I binari congelati vengono riutilizzati senza ricompilarli durante le misure; comando,
SHA-256 del binario, ripetizione, esito e timeout sono nei JSON di ogni corsa. Il
[runner usato](../../../build/moonshot-fase0-native/runner-used.py) è conservato separatamente.
Le prove sono seriali; le compilazioni non si sovrappongono alle misure.
Log, CSV, metadati e sorgenti della strumentazione sono conservati anche in
[`fase0-prove.zip`](fase0-prove.zip), con percorsi `build/...` per ripristinare i riferimenti in un clone.

**FATTO di protocollo:** canvas effettivo 1920×1080, `target_fps=0`, `vsync_hint=false`, nessuna cattura
immagine/readback nel benchmark. Simulazione a `f32(1)/60`, compresi prestage, warmup e animazioni statiche;
`frame.time` dipende dall'indice del driver. I quattro stage che chiamano il gameplay reale (25, 26,
196, 197) usano input costruito dal driver senza tasti live. Gli stage non selezionati avanzano dopo due
frame e preparano comunque le scene successive. Non viene simulata un'intera partita normale.
Fonti: [driver v1](../../../build/moonshot-fase0-native/source-driver-v1.odin),
righe 278, 472–485 e 513–568; intestazioni dei log sotto.

Il frame time è l'intervallo reale riportato da `rl.GetFrameTime()`, mentre il `dt` della simulazione resta
fisso: venti secondi simulati non richiedono venti secondi di parete. `wrapped_draw_ms` e i breakdown
`CPU SCENE/WORLD/SUBMISSION` misurano tempo CPU e possono comprendere attese del driver; non sono
query GPU. Alcuni scope sono annidati e non vanno sommati. Il CSV viene accumulato in memoria e stampato
alla fine di ogni stage, dopo i campioni; il warmup seguente tiene fuori dalle statistiche questa transizione.
Fonti: driver v1, righe 271–352 e 562–568.

## Completezza e significato degli stage

| Caso | Processi osservati | Esito | Stage completi per corsa | Campioni misurati per stage | CSV per corsa, warmup incluso |
|---|---:|---|---|---|---:|
| 1× `-o:none` | 3 | 3 exit 0 | 0, 25, 26, 39, 40, 63, 88, 195, 196, 197 | 600; 25/26: 240 | 5.880 |
| 1× `-o:speed` | 3 | 3 exit 0 | stessi dieci | 600; 25/26: 240 | 5.880 |
| 2× `-o:speed` | 3 | 3 exit 0 | 0, 25, 26 | 600; 25/26: 1.200 | 3.180 |
| 4× `-o:speed` | 1 | timeout esterno 360 s | 0, 25; manca 26 | 600; 25: 1.200 | 1.920 |
| 8× `-o:speed` | 3 | 3 exit 0 | 0, 25, 26 | 600; 25/26: 1.200 | 3.180 |

Ogni stage selezionato ha 60 frame di warmup esclusi dalle statistiche e presenti nel CSV.
**MISURA di controllo:** su tutte le 80 finestre sono stati verificati schema CSV, numerazione consecutiva,
conteggi, `dt`, canvas e corrispondenza tra statistiche ricalcolate dai CSV e riepiloghi del log entro
l'arrotondamento a tre decimali. I 24 processi headless della stessa sessione sono descritti nel
[rapporto separato](fase0-headless.md); i 37 record totali non sono 37 prove grafiche.

La [politica delle ripetizioni](../../../build/moonshot-fase0-native/repetition-policy.json) registra che,
dopo il primo timeout 4×, r2 e r3 di quel caso **non sono state eseguite**. Un primo avvio di 8× r2 è stato
interrotto nel cambio di sequenza, conservato in
[`interrupted/`](../../../build/moonshot-fase0-native/interrupted/) ed escluso; il nuovo r2 completo usa
lo stesso binario. Queste eccezioni impediscono di chiamare la sessione «tre repliche per ogni caso».

| Stage | Scena e natura della prova |
|---:|---|
| 0 | Vista iniziale Cyber, scena statica con animazioni |
| 25 | Secret, montato, input W+D continuo, gameplay reale |
| 26 | Secret, a piedi verso una pattuglia, input S+D continuo, gameplay e incontri reali |
| 39 | Laboratorio visivo Cyber, scena statica con animazioni |
| 40 | Laboratorio visivo West, scena statica con animazioni |
| 63 | Rilievo Cyber, scena statica con animazioni |
| 88 | Snow, appena dentro la prima caverna abitata, scena statica con animazioni |
| 195 | Cyber, fixture di sei nemici, scena statica con animazioni |
| 196 | Gameplay della fixture, input W+D solo nei primi 45 frame |
| 197 | Gameplay della fixture, input S+A solo nei primi 45 frame |

Fonti: driver v1, righe 152–233, 529–559, 678–738, 746–762, 807–844 e
[`campaign_cartoon_smoke.odin:28`](../../../src/application/campaign_cartoon_smoke.odin).
Per 39/40/63/88/195/196/197 non è stata eseguita una misura alle scale 2×/4×/8×.

## Tempi delle finestre misurate

Tutte le durate sono in millisecondi. «Intervallo» significa minimo–massimo fra i tre valori calcolati
**separatamente per corsa**; p95 e p99 sono nearest-rank per singola corsa, non percentili aggregati.
«Massimo osservato» è il maggiore dei massimi delle corse. L'ultima colonna conserva i conteggi r1/r2/r3
di frame strettamente maggiori di 16,67 ms. Non si aggregano campioni o finestre di durata diversa.

### Baseline 1×, `-o:none`

Fonti dei numeri: [r1](../../../build/moonshot-fase0-native/logs/baseline-none-r1.log), [r2](../../../build/moonshot-fase0-native/logs/baseline-none-r2.log), [r3](../../../build/moonshot-fase0-native/logs/baseline-none-r3.log).

| Stage | Media ms, intervallo | p95 ms, intervallo | p99 ms, intervallo | Massimo ms osservato | Frame >16,67 ms, r1 / r2 / r3 |
|---:|---:|---:|---:|---:|---|
| 0 | 10,108–10,279 | 13,175–13,704 | 14,509–14,825 | 15,815 | 0 / 0 / 0 |
| 25 | 13,030–13,061 | 16,230–16,413 | 16,951–17,373 | 19,847 | 6 / 9 / 8 |
| 26 | 12,933–13,083 | 17,168–18,160 | 40,242–46,493 | 83,349 | 16 / 16 / 14 |
| 39 | 13,273–13,365 | 14,904–15,020 | 16,440–16,876 | 17,909 | 7 / 4 / 4 |
| 40 | 14,745–14,778 | 17,440–17,782 | 18,059–20,521 | 22,166 | 98 / 120 / 102 |
| 63 | 12,400–13,054 | 14,494–16,094 | 16,763–18,406 | 51,779 | 8 / 15 / 16 |
| 88 | 11,350–12,391 | 13,045–15,461 | 13,677–16,141 | 17,393 | 1 / 6 / 0 |
| 195 | 12,709–13,873 | 14,024–16,578 | 14,826–17,605 | 18,313 | 26 / 25 / 0 |
| 196 | 13,534–14,685 | 14,820–17,116 | 36,968–38,641 | 73,718 | 48 / 50 / 10 |
| 197 | 13,768–14,959 | 15,390–17,219 | 37,510–39,895 | 71,669 | 60 / 71 / 9 |

### Baseline 1×, `-o:speed`

Fonti dei numeri: [r1](../../../build/moonshot-fase0-native/logs/baseline-speed-r1.log), [r2](../../../build/moonshot-fase0-native/logs/baseline-speed-r2.log), [r3](../../../build/moonshot-fase0-native/logs/baseline-speed-r3.log).

| Stage | Media ms, intervallo | p95 ms, intervallo | p99 ms, intervallo | Massimo ms osservato | Frame >16,67 ms, r1 / r2 / r3 |
|---:|---:|---:|---:|---:|---|
| 0 | 9,571–10,289 | 11,123–14,547 | 12,179–15,543 | 17,528 | 0 / 1 / 0 |
| 25 | 12,087–13,054 | 14,423–16,044 | 15,381–16,717 | 22,452 | 3 / 2 / 1 |
| 26 | 11,566–12,641 | 14,721–17,285 | 19,144–19,993 | 23,063 | 15 / 13 / 10 |
| 39 | 12,365–13,479 | 13,879–16,005 | 14,794–17,097 | 17,686 | 11 / 12 / 0 |
| 40 | 13,732–14,777 | 15,324–17,110 | 15,852–18,908 | 20,743 | 60 / 58 / 0 |
| 63 | 11,934–13,042 | 13,445–15,746 | 14,083–16,983 | 18,164 | 7 / 12 / 0 |
| 88 | 11,420–12,444 | 12,887–15,410 | 13,464–16,927 | 17,839 | 9 / 3 / 0 |
| 195 | 12,816–14,184 | 14,259–17,079 | 14,845–18,111 | 22,880 | 44 / 43 / 0 |
| 196 | 13,220–14,541 | 14,738–17,175 | 15,120–18,062 | 19,752 | 60 / 61 / 0 |
| 197 | 13,396–14,843 | 15,118–17,436 | 16,114–18,601 | 19,789 | 74 / 72 / 2 |

### Scala 2×, `-o:speed`

Fonti dei numeri: [r1](../../../build/moonshot-fase0-native/logs/scale-2-speed-r1.log), [r2](../../../build/moonshot-fase0-native/logs/scale-2-speed-r2.log), [r3](../../../build/moonshot-fase0-native/logs/scale-2-speed-r3.log).

| Stage | Media ms, intervallo | p95 ms, intervallo | p99 ms, intervallo | Massimo ms osservato | Frame >16,67 ms, r1 / r2 / r3 |
|---:|---:|---:|---:|---:|---|
| 0 | 9,431–10,109 | 10,871–13,706 | 11,597–15,104 | 19,450 | 0 / 0 / 1 |
| 25 | 11,815–12,913 | 13,565–16,003 | 14,537–16,804 | 20,233 | 17 / 13 / 0 |
| 26 | 11,449–12,570 | 13,780–15,952 | 14,581–16,900 | 24,924 | 16 / 20 / 4 |

### Scala 4×, `-o:speed`, una sola corsa parziale

Fonti dei numeri: [r1](../../../build/moonshot-fase0-native/logs/scale-4-speed-r1.log).

| Stage | Media ms, intervallo | p95 ms, intervallo | p99 ms, intervallo | Massimo ms osservato | Frame >16,67 ms, r1 / r2 / r3 |
|---:|---:|---:|---:|---:|---|
| 0 | 10,212 | 13,578 | 14,740 | 15,722 | 0 |
| 25 | 13,197 | 16,381 | 17,137 | 17,831 | 39 |
| 26 | mancante | mancante | mancante | mancante | nessun CSV v1 |

### Scala 8×, `-o:speed`

Fonti dei numeri: [r1](../../../build/moonshot-fase0-native/logs/scale-8-speed-r1.log), [r2](../../../build/moonshot-fase0-native/logs/scale-8-speed-r2.log), [r3](../../../build/moonshot-fase0-native/logs/scale-8-speed-r3.log).

| Stage | Media ms, intervallo | p95 ms, intervallo | p99 ms, intervallo | Massimo ms osservato | Frame >16,67 ms, r1 / r2 / r3 |
|---:|---:|---:|---:|---:|---|
| 0 | 10,018–10,766 | 11,319–14,091 | 11,991–15,309 | 15,881 | 0 / 0 / 0 |
| 25 | 12,750–13,843 | 14,549–16,598 | 15,541–17,136 | 25,734 | 55 / 16 / 4 |
| 26 | 13,342–15,409 | 16,513–18,107 | 21,906–25,343 | 75,123 | 253 / 51 / 75 |

Per 4× i numeri singoli riguardano r1: non esiste una stima della variabilità fra repliche.
Il mancato stage 26 non vale zero e non viene sostituito da dati di altre scale o della validazione v2.
`-o:none` non implica il flag `-debug`. Le differenze none/speed sono osservate in sessioni separate:
non isolano da sole un collo di bottiglia CPU o GPU, né eliminano effetti dell'ordine e dello stato termico.

## Tracciati ripetibili e movimento realmente osservato

**MISURA:** le tre repliche di ciascun caso completo hanno lo stesso hash dei tracciati per ogni stage;
anche tutte le sei baseline none/speed coincidono. Il confronto include ogni frame, warmup compreso:
`simulation_dt`, `world_clock`, posizione roam, cella/layer, fase, montatura, posizione e target della camera.
Gli hash sono nei [risultati](../../../build/moonshot-fase0-native/results.json); il calcolo è in
[`summarize_frames`](../../../tools/moonshot/benchmark.py). Questo verifica l'uguaglianza dei campi
serializzati, non dell'intero stato: salute, carte, nemici e RNG non sono tutti inclusi.
Nessun confronto fra scale pretende identità della geometria o del percorso.

La tabella seguente usa tutti i frame di ogni stage, warmup incluso. «Percorso» è la somma delle distanze
fra posizioni roam consecutive, in unità di cella; può includere gli spostamenti del tattico, non solo passi
liberi. La coda conta le posizioni finali consecutive uguali entro 0,00001 celle. I dati coincidono nelle
repliche del rispettivo caso; 4× ha soltanto r1. Fonti: i CSV nei log già collegati.

| Scala | Stage | Frame con warmup | Percorso osservato, celle | Coda di posizioni ferme, frame |
|---|---:|---:|---:|---:|
| 1× none/speed | 25 | 300 | 25,019 | 48 |
| 1× none/speed | 26 | 300 | 16,269 | 6 |
| 1× none/speed | 196 | 660 | 0,000 | 660 |
| 1× none/speed | 197 | 660 | 1,000 | 624 |
| 2× | 25 | 1260 | 25,019 | 1008 |
| 2× | 26 | 1260 | 88,904 | 1 |
| 4×, r1 | 25 | 1260 | 25,019 | 1008 |
| 8× | 25 | 1260 | 25,019 | 1008 |
| 8× | 26 | 1260 | 85,967 | 1 |

**MISURA:** nello stage 25 lungo, le ultime 1.008 posizioni su 1.260 sono ferme: l'estensione a 1.200
campioni non produce venti secondi di movimento sostenuto. Un ostacolo o una collisione sono
**INFERENZE compatibili**, non una causa dimostrata dal CSV. Lo stage 26 a 2×/8× mantiene invece
spostamenti fino in fondo e attraversa sia `.Loot` sia `.Combat`; a 1× gran parte del tratto è già in
combattimento. Non si può attribuire una differenza di tempo esclusivamente al lato della mappa:
contenuti vicini, posizione, durata e lavoro del gameplay cambiano.

Gli input di 196/197 finiscono prima del warmup di 60 frame. **MISURA:** 196 è immobile per l'intero
tracciato e 197 compie un solo spostamento di una cella prima di restare fermo. Sono prove con gameplay,
nemici e timeline attivi, non di attraversamento prolungato né di combattimento mobile sostenuto.
**FATTO:** il limite `held<45` è nel driver v1, righe 529–538; la strumentazione v2 non lo estende.

## Cache, ingressi e memoria

**MISURA:** questi sono incrementi dei contatori fra fine warmup e ultimo frame misurato, uguali fra
repliche. I contatori non sono durate; la loro coincidenza con un picco non dimostra causalità.
Gli altri stage baseline e lo stage 0 a ogni scala completata hanno incrementi 0 / 0 / 0.
Fonti: record `GEOMETRY CACHE`, `SUN CACHE` e colonne CSV dei log collegati sopra.

| Caso/stage | Rebuild misurati | Upload misurati | Render sole misurati |
|---|---:|---:|---:|
| 1× none/speed, 25 | 0 | 7 | 4 |
| 1× none/speed, 26 | 0 | 9 | 3 |
| 2×, 25 | 0 | 7 | 4 |
| 2×, 26 | 0 | 98 | 23 |
| 4× r1, 25 | 0 | 7 | 4 |
| 8×, 25 | 0 | 7 | 4 |
| 8×, 26 | 0 | 97 | 22 |

Il warmup non scompare dai dati. Esempi della **sola r1**, separati dalle tabelle dei campioni misurati:

| Caso | Primo intervallo stage 0, ms | Primo intervallo stage 25, ms | Massimo warmup stage 26, ms |
|---|---:|---:|---:|
| 1× none | 5839,495 | 465,993 | 265,926 |
| 1× speed | 715,598 | 465,310 | 49,052 |
| 2× speed | 769,806 | 531,945 | 48,287 |
| 4× speed | 875,577 | 550,680 | mancante |
| 8× speed | 1394,467 | 510,514 | 76,793 |

Questi intervalli possono includere setup della scena, cambio canvas, caricamenti e lavoro dopo la
presentazione precedente; dopo uno stage comprendono anche la transizione dal log precedente.
Non sono cronometri isolati della generazione o dell'intero caricamento. I record `EXPEDITION STOCK`
misurano separatamente decode/fallback e upload/mip delle scorte, non tutto l'avvio. Tutti i record stock
della sessione indicano `procedural_fallback=false`.

La RSS è il picco del **processo completo**, riportato da `/usr/bin/time -l`; è distinta dal payload mesh,
dalla memoria richiesta agli allocatori e dalla VRAM. Conversione: MiB = byte / 1.048.576.
Fonti: campo `process_peak_rss_bytes` nei JSON delle corse e righe `maximum resident set size` dei log.

| Caso | Picco RSS MiB r1 / r2 / r3 |
|---|---|
| 1× none | 337,12 / 407,62 / 429,12 |
| 1× speed | 399,28 / 455,59 / 442,42 |
| 2× speed | 445,61 / 549,89 / 514,05 |
| 4× speed | non disponibile: timeout |
| 8× speed | 1322,72 / 1441,31 / 1454,94 |

Non confrontare queste RSS come se tutti i processi avessero la stessa storia: la baseline percorre dieci
stage selezionati e tutti i prestage, le scale grandi solo i primi tre selezionati. Il campo
`GEOMETRY RESIDENT mesh_payload_bytes` conta 36 byte per vertice delle mesh di terreno, siti e
strutture; esclude texture, overhead driver e copia CPU Raylib. `line_bytes` è memoria di linee CPU.
**FATTO:** driver v1, righe 325–334. Nessuno di questi numeri è la memoria GPU totale.

## Scala 4×: dato incompleto e correzione dell'osservabilità

**MISURA v1:** [r1 4×](../../../build/moonshot-fase0-native/logs/scale-4-speed-r1.log) termina le finestre
0 e 25, poi scarica le risorse della spedizione; non stampa il riepilogo né CSV di 26 e non chiude
normalmente il processo. Il [JSON della corsa](../../../build/moonshot-fase0-native/logs/scale-4-speed-r1.json)
registra il timeout esterno a 360 s. Il teardown è visibile nelle righe finali del log. Non si dispone di
salute e fase finali v1; non si ricostruiscono campioni dello stage 26 mancanti.

**FATTO di codice congelato:** 26 posiziona il giocatore a piedi prima di una pattuglia (driver v1,
righe 417–430 e 716) e chiama l'update reale (righe 541–549). La sconfitta o salute non positiva fa
`host.pop` ([expedition_scene.odin](../../../src/run/expedition_scene.odin),
righe 432–433); il pop distrugge la scena e riprende quella sottostante senza necessariamente chiudere
l'app ([host/scene.odin](../../../src/engine/host/scene.odin), righe 200–217).
Il distruttore v1 libera lo smoke senza registrare l'incompletezza (driver, riga 509), e il CSV viene stampato
solo al completamento della finestra (righe 343–352).

**INFERENZA v1:** una sconfitta e il ritorno all'hub sono compatibili con il teardown e con il processo
ancora vivo. La sola v1 non dimostra quale condizione abbia causato l'uscita dalla spedizione.
Non ci sono frame del menu inseriti nelle statistiche: il driver scompare prima di registrare 26.
Il timeout non è prova che la GPU non regga 4×; la riuscita di 8× esclude una lettura monotona semplicistica.

La strumentazione **v2**, successiva e fuori dalle copie congelate, marca il completamento normale;
se lo smoke viene distrutto incompleto stampa stage, held, conteggi, salute, fase e stato di estrazione,
scarica il CSV parziale e dopo il normale cleanup termina con exit 2. Cambia osservabilità e uscita del
benchmark, non salute, input, selezione stage o gameplay. Le sue validazioni sono separate dalle 13 corse
v1 e non alimentano le tabelle di questo rapporto. Fonte: [driver v2 conservato](../../../build/moonshot-fase0-validation-v2/source-driver-v2.odin),
righe 522–536 e 694.

**MISURA diagnostica v2, separata:** il [test normale](../../../build/moonshot-fase0-validation-v2/logs/normal.json)
termina con exit 0 e tre righe CSV nello stage 0. La [prova incompleta 4×](../../../build/moonshot-fase0-validation-v2/logs/incomplete.json),
compilata `-o:none`, termina senza timeout con exit 2 e 2.889 righe CSV: 660 nello stage 0, 1.260 nel 25,
969 nel 26. Il [log diagnostico](../../../build/moonshot-fase0-validation-v2/logs/incomplete.log), riga 5072,
registra `health=0 phase=Defeat finished=true`, con `extracting=false world_extracting=false`;
`held=969`, `measured_samples=909`, `captured_frames=969`. La sconfitta è quindi osservata direttamente
in questa nuova esecuzione, non dedotta dal timeout. I tracciati precedenti 0 e 25 coincidono con v1
(`prior_trajectory_matches_v1` entrambi `true`). Il protocollo di questa diagnosi conserva dt e durata
originali, ma usa una build diversa: non riscrive il dato storico v1, non sostituisce le repliche mancanti
e i suoi tempi non entrano nelle tabelle prestazionali. Comandi e parametri sono nel
[record di compilazione](../../../build/moonshot-fase0-validation-v2/logs/build-incomplete.json).

## Conseguenze per il piano

**INFERENZA sostenuta dalle misure:** conviene conservare una baseline che includa distribuzione e picchi,
non soltanto la media. Ci sono già scene baseline oltre budget, e un percorso 8× completo ha p99 oltre
budget pur mantenendo tutte le medie sotto soglia. Prima di scegliere una dimensione di produzione servono
percorsi verificati, copertura degli altri biomi/architetture e il contratto di salvataggio descritto nel
[rapporto headless](fase0-headless.md).

Questa sessione non misura l'esplorazione completa di una mappa, un nuovo renderer, un back-end alternativo,
un tempo GPU isolato, né la qualità artistica o le occlusioni. Le mappe scalate modificano il lato nelle copie;
non aggiungono il sistema di contenuti e streaming del moonshot. Questi numeri possono guidare le prossime
prove in laboratorio, ma non dimostrano che moltiplicare il lato basti a ottenere vastità giocabile.
