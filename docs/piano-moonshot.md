[← Odin PP](../README.md)

# Piano moonshot: un mondo che si alza dalla pagina

Proposta del 4 novembre 2026. Base verificata: `ddc6b186942d4c78597dc0f3f06c1a73483b716e`, ramo
`piano-moonshot`, già presente all'inizio del lavoro e coincidente con `origin/piano-ia` locale.
Il commit segue `d71b83a`: cambia soltanto lo strumento delle catture e il CHANGELOG. Nessuna fase di
implementazione viene eseguita scrivendo questo piano. Le decisioni successive dell’utente sono registrate negli aggiornamenti e nella sezione 1.

**Esecuzione del 4 novembre 2026:** su richiesta dell'utente è stata eseguita la parte locale della Fase 0,
con strumenti, misure e una correzione diagnostica verificata. [Esito e limiti](riferimenti/moonshot/fase0-risultati.md).
Questa era la fotografia iniziale; per il gameplay prevale il successivo indirizzo di polish della spedizione. Su ulteriore comando è stato implementato il laboratorio della
Fase 1: [risultati, catture e limiti](riferimenti/moonshot/fase1-risultati.md). L'[ottimizzazione successiva](riferimenti/moonshot/fase1-prestazioni.md)
raggiunge il budget locale del p95 sul M1 a 1080p; restano giudizio visivo, prova Windows e limiti del campione.
Le fasi successive restano su comando dell'utente.

**Estensione richiesta dall'utente:** collegati al campione il cartoncino e gli sprite procedurali esistenti,
con stampa animata aderente alla piega. Anticipata dalla Fase 4 la rimozione della capacità fissa degli snapshot,
con formato dei layer aggiornato e compatibilità v1. [Implementazione, prove e limiti](riferimenti/moonshot/fase1-cartoncino-capacita.md).
Le dimensioni ordinarie della campagna e la gestione delle regioni non cambiano.

**La proposta:** trasformare Odin PP in un atlante abitabile. Ogni bioma è un capitolo: una geografia riconoscibile,
grandi itinerari, edifici in cui entrare e arene che cambiano durante lo scontro. Tutto nasce dalla stessa pagina,
dal piede del Viandante alla volta di una cattedrale. Il salto di qualità si dimostra prima in un itinerario Cyber
completo; poi si estende ai dodici biomi. La carta IA deve comprenderne tutte le regole fin dal laboratorio.

## 1. Decisioni, raccomandazioni e stato della ricerca

### Decisioni già date dall'utente

- Gameplay molto più dinamico; mappa molto più grande, attraversamento lungo ed esplorazione interessante;
  arene elaborate e architetture complesse; miglioramenti visivi.
- Il mondo è un libro, il terreno è la pagina: le figure sono parti sollevate della pagina, con continuità al piede.
  Le vecchie indicazioni di semplice appoggio sono superate. Niente basette o cavalletti.
- Grafica e suoni prodotti da codice. Ricerca su fonti primarie; niente asset scaricati.
- Italiano; niente commit su `main`, niente push senza richiesta; fasi una alla volta su comando dell'utente;
  nuove meccaniche prima nel laboratorio; qualità e prestazioni verificate insieme.
- Ogni novità di gioco aggiorna la IA nello stesso lavoro, con i sei adempimenti di `AGENTS.md:12`.

- **Indirizzo definitivo del 5 novembre:** la spedizione attuale resta la base. Il gameplay richiede
  polish dei sistemi esistenti, senza deviare in un altro sistema di combattimento. Esplorazione libera e
  combattimento tattico a griglia sono preservati. L’utente ha chiesto di togliere le prove di gameplay:
  il laboratorio A/B/C e i suoi artefatti sono rimossi. L’effetto cartoncino rimane.

### Raccomandazioni tecniche da provare

| Scelta | Raccomandazione | Condizione per confermarla |
|---|---|---|
| Gameplay | Polish della spedizione e del combattimento tattico esistenti; non sostituirne le regole | Ogni intervento risolve un problema riproducibile nel gioco reale e viene verificato lì |
| Dimensione | Prima 2× il lato; obiettivo del moonshot 4×, con regioni caricate secondo necessità; 8× solo stress tecnico | Densità interessante, salvataggi corretti e budget misurato: nessuna promozione per il solo numero di celle |
| Generazione | Geografia e luoghi principali progettati; dettagli e varianti generati con vincoli | Ogni itinerario resta riconoscibile e ogni variante giocabile |
| Camera | Conservare quella attuale nella prima prova; vastità attraverso composizione e percorso | Una camera diversa richiede una scelta esplicita e prove di occlusione/picking |
| Tecnica | raylib/OpenGL 3.3 come controllo; ottimizzare dati e lavoro visibile prima della migrazione | Cambiare back-end solo se una prova equivalente dimostra un beneficio necessario |
| Carta | Geometria continua fra superficie, piega e figura; movimento come trasferimento della piega | La continuità si legge da vicino e durante il passo, senza sembrare un sostegno |

### Che cosa è stato consultato e che cosa manca

**FATTO di sessione.** I 17 rapporti citati nella richiesta si trovano in percorsi Windows non accessibili da
questo workspace. Nella ricerca locale iniziale è stato trovato `output/moonshot/CONTESTO.md`, ma non le due
raccolte complete. Questo documento non dichiara di aver letto quei rapporti. Lo stato «pronti alle 04:18» è una
segnalazione dell'utente, non una verifica della disponibilità locale.

È stata svolta una verifica indipendente in parallelo su combattimento/mondo/IA, carta/renderer e scala/back-end,
integrata con storia dei piani e ricerca primaria su design ed esplorazione. I rapporti originali restano una
fonte da riconciliare quando disponibili; non sono sostituiti da una falsa checklist di 17 letture completate.

I tre rapporti indipendenti sono conservati con il piano:
[combattimento e mondo](riferimenti/moonshot/combat-world.md),
[carta e renderer](riferimenti/moonshot/paper-render.md),
[scala e back-end](riferimenti/moonshot/scale-backend.md). Il terzo contiene protocollo e tabella completa;
[harness](riferimenti/moonshot/scala/probe.odin.txt) e log nella stessa cartella rendono verificabili le misure.
Il [supplemento grafico](riferimenti/moonshot/scala-grafica.md) aggiorna il primo tentativo fallito;
il [registro delle prove](riferimenti/moonshot/LEGGIMI.md) spiega come riprodurle.
Non sono i 17 rapporti Windows. I percorsi `/tmp` nei rapporti descrivono il luogo originario della prova.

Legenda delle evidenze:

- **FATTO:** codice o documento letto, con `file:riga` riferito alla base sopra.
- **MISURA DOCUMENTATA:** risultato nel repository, non ripetuto in questa sessione.
- **MISURA:** prova eseguita per questa ricerca, con condizioni e limiti.
- **FONTE:** affermazione di una fonte primaria effettivamente aperta, con URL.
- **INFERENZA / PROPOSTA:** deduzione o progetto da validare. Tutte le sezioni di progetto e le fasi future,
  salvo evidenze marcate diversamente, appartengono a questa categoria.

## 2. Come funziona oggi e dove il riepilogo va corretto

La tabella fotografa la base iniziale del piano. Per la successiva correzione della capacità dei salvataggi
vedere l’aggiornamento della Fase 4 e il [resoconto dedicato](riferimenti/moonshot/fase1-cartoncino-capacita.md).

