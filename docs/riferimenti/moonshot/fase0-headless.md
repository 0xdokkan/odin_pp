# Fase 0 — Misure headless native: scala, memoria, snapshot e IA

4 novembre 2026. **MISURA:** 24 processi conclusi con exit 0, 72 record, nessun timeout né errore del probe.
La generazione riesce a tutte le scale provate. Le 18 capture a scala 1× sono valide; le 54 capture a 2×/4×/8×
sono rifiutate. Tutti i 72 primi consigli ottenuti sono validi ed eseguibili secondo `advisor.advice_possible`.
Questo risultato non certifica il salvataggio di un mondo ampliato o le prestazioni del gioco completo.

## Provenienza e protocollo

È stata analizzata **soltanto** la sessione `build/moonshot-fase0-native`, eseguita fuori sandbox. Il precedente
tentativo `build/moonshot-fase0` contiene un errore di `/usr/bin/time` nell'accesso a `sysctl`: non entra in
nessuna tabella di questo rapporto. Non entrano neppure le prove esplorative del piano o la singola corsa
funzionale del probe.

Il [manifest nativo](../../../build/moonshot-fase0-native/manifest.json) registra base
`ddc6b186942d4c78597dc0f3f06c1a73483b716e`, macOS 26.6.2 arm64, Odin `dev-2026-10:84bc3fc21`, seed 42
ed hash dei file nelle copie. La macchina della sessione è il Mac M1; non ci sono dati Windows/RTX 3060.
La base include gli strumenti della Fase 0 identificati dagli hash: non presentarla come eseguibile storico
immutato del solo commit. Il protocollo eseguibile è nel [README](../../../tools/moonshot/README.md);
l'harness è [probe/main.odin](../../../tools/moonshot/probe/main.odin).

Otto casi: quattro scale del lato per due build (`-o:none` diagnostica e `-o:speed` ottimizzata). Tre processi
separati per caso; ogni processo misura una volta Cyber, Snow e Space, in questo ordine. L'ordine dei casi
è invertito nella seconda ripetizione. Nessuna compilazione si sovrappone a queste misure. `-o:none` qui
non implica il flag `-debug`. Le mediane sono calcolate sui tre campioni, non su medie dei biomi.

Nelle copie cambia soltanto il moltiplicatore di `map_size`; i guardrail restano attivi. Generazione con
`retouched=false`, giocatore di prova con salute 100, attacco 5, difesa 0, nessuno zaino; per la IA si attiva
il gruppo generato numero 0. Il contesto passa dalla funzione reale `run.advisor_context_expedition`.
La ricerca si ferma al primo consiglio oppure al limite di 128 unità di lavoro/5000 ms di ricerca.
Il limite temporale viene controllato fra chiamate: un nodo non è interrompibile. Timeout esterno 240 s
per il processo con i tre biomi. Tutti i consigli di questa serie arrivano prima del limite.

**Che cosa misura «prima risposta API»:** `first_advice_ms` somma fotografia IA, costruzione della radice e
ricerca fino al primo risultato osservabile dopo `search_step`. Esclude preparazione dell'incontro,
creazione del contesto e inizializzazione della ricerca. Non include thread, attese, pubblicazione,
lettura e visualizzazione della carta nel gioco; non è latenza della carta UI. L'inizializzazione è registrata
separatamente nei log. La soglia di 5000 ms riguarda la sola ricerca, non questa somma.

## Build ottimizzata: tutte le combinazioni

Mediane di tre campioni in millisecondi. La fotografia IA è una componente della prima risposta, non un
tempo da sommarle di nuovo. Tutti i primi consigli hanno profondità 1: la ricerca è interrotta alla prima
risposta e non ha completato i successivi approfondimenti. «Capture» riguarda il checkpoint prima dell'incontro.

