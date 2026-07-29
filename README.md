# Odin 2D Engine

Vertical slice di un roguelike 2D a griglia isometrica scritto in Odin.

Documentazione del gameplay: [Action System](ACTION_SYSTEM.md),
[Status And Event System](STATUS_SYSTEM.md), [Reaction Queue](REACTION_SYSTEM.md),
[Enemy Intents](ENEMY_INTENT_SYSTEM.md),
[Magnetic Loot](LOOT_SYSTEM.md), [Card System](CARD_SYSTEM.md),
[Targeting System](TARGETING_SYSTEM.md), [Movement System](MOVEMENT_SYSTEM.md),
[Grid Objects](GRID_OBJECT_SYSTEM.md),
[Content Pass](CONTENT_PASS.md),
[Deck Runtime](DECK_SYSTEM.md),
[Card Lifecycle](CARD_LIFECYCLE.md), [Hand Cycle](HAND_CYCLE.md) e
[Card Rewards](REWARD_SYSTEM.md). Rarita, upgrade, rimozione e shop sono in
[Deck Economy](DECK_ECONOMY.md); distribuzione e lifecycle di Shop, Rest, Event e
Treasure in [Special Nodes](SPECIAL_NODES.md). Il confine fra simulazione,
animazioni e input bufferizzato e documentato in
[Presentation Timeline](PRESENTATION_TIMELINE.md); observer e scenari headless
sono descritti in [Combat Telemetry](COMBAT_TELEMETRY.md). Le milestone sono raccolte
nella [Roadmap](ROADMAP.md); i contratti di M1, M2 e M3 sono in
[Room Generation](ROOM_GENERATION.md), [Deck Economy](DECK_ECONOMY.md) e
[Special Nodes](SPECIAL_NODES.md).

![Anteprima della griglia isometrica](odin_pp_isometric.png)

![Prima stanza procedurale deterministica](odin_pp_procedural_room.png)

![Mappa procedurale della run](odin_pp_route.png)

![Status durante il combattimento](odin_pp_status.png)

![Loot magnetico durante e dopo il combattimento](odin_pp_loot.png)

![Trascinamento di una carta e anteprima del range](odin_pp_card_drag.png)

![Cast range e footprint 3x3 del targeting](odin_pp_advanced_targeting.png)

![Percorso e landing di Dash sopra una trappola](odin_pp_spatial_targeting.png)

![Ice Block targetabile con Shove](odin_pp_ice_block.png)

![Fire persistente durante il cue BURN](odin_pp_fire.png)

![Cinque nuove carte e targeting 3x3 di Caustic Bloom](odin_pp_content_pass.png)

![Scelta della ricompensa dopo una stanza](odin_pp_reward.png)

![Nodo Shop con offerte e servizi sul deck](odin_pp_shop.png)

![Scelte del nodo Rest e upgrade per istanza](odin_pp_rest.png)

![Evento deterministico della rotta](odin_pp_event.png)

![Ricompensa del nodo Treasure](odin_pp_treasure.png)

![Risultato one-shot di un nodo speciale](odin_pp_special_result.png)

![Intenti committed dei nemici](odin_pp_enemy_intents.png)

![Inseguitore, arciere e bruto con carica telegrafata](odin_pp_enemy_archetypes.png)

![Timeline FIFO durante la giocata di una carta](odin_pp_timeline.png)

![Create, carta temporanea ed exhaust nel deck runtime](odin_pp_deck_flow.png)

![Refocus con Retain ed Ethereal](odin_pp_refocus.png)

![Schermata di sconfitta con restart](odin_pp_defeat.png)

## Eseguire la demo

```sh
odin run src
```

Le grandi assegnazioni per valore di `Room` restano confinate negli helper di
installazione, evitando che LLVM le scalarizzi dentro `main`. `-o:none` resta
disponibile per esperimenti senza ottimizzazione; `odin build src -out:odin_pp`
produce invece un eseguibile persistente.

