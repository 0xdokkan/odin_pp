# Room Generation

Questo documento descrive la milestone M1 completata e i successivi incrementi
del director: seed per nodo, layout validato, encounter budget, composizioni
tattiche, modificatori della stanza, blueprint e installazione transazionale. La
[Definition of Done](ROADMAP.md#definition-of-done) raccoglie i criteri usati per
accettare l'incremento.

## Stato dell'incremento

Il codice corrente comprende:

- `Run_Node.room_seed`, derivato senza consumare gli RNG della run;
- `level.Room_Generation_Config`, `level.generate_room` e
  `level.validate_generated_room`;
- `game.Encounter_Generation_Config` e profili `Combat`, `Elite` e `Boss`;
- `game.Room_Blueprint`, che possiede layout e spawn prima del commit;
- stream RNG separati per layout ed encounter, con salt dedicati a composizione
  e modificatore;
- composizioni Polveriera, Scorta e Assalto, con coppie iniziali vicine;
- Demolitore a due fasi nei nodi Boss;
- Furnace deterministico con preavviso e vie di uscita statiche;
- preparazione e installazione della stanza senza mutare la run su un fallimento;
- test di determinismo, profili, ownership e 4096 combinazioni seed/profilo.

La suite completa passa, incluso lo stress su 4096 blueprint, e
`odin check src -vet -strict-style` termina con successo. Anche
`--smoke-generation` completa la verifica visuale della prima stanza e produce
`odin_pp_procedural_room.png`.

## Obiettivi

La generazione deve produrre una stanza che sia:

- deterministica rispetto a run, nodo e configurazione;
- valida prima di modificare lo stato persistente del player;
- attraversabile dallo spawn all'uscita;
- adatta a contenuti con budget crescente;
- indipendente dal renderer e dal generatore casuale globale.

Non rientrano in M1 editor visuali, stanze su piu piani, biome, decorazioni,
porte multiple o salvataggio del layout. Il primo boss a fasi e stato aggiunto
dal successivo incremento degli encounter, sopra lo stesso contratto del blueprint.

## Layering

La pipeline rispetta le dipendenze gia presenti:

```text
grid       coordinate, memoria contigua, accesso sicuro
  ^
level      tile, layout, query di raggiungibilita e validazione topologica
  ^
game       profilo del nodo, encounter budget, spawn e creazione della Room
  ^
main       composizione della demo e sostituzione atomica della stanza
```

`level` non conosce `Node_Kind`, nemici, statistiche, difficolta o reward. Riceve
solo una configurazione topologica e un seed, poi restituisce un `Level` valido o
un errore. `game` traduce `Combat`, `Elite` e `Boss` in profili e colloca i
contenuti sul layout gia validato. Il renderer continua soltanto a leggere
`Level` e `Room`.

## Contratto del seed

`derive_node_room_seed` assegna `Run_Node.room_seed` a partire da:

```text
run seed + node id + node depth + node kind + ROOM_SEED_SALT
```

La derivazione deve avere queste proprieta:

1. non consuma lo stato RNG della rotta, del deck o delle ricompense;
2. visitare o renderizzare altre schermate non cambia la stanza;
3. lo stesso input produce la stessa sequenza casuale;
4. cambiare il salt del generatore e una scelta esplicita;
5. layout ed encounter possono usare stream o salt separati.

`derive_room_stream_seed` applica poi `ROOM_LAYOUT_SEED_SALT` oppure
`ROOM_ENCOUNTER_SEED_SALT`. Separare gli stream impedisce che aggiungere una
scelta topologica al layout sposti automaticamente tutti gli archetipi
dell'encounter.

`ROOM_RECIPE_SEED_SALT` sceglie la composizione e `ROOM_MODIFIER_SEED_SALT`
sceglie il modificatore e la sua geometria. Queste derivazioni non consumano lo
stream del placement. Durante i pulse Furnace usa solo scadenze gia determinate:
non estrae nuovi valori casuali.

Il contratto e deterministico per la versione corrente del generatore. Prima di
salvare soltanto il seed su disco, la milestone di persistenza dovra aggiungere
una versione del formato e golden vector che rendano esplicite le migrazioni fra
algoritmi o versioni della libreria random di Odin.

## Pipeline

La costruzione avviene fuori dallo stato autorevole e viene committata soltanto
dopo la validazione completa.

### 1. Selezione del profilo

`room_generation_profile` sceglie una `Room_Generation_Profile` a partire dal
nodo. Il profilo contiene `level.Room_Generation_Config`, distanze riservate e
un `Encounter_Generation_Config` per nemici, trappole e ostacoli. Profondita e
tipo del nodo modificano il budget, ma non le regole fondamentali di validita.

### 2. Layout candidato

`level.generate_room` crea una griglia candidata con bordo di muri, spawn in uno
dei quattro angoli interni e uscita entro una regione configurabile attorno al
centro. Le pareti interne vengono applicate secondo `wall_density_percent`, fuori
dalle aree di clearance. Ogni tentativo usa lo stesso Xoshiro locale ed e
limitato da `max_attempts`; un fallimento restituisce
`Room_Generation_Error.Attempts_Exhausted`. Dimensioni, raggi e tentativi hanno
limiti massimi espliciti prima di qualsiasi prodotto o allocazione.

### 3. Flood fill o BFS

La validazione parte dallo spawn e visita soltanto celle calpestabili. La mappa di
visita serve a verificare almeno:

- uscita raggiungibile;
- numero minimo di celle disponibili;
- area riservata attorno allo spawn;
- assenza di regioni importanti isolate.

`level.validate_generated_room` richiede inoltre che tutte le celle calpestabili
appartengano alla stessa componente e restituisce conteggi, distanza spawn-uscita
ed errore diagnostico. La traversal usa storage legato alle dimensioni della
griglia, non cambia il layout e non dipende dall'ordine di rendering.
`min_spawn_exit_distance` usa la distanza Manhattan fra gli anchor; il report
conserva invece la distanza effettiva del cammino minimo trovata dalla BFS.

### 4. Encounter budget

Soltanto dopo un layout valido, `generate_room_blueprint` costruisce candidati
per i contenuti. `enemy_budget` determina quantita e costo relativo degli
archetipi, non posizioni hard coded. `Chaser` costa un punto, `Archer`, `Bomber`
e `Custodian` due, `Brute` tre e `Demolitionist` sei. Il director sceglie la
composizione prima del placement, riserva la coppia che la caratterizza e spende
il budget restante con archetipi ordinari, entro `max_enemies`.

| Composizione | Coppia garantita | Uso |
| --- | --- | --- |
| Polveriera / Powder Keg | Bomber + Chaser | Garantita nei Combat di profondita 0–1; selezionabile in seguito |
| Scorta / Escort | Custodian + Archer | Protezione di un alleato e priorita dei bersagli |
| Assalto / Assault | Brute + Chaser | Pressione ravvicinata e recupero dopo la carica |
| Demolitore / Demolitionist | Demolitionist + Bomber | Garantita nei nodi Boss |

Negli altri Combat e negli Elite la scelta fra le prime tre composizioni dipende
dal seed. Il Demolitore viene escluso dall'estrazione casuale degli archetipi e
compare esattamente una volta nella composizione Boss. Ha 30 HP e attacco base 2;
le sue due fasi sono gestite dal sistema degli intenti, senza cambiare il layout.

Le prime due unita sono adiacenti oppure allineate a distanza Manhattan 2, con
il collegamento libero da muri e ostacoli. Nella Scorta anche il successivo
placement degli oggetti preserva quel collegamento, cosi il Custode puo iniziare
con un alleato effettivamente raggiungibile dalla protezione. La selezione rispetta:

- distanza minima dallo spawn;
- uscita e celle riservate libere;
- cella calpestabile e non gia occupata;
- limiti massimi di `Room`;
- profili distinti per `Combat`, `Elite` e `Boss`.

Gli ostacoli vengono accettati soltanto se tutte le celle rimaste libere sono
ancora connesse; se il conteggio richiesto non e raggiungibile, il blueprint
fallisce invece di ridurre silenziosamente la difficolta. Statistiche, danno
delle trappole, budget e conteggi vengono ricalcolati dal validatore. Anche la
disponibilita di celle per l'intero budget dei contenuti viene verificata qui,
dove il profilo encounter e noto, non dal package `level`.

### 5. Oggetti e modificatore

Prima del commit, il placement aggiunge Barrel, Ice Block e Fire: tre oggetti
nei nodi Combat, quattro se la composizione e Polveriera, sei negli Elite e Boss.
La Polveriera iniziale contiene due barili, un blocco di ghiaccio e una fiamma.
Il placement preferisce collocare i barili entro due celle dal primo nemico e
completa gli altri oggetti usando i candidati disponibili. Riusa i candidati gia
mescolati dopo nemici e trappole, senza consumare altri valori RNG. Il controllo di
connettivita considera tutti gli oggetti come celle da evitare, incluso Fire,
cosi rimane un percorso senza danno da fuoco. Il blueprint possiede e valida
anche gli spawn degli oggetti.

Le stanze di profondita 0–1 e i nodi Boss hanno modificatore `Calm`. Negli altri
nodi il seed sceglie fra Calm e `Furnace`, mostrato insieme alla composizione
all'ingresso. Furnace sceglie una fila o colonna, al massimo 16 celle:

- spawn, uscita, muri e ostacoli fissi sono esclusi;
- ogni cella selezionata ha una via fuori dalla fila o colonna entro due passi
  nel layout iniziale, senza attraversare oggetti, fuoco o ostacoli;
- il controllo della via statica ignora gli attori: il loro movimento e gli
  oggetti spostati durante lo scontro possono cambiare le opzioni disponibili;
- se non esiste una linea adatta, il modificatore rimane Calm.

La prima fiammata scatta dopo due decisioni accettate del player. Infligge 3 danni
attraverso la normale pipeline a player, nemici e oggetti sulle celle segnate;
gli effetti di difesa e Shield restano validi. Puo quindi accendere un barile,
che riceve il proprio nuovo countdown di due decisioni. I comandi rifiutati non
avanzano la scadenza.

Dopo ogni fiammata trascorrono due impulsi di pausa e due di preavviso prima
della successiva. Le celle e la cadenza restano fisse, senza generare oggetti Fire
persistenti. L'evento `Room_Hazard_Triggered` precede gli eventi di danno; il
modificatore si disattiva quando il combattimento termina, anche se termina
durante un'azione del player.

`Room_Blueprint`, `Room_Content` e `Room` trasportano `encounter_kind` e
`modifier`. Il validatore ricalcola composizione e modificatore dal seed e
controlla la coppia, l'unicita del boss e gli spawn. `create_room` verifica anche
capacita, danno, scadenza, allineamento e celle uniche del modificatore prima di
iniziare il deck di combattimento; un payload invalido non consuma lo stato del
player.

### 6. Commit

La pipeline costruisce un `Room_Blueprint`, poi un `Prepared_Demo_Room` con copie
temporanee di `Player`, `Level` e `Room`. `install_prepared_demo_room` committa il
gruppo soltanto dopo la validazione completa. In caso di errore:

- la vecchia stanza resta valida finche la nuova non e pronta;
- player, vita, oro, deck e status persistenti non vengono modificati a meta;
- ogni allocazione temporanea viene liberata dal proprio owner;
- l'errore resta distinguibile da una stanza valida ma vuota.

## Ownership

`Level` possiede la memoria della propria `Grid(Tile)` e deve essere distrutto una
sola volta con `level.destroy`. `Room_Blueprint` possiede il `Level` generato e
gli array di spawn finche non vengono trasferiti. `Room` possiede gli array
dinamici di nemici, trappole, ostacoli e loot, ma prende in prestito `^Level` e
`^Player`.

Ne consegue questo ordine per una sostituzione:

1. trasferire il `Level` dal blueprint al contenitore preparato;
2. costruire la nuova `Room` contro `prepared.level_data` e `prepared.player`;
3. distruggere la vecchia `Room` prima del vecchio `Level`;
4. trasferire player e livello nelle destinazioni stabili;
5. riassegnare `Room.player` e `Room.level_data` alle destinazioni stabili;
6. installare la nuova `Room` e azzerare gli owner temporanei trasferiti.

Una grande assegnazione per valore di `Room` deve continuare a essere confinata
in un helper, per evitare la scalarizzazione osservata nella build della demo.

## Invarianti

Una stanza generata e accettabile soltanto se:

- dimensioni e capacita rispettano la configurazione;
- bordo, spawn e uscita hanno tile coerenti;
- esiste un solo spawn e una sola uscita;
- spawn e uscita sono distinti e connessi;
- tutte le posizioni sono entro i bounds;
- nemici, trappole e oggetti occupano celle consentite;
- composizione, statistiche, budget e modificatore corrispondono al seed;
- la coppia prevista ha un collegamento valido e il boss resta unico;
- le celle Furnace rispettano limiti, anchor e vie statiche di uscita;
- nessuna sovrapposizione vietata raggiunge `create_room`;
- l'area di sicurezza del player e libera;
- gli ID delle entita vengono assegnati da `Room`, non dal generatore;
- nessun RNG globale viene letto o modificato;
- un fallimento non muta lo stato persistente della run.

Il validatore deve essere utilizzabile nei test senza aprire una finestra.

## Test

I test mirati devono coprire:

- configurazioni minime, massime e invalide;
- determinismo dello stesso seed e divergenza fra nodi;
- raggiungibilita di spawn e uscita;
- area di sicurezza e assenza di overlap;
- budget e profili `Combat`, `Elite` e `Boss`;
- copertura delle tre composizioni, disposizione della coppia e unicita del boss;
- determinismo del modificatore e rifiuto di metadati alterati;
- preavviso, pausa, comandi rifiutati, danno a nemici e oggetti e fine combattimento;
- morte simultanea di player e ultimo nemico senza sovrascrivere `Defeat`;
- limite dei tentativi e cleanup sui fallimenti;
- sostituzione senza puntatori pendenti;
- stress test deterministico su 4096 combinazioni di seed, profondita e profilo.

Verifica completa:

```sh
odin test src -all-packages -define:ODIN_TEST_THREADS=1 -o:none
odin check src -vet -strict-style
```

Un test generativo deve stampare seed, nodo e profilo quando fallisce, cosi il
caso puo essere riprodotto direttamente invece di dipendere dall'ordine dei test.
