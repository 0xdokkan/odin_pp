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
`grid.Position` resta una coordinata intera, con il piano della mappa (`layer`: 0 la
terra, −1 e −2 sotto, +1 sopra; [piano della profondità](piano-profondita.md), Fase 2).
Una `Grid` ha un solo piano, la terra: `contains`, `index_of`, `get` e `set` rifiutano le
posizioni di altri piani, e così `grid.cell_index` per le tabelle parallele; la vicina di
una posizione si calcola con `grid.offset`, che ne conserva il piano. Le soglie di
normalizzazione della fisica e degli effetti, e l'ordine delle operazioni floating
point, restano intenzionalmente quelli precedenti.

La griglia del gioco ha coordinate `(x, y)` e un piano: per ora tutto sta sulla terra
(piano 0); il terreno 3D e gli sprite sulla camera non introducono movimento verticale. Il canvas virtuale è `960x540`.

### Sole, cielo e contatto del terreno

`Expedition_Material.sun` possiede `Expedition_Sun` (`expedition_sun.odin`);
`destroy_expedition_material` ne libera mappe e shader. Il sole usa una
profondità 2048² con confronto hardware, con R8 di riserva se il driver
richiede un attachment colore. Il cielo usa due target 512² RGBA16F:
altezza mondo dall'alto e copia per due giri di blur separabile. Le mappe
coprono 60 unità con matrici agganciate ai texel, indipendenti dal canvas.

I sampler occupano le unità **14 e 15**, legate esplicitamente e slegate
prima di scrivere nei target. Gli slot del batch del pavimento sono già
occupati: non aggiungere le mappe con `SetShaderValueTexture`. Il materiale
comune riusa `EXPEDITION_SUN_GLSL`; il sole attenua le bande cel con una tinta
fredda, il cielo modella l'occlusione presso i solidi. `skyShade` conserva
l'illuminazione sotterranea. `lightMirror` esclude il calcolo dove impostato;
i blocchi riflessi in VBO usano coordinate mondo e `lightMirror=0`, quindi
ricevono ancora il sole.

`Expedition_Sun_Key` conserva target, vettore destro della camera, revisioni
di costruzione/upload dell'architettura, revisione del rilievo, maschera dei
64 tetti e bioma. Una traslazione orizzontale entro 5 unità riusa le mappe;
rotazioni della carta, modifiche della geometria e cambi dei tetti invalidano
la cache. `sun.renders` conta i ridisegni. Terreno e deck CPU sono preparati
prima della chiave: anche la prima passata vede tutte le superfici.

Proiettano ombre blocchi e siti in cache, rilievo, deck con spessore e
supporti, edifici con tetto governato da `Structure_Views.roof` e sagome
alpha-tested degli arredi. La dissolvenza sulla soglia conserva il solido
che proietta ombra; con `roof=false` il tetto esce dai caster. Gli attori
mantengono il disco di contatto e non sono caster. I caster delle superfici
riusano le mesh già caricate o, prima dell'upload, gli stessi vertici CPU,
senza una seconda risorsa GPU.

#### Integrazione del 3–4 novembre 2026, verifiche concluse

Le seguenti modifiche sono integrate nei sorgenti. Le copie e i delta in
`build/redesign-sole/session-20261103/` ne conservano la provenienza.
Il renderer passa 477 test con E attiva; smoke oggetti, fallback,
camminata e completo sono conclusi. G è verificata nelle catture v4 e il
confronto prestazionale finale ha tutte le dodici corse. Anche il controllo
del movimento a percorso identico è concluso: restano variabilità e picchi,
e il target 60 FPS a 1080p non è raggiunto. Esiti e limiti sono nel rapporto:

- **B/P1**: due PNG 1024² embedded, generati dalle routine Odin
  del pigmento senza duplicarne le formule. Il manifest registra versione e
  hash di sorgenti, generatore e pixel. Il preload dopo `roguelike_attach`
  prepara entrambe le texture prima del primo draw; il fallback procedurale
  resta nel caricamento. `Expedition_Floor` conserva ownership, mipmap e
  massimo due texture da 5,333 MiB ciascuna. Il probe GPU verifica pixel
  identici, cache e fallback; decode/upload e primo present sono misurati
  separatamente nel rapporto. Non sono tempi del caricamento completo del gioco.
