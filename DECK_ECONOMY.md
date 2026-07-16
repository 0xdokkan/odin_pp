# Deck Economy

Questo documento descrive la milestone M2: rarita e offerte pesate, mutazioni
persistenti delle istanze, economia dei nodi Shop e transazioni atomiche.

## Indice

- [Lifecycle](#lifecycle)
- [Metadati delle carte](#metadati-delle-carte)
- [Offerte pesate](#offerte-pesate)
- [Stream RNG](#stream-rng)
- [Mutazioni del deck](#mutazioni-del-deck)
- [Shop](#shop)
- [Transazioni](#transazioni)
- [Prezzi](#prezzi)
- [Presentazione](#presentazione)
- [Invarianti e test](#invarianti-e-test)
- [Limiti intenzionali](#limiti-intenzionali)

## Lifecycle

Reward e Shop sono due tappe indipendenti della run:

```text
Combat o Elite -> Reward -> Choose_Path
Choose_Path -> Shop -> Choose_Path
```

Il boss continua a passare direttamente da `In_Room` a `Victory`. Lo shop e un
vero `Node_Kind.Shop`: il payload viene costruito soltanto quando il player sceglie
quel nodo dalla rotta. Uscire dal vendor completa il nodo e conserva offerte
vendute e servizi usati; il pulsante sulla mappa permette di rientrare senza
reroll finche lo Shop resta il nodo corrente. Entrare nel nodo successivo azzera
il payload precedente. Il lifecycle comune dei nodi della rotta e descritto in
[Special Nodes](SPECIAL_NODES.md).

## Metadati delle carte

Ogni `Card_Definition` dichiara:

```odin
rarity:          Card_Rarity
reward_weight:   u32
shop_base_price: i32
```

Le rarita correnti sono `Common`, `Uncommon` e `Rare`. Il peso individuale
permette di differenziare due carte della stessa rarita senza inserire copie
fisiche nel pool. Il prezzo base appartiene alla definizione, mentre i
sovrapprezzi di profondita sono calcolati dallo shop.

`validate_card_definition` rifiuta rarita fuori enum e metadati incoerenti. Le
carte collezionabili richiedono peso e prezzo positivi; una definizione
`temporary_only` richiede entrambi a zero ed e esclusa dalle offerte. Reward e
shop conservano soltanto `Card_Id`: una preview non crea una `Card_Instance` e
non consuma `next_card_id`.

## Offerte pesate

`card_rarity_weights(kind, depth)` produce tre pesi interi. La profondita viene
limitata a `MAX_CARD_OFFER_DEPTH` prima dei calcoli; `Elite`, `Boss`, `Shop` ed
`Event` possiedono profili espliciti. I profili piu avanzati spostano peso da
Common verso Uncommon e Rare.

Il peso effettivo di una definizione e:

```text
rarity_weight(node kind, depth) * definition.reward_weight
```

`generate_weighted_card_choices` esegue sampling pesato senza rimpiazzo. Per
ogni slot somma il peso delle definizioni non ancora scelte, estrae un roll nel
totale e percorre il catalogo in ordine stabile. Le tre offerte sono quindi
distinte, deterministiche e indipendenti dall'ordine di rendering.

## Stream RNG

La run mantiene stream separati:

```text
Deck_State.random_state       shuffle e reshuffle
Run_State.reward_random_state ricompense
Run_State.shop_random_state   inventario del vendor
Run_Map seed                  topologia e seed delle stanze
```

Reward e shop copiano lo stato RNG in una variabile locale, costruiscono e
validano l'intera offerta, quindi committano lo stato avanzato. Un fallimento non
consuma random. Comprare, migliorare, rimuovere, uscire o rientrare nello shop
non estrae altri numeri.

## Mutazioni del deck

Le operazioni permanenti usano sempre l'ID dell'istanza:

```odin
upgrade_owned_card(deck, card_id)
remove_owned_card(deck, card_id)
```

Questo distingue due copie della stessa definizione. Entrambe richiedono un
deck valido e inattivo:

- upgrade conserva ID, ordine, conteggio, `next_card_id` e RNG;
- remove compatta stabilmente `owned`, azzera la coda e non ricicla l'ID;
- `MIN_OWNED_CARDS` impedisce di rendere impossibile il combattimento;
- `MAX_CARD_UPGRADE_LEVEL` limita la progressione numerica.

La successiva carta aggiunta usa comunque il vecchio `next_card_id`, anche se
un'istanza e stata rimossa.

## Shop

`Shop_State` appartiene a `Run_State` e usa storage fisso:

```odin
Shop_State :: struct {
    offers:       [3]Shop_Card_Offer,
    offer_count:  int,
    source_node:  Node_Id,
    upgrade_used: bool,
    removal_used: bool,
}
```

Ogni vendor generato offre tre carte distinte, un upgrade e una rimozione. I due
servizi sono one-shot per nodo; gli acquisti di carte marcano soltanto lo slot
relativo come `sold`. Rientrare nello stesso vendor conserva questi stati. Un
deck pieno disabilita gli acquisti ma lascia disponibili upgrade, rimozione e
`Continue`.

## Transazioni

Le operazioni economiche validano prima fase, shop, target, oro e limiti. Le
mutazioni del deck avvengono su una copia staged; soltanto un risultato valido
viene assegnato al player.

Un acquisto riuscito:

1. aggiunge una sola istanza con il vecchio `next_card_id`;
2. sottrae esattamente il prezzo;
3. marca l'offerta come venduta;
4. non modifica alcun RNG.

Upgrade e rimozione seguono lo stesso schema, poi marcano il rispettivo servizio
come usato. Fase errata, indice o ID invalido, slot venduto, oro insufficiente,
deck pieno/minimo e livello massimo restituiscono un risultato esplicito senza
modificare run, oro, ID o RNG.

La reward non prepara un vendor. `choose_card_reward` committa il nuovo deck,
azzera l'offerta e passa a `Choose_Path`; `Skip` usa lo stesso confine senza
cambiare il deck. Lo shop RNG avanza in seguito, e soltanto se l'ingresso in un
nodo Shop costruisce e valida tutte le sue offerte.

## Prezzi

I prezzi sono funzioni pure e intere:

- carta: `shop_base_price + min(depth, 12) / 3`;
- upgrade: `2 + int(rarity) + 2 * upgrade_level + min(depth, 12) / 4`;
- rimozione: `4 + min(depth, 12) / 4`.

Per la formula dell'upgrade le rarita `Common`, `Uncommon` e `Rare` valgono
rispettivamente `0`, `1` e `2`. La divisione intera crea scalini leggibili e il
clamp mantiene stabile la crescita oltre `MAX_CARD_OFFER_DEPTH`. I calcoli usano
intermedi `i64` e validano il cast finale a `i32`.

## Presentazione

`shop_renderer.odin` disegna una schermata full-canvas con:

- tre offerte e prezzo separato dal costo energia;
- rarita riconoscibile dal colore del prezzo;
- deck posseduto paginato, otto istanze per pagina;
- selezione per instance ID;
- controlli Upgrade, Remove, Continue e frecce pagina;
- stati sold, non acquistabile, servizio usato e livello massimo.

Lo stato hover, pagina e selezione resta in `main`; non entra in `Run_State`.
La mappa espone il comando per riaprire lo Shop soltanto dopo `leave_shop` e
finche il vendor del nodo corrente e ancora associato alla run.

## Invarianti e test

`validate_shop_state` impone esclusivita fra reward e shop, nodo sorgente di tipo
`Shop`, offerte distinte, prezzi ricalcolabili, deck inattivo e oro non negativo.
Il nodo e entrato ma non completato durante `Run_Phase.Shop`; dopo `leave_shop` e
completato e il payload puo restare in `Choose_Path` per la riapertura. Fuori da
queste due fasi, il payload deve essere azzerato.

I test coprono:

- tabelle dei pesi, profondita limitata e input invalidi;
- determinismo e separazione degli RNG;
- sampling senza rimpiazzo;
- upgrade e rimozione con definizioni duplicate;
- acquisto, slot sold, oro insufficiente e deck pieno;
- livello massimo, deck minimo e servizi gia usati;
- snapshot completi su ogni fallimento;
- leave, reopen e pulizia al cambio nodo;
- bounds, hit test e quattro pagine con 32 carte.

Verifica completa:

```sh
odin test src -all-packages -define:ODIN_TEST_THREADS=1
odin check src -vet -strict-style
odin run src -- --smoke-shop
```

## Limiti intenzionali

L'economia corrente non introduce unlock, pool per classe, reroll, sconti,
vendita di carte o offerte gia migliorate. Lo starter deck conserva tutte le
definizioni per mantenere compatibili gli smoke test della vertical slice. Rest
e Forgotten Armory riusano le stesse mutazioni permanenti senza spostarne
l'ownership; i loro contratti sono in [Special Nodes](SPECIAL_NODES.md).