| Ambito | Evidenza verificata | Implicazione |
|---|---|---|
| Biomi | **FATTO:** dodici voci, da Cyber a Secret (`src/campaign/campaign.odin:8`) | L'identità deve attraversare dodici ambientazioni, non fermarsi alla scena Cyber |
| Dimensioni | **FATTO:** `map_size` raddoppia 80/96/112 (`src/expedition/world.odin:121`) | Le mappe nuove sono 160/192/224; le vecchie dimensioni possono ancora esistere |
| Combattimento | **FATTO:** battito da 1 s (`src/game/tactical_clock.odin:3`), nessuna finestra decisionale nel prodotto (`src/game/tactical.odin:32`); passo normalmente 0,4 s e colpo/schivata 0,5 s (`src/game/tactical_action_cost.odin:6`, `:16`, `:30`); avvisi base nemici 3–5 s (`src/game/tactical_clock.odin:72`) | Un battito al secondo non significa una sola azione al secondo; accelerare ancora richiede valutare l'intreccio degli intenti |
| Esplorazione | **FATTO:** posizione continua, velocità nominali 5,4 a piedi e 8,4 in sella (`src/expedition/roam.odin:7`) | Il movimento continuo esiste già fuori dagli scontri; 3,6 nei documenti più vecchi non è il valore attuale |
| Verticalità | **FATTO:** posizione con `layer`, piani −2, −1, 0, +1 (`src/engine/grid/grid.odin:11`); scale, ascensori e cancelli nel Level (`src/level/level.odin:41`) | Ponti e grotte non sono una novità del moonshot; serve migliorare connessioni, scala e leggibilità |
| Altezze | **FATTO:** salita massima di un gradino, caduta con danno, bonus di gittata da quattro gradini (`src/game/height.odin:18`) | Architettura e rilievo hanno già conseguenze tattiche |
| Geografia | **FATTO:** terreno funzione del bioma e delle coordinate; ritocchi di mappa sovrapposti (`src/expedition/world.odin:142`, `:167`) | Esiste una base per memoria dei luoghi e intervento autoriale |
| Strutture | **FATTO:** planimetrie fino a 12×12 e 64 strutture per Level (`src/level/structure.odin:21`); celle di muro, porta, recinto e uso (`:26`) | Una megastruttura richiede composizione e identità più ampie, non una scatola ingrandita |
| Salvataggio | **FATTO:** massimo 224² celle, 4096 celle supplementari; indice dei piani in 16 bit (`src/expedition/snapshot.odin:7`, `:68`); rifiuto dimensioni oltre limite (`:85`) | Il solo aumento del lato non è un ampliamento funzionante del gioco |
| IA | **FATTO:** ricerca a orizzonti 3/6 secondi, profondità massima 3, 64 candidati (`src/advisor/search.odin:17`); copia profonda del livello (`src/advisor/copy.odin:92`) | «Conoscere tutto» resta un contratto; la ricerca attuale è limitata e non una dimostrazione matematica di ottimalità globale |
| Renderer | **FATTO:** già usa chunk 8×8, preparazione entro ±26 celle e culling (`src/render/expedition_geometry.odin:13`, `:138`, `:238`); gli attori sono quad senza raccordo col suolo (`src/render/expedition_cartoon.odin:258`) | Non riprogettare da zero il culling; la continuità della pagina è invece un lavoro nuovo |
| Contesto IA | **FATTO:** considera progressione, cure e nemici fuori dallo scontro (`src/run/advisor_context.odin:118`); eccezione Cibo pescato (`:80`) | Streaming e nuove distanze devono conservare questa conoscenza |

### Contraddizioni e buchi da non trascinare nel piano

1. **FATTO documentale:** `direzione.md:64` parla ancora di 80–112 celle; il codice ora dice 160–224.
   `docs/piano-profondita.md:292` descrive il punto di partenza storico, mentre la tabella a `:48` riporta le
   fasi concluse. Non usare quel «Com'è oggi» come fotografia del commit corrente.
2. **FATTO documentale:** «carta nel vuoto digitale» e «senza texture» (`direzione.md:33`) sono una direzione
   precedente. La richiesta presente impone la pagina e ammette grafica generata da codice. La storia del robot
   e della memoria (`direzione.md:16`) resta materiale da reinterpretare, non viene cancellata implicitamente.
3. **FATTO documentale:** la camera a 26°/FOV 76° è stata respinta per occlusioni
   (`docs/riferimenti/cartoncino-cartoon/PIANO_PRESTAZIONI_E_SCENA_ILLUSTRATA.txt:246`). Non è una variante approvata.
4. **MISURA DOCUMENTATA:** 18,249 ms Cyber, 14,646 ms West e 26,018 ms con sei nemici sono dati storici
   (`docs/riferimenti/cartoncino-cartoon/PIANO_PRESTAZIONI_E_SCENA_ILLUSTRATA.txt:16`). Esistono misure più recenti,
   riportate sotto. Non dedurre il costo release dai soli risultati `-o:none`.
5. **FATTO documentale:** la pittura procedurale lenta al caricamento normale è già stata affrontata con immagini
   embedded generate dalle routine Odin; cache e fallback verificati
   (`docs/riferimenti/cartoncino-cartoon/VERIFICA_REDESIGN_SOLE.txt:431`). Non pianificare come nuovo un intervento
   già consegnato; verificare invece il suo comportamento sulle regioni grandi.
6. **Buco:** mancano il confronto dei 17 rapporti originali, una misura grafica della scala ampliata su entrambe
   le macchine e una prova dell'utente sulla continuità animata della pagina. Nessuna fonte esterna colma questi buchi.

### Prestazioni: evidenza più recente, senza confondere le corse

**MISURA DOCUMENTATA**, non benchmark di questa sessione: confronto finale del redesign su M1,
1920×1080, limite FPS e vsync disabilitati, 60 frame di riscaldamento, 600 campioni per scena statica,
tre ripetizioni; `-o:speed`, variante finale. Tempi dei frame presentati, non query GPU isolate.
Fonte e protocollo: `docs/riferimenti/cartoncino-cartoon/VERIFICA_REDESIGN_SOLE.txt:254`.

| Scena | Media r1 / r2 / r3, ms | p95 r1 / r2 / r3, ms |
|---|---|---|
| Officina Cyber | 23,477 / 23,068 / 22,949 | 28,525 / 27,449 / 27,435 |
| Officina West | 24,381 / 21,890 / 21,070 | 34,252 / 27,308 / 24,370 |
| Cyber, sei nemici | 29,226 / 25,402 / 25,180 | 36,352 / 31,071 / 30,260 |

**INFERENZA:** il target di 16,67 ms non è dimostrato. West e scontro non migliorano uniformemente in release;
il rapporto stesso segnala variabilità senza causa isolata (`:304`). Non attribuirla automaticamente a GPU,
OpenGL, temperatura o compilatore. Non confrontare M1 debug con RTX release come se fosse un confronto di hardware.

## 3. L'esperienza da costruire

**PROPOSTA.** Il Viandante entra nel capitolo Cyber lungo una piega rialzata della pagina. Oltre una sequenza di
arcate vede il dorso di una grande officina; la strada diretta attraversa un piazzale sorvegliato, una seconda
segue il canale d'inchiostro e raggiunge i sotterranei. Un dettaglio visto dall'esterno anticipa una stanza
raggiungibile più tardi. Il viaggio ha un orientamento, pause e sorprese, non solo una destinazione sull'ologramma.

Nell'officina si combatte passando fra cortile, passerella e sala macchine. Gli avvisi sono disegnati sulla stessa
superficie calpestabile. Una carta sposta un nemico verso un bordo già esistente; un dispositivo può richiudere
una passerella dopo un avviso, oppure aprire una copertura. Il cambiamento è leggibile prima di essere pericoloso.
La IA sa confrontare l'attacco immediato con l'apertura di un percorso sicuro e con la cura raggiungibile dopo.

Vinto lo scontro si apre un collegamento breve al percorso iniziale. Il viaggio di andata è lungo; il ritorno
premia la conoscenza del luogo. Un frammento di memoria modifica il significato di un simbolo visto prima.
La grande architettura funziona come luogo, arena e racconto. Questa scena è la prova della direzione, non
un filmato promozionale separato dal gioco.

## 4. Gameplay: polish della spedizione attuale

**Decisione dell’utente del 5 novembre:** tenere la spedizione come base e migliorarne molto il polish.
Il movimento libero resta nell’esplorazione, la griglia resta fondamentale nel combattimento.
Non si riparte da un kernel alternativo e non si amplia il catalogo per inseguire le varianti A/B/C.
Il laboratorio di combattimento e le sue prove sono stati rimossi su richiesta; il cartoncino grafico resta.

Gli interventi devono partire da un problema concreto del percorso reale:

1. **Comandi e transizioni:** risposta al movimento, priorità degli input, pausa, ripresa, annullamento
   delle azioni accodate e passaggio già esistente fra esplorazione e scontro.
2. **Carte e interazioni:** selezione, bersagli, portata, costo, rifiuto del comando e conseguenza visibile;
   niente comandi che partono in ritardo senza un segnale comprensibile.
3. **Leggibilità:** intenti, danni, coperture, personaggi e ostacoli nella camera della spedizione.
4. **Resa e prestazioni:** applicare il lavoro di cartoncino nel percorso grafico corretto, con misure
   del gioco reale e conservazione delle regole; non dedurre qualità o prestazioni da una demo separata.

Una correzione alla volta: riproduzione, modifica mirata, verifica pertinente e prova nella spedizione.
La carta IA resta aggiornata nello stesso lavoro quando cambiano regole o stato. Un fix di UI che ripristina
un contratto già noto alla IA va documentato come tale, senza fingere una nuova meccanica.
Le proposte di nuove meccaniche nelle fasi future sono da riesaminare dopo il polish, su comando dell’utente.

## 5. Vastità, dimensioni e generazione

### Prova reale di scala di questa ricerca

**MISURA esplorativa:** copia usa e getta di `ddc6b18`, macOS 26.6.2 arm64, Odin
`dev-2026-10:84bc3fc21`, seed 42, Cyber/Snow/Space, tre ripetizioni per caso. Modificata solo `map_size`
con un moltiplicatore; nessun controllo rimosso. Ritocchi manuali esclusi esplicitamente (`retouched=false`).
Generazione e creazione stanza riescono in tutti i casi; `capture` riesce a 1× e fallisce in tutti i casi da 2×.

