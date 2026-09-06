# Presentation Timeline

Gli esplosivi aggiungono `Object_Spawned`, `Explosive_Armed`, `Explosion` e
`Explosive_Disarmed`. Lo snapshot copia `detonation_pulse`; il countdown segue
il proprio `pulse_count`, senza leggere lo stato futuro della stanza.
`Explosion` nasconde la sorgente prima dei cue di danno. Gli spawn riusano
slot invisibili, mantenendo ID distinti anche quando la capienza e piena.
Le regole giocabili sono in [Combattimento tattico](TACTICAL_COMBAT.md).

Lo snapshot conserva anche ricetta dell'incontro, corsia e scadenza della
Fornace e fase del Demolitore. `Room_Hazard_Triggered` mostra il lampo della
corsia prima dei cue di danno e registra la prossima attivazione. La fase del
boss viene sincronizzata su `Pulse_Advanced`, alla stessa frontiera della
pianificazione: HUD e corpo non anticipano la trasformazione mentre si anima
l'attacco precedente. Alla morte conclusiva la vista disarma la Fornace anche
se il comando ha chiuso Combat senza produrre un nuovo pulse. Lo scudo del
Custode usa il normale replay di status.

Questa guida descrive il confine fra la simulazione autorevole della `Room`, la
riproduzione visuale degli eventi e il buffer dei comandi. La produzione degli
eventi e descritta in [Action System](ACTION_SYSTEM.md) e
[Status And Event System](STATUS_SYSTEM.md); targeting e compilazione delle carte
in [Targeting System](TARGETING_SYSTEM.md) e [Card System](CARD_SYSTEM.md);
percorsi e ordine degli hazard in [Movement System](MOVEMENT_SYSTEM.md).

## Indice

