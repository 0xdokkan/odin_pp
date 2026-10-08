# Odin 2D Engine

Vertical slice di un roguelike con deck building e griglia isometrica 2D,
scritto in Odin con Raylib. La run attraversa sette livelli di una rotta
procedurale, fra combattimenti, ricompense e nodi speciali, fino al Demolitore.
Carte, spinte, esplosivi, status e reliquie condividono una simulazione
deterministica, separata dalle animazioni.

Questo README raccoglie la documentazione del progetto: uso della demo,
contratti dei sistemi, riferimenti per sviluppare e lavoro ancora pianificato.
Per i dettagli delle API, ogni sezione rimanda ai sorgenti pertinenti.

## Indice

- [Avvio](#avvio)
- [Controlli e loop di gioco](#controlli-e-loop-di-gioco)
- [Verifica e smoke test](#verifica-e-smoke-test)
- [Architettura e ownership](#architettura-e-ownership)
- [Azioni, impulsi, status e reazioni](#azioni-impulsi-status-e-reazioni)
- [Targeting e movimento](#targeting-e-movimento)
- [Oggetti, esplosivi e loot](#oggetti-esplosivi-e-loot)
- [Carte e ciclo del mazzo](#carte-e-ciclo-del-mazzo)
- [Spell e dadi](#spell-e-dadi)
- [Nemici e combattimento tattico](#nemici-e-combattimento-tattico)
- [Rotta e generazione delle stanze](#rotta-e-generazione-delle-stanze)
- [Ricompense, economia e nodi speciali](#ricompense-economia-e-nodi-speciali)
- [Reliquie](#reliquie)
- [Timeline e input](#timeline-e-input)
- [Sprite e animazioni personalizzate](#sprite-e-animazioni-personalizzate)
- [Telemetria e playtest](#telemetria-e-playtest)
- [Odin: appunti per lo sviluppo](#odin-appunti-per-lo-sviluppo)
- [Roadmap e manutenzione](#roadmap-e-manutenzione)

## Avvio

Serve Odin con i binding e le librerie native Raylib della distribuzione.
La toolchain registrata nelle verifiche precedenti del progetto è
`odin version dev-2026-08:8412dc37a`; non è un vincolo imposto automaticamente.
Eseguire i comandi dalla radice della repo:

```sh
odin run src
odin build src -out:odin_pp
odin run src -- --seed=0xC0FFEE --fast
```

`-o:none` permette build senza ottimizzazione. `--seed` accetta un `u64`
decimale o esadecimale con prefisso `0x`; seed e percorso scelto rendono la run
riproducibile per la versione corrente del generatore.

| Opzione | Uso |
|---|---|
| `--animation-speed=2` | velocità della timeline, fra 0.25x e 4x |
| `--fast` | velocità 4x |
| `--spell-lab` | arena con Firebomb, Fate Strike, Chain Lightning, Sundering Blow e Guard |
| `--dice-lab` | arena con Fate Strike, Sundering Blow, Prismatic Barrage, Twin Venom e Guard |
| `--sprites=/percorso/sprites.json` | manifest grafico alternativo |
| `--debug-abilities` | abilita gli shortcut di debug `C` e `V` |
| `--playtest-report` | registra una sessione interattiva |
| `--playtest-output=/percorso/sessione.json` | attiva la telemetria e sceglie il percorso di base |

Nei laboratori le carte sono già in mano, nell'ordine indicato; `F5` ricrea
l'arena con un nuovo seed. Restano attivi costi, pulse e risposta dei nemici.
Usare i laboratori senza opzioni smoke o report di playtest. Gli smoke grafici
mantengono velocità 1x per rendere riproducibile la cattura.

## Controlli e loop di gioco

Prima del primo combattimento si sceglie una reliquia fra tre offerte, oppure
si usa Skip. Ogni stanza parte con cinque carte e tre energia. I nemici
annunciano già il piano per la prossima risposta: schivare o spostare un
bersaglio può invalidarlo, senza permettere all'IA di cambiarlo all'ultimo momento.

Un comando accettato durante Combat concede un **pulse**, cioè una risposta
nemica, se lo scontro continua. Vale per movimento, bump attack, attesa,
abilità, carta e Refocus; una carta con più effetti costa al massimo un pulse.
I comandi rifiutati non avanzano il tempo di combattimento. Ogni pulse
rigenera un'energia, fino al massimo di tre.

Alla morte dell'ultimo nemico la stanza passa a Loot. Ci si può muovere senza
pulse, raccogliere i drop rimasti ed entrare sull'uscita verde. Una stanza non
finale offre tre carte: scelta o Skip aprono la mappa. Un Elite offre prima una
reliquia. Shop, Rest, Event e Treasure hanno schermate dedicate; il boss porta
a Victory, la morte del player a Defeat.

| Contesto / input | Azione |
|---|---|
| hover su carta | mostra regole, costo e range |
| trascina carta sulla griglia | anteprima di area, percorso, landing e blocker; il rilascio prova la giocata |
| `1`–`8` in Combat | gioca una carta non spaziale o seleziona una carta spaziale |
| click su cella | conferma il bersaglio della carta selezionata |
| `Esc` / click destro | annulla selezione o drag |
| `WASD` | un passo per pressione; contro un nemico esegue un bump attack senza muovere il player |
| `Spazio` | attende un pulse in Combat |
| `F` / Refocus | riordina la mano, concede un pulse e poi pesca il refill |
| `C`, `V` con `--debug-abilities` | Thorn Coat e Afterimage |
| frecce / trascinamento rotella | muove la camera |
| rotella / `R` | zoom ancorato al cursore / inquadra il livello |
| `M` | mostra o nasconde la rotta nella stanza, a timeline idle |
| click / `1`–`3` in Reward, scelta reliquie o mappa | sceglie una delle opzioni |
| `S` / Skip | salta la ricompensa di carte o reliquie |
| click / `1`–`3` nello Shop | acquista una carta |
| click su carta posseduta | seleziona l'istanza da migliorare o rimuovere |
| `U`, `R` nello Shop | upgrade / rimozione della selezione |
| frecce nello Shop o al Rest | pagina del deck, otto carte per pagina |
| `Enter`, `Esc` / Continue nello Shop | esce; il pulsante Shop sulla mappa riapre lo stesso vendor |
| `1` in Rest, Event, Treasure | Recover, prima scelta Event o Claim |
| `2` in Rest o Event | upgrade della selezione o seconda scelta Event |
| `U` al Rest | upgrade della carta selezionata |
| `L` / Leave | risolve un nodo speciale senza ricompensa |
| `Enter` / Continue dopo il risultato | completa il nodo speciale e torna alla mappa |
| `Enter` / Restart in Defeat | avvia una nuova run |
| `F5` | nuova run o laboratorio, con seed diverso |
| `F1`, `F2`, `F3` | scaling fit con letterbox, integer, stretch |
| `F4` | cambia velocità: 1x, 2x, 4x |
| `F11` | fullscreen borderless |

Per spostare un barile serve **Shove in mano, un'energia e adiacenza
ortogonale**. Trascinare la carta sul corpo del barile oppure selezionarla e
cliccare: la spinta va di una cella lontano dal player. Camminargli contro in
Combat non lo spinge. Shove accende un barile spento anche se la spinta è
bloccata; l'esplosione arriva dopo altre due azioni accettate.

## Verifica e smoke test

[Lo script di verifica](scripts/check.sh) esegue controllo statico, suite di tutti
i package e link della demo, sia con assert attivi sia con `-disable-assert`.
I binari sono temporanei; `ODIN` può indicare un compilatore alternativo.

```sh
sh scripts/check.sh
sh scripts/check.sh --headless
```

`--headless` omette le build della demo con finestra. I comandi utili per una
verifica mirata sono:

```sh
odin check src -vet -strict-style
odin test src -all-packages -define:ODIN_TEST_THREADS=1 -o:none
odin test src/game
odin test src/render
odin test src/combatdebug
```

Anche `src/grid`, `src/level` e `src/view` hanno test dedicati. I test del renderer
verificano la logica testabile; gli smoke con finestra verificano anche la resa
GPU. Un `libraylib.a` contenente `version https://git-lfs.github.com/spec/v1` è
un puntatore LFS, non un archivio collegabile: occorrono gli artefatti nativi
della toolchain. Era il limite dell'ambiente Linux dell'audit storico.

Gli smoke si eseguono con `odin run src -- <flag>`, uno alla volta. Quelli
grafici salvano lo screenshot nella directory di avvio e chiudono la finestra;
le immagini sono output rigenerabili, non prerequisiti del checkout.

| Flag | Screenshot / verifica |
|---|---|
| `--smoke` | `odin_pp_isometric.png` |
| `--smoke-generation` | `odin_pp_procedural_room.png` |
| `--smoke-map` | `odin_pp_route.png` |
| `--smoke-family=pillars` | `odin_pp_pillars.png` |
| `--smoke-family=ring` | `odin_pp_ring.png` |
| `--smoke-family=courts` | `odin_pp_courts.png` |
| `--smoke-family=cover` | `odin_pp_cover.png` |
| `--smoke-status`, `--smoke-loot` | `odin_pp_status.png`, `odin_pp_loot.png` |
| `--smoke-card` | `odin_pp_card_drag.png` |
| `--smoke-targeting` | `odin_pp_advanced_targeting.png` |
| `--smoke-spatial` | `odin_pp_spatial_targeting.png` |
| `--smoke-object`, `--smoke-fire` | `odin_pp_ice_block.png`, `odin_pp_fire.png` |
| `--smoke-content` | `odin_pp_content_pass.png` |
| `--smoke-movement` | `odin_pp_enemy_movement.png` |
| `--smoke-timeline` | `odin_pp_timeline.png` |
| `--smoke-deck-flow`, `--smoke-refocus` | `odin_pp_deck_flow.png`, `odin_pp_refocus.png` |
| `--smoke-reward`, `--smoke-shop` | `odin_pp_reward.png`, `odin_pp_shop.png` |
| `--smoke-rest`, `--smoke-event` | `odin_pp_rest.png`, `odin_pp_event.png` |
| `--smoke-treasure`, `--smoke-special-result` | `odin_pp_treasure.png`, `odin_pp_special_result.png` |
| `--smoke-intents`, `--smoke-archetypes` | `odin_pp_enemy_intents.png`, `odin_pp_enemy_archetypes.png` |
| `--smoke-tactics`, `--smoke-encounters` | `odin_pp_tactics.png`, `odin_pp_encounters.png` |
| `--smoke-miniboss`, `--smoke-furnace` | `odin_pp_miniboss.png`, `odin_pp_furnace.png` |
| `--smoke-defeat` | `odin_pp_defeat.png` |
| `--smoke-relics`, `--smoke-relic-combat` | `odin_pp_relics.png`, `odin_pp_relic_combat.png` |
| `--smoke-firebomb-spell` | `odin_pp_firebomb_spell.png` |
| `--smoke-dice`, `--smoke-dice-pool` | `odin_pp_dice.png`, `odin_pp_dice_pool.png` |
| `--smoke-chain`, `--smoke-spell-preview` | `odin_pp_chain.png`, `odin_pp_spell_preview.png` |
| `--smoke-sunder-preview` | `odin_pp_sunder_preview.png` |
| `--smoke-barrage`, `--smoke-twin-venom` | `odin_pp_barrage.png`, `odin_pp_twin_venom.png` |
| `--smoke-sprites` | `odin_pp_sprites.png`, caricamento, alpha, clip e fallback |
| `--smoke-playtest` | headless: al massimo venti decisioni, `odin_pp_playtest_smoke.json` |

Gli smoke di spell e impatti controllano anche il completamento del replay;
le preview non consumano RNG. Lo smoke sprite crea e rimuove asset diagnostici
temporanei. Per i report interattivi vedere [Telemetria](#telemetria-e-playtest).

## Architettura e ownership

| Percorso | Responsabilità |
|---|---|
| [src/main.odin](src/main.odin) | composizione della demo, schermate e transizioni |
| [src/app](src/app) | finestra, canvas virtuale e presentazione |
| [src/grid](src/grid) | `Grid(T)`, coordinate, memoria contigua, accesso sicuro |
| [src/level](src/level) | tile, layout e validazione topologica BFS |
| [src/game](src/game) | simulazione, azioni, carte, run, generazione degli incontri |
| [src/view](src/view) | scaling, camera e proiezione testabili |
| [src/render](src/render) | renderer Raylib, snapshot e timeline |
| [src/combatdebug](src/combatdebug) | observer, scenari headless e report |
| [src/gameplay_input.odin](src/gameplay_input.odin) | comandi logici, buffer e dispatcher |
| [src/runtime_options.odin](src/runtime_options.odin) | opzioni della sessione |

`grid` non conosce il gioco. `level` conosce la topologia, ma non difficoltà,
nemici o tipi di nodo. `game` non dipende dal renderer o dalla telemetria;
`combatdebug` legge `game`. Il rendering non modifica gameplay o RNG.
La griglia ha soltanto coordinate `(x, y)`: profondità visiva e ordine di
disegno derivano dalla proiezione isometrica. Il canvas virtuale è `960x540`.

`Run_State` possiede player, deck, reliquie, grafo e payload dei nodi. `Level`
possiede la propria `Grid(Tile)`. `Room` possiede nemici, trappole, ostacoli,
oggetti, loot e scratch buffer, ma prende in prestito `^Level` e `^Player`.
Il renderer possiede soltanto risorse e copie di presentazione.

La nuova stanza viene costruita in un `Room_Blueprint` e preparata con copie di
player, livello e stanza. Si valida tutto prima del commit; un fallimento libera
le risorse temporanee senza cambiare run, salute, oro, status, deck o RNG.
Nell'installazione si distrugge la vecchia Room **prima** del vecchio Level,
si trasferiscono gli owner e si riagganciano i puntatori alle destinazioni
stabili. Gli owner trasferiti vengono azzerati. Le grandi copie per valore di
Room restano negli helper di installazione, per evitare la scalarizzazione
LLVM osservata quando erano dentro `main`.

I riferimenti durevoli sono ID, mai puntatori o indici di array dinamici.
`Entity_Ref` contiene categoria e ID: player e sistema usano zero; nemici,
trappole e oggetti hanno ID stabili. Una rimozione `unordered_remove` può
cambiare l'indice, ma non il destinatario di un'azione già costruita.

## Azioni, impulsi, status e reazioni

Sorgenti: [action.odin](src/game/action.odin), [pulse.odin](src/game/pulse.odin),
[event.odin](src/game/event.odin), [status.odin](src/game/status.odin),
[reaction.odin](src/game/reaction.odin),
[reaction_definition.odin](src/game/reaction_definition.odin) e
[reaction_binding.odin](src/game/reaction_binding.odin).

### Azioni e commit

```text
Input / IA / trigger -> Action -> validazione -> effetti ordinati
                                            -> reazioni FIFO -> report
Il chiamante decide poi se avanzare il pulse.
```

Il target primario descrive la scelta; i destinatari degli effetti possono
essere diversi, come per un'area o una carta che colpisce e concede Shield.
Gli effetti comprendono `Damage`, `Heal`, `Gain_Gold`, `Move`,
`Apply_Status`, `Remove_Status`, `Add_Reaction_Binding`, `Draw_Cards`,
`Discard_Cards` e `Create_Card`.

Il resolver valida fase, sorgente, target e almeno un effetto inizialmente
applicabile, se presente. Ricontrolla poi ogni effetto nell'ordine dichiarato:
un effetto diventato invalido incrementa `skipped_effects`, senza annullare
quelli già applicati. Per esempio, Shove può infliggere danno e saltare la
spinta se il bersaglio muore. Un'azione vuota come Wait resta valida.

`resolve_action_once` risolve una sola azione; `resolve_action` aggiunge il
dispatch reattivo. Nessuno dei due avanza il pulse. La transazione della carta
paga energia e cambia zone del deck, ripristinandole se l'intera azione è
rifiutata: non offre rollback globale degli effetti di un'azione già accettata.

### Ordine del pulse e degli eventi

Dopo azione del player, reazioni e prima raccolta magnetica, se Combat continua:

1. scoppiano gli esplosivi in scadenza;
2. si risolve l'eventuale corsia Furnace;
3. si risolvono i Protect, poi gli altri intenti nemici, ordinati per ID;
4. se il fight continua, avanzano gli status del player e poi dei nemici;
5. avanzano le durate dei binding; si rigenera energia se ancora in Combat;
6. aumenta `pulse_count`, si pianifica il prossimo intento o si svuotano i piani;
7. `Pulse_Advanced` registra pulse, energia recuperata/sprecata e tick;
8. seguono la raccolta magnetica post-pulse e l'eventuale pesca o refill.

Le fasi già concluse o terminali non eseguono i segmenti successivi non più
validi. Un'azione che elimina l'ultimo nemico prima della risposta non avvia
un pulse; muoversi in Loot non lo avvia. `Room.recent_events` conserva soltanto
l'ultimo comando e viene azzerato all'inizio del successivo.

### Status

Ogni combattente possiede uno `Status_Set` inline, con massimo otto status e
una sola istanza per tipo. Potenza e durata devono essere positive.

| Status | Stacking | Comportamento |
|---|---|---|
| Shield | somma saturata della potenza, durata maggiore | assorbe danno dopo la difesa; a zero viene rimosso |
| Poison | potenza e durata maggiori | danno di sorgente System a fine pulse, poi decremento della durata |
| Thorns | potenza e durata maggiori | contraccolpo per danno effettivo ricevuto da un avversario vivo |
| Afterimage | potenza e durata maggiori | dopo il proprio `Moved` in Combat concede Shield pari alla potenza, per due pulse |

Il danno al player segue `danno base -> difesa -> Shield -> salute`; i nemici
non hanno ancora una statistica difesa. Anche Poison usa questo percorso,
può essere assorbito e può concludere il fight. La durata applicata prima della
risposta nemica avanza già alla fine di quel pulse. L'ordine dei tick per entità
è Poison, Shield, Thorns, Afterimage.

Thorns non scatta su danno interamente assorbito, veleno o hazard neutrali.
Afterimage osserva solo il movimento terminale: un Dash di tre celle lo attiva
una volta. Il suo Shield arriva **dopo** gli hazard attraversati, ma prima della
risposta nemica. Nessuna reazione può essere costruita per un owner già morto.
Gli status sono locali alla stanza; non avanzano durante Loot o schermate della
run e si azzerano solo quando la nuova stanza viene installata con successo.

### Reazioni e limiti

Il dispatcher osserva gli eventi solo dopo gli effetti dell'azione radice.
Se la radice produce A e B e A genera C, la coda procede A, B, C. Le reazioni
sono normali Action risolte senza ricorsione. Una definizione dichiara trigger,
filtri, reactor, priorità e template; il binding runtime aggiunge owner,
potenza, cariche, durata e sorgente System, Ability, Card o Passive.

Le richieste sono ordinate per priorità decrescente e poi per `Reaction_Id`.
Il modificatore di priorità usa somma saturata. Cariche e durata usano `-1`
per illimitato, mai zero come stato attivo; una carica si consuma solo dopo
una reazione accettata. Esaurimento, scadenza e morte dell'owner rimuovono i
binding e producono la diagnostica prevista.

| Budget | Limite |
|---|---:|
| effetti per Action / nemici per Room | 32 / 32 |
| template per carta | 4, di cui al massimo un Move |
| eventi per log / cue di presentazione | 416 / 416 |
| richieste reattive per evento | 8 |
| azioni reattive per catena / binding per Room | 32 / 32 |
| oggetti / trappole per Room | 32 / 64 |

L'overflow di un log staged rifiuta la transazione. Gli eventi di
`Action_Report` alimentano anche le reazioni: perderli cambierebbe il gameplay,
quindi `record_report_event` termina esplicitamente in caso di esaurimento.
Solo le copie post-commit per storico e presentazione possono perdere eventi,
contando `dropped_count` e convergendo allo snapshot finale. Il limite anti-ciclo
delle reazioni è distinto e resta diagnosticabile.

Lo stress storico produce 258 eventi, con 158 slot di margine; il caso di dodici
celle con trappole ne produce 36. Nuovi effetti composti devono verificare il
proprio envelope, senza aumentare i limiti per nascondere cicli o overflow.
I template reattivi non rappresentano ancora Move o Add_Reaction_Binding;
gli eventi di scadenza dello scheduler vengono registrati ma non riaprono
catene reattive. Le definizioni restano tabelle compilate, non file esterni.

## Targeting e movimento

Sorgenti: [targeting.odin](src/game/targeting.odin),
[movement.odin](src/game/movement.odin) e [hazard.odin](src/game/hazard.odin).

### Geometria condivisa

`Targeting_Spec` distingue origine, range dell'anchor e forma colpita.
Il range limita **l'anchor**, non ogni bersaglio nell'area: un nemico sul bordo
della Firebomb può essere più lontano dal player del suo range di cast.
Manhattan misura `abs(dx) + abs(dy)`, Chebyshev `max(abs(dx), abs(dy))`;
minimo e massimo sono inclusivi.

| Forma | Regola |
|---|---|
| None | niente celle; target implicito Self, Player o None |
| Single | solo anchor, raggio zero |
| Line | esclude origine, include anchor; otto direzioni ortogonali o diagonali perfette |
| Cross | centro e quattro bracci fino al raggio; i muri possono fermare i singoli bracci |
| Square | lato `2 * radius + 1`; raggio uno produce un 3x3 |

Footprint fuori bounds o su celle staticamente bloccate vengono ritagliate,
senza duplicati. Un'area sul bordo può restare valida. Square non proietta
ombre fra le proprie celle. `requires_line_of_sight` e `stops_on_wall`
controllano il percorso di cast; la diagonale fra due blocchi ortogonali è
vietata. Un oggetto targetable può essere l'endpoint di un ray anche se opaco.
Gli attori non bloccano la LoS; `stops_on_actor`, riservato a Line, include il
primo attore e ferma lì la footprint. Piercing Ray attraversa gli attori.

`evaluate_target_query` è pura. Restituisce percorso, footprint, target,
blocker e ID nemici ordinati; `error == .None` è il verdetto completo.
`anchor_reachable` serve a mostrare il range, ma non garantisce una giocata:
un'area vuota può produrre `No_Effects`. L'energia viene controllata da
`play_card`, fuori dalla query geometrica.

Preview, drop e compilazione usano `evaluate_card_targeting`. Se una carta
sposta un'entità, questa valutazione include anche `Movement_Query`:
anchor e destinazione del movimento sono concetti distinti. Il renderer
visualizza questi risultati senza ricostruire geometria o selezionare bersagli.

I limiti sono range 12, raggio 4, traccia e movimento 12 celle, footprint 81
celle. Specifiche incoerenti, linea non allineata, target invalido, blocker e
capacità superata producono errori espliciti. La compilazione distingue fra
l'altro `Target_Out_Of_Range`, `Target_Blocked`, `No_Effects` e
`Too_Many_Effects`; nessuna giocata viene troncata silenziosamente.

### Percorsi e hazard

| Modalità | Validazione e applicazione |
|---|---|
| Traverse | intera linea in una delle otto direzioni, ogni cella libera da blocker e attori |
| Teleport | solo landing; ignora geometria, attori e hazard intermedi |

Entrambe verificano la destinazione; `Teleport` non permette un atterraggio
illegale. Movimento e LoS hanno query separate: `cell_blocks_movement` e
`cell_blocks_line_of_sight`. La geometria statica viene controllata prima degli
attori. Un oggetto mobile non può sovrapporsi ad alcun altro oggetto, incluso
Fire, anche se un attore potrebbe attraversarlo.

Il resolver ricontrolla la query prima dell'applicazione. Ogni ingresso produce
`Movement_Step`, l'ultimo `Moved`; subito dopo si risolve la trappola e poi
l'eventuale oggetto pericoloso, se l'attore è vivo:

```text
Movement_Step / Moved -> Trap_Triggered -> danno
                     -> Hazard_Triggered -> danno -> eventuale morte e drop
```

Le trappole si disarmano; Fire resta e infligge due danni a ogni ingresso in
Combat o Loot. Wait e permanenza sul fuoco non causano tick. Traverse risolve
tutte le celle; Teleport solo la landing. Se un hazard uccide il mover, il
percorso si ferma e l'ultimo step viene promosso a Moved, senza inventare celle
attraversate. Gli oggetti spinti non attivano hazard o trappole.

Shove e Grappling Hook applicano danno, poi movimento opzionale; un blocker
non annulla il danno. Dash contiene solo Move: il percorso deve essere valido
prima di pagare. Tutte e tre usano Traverse. Grappling Hook si ferma al primo
attore e trascina il bersaglio fino alla cella adiacente al player.
Spostare un nemico non aggiorna il suo intento già committed: il piano stale
produce miss o blocco, poi viene ripianificato per il pulse successivo.

## Oggetti, esplosivi e loot

Sorgenti: [grid_object.odin](src/game/grid_object.odin),
[explosive.odin](src/game/explosive.odin), [room.odin](src/game/room.odin).

### Oggetti sulla griglia

`Grid_Object_Definition` contiene capability immutabili; l'istanza conserva ID,
posizione, HP e `detonation_pulse`. Collisione, LoS, targeting, danno,
movimento, pericolosità ed esplosione sono proprietà indipendenti. Non esiste
un generico `is_occupied`: loot, trappole e Fire hanno regole diverse dai solidi.

| Oggetto | Movimento / LoS | Interazione |
|---|---|---|
| Ice Block | blocca entrambi | 4 HP, selezionabile, danneggiabile e spostabile |
| Fire | attraversabile / trasparente | 2 danni all'ingresso; non selezionabile, danneggiabile o spostabile |
| Barrel | solido / trasparente | spostabile; in Combat il danno accende la miccia |
| Bomb | attraversabile / trasparente | spostabile, nasce accesa dal lancio del Bombarolo |

Gli oggetti hanno storage preallocato per 32 istanze e ID monotoni non nulli.
Lo spawn iniziale rifiuta sovrapposizioni con attori, uscita, spawn, trappole,
ostacoli e altri oggetti, anche per Fire. Lo spawn runtime di una bomba può
invece avvenire sotto un attore; non sopra un altro oggetto o un ostacolo.
Un fallimento non consuma ID. Una spinta può portare ghiaccio su una trappola,
ma non la disarma. La distruzione di oggetti non conclude Combat: contano i
nemici vivi. Gli oggetti non ricevono status, Shield, difesa o cure degli attori.

`Opponent_Or_Object` permette a Shove, Strike e Arc Bolt di selezionare un
oggetto valido. Il picking riconosce anche il corpo rialzato, mentre aree e
Dash usano il pavimento; un attore disegnato sopra una bomba mantiene priorità.
La preview Shove indica `PUSH 1`, `BLOCKED` o `BREAKS` quando il ghiaccio morirà
prima della spinta. Durante Loot il bump può rompere i solidi spostabili,
senza pulse, per liberare corridoi o uscita.

### Micce e combinazioni

Una bomba o un barile acceso infligge **4 danni base nel 3x3** a player, nemici
e oggetti danneggiabili. La footprint esclude muri, ostacoli fissi e fuori
bounds; non richiede LoS fra le celle dell'area. Difesa e Shield valgono
normalmente. Preview e danno condividono le stesse celle.

La miccia misura decisioni accettate, non secondi: dopo il comando che accende
l'esplosivo restano due ulteriori azioni. Alla seconda, lo scoppio precede gli
intenti nemici. Un comando rifiutato non consuma miccia. Spostare o colpire un
esplosivo acceso non ne rinvia la scadenza; il solo danno a un esplosivo già
acceso viene rifiutato. Shove resta valido se riesce a spostarlo.

- Strike, Arc Bolt e Firebomb accendono i barili; Firebomb può colpire soltanto oggetti.
- Shove accende e sposta un barile spento; anche con movimento bloccato il danno può essere valido.
- Spostare un barile accanto a Fire, a distanza ortogonale uno, accende la miccia.
- Un'esplosione che accende un altro barile avvia una nuova miccia: la catena è ritardata.
- Il limite è quattro **bombe** accese, condiviso fra lanci e prenotazioni; i barili hanno micce indipendenti.
- Uccidere il lanciatore non cancella una bomba se il fight continua.
- A fine Combat tutte le micce vengono disinnescate. Morte simultanea del player e dell'ultimo nemico produce Defeat.

Gli eventi `Object_Spawned`, `Explosive_Armed`, `Explosion` ed
`Explosive_Disarmed` mantengono countdown e replay osservabili.

### Loot magnetico

Il magnete raccoglie in Combat e Loot entro distanza Chebyshev tre, quindi
un quadrato massimo 7x7. Si controlla dopo l'azione accettata, dopo il pulse e
dopo gli spostamenti in Loot. La raccolta non paga energia o pulse e ignora
LoS, muri, ostacoli, trappole e uscita: raccogliere da quelle celle non significa
entrarci.

Ogni raccolta usa una normale Action Collect con Gain_Gold o Heal e rimuove il
drop soltanto se accettata. Una cura a vita piena viene consumata con guarigione
effettiva zero. `Loot_Dropped` precede `Loot_Collected`, poi Gold_Gained o Healed;
la simulazione assegna tutto subito, la timeline ne mostra il percorso.
`create_room` prealloca il drop d'oro di ogni nemico più i drop curativi previsti,
così il resolver non deve far crescere il buffer durante le uccisioni.

## Carte e ciclo del mazzo

Sorgenti: [card.odin](src/game/card.odin), [card_play.odin](src/game/card_play.odin),
[deck.odin](src/game/deck.odin) e [refocus.odin](src/game/refocus.odin).

### Definizioni, istanze e compilazione

Una `Card_Definition` contiene nome, rarità, peso, prezzo, costo, policy,
targeting e fino a quattro effect template. Una `Card_Instance` contiene ID
non nullo, definizione, upgrade e lifetime. La Action compilata è temporanea:
non resta nel mazzo. La compilazione valida fase, istanza e definizione,
riesegue targeting e movimento, espande i destinatari per ID e controlla la
capacità prima di produrre effetti. Non paga energia e non modifica RNG.

I selettori sono `Chosen_Entity`, `Player`, `Each_Enemy` ed
`Each_Affected_Enemy`. Un template Move deriva la destinazione come
`Player_To_Anchor`, `Away_From_Player` o `Adjacent_To_Player`. Create_Card
richiede una definizione esplicita con `has_card_definition = true`.
Lo scaling ordinario è `base_amount + amount_per_upgrade * upgrade_level`,
con livello 0–10 e controllo overflow in `i64`. Durata, cariche e costo non
scalano automaticamente.

### Ownership, zone e risorse

| Dato | Regola |
|---|---|
| `owned` | massimo 32 permanenti; rimozione consentita fino al minimo di 5 |
| carte temporanee | massimo 16 presenti nel runtime, mai in owned |
| draw / discard / exhaust | ciascuno può contenere tutte le 48 carte runtime |
| mano | massimo 8; `hand_size = 5` è il target iniziale e di refill |
| resolving | uno slot interno, durante la giocata |
| energia | massimo 3, recupero 1 per pulse |
| ID | unico `next_card_id` monotono, senza riciclo |

Lo starter deck ha dieci carte: Strike, Arc Bolt, Piercing Ray, Shove,
Firebomb, Guard, Toxic Wave, Thorn Coat, Afterimage e Dash.
`begin_deck_combat` copia owned nel draw, imposta `combat_card_id_floor`,
mescola e pesca cinque carte. Fisher–Yates usa uno xorshift64* locale separato
dagli RNG della run. Si pesca dalla fine del draw in fondo alla mano; quando
serve, il discard diventa draw e viene rimescolato.

Una permanente compare esattamente in una zona durante Combat. Una carta con
lifetime `Combat` usa un ID almeno pari al floor del fight, non entra in owned
e scompare a fine stanza; gli ID consumati restano consumati. Una definizione
`temporary_only`, come Spark, non è collezionabile e ha peso/prezzo zero.
Lifetime ed Exhaust sono distinti: una permanente exhaustata torna nel prossimo
fight; una temporanea può essere scartata e rimescolata, ma viene sempre
exhaustata quando giocata. `finish_deck_combat` svuota tutte le zone, energia e
floor, conservando owned, upgrade, RNG e prossimo ID.

`validate_deck_state` verifica identità, lifetime, capacità e ownership.
`-define:DECK_DEEP_VALIDATION=false` alleggerisce solo le primitive interne:
i confini di transazione mantengono la validazione completa.

### Giocata ed effetti sul deck

```text
validazione e compilazione -> snapshot del deck -> pagamento
-> Hand → Resolving -> effetti e reazioni -> Discard oppure Exhaust
-> pulse se Combat continua -> pesca di rimpiazzo se possibile
```

Resolving impedisce alla carta di rimescolarsi e pescare se stessa durante i
propri effetti Draw. Una giocata rifiutata ripristina deck, energia, zone e RNG.
`Played`, `Combat_Ended` e `Player_Defeated` indicano tutti un commit avvenuto;
`card_play_was_committed` centralizza il controllo. Una giocata terminale non
produce pulse o rimpiazzo aggiuntivi.

Draw, Discard e Create sono normali effetti sequenziali **fino a N**:
Draw si ferma a mano piena o fonti vuote; Discard usa la carta più a sinistra;
Create inserisce temporanee in mano fino al limite di mano, budget o ID.
Create non usa RNG. Calculated Risk pesca prima di scartare; Volatile Study
crea prima la Spark e poi pesca. Un effetto successivo invalido non annulla
quelli precedenti. Purifying Guard concede Shield anche senza Poison da rimuovere.

Gli eventi `Card_Played`, `Card_Drawn`, `Card_Moved` e `Card_Created`
conservano identità completa, upgrade, lifetime e zone. Per Create, la zona
sorgente `.Count` significa assenza di origine. Il replay usa le stesse
primitive su una copia del deck e controlla anche gli ID e l'RNG del reshuffle.

### Refocus, Retain ed Ethereal

Refocus è la frontiera manuale della mano, non la fine di ogni pulse.
Osserva la mano originale da sinistra a destra: Retain resta in mano,
Ethereal va in Exhaust, le altre carte in Discard. Le due policy sono
mutuamente esclusive; `exhaust_on_play` è una regola distinta.

Il cleanup viene validato e committato, poi si concede un pulse e, soltanto se
Combat continua, si pesca fino a cinque contando le retained. Refocus non
resetta l'energia: vale la rigenerazione normale. Anche una mano vuota è
valida. Se il pulse conclude il fight o uccide il player, niente refill;
il cleanup resta committed.

`Hand_Refocused` precede un `Card_Refocused` per ogni carta originale,
compreso `Hand -> Hand` per Retain; seguono pulse, raccolta e refill.
Questi eventi non sono intercambiabili con Card_Moved senza normalizzare la
causa. F può essere bufferizzato durante la timeline, il pulsante è disabilitato.

### Catalogo delle carte

Nella tabella gli effetti sono al livello base, con gli incrementi indicati.
Le spell con dadi e rimbalzi sono descritte subito dopo. Rarità e metadati
completi restano in `CARD_DEFINITIONS`; l'upgrade è disponibile solo se
`card_can_upgrade` rileva un beneficio effettivo.

| Carta | Rarita | Costo | Anchor e forma | Effetto base |
|---|---|---:|---|---|
| `Strike` | Common | 1 | avversario o oggetto, Manhattan 1, Single | 3 danni, +1 per upgrade; accende barili |
| `Arc_Bolt` | Common | 2 | avversario o oggetto, Manhattan 1-3, Single, LoS | 3 danni, +1 per upgrade; accende barili |
| `Piercing_Ray` | Uncommon | 2 | cella, Chebyshev 1-5, Line | 2 danni a ogni nemico attraversato, +1 per upgrade |
| `Cross_Slash` | Uncommon | 2 | cella, Manhattan 1-3, Cross raggio 1 | 2 danni a ogni nemico nella croce, +1 per upgrade |
| `Firebomb` | Rare | 2 | cella, Chebyshev 1-3, Square raggio 1 | 2 danni a nemici e oggetti nel 3x3, +1 per upgrade; accende barili |
| `Guard` | Common | 1 | player, None | Shield 3 per 3 pulse |
| `Toxic_Wave` | Rare | 2 | implicito, None | Poison 1 per 3 pulse a ogni nemico |
| `Thorn_Coat` | Uncommon | 1 | player, None | Thorns 1 per 3 pulse |
| `Afterimage` | Uncommon | 1 | player, None | Afterimage 1 per 4 pulse |
| `Counter_Rune` | Rare | 1 | player, None | Retain; due contraccolpi, durata 4 pulse |
| `Battle_Focus` | Rare | 1 | player, None | Ethereal; pesca 2, poi exhaust |
| `Calculated_Risk` | Uncommon | 1 | player, None | pesca 2, poi scarta la carta piu a sinistra |
| `Spark_Forge` | Uncommon | 1 | player, None | crea una `Spark` temporanea |
| `Spark` | temporary only | 0 | avversario, Manhattan 1-2, Single | 2 danni, +1 per upgrade; exhaust on play |
| `Shove` | Common | 1 | avversario o oggetto, Manhattan 1, Single | 1 danno, +1 per upgrade; spinta di 1 cella |
| `Dash` | Uncommon | 2 | cella, Chebyshev 1-3, Line, LoS | attraversa la linea fino all'anchor |
| `Grappling_Hook` | Rare | 2 | avversario, Chebyshev 2-4, Line, LoS e actor stop | 1 danno, +1 per upgrade; trascina adiacente al player |
| `Heavy_Blow` | Common | 2 | avversario adiacente, Single | 5 danni, +1 per upgrade |
| `Venom_Needle` | Common | 1 | avversario, Chebyshev 1-3, Single, LoS | 1 danno, +1 per upgrade; Poison 1 per 3 pulse |
| `Caustic_Bloom` | Uncommon | 2 | cella, Chebyshev 1-3, Square raggio 1 | Poison 2, +1 per upgrade, per 2 pulse ai nemici nel 3x3 |
| `Purifying_Guard` | Uncommon | 1 | player, None | Shield 2, +1 per upgrade, per 3 pulse; rimuove Poison se presente |
| `Volatile_Study` | Rare | 2 | player, None | Ethereal; crea 1 `Spark`, pesca 1 + upgrade, poi exhaust |

## Spell e dadi

Sorgenti: [spell.odin](src/game/spell.odin), [dice.odin](src/game/dice.odin),
[spell_renderer.odin](src/render/spell_renderer.odin),
[dice_physics.odin](src/render/dice_physics.odin) e
[dice_playback.odin](src/render/dice_playback.odin).

`U` è il livello dell'istanza. Tutte queste carte costano due energia;
valori prima di difesa, Shield e reazioni:

| Carta | Rarità | Primo bersaglio con LoS | Effetto |
|---|---|---|---|
| Firebomb | Rare | cella calpestabile, Chebyshev 1–3 | `2 + U` danni ai nemici e oggetti validi nel 3x3 |
| Fate Strike | Uncommon | nemico, Manhattan 1–4 | `2 + U + D6`; con 6, possibile rimbalzo da `3 + U` |
| Chain Lightning | Rare | nemico, Manhattan 1–4 | `3 + U` a fino a tre nemici distinti |
| Sundering Blow | Uncommon | nemico allineato, Manhattan 1–2 | `2D6 + U`; somma dei dadi almeno 8: spinta di una cella |
| Prismatic Barrage | Uncommon | nemico, Manhattan 1–3 | `3D6`: ogni 4+ vale `3 + U` danni; ogni dado basso dà 1 Shield per due pulse |
| Twin Venom | Uncommon | nemico, Manhattan 1–3 | `1 + max(2D6) + U`; una coppia applica Poison 2 per due pulse al sopravvissuto |

Fate ha probabilità `1/6` di bonus; Sundering `15/36` di spinta, calcolata
sui soli dadi. Barrage aggrega i danni dei successi in un colpo, preceduto dallo
Shield: con zero successi è comunque una giocata valida da tre Shield.
La probabilità di almeno un successo è `7/8`. Twin Venom ha probabilità `1/6`
di coppia; l'upgrade non cambia potenza, durata o probabilità del veleno.

### RNG e percorso committed

`Player.dice` contiene uno stream e un contatore dedicati, indipendenti da
mazzo, mappa, incontri, reward e rendering. Il D6 usa rejection sampling per
non introdurre bias di modulo. `roll_d6_pool` prepara su copia fino a tre
facce e totale; `Dice_Rolled` rappresenta l'intero lancio. Il commit avviene
con l'effetto accettato; una giocata rifiutata non consuma dadi. Hover,
preview e compilazione non estraggono risultati.

`query_spell_path` sceglie tutti i destinatari prima della risoluzione. Ogni
salto parte dalla posizione precedente e cerca un nemico vivo non visitato,
entro tre passi Manhattan e con LoS. Vince il più vicino, poi l'ID minore.
Chain conserva massimo tre bersagli, Fate due. La preview numera i salti;
il secondo di Fate è tratteggiato e marcato `6 ONLY`, la spinta di Sundering `8+`.

Ogni colpo conclude le proprie reazioni prima del successivo. Morte del player,
fine combattimento o scomparsa del prossimo bersaglio interrompono il resto:
nessuna sostituzione o ricerca successiva. La carta rimane Resolving per tutta
la sequenza, pagando e avanzando il combattimento una sola volta.

### Impatti e presentazione dei dadi

`Spell_Launched` e `Spell_Impact` precedono i danni; Dice_Rolled precede il
lancio quando richiesto. Firebomb registra il 3x3 filtrato in `area_mask` e
assegna un `visual_group` ai feedback diretti compatibili: si animano insieme,
ma le mutazioni dello snapshot restano ordinate. Reazioni e rimbalzi restano
separati. Il renderer non interroga la stanza futura per ricostruire l'area.

I dadi rossi hanno mesh smussate, collisioni col piano e fra corpi, fino a tre
simultanei. La fisica è cosmetica, precalcolata a passo fisso una volta per
lancio. Le facce vengono orientate prima del playback per mostrare il risultato
committed, senza cambiare numeri durante la caduta; le facce opposte sommano sette.
I primi due urti danno spinte verticali di 12 e 9 unità/s e impulsi angolari;
seguono attrito e assestamento, senza leggere RNG del gameplay.

Il cue dura nominalmente 2,1 secondi a 1x, indipendentemente dal numero di dadi.
I primi contatti sono a 0,648, 0,972 e 1,224 secondi. Il loop limita l'avanzamento
per frame a 1/18 del tiro e mostra i contatti prima di proseguire; in quel caso
scarta il tempo eccedente. I seek espliciti dei test restano immediati.
Successi, massimo e coppia sono letti dalle facce registrate; la somma resta
visibile. Una render texture trasparente riutilizzata viene composta in
coordinate finestra dopo il canvas, anche nel letterbox e senza deformazioni
in Stretch. Le risorse GPU si liberano prima della finestra.

## Nemici e combattimento tattico

Sorgenti: [enemy_intent.odin](src/game/enemy_intent.odin),
[bomber.odin](src/game/bomber.odin), [custodian.odin](src/game/custodian.odin),
[miniboss.odin](src/game/miniboss.odin) e [room_modifier.odin](src/game/room_modifier.odin).

### Intenti committed

Ogni nemico conserva un `Enemy_Intent` per `pulse_count + 1`, con origine,
percorso, destinazione, celle minacciate e danno. Protect conserva anche ID e
cella dell'alleato. Il piano è un impegno sulle celle, non una Action con target
che segue il player. Viene creato all'ingresso e dopo ogni pulse, mai per un
comando rifiutato o durante la risoluzione corrente.

La pianificazione ordina gli ID e aggiorna una copia delle posizioni previste:
i nemici successivi vedono le prenotazioni, senza occupare la stessa
destinazione. Il planner non usa RNG; il Demolitore aggiorna fase e ciclo al
confine della nuova pianificazione. La BFS dal player usa scratch buffer della
Room e considera muri e oggetti solidi; gli attori sono gestiti dalle prenotazioni.

La risoluzione fotografa gli ID vivi, consuma prima i Protect e poi gli altri
intenti in ordine di ID. Ogni nemico agisce al massimo una volta; morti e
rimozioni unordered non invalidano l'iterazione. Eventuali spawn agiranno dal
pulse successivo. Origine spostata, cella liberata o percorso occupato producono
`Attack_Missed` o `Move_Blocked`, senza retargeting. Gli attacchi a distanza
ricontrollano anche la LoS. In Loot e Defeat i piani vengono azzerati.

### Archetipi

| Archetipo | Regole principali |
|---|---|
| Chaser | melee se adiacente, altrimenti un passo ortogonale che riduce la distanza BFS; Wait se impossibile |
| Archer | tiro ortogonale con LoS a Manhattan 2–5; da adiacente arretra o attacca; fuori finestra usa il Chaser |
| Brute | carica ortogonale a distanza 2–4, impatto doppio, poi recupero 1; altrimenti melee/Chaser |
| Bomber | lancia a Manhattan 2–5 anche oltre coperture, poi recupero 1; da adiacente arretra o attacca |
| Custodian | protegge un alleato a Manhattan 1–2 con LoS, poi recupero 1; altrimenti cerca gli alleati o avanza |
| Demolitionist | boss con 30 HP, attacco base 2 e ciclo a due fasi |

Il Chaser risolve le parità preferendo l'asse con distanza maggiore, poi X,
poi North, East, South, West. L'Archer prova le ritirate nello stesso ordine
cardinale e conserva la prima alla massima distanza. Il Brute verifica tutta
la carica: se il percorso è bloccato non muove né colpisce; se il player ha
schivato completa il movimento e manca l'impatto. Anche un tentativo fallito
lascia il recupero previsto.

Il Bombarolo preferisce la cella del player, poi una delle otto vicine libere
da oggetti; le anchor sono prenotate senza duplicati. Spostare il lanciatore
o occupare l'anchor invalida il lancio, che conserva comunque il recupero.

Il Custode preferisce alleati senza almeno tre Shield, vicini al player e di
altri archetipi; le parità si risolvono per ID. `SHIELD 3` concede protezione
per due decisioni del player: durata interna tre perché il primo tick segue
subito. Spostare Custode o alleato, ucciderli o interrompere la LoS invalida il
piano. Lo Shield già applicato non dipende più dalla distanza.

### Incontri, Furnace e boss

| Composizione | Coppia garantita |
|---|---|
| Powder Keg / Polveriera | Bomber + Chaser; due barili nei Combat |
| Escort / Scorta | Custodian + Archer vicini, con collegamento libero |
| Assault / Assalto | Brute + Chaser |
| Demolitionist | Demolitore + Bomber, nei nodi Boss |

Il budget può aggiungere altri nemici. I Combat di profondità 0–1 sono
Polveriera; i successivi Combat e gli Elite scelgono fra le prime tre ricette
in modo deterministico.

Furnace evidenzia una fila o colonna, fino a 16 celle, e infligge tre danni
base a player, nemici e oggetti. Il primo scatto segue due azioni accettate;
poi ci sono due pulse di pausa e due di preavviso, per una cadenza di quattro.
Si risolve dopo gli esplosivi e prima dei nemici, può accendere barili e non
crea Fire persistente. La corsia resta fissa. Profondità 0–1 e Boss sono Calm;
a fine Combat Furnace si spegne.

| Fase del Demolitore | Ciclo |
|---|---|
| Demolition | bomba → recupero 1 → carica da 4 danni, range 2–4 → recupero 2 |
| Overdrive, HP ≤ 15 | due lanci → carica da 6 danni, range 2–6 → recupero 2 |

La transizione avviene alla prossima pianificazione: non cambia un attacco
annunciato e conserva il recupero guadagnato. Senza linea per caricare, il boss
prova al massimo due avvicinamenti o attese, poi recupera e riparte dai lanci.
Il Bombarolo di supporto agisce anche durante le pause del boss.

La presentazione distingue `WAIT`, `MOVE`, `ATK N`, `CHG N`, `BOMB 2`,
`SHIELD 3` e `RECOVER N`, senza prendere decisioni. I limiti per intento sono
otto celle di percorso e sedici minacciate; la BFS non pianifica ancora code
su più pulse e gli altri nemici non sono copertura per l'Archer.

## Rotta e generazione delle stanze

Sorgenti: [run.odin](src/game/run.odin),
[run_validation.odin](src/game/run_validation.odin),
[room_generation.odin](src/game/room_generation.odin),
[encounter_director.odin](src/game/encounter_director.odin),
[room_generation_objects.odin](src/game/room_generation_objects.odin) e
[level.odin](src/level/level.odin).

### Rotta e seed

La rotta è un DAG a livelli: un Combat iniziale, un Boss finale, due o tre nodi
per livello intermedio con esattamente uno speciale e almeno uno con stanza.
Gli archi portano solo al livello successivo, senza duplicati, con massimo tre
uscite; ogni nodo è raggiungibile dall'inizio e conduce al boss.
Il ciclo speciale è Shop → Rest → Event → Treasure, con offset dal seed.
`validate_run_map` ricontrolla distribuzione, collegamenti e room seed.

`room_seed` deriva da seed run, ID, profondità, tipo del nodo e salt dedicato,
senza consumare RNG della rotta, deck o reward. Layout ed encounter hanno
stream separati; famiglia, ricetta e modificatore hanno salt distinti.
La casualità grafica non deve cambiare alcuno di questi risultati.

`last_room_family` esclude la famiglia dell'ultima stanza **installata**,
anche passando da nodi speciali. Si aggiorna solo al commit e si azzera al
restart; un ingresso fallito non consuma storico. Lo stesso nodo raggiunto da
una famiglia precedente diversa può quindi cambiare geometria. Il determinismo
vale per la versione corrente: un futuro save basato sul seed richiede versione
del generatore e golden vector per le migrazioni.

### Layout e placement

| Famiglia | Geometria |
|---|---|
| Pillars | quattro isole di copertura e corsie |
| Ring | blocco centrale aggirabile sui due lati |
| Twin Courts | due cortili separati, con due passaggi indipendenti |
| Asymmetric / Broken Cover | parete a L e copertura isolata, specchiate dal seed |

Combat usa 15x9, Elite 17x10, Boss 19x11. Prima si costruisce la forma, poi
spawn e uscita con clearance e distanza minima. Le famiglie tattiche richiedono
almeno 13x9. `Scattered` resta il default generico e la sentinella dello
storico iniziale; la demo non vi ripiega quando una famiglia fallisce.
I tentativi sono limitati e restituiscono errori espliciti.

La BFS valida un solo spawn e un'uscita, bordo, clearance, spazio disponibile
e connessione di tutte le celle aperte. `min_spawn_exit_distance` usa distanza
Manhattan; il report conserva anche la lunghezza del percorso minimo BFS.
Soltanto dopo questa verifica `game` spende il budget degli incontri:
Chaser costa 1, Archer/Bomber/Custodian 2, Brute 3, Demolitionist 6.
Il boss compare esattamente una volta e non entra nel campionamento comune.

La coppia della ricetta è adiacente o allineata a distanza due con collegamento
libero. Il placement cerca coperture con più approcci per Archer, corsie di
almeno tre celle per Brute e Demolitore, spazio per Bomber e prossimità per
Chaser. Gli oggetti successivi conservano quelle opportunità e la LoS della
Scorta. Ostacoli che disconnettono il layout vengono rifiutati; un budget non
collocabile fa fallire il blueprint, senza ridurre di nascosto la difficoltà.

Il perimetro e i due accessi dei cortili sono riservati rispetto a ostacoli e
oggetti; nemici e trappole possono usarli. Combat contiene tre oggetti, quattro
in Polveriera; Elite e Boss sei. Si aggiungono barili, Ice Block e Fire usando
candidati già mescolati, senza consumare altro RNG o spostare gli spawn scelti.
La connettività considera anche Fire come cella da evitare, garantendo un
percorso iniziale senza danno da fuoco.

Ogni barile deve avere almeno due celle opposte libere: una per raggiungerlo,
una per la spinta. Il controllo finale include tutti i contenuti.
Furnace esclude spawn, uscita e solidi fissi; ogni cella segnata deve avere
un'uscita dalla corsia entro due passi, evitando oggetti e fuoco. Gli attori
sono esclusi da questo controllo statico. Se non esiste una corsia valida,
il modificatore resta Calm. Le condizioni durante il fight possono cambiare.

`Room_Blueprint` possiede layout e spawn fino al trasferimento; la validazione
ricalcola famiglia, composizione, budget, statistiche e modificatore prima
dell'installazione transazionale. Gli ID vengono assegnati dalla Room.
I test includono 1536 layout delle famiglie e 4096 combinazioni di seed,
profilo e famiglia precedente; i fallimenti devono riportare seed e nodo
riproducibili.

Per i livelli ASCII: spazio = Void, `.` = pavimento, `#` = muro, `+` = porta,
`@` = spawn, `>` = uscita.

## Ricompense, economia e nodi speciali

Sorgenti: [reward.odin](src/game/reward.odin), [economy.odin](src/game/economy.odin),
[shop.odin](src/game/shop.odin), [special_node.odin](src/game/special_node.odin).

### Reward e modifiche permanenti

`finish_room` chiude il deck runtime, completa il nodo e incrementa
`cleared_count`. Una stanza con uscite apre Reward; il boss porta direttamente
a Victory. Reward conserva tre `Card_Id` distinti, non istanze: gli ID si
consumano soltanto quando una scelta valida aggiunge la carta.

Le offerte combinano `reward_weight` della definizione e peso della rarità
Common/Uncommon/Rare per tipo di nodo e profondità, limitata a 12.
Il sampling è pesato senza rimpiazzo, in ordine stabile di catalogo.
Reward e Shop preparano offerta e avanzamento RNG su copie, confermandoli solo
dopo la validazione; gli stream sono separati dal deck e fra loro.
Le carte `temporary_only` sono escluse.

`choose_card_reward` modifica una copia del deck, valida la run risultante,
azzera l'offerta e passa a Choose_Path. Skip fa lo stesso senza creare carte.
Deck pieno lascia la reward aperta con Skip disponibile; indice errato, ID
esauriti e tentativi ripetuti non consumano risorse. Durante Reward non si
può scegliere un nodo della mappa.

Upgrade e rimozione richiedono deck inattivo e **ID della specifica istanza**.
Upgrade conserva identità, ordine, RNG e prossimo ID; remove compatta owned
senza riciclare ID e conserva almeno cinque carte. Il livello massimo è dieci.
`card_can_upgrade` richiede un beneficio effettivo: Battle Focus, Calculated
Risk, Spark Forge e Dash non sono migliorabili. Shop e Rest condividono la
query e la preview prima/dopo, restituendo `Upgrade_Unavailable` senza costi.

### Shop

Il vendor è un vero nodo della rotta: tre carte, un upgrade e una rimozione.
Ogni offerta può essere venduta una volta e ogni servizio usato una volta.
Acquisti e servizi lavorano su copie staged; solo il successo modifica deck,
oro e flag. Non consumano RNG. Deck pieno impedisce l'acquisto ma non i servizi
o l'uscita.

Con `d = min(depth, 12)` e rarità Common = 0, Uncommon = 1, Rare = 2:

| Acquisto | Prezzo, divisione intera |
|---|---|
| carta | `shop_base_price + d / 3` |
| upgrade | `2 + rarity + 2 * upgrade_level + d / 4` |
| rimozione | `4 + d / 4` |

I calcoli usano intermedi `i64` e validano il risultato `i32`. Oro insufficiente,
slot venduto, deck pieno/minimo, carta invalida o livello massimo lasciano tutto
invariato. `leave_shop` completa il nodo una sola volta e apre Choose_Path.
Finché resta il nodo corrente, `open_shop` lo riapre senza reroll; entrare nel
nodo successivo azzera il payload.

### Rest, Event e Treasure

Un nodo speciale non crea una Room vuota: `Run_State` possiede un payload
costruito e validato prima di cambiare nodo, fase, RNG o flag entered.
Si può entrare solo in un'uscita disponibile non già visitata.

| Nodo / evento | Scelte |
|---|---|
| Rest | recupera 30% della vita massima, minimo 1; oppure upgrade gratuito di un'istanza; oppure Leave |
| Blood Offering | paga 20% della vita massima per `8 + 2*d` oro; oppure rifiuta |
| Healing Spring | cura fino al 25% della vita massima; oppure ottieni `4 + d` oro |
| Forgotten Armory | aggiungi la carta offerta; oppure ottieni `5 + d` oro |
| Treasure | Claim assegna `7 + 2*d` oro e nella demo offre anche una reliquia; oppure Leave |

Event e carta dell'Armory derivano dal seed del nodo, indipendentemente da
pescate e rendering. Blood Offering richiede vita strettamente maggiore del
costo. Le cure non superano max_health; Recover a vita piena è valido con
beneficio zero. Overflow dell'oro, deck pieno, ID esauriti e upgrade invalido
non risolvono il nodo e non alterano lo stato.

Una scelta o Leave rende il payload `resolved` e mostra l'esito. Solo dopo
`continue_special_node` completa il nodo, incrementa `cleared_count`, azzera
il payload e apre Choose_Path, dopo l'eventuale scelta reliquia. Scelte e
Continue sono one-shot. Solo il payload pertinente alla fase può essere attivo;
nessuno di questi nodi avanza pulse o status. Hover, pagina e selezione
appartengono alla presentazione, non allo stato della run.

## Reliquie

Sorgenti: [relic.odin](src/game/relic.odin),
[relic_effects.odin](src/game/relic_effects.odin) e
[run_relic_reward.odin](src/game/run_relic_reward.odin).

Le reliquie durano per l'intera run e si azzerano al restart. La demo offre una
scelta iniziale, una dopo gli Elite prima delle carte e una dopo Claim al
Treasure. Le offerte dipendono da seed, nodo e inventario, senza duplicati o
reliquie già possedute. Se ne restano meno di tre, l'offerta si riduce;
con tutte e sei non compare. Scegliere o saltare è necessario per proseguire.

| Reliquia | Effetto | Sinergia |
| --- | --- | --- |
| Iron Knuckle | Il primo spostamento forzato riuscito di un nemico o oggetto in ogni impulso dà 1 Shield per 2 impulsi | Shove, Grappling Hook e barili |
| Ash Bookmark | Il primo Exhaust di ogni combattimento pesca una carta aggiuntiva | Battle Focus, Volatile Study, Ethereal |
| Swift Soles | La prima carta che sposta effettivamente il giocatore in ogni combattimento recupera 1 energia | Dash e riposizionamento |
| Venom Vial | La prima applicazione riuscita di Poison a un nemico in ogni combattimento ha potenza +1 | Venom Needle e Caustic Bloom |
| Guard Sigil | All'ingresso in combattimento dà 2 Shield per 3 impulsi | Avvicinamento e prime decisioni |
| Mending Thread | Alla fine di un combattimento vinto cura 2 HP | Recupero fra gli scontri |

Una spinta bloccata non attiva Iron Knuckle; camminare non attiva Swift Soles.
Venom Vial modifica soltanto il primo bersaglio valido. Ash Bookmark funziona
anche con l'Ethereal exhaustata da Refocus: la pesca bonus segue pulse e refill,
se Combat continua. Mending Thread cura una volta alla vittoria, mai alla
sconfitta o durante il giro Loot. Salute ed energia rispettano i massimi.

L'inventario vive nel Player; i limiti per fight si reimpostano all'installazione.
I bonus usano azioni ed eventi ordinari senza consumare RNG di combattimento;
Swift Soles produce `Energy_Gained` prima del prossimo Pulse_Advanced.
`create_run(..., with_relic_rewards = true)` abilita le offerte nella demo;
il default API resta false per gli scenari headless preesistenti. Offerte
obsolete, indici invalidi e tentativi ripetuti non modificano inventario,
deck o RNG.

## Timeline e input

Sorgenti: [presentation_timeline.odin](src/render/presentation_timeline.odin),
[frame_timeline.odin](src/render/frame_timeline.odin),
[gameplay_input.odin](src/gameplay_input.odin).

### Due stati, un solo gameplay

```text
comando -> snapshot prima -> simulazione sincrona -> eventi + snapshot finale
                                |                         |
                            Room finale            replay sulla copia
```

`commit_gameplay_command` cattura le viste prima e dopo
`execute_gameplay_command`. Solo un risultato committed avvia la timeline;
un comando senza eventi non la rende busy. Room è già nello stato finale,
mentre `Room_Presentation` riproduce gli eventi su una copia arretrata.
La copia non viene mai scritta nella simulazione.

La vista conserva attori, oggetti, trappole, loot, deck, status, reliquie,
famiglia, modifier e fase del boss. Gli ID restano validi anche se l'entità
è stata rimossa dalla Room. I cue rispettano il log: movimento, trigger,
Shield/danno, morte, drop e raccolta si mostrano nell'ordine causale.
Card_Played paga e sposta in Resolving; Draw riproduce reshuffle e RNG;
Create deve generare lo stesso ID; mismatch rollbackano la mutazione visuale.

`Explosion` nasconde la sorgente prima dei danni. Il countdown usa il pulse
dello snapshot. `Room_Hazard_Triggered` mostra Furnace e aggiorna la scadenza;
`Pulse_Advanced` sincronizza durate, energia, reliquie e nuova fase del boss.
La Fornace viene disarmata anche se il comando conclude Combat senza pulse.
Il set dei reaction binding non è copiato: i relativi eventi mostrano avvisi.

Di norma è attivo un cue; eventi contigui, compatibili e con lo stesso
`visual_group` esplicito possono animarsi insieme. Firebomb usa questa regola
per gli effetti diretti, applicando comunque le mutazioni in ordine e usando
la durata massima del gruppo. Somiglianza o vicinanza non autorizzano gruppi;
reazioni, movimenti e frontiere dei pulse restano separate.

Il delta residuo passa ai cue successivi, salvo i limiti per frame dei dadi.
Oltre dodici secondi nominali, la sequenza comprime proporzionalmente le durate.
`PRESENTATION_TIME_SCALE` maggiore di uno le allunga; la velocità runtime
0.25x–4x scala invece il delta, viene conservata fra stanze/restart e non cambia
il gameplay. Corpi animati usano un clock cosmetico; clip evento seguono il cue.

### Buffer e transizioni

Il buffer ha capacità **uno**, politica first-wins: durante una timeline si
conserva il primo comando discreto e si scartano i successivi. Alla fine viene
estratto una volta e rivalidato contro Room e fase d'origine. Memorizza valori
logici e ID, mai puntatori o indici visuali. Un Move nato in Combat non diventa
implicitamente un Move in Loot. Tenere un tasto premuto non genera repeat.

Mentre lo snapshot è arretrato, drag, drop, click spaziali, range e intenti a
terra sono sospesi; il drag attivo si annulla. La tastiera può bufferizzare
comandi discreti, con slot risolti contro la mano visibile: una carta pescata
non è disponibile prima del relativo cue. Nuove selezioni spaziali aspettano
che timeline e buffer siano idle. La camera resta indipendente.

`finish_room` e le schermate Reward, Victory e Defeat aspettano l'ultimo cue.
Restart, nuova stanza e cambio schermata svuotano timeline e buffer; anche
l'apertura manuale della mappa richiede idle e cancella il vecchio contesto.

### Diagnostica ed estensioni

Timeline e log hanno 416 slot; lo snapshot conserva 32 nemici, 64 trappole,
32 oggetti e 64 drop. `dropped_count` segnala perdite; `update_failures`
segnala eventi non applicabili. Il buffer espone offered, dropped e consumed.
Controllare lo stato intermedio dei cue nei test: la convergenza finale può
nascondere errori nell'ordine visuale.

Per un evento nuovo: payload sufficiente, mapping esaustivo a cue, durata,
mutazioni start/finish, interpolazione, disegno e verifica di ordine e delta
in eccesso. Il renderer non deve recuperare payload mancanti dalla Room futura.
Per un comando nuovo: kind e payload stabili, polling senza mutazioni,
API autorevole, criterio committed, snapshot e rivalidazione del buffer.

| Sintomo | Controllo |
|---|---|
| salto visivo / danno su entità scomparsa | ordine eventi, ID, payload from/to, start/finish, update_failures |
| ultimo feedback tagliato | guardia timeline idle prima della transizione |
| input perso | slot già occupato e contatori first-wins |
| comando vecchio nella stanza nuova | reset del buffer |
| preview diversa dall'esito | targeting attivo su snapshot arretrato |
| coda incompleta | dropped_count e budget eventi |

## Sprite e animazioni personalizzate

Il renderer può sostituire il corpo del giocatore, dei nemici e degli oggetti con PNG, sprite sheet PNG o GIF animate. Supporta anche clip per lancio, proiettile, impatto e danno, sincronizzate con gli eventi di combattimento. Gli indicatori di salute, le intenzioni e le micce restano gestiti dal gioco. Senza un asset valido continua a essere usata la grafica procedurale di quel tipo o effetto.

Non sono incluse nuove illustrazioni: il sistema permette di inserire le proprie immagini senza ricompilare.

### Avvio rapido

1. Crea `assets/sprites.json`, prendendo come riferimento [assets/sprites.example.json](assets/sprites.example.json).
2. Inserisci le immagini nelle posizioni indicate dal manifest. I percorsi dei file sono relativi alla cartella che contiene il manifest.
3. Avvia `odin run src`. Il manifest predefinito è `assets/sprites.json`, relativo alla directory di avvio.

Per usare un altro pacchetto:

```sh
odin run src -- --sprites=/percorso/del/pacchetto/sprites.json
```

Per cominciare con una sola immagine statica:

```json
{
  "version": 1,
  "sprites": [
    {
      "key": "player",
      "file": "player.png",
      "width": 32,
      "height": 48,
      "anchor": [0.5, 1.0]
    }
  ]
}
```

Non occorre specificare gli altri tipi. Riavvia il gioco dopo aver modificato il manifest o un'immagine; il caricamento avviene una sola volta all'avvio.

### Tipi e dimensioni

Le chiavi dei corpi, animate in loop durante l'attesa, sono `player`, `chaser`, `archer`, `brute`, `bomber`, `custodian`, `demolitionist`, `ice_block`, `fire`, `barrel` e `bomb`. Le clip evento usano le otto chiavi descritte più sotto. Ogni chiave può apparire una sola volta nello stesso manifest, che mantiene `version: 1`.

| Campo | Significato | Valore predefinito |
| --- | --- | --- |
| `file` | PNG o GIF; il formato viene riconosciuto dal contenuto | Obbligatorio |
| `width`, `height` | Dimensioni sul canvas con zoom 1; seguono lo zoom della camera | Dimensioni di un frame |
| `anchor` | Punto dell'immagine che coincide con la posizione dell'attore, oggetto o effetto, da 0 a 1 | `[0.5, 1.0]`, centro in basso |
| `columns`, `rows` | Griglia regolare dei frame di uno sheet PNG | `1`, `1` |
| `frames` | Numero di frame PNG usati, in ordine da sinistra a destra e dall'alto al basso | Tutte le celle dello sheet |
| `fps` | Velocità del loop in frame al secondo; ignorata dalle clip evento | `8` |

Lo zoom 1 usa tessere larghe 64 e alte 32 pixel. Per gli attori sono un buon punto di partenza immagini mostrate a 32 × 48 pixel; conviene assegnare sempre dimensioni esplicite se il file sorgente è grande. Gli sprite possono avere margini trasparenti: adatta `anchor`, per esempio `[0.5, 0.9]`, se i piedi non arrivano al bordo inferiore dell'immagine.

Le immagini vengono disegnate con filtro nearest-neighbor, adatto alla pixel art. La selezione usa l'alpha del frame visibile: la testa rialzata di uno sprite è cliccabile, mentre i margini trasparenti lasciano passare il puntatore. Il bersaglio resta sempre la cella dell'entità; portata, collisioni e regole delle carte restano invariati.

### GIF e sprite sheet

Per una GIF indica soltanto `file`, dimensioni, eventuale `anchor` e `fps`. Non impostare `columns`, `rows` o `frames`: i frame provengono dal file GIF. Le animazioni dei corpi vengono ripetute a velocità uniforme; le durate originali dei singoli frame GIF e il numero di ripetizioni non vengono usati. Raylib non espone le durate attraverso la funzione di caricamento impiegata.

Uno sprite sheet PNG deve avere dimensioni divisibili per `columns` e `rows`. `frames` permette di escludere celle vuote finali. Tutte le istanze del corpo di uno stesso tipo condividono la fase del loop. Questa animazione è cosmetica e non fa avanzare impulsi, intenzioni o RNG; le animazioni di spostamento e combattimento del gioco continuano ad applicarsi allo sprite.

### Clip collegate agli eventi

Le clip evento partono quando il renderer presenta il relativo lancio, volo, impatto o danno. Non vengono riprodotte continuamente: terminano insieme alla fase dell'evento che le contiene.

| Chiave | Uso |
| --- | --- |
| `player_cast` | Animazione del giocatore durante il lancio |
| `player_hit` | Animazione del giocatore quando subisce danno |
| `firebomb_cast` | Effetto di preparazione/lancio di Firebomb |
| `firebomb_projectile` | Proiettile di Firebomb, lungo il suo percorso |
| `firebomb_impact` | Impatto di Firebomb |
| `chain_bolt` | Effetto di un fulmine di Chain Lightning |
| `fate_cast` | Effetto di lancio di Fate Strike |
| `fate_impact` | Effetto di risoluzione di Fate Strike |

Le clip accettano PNG statici, sheet PNG e GIF con gli stessi campi dei corpi. Per un'esplosione o un fulmine centrato sulla posizione dell'effetto è spesso più comodo `anchor: [0.5, 0.5]`; per `player_cast` e `player_hit` usa dimensioni e anchor compatibili con il corpo `player`.

```json
{
  "version": 1,
  "sprites": [
    {
      "key": "firebomb_impact",
      "file": "effects/firebomb_impact.png",
      "columns": 4,
      "rows": 2,
      "frames": 8,
      "width": 112,
      "height": 96,
      "anchor": [0.5, 0.5]
    }
  ]
}
```

La durata di una clip si adatta alla durata della fase di presentazione del gioco. `fps` influenza soltanto i loop dei corpi: non accelera né rallenta un'azione. All'inizio viene mostrato il primo frame, alla fine l'ultimo, senza tornare al primo. Due impatti contemporanei possono usare lo stesso file e avere progressi diversi; non si azzerano né si sincronizzano a vicenda. Un PNG statico resta visibile per la durata della fase.

Il manifest può contenere insieme corpi e clip; è possibile sostituire soltanto gli effetti desiderati. Le clip mancanti mantengono gli effetti procedurali. Le clip non sono bersagli selezionabili e non alterano collisioni o risultati del combattimento. Questa versione non aggiunge animazioni distinte per direzione.

### Caricamento e limiti

I file condivisi da più chiavi usano la stessa texture, anche quando una chiave è un corpo in loop e l'altra è una clip evento. I frame GIF vengono riuniti in un atlas, caricato sulla GPU una sola volta; durante il gioco non vengono decodificate GIF né ricaricate texture. Le risorse GPU e le maschere alpha vengono liberate prima della chiusura della finestra.

- Manifest fino a 64 KiB, con un massimo di 19 associazioni: 11 corpi e 8 clip evento.
- File PNG/GIF fino a 16 MiB; massimo 128 frame e 8 milioni di pixel decodificati per file/atlas.
- Texture con lato massimo di 4096 pixel; budget complessivo di 32 milioni di pixel.
- Dimensioni visualizzate positive fino a 256 pixel per asse e velocità fino a 60 fps.

Dimensioni PNG e struttura GIF vengono controllate prima della decodifica. Manifest mancante, file non validi o configurazioni incompatibili conservano la grafica procedurale; un errore di un singolo sprite non impedisce il caricamento degli altri.

### Verifica grafica

```sh
odin run src -- --smoke-sprites
```

Il comando crea PNG e GIF di prova temporanei, verifica condivisione delle
texture fra corpi e clip, primo e ultimo frame di una clip leggendo i pixel
renderizzati sulla GPU, cambio di frame GIF, selezione trasparente e fallback, poi salva
`odin_pp_sprites.png` e chiude la finestra. Lo screenshot mostra anche la barra
di salute di un Ice Block danneggiato sopra lo sprite personalizzato. Le immagini
di prova vengono rimosse; non costituiscono un pacchetto grafico per la run.

## Telemetria e playtest

Sorgenti: [telemetry.odin](src/combatdebug/telemetry.odin),
[session.odin](src/combatdebug/session.odin), [report.odin](src/combatdebug/report.odin),
[kiting.odin](src/combatdebug/kiting.odin) e [playtest_session.odin](src/playtest_session.odin).

Il dispatcher condiviso da input diretto e bufferizzato cattura uno snapshot
pre-comando e un descrittore della carta, esegue l'API autorevole e passa
esito e Room finale a `observe_command_detailed`. Il tipo è esplicito:
un Move contro un nemico viene classificato Bump_Attack prima della risoluzione,
anche se il colpo termina il combattimento.

Un rifiuto incrementa attempted/rejected senza leggere un log precedente.
Per i commit si aggrega `Room.recent_events`, verificando marker Pulse_Advanced
e delta del pulse; perdite o mismatch rendono il sample incompleto.
Il perimetro della carta va da Card_Played alla sua uscita da Resolving,
separando danno diretto, reazioni, status, trappole e risposta nemica.
`has_status_cause/status_cause` attribuisce i tick anche quando Shield assorbe tutto.

Le metriche contano comandi e carte, pulse, target previsti/effettivi, danni
subiti/diretti/indiretti/assorbiti, energia spesa/recuperata/sprecata, Poison,
Refocus, movimento forzato e hazard. I campi `object_hazard_*` distinguono
trigger e danno effettivo su player e nemici. Il confronto bump/Strike/Heavy
Blow considera solo decisioni in cui tutte e tre le opzioni erano disponibili.

`Playtest_Session` apre e chiude ogni fight una volta sola; il giro Loot non
contamina i campioni. Il JSON ha `schema_version = 1`, seed, outcome Victory,
Defeat o Abandoned, completezza, metadata del nodo, aggregati e sample ordinati.
Usa interi e booleani, senza timestamp, hash map o dati del renderer: stessa
sequenza e seed producono gli stessi byte.

```sh
odin run src -- --seed=0xC0FFEE --playtest-report
odin run src -- --playtest-output=/percorso/sessione.json
odin run src -- --smoke-playtest
```

Il report interattivo viene scritto a fine run, restart o chiusura come
`odin_pp_playtest_<seed>.json`; creazione esclusiva e suffissi `_1`, `_2`, ecc.
proteggono anche sessioni concorrenti. Il percorso esplicito è una base con la
stessa protezione; la directory deve esistere. Il nome effettivo è stampato
fuori dal JSON. Lo smoke headless non inizializza Raylib e sovrascrive invece
intenzionalmente `odin_pp_playtest_smoke.json` o il file esatto scelto con output.

La policy headless considera North, East, South, West e Wait. Valida le mosse
con Movement_Query, tratta Wait separatamente, minimizza danno da hazard,
evita le celle minacciate, massimizza distanza minima e somma delle distanze,
poi preferisce la direzione precedente e l'ordine fisso dei candidati.
Termina per budget, fine fight, sconfitta o comando rifiutato.

### Domande per il bilanciamento

| Azione melee base | Danno | Energia | Pulse se il fight continua |
|---|---:|---:|---:|
| bump attack | 2 | 0 | 1 |
| Strike | 3 | 1 | 1 |
| Heavy Blow | 5 | 2 | 1 |

Heavy Blow concentra danno in una sola risposta nemica; il valore non si misura
soltanto in danno per energia. Prima di aggiungere nuove primitive, confrontare
più run riproducibili e misurare:

- scelta fra bump, Strike e Heavy Blow, danno subito ed energia sprecata;
- quanti Venom Needle ottengono almeno due tick prima della morte del bersaglio;
- numero medio di nemici colpiti da Caustic Bloom;
- quante Purifying Guard rimuovono davvero Poison;
- Volatile Study giocata o exhaustata da Refocus, rispetto a Battle Focus;
- spinte/pull che attivano hazard o invalidano intenti;
- Refocus come ricerca di una risposta o semplice recupero di una mano debole.

Root/Slow, coni e costi dinamici devono rispondere a un bisogno ripetuto dei
playtest, non alla sola possibilità tecnica di aggiungerli.

## Odin: appunti per lo sviluppo

Questi appunti conservano i principi e la sintassi utili delle guide originali.
Il progetto privilegia dati, ownership, lifetime e costi espliciti.

### Dati, memoria ed errori

Odin usa struct e procedure esterne, composizione e allocatori espliciti;
non ha GC, classi con ereditarietà o eccezioni. Una directory è un package;
i file condividono `package`, le dichiarazioni sono pubbliche per default,
`@(private)` restringe al package e `@(private="file")` al file.

| Container | Uso |
|---|---|
| `[N]T` | storage fisso, nessuna allocazione |
| `[Enum]T` | tabella indicizzata da enum |
| `[]T` | vista su memoria altrui, senza ownership |
| `[dynamic]T` | collezione densa che può crescere |
| `map[K]V` | lookup per asset/config/cache; ordine di iterazione non stabile |
| `#soa[dynamic]T` | layout per campi, da introdurre quando le misure lo giustificano |

Una slice o stringa temporanea non può sopravvivere al backing storage.
`append` può riallocare un array dinamico e invalidare i puntatori;
`unordered_remove` può cambiarne gli indici. Conservare ID e risolverli al
momento dell'uso. `reserve` va fatto in inizializzazione quando la capacità
è prevedibile. `clear` conserva il buffer; `ordered_remove` preserva l'ordine.

Acquisire una risorsa e dichiarare subito il cleanup con `defer`, eseguito a
fine **scope** in ordine inverso. `new/free` gestiscono un valore;
`make/delete` il backing storage dei container. `free_all` svuota allocatori
che lo supportano. `context.allocator` e `context.temp_allocator` propagano la
politica alle chiamate nello scope: gli asset richiedono vita lunga, lo scratch
di frame può essere liberato a fine frame. Mai conservare dati temp oltre quel
confine. Le risorse GPU vanno rilasciate prima della finestra.

Gli errori attesi, come file mancanti o input malformati, sono valori restituiti;
assert controlla invarianti interne, panic stati irrecuperabili. Non inserire
mutazioni dentro assert: con `-disable-assert` non verrebbero eseguite.
Eseguire prima l'operazione e controllarne il risultato separatamente.
`or_return` serve quando propagare l'errore è la gestione voluta; altrimenti
aggiungere contesto con un controllo esplicito.

### Sintassi essenziale

```odin
count: i32 = 10                 // tipo esplicito
speed := f32(240)               // inferenza e conversione esplicita
MAX_COUNT :: 32                // costante compile-time
Vec2 :: [2]f32
Entity_Id :: distinct u32       // stesso layout, identità di tipo diversa

position := Vec2{10, 20}
position += Vec2{1, 0} * 2      // operazioni su array; accessori .x, .y

Actor :: struct {
    id: Entity_Id,
    health: i32,
}

hurt :: proc(actor: ^Actor, amount: i32) {
    actor.health -= amount     // accesso ai campi tramite puntatore
}

actor := Actor{id = Entity_Id(1), health = 10}
ptr := &actor.health
ptr^ -= 1                      // dereferenziazione

for i in 0..<10 { }             // limite escluso; 0..=9 lo include
for value, index in values { }  // value è una copia
for &value in values {          // modifica in place
    value += 1
}

Mode :: enum { Menu, Playing }
mode := Mode.Playing
switch mode {                  // enum esaustivo, no fallthrough implicito
case .Menu:
case .Playing:
}

first :: proc(values: []$T) -> (value: T, ok: bool) {
    if len(values) == 0 do return {}, false
    return values[0], true
}
```

Gli snippet illustrano costrutti separati, non un file eseguibile completo.
I parametri sono immutabili: per modificare il chiamante passare `^T`.
`using` promuove campi per composizione, senza introdurre una gerarchia.

| Costrutto | Promemoria |
|---|---|
| `nome := valore`, `nome :: valore` | variabile inferita / costante o dichiarazione di tipo/procedura |
| `T(x)`, `cast(T)x` | conversione esplicita; valutare range, precisione e segno |
| `transmute(T)x` | reinterpretazione dei bit, con stessa dimensione |
| `size_of(T)`, `align_of(T)`, `type_of(x)` | introspezione di layout e tipo |
| `if cond do return` | corpo a istruzione singola |
| `a if cond else b` | espressione condizionale |
| `for cond {}`, `for {}` | ciclo condizionale / infinito |
| `proc(a: i32 = 1)` | parametro con default; chiamata con nome `f(a = 2)` |
| `f :: proc{f_int, f_float}` | overload esplicito |
| `bit_set[Enum]` | insieme di flag; `in`, `+`, `-`, `&`, `card` |
| `union {bool, i64, string}` | alternative tipizzate; `v.(T)` e type switch |
| `any` | valore dinamico per tooling/reflection, non sostituto delle invarianti |
| `x := expr or_else fallback` | fallback su risultato optional |
| `or_return`, `or_break`, `or_continue` | propagazione o controllo del loop |
| `$T: typeid`, `[]$T` | parametric polymorphism esplicito o inferito |
| `when ODIN_DEBUG`, `when ODIN_OS == .Linux` | selezione compile-time |
| `#partial switch` | gestione intenzionalmente parziale di enum |
| `@(test)` | procedura di test con `t: ^testing.T` |

String è una vista UTF-8 immutabile: `len` conta byte, l'iterazione produce
rune e indice in byte. Usare `strings.Builder` per costruire testo;
`fmt.tprintf` e `fmt.ctprintf` producono rispettivamente string/cstring temp,
valide solo fino al reset dell'allocatore. Le stringhe raw fra backtick non
interpretano escape. Map lookup supporta `value, ok := map[key]`;
`delete_key(&map, key)` rimuove una chiave.

`foreign` collega API native; `proc "c"` non riceve il context Odin.
A ogni confine C verificare ownership, durata dei puntatori, layout e calling
convention. Raylib si importa con `import rl "vendor:raylib"`.

| Package | Utilità |
|---|---|
| `core:fmt`, `core:strings` | formattazione e testo |
| `core:math`, `core:math/linalg` | scalari, vettori, matrici e quaternioni |
| `core:math/rand` | generatori con seed espliciti |
| `core:mem` | allocatori, arene e tracking |
| `core:slice`, `core:container` | ordinamento, ricerca e container |
| `core:os`, `core:time`, `core:log` | file, argomenti, clock e logging |
| `core:encoding/json`, `core:testing` | configurazioni e test |

### Metodo di lavoro

Chiarire dati, proprietario, durata e procedure che possono mutarli prima di
introdurre astrazioni. Mantenere simulazione senza finestra, renderer passivo,
input trasformato in comandi e RNG isolati. La simulazione corrente avanza per
pulse; il timestep fisso della fisica cosmetica non deve influenzarla.

Preferire servizi richiesti dal gioco a ECS o generics anticipati. Misurare
frame time, allocazioni e copie prima di ottimizzare; `mem.Tracking_Allocator`
e il runner di test aiutano a rilevare leak e bad free. Mantenere il tracking
attivo per tutta la durata delle operazioni osservate e distruggerlo dopo le
risorse tracciate. Testare logica pura, ID, parsing, determinismo e transizioni;
per la presentazione verificare anche snapshot intermedi e smoke grafici.

Il flusso quotidiano è modifica piccola, `odin check`, test pertinenti e demo
quando cambiano grafica o input. Per un singolo file usare
`odin run esempio.odin -file`; `odin doc core:fmt` apre la documentazione CLI.
`-debug` aggiunge simboli, `-o:speed` ottimizza, `-out:...` sceglie il binario,
`--` separa gli argomenti del programma.

Riferimenti: [overview Odin](https://odin-lang.org/docs/overview/),
[guida ai test](https://odin-lang.org/docs/testing/),
[indice dei package](https://pkg.odin-lang.org/),
[sorgenti Odin](https://github.com/odin-lang/Odin),
[materiale Odin e Raylib di Karl Zylinski](https://zylinski.se/).

## Roadmap e manutenzione

Una milestone è completa quando è integrata nella demo, coperta da test delle
invarianti e descritta dalla documentazione. Stati: `[x]` completata,
`[~]` in corso, `[ ]` pianificata.

| Milestone | Stato | Risultato / lavoro restante |
|---|---|---|
| Baseline | [x] | loop della run, griglia, azioni, deck, intenti, timeline e buffer |
| M1 + M1A | [x] | stanze procedurali, quattro famiglie, placement tattico, seed e commit transazionale |
| M2 | [x] | rarità, reward pesate, upgrade, rimozione e Shop |
| M3 | [x] | nodi Shop, Rest, Event e Treasure con distribuzione e scelte one-shot |
| M4 | [~] | profondità di carte e status; sotto-incrementi elencati qui |
| M4A | [x] | Resolving, Exhaust, temporanee, Draw/Discard/Create |
| M4B | [~] | Refocus, Retain ed Ethereal completati; costi/rigenerazione dinamici e scarto selezionato restano da fare |
| M4C | [x] | movimento condiviso, hazard, Shove/Dash/Grappling Hook |
| M4C.1–M4C.2 | [x] | content pass e telemetria deterministica |
| M4C.3–M4C.5 | [x] | oggetti, Fire persistente, esplosivi e prima zona tattica |
| M4D | [ ] | nuovi trigger e scadenze, coni e nuove footprint motivate dal playtest |
| M4E | [x] | sei reliquie, acquisizione e sinergie |
| M4F | [x] | spell, pool di dadi, catene, gruppi di impatto e laboratori |
| M5 + M5A | [~] | M5A completata: cooperazione, composizioni e primo boss; restano altri elite/boss, evocazione, controllo e nuove geometrie nemiche |
| M6 + M6A | [~] | M6A completata: sprite, GIF, sheet e clip; restano persistenza, replay e ulteriori feedback |

### Criteri per gli incrementi successivi

Per carte e geometrie: preview e compilazione devono concordare, zone e ID
restare validi, timeline seguire le mutazioni e test coprire composizione e
limiti. Per encounter: intenti committed e deterministici, geometria condivisa,
simulazioni headless con morti, blocchi, spawn e cambi di fase senza deadlock
o overflow. Per persistenza: save versionati con round trip, migrazioni e
corruzione diagnosticabili, replay dei comandi con stesso risultato finale.
Velocità o disattivazione dei feedback non devono cambiare il gameplay.

Restano fuori dallo scope attuale: Chest con stato/interazione e premio
one-shot; fuoco periodico o propagazione; status e binding degli oggetti;
status persistenti fra stanze, immunità e tipi di danno; cataloghi caricati da
file; unlock, reroll, sconti e vendita di carte; eventi concatenati;
animazioni complete fra pile, direzioni dei personaggi e raggruppamento
generale di azioni indipendenti. Audio, illustrazioni definitive, particelle,
hit stop e screen shake ulteriori appartengono agli incrementi di game feel.

### Indicazioni conservate dall'audit

L'audit del 6 settembre 2026 si riferiva al commit `ca64a3a`. Conteggi dei test,
tempi, dimensioni delle struct e riproduzioni in `/tmp` erano misure locali di
quella versione, non benchmark o istruzioni valide per ogni checkout.
Le correzioni successive comprendono upgrade senza benefici rifiutati,
policy headless che usa Movement_Query, report con creazione esclusiva,
velocità configurabile, BFS e loot preallocato. Le verifiche con e senza assert
sono raccolte in `scripts/check.sh`; le regressioni economiche e del loot in
[audit_regression_test.odin](src/game/audit_regression_test.odin).

Le indicazioni di manutenzione ancora utili sono:

- mantenere ogni mutazione fuori dagli assert e verificare entrambe le configurazioni;
- derivare numeri e preview delle carte dai template, evitando copie manuali divergenti;
- rendere chiari i motivi di rifiuto delle giocate e migliorare la consultazione del deck;
- proseguire l'estrazione di controller e disegno dai file principali quando il confine è utile;
- misurare preview, conteggi intenti, copie dei report e validazioni prima di introdurre cache;
- conservare la validazione completa ai confini e controllare i budget di stack degli eventi;
- se l'envelope cresce, valutare storage a blocchi con ownership esplicita invece di gonfiare gli array;
- automatizzare check, test e link in CI, documentando la toolchain verificata.

Le nuove nozioni e decisioni vanno aggiornate nella sezione pertinente di questo
README, mantenendo un unico riferimento e distinguendo implementato e pianificato.