- **B/pavimento**: le scorciatoie del frammento saltano contributi
  matematicamente nulli. Il confronto finale misura il pacchetto integrato;
  non attribuisce il beneficio alla sola scorciatoia.
- **C/D**: una mesh in cache per struttura non edificio
  evita duplicazioni e allargamento dei blocchi 8×8. Cart, Fountain, Statue,
  Machine, Ruin e Pen hanno forme proprie; le recinzioni hanno pali e traverse.
  La cache possiede e libera mesh e linee, compresi upload parziali. Rendering
  normale, riflesso, fallback e caster condividono la geometria.
  Anche il fallback senza cache proietta gli oggetti interi. Gli assi hanno
  entrambi i tappi, verificati con quattro rotazioni e specchio.
  I muri generici ricevono zoccolo, facce esterne arretrate, copertina e
  pilastri convessi; Cyber/West preservano le stampe e aggiungono una fascia bassa.
- **F1/F2/G**: fioriere Cyber contenute nella cella,
  `post_fill` esplicito per i pilastri blu e angoli avorio.
  `expedition_sky_crowd` condivide una lettura dell'altezza sfocata fra AO,
  accumuli del bioma e densità di `paperDetails`. Una maschera bilineare
  continua esclude hazard e rive senza gradini sulla griglia; audit
  matematico e catture v4 verificano la correzione.
- **F4**: il disegno della pressa Cyber è allargato del 6% e alzato del 2%;
  cella occupata, densità, dimensioni dell'atlante e quad restano invariati.
  I tre accessori esistenti formano gruppi meno simmetrici nelle stesse
  dieci celle bloccate, con identica scelta nel pass colore e nei caster.
  Gli interni riordinano attrezzi e scorte e aggiungono un armadietto
  dipinto accanto alla porta: +54 vertici Hut e +90 Cottage, senza mobili
  nelle celle libere o nuove risorse GPU.
- **E**: shader locale alla spedizione per attenuare
  soltanto la stampa colorata. Dopo il confronto on/off e l'approvazione
  dell'utente, `EXPEDITION_ACTOR_SHADOW=true` è il default, forza `.15`;
  carta, inchiostro e feedback di colpo mantengono il trattamento.
  Lo shader appartiene al sole del materiale, senza modificare `engine/gfx`.
  L'idoneità esplicita precede le tinte permanenti del bioma e verifica la
  grotta per attore, secondo la sua quota e posizione di presentazione.
  `-define:EXPEDITION_ACTOR_SHADOW=false` conserva il confronto senza effetto.

Gli interventi mantengono mappe, collisioni, quote, picking, visibilità di
gioco e RNG. Esiti e limiti sono in
[`VERIFICA_REDESIGN_SOLE.txt`](riferimenti/cartoncino-cartoon/VERIFICA_REDESIGN_SOLE.txt).

### Proprietà delle scene e transizioni

`Expedition_Material` possiede anche `Expedition_Cartoon_Assets`, creato al
primo attore di una spedizione. Sono due texture immutabili con filtro nearest:
stampa RGBA 2496×3120 (720 pose, circa 29,71 MiB) e sagome 832×104 (338 KiB).
Le otto maschere CPU da 104×104 byte servono al picking; il bordo superiore
precotto ancora vita e intenzione sopra la sagoma. I buffer CPU di costruzione
sono temporanei e liberati dopo l'upload. Animazioni, cambio di direzione,
cambio bioma e resize selezionano soltanto celle/quadrilateri; non ricreano
texture. `destroy_expedition_material` rilascia entrambi gli atlanti e le
maschere. Anche il renderer prestato possiede il proprio eventuale materiale
di spedizione: questa risorsa non introduce proprietà GPU condivisa implicita.