| Lato relativo | Generazione mediana Cyber / Snow / Space, ms, `-o:none` | Picco heap tracciato Space, byte | Salvataggio |
|---|---|---:|---|
| 1× | 58,382 / 12,947 / 23,579 | 4.582.112 | Capture riuscita |
| 2× | 210,563 / 56,797 / 183,665 | 12.560.096 | Capture rifiutata |
| 4× | 974,483 / 234,029 / 427,746 | 44.472.032 | Capture rifiutata |
| 8× | 1.994,378 / 942,227 / 1.721,736 | 172.119.776 | Capture rifiutata |

La serie aggiuntiva `-o:speed` a 8× misura generazione mediana di 368,202 / 113,700 / 203,602 ms.
Non misura FPS. Il picco include stanza e snapshot, esclude renderer, IA, allocatore temporaneo, stack e
overhead: **non è RSS né memoria totale**. Il tracking torna a zero dopo le distruzioni; non prova assenza di
perdite negli allocatori esclusi. Alcune compilazioni erano concorrenti nella prima serie: nessuna previsione
statistica di prestazioni del prodotto da tre campioni. Tutti i campioni restano nei
[log](riferimenti/moonshot/scala/probe-8.log) e nel [rapporto](riferimenti/moonshot/scale-backend.md).

**MISURA di contenuto:** siti/gruppi restano 16/10 Cyber, 19/14 Snow, 16/12 Space a ogni scala.
**FATTO:** alcuni HP dipendono da `p.x` (`src/expedition/world.odin:274`); i ritocchi richiedono dimensioni
uguali (`src/level/map_edits.odin:87`); `campaign.biome_size` ripete le taglie (`src/campaign/campaign.odin:21`).
**INFERENZA:** questa patch di stress non è un mondo bilanciato o una migrazione utilizzabile.

**MISURA grafica esplorativa:** il primo avvio nella sandbox non produceva frame; la ripetizione fuori sandbox,
autorizzata dalla revisione automatica, riesce a tutte le scale. Log: Apple M1, raylib 6.0, OpenGL 4.1 Metal 90.5.
Una corsa per scala, `-o:none`, ingresso Cyber stage 0, 1920×1080, vsync/limite FPS disabilitati,
20 frame di riscaldamento e 120 campioni. Dettagli nel [supplemento](riferimenti/moonshot/scala-grafica.md).

| Scala | Media / mediana / p95 / massimo, ms | CPU preparazione vista media, ms |
|---|---|---:|
| 1× | 10,549 / 10,595 / 12,464 / 14,318 | 0,181 |
| 2× | 10,112 / 10,289 / 13,232 / 16,529 | 0,447 |
| 4× | 10,127 / 10,294 / 13,277 / 14,520 | 1,601 |
| 8× | 10,346 / 9,799 / 13,664 / 14,512 | 6,411 |

**Limiti:** scena ferma, niente simulazione completa dello scontro; l'ingresso cambia coordinata y con il lato,
quindi cambia anche la geometria locale. Questi frame non sono confrontabili con l'officina o i sei nemici del
redesign. Il costo della vista cresce mentre altri costi cambiano in senso opposto: la media quasi stabile non
dimostra costo costante della scala. Non sono stati certificati gameplay, lunga traversata, release, altri
biomi grafici, costo IA o Windows. Le misure preliminari non sostituiscono il protocollo della Fase 0.

### Quanto cresce la mappa

**CALCOLO, non misura:** moltiplicare il lato per 2/4/8 moltiplica la superficie per 4/16/64.

| Scala del lato | Lati rispetto alle mappe attuali | Celle del caso più grande |
|---|---|---|
| 1× | 160 / 192 / 224 | 50.176 |
| 2× | 320 / 384 / 448 | 200.704 |
| 4× | 640 / 768 / 896 | 802.816 |
| 8× | 1.280 / 1.536 / 1.792 | 3.211.264 |

**CALCOLO illustrativo:** 896 celle percorse in rettilineo a velocità costante di 5,4 richiedono circa 166 s;
a 8,4 circa 107 s. Non sono tempi di partita: ignorano accelerazione, terreno, curve, incontri e soste.
Quindi neppure 4× garantisce da sola un viaggio lungo e interessante. Il criterio vero è la durata dell'itinerario
con le sue scelte, non il cammino da bordo a bordo.

**PROPOSTA:** un primo percorso completo a 2×; un capitolo a 4× come obiettivo, solo dopo verifica. 8× serve a
scoprire cedimenti e margini, non diventa una promessa. Una mappa intera sempre residente e una regione visibile
non devono essere la stessa unità di memoria, disegno, salvataggio o ricerca IA.

### Tre modi di costruirla

| Modello | Vantaggio | Limite |
|---|---|---|
| Grande griglia densa | Estensione diretta dei dati attuali | Copie, salvataggi e scansioni crescono con tutta l'area |
| Regioni contigue caricate a richiesta | Grande viaggio continuo, costo locale controllabile | Richiede confini stabili, persistenza, caricamento anticipato e regole oltre il bordo |
| Pagine separate da transizioni | Costi limitati e composizione precisa | Può indebolire l'attraversamento continuo e la percezione di un solo luogo |

**Raccomandazione:** regioni contigue nello stesso capitolo, transizioni di pagina fra biomi. Progettare prima
la rete di percorsi: asse principale, deviazioni, ritorni e punti riconoscibili. Conservare geografia significativa
fra le run; variare incontri, ricompense, accessi secondari e dettagli attraverso seed separati e versionati.
Un edificio può variare stanze senza spostare ogni volta il punto di riferimento che il giocatore ha imparato.

La densità segue il percorso, non la superficie. Alternare tratto di viaggio, indizio, scelta, arena e sollievo;
tenere spazi vuoti deliberati con una vista o un'aspettativa. Distribuire cure e ricompense sulla difficoltà e sul
costo del tragitto. Aumentare linearmente i nemici con i chilometri quadrati produrrebbe soprattutto lavoro ripetuto.

