# Moonshot — Cartoncino stampato e capacità delle celle

4 novembre 2026, ramo `piano-moonshot`, base `ddc6b186942d4c78597dc0f3f06c1a73483b716e`.
Modifiche locali su richiesta esplicita; nessun commit o push. Estensione del laboratorio F1 e anticipo della sola
capacità degli snapshot dalla F4. Non abilita mappe più grandi nella campagna e non avvia la Fase 2.

## Salvataggi: che cosa cambia

**FATTO — `src/expedition/snapshot.odin:9,25,71,161`:** 224² resta per il formato v1 e per la bitmap
storica della presentazione; non limita più gli snapshot v2.
Terreno, altezze, ostacoli, liquidi e celle dei layer sono ora buffer posseduti proporzionati allo stato.
Il formato `layers_version = 2` usa un indice di cella a 32 bit nel valore packed a 64 bit; la lettura v1
interpreta ancora il precedente indice a 16 bit e gli array con padding. I vecchi snapshot v0 già rifiutati
restano esclusi. La versione dell’envelope JSON rimane 2; la discriminante della mappa è separata.

**FATTO — `src/campaign/save_queue.odin:85`, `src/expedition/snapshot_storage.odin:26,48`,
`src/campaign/persistence.odin:102,106,130`:** ogni job di salvataggio asincrono possiede una copia autonoma prima di avviare il worker.
Il caricamento verifica il limite del file prima di allocarne il contenuto, controlla il checksum sui byte
originali e decodifica entro un’arena limitata. Il ripristino costruisce una stanza temporanea e trasferisce
gli owner solo dopo il successo: un fallimento non distrugge la stanza corrente. La distruzione degli snapshot
libera i sei buffer; i call site del menu, della run e dei test rispettano questa proprietà.

Limiti espliciti: lato massimo 1792; snapshot/payload posseduto 256 MiB; file JSON 128 MiB; arena temporanea
di decodifica 512 MiB riservati virtualmente con commit progressivo. Questi budget non sono un tetto al RSS
del processo, che comprende anche stanza, tabelle, copie e allocatori. Scene con troppi contenuti possono
raggiungere un budget prima del lato massimo. Non è un formato per mondi illimitati.

## Prova reale di capacità

**MISURA:** Apple M1, Odin `dev-2026-10:84bc3fc21`, probe `-o:speed`, quattro processi seriali senza build
concorrenti. Livello e stanza reali controllati, piano superiore con quota valida, liquidi distinguibili
su entrambi i piani. Cattura → JSON su file nuovo → caricamento → ripristino; confronto completo di celle,
altezze e liquidi, più posizione del giocatore. I file di prova non sono gli slot del profilo.

| Lato | Celle | Snapshot MiB | JSON MiB | RSS massimo MiB | Cattura ms | Salva ms | Carica ms | Ripristina ms | Esito |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 224 | 50,176 | 0.56 | 1.23 | 12.38 | 0.76 | 52.77 | 116.17 | 1.30 | uguale, exit 0 |
| 448 | 200,704 | 1.42 | 3.38 | 26.02 | 1.21 | 72.00 | 318.49 | 5.22 | uguale, exit 0 |
| 896 | 802,816 | 4.87 | 12.00 | 87.92 | 5.17 | 262.22 | 1094.80 | 19.02 | uguale, exit 0 |
| 1792 | 3,211,264 | 18.65 | 46.45 | 300.97 | 20.47 | 1009.55 | 4427.00 | 77.92 | uguale, exit 0 |

Tabella: serie finale `r3`, una misura per dimensione; anche `r2` ha completato tutti i roundtrip.
È una prova di capacità e ordine di costo, non distribuzione statistica né benchmark
di una spedizione popolata. Il probe non misura generazione, rendering, IA o attraversamento. A 1792 il liquido
del piano superiore usa l’indice 12.839.676; l’indice locale della cella è 3.205.884, oltre 65535.

**Tentativo fallito conservato:** la serie `r1` aveva un errore nel fixture: piano superiore a quota zero
sopra il pavimento rialzato. Tutti i restore sono stati correttamente rifiutati. La serie `r2` assegna
`LAYER_SPACING+2` al piano superiore; non aggira la verifica delle colonne. Log di entrambe le serie
e risultati strutturati sono conservati nelle prove. Il caricamento a 1792 richiede circa 4,4 s in questo
caso: lo sblocco del formato non certifica caricamenti istantanei.

## Cartoncino e disegni esistenti

**FATTO — `src/render/page_lab_print.odin:13,61,106,203`:** il laboratorio usa `expedition_robot_art` e il Brute di `expedition_cyber_actor_art`.
L’atlante procedurale immutabile contiene tre attori/assetti, tre clip e dodici frame: 1248×936 RGBA8,
4.672.512 byte di pixel. Generazione CPU una volta per processo; una texture GPU per il laboratorio,
caricata una volta e distrutta all’uscita. La cache CPU resta intenzionalmente disponibile per le riaperture.
Non vengono generati o caricati asset ogni fotogramma.

