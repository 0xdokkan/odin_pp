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

### [x] M1A - Famiglie di stanze e placement tattico

- quattro geometrie compatte: arena con pilastri, anello, cortili con due
  passaggi e coperture asimmetriche;
- varianti riproducibili dal seed, con spawn e uscita scelti dopo la geometria;
- nessuna ripetizione della famiglia dell'ultima stanza effettivamente
  installata, anche attraversando nodi speciali;
- Archer vicino a coperture aggirabili, Brute con corsie di carica e coppie
  degli incontri disposte secondo i rispettivi ruoli;
- perimetro e accessi ai due cortili riservati durante il placement di ostacoli
  e oggetti, con almeno una direzione iniziale di spinta libera per ogni barile;
- verifica delle forme su 1536 layout, test dei due passaggi indipendenti e
  4096 combinazioni di seed, profilo e famiglia precedente;
- test del commit dello storico, del passaggio nei nodi speciali, del restart
  e della riproducibilita di una rotta scelta.

Il generatore generico conserva la modalita `Scattered`; la demo usa le quattro
famiglie tattiche e non torna alla modalita casuale in caso di fallimento.

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
  `Movement -> Trigger -> Damage -> Defeat`;
- `Shove`, `Dash` e `Grappling Hook` sopra normali effect template;
- preview, drop e compilazione alimentati dalla stessa valutazione di targeting e
  movimento;
- spostamenti forzati che rendono stale gli intenti committed senza retargeting;
- replay FIFO di `Movement_Step`, `Trap_Triggered` e `Hazard_Triggered`, con
  envelope eventi `258 + 158 = 416`.

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

### [x] M4C.2 - Telemetria di playtest

- snapshot e descrittore pre-comando collegati all'unico dispatcher di input;
- sample per tentativi accepted/rejected e aggregati per stanza e intera run;
- breakdown nominato per comando e carta, inclusi target pianificati/reali,
  danno, energia, Poison, Refocus, movimento forzato e combo con trappole;
- confronto osservabile fra bump, `Strike` e `Heavy Blow` quando tutte e tre le
  opzioni sono disponibili;
- report JSON deterministico con schema versionato, integrita esplicita e
  outcome `Victory`, `Defeat` o `Abandoned`;
- acquisizione interattiva e smoke headless senza inizializzare Raylib;
- test di attribuzione, aggregazione exactly-once e serializzazione stabile.

Il formato, i confini di attribuzione e i comandi CLI sono descritti in
[Combat Telemetry](COMBAT_TELEMETRY.md). I risultati di piu run comparabili
decideranno se il prossimo intervento sara tuning del contenuto o una primitiva
di controllo come `Slow`/`Root`.

### [x] M4C.3 - Oggetti fisici sulla griglia

- dominio `Grid_Object` data-driven con ID stabile e capability separate per
  movimento, LoS, targeting, danno e spostamento;
- query spaziali condivise da player, AI, cariche, targeting e movimento;
- Ice Block targetabile, spostabile con `Shove`, danneggiabile e distruttibile;
- policy esplicita: gli oggetti spinti non attivano le trappole e non governano
  la fine del combat;
- replay timeline di movimento, danno e distruzione, renderer isometrico e smoke
  `--smoke-object`;
- test di storage, overlap, collisione, LoS, action resolver e snapshot.

Il contratto e descritto in [Grid Object System](GRID_OBJECT_SYSTEM.md). Lo
spawn procedurale e stato integrato in M4C.5, includendo gli oggetti nella
verifica della connettivita.

### [x] M4C.4 - Fire persistente

- capability data-driven `hazardous` e `hazard_damage`, indipendenti da
  collisione, LoS, targeting, danno e movimento;
- `Fire` attraversabile e trasparente che infligge 2 danni a player e nemici
  dopo ogni ingresso in `Combat` o `Loot`;
- policy entry-only: nessun tick su `Wait` o permanenza, ogni cella attraversata
  viene risolta, la landing di `Teleport` viene risolta una volta;
- pipeline condivisa per difesa, Shield, morte, loot e cambio di fase, senza
  consumare la fiamma;
- evento `Hazard_Triggered`, replay `BURN`, renderer a strati e smoke
  `--smoke-fire`;
- telemetria generica `object_hazard_*`, separata per trigger e danno effettivo
  su player/nemici, con aggregazione e JSON deterministici;
- test di catalogo, overlap, geometria, danno, Shield, morte, fase, targeting,
  timeline e telemetria.

Il contratto e descritto in [Grid Object System](GRID_OBJECT_SYSTEM.md) e
[Movement System](MOVEMENT_SYSTEM.md). `Chest` resta pianificato: provera stato
chiuso/aperto, interazione e ricompensa one-shot.

### [x] M4C.5 - Esplosivi e prima zona tattica

- Barrel spostabile e Bomb con countdown di due decisioni accettate;
- area 3x3 condivisa fra preview e danno, inclusi nemici e oggetti;
- catene ritardate e disinnesco degli esplosivi alla fine del combattimento;
- Bomber con bersaglio committed e Brute con recupero dopo la carica;
- Shove e Dash nel mazzo iniziale;
- Barrel, Ice Block e Fire nelle stanze procedurali, con un percorso disponibile
  anche considerando il fuoco come cella da evitare;
- intenti, countdown, timeline e smoke delle interazioni tattiche.

Le regole giocabili sono raccolte in [Tactical Combat](TACTICAL_COMBAT.md).

### [ ] M4D - Reazioni e nuove geometrie

- nuovi trigger e condizioni di scadenza;
- targeting a cono e nuove footprint condivise fra preview e resolver.

