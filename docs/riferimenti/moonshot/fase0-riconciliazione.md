# Fase 0 — Riconciliazione delle evidenze e criteri di prova

Ricognizione del 4 novembre 2026 sul ramo `piano-moonshot`, base
`ddc6b186942d4c78597dc0f3f06c1a73483b716e`. Questo rapporto riguarda ricerca locale,
lettura del codice e definizione delle verifiche. **Nessun benchmark è stato eseguito
per scrivere questo rapporto.** I risultati precedenti sono chiamati «misure
documentate»; quelli prodotti dagli altri lavori della Fase 0 vanno aggiunti nel
resoconto della fase, senza attribuirli a questa ricognizione.

L'[esito successivo della Fase 0](fase0-risultati.md) contiene le nuove misure e il rilievo hardware
riuscito dopo questa ricognizione; le osservazioni sull'accesso negato qui sotto descrivono il primo tentativo.

Le citazioni dei sorgenti descrivono la base indicata, prima delle modifiche di
strumentazione della Fase 0. Il rapporto distingue **FATTO**, **MISURA DOCUMENTATA**
e **PROPOSTA**. Non sostituisce la verifica Windows/RTX 3060 Laptop.

## 1. I diciassette rapporti originali

**FATTO di ricognizione.** Sono stati enumerati i nomi dei file in
`output/moonshot`, `/private/tmp` e `/Users/dokkan/Downloads`, cercando le raccolte
`understand`/`ricerca` e rapporti pertinenti. I percorsi `/tmp/understand` e
`/tmp/ricerca` non sono risultati disponibili. In `output/moonshot` è presente
soltanto `CONTESTO.md`; i Markdown pertinenti trovati in `/private/tmp` sono i
quattro rapporti complementari della sessione Mac. I nomi in Downloads non
identificano rapporti moonshot; i file estranei non sono stati letti. Sono emersi
anche artefatti di cattura e prove del redesign in uno scratchpad locale di
Claude, senza le due raccolte originali. Non è stata effettuata una ricerca
indiscriminata nei documenti personali.

**Esito: 0/17 originali acquisiti nei percorsi verificati.** Questo non dimostra
che non esistano sul PC Windows o in una cartella non consultata. Autore preciso,
hash, stato finale e contenuto di ciascun originale restano non verificati. Lo
stato «pronti alle 04:18» resta quello riportato dall'utente; non viene convertito
in una lettura effettuata.

I rapporti Mac hanno provenienza dichiarata e non vengono rinominati come se
fossero gli originali: `docs/riferimenti/moonshot/LEGGIMI.md:3`.

