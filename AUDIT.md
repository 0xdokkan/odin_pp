**Audit tecnico e di gameplay — 6 settembre 2026**

Riferimento: commit `ca64a3a`. Audit di codice, contratti documentati, test e screenshot esistenti. Le riproduzioni aggiuntive sono headless. Questo documento è l'unica aggiunta al repository; il codice del gioco resta invariato.

La base architetturale è buona: simulazione indipendente da Raylib, RNG separati, ID stabili, installazione transazionale delle stanze, targeting condiviso e presentazione separata dallo stato autorevole. Le priorità emerse sono affidabilità delle build, upgrade effettivi e qualità del playtest.

**Verifiche eseguite**

Ambiente: Linux, `odin version dev-2026-08:8412dc37a`.

| Verifica | Risultato |
|---|---|
| `odin check src -vet -strict-style` | Passa |
| `odin test src -all-packages -define:ODIN_TEST_THREADS=1` | 390 test passati; esecuzione test 1,55 s |
| Stessa suite con `-o:none -show-timings` | 390 test passati; compilazione 4,25 s, esecuzione 2,23 s |
| Tracking memoria della suite | Nessun problema segnalato |
| Riproduzioni mirate | Confermano assert con effetti collaterali, upgrade inefficaci, bot bloccato e crescita del buffer loot |
| Build grafica con `-o:none` | Link fallito: la Raylib installata è un puntatore Git LFS |

I tempi sono misure locali, non benchmark comparativi controllati. Gli eseguibili di verifica sono stati indirizzati in `/tmp`. Il passaggio dei test del renderer verifica la sua logica testabile; non equivale all'esecuzione della finestra grafica.

**1. Priorità alta: operazioni di gioco dentro gli assert**