**FONTE:** la presentazione di Kelsey Beachum descrive una progressione guidata da curiosità e indizi nel mondo
([abstract originale GDC](https://www.gdcvault.com/play/1027368/Independent-Games-Summit-Sparking-Curiosity)).
È stato letto l'abstract, non il video. **INFERENZA:** ogni luogo importante di Odin PP deve promettere qualcosa
da scoprire e lasciare un indizio su un altro luogo, senza importare loop temporali o la struttura di Outer Wilds.

### Camera e senso di vastità

La scelta iniziale mantiene la camera corrente. Comporre grandi forme parzialmente fuori quadro, archi che
incorniciano un luogo successivo, piani sovrapposti, ombre coerenti, variazione fra passaggi stretti e cortili,
percorsi che tornano su luoghi già visti da un'altra quota. L'ologramma mostra il capitolo e i collegamenti
scoperti; non deve diventare obbligatorio per capire dove si cammina.

Alternativa da sottoporre esplicitamente all'utente: viste panoramiche in punti sicuri, o un assetto diverso
durante l'esplorazione. Nessuna rotazione automatica nel mezzo di uno scontro. La camera 26° respinta non rientra
di nascosto. Qualunque variante deve superare prove di porte, interni, passerelle, bersagli vicini e carte sotto
un tetto: un nemico invisibile non diventa accettabile perché il panorama è bello.

## 6. Architetture: complessità attraversabile

**FONTE:** l'abstract universitario di Müller e colleghi descrive CGA Shape come grammatica gerarchica di
involucri architettonici, con regole sensibili al contesto
([Arizona State University](https://asu.elsevierpure.com/en/publications/procedural-modeling-of-buildings-2/)).
È stato letto l'abstract, non il paper completo. **INFERENZA:** separare masse e dettagli è utile, ma un
involucro generato non garantisce interni giocabili; il grafo di percorsi e i validatori qui proposti sono lavoro di Odin PP.

**PROPOSTA:** una grammatica di spazi prima di una grammatica di facciate. Generare un grafo con ingresso,
cortile, sala principale, percorso alto, deviazione e uscita; poi assegnare volumi compatibili con la pagina.
Le relazioni producono porte, scale, passerelle, tagli nella carta e coperture. La planimetria delle regole è la
sorgente di collisioni, navigazione, bersagli e mesh: mai una porta dipinta sopra un muro invalicabile.

Tre scale di lavoro:

- **Modulo:** arco, rampa, pilastro ripiegato, finestra, tetto; giunti, impronta, spazio libero e materiale dichiarati.
- **Edificio:** combinazione con accessi multipli e vista leggibile degli spazi; tetti e pareti si aprono come
  pagine per far leggere l'interno. Aprirli solo visivamente non deve aprire anche la linea di tiro.
- **Complesso:** più edifici e arene con percorsi di aggiramento, punti di orientamento e scorciatoie persistenti.
  I quattro piani esistenti sono il primo limite di progetto; nuovi piani si valutano solo se davvero necessari.

La prima officina comprende un cortile centrale libero, un percorso laterale protetto, un attraversamento alto
e una sala profonda con uscita leggibile. La variante West usa la stessa infrastruttura con silhouette e ritmo
spaziale differenti: portici, strada principale e retrobottega. Così si verifica che il sistema non sappia costruire
solo una cattedrale Cyber.

Validare connessione ingresso/uscita, accesso a servizi e ricompense, larghezza percorribile, spazio libero in
altezza, linee di tiro e possibilità di fuggire dagli avvisi. Separare decorazione e collisione; un livello di
dettaglio lontano può semplificare una cornice, non cambiare una porta. L'editor deve mostrare grafo, superfici
di gioco e pieghe, consentire correzioni manuali e conservare seed/versione della generazione.

## 7. La regola totale: la figura continua nella pagina

**PROPOSTA di interpretazione rigorosa:** la continuità deve essere geometrica e leggibile. Il terreno curva
nel piede e il piede nella sagoma; una linea di taglio separa il contorno, una linea non tagliata fa da piega.
Materiale e stampa continuano attraverso il giunto. Una basetta dello stesso colore o un'ombra non soddisfano
la richiesta. Il comportamento fantastico della carta che cammina va approvato in una prova animata.

**FONTE:** lo studio geometrico dei pop-up a V considera vincoli di pannelli e chiusura senza intersezioni
([abstract universitario](https://orca.cardiff.ac.uk/id/eprint/45698/)); il modello di
[Robert Sabuda](https://www.robertsabuda.com/uploads/2/3/7/2/23729156/white_house_pop.pdf) distingue tagli,
pieghe e pannelli di un edificio. Sono stati letti l'abstract e il testo dello schema, non verificata la
costruzione fisica. **INFERENZA:** adottare giunti e pannelli coerenti; la piega che viaggia è una continuità
geometrica istantanea di un libro fantastico, non una promessa di carta fisicamente fabbricabile.

**FONTE:** [Paper Trail](https://www.papertrailgame.com/) presenta pieghe che cambiano i percorsi;
[Media Molecule su Tearaway](https://www.mediamolecule.com/blog/article/creative_challenge_-_make_a_squirrel/)
descrive un vocabolario di oggetti ricostruibili in carta. **INFERENZA:** la materia guida mondo e azioni.
Queste fonti non dimostrano che ogni loro personaggio continui nel terreno: quella è la richiesta di Odin PP.

| Categoria | Come nasce dalla pagina | Movimento o trasformazione | Verifica |
|---|---|---|---|
| Viandante e nemici a terra | Piede ricavato dalla superficie; bordo inferiore non tagliato nel punto di contatto | Una piega si richiude dietro e si apre davanti, trasferendo il contatto; almeno un contatto visibile durante il passo normale | Fermo, partenza, curva, frenata, salita: niente pattinamento o fessura |
| Cavalcature | Sagoma della mount sollevata; gambe e ventre costruiti dalla stessa porzione di foglio | Passaggio dei contatti più ampio e rapido, cavaliere come piega interna della figura | Montare, smontare, ingaggio e scale senza placca sotto |
| Alberi, rocce, vegetazione | Tagli e pieghe radiali della superficie, con masse che hanno una radice leggibile | Oscillazione limitata che non stacca l'origine | Visti di lato e dall'alto, anche con ombra disabilitata |
| Edifici e strutture posabili | Pareti alzate dalla pianta, volte e tetti ripiegati; fondazione parte del suolo | Piazzamento come apertura; danno come piega/schiacciamento secondo la regola reale | Impronta, porte, orientamenti e rottura coerenti |
| Ponti, scale, grotte | Pieghe e strati del libro con connessione alle due estremità; grotta fra fogli | Aperture solo dove il passaggio esiste; ascensore come superficie collegata da soffietto | Piano sotto e sopra distinti, nessun fondo invisibile attraversabile |
| Acqua, lava, pozze, ghiaccio | Inchiostro, vernice o lamina della pagina, con bordo che ne dichiara lo spessore | Onde e flusso nella superficie; nessun mare realistico estraneo al libro | Pericolo e superficie calpestabile leggibili senza affidarsi solo al colore |
| Bottino e oggetti mobili | Lembo sagomato che emerge dalla pagina nel punto reale dell'oggetto | Raccolta come ripiegamento nel libro/zaino; spinta trasferisce la piega | Visibilità del bersaglio e della posizione vera |
| Evocazioni, Regina, Nido e ragnetti | Apertura locale della pagina; ogni creatura mobile segue la stessa regola dei piedi | Nascita/morte come apertura/chiusura, mai apparizione su basetta | Molti oggetti insieme senza coprire gli avvisi |
| Figure volanti e salti | Piega alta o curva della stessa superficie, parte della figura, non asta aggiunta | Apertura e chiusura sincronizzate con traiettoria e atterraggio | Se il collegamento sembra un cavalletto, la soluzione è respinta |
| Frecce, bombe, detriti | Lembo della figura sorgente collegato al foglio, oppure traccia sollevata continua lungo il percorso | Una striscia si apre davanti e si richiude dietro; la punta rappresenta il corpo fisico | Arco, impatto, occlusioni e carta leggibili anche con molti proiettili |
| Fiamme, raggi, esplosioni, stati | Segni d'inchiostro e pieghe luminose ancorati alle superfici/figure interessate | L'effetto segue la simulazione; luce e ombra non creano falsi solidi | Area dannosa identica all'anteprima |
| HUD, mano, ologramma, hub e minigiochi | Margini, indici e pagine del libro; il mondo dell'hub e dei cabinati applica la stessa grammatica | Transizioni come apertura di sezioni; testi e bersagli restano stabili | Non limitare la regola alla spedizione; controllare anche le viste in prima persona |

Il contratto dei contatti comprende anche schivata, spinte, caduta, morte, cambio quota e variazione di camera.
Per proiettili e detriti la striscia è presentazione: collidono solo corpo e traiettoria autorevoli. Deve essere
chiaro che non è una corda o un ostacolo; segue le occlusioni e non rivela un bersaglio nascosto dietro un muro.

**Questione aperta esplicita:** un corpo completamente staccato in volo contraddice la continuità permanente.
Le soluzioni della tabella sono proposte, non eccezioni già autorizzate. Prima di applicarle al catalogo completo,
provare una freccia, una bomba e un personaggio volante. Se la striscia continua peggiora troppo la leggibilità,
occorre scegliere con l'utente una diversa rappresentazione del volo o una precisa eccezione alla regola.
Non sostituirla tacitamente con «tutto ha una texture di carta».

### Realizzazione e qualità visiva

**FONTE:** il modello di Papas, de Mesa e Jensen distingue riflessione, trasmissione e comportamento dei due
lati della carta ([abstract dell'editore, letto](https://onlinelibrary.wiley.com/doi/10.1111/cgf.12420)).
**INFERENZA per il tempo reale:** partire da fronte/retro differenziati, rugosità controllata e trasmissione
stilizzata sulle pieghe sottili. Il paper non dimostra che questa approssimazione, o il suo modello completo,
rispetti il budget di Odin PP: confrontare qualità e costo sul campione della Fase 1.

Rappresentare superficie sorgente, tagli, linee di piega e pannelli; costruire mesh sottili con fronte, retro e
spessore. Per attori mobili, un intorno deformabile limitato collega il piede al terreno senza rifare la mesh
di tutta la regione. Separare deformazione cosmetica e geometria autorevole: una piega grafica non cambia
collisioni o altezze finché una meccanica non lo stabilisce. Nei giunti di regione mantenere gli stessi campioni
di bordo, normali e coordinate della stampa.

Non serve una simulazione fisica completa della carta per ogni filo d'erba. Pieghe analitiche e pannelli rigidi
articolati sono la prima prova; pieghe complesse solo sui protagonisti e sui luoghi importanti. Da lontano si
riduce il dettaglio, conservando silhouette e origine nel foglio. Texture, maschere, mesh e campioni sonori possono
essere precalcolati dalle routine del progetto; il vincolo è la provenienza da codice, non rigenerarli ogni frame.

Ordine dei fix visivi: contatto e assenza di compenetrazioni; ombre coerenti con quota e piega; separazione dei
piani; bordi stabili senza tremolio; contrasto fra terreno, figure e avvisi; riduzione del rumore decorativo;
solo dopo micrograna, usura e dettagli. Verificare il retro delle figure, clipping ai piedi, giunti dei tetti,
alpha/ordine di disegno, selezione del piano sotto il mouse, prima persona e leggibilità delle carte.

## 8. Suono e racconto del mondo-libro

**FONTE:** [Crumpling Sound Synthesis](https://www.cs.columbia.edu/cg/crumpling/) collega suoni a eventi di
instabilità della carta; è stato letto l'abstract del gruppo di ricerca. **INFERENZA:** sincronizzare frizione,
scatto e strappo agli eventi è utile anche con sintesi semplice. Non importare automaticamente il solver del paper.
**FATTO:** esistono già DSP procedurali e suoni legati a eventi (`tools/audio/dsp.py:1`, `src/render/lab_sounds.odin:9`).

**PROPOSTA:** distinguere carta sottile, cartoncino e copertina con rumore filtrato, inviluppi e risonanze sintetiche.
Una piega breve marca il passo; uno strappo segnala una rottura vera; un fruscio ampio accompagna un'apertura;
gli impatti tattici hanno attacchi brevi e riconoscibili. Collegare energia e durata del suono allo stato reale,
con varianti deterministiche cosmetiche separate dal RNG del gameplay. Limitare le voci simultanee e dare priorità
agli avvisi. Rendere regolabili fruscii, effetti e musica; non affidare un pericolo al solo audio.

La memoria digitale può essere rappresentata come libro riscritto dal creatore: cancellature, annotazioni e
stampe precedenti diventano tracce da interpretare. È una proposta narrativa compatibile con la premessa attuale,
non una nuova storia già approvata. Ogni bioma mantiene materiali e motivi propri: circuiti stampati in Cyber,
manifesti nel West, fogli vegetali nella Giungla, stampe sovrapposte nella City. Le restanti ambientazioni ricevono
una scheda di forma, palette, piega, suono e indizio prima dell'espansione dei contenuti.

## 9. Tecnica: prestazioni, mondo grande e back-end

### Lavoro locale, conoscenza globale

**FONTE:** [World Partition di Epic](https://dev.epicgames.com/documentation/unreal-engine/world-partition-in-unreal-engine)
descrive celle caricate da sorgenti di streaming; i
[geometry clipmaps di Asirvatham e Hoppe](https://developer.nvidia.com/gpugems/gpugems2/part-i-geometric-complexity/chapter-2-terrain-rendering-using-gpu-based-geometry)
mantengono griglie a dettaglio variabile aggiornate incrementalmente. **INFERENZA:** prendere il principio di
residenza e aggiornamento limitati; non migrare a Unreal né applicare automaticamente heightfield a grotte e ponti.

**PROPOSTA:** separare descrizione persistente del capitolo, regioni residenti, insieme attivo della simulazione
e insieme visibile del renderer. Mantenere ID stabili per entità, luoghi e superfici; coordinate intere di regione
e locali, con conversioni esplicite per carte e piani. Evitare puntatori a memoria di una regione scaricata.

Caricare in anticipo lungo i percorsi; preparare dati e geometria fuori dal frame, effettuare upload nel contesto
grafico corretto con budget; espellere cache lontane con limite dichiarato. Conservare modifiche, morti, bottino,
stato dei dispositivi e RNG. Il caricamento non deve duplicare ricompense né resuscitare pattuglie. La navigazione
usa collegamenti fra regioni e ricerca locale, con fallback definito per una regione in arrivo.

Un nemico o proiettile capace di influenzare il giocatore deve restare simulato anche oltre un confine. Definire
il raggio d'influenza dal massimo spostamento/attacco/effetto reale, non dal rettangolo della camera. Dati persistenti
globali danno alla IA cure, pericoli e progresso; copia e simulazione includono tutta la regione causalmente
rilevante. «Non disegnato» non significa «sconosciuto alla IA». Strutture dinamiche invalidano precisamente
navigazione, viste, snapshot e cache interessate.

**FATTO:** Inondazione legge larghezza/altezza della stanza e visita i nemici attivi raggiungibili
(`src/game/flood.odin:58`, `:144`, `:168`). **PROPOSTA:** censire tutti gli effetti globali e definire esplicitamente
che cosa sia la «stanza» in un capitolo a regioni. Un raggio locale finito non copre tutte le carte: servono query
globali o rappresentazioni sufficienti dei dati remoti, mantenendo esattamente i bersagli previsti. Non estendere
silenziosamente l'effetto ai dormienti né restringerlo alla regione caricata. Qualunque revisione della regola
richiede scelta esplicita, IA e puzzle di equivalenza ai confini.

**FATTO:** anche la cronologia visiva delle pozze scarta indici oltre il bitset corrente
(`src/render/presentation_timeline.odin:425`). La migrazione della scala deve censire tutti i consumatori
di `MAX_CELLS`, non soltanto il salvataggio.

Versionare il salvataggio prima di promuovere mappe grandi. Ampliare solo `MAX_CELLS` lascia irrisolti indici a
16 bit, limiti degli altri piani, copia globale e formato. Provare apertura di copie di salvataggi esistenti,
andata/ritorno del formato nuovo, interruzione del checkpoint e corruzione; mai utilizzare il salvataggio personale
come fixture. La politica di migrazione o di rifiuto esplicito va decisa prima della distribuzione.

### Confronto del back-end

**FONTE:** [raylib](https://github.com/raysan5/raylib/wiki/raylib-platforms-and-graphics) documenta la scelta
OpenGL tramite rlgl e l'assenza di OpenGL 4.3 su macOS; la [FAQ GLFW](https://www.glfw.org/faq#how-do-i-create-an-opengl-30-context)
documenta il percorso macOS fino a 4.1. [Apple](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/OpenGL-MacProgGuide/opengl_intro/opengl_intro.html)
dichiara OpenGL deprecato da macOS 10.14. Deprecato non significa che il gioco corrente non possa usarlo.
**FATTO locale:** gli shader dichiarano GLSL 330 (`src/render/expedition_material.odin:110`, `:133`).

**FONTE:** [Sokol](https://github.com/floooh/sokol) offre più back-end e binding Odin; finestra e traduzione
degli shader sono responsabilità distinte da `sokol_gfx`. [bgfx](https://bkaradzic.github.io/bgfx/overview.html)
offre rendering multipiattaforma indipendente dall'engine. **INFERENZA:** Sokol è un candidato pratico per una
prova Odin/Metal, non un'accelerazione dimostrata del nostro gioco.

| Opzione | Beneficio possibile | Costo / limite | Raccomandazione |
|---|---|---|---|
| raylib + OpenGL 3.3 | Riutilizza integrazione, renderer e strumenti; adatto alla prova di mesh e disegno in lotti | Va profilato il costo di submission, ombre, trasparenze e upload | Controllo iniziale |
| raylib con accesso più mirato a rlgl | Intervento circoscritto su passate e batching | Gestione esplicita dello stato GPU e dipendenza dalla versione | Solo sui colli di bottiglia misurati |
| Astrazione come sokol_gfx o bgfx | Percorso verso API native su più piattaforme | Integrazione Odin, shader, risorse, catture e QA da verificare; non è una sostituzione gratuita | Prototipo isolato solo dopo diagnosi |
| Metal su Mac e un altro back-end su Windows | Controllo diretto delle piattaforme | Due percorsi da mantenere per un team di due persone | Ultima opzione se il beneficio lo richiede |

Non basare il progetto comune su funzionalità OpenGL 4.3 richieste obbligatoriamente: il percorso Mac non le
garantisce. Una migrazione non risolve scansioni globali, memoria quadratica o contenuti poveri. Il confronto
deve disegnare la stessa scena con identiche luci, ombre, risoluzione e qualità: misurare p95/p99, caricamento,
memoria, correttezza e costo di manutenzione; una demo vuota veloce non decide il back-end del gioco.

### Budget e protocollo

**OBIETTIVO proposto, non risultato:** 60 FPS a 1920×1080 su M1 e RTX 3060 Laptop, p95 entro 16,67 ms per
ciascun percorso concordato. Riportare anche p99, massimo e numero di frame oltre budget; il solo p95 non
certifica assenza di scatti. Fissare budget di memoria e caricamento dopo la baseline sulle macchine reali.

Registrare commit e patch della prova, toolchain, OS, hardware, alimentazione, carico concorrente, risoluzione
effettiva, seed, camera e qualità. Separare `-o:none` e `-o:speed`. Fare tre ripetizioni per variante in ordine
alternato, 60 frame di riscaldamento e almeno 600 campioni statici; percorso deterministico per il movimento.
Conservare CSV dei frame, non soltanto medie. Catture visive in una corsa separata. Misurare generazione CPU,
upload, primo ingresso a cache fredda/calda, traversata dei confini, salvataggio, picco di heap e risorse GPU;
distinguere memoria tracciata e RSS del processo. Non sommare tempi CPU e GPU sovrapposti come costi sequenziali.

## 10. La carta IA accompagna ogni fase

Non esiste una fase finale «poi aggiorniamo la IA». Per ogni nuova regola:

1. Copiare nuovo stato e RNG in `src/advisor/`; garantire snapshot immutabile e assenza di riferimenti al mondo vivo.
2. Generare mosse e bersagli utili: azionare una piega, attraversare un varco, attaccare attraverso la quota corretta.
3. Valutare gli effetti oltre l'orizzonte: scorciatoia aperta, risorsa spesa, copertura perduta, danno evitato più tardi.
4. Aggiornare `src/run/advisor_context.odin`: accessibilità e quantità delle cure, pericoli, progresso e nemici
   fuori vista. Contare tutte le cure vere tranne Canna da pesca e Cibo pescato.
5. Aggiungere almeno un puzzle significativo e una verifica di equivalenza fra copia e simulazione reale.
6. Scrivere «IA aggiornata» nel registro carte o CHANGELOG. Tabelle esaustive: niente `#partial`, voci fittizie
   o test esclusi per aggirare la regola.

Puzzle minimi del moonshot: aprire un passaggio per evitare un attacco; rinunciare a una scorciatoia che porta
sotto tiro; raggiungere una cura su un altro piano; colpire oltre un confine di regione; scegliere un'azione
utile a una trasformazione che termina dopo sei secondi; cambiare consiglio quando una regione muta.
Per B/C servono inoltre traiettorie e consigli eseguibili con input continuo. Misurare qualità e freschezza del
consiglio, copie e latenza del worker: non eliminare conoscenza del gioco per recuperare FPS.

Una modifica esclusivamente visiva non inventa uno stato di gameplay: si verifica che non abbia cambiato collisione,
bersagli o tempi. Se li cambia, scattano tutti i sei adempimenti. Questo piano documentale non aggiunge una
meccanica e non dichiara falsamente «IA aggiornata» nel codice.

## 11. Stato delle fasi e modo di eseguirle

| Fase | Risultato | Dipende da | Stato |
|---|---|---|---|
| 0 | Evidenze riconciliate e baseline riproducibile | — | Parte locale eseguita; chiusura complessiva aperta, limiti nel resoconto |
| 1 | Pagina continua animata e camera verificata nel laboratorio | 0 | Campione con cartoncino e stampa animata; budget p95 locale verificato, giudizio visivo e prova Windows aperti |
| 2 | Polish della spedizione attuale | 0, 1 per la resa | Riallineata su richiesta: base attuale preservata, prove A/B/C rimosse, fix mirati nel gioco reale |
| 3 | Un'arena dinamica completa, compresa IA | 2 | Da eseguire |
| 4 | Dati del mondo grande, salvataggi e regioni | 0, scelta 2 | Anticipati snapshot dinamici e indici ampi su richiesta; regioni e traversata da eseguire |
| 5 | Grammatica architettonica ed editor | 1, 3, 4 | Da eseguire |
| 6 | Itinerario Cyber a 2× e prova West nel laboratorio | 3, 4, 5 | Da eseguire |
| 7 | Capitolo a 4×, materiali, suoni e copertura delle categorie | 6 | Da eseguire |
| 8 | Biomi rimanenti e integrazione nel gioco vero | 7 | Da eseguire |
| 9 | Verifica finale, prestazioni e chiusura | 8 | Da eseguire |

Il comando è «Esegui la Fase N». Completare una fase non autorizza la successiva. Ogni fase registra decisioni,
file toccati, prove pertinenti e rischi residui; domande soltanto per scelte mancanti che ne cambiano il risultato.
Le nuove meccaniche restano nel laboratorio fino alla Fase 8. I controlli completi sono della Fase 9; prima
si fanno `odin check src -vet -strict-style`, test dei pacchetti toccati e di chi li usa, puzzle IA e atto del
laboratorio pertinente. Benchmark quando cambia il costo del frame o dei dati. Su Windows usare gli script
del progetto e su Mac gli equivalenti documentati, verificandone gli argomenti nella fase.

### Fase 0 — Chiudere le evidenze, prima di impegnare l'architettura

1. Acquisire i 17 rapporti originali; censire autore, base, area e fonti. Risolvere divergenze con codice e prove.
2. Ripetere baseline corrente release/debug; separare scene statiche e percorso deterministico.
3. Completare scala 1×/2×/4×/8× in copia temporanea: generazione, memoria, frame, primo ingresso, traversal,
   snapshot e IA. Conservare esattamente patch, comandi, log e fallimenti.
4. Identificare il costo dominante prima del prototipo di back-end; fissare soglie di memoria e caricamento.

**Fatto quando:** ogni dato ha provenienza; ogni misura impossibile è elencata con causa; la scelta della
dimensione ha limiti espliciti e un protocollo eseguibile su entrambe le macchine. La ricerca di questa sessione
è input della fase, non certificazione che la fase sia già fatta.

**Esito locale:** [risultati e prove](riferimenti/moonshot/fase0-risultati.md),
[riconciliazione delle evidenze](riferimenti/moonshot/fase0-riconciliazione.md) e
[protocollo eseguibile](../tools/moonshot/README.md). Il driver grafico conserva i singoli fotogrammi e
usa un passo simulato fisso opzionale; un probe separato misura mondo, snapshot e ricerca IA. Le copie
di scala mantengono tutti i guardrail. Il gioco distribuito non viene ingrandito da queste prove.
24 corse headless e 12 grafiche complete, un timeout grafico conservato; correzione dell'uscita anticipata
verificata in una serie separata. Mancano gli originali Windows, le prove sul secondo PC, il caricamento
completo freddo/caldo e la memoria su una traversata chiusa. La carta IA non ha nuove regole in questa fase.

### Fase 1 — La pagina prende vita

1. Un campione di suolo, Viandante, nemico, oggetto, arco e piccolo ponte collegati alla pagina.
2. Passo, curva, salita, montata, morte; poi freccia, bomba e volo per decidere i casi difficili.
3. Catture ravvicinate e sequenza nella camera reale; picking sotto arco e tetto, ombre, prima persona.
4. Confronto visivo dell'utente; scegliere esplicitamente ogni eventuale eccezione. Misurare costo e memoria.

**Fatto quando:** il piede appare parte della pagina anche in movimento; nessuna basetta; i bersagli restano
leggibili. **Rischio:** effetto bello da fermo che durante il passo sembra gomma o una striscia di sostegno.

**Esito locale:** [primo campione, misure e limiti](riferimenti/moonshot/fase1-risultati.md), seguito dal
[collegamento del cartoncino con gli sprite esistenti](riferimenti/moonshot/fase1-cartoncino-capacita.md).
La stampa anima occhi e passo sulla superficie piegata. Nella morte cambia l'espressione mentre la geometria
richiude la figura nella pagina: il disegno non deve collassare una seconda volta dentro la sagoma.
Restano aperti giudizio sul movimento, stile definitivo ed eccezioni freccia/bomba/volo.

**Ottimizzazione locale del 4–5 novembre:** [misure e parità](riferimenti/moonshot/fase1-prestazioni.md).
Ombre indicizzate nello spazio della luce, emissione per poligono e classificazione delle sagome per zone.
Sul M1 a 1080p tutte le dodici misure finali del p95 sono entro 16,7 ms; in salita 14,08–16,31 ms contro
17,81–18,20 ms della baseline. Geometria identica su 2.185 pose e 61 catture native identiche; 543 test renderer
superati. È una verifica del campione, non di ogni frame della campagna o del secondo PC.
La Fase 2 e la pulizia dei branch non vengono avviate da questo intervento.

### Fase 2 — Polish della spedizione attuale

1. Riprodurre un problema concreto di comandi, interazioni o leggibilità nella spedizione esistente.
2. Correggerlo senza cambiare modello di gameplay; verificare copie, contesto e consiglio IA se interessati.
3. Eseguire test pertinenti e una prova del percorso reale quando cambiano grafica o input.
4. Raccogliere il riscontro dell’utente prima di ampliare l’intervento a un altro sistema.

**Fatto quando:** le criticità concordate della spedizione sono risolte, il controllo è prevedibile,
le conseguenze leggibili e il budget misurato nel gioco reale. **Rischio:** scambiare nuove meccaniche
per polish e perdere nuovamente la direzione.

**Riallineamento del 5 novembre:** rimossi laboratorio A/B/C, relativo kernel/renderer/IA, driver,
flag e artefatti. Restano il cartoncino, le sue prove grafiche e la correzione degli snapshot.
La Fase 3 non è avviata; le proposte di gameplay future devono essere rivalutate alla luce di questo vincolo.

**Primo fix concreto:** la pausa della spedizione elimina l’input accodato, come già fa il controller tattico
(`src/run/expedition_scene.odin:322`). La regressione `src/run/expedition_pause_test.odin:7` fallisce prima
ed è superata dopo: nessun passo pre-pausa viene emesso alla ripresa, un nuovo input resta valido e il
Player completo è invariato. Non introduce regole nuove per la IA; il suo stato e i controlli restano intatti.

**Polish del 6 novembre:** esteso il controllo a zaino, scheda personaggio, mappa, modali e fine incontro;
verificato il focus. I pannelli liberano il cursore in prima persona e la chiusura non diventa un colpo.
La IA riceve ora la notifica dei consumabili effettivamente usati. Il rossore degli
attacchi era già presente: viene propagato anche ai costumi che lo coprivano, conservando il countdown
canonico. Questi interventi lavorano sulla spedizione reale; non riaprono il confronto A/B/C.

**Passo successivo autorizzato il 6 novembre — carte e leggibilità:** annullamento delle carte accodate,
cambio carta durante un piazzamento orientabile, motivi dei bersagli rifiutati e feedback alla quota
corretta su rilievi, ponti e grotte. La carta IA verifica anche la validità attuale del bersaglio e segue
il nemico che si sposta. Verifica con regressioni, copia/live e input reali nella spedizione; il comando
autorizza commit e push sul ramo `piano-moonshot` dopo i controlli. Esplorazione e integrazione del nuovo
cartoncino nella spedizione sono i passi successivi, ancora da avviare. Pulizia dei branch rinviata.

### Fase 3 — Una trasformazione tattica completa

1. Un dispositivo di piega apre/chiude un passaggio con avviso; definire occupanti, traiettorie e interruzioni.
2. Comporre un'arena con quota e aggiramento, usando le regole della variante scelta.
3. Copia, mosse, valutazione, contesto e puzzle IA; prove equivalenza e input durante la trasformazione.
4. Animazione e suono da codice, anteprima e fallback leggibile; prova dell'utente.

**Fatto quando:** il cambiamento offre una scelta comprensibile e la IA la usa bene. **Rischio:** trasformazioni
puramente spettacolari o blocchi senza fuga. Non aggiungere contemporaneamente un intero catalogo di dispositivi.

### Fase 4 — Il mondo può crescere senza perdere lo stato

1. Specificare ID, confini, regioni residenti, effetti globali, copie IA e invalidazione; rimuovere limiti di formato necessari.
2. Formato versionato e compatibilità concordata; checkpoint su copie, ricompense e nemici persistenti.
3. Caricamento anticipato, cache limitate, navigazione fra regioni e simulazione al bordo.
4. Misure 2×/4×/8×; attraversare ripetutamente confini, combatterci sopra e riaprire il salvataggio.

**Fatto quando:** nessuna perdita o duplicazione di stato, memoria stabilizzata durante una lunga traversata,
IA completa e tempi registrati. **Rischio:** copie dell'intera mappa nascoste o dipendenze da regioni scaricate.

**Anticipo autorizzato:** snapshot dinamici fino a 1792×1792, layer con indice a 32 bit, copie autonome
per il salvataggio asincrono e caricamento limitato; prove di salvataggio/caricamento/ripristino e puzzle IA
oltre l'indice 65535. Questo conclude la correzione di capacità richiesta, non la Fase 4: mancano regioni,
memoria stabilizzata, cache di presentazione estese e attraversamento dei confini.

### Fase 5 — Costruire luoghi, non decorazioni

1. Grafo di spazi, moduli con giunti e connessioni, edifici e complessi; generazione con seed/versione.
2. Un'unica pianta produce regole e geometria; editor con correzioni conservate.
3. Validatori di percorribilità, altezze, accessi, avvisi e uscite; casi IA fra piani.
4. Officina Cyber e variante West, viste esterne/interne e tetti aperti.

**Fatto quando:** si può entrare, aggirare, combattere e uscire da ogni variante accettata. **Rischio:** facciate
ricche davanti a stanze tutte uguali; nuovi limiti sostituiti da numeri arbitrariamente enormi.

### Fase 6 — La prima traversata lunga

1. Percorso Cyber a 2× con viaggio, arena, deviazione, servizio, segreto e ritorno breve.
2. Geografia riconoscibile e contenuto finito; mappa e indizi coerenti con i luoghi.
3. Misurare tempi di viaggio, soste, deviazioni scelte, leggibilità e costo delle transizioni.
4. Provare una sezione West per verificare varietà del sistema; test dell'utente.

**Fatto quando:** l'utente vuole esplorare il percorso e sa orientarsi; prestazioni e persistenza rispettano i
budget concordati. **Rischio:** distanza percepita come attesa, distribuzione di cure/ricompense sbilanciata.

### Fase 7 — Il capitolo del moonshot

1. Estendere a 4× se la prova 2× funziona; altrimenti correggerne ritmo e tecnica prima di ingrandire.
2. Coprire tutte le categorie della sezione 7, compresi hub, minigiochi e viste speciali con campioni rappresentativi.
3. Materiali, suoni sintetici e racconto ambientale; impostazioni di leggibilità e intensità effetti.
4. Profilare piena densità, combattimenti e lunga permanenza, anche con IA accesa.

**Fatto quando:** il capitolo completo esprime tutti e cinque gli obiettivi senza eccezioni grafiche nascoste.
**Rischio:** costo della copertura del catalogo sottovalutato; 8× resta prova di stress.

### Fase 8 — Portare il risultato nel gioco vero

1. Scheda di identità e percorso per ogni bioma; estensione per piccoli gruppi, con riscontri dell'utente.
2. Catalogo completo di carte, nemici, oggetti, strutture, ambienti, hub e cabinati con stato di conversione.
3. Aggiornamento IA e registri insieme a ciascun contenuto. Versione salvataggi e note di compatibilità.
4. Promuovere dal laboratorio solo ciò che ha superato i criteri; documentare ciò che viene rimandato.

**Fatto quando:** ogni categoria e ogni bioma hanno una copertura verificata. **Rischio:** mescolare qualità
vecchia e nuova dichiarando conclusa la regola totale.

### Fase 9 — Consegna verificabile

1. Check completi del progetto, laboratorio completo, suite IA, salvataggi e regressioni.
2. Benchmark su M1 e RTX 3060 Laptop, stesso protocollo e scene; sessioni lunghe, cache fredda/calda.
3. Catture native e filmati di viaggio, contatto del piede, architettura e combattimento; ispezione visiva reale.
4. Verifica dei cinque obiettivi, aggiornamento piani/regole/registro e pulizia dei soli residui delle prove.

**Fatto quando:** l'utente approva l'esperienza, i budget sono rispettati o gli scostamenti sono esplicitamente
accettati, tutti i buchi sono dichiarati. Nessun push automatico.

## 12. Rischi e criteri per cambiare strada

| Rischio | Segnale osservabile | Risposta |
|---|---|---|
| Mondo grande ma vuoto | Tratti lunghi senza orientamento o scelta | Riprogettare percorso e indizi prima di altra superficie |
| Carta continua illeggibile | Piedi, strisce o pieghe nascondono minacce | Rivedere la grammatica in Fase 1; decidere esplicitamente i casi impossibili |
| Architettura occludente | Danno da nemico non leggibile, clic sul piano sbagliato | Correggere taglio dei tetti, sagome e composizione; camera solo con nuova decisione |
| IA resta indietro | Copia divergente, mosse mancanti, consiglio fuori tempo | Fermare la promozione della meccanica, aggiornare modello e puzzle |
| Memoria cresce con la traversata | Cache lontane mai liberate, RSS crescente dopo ritorni | Limiti di residenza, ownership e distruzione verificati |
| Cambio back-end senza beneficio | Demo veloce, scena reale ancora lenta | Tornare alla diagnosi CPU/GPU/dati, conservare il controllo raylib |
| Scope oltre il team | Nuovi biomi, combattimento e renderer riscritti insieme | Prima itinerario completo; ogni fase consegna un risultato giocabile |
| Regressione dei salvataggi | Ripresa diversa o premio duplicato | Non distribuire; correggere versione e transazioni su fixture |

## 13. Fonti e copertura della richiesta

Le fonti locali sono citate accanto ai fatti. Le fonti esterne aperte sono citate nelle sezioni pertinenti e nei
rapporti integrativi collegati nella sezione 1; da ciascuna si prende un principio, non un asset o un sistema da copiare.

**Verifica documentale iniziale del 4 novembre, prima dell'esecuzione:** due revisioni indipendenti hanno controllato combattimento/mondo/IA
e carta/renderer. Integrate le correzioni su ritmi già accelerati, effetti globali come Inondazione, continuità
nelle azioni speciali e infrastruttura grafica già esistente. Controllati esistenza dei file e validità delle
righe citate, collegamenti locali, mediane contro i log e copertura dei cinque obiettivi. In quella stesura
nessun file del gioco era cambiato e nessuna fase era stata eseguita. L'esecuzione successiva è registrata
nella Fase 0. Restano aperte le evidenze elencate
nelle sezioni 1, 2 e 5, compresi rapporti originali e verifica completa su entrambe le macchine.

| Richiesta | Risposta nel piano | Prova che la chiude |
|---|---|---|
| Gameplay dinamico | §4, §10 | Polish della spedizione e del tattico esistenti, con IA coerente |
| Mappa grande, arene, vastità e viaggio | §3, §5, §9 | Percorso 2×, capitolo 4× condizionato, scala misurata |
| Architetture complesse | §6 | Edificio e complesso con percorsi e piani reali |
| Fix e qualità visiva | §7, §9 | Catture native, picking, ombre, bordi e budget su entrambe le macchine |
| Tutto nasce dalla pagina | Matrice §7 | Passo/volo/oggetti/architettura, poi catalogo completo |
| Carta IA conosce ogni novità | §10 e tutte le fasi meccaniche | Copia, mosse, valutazione, contesto, puzzle e registro |
| Ricerca e confronto nella stesura iniziale | §1, §11 | Fonti verificabili e distinzione fra proposta ed esecuzione |
| Mettere in atto il piano, richiesta successiva | Fase 0 e relativo resoconto | Strumenti, misure, test e limiti registrati; fasi successive su comando |

## Appendice A — Richiesta ricevuta, parola per parola

Il testo seguente è la richiesta di questa sessione. Non ricostruisce i prompt di altre conversazioni.

```text
HELLUUUUUU!! :33
questo e' il task di oggi!!

MOONSHOT DI ODIN PP: COSA STIAMO FACENDO E COME È ORGANIZZATA LA RICERCA

  PROGETTO
  Odin PP è un roguelike di esplorazione e deck building in Odin + raylib, fatto da
  LucaGranito (Windows, RTX 3060 Laptop) e 0xdokkan (Mac M1).
  Base di lavoro: ramo piano-ia, commit d71b83a. È lo stato più nuovo del gioco e include
  il redesign di cartoncino di 0xdokkan.

  OBIETTIVO
  Scrivere un documento che proponga un moonshot per farne il gioco dei sogni dell'utente:
  1. gameplay molto più dinamico;
  2. mappa molto più grande, con arene elaborate, senso di vastità, attraversamento lungo
     ed esplorazione bella;
  3. strutture architettoniche molto più complesse;
  4. fix visivi e accorgimenti belli sulla grafica;
  5. regola grafica totale: il mondo è un libro e il terreno è la pagina. Personaggi,
     nemici e oggetti non sono appoggiati: sono pezzi della pagina staccati, aperti e
     sollevati. Esempio: il piede resta spiccicato sul pavimento e la figura si alza da lì.

  COSA È GIÀ ACCERTATO
  - Oggi ci sono 12 biomi, mappe da 160, 192 o 224 celle per lato, combattimento a griglia
    con battito di un secondo e senza timer, camera dall'alto leggermente inclinata.
  - Nel redesign i 60 FPS non sono ancora raggiunti. Misure su M1 in build -o:none: Cyber
    18,2 ms di media, West 14,6 ms, combattimento con sei nemici 26 ms.
  - Un prototipo di camera a 26 gradi è stato scartato per le occlusioni: la vastità dovrà
    ottenere una nuova scelta esplicita sulla camera, o farne a meno.
  - I prompt moonshot precedenti vietano basette e cavalletti. La nuova regola va oltre:
    la figura deve continuare nella pagina.
  - Regola per sempre: ogni novità del gioco aggiorna anche la carta IA.

  COME È ORGANIZZATA LA RICERCA
  Due filoni in parallelo, ognuno con agenti indipendenti che scrivono un rapporto.

  Filone 1, capire il gioco: nove rapporti.
  Combattimento, mondo, strutture, rendering, arte e carta, contenuti, processo di lavoro,
  storia delle decisioni, e una prova reale di scala: in una copia usa e getta si fa
  crescere la mappa a circa 2x, 4x e 8x di lato, annotando cosa si rompe e misurando
  generazione, memoria e tempo del fotogramma.
  Rapporti in: C:\Users\lukeg\AppData\Local\Temp\claude\C--Users-lukeg-OneDrive-Documenti-GitHub-ODIN\96e83fbd-cc4c-48eb-928a-e0b693946aec\scratchpad\understand

  Filone 2, ricerca esterna: otto rapporti.
  Ingegneria della carta e libri pop-up, giochi di carta e di libri, resa della carta in
  tempo reale, architettura procedurale, combattimento dinamico, vastità ed esplorazione,
  tecnica per mondi grandi e scelta del back-end grafico, suono e narrazione del mondo-libro.
  Rapporti in: C:\Users\lukeg\AppData\Local\Temp\claude\C--Users-lukeg-OneDrive-Documenti-GitHub-ODIN\96e83fbd-cc4c-48eb-928a-e0b693946aec\scratchpad\ricerca

  REGOLE DI PROVA
  - Sul codice: sola lettura, ogni affermazione con file:riga, numeri veri, e distinzione
    fra FATTO, MISURA e INFERENZA. Se documento e codice divergono, vale il codice.
  - Sul web: fonti primarie lette davvero, URL per ogni fatto importante, distinzione fra
    FONTE e INFERENZA. Nessun download di asset e nessun numero inventato.
  - Dai riferimenti si estraggono principi, non si copiano giochi.

  COSA VIENE DOPO
  1. Leggere tutti i rapporti e segnare contraddizioni e buchi.
  2. Confrontare più approcci sulle scelte di fondo:
     - combattimento: griglia veloce, griglia fine con movimento continuo, o azione libera
       con le carte come abilità;
     - mondo: quanto cresce la mappa e quanta parte è procedurale;
     - tecnica: restare su raylib e OpenGL 3.3 o cambiare back-end, sapendo che il Mac si
       ferma a OpenGL 4.1;
     - resa: come applicare la regola della pagina a ogni categoria di cose disegnate.
  3. Scrivere il documento in italiano, con raccomandazioni e fasi. Destinazione prevista,
     non ancora creata: docs/piano-moonshot.md su un nuovo ramo partito da piano-ia.
     Struttura come gli altri piani: decisioni, stato delle fasi, come funziona oggi,
     fasi con passi, rischi, fonti, appendice con la richiesta parola per parola.
  4. Verificare il documento contro il codice e la fattibilità, e controllare che ogni
     punto della richiesta abbia la sua risposta.

  VINCOLI
  Risposte e documenti in italiano. Niente commit su main e niente push senza richiesta.
  Fasi eseguite una alla volta su comando dell'utente. Nuove meccaniche prima nel
  laboratorio. Grafica e suoni fatti da codice. Sempre massima qualità e prestazioni.
  Ricerca su internet per tecnica e riferimenti.

  STATO ALLE 04:18
  Pronti: arte e carta, contenuti, decisioni, architettura, giochi di carta.
  Gli altri rapporti non risultano ancora pronti, e la prova di scala non ha ancora un
  rapporto. Nessuna scelta di design è stata presa e nel repository non è stato scritto
  nulla.
```

## Appendice B — Comando di esecuzione successivo

```text
ora che hai scritto il piano vorrei che tu lo metta in atto :33
```

Applicato alla Fase 0, rispettando la regola già richiesta: una fase alla volta, su comando dell'utente.


## Appendice C — Comando per la Fase 1 e chiarimenti

> vai alla prossima!! perche' gli snapshot falliscono??

Applicato alla Fase 1, con spiegazione del limite di snapshot e mantenendo la migrazione dei salvataggi in Fase 4.

> questi disegnini che stai facendo e stai anche facendo muovere che utilizzo hanno??

Chiarito lo scopo di campione tecnico della continuità della pagina, distinto dall'approvazione dello stile definitivo.

> sara' poi possibile applicare l'effetto cartoncino e delle animazioni all'interno del cartoncino come nei placeholder che abbiamo attualmene??

Confermata la fattibilità progettuale di supporto piegato e stampa animata, mantenendo esplicito il lavoro di integrazione
ancora necessario; vedere il resoconto F1. Nessuna nuova fase autorizzata da questi chiarimenti.


> fai partire il test di nuovo voglio rivederlo!! e continua a fare quello che stai dacendo!! :3

> facendo*

Laboratorio riaperto in modalità interattiva e lasciato disponibile mentre vengono completati controlli e documentazione.


## Appendice D — Capacità e stampa nel cartoncino

> risolvi la capacita' delle celle!! quali sono i prossimi step e puoi gia' implementare l'effetto cartoncino con sprite dentro nel test che hai fatto dei fogli??

Autorizza la correzione degli snapshot anticipata dalla Fase 4 e il collegamento del cartoncino al campione Fase 1.
Non equivale all'avvio del confronto di combattimento né all'ampliamento predefinito della campagna.

> lo sprite della morte e' giu' quindi non rende bene l'effetto!!

Correzione applicata alla stampa del laboratorio: anatomia eretta sul supporto, espressione di morte negli occhi;
la chiusura verso il terreno appartiene alla geometria del cartoncino.


## Appendice D — Chiarimento sul movimento, parola per parola

> no comunque la componente del movimento a griglia tattico e' davvero fondamentale :'3

> non si puo' rimuovere pur troppo!!

> - Muoversi liberamente fuori dallo scontro e usare la griglia durante il combattimento.
> !!!


## Appendice E — Ritorno alla spedizione e rimozione delle prove

> per quanto riguarda le migliorie del gameplay!! teniamo la base attuale del gioco (ovvero la spedizione) e lavoriamo tanto su un polish di quello!! non divaghiamo troppo perche' stiamo perdendo direzione :33

> puoi anche togliere le prove che hai fatto perche' non servono!! ma l'effetto a cartoncino che hai progettato puo' benissimo rimanere!!

## Appendice F — Carte, leggibilità e pubblicazione del ramo

I punti 1 e 2 sono il polish delle carte e la leggibilità degli scontri nella spedizione.

> ti direi di fare fino al punto 2 poi puoi committare e pushare!! :3