| Scala lato | Bioma | Lato | Generazione ms | Fotografia IA ms | Prima risposta API ms | Intervallo risposta API ms | Capture valida |
|---|---|---:|---:|---:|---:|---|---|
| 1× | Cyber | 160 | 8,807 | 0,121 | 83,970 | 83,937–84,063 | 3/3 |
| 1× | Snow | 192 | 1,568 | 0,174 | 73,221 | 72,874–73,623 | 3/3 |
| 1× | Space | 224 | 2,789 | 0,255 | 140,740 | 140,598–140,953 | 3/3 |
| 2× | Cyber | 320 | 37,299 | 0,601 | 91,214 | 91,018–92,483 | 0/3; rifiutata |
| 2× | Snow | 384 | 6,821 | 0,722 | 104,495 | 104,347–109,996 | 0/3; rifiutata |
| 2× | Space | 448 | 12,247 | 0,846 | 149,160 | 148,941–164,925 | 0/3; rifiutata |
| 4× | Cyber | 640 | 150,321 | 2,325 | 102,656 | 101,698–103,530 | 0/3; rifiutata |
| 4× | Snow | 768 | 27,728 | 2,530 | 121,640 | 121,077–121,649 | 0/3; rifiutata |
| 4× | Space | 896 | 49,906 | 3,276 | 175,125 | 173,918–176,870 | 0/3; rifiutata |
| 8× | Cyber | 1280 | 344,015 | 9,118 | 147,249 | 146,476–165,327 | 0/3; rifiutata |
| 8× | Snow | 1536 | 111,870 | 9,916 | 192,095 | 191,283–195,684 | 0/3; rifiutata |
| 8× | Space | 1792 | 200,834 | 13,079 | 328,521 | 325,926–329,337 | 0/3; rifiutata |

## Build diagnostica, separata

Ogni terna è Cyber / Snow / Space, sempre mediana di tre campioni, in ms. Le condizioni del probe e i risultati
logici sono gli stessi. Non usare queste durate per stimare automaticamente il frame time della build ottimizzata.

| Scala lato | Generazione ms | Prima risposta API ms |
|---|---|---|
| 1× | 61,231 / 13,367 / 24,056 | 1.391,194 / 1.100,095 / 2.345,763 |
| 2× | 216,060 / 57,403 / 105,821 | 1.495,877 / 1.577,481 / 2.439,295 |
| 4× | 877,526 / 235,101 / 430,961 | 1.583,587 / 1.711,675 / 2.656,018 |
| 8× | 1.999,495 / 949,349 / 1.732,401 | 1.857,858 / 2.141,692 / 3.419,370 |

## Memoria: richieste, arene e RSS restano distinte

**MISURA:** i picchi delle richieste intercettate da heap e temp coincidono fra le tre ripetizioni e fra
le due build, per ciascuna combinazione. La tabella riporta byte, non MiB, per conservare i valori esatti.
Sono massimi separati: non sommarli chiamandoli picco simultaneo o RSS.

| Scala lato | Bioma | Picco heap tracciato, byte | Picco temp tracciato, byte |
|---|---|---:|---:|
| 1× | Cyber | 4.959.316 | 7.573.190 |
| 1× | Snow | 5.592.576 | 517.875 |
| 1× | Space | 7.062.244 | 1.156.201 |
| 2× | Cyber | 11.606.884 | 35.096.262 |
| 2× | Snow | 15.275.352 | 2.066.163 |
| 2× | Space | 19.857.124 | 4.500.969 |
| 4× | Cyber | 38.026.084 | 140.379.846 |
| 4× | Snow | 53.319.000 | 8.259.315 |
| 4× | Space | 71.036.644 | 17.764.129 |
| 8× | Cyber | 143.702.884 | 280.757.958 |
| 8× | Snow | 205.493.592 | 33.031.923 |
| 8× | Space | 275.754.724 | 70.733.601 |

Il tracking conta le richieste indirizzate agli allocatori intercettati. Le sue mappe interne sono allocate
fuori da questi conteggi: **i byte non includono tutto l'overhead del tracker, i tempi includono il suo costo**.
Le allocazioni virtuali della IA sono censite separatamente come occupate, riservate e impegnate; il suo heap
diretto contiene un payload di 423.936 byte in ogni caso. Questi dati non includono renderer o memoria GPU.

`advisor_snapshot_memory`, `advisor_rehearsal_memory` e `advisor_try_memory` sono fotografie dell'allocatore
al punto di osservazione, non picchi durante l'intera ricerca. La try arena si resetta fra le prove. Il worker
reale usa tre slot di fotografia (`src/advisor/worker.odin:93`); qui si misura una fotografia e una ricerca sincrona. A 8× Space, per esempio,
la fotografia e la radice hanno rispettivamente 170.313.926 e 170.301.262 byte occupati nella prima ripetizione
ottimizzata; non sono misure della memoria totale del worker.

**Limite del protocollo:** il probe trattiene l'arena temporanea della generazione fino alla fine del sample,
anche mentre misura la IA, e mantiene il checkpoint allocato. La memoria liberata logicamente dall'allocatore
temporaneo può restare nell'arena fino al reset. Nella prima ripetizione Cyber 8× ottimizzata, il picco temp
richiesto è 280.757.958 byte, mentre l'arena temporanea a fine sample ha 502.022.088 byte impegnati.
Non sono valori in contraddizione: descrivono richieste vive e memoria trattenuta con durate diverse.
Questa durata di vita del protocollo non certifica quella di una partita reale.

