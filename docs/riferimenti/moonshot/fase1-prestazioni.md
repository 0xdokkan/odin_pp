# Fase 1 — Ottimizzazione del cartoncino

4–5 novembre 2026, ramo locale `piano-moonshot`, base `ddc6b186942d4c78597dc0f3f06c1a73483b716e`.
Prosecuzione autorizzata dall'utente; pulizia dei branch rimandata. Nessun commit o push.

## Intervento e confini

**FATTO:** il renderer prepara una volta per fotogramma il piano e le tre normali di ritaglio di ogni
triangolo che riceve le ombre (`src/render/page_lab_shadow.odin:18`). La proiezione, le soglie e il bias
rimangono quelli della procedura precedente (`:36`). L'indice usa coordinate nello spazio della luce:
`q = (x − Lx·y/Ly, z − Lz·y/Ly)`, invarianti lungo ciascun raggio (`:57`). Questa proprietà permette
di restringere i candidati senza estendere ogni piccolo triangolo su tutta l'altezza del terreno.

**FATTO:** griglia 64×48, dominio calcolato dai ricevitori, margine numerico conservativo e lista completa
di riserva se si eccede il budget dell'indice o il perimetro previsto (`src/render/page_lab_draw.odin:66`,
`:377`, `:426`). Il margine amplia soltanto la ricerca; non ingrossa le ombre disegnate. Il diverso ordine
dei candidati è compatibile con il blending MIN/MAX e la scrittura della profondità disabilitata (`:465`).

**FATTO:** ombre e bordi sono inviati a raylib per poligono, con una sola riserva nel batch e una sola
impostazione di colore e UV. Il fan mantiene lo stesso ordine dei vertici; le facce con stampa conservano
il percorso precedente (`src/render/page_lab_draw.odin:232`). Nessuna nuova risorsa GPU o allocazione
per fotogramma. Le risorse sono possedute e liberate dallo stesso contesto del laboratorio.

**FATTO:** durante la ricostruzione del foglio, origini e riferimenti alle maschere della stampa sono preparati
una volta per superficie; le coordinate dei pixel sono preparate per asse (`src/render/page_lab_geometry_sample.odin:57`).
La classificazione visita soltanto la regione conservativa di ciascuna figura, con un margine di un passo
del reticolo; mantiene predicati e precedenza delle figure (`:111`). Il margine comprende anche la punta
dell'ala che supera leggermente il rettangolo di raffinamento (`:34`): gli assi e il dettaglio della mesh
non vengono ridotti. Rimosso un azzeramento ridondante del buffer temporaneo:
la successiva ricerca delle isole scrive la propria coda prima di leggerla e azzera il buffer prima della
costruzione della mesh (`src/render/page_lab_geometry.odin:475`, `:358`).

Il risultato resta confinato al laboratorio della pagina. Nessuna regola, stato, bersaglio, collisione,
carta o comando di gioco nuovo: la carta IA continua a usare lo stesso modello. I controlli IA restano
attivi e non vengono aggirati. Snapshot, dimensioni della campagna, combattimento e back-end non cambiano
in questo intervento. La morte mantiene la correzione precedente: è il cartoncino a richiudersi, mentre
il disegno conserva l'anatomia eretta e anima l'espressione.

## Verifiche funzionali

**MISURA:** `odin check src -vet -strict-style`, build complete `-o:none` e `-o:speed`, 543 test renderer
e 27 test run superati. Le suite usano `-o:none -vet -strict-style -define:ODIN_TEST_THREADS=1`, con tracking
della memoria attivo. Non sono misure prestazionali; il controllo completo di tutti i package non è stato
ripetuto per questo intervento esclusivamente nel renderer.

**MISURA:** lo stesso probe, compilato `-o:speed` contro le due copie dei sorgenti, produce CSV identici
su 2.185 pose: 240 per ciascuno dei nove atti e le 25 pose native. Tutte superano la validazione topologica.
L'impronta include conteggi, ordine, bit delle coordinate, triangoli, superfici, colori, tagli e cerniere;
esclude padding e buffer temporanei. SHA-256 comune dei CSV:
`2ffff65a8c0b5f469effec1283905746c9c888051e328a345262dab7f6f05036`.
Driver: `tools/moonshot/geometry_fingerprint/main.odin`.

