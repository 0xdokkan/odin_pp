# Deck Runtime

Questa guida descrive ownership delle carte, zone, shuffle, energia e transazione
di giocata. Le definizioni e la compilazione degli effetti sono in
[Card System](CARD_SYSTEM.md); cast range e footprint in
[Targeting System](TARGETING_SYSTEM.md); la risoluzione e in
[Action System](ACTION_SYSTEM.md); rarita, upgrade, rimozione e shop in
[Deck Economy](DECK_ECONOMY.md).

## Indice

- [Ownership e zone](#ownership-e-zone)
- [Storage fisso](#storage-fisso)
- [Invarianti](#invarianti)
- [Starter deck](#starter-deck)
- [Inizio e fine combattimento](#inizio-e-fine-combattimento)
- [Shuffle deterministico](#shuffle-deterministico)
- [Pesca e reshuffle](#pesca-e-reshuffle)
- [Energia per pulse](#energia-per-pulse)
- [Giocata atomica](#giocata-atomica)
- [Eventi e report](#eventi-e-report)
- [Ricompense](#ricompense)
- [Input e presentazione](#input-e-presentazione)
- [Limiti intenzionali](#limiti-intenzionali)

## Ownership e zone

`Player` possiede un `Deck_State`, perche le carte persistono fra le stanze della
run. La `Room` prende in prestito lo stesso player e non duplica il deck.

```text
owned          tutte le Card_Instance permanenti della run
draw_pile      carte non ancora pescate nel ciclo corrente
hand           carte attualmente giocabili
discard_pile   carte giocate in attesa del reshuffle
```

`owned` e la sorgente persistente. Le altre tre zone sono copie temporanee delle
stesse istanze e vengono ricostruite all'inizio di ogni combattimento.

## Storage fisso

```odin
Deck_State :: struct {
	owned:         [32]Card_Instance,
	owned_count:   int,
	draw_pile:     [32]Card_Instance,
	draw_count:    int,
	hand:          [8]Card_Instance,
	hand_count:    int,
	discard_pile:  [32]Card_Instance,
	discard_count: int,
	energy:        i32,
	// regole, prossimo ID, RNG e lifecycle
}
```

Pesca, discard e shuffle non allocano memoria. I limiti rendono esplicito il
budget del sistema e consentono di rifiutare un reward prima di corrompere le
zone.

## Invarianti

`validate_deck_state` controlla:

- ID posseduti non nulli e univoci;
- definizione e upgrade validi per ogni istanza;
- `next_card_id` maggiore di ogni ID esistente;
- contatori entro la capacita degli array;
- energia compresa fra zero e massimo;
- mano non oltre `hand_size`;
- durante `Combat`, ogni carta posseduta presente in esattamente una zona;
- fuori dal combattimento, zone temporanee vuote ed energia zero.

L'ultima proprieta impedisce sia duplicazioni sia carte perse durante un
reshuffle.

## Starter deck

Il deck iniziale contiene dieci istanze con ID da 1 a 10:

```text
1 Strike, 1 Arc Bolt, 1 Piercing Ray, 1 Cross Slash, 1 Firebomb,
1 Guard, 1 Toxic Wave, 1 Thorn Coat, 1 Afterimage, 1 Counter Rune
```

`add_owned_card` genera l'ID successivo e funziona soltanto fuori dal
combattimento. Questa regola permette a reward, Shop e Forgotten Armory di
aggiungere carte senza dover aggiornare tre zone attive contemporaneamente.

`upgrade_owned_card` modifica soltanto l'istanza identificata dal suo ID.
`remove_owned_card` compatta stabilmente `owned`, non ricicla ID e conserva
almeno `MIN_OWNED_CARDS`.

## Inizio e fine combattimento

`create_room` modifica il deck soltanto dopo aver validato interamente livello,
nemici, trappole e ostacoli.

Per una stanza `Combat`, `begin_deck_combat`:

1. copia `owned` nel draw pile;
2. mescola;
3. imposta energia al massimo;
4. pesca fino alla mano iniziale di cinque carte.

Quando il fight termina, `finish_deck_combat` svuota draw, hand e discard e
azzera l'energia. `owned`, upgrade, prossimo ID e stato RNG restano persistenti.

## Shuffle deterministico

Il deck usa uno stato xorshift64* locale. `create_run` lo deriva dal seed della
run; non viene toccato il generatore globale e non viene usato il generatore
della mappa.

Fisher-Yates sceglie ogni scambio con lo stato locale. Stesso starter deck, seed
e sequenza di pescate producono lo stesso ordine.

Tenere RNG separati evita che aggiungere una particella casuale cambi la mano
della stanza successiva.

## Pesca e reshuffle

`draw_card` estrae dalla fine del draw pile e inserisce in fondo alla mano. Se il
draw pile e vuoto:

1. tutto il discard viene spostato nel draw pile;
2. il discard viene azzerato;
3. il nuovo draw pile viene mescolato;
4. la pesca continua.

Se anche il discard e vuoto, la pesca fallisce senza modificare lo stato. Una
carta giocata entra nel discard prima della pesca di rimpiazzo, quindi puo
ricomparire subito quando era l'unica carta disponibile.

## Energia per pulse

Le regole iniziali sono:

```text
energia massima             3
rigenerazione per pulse     1
```

L'energia non viene riportata automaticamente a tre dopo ogni azione. In questo
gioco ogni azione provoca gia la risposta dei nemici: un reset completo renderebbe
quasi irrilevanti i costi.

Esempio con una carta da costo 2:

```text
3 -> paga 2 -> 1 -> pulse -> 2
2 -> paga 2 -> 0 -> pulse -> 1
terza giocata rifiutata; movimento o Wait produce un pulse e recupera 1
```

La rigenerazione avviene dentro `advance_combat_pulse`, quindi vale anche per
movimento, attesa e abilita debug. E sempre saturata al massimo.

## Giocata atomica

`play_card(room, card_id, target)` segue questo ordine:

1. valida stanza, fase e invarianti del deck;
2. trova l'ID nella mano;
3. valuta anchor, cast range e footprint, poi compila gli effetti senza mutazioni;
4. controlla l'energia disponibile;
5. chiama `resolve_action`;
6. soltanto se il report e accettato sottrae energia e sposta la carta;
7. registra gli eventi e raccoglie il loot vicino;
8. se il fight continua, esegue un solo pulse e pesca un rimpiazzo.

Target invalido, energia insufficiente o azione rifiutata non modificano energia,
zone o RNG. Se la carta conclude il fight, viene comunque pagata e scartata, ma
non viene prodotto un pulse aggiuntivo.

## Eventi e report

`Card_Play_Report` conserva risultato, eventuale `Card_Compile_Error`, carta,
costo, energia prima/dopo, `Action_Report`, `Pulse_Report` e carta pescata.

I risultati `Played`, `Combat_Ended` e `Player_Defeated` indicano tutti una
transazione gia confermata. `card_play_was_committed` centralizza questo test.

`Room.recent_events` aggiunge:

- `Card_Played`, prima degli eventi degli effetti;
- `Card_Drawn`, dopo il pulse e la pesca.

Entrambi conservano ID e `Card_Id`. La timeline parte da una copia del deck:
`Card_Played` paga e scarta nella copia, mentre `Card_Drawn` riproduce pescata ed
eventuale reshuffle con lo stato RNG catturato.

## Ricompense

Dopo una stanza non finale, `Run_Phase.Reward` presenta tre `Card_Id` distinti.
L'offerta non contiene `Card_Instance`: mostrare una carta non consuma un ID.

`choose_card_reward` applica `add_owned_card` a una copia staged soltanto dopo
aver validato fase, offerta, indice e capacita. Ownership e `next_card_id`
avanzano esattamente una volta, l'offerta viene azzerata e la run passa a
`Choose_Path`. `Skip`, indice invalido o deck pieno non modificano alcuna zona.
Dettagli e RNG sono in [Card Rewards](REWARD_SYSTEM.md).

Le modifiche offerte dai nodi speciali attraversano le stesse primitive:
`Rest` migliora gratuitamente una specifica istanza, mentre `Forgotten_Armory`
puo aggiungere la carta deterministica proposta dall'evento. Deck pieno, livello
massimo e ID esauriti lasciano la run invariata. Il lifecycle e documentato in
[Special Nodes](SPECIAL_NODES.md).

## Input e presentazione

La mano inferiore e parte del renderer, non di `Deck_State`. Le carte sono
sovrapposte e quasi nascoste quando inattive; hover e selezione ne sollevano una.
Energia, draw e discard restano contatori separati ai lati. Le carte non pagabili
vengono attenuate.

Durante una timeline la mano legge il deck presentazionale, non quello autorevole
gia risolto. Carta giocata e rimpiazzo cambiano quindi esattamente sui rispettivi
cue; `Pulse_Advanced` sincronizza l'energia rigenerata.

Con il mouse, la pressione salva soltanto `dragged_card_id`. Durante il drag il
renderer chiama `evaluate_card_targeting` per mostrare anchor raggiungibili,
percorso, footprint e blocker. Al rilascio `card_drop_target` usa la stessa query
per convertire la cella nel `primary_target`; `play_card` ricompila e decide se
commettere la transazione. Rilasciare sulla mano, fuori griglia o su un target
invalido annulla il drag senza mutazioni.

`1`-`8` conserva il percorso rapido: carte self o senza target partono subito;
una carta spaziale salva `selected_card_id` nella presentazione e attende un
click su una cella. Il gameplay riceve sempre e soltanto `card_id` e `Target`;
lo stato hover/drag non entra in `Deck_State`.

## Limiti intenzionali

Non sono ancora implementati exhaust, retain e carte ethereal, effetti che
pescano o scartano altre carte, modificatori dinamici di costo o rigenerazione,
salvataggio serializzato, descrizioni complete e animazioni spaziali fra le zone.
Cue e cambio di zona sincronizzato sono gia presenti.

Shop, Rest, Event e Treasure sono nodi reali della rotta. Le relative schermate
mantengono hover, pagina e selezione nel renderer, mentre ownership e mutazioni
del deck restano in `Run_State`; il contratto e in
[Special Nodes](SPECIAL_NODES.md).
