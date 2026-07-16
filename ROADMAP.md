# Roadmap

Questa roadmap organizza il lavoro in incrementi giocabili. Una milestone viene
marcata come completata soltanto quando il suo comportamento e integrato nella
demo, le invarianti sono coperte da test e la documentazione descrive il codice
effettivamente presente.

Stati usati:

- `[x]` completata;
- `[~]` in corso;
- `[ ]` pianificata.

## [x] Baseline - Vertical slice

La prima vertical slice stabilisce il loop e i confini architetturali su cui
costruire il gioco:

- griglia 2D e proiezione isometrica su canvas virtuale;
- rotta della run come DAG deterministico;
- fasi `Combat`, `Loot`, `Reward`, `Shop`, `Rest`, `Event`, `Treasure`,
  `Choose_Path`, `Victory` e `Defeat`;
- azioni atomiche, impulsi, status e reazioni FIFO;
- intenti committed e archetipi `Chaser`, `Archer` e `Brute`;
- deck runtime, carte, targeting spaziale, drag e ricompense;
- loot magnetico durante e dopo il combattimento;
- timeline di presentazione e buffer di un comando.

La baseline e completata quando la demo attraversa un'intera run e la suite
completa, lo smoke test della timeline e lo smoke test del targeting terminano
senza errori.

## [x] M1 - Stanze procedurali

**Obiettivo:** sostituire layout e spawn dimostrativi con stanze riproducibili,
valide e differenziate per nodo, mantenendo separate topologia e difficolta.

Lo scope comprende:

- configurazione esplicita di dimensioni, densita e distanze di sicurezza;
- seed della stanza derivato da seed della run e identita del nodo;
- generazione del layout senza dipendenze di `level` dal gameplay;
- validazione della raggiungibilita con flood fill o BFS;
- encounter director con budget distinti per `Combat`, `Elite` e `Boss`;
- collocamento deterministico di nemici, trappole e ostacoli;
- integrazione nella creazione e sostituzione della stanza;
- test generativi su un insieme ampio di seed.

### Definition of Done

M1 e completata quando:

1. gli stessi seed, nodo e configurazione producono lo stesso layout e gli stessi
   spawn;
2. esistono esattamente uno spawn del player e un'uscita, entrambi calpestabili;
3. l'uscita e raggiungibile dallo spawn e le celle riservate non sono isolate;
4. ogni entita e entro i bounds, su una cella valida e senza sovrapposizioni non
   consentite;
5. l'area di sicurezza del player e rispettata e nessun ostacolo blocca l'unico
   percorso valido;
6. profondita e tipo del nodo modificano il budget senza entrare nel package
   `level`;
7. almeno 4096 combinazioni deterministiche di seed e profilo superano il
   validatore senza fallback invalido;
8. `odin test src -all-packages -define:ODIN_TEST_THREADS=1` e
   `odin check src -vet -strict-style` terminano con successo.

Il contratto tecnico e lo stato dell'incremento sono descritti in
[Room Generation](ROOM_GENERATION.md).

## [x] M2 - Economia del deck

**Obiettivo:** rendere le carte una progressione con costi e scelte permanenti.

- pool e rarita pesati per profondita e tipo di nodo;
- upgrade e rimozione di una `Card_Instance`;
- shop con prezzi, acquisto e gestione del deck pieno;
- reward aggiornati senza rompere ID e RNG separati.

### Definition of Done

M2 e completata quando:

1. reward e shop estraggono offerte uniche con pesi dipendenti da rarita, tipo
   del nodo e profondita;
2. RNG di combattimento, reward e shop restano separati e riproducibili;
3. scelta, skip, acquisto, upgrade e rimozione sono transazioni atomiche;
4. fallimenti, deck pieno e ID esauriti non consumano oro, ID, offerte o RNG;
5. upgrade e rimozione agiscono sull'ID della specifica `Card_Instance`;
6. il nodo Shop corrente puo essere lasciato e riaperto dalla route senza
   rigenerare offerte;
7. le modifiche al deck persistono nella stanza procedurale successiva;
8. UI, smoke test, suite completa e controllo statico terminano con successo.

Il contratto tecnico e lo stato dell'incremento sono descritti in
[Deck Economy](DECK_ECONOMY.md).

## [x] M3 - Nodi speciali

**Obiettivo:** dare alla rotta decisioni diverse dal combattimento.

- nodi `Shop`, `Rest`, `Event` e `Treasure`;
- configurazioni, schermate e transizioni dedicate;
- vincoli di distribuzione nel DAG.

### Definition of Done

M3 e completata quando:

1. ogni layer intermedio contiene esattamente un nodo speciale e almeno un nodo
   con stanza;
2. Shop, Rest, Event e Treasure seguono un ciclo deterministico con offset dal
   seed, verificato da `validate_run_map`;
3. l'ingresso costruisce e valida il payload prima di modificare nodo corrente,
   fase, RNG o flag `entered`;
4. lo Shop e un nodo della rotta, conserva offerte e servizi durante la
   riapertura e li azzera entrando nel nodo successivo;
5. Rest, i tre tipi di Event e Treasure applicano scelte distinte e mostrano un
   risultato prima di tornare alla rotta;
6. Leave, risoluzione e Continue sono one-shot e incrementano `cleared_count`
   esattamente una volta;