Riferimenti: [parser ASCII](src/level/level.odin#L219), [generazione](src/level/level.odin#L540), [compilazione carte](src/game/card.odin#L1237), [distruzione oggetti](src/game/action.odin#L564).

Il codice usa espressioni come `assert(set_tile(...))`, `assert(instantiated && add_effect(...))` e `assert(remove_grid_object(...))`. Con `-disable-assert` queste operazioni non vengono eseguite.

Risultati riprodotti con il compilatore installato:

- Il parser ASCII restituisce `None` come errore, ma la cella dell'uscita rimane `Void`.
- La generazione procedurale restituisce `Level_Generation_Failed`.
- Isolando il problema del parser nella fixture, `Strike` compila con successo ma contiene **0 effetti**; il nemico resta a 10 HP invece di scendere a 7.
- Un Ice Block viene riportato come distrutto, ma rimane nell'array degli oggetti.

La condizione è specificamente `-disable-assert`; `-o:speed` da solo non causa questo difetto. Il pattern compare anche nella finalizzazione e nell'avvio delle sessioni di telemetria in `main.odin`.

Intervento: eseguire sempre la mutazione e controllare separatamente il risultato, per esempio `added := add_effect(&action, effect)` seguito da `assert(added)`. Dove il fallimento è recuperabile, restituire l'errore. Aggiungere una verifica della build con assert disabilitati che controlli risultati reali di generazione, carte, oggetti e telemetria.

**2. Priorità alta per il gameplay: upgrade acquistabili senza benefici**

Riferimenti: [upgrade del deck](src/game/deck.odin#L171), [shop](src/game/shop.odin#L274), [Rest](src/game/special_node.odin#L358), [catalogo](src/game/card.odin).

`Battle Focus`, `Calculated Risk`, `Spark Forge` e `Dash` accettano l'upgrade, ma nessun loro effetto scala con `upgrade_level`. Costo, range, keyword e caratteristiche della carta creata rimangono invariati.

Riproduzione nello shop: migliorare `Dash` restituisce `Upgraded`, porta l'oro da **10 a 7** e imposta `upgrade_used = true`; la carta mantiene costo 2 e range massimo 3. Al Rest viene consumata la scelta di upgrade attraverso la stessa primitiva.

Intervento immediato: una query condivisa `card_can_upgrade` deve escludere gli upgrade privi di effetti e alimentare sia UI sia mutazioni. In alternativa, definire un beneficio concreto per ogni carta. Mostrare una preview prima/dopo evita che il giocatore debba indovinare cosa acquista. Un test del catalogo dovrebbe verificare che ogni upgrade consentito cambi almeno una proprietà di gameplay.

**3. Priorità media: il bot dei playtest non considera gli oggetti solidi**

Riferimento: [candidate_is_legal](src/combatdebug/kiting.odin#L59).

La policy controlla pavimento, ostacoli ed entità nemiche, ma ignora `Grid_Object`. In un corridoio con player a `(2,1)`, Chaser a `(3,1)` e Ice Block a `(1,1)`, sceglie West. Il gioco blocca il movimento e lo scenario termina con `Command_Rejected`, **0 comandi eseguiti e 0 pulse**.

Intervento: usare `query_entity_movement` per valutare gli spostamenti candidati; trattare Wait separatamente. Aggiungere poi al punteggio il danno da trappole e Fire: una cella attraversabile può essere tatticamente pessima. Gli oggetti non sono ancora generati nelle stanze procedurali, quindi il difetto interessa le fixture che li contengono e i futuri playtest su quel contenuto.

**4. Priorità media per i dati: report interattivi sovrascritti tra sessioni**

Riferimenti: [nome del report](src/main.odin#L754), [seed iniziale](src/main.odin#L972), [scrittura](src/combatdebug/report.odin#L451).

Il nome del file dipende solo dal seed, e ogni avvio parte da `0xC0FFEE`. Due sessioni interattive nella stessa directory possono quindi scrivere entrambe `odin_pp_playtest_12648430.json`: si perde il primo campione. È una conseguenza del percorso di scrittura osservato nel codice.

Intervento: usare una directory o un identificatore distinto per sessione e consentire un percorso di output esplicito. L'identificatore nel nome del file può essere indipendente dal JSON: la serializzazione deterministica resta possibile. La sovrascrittura dello smoke deterministico può invece rimanere intenzionale.

**Ritmo del gioco e IA**

La timeline è coerente con il contratto documentato, ma merita un tuning prima di aggiungere effetti. Nel campione boss `19×11`, profondità 6, nodo 6, seed run `0xC0FFEE`, il primo Wait produce 7 cue e **2,673 secondi** di occupazione della timeline. Durante questo intervallo un comando discreto può essere bufferizzato, ma non eseguito, e il targeting spaziale è sospeso. Il limite generale è 12 secondi per sequenza.

Proposta: velocità delle animazioni configurabile, modalità rapida e misura del tempo tra comando e ritorno dell'interazione. In seguito, gruppi di cue per movimenti indipendenti, preservando rigorosamente l'ordine causale di movimento, hazard, danno e morte. Questa evoluzione è già coerente con M6.

Il Chaser considera soltanto passi che riducono la distanza lungo gli assi. Con nemico a `(1,2)`, player a `(3,2)` e muro a `(2,2)`, resta fermo per 20 Wait pur avendo un percorso aperto sopra e sotto. Archer e Brute riusano quel planner per l'avvicinamento. È un limite già riconosciuto in M5, ma con stanze procedurali ne anticiperei la soluzione.

Una BFS delle distanze verso il player, ricalcolata alla pianificazione, può fornire un passo attorno agli ostacoli; le prenotazioni tra nemici e gli ID ordinati restano necessari. La risoluzione deve continuare a rispettare gli intenti committed.

**Ottimizzazioni proporzionate alle misure**

| Intervento | Evidenza e priorità |
|---|---|
| Preallocare tutto il loot potenziale | In `create_room` la capacità è il numero di nemici, ma alcuni rilasciano due oggetti. Con tre uccisioni e un drop curativo ho misurato capacità **3 → 8** per quattro drop durante `resolve_action`. Correzione semplice: riservare nemici + drop curativi, oppure due slot per nemico. |
| Memorizzare le preview finché lo stato non cambia | `draw_card_target_range` rivaluta tutte le celle a ogni frame. Sul campione boss, 1.000 scansioni di Firebomb hanno richiesto circa **0,038 ms/scansione con `-o:speed`**. È un costo contenuto: ottimizzazione successiva, specialmente se aumentano dimensioni e contenuti. |
| Riutilizzare i conteggi degli intenti | Il renderer scandisce la griglia e riconta gli intenti per ogni cella. Si possono preparare i conteggi quando viene pianificato il pulse. L'hover aggiorna solo l'evidenziazione. |
| Limitare le copie e le validazioni ridondanti | I report sono grandi e il deck viene validato più volte per primitiva. Prima misurare il percorso completo di play/Refocus. Esiste già `DECK_DEEP_VALIDATION`: conservarne i controlli completi ai confini transazionali. |

Il microbenchmark delle preview misura soltanto le query CPU, senza disegno, GPU o frame completo. Il checksum dei risultati è stato utilizzato per mantenere osservabile il lavoro.

Dimensioni rilevate sulla piattaforma locale:

| Tipo | Byte |
|---|---:|
| `Game_Event` | 216 |
| `Event_Log` | 89.872 |
| `Room` | 92.200 |
| `Action_Report` | 90.032 |
| `Card_Play_Report` | 180.160 |
| `Room_Presentation` | 17.784 |
| `Renderer` | 139.120 |

I budget di stack sono già documentati e testati. Aumentare ancora `MAX_GAME_EVENTS` moltiplicherebbe il costo in diversi contenitori. Se gli eventi crescono, valutare payload specifici o storage preallocato condiviso per comando, con ownership esplicita; passare i report grandi per puntatore dove la profilazione ne dimostra il vantaggio. Mantenere la separazione tra eventi autorevoli e copie di presentazione.

**Manutenibilità e leggibilità**

- Separare fixture smoke, lifecycle della sessione e controller delle schermate da `main.odin` (2.004 righe); estrarre carte, intenti e disegno della stanza da `isometric_renderer.odin` (2.464 righe). I confini di package esistenti offrono già una buona base.
- Derivare i numeri dei testi delle carte dal catalogo e dagli effetti istanziati. `card_detail_lines` replica manualmente valori e regole: ogni tuning richiede aggiornamenti paralleli. Mantenere testi specifici dove aiutano davvero la comprensione.
- Conservare il motivo di rifiuto di una giocata nel risultato del dispatcher e mostrarlo brevemente: energia insufficiente, target invalido, effetto indisponibile. Oggi il dispatcher riduce molti esiti a `committed = false`.
- Rendere i comandi debug `C` e `V` attivabili esplicitamente. Consentono status senza possedere la carta in mano e possono alterare le sessioni usate per il bilanciamento, anche se la telemetria li distingue come `Ability`.
- Per il playtest, aggiungere seed selezionabile, confronto degli upgrade e consultazione del deck. Save/replay completi possono seguire la roadmap; il controllo del seed è utile già ora.
- Fissare una versione verificata di Odin/Raylib e aggiungere un comando unico per check, test e build. Nel checkout non c'è una configurazione CI. Verificare anche il link della demo, oltre ai test headless.

**Limite dell'ambiente grafico**

`/usr/lib/odin/vendor/raylib/linux/libraylib.a` contiene il testo `version https://git-lfs.github.com/spec/v1`, non un archivio compilato. Per questo la demo non si collega. È un problema dell'installazione presente nell'ambiente dell'audit; non dimostra un difetto del repository. Non ho modificato l'installazione né eseguito smoke grafici. I suggerimenti visivi si basano sul codice e sulle immagini già presenti.

**Sequenza di lavoro proposta**

1. Spostare le mutazioni fuori dagli assert e verificare le configurazioni di build.
2. Correggere gli upgrade inefficaci e proteggerne il valore nei test.
3. Correggere policy dei playtest e nomi dei report; raccogliere più sessioni comparabili.
4. Aggiungere velocità della timeline e pathfinding minimo attorno agli ostacoli.
5. Preallocare il loot; intervenire su cache e storage degli eventi quando le misure lo giustificano.

Le riproduzioni locali sono conservate in `/tmp/odin_pp_audit/probe.odin`. Per rieseguirle da questo workspace:

```sh
odin run /tmp/odin_pp_audit -collection:project=/home/raven/Code/odin_pp/src -o:none
odin run /tmp/odin_pp_audit -collection:project=/home/raven/Code/odin_pp/src -o:none -disable-assert
odin run /tmp/odin_pp_audit -collection:project=/home/raven/Code/odin_pp/src -o:speed
```
