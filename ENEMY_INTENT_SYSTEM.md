# Enemy Intent System

Questa guida descrive come i nemici dichiarano in anticipo la propria prossima
azione. Gli intenti appartengono alla simulazione: il renderer li visualizza, ma
non prende decisioni e non ricalcola il comportamento dell'IA. Le primitive
condivise per traccia e blocker sono descritte in
[Targeting System](TARGETING_SYSTEM.md).

## Indice

- [Obiettivo](#obiettivo)
- [Modello](#modello)
- [Lifecycle committed](#lifecycle-committed)
- [Pianificazione deterministica](#pianificazione-deterministica)
- [Archetipi](#archetipi)
- [Incontri e modificatori](#incontri-e-modificatori)
- [Risoluzione](#risoluzione)
- [Bump attack](#bump-attack)
- [Eventi e reazioni](#eventi-e-reazioni)
- [Rendering](#rendering)
- [Invarianti](#invarianti)
- [Limiti attuali](#limiti-attuali)

## Obiettivo

Durante `Combat`, ogni comando accettato del player produce un pulse se il fight
rimane attivo. Prima che il player scelga, ogni nemico mostra gia cosa tentera
di fare durante quel pulse:

- `WAIT`: rimane fermo;
- `MOVE`: segue il percorso indicato verso una destinazione;
- `ATK N`: minaccia celle precise e infligge `N` danni base se il player rimane
  in una di esse;
- `CHG N`: attraversa il percorso indicato e tenta un impatto da `N` danni sulla
  cella minacciata;
- `BOMB 2`: lancia una bomba sull'anchor dichiarata, con due ulteriori azioni
  prima dello scoppio;
- `SHIELD 3`: il Custode proteggera l'alleato indicato dalla linea turchese;
- `RECOVER N`: resta fermo per i prossimi `N` impulsi.

La previsione e un impegno, non una stima aggiornata continuamente. Spostare il
player non permette al nemico di cambiare bersaglio all'ultimo momento. Questa
regola rende le celle colorate informazioni utilizzabili per prendere decisioni.

## Modello

Ogni `Enemy` possiede inline un singolo `Enemy_Intent`:

```odin
Enemy_Intent :: struct {
	kind:                  Enemy_Intent_Kind,
	origin:                grid.Position,
	destination:           grid.Position,
	path:                  [MAX_ENEMY_INTENT_PATH_CELLS]grid.Position,
	path_count:            int,
	threatened_cells:      [MAX_ENEMY_INTENT_THREAT_CELLS]grid.Position,
	threatened_cell_count: int,
	damage:                i32,
	planned_pulse:         u64,
	protected_ally:        Entity_Ref,
}
```

`origin` fotografa la posizione dalla quale il nemico ha pianificato. `path` e
`destination` descrivono un movimento, mentre `threatened_cells` e `damage`
descrivono un attacco. `planned_pulse` deve essere sempre
`room.pulse_count + 1` durante la fase decisionale del player.
Per `Protect`, `protected_ally` conserva l'ID dell'alleato e `destination` la sua
cella: servono entrambi, per evitare che uno spostamento faccia seguire il target.

L'intento non contiene una `Action` precompilata. Un target entita seguirebbe la
posizione corrente del player e perderebbe la cella telegrafata. L'intento resta
quindi un dato dichiarativo; soltanto durante la risoluzione viene costruita la
normale `Action` compatibile.

Gli array sono fissi: otto celle di percorso e sedici celle minacciate per
nemico. `Move` usa una cella di percorso, mentre `Charge` puo usarne diverse;
Attack e Charge minacciano una singola cella, Bombard un'area fino a 3x3.
Il modello non alloca memoria
durante il combattimento.

## Lifecycle committed

Il ciclo di un intento e:

```text
create_room
    |
    v
plan_enemy_intents                    intenti per pulse 1
    |
    v
input e Action del player             gli intenti non cambiano
    |
    v
esplosivi in scadenza                  danno prima dei nemici
    |
    v
Furnace in scadenza                    danno sulla corsia annunciata
    |
    v
resolve_enemy_intents                 Protect, poi gli altri piani salvati
    |
    v
tick status e reaction binding
    |
    v
incremento pulse_count + energia
    |
    v
plan_enemy_intents                    intenti per il pulse successivo
```

`create_room` genera il primo piano dopo aver inizializzato il combattimento del
deck. `advance_combat_pulse` risolve il piano corrente prima dei tick e ne crea
uno nuovo soltanto dopo aver incrementato `pulse_count`.

Un comando rifiutato, un movimento bloccato del player o una carta non giocata
non producono un pulse e non rigenerano gli intenti. Se il combattimento termina
in `Loot` o `Defeat`, `clear_enemy_intents` azzera ogni piano ancora presente.

## Pianificazione deterministica

`enemy_ids_in_planning_order` raccoglie gli ID dei nemici in un array inline e
li ordina in modo crescente. La pianificazione usa questo ordine; la risoluzione
esegue prima i `Protect` in ordine di ID, poi gli altri intenti nello stesso
ordine. L'ordine non dipende quindi dagli indici di `Room.enemies`, che possono
cambiare quando `unordered_remove` elimina un nemico.

Il planner copia le posizioni in un array temporaneo di massimo 32 elementi.
Quando assegna un movimento aggiorna soltanto questa simulazione, non la stanza.
I nemici successivi vedono cosi le celle che i precedenti intendono liberare e
occupare. Due intenti non possono prenotare la stessa destinazione.

Pareti, ostacoli, player e posizioni previste degli altri nemici bloccano una
destinazione. Il planner non usa RNG e non modifica posizioni, vita, status o
`pulse_count`. Aggiorna invece la fase del Demolitore e il relativo ciclo quando
la salute ha raggiunto la soglia prevista, prima di dichiarare il nuovo intento.

## Archetipi

`Enemy_Archetype` sceglie il planner, ma tutti gli archetipi producono lo stesso
`Enemy_Intent` e vengono risolti dallo stesso scheduler.

| Archetipo | Pianificazione |
|---|---|
| `Chaser` | attacco melee se adiacente; altrimenti un passo ortogonale verso il player |
| `Archer` | arretra se adiacente; attacca a distanza su una linea ortogonale libera; altrimenti usa il fallback del Chaser |
| `Brute` | attacco melee se adiacente; carica ortogonale a media distanza, poi recupero; altrimenti fallback del Chaser |
| `Bomber` | lancia una bomba a distanza Manhattan 2–5, poi recupera; da adiacente arretra o attacca, fuori portata si avvicina |
| `Custodian` | protegge un alleato entro due celle e linea libera; poi recupera; altrimenti si avvicina agli alleati o usa il fallback del Chaser |
| `Demolitionist` | miniboss a due fasi: alterna bombe, carica o avvicinamento limitato e recupero di due impulsi |

### Chaser

Una BFS dal player calcola le distanze attraverso pavimento, pareti, ostacoli
e oggetti solidi. Il campo viene ricostruito a ogni pianificazione usando due
buffer posseduti dalla Room e allocati durante `create_room`.
Il Chaser sceglie un passo ortogonale disponibile che riduce la distanza BFS;
a parita mantiene la preferenza per l'asse con distanza maggiore, poi X,
seguita da North, East, South, West. Puo cosi aggirare pareti e vicoli ciechi.
Se nessun passo e disponibile o il player e irraggiungibile, usa `Wait`.
Gli attori restano gestiti dalle prenotazioni ordinate per ID. La BFS viene
usata soltanto per nuovi piani: gli intenti committed non vengono ricalcolati
durante la risoluzione.

### Archer

L'Archer attacca quando il player e allineato sullo stesso asse, a distanza
Manhattan compresa tra due e cinque celle, e nessuna parete o ostacolo interrompe
la linea. L'intento minaccia la posizione corrente del player, non la linea
intera: uscire da quella cella provoca `Attack_Missed`.

`has_clear_orthogonal_line` riusa `trace_targeting_line` e
`targeting_path_blocker`. Pareti, ostacoli statici e regola di blocco restano
quindi coerenti con il targeting delle carte, senza dipendere dal renderer.

Quando il player e adiacente, prova in ordine nord, est, sud e ovest e conserva
la prima cella valida alla distanza massima trovata. Se non puo arretrare, usa un
attacco melee. Fuori dalla finestra di tiro si comporta come un Chaser.

### Brute

Il Brute pianifica `Charge` quando il player e allineato ortogonalmente a distanza
da due a quattro celle e il corridoio e libero. Il percorso termina sulla cella
immediatamente precedente alla posizione minacciata; l'impatto infligge il doppio
del suo attacco base. Se non puo caricare usa il comportamento del Chaser.

La demo assegna inoltre due punti vita extra ai Brute e li disegna piu grandi.
Questi modificatori appartengono alla costruzione della stanza, non al planner.

Ogni tentativo di Charge, incluso un impatto mancato o percorso bloccato,
imposta `recovery_pulses = 1`. Il prossimo intento e `Recover`: non muove e non
attacca, poi consuma il recupero. Il planner non decrementa il contatore.

### Bomber

`Bombard.destination` e la cella di arrivo della bomba. Il planner preferisce
la cella del player e poi una delle otto adiacenti libere da oggetti. Il lancio
supera le coperture; la zona viola indica l'area futura, distinta dal rosso dei
colpi immediati. Bombe gia attive e lanci prenotati condividono il limite di
quattro; i nemici prenotano anchor distinte in ordine di ID.

Il resolver conserva origine e anchor. Se la sorgente e stata spostata o la
cella non e piu disponibile, emette `Attack_Missed` senza cercare un nuovo
bersaglio. Dopo il tentativo il Bomber recupera per un impulso. Timer, danno
amico e catene sono in [Combattimento tattico](TACTICAL_COMBAT.md).

### Custodian

Il Custode sceglie un alleato a distanza Manhattan 1–2 con linea di vista libera,
anche diagonale. Preferisce gli alleati senza almeno tre punti Shield, piu vicini
al player; favorisce gli altri archetipi rispetto ai Custodi e risolve le parita
per ID. `Protect` salva origine, ID dell'alleato e cella dell'alleato.

La protezione concede tre punti Shield per due decisioni del player. Il resolver
applica una durata interna di tre impulsi, perche segue subito il tick degli
status dello stesso impulso. Dopo ogni tentativo il Custode recupera per un
impulso. Il recupero e consumato anche quando la protezione fallisce.

Spostare il Custode dalla sua origine, spostare l'alleato dalla cella dichiarata,
uccidere uno dei due o interrompere la linea con una copertura annulla il piano.
Non viene scelto un sostituto. Una protezione gia applicata resta uno Shield
ordinario: termina per danno assorbito o scadenza, senza un vincolo di distanza.

### Demolitionist

Il Demolitore compare nei nodi Boss, con 30 punti vita e attacco base 2. Non entra
nel campionamento casuale dei nemici comuni. Usa gli intenti esistenti; la fase
e visibile nella barra del boss.

| Fase | Sequenza e carica |
|---|---|
| 1, `Demolition` | bomba, recupero 1, carica da 4 danni base a distanza 2–4, recupero 2 |
| 2, `Overdrive`, vita <= 15 | due lanci consecutivi, carica da 6 danni base a distanza 2–6, recupero 2 |

Ogni bomba conserva miccia, area e danno del Bombarolo; il limite di quattro
bombe e condiviso. I lanci restano subordinati a distanza e celle disponibili.
Durante lo stadio di carica, da adiacente il boss attacca in mischia; senza una
linea valida puo tentare al massimo due avanzamenti o attese, poi recupera per
due impulsi e ricomincia dalle bombe. Anche una carica interrotta, mancata o
bloccata lascia l'intera finestra di recupero.

Il passaggio di fase avviene soltanto durante la pianificazione successiva:
attraversare la soglia non cambia danno, bersaglio o percorso gia dichiarati.
La nuova fase riparte dai lanci e conserva l'eventuale recupero gia guadagnato
dal player. `boss_phase`, `boss_cycle` e `boss_approach_pulses` sono stato del
nemico; il renderer non li modifica.

## Incontri e modificatori

Il generatore sceglie una composizione deterministica dal seed: `Powder Keg`
(Bombarolo e Chaser, con barili aggiuntivi nei nodi Combat), `Escort` (Custode e
Archer vicini, con linea iniziale libera) oppure `Assault` (Brute e Chaser).
Il budget rimanente aggiunge altri nemici; i nodi Boss garantiscono Demolitore e
Bombarolo. I primi nodi Combat usano `Powder Keg`.

Oltre la profondita 1, le stanze possono avere il modificatore `Furnace`: una
corsia evidenziata infligge tre danni base a player, nemici e oggetti danneggiabili.
Il primo colpo arriva dopo due azioni; i successivi ogni quattro impulsi, sempre
con due decisioni di preavviso. Prima si risolvono gli esplosivi in scadenza, poi
Furnace, poi il supporto e gli altri intenti nemici. Furnace puo quindi eliminare
un attaccante o accendere un barile prima del suo turno.

Il modificatore e annunciato nella stanza e non cambia corsia durante il fight.
La generazione verifica vie d'uscita iniziali dalla corsia entro due passi.
Le stanze iniziali e i nodi Boss restano `Calm`; a fine combattimento Furnace si
disattiva. Dettagli per il player e uso dei barili sono in
[Combattimento tattico](TACTICAL_COMBAT.md).

## Risoluzione

`resolve_enemy_intents` fotografa gli ID vivi in ordine crescente. Prima di
eseguire il piano di un nemico, lo rimuove dall'entita; in questo modo una
reazione o una morte non lascia dati gia consumati.

### Protect

Un primo passaggio consuma tutti i `Protect` in ordine di ID, verificando origine,
alleato, cella e linea di vista. Una protezione riuscita usa `Action.Trigger` e
`Status_Applied`; un fallimento registra `Attack_Missed` con l'alleato come target.
Il successivo passaggio salta gli ID gia risolti ed esegue gli altri intenti.
Questo ordine permette agli alleati di muoversi normalmente dopo aver ricevuto
lo scudo; lo spostamento forzato dal player ha gia avuto luogo e invalida il piano.

### Attack

L'attacco riesce soltanto se:

- il nemico esiste ancora ed e rimasto sulla propria `origin`;
- la posizione attuale del player e contenuta nelle celle minacciate.

Se una condizione non vale, il nemico consuma comunque la propria azione ma non
insegue il nuovo bersaglio. Il pulse registra `Attack_Missed`. In caso di hit
viene costruita una normale `Action.Attack`: difesa, Shield, danno, Thorns e le
altre reazioni attraversano la pipeline esistente.

### Move

Il movimento prova esclusivamente la `destination` salvata. Se il nemico non e
piu sulla propria origine oppure la destinazione e ora occupata, il piano viene
consumato senza scegliere una deviazione e il pulse registra `Move_Blocked`.

Se la cella e ancora valida, il resolver costruisce una normale `Action.Move`.
Il relativo evento `Moved` alimenta sia le reazioni sia l'animazione visuale.

Questa semantica permette al player di schivare una cella minacciata oppure di
entrare deliberatamente in una destinazione per bloccare un avanzamento. Non
esiste replanning a meta-pulse.

### Charge

La carica verifica di nuovo origine e intero percorso committed. Una parete, un
ostacolo, il player o un altro nemico comparsi su una delle celle previste
annullano tutto il piano e producono `Move_Blocked`; il nemico non cerca una
deviazione e non attacca da fermo.

Con il percorso libero, il resolver costruisce prima una `Action.Move` verso la
destinazione salvata. Se il player occupa ancora la cella minacciata, costruisce
poi una `Action.Attack` con il danno della carica. Se il player l'ha lasciata, il
movimento resta valido ma l'impatto produce `Attack_Missed`. Le due azioni
appartengono allo stesso intento e allo stesso pulse nemico.

## Bump attack

Premere una direzione contro un nemico adiacente esegue l'attacco melee base del
player senza spostarlo. Durante `Combat` il bump attack produce un pulse e lascia
quindi risolvere la risposta committed dei nemici.

Un colpo non letale lascia il player sulla propria cella, quindi l'intento
committed del nemico colpito puo ancora risolversi. Un colpo letale elimina
l'entita e il relativo intento. Se era l'ultimo nemico, il combattimento termina
prima di aprire un nuovo pulse; altrimenti gli altri intenti continuano in ordine
di ID.

Il bump attack rimane un'azione base accanto alle carte. Ripeterlo significa
accettare un nuovo pulse avversario a ogni colpo.

## Eventi e reazioni

Una risoluzione riuscita usa gli eventi gia esistenti:

- `Moved` per un movimento applicato;
- `Status_Applied` per lo Shield concesso dal Custode;
- `Damaged`, `Damage_Absorbed` ed eventuali eventi reattivi per un attacco.

I fallimenti committed aggiungono due eventi diagnostici al `Pulse_Report`:

| Evento | Significato |
|---|---|
| `Attack_Missed` | attacco, lancio o protezione invalidati senza cambiare il target dichiarato |
| `Move_Blocked` | la destinazione committed non e piu disponibile |

Questi due eventi vengono registrati direttamente dallo scheduler. Non aprono
una reaction queue: le definizioni attuali reagiscono agli effetti realmente
applicati, come `Damaged` e `Moved`.

Durante la risoluzione una reazione puo eliminare il nemico corrente o uno dei
successivi. Lo scheduler conserva soltanto ID, non puntatori o indici, e verifica
nuovamente l'esistenza dell'entita prima di usarla.

## Rendering

Il rendering e diviso in due passaggi:

- `draw_enemy_intent_ground` disegna percorsi, destinazioni e celle minacciate
  sopra il livello ma sotto il range della carta;
- `draw_enemy_intent_badges` disegna `WAIT`, `MOVE`, `ATK N`, `CHG N`, `BOMB 2`, `SHIELD 3` o `RECOVER N` sopra
  le entita, dopo i corpi dei nemici.

Le destinazioni di movimento usano un percorso ambra, mentre le minacce usano
un overlay rosso. Se piu attacchi condividono una cella, il renderer mostra il
numero di minacce. Passare il mouse sopra un nemico mette a fuoco il suo piano;
durante il targeting di una carta gli intenti vengono attenuati per lasciare
priorita alla selezione del player.

I corpi rendono leggibile l'archetipo anche senza badge: Chaser rosso e circolare,
Archer azzurro con un tratto orizzontale, Brute arancione, quadrato e piu grande.
Il Bomber e viola con una piccola bomba. `draw_explosive_ground` mostra anchor
future, footprint e scoppio; i countdown leggono lo snapshot durante la timeline.
Il Custode ha uno scudo turchese e una linea verso la cella dell'alleato protetto.
Il Demolitore ha una sagoma piu grande, barra vita dedicata e colore che cambia
in fase 2. La corsia Furnace e evidenziata durante il preavviso e lo scatto.

Il renderer legge esclusivamente `Enemy.intent`. Non sceglie target, non verifica
collisioni e non modifica la simulazione. Le animazioni continuano a derivare
dagli eventi applicati, non dalla previsione.

![Intenti committed dei nemici](odin_pp_enemy_intents.png)

![Tre archetipi e carica telegrafata](odin_pp_enemy_archetypes.png)

## Invarianti

`validate_enemy_intent` e `validate_enemy_intents` controllano che:

- ogni nemico vivo in `Combat` abbia un intento diverso da `None`;
- ogni intento appartenga a `room.pulse_count + 1`;
- l'origine coincida con la posizione del nemico al momento del piano;
- `Wait` e `Recover` non abbiano percorso, minacce o danno;
- `Protect` abbia un ID alleato, una cella entro due passi e nessun percorso,
  minaccia o danno; esistenza e posizione del bersaglio sono ricontrollate al resolve;
- `Move` abbia una destinazione adiacente, calpestabile e senza ostacolo statico;
- `Attack` abbia almeno una cella minacciata valida, senza duplicati, e danno
  positivo;
- `Charge` abbia un percorso ortogonale contiguo e senza duplicati, una
  destinazione uguale all'ultima cella, almeno una minaccia e danno positivo;
- fuori da `Combat` tutti gli intenti siano `None`;
- contatori di percorso e minacce restino entro le capacita fisse.

Ulteriori garanzie dello scheduler sono:

- ogni ID pianificato agisce al massimo una volta per pulse;
- un nemico morto prima del proprio turno viene saltato;
- l'ordine non cambia dopo una rimozione unordered;
- una destinazione o minaccia invalidata non viene sostituita durante il pulse;
- la pianificazione non muta il risultato del combattimento.

## Limiti attuali

- Ogni nemico produce un solo intento per pulse. `Charge` puo risolvere due
  `Action` ordinate, ma resta una sola decisione committed del Brute.
- Chaser e fallback avanzano di un solo passo. La BFS considera gli ostacoli
  statici; le prenotazioni evitano collisioni ma non pianificano lo smaltimento
  di code di nemici su piu pulse.
- La line of sight dell'Archer considera pareti e ostacoli statici, ma non tratta
  ancora gli altri nemici come copertura e non crea un proiettile persistente.
- Attacchi e cariche nemiche minacciano una sola cella; Bombard usa un 3x3.
- La preparazione di una carica dichiarata dura una finestra decisionale; segue
  un impulso di recupero per il Brute, due per il Demolitore.
- Percorsi oltre otto celle e aree oltre sedici celle non sono rappresentabili.
- La simulazione si risolve subito e la timeline presenta gli eventi in FIFO. Non
  esiste ancora un `action_group_id`, quindi movimenti e attacchi di piu nemici
  non possono essere raggruppati in parallelo senza perdere causalita.

Traccia e blocker statici sono gia condivisi con il targeting delle carte. Gli
oggetti fisici vengono ricontrollati alla risoluzione: possono produrre
`Move_Blocked` su movimento/carica oppure `Attack_Missed` entrando nella linea
di tiro di un arciere senza cambiare il target committed. Le
future footprint nemiche dovranno consumare la stessa autorita geometrica e poi
essere copiate nell'intento committed. Il renderer deve continuare a ricevere
celle gia calcolate, senza reimplementare le regole.