7. vita insufficiente, overflow, deck pieno, livello massimo, ID esauriti e
   payload corrotti non producono mutazioni parziali;
8. renderer, controlli, smoke dei quattro tipi, suite completa e controllo
   statico terminano con successo.

Il contratto tecnico e lo stato dell'incremento sono descritti in
[Special Nodes](SPECIAL_NODES.md).

## [~] M4 - Profondita di carte e status

**Obiettivo:** ampliare le decisioni del deck senza duplicare resolver o
targeting.

- `Exhaust`, `Retain`, carte temporanee e carte ethereal;
- effetti di pesca e scarto, modificatori di costo e rigenerazione;
- nuovi trigger di reazione e scadenza;
- targeting a cono e ulteriori footprint condivise.

### [x] M4A - Lifecycle e primitive del deck

- zone `Exhaust` e `Resolving`, lifetime permanente o limitato al fight;
- ID temporanei monotoni, budget fisso e validazione di ownership fra tutte le zone;
- effetti autorevoli `Draw Cards`, `Discard Cards` e `Create Card`;
- `Battle Focus`, `Calculated Risk`, `Spark Forge` e token `Spark`;
- replay FIFO di play, draw, move e create, con HUD `EXH` e tag `TEMP`;
- smoke `--smoke-deck-flow` e test di reshuffle, rollback, capacita e mismatch.

Il contratto di M4A e descritto in [Card Lifecycle](CARD_LIFECYCLE.md).

### [~] M4B - Ciclo della mano e costi

- [x] `Refocus` manuale come frontiera esplicita per refill, retain ed ethereal;
- [x] cleanup stabile, un pulse nemico, refill condizionale e replay FIFO;
- [x] pulsante, shortcut `F`, tag e smoke `--smoke-refocus`;
- aggiungere modificatori di costo e rigenerazione con durata osservabile;
- progettare lo scarto selezionato senza inserire stato UI nel deck autorevole.

Il contratto dell'incremento completato e in [Hand Cycle](HAND_CYCLE.md). M4B
resta in corso finche costi dinamici e selezione dello scarto non sono integrati.

### [x] M4C - Movimento spaziale e hazard

- query pura `Movement_Query` con semantiche `Traverse` e `Teleport`;
- percorso cella per cella, blocker statici/attori e corner squeeze condivisi;
- hazard neutrali per player e nemici, con ordine esplicito
  `Movement -> Trap -> Damage -> Defeat`;
- `Shove`, `Dash` e `Grappling Hook` sopra normali effect template;
- preview, drop e compilazione alimentati dalla stessa valutazione di targeting e
  movimento;
- spostamenti forzati che rendono stale gli intenti committed senza retargeting;
- replay FIFO di `Movement_Step` e `Trap_Triggered`, con envelope eventi
  `258 + 158 = 416`.

Il contratto di M4C e descritto in [Movement System](MOVEMENT_SYSTEM.md).

### [x] M4C.1 - Content pass

- cinque definizioni senza nuove primitive: `Heavy Blow`, `Venom Needle`,
  `Caustic Bloom`, `Purifying Guard` e `Volatile Study`;
- confronto esplicito bump / `Strike` / `Heavy Blow` nell'economia dei pulse;
- danno + status, status 3x3, cleanup opzionale e Create + Draw + Exhaust;
- casi renderer distinti, smoke `--smoke-content` e test di composizione;
- matrice e domande misurabili in [Content Pass](CONTENT_PASS.md).

Il prossimo incremento deve essere scelto dai risultati di playtest, non dalla
sola disponibilita di una nuova primitiva.

### [ ] M4D - Reazioni e nuove geometrie

- nuovi trigger e condizioni di scadenza;
- targeting a cono e nuove footprint condivise fra preview e resolver.

**Definition of Done:** preview e compilazione producono gli stessi bersagli;
zone e ID del deck restano validi dopo ogni combinazione; la timeline mostra le
mutazioni nello stesso ordine della simulazione; i nuovi effetti hanno test di
composizione e casi limite.

## [ ] M5 - Encounter e boss

**Obiettivo:** costruire combattimenti con cooperazione fra nemici e pressione
spaziale crescente.

- pathfinding attorno agli ostacoli;
- intenti nemici con linee, croci e aree;
- archetipi di supporto, evocazione e controllo;
- elite e boss a fasi con regole esplicite.

**Definition of Done:** gli intenti restano committed e deterministici, usano la
stessa autorita geometrica delle carte e non dipendono dal renderer; simulazioni
headless coprono morte, blocchi, spawn e cambi di fase senza deadlock o overflow.

## [ ] M6 - Persistenza e game feel

**Obiettivo:** rendere la vertical slice riproducibile, diagnosticabile e
presentabile senza accoppiare feedback e simulazione.

- salvataggi versionati e caricamento della run;
- replay deterministici basati sui comandi;
- selettore del seed e strumenti di debug;
- gruppi espliciti di cue, audio, particelle, hit stop e screen shake controllato.

**Definition of Done:** un save completa il round trip senza perdere invarianti;
un replay ricostruisce lo stesso stato finale; migrazioni e dati corrotti falliscono
in modo diagnosticabile; disabilitare o rallentare i feedback non cambia il
risultato del gameplay.