| ID | Rapporto originale atteso | Originale | Copertura complementare disponibile | Buco residuo |
|---|---|---|---|---|
| U1 | Combattimento | Non acquisito | `combat-world.md`, §1–2 | Confronto con conclusioni e prove dell'originale |
| U2 | Mondo | Non acquisito | `combat-world.md`, §3–4; `scale-backend.md` | Inventario originale e divergenze |
| U3 | Strutture | Non acquisito | `combat-world.md`, §5 | Copertura completa dei generatori e del catalogo originale |
| U4 | Rendering | Non acquisito | `paper-render.md`, §1; `scala-grafica.md` | Profilo aggiornato del percorso completo |
| U5 | Arte e carta | Non acquisito | `paper-render.md`, §2–4 | Verifica visiva e conclusioni originali |
| U6 | Contenuti | Non acquisito | Citazioni selettive nei rapporti e matrice del piano | Inventario completo di carte, oggetti e viste |
| U7 | Processo di lavoro | Non acquisito | `docs/sviluppo.md`; script e CI verificati sotto | Confronto con rapporto originale |
| U8 | Storia delle decisioni | Non acquisito | Piani e verbali locali citati in `piano-moonshot.md`, §2 | Cronologia originale e decisioni non presenti nei documenti |
| U9 | Scala reale 2×/4×/8× | Non acquisito | `scale-backend.md`; `scala-grafica.md`; log in `scala/` | Ripetizioni complete, IA, percorso e Windows |
| R1 | Ingegneria della carta/pop-up | Non acquisito | Fonti e limiti di lettura in `paper-render.md:64` | Lettura completa dei paper ove ancora mancante |
| R2 | Giochi di carta/libri | Non acquisito | Fonti ufficiali in `paper-render.md:66` | Confronto con rapporto originale |
| R3 | Carta in tempo reale | Non acquisito | `paper-render.md:13`, `:71`, `:85`; codice shader | Validazione di una resa continua animata e suo costo |
| R4 | Architettura procedurale | Non acquisito | Proposta del piano §6; limiti in `scale-backend.md:64` | Mancante una lettura integrale del paper specifico citato come candidato |
| R5 | Combattimento dinamico | Non acquisito | Confronto A/B/C e fonte primaria nel piano §4 | Prototipi comparabili e giudizio del giocatore |
| R6 | Vastità/esplorazione | Non acquisito | Piano §5; fonte su curiosità dichiarata come abstract | Validazione del percorso e conclusioni originali |
| R7 | Mondi grandi/back-end | Non acquisito | Fonti aperte in `scale-backend.md:50`; prove scala | Confronto equivalente di back-end e piattaforme |
| R8 | Suono/narrazione | Non acquisito | `paper-render.md:68`, `:73`; piano §8 | Campione sonoro sintetico e prova integrata |

**PROPOSTA di riconciliazione quando arrivano.** Registrare per ciascun originale
nome, autore dichiarato, data, commit, hash del file e fonti; leggere tutto il
testo; estrarre affermazione, prova e conclusione. Risolvere prima le divergenze
che cambiano direzione o costi. Non confrontare soltanto i riassunti. Il codice
prevale sulle descrizioni storiche; misure con scene/configurazioni diverse
restano serie distinte. Una fonte citata nell'originale non diventa automaticamente
una fonte letta in questa sessione.

## 2. Contraddizioni già risolte e limiti rimasti

- **FATTO:** esplorazione già continua, 5,4 celle/s a piedi e 8,4 in sella
  (`src/expedition/roam.odin:7`); il passo tattico normalmente costa 0,4 s e il
  colpo 0,5 s, dal divisore 2 (`src/game/tactical_action_cost.odin:6`, `:16`, `:30`).
  Il battito di un secondo non limita il giocatore a una sola azione al secondo.
- **FATTO:** quattro piani, scale, ascensori e cancelli sono già dati reali
  (`src/engine/grid/grid.odin:17`; `src/level/layers.odin:27`). Non sono nuove
  funzionalità da promettere come risultato del moonshot.
- **FATTO:** il salvataggio rifiuta mappe oltre 224² e impacchetta gli indici dei
  piani supplementari in 16 bit (`src/expedition/snapshot.odin:7`, `:68`, `:86`).
  Una finestra grafica che si apre a 8× non prova un mondo persistente funzionante.
- **FATTO:** i ritocchi richiedono la stessa dimensione
  (`src/level/map_edits.odin:87`); gli HP dipendono anche dalla coordinata x
  (`src/expedition/world.odin:274`). Lo stress test che modifica soltanto il lato
  non mantiene automaticamente contenuto e bilanciamento equivalenti.
- **MISURA DOCUMENTATA:** le vecchie medie M1 di 18,249/14,646/26,018 ms descrivono
  una fase precedente; il confronto finale release ha altre scene e valori
  (`docs/riferimenti/cartoncino-cartoon/VERIFICA_REDESIGN_SOLE.txt:254`). La serie
  preliminare di scala è un ingresso Cyber statico, 120 campioni e una corsa per
  scala (`docs/riferimenti/moonshot/scala-grafica.md:7`). Non è una conferma dei
  60 FPS del prodotto.