La demo apre una finestra ridimensionabile e avvia una run di sette livelli. Ogni
nodo possiede un seed di stanza derivato dalla run: layout, nemici, trappole e
ostacoli vengono generati in modo riproducibile per i profili `Combat`, `Elite` e
`Boss`.

Per produrre lo screenshot deterministico del targeting avanzato:

```sh
odin run src -- --smoke-targeting
```

Il flag prepara `Firebomb`, mostra cast range e footprint sulla griglia, salva
`odin_pp_advanced_targeting.png` dopo tre frame e chiude la demo.

Per verificare la preview condivisa di targeting e movimento:

```sh
odin run src -- --smoke-spatial
```

Il flag trascina una `Dash` temporanea su una linea di tre celle, colloca una
trappola armata sul percorso e salva `odin_pp_spatial_targeting.png` dopo tre
frame.

Per verificare collisione, linea di vista e targeting degli oggetti fisici:

```sh
odin run src -- --smoke-object
```

Il flag prepara `Shove` contro un Ice Block adiacente e salva
`odin_pp_ice_block.png`. Gli oggetti correnti sono inseriti manualmente
nelle stanze statiche; non fanno ancora parte della generazione procedurale.

Per verificare l'hazard persistente `Fire` e il relativo replay:

```sh
odin run src -- --smoke-fire
```

Il flag fa entrare il player nella cella, mostra il cue `BURN`, mantiene la
fiamma nella timeline e salva `odin_pp_fire.png`.

Per verificare il content pass e la leggibilita delle nuove carte:

```sh
odin run src -- --smoke-content
```

Il flag prepara una mano con `Heavy Blow`, `Venom Needle`, `Caustic Bloom`,
`Purifying Guard` e `Volatile Study`, trascina Bloom su tre nemici e salva
`odin_pp_content_pass.png`.

Per raccogliere metriche durante una run interattiva:

```sh
odin run src -- --playtest-report
```

Alla fine della run, al restart o alla chiusura viene scritto
`odin_pp_playtest_<seed>.json`. Il report separa comandi e carte e conserva i
sample ordinati di ogni fight. La variante headless non inizializza Raylib:

```sh
odin run src -- --smoke-playtest
```

Esegue venti decisioni deterministiche al massimo e scrive
`odin_pp_playtest_smoke.json`.

Per verificare la timeline con uno snapshot pre-comando e un cue carta attivo:

```sh
odin run src -- --smoke-timeline
```

Per esercitare nello stesso flusso `Create Card`, lifetime temporaneo, zona
`Resolving`, `Exhaust` e replay del deck:

```sh
odin run src -- --smoke-deck-flow
```

Il comando salva `odin_pp_deck_flow.png` con una `Spark` temporanea visibile,
`Spark Forge` in exhaust e i contatori aggiornati.

Per verificare Refocus, Retain, Ethereal, pulse e refill nello stesso flusso:

```sh
odin run src -- --smoke-refocus
```

Il comando salva `odin_pp_refocus.png` durante il cue iniziale della frontiera.

Per produrre uno screenshot deterministico della prima stanza procedurale:

```sh
odin run src -- --smoke-generation
```

Il comando salva `odin_pp_procedural_room.png` dopo tre frame e chiude la demo.

Per verificare offerte, deck paginato e servizi dello shop:

```sh
odin run src -- --smoke-shop
```

Le schermate degli altri nodi speciali hanno smoke dedicati:

```sh
odin run src -- --smoke-rest
odin run src -- --smoke-event
odin run src -- --smoke-treasure
odin run src -- --smoke-special-result
```

I comandi salvano `odin_pp_rest.png`, `odin_pp_event.png` e
`odin_pp_treasure.png`; l'ultimo salva `odin_pp_special_result.png` con il
pannello risolto e Continue disponibile.

## Loop attuale

1. La stanza parte in `Combat`: il deck viene mescolato, si pescano cinque carte
   e il player riceve tre energia.