**Definition of Done:** preview e compilazione producono gli stessi bersagli;
zone e ID del deck restano validi dopo ogni combinazione; la timeline mostra le
mutazioni nello stesso ordine della simulazione; i nuovi effetti hanno test di
composizione e casi limite.

### [x] M4E - Reliquie della run

- sei reliquie con sinergie per spinte, Exhaust, movimento, Poison, difesa e cure;
- scelta iniziale e offerte dopo Elite e Claim al Treasure, senza duplicati;
- inventario persistente fra nodi, limiti per combattimento e reset al restart;
- offerte deterministiche e transazioni che conservano deck, ricompense e RNG;
- schermata di scelta, shortcut, barra con descrizioni e due smoke grafici;
- eventi normali per i bonus e replay esplicito del recupero di energia;
- test delle giocate reali, della timeline e delle transizioni della run.

Il catalogo e le regole sono in [Reliquie](RELICS.md).

### [x] M4F - Spell, dadi e impatti condivisi

- Fate Strike: RNG D6 dedicato, danno variabile e rimbalzo condizionale su 6;
- Chain Lightning: tre bersagli distinti con distanza, LoS e ordine deterministici;
- preview senza consumo di RNG, con tratto condizionale per il bonus del dado;
- Firebomb con proiettile, impatto unico e footprint catturata nel log;
- gruppi visivi espliciti per gli effetti diretti dell'area, seguiti dalle reazioni;
- dado 3D su texture trasparente con risultato coerente con la simulazione;
- clip PNG/GIF di lancio, impatto e cast/hit del player, con fallback procedurale;
- arena `--spell-lab`, smoke grafici e test di RNG, replay, gruppi e risorse.
- pool fino a tre D6 con mesh smussate, collisioni e rimbalzi fisici;
- Sundering Blow con somma e spinta, Prismatic Barrage con successi e Shield,
  Twin Venom con massimo e coppie; arena dedicata `--dice-lab`.

Le regole e i comandi sono in [Spell e dadi](SPELLS.md). Ulteriori carte,
evocazioni, aure, audio e animazioni dedicate agli altri personaggi restano
incrementi successivi.

## [~] M5 - Encounter e boss

**Obiettivo:** costruire combattimenti con cooperazione fra nemici e pressione
spaziale crescente.

- [x] pathfinding attorno agli ostacoli e agli oggetti solidi;
- [x] intenti di carica in linea e bombe con area 3x3;
- [x] primo archetipo di supporto e primo boss a due fasi;
- [ ] ulteriori geometrie, inclusi attacchi a croce;
- [ ] archetipi di evocazione e controllo;
- [ ] ulteriori elite e boss con regole distinte.

### [x] M5A - Cooperazione, composizioni e primo boss

- Custodian annuncia la protezione di un alleato; spostamento fuori portata,
  copertura e bersaglio non piu valido interrompono la protezione;
- Polveriera, Scorta e Assalto selezionate dal seed, con una coppia vicina che
  caratterizza lo scontro e budget restante validato;
- Polveriera iniziale con Bomber, Chaser, due barili, ghiaccio e fuoco;
- modificatore Furnace con fila o colonna annunciata, due decisioni prima del
  danno, pausa fra attivazioni e vie statiche per uscire dall'area;
- stanze iniziali e Boss con modificatore Calm, per introdurre la pressione in
  modo graduale;
- Demolitionist unico nei nodi Boss: due fasi che alternano bombe, cariche e
  recupero, con attacchi annunciati e transizione osservabile;
- metadati condivisi fra blueprint, stanza e presentazione; validazione della
  composizione, dell'area Furnace, del budget e dell'unicita del boss;
- test di cooperazione, scadenze, catene, cambi di fase e fine combattimento,
  oltre ai 4096 scenari del generatore.

Il contratto della generazione e in [Room Generation](ROOM_GENERATION.md); le
regole di combattimento sono in [Tactical Combat](TACTICAL_COMBAT.md). M5 resta
in corso: questo incremento completa il primo insieme giocabile, mentre
evocazione, controllo e ulteriori famiglie di elite e boss restano pianificati.

**Definition of Done di M5:** gli intenti restano committed e deterministici, usano la
stessa autorita geometrica delle carte e non dipendono dal renderer; simulazioni
headless coprono morte, blocchi, spawn e cambi di fase senza deadlock o overflow.

## [~] M6 - Persistenza e game feel

**Obiettivo:** rendere la vertical slice riproducibile, diagnosticabile e
presentabile senza accoppiare feedback e simulazione.

- salvataggi versionati e caricamento della run;
- replay deterministici basati sui comandi;
- selettore del seed e strumenti di debug;
- gruppi espliciti di cue, audio, particelle, hit stop e screen shake controllato.

### [x] M6A - Sprite personalizzati

- PNG statici, sprite sheet PNG e GIF per player, nemici e oggetti;
- manifest opzionale con dimensioni, anchor, frame e FPS configurabili;
- clock cosmetico separato dalla simulazione e fallback per tipo;
- texture condivise, alpha picking e scaricamento delle risorse prima della finestra;
- indicatori di gioco conservati sopra le immagini e smoke GPU con asset temporanei.

La [guida agli sprite](SPRITES.md) descrive il formato e i limiti, incluso il
timing uniforme delle GIF. Le illustrazioni definitive e le animazioni distinte
per azione restano da aggiungere. M6 resta in corso per persistenza, replay e
gli altri feedback pianificati.

**Definition of Done:** un save completa il round trip senza perdere invarianti;
un replay ricostruisce lo stesso stato finale; migrazioni e dati corrotti falliscono
in modo diagnosticabile; disabilitare o rallentare i feedback non cambia il
risultato del gameplay.
