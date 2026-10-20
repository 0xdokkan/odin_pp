[← Odin PP](../README.md)

## Architettura e ownership

Il punto d'ingresso chiama `application.start`. Il gioco mantiene un solo
runtime tattico e la simulazione non importa presentazione, input nativo o
strumenti di sviluppo.

| Package | Responsabilità e dipendenze |
|---|---|
| [main](../src/main.odin) | inoltra gli argomenti; la riserva dello stack Windows rimane separata |
| [application](../src/application) | CLI, launcher, creazione dell'host; compone `run`, `activities` e `devtools` |
| [run](../src/run) | sessione, controller, schermate, attività sulla board, pratica e Mostra effetto; non importa `application` o `devtools` |
| [activities](../src/activities) | catalogo dei minigiochi e sessione delle modalità libere; non possiede la progressione della run |
| [devtools](../src/devtools) | scenari riproducibili, laboratori tecnici, diagnostica e catture; usa l'API della run |
| [engine](../src/engine) | clock, geometria, collisioni, input, host, audio, UI; include `app`, `view` e `grid` |
| [level](../src/level) | topologia e validazione BFS, senza regole di difficoltà o nemici |
| [game](../src/game) | simulazione deterministica, cataloghi, carte, incontri, economia e progressione |
| [render](../src/render) | risorse GPU, HUD, snapshot e timeline; legge la simulazione |
| [combatdebug](../src/combatdebug) | osservazione, scenari headless e report della simulazione |
| [fight](../src/fight), [shooter](../src/shooter), [minigames](../src/minigames) | simulazioni e scene delle attività |
| [integration](../src/integration) | scenari che attraversano i confini dell'applicazione; incluso dal solo entry point dei test |

Le dipendenze fra package sono acicliche. `Run_Diagnostics` è un insieme di
callback opzionali con dati posseduti dal provider e distruttore esplicito:
`run` non conosce i tipi delle catture. Il laboratorio delle carte e i film
Mostra effetto sono funzioni del prodotto, quindi rimangono in `run`.
Gli alias CLI delle milestone e i nomi dei file di salvataggio restano
compatibili; i tipi di sessione sono `Player_Activities` e `Free_Mode_Session`.

### Input e schermate

`engine/input.capture_devices` legge i dispositivi una volta per frame.
`host.Frame` presta lo snapshot ai proprietari attivi. `Run_Input` conserva
valori, mai il puntatore a un frame ormai terminato; mappa `Run_Action` tramite
`Action_Map`. Controller, HUD e menu ricevono questi dati senza interrogare
Raylib. Focus, sospensione e cursore FPS hanno confini espliciti.

`Run_State.phase` resta l'autorità. `run_screen` ricava la schermata corrente,
con sola precedenza della mappa richiesta dal giocatore; `update_run_screen`
e `draw_run_screen` gestiscono gli stessi casi. Non esistono copie mutabili di
`reward_visible`, `shop_visible`, `special_visible`, `route_visible` o
`defeat_visible`. Pausa, scheda e film sono overlay separati.

### Carte e regole condivise

`CARD_DEFINITIONS` è un array enumerato `[Card_Id]Card_Definition`: una nuova
voce enum richiede la relativa definizione, con `.Count` esplicitamente invalida.
Tratti, costo temporale, numero di dadi e livello massimo di upgrade sono dati
nel catalogo. `Card_Visual`, privato al renderer, raccoglie icona, palette,
accento, nomi brevi e suono. Le descrizioni variabili derivano da parametri del
gameplay; algoritmi, effetti e animazioni speciali mantengono moduli dedicati.
Una carta con meccanica propria richiede ancora coordinamento fra i livelli:
le tabelle non sostituiscono un'implementazione e un contratto di eventi.

`tactical_control_allowed` centralizza le capacità, mentre la policy del clock
seleziona World, Cast, Shadow o Paused. Il cleanup di inizio/fine combattimento
è condiviso. Pinball può coesistere con altre azioni; Shadow sospende il mondo;
terreno e dispositivi hanno durate proprie. Queste combinazioni intenzionali
non vengono cancellate da uno slot esclusivo generico.

### Memoria e durata degli eventi

`Run_State` possiede player, mazzo, reliquie, grafo e payload dei nodi. `Level`
possiede `Grid(Tile)`. `Room` possiede nemici, oggetti, scratch buffer e un
`^Event_Log`, creato e distrutto con la stanza usando l'allocatore registrato;
prende in prestito `^Level` e `^Player`. Copiare `Room` non duplica queste risorse.