- **FATTO:** chunk grafici e culling esistono, ma la residenza non è una cache con
  espulsione dei chunk lontani in quel percorso
  (`src/render/expedition_geometry.odin:129`, `:138`, `:238`). Serve una traversata
  con ritorno: la vista iniziale da sola non verifica la stabilità della memoria.

## 3. Strumentazione grafica: che cosa misura già

**FATTO.** `src/application/campaign_smoke.odin:80` espone la modalità benchmark,
intervallo di stadi, canvas fisico e warmup/campioni. I default sono 20 frame di
warmup e 120 campioni statici; il percorso usa 240 campioni (`:91–98`). Per il
protocollo del piano bisogna passare esplicitamente 60 e 600: i default non lo
implementano già.

`expedition_benchmark_present` legge `rl.GetFrameTime`, tempo del wrapper di
disegno e somme delle fasi CPU (`:213–230`); calcola media, mediana, p95 e massimo
(`:233–244`). I tempi di submission sono dichiarati CPU, non query GPU (`:208`).
I campi di scena e mondo sono annidati, quindi non sono addendi indipendenti
(`:248–252`). I contatori riportano rebuild/upload e payload mesh (`:254–266`),
che esclude overhead del driver e copia CPU di raylib. Nella base non sono
registrati p99, conteggio oltre budget e serie CSV per frame.

**FATTO decisivo sul percorso.** Gli stadi 25/26 usano i tasti tenuti e l'update
reale con `frame.dt` (`src/application/campaign_smoke.odin:432`). Il tempo arriva
dal frame reale dell'host (`src/engine/host/host.odin:155`). A parità di 240 frame,
macchine con FPS diversi possono percorrere distanze diverse. Gli stadi statici
aggiornano atmosfera/timeline (`src/application/campaign_smoke.odin:445`), mentre
gli stadi successivi alla prima scena cartoon chiamano la simulazione completa
(`:421`). Non chiamare «combattimento simulato completo» una scena che disegna
sei nemici fermi.

**PROPOSTA per modifiche circoscritte della Fase 0:**

1. Conservare tempo reale del frame per il costo, ma aggiungere un modo di replay
   con dt di simulazione fissato, input e numero di passi dichiarati. Applicare
   lo stesso orologio agli aggiornamenti e alla presentazione dipendente dal
   tempo, oppure dichiarare la differenza. Registrare posizione, piano, fase e
   checksum dello stato a punti noti. Un input ripetuto non basta a dimostrare
   che il percorso è lo stesso.
2. Registrare campioni ordinati temporalmente; ordinarne una copia per i
   percentili. Definire il percentile usato e la soglia esatta: per 60 Hz il
   valore è `1000/60` ms, non una costante arrotondata in modo diverso fra tool.
3. Scrivere il CSV dopo l'ultimo campione del blocco. Associare indice locale,
   stadio, seed, canvas, dt simulazione e tempi reali; non aggiungere I/O o
   allocazioni per campione. Un errore di scrittura deve essere riportato e
   non produrre una corsa apparentemente completa.
4. Conservare warmup, primo ingresso e setup come intervalli separati. Un frame
   che contiene resize o cambio scena non diventa un campione steady state.
5. Registrare configurazione, hash patch/binario e condizioni della macchina
   accanto ai risultati. Compilazioni, test e altre corse prestazionali vanno
   concluse prima di misurare. Catture visive in una corsa distinta.

## 4. IA e salvataggi: harness e verifiche pertinenti

**FATTO.** Esistono già strumenti riusabili:

| Strumento | Evidenza | Che cosa dimostra / limite |
|---|---|---|
| Copia e simulazione IA | `src/integration/advisor_copy_test.odin:323` | Medie di 20 snapshot/rehearsal, 500 ripristini, simulazione; non distribuzione dei picchi |
| Spedizione Space | `src/integration/advisor_special_test.odin:235` | Seed 42, quattro inseguitori, root/primo consiglio/ricerca; limite di lavoro 4000, non prova grafica |
| Ricerca e fallback | `src/integration/advisor_search_test.odin:563` | Nodi/s, avanzamento a 1/10/100 ms, costo massimo della fetta del pilota |
| Worker equivalente | `src/integration/advisor_worker_test.odin:46` | Confronto con ricerca a fette e limite uguale di lavoro |
| Worker interrotto | `src/integration/advisor_worker_test.odin:83` | Cambio radice senza contaminazione della ricerca nuova |
| Pilota non bloccante | `src/integration/advisor_worker_test.odin:119` | Worker trattenuto, costo del pilota e consiglio anticipato; contiene già un'asserzione <2 ms nell'arena specifica |
| Checkpoint | `src/run/checkpoint_benchmark_test.odin:12` | Capture/save/enqueue separati, dieci campioni con define `CAMPAIGN_SAVE_BENCHMARK`; file temporaneo |

**PROPOSTA.** L'harness di scala IA deve separare copia profonda, costruzione della
rehearsal, primo consiglio, ricerca a budget di nodi e memoria. Riportare numero
di nemici/carte, seed, horizon/round ottenuto e consiglio valido. Un timeout è
un esito incompleto, non uno zero millisecondi né un consiglio «riuscito».
Il confronto dei tempi richiede lo stesso lavoro; una ricerca che termina meno
round non ha necessariamente migliorato le prestazioni.

Non mettere log o tracker ad alta frequenza dentro il percorso misurato del
worker senza una corsa di controllo. `context.allocator` non copre automaticamente
le arene virtuali della IA (`src/advisor/copy.odin:143`, `:172`): includerle nella
contabilità o dichiararle escluse. I blocchi iniziali 8/8/4 MiB (`:25`) non sono
un tetto alla memoria del motore.

**Verifiche proporzionate alle modifiche, da eseguire dal coordinatore:**

- Solo aggiunte allo smoke: `odin check src -vet -strict-style`, test del package
  `src/application`, build del percorso smoke e controllo reale dell'output.
  La gallery headless già presente verifica fixture e legalità dei probe, non
  la statistica del benchmark (`src/application/campaign_objects_smoke_test.odin:11`).
- Se vengono introdotti calcolo dei percentili o serializzazione CSV riusabili,
  verificare casi che possono produrre risultati falsi: campioni piccoli e
  ripetuti, copia ordinata senza perdere l'ordine temporale, buffer capiente e
  numero di righe corrispondente ai campioni. Non serve una suite che ripeta
  semplicemente il codice del writer.
- Harness IA esterno: check/build dell'harness, input validi, cleanup e
  fingerprint del mondo invariato dopo la ricerca. Se cambiano anche sorgenti
  IA: test copia campi (`src/integration/advisor_copy_test.odin:145`), equivalenza
  reale/copia (`:267`), worker e cancellazione; controlli sullo stesso budget.
- Snapshot di spedizioni grandi: il rifiuto attuale è risultato atteso. Non
  alzare limiti o saltare assert per trasformare la misura in successo. Gli
  eventuali harness devono gestire il fallimento senza serializzare dati
  invalidi, e usare soltanto fixture/copie del salvataggio.

**FATTO.** `scripts/check.sh:23` esegue check e tutti i package; la modalità
completa ripete con assert disabilitati (`:25`) e costruisce i binari (`:32`).
`--headless` omette il link della demo, non riduce la suite (`:9`, `:32`).
`--quick` riduce matrici costose e non equivale a una selezione del solo codice
toccato. Per controlli mirati usare gli esempi in `docs/verifica.md:138`, sempre
con `-out` temporaneo. La CI contiene job Mac e Windows
(`.github/workflows/check.yml:24`, `:51`): leggerne la definizione **non prova**
che siano stati eseguiti né che la grafica funzioni sulla RTX.