**MISURA:** i test delle ombre confrontano il nuovo indice con il ritaglio precedente contro tutti i
ricevitori, su caster campionati in nove pose, più casi sui bordi della pagina, sui confini dei bucket e
fuori dal dominio. Nessun poligono positivo omesso; stessi conteggi e coordinate numericamente identiche.
Non è un confronto esaustivo di tutte le coppie in ogni animazione né un confronto dei bit degli zeri con
segno (`src/render/page_lab_shadow_test.odin:37`).

**MISURA:** gli smoke nativi completi producono 25 viste e 36 fotogrammi di sequenza, tutti validi,
con uscita 0. Alcuni avvii non riescono a inizializzare il monitor GLFW e terminano con 2; i tentativi
falliti rimangono nei log, separati dalle corse complete. Non è stata dimostrata la causa del problema
di inizializzazione. Le catture non sono usate per misurare le prestazioni.

Il primo confronto mescolava la vecchia build non ottimizzata con quella nuova ottimizzata: 60/61 immagini
identiche, con 16 pixel diversi in `morte_piega`. Ripetendo con la vecchia build `-o:speed` già identificata
nel manifest precedente, tutte le 61 immagini coincidono con la variante A. Il dettaglio della morte
ha SHA-256 RGBA8 `848288d453ac65446bebd1efa152baebff895de9e1718c99e1a7913a6088b888` in entrambe
le build ottimizzate. Il confronto finale usa soltanto build con le stesse opzioni.

## Protocollo delle misure

Mac M1, macOS 26.6.2 ARM64; Odin `dev-2026-10:84bc3fc21`, raylib 6.0. Il driver isolato usa lo stesso
canvas logico e raster 1920×1080 per entrambe le versioni, senza audio o profilo. Quattro atti, 60 frame
di riscaldamento esclusi e 600 misurati per atto, tempo simulato fisso 1/60 s; nessuna cattura nel benchmark.
La compilazione precede le misure. I processi grafici girano uno alla volta.

I percentili sono ricalcolati dai singoli campioni CSV con rango superiore. `frame` include il tempo del
fotogramma presentato; `update` e `draw` sono scope CPU interni e non misure GPU. La RSS riguarda tutto il
processo, mentre `context_capacity_bytes` è capacità CPU del contesto. Il contatore `last_shadow_cpu_ms`
è soltanto l'ultimo campione dell'atto, non una media.

## Risultato finale sul M1

**MISURA:** sei corse complete con uscita 0, nell'ordine prima/finale/finale/prima/prima/finale,
con avvii nativi separati e display mantenuto attivo soltanto durante le prove. Serie `c2`, variante finale C.
Ogni versione comprende 7.200 fotogrammi misurati, oltre ai riscaldamenti. Nessun compilatore, test o altra
nostra finestra di gioco attivi durante le misure. La soglia locale è p95 ≤16,7 ms per ciascun atto e replica.

| Atto | p95 prima, tre repliche (ms) | p95 finale, tre repliche (ms) |
|---|---|---|
| Fermo | 15,61 / 14,25 / 15,06 | 14,39 / 14,68 / 14,58 |
| Passo | 17,45 / 16,64 / 16,63 | 15,03 / 15,35 / 15,93 |
| Salita | 17,92 / 18,20 / 17,81 | 16,31 / 14,08 / 15,99 |
| Volo | 14,89 / 15,85 / 15,65 | 14,79 / 13,47 / 14,56 |

Tutte le 12 misure finali rispettano la soglia. In salita la mediana CPU dell'update passa da
3,71 / 3,73 / 3,73 ms a 2,37 / 2,10 / 2,37 ms;
quella del draw da 12,29 / 12,33 / 12,27 ms a 7,37 / 6,63 / 7,54 ms.
I picchi delle coppie esaminate per le ombre scendono da 701224 a
103314. Rimangono invariati i picchi di geometria e invio:
6572 vertici, 10920 triangoli del modello,
11791 triangoli d'ombra e 2646360 byte
attributi inviati per frame; nessun fallback dell'indice nelle sei corse.