`recent_events` è valido fino alla successiva scrittura/reset o alla distruzione
della stanza. Sono validi soltanto gli elementi prima di `count`; il reset
invalida il prefisso senza azzerare tutto il buffer. `copy_event_log` copia il
prefisso valido e `dropped_count`. Chi deve conservare uno snapshot indipendente
copia i valori, non il puntatore: vale per replay, preview e rollback.

I report pubblici conservano il loro contratto per valore; la risoluzione
interna dell'azione scrive nel report del chiamante e non alloca copie enormi
annidate. Il log è spostato, non eliminato: si riducono `Room` e la pressione
sullo stack, non i byte totali del log. La riserva Windows rimane finché una
misura dello stack dell'intero percorso nativo su Windows ne giustifica la rimozione.

### Superficie pubblica e geometria

Gli helper locali di `game` e `render` sono privati al file o al package.
L'API pubblica espone comandi, transizioni, query delle regole e del catalogo;
nel renderer espone lifecycle, aggiornamento, picking e schermate. Layout,
shader, mesh, palette, risolutori e pianificazione interna non sono API esterne.

`engine/app`, `engine/view` e `engine/grid` non dipendono dai package del gioco:
l'engine può essere controllato autonomamente. I vettori continui sono array
nativi `[2]f32` e `[3]f32`, compatibili con Raylib e `core:math/linalg`.
`grid.Position` resta una coordinata intera. Le soglie di normalizzazione della
fisica e degli effetti, e l'ordine delle operazioni floating point, restano
intenzionalmente quelli precedenti.

La griglia del gioco ha coordinate `(x, y)`: il terreno 3D e gli sprite sulla
camera non introducono movimento verticale. Il canvas virtuale è `960x540`.

### Proprietà delle scene e transizioni

`Effect_Window`, nella sessione della run, possiede il film di
[Mostra effetto](presentazione.md#mostra-effetto) (`Card_Demo`, sull'heap: la sua stanza punta
dentro di lui), il suo renderer e i render target dello stage. Il film possiede
la sua stanza, il suo livello e il suo giocatore, e non tocca mai quelli della
run. Il suo renderer possiede soltanto il proprio stato di vista e prende in
prestito le risorse GPU del renderer della run, che vive più a lungo
(rilasciato prima degli asset della run in `roguelike_destroy`). Un asset nuovo
del `Renderer` va preso in prestito anche in `borrow_renderer_assets`: il test
che percorre il `Renderer` con `core:reflect` fallisce finché non c'è, e così se
il renderer prestato divide con quello della run un puntatore o uno stato. Un
pezzo di stato nuovo che `destroy_tactical_assets` libera va liberato anche in
`destroy_borrowed_renderer`.

`engine`, `fight` e `shooter` non importano Raylib, `game` o la griglia tattica.
Le due simulazioni libere possiedono ciascuna il proprio `engine.World` e
dipendono soltanto dai servizi geometrici/temporali condivisi. `Free_Mode_Session`
possiede la modalità corrente e la registrazione dinamica, liberata da
`destroy_free_mode_session`. Il loop principale sospende l'aggiornamento tattico mentre
questa sessione è aperta; il renderer non decide esiti o ricompense.
Il risultato del ring passa attraverso `settle_ring_challenge`, mantenendo la
progressione M8 senza usare il vecchio duello monodimensionale nel gioco live.

La nuova stanza viene costruita in un `Room_Blueprint` e preparata con copie di
player, livello e stanza. Si valida tutto prima del commit; un fallimento libera
le risorse temporanee senza cambiare run, salute, oro, status, deck o RNG.
Nell'installazione si distrugge la vecchia Room **prima** del vecchio Level,
si trasferiscono gli owner e si riagganciano i puntatori alle destinazioni
stabili. Gli owner trasferiti vengono azzerati. Le copie temporanee di `Room` trasferiscono ora un puntatore al log; non
producono una seconda proprietà. Dopo il trasferimento la sorgente viene
azzerata; una copia di lavoro che registra eventi deve invece avere un log
indipendente, come lo staging di Refocus.

I riferimenti durevoli sono ID, mai puntatori o indici di array dinamici.
`Entity_Ref` contiene categoria e ID: player e sistema usano zero; nemici,
trappole e oggetti hanno ID stabili. Una rimozione `unordered_remove` può
cambiare l'indice, ma non il destinatario di un'azione già costruita.