2. Prima dell'input, inseguitori, arcieri e bruti mostrano l'intento committed per
   il prossimo impulso: movimento, attacco, carica e celle minacciate non vengono
   ricalcolati dopo la scelta del player. Una spinta o un pull puo renderli stale:
   al pulse producono miss o blocco invece di retargettare.
3. Le carte passano dalla mano a `Resolving`, applicano in ordine danno, status o
   effetti `Move`/`Draw`/`Discard`/`Create`, poi entrano in discard o exhaust.
   Se il fight continua tentano di pescare un rimpiazzo e recuperano una energia
   per impulso.
4. Ogni passo valido, bump attack, attesa, abilita, carta o Refocus accettato
   produce un impulso se il fight continua. Il player puo camminare senza un
   limite numerico, ma ogni cella attraversata concede la risposta committed ai
   nemici.
5. Ogni drop entro tre celle per asse viene assorbito anche durante `Combat`;
   eliminato l'ultimo nemico, la stanza passa a `Loot` e gli spostamenti non
   producono piu pulse.
6. Entrare sull'uscita verde conclude la stanza e apre `Reward` con tre carte
   distinte, pesate per rarita, profondita e tipo del nodo.
7. Scegliere una carta la aggiunge al deck; `Skip` prosegue senza modificarlo.
   Entrambe le decisioni azzerano la reward e aprono `Choose_Path`.
8. `Choose_Path` permette di scegliere uno, due o tre nodi collegati. `Combat`,
   `Elite` e `Boss` installano una stanza deterministica con il profilo relativo.
9. Un nodo `Shop` offre tre carte, un upgrade e una rimozione. Uscire completa il
   nodo e apre la mappa; il vendor corrente puo essere riaperto senza reroll.
10. `Rest`, `Event` e `Treasure` mostrano scelte dedicate. Una scelta oppure Leave
   produce un risultato one-shot; Continue completa il nodo e torna alla rotta.
11. L'ultimo nodo e il boss. Superarlo porta a `Victory`; morire apre `Defeat`, da
   cui si puo iniziare una nuova run con `Enter` o il pulsante `Restart`.

Gli attacchi a contatto restano disponibili accanto alle carte. Carte e bump
attack costruiscono normali `Action`: il bump non sposta il player, ma produce
comunque un pulse. Il suo costo tattico e quindi la risposta nemica, non il
posizionamento. `Strike` porta il danno melee a 3 per un'energia; `Heavy Blow`
ne concentra 5 in un solo pulse al costo di due energie. Il confronto e parte
del playtest descritto in [Content Pass](CONTENT_PASS.md).

### Controlli

| Input | Azione |
|---|---|
| hover su carta | solleva la carta e mostra regole, costo e cast range |
| trascina carta sulla griglia | mostra anchor, footprint, percorso di cast e movimento, landing e blocker; prova la giocata sulla cella di rilascio |
| `1`-`8` | gioca una carta non spaziale o seleziona una carta spaziale |
| click su cella | usa la carta spaziale selezionata da tastiera sull'anchor |
| `Esc` / click destro | annulla selezione o trascinamento |
| `WASD` | un comando per pressione: muove il player; contro un nemico esegue un attacco |
| `Spazio` | aspetta un impulso durante il combattimento |
| `F` / pulsante Refocus | applica Retain/Ethereal, produce un pulse e pesca fino alla dimensione mano |
| `C` `V` | abilita debug per Thorn Coat e Afterimage |
| frecce | sposta la camera |
| rotella | zoom ancorato al cursore |
| trascinamento rotella | sposta la camera col mouse |
| `R` | inquadra nuovamente il livello |
| `M` | mostra o nasconde la rotta durante una stanza |
| click / `1` `2` `3` | sceglie una carta durante `Reward` |
| `S` / pulsante Skip | salta la ricompensa |
| click / `1` `2` `3` nello shop | acquista una delle offerte disponibili |
| click su carta posseduta | seleziona l'istanza da migliorare o rimuovere |
| `U` / pulsante Upgrade | migliora la carta selezionata |
| `R` / pulsante Remove | rimuove la carta selezionata |
| frecce / pulsanti freccia | cambia pagina del deck nello shop |
| `Enter` / `Esc` / Continue | esce dallo shop e apre la mappa |
| pulsante Shop sulla mappa | riapre il nodo Shop corrente senza reroll |
| click / `1` in un nodo speciale | Recover al Rest, prima scelta Event o Claim al Treasure |
| click / `2` in Rest o Event | migliora la carta selezionata oppure usa la seconda scelta Event |
| click su carta al Rest | seleziona la specifica istanza da migliorare |
| `U` al Rest | migliora la carta selezionata |
| frecce / pulsanti freccia al Rest | cambia pagina del deck e azzera la selezione |
| `L` / pulsante Leave | risolve Rest, Event o Treasure senza prendere la ricompensa |
| `Enter` / Continue dopo il risultato | completa il nodo speciale e torna alla mappa |
| click / `1` `2` `3` | sceglie uno dei nodi disponibili |
| `Enter` / pulsante Restart | avvia una nuova run dalla schermata `Defeat` |
| `F5` | crea una nuova run con un seed diverso |
| `F1` | scaling fit con letterbox |
| `F2` | integer scaling |
| `F3` | scaling stretch |
| `F11` | fullscreen borderless |