## 5. Budget fondati: che cosa si può già fissare

**MISURA DOCUMENTATA.** Il picco heap della prova headless precedente è
4.582.112 byte nel caso Space 1× e 172.119.776 byte a 8×; include lo snapshot di
spedizione e non include renderer, ricerca IA, scratch temporaneo, stack o RSS
(`docs/riferimenti/moonshot/scale-backend.md:17`, `:23`, `:32`). Le generazioni
8× release hanno mediane 368,202/113,700/203,602 ms per Cyber/Snow/Space (`:34`).
Questi dati non fissano da soli un budget di memoria totale o primo ingresso.
Il comando informativo `sysctl -n hw.memsize` in questa ricognizione è stato
negato dalla sandbox: non si presume una quantità di RAM del Mac dal solo nome M1.

**PROPOSTA di budget verificabile, senza numeri arbitrari spacciati per requisiti:**

| Voce | Regola proposta | Fondamento e dato necessario |
|---|---|---|
| Frame completo | p95 ≤ `1000/60` ms; pubblicare p99, massimo e conteggio oltre soglia | Obiettivo 60 Hz del piano; non affermato come già raggiunto |
| Lavoro sincrono di streaming | Deve stare nel margine del frame reale; nessun nuovo blocco nascosto dal warmup | Margine = budget frame meno costo già misurato della scena; se è negativo, va prima recuperato |
| Heap headless della strumentazione | Stesso caso/seed e stesso stato: nessuna crescita oltre baseline più buffer strumentali dichiarati | Baseline precedente disponibile; buffer espliciti permettono di attribuire la differenza |
| Fine vita delle risorse tracciate | Zero residui e zero bad free dopo distruzione | Il precedente harness già li registra (`scala/probe.odin.txt:31`); copertura limitata all'allocatore tracciato |
| Memoria a lungo termine | Stesso percorso chiuso ripetuto: working set stabilizzato dopo riempimento delle cache; niente crescita con numero di giri | Serve campionamento RSS più heap e risorse grafiche; distinguere cache trattenuta da leak |
| Futuro budget delle regioni | `memoria fissa + N residenti × costo massimo regione + N in caricamento × costo massimo staging + copie IA` | Fissare N dalla distanza di influenza/anticipo e misurare i costi massimi con casi densi; non dal lato totale del capitolo |
| Primo ingresso | Nessuna regressione rispetto alla baseline 1× equivalente per il futuro streaming; soglia numerica da compilare dal massimo delle ripetizioni baseline | Misurare processo→primo frame giocabile e cambio bioma separatamente, con cache fredda/calda definita |
| Anticipo caricamento | `tempo caricamento + upload + margine osservato < distanza di anticipo / velocità massima reale` | Velocità nominale in sella 8,4 celle/s (`src/expedition/roam.odin:15`); includere trasporti e movimento speciale |

Queste sono regole di accettazione e contabilità, non una promessa che l'attuale
implementazione le rispetti. Per fissare un tetto totale in MiB e un tempo
massimo d'ingresso in secondi mancano ancora RSS, memoria grafica completa e
primo ingresso della baseline F0. Il resoconto deve compilare quelle soglie con
le nuove misure o mantenerle esplicitamente aperte. Scegliere qui «1 GiB» o
«un secondo» senza tali dati sarebbe una scelta di prodotto non motivata dalle
prove disponibili.

## 6. Che cosa è chiudibile su Mac

**Realizzabile localmente:** baseline grafica none/speed su scene nominate;
percorso ripetibile; headless a quattro scale; snapshot, primo consiglio e costo
IA; primo ingresso; memoria del processo e dei sottosistemi quando gli strumenti
sono accessibili; verifica dei file di prova e dei rifiuti previsti. Distinguere
la serie originale dalla nuova serie: una nuova strumentazione cambia il
protocollo e non deve sovrascrivere i vecchi log.

