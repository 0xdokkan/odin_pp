# Action System

Questa guida descrive il percorso seguito da una decisione di gameplay prima
che modifichi lo stato della stanza. Status ed eventi sono descritti in
[Status And Event System](STATUS_SYSTEM.md); le catene reattive in
[Reaction Queue](REACTION_SYSTEM.md); pianificazione e telegraph dei nemici in
[Enemy Intent System](ENEMY_INTENT_SYSTEM.md); cast range e footprint in
[Targeting System](TARGETING_SYSTEM.md).

## Indice

- [Pipeline](#pipeline)
- [Riferimenti stabili](#riferimenti-stabili)
- [Target primario](#target-primario)
- [Effetti](#effetti)
- [Validazione](#validazione)
- [Ordine e risoluzione parziale](#ordine-e-risoluzione-parziale)
- [Scheduler degli impulsi](#scheduler-degli-impulsi)
- [Flussi attuali](#flussi-attuali)
- [Compilazione delle carte](#compilazione-delle-carte)
- [Limiti intenzionali](#limiti-intenzionali)

## Pipeline

```text
Input / IA / Trigger
        |
        v
Costruzione Action
        |
        v
Validazione source + target + effetti
        |
        v
Applicazione ordinata degli Effect
        |
        v
Action_Report
        |
        v
Reaction queue: osserva gli eventi e risolve altre Action
        |
        v
Scheduler: decide se produrre un impulso dei nemici
```

Il resolver modifica lo stato e svuota la propria catena reattiva, ma non decide
quando comincia un nuovo turno. Questa separazione impedisce a un attacco nemico
di richiamare ricorsivamente l'intero turno dei nemici.

## Riferimenti stabili

`Entity_Ref` contiene una categoria e un ID:

```odin
Entity_Ref :: struct {
	kind: Entity_Kind,
	id:   u32,
}
```

Gli indici delle dynamic array non vengono conservati nelle azioni. Quando un
nemico muore, `unordered_remove` puo spostare l'ultimo nemico nello spazio appena
liberato. L'ID resta invece invariato e viene convertito nell'indice corrente
soltanto durante la risoluzione.

Il player e il sistema sono singleton con ID zero. Nemici e trappole ricevono
ID crescenti quando viene costruita la stanza.

## Target primario

`Target` e una tagged struct manuale: `kind` stabilisce quale payload e valido.

```odin
Target :: struct {
	kind:   Target_Kind,
	entity: Entity_Ref,
	cell:   grid.Position,
}
```

`Target_Rule` descrive come puo essere mirata un'azione:

| Regola | Significato |
|---|---|
| `None` | nessun target, per esempio `Wait` |
| `Self` | la sorgente deve mirare se stessa |
| `Player` | il target deve essere il player |
| `Opponent` | player contro nemico o nemico contro player |
| `Adjacent_Opponent` | come `Opponent`, ma a distanza Manhattan 1 |
| `Cell` | una cella interna alla griglia |
| `Walkable_Cell` | cella calpestabile senza ostacolo statico |

Il target primario rappresenta la scelta effettuata dal giocatore o dall'IA.
I destinatari degli effetti possono essere diversi. Questa distinzione serve a
carte ad area, rimbalzi, contraccolpi e abilita che danneggiano un nemico mentre
curano il player.

Per le carte spaziali il target primario e l'anchor scelta. La relativa query
geometrica produce separatamente percorso, footprint e ID dei nemici colpiti;
l'`Action` riceve poi effetti concreti verso quegli ID.

## Effetti

Un `Effect` e una singola mutazione richiesta:

```odin
Effect :: struct {
	kind:        Effect_Kind,
	target:      Entity_Ref,
	amount:      i32,
	destination: grid.Position,
	status:      Status_Kind,
	duration:    i32,
	reaction:    Reaction_Id,
	charges:     i32,
	priority_modifier: i32,
	binding_source: Reaction_Binding_Source,
}
```

Gli effetti disponibili sono:

- `Damage`: applica danno; la difesa del player viene calcolata qui;
- `Heal`: cura senza superare `max_health`;
- `Gain_Gold`: modifica l'oro persistente del player;
- `Move`: sposta un'entita su una destinazione valida;
- `Apply_Status`: applica o rinnova uno status con potenza e durata;
- `Remove_Status`: rimuove uno status esistente;
- `Add_Reaction_Binding`: installa una reazione runtime con potenza, cariche,
  durata, priorita e sorgente.

I campi non pertinenti al tipo di effetto restano al valore zero. Stacking,
durate e tick sono descritti nella guida dedicata agli status.

Ogni azione contiene un array fisso di `MAX_ACTION_EFFECTS`, oggi 32 come
`MAX_ENEMIES_PER_ROOM`. Non avvengono allocazioni durante la risoluzione e un
limite corrotto viene rifiutato.

## Validazione

L'ordine di validazione e:

1. stanza e fase modificabili;
2. sorgente ancora esistente;
3. target compatibile con `Target_Rule`;
4. almeno un effetto inizialmente applicabile, se l'azione ne contiene.

Un movimento contro un muro o un ostacolo viene rifiutato prima di costruire una
mutazione valida. Non cambia la stanza e non produce un pulse.

Il resolver non gestisce risorse di movimento. Il costo energia delle carte
appartiene alla transazione `play_card`, perche coinvolge anche mano e discard:
viene controllato prima del resolver e pagato soltanto dopo un
`Action_Report.accepted`.

## Ordine e risoluzione parziale

Gli effetti vengono applicati nell'ordine in cui sono stati aggiunti. Non esiste
rollback dell'intera azione.

Se il primo effetto uccide un nemico e il secondo tenta di colpire lo stesso ID,
il secondo viene registrato come `skipped_effects`. Gli effetti successivi ancora
validi continuano normalmente.

Questa semantica e intenzionale: permette sequenze come danno, cura e movimento
senza dover costruire un sistema transazionale complesso. `Action_Report` rende
esplicito cio che e stato realmente applicato.

## Scheduler degli impulsi

`resolve_action_once` applica una sola azione. `resolve_action` la avvolge con il
dispatch FIFO delle reazioni, ma non chiama mai `advance_combat_pulse`.

- `try_move_player` risolve un movimento o un bump attack e, se il fight
  continua, produce un impulso;
- `wait_player_turn` risolve una `Wait` vuota e poi produce un impulso;
- `use_player_ability` risolve tutti gli effetti dell'abilita e poi produce un impulso;
- `play_card` risolve una carta, ne conferma costo e cambio zona, poi produce un impulso;
- `advance_combat_pulse` risolve gli intenti committed, processa gli status,
  incrementa `pulse_count` e pianifica gli intenti successivi;
- `resolve_enemy_intents` trasforma ogni piano ancora valido in una normale
  `Action`, senza produrre impulsi annidati o ricalcolare il bersaglio; una
  `Charge` valida concatena un movimento e un attacco nello stesso pulse;
- loot e trappole usano il resolver, ma rispettano la fase e il flusso chiamante.

Una carta con cinque effetti dovra quindi produrre un solo impulso, non
cinque.

La UI invia questi comandi sul fronte di pressione del tasto, senza keyboard
repeat. Durante la timeline visuale il primo nuovo comando occupa un buffer di
capacita uno; viene estratto e validato nuovamente quando la presentazione torna
idle. Tenere premuto `WASD`, `Spazio`, `C` o `V` non produce comandi aggiuntivi.

Le reazioni sono a loro volta normali `Action`. Le definizioni dichiarative
trasformano un evento compatibile in effect template concreti, poi usano
`resolve_action_once` per evitare dispatch ricorsivi.

## Flussi attuali

### Attacco melee del player

```odin
action := make_action(
	.Attack,
	PLAYER_ENTITY,
	entity_target(enemy_entity(enemy.id)),
	target_rule = .Adjacent_Opponent,
)
add_effect(&action, damage_effect(enemy_entity(enemy.id), player.stats.attack))
report := resolve_action(room, &action)
```

Il bump attack usa lo stesso input del movimento: premere una direzione contro
un nemico adiacente non sposta il player, ma produce un pulse. L'intento del
nemico non viene ricalcolato dopo il colpo: se sopravvive puo ancora eseguire la
risposta gia dichiarata. Il costo tattico del melee base e questa risposta
committed.

### Movimento del player

```odin
action := make_action(
	.Move,
	PLAYER_ENTITY,
	cell_target(destination),
	target_rule = .Walkable_Cell,
)
add_effect(&action, move_effect(PLAYER_ENTITY, destination))
report := resolve_action(room, &action)
```

Durante `Combat` non esiste un contatore di spostamenti: ogni `Action.Move` valida
puo essere eseguita. Lo scheduler produce poi esattamente un pulse, percio
attraversare una cella resta una decisione tattica. Muri e ostacoli rifiutano il
comando senza pulse; il bump contro un'entita valida segue il flusso melee
descritto sopra.

### Carica del bruto

`Enemy_Intent.Charge` e un unico piano committed, ma la sua risoluzione puo
costruire due azioni ordinate nello stesso pulse:

```text
verifica dell'intero percorso
        |
        v
Action.Move verso la destinazione adiacente alla cella minacciata
        |
        v
Action.Attack con danno doppio, se il player occupa ancora quella cella
```

Se una cella del percorso e diventata occupata, nessuna delle due azioni viene
costruita e viene registrato `Move_Blocked`. Se il percorso e libero ma il player
ha lasciato la cella telegrafata, il bruto completa il movimento e registra
`Attack_Missed`. Movimento, danno, difesa, status e reazioni continuano cosi ad
attraversare lo stesso resolver usato dagli altri archetipi.

### Trappola

La trappola diventa la sorgente, il player e il target primario e il danno e un
effetto. Disarmare la trappola resta una responsabilita del trigger che costruisce
l'azione.

## Compilazione delle carte

`Card_Definition` non modifica direttamente una `Room`. Contiene nome, costo,
un `Targeting_Spec` e una lista fissa di massimo quattro
`Card_Effect_Template`. `Card_Instance` aggiunge identita stabile e livello di
upgrade.

```odin
instance := Card_Instance{
	id = 42,
	definition_id = .Counter_Rune,
	upgrade_level = 1,
}
action, err := compile_card_action(
	room,
	instance,
	entity_target(PLAYER_ENTITY),
)
```

Il compilatore valida fase, istanza e definizione, ricostruisce una
`Target_Request` ed esegue `evaluate_card_targeting`. La query verifica anchor,
cast range, allineamento, line of sight e footprint, poi raccoglie gli ID nemici
in ordine stabile. Il compilatore calcola gli upgrade, espande `Each_Enemy` o
`Each_Affected_Enemy` e rifiuta in anticipo azioni oltre la capacita di 32
effetti. Un binding prodotto da una carta conserva `Card_Instance.id` come
sorgente.

Il flusso completo implementato e:

1. la UI seleziona una carta;
2. la preview esegue la query per l'anchor puntata senza mutare la stanza;
3. `compile_card_action` riesegue la stessa query autorevole;
4. gli ID della footprint diventano effetti concreti;
5. si costruisce una sola `Action`;
6. il resolver restituisce un `Action_Report`;
7. `play_card` paga energia, sposta la carta e produce un solo impulso;
8. se il fight continua, pesca una carta di rimpiazzo.

Le semantiche di `Single`, linea a otto direzioni, croce, area 3x3, clipping e
blocker sono documentate in [Targeting System](TARGETING_SYSTEM.md). Il resolver
non ricalcola la geometria: riceve destinatari gia compilati e conserva la
propria responsabilita limitata alle mutazioni.

## Limiti intenzionali

Questo incremento non implementa ancora:

- coni, proiettili persistenti o rotazioni libere delle footprint;
- trigger aggiuntivi come `Status_Expired` o `Entity_Defeated`;
- raggruppamento parallelo di piu eventi appartenenti alla stessa azione.

Danno, status, carte, sconfitte e loot sono gia riprodotti dalla timeline FIFO
descritta in [Presentation Timeline](PRESENTATION_TIMELINE.md). Le estensioni
restano esterne al resolver.