## Eseguire i test

```sh
odin test src/grid
odin test src/level
odin test src/view
odin test src/game
odin test src/combatdebug
odin test src/render
```

La verifica completa, inclusi i test di integrazione del package principale, e:

```sh
odin test src -all-packages -define:ODIN_TEST_THREADS=1
odin check src -vet -strict-style
```

## Simboli della mappa

| Simbolo | Tile |
|---|---|
| spazio | vuoto |
| `.` | pavimento |
| `#` | muro |
| `+` | porta |
| `@` | spawn del player |
| `>` | uscita |

## Struttura attuale

```text
src/
  main.odin         # demo e punto di ingresso
  app/              # finestra, canvas virtuale e presentazione
  game/             # simulazione, profili encounter e blueprint della stanza
  grid/             # container generico Grid(T)
  level/            # tile, layout procedurale e validazione BFS
  render/           # renderer isometrico Raylib
  view/             # scaling, proiezione e camera testabili
```

`grid` non conosce il gioco. Gestisce solo coordinate, memoria contigua e
accesso sicuro. `level` assegna un significato alle celle, genera la topologia e
ne verifica la raggiungibilita senza conoscere nemici o tipi di nodo. Per
`Combat`, `Elite` e `Boss`, `game` traduce il nodo in un profilo, applica
l'encounter budget e costruisce un `Room_Blueprint`; per i nodi speciali prepara
invece un payload dedicato senza creare una stanza vuota. `Run_State` possiede il
player, il grafo e questi payload. Una `Room` possiede soltanto le entita
temporanee e prende in prestito puntatori al livello e al player della run. Il
renderer legge questi dati, ma non li possiede e non li cambia.

