# Reliquie della run

Le reliquie sono bonus permanenti per la run, pensati per dare una direzione al
mazzo e alle decisioni sulla griglia. Si conservano fra stanze e nodi speciali;
una nuova run azzera l'inventario.

## Acquisizione e controlli

- Prima di agire nella prima stanza scegli una fra tre reliquie.
- Dopo un Elite scegli una reliquia, poi ricevi la normale ricompensa di carte.
- Al Treasure, Claim assegna il tesoro e apre anche una scelta di reliquie.
- Usa il click oppure `1`, `2`, `3`; `S` o Skip salta la scelta.
- Le icone sopra la barra dell'energia mostrano le reliquie possedute. Passaci
  sopra con il mouse per leggerne nome ed effetto.

Le offerte dipendono dal seed, dal nodo e dalle reliquie già possedute. Non
contengono duplicati e non offrono reliquie già acquisite. Quando ne restano meno
di tre, la scelta si riduce; quando possiedi tutte e sei, non appare un'altra
offerta. Occorre scegliere o saltare prima di proseguire.

## Catalogo iniziale

| Reliquia | Effetto | Sinergia |
| --- | --- | --- |
| Iron Knuckle | Il primo spostamento forzato riuscito di un nemico o oggetto in ogni impulso dà 1 Shield per 2 impulsi | Shove, Grappling Hook e barili |
| Ash Bookmark | Il primo Exhaust di ogni combattimento pesca una carta aggiuntiva | Battle Focus, Volatile Study, Ethereal |
| Swift Soles | La prima carta che sposta effettivamente il giocatore in ogni combattimento recupera 1 energia | Dash e riposizionamento |
| Venom Vial | La prima applicazione riuscita di Poison a un nemico in ogni combattimento ha potenza +1 | Venom Needle e Caustic Bloom |
| Guard Sigil | All'ingresso in combattimento dà 2 Shield per 3 impulsi | Avvicinamento e prime decisioni |
| Mending Thread | Alla fine di un combattimento vinto cura 2 HP | Recupero fra gli scontri |

La normale scadenza degli status continua ad avanzare con gli impulsi. Una
spinta bloccata non attiva Iron Knuckle; camminare non attiva Swift Soles. Il
bonus di Venom Vial si applica al primo bersaglio valido, anche con una carta ad
area. Energia e salute rispettano i massimi del giocatore.

Ash Bookmark si attiva anche quando Refocus manda una carta Ethereal in Exhaust:
la pesca aggiuntiva avviene dopo il pulse nemico e il normale refill, se il
giocatore è ancora in combattimento. Una sconfitta non assegna cure o bonus di
fine giocata. Mending Thread non si riattiva spostandosi nella stanza ripulita.

## Integrazione e verifica

L'inventario vive nel `Player` della run; i limiti per combattimento vengono
reimpostati all'installazione di una stanza. Gli effetti usano le normali azioni,
gli status e gli eventi del gioco, senza consumare RNG di combattimento. Il
recupero di energia produce `Energy_Gained`, riprodotto dalla timeline prima
del successivo `Pulse_Advanced`.

L'app abilita le offerte passando `with_relic_rewards = true` a `create_run`.
Il valore predefinito dell'API resta `false` per gli scenari headless preesistenti.
Scelta e ricompense hanno validazione prima del commit: indici errati, offerte
obsolete o alterate e tentativi ripetuti non modificano inventario, deck o RNG.

Gli smoke grafici sono:

```sh
odin run src -- --smoke-relics
odin run src -- --smoke-relic-combat
```

Salvano rispettivamente `odin_pp_relics.png` e `odin_pp_relic_combat.png`.
I test coprono gli effetti durante giocate reali, lo stato intermedio della
timeline, le offerte iniziali, Elite e Treasure, la persistenza e il restart.
La verifica completa è `sh scripts/check.sh`.
