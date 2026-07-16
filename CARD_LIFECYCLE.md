# Card Lifecycle

Questa guida descrive il ciclo di vita autorevole delle carte durante un fight:
ownership, lifetime, zone, ID, `Exhaust`, effetti sul deck e replay nella timeline.
Definizioni e compilazione sono in [Card System](CARD_SYSTEM.md); il contenitore
completo in [Deck Runtime](DECK_SYSTEM.md); l'ordine visuale in
[Presentation Timeline](PRESENTATION_TIMELINE.md). La frontiera manuale della
mano e approfondita in [Hand Cycle](HAND_CYCLE.md).

## Indice

- [Due lifetime](#due-lifetime)
- [Zone del combattimento](#zone-del-combattimento)
- [Capacita](#capacita)
- [Identita e ID floor](#identita-e-id-floor)
- [Inizio e fine fight](#inizio-e-fine-fight)
- [Transazione di giocata](#transazione-di-giocata)
- [Effetti sul deck](#effetti-sul-deck)
- [Semantica sequenziale](#semantica-sequenziale)
- [Eventi e replay](#eventi-e-replay)
- [Carte dimostrative](#carte-dimostrative)
- [Invarianti](#invarianti)
- [Refocus, Retain ed Ethereal](#refocus-retain-ed-ethereal)
- [Limiti intenzionali](#limiti-intenzionali)

## Due lifetime

`Card_Instance.lifetime` distingue due categorie:

| Lifetime | Ownership | Fine fight |
|---|---|---|
| `Permanent` | presente in `Deck_State.owned` | resta nella run |
| `Combat` | esiste soltanto nelle zone runtime | viene eliminata |

Una carta temporanea puo usare una normale definizione collezionabile. Una
definizione `temporary_only`, come `Spark`, richiede invece lifetime `Combat` e
non puo essere aggiunta da reward, shop o `add_owned_card`.

Lifetime ed exhaust sono ortogonali:

- una permanente puo essere exhaustata fino alla fine del fight;
- una temporanea puo essere scartata e rimescolata;
- ogni temporanea viene comunque exhaustata quando viene giocata.

## Zone del combattimento

```text
Draw <-------- reshuffle -------- Discard
  |                                  ^
  | draw                             | discard effect
  v                                  |
Hand -------- play --------> Resolving
                              |      |
                              |      +----> Exhaust
                              +-----------> Discard
```

`Resolving` e una zona interna di capacita uno. Serve a rimuovere subito la carta
dalla mano senza inserirla nel discard prima dei suoi effetti.

Senza questa zona, una carta con `Draw` giocata a draw pile vuoto entrerebbe nel
discard, verrebbe rimescolata e potrebbe pescare se stessa. Con `Resolving`:

1. la carta libera uno slot della mano;
2. non appartiene ancora a draw, discard o exhaust;
3. gli effetti vengono risolti;
4. soltanto dopo entra nella destinazione finale.

## Capacita

```odin
MAX_OWNED_CARDS     :: 32
MAX_TEMPORARY_CARDS :: 16
MAX_COMBAT_CARDS    :: 48
MAX_HAND_CARDS      :: 8
```

Draw, discard ed exhaust hanno ciascuno capacita 48: nel caso limite tutte le 32
permanenti e le 16 temporanee possono trovarsi nella stessa zona. La mano resta a
otto e `Resolving` a uno.

`Deck_Rules.hand_size`, inizialmente cinque, e un target di refill iniziale. Non
e il limite runtime: `Draw` e `Create Card` possono portare la mano fino a otto.

## Identita e ID floor

Permanenti e temporanee condividono un solo `next_card_id` monotono.

- creare una temporanea consuma un ID;
- l'ID non viene recuperato a fine fight;
- reward e shop successivi possono lasciare buchi nella sequenza;
- un binding puo continuare a riferirsi senza ambiguita alla carta sorgente.

All'inizio del fight:

```odin
combat_card_id_floor = next_card_id
```

Ogni permanente deve avere ID minore del floor. Ogni carta `Combat` deve avere ID
maggiore o uguale al floor e minore di `next_card_id`. Fuori dal fight il floor e
zero.

## Inizio e fine fight

`begin_deck_combat`:

1. parte da un deck inattivo valido;
2. copia tutte le permanenti nel draw pile;
3. imposta il floor degli ID temporanei;
4. mescola con l'RNG locale del deck;
5. pesca fino a `rules.hand_size`;
6. committa soltanto uno stato finale valido.

`finish_deck_combat` svuota draw, hand, discard, exhaust e resolving. Conserva
`owned`, upgrade, RNG e `next_card_id`; per questo una permanente exhaustata torna
nel fight successivo, mentre una temporanea scompare senza riciclare il proprio ID.

## Transazione di giocata

`play_card` segue questo ordine:

1. valida stanza, fase, deck, carta e target;
2. compila una `Action` senza mutazioni;
3. verifica l'energia;
4. salva una copia del deck;
5. paga e sposta `Hand -> Resolving`;
6. risolve gli effetti autorevoli;
7. se l'azione e rifiutata, ripristina interamente il deck;
8. sposta `Resolving -> Discard` oppure `Resolving -> Exhaust`;
9. produce il pulse dei nemici, se il fight continua;
10. pesca il normale rimpiazzo, se possibile.

La destinazione e `Exhaust` quando la definizione ha `exhaust_on_play` oppure
l'istanza ha lifetime `Combat`; negli altri casi e `Discard`.

## Effetti sul deck

I tre effetti sono normali `Effect_Kind` e attraversano `resolve_action`.

### Draw Cards

`Draw_Cards(N)` pesca fino a N carte, fermandosi quando:

- la mano raggiunge otto;
- draw e discard sono entrambi vuoti.

Ogni carta pescata produce un `Card_Drawn`. Il reshuffle usa lo stesso RNG
deterministico del deck. Il rimpiazzo automatico della giocata avviene dopo il
pulse ed e separato dall'effetto.

### Discard Cards

`Discard_Cards(N)` scarta fino a N carte. M4A non apre una selezione modale: usa
deterministicamente la carta piu a sinistra, indice zero, dopo che la carta giocata
e gia in `Resolving`. Ogni scarto produce `Card_Moved(Hand, Discard)`.

### Create Card

`Create_Card(definition, N)` crea fino a N istanze `Combat` direttamente in mano.
Si ferma a mano piena, budget di 16 temporanee o ID esauriti. Non consuma RNG e
ogni successo produce `Card_Created` con ID, definizione, upgrade e lifetime;
`from_card_zone = .Count` rappresenta l'assenza intenzionale di una zona sorgente.

Tutte e tre le primitive usano semantica **up to N**: applicano quanto possibile
e riportano il numero effettivo in `Action_Report`.

## Semantica sequenziale

Il resolver conserva il contratto generale delle `Action`: gli effetti vengono
ricontrollati e applicati in ordine. Se un effetto successivo non e piu valido,
incrementa `skipped_effects`; non annulla quelli gia applicati.

Esempio: `Calculated Risk` compila `Draw 2`, poi `Discard 1`. Lo scarto vede la
mano risultante dalle pescate. Una futura carta `Damage + Create Card` potrebbe
applicare il danno e saltare la creazione se il budget temporaneo e esaurito.

La transazione di `play_card` garantisce rollback quando l'intera azione viene
rifiutata, non atomicita globale fra effetti gia accettati. Cambiare questa regola
richiedera un preflight sequenziale su copie staged di tutti gli stati coinvolti.

## Eventi e replay

La sequenza di una carta con effetto deck e:

```text
Card_Played       paga e riproduce Hand -> Resolving
eventi Action     Drawn, Moved o Created nell'ordine autorevole
Card_Moved        riproduce Resolving -> Discard/Exhaust
eventi pulse
Card_Drawn        eventuale rimpiazzo automatico
```

La timeline opera su `Room_Presentation.deck`, mai sul deck autorevole. Ogni
applicatore salva una copia locale, usa le stesse primitive del dominio, confronta
l'identita completa col payload e rollbacka su mismatch. Il draw riproduce anche
reshuffle e RNG; la create deve ottenere esattamente l'ID registrato.

## Carte dimostrative

| Carta | Costo | Effetto | Lifecycle |
|---|---:|---|---|
| `Battle Focus` | 1 | Draw 2 | Ethereal; exhaust on play |
| `Calculated Risk` | 1 | Draw 2, poi discard 1 | normale |
| `Spark Forge` | 1 | crea una `Spark` | normale |
| `Spark` | 0 | 2 danni, range Manhattan 1-2 | temporary only |

Le prime tre possono comparire in reward e shop. `Spark` ha peso e prezzo zero e
viene filtrata da ogni offerta persistente.

## Invarianti

`validate_deck_state` garantisce:

1. ogni permanente posseduta compare esattamente una volta nelle zone runtime;
2. nessuna temporanea compare in `owned`;
3. nessun ID e duplicato fra le cinque zone;
4. lifetime e intervalli ID rispettano `combat_card_id_floor`;
5. il numero di temporanee non supera 16;
6. il totale non supera 48;
7. contatori, energia e slot resolving sono coerenti;
8. fuori combat tutte le zone runtime e il floor sono vuoti.

Le primitive di creazione e movimento lavorano su una copia staged e committano
soltanto dopo questa validazione.

## Refocus, Retain ed Ethereal

La frontiera esplicita della mano e `Refocus`, non ogni pulse. Il comando ripulisce
la mano originale in ordine: Retain resta in mano, Ethereal entra in exhaust e
le altre carte entrano in discard. Produce poi un normale pulse e, se il fight
continua, pesca fino a `hand_size`. Contratto, eventi e casi terminali sono in
[Hand Cycle](HAND_CYCLE.md).

## Limiti intenzionali

Restano inoltre fuori da M4A:

- selezione interattiva della carta da scartare;
- effetti che exhaustano una carta scelta dalla mano;
- modificatori runtime di costo ed energia;
- animazioni spaziali fra pile;
- atomicita globale di azioni composte.

Lo smoke `odin run src -- --smoke-deck-flow` esercita create, lifetime temporaneo,
resolving, exhaust, timeline e HUD nello stesso flusso.