La stampa segue le coordinate materiali della superficie piegata, con proporzioni uniformi e margine
di cartoncino. La sagoma conserva teste e braccia nell’unione dei frame previsti; le ultime cinque righe presso le suole
restano vincolate alle finestre dei piedi. Occhi e camminata animano il disegno interno.
I due piedi conservano radici separate nella pagina. Il retro non mostra uno sprite specchiato. Il comando
`P`/«Stampa» permette di confrontare disegno e supporto nudo; il supporto fermo non viene ricostruito
per il solo battito degli occhi. Montata resta un campione con supporto unico di cavaliere e cavalcatura.

**Correzione richiesta durante la prova:** il primo collegamento riusava il clip di morte del vecchio sprite,
che comprimeva il corpo verso il basso dentro una sagoma ancora alta. Ora l’anatomia resta eretta sulla carta;
restano la lieve oscillazione originale dell’idle e le proporzioni, mentre la morte cambia l’espressione
degli occhi usando il disegno ferito già presente. Il cedimento appartiene alla mesh
che richiude la figura nella pagina. Un test confronta tutti i pixel fuori dalla banda degli occhi.

Le catture native aggiornate sono 2560×1440 e comprendono 25 viste e tre sequenze da 12 immagini: pagina, piede, passo,
curva, salita, montata, morte, casi limite, ombre, stampa idle A/B, supporto senza stampa e retro.
Le sequenze sono campionate a 3 immagini per secondo simulato: servono a leggere il movimento, non a certificare frame adiacenti.

**FATTO — `src/render/page_lab_geometry.odin:21,333,367`:** il nemico del campione è stato distanziato dal
Viandante per evitare che i ritagli si tocchino alla fine della salita. Il generatore rifiuta ora anche
saldature involontarie fra figure. Le piccole isole di pagina completamente circondate da una sola sagoma
vengono incluse nel suo cartoncino; le aperture connesse al foglio esterno restano libere. Il controllo
comprende le 25 pose native e 2160 fotogrammi delle nove animazioni, oltre a separazione, radici e stampa.

## IA e limiti residui

**IA aggiornata:** due prove in `src/advisor/large_map_test.odin` coprono copia/simulazione a 320×320,
indipendenza dei buffer e un puzzle oltre l’indice 65535: la IA sceglie l’attacco adiacente che elimina
l’ultimo nemico. `src/run/advisor_large_map_test.odin` verifica cure, nemici dormienti, distanze del contesto
e l’esclusione del cibo pescato. Le regole, le mosse e i criteri di valutazione sono quelli esistenti;
nessuna nuova meccanica visiva è stata introdotta nella simulazione. I controlli della carta IA restano attivi.

**FATTO:** la campagna genera ancora mappe da 160/192/224 celle. La bitmap dei liquidi della presentazione
(`src/render/presentation_timeline.odin`) conserva il proprio limite storico: va adattata nella restante F4
prima di certificare mappe grandi nel gioco. Anche le copie IA e le tabelle delle distanze sono ancora
proporzionali all’intera mappa, non alle sole regioni residenti. I puzzle a 320 non misurano una IA a 1792.

**CALCOLO, non RSS misurato:** a 1792² e quattro layer, una tabella di liquidi i32 più una di distanze `int` da 8 byte sui target 64 bit
richiede circa 147 MiB. Più copie del worker moltiplicano quel costo. Il successivo lavoro sulle regioni
deve ridurre memoria e scansioni globali; ampliare soltanto il numero di celle non lo risolve.

Prossimi passi: verificare dal vivo stile e morte corretta; ottimizzare il campione rispetto alle misure;
su comando, confrontare le tre varianti di combattimento F2. Completare poi regioni/persistenza locale F4,
architetture F5 e traversata Cyber 2× F6, con IA e prove dei confini in ogni fase.


## Riferimenti del codice

| Contratto | Evidenza |
|---|---|
| Dimensione e formato v1/v2 | `src/expedition/snapshot.odin:9,25,71,161` |
| Budget e copia indipendente del worker | `src/campaign/save_queue.odin:85`, `src/campaign/save_ownership.odin:12` |
| Lettura limitata e checksum | `src/campaign/persistence.odin:102,106,130` |
| Restore senza mutare lo stato sul fallimento | `src/expedition/snapshot_storage.odin:26` |
| Prova JSON con quote e confronto integrale | `tools/moonshot/snapshot_capacity/main.odin:51,107` |
| IA, copia e puzzle ad alto indice | `src/advisor/large_map_test.odin:80,149`, `src/run/advisor_large_map_test.odin:44` |
| Stampa e risorse | `src/render/page_lab_print.odin:61,106,203`, `src/render/page_lab_draw.odin:99,125` |
| Morte senza doppio collasso | `src/render/page_lab_print_test.odin:40`, `src/render/page_lab_geometry_test.odin:80` |
| Stampa su supporto fermo | `src/run/page_lab_scene.odin:196,202,278` |

