# Special Nodes

Questo documento descrive la milestone M3: distribuzione deterministica dei nodi
speciali, lifecycle dedicati, scelte atomiche e presentazione di `Shop`, `Rest`,
`Event` e `Treasure`.

## Indice

- [Lifecycle della run](#lifecycle-della-run)
- [Distribuzione nella rotta](#distribuzione-nella-rotta)
- [Ingresso transazionale](#ingresso-transazionale)
- [Shop](#shop)
- [Rest](#rest)
- [Event](#event)
- [Treasure](#treasure)
- [Risoluzione e Continue](#risoluzione-e-continue)
- [Atomicita e limiti](#atomicita-e-limiti)
- [Presentazione e controlli](#presentazione-e-controlli)
- [Invarianti](#invarianti)
- [Test e smoke](#test-e-smoke)
- [Limiti intenzionali](#limiti-intenzionali)

## Lifecycle della run

Una reward non apre piu automaticamente uno shop. Il percorso post-combattimento
e:

```text
Combat o Elite -> Reward -> Choose_Path
Boss -> Victory
```

Da `Choose_Path`, il nodo scelto determina la fase successiva:

```text
Combat, Elite, Boss -> In_Room
Shop                -> Shop -> Choose_Path
Rest                -> Rest -> risultato -> Continue -> Choose_Path
Event               -> Event -> risultato -> Continue -> Choose_Path
Treasure            -> Treasure -> risultato -> Continue -> Choose_Path
```

I nodi con combattimento costruiscono una `Room`. I nodi speciali non installano
un livello vuoto: costruiscono invece un payload appartenente a `Run_State` e
mostrano una schermata dedicata.

## Distribuzione nella rotta

La prima profondita contiene un solo nodo `Combat` e l'ultima un solo `Boss`.
Ogni livello intermedio contiene:

- esattamente un nodo speciale;
- almeno un nodo con stanza `Combat` o `Elite`;
- da due a tre nodi totali, secondo `Run_Map_Config`.

`special_node_kind_for_depth` sceglie il tipo speciale con un offset derivato dal
seed della run, poi percorre ciclicamente:

```text
Shop -> Rest -> Event -> Treasure -> Shop -> ...
```

L'offset cambia il primo tipo senza rompere il ciclo. Lo stesso seed e la stessa
profondita producono sempre lo stesso risultato. La lane speciale viene scelta da
uno stream Xoshiro locale separato; `validate_run_map` ricalcola il tipo atteso e
rifiuta layer senza speciale, con piu speciali o senza una stanza di
combattimento.

Ogni nodo conserva un `room_seed` derivato da seed della run, ID, profondita e
tipo. Nei nodi speciali viene usato per offerte ed eventi, senza consumare RNG di
deck o reward.

## Ingresso transazionale

`enter_node` accetta soltanto un ID presente fra le uscite del nodo corrente. Il
target non deve essere gia entrato o completato.

Prima di modificare `current_node`, fase o flag `entered`, l'ingresso prepara lo
stato necessario:

- `build_shop_state_for_node` per `Shop`, con una copia dello shop RNG;
- `build_rest_node_state` per `Rest`;
- `build_route_event_state` per `Event`;
- `build_treasure_node_state` per `Treasure`.

Soltanto un payload valido viene committato. Un errore lascia invariati player,
nodo corrente, RNG, payload e contatori della run.

## Shop

Lo shop e un vero `Node_Kind.Shop`. Entrarvi genera tre offerte distinte e
prezzate, piu un servizio di upgrade e uno di rimozione. Generazione, prezzi e
mutazioni permanenti sono descritti in [Deck Economy](DECK_ECONOMY.md).

`leave_shop`:

1. marca completato il nodo, se non lo era gia;
2. incrementa `cleared_count` una sola volta;
3. passa a `Choose_Path`;
4. conserva offerte vendute e servizi usati.

Finche il nodo Shop resta quello corrente, il pulsante sulla rotta puo chiamare
`open_shop` e riaprire lo stesso vendor senza reroll. Entrare nel nodo successivo
azzera il payload precedente.

## Rest

Un Rest offre una scelta one-shot fra recupero, upgrade gratuito di una carta e
abbandono.

### Recover

`heal_amount` vale il 30% della vita massima, con minimo uno. `safe_heal` usa
intermedi `i64` e limita il risultato a `max_health`. Recuperare a vita piena e
valido: l'esito viene risolto con `applied_amount` uguale a zero.

### Upgrade

L'upgrade riceve l'ID della specifica `Card_Instance`, non la definizione. Aumenta
il livello di una sola istanza e non costa oro. Carta assente, deck invalido o
`MAX_CARD_UPGRADE_LEVEL` lasciano il Rest irrisolto e non modificano il deck.

### Leave

Abbandonare registra `Special_Node_Outcome.Left` senza cambiare vita, oro o deck.

## Event

Il tipo di evento viene derivato da `Run_Node.room_seed` e da un salt dedicato.
La stessa run presenta quindi lo stesso evento indipendentemente dal rendering o
dalle pescate del deck.

Le formule usano `d = min(depth, MAX_CARD_OFFER_DEPTH)`, attualmente con limite
12:

| Evento | Scelta primaria | Scelta secondaria |
|---|---|---|
| `Blood_Offering` | paga il 20% della vita massima e ottiene `8 + 2*d` oro | rifiuta senza effetti |
| `Healing_Spring` | recupera fino al 25% della vita massima | imbottiglia e ottiene `4 + d` oro |
| `Forgotten_Armory` | aggiunge la carta offerta | recupera materiali per `5 + d` oro |

`Blood_Offering` non puo ridurre la vita a zero: la scelta primaria richiede vita
strettamente maggiore del costo. `Forgotten_Armory` usa il sampling pesato delle
reward con uno stato locale derivato dal seed del nodo. L'offerta non assegna un
instance ID finche la scelta primaria non viene confermata.

## Treasure

Un Treasure offre `7 + 2*d` oro, con la stessa profondita limitata usata dagli
eventi. `claim_treasure` applica l'importo una sola volta; Leave chiude il nodo
senza raccoglierlo.

Il calcolo dell'oro usa `i64` e rifiuta un risultato oltre `max(i32)`. Non esiste
un clamp silenzioso.

## Risoluzione e Continue

Rest, Event e Treasure separano la decisione dall'uscita della schermata:

1. il payload nasce con `resolved = false`;
2. una scelta valida oppure Leave registra esito e delta applicato;
3. la schermata mostra il risultato;
4. `continue_special_node` marca il nodo completato, incrementa `cleared_count`,
   azzera i tre payload speciali e passa a `Choose_Path`.

Prima della risoluzione, Continue e rifiutato. Dopo la prima scelta, ulteriori
scelte restituiscono `Already_Resolved`. Dopo Continue, una seconda chiamata e
rifiutata dalla fase. Il nodo e quindi one-shot sia nella decisione sia nel
conteggio di completamento.

Lo Shop usa un lifecycle leggermente diverso per consentire la riapertura: il
pulsante Continue esegue direttamente `leave_shop` e conserva il suo payload
finche il player non entra nel nodo seguente.

## Atomicita e limiti

Le operazioni speciali validano l'intera run prima del tentativo e preparano le
mutazioni su copie staged. Vengono committati soltanto i campi previsti
dall'operazione.

I fallimenti espliciti comprendono:

- carta Rest inesistente o gia al livello massimo;
- vita insufficiente per `Blood_Offering`;
- deck pieno o `next_card_id` esaurito in `Forgotten_Armory`;
- overflow dell'oro in Event e Treasure;
- payload corrotto, fase errata o nodo sorgente errato;
- seconda risoluzione dello stesso nodo.

Un fallimento conserva vita, oro, deck, ID, RNG, payload, fase, `cleared_count` e
flag del nodo. Nessuna scelta viene sostituita automaticamente con un'alternativa.

## Presentazione e controlli

`special_node_renderer.odin` disegna schermate full-canvas per Rest, Event e
Treasure. Il renderer legge il payload autorevole e mantiene soltanto hover,
pagina e carta selezionata in `Special_Node_Render_State`.

Controlli comuni:

| Input | Azione |
|---|---|
| click sul comando | sceglie l'azione mostrata |
| `1` | scelta primaria: Recover, prima opzione Event o Claim |
| `2` | scelta secondaria di Rest o Event |
| `L` | lascia il nodo senza applicare una ricompensa |
| `Enter` | continua verso la rotta dopo la risoluzione |

Nel Rest, il deck usa otto istanze per pagina. Click su una carta seleziona il suo
instance ID; `U` oppure `2` richiede l'upgrade della selezione. Frecce o pulsanti
freccia cambiano pagina e azzerano la selezione.

Lo Shop conserva i controlli documentati in [Deck Economy](DECK_ECONOMY.md):
offerte con click o `1`-`3`, selezione di una carta posseduta, `U`, `R`, frecce ed
`Enter` o `Esc` per tornare alla rotta.

## Invarianti

`validate_special_node_state` impone che:

- soltanto il payload della fase corrente sia presente;
- il nodo corrente sia entrato, del tipo atteso e non ancora completato;
- `source_node` coincida con `current_node`;
- deck di combattimento e zone temporanee siano inattivi;
- importi, tipo di evento e carta offerta coincidano con i builder deterministici;
- uno stato irrisolto non contenga outcome o delta;
- uno stato risolto contenga un outcome compatibile e riferimenti ancora validi.

Fuori da `Rest`, `Event` e `Treasure`, i relativi payload devono essere azzerati.
`validate_run_state` combina queste regole con mappa, player, reward, shop e deck.

## Test e smoke

I test coprono:

- ciclo e distribuzione dei quattro tipi in molte mappe;
- rifiuto di layer o seed dei nodi manomessi;
- ingresso e builder deterministici;
- recovery limitato e upgrade per instance ID;
- entrambe le scelte di ogni evento;
- claim e Leave del Treasure;
- lifecycle resolved/Continue one-shot;
- deck pieno, ID esauriti, vita insufficiente e overflow;
- snapshot completi sui fallimenti e payload corrotti;
- bounds, hit test, paginazione e selezione del renderer.

Verifica completa:

```sh
odin test src -all-packages -define:ODIN_TEST_THREADS=1
odin check src -vet -strict-style
odin run src -- --smoke-shop
odin run src -- --smoke-rest
odin run src -- --smoke-event
odin run src -- --smoke-treasure
odin run src -- --smoke-special-result
```

Gli smoke salvano rispettivamente `odin_pp_shop.png`, `odin_pp_rest.png`,
`odin_pp_event.png` e `odin_pp_treasure.png`. L'ultimo risolve un Treasure e
salva `odin_pp_special_result.png`, coprendo anche il pannello risultato.

## Limiti intenzionali

Gli eventi sono attualmente tre definizioni built-in e non vengono caricati da
file. Non sono presenti reroll, eventi concatenati, probabilita condizionate dal
deck, maledizioni, reliquie, shop con sconti o Rest con opzioni aggiuntive.

I nodi speciali non producono una `Room` esplorabile e non avanzano pulse o status.
Persistenza serializzata e migrazione dei seed restano milestone successive.
