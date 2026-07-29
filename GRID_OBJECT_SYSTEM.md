# Grid Object System

Questa guida descrive gli oggetti persistenti sulla griglia. Le prime due
vertical slice separano due famiglie di comportamento:

- `Ice_Block` occupa una cella, blocca movimento e linea di vista, puo essere
  selezionato, danneggiato, spinto e distrutto;
- `Fire` e attraversabile e trasparente, ma infligge danno a player e nemici
  ogni volta che entrano nella sua cella.

Il sistema e collegato a [Action System](ACTION_SYSTEM.md),
[Targeting System](TARGETING_SYSTEM.md), [Movement System](MOVEMENT_SYSTEM.md),
[Presentation Timeline](PRESENTATION_TIMELINE.md) e
[Combat Telemetry](COMBAT_TELEMETRY.md).

## Indice

- [Autorita spaziale](#autorita-spaziale)
- [Definizione e istanza](#definizione-e-istanza)
- [Capability](#capability)
- [Storage e lifecycle](#storage-e-lifecycle)
- [Collisione e linea di vista](#collisione-e-linea-di-vista)
- [Targeting e Shove](#targeting-e-shove)
- [Danno e distruzione](#danno-e-distruzione)
- [Movimento e hazard](#movimento-e-hazard)
- [Fire persistente](#fire-persistente)
- [Eventi e presentazione](#eventi-e-presentazione)
- [Spawn manuale](#spawn-manuale)
- [Aggiungere un nuovo tipo](#aggiungere-un-nuovo-tipo)
- [Limiti intenzionali](#limiti-intenzionali)

## Autorita spaziale

`grid.Position` resta il tipo canonico per le coordinate. La `Room` non usa una
occupancy grid unica: conserva collezioni separate per attori, trappole,
ostacoli, oggetti e loot. Alle dimensioni correnti le ricerche lineari sono
piccole, deterministiche e piu semplici da validare di un indice duplicato.

Non esiste un generico `is_occupied`. Una cella con loot, trappola o `Fire` e
attraversabile, un `Ice_Block` no. Movimento, linea di vista, targeting e hazard
sono capability indipendenti, espresse da query specifiche.

## Definizione e istanza

```odin
Grid_Object_Kind :: enum {
	Ice_Block,
	Fire,
	Count,
}

Grid_Object_Definition :: struct {
	kind:                 Grid_Object_Kind,
	name:                 string,
	max_health:           i32,
	blocks_movement:      bool,
	blocks_line_of_sight: bool,
	targetable:           bool,
	damageable:           bool,
	movable:              bool,
	hazardous:            bool,
	hazard_damage:        i32,
}

Grid_Object :: struct {
	id:         u32,
	kind:       Grid_Object_Kind,
	position:   grid.Position,
	max_health: i32,
	health:     i32,
}
```

La definizione e immutabile e condivisa da tutte le istanze. L'istanza contiene
soltanto identita e stato runtime. `Ice_Block` ha 4 HP e tutte le capability
fisiche correnti abilitate; `Fire` ha 0 HP perche non e danneggiabile e dichiara
in definizione un danno hazard pari a 2.

`Entity_Kind.Object` identifica il dominio nel resolver; `Grid_Object_Kind`
identifica il contenuto. Nuovi contenuti non richiedono quindi un nuovo dominio
di entita.

## Capability

Le capability appartengono a `GRID_OBJECT_DEFINITIONS`, non sono booleani
liberamente modificabili su ogni istanza. Questo garantisce che due Ice Block
abbiano le stesse regole e concentra la validazione in un solo catalogo.

| Capability | Effetto |
|---|---|
| `blocks_movement` | rifiuta traverse e teleport sulla cella |
| `blocks_line_of_sight` | interrompe ray e footprint che richiedono LoS |
| `targetable` | consente le regole carta che includono oggetti |
| `damageable` | autorizza `Effect.Damage` |
| `movable` | autorizza `Effect.Move` e la relativa query |
| `hazardous` | abilita il trigger quando un attore entra nella cella |
| `hazard_damage` | quantita inviata alla pipeline condivisa del danno |

`damageable`, `movable` e `hazardous` vengono ricontrollati dal gameplay, non
soltanto dalla UI. Una preview non puo quindi autorizzare una mutazione che il
resolver non sa applicare. La validazione del catalogo richiede
`damageable == (max_health > 0)` e
`hazardous == (hazard_damage > 0)`.

## Storage e lifecycle

`Room.objects` e un array dinamico limitato da
`MAX_GRID_OBJECTS_PER_ROOM`. `next_object_id` assegna ID monotoni non nulli;
lookup e rimozione usano `object_index_at`, `object_index_by_id`,
`grid_object_at` e `remove_grid_object`.

`Room_Content.objects` riceve `Grid_Object_Spawn`. `create_room` rifiuta:

- kind sconosciuti o capacita superata;
- tile non calpestabili;
- overlap con spawn, uscita, ostacoli, nemici, trappole o altri oggetti.

La regola di spawn e intenzionalmente piu stretta della collisione runtime:
anche un `Fire` attraversabile non puo nascere sotto un attore. Entrarci deve
restare una transizione osservabile, non danno implicito durante
`create_room`.

`destroy_room` libera anche lo storage degli oggetti. La distruzione di un
oggetto durante il fight non modifica `Room_Phase`: soltanto i nemici vivi
determinano il passaggio da `Combat` a `Loot`.

## Collisione e linea di vista

Le due autorita condivise sono:

```odin
cell_blocks_movement(room, position)
cell_blocks_line_of_sight(room, position)
```

Entrambe comprendono tile e vecchi ostacoli, poi consultano la definizione
dell'eventuale oggetto. Player movement, AI, carica del Brute,
`Movement_Query`, `Walkable_Cell` e targeting non ricostruiscono piu questa
regola localmente.

Il movimento conserva un path blocker distinto dalla LoS. E importante: una
futura entita potrebbe essere attraversabile ma opaca, quindi riusare la query
di targeting per muoversi introdurrebbe un accoppiamento scorretto.

Un oggetto opaco e comunque selezionabile come endpoint se e targetable: blocca
cio che si trova dietro, non il ray che termina su di esso. `Fire` non blocca ne
movimento ne LoS. Il corner squeeze diagonale resta vietato.

## Targeting e Shove

`Entity_Ref{kind = .Object, id = ...}` rende l'oggetto indirizzabile da eventi
ed effetti. `entity_exists` ed `entity_position` risolvono l'ID contro la stanza.

La regola `Opponent_Or_Object` accetta un normale avversario oppure un oggetto
con `targetable = true`. `Shove` usa questa regola con range Manhattan 1:

```text
player -> Ice Block -> cella libera
          1 danno      Move di una cella
```

La preview, il drop della carta e `compile_card_action` condividono la stessa
`Target_Query_Result` e la stessa `Movement_Query`. Se la destinazione e
bloccata, il danno resta valido e il solo movimento viene saltato, come gia
avveniva contro i nemici.

Gli intenti nemici restano committed. Se un oggetto viene spinto sul percorso
di un movimento o di una carica gia pianificati, la struttura dell'intento resta
valida ma la risoluzione emette `Move_Blocked`. Se entra nella linea di tiro di
un arciere, l'attacco gia telegrafato emette `Attack_Missed`.

## Danno e distruzione

`Effect.Damage` accetta un oggetto soltanto quando la sua definizione e
`damageable`. Gli oggetti non ricevono difesa, shield, heal o status degli
attori. Quando gli HP raggiungono zero:

1. viene emesso `Damaged`;
2. l'istanza viene rimossa da `Room.objects`;
3. `Action_Report.objects_destroyed` viene incrementato;
4. viene emesso `Entity_Defeated`;
5. la fase combat resta invariata.

Gli eventi esistenti bastano per resolver, reazioni future e presentazione; non
serve un resolver parallelo dedicato all'Ice Block.

## Movimento e hazard

`query_entity_movement` accetta `.Object` soltanto se `movable`. La cella di
destinazione deve essere libera da geometria, qualunque altro grid object,
player e nemici. Anche un oggetto attraversabile per gli attori resta quindi un
`Object_Blocker` per un oggetto mobile: `Shove` non puo sovrapporre un Ice Block
a `Fire`. `set_entity_position` aggiorna l'istanza per ID e produce i normali
eventi `Movement_Step`/`Moved`.

Gli hazard vengono risolti soltanto per player e nemici dopo ogni ingresso.
`trigger_cell_hazard` prova prima la trappola e poi l'oggetto pericoloso, fermando
la sequenza se il mover muore. Un `Ice_Block` spinto sopra una trappola puo
condividerne la cella, ma non la disarma e non subisce danno.

## Fire persistente

`Fire` usa la stessa pipeline di danno di attacchi e trappole. Difesa e Shield
si applicano normalmente; morte del player, morte del nemico, loot e cambio di
fase restano responsabilita degli helper condivisi.

Il contratto temporale e deliberatamente stretto:

- il trigger avviene a ogni ingresso in una cella `Fire`, sia in `Combat` sia in
  `Loot`;
- un `Traverse` che attraversa piu celle di fuoco le risolve tutte in ordine;
- un `Teleport` controlla soltanto la cella di atterraggio;
- restare fermi, usare `Wait` o iniziare un pulse sopra il fuoco non causa un
  tick aggiuntivo;
- il fuoco non viene consumato, disarmato o rimosso dopo il trigger;
- `Fire` non e targetable, damageable o movable.

Questa policy conserva la catena esplicita
`Move -> Hazard_Triggered -> Damage`. Un futuro danno periodico dovra introdurre
una frontiera temporale propria invece di riusare implicitamente l'ingresso.

## Eventi e presentazione

`Room_Presentation` copia gli oggetti prima del comando. La timeline applica al
proprio snapshot movimento, danno e dissolvenza di distruzione anche se lo stato
autorevole ha gia rimosso l'istanza.

Il renderer mostra l'Ice Block come volume isometrico cyan. Quando e danneggiato
espone una barra HP; `Damaged` e `Entity_Defeated` usano lo stesso sistema di cue
degli attori. La distruzione visuale di un oggetto non forza la schermata Loot.

`Fire` usa una sagoma a strati con fiamma ed ember, senza volume solido.
`Hazard_Triggered` produce il cue `BURN`; il successivo `Damaged` o
`Damage_Absorbed` possiede la quantita numerica. La timeline non rimuove
l'oggetto quando applica il trigger, quindi lo snapshot rimane coerente con la
persistenza autorevole.

## Spawn manuale

Le stanze statiche della demo inseriscono gli oggetti tramite `Room_Content`.
Lo smoke deterministico prepara `Shove` contro un blocco adiacente:

```sh
odin run src -- --smoke-object
```

Il comando salva `odin_pp_ice_block.png`. La generazione procedurale non crea
ancora oggetti: prima dovra includerli nella connettivita e mantenere separato lo
stream RNG, per non cambiare nemici e trappole dei seed esistenti.

Lo smoke di `Fire` fa entrare il player nella cella, avanza la timeline fino al
cue e conserva la fiamma nello snapshot:

```sh
odin run src -- --smoke-fire
```

Il comando salva `odin_pp_fire.png`.

## Aggiungere un nuovo tipo

Per un altro oggetto fisico:

1. aggiungere il valore a `Grid_Object_Kind` prima di `Count`;
2. aggiungere la definizione allo stesso indice in
   `GRID_OBJECT_DEFINITIONS`;
3. decidere capability, HP e policy di overlap;
4. aggiungere il caso grafico in `draw_grid_object_body`;
5. aggiungere test per la combinazione di capability;
6. introdurre eventi o stato specifici soltanto se le primitive esistenti non
   descrivono il comportamento.

`Chest` richiedera stato chiuso/aperto, `Interact` e una ricompensa one-shot.
Questo comportamento non viene anticipato dentro gli oggetti esistenti.

## Limiti intenzionali

- nessuna occupancy grid o ECS;
- nessuno spawn procedurale di oggetti;
- nessun depth sort globale fra attori e volumi alti;
- nessuno status o reaction binding posseduto dagli oggetti;
- nessun trigger di trappola da oggetto;
- nessun tick periodico o propagazione del fuoco;
- nessuna interazione generica per bauli o leve.

Le slice correnti validano storage, capability, geometria, action resolver,
hazard persistenti, timeline e telemetria. Il baule sara il prossimo test per
stato e interazione con ricompensa.
