# Deck Runtime

Questa guida descrive ownership delle carte, zone, shuffle, energia e transazione
di giocata. Le definizioni e la compilazione degli effetti sono in
[Card System](CARD_SYSTEM.md); cast range e footprint in
[Targeting System](TARGETING_SYSTEM.md); la risoluzione e in
[Action System](ACTION_SYSTEM.md); rarita, upgrade, rimozione e shop in
[Deck Economy](DECK_ECONOMY.md). Lifetime, exhaust e resolving sono approfonditi
in [Card Lifecycle](CARD_LIFECYCLE.md); Refocus, Retain ed Ethereal in
[Hand Cycle](HAND_CYCLE.md).

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
exhaust_pile   carte escluse fino alla fine del fight
resolving      al massimo una carta, mentre applica i propri effetti
```

`owned` e la sorgente persistente. Le zone runtime contengono tutte le permanenti
e fino a 16 istanze con lifetime `Combat`, create durante il fight. Le temporanee
non entrano mai in `owned`.

## Storage fisso

```odin
Deck_State :: struct {
	owned:         [32]Card_Instance,
	owned_count:   int,
		draw_pile:     [48]Card_Instance,
	draw_count:    int,
	hand:          [8]Card_Instance,
	hand_count:    int,
		discard_pile:  [48]Card_Instance,
		discard_count: int,
		exhaust_pile:  [48]Card_Instance,
		exhaust_count: int,
		resolving_card: Card_Instance,
		has_resolving_card: bool,
		energy:        i32,
		// regole, prossimo ID, ID floor, RNG e lifecycle
}
```

Pesca, discard, exhaust, create e shuffle non allocano memoria. Il budget massimo
e 32 permanenti piu 16 temporanee; ogni pila lunga puo contenere tutte e 48.

## Invarianti

`validate_deck_state` controlla:

- ID posseduti non nulli e univoci;
- definizione e upgrade validi per ogni istanza;
- `next_card_id` maggiore di ogni ID esistente;
- contatori entro la capacita degli array;
- energia compresa fra zero e massimo;
- mano non oltre `MAX_HAND_CARDS`; `hand_size` e soltanto il target di refill;
- durante `Combat`, ogni carta posseduta presente in esattamente una delle cinque zone;
- temporanee assenti da `owned`, univoche e comprese nell'intervallo ID del fight;
- massimo 16 temporanee e 48 carte runtime totali;
- slot resolving e relativo flag coerenti;
- fuori dal combattimento, zone temporanee vuote ed energia zero.

L'ultima proprieta impedisce sia duplicazioni sia carte perse durante un
reshuffle.

La validazione profonda e quadratica nel numero di carte e gira su ogni
primitiva tramite `deck_state_is_consistent`. I confini transazionali
(`begin_deck_combat`, `play_card`, `refocus_player_hand`, shop e mutazioni fuori
combattimento) chiamano sempre `validate_deck_state` per intero;
`-define:DECK_DEEP_VALIDATION=false` riduce le sole primitive interne ai
controlli strutturali economici di `deck_counts_are_valid`.

## Starter deck

Il deck iniziale contiene dieci istanze con ID da 1 a 10:

```text
1 Strike, 1 Arc Bolt, 1 Piercing Ray, 1 Shove, 1 Firebomb,
1 Guard, 1 Toxic Wave, 1 Thorn Coat, 1 Afterimage, 1 Dash
```

`add_owned_card` genera l'ID successivo e funziona soltanto fuori dal
combattimento. Questa regola permette a reward, Shop e Forgotten Armory di
aggiungere carte senza dover aggiornare le cinque zone runtime contemporaneamente.

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

Quando il fight termina, `finish_deck_combat` svuota draw, hand, discard, exhaust
e resolving e azzera energia e ID floor. `owned`, upgrade, prossimo ID e stato
RNG restano persistenti; gli ID consumati dalle temporanee non vengono riciclati.

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

Se anche il discard e vuoto, la pesca fallisce senza modificare lo stato. La carta
giocata resta in `Resolving` fino al termine dei propri effetti: un effetto `Draw`
non puo quindi rimescolare e pescare la carta che lo ha prodotto.

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
5. salva il deck, sottrae energia e sposta `Hand -> Resolving`;
6. chiama `resolve_action` con uno stato del deck ancora valido;
7. se il report e rifiutato ripristina la copia senza consumare risorse;
8. se accettato sposta `Resolving -> Discard/Exhaust` e registra gli eventi;
9. se il fight continua, esegue un solo pulse e pesca un rimpiazzo.

Target invalido, energia insufficiente o azione rifiutata non modificano energia,
zone o RNG. Se la carta conclude il fight, la transazione viene comunque
confermata, ma non viene prodotto un pulse aggiuntivo e le zone runtime vengono
poi svuotate.

## Eventi e report

`Card_Play_Report` conserva risultato, eventuale `Card_Compile_Error`, carta,
costo, energia prima/dopo, `Action_Report`, `Pulse_Report` e carta pescata.

I risultati `Played`, `Combat_Ended` e `Player_Defeated` indicano tutti una
transazione gia confermata. `card_play_was_committed` centralizza questo test.

`Room.recent_events` aggiunge:

- `Card_Played`, che paga e riproduce `Hand -> Resolving`;
- gli eventi degli effetti: `Card_Drawn`, `Card_Moved` o `Card_Created`;
- `Card_Moved`, che conclude `Resolving -> Discard/Exhaust`;
- un eventuale `Card_Drawn` di rimpiazzo dopo il pulse.

`Refocus` usa una transazione distinta: `Hand_Refocused`, un
`Card_Refocused` per ogni carta originale, un pulse e infine il refill. Retain,
Ethereal, energia e casi terminali sono descritti in [Hand Cycle](HAND_CYCLE.md).

Gli eventi conservano identita completa, lifetime e zone. La timeline parte da
una copia del deck e richiama le stesse primitive autorevoli; ogni mismatch
rollbacka la singola mutazione presentazionale.

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
Energia, draw, discard ed exhaust restano contatori separati ai lati. Le carte
temporanee mostrano `TEMP`; le policy della frontiera mostrano `RETAIN` o
`ETHEREAL`; quelle non pagabili vengono attenuate.

Durante una timeline la mano legge il deck presentazionale, non quello autorevole
gia risolto. Carta giocata e rimpiazzo cambiano quindi esattamente sui rispettivi
cue; `Pulse_Advanced` sincronizza l'energia rigenerata.

Con il mouse, la pressione salva soltanto `dragged_card_id`. Durante il drag il
renderer chiama `evaluate_card_targeting` per mostrare anchor raggiungibili,
percorso, footprint e blocker. Al rilascio `card_drop_target` usa la stessa query
per convertire la cella nel `primary_target`; `play_card` ricompila e decide se
commettere la transazione. Rilasciare sulla mano, fuori griglia o su un target
invalido annulla il drag senza mutazioni.

La carta trascinata resta centrata sotto il cursore sopra la mano. Quando il
cursore entra realmente su una cella della griglia, la carta viene nascosta fino
all'uscita dalla griglia: range, percorso e footprint rimangono cosi interamente
leggibili senza cambiare lo stato del drag.

`1`-`8` conserva il percorso rapido: carte self o senza target partono subito;
una carta spaziale salva `selected_card_id` nella presentazione e attende un
click su una cella. Il gameplay riceve sempre e soltanto `card_id` e `Target`;
lo stato hover/drag non entra in `Deck_State`.

`F` e il pulsante `REFOCUS` producono lo stesso comando bufferizzabile. Dopo un
commit riuscito hover, selezione e drag vengono azzerati; un rifiuto lascia
intatta la mano e non produce un pulse.

## Limiti intenzionali

Non sono ancora implementati selezione modale dello scarto, modificatori
dinamici di costo o rigenerazione, salvataggio serializzato, descrizioni complete
e animazioni spaziali fra le zone.

Shop, Rest, Event e Treasure sono nodi reali della rotta. Le relative schermate
mantengono hover, pagina e selezione nel renderer, mentre ownership e mutazioni
del deck restano in `Run_State`; il contratto e in
[Special Nodes](SPECIAL_NODES.md).
