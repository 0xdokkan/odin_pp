# Card System

Questa guida descrive il primo confine del deck building: definizioni immutabili,
istanze runtime e compilazione in [Action](ACTION_SYSTEM.md). La geometria
autorevole e in [Targeting System](TARGETING_SYSTEM.md); ownership, mano, pesca,
energia e giocata sono descritte in [Deck Runtime](DECK_SYSTEM.md). Percorsi,
spostamenti e hazard sono in [Movement System](MOVEMENT_SYSTEM.md).
Lifetime, zona resolving ed exhaust sono in [Card Lifecycle](CARD_LIFECYCLE.md);
Refocus, Retain ed Ethereal in [Hand Cycle](HAND_CYCLE.md).
Il catalogo aggiuntivo e le domande di bilanciamento sono in
[Content Pass](CONTENT_PASS.md).

## Indice

- [Tre livelli distinti](#tre-livelli-distinti)
- [Card Definition](#card-definition)
- [Card Instance](#card-instance)
- [Effect Template](#effect-template)
- [Movimento delle carte](#movimento-delle-carte)
- [Compilazione](#compilazione)
- [Dalla compilazione alla giocata](#dalla-compilazione-alla-giocata)
- [Targeting](#targeting)
- [Targeting Spec](#targeting-spec)
- [Upgrade](#upgrade)
- [Carte disponibili](#carte-disponibili)
- [Errori espliciti](#errori-espliciti)
- [Esempio](#esempio)
- [Limiti intenzionali](#limiti-intenzionali)

## Tre livelli distinti

```text
Card_Definition  dati condivisi da tutte le copie di una carta
Card_Instance    identita, upgrade e lifetime di una copia runtime o posseduta
Action           comando concreto costruito per la stanza corrente
```

La definizione non contiene stato per-run. L'istanza non contiene effetti gia
risolti. L'azione non resta nel mazzo: e un valore temporaneo consegnato al
resolver.

Questa separazione evita di duplicare nome e regole in ogni copia, ma permette
di distinguere due copie con upgrade o binding differenti.

## Card Definition

```odin
Card_Definition :: struct {
	id:              Card_Id,
	name:            string,
	rarity:          Card_Rarity,
	reward_weight:   u32,
	shop_base_price: i32,
	cost:            i32,
	temporary_only:  bool,
	exhaust_on_play: bool,
	retain_on_refocus: bool,
	ethereal:          bool,
	targeting:       Targeting_Spec,
	effects:         [MAX_CARD_DEFINITION_EFFECTS]Card_Effect_Template,
	effect_count:    int,
}
```

`CARD_DEFINITIONS` e indicizzato da `Card_Id`. `validate_card_definitions`
verifica che indice e ID coincidano, rarita, costo e metadati economici siano
validi, la specifica di targeting sia valida e ogni template sia rappresentabile.
Una definizione `temporary_only` deve avere peso e prezzo zero; tutte le altre
devono essere acquistabili. `retain_on_refocus` ed `ethereal` sono mutuamente
esclusive. La loro frontiera esplicita e descritta in [Hand Cycle](HAND_CYCLE.md).

Il costo e un dato della definizione. `compile_card_action` non lo paga perche e
una trasformazione pura; `play_card` salva il deck, paga prima del resolver e
ripristina l'intero snapshot se l'azione viene rifiutata.

## Card Instance

```odin
Card_Instance :: struct {
	id:            u32,
	definition_id: Card_Id,
	upgrade_level: i32,
	lifetime:      Card_Lifetime,
}
```

`id` identifica una singola copia e non puo essere zero. Serve soprattutto per
effetti persistenti: un `Reaction_Binding` installato da `Counter_Rune` conserva
la sorgente `{kind = .Card, id = instance.id}`.

L'upgrade valido e compreso fra zero e dieci. `Permanent` e il valore zero e
mantiene valide le istanze possedute; `Combat` identifica carte create nel fight.
Questo lifetime viene validato insieme alla definizione prima di costruire effetti.

## Effect Template

Un template contiene un normale `Effect_Kind`, un selettore del destinatario e
i dati necessari all'effetto:

```odin
Card_Effect_Template :: struct {
	kind:               Effect_Kind,
	target:             Card_Target_Selector,
	base_amount:        i32,
	amount_per_upgrade: i32,
	status:             Status_Kind,
	duration:           i32,
	reaction:           Reaction_Id,
	charges:            i32,
	priority_modifier:  i32,
	card_definition:    Card_Id,
	has_card_definition: bool,
	movement:           Card_Movement_Kind,
	movement_distance:  int,
}
```

`card_definition` e usato da `Create_Card` e deve essere accompagnato da
`has_card_definition = true`: in questo modo un campo omesso non crea
silenziosamente la carta con ID zero. I campi non pertinenti restano a zero.
`Move` usa il normale selettore di entita per il mover e deriva la destinazione
dalla query di targeting tramite `movement` e `movement_distance`.

`Draw_Cards`, `Discard_Cards` e `Create_Card` richiedono il selettore `Player` e
una quantita positiva. La create valida anche il `Card_Id` prodotto. In
compilazione diventano normali `Effect`, quindi report, ordine causale e timeline
non richiedono un secondo resolver dedicato al deck.

## Movimento delle carte

`Card_Movement_Kind` descrive come trasformare anchor e target primario in una
destinazione concreta:

| Kind | Mover e destinazione |
|---|---|
| `None` | il template non e un movimento spaziale |
| `Player_To_Anchor` | sposta il player sulla cella scelta |
| `Away_From_Player` | sposta il bersaglio oltre la sua posizione, lungo la linea dal player |
| `Adjacent_To_Player` | deriva la cella della linea adiacente al player; la query ne verifica la liberta |

Una definizione puo contenere al massimo un template `Move`. La validazione
richiede una combinazione coerente fra kind, selettore e distanza. Le carte
correnti compilano movimenti `Traverse`; attraversano quindi ogni cella della
linea e innescano gli hazard incontrati.

Se il movimento e l'unico template, come in `Dash`, deve risultare valido per
accettare la carta. In una carta composta, come `Shove` o `Grappling Hook`, la
query di movimento resta visibile ma un blocker non invalida il danno: durante
la risoluzione il solo effetto `Move` puo essere saltato. Questo sfrutta la
semantica ordinata e parziale dell'Action System.

## Compilazione

`compile_card_action` e una trasformazione, non una giocata completa:

1. verifica stanza e fase `Combat`;
2. valida ID e upgrade dell'istanza;
3. trova e ricontrolla la definizione;
4. ricostruisce una `Target_Request` dal target scelto;
5. esegue la stessa query geometrica usata dalla preview;
6. se esiste un template `Move`, deriva la destinazione ed esegue la stessa
   `Movement_Query` mostrata dalla preview;
7. raccoglie gli ID nemici della footprint in ordine stabile;
8. calcola quanti effetti concreti saranno necessari;
9. applica lo scaling dell'upgrade;
10. produce una sola `Action_Kind.Card`.

La funzione non modifica stanza, carta o player. Soltanto `resolve_action`
applica gli effetti risultanti.

## Dalla compilazione alla giocata

`play_card` aggiunge le responsabilita runtime che non appartengono al compilatore:

1. trova l'ID nella mano corrente;
2. compila target ed effetti;
3. verifica il costo contro l'energia disponibile;
4. salva il deck, paga e sposta la carta in `Resolving`;
5. risolve l'azione e rollbacka il deck se viene rifiutata;
6. sposta la carta in discard o exhaust;
7. esegue un pulse e pesca un rimpiazzo se il fight continua.

Una carta rifiutata lascia invariati energia, mano, draw, discard e stato RNG.

## Targeting

I selettori implementati sono:

| Selettore | Destinatario concreto |
|---|---|
| `Chosen_Entity` | entita scelta nel `Target` primario |
| `Player` | `PLAYER_ENTITY` |
| `Each_Enemy` | un effetto per ogni ID nemico corrente |
| `Each_Affected_Enemy` | un effetto per ogni ID nemico nella footprint |

Il target primario resta nell'azione e viene validato di nuovo dal resolver.
Gli effetti ad area copiano ID stabili, non indici della dynamic array.

Per un template `Move`, il selettore identifica invece l'entita spostata. La
destinazione non viene inventata come target cella secondario: viene derivata da
anchor e `Card_Movement_Kind`, conservando distinti la scelta del giocatore e il
risultato dello spostamento.

Un'azione puo contenere al massimo `MAX_ACTION_EFFECTS`, oggi 32 come
`MAX_ENEMIES_PER_ROOM`. Una compilazione che richiederebbe piu effetti restituisce
`Too_Many_Effects` prima di creare una carta parziale.

Il mouse costruisce una `Target_Request` dalla cella puntata e usa
`evaluate_card_targeting`. Una carta `Opponent` richiede un nemico sull'anchor,
una carta `Walkable_Cell` produce un target cella e una carta con forma `None`
usa il target implicito dichiarato. La compilazione riesegue la stessa query e
resta l'autorita finale.

## Targeting Spec

```odin
Targeting_Spec :: struct {
	rule:                   Target_Rule,
	cast_range:             Targeting_Range,
	shape:                  Target_Shape,
	radius:                 int,
	requires_line_of_sight: bool,
	stops_on_wall:          bool,
	stops_on_actor:         bool,
}
```

`cast_range` limita la posizione dell'anchor; `shape` e `radius` costruiscono la
footprint colpita. Minimo e massimo del cast range sono inclusivi. Manhattan
produce un rombo, Chebyshev un quadrato con diagonali.

`Single`, `Line`, `Cross` e `Square` sono implementate. Le linee accettano le
otto direzioni ortogonali e diagonali perfette; Cross costruisce centro e bracci;
Square con raggio 1 costruisce un'area 3x3. Bounds, blocker statici, corner
squeeze, clipping, actor stop e significato dei campi della query sono descritti
in [Targeting System](TARGETING_SYSTEM.md).

## Upgrade

La quantita concreta e:

```text
base_amount + amount_per_upgrade * upgrade_level
```

La validazione calcola anche il valore al livello massimo usando `i64` e rifiuta
definizioni che potrebbero superare `i32`. Durata, cariche e costo non scalano
ancora con l'upgrade.

## Carte disponibili

| Carta | Rarita | Costo | Anchor e forma | Effetto base |
|---|---|---:|---|---|
| `Strike` | Common | 1 | avversario, Manhattan 1, Single | 3 danni, +1 per upgrade |
| `Arc_Bolt` | Common | 2 | avversario, Manhattan 1-3, Single, LoS | 3 danni, +1 per upgrade |
| `Piercing_Ray` | Uncommon | 2 | cella, Chebyshev 1-5, Line | 2 danni a ogni nemico attraversato, +1 per upgrade |
| `Cross_Slash` | Uncommon | 2 | cella, Manhattan 1-3, Cross raggio 1 | 2 danni a ogni nemico nella croce, +1 per upgrade |
| `Firebomb` | Rare | 2 | cella, Chebyshev 1-3, Square raggio 1 | 2 danni a ogni nemico nel 3x3, +1 per upgrade |
| `Guard` | Common | 1 | player, None | Shield 3 per 3 pulse |
| `Toxic_Wave` | Rare | 2 | implicito, None | Poison 1 per 3 pulse a ogni nemico |
| `Thorn_Coat` | Uncommon | 1 | player, None | Thorns 1 per 3 pulse |
| `Afterimage` | Uncommon | 1 | player, None | Afterimage 1 per 4 pulse |
| `Counter_Rune` | Rare | 1 | player, None | Retain; due contraccolpi, durata 4 pulse |
| `Battle_Focus` | Rare | 1 | player, None | Ethereal; pesca 2, poi exhaust |
| `Calculated_Risk` | Uncommon | 1 | player, None | pesca 2, poi scarta la carta piu a sinistra |
| `Spark_Forge` | Uncommon | 1 | player, None | crea una `Spark` temporanea |
| `Spark` | temporary only | 0 | avversario, Manhattan 1-2, Single | 2 danni, +1 per upgrade; exhaust on play |
| `Shove` | Common | 1 | avversario o oggetto, Manhattan 1, Single | 1 danno, +1 per upgrade; spinta di 1 cella |
| `Dash` | Uncommon | 2 | cella, Chebyshev 1-3, Line, LoS | attraversa la linea fino all'anchor |
| `Grappling_Hook` | Rare | 2 | avversario, Chebyshev 2-4, Line, LoS e actor stop | 1 danno, +1 per upgrade; trascina adiacente al player |
| `Heavy_Blow` | Common | 2 | avversario adiacente, Single | 5 danni, +1 per upgrade |
| `Venom_Needle` | Common | 1 | avversario, Chebyshev 1-3, Single, LoS | 1 danno, +1 per upgrade; Poison 1 per 3 pulse |
| `Caustic_Bloom` | Uncommon | 2 | cella, Chebyshev 1-3, Square raggio 1 | Poison 2, +1 per upgrade, per 2 pulse ai nemici nel 3x3 |
| `Purifying_Guard` | Uncommon | 1 | player, None | Shield 2, +1 per upgrade, per 3 pulse; rimuove Poison se presente |
| `Volatile_Study` | Rare | 2 | player, None | Ethereal; crea 1 `Spark`, pesca 1 + upgrade, poi exhaust |

La mano in basso sovrappone le carte e ne lascia visibili soltanto le testate.
L'hover solleva una carta; il drag la porta sul campo e mostra cast range,
percorso di targeting, footprint, percorso di movimento, landing e blocker. Il
rilascio costruisce il target primario e chiama `play_card`; un drop invalido non
paga, non scarta e non avanza il pulse. `1`-`8` resta la scorciatoia da tastiera:
le carte `None` partono subito, quelle spaziali restano selezionate in attesa di
una cella.

## Errori espliciti

Il compilatore restituisce `Card_Compile_Error`, fra cui:

- `Invalid_Phase`;
- `Invalid_Instance`;
- `Unknown_Definition`;
- `Invalid_Target`;
- `Target_Out_Of_Range`;
- `Target_Blocked`;
- `No_Effects`;
- `Too_Many_Effects`.

Un enum diagnostico consente a UI, test e log di distinguere una selezione
sbagliata da un limite strutturale.

## Esempio

```odin
enemy := enemy_entity(room.enemies[0].id)
strike := Card_Instance{
	id = 101,
	definition_id = .Strike,
	upgrade_level = 2,
}
action, err := compile_card_action(&room, strike, entity_target(enemy))
if err == .None {
	report := resolve_action(&room, &action)
	// Strike +2 produce un singolo effetto Damage(5).
}
```

Per una giocata completa si usa invece `play_card`, che produce il pulse una sola
volta soltanto se la carta e stata accettata.

## Limiti intenzionali

Non sono ancora implementati:

- selezione interattiva della carta da scartare;
- modificatori runtime di costo e rigenerazione;
- coni, rotazioni libere delle footprint e proiettili persistenti;
- upgrade di durata, cariche o costo;
- caricamento delle definizioni da file;
- descrizione completa degli effetti e tooltip nella UI.

Le ricompense sono descritte in [Card Rewards](REWARD_SYSTEM.md); rarita,
upgrade e modifica persistente del deck in [Deck Economy](DECK_ECONOMY.md).
