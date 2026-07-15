# Reaction Queue

Questa guida descrive come gli eventi prodotti da un'azione attivano reazioni
senza ricorsione. Si appoggia ad [Action System](ACTION_SYSTEM.md) e
[Status And Event System](STATUS_SYSTEM.md).

## Indice

- [Perche una queue](#perche-una-queue)
- [Due livelli di risoluzione](#due-livelli-di-risoluzione)
- [Struttura FIFO](#struttura-fifo)
- [Algoritmo](#algoritmo)
- [Ordine causale](#ordine-causale)
- [Matching e costruzione](#matching-e-costruzione)
- [Definizioni dichiarative](#definizioni-dichiarative)
- [Binding runtime](#binding-runtime)
- [Priorita](#priorita)
- [Thorns](#thorns)
- [Afterimage](#afterimage)
- [Limiti anti-ciclo](#limiti-anti-ciclo)
- [Scheduler dei nemici](#scheduler-dei-nemici)
- [Report e diagnostica](#report-e-diagnostica)
- [Estensione futura](#estensione-futura)

## Perche una queue

Gli eventi vengono consumati con una queue FIFO: il primo evento emesso e il
primo a essere osservato. Una reazione aggiunge i propri eventi in fondo.

Uno stack LIFO invertirebbe l'ordine degli eventi gia prodotti. In una sequenza
`Damaged`, `Entity_Defeated`, la morte verrebbe osservata prima del danno. Inoltre
una nuova reazione verrebbe esplorata subito in profondita, rendendo piu difficile
seguire e limitare catene annidate.

La FIFO preserva l'ordine di emissione e processa la catena per livelli. A parita
di stato iniziale, l'ordine e sempre deterministico.

## Due livelli di risoluzione

Il resolver e diviso intenzionalmente:

- `resolve_action_once` valida e applica una sola azione atomica;
- `resolve_action` applica l'azione radice e poi svuota la reaction queue.

Il dispatcher usa soltanto `resolve_action_once` per le azioni reattive. Non
richiama `resolve_action`, quindi una reazione non crea ricorsione nello stack di
chiamate. Gli eventi prodotti vengono invece rimessi nella queue esplicita.

Questa separazione rende possibile testare il resolver atomico indipendentemente
dalla politica di dispatch.

## Struttura FIFO

`Reaction_Event_Queue` e un ring buffer inline:

```odin
Reaction_Event_Queue :: struct {
	items:         [MAX_REACTION_QUEUE_EVENTS]Game_Event,
	head:          int,
	count:         int,
	dropped_count: int,
}
```

La posizione di inserimento e:

```text
tail = (head + count) % capacity
```

Un pop avanza `head` con lo stesso wrap-around. Push e pop sono `O(1)` e non
allocano memoria.

## Algoritmo

Il flusso del dispatcher e:

```text
resolve_action_once(root)
enqueue(root.events)

while queue non vuota:
    event = pop_front()
    requests = collect_reactions(event)

    for request in requests:
        reaction = build_reaction_action(request)
        report = resolve_action_once(reaction)
        enqueue(report.events)
        merge(report)
        consume_binding_charge_if_needed(request)
```

Il report finale contiene sia gli effetti dell'azione radice sia quelli delle
azioni reattive. Il chiamante continua quindi a vedere una sola risoluzione.

## Ordine causale

Supponiamo che l'azione radice emetta `A` e `B`:

```text
queue iniziale: [A, B]
pop A
A produce la reazione C
queue:          [B, C]
pop B
pop C
```

Gli eventi reattivi non scavalcano quelli gia emessi. Gli effetti dell'azione
radice sono comunque atomici: tutte le sue mutazioni sono concluse prima che il
dispatcher cominci a osservare il log.

## Matching e costruzione

`collect_reactions` scandisce `REACTION_DEFINITIONS` e converte ogni definizione
compatibile in una `Reaction_Request`. Il matcher generico controlla trigger,
fase, quantita minima, reactor e relazione con la sorgente. L'attivazione puo
provenire da uno status oppure da un binding runtime.

`build_reaction_action` trasforma una richiesta in una normale `Action`. La
reazione attraversa quindi le stesse validazioni e gli stessi `Effect` di ogni
altra azione. Non esiste un percorso speciale che modifichi direttamente la
stanza.

Ogni evento puo attivare al massimo otto richieste. L'ordine di inserimento nel
`Reaction_Batch` viene normalizzato dalla priorita prima della risoluzione.

## Definizioni dichiarative

Una `Reaction_Definition` descrive il comportamento senza contenere stato
runtime:

```odin
Reaction_Definition :: struct {
	id:                   Reaction_Id,
	name:                 string,
	trigger:              Game_Event_Kind,
	reactor:              Reaction_Reactor_Selector,
	source_relation:      Reaction_Source_Relation,
	minimum_event_amount: i32,
	priority:             i32,
	combat_only:          bool,
	has_status_activation: bool,
	status_activation:     Status_Kind,
	effects:              [4]Reaction_Effect_Template,
	effect_count:         int,
}
```

Il reactor puo essere la sorgente o il target dell'evento. La relazione con la
sorgente puo essere `Any`, `Self` oppure `Opponent`.

Ogni effect template sceglie:

- un normale `Effect_Kind`;
- un target fra reactor, sorgente evento e target evento;
- un valore fisso, la potenza dell'attivazione oppure `event.amount`;
- status e durata quando costruisce `Apply_Status` o `Remove_Status`.

`Move` non e ancora rappresentabile perche richiederebbe anche un selettore di
coordinate. Anche `Add_Reaction_Binding` e escluso dai template reattivi finche
il template non conterra cariche, durata, priorita e sorgente. La validazione
rifiuta esplicitamente entrambi; le normali `Action` possono comunque installare
binding.

Le definizioni built-in sono costanti compilate nel programma. Sono gia
data-driven rispetto al dispatcher, ma non vengono ancora caricate da file.

## Binding runtime

Una definizione non contiene owner, durata o cariche. Questi dati appartengono a
`Reaction_Binding`:

```odin
Reaction_Binding :: struct {
	id:                u32,
	definition_id:     Reaction_Id,
	owner:             Entity_Ref,
	potency:           i32,
	remaining_charges: i32,
	remaining_pulses:  i32,
	priority_modifier: i32,
	source:            Reaction_Binding_Source,
}
```

La sorgente distingue `System`, `Ability`, `Card` e `Passive` e conserva un ID
opaco. `-1` rappresenta cariche o durata illimitate; zero non e mai uno stato
runtime valido.

Una stanza contiene al massimo 32 binding in storage inline. Gli ID restano
stabili anche quando la rimozione compatta l'array.

`Add_Reaction_Binding` e un normale `Effect`. Una carta puo quindi installare un
binding attraversando validazione, costo, resolver ed evento
`Reaction_Binding_Added`, senza modificare direttamente la stanza.

Il matcher puo produrre richieste dalla status activation dichiarata oppure da
ogni binding con definition e owner compatibili. La richiesta ricorda l'ID del
binding; la carica viene consumata soltanto dopo che la relativa azione reattiva
e stata accettata.

L'ultima carica emette `Reaction_Binding_Exhausted`. La durata viene decrementata
alla fine dell'impulso e lo zero emette `Reaction_Binding_Expired`. I binding di
un nemico vengono rimossi insieme all'owner quando muore.

## Priorita

Le richieste sono ordinate per priorita decrescente. Un binding somma il proprio
`priority_modifier` alla priorita della definizione con saturazione `i32`. A
parita viene usato l'ordine stabile di `Reaction_Id`.

Questa regola rende deterministico il caso in cui piu passive osservano lo stesso
evento. La priorita decide quale azione modifica per prima la stanza; gli eventi
prodotti da tutte le reazioni vengono comunque accodati in FIFO.

## Thorns

`Thorns` e la prima reazione concreta. Quando un combattente vivo riceve un
evento `Damaged` da un avversario vivo:

1. il target danneggiato diventa il reactor;
2. la sorgente del danno diventa il target della reazione;
3. viene costruita una `Action_Kind.Reaction`;
4. la reazione infligge danno pari alla potenza di `Thorns`.

`Damage_Absorbed` non attiva `Thorns`: se lo scudo assorbe tutto, la vita non e
stata danneggiata. Veleno e trappole non sono avversari, quindi non ricevono il
contraccolpo.

Due combattenti con `Thorns` possono reagire reciprocamente. La catena resta
iterativa ed e fermata dal limite globale se nessuno muore prima.

La definizione `Thorns_Counter` dichiara:

```text
trigger Damaged, reactor Event_Target, source Opponent
status activation Thorns, priority 100
Damage(Event_Source, Activation_Potency)
```

## Afterimage

`Afterimage` osserva `Moved` quando la sorgente e il reactor coincidono. Dopo un
movimento del proprietario applica `Shield` con potenza uguale alla potenza di
`Afterimage` e durata due impulsi.

```text
trigger Moved, reactor Event_Target, source Self
status activation Afterimage, priority 50, combat only
Apply_Status(Reactor, Shield, Activation_Potency, duration 2)
```

Il movimento viene risolto prima della reazione, mentre lo scudo viene applicato
prima che inizi la risposta nemica. Un movimento durante `Loot` non attiva la
definizione perche il filtro `combat_only` e abilitato.

## Limiti anti-ciclo

I limiti attuali sono:

| Risorsa | Capacita |
|---|---:|
| eventi contemporaneamente in queue | 64 |
| richieste prodotte da un evento | 8 |
| azioni reattive in una catena | 32 |
| eventi conservati in un report | 64 |
| binding runtime in una stanza | 32 |

Raggiungere un limite non annulla mutazioni gia applicate. Il sistema termina la
catena in modo deterministico e registra il problema nei contatori del report.
Questo comportamento fail-soft evita crash e loop infiniti, ma rende comunque
visibile un errore di bilanciamento o di configurazione.

## Scheduler dei nemici

Ogni nemico conserva inline l'intento committed per il pulse successivo.
Pianificazione e risoluzione raccolgono gli ID in un array inline e li ordinano
in modo crescente. L'ordine non dipende dagli indici di `Room.enemies`, che
possono cambiare quando `kill_enemy` usa `unordered_remove`.
Il lifecycle completo e descritto in
[Enemy Intent System](ENEMY_INTENT_SYSTEM.md).

All'inizio della risoluzione lo scheduler fotografa gli ID vivi. Prima di
eseguire un intento verifica nuovamente che l'entita esista e consuma il piano.
La relativa `Action` attraversa quindi la stessa reaction queue del resto del
gameplay:

- ogni nemico presente nello snapshot agisce al massimo una volta;
- un nemico eliminato prima del proprio turno viene saltato;
- un nemico eliminato durante la propria reazione non invalida l'iterazione;
- eventuali nemici creati durante l'impulso agiranno dall'impulso successivo.

La stanza accetta al massimo 32 nemici, lo stesso limite dello snapshot inline.
Un attacco che non trova piu il player nella cella minacciata produce
`Attack_Missed`; un movimento la cui destinazione non e piu libera produce
`Move_Blocked`. Questi eventi diagnostici vengono aggiunti direttamente al
`Pulse_Report` e non aprono una nuova catena reattiva. Gli intenti riusciti
continuano invece a emettere `Damaged` o `Moved` tramite normali `Action`.

## Report e diagnostica

`Action_Report` espone:

- `reactions_triggered`;
- `reactions_dropped`;
- `reaction_events_processed`;
- `reaction_events_dropped`;
- `reaction_limit_reached`.

Il report conta anche binding aggiunti e rimossi. Gli eventi di binding
conservano definition ID, binding ID e sorgente originaria.

I valori numerici di danno, cura, status e sconfitte includono azione radice e
reazioni. `Pulse_Report` aggrega gli stessi contatori per l'intero impulso.

## Estensione futura

Il matching, il builder e i binding runtime sono generici. Le definizioni sono
ancora una tabella built-in e non esiste un modello di carta. Il passo successivo
sara creare `Card_Definition` e `Card_Instance` contenenti:

```text
costo + targeting + effect template + reaction binding template
```

Le carte potranno installare i binding con `Add_Reaction_Binding`. In seguito la
tabella delle definizioni potra essere caricata dai dati di gioco senza cambiare
queue, resolver o scheduler.

Gli eventi di scadenza prodotti direttamente dallo scheduler sono per ora
registrati ma non riaperti come nuove catene reattive. Questo andra risolto prima
di aggiungere definizioni su `Status_Expired` o `Reaction_Binding_Expired`.
