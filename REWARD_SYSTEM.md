# Card Rewards

Questa guida descrive la fase post-stanza che offre tre carte e modifica il deck
in modo atomico prima di tornare alla scelta del percorso. L'economia completa e
documentata in [Deck Economy](DECK_ECONOMY.md); Shop e altri nodi della rotta in
[Special Nodes](SPECIAL_NODES.md).

## Indice

- [Lifecycle](#lifecycle)
- [Stato](#stato)
- [Generazione deterministica](#generazione-deterministica)
- [Scelta atomica](#scelta-atomica)
- [Skip e deck pieno](#skip-e-deck-pieno)
- [Presentazione](#presentazione)
- [Invarianti](#invarianti)
- [Limiti intenzionali](#limiti-intenzionali)

## Lifecycle

La ricompensa appartiene alla run, non alla stanza:

```text
In_Room -> Room.Complete -> Reward -> Choose_Path
```

`finish_room` chiude il runtime del deck, marca il nodo come completato e
incrementa `cleared_count`. Se il nodo ha uscite genera l'offerta e restituisce
`Run_Transition.Reward`. Il boss non ha uscite e passa direttamente a `Victory`.

Durante `Reward`, `available_nodes` restituisce una slice vuota. Soltanto una
scelta valida o Skip azzera l'offerta e abilita `Choose_Path`. Un eventuale Shop
si apre in seguito entrando in un vero `Node_Kind.Shop`.

## Stato

```odin
Card_Reward_State :: struct {
	choices:      [3]Card_Id,
	choice_count: int,
	source_node:  Node_Id,
}
```

L'offerta conserva definizioni, non istanze. Nessun ID persistente viene creato
finche il giocatore non conferma una scelta. `source_node` lega l'offerta al nodo
appena completato e impedisce di riutilizzarla dopo una transizione.

`Run_State` possiede inoltre `reward_random_state`. La `Room` non possiede e non
modifica questi dati.

## Generazione deterministica

Il reward usa uno xorshift64* locale inizializzato dal seed della run e da un
salt dedicato. Non condivide stato con:

- Xoshiro della generazione della mappa;
- xorshift64* dello shuffle del deck;
- xorshift64* dell'inventario dei nodi Shop;
- eventuale casualita grafica futura.

Cambiare quante carte vengono pescate non cambia quindi l'offerta successiva.

La generazione combina `Card_Rarity`, `reward_weight`, profondita e tipo del
nodo. Un sampling pesato senza rimpiazzo produce tre definizioni valide e
distinte. Lo stato RNG viene avanzato su una copia locale e committato soltanto
dopo aver costruito l'intera offerta.

Le definizioni `temporary_only` hanno peso zero e non sono eleggibili: vengono
create soltanto dagli effetti di combattimento descritti in
[Card Lifecycle](CARD_LIFECYCLE.md).

## Scelta atomica

`choose_card_reward(run, index)` segue questo ordine:

1. richiede `Run_Phase.Reward`;
2. valida stato reward e deck;
3. controlla indice e capacita massima;
4. applica `add_owned_card` a una copia staged del deck;
5. prepara una copia della run con reward azzerata e fase `Choose_Path`;
6. valida il nuovo stato completo;
7. committa deck, reward e fase.

La nuova `Card_Instance` riceve `next_card_id` soltanto al punto quattro. Una
seconda scelta fallisce per phase gate, quindi ownership e ID avanzano una volta
sola.

## Skip e deck pieno

`skip_card_reward` azzera l'offerta e passa a `Choose_Path` senza modificare deck,
ID o RNG del deck. Non genera offerte Shop e non avanza lo shop RNG.

Se `owned_count` ha raggiunto `MAX_OWNED_CARDS`, una scelta restituisce
`Deck_Full`. La fase resta `Reward`, l'offerta rimane visibile e il giocatore puo
usare `Skip`. Il sistema non sceglie automaticamente e non elimina una carta
posseduta.

## Presentazione

`reward_renderer.odin` riusa `draw_card_face` per mostrare le tre definizioni.
Le `Card_Instance` costruite dal renderer sono soltanto preview locali e non
entrano mai in `Deck_State`.

Mouse oppure `1`-`3` selezionano una carta. Il pulsante `Skip` e il tasto `S`
saltano l'offerta. L'hover solleva la carta e viene disegnato per ultimo; con il
deck pieno le carte sono attenuate e Skip resta disponibile.

## Invarianti

`validate_card_reward_state` controlla:

- RNG reward e shop non nulli;
- oro non negativo;
- deck valido e inattivo durante `Reward`;
- esattamente tre scelte durante la fase e stato azzerato fuori fase;
- assenza simultanea di un payload shop;
- `source_node` uguale al nodo corrente;
- nodo completato con almeno una uscita;
- definizioni valide e mutualmente distinte.

I test coprono 128 seed, pesi e rarita, indipendenza degli RNG, scelta one-shot,
indici invalidi, skip, deck pieno, rollback, sconfitta e boss finale.

## Limiti intenzionali

Non sono ancora implementati carte escluse o requisiti di unlock, reward con
upgrade gia applicati, reroll e relativa valuta, oppure l'animazione della carta
che entra nel deck. La rimozione e disponibile nello shop, ma non direttamente
dalla schermata Reward.