Le mesh dell'architettura conservano la cache a blocchi e rispettano i budget
di geometria: le coordinate `print_uv` permettono al materiale comune di disegnare
inchiostro e un sottile margine avorio sui quad, compresi i cappelli rettangolari.
Lo spessore si adatta alla dimensione proiettata: i controlli piccoli conservano
colore; i segni più minuti si attenuano quando diventano subpixel.
`ink_wall_sheet` unisce i margini delle facce adiacenti in tutti i biomi,
senza cambiare le celle occupate. Le decorazioni delle altre undici famiglie
sono motivi analitici nello stesso materiale, anziché box sottili sovrapposti.
L'antialiasing misura le derivate prima della ripetizione delle coordinate,
evitando cuciture puntinate al confine dei motivi. Non introduce texture,
allocazioni o upload per frame. `UnloadMesh` libera anche
il buffer UV; i vertici del terreno usano coordinate sentinella, poiché il
pavimento conserva il proprio shader e la propria cache.

La libreria `expedition_profiles.odin` aggiunge profili concavi disegnati a mano:
triangolazione a orecchie con scratch fisso (massimo 32 punti), estrusione e
contorno selettivo. Viene eseguita nel bake dei blocchi esistenti; la durata di
mesh, UV e linee resta quella di `Expedition_Architecture_Cache`. Non vengono
create texture. Le pareti codificano `print_uv.x + 4`: il materiale decodifica
il tag prima dei bordi e applica le illustrazioni di `expedition_print.odin`
solo alle facce verticali dell'architettura. Attrezzature, foglie e piccole
facce non ereditano glifi della parete. `{2,2}` resta la sentinella senza stampa.

`expedition_biome_forms.odin` compone arredi nelle sole celle già occupate dalle
coperture dell'officina. I profili e le rotazioni non scrivono nella mappa.
Il movimento degli strumenti è campionato nei due fotogrammi delle stampe,
con fase cosmetica deterministica per posizione; non invalida la cache.

Gli edifici esplorabili usano `structure_print_cell`: solo facce esposte e un
dominio UV continuo sui fogli adiacenti. Il tag `x+8` distingue la stampa del
tetto da quella della facciata (`x+4`). Quota d'appoggio, impronta, apertura del tetto,
trasparenza dell'involucro e picking continuano a usare i dati strutturali.
Il contorno viene composto dal materiale, senza un secondo reticolo di linee.

`expedition_ground_art.odin` aggiunge al massimo un piccolo gruppo ogni 4×4
celle (180 vertici aggiuntivi per blocco 8×8, massimo teorico 6.3 KiB di payload).
Le radici seguono `point_ground` vertice per vertice; decorazioni sotto 0.12
unità, assenti da porte, hazard, spawn, strutture e interni dei POI. La scelta
non dipende dalla posizione corrente del giocatore e non invalida la cache.
Nei cortili sono ammessi piccoli gruppi solo vicino alle pareti, lontani dal
punto di interazione e dalle superfici di passaggio.

`Expedition_Material` possiede anche `fixtures` (atlanti nearest e maschere
CPU), `fixture_shader` e `costumes` (inviluppi CPU dei costumi). I renderer
prestati possiedono le proprie eventuali istanze; `destroy_expedition_material`
le rilascia. I 96 disegni dei prop (sei funzioni e due arredi per ciascuno dei
dodici biomi) usano 104×104 pixel, due pose: stampa 1248×1664 e carta 1248×832,
11.883 MiB GPU complessivi e circa 0.990 MiB di maschere CPU. I buffer RGBA
di costruzione sono temporanei. Upload una sola volta per materiale; cambi
bioma, animazione e resize selezionano rettangoli dell'atlante. Il fallimento
di upload libera le risorse parziali e mantiene il fallback geometrico.

Le scene Cyber e West aggiungono in `Expedition_Fixture_Assets`
`hero_print` (**416 × 624 pixel**) e `hero_paper` (**416 × 312 pixel**):
due texture RGBA, **1,485 MiB GPU complessivi**, 0,495 MiB in più rispetto
alla sola pressa Cyber. `expedition_fixture_hero.odin` impacchetta
quattro pose della pressa in celle 104×208 e tre arredi secondari
(materiali, convogliatore, scaffale) nella fascia inferiore da 104 pixel.
`expedition_fixture_west.odin` aggiunge sega a telaio, tronchi, banco e assi,
con quattro pose e celle separate nello stesso pack. Il supporto è l'unione
delle quattro pose; maschera e bounds sono preparati
all'upload. Il clock cosmetico seleziona soltanto il rettangolo della stampa;
lo stato risolto conserva la posa ferma. I buffer RGBA di costruzione sono
temporanei sull'heap, e il distruttore degli asset libera entrambe le texture
anche dopo un upload parziale. Rimangono condivisi shader, profondità,
occlusione, passaggio riflesso e regole di interazione dei prop esistenti.
La visibilità ai margini di pressa e sega usa una sfera derivata dalla sagoma
opaca, bordo compreso: la testa rimane visibile anche con i piedi fuori campo.
Gli altri oggetti conservano i parametri precedenti del frustum.