**Resta esterno:** acquisizione e confronto dei 17 originali; esecuzione sul
Windows reale di LucaGranito con RTX 3060 Laptop. È possibile preparare i
comandi e le fixture Windows, ma una compilazione Mac, una matrice CI o una
stima del rapporto fra GPU non certificano quei risultati.

**Stato di questa ricognizione:** inventario locale e verifica degli strumenti
completati; benchmark non eseguiti da questo agente; originali non acquisiti;
budget numerici complessivi subordinati alle misure F0. La chiusura della fase
deve riportare separatamente lavoro Mac completato, misure impossibili con
causa, attività Windows pendenti e riconciliazione documentale ancora aperta.
Non chiamare «Fase 0 verificata su entrambe le macchine» il solo completamento
del sottolavoro locale.

## 7. Diagnosi statica del costo CPU `view`

Ricognizione del 4 novembre 2026, senza benchmark e senza modifiche al codice.
I file citati in questa sezione risultano invariati rispetto a HEAD al momento
della lettura (`git diff --stat --` sui relativi percorsi non restituisce
modifiche). Le righe sono quelle dei sorgenti attuali, non quelle delle copie
sacrificabili o di un futuro intervento. La diagnosi serve a interpretare le
nuove misure F0; non attribuisce causalmente i tempi del precedente benchmark.

**FATTO — confine della misura.** `src/run/expedition_scene.odin:611` chiama
`render.update_tactical_view` con `refresh_only=true`; la misura `view_ms`
termina subito dopo (`src/run/expedition_scene.odin:612`). La preparazione e il
disegno del mondo iniziano alla riga 613. Il parametro `refresh_only` interrompe
la funzione soltanto dopo snapshot, visibilità e camera
(`src/render/tactical_renderer.odin:412`): non evita la cattura dello stato.

**FATTO — scansione completa ricorrente.** Il percorso è:

1. `src/render/tactical_renderer.odin:313`: assegnazione dello snapshot mediante
   `renderer_presentation_snapshot`.
2. `src/render/world_playback.odin:281`: chiamata incondizionata a
   `capture_room_presentation`.
3. `src/render/presentation_timeline.odin:402`: chiamata a
   `capture_presentation_ground`.
4. `src/render/presentation_timeline.odin:425`: visita di ogni elemento di
   `room.ground.pool`, anche quando tutti i valori sono zero; il controllo del
   valore avviene dentro il ciclo, alla riga 426.

La tabella è allocata da `src/game/room.odin:528` con
`room_table_cells(level_data)`. `src/game/layers.odin:140`–143 restituisce N
elementi senza piani aggiuntivi e `N*LAYER_COUNT` appena esiste un piano
aggiuntivo, dove N è il numero di celle della pagina. I piani possibili sono
quattro (`src/level/layers.odin:19`, `src/engine/grid/grid.odin:17`–19).
La capacità fissa della rappresentazione visiva non limita la scansione: il
controllo `MAX_PRESENTATION_GROUND_CELLS` è anch'esso dentro il ciclo
(`src/render/presentation_timeline.odin:427`).

**INFERENZA — costo.** Questa visita richiede Θ(N) senza altri piani e Θ(LN)
con piani, con L attualmente pari a quattro. A pari presenza di piani,
moltiplicare il lato per otto moltiplica per 64 gli elementi visitati. È un
candidato concreto per la crescita del tempo `view`, ma il rapporto fra i
tempi totali non deve necessariamente essere 64: la funzione contiene anche
lavoro fisso e altri percorsi. Per attribuire una quota precisa servono misure
distinte della cattura, della cache delle altezze e della visibilità.