La RSS viene da `/usr/bin/time -l`, campo `maximum resident set size`, acquisito nel JSON come
`process_peak_rss_bytes`. È il massimo del **processo che misura tutti e tre i biomi**, non un dato per bioma.
La tabella riporta il massimo fra le tre esecuzioni. Include processo e overhead; può dipendere dalle politiche
di memoria del sistema. Non va attribuita alla sola area, alla sola IA o a Space perché è l'ultimo bioma.

| Scala lato | RSS max processo `-o:none`, byte | RSS max processo `-o:speed`, byte |
|---|---:|---:|
| 1× | 22.675.456 | 21.807.104 |
| 2× | 69.828.608 | 68.993.024 |
| 4× | 295.256.064 | 294.436.864 |
| 8× | 903.020.544 | 947.568.640 |

Il massimo osservato è 947.568.640 byte nel caso 8× ottimizzato (circa 903,7 MiB, conversione aritmetica).
È il consumo del protocollo con le durate indicate, non una previsione della memoria del prodotto.
La variabilità è visibile anche senza cambiare sorgenti: le tre RSS del caso 8× diagnostico sono
903.020.544 / 796.082.176 / 777.371.648 byte. Non assegnare una causa specifica senza un profilo ulteriore.

## Esiti logici, lavoro della IA e differenze del contenuto

- 72 generazioni e creazioni stanza riuscite, 72 contesti IA noti, 72 consigli validi ed eseguibili;
  zero timeout, zero `error`, zero budget esauriti. Tutti i consigli sono il primo approfondimento, profondità 1;
  `advisor_done=false` significa che resterebbero approfondimenti, non che manca il risultato.
- Le 18 capture 1× riescono e passano `valid_snapshot`; le altre 54 sono rifiutate. È una verifica della copia
  in memoria prima dello scontro, non un round-trip di restore, serializzazione JSON, scrittura e lettura su disco.
  Le durate quasi nulle del rifiuto nelle mappe grandi non sono un'accelerazione del salvataggio.
- Tutti i record terminano con heap/temp tracciati residui pari a zero e zero bad free. Questo non dimostra
  assenza di perdite in tutti gli allocatori del processo.
- `level_recopies=pool_recopies=0` in tutti i casi: questi contatori escludono le copie iniziali della fotografia
  e della radice (`src/advisor/copy.odin:193`). Non significano «la IA non copia la mappa».

| Scala lato | HP totali gruppo Cyber / Snow / Space | Nodi Cyber / Snow / Space | Consiglio Space |
|---|---|---|---|
| 1× | 10 / 22 / 56 | 22 / 29 / 34 | Dodge |
| 2× | 14 / 22 / 64 | 22 / 29 / 34 | Dodge |
| 4× | 18 / 22 / 76 | 22 / 29 / 34 | Dodge |
| 8× | 30 / 22 / 108 | 22 / 29 / 34 | Card |

Nodi e unità di lavoro coincidono in questa serie e sono stabili fra ripetizioni e build. Cyber/Snow hanno
due nemici, Space quattro; la mano ha cinque carte. Cyber e Snow consigliano una carta a ogni scala;
Space passa da schivata a carta a 8×. **INFERENZA:** l'aumento degli HP e il cambiamento di geografia/posizione
contribuiscono a cambiare la situazione; il passaggio del consiglio non prova da solo un errore o una scelta
migliore, e l'aumento del tempo non misura soltanto l'area della mappa.

I siti/gruppi restano 16/10 Cyber, 19/14 Snow, 16/12 Space. Le dimensioni diventano rispettivamente
160/192/224, 320/384/448, 640/768/896 e 1280/1536/1792. È uno stress tecnico della taglia: non un mondo
ripopolato, bilanciato o esplorato fino al bordo.

In serie future un consiglio assente deve restare un esito esplicito: `first_advice_ms=0` con `advice_valid=false`
è un valore sentinella e non entra nelle medie. `advisor_budget_exhausted=true` indica mancata risposta entro
il budget; `advisor_done=true` senza consiglio indica ricerca terminata senza proposta. `advisor_skipped` ed
`error` distinguono misura non eseguita ed errore. Anche `complete=true` nel report del runner significa
raccolta completa, non promozione di capture, consiglio o prodotto.

## Implicazioni per il piano