- [Modello](#modello)
- [Flusso di un comando](#flusso-di-un-comando)
- [Snapshot e cue FIFO](#snapshot-e-cue-fifo)
- [Input buffer](#input-buffer)
- [Targeting durante la timeline](#targeting-durante-la-timeline)
- [Transizioni e reset](#transizioni-e-reset)
- [Invarianti](#invarianti)
- [Capacita e diagnostica](#capacita-e-diagnostica)
- [Estendere la timeline](#estendere-la-timeline)
- [Aggiungere un comando](#aggiungere-un-comando)
- [Test e debug](#test-e-debug)
- [Limiti intenzionali](#limiti-intenzionali)

## Modello

La simulazione non aspetta le animazioni. Un comando valido modifica subito la
`Room` e produce un `Event_Log` ordinato. Se consuma un turno mentre il combattimento
continua, risolve sincronicamente anche l'intero pulse nemico; i movimenti in
`Loot` e le azioni del player che chiudono il combattimento prima della risposta
nemica non ne avviano uno. La timeline possiede una copia catturata prima del
comando, applica gli eventi uno alla volta e conserva anche uno snapshot finale
per sincronizzare valori assoluti che non richiedono un evento separato.

```text
input discreto
      |
      v
Gameplay_Command
      |
      +---- snapshot pre-comando --------+
      |                                  |
      v                                  v
simulazione sincrona                 vista iniziale
      |
      +---- Event_Log FIFO -------------> Presentation_Timeline
      |                                  ^
      +---- snapshot post-comando -------+
      |
      v
Room finale                     rendering dei cue sulla copia
```

Esistono quindi due viste per un intervallo breve:

- la `Room` e lo stato autorevole gia risolto, usato da regole e validazione;
- `Room_Presentation` e lo stato visuale arretrato, usato dal renderer finche la
  timeline contiene cue; `final_view` e una copia completa post-comando, consultata
  soltanto dalle sincronizzazioni esplicite.

Quando la timeline diventa idle, il renderer torna a leggere direttamente la
`Room`. La copia non viene mai riscritta dentro la simulazione.

## Flusso di un comando

Il percorso normale e:

1. `poll_gameplay_command` converte un fronte di input in un valore
   `Gameplay_Command`.
2. Se la timeline e idle, `commit_gameplay_command` cattura lo snapshot corrente.
3. `execute_gameplay_command` chiama l'API autorevole appropriata: movimento,
   attesa, abilita, carta o Refocus.
4. Soltanto un comando realmente committed puo avviare una presentazione; un
   muro, una fase incompatibile o una carta rifiutata non creano cue.
5. La simulazione risolve subito azione, reazioni, loot e cambio di fase; quando il
   combattimento continua risolve anche impulso nemico e status. Il relativo
   ordine e registrato in `room.recent_events`.
6. Viene catturato lo snapshot post-comando; `begin_event_timeline` copia eventi,
   vista iniziale e vista finale nella timeline.
7. `update_event_timeline` avanza il cue in testa. Se `dt` supera il tempo che gli
   resta, il residuo viene consumato dai cue successivi nello stesso frame.
8. Dopo l'ultimo cue, il renderer mostra nuovamente la `Room` finale.

Un comando committed che non produce eventi non rende la timeline busy. Lo stato
autorevole e gia aggiornato e viene mostrato normalmente.

## Snapshot e cue FIFO

`Room_Presentation` contiene i dati necessari a disegnare la stanza: fase,
player, nemici, trappole, grid object, loot, oro, pulse, status e una copia
inline del deck. Attori e oggetti sono referenziati con `Entity_Ref`, quindi la
rimozione o il riordino nella `Room` non invalida il bersaglio di un evento gia
copiato.

Ogni `Game_Event` diventa un `Presentation_Cue`. La coda e strettamente FIFO:
non raggruppa eventi simili e non riordina danno, reazioni o loot. Un solo cue e
attivo alla volta.

Le famiglie visualizzate sono:

| Famiglia | Effetto sulla copia di presentazione |
|---|---|
| `Movement_Step`, `Moved` | interpolano una tratta con easing; lo step usa una durata piu breve |
| `Trap_Triggered` | disarma esplicitamente la trappola nello snapshot prima del danno |
| `Hazard_Triggered` | valida sorgente, attore e cella, mostra `BURN` senza consumare l'oggetto |
| `Room_Hazard_Triggered` | illumina la corsia Fornace prima del danno e memorizza la prossima scadenza |
| `Damaged`, `Damage_Absorbed`, `Healed` | aggiorna vita o shield e mostra il feedback |
| eventi status | aggiorna i badge dello snapshot e mostra il relativo avviso |
| eventi binding | mostra l'avviso; il set dei binding non e copiato nello snapshot |
| `Card_Played` | paga e riproduce `Hand -> Resolving` |
| `Card_Drawn` | pesca e riproduce l'eventuale reshuffle/RNG |
| `Card_Moved` | riproduce `Hand/Resolving -> Discard/Exhaust` |
| `Card_Created` | richiede origine `.Count` e ricrea la stessa istanza temporanea e lo stesso ID in mano |
| `Hand_Refocused` | mostra la frontiera manuale prima del cleanup |
| `Card_Refocused` | valida policy e identita; mantiene Retain o muove verso discard/exhaust |
| `Entity_Defeated` | mantiene l'attore nello snapshot durante il fade, poi lo nasconde |
| `Loot_Dropped` | aggiunge il drop sulla cella e ne mostra il pulse |
| `Loot_Collected`, `Gold_Gained` | anima la raccolta e aggiorna la copia dell'oro |
| `Pulse_Advanced` | sincronizza pulse, energia, durate status, modificatore e fase del boss dalla vista finale |
| `Attack_Missed`, `Move_Blocked` | mostra un avviso senza mutare la `Room` |

La durata appartiene al tipo di cue. I movimenti del player e dei nemici possono
quindi avere timing diversi senza introdurre attese nella simulazione. Modificare
una durata cambia soltanto la presentazione. `PRESENTATION_TIME_SCALE` moltiplica
tutte le durate: un valore maggiore di uno rallenta l'intera timeline conservando
il ritmo relativo fra le famiglie di cue. Le sequenze normali mantengono queste
durate senza modifiche; se la somma supera 12 secondi,
`begin_event_timeline` scala proporzionalmente tutti i cue. Il limite impedisce
che un AoE denso blocchi l'input per decine di secondi senza alterare l'ordine.

Il renderer applica inoltre una velocita runtime tra 0.25x e 4x al delta della
timeline. `--animation-speed=2`, `--fast` (4x) e `F4` controllano questa velocita,
indicata nell'HUD e conservata tra stanze e restart. Il limite di 12 secondi si
riferisce al tempo della timeline a 1x. Ordine FIFO, snapshot, buffer input e
simulazione restano identici a ogni velocita; gli smoke grafici usano sempre 1x.

Un movimento multi-cella arriva gia segmentato dal gameplay. La timeline non
interpola direttamente origine-destinazione: riproduce ogni `Movement_Step` e il
`Moved` terminale in FIFO. Se una cella contiene una trappola o un oggetto
pericoloso, il relativo `Trap_Triggered` o `Hazard_Triggered` viene quindi
mostrato dopo l'ingresso e prima dei propri eventi di shield, danno o sconfitta,
esattamente come nella simulazione.

## Input buffer

`Buffered_Gameplay_Command` e una coda intenzionalmente ridotta a un solo slot
con politica first-wins:

```text
timeline busy + primo comando  -> memorizzato
timeline busy + altri comandi  -> scartati
timeline idle                  -> estrazione atomica e nuova validazione
```

Il buffer conserva valori logici, non callback ne indici visuali: fase d'origine,
direzione, abilita, ID stabile della carta, target oppure il marker Refocus.
Quando viene estratto, il
comando passa di nuovo dalle normali API di gameplay. Una carta puo essere uscita
dalla mano, un target puo essere morto o la fase puo essere cambiata; in questi
casi il comando viene rifiutato senza forzare uno stato ormai invalido. In
particolare, un movimento formulato in `Combat` non diventa implicitamente un
movimento `Loot` dopo la morte dell'ultimo nemico.

La capacita uno permette di preparare la prossima decisione senza accumulare una
sequenza di turni mentre il giocatore sta ancora guardando le conseguenze del
precedente. Gli input da tastiera sono edge-triggered: tenere premuto un tasto
non continua a offrire lo stesso comando.

## Targeting durante la timeline

Il targeting spaziale dipende dalla cella visualizzata sotto il cursore. Durante
una timeline, quella cella appartiene allo snapshot, mentre le query autorevoli
leggerebbero gia la `Room` finale. Mescolare i due stati renderebbe una preview
ingannevole.

Per questo, finche la timeline e busy:

- drag, drop e click sulla griglia sono sospesi;
- il drag eventualmente attivo viene annullato;
- cast range, footprint e intenti a terra non vengono disegnati;
- gli intent badge correnti non vengono sovrapposti alla stanza arretrata;
- i comandi discreti da tastiera possono occupare il buffer;
- una selezione spaziale gia attiva puo restare memorizzata, ma una nuova carta
  targettata non viene selezionata finche timeline e buffer non sono idle.

Gli shortcut numerici vengono risolti contro il deck presentazionale attualmente
visibile. Non possono quindi accodare una carta appena pescata prima che il suo cue
l'abbia mostrata. Camera e rendering della mano restano indipendenti dal blocco del
targeting spaziale.

Il pulsante Refocus e disabilitato durante la timeline. Lo shortcut `F` resta un
comando discreto e puo occupare il buffer; al consumo viene rivalidato come ogni
altra intenzione. Il replay completo e descritto in [Hand Cycle](HAND_CYCLE.md).

## Transizioni e reset

La `Room` puo raggiungere `Complete` o `Defeat` durante la risoluzione sincrona,
ma `finish_room` viene chiamato soltanto quando la timeline e idle. In questo
modo l'ultima morte, il loot o il feedback conclusivo non vengono tagliati da una
schermata di ricompensa, vittoria o sconfitta.

Timeline e buffer vengono svuotati quando il vecchio contesto non e piu valido:

- restart della run;
- ingresso in una nuova stanza;
- passaggio a ricompensa, rotta, vittoria o sconfitta;
- apertura manuale della mappa, consentita soltanto a timeline idle.

Un comando bufferizzato non deve mai attraversare questi confini.

## Invarianti

Il sistema deve conservare queste proprieta:

1. La timeline non modifica mai `Room`, `Player`, deck o RNG autorevoli; i cue
   delle carte avanzano soltanto le copie di deck e RNG in `Room_Presentation`.
2. Gli snapshot iniziale e finale vengono catturati ai due lati dello stesso comando.
3. I cue rispettano esattamente l'ordine del `Event_Log`.
4. Esiste al massimo un cue attivo; il `dt` residuo non viene perso.
5. Ogni riferimento a un attore usa un ID stabile, non un indice di dynamic array.
6. Un nuovo comando non viene eseguito mentre la timeline e busy.
7. Il buffer contiene al massimo il primo comando offerto ed e riletto una sola volta.
8. Un comando estratto viene sempre validato contro lo stato autorevole corrente
   e contro la fase nella quale era stato formulato.
9. Targeting e intenti autorevoli non vengono mostrati sopra uno snapshot arretrato.
10. Nessuna transizione di run sostituisce la stanza prima dell'ultimo cue.

Se una modifica richiede di violare una di queste regole, deve prima cambiare il
contratto esplicito del sistema e i relativi test.

## Capacita e diagnostica

Timeline ed `Event_Log` usano array fissi e non allocano durante la riproduzione.
`MAX_PRESENTATION_CUES` coincide con `MAX_GAME_EVENTS`, attualmente 416; lo
snapshot conserva fino a 32 nemici, 64 trappole, 32 grid object e 64 drop. Il log
espone `dropped_count` e la timeline conserva sia gli eventi gia persi a monte
sia quelli che non riesce a copiare.

Prima del commit, un producer staged tratta l'overflow come fallimento e non
modifica lo stato autorevole. `Action_Report` e un caso piu severo: i suoi eventi
alimentano anche il dispatcher delle reazioni, quindi `record_report_event`
termina esplicitamente il processo se esaurisce la capacita. Perdere un evento
qui cambierebbe il gameplay. Solo le copie post-commit destinate a storico e
presentazione restano fail-soft: contano gli eventi persi e convergono allo
snapshot finale. Un `dropped_count` non nullo resta comunque un errore
diagnostico, non un esito normale.

Lo stress test denso compone 258 eventi: play e movimento carta, status su 32
nemici, 32 intenti, morti, drop doppi, raccolte, pulse e pesca. Un secondo test
percorre le 12 celle massime sopra 12 trappole e produce 36 eventi senza drop.
Il limite lascia 158 slot oltre il primo envelope (`258 + 158 = 416`), ma i due
envelope non vanno sommati alla cieca: una futura carta che combini AoE,
movimento e nuove reazioni deve estendere il test. Se il massimo reale cresce,
va sostituito l'array monolitico con storage a blocchi invece di alzare il limite.

`Presentation_Timeline.update_failures` conta eventi che non possono essere
applicati alla copia, per esempio un target assente dallo snapshot. Il buffer
espone `offered_count`, `dropped_count` e `consumed_count`. Questi contatori
distinguono rapidamente un overflow, un contratto eventi incompleto e un input
scartato correttamente dalla politica first-wins.

La capacita non va aumentata per nascondere un ciclo infinito di reazioni. Ogni
nuova famiglia causale deve aggiungere un test di bordo e mantenere osservabile
`dropped_count`.

## Estendere la timeline

Per presentare un nuovo `Game_Event`:

1. assicurarsi che l'evento contenga tutto il payload necessario a ricostruire
   la variazione dallo snapshot, inclusi target e valori prima/dopo impliciti;
2. aggiungere il relativo `Presentation_Cue_Kind`;
3. mappare l'evento in `presentation_cue_kind`;
4. scegliere una durata in `presentation_cue_duration`;
5. applicare la mutazione visuale iniziale in `start_presentation_cue`;
6. implementare l'interpolazione in `update_active_presentation_cue`, se serve;
7. completare lo stato differito in `finish_presentation_cue`;
8. disegnare il feedback in `isometric_renderer.odin` leggendo cue e snapshot;
9. testare ordine, stato intermedio, completamento e avanzamento con `dt` in eccesso.

`presentation_cue_kind` considera esaustivo l'enum degli eventi: aggiungere un
evento di gameplay senza la relativa mappatura e un errore di contratto, non un
caso da ignorare silenziosamente.

Una visualizzazione non deve interrogare la `Room` finale per recuperare dati
mancanti al cue. Se il payload non basta, va esteso il `Game_Event`; altrimenti
la timeline puo mostrare una causa insieme all'effetto di un momento successivo.

## Aggiungere un comando

Per rendere bufferizzabile una nuova azione del player:

1. aggiungere kind e payload a `Gameplay_Command` usando ID o valori stabili;
2. produrre il comando nella fase di polling senza modificare la `Room`;
3. gestirlo in `execute_gameplay_command` tramite una API autorevole;
4. definire con precisione quando il risultato e committed;
5. lasciare che `commit_gameplay_command` catturi entrambi gli snapshot e il log;
6. aggiungere test per copia del payload, first-wins, consumo e rivalidazione.

Non inserire puntatori a elementi della mano, indici di nemici o coordinate
derivate dal renderer nel buffer. Possono diventare obsoleti prima del consumo.

## Test e debug

I test mirati sono:

```sh
odin test src/render
odin test src/game
```

La verifica completa include anche il package principale e le regole di stile:

```sh
odin test src -all-packages -define:ODIN_TEST_THREADS=1
odin check src -vet -strict-style
```

Sintomi comuni e controlli:

| Sintomo | Controllo |
|---|---|
| salto visuale a meta sequenza | ordine eventi, payload `from/to` e mutazione in `start`/`finish` |
| danno su un attore scomparso | ID del target, ordine rispetto a `Entity_Defeated`, `update_failures` |
| ultimo feedback tagliato | guardia `timeline idle` prima di `finish_room` |
| input apparentemente perso | slot gia occupato e `Buffered_Gameplay_Command.dropped_count` |
| comando vecchio nella stanza nuova | reset del buffer nel cambio di contesto |
| preview diversa dall'esito | targeting ancora attivo mentre la timeline e busy |
| coda incompleta | `Event_Log.dropped_count`, `Presentation_Timeline.dropped_count` e limite 416 |

I test della timeline devono controllare lo stato durante il cue, non soltanto il
risultato finale. Il risultato finale puo sembrare corretto anche se due eventi
sono stati mostrati nell'ordine sbagliato.

## Limiti intenzionali

La timeline serializza tutti gli eventi. Oltre 12 secondi comprime le durate ma
non raggruppa cue in parallelo. Un vero batching richiederebbe un identificatore
esplicito di azione o gruppo nel log; dedurlo dal tipo o dalla vicinanza degli
eventi sarebbe ambiguo.

Il buffer conserva una sola intenzione e non e una macro queue. Questa scelta
favorisce decisioni leggibili e impedisce di inviare molti pulse senza osservarne
le conseguenze. Eventuali combo o azioni simultanee dovranno essere modellate
come comandi e azioni di gameplay espliciti, non aumentando implicitamente la
profondita del buffer.
