# Status And Event System

Questa guida descrive status, impulsi ed eventi costruiti sopra
[Action System](ACTION_SYSTEM.md). Il dispatch reattivo e descritto in
[Reaction Queue](REACTION_SYSTEM.md).

## Indice

- [Status storage](#status-storage)
- [Stacking](#stacking)
- [Applicazione tramite Effect](#applicazione-tramite-effect)
- [Ordine di un impulso](#ordine-di-un-impulso)
- [Shield](#shield)
- [Poison](#poison)
- [Thorns](#thorns)
- [Afterimage](#afterimage)
- [Event log](#event-log)
- [Recent events](#recent-events)
- [Abilita temporanee](#abilita-temporanee)
- [Ciclo di vita](#ciclo-di-vita)
- [Limiti intenzionali](#limiti-intenzionali)

## Status storage

Player e nemici contengono uno `Status_Set` inline:

```odin
Status :: struct {
	kind:             Status_Kind,
	potency:          i32,
	remaining_pulses: i32,
}

Status_Set :: struct {
	items: [MAX_STATUSES_PER_ENTITY]Status,
	count: int,
}
```

Non viene allocata memoria durante applicazione, ricerca, tick o rimozione.
Attualmente un'entita puo contenere al massimo otto status e una sola istanza
per ogni `Status_Kind`.

La rimozione mantiene l'ordine degli elementi spostando quelli successivi. Gli
status sono pochi, quindi la prevedibilita dell'ordine vale piu di una rimozione
`O(1)` con `unordered_remove`.

## Stacking

Le policy sono definite per tipo:

| Status | Nuova potenza | Nuova durata |
|---|---|---|
| `Poison` | mantiene la potenza maggiore | mantiene la durata maggiore |
| `Shield` | somma i punti di scudo | mantiene la durata maggiore |
| `Thorns` | mantiene la potenza maggiore | mantiene la durata maggiore |
| `Afterimage` | mantiene la potenza maggiore | mantiene la durata maggiore |

Riapplicare un veleno piu debole puo quindi rinnovarne la durata, ma non riduce
la potenza esistente. Lo scudo e additivo e usa una somma saturata per evitare
overflow di `i32`. `Thorns` segue la policy conservativa del veleno.
`Afterimage` usa la stessa policy e converte la propria potenza in scudo.

## Applicazione tramite Effect

Gli status runtime non devono essere modificati direttamente dalle abilita.
Il resolver supporta due effetti:

```odin
apply_status_effect(target, .Poison, potency, duration)
remove_status_effect(target, .Poison)
```

`Apply_Status` viene rifiutato se potenza o durata non sono positive, il target
non e un combattente oppure lo storage e pieno. `Remove_Status` viene rifiutato
se lo status non esiste.

Un'applicazione o rimozione accettata produce rispettivamente gli eventi
`Status_Applied` e `Status_Removed`.

## Ordine di un impulso

L'azione del player e la sua catena reattiva vengono risolte dal chiamante. Se il
combattimento continua, `advance_combat_pulse` e l'unico scheduler della risposta:

1. ogni nemico esegue una singola azione, seguita dalla relativa catena reattiva;
2. vengono processati gli status del player e poi quelli dei nemici, decrementando
   le durate e facendo scadere gli status arrivati a zero;
3. avanzano le durate dei reaction binding;
4. se il combattimento e ancora attivo, viene rigenerata l'energia del deck;
5. `pulse_count` aumenta e vengono pianificati gli intenti successivi, oppure
   svuotati quelli rimasti se il combattimento e terminato;
6. un `Pulse_Advanced` terminale registra pulse, energia e presenza dei tick.

Uno status applicato dall'azione del player e quindi attivo durante la risposta
nemica e, se il combattimento continua fino ai tick, riceve il primo avanzamento
alla fine dello stesso impulso.

`pulse_count` aumenta una volta per ogni impulso, indipendentemente dal numero di
nemici, status o effetti coinvolti.

## Shield

L'ordine del danno sul player e:

```text
danno raw
  -> difesa del player, con minimo 1
  -> assorbimento Shield
  -> sottrazione dalla vita
```

Lo scudo dei nemici non passa attraverso una statistica di difesa, perche i
nemici non la possiedono ancora.

Il report distingue:

- `damage_absorbed`: punti consumati dallo scudo;
- `damage_dealt`: punti realmente sottratti alla vita.

Quando la potenza dello scudo raggiunge zero, lo status viene rimosso subito e
vengono emessi `Damage_Absorbed` e `Status_Removed`.

## Poison

Alla fine di ogni impulso, `Poison` costruisce una normale azione di danno con
sorgente `SYSTEM_ENTITY`. Questo significa che usa esattamente lo stesso resolver
di attacchi, trappole e abilita.

Con le regole attuali:

- il veleno viene mitigato dalla difesa del player;
- lo scudo puo assorbire il veleno;
- il veleno puo uccidere player o nemici;
- uccidere l'ultimo nemico porta la stanza a `Loot` durante il tick;
- dopo ogni tick la durata diminuisce di uno.

Se la durata arriva a zero viene emesso `Status_Expired`. Se l'entita muore prima,
lo status scompare insieme all'entita e non produce un evento di scadenza.

## Thorns

`Thorns` reagisce a `Damaged` prodotto da un avversario. Costruisce una normale
azione di contraccolpo e infligge la propria potenza alla sorgente del danno.
Non reagisce al danno interamente assorbito, alle trappole o al veleno.

Le reazioni sono elaborate dalla queue FIFO dopo ogni azione atomica. Due
combattenti con `Thorns` possono generare una catena reciproca, limitata a 32
azioni reattive.

## Afterimage

`Afterimage` reagisce al movimento del proprio owner durante `Combat`. Applica
`Shield` con potenza pari alla propria potenza e durata due impulsi. Poiche la
reazione viene risolta prima dello scheduler nemico, lo scudo puo proteggere
dalla risposta allo stesso movimento.

Movimenti nemici, spostamenti durante `Loot` e movimenti di altre entita non
attivano lo status del player.

## Event log

Ogni `Action_Report` e `Pulse_Report` contiene un `Event_Log` inline con capacita
288. Gli eventi disponibili sono:

- `Damaged`;
- `Damage_Absorbed`;
- `Healed`;
- `Moved`;
- `Move_Blocked`;
- `Attack_Missed`;
- `Gold_Gained`;
- `Loot_Dropped`;
- `Loot_Collected`;
- `Card_Played`;
- `Card_Drawn`;
- `Card_Moved`;
- `Card_Created`;
- `Hand_Refocused`;
- `Card_Refocused`;
- `Entity_Defeated`;
- `Status_Applied`;
- `Status_Removed`;
- `Status_Expired`;
- `Reaction_Binding_Added`;
- `Reaction_Binding_Exhausted`;
- `Reaction_Binding_Expired`;
- `Pulse_Advanced`.

Un evento conserva sorgente, target, quantita, status, durata, tipo di loot,
coordinate e, quando pertinente, identita, definizione, upgrade, lifetime e zone
della carta. Per `Card_Created`, `.Count` indica esplicitamente l'assenza di una
zona di origine. `Card_Refocused` registra anche `Hand -> Hand` per una carta
retained, rendendo osservabile la policy senza inventare uno spostamento.
`Pulse_Advanced` aggiunge contatore, energia finale, energia realmente recuperata,
energia sprecata al cap e informazione sui tick. Il renderer usa la sequenza per riprodurre le cause; lo snapshot finale
sincronizza soltanto i valori assoluti non emessi singolarmente.

Se il log e pieno, gli eventi successivi non vengono allocati: `dropped_count`
registra quanti eventi sono stati persi.

La capacita segue una policy diversa ai due lati del commit. Un log costruito su
stato staged deve contenere tutti gli eventi necessari: un `record_event` fallito
annulla la transazione prima che diventi autorevole. Dopo il commit non e invece
possibile rollbackare simulazione, RNG o ID soltanto per un limite della
presentazione; gli eventi eccedenti vengono scartati, `dropped_count` resta
osservabile e lo snapshot finale riconcilia la vista. I command report devono
propagare questa diagnostica quando il loro envelope puo avvicinarsi al limite.

## Recent events

`Room.recent_events` conserva l'ordine prodotto dai sottosistemi e contiene
soltanto i segmenti realmente eseguiti:

1. l'eventuale `Card_Played`, seguito dagli eventi dell'azione e delle reazioni;
2. drop, raccolte magnetiche ed eventuale trappola innescati dall'azione;
3. se il combattimento continua, azioni nemiche, tick di status e binding, quindi
   il `Pulse_Advanced` terminale;
4. raccolte magnetiche prodotte dopo il pulse;
5. l'eventuale `Card_Drawn`, soltanto per una carta risolta mentre il combattimento
   continua.

Un movimento in fase `Loot` e un'azione del player che termina il combattimento
prima della risposta nemica non producono un pulse.

Il log viene azzerato all'inizio del comando successivo. Azioni bloccate lasciano
quindi un log vuoto.

## Abilita temporanee

Quattro abilita rendono il sistema provabile prima del deck building:

- `Guard` applica `Shield(3, 3)` al player;
- `Toxic Wave` applica `Poison(1, 3)` a tutti i nemici;
- `Thorn Coat` applica `Thorns(1, 3)` al player;
- `Afterimage` applica `Afterimage(1, 4)` al player.

Tutte costruiscono una sola `Action` e producono un solo impulso. `Toxic Wave`
usa un effetto per nemico e viene rifiutata se il numero di bersagli supera la
capacita fissa dell'azione.

Le API restano utili a test e smoke test. Soltanto `Thorn Coat` e `Afterimage`
mantengono scorciatoie debug, rispettivamente `C` e `V`; `Guard` e `Toxic Wave`
si usano tramite le carte. Le carte attraversano pagamento, cambio zona, pulse
e pesca.

## Ciclo di vita

Gli status del player sono attualmente specifici della stanza. Una nuova stanza
li cancella soltanto dopo che tutta la costruzione e stata validata con successo.

Un fallimento nella creazione della stanza non modifica status, posizione,
vita, oro o mazzo persistenti del player.

Gli status non avanzano durante `Loot`, `Reward`, `Shop`, `Rest`, `Event`,
`Treasure`, `Choose_Path`, `Victory` o `Defeat`.

## Limiti intenzionali

Non sono ancora implementati:

- status persistenti fra stanze;
- immunita, resistenze o tipi di danno;
- sorgente originale conservata dentro uno status;
- reazioni a `Status_Expired` o `Entity_Defeated`;
- caricamento delle definizioni da dati esterni;
- priorita configurabili dei tick;
- tooltip e targeting grafico delle abilita.

Queue, matcher e binding runtime sono separati dal resolver atomico. La timeline
FIFO visualizza gia danno, status e binding senza cambiare lo scheduler; il
contratto e in [Presentation Timeline](PRESENTATION_TIMELINE.md).
