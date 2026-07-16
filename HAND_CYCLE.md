# Hand Cycle

Questa guida descrive `Refocus`, la frontiera esplicita della mano durante il
combattimento. Il lifecycle generale delle istanze e in
[Card Lifecycle](CARD_LIFECYCLE.md), il contenitore in
[Deck Runtime](DECK_SYSTEM.md) e il replay visuale in
[Presentation Timeline](PRESENTATION_TIMELINE.md).

## Indice

- [Perche esiste Refocus](#perche-esiste-refocus)
- [Comando](#comando)
- [Cleanup della mano](#cleanup-della-mano)
- [Ordine della transazione](#ordine-della-transazione)
- [Eventi](#eventi)
- [Energia](#energia)
- [Casi terminali](#casi-terminali)
- [Presentazione](#presentazione)
- [Invarianti](#invarianti)
- [Limiti intenzionali](#limiti-intenzionali)

## Perche esiste Refocus

Nel loop corrente ogni azione valida del player produce un pulse nemico. Un
pulse non e pero una fine turno: puo derivare da un passo, una carta, un bump
attack o un'attesa. Scartare la mano a ogni pulse renderebbe `Retain` quasi
obbligatorio e spezzerebbe il ritmo fast-paced.

`Refocus` e quindi una decisione manuale. Il player rinuncia a un'azione, lascia
rispondere i nemici e ricostruisce la mano. La simulazione conserva cosi una
frontiera osservabile senza introdurre un turno globale separato.

## Comando

Durante `Combat`, `F` o il pulsante `REFOCUS` producono lo stesso
`Gameplay_Command.Refocus`. Il comando attraversa il buffer di capacita uno e
viene rivalidato quando la timeline torna idle.

Il comando viene rifiutato senza pulse se:

- stanza o player non sono validi;
- la fase non e `Combat`;
- il deck non e attivo o viola le invarianti;
- una carta occupa ancora lo slot `Resolving`;
- cleanup o staging degli eventi falliscono.

Una mano vuota e invece valida: Refocus produce comunque un pulse e tenta poi il
refill.

## Cleanup della mano

`Card_Definition` contiene due policy della frontiera:

```odin
retain_on_refocus: bool,
ethereal:          bool,
```

Per ogni carta che si trovava nella mano originale, da sinistra a destra:

| Policy | Destinazione |
|---|---|
| `retain_on_refocus` | resta in `Hand` |
| `ethereal` | passa in `Exhaust` |
| nessuna delle due | passa in `Discard` |

Le due flag sono mutuamente esclusive. `Counter Rune` dimostra `Retain`;
`Battle Focus` dimostra `Ethereal`.

`exhaust_on_play` non significa `ethereal`: la prima policy si applica dopo una
giocata riuscita, la seconda soltanto a una carta non giocata durante Refocus.
Anche il lifetime `Combat` e indipendente: una carta temporanea normale viene
scartata, non exhaustata, e continua a esistere fino alla fine del fight.

## Ordine della transazione

`refocus_player_hand` esegue questo ordine autorevole:

```text
valida stanza e deck
  -> cleanup staged della mano originale
  -> commit del cleanup e degli eventi iniziali
  -> un solo pulse nemico
  -> loot magnetico
  -> se il fight continua, pesca fino a hand_size
```

Le carte retained occupano gia slot della nuova mano. Il refill pesca quindi
soltanto `max(0, hand_size - retained_count)` carte. Se il numero di retained e
maggiore o uguale a `hand_size`, non viene pescato nulla; `MAX_HAND_CARDS` resta
comunque il limite strutturale.

La pesca usa le primitive normali: quando il draw pile termina, il discard viene
mescolato con lo stesso RNG deterministico del deck. Nessuna scorciatoia speciale
duplica shuffle o ownership.

## Eventi

L'ordine in `Room.recent_events` e:

1. un marker `Hand_Refocused`;
2. un `Card_Refocused` per ogni carta della mano originale, nello stesso ordine;
3. tutti gli eventi del pulse;
4. gli eventuali eventi della raccolta magnetica successiva al pulse;
5. un `Card_Drawn` per ogni carta del refill, se il combattimento continua.

`Card_Refocused` conserva ID, definizione, upgrade, lifetime e zone. Anche una
carta retained emette `Hand -> Hand`: non e una mutazione fisica, ma rende
osservabile la decisione della policy e permette alla timeline di validarla.

Questo evento e la causa canonica del cleanup. Un futuro matcher generico delle
transizioni non deve trattarlo come intercambiabile con `Card_Moved` soltanto
perche le zone coincidono: deve normalizzare almeno kind, origine e destinazione.

## Energia

Refocus non resetta e non imposta direttamente l'energia. Consuma una decisione
del player e produce il normale pulse; l'unico recupero e quindi
`energy_regen_per_pulse`, applicato da `advance_combat_pulse` e mostrato da
`Pulse_Advanced`.

Questa regola evita un secondo modello di rigenerazione nascosto nel ciclo mano.
I modificatori temporanei di costo ed energia appartengono a un incremento
successivo di M4B.

## Casi terminali

Il cleanup e gia committed quando parte il pulse. Se quel pulse:

- elimina l'ultimo nemico, il risultato e `Combat_Ended`;
- porta il player a zero vita, il risultato e `Player_Defeated`.

In entrambi i casi non avviene il refill. `sync_deck_with_room_phase` chiude il
deck runtime secondo il normale lifecycle della stanza. I risultati terminali
restano committed: la timeline deve mostrare cleanup, risposta nemica e
transizione finale nello stesso ordine.

## Presentazione

`Hand_Refocused` produce un cue breve di frontiera. Ogni `Card_Refocused` applica
poi la stessa policy alla copia presentazionale: Hand e un no-op validato,
Discard ed Exhaust usano un movimento atomico per ID. I successivi cue del pulse
e di pesca avanzano la stessa copia fino allo snapshot finale.

La mano mostra tag `RETAIN` ed `ETHEREAL`, oltre a `TEMP`. Durante una timeline il
pulsante Refocus e disabilitato; `F` puo occupare il normale input buffer. Un
commit riuscito azzera hover, selezione e drag per evitare ID visuali ormai
usciti dalla mano.

Lo smoke deterministico e:

```sh
odin run src -- --smoke-refocus
```

Prepara nella stessa mano una carta retained e una ethereal, esegue Refocus e
salva `odin_pp_refocus.png` durante il marker iniziale.

## Invarianti

1. Il cleanup osserva esattamente la mano presente all'inizio del comando.
2. Ordine relativo e identita delle carte retained non cambiano.
3. Ogni carta originale produce esattamente un `Card_Refocused`.
4. Nessuna carta puo essere contemporaneamente retained ed ethereal.
5. Un Refocus committed produce esattamente un pulse.
6. Il refill avviene soltanto dopo il pulse e soltanto se la fase resta `Combat`.
7. Energia, RNG, ID e ownership passano esclusivamente dalle primitive del deck.
8. Un fallimento prima del commit non modifica deck, stanza, eventi o pulse.

## Limiti intenzionali

Questo incremento non completa tutta M4B. Restano separati:

- modificatori runtime di costo e rigenerazione;
- scarto o exhaust di una carta scelta tramite UI;
- animazioni spaziali complete fra mano e pile;
- raggruppamento parallelo dei cue di cleanup.