Input, IA, hazard e loot costruiscono `Action` composte da effetti ordinati.
`resolve_action` valida sorgente e target, richiede almeno un effetto inizialmente
valido, poi ricontrolla e applica gli effetti in sequenza: un effetto successivo
puo essere saltato se lo stato prodotto dai precedenti lo rende non piu valido.
Lo scheduler degli impulsi resta separato dal resolver.
`Movement_Query` e l'autorita pura degli spostamenti: `Traverse` valida e
attraversa l'intera linea, `Teleport` ignora le celle intermedie ma controlla la
landing. L'applicazione entra cella per cella, registra `Movement_Step` e `Moved`
e risolve subito trappole e grid object pericolosi per player o nemici. `Fire`
e attraversabile, trasparente e persistente: infligge danno a ogni ingresso, ma
non produce tick quando un attore resta fermo. Il relativo contratto e in
[Movement System](MOVEMENT_SYSTEM.md) e [Grid Object System](GRID_OBJECT_SYSTEM.md).
Ogni nemico conserva inline un intento committed per `pulse_count + 1`.
Pianificazione e risoluzione seguono gli ID in ordine crescente; spostarsi fuori
da una cella minacciata produce un miss, mentre occupare una destinazione puo
bloccare un movimento senza causare replanning. Anche uno spostamento forzato
lascia intatto il piano congelato: un intento stale fallisce e viene ripianificato
soltanto per il pulse successivo.
`Enemy_Archetype` seleziona tre planner sulla stessa pipeline: il `Chaser` avanza
o attacca in melee, l'`Archer` arretra quando viene ingaggiato e spara lungo una
linea ortogonale libera, mentre il `Brute` puo attraversare piu celle con una
carica telegrafata che infligge danno doppio. Corpo, badge e colori distinguono
gli archetipi senza spostare decisioni di gameplay nel renderer.
`Shield`, `Poison`, `Thorns` e `Afterimage` hanno potenza e durata in impulsi.
L'HUD li mostra come `potenza:impulsi`; gli eventi dell'ultimo comando sono
conservati dalla stanza.
`Thorns` converte gli eventi di danno avversario in azioni reattive. Una queue
FIFO risolve le catene senza ricorsione e conserva l'ordine causale degli eventi.
Le definizioni dichiarano trigger, filtri, priorita e template degli effetti;
`Afterimage` usa la stessa pipeline osservando il solo `Moved` terminale, quindi
un attraversamento multi-cella lo attiva una volta.
I binding runtime aggiungono owner, potenza, cariche, durata e sorgente carta o
passiva senza duplicare le definizioni.
`Card_Definition` e `Card_Instance` compilano targeting, upgrade ed effect
template in normali `Action`. `Targeting_Spec` separa cast range e footprint:
Single, linee nelle otto direzioni, croci e quadrati 3x3 condividono clipping,
line of sight e blocker statici. La query raccoglie ID nemici stabili; il
renderer visualizza il risultato senza ricalcolare la geometria. `Shove`, `Dash`
e `Grappling Hook` aggiungono una `Movement_Query` alla stessa valutazione: la
preview mostra percorso, landing e blocker che compilazione e resolver
ricontrollano. `Deck_State`
conserva ownership, draw, mano, discard, exhaust, uno slot resolving ed energia in
array fissi; shuffle e reshuffle sono deterministici. Istanze `Combat` create
durante il fight usano ID monotoni, non entrano in ownership e spariscono a fine
stanza senza riciclare l'ID.
`play_card` salva il deck, paga e sposta la carta in `Resolving`; un'azione
rifiutata ripristina lo snapshot, mentre una accettata termina in discard o
exhaust. Gli effetti deck attraversano lo stesso resolver delle altre mutazioni.
`Refocus` e la frontiera manuale della mano: conserva le carte Retain, exhausta
le Ethereal, scarta le altre, concede un pulse nemico e solo dopo pesca il refill.
Fra stanza e mappa, `Run_Phase.Reward` offre tre definizioni distinte tramite un
RNG dedicato e pesi di rarita. Soltanto la scelta confermata crea una nuova
`Card_Instance`; skip, indice invalido e deck pieno non consumano ID. Scelta e
Skip passano direttamente a `Choose_Path`. Entrare in un nodo Shop usa un terzo
RNG, prezzi interi e copie staged del deck per acquisto, upgrade e rimozione;
fallimenti non modificano oro, ID o random state. Rest, Event e Treasure
mantengono payload deterministici separati, richiedono una sola scelta e vengono
completati esplicitamente con Continue.
La mano compatta a ventaglio, hover e drag sono stato di presentazione: durante
il trascinamento il renderer interroga `evaluate_card_targeting` per ogni anchor
e per la cella puntata. La compilazione riesegue la stessa valutazione autorevole,
incluso il percorso di movimento, prima della giocata.
Durante `Combat` e `Loot`, i drop entro distanza Chebyshev tre vengono raccolti
tramite normali `Action`, anche quando si trovano sopra trappole, ostacoli o
uscita. Oro e cura vengono assegnati subito dalla simulazione autorevole; gli
eventi prodotti dal comando alimentano poi la presentazione.
Prima di eseguire un comando accettato viene catturato uno snapshot della stanza;
dopo la risoluzione ne viene catturato un secondo per i valori terminali. La
`Room` risolve sincronicamente l'intera azione, mentre il renderer riproduce gli
eventi in una timeline FIFO sulla copia presentazionale. Movimento, danno,
status, mano, energia, sconfitte e loot restano nello stesso ordine causale senza
rallentare o modificare la simulazione. Gli ingressi intermedi, le trappole e i
grid object pericolosi hanno cue distinti, cosi il replay conserva l'ordine
`Movement -> Trigger -> Damage`.
Durante la timeline, il primo nuovo comando discreto viene conservato in un
buffer di capacita uno; gli input successivi vengono scartati. Quando la timeline
torna idle, il comando viene estratto e validato di nuovo contro la `Room`
autorevole. Drag, click e preview del targeting spaziale sono sospesi mentre lo
snapshot e indietro, per evitare di confrontare il mouse con due stati diversi.
Le transizioni verso `Reward`, `Victory` e `Defeat` vengono mostrate soltanto
dopo l'ultimo cue. Restart, cambio stanza e cambio schermata svuotano timeline e
buffer. Il contratto completo e in
[Presentation Timeline](PRESENTATION_TIMELINE.md).
I comandi turn-based restano edge-triggered: tenere premuto un tasto non genera
repeat e non riempie il buffer. A vita zero, un overlay `Defeat` separa
chiaramente lo stato terminale da un blocco dell'input e offre un restart esplicito.
La scena viene prima disegnata su un canvas virtuale `960x540`, poi adattata
alla finestra reale secondo la modalita di scaling selezionata.