**INFERENZA:** il blocco funzionale più netto resta il checkpoint già a 2×, mentre generazione e primo
consiglio API completano lo stress 8× in questo sottoinsieme. Il costo della fotografia IA cresce e la memoria
contemporanea del protocollo diventa rilevante: prima di promuovere la taglia occorre definire residenza dei
dati, durata dello scratch, fotografia e salvataggio, senza aggirare i controlli. Questi dati non giustificano
ancora una migrazione di back-end grafico: qui la GPU non è misurata.

Restano fuori da questo rapporto: frame presentati, traversata, massima complessità del combattimento,
worker concorrente al renderer, tutti i dodici biomi, seed diversi, stato dopo modifiche persistenti e Windows.
Tre campioni rendono verificabile la prova, non una certificazione statistica generale.

## Log nativi e riproduzione dei calcoli

Ogni link sotto punta al log integrale usato; il JSON omonimo conserva comando, exit code, timeout, RSS e hash
del binario. I file nella directory `build/` sono artefatti locali della sessione e vanno conservati insieme
al manifest per audit. Le prove esplorative archiviate in `scala/` sono una serie diversa.

| Caso | Ripetizioni native |
|---|---|
| headless-1-speed | [headless-1-speed-r1.log](../../../build/moonshot-fase0-native/logs/headless-1-speed-r1.log) · [headless-1-speed-r2.log](../../../build/moonshot-fase0-native/logs/headless-1-speed-r2.log) · [headless-1-speed-r3.log](../../../build/moonshot-fase0-native/logs/headless-1-speed-r3.log) |
| headless-2-speed | [headless-2-speed-r1.log](../../../build/moonshot-fase0-native/logs/headless-2-speed-r1.log) · [headless-2-speed-r2.log](../../../build/moonshot-fase0-native/logs/headless-2-speed-r2.log) · [headless-2-speed-r3.log](../../../build/moonshot-fase0-native/logs/headless-2-speed-r3.log) |
| headless-4-speed | [headless-4-speed-r1.log](../../../build/moonshot-fase0-native/logs/headless-4-speed-r1.log) · [headless-4-speed-r2.log](../../../build/moonshot-fase0-native/logs/headless-4-speed-r2.log) · [headless-4-speed-r3.log](../../../build/moonshot-fase0-native/logs/headless-4-speed-r3.log) |
| headless-8-speed | [headless-8-speed-r1.log](../../../build/moonshot-fase0-native/logs/headless-8-speed-r1.log) · [headless-8-speed-r2.log](../../../build/moonshot-fase0-native/logs/headless-8-speed-r2.log) · [headless-8-speed-r3.log](../../../build/moonshot-fase0-native/logs/headless-8-speed-r3.log) |
| headless-1-none | [headless-1-none-r1.log](../../../build/moonshot-fase0-native/logs/headless-1-none-r1.log) · [headless-1-none-r2.log](../../../build/moonshot-fase0-native/logs/headless-1-none-r2.log) · [headless-1-none-r3.log](../../../build/moonshot-fase0-native/logs/headless-1-none-r3.log) |
| headless-2-none | [headless-2-none-r1.log](../../../build/moonshot-fase0-native/logs/headless-2-none-r1.log) · [headless-2-none-r2.log](../../../build/moonshot-fase0-native/logs/headless-2-none-r2.log) · [headless-2-none-r3.log](../../../build/moonshot-fase0-native/logs/headless-2-none-r3.log) |
| headless-4-none | [headless-4-none-r1.log](../../../build/moonshot-fase0-native/logs/headless-4-none-r1.log) · [headless-4-none-r2.log](../../../build/moonshot-fase0-native/logs/headless-4-none-r2.log) · [headless-4-none-r3.log](../../../build/moonshot-fase0-native/logs/headless-4-none-r3.log) |
| headless-8-none | [headless-8-none-r1.log](../../../build/moonshot-fase0-native/logs/headless-8-none-r1.log) · [headless-8-none-r2.log](../../../build/moonshot-fase0-native/logs/headless-8-none-r2.log) · [headless-8-none-r3.log](../../../build/moonshot-fase0-native/logs/headless-8-none-r3.log) |

Calcoli: leggere le righe JSON dei soli `headless-*-r*.log` nativi, raggruppare per scala/build/bioma,
verificare tre campioni per gruppo, applicare la mediana a `generation_ms` e `advisor_snapshot_ms` e ai
`first_advice_ms` con `advice_valid=true`. Massimi dei campi heap/temp per la relativa combinazione;
RSS massima dei tre JSON di processo per scala/build. Nessuna media aggrega biomi o build differenti.