**FATTO — copie complete, ma condizionate dalla cache.**
`src/render/tactical_renderer.odin:307` chiama `set_board_level`. In
`src/render/height_view.odin:91`, identità, revisione, dimensione delle altezze,
presenza di piani e base uguali causano il ritorno immediato. Se la cache deve
essere ricostruita, le righe 97–108 copiano tutte le altezze e le caselle del
suolo e dei piani presenti; le righe 112–119 percorrono le altezze per il
massimo e le caselle dei piani per marcare le colonne sovrapposte. Le tabelle
dei piani sono dense quanto la pagina quando allocate
(`src/level/layers.odin:99`, `src/level/layers.odin:114`).

**INFERENZA — costo della cache.** Una ricostruzione costa Θ(N più celle dei
piani allocati) in copie e scansioni; una cache valida non introduce questa
visita completa a ogni frame. Non attribuire a queste copie la crescita della
media stabile senza verificare che la revisione cambi o che la cache venga
invalidata durante i campioni. `level.has_heights` legge solo la lunghezza
(`src/level/level.odin:161`); `level.has_layers` esamina soltanto i descrittori
dei piani (`src/level/layers.odin:66`), non le caselle.

**FATTO — lavoro che non percorre l'intera pagina.**

- La ricostruzione di `board_actors` visita ascensori, nemici e oggetti
  (`src/render/height_view.odin:128`–142), senza iterare le celle. Anche lo
  snapshot copia nemici, trappole, oggetti e bottino entro i rispettivi limiti
  (`src/render/presentation_timeline.odin:362`–415).
- `level.layer_map` e `board_layer_map` costruiscono descrittori di slice:
  assegnano riferimenti alle tabelle, senza copiarne gli elementi
  (`src/level/layer_sight.odin:13`–20,
  `src/render/height_view.odin:166`–175). `set_board_view` legge la colonna del
  giocatore per stabilire se è sotto una volta
  (`src/render/height_view.odin:294`–301,
  `src/game/layer_view.odin:64`–67).
- La visibilità itera l'impronta locale `size` attorno al giocatore e i piani
  (`src/render/tactical_renderer.odin:335`–355), non larghezza e altezza del
  mondo. Con `vision_size=0`, `tactical_vision_size` restituisce zero
  (`src/game/tactical_cards.odin:26`–29): non espande l'impronta all'intera
  mappa. Le verifiche dei raggi e degli oggetti hanno costi propri, ma non
  equivalgono alla scansione completa di N caselle identificata sopra.
- `Room_Presentation` è un valore con array a capacità fissa
  (`src/render/presentation_timeline.odin:249`–281). Il bitset del terreno usa
  `MAX_PRESENTATION_GROUND_CELLS` (`src/render/presentation_timeline.odin:18`),
  derivato anche da `world.MAX_CELLS=224*224`
  (`src/expedition/snapshot.odin:7`). Nelle copie che cambiano soltanto
  `map_size`, la capacità non cresce con il lato: gli azzeramenti, le copie
  del valore e i confronti fra snapshot non sono copie della mappa 8×. La
  scansione della tabella reale delle pozze, invece, cresce comunque.

**FATTO — frequenza da distinguere.** Nel normale aggiornamento della
spedizione c'è un'altra chiamata a `update_tactical_view`
(`src/run/expedition_scene.odin:384`, nel ramo non in pausa personaggio). Il
timer `view_ms` del disegno copre soltanto quella alla riga 611. Nelle scene
che eseguono entrambe, il costo complessivo del frame può quindi comprendere
due catture, ma non entrambe dentro `view_ms`; alcuni stage statici dello
smoke non percorrono l'aggiornamento completo.

**INFERENZA — scelta del prossimo lavoro.** La scansione completa è lavoro
CPU nella preparazione dei dati. Cambiare API grafica, da solo, non elimina
questo ciclo. Se la nuova baseline conferma crescita di `view` a cache stabile,
il prossimo esperimento motivato è separare quei costi e verificare il peso
della rappresentazione del terreno; la scelta del backend richiede evidenze
distinte sui costi di invio e di esecuzione grafica. Questa sezione non propone
né applica un'ottimizzazione e non presume che la scansione sia l'unico limite.