La griglia e interamente bidimensionale: ogni cella vive sullo stesso piano e
possiede soltanto coordinate `(x, y)`. La sensazione di profondita deriva dalla
proiezione isometrica e dall'ordine di disegno, non da quote o livelli verticali.

## Generazione della rotta

La rotta e un grafo diretto aciclico organizzato in livelli:

- un solo nodo iniziale e un solo boss finale;
- due o tre nodi per ogni livello intermedio;
- esattamente un nodo speciale per livello intermedio e almeno un nodo con
  stanza;
- ciclo deterministico `Shop`, `Rest`, `Event`, `Treasure` con offset dal seed;
- archi soltanto verso il livello immediatamente successivo;
- massimo tre uscite per nodo e nessun arco duplicato;
- ogni nodo generato e raggiungibile dall'inizio e conduce verso il boss.

Il generatore Xoshiro usa uno stato locale inizializzato da seed. Non modifica il
generatore casuale globale: stesso seed e stessa configurazione producono sempre
la stessa rotta. `validate_run_map` ricontrolla tutte le invarianti prima che una
run venga accettata.

## Generazione delle stanze

Ogni `Run_Node` conserva un `room_seed` non nullo derivato da seed della run, ID,
profondita e tipo del nodo. Due stream separati alimentano layout ed encounter,
senza consumare gli RNG della rotta, del deck o delle ricompense.

`level.generate_room` sceglie spawn, uscita centrale e pareti interne entro un
numero massimo di tentativi. `level.validate_generated_room` usa BFS per
controllare bordo, clearance, distanza minima, percentuale calpestabile e
connessione di tutte le celle aperte. Dopo questa validazione,
`game.generate_room_blueprint` spende il budget del profilo in archetipi e
colloca trappole e ostacoli senza sovrapposizioni; un ostacolo viene mantenuto
soltanto se non disconnette lo spazio libero.

La stanza viene preparata fuori dallo stato corrente. Il commit distrugge la
vecchia `Room` prima del vecchio `Level`, trasferisce i nuovi owner e riaggancia i
puntatori presi in prestito. Un fallimento lascia invariati run e player. Il
contratto completo e in [Room Generation](ROOM_GENERATION.md).