`expedition_cyber_floor.odin` e `expedition_west_ground.odin` descrivono
pigmenti e percorsi nelle coordinate locali delle officine. Il generatore
`tools/art/build_workshop_stock.py` estrae le routine Odin e salva la pittura
in due PNG incorporati da `expedition_workshop_stock_data.odin`:
1024×1024 RGBA8, undici livelli mip, filtro trilineare e clamp. Ogni bioma
costa 5,333 MiB GPU; `Expedition_Floor` possiede al massimo due texture e le
libera nel proprio distruttore. I buffer CPU sono temporanei. Decode e
upload avvengono nel caricamento dopo `roguelike_attach`, prima del draw;
il fallback procedurale resta in quel caricamento. Animazione, draw e resize
riusano le texture e non rigenerano il pigmento.
Centro e orientamento restano uniformi per sito, senza modifiche alla mappa.
La texture dati conserva pericoli e superfici; in Cyber il nibble alto di B
memorizza anche i raccordi dei muri continui, ricalcolati solo quando cambia
la geometria. Il pigmento dei dirupi segue quota e normali esistenti.
Il binding mesh usa `MAP_NORMAL` come alias dello slot 2 del pigmento:
floorMap=1, workshopStock=2, reflectionSharp=3. Usare ROUGHNESS sovrascriverebbe
il riflesso; batch e mesh devono mantenere gli stessi slot.

`expedition_cyber_building.odin` completa soltanto `Hut` e `Cottage` Cyber.
Una composizione canonica segue rotazione e specchio del piano strutturale.
Facciata, console, banco e scaffale sono triangoli di stampa aderenti alle
facce dei muri; pochi segni piatti sul pavimento lasciano libero il percorso.
Il tetto ha spalle piegate entro l'impronta esistente e conserva l'apertura
sopra la cella `Door`. Viene emesso con i suoi dettagli solo quando
`Structure_Views.roof` lo richiede; opacità e stato interno provengono ancora
da `game.structure_visibility`. Questa geometria usa la passata dell'involucro
esistente, senza texture nuove né allocazioni per frame. I test verificano
entrambi i piani in tutte le rotazioni e riflessioni, adesione degli arredi
ai muri, copertura effettiva del tetto e assenza di residui nel taglio interno.
`expedition_west_building.odin` usa la stessa trasformazione dei piani per
tetti a falde, legno, imposte e attrezzi dipinti sulle pareti. Il generatore
colloca due edifici West con le protezioni esistenti di spawn e servizi,
senza spianare il terreno. I vecchi salvataggi mantengono tile e strutture
salvati: gli edifici nuovi compaiono soltanto nelle nuove spedizioni.
Gli altri dieci biomi restano nella roadmap.

Le annotazioni della spedizione riservano le sagome opache: otto bande CPU
preparate all'upload per il cartoon, inviluppi dei costumi già in cache negli
altri biomi. Vita e intento cercano una posizione entro 36 pixel dalla testa,
in ordine stabile di entità; l'eventuale collegamento non attraversa altri
corpi. Se non esiste spazio resta il cartellino ancorato, senza omettere HP.
L'allocatore usa memoria fissa; non rigenera maschere durante il disegno.

Le sagome scrivono profondità solo nei pixel opachi. Il passaggio normale
stampa i pigmenti dopo il resolve; il riflesso usa gli stessi atlanti nel
passaggio speculare, convertendo esplicitamente sRGB in lineare. I prop si
attenuano solo quando ingombro proiettato e profondità indicano un attore
coperto. Interazione E, celle di collisione e navigazione rimangono della mappa.
Gli inviluppi dei costumi non Cyber sono immutabili, costruiti una volta per
costume dai suoi estremi animati; la stampa sola cambia posa e orientamento.
Il picking usa i medesimi poligoni del supporto, senza rettangoli invisibili.

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
