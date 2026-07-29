# Movement System

Questa guida descrive l'autorita condivisa per spostare player e nemici. Il
sistema separa la query pura del percorso dalla mutazione della `Room`, registra
ogni cella attraversata e risolve gli hazard nello stesso ordine causale. Gli
effetti che richiedono un movimento sono descritti anche in
[Action System](ACTION_SYSTEM.md); carte e preview in
[Card System](CARD_SYSTEM.md) e [Targeting System](TARGETING_SYSTEM.md).

## Indice

- [Modello](#modello)
- [Movement Query](#movement-query)
- [Traverse e Teleport](#traverse-e-teleport)
- [Blocker](#blocker)
- [Applicazione](#applicazione)
- [Hazard e ordine eventi](#hazard-e-ordine-eventi)
- [Interruzione del percorso](#interruzione-del-percorso)
- [Carte spaziali](#carte-spaziali)
- [Preview e compilazione](#preview-e-compilazione)
- [Smoke visuale](#smoke-visuale)
- [Reazioni al movimento](#reazioni-al-movimento)
- [Intenti committed e spostamento forzato](#intenti-committed-e-spostamento-forzato)
- [Capacita](#capacita)
- [Estendere il sistema](#estendere-il-sistema)

## Modello

Il movimento segue due fasi distinte:

```text
query_entity_movement(room, mover, destination, mode)
        |
        +--> percorso, destinazione, blocker oppure errore
        |
        v
Effect.Move
        |
        v
apply_movement_effect
        |
        +--> ingresso ordinato nelle celle
        +--> eventi di movimento
        +--> hazard immediati
```

`query_entity_movement` legge la stanza senza modificarla. La query e usata da
validazione, preview e compilazione. `apply_movement_effect` viene raggiunta dal
normale action resolver e modifica lo stato soltanto dopo che l'effetto e stato
accettato.

## Movement Query

```odin
Movement_Query :: struct {
	error:       Movement_Error,
	mode:        Movement_Mode,
	mover:       Entity_Ref,
	origin:      grid.Position,
	destination: grid.Position,
	cells:       [MAX_MOVEMENT_PATH_CELLS]grid.Position,
	count:       int,
	blocker:     grid.Position,
	has_blocker: bool,
}
```

`cells[0:count]` contiene le celle da attraversare, esclude l'origine e include
la destinazione. `movement_query_is_clear` richiede `error == .None`, un percorso
non vuoto entro capacita e nessun blocker.

Gli errori distinguono stanza o mover invalidi, destinazione uguale all'origine,
bounds, allineamento, capacita del percorso, blocker statico, blocker attore e
blocker oggetto. Quest'ultimo impedisce a un grid object mobile di sovrapporsi a
un altro oggetto anche quando la destinazione, come `Fire`, e attraversabile per
gli attori. Il fallimento e diagnostico: quando esiste una cella responsabile,
`has_blocker` e `blocker` permettono alla UI di mostrarla.

## Traverse e Teleport

`Movement_Mode` stabilisce quali celle devono essere validate:

| Modalita | Percorso | Geometria intermedia | Attori |
|---|---|---|---|
| `Traverse` | linea ordinata origin-destination | controllata per intero | ogni cella attraversata deve essere libera |
| `Teleport` | sola destinazione | ignorata | la cella di atterraggio deve essere libera |

`Traverse` accetta le otto direzioni ortogonali o diagonali perfette e condivide
il tracciamento lineare del targeting. Una pendenza non allineata fallisce con
`Path_Not_Aligned`; un percorso oltre `MAX_MOVEMENT_PATH_CELLS` con
`Path_Too_Long`. Anche il corner squeeze diagonale fra due blocchi ortogonali
viene rifiutato.

`Teleport` non autorizza un atterraggio illegale: bounds, tile, ostacoli e attori
sulla destinazione restano validati. Ignora invece muri, ostacoli, attori e
hazard fra origine e destinazione, perche quelle celle non vengono mai
attraversate. Una trappola o un `Fire` sulla landing viene comunque innescato.

## Blocker

I blocker statici sono tile non calpestabili, ostacoli della stanza e oggetti
con `blocks_movement`. La query dedicata `cell_blocks_movement` e distinta da
`cell_blocks_line_of_sight`: le due capability possono divergere. Gli attori
sono player e nemici vivi; il mover non blocca se stesso. Trappole e `Fire` non
sono blocker: la loro cella puo essere attraversata e viene risolta come hazard
dopo l'ingresso.

La query controlla prima la geometria statica e poi gli attori. Questa priorita
rende stabile l'errore anche se piu vincoli falliscono sullo stesso percorso.

## Applicazione

Un `Effect.Move` conserva target, destinazione e `movement_mode`. Il resolver
riesegue `query_entity_movement` durante la validazione dell'effetto; subito prima
dell'applicazione la query viene ricostruita e deve essere ancora valida.

Per `Traverse`, `apply_movement_effect` aggiorna la posizione una cella alla
volta. Ogni ingresso intermedio emette `Movement_Step`; l'ultimo emette `Moved`.
`Teleport` contiene una sola cella e produce quindi direttamente `Moved`.

Questa granularita non introduce turni aggiuntivi. Una carta con un percorso di
tre celle resta un solo comando e, se accettata, un solo pulse del player.

## Hazard e ordine eventi

Subito dopo ogni ingresso, `trigger_cell_hazard` controlla la cella corrente.
Funziona per player e nemici durante `Combat` e `Loot`. Risolve prima la
trappola, che viene disarmata, poi un eventuale oggetto `hazardous`, che resta
persistente. Entrambi usano la pipeline condivisa del danno, inclusi shield,
difesa, morte, drop e transizione di fase.

L'ordine per una singola cella e:

```text
Movement_Step oppure Moved
Trap_Triggered, se presente
  -> Damage_Absorbed / Status_Removed / Damaged / Defeat / Loot
Hazard_Triggered, se il mover vive ed e presente un oggetto hazardous
  -> Damage_Absorbed / Status_Removed / Damaged / Defeat / Loot
```

Ogni trigger e seguito immediatamente dai propri eventi di danno; la seconda
sorgente viene provata soltanto se il mover e ancora vivo. Il movimento e
osservabile prima della conseguenza della cella appena raggiunta. La
presentazione non deduce il trigger dal danno: usa `Trap_Triggered` per disarmare
la trappola e `Hazard_Triggered` per mostrare il cue dell'oggetto persistente.

`Fire` scatta solo all'ingresso: non produce tick con `Wait`, all'inizio del
pulse o mentre un attore resta fermo sulla cella. Un Traverse attraverso piu
fiamme le attiva tutte; un Teleport considera soltanto la landing.

## Interruzione del percorso

Un hazard puo uccidere il mover prima della destinazione. In quel caso il
percorso si ferma immediatamente e la posizione autorevole resta sull'ultima
cella raggiunta.

Se l'evento appena prodotto era un `Movement_Step`, viene promosso a `Moved`.
La sequenza mantiene cosi un evento terminale valido per la timeline e per le
reazioni, senza dichiarare celle mai attraversate.

## Carte spaziali

`Card_Effect_Template` usa un solo template `Move` per definizione e dichiara
come derivare la destinazione con `Card_Movement_Kind`:

| Kind | Destinazione |
|---|---|
| `Player_To_Anchor` | anchor scelta, con il player come mover |
| `Away_From_Player` | oltre il bersaglio, lungo la linea player-bersaglio |
| `Adjacent_To_Player` | ultima cella della linea adiacente al player |

Le carte correnti sono:

| Carta | Movimento | Composizione |
|---|---|---|
| `Shove` | spinge di una cella un nemico o Ice Block | 1 danno, poi movimento opzionale |
| `Dash` | attraversa 1-3 celle fino all'anchor | solo movimento, quindi percorso obbligatorio |
| `Grappling_Hook` | trascina il nemico fino a una cella adiacente al player | 1 danno, poi movimento opzionale |

Per `Shove` e `Grappling_Hook`, se il danno cambia lo stato oppure il movimento
risulta bloccato al momento della risoluzione, il resolver conserva gli effetti
gia applicati e registra il movimento in `skipped_effects`. `Dash` contiene solo
il movimento: un percorso bloccato rende invalida l'intera carta prima di
pagamento, cambio zona o pulse.

Tutti e tre usano attualmente `Traverse`. `Grappling_Hook` ferma anche la linea
di targeting sul primo attore, quindi non puo selezionare un nemico attraverso
un altro attore.

## Preview e compilazione

`evaluate_card_targeting` restituisce un `Card_Target_Evaluation` che contiene
sia `Target_Query_Result` sia, quando presente, `Movement_Query`. La stessa
funzione:

1. valida cast range, line of sight, footprint e target primario;
2. deriva il mover e la destinazione dal template;
3. esegue `query_entity_movement`;
4. conserva percorso, landing ed eventuale blocker;
5. traduce un movimento obbligatorio fallito in `Card_Compile_Error`.

Il renderer legge direttamente `evaluation.movement`: non ricostruisce il
percorso. Il drag mostra celle attraversate e landing in teal quando libere,
oppure percorso, landing e blocker in rosso quando il movimento fallisce.
`card_drop_target` e `compile_card_action` rieseguono la stessa valutazione, per
cui preview, drop e compilazione condividono il verdetto autorevole.

## Smoke visuale

![Percorso e landing di Dash sopra una trappola](odin_pp_spatial_targeting.png)

La scena deterministica si genera con:

```sh
odin run src -- --smoke-spatial
```

Il flag crea una `Dash` temporanea, la porta in drag verso una cella a distanza
tre e colloca una trappola armata sul percorso. Dopo tre frame salva
`odin_pp_spatial_targeting.png` e termina.

## Reazioni al movimento

`Movement_Step` esiste per percorso, hazard e animazione, ma non attiva
`Afterimage`. Il matcher osserva soltanto il `Moved` terminale. Un `Dash` di tre
celle concede quindi lo shield una volta, non tre. Gli hazard sono gia risolti
quando parte il dispatch reattivo: lo shield ottenuto da `Afterimage` non
protegge da trappole o fuoco dello stesso attraversamento, ma puo proteggere
dalla successiva risposta nemica. Se il mover muore, la promozione conserva il
terminale per replay e matching, ma la reazione non puo essere costruita per un
owner ormai inesistente.

## Intenti committed e spostamento forzato

Un intento nemico conserva l'origine pianificata. Spingere o trascinare il
nemico non modifica e non ricalcola il piano gia committed:

- `validate_enemy_intent_structure` controlla che il piano congelato sia
  strutturalmente valido per il pulse previsto;
- `validate_enemy_intent` richiede inoltre che `intent.origin` coincida con la
  posizione corrente;
- durante la risoluzione, un attacco stale produce `Attack_Missed`;
- un movimento o una carica stale produce `Move_Blocked`.

L'intento viene consumato senza retargeting. Se il combattimento continua, la
pianificazione del pulse successivo parte normalmente dalla nuova posizione.

## Capacita

`MAX_MOVEMENT_PATH_CELLS` coincide con `MAX_TARGETING_PATH_CELLS`, oggi 12.
`Event_Log` ha capacita 416. Lo stress envelope denso occupa 258 eventi; il test
spaziale massimo attraversa 12 trappole in 12 celle e produce 36 eventi senza
drop. Le celle `Fire` aggiungono un evento trigger e la normale sequenza del
danno a ogni ingresso. Restano 158 slot oltre l'envelope denso
(`258 + 158 = 416`), ma ogni futura composizione AoE + movimento + reazioni deve
dimostrare nuovamente il proprio massimo. Un overflow di `Action_Report` termina
esplicitamente il processo: quegli eventi pilotano le reazioni e non possono
degradare in modo fail-soft.

I test fissano inoltre un budget di 96 KiB per log e report singoli e 192 KiB
per `Card_Play_Report`; l'aumento di una capacita inline deve quindi affrontare
anche il costo di stack e copie, non soltanto far passare il conteggio eventi.

## Estendere il sistema

Per aggiungere una nuova forma di movimento:

1. definire se attraversa oppure salta le celle intermedie;
2. implementare la semantica nella query pura prima della mutazione;
3. mantenere lo stesso risultato per preview, drop, compilazione e resolver;
4. dichiarare l'ordine fra ingresso, hazard, danno, morte e reazioni;
5. decidere esplicitamente se il movimento deve rendere stale gli intenti
   committed;
6. aggiungere test per muri, corner squeeze, attori, hazard multipli, morte a
   meta percorso, reazioni ed envelope eventi;
7. far consumare al renderer gli eventi e la query, senza replicare regole.

Il sistema non implementa pathfinding, curve o knockback che aggira ostacoli.
`Traverse` e una linea validata; percorsi articolati devono essere modellati da
una query dedicata invece di concatenare mutazioni invisibili.