Il lavoro riusa le API già presenti nel repository. Riferimento primario consultato per la serializzazione:
[documentazione JSON di Odin](https://pkg.odin-lang.org/core/encoding/json/). Le proprietà di capacità,
memoria e prestazioni qui riportate provengono dal codice locale e dalle prove, non da promesse della libreria.


## Verifiche eseguite

| Verifica | Esito |
|---|---|
| `odin check src -vet -strict-style` | superato |
| Campaign | 31/31, compresi copia del worker, fallimenti e budget |
| Expedition | 78/78; leak nel vecchio fixture heights corretto e regression 1/1 senza leak |
| Advisor | 2/2 nuovi test ad alto indice, compreso puzzle reale |
| Run | 27/27, compresa IA di contesto e clock stampa |
| Application | 23/23 |
| Renderer | 538/538, compreso ciclo delle nove animazioni |
| Strumenti Python | 21/21 |
| Integrazione, quick `-o:speed`, assert attivi | 220/220; 242,41 s di test, esclusa compilazione |

I tentativi iniziali hanno rilevato problemi poi corretti: copia con allocatore nullo, fixture JSON costruita
con graffe interpretate da `fmt`, buffer heights perso nel vecchio test, risultato del colpo finale atteso
come attacco anziché fine del combattimento, copertura della stampa in montata e topologia dei ritagli.
Log dei fallimenti conservati insieme alle verifiche successive. Nessun controllo IA disabilitato.
La prima suite di integrazione quick `-o:none` è stata interrotta dopo circa 17,6 minuti, senza esito completo;
non viene contata come superata. La ripetizione con lo stesso profilo quick e assert attivi in `-o:speed` ha superato tutti i 220 test.
Lo smoke finale `r4` è completo, exit 0, 25 viste e 36 fotogrammi di sequenza tutti `valid=true`;
una texture e un upload della stampa in tutte le viste. Il tentativo `r3` era fallito inizializzando la
finestra macOS; il riavvio diretto è riuscito senza altre modifiche del codice. Le catture sono una verifica
funzionale svolta durante le suite: i loro tempi non vengono usati per le prestazioni.


## Misure grafiche finali

**MISURA:** Apple M1, OpenGL 4.1 Metal, Odin `dev-2026-10:84bc3fc21`; driver `-o:speed`, canvas logico
e raster 1920×1080, vsync e limite FPS disattivati. Tre processi seriali dopo la fine di tutte le compilazioni
e suite. Quattro atti, ognuno con 60 frame esclusi e 600 misurati: 7200 campioni misurati, 7920 totali.
Nessuna cattura durante le misure. Tutti i processi hanno exit 0 e protocollo completo.

| Atto | Media r1 / r2 / r3, ms | p95 r1 / r2 / r3, ms |
|---|---|---|
| Fermo | 13,84 / 9,54 / 9,59 | 18,94 / 16,40 / 16,34 |
| Passo | 14,08 / 12,39 / 11,70 | 17,73 / 16,41 / 12,49 |
| Salita | 17,52 / 16,84 / 16,25 | 21,22 / 19,23 / 17,29 |
| Volo | 9,90 / 9,89 / 10,24 | 10,32 / 10,45 / 12,26 |

Il p95 della salita resta sopra 16,7 ms in tutte le repliche: **60 FPS stabili non certificati**. Nessuna
replica viene scartata. RSS massimo del processo: 134,94 / 145,31 / 141,34 MiB. Una texture della stampa,
un solo upload e payload di 4.672.512 byte restano costanti ai quattro checkpoint fino a 2640 frame
per processo. Il contatore non è un checksum dei pixel; le catture e i test verificano separatamente la resa.

I tempi CPU update/draw sono annidati, non sommabili e non sono query GPU. Il fermo riusa la geometria;
le animazioni ricostruiscono il dominio del foglio. In salita il draw medio è circa 12 ms e l'update
circa 3,7–3,9 ms: questi dati indicano dove profilare prima di estendere il campione. Non dimostrano
prestazioni del mondo grande o della campagna con nemici. La prova su Windows resta da fare.

[Dati completi e protocollo](fase1-cartoncino-misure.md), [JSON dei frame riassunti](fase1-cartoncino-misure.json),
[dati di capacità](fase1-capacita-misure.json). La [galleria locale](../../../build/moonshot/capacity-cardboard/gallery/index.html)
conserva tutti i 61 PNG originali, senza ritocchi.

Per rivedere dal vivo: `build/odin-page-cardboard-play --page-lab` (build `-o:speed`); `6` seleziona la morte,
`C` passa al dettaglio, `P` confronta la stampa con il supporto, Spazio ferma entrambi i clock.
L’[archivio delle prove](fase1-cartoncino-capacita-prove.zip) conserva sorgenti, manifest/hash, log completi
anche dei tentativi falliti, misure e alcune immagini native rappresentative; i JSON di mappa voluminosi
restano in `build/` e sono identificati con hash nel manifest.