Il contesto CPU passa da 3.409.520 a 6.447.240 byte: **+2,90 MiB** per i ricevitori preparati e l'indice.
Il modello resta a 5.712.064 byte; atlas della stampa 4.672.512 byte, una texture e un solo caricamento
nei 2.640 frame di ogni corsa. Uno shader e zero mesh GPU posseduti dal laboratorio; escluse le risorse
condivise dell'host. RSS del processo: 134.89–138.73 MiB
prima, 138.20–140.41 MiB finale.

**MISURA:** anche l'ultimo smoke C termina con uscita 0 e tutte le 61 catture native, 2560×1440,
coincidono pixel per pixel con la baseline `-o:speed`. Nessuna diminuzione di risoluzione, triangoli,
stampa o dettaglio. La [galleria finale locale](../../../build/moonshot/cardboard-performance/candidate-c/gallery/index.html)
conserva gli originali e permette di rivedere le sequenze.

**Limiti:** la soglia è sul p95, non sul massimo: rimangono fotogrammi oltre 16,7 ms. Non è una garanzia
che ogni frame del gioco intero rispetti 60 FPS. È il campione di laboratorio sul M1, non una spedizione
popolata o la prova Windows/RTX 3060. Restano il giudizio visivo dell'utente e le eccezioni di design già
aperte nel piano. La Fase 2 non è iniziata; nessun branch è stato ripulito.

Le varianti intermedie A e B, i tre benchmark preliminari e gli avvii GLFW falliti sono conservati
separatamente. B aveva ancora p95 fuori budget in due dei dodici casi; la classificazione per zone di C
completa l'intervento. La tabella usa tutte e sole le sei corse complete `c2` della versione finale,
non una selezione delle repliche migliori. Il primo tentativo della serie C si fermava all'avvio del
monitor, prima dei campioni: resta registrato con uscita 2.

Dati: [confronto completo](fase1-prestazioni-misure.json), [repliche prima](fase1-prestazioni-prima.json),
[repliche finali](fase1-prestazioni-finale.json), [parità dei pixel](fase1-prestazioni-pixel.json),
[manifest](fase1-prestazioni-manifest.json) e [archivio riproducibile](fase1-prestazioni-prove.zip).
L'archivio contiene il delta rispetto alla precedente prova, sorgenti intermedi, comandi, log,
exit code, impronte e catture selezionate; richiede gli assets originali del checkout.
Dimensione: 21,350,573 byte; SHA-256 `dadc4e2607dd921801f539b90d35caa5acce6a47718fdb0c4d44718097c4eaf1`.

Per rivedere la versione misurata: `build/moonshot/cardboard-performance/candidate-c/odin-page-cardboard-play --page-lab`.
`4` seleziona la salita, `6` la morte, `C` cambia camera, `P` alterna la stampa.

## Fonti e riproduzione

**FONTE:** il codice primario di [raylib 6.0, rcore.c](https://github.com/raysan5/raylib/blob/6.0/src/rcore.c)
definisce `GetFrameTime` come tempo dell'ultimo fotogramma. La collocazione della lettura dopo la presentazione
è verificata nel nostro host e in `src/run/page_lab_scene.odin:338`; non è una misura GPU attribuita alla libreria.

**FONTE:** la [documentazione primaria FFmpeg sui muxer hash](https://github.com/FFmpeg/FFmpeg/blob/master/doc/muxers.texi#L1702)
descrive il confronto dopo conversione in video grezzo. Per le catture si decodifica esplicitamente in RGBA8,
con dimensioni uguali, prima di confrontare i pixel; il checksum del file PNG da solo non prova tale uguaglianza.

Comandi di build, benchmark, galleria e probe sono nel [README degli strumenti](../../../tools/moonshot/README.md).
La copia precedente proviene dall'[archivio del cartoncino e della capacità](fase1-cartoncino-capacita-prove.zip),
identificato nel relativo manifest; nessuna sorgente precedente viene ricostruita a memoria.
