# Cronologia e roadmap storica

Questa sezione conserva la cronologia delle implementazioni e delle verifiche.
I riferimenti a Classica, `--flat` e ai vecchi smoke descrivono versioni precedenti;
per i comandi disponibili oggi valgono il [README](README.md) e la documentazione collegata.


## 2026-10-27 — Profondità, Fase 7 (in corso): Cielo, Spazio e Memoria

- **Cielo, un'isola sospesa** (scelta dell'utente): su un'isola libera galleggia un'isola più piccola di marmo, 14 gradini
  sopra, con guardie e segreto. Ci si sale da una scalinata che gira attorno a un pilastro; l'ascensore, una colonna di
  luce, ha il cancello sul pianerottolo, che si apre dall'isola. Sotto ci si passa all'ombra; i ponti fra le isole restano
  come prima.
- **Spazio, gallerie fra i crateri:** lo Spazio si alza di una base e si vede come prima. Tre crateri profondi 14: uno con
  la scala, uno con guardie e segreto sul fondo, uno con l'ascensore. Le gallerie sul piano −2 li uniscono uscendo dalle
  loro pareti; il cancello fra il cratere del segreto e quello dell'ascensore si apre dalla parte del segreto. In superficie
  la stazione: tre moduli uniti da passerelle, rampa, ascensore con il cancello in cima, segreto e guardie sul modulo di
  mezzo. I pozzi di gravità restano dove sono, anche sopra i moduli.
- **Memoria, la collina del masso:** la grande collina in mezzo alla mappa era tagliata dal terreno in piano della Fonte e
  della Prova (restava una cresta alta 7) e non c'è più. Al suo posto, in un punto libero, una collina vera alta 14 con il
  masso in cima: un sentiero sale da sud a una terrazza, la gira e sale sul fianco est fino in cima; da lì un pozzo con
  l'ascensore scende nella sala della memoria, dentro la collina, con guardie e segreto. Il passaggio della sala esce ai
  piedi dello sperone sud, con un cancello che si apre da dentro.
- Segni nuovi nelle mappe dei complessi: segreto e guardie su un ponte (`+`, `*`), segreto in galleria (`?`), il masso
  (`O`). Fino a quattro complessi per bioma; un cratere si cerca il posto vicino a quello prima.
- **Tutti i dodici biomi hanno i loro piani:** il lavoro della Fase 7 è fatto; per chiuderla restano due verifiche alla
  corrente (sotto). Nel documento torna il titolo della Fase 8, perso con il primo gruppo.
- Smoke delle spedizioni: 18 catture nuove dei complessi e 3 delle gallerie dello Spazio (191 in tutto); i complessi vanno
  dallo stage 104 al 175, le reti dal 176 al 190.
- Test nuovi: l'isola sospesa, le gallerie fra i crateri, la collina con la sala; complessi e prove con i nemici liberi in
  dodici biomi (1735 in tutto).
- Verifiche: check completo con e senza assert, smoke delle spedizioni (191 catture) e dell'editor senza errori. Lo smoke
  del laboratorio si è fermato al limite di tempo a 86 catture su 129 (83 identiche al byte, tre delle strutture con pochi
  pixel diversi) e il benchmark non è fatto: il portatile era a batteria, al 4%. Tutti e due vanno rifatti alla corrente.

## 2026-10-26 — Profondità, Fase 7 (in corso): Neve, Inferno e Gotico

- **Neve, il crepaccio scavato** (scelta dell'utente): la Neve si alza di una base, come City pop, Egitto e Vietnam, e si
  vede come prima (montagna e grotta della montagna comprese). Nella neve c'è un crepaccio profondo 14: una scala scende
  dall'ovest, il ponte di corda lo attraversa alla quota della neve, sul fondo guardie e segreto, e un ascensore scende
  dalla neve in una nicchia il cui cancello si apre dal fondo.
- **Inferno, il ponte di ossa:** due rupi ai lati di un fiume di lava, il ponte sopra la lava fra le cime. Nella rupe est
  c'è la caverna di lava con le guardie, chiusa da un cancello che si apre da dentro, con il pozzo fino alla cima. Si sale
  a piedi da una scala che gira. L'eruzione non rompe più la roccia dei complessi.
- **Gotico, cripta e catacombe:** il Gotico si alza di una base. Sotto ci sono il pozzo con l'ascensore, la cripta sotto la
  collina (guardie e segreto) e le catacombe fino al cimitero, con scale da due tombe aperte. Il cancello fra il pozzo e la
  cripta si apre dalla cripta. Sopra, il fienile e la casa in rovina con il ballatoio fra i tetti.
- **Il killer del Gotico non scende sotto terra:** lì lo si semina; uno scontro con lui finisce quando il robot scende.
- **Disegno:** le pareti delle buche sotto la base (scale e crepaccio) hanno la roccia del bioma, più chiara al bordo, e il
  fondo si scurisce con la profondità: prima erano una fessura nera. Ponti di corda, di ossa e il ballatoio hanno il loro
  materiale.
- Smoke delle spedizioni: 18 catture nuove dei complessi e 3 della rete del Gotico; i complessi vanno dallo stage 104 al
  157, le reti dal 158. La cima della montagna e lo scontro su due livelli contano le quote della Neve dalla base.
- Test nuovi: il crepaccio scavato, il ponte sopra la lava, il killer che non scende; complessi e prove con i nemici liberi
  in nove biomi (1732 in tutto). Il test dell'arena degli ascensori non perde più la memoria della registrazione del
  renderer.
- Verifiche: smoke del laboratorio identico al byte (129 catture), smoke delle spedizioni (170 catture) e dell'editor senza
  errori; benchmark alla corrente in ordine bilanciato: media −2,4%, i complessi nuovi 1,12 ms, la rete del Gotico 1,18 ms.

## 2026-10-26 — Profondità, Fase 7 (in corso): City pop, Egitto e Vietnam, con i sotterranei

- **Terreno alzato di una base** (scelta dell'utente): City pop, Egitto e Vietnam sono alzati tutti di 14 gradini, così
  sotto c'è posto per reti vere sul piano −2. La superficie è identica e si vede come prima: il disegno toglie la base.
- **Le reti sotterranee:**
  - City pop: la metropolitana, tre stazioni unite da gallerie, con le scale dalla strada alle due stazioni in fondo e
    l'ascensore in quella di mezzo; il cancello fra la stazione di mezzo e quella a sud-est si apre da sud-est;
  - Egitto: la necropoli, con la grande sala (scala che scende dalla sabbia), una tomba col segreto e la sala sotto la
    piramide, raggiunta dal pozzo con l'ascensore che scende dalla sua cima; il cancello si apre dalla grande sala;
  - Vietnam: la galleria vera, dal tunnel di oggi fino a dove il tunnel portava, con sei camere e quattro botole; il
    salto con E non c'è più.
  - Le scale sono buche con una rampa di 13 gradini; le gallerie girano attorno a muri e decorazioni; nelle sale ci sono
    nemici del bioma e un segreto.
- **I complessi:** in City pop tetti e cavalcavia fra tre palazzi (scala antincendio, ascensore, cancello sul
  cavalcavia); in Egitto due piramidi a gradoni con le terrazze e una scala che gira; in Vietnam due colline sulle rive
  di un fiume e un ponte di bambù sopra l'acqua, con cancello e ascensore.
- **Disegno:** le buche delle scale hanno le loro pareti; sotto terra la finestra attorno al robot è più larga e la
  superficie più scura; cavalcavia e ponti di bambù hanno il loro materiale.
- **La telecamera dopo un salto:** sui piani prendeva la quota nuova un po' alla volta anche quando saltava (una mappa
  nuova, il robot messo altrove), partendo da quella di prima. Ora la prende subito: cambiano le catture degli smoke
  fatte dopo un salto di piano, con la stessa scena e il robot al centro.
- Smoke delle spedizioni: 18 catture dei complessi nuovi e 9 delle reti, dagli stage 122 e 140
  (`ODIN_PP_SMOKE_ONLY=complessi`, `ODIN_PP_SMOKE_ONLY=reti`).
- Test nuovi: le reti nei biomi alzati, segreto e nemici raggiungibili, la galleria del Vietnam dal tunnel all'arrivo,
  la base nel salvataggio, la telecamera che salta di piano; le prove con i nemici liberi ora girano nei sei complessi
  (1729 in tutto).
- Prestazioni (RTX 3060, alla corrente): media +2,0%, dentro il rumore; costano 0,1-0,15 ms in più solo le viste dove la
  rete passa sotto, al centro di City pop e dell'Egitto.

## 2026-10-26 — Profondità, Fase 7 (in corso): i complessi di Robotica, Far West e Giungla

- **Complessi a tema, alti 14** (scelta dell'utente all'inizio del primo gruppo di biomi): la regola dei piani vuole 12
  gradini fra due pavimenti della stessa colonna, e gli altopiani di oggi ne hanno 3 o 4. Ogni bioma del gruppo ha ora
  un complesso a un posto fisso, uguale a ogni run; il resto della mappa resta com'era.
  - **Robotica cibernetica:** due piattaforme dati unite da una passerella. Sotto la piattaforma col segreto c'è un
    condotto: il cancello all'imbocco si apre da dentro, e un pozzo con l'ascensore sale fino in cima.
  - **Far West:** il ponte del treno fra due mese, con binari e cavalletti. Sulla mesa col segreto, l'ascensore lungo il
    fianco ha in cima un cancello che si apre dalla mesa. La miniera resta la grotta di prima.
  - **Giungla preistorica:** la collina delle ossa con la caverna sotto, aperta ai due lati, con le guardie dentro; due
    alberi giganti uniti da ponti di liane. Il cancello sul secondo ponte si apre dal primo albero, dove c'è il segreto;
    il secondo albero ha l'ascensore.
  - In ogni complesso si sale anche a piedi (rampa o pendio) e il luogo importante ha due strade: quella lunga e la
    scorciatoia, che si apre solo dall'altra parte e si richiude a ogni run.
- **Ascensori e cancelli nelle spedizioni:** si chiamano e si aprono spingendo contro la casella, anche camminando liberi;
  i nemici li usano come nel laboratorio. Il salvataggio tiene i cancelli aperti e dove riposano le piattaforme; mentre
  una piattaforma porta qualcuno non si salva (resta il salvataggio di prima).
- **Disegno:** i ponti e le passerelle hanno un passaggio loro, con il materiale del bioma; sopra gli occhi del robot si
  diradano come la roccia sopra una grotta. Nei condotti vale la vista della grotta (fuori più scuro, la lampada).
- Smoke delle spedizioni: 18 catture nuove dei complessi, dallo stage 104 (`ODIN_PP_SMOKE_ONLY=complessi`).
- Test nuovi: complessi fissi a ogni run, tutto raggiungibile con i cancelli chiusi, salvataggio, ascensore e cancello
  camminando, un minuto di scontro con le guardie libere, un nemico libero che sale in ascensore dietro al robot. I test
  di raggiungibilità dei biomi ora contano anche i piani, i ponti e gli ascensori.

## 2026-10-26 — Profondità, Fase 7 (in corso): ascensori e cancelli nella Prova meccaniche

- **Ascensori da chiamare e aspettare** (scelta dell'utente):
  - un passo verso il pianerottolo vuoto chiama la piattaforma, che arriva a 8 gradini al secondo;
  - un passo sulla piattaforma la fa partire, e chi c'è sopra arriva all'altro capo senza agire né essere colpito;
  - anche i nemici la chiamano, la aspettano e ci salgono.
- **Cancelli delle scorciatoie:** sbarre che si aprono solo con un passo dal lato della leva e restano aperte fino
  alla fine della spedizione.
- Tutto si prova nella nuova arena «Ascensori» (settima di F3) e nell'atto `lift` dello smoke, che gira per ultimo.
  Test nuovi per dati, regole e nemici, e uno che fa vivere l'arena un minuto con i nemici liberi.
- Corretti dopo le prove dell'utente:
  - un crash quando un nemico scendeva dall'ascensore;
  - le piattaforme ferme dopo F7.
- **Il robot si disegna sul suo piano.** Prima veniva disegnato sempre all'altezza del terreno di terra: sotto il
  ponte su cui stava, sopra il massiccio quando era in una grotta, e a terra mentre l'ascensore saliva. Il difetto
  c'era dalla Fase 3.

## 2026-10-26 — Profondità, Fase 6: editor per scolpire

- `--editor-mappe` apre un programma a parte per scolpire a mano le sei arene della Prova meccaniche e le mappe dei
  dodici biomi, piano per piano, con telecamera libera. I pennelli: alza, abbassa, leviga, appiattisci, dipingi
  (pavimento, roccia, vuoto, recinto) e, scelta dell'utente, rampa, copia e incolla, rumore. Si scolpiscono le
  caselle, e gli angoli si ricavano come prima. C'è l'annulla e ripeti per passate intere.
- Pennelli e ritocchi lasciano al codice gli edifici, la partenza, l'uscita e le porte.
- I ritocchi si salvano come PNG in `assets/mappe` (per piano: altezze in grigio, tipi a colori, trasparente dove la
  mappa resta del codice). Il gioco li applica all'avvio alle arene e alle mappe dei biomi, dopo la geografia e prima
  degli abitanti; la mappa resta la stessa a ogni partita. File dipinti a mano che rompono la regola dei piani restano
  fuori.
- Prima di salvare, l'editor controlla:
  - le colonne dei piani e la partenza;
  - nei biomi, anche i luoghi in piano e se dalla partenza si arriva a luoghi, grotte e uscita.

  Gli errori sono segnati in rosso e **G** li mostra uno per uno; con errori la mappa non si salva.
- `--smoke-editor-mappe` scolpisce, salva, riapre e prova i pennelli, le grotte e gli errori, poi usa l'editor con mouse
  e tasti simulati (64 azioni), con 12 catture. La prova ha corretto la scelta della casella sulla roccia e i messaggi
  rimasti dalla mappa di prima.
- Test: 15 nuovi (1707 in tutto). Senza file in `assets/mappe` il gioco non cambia: le catture del laboratorio sono
  identiche al byte a quelle della Fase 5, e mappe e mondi dei biomi sono gli stessi.

## 2026-10-26 — Profondità, Fase 5: grotte senza caricamento

- Le grotte delle spedizioni sono il piano sotto la terra: stanze sotto un massiccio di roccia, a cui si arriva
  camminando dall'imbocco, senza dissolvenza e senza cambiare mappa. Ogni bioma con grotte (Neve, Far West, Egitto,
  Inferno) ha i suoi posti fissi, sempre con massiccio e grotta; la run sceglie quali 1–3 hanno nemici e segreto. Nella
  Neve la grotta della montagna è una stanza nel nucleo, con l'imbocco sul sentiero. Nel Far West, dove la mappa non ha
  spazio, le grotte sono di 24×14 con due stanze (scelta dell'utente durante la fase).
- In grotta: la roccia sopra il robot si dirada con un retino, il fuori si scurisce, la luce del cielo cala e la lampada
  del robot illumina le stanze. Si entra anche in sella; un evento che sveglia nemici fa scendere il robot. Le pattuglie
  entrano, e si combatte anche a cavallo dell'imbocco. L'ologramma segue il piano del robot e segna gli imbocchi trovati.
- Salvataggi: i piani sono salvati come lista di caselle; quelli di prima della fase sono rifiutati senza danni.
- Via `Outer_Map`, `enter_cave`, `exit_cave`, la dissolvenza e il bioma 255.

## 2026-10-25 — Profondità, Fase 4: piani nel laboratorio, grafica

- I piani si leggono a schermo, con funzioni pure come quelle degli edifici (`game/layer_view.odin`). Ciò
  che sta sopra la testa del robot si apre a poco a poco entro 6 caselle. In grotta il fuori si scurisce e
  la luce del cielo cala; resta la lanterna, che illumina solo il suo piano. Sul ponte ciò che sta sotto si
  scurisce un poco (scelta dell'utente).
- Chi è coperto si vede con il contorno del suo colore (`render/layer_outline.odin`). Il mouse attraversa
  ciò che è diradato e da sotto il ponte punta la strada. La telecamera segue morbida il cambio di piano.
- Atto dello smoke `layers` con tre catture nuove: nemico sotto il ponte visto dal ponte, mouse su una
  casella sotto il ponte, nemico sul ponte sopra il robot. Senza piani nulla cambia: un tabellone con i
  piani usa una variante dello shader della resina, e le altre catture restano identiche al byte.
  Prestazioni: −0,0% di media rispetto alla Fase 3. Test: 4 nuovi (1688 in tutto).

## 2026-10-25 — Profondità, Fase 3: piani nel laboratorio, dati e regole

- La mappa può avere caselle sopra la terra (un ponte, piano +1) e sotto (grotte, −1 e −2): `level.Level`
  ha i suoi piani, vuoti finché non servono, e le scale a pioli. Due pavimenti della stessa colonna distano
  almeno 12 gradini (10 di luce e 2 di spessore, come ha scelto l'utente); una mappa che non lo rispetta è
  rifiutata.
- Le regole passano da un piano all'altro: passo (rampe e imbocchi), scale (solo scale, niente ascensori),
  spinte e cadute oltre il bordo aperto di un ponte, vista e tiri nelle due direzioni, aree che seguono un
  imbocco e si fermano a ponti e volte, mischia fra piani solo agli imbocchi, campo delle distanze dei
  nemici. Le carte speciali agiscono sul piano di chi le gioca come prima e sugli altri piani solo su ciò che
  vede. Senza piani tutto è come prima.
- Nella Prova meccaniche la sesta arena di F3, «Piani»: strada sotto un ponte con due rampe, collina con
  una grotta e due imbocchi, scala sul dirupo, un nemico per piano. Disegno semplice: ciò che copre il robot
  quando è sotto diventa mezzo trasparente. Atto dello smoke `layers` (`ODIN_PP_LAB_ONLY=layers`), sette
  catture. Prestazioni: +0,3% di media rispetto alla Fase 2, il gruppo peggiore +2,4% (gli ologrammi):
  rumore. Test: 19 nuovi (1684 in tutto).

## 2026-10-25 — Profondità, Fase 2: posizioni con il piano

- `grid.Position` ha un terzo campo, `layer`: −2 sotto profondo, −1 sotto, 0 terra, +1 sopra (quattro
  piani, come ha scelto l'utente). Tutto resta sulla terra, quindi il gioco non cambia. Una `Grid` rifiuta
  le posizioni di altri piani; `grid.offset` dà la vicina conservando il piano; `grid.cell_index` vale per
  le tabelle parallele.
- 3215 posizioni riscritte con l'aiuto del compilatore: 2909 con i nomi, 300 vicine con `grid.offset`.
- Una posizione pesa 24 byte invece di 16: i limiti del test sul budget dello stack crescono (`Room` 9 KB,
  registri degli eventi 104 KB), le `Renderer` dei test passano sullo heap, i salvataggi crescono del 21%
  (+50 ms, in background). Test: 3 nuovi (1665 in tutto).

## 2026-10-25 — Profondità, Fase 1: terreno scolpito

- Le altezze si disegnano come una **superficie scolpita** ([surface.odin](src/level/surface.odin),
  funzione pura): il centro di ogni casella alla sua quota, ogni angolo la media delle vicine a un gradino
  al massimo. Le scale diventano rampe e le colline a gradoni colline; i dirupi tengono lo spigolo, con
  pareti di roccia sfaccettate e un bordo al neon tenue del colore del bioma. Luce morbida sulle salite;
  via le righe dei gradini.
- Spedizioni: il rilievo in blocchi 8×8 è riscritto sulla superficie. Laboratorio: le caselle in pendenza
  sono piastrelle inclinate. Personaggi, piedistalli, ombre e puntatore stanno sulla superficie; anteprime
  e segni sulla cima della casella. Le regole non cambiano.
- Gli smoke non si fermano più quando la loro finestra è ridotta a icona (`keep_running` del host).
- Prestazioni: +2,4% di media rispetto alla Fase 0, il gruppo peggiore +4,3%. Test: 7 nuovi (1662 in
  tutto).

## 2026-10-25 — Profondità, Fase 0: misure di partenza

- Il benchmark delle spedizioni misura tutto il percorso dello smoke (stage
  0–102, prima al massimo 0–50), oppure un intervallo scelto in compilazione
  con `EXPEDITION_BENCHMARK_FIRST` e `EXPEDITION_BENCHMARK_LAST`. Ogni scena si
  disegna su un canvas fisso di 1920×1080 pixel (`fixed_canvas_size` della
  finestra), così le misure non dipendono dallo schermo.
- Sui portatili con due schede video il gioco chiede la scheda dedicata
  ([windows_gpu.odin](src/windows_gpu.odin)). Sul PC di sviluppo disegnava con
  la Intel UHD accanto a una RTX 3060; con la RTX gli stessi stage sono circa
  quattro volte più rapidi.
- Misure di partenza (due giri concordi, quasi tutte le scene intorno a 1 ms)
  nell'esito della Fase 0 e nell'appendice A di
  [piano-profondita.md](docs/piano-profondita.md). Test: 1 nuovo (1655 in tutto).
- Lo smoke del laboratorio non è arrivato in fondo: si ferma quando la sua
  finestra è ridotta a icona. La correzione apre la Fase 1.

## 2026-10-25 — Piano di lavoro della profondità

- Nuovo [documento](docs/piano-profondita.md) in nove fasi (0–8), da eseguire
  una alla volta solo su comando dell'utente: terreno scolpito (rampe, colline,
  dirupi di roccia), posizioni con il piano, mappa a piani (sotto, terra,
  sopra) nel laboratorio, grotte senza caricamento nelle spedizioni, editor per
  scolpire, ponti, gallerie e scorciatoie nei biomi, ologramma a piani. Il
  combattimento resta a griglia su ogni piano.
- La Fase 0 è una proposta di Claude: oggi il benchmark non arriva agli stage
  di rilievi, montagna e grotte.

## 2026-10-25 — Test: tutti i biomi sbloccati (temporaneo)

- Nella galassia del Portale, il pulsante **TEST tutti i biomi** (SI/NO) apre tutte e 12 le isole per giocarle, in ogni
  slot; si cambia solo tra una spedizione e l'altra e lo slot se lo ricorda.
- Il progresso vero non cambia: i biomi sbloccati restano quelli guadagnati e, spento il test, la galassia torna com'era.
  Una spedizione in un bioma aperto solo dal test ("Solo prova: non conta") non tocca biomi vinti, serie, sblocchi,
  morti e finali; lo zaino segue le regole normali (torna a casa se vinci, si perde se muori) e le stelle danno il loro
  premio. I biomi già sbloccati davvero contano come sempre anche a test acceso.
- Per toglierlo: cercare `test_all_biomes` e `Run_Progress.test` (commento in `src/campaign/campaign.odin`); prima,
  finire le spedizioni di prova in corso, altrimenti quello slot non si carica più. Test: 3 nuovi.

## 2026-10-25 — Revisione delle carte

- **Ritirate** (il codice resta, ma niente le dà più): Thorn Coat, Afterimage, Counter Rune, Battle Focus, Spark Forge,
  Spark, Volatile Study, Titan Grip.
- **Diventate potenziamenti** (al secondo potenziamento della carta base, poi ripartono dal livello 0): Guard → Purifying
  Guard, Strike → Cross Slash, Arc Bolt → Chain Lightning, Fate Strike → Prismatic Barrage, Venom Needle → Twin Venom.
- Mazzo iniziale da 8 carte; il primo ring dà Grappling Hook; archivi dei biomi aggiornati. Tutto, con l'effetto di ogni
  carta e il modo di rimetterla, in [docs/registro-carte.md](docs/registro-carte.md).

## 2026-10-24 — Posare le strutture

- **Fase 7 del piano fatta, ultima del piano.** Un kit nello zaino (si trova nelle cache e si compra nelle officine per 25 crediti)
  permette di posare una struttura sulla mappa: **POSA** dallo zaino, l'impronta segue il mouse (verde dove ci sta, rossa dove no,
  con il motivo), la rotella la gira, R la specchia, clic posa, tasto destro annulla. Tre per spedizione, non si smontano.
- Gli oggetti e i recinti posati hanno salute e i colpi dei nemici li rompono (carro 6, fontana 8, statua 10, macchina 8, rovina 8,
  recinto 6); gli edifici no. Le strutture rotte non tornano al salvataggio. Test: 6 nuovi (1649 in tutto).

## 2026-10-24 — Le caverne

- **Fase 5 del piano fatta.** Nella Neve, nel Far West, nell'Egitto e nell'Inferno ci sono da una a tre grotte per mappa, ognuna
  un arco-segreto (nascosto sull'ologramma finché non lo si scopre; nella Neve, il primo sul sentiero della montagna, a
  metà salita). Con E all'arco, dissolvenza al nero ed entri in una mappa a parte: due o tre stanze in fila con dei
  nemici e in fondo, in una nicchia, crediti e una reliquia; con E vicino all'arrivo esci, allo stesso arco.
- Tecnicamente l'interno sta sulla stessa griglia (la mappa aperta viene messa da parte e poi riportata identica); un
  salvataggio preso in grotta si riapre in grotta. Nuova arena «Grotta» nel laboratorio (F3). Test: 11 nuovi (1643
  in tutto).

## 2026-10-24 — La montagna a spirale

- **Fase 4 del piano fatta.** Le nuove Montagne innevate hanno una montagna tonda con un sentiero largo due
  caselle che la avvolge per tre giri, un gradino a ogni passo fino alla cima (94 gradini); tra i giri c'è un
  dirupo, quindi non si taglia. Sul sentiero: una pattuglia a metà salita e due tratti di ghiaccio; in cima, una
  reliquia da raccogliere a mano. Il bordo esterno è libero.
- Il pavimento rialzato si apre in una finestra tonda con un sottile bordo luminoso davanti al robot, quindi il robot
  si vede anche dietro la montagna; i nemici dietro la montagna restano nascosti. Corretto un difetto della Fase 3:
  il robot che cammina libero (e ogni figura) non veniva alzato alla quota del terreno (un `defer` su un risultato
  con nome non ha effetto in Odin); l'ologramma raggruppa le altezze oltre 12 a bande; nuova arena «Montagna» nel laboratorio (F3) e atto
  di smoke. Test: 14 nuovi (1632 in tutto).

## 2026-10-24 — Rilievi nelle spedizioni

- **Fase 3 del piano fatta.** Tutti i dodici biomi hanno un rilievo a tema: piattaforme, mesa, colline,
  piazze, dune, terrazze, altopiani con scala, cenge, tumuli, isole a quote diverse, crateri, la grande
  collina del masso. Funzione pura del bioma, quindi la stessa geografia a ogni run; servizi, partenza e
  pattuglie restano su terreno piano.
- In esplorazione il robot (a piedi e in sella), i gruppi che dormono, le pattuglie e l'avvistamento
  seguono le regole di passo e di vista dei dislivelli; il pavimento ha terrazze, più chiare con la quota e
  con una riga a ogni gradino; l'ologramma ha ombreggiatura e curve di livello. Gli slot vecchi si caricano
  piatti. Test: 9 nuovi (1618 in tutto).

## 2026-10-24 — Strutture su più caselle

- **Fase 6 del piano fatta.** Edifici (casetta, capanna, tempietto) e oggetti complessi (carro, fontana,
  statua, macchinario, rovina, recinto) che occupano tutte le caselle della loro impronta, da piante a
  caratteri con rotazione e specchio, posati con controlli (fuori mappa, sovrapposizione, porta bloccata,
  sacche). Nuovo tipo di casella, il muretto, che ferma il passo ma non la vista.
- Gli edifici diventano trasparenti avvicinandosi (intero da 5 caselle, sparito a una casella da una porta,
  minimo del 25% accanto a un muro cieco); dentro i muri tornano pieni, il tetto si nasconde e il fuori si
  scurisce; resta il contorno a terra. Solo grafica: i muri fermano sempre passo e vista.
- Laboratorio: terza arena (F3) con tutto il catalogo. Spedizioni: Robotica cibernetica ha 14 strutture
  fisse, salvate con il mondo. Test: 21 nuovi (1609 in tutto).

## 2026-10-23 — Hub in 3D: dentro la sala giochi

- **Fase 11 del piano fatta: l'hub 3D è completo.** Entrando nella Sala giochi dalla piazza
  si passa, con la dissolvenza, a dodici posti a semicerchio: i cabinati dei biomi vinti
  sono accesi, con nome, stelle e record, e si gioca entrandoci; gli altri sono coperti da
  un telo e non dicono a quale bioma appartengono. Dopo una partita il robot è davanti al
  cabinato e il record è aggiornato. La vecchia pagina «Cabinati» è sostituita dalla sala.
- Sala in `hubworld/arcade.odin` e `render/hub_arcade.odin`, collegamento in
  `application/hub_arcade_room.odin`. Test: 8 nuovi (1588 in tutto).

## 2026-10-23 — Hub in 3D: dentro il deposito

- **Fase 10 del piano fatta.** Entrando nel Deposito dalla piazza si passa, con la
  dissolvenza, alla sua sala: lo zaino su un tappetino, un manichino su una pedana che
  indossa arma e reliquie vere, un terminale con lo scaffale delle carte scoperte che si
  accendono, casse che crescono con gli oggetti conservati e la porta «Piazza». Zaino,
  manichino e archivio aprono i pannelli di prima e al ritorno il robot è davanti a loro.
- Le sale di casinò e deposito condividono ora codice (`Hub_Room`, `hub_rooms.odin`,
  `render/hub_room`-helper). Test: 9 nuovi (1580 in tutto).

## 2026-10-23 — Hub in 3D: dentro il casinò

- **Fase 9 del piano fatta.** Entrando nel Casinò dalla piazza si passa, con una
  dissolvenza, alla sala: 6 Ranch 7, Tre in fuga, roulette europea e Duello del d20 sono
  strutture a cui il robot cammina; entrandoci si apre il gioco di prima, con lo stesso
  portafoglio, e alla fine si è davanti alla struttura. La porta «Piazza» riporta davanti
  al Casinò. Un'insegna mostra i crediti del deposito; suoni d'ambiente leggeri.
- Stanze e dissolvenza in `hubworld/zone.odin` (riusabili dal deposito e dalla sala
  giochi), disegno in `render/hub_casino.odin`. Test: 9 nuovi (1571 in tutto).

## 2026-10-23 — Hub in 3D: la piazza

- **Fase 8 del piano fatta.** L'hub è una piazza rotonda con sette edifici (Portale dei
  ricordi, Deposito, Progressi, Uscita, Frammenti del creatore, Sala giochi, Casinò): il
  robot di carta cammina con WASD o frecce, o con un clic su un edificio, e ogni porta
  apre la pagina di prima. Gli edifici sbiadiscono avvicinandosi e si vede l'interno.
  Dopo una spedizione il robot riappare davanti al Portale, dopo una pagina davanti
  al suo edificio; «Torna in piazza» sostituisce la barra dei pulsanti.
- Regole nel nuovo pacchetto `hubworld` (testate senza finestra), disegno in
  `render/hub_world.odin`; smoke `--smoke-hub-world`. Test: 11 nuovi (1562 in tutto).

## 2026-10-23 — Piano di lavoro della griglia

- Nuovo [piano](docs/piano-griglia.md) in undici fasi, da eseguire una alla
  volta solo su comando dell'utente: bersagli in evidenza mentre si sceglie una
  carta, altezze nel laboratorio e nelle spedizioni, montagna a spirale delle
  Montagne innevate, caverne, strutture su più caselle e, se confermata, la
  loro posa da parte del giocatore.
- Fasi 8–11: l'hub diventa un mondo 3D in cui il robot cammina (piazza,
  casinò, deposito, sala giochi), dai disegni dell'utente in
  `docs/immagini/`.
- **Fase 2 del piano fatta: altezze nel laboratorio.** Ogni cella può avere un'altezza in
  gradini (0 ovunque = il gioco di prima).
  - Regole: il passo fra celle vicine è al massimo di 1 gradino, di più è un dirupo (un muro
    per chi cammina); le spinte non salgono un dirupo ma lo scendono, cadendo (danno =
    dislivello − 1, al massimo 10); i nemici non camminano sui dirupi; linea di tiro e di vista
    seguono il terreno; +1 gittata dalle carte a distanza da 4 o più gradini in alto; il First
    Person Shooter segue le altezze.
  - Grafica del laboratorio: pavimento rialzato con le linee dei gradini, personaggi, ombre,
    anteprime, segni dei bersagli e intenti alla quota giusta, telecamera che segue il giocatore,
    puntatore che sceglie la cima o la faccia giusta.
  - Seconda arena della Prova meccaniche (F3): altopiano con scala, pilastro e collina a
    spirale. Le spedizioni restano piatte (Fase 3).
  - Test: 13 nuovi (1551 in tutto); atto `mechanics_lab_heights` dello smoke (`ODIN_PP_LAB_ONLY=heights`).
- **Fase 1 del piano fatta: bersagli in evidenza.** Mentre si sceglie una carta,
  ogni nemico che una giocata valida colpirebbe davvero ha la casella accesa (nucleo
  quasi bianco che pulsa, contorno d'inchiostro, angoli, alone viola elettrico, verde
  acido nello Spazio), un fascio di luce con scintille che sale dalla sua casella e,
  col puntatore sulla casella giusta, angoli che si chiudono e un anello che si apre.
  - Il calcolo è `game.card_hit_enemies`, sul piano degli effetti della giocata: lo
    Scatto non segna chi sta sulla sua linea; l'Inondazione segna tutti.
  - Con una carta solo sotto il mouse nella mano, raggio e bersagli compaiono più tenui.
  - Lazzo, Pinball, Cannone e Inondazione usano questo segno al posto dei loro mirini
    sui nemici.
  - Test: 9 nuovi (1538 in tutto). Catture: `odin_pp_mechanics_lab_hit_*.png` e
    `odin_pp_expedition_bersagli_*.png` (Neve, Far West, Giungla, Spazio).
- **Fase 0 del piano fatta: test affidabili su Windows.** `check.ps1` completo
  finisce con 1529 test verdi due volte (con e senza assert) e le due build.
  - 14 percorsi `/private/tmp` in 6 test (di 0xdokkan) ora usano la cartella
    temporanea del sistema.
  - Nuovo pacchetto `src/engine/teststack`: dà 32 MiB di stack agli
    eseguibili di test su Windows, perché `core:encoding/json` usa circa 6 MB
    di stack per decodificare lo snapshot della spedizione (1,3 MB). Era la
    causa del crash a metà della suite e dei pacchetti che si bloccavano da
    soli. Il gioco non ne era toccato.
  - Tolleranza dell'andata e ritorno schermo→mondo della camera da 0,001 a
    0,005 caselle (rumore dei numeri a 32 bit), e conteggio delle carte
    offribili di `test_m8_locked_cards_never_leak_into_reward_pool`.
- Scaletta per priorità, all'inizio del piano. La tabella delle fasi segue
  questo ordine: Fase 0 (proposta: test affidabili su Windows), bersagli,
  hub, altezze nel laboratorio, strutture, altezze nelle spedizioni,
  montagna, caverne, posa da parte del giocatore.
- Fase 6 precisata: oggetti complessi ed edifici occupano tutte le caselle
  della loro impronta. Gli edifici diventano trasparenti man mano che il robot
  si avvicina, spariscono sulla soglia e, quando il robot è dentro, tornano
  con i muri normali che isolano la vista. La regola vale anche per la piazza
  dell'hub, se l'utente lo conferma alla Fase 8.
- Quattro immagini di riferimento in 3D dell'hub, `docs/immagini/hub-3d-*.png`:
  render di concetto fatti da Claude con Blender dai disegni dell'utente, nello
  stile delle spedizioni, con il robot del gioco e il font Jersey 10.
- Per ogni fase: come funziona oggi il codice, il progetto, le domande da fare
  prima di iniziare, i passi, i test e il comando da dare a Claude. La sezione
  1 contiene le regole per Claude, compreso lo stop a fine fase.

## 2026-10-23 — Le carte del laboratorio tornano, solo in Prova meccaniche

- Bomb Marley, Inondazione, Cannone, Cannone Laser, Buco Nero, Dinosauro e il
  Sanguinamento (le voci del 21 ottobre qui sotto) tornano sopra la campagna dei
  dodici biomi, **solo nella Prova meccaniche** per ora: non si offrono, non si
  comprano, non si scoprono nell'archivio e non entrano nel pool di una
  spedizione (tratto `Lab_Only`, `game.card_is_lab_only`).
- Le carte con gli stessi nomi della campagna (gli ordigni di Cannone,
  Inondazione, Buco Nero, Bomb Marley e lo scudo del Dinosauro) restano com'erano.
  Le nostre hanno nomi interni propri: `Marley_Party`, `Flood_Wave`,
  `Field_Cannon`, `Laser_Cannon`, `Devouring_Hole`, `Dino_Ride`; gli oggetti posati
  `Field_Cannon` e `Devouring_Hole`.
- Il mondo neon non torna: la grafica resta quella di main.
- Il passo calcolato da main (`expedition_step_seconds`) parte da quello del
  giocatore, così il Velociraptor cavalcato fa di nuovo passi da 0,4 s.

## 2026-10-21 — Cannone, Buco Nero, Dinosauro e Sanguinamento

- **Cannone** (non comune, energia 2, 2 s, fino a +2): una torretta su una casella
  libera, girata con la rotella, spara ogni secondo del mondo per 20 s una palla
  da 2 danni (+1) al primo nemico della linea e poi si sbriciola. Al secondo
  upgrade **diventa Cannone Laser** (rara, mai offerta): un raggio da 3 danni
  (+1, fino a 3 upgrade) a tutti i nemici della linea. Massimo due cannoni.
- **Buco Nero** (rara, energia 3, 2 s, fino a +4): un buco per 8 s del mondo; il
  3x3 prende 4 danni a battito (+1 per upgrade; l'area cresce con gli upgrade),
  il 5x5 intorno viene tirato di una casella verso il centro, boss e miniboss
  esclusi; chi muore viene inghiottito con una spirale.
- **Dinosauro** (rara, energia 3, 2 s, fino a +5): un d4 sceglie per 20 s (+3 per
  upgrade) Velociraptor (passi da 0,4 s, urto che sanguina), Stegosauro (ogni
  colpo ricevuto torna indietro senza cariche), Dilophosaurus (1 Veleno a chi
  ferisce o è ferito) o Giganotosauro (passi che schiacciano le 4 caselle intorno
  per 6, urto che uccide Chaser, Archer e Bomber all'istante).
- Dinosauro, ritocco: il dinosauro si gira come la carta del Viandante (prima poteva
  tornare indietro dopo il passo); mentre si cavalca i passi e i colpi li fa il
  dinosauro (scatto in avanti a testa bassa), non il disegno del Viandante; il
  **Giganotosauro**, se il suo urto ucciderebbe il nemico, ne prende la casella e
  lo schiaccia invece di colpirlo; se sopravvive lo morde.
- **Sanguinamento**: nuovo status dei nemici, +N danni da ogni fonte, una volta,
  gli stack non calano.
- Catalogo a 50 carte (il Cannone Laser non si offre). Icone, 25 suoni
  originali, pixel art dei quattro dinosauri, testi, chip `RAPTOR 14s`, film di
  Mostra effetto a ogni livello e atti della Prova meccaniche.
- Il mazzo della Prova meccaniche cambia: Pozza di Veleno, Deflect e Feretro
  lasciano il posto a Cannone, Buco Nero e Dinosauro (restano nel gioco; lo smoke
  li riprende per i loro atti).
- Regole in `game/emplacement.odin`, `cannon.odin`, `black_hole.odin`,
  `dinosaur.odin`; disegno in `render/arsenal.odin` e `render/dino_art.odin`.

## 2026-10-21 — Bomb Marley e Inondazione

- **Inondazione** (non comune, energia 2, 2 s, fino a +3): un'onda attraversa
  tutta la mappa dal muro dietro la direzione scelta al muro davanti, spegne
  tutti i fuochi e spinge ogni nemico di una casella (+1 per upgrade, +1 sul
  colpo a tempo) con le normali regole di spinta; nessun danno. Regole in
  `game/flood.odin`, onda e vapore in `render/flood.odin`.
- **Bomb Marley** (rara, energia 3, 2 s, fino a +5): una festa di 35 s del
  mondo (+5 s per nemico ucciso da una bomba, 90 in tutto) a battiti di un
  secondo. Una sfera da discoteca illumina caselle che salvano; bombe da 6
  danni (+1 per upgrade) attraversano colonne intere, annunciate due battiti
  prima, e non toccano chi sta su una luce. Poche bombe all'inizio, poi sempre
  di più; le luci calano con il tempo. Bomb Marley non è un'entità della stanza:
  nessuno lo tocca né lo vede come bersaglio. I nemici evitano le colonne
  annunciate e cercano le luci vicine. Regole in `game/marley.odin`, tavolo in
  `render/marley.odin`.
- Catalogo a 46 carte. Icone, suoni (compreso un groove reggae a 60 BPM),
  testi, chip dell'HUD, film di Mostra effetto (quello di Bomb Marley finisce
  alla prima bomba, non dopo l'intera festa) e atti della Prova meccaniche.
- Bomb Marley, ritocco: bombe di cartoncino che vengono lanciate dalla figura e
  rimbalzano lungo la colonna (un salto ogni 3 caselle) senza cambiare il danno,
  che colpisce chiunque sia nella colonna; luci molto più numerose (4 più dei
  personaggi, una in meno ogni 5 s) e sparse; le caselle del turno dopo si vedono
  in anteprima per tutto il tempo.
- Inondazione, ritocco: con la carta in mano la rotella del mouse gira la
  direzione dell'onda di un quarto di giro a scatto (la camera non zooma) e la
  mappa mostra una freccia grande dal muro di partenza a quello di arrivo, con
  barre `PARTE` e `FINE` e frecce più sottili sulle altre corsie.
- Il mazzo della Prova meccaniche resta di dieci carte più la Canna: Movimento
  Ombra e Lama Velenosa lasciano il posto alle due nuove (restano nel gioco).

## 2026-10-20 — Verifica prima della pubblicazione

- Ripristinato `scripts/check.sh --quick`: il registro delle combinazioni
  delle stanze viene dichiarato solo nel profilo completo, che lo usa.
  Nessuna modifica agli scenari o agli assert dei test.

## 2026-10-20 — Targhette della vita ancorate ai nemici

- Rimosso il riposizionamento automatico per evitare player, status e altre
  etichette: ogni targhetta resta centrata sopra la testa del proprio nemico
  e segue la sua carta. Nessuno spostamento forzato ai bordi del viewport.
- Larghezza della vita corrente riservata in base al massimo, senza scatti
  di targhetta e intento quando il danno cambia il numero di cifre.
- Bombe e micce cercano spazio dopo la prenotazione dei cuori fissi; dadi e
  avvisi Pinball mantengono la loro gestione delle sovrapposizioni.
- Sostituiti i test del vecchio layout mobile con regressioni sull’ancoraggio
  fra ostacoli grafici variabili, movimento del proprietario e danno/cura.

## 2026-10-20 — Illuminazione della portata delle carte

- Portata integrata nel materiale del pavimento 3D, bordo blu continuo,
  alone sfumato e pulsazione lenta. Area d’impatto ambra, bersaglio e
  destinazione menta; blocchi e giocate impossibili rossi.
- Minacce e sprite restano sopra la luce; profondità, fog e guide delle
  meccaniche conservano la propria funzione. Energia insufficiente attenua
  la portata. Nessuna traccia della selezione dopo cambio carta o fine fight.
- Maschera locale condivisa fra materiale e feedback, ricostruita una volta
  per frame entro il range della carta; eliminata la scansione dell’intera
  stanza. Due regressioni coprono il catalogo e i reset di visibilità/input.

## 2026-10-20 — Ritmo del combattimento e intenti compatti

- Nuove azioni nemiche ogni 3/4/5 secondi secondo l'archetipo (prima 2/3/4).
  Recupero e rilascio di attacchi già preparati mantengono il proprio ritmo;
  clock, QTE e cast restano indipendenti.
- Passi ordinari e diagonali sul battito da 1 a 0,8 secondi. Gli attacchi base
  e le carte conservano i costi precedenti.
- Intento in pixel 7×7 dentro il cartellino della vita, con sagoma distinta per
  ogni azione. Rimossi sigilli, adesivi separati e memoria del vecchio intento.
  Le minacce sul pavimento restano; nel laboratorio F6 confronta HUD con o
  senza terreno. Il layout riserva un solo rettangolo per vita e simbolo.

## 2026-10-16 — Lazzo: spinta interna fino al perimetro

- I nemici toccati dalla corda dentro il raggio vengono spinti fino alla prima
  casella dell'anello, indipendentemente dalla forza del contatto, senza
  oltrepassarla. Muri, ostacoli e altri corpi continuano a fermare la spinta;
  gli effetti del terreno si applicano lungo tutto il percorso.
- Il trascinamento interno resta privo di danno diretto e avviene una volta
  per giro. Dal giro successivo il bersaglio sul bordo può essere colpito dal
  nemico roteato, secondo le regole delle collisioni sul perimetro.

## 2026-10-16 — Lazzo senza limite di peso e AK dal riferimento

- Dentro il raggio la corda respinge senza infliggere danni diretti, neppure
  al nemico roteato. Restano le collisioni sul perimetro, gli effetti del
  terreno attraversato e il punto vita perso a ogni giro.
- Boss e miniboss sono bersagli validi del Lazzo. Mirini, ispettore e Prova
  meccaniche seguono la stessa regola; il limite di peso del Pinball resta.
- AK della carta FPS ricavata dall'immagine fornita, senza mani o braccia:
  PNG trasparente incorporato, sagoma e dettagli del riferimento, posizione
  della bocca condivisa con fiammata e traccianti.

## 2026-10-16 — Lazzo, risultati dei dadi e arma FPS

- La corda del Lazzo colpisce e respinge anche i nemici interni al raggio,
  al passaggio della rotazione, una volta per giro. Mantiene danni progressivi,
  ostacoli, effetti del terreno e contatti sul perimetro.
- Il pannello dei dadi distingue il tiro dall'effetto applicato, inclusi i
  critici e gli assorbimenti. Legge gli eventi della stessa giocata nella run,
  nei film e nei laboratori; formule e RNG restano invariati.
- La carta FPS mostra un AK imbracciato in prospettiva, con maniche e guanti del
  Viandante, acciaio blu e bordo di carta. La stampa è incorporata e riproducibile;
  rinculo, fiammata e traccianti condividono l'ancoraggio alla bocca dell'arma.

## 2026-10-16 — Sei interventi sull'architettura

Lotto successivo al ritiro della modalità classica e della vista piatta.
Il confronto parte dalla copia del working tree all'inizio del lotto, non da
HEAD: il lavoro precedente, inclusi gli atlanti PNG, è preservato.

1. **Carte:** catalogo enumerato, tratti/costi/dadi/upgrade nella definizione;
   tabella visuale privata per icone, palette, nomi e suoni. I parametri numerici
   delle descrizioni provengono dal gameplay. Le meccaniche speciali mantengono
   algoritmi dedicati.
2. **Input e schermate:** snapshot dei dispositivi una volta per frame,
   `Run_Action` rimappabili, stato posseduto dalla sessione, eventi di pressione
   anche per assi e rotella. Una sola schermata derivata dalla fase della run;
   aggiornamento suddiviso per controlli, attività, vista, comandi e overlay.
3. **Eventi e memoria:** `Room` possiede il log sull'heap con allocatore e durata
   espliciti; reset del prefisso valido, snapshot indipendenti e copie dei report
   ridotte nella risoluzione interna. Nessun buffer globale condiviso.
4. **Policy delle meccaniche:** capacità e clock comuni; cleanup coerente.
   Preservate le combinazioni di Pinball, Shadow, FPS, terreno e dispositivi.
5. **Package:** `application` compone `run`, `activities` e `devtools`.
   Il gioco usa callback opzionali per la diagnostica e non importa i tool;
   Mostra effetto e pratica rimangono funzioni del prodotto. Test trasversali
   nel package di integrazione, raggiungibile dal solo entry point dei test.
6. **Confini e repository:** helper privati, `app/view/grid` dentro l'engine,
   vettori float nativi, documentazione divisa per argomento, `.editorconfig`,
   build e catture sotto `build/`; binario `game` fuori dall'indice Git.

| Metrica sul working tree | Inizio lotto | Fine lotto |
|---|---:|---:|
| `size_of(Room)` su macOS ARM64 | 103.448 B | 6.944 B |
| Righe di produzione in `main` | 12.202 | 24 |
| Righe di `roguelike_update` | 423 | 33 |
| Procedure pubbliche di `game` | 734 | 338 |
| Procedure pubbliche di `render` | 1.028 | 186 |
| Righe del README | 5.027 | 95 |
| Righe fisiche Odin di produzione | 83.966 | 85.521 |

Il totale fisico cresce di 1.555 righe: 1.249 sono nuove annotazioni di privacy;
il resto include soprattutto il confine di input, le policy e la composizione.
L'estrazione dei package sposta codice, non ne elimina le funzioni. Il log da
96.528 byte esiste ancora sull'heap; i report pubblici conservano il proprio
contratto per valore. Questi numeri misurano dimensioni e responsabilità, non
una riduzione equivalente della memoria totale o del binario.

Verifica locale con `dev-2026-10:84bc3fc21`:

- `scripts/check.sh` completo: 1.294 test con assert e 1.294 senza, tutti verdi,
  controllo della memoria attivo, controllo statico e due build native.
- Engine/host controllato autonomamente; nessun import verso i package del
  gioco e nessuna interrogazione Raylib di tasti/mouse fuori dal campionamento.
- Oracoli: 2.425 righe di catalogo/visuali/offerte RNG identiche, 286.725
  confronti delle guardie, 60.000 confronti esatti dei bit dei vettori.
- Report di stress tattico e telemetria headless identici byte per byte.
- Finestra nativa: sei minigiochi, combattimento/QTE/ologramma, dispositivi,
  loot, stanza successiva, dadi e Mostra effetto; tutti gli scenari eseguiti
  terminano con successo. 114 catture deterministiche identiche; altre sei,
  una per minigioco, identiche usando un passo di 1/60 nelle sole copie di
  confronto. Il gioco conserva il tempo reale dei frame.
- Film selezionati Strike/Guard/Tesla base e massimo: 2.248 frame, media
  9,21 ms, p95 11,16 ms, p99 11,92 ms, nessun frame oltre 16,7 ms. Verdi anche
  i controlli a 60 fps su Pinball, Wildfire e First Person. Misura locale,
  non benchmark dell'intero catalogo né promessa su altri dispositivi.
- Link locali della documentazione e `git diff --check` validi.

Screenshot: [combattimento](build/captures/refactor/combattimento.png),
[loot](build/captures/refactor/loot.png),
[stanza successiva](build/captures/refactor/stanza-successiva.png).
I log e le metriche locali sono in `build/validation/`, ignorata da Git.

Windows non è stato eseguito localmente: la riserva dello stack resta finché
una misura nativa dell'intero percorso ne dimostra la rimozione sicura.
Non sono stati introdotti un ECS, una union esclusiva per tutte le meccaniche,
una localizzazione globale o un nuovo formato dei salvataggi. Non viene
promesso un limite di file per una carta nuova: dipende dalla sua meccanica.


Una milestone è completa quando è integrata nella demo, coperta da test delle
invarianti e descritta dalla documentazione. Stati: `[x]` completata,
`[~]` in corso, `[ ]` pianificata.

| Milestone | Stato | Risultato / lavoro restante |
|---|---|---|
| Baseline | [x] | loop della run, griglia, azioni, deck, intenti, timeline e input |
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
| M6 + M6A | [~] | M6A completata: sprite, GIF, sheet e clip; M8 salva gli sblocchi, M9 registra input in memoria; restano salvataggio run, replay su disco e ulteriori feedback |
| M7 | [~] | prototipo M7A–M7F integrato; M7G attende playtest umano e bilanciamento |
| M7A | [x] | timer decrescente e cicli di recupero locali alla stanza; statistiche cumulative della run |
| M7B | [x] | visibilità locale 7×7 predefinita, confronto 2/3/5/7/9 senza memoria, ologramma 3D ruotabile e con countdown attivo |
| M7C | [x] | più azioni per finestra con costi in tempo; recupero mobile fisso al posto della preparazione anticipata |
| M7D | [x] | QTE da tastiera difficile per un passo diagonale, con esito e costo espliciti |
| M7E | [x] | difese abilitate da carte/condizioni, in alcuni casi con QTE da tastiera |
| M7F | [x] | ambiente 3D illuminato con sprite 2D, camera prospettica orbitabile e parallasse |
| M7G | [~] | stress e run terminali deterministiche, telemetria e smoke grafico completati; bilanciamento manuale da fare |
| M7H | [x] | revisione leggibilità: mano completa senza sovrapposizioni, dettagli carta, selezione con clic e mappa con pulsante dedicato |
| M7I | [x] | veste dark fantasy pixel: font incorporato, carte e sprite illustrati, pietra e archi gotici, HUD avorio/cremisi e ologramma rosso con legenda |
| M7J | [x] | art delle carte più pixelata, ambiente e fog a blocchi 3D, nemici adattati alle nuove interazioni e menu unificati; bilanciamento umano in M7G |
| M7K | [x] | blocchi grigio-blu lucidi senza fondali, vista ampliata, stanze più grandi e due nemici aggiuntivi, schivata senza carte con recupero e dadi 3D coordinati |
| M7L | [x] | catalogo tattico, interruzione/ricognizione/contrattacco, ruoli nemici e recuperi leggibili, pannello nemico e starter aggiornato; bilanciamento umano in M7G |
| M8 / 0.4 | [x] | cast e cinematiche separati, Shock Floor/Tesla, arma a utilizzi, scheda 3D, ring giocabile con sblocchi persistenti e contorni da illustrazione |
| M9A — arena libera | [x] | clock 60 Hz, movimento continuo X/Z, collisioni corpi/solidi, raycast, layer e livelli con coperture |
| M9B — ring | [x] | duello live libero, mosse configurabili, guardia, schivata, presa a quattro pose, hit-stop e ritorno alla run con sblocco singolo |
| M9C — FPS | [x] | due stanze, arma con caricatore/riserva/ricarica, tre nemici con telegraph, vittoria/sconfitta e gestione del cursore |
| M9D — strumenti | [x] | laboratorio mouse, collider/hitbox, passo singolo, preset mosse JSON validati e replay degli input in memoria |
| M9 / 0.5 | [x] | engine condiviso in tredici package, run come scena, menu e impostazioni, sei prove (platform 2D e 3D, arena, FPS, puzzle, ring unificato) e sfide nella run; launcher e script Windows disponibili |
| Dopo M9 | [ ] | bilanciamento umano di run e minigiochi, input del roguelike su action map (rimappatura, pad), timeline di presentazione generica nell'engine, altri oggetti/armi; salvataggio completo della run |

### M7: implementazione e verifiche storiche

Il prototipo M7 è stato integrato il 9 ottobre 2026. Questa sezione conserva
la cronologia della base su cui interviene M8; per tempo, dispositivi e
persistenza correnti vedere [M8](docs/regole/combattimento.md#m8-versione-04). Le attività ancora aperte
di M4–M6 restano valide. M8 salva gli sblocchi, ma non la run o replay completi.

| Incremento | Sorgenti / contratto implementato |
|---|---|
| M7A | [tactical.odin](src/game/tactical.odin), [tactical_controller.odin](src/run/tactical_controller.odin): pressione azzerata alla creazione riuscita di una nuova stanza; clock fornito dall'app; timeout esplicito; recupero fisso di 1 secondo attivo |
| M7B | visibilità logica senza memoria, condivisa col targeting; il renderer ricostruisce la maschera sullo snapshot mostrato; ologramma completo consultabile con countdown attivo |
| M7C | [card_play.odin](src/game/card_play.odin): base del costo temporale; in M8 il pagamento avviene durante il cast e il refill alla sua conclusione; carte sospese durante il recupero mobile |
| M7D | QTE diagonale con input ordinati, validazione del movimento e un secondo per successo o fallimento; nessun attraversamento degli angoli bloccati |
| M7E | pulse segmentato con ordine Protect/priorità per ID conservato; attacco fermato prima del danno, QTE da tastiera, ripresa una sola volta; difese disponibili anche durante il recupero |
| M7F | [tactical_renderer.odin](src/render/tactical_renderer.odin): terreno 3D, sprite su quad, alpha e profondità, [tactical_scene.odin](src/render/tactical_scene.odin): camera orbitabile, shader di luce/nebbia e geometrie; picking coerente con la camera; [hologram.odin](src/render/hologram.odin): schermo dedicato con miniature distinte, rotazione e zoom |
| M7H | [tactical_hand.odin](src/render/tactical_hand.odin): dock leggibile, dettagli effetti/QTE, targeting e costi visibili |
| M7I | [gothic_theme.odin](src/render/gothic_theme.odin), [assets/gothic](assets/gothic): atlanti trasparenti incorporati, font Jersey 10 con licenza OFL, pergamena, palette e cornici; sprite esterni e picking alpha conservati |
| M7J | [voxel_scene.odin](src/render/voxel_scene.odin): props, fog e minacce nello spazio 3D; [enemy_tactical_ai.odin](src/game/enemy_tactical_ai.odin): percorsi pesati, bombe annunciate, spinte e interazioni ambientali; [menu_theme.odin](src/render/menu_theme.odin): tema condiviso delle schermate |
| M7K | [resin_material.odin](src/render/resin_material.odin): materiale e mesh smussate condivisi con i dadi; [tactical_dodge.odin](src/game/tactical_dodge.odin): schivate attive/reattive e recupero; [room_generation.odin](src/game/room_generation.odin): profilo M7 ampliato; [m7_resin_smoke.odin](src/devtools/tactical_resin_smoke.odin): avvio reale e tiro di tre dadi da carta |
| M7L | [tactical_cards.odin](src/game/tactical_cards.odin): catalogo e status; [tactical_enemy_inspector.odin](src/render/tactical_enemy_inspector.odin): lettura dei nemici; [m7_rework_smoke.odin](src/devtools/tactical_rework_smoke.odin): interruzione, recupero e ricognizione tramite comandi reali |
| M7G | [m7_smoke.odin](src/devtools/tactical_smoke.odin), [m7_view_smoke.odin](src/devtools/tactical_view_smoke.odin): stress, confronto classico/M7, replay deterministico dei driver e verifica GPU; prove umane ancora da fare |

`Player.tactical` conserva configurazione, budget, cicli e metriche. La Room
possiede il cursore del pulse, il QTE attivo e la pesca rinviata. Ogni
continuazione produce un log limitato: il debito di tempo non accumula tutti i
beat nei 416 slot di un singolo comando. Fine del combattimento e restart
cancellano continuazioni/QTE; una nuova stanza azzera il contatore di finestre,
il recupero schivata e ripristina budget/timer. Configurazione e metriche
restano nel player della run. Il clock decisionale e quello QTE non dipendono da
FPS, `--fast` o velocità delle animazioni.

I comandi M7 passano dal dispatcher condiviso: `Timeout`, `Continue_Pulse`,
`Begin_Diagonal`, `Defense`, `QTE_Key`, `QTE_Fail`.
Il pulse conserva gli intenti committed; parry e deviazione annullano la
risoluzione dell'attacco senza riscriverne il piano. I comandi ordinari non
possono intervenire mentre una risposta è sospesa.

```sh
sh scripts/check.sh
odin run src -o:none -- --smoke-m7
odin run src -o:none -- --smoke-m7-view
odin run src -o:none -- --decision-time=15 --vision=2 --playtest-report
```

Lo smoke headless scrive `odin_pp_m7_stress.json`: dieci combinazioni di
15/20 secondi e visibilità completa/2×2/3×3/5×5/7×7, ripetute due volte. Ogni arena
raggiunge otto cicli e otto beat di recupero. La salute elevata dell'arena serve
a verificare cicli ripetuti, non a stimare il bilanciamento. Quattro run con
statistiche normali confrontano classico/M7 su due seed fino a Victory o
Defeat, anch'esse ripetute; il driver semplice non rappresenta un giocatore
esperto e può perdere. Ogni percorso controlla commit, log e terminazione.

Lo smoke grafico salva `odin_pp_m7_scene.png`, `odin_pp_m7_hologram.png`,
`odin_pp_m7_hologram_rotated.png`, `odin_pp_m7_cards.png`,
`odin_pp_m7_full_hand.png`, `odin_pp_m7_diagonal.png` e `odin_pp_m7_defense.png`; ruota e ingrandisce
l’ologramma verificando che consumi tempo, esegue una diagonale e
un parry usando i comandi reali, verifica un solo avanzamento del pulse contenente il parry e la sincronizzazione
della timeline. Cattura inoltre `odin_pp_m7_voxels_0/1/2.png` per oggetti,
camera ruotata e confronto senza fog; salva schermate di reliquie, ricompense,
rotta, mercante, riposo, eventi, tesori, vittoria e sconfitta, poi chiude la
finestra. Le scene di combattimento sono arene controllate.
`odin_pp_m7_expanded_room.png` mostra invece il primo incontro realmente
generato; `odin_pp_m7_expanded_overview.png` ne mostra il confronto senza fog.
`odin_pp_m7_resin_dice_0/1.png` catturano rimbalzo e assestamento di tre dadi,
prodotti da una giocata reale di Prismatic Barrage: il playback verifica
che lo stato RNG non cambi e che la timeline termini senza errori.
`odin_pp_m7_rework_cards.png`, `odin_pp_m7_rework_enemy.png` e
`odin_pp_m7_rework_survey.png` mostrano carte, pannello nemico e visuale ampliata
dopo vere giocate di Heavy Blow e Battle Focus.

Con `--playtest-report`, oltre al report esistente, viene scritto un file
separato `*.m7_N.json` con `schema_version = 2`, seed, configurazione e
metriche M7: decisioni, timeout, recuperi, beat del recupero (`forced_pulses`,
nome storico), esiti QTE e tempo attivo (`decision_seconds`, incluso recupero)
e nell'ologramma. La versione 2 rimuove durata della preparazione e carte
anticipate; anche `odin_pp_m7_stress.json` usa lo schema 2. La creazione
esclusiva evita sovrascritture; i tempi riflettono la sessione interattiva.
Lo schema del report di combattimento classico resta invariato. I segmenti
M7 vengono osservati separatamente: per il costo complessivo di una carta
va considerata anche la successiva risposta nemica.

Le regressioni di [tactical_test.odin](src/game/tactical_test.odin) verificano
cicli, recupero fisso, timeout, QTE, angoli, difese e morte. I test
`tactical_room_pressure_test.odin` nei package game/main coprono reset della
pressione alla nuova stanza, transizione con reward e mancata mutazione
quando la costruzione fallisce. Quelle di [tactical_renderer_test.odin](src/render/tactical_renderer_test.odin)
verificano fog dello snapshot, proiezione/picking in entrambe le camere e
selezione alpha degli sprite e selezione dei volumi degli oggetti, esclusi
quelli nascosti dalla fog. [enemy_tactical_ai_test.odin](src/game/enemy_tactical_ai_test.odin)
copre preparazione e interruzione dei lanci, micce e danni, percorsi sicuri,
spinte, blocchi completi, parry delle cariche e barili spostati. Verifica anche
che l'avvio M7 ripianifichi gli intenti inizialmente creati con le regole classiche.
[tactical_controller_test.odin](src/integration/tactical_controller_test.odin)
verifica il gestore condiviso degli input: pulsante, trascinamento, zoom,
ricentramento, chiusura senza clic passanti e countdown durante la mappa.
Il test interattivo tramite automazione macOS non ha recepito i clic sintetici:
resta da confermare la sensazione dei controlli con mouse/tastiera reali.
La suite classica viene eseguita insieme a
quelle nuove, con e senza assert.

### Stabilità input e verifica del blocco persistente

La revisione del 9 ottobre distingueva due problemi. Il primo era la
**pressione WASD persa durante la timeline M7**: il controller ritornava
prima che il poll ordinario potesse leggerla. La correzione di allora la
conservava (al massimo un passo nella stessa fase Combat/Loot); dal 14 ottobre
la regola è l'opposto e vale in tutto il gioco: **nessun comando resta in
coda**. Il passo conservato partiva da solo alla fine dell'azione, e chi
premeva più volte si trovava azioni in più; ora una pressione fatta durante la
propria azione (animazione, secondi dell'azione o passo dell'ombra) viene
scartata e agisce solo una pressione successiva
([Input senza coda e transizioni](docs/presentazione.md#input-senza-coda-e-transizioni)). Resta solo
il passo premuto sul secondo, che aspetta per 0,06 s il tasto della diagonale:
QTE, fine della finestra, cambio fase, ologramma, pausa e perdita del focus lo
lasciano cadere, e non esiste uno sblocco forzato. L'ingresso nel recupero
permette un nuovo passo nello stesso frame; durante il recupero i nuovi passi
restano validi.

Il **blocco persistente anche con nuove pressioni** segnalato nel playtest
non è ancora riprodotto: non va considerato risolto né dalla coda di allora né
dalla sua rimozione.
Il successivo pass grafico è stato richiesto separatamente: i nuovi feedback
leggono la timeline esistente e non introducono timer di blocco o fasi logiche.
Quando si verifica, premere **F8** prima di riavviare: viene creato un file
esclusivo `odin_pp_input_N.txt` nella directory di avvio (massimo 8 KiB per
cattura, 256 file). Contiene seed, nodo, fasi logiche e mostrate, focus,
pausa, QTE, clock, pulse, cursore/tempo della timeline, drag, il passo in
attesa della diagonale (`chord_active`, `chord_direction`, `chord_timer`) e
collisioni delle quattro celle vicine. Ripetere F8 dopo una nuova pressione
WASD consente di confrontare gli stati. La cattura non modifica il gioco.
Per una traccia di ogni input durante lo sviluppo:

```sh
odin run src -o:none -define:M7_INPUT_TRACE=true
```

Le regressioni di `gameplay_input_test.odin` e `tactical_controller_test.odin`
fanno passare ogni pressione per una copia della corsia della scena
(presentazione, controller, scarto dell'input nei fotogrammi che il controller
tiene per sé, poi il comando con lo stesso stato "occupato" della scena) e
verificano che una pressione durante la propria azione si perda invece di
accodarsi, senza che il controller ne tenga nulla da parte, premendo a ogni
fotogramma: per tutto il secondo di un passo in combattimento, per tutto il
turno di un passo con `--classic` (la stessa corsia di `--spell-lab` e
`--dice-lab`) e per tutto un passo del loot. Verificano anche che la schivata
interrompa ancora l'azione e che il passo in attesa della diagonale cada a ogni
confine; `shadow_controller_test.odin` fa lo stesso dentro l'ombra di Movimento
Ombra. `tactical_liveness_test.odin` attraversa controller e timeline frame per
frame, con timestep regolari/irregolari, velocità 1×/4×, QTE,
recuperi ripetuti. Verifica inoltre tre finali di fight (parry, veleno durante
recupero, parry durante recupero), Loot, reward e
movimento nella nuova stanza. Un harness esplorativo temporaneo ha provato
192 partite generate: 7.610 comandi, 8.028 pulse, 474 tiri di dadi e 388
Refocus, senza stalli; questo non dimostra l'assenza del bug segnalato.

Lo smoke grafico include `m7_polish_smoke.odin`: movimento che dimentica la
vecchia zona visibile, uccisione reale con Piercing Ray, transizione luminosa,
sette passi nel loot con raccolta del drop (durante il primo, `D` premuto a
ogni fotogramma passa per la corsia della scena e si perde: il giocatore resta
fermo finché un nuovo tasto non lo muove di una casella), reward, stanza
successiva e nuovo movimento, verificando reset di luce/fog e assenza di
errori di timeline.
Salva `odin_pp_m7_polish_combat.png`, `odin_pp_m7_polish_loot.png` e
`odin_pp_m7_polish_next_room.png`. L'automazione nativa macOS non ha consegnato
tasti/clic a Raylib neppure nel menu iniziale: il playtest automatizzato in
finestra usa i controller e i comandi reali del progetto.

Il refactor di `render/card_description.odin` elimina la tabella numerica
parallela nei testi di mano/ispettore: valori, durate, raggi e cariche derivano
dal catalogo effettivo, compresi gli upgrade. Formule dei dadi e differenze
intenzionali classico/M7 restano esplicite e coperte da test.

### Direzione visiva: diorama gotico e pixel dark fantasy

La scena M7 unisce architettura 3D in resina blu scuro e personaggi 2D pixel.
`render/diorama_scene.odin` raccoglie pavimenti incisi, modanature, nicchie,
lanterne e pulviscolo. Lo shader usa al massimo quattro lanterne visibili,
oltre alla luce del giocatore; la scelta è deterministica e non consuma RNG.
Gli elementi trasparenti rispettano la profondità senza scriverla. La fog
non conserva memoria e le decorazioni non rivelano celle nascoste.

I nuovi personaggi incorporati sono in `assets/gothic/figures-v2.png`:
arciere con balestra, bruto corazzato, ghoul, custode e pose del pellegrino
hanno silhouette e accenti blu più distinti. La versione precedente resta
disponibile; metodo, prompt e regioni dell'atlante sono documentati in
[`assets/gothic/generation-prompts.md`](assets/gothic/generation-prompts.md).
L'opzione `--sprites` continua a prevalere sugli asset incorporati. Salute
e intenti si ancorano alla geometria effettiva dello sprite, incluse le pose.
L'allocatore riserva anche le sagome proiettate: il vincolo del bordo superiore
non può spingere un'etichetta sopra un personaggio. Se le corsie preferite
sono occupate, una ricerca limitata sceglie lo spazio libero più vicino,
anche sotto l'ancoraggio. Due regressioni coprono bordo superiore e folla.

`render/tactical_feedback.odin` interpreta le cue già esistenti: piccoli
salti, flash di danno, scudi esagonali, rune, interruzioni, proiettili e
frammenti d'impatto. Gli effetti sono locali, limitati a 32 cue simultanee,
senza particelle persistenti o aggiornamenti di gameplay. I badge condividono
l'allocatore di cuori, sigilli e bombe e, se spostati, hanno un collegamento
al bersaglio. Le carte mostrano cornici metalliche, gemme energia, sigilli
rarità e feedback di selezione; a otto carte i dettagli lunghi restano
consultabili nell'ispettore. Layout e hitbox della mano non cambiano.

La transizione di 1,2 secondi dopo il combattimento schiarisce stanza,
percorso e loot; una nuova stanza ripristina luce e fog da combattimento.
`--smoke-m7-view` include ora `m7_visual_smoke.odin`: azioni reali generano
cast, movimento, danni a entrambi gli attori, scudo, assorbimento,
interruzione, volo e impatto di Firebomb. Salva `odin_pp_m7_visual_*.png`,
controlla RNG e integrità della timeline e stampa un microprofilo locale
di update e invio draw CPU. Quest'ultimo esclude present/vsync, screenshot
e completamento GPU: non è una misura del frame time complessivo.

I test dei feedback verificano isolamento del bersaglio, immutabilità della
timeline e ritorno a terra al termine del movimento senza contatori residui.
Gli smoke di loot/stanza successiva e le suite classica/M7 restano attivi.

Verifica locale del primo pass (9 ottobre 2026, Apple M1, build `-o:none`):
`scripts/check.sh` passa 634 test sia con sia senza assert, check strict/vet
e build in entrambe le configurazioni. Lo smoke 3D attraversa combattimento,
sette passi nel loot, raccolta e nuova stanza con zero errori di timeline.
Il campione dei nove feedback comprende 328 frame: invio draw CPU medio
7,893 ms, picco 13,221 ms. Non certifica tempi GPU o tutti gli incontri densi.

### Reset stanza, spawn centrale e HUD compatto

Il ciclo di penalità era conservato in `Player.tactical` anche entrando nella
stanza successiva. `begin_tactical_room` ripristina ora ciclo zero, fase Decision,
timer/budget configurati, zero pulse residui e zero recupero schivata. Il reset
avviene soltanto dopo la costruzione riuscita della stanza; configurazione,
orientamento e metriche cumulative restano conservati. Ogni stanza riparte da
Pulse 1; il recupero resta sempre di un secondo. I percorsi classici non
applicano questo reset.

Le stanze procedurali M7 selezionano lo spawn centrale **prima** di collocare
incontri e oggetti. Viene scelta la cella valida più vicina al centro, con
clearance completa e un'uscita alla distanza minima richiesta; i pareggi
dipendono dal seed. Le forme delle cinque famiglie, la connettività e le
distanze da nemici, trappole e solidi restano validate. Classico e arene
costruite a mano conservano gli spawn previsti. Le regressioni coprono
360 layout con rigenerazione deterministica e 192 blueprint M7.

`render/tactical_hud.odin` separa salute/stati, fase/timer e controlli in
tre pannelli compatti. Rosso per urgenza e danni; blu per informazioni normali.
L'area mano passa da 221 a 184 pixel logici, le carte da 182 a 154; vengono
eliminate istruzioni e footer ripetuti. Le hitbox condividono i nuovi bounds.
L'ispettore conserva i testi completi anche con otto carte e i QTE mostrano
sempre le difese disponibili. La camera lascia più spazio al campo di gioco.

Il nuovo pass usa smussi uniformi nello spazio 3D, riflessi e grana più
controllati, incavi sui capitelli e ombre di contatto morbide sotto gli attori.
`render/tactical_surface.odin` disegna la scena 3D e l'ologramma a risoluzione
2×, riducendoli con filtro bilineare prima di comporre HUD e testi pixel.
Il target GPU viene allocato una volta e rilasciato con il renderer; se non
disponibile resta il percorso diretto. Il resolve è opaco: l'ologramma non
lascia trasparire le carte o la scena precedente. Picking e regole rimangono
in coordinate logiche. La mappa ha griglia ciano, minacce rosse, sprite reali
e legenda orizzontale; il countdown continua durante la consultazione.

`m7_room_refresh_smoke.odin`, incluso in `--smoke-m7-view`, attraversa due
stanze realmente generate con comandi, loot, reward e ingresso nel nodo.
Verifica spawn centrali, reset di ciclo/timer, metriche conservate e ritorno
a fog/luce da combattimento. Salva `odin_pp_m7_room_refresh_first.png` e
`odin_pp_m7_room_refresh_next.png`. La fixture usa salute/attacco elevati per
verificare la transizione, non per misurare il bilanciamento.

Verifica della revisione: `scripts/check.sh` supera 640 test con e senza
assert, strict/vet e entrambe le build; `--smoke-m7` passa 10 preset e quattro
run terminali ripetuti. Lo smoke 3D conferma spawn `{8,5}` nelle due stanze
generate della fixture, ciclo `5 → 0`, metriche conservate e zero errori di
timeline. QA visiva completata su HUD, otto carte, QTE, ologramma normale e
ruotato, loot e nuova stanza. Nel campione finale di 328 frame il costo CPU
medio di invio draw è 7,729 ms (picco 15,465 ms, Apple M1, `-o:none`), sempre
esclusi present/vsync, cattura PNG e completamento GPU.

### Mura interne trasparenti e perimetro orientato alla camera

Nel diorama 3D le mura interne conservano l'altezza completa (1,58 unità),
con corpo e rilievi blu semitrasparenti e zoccolo opaco per rendere leggibile
la cella occupata. Si abbassano a 0,5 unità soltanto i due lati del perimetro
rivolti verso la camera. I lati opposti rimangono alti; un raccordo angolare
continuo evita scatti quando la camera passa da un quadrante al successivo.
Lo spostamento del player o lo zoom non cambiano i lati abbassati.

`render/diorama_scene.odin` separa basamenti opachi e corpi delle mura.
`render/tactical_translucency.odin` ordina pareti interne e sprite insieme,
dal fondo verso la camera, conservando il test di profondità del terreno
senza scrivere profondità per le superfici trasparenti. Anche rilievi e
lampade interne seguono la trasparenza. Il buffer di ordinamento riusa la
capacità fra i frame ed è rilasciato con il renderer.

È una modifica di presentazione: le mura restano solide e bloccano la linea
di vista. La fog di combattimento continua a nascondere le celle non visibili;
il materiale trasparente non rivela nemici oltre la fog. L'ologramma conserva
la propria geometria e il timer attivo; la modalità classica non cambia.

Le regressioni coprono classificazione interno/perimetro, quattro quadranti,
rotazione continua, traslazione/zoom, ordine dei layer e visibilità. Lo smoke
`m7_wall_smoke.odin`, incluso in `--smoke-m7-view`, cattura un combattimento
con nemico occluso e quattro angoli della stessa stanza in Loot:
`odin_pp_m7_walls_combat.png` e `odin_pp_m7_walls_corner_0.png` … `_3.png`.

Verifica della revisione: `scripts/check.sh` supera 645 test con e senza
assert, strict/vet e le due build. Gli smoke headless e 3D passano; la prova
in finestra include quattro angoli, nemico nascosto dalla fog, combattimento,
movimento nel Loot e nuova stanza, con zero errori della timeline.

### M7: pulse temporale e cadenze autonome

Nota storica: in M7 anche il costo delle carte maturava beat immediati. M8
separa il cast dal clock del mondo; la descrizione seguente conserva il contesto
del rework, con smoke e regressioni aggiornati alla nuova regola.

`game/tactical_clock.odin` riceve sia il tempo decisionale reale sia il costo
delle azioni accettate. Accumula le frazioni e accoda beat da un secondo;
`Continue_Pulse` li risolve con log limitati, senza ricorsione né perdita dei
beat durante un QTE. La scadenza della finestra usa `tactical_expire_window`,
dopo aver risolto il tempo già pagato. `remaining` non viene più ripristinato
al termine di ogni comando. Le regole e i valori iniziali sono descritti in
[Modalità tattica M7](docs/regole/combattimento.md#modalità-tattica-m7).

I nemici conservano una scadenza individuale e l'intento già annunciato.
Gli status a durata, le bombe e i recuperi avanzano sul clock del mondo; il
Veleno morde le azioni di chi lo porta, la Bruciatura ogni finestra che scade e
il Rallentamento allunga i prossimi intenti del nemico; l'energia ha
una cadenza distinta di tre secondi. Stagger cancella un intento anche prima
della sua scadenza e lascia almeno un secondo di recupero sfruttabile dopo
il costo della carta. Fine fight e nuova stanza cancellano frazioni/debito,
continuazioni e QTE. Il classico conserva la risposta a ogni comando.

La presentazione M7 ha due canali: l’azione del player e i cue del mondo.
`drain_tactical_world_commands` completa i segmenti logici dovuti nello stesso
frame, con budget derivato dal debito e dal numero massimo di nemici; si ferma
su QTE o fine fight. Il polling del player avviene subito dopo, senza attendere
le immagini. `renderer_blocks_player_input` considera soltanto la propria azione;
`renderer_timeline_is_busy` include entrambi i canali per completare correttamente
transizioni e smoke. Il clock reale prosegue durante i cue ordinari. In M8
il cast ferma il mondo e le cinematiche fermano anche il countdown del player.

`render/world_playback.odin` conserva cue e trasformazioni, senza sostituire lo
stato aggiornato con snapshot di vecchi beat. Corpi diversi si animano insieme;
i waypoint dello stesso corpo mantengono ordine e durata. Un banco limitato,
allocato una volta e riutilizzato, riserva spazio prima del commit logico: nessun
beat già applicato perde la sua presentazione. Clear e distruzione includono
entrambi i canali. Lo snapshot diagnostico F8 distingue il blocco della propria
animazione, i cue del mondo e il debito del clock. Il flag interno `forced`
identifica soltanto i beat maturati durante il recupero e non blocca l'input.

Lo smoke `m7_timed_pulse_smoke.odin` esegue due passi e Guard nello stesso
Pulse 1 (`20 → 17 s`), poi consulta l'ologramma per 1,25 secondi (`15,75 s`).
In M8 i due passi producono due beat e Guard nessuno: il successivo tempo
dell’ologramma aggiunge il terzo beat, rispettando le cadenze dei nemici. Salva
`odin_pp_m7_timed_actions.png` e `odin_pp_m7_timed_hologram.png`.
Lo smoke `m7_independent_world_smoke.odin` esegue un passo, una nuova pressione
e Guard durante animazioni nemiche ancora attive, facendo avanzare il clock a
ogni frame. Salva `odin_pp_m7_independent_movement.png` e
`odin_pp_m7_independent_card.png`; `odin_pp_m7_independent_ready.png` mostra
il ritorno immediato ai comandi mentre i nemici stanno ancora animando.
Le regressioni verificano anche interpolazione
simultanea, stato aggiornato dopo danni/scudi, velocità di playback 1×/4× e
countdown attivo ma mondo fermo durante il cast del player.
Le regressioni coprono anche input esattamente sul beat, targeting conservato,
scadenza senza doppio addebito, animazioni/QTE, tempo frazionario, interruzioni
e cancellazione del debito nel Loot. La fixture grafica usa salute elevata
per verificare il flusso; i costi sono una prima taratura da valutare in run.

Verifica storica della base M7: `scripts/check.sh` passava 683 test con e senza assert, strict/vet
e le due build. Lo smoke headless completa dieci preset e quattro run terminali
ripetuti due volte. Lo smoke 3D verifica azioni multiple, ologramma, nove feedback,
combattimento/Loot/stanza successiva e quattro angoli delle mura, senza errori
della timeline. La QA visiva conferma costi energetici e temporali distinti e
countdown dei nemici leggibili; il bilanciamento resta da valutare giocando.


### M7: recupero mobile di un secondo

Il precedente salto di turno contava beat `1, 3, 5…` ma aspettava la timeline
per ogni segmento: la durata percepita dipendeva da nemici, effetti e velocità
visiva. Ora `TACTICAL_RECOVERY_SECONDS = 1` usa il clock attivo condiviso.
`tactical_allows_movement` separa la camminata dall'offensiva;
`tactical_allows_action` viene usato da gameplay, carte, preview e HUD.
Il controllo dell'attacco contro un nemico avviene prima di modificare il log.

`Recovery` sostituisce `Forced`; sono rimossi `Preparation`, `End_Preparation`,
la configurazione della preparazione, il contatore di pulse da saltare e la
formula crescente. `Continue_Pulse` accetta soltanto beat già maturati:
richiamarlo non accelera il recupero. `tactical_finish_recovery` riattiva le
azioni soltanto dopo timer zero, debito risolto e nessun QTE pendente. Camminare
non genera tempo, energia o beat aggiuntivi; bombe, status e collisioni
conservano gli effetti normali. Il classico conserva le sue regole.

Le regressioni verificano partizioni del secondo a 1/4/60/120 aggiornamenti,
playback 1×/4×, passi ripetuti gratuiti, attacchi/carte/refocus respinti senza
mutazioni, beat anticipato, QTE sospeso e ripreso, morte da hazard e fine fight
da veleno. `m7_recovery_smoke.odin` usa i comandi reali anche nella finestra 3D:
cattura `odin_pp_m7_recovery_walk.png` a metà recupero, dopo due passi, e
verifica il ritorno delle carte al pulse successivo. Un secondo è la prima
taratura da valutare con partite reali, non un bilanciamento definitivo.

### M8 / 0.4: implementazione e verifica

Il perimetro consegnato e i controlli sono descritti in [M8](docs/regole/combattimento.md#m8-versione-04).
Le policy temporali sono separate in `cast_playback.odin`, `frame_timeline.odin`
e `tactical_controller.odin`; i costi restano centralizzati nel catalogo tattico.
Geometria, preview e danno dei dispositivi condividono `board_device.odin`.
`m8_equipment.odin` gestisce gli utilizzi senza cambiare l'attacco classico;
`m8_ring.odin` conserva la progressione, i traguardi una sola volta e la
simulazione originaria per compatibilità. Il duello live corrente è in `fight`;
`m8_session.odin` possiede il passaggio alla sessione M9 e il file del profilo.

I test coprono separazione dei clock, mancato doppio addebito, dadi e F4,
scadenza a fine cast, rifiuti senza mutazioni, d4 con più bersagli, massimo
numero di dispositivi, distanza, linea di vista, campo con fuoco amico, ricarica
e rimozione nel Loot. Equipaggiamento e ring verificano cariche, swap, vincita
con tre schivate/prese, quattro pose, sconfitta non letale, sblocchi a mazzo pieno,
filtri delle offerte, input temporali non finiti e persistenza del profilo.
Gli smoke precedenti sono migrati al nuovo cast, mantenendo classico, QTE,
recupero, fog, ologramma, Loot e ingresso nella stanza successiva.

```sh
sh scripts/check.sh
./run.sh --smoke-m7
./run.sh --smoke-m8-view
./run.sh --smoke-arenas-view
./run.sh --smoke-dice-set
```

Verifica precedente della base M8 del 9 ottobre 2026: `scripts/check.sh` completo, **748 test superati**
sia con assert sia senza, vet/strict-style e build puliti, nessun leak segnalato.
Passati lo stress headless (10 preset e 4 run terminali ripetute due volte),
il percorso 3D M7 e quello M8: piazzamenti, d4, campo Tesla con fuoco amico,
equipaggiamento, Loot, ring con quattro pose/sblocco e stanza successiva.
Lo smoke headless delle run avanza un cast direttamente attraverso
`tactical_tick(cast_remaining)`: il suo limite conta passi logici anziché ogni
frame grafico a 60 Hz, che nei nuovi combattimenti esauriva prematuramente il
budget. Il comportamento a frame rimane coperto dai test dei clock/controller
e dagli smoke 3D. Il seed che falliva completa ora tutti i sette nodi.
Le regressioni includono l'ultimo frame cinematografico senza addebito,
la sospensione di eventi già pendenti, i bordi della pausa e il campo che
colpisce tutti i bersagli anche quando la stessa scarica uccide il player.
I controlli solo mouse verificano equipaggiamento e attivazione al singolo
clic, pulsanti disabilitati e apertura/chiusura dei modali senza clic sulla board.

Lo smoke M8 usa una vera finestra Raylib 3D e comandi scriptati attraverso il
dispatcher. Salva d4, rete elettrica, scheda personaggio, Loot, quattro pose del
ring e stanza successiva. Queste sono prove riproducibili di integrazione e resa
visiva; non sostituiscono una sessione manuale di bilanciamento. Gli esiti finali
della verifica vanno riferiti alla revisione eseguita, senza riutilizzare i
conteggi storici delle milestone precedenti.

Aggiornamento trappole, Tesla e dadi del 9 ottobre 2026: **770 test superati**
con e senza assert, `scripts/check.sh` completo (vet/strict-style e due build).
Le regressioni aggiunte coprono attesa senza consumo, ingresso/spinta/carica,
teletrasporto, player escluso dall'innesco, pulsante solo Tesla e sincronizzazione
del nuovo evento `Hazard_Triggered` con la presentazione. Per la rete verificano
persistenza delle pareti, cooldown, danni prima del consumo delle quattro torri
e possibilità di riposarle. I test dei dadi verificano geometria chiusa,
numerazione fissa, appoggio di ogni risultato sul piano, ripetibilità e assenza
di mutazioni durante il playback.
Un controllo nativo più stretto ha inoltre riprodotto due errori di timeline
per ogni piazzamento Tesla: il validator dei lanci/impatti ammetteva solo le
vecchie spell e le carte con dadi. Ora riconosce anche le carte dispositivo;
una regressione verifica gli eventi reali di posa, scarica e consumo, con
zero errori di presentazione e nessun evento perso.

Passati lo stress M7 (10 preset e 4 run ripetute due volte) e gli smoke nativi
M8 e set dadi. Il primo prova pedana automatica, consumo della mega con fuoco
amico, equipaggiamento, Loot, ring e stanza successiva. Il secondo disegna i
sette modelli lungo 100 frame di lancio, tutti i risultati del D4 e lo 00 del
percentuale. Screenshot: `odin_pp_dice_set.png`, `odin_pp_dice_d4_detail.png`,
`odin_pp_m8_d4.png`, `odin_pp_m8_devices.png` (rete prima della mega) e
`odin_pp_m8_mega_combo.png` (dopo il consumo). La verifica visiva ha corretto
anche il materiale che ignorava l'alpha dell'atlante e copriva le cifre con
rettangoli: ora la resina campiona la texture dei numeri e mantiene l'avorio
leggibile sulle facce in ombra.

La verifica delle arene progressive usa quattro blueprint reali (17×11,
25×17, 33×23 e 45×31), fino a 22 nemici. Lo smoke 3D ha verificato 28 beat
nemici, quattro movimenti durante il playback indipendente, 63 passi nel Loot,
quattro transizioni e nessun evento scartato. Per isolare il flusso usa un player
con 1.000 HP e un finisher scriptato attraverso il normale risolutore di effetti;
non dimostra il bilanciamento di una vittoria giocata manualmente.
Il log distingue tempo CPU di generazione/simulazione e invio del disegno di
mondo/ologramma, escludendo presentazione, vsync, PNG e completamento GPU.

### M9: implementazione e verifica

Le [fondazioni M9](docs/modalita_libere.md#m9-fondazioni-per-le-modalità-libere) sono integrate nella
base 0.4. Prima dell’integrazione del branch engine, il controllo del
10 ottobre 2026 superava **829 test** in
tutti i package, sia con assert sia senza, oltre a vet/strict-style e alle
due build. Lo smoke nativo M9 verifica collisioni nell'arena, vittoria contro
l'IA del ring con valori ordinari, presa in quattro pose, replay identico,
FPS con attacco annunciato, ricarica, vittoria e ritorno fra modalità.
Sulla stessa build passano anche il confronto headless M7 (dieci preset,
quattro run terminali e otto cicli stress) e lo smoke 3D M8: dispositivi,
equipaggiamento, loot e ingresso nella stanza successiva.

Le regressioni coprono anche pareti sottili, collisioni veloci, colpi e prese
ostruiti dai pilastri, lancio fermato al primo contatto, registrazione dei
corpi dopo cambio livello, mancato click sui controlli nascosti, input al
cambio focus e assegnazione singola degli sblocchi. Le prove scriptate
dimostrano questi contratti; difficoltà, varietà delle mosse e qualità del
ritmo restano da valutare con partite umane.

Screenshot rigenerabili: `odin_pp_m9_arena.png`, `odin_pp_m9_ring.png`,
`odin_pp_m9_fps.png`, `odin_pp_m9_tools.png` e le quattro pose
`odin_pp_m9_ring_grab_0.png`–`odin_pp_m9_ring_grab_3.png`.

Correzione dell'avvio FPS con il mouse: il precedente messaggio centrale era
solo disegnato, mentre il clic era riconosciuto esclusivamente su **RIPRENDI**
in alto. Ora il pannello centrale è un pulsante con disegno e hitbox condivisi,
attivo solo durante una partita FPS in pausa. La ripresa è idempotente e
consuma il clic senza sparare. Le regressioni seguono il percorso
posizione del mouse → controllo → simulazione e verificano anche gli stati
non riprendibili; l'avvio è stato confermato nella finestra macOS.


### Integrazione del branch engine/minigiochi

Il 10 ottobre 2026 è stato integrato `claude/engine-minigiochi` (`67b6297`)
partendo dal checkpoint locale M9 `5f7650a`. Il merge a tre vie mantiene
entrambi gli sviluppi: i servizi dell’engine, il menu e i cinque minigiochi del
branch; collisioni continue, ring, FPS, replay, strumenti e fix del clic M9
locali. Dadi canonici, Tesla persistenti e trappola passiva restano presenti.
Il controller continuo X/Z di `src/engine` e i controller tile/voxel di
`src/engine/physics` coprono domini diversi; non sono stati sostituiti l’uno
con l’altro. RNG ed easing comuni eliminano duplicazioni senza cambiare le
sequenze di gameplay.

L’audit ha aggiunto regressioni e correzioni funzionali:

- FPS e arena conservano un clic breve ricevuto fra due tick e lo consumano
  una volta. Il clic del menu non spara all’avvio o alla ripresa.
- Pausa e perdita del focus cancellano input pendenti e frazioni temporali
  residue; i clock ignorano delta negativi o non finiti. I tick completati
  non vengono azzerati.
- I profili corrotti o di versione futura non vengono sovrascritti con i
  valori predefiniti. Il decode JSON usa memoria temporanea fino alla
  validazione, evitando perdite con dati annidati rifiutati.
- Un raycast può entrare dall’esterno in una tile map aperta.
- Le sfide della run verificano identità, stanza ed esito pendente prima
  della ricompensa. Risultati duplicati, estranei o già consumati non pagano.
- Seed CLI riproducibile, nessuna scrittura dei profili negli smoke/lab e
  pulsante delle nuove sfide azionabile con il mouse, separato dai controlli M9.

Verifica dell’integrazione: `scripts/check.sh` copre tutti i **1.011 test**
con assert attivi e disattivati, controllo strict/vet e due build. Tutti i
servizi e minigiochi registrati sono raggiungibili da `src`: le due esecuzioni
`-all-packages` bastano, senza ripetere singolarmente le stesse suite negli
script Unix e PowerShell.

Il report headless M7 prima/dopo il merge è identico byte per byte (4.023
byte, SHA-256 `343cae6483dc8f40cc4cf4973a721b8107861abbeb64b7db00e0f767acd8687c`):
dieci preset, quattro run terminali ripetute e otto cicli stress. Gli smoke
nativi verificano menu, avvio/rendering dei cinque minigiochi, flusso M9,
dispositivi/loot/cambio stanza M8 e i sette dadi 3D. Catture rigenerabili:
`odin_pp_menu.png`, `odin_pp_platform2d.png`, `odin_pp_platform3d.png`,
`odin_pp_arena.png`, `odin_pp_fps.png`, `odin_pp_puzzle.png`, oltre alle
catture M8/M9 e del tavolo dadi.

Le verifiche native sono state eseguite su macOS; gli script Windows sono
inclusi ma non sono stati eseguiti su Windows in questa integrazione.
Gli smoke dei nuovi minigiochi durano 180 frame: le partite complete sono
coperte dai bot headless, non da playtest umani. Restano da valutare difficoltà,
ritmo e coerenza visiva fra le modalità. Raylib segnala dodici codepoint non
presenti nel font incorporato; nelle catture esaminate i testi di gioco sono
leggibili, ma non è una verifica completa di tutti i caratteri del font.


### Allineamento engine e HUD dopo il merge

L’host gestisce ora interattività e sospensione delle scene in modo uniforme;
la run e le attività M9 rispettano la stessa ownership dell’input. Sono stati
riprodotti e corretti due difetti del contratto scene: una prova continuava a
simulare sotto un overlay non modale e il nome/esito di una scena poteva
essere invalidato da `destroy` prima della callback di ritorno. Le regressioni
coprono anche overlay modali, push rifiutati e clic ereditati fra schermate.
`Resume_Gate` sostituisce cinque implementazioni locali della ripresa input.

HUD e menu condividono palette e primitivi grafici dell’engine. Nella run
sono stati rimossi pannelli vuoti, ridotte le informazioni ripetute e separate
le attività del Loot dal percorso centrale. Nelle cinque prove sono allineati
pannelli, barre, obiettivi e notifiche; il puzzle riserva esplicitamente spazio
alla board su tutti i livelli. Il test della barra oggetti distingue controlli
nascosti, controlli visibili disabilitati e click sulla board.

Verifica del 10 ottobre 2026: **1.025 test** con e senza assert, strict/vet e
due build tramite `scripts/check.sh`. Dopo l’ultimo aggiustamento geometrico
del pannello Loot sono state ripetute le regressioni HUD e lo smoke M8.
Il report M7 è ancora identico byte per byte al merge precedente. Gli smoke
nativi coprono menu, avvio e rendering delle cinque prove, ring/FPS/replay M9,
combattimento e dispositivi M8, Loot e stanza successiva. Screenshot:
`odin_pp_menu.png`, `odin_pp_m8_devices.png`, `odin_pp_m8_loot.png`,
`odin_pp_platform3d.png`, `odin_pp_fps.png`, `odin_pp_puzzle.png`.

Questo allineamento non modifica bilanciamento o regole di combattimento.
Griglia tattica, fisica continua X/Z e controller platform tile/voxel restano
specializzati; i laboratori CLI conservano i propri driver diagnostici.
L’input del roguelike non è ancora completamente rimappabile tramite action
map e le due progressioni salvate restano distinte. La revisione artistica successiva è descritta sotto. Verifiche native su
macOS, script Windows non eseguiti.


### Coesione delle prove e FPS/ring unificati

Tutte le prove adottano nero, ardesia/blu e avorio. Rosso comunica pericolo,
oro indica rune e ricompense. FPS e platform 3D usano le figure dell’atlante
principale con silhouette di carta separate, precompilate al caricamento;
platform 2D, arena e puzzle conservano le pose dei propri sprite e ricevono
la stessa cornice avorio/nera. Nessuna rigenerazione di texture per frame.
La lieve lucentezza è un parametro opzionale del lighting condiviso, zero
per i renderer che non la richiedono.

Il ring ha una pedana scolpita, intarsi, angoli illuminati e camera più ampia.
La Cripta ha superfici blu levigate, architettura incisa, magie leggibili e
segnali d’attacco. Guglie Sospese sostituisce l’avatar cubico con il Viandante;
le piattaforme hanno bordi e nicchie. Torre di Cenere, Arena delle Braci e
Sigilli della Cripta condividono pietra, cornici e accenti freddi mantenendo
intatti geometria di gioco, collisioni e obiettivi.

`ring_minigame.odin` adatta l’unica simulazione `fight` alla shell. Il receipt
M8 conserva soltanto esito e pagamento, senza simulazione parallela. Le
regressioni verificano routing unico, assenza di ricompense dalla pratica,
un solo sblocco al ritorno, abbandono, sospensione e input ripresi senza
azioni ereditate. Gli strumenti M9 restano diagnostica esplicita: non sono
una seconda scelta di FPS/ring nel gioco. Non sono stati unificati i due
formati di profilo o modificati pulse, carte e combattimento della run.

Verifica: **1.028 test con e senza assert**, strict/vet e due build.
Smoke nelle finestre native per menu, tutte le sei prove, dispositivi M8,
ring/sblocco/ritorno Loot/stanza successiva e laboratori M9 con replay.
Il report M7 prima/dopo è identico byte per byte (4.023 byte). Le catture
usano bot e seed 7, senza registrare record o sblocchi di test.
Regressioni aggiuntive proteggono il mirror delle celle dell’atlante,
la presa su RB (B/Start appartengono alla shell) e il clic su Sfida extra,
che non deve attraversare la HUD fino alla board. Le due figure trasparenti
di ogni attore si compongono senza scrivere profondità: pareti e piattaforme
continuano a occultarle, mentre il bordo non può coprire la propria illustrazione.
Dopo questa correzione grafica sono stati ripetuti strict/vet, build, test FPS
e verifiche native di FPS e platform 3D.

Screenshot: `odin_pp_menu.png`, `odin_pp_ring.png`, `odin_pp_fps.png`,
`odin_pp_platform2d.png`, `odin_pp_platform3d.png`, `odin_pp_arena.png`,
`odin_pp_puzzle.png`. Le animazioni dei cutout usano pose e trasformazioni
a scatti dei disegni esistenti, non nuovi fotogrammi anatomici disegnati.
Restano da valutare in playtest umano difficoltà, pad e leggibilità alle
varie distanze; verifica nativa effettuata su macOS, non su Windows.


### Merge gameplay-tempo-ring-western — 15 ottobre 2026

Integrati i 22 commit del branch fino a `e3bac7b` sul `main` aggiornato
`a83dca8`, conservando il fix di avvio `4b90f7f` e la grafica gotica già
integrata. I cambi alle regole di azioni, status, carte e accesso al ring
sono quelli del branch; il merge non introduce un ulteriore ribilanciamento.
Le catture rigenerabili dei nuovi smoke sono escluse dal versionamento.

Validazione su macOS: **1.335 test con assert attivi e disattivati**, strict/vet
e due build tramite `scripts/check.sh`; smoke M7 su dieci preset, quattro
run terminali ripetute e otto cicli stress. Le prove native coprono menu,
Tesla/tag match/ritorno Loot/cambio stanza M8, evento Western con ricompensa
e l'intera Prova meccaniche, incluse Lazzo, Pinball, FPS temporaneo e pesca.
Lo smoke Mostra effetto verifica ingressi, chiusure, ridimensionamento e
ripresa della run, più otto film completi: Strike, Incendio, Pinball e First
Person Shooter al livello base e massimo, senza errori. Le misure a 60 FPS
rientrano nella soglia dello smoke; non è stata ripetuta la cattura di tutte
le altre carte né la variante piatta di questo smoke.
L'audit verifica inoltre gli asset incorporati e la completezza degli
atlanti e del manifest audio. Le verifiche Windows non sono state eseguite.


### Refactor mirati e selezione dei test — 15 ottobre 2026

Accorpate nove procedure di test: determinismo d4, compilazione delle carte
di flusso, FIFO Refocus costruito a mano, sessione puzzle, rivelazione dei dadi,
due microtest della sconfitta, snapshot dei raggi dei nemici e prova del bot
platform ora integrata con la raggiungibilità. Le aspettative ancora utili
sono nei test del comportamento reale. Non vengono eliminate le regressioni
su blocchi dell'input, orologi, pause, ownership, salvataggi o transizioni.

I refactor di produzione condividono la validazione delle carte fra preview
e compiler, la costruzione dei metadati degli eventi del mazzo, il picking
delle carte possedute in Shop/Rest, la geometria di caduta e picking delle
figure di carta, la dilatazione dei contorni, il caricamento/liberazione delle
texture e la base della camera del platform 3D. Restano distinti registrazione degli eventi e reazioni,
ordine degli errori, regole Classica/M7, animazioni living/flipbook e formati
delle texture. Il timing delle clip conserva le proprie differenze intenzionali.
Per i contorni, il confronto prima/dopo dei sei disegni (due guanti, AK, due
lampi e tracciante) produce **40.908 byte identici**; maschere e buffer temporanei
restano sullo stack, senza allocazioni per frame.

Con la toolchain e `-o:none` indicati sopra, la suite completa passa **1.326
test**, circa **72 secondi per esecuzione**, con assert attivi e disattivati;
passano anche strict/vet e le due build. La rapida passa **1.319 test in circa
27 secondi**, contro i 74–75 secondi della suite prima della selezione. Sono
tempi del runner su questo Mac, esclusa compilazione: la rapida riduce le
matrici, mentre la completa conserva tutti i seed e le simulazioni lunghe.
Verificati anche combinazione/ordine delle opzioni dello script shell e rifiuto
degli argomenti sconosciuti; il corrispondente PowerShell è aggiornato ma non
è stato eseguito su Windows.

Passano anche lo smoke M7 (dieci preset, replay e stress), la finestra del
platform 3D, lo smoke M8 (cast, trappola, Tesla, ring, loot e cambio stanza)
e Mostra effetto con gli ingressi Shop/Rest e quattro film completi
(Strike/Tesla al livello base e massimo). Catture e log della verifica sono
artefatti temporanei, non asset del gioco.


### Secondo lotto di refactor e selezione — 15 ottobre 2026

Accorpate altre **sei procedure**, portando la suite completa da 1.326 a
**1.320 test** e quella rapida da 1.319 a **1.313**. Catalogo, disponibilità
delle carte e ID stabili hanno un solo punto di verifica; i test degli effetti
reali e degli upgrade rimangono. Le tre forme degli attacchi ad area sono
verificate da una tabella con bersagli attesi indipendenti dalla preview.
Fuoco e blocco di ghiaccio condividono la tabella delle capacità, mantenendo
separate le prove di collisione, danno e persistenza. Shop verifica nello
stesso test mazzo parziale e pieno, paginazione, hover e copertura di tutte le
carte, senza duplicare l'intera procedura.

Per i dadi, la raggiungibilità di ogni faccia da d4 a d20 è verificata nella
primitiva; il wrapper delle carte mantiene tutte le combinazioni carta/livello
con quattro seed rappresentativi, **120 coppie di lanci invece di 7.680**.
Restano verificati ordine dei risultati, consumo del generatore e rifiuti
senza mutazioni. La selezione non elimina scenari di input, softlock, pause,
timeline, QTE, transizioni o salvataggi.

Quattro ordinamenti manuali degli ID usano ora `core:slice.sort` su snapshot
fissi, prima delle mutazioni: bersagli degli oggetti, esplosivi, cleanup dei
dispositivi e pianificazione dei nemici. Restano distinti gli ordinamenti
per distanza e quelli che associano ID e posizione. Il test esistente di fine
fight copre anche dispositivi in ordine di memoria invertito, verificando
l'ordine degli eventi e la conservazione del barile.

Living e flipbook condividono somma delle durate e ricerca del fotogramma;
conservano le rispettive normalizzazioni dei loop, che possono differire ai
confini in virgola mobile. Il confronto temporaneo con le implementazioni
precedenti ha verificato **219.857 risultati esatti su 262 clip**, con assert
attivi e disattivati. I due test permanenti degli adattatori includono ora
anche i confini temporali e le clip vuote o di durata zero. Il laboratorio
condivide ricerca/spawn dei nemici e cattura del targeting; i test dei menu
condividono solo gli helper geometrici indipendenti dal picking di produzione.

Validazione su macOS: suite completa **1.320/1.320** con assert attivi e
disattivati, circa **73/72 secondi**; rapida **1.313/1.313 in 27 secondi**.
Passano strict/vet e le due build. Il report deterministico M7, con dieci
preset, replay e stress, è identico byte per byte a quello precedente.
Passano nella finestra nativa platform 3D, M8 (cast, trappola, campo Tesla,
ring, loot e stanza successiva) e il laboratorio completo, inclusi Lazzo,
Pinball, FPS temporaneo, pesca e feedback audio. Controllate anche le catture
di combattimento, loot, nuova stanza, platform e targeting del Lazzo.
I tempi sono del runner, esclusa compilazione: questo lotto riduce soprattutto
la manutenzione delle duplicazioni, senza un ulteriore taglio sostanziale
dei tempi rispetto al primo. Le verifiche Windows restano da eseguire.


### Terzo lotto di refactor e selezione — 16 ottobre 2026

Shop e Rest condividono ora anche il disegno del mazzo posseduto: titolo,
paginazione, selezione e carta in hover disegnata per ultima. Validatori e
azioni dei due menu rimangono distinti. Trascinamento, click su una cella e
film di Mostra effetto usano la stessa costruzione del comando di targeting;
il polling conserva il mazzo di presentazione e la gestione della selezione,
mentre le regole di targeting restano nel gameplay. Rimossa anche la delega
superflua alla verifica del target spaziale.

Camera 2D, accelerazione del platformer, Arena e presentazione dei platform
riusano `tween.damp`, `tween.approach` e `tween.ease`, già presenti nell'engine.
Restano separati i loop dei minigiochi, hit-stop, ripresa dopo pausa e calcoli
con wrap angolare o precisione differente. Il confronto temporaneo con le
formule precedenti ha prodotto **101.751 risultati bit per bit identici**;
per Shop/Rest, **57.120 combinazioni** di mazzo, pagina, hover, selezione e
pulsanti producono le stesse chiamate di disegno nello stesso ordine.

Accorpate **quattro procedure di test**, conservando i casi: movimento valido
e rifiutato, Poison assorbito completamente o parzialmente dallo scudo, range
di targeting zero/minimo/massimo e pulsanti abilitati/disabilitati. Gli oracoli
rimangono espliciti; gli eventi di danno verificano anche l'assenza di duplicati
e il movimento rifiutato non produce effetti o eventi. La suite passa da
1.320 a **1.316 procedure complete**, da 1.313 a **1.309 rapide**. Il lotto
rimuove complessivamente **147 righe Odin**, senza nuovi test permanenti né
riduzioni delle matrici di seed o dei test di regressione temporali.

Validazione su macOS: **1.316 test con assert attivi e disattivati**, circa
73 secondi per passaggio; rapida **1.309 test in 27 secondi**, strict/vet e
due build superati. Il report M7 resta identico byte per byte al secondo lotto.
Passano gli smoke nativi di Arena, platform 2D/3D, M8 e Mostra effetto con
ingressi Shop/Rest, chiusura/ripartenza/ridimensionamento e **sei film completi**
(Strike, Guard e Tesla al livello base e massimo), 48 catture e zero errori.
Controllate visivamente anche le schermate dei tre minigiochi e dei due menu.
Per i film campione: 2.248 frame senza limite FPS, media 9,62 ms e percentile
99 di 14,12 ms; sono misure locali dello smoke, non un benchmark generale.
Windows non verificato. Screenshot, log e confronti temporanei restano fuori
dal repository.


### Refactor del codice di produzione — 16 ottobre 2026

Questo lotto riguarda le responsabilità e le regole del runtime:

- **Shop:** disponibilità dei pulsanti e comandi di acquisto condividono i
  controlli per carta, upgrade e rimozione. Restano invariati prezzi, priorità
  degli errori e preparazione della mutazione del mazzo prima dell'addebito.
- **Input dei menu:** `run_menu_input.odin` gestisce azioni e transizioni di
  Shop, Rest, Event e Treasure; la scena campiona input, hover e visibilità.
  Mouse e tastiera dello Shop usano lo stesso dispatcher. Conservate le
  differenze: lo Shop può eseguire più azioni nello stesso frame, mentre un
  click nei nodi speciali sostituisce la scelta della tastiera; il cambio
  pagina azzera la selezione prima di valutare un upgrade.
- **Colpi nemici:** attacco normale e colpo finale della carica condividono
  Riflesso, danno/reazioni, eventi e spinta M7. Puntamento, cancellazione,
  movimento della carica e conclusione dell'azione restano nei rispettivi
  flussi, preservando le differenze fra Classica e M7.
- **Collisioni:** `engine.sweep_body` ricerca il primo contatto per movimento
  e lancio nel ring. Il controller conserva scorrimento e depenetrazione;
  il lancio conserva traiettoria rettilinea e margine di arresto propri.
  La query non modifica il mondo e mantiene filtri e ordine dei contatti.
- **Presentazione:** il replay del mazzo è separato dalla timeline in
  `render/presentation_deck.odin`, con un controllo comune dei metadati
  carta/evento. Lazzo, critici e Riflesso condividono l'accesso alle cue
  bufferizzate, anche future, mantenendo foreground prima di world. Il
  disegno continua a scorrere soltanto le cue attive; restano i rollback
  delle transazioni e la separazione fra stato reale e presentazione.

Non cambiano bilanciamento, aspetto, catalogo o comportamento previsto.
I confronti temporanei con il codice precedente danno risultati identici per
52.020 movimenti e 47.685 traiettorie di lancio, 130.598 confronti Shop,
576 scenari di attacco Classica/M7, 31.360 transazioni di replay del mazzo e
12.672 query sui feedback. I probe sono stati rimossi dai sorgenti e
conservati fuori dal repository.

Nessun test eliminato in questo lotto: aggiunte tre regressioni sui contratti
condivisi (collisioni e due flussi di menu), ed esteso un test esistente per
distinguere cue future e attive. La suite comprende **1.319 procedure complete**
(**1.312** nel profilo rapido). Il codice di produzione cala di 45 righe
nette; la scena perde 134 righe e la timeline 159, ora collocate nei moduli
che gestiscono rispettivamente menu e replay del mazzo.

Validazione su macOS: **1.319/1.319 test con assert attivi e disattivati**,
strict/vet e build in entrambe le configurazioni superati. Il report M7
rimane identico byte per byte al terzo lotto. Passano gli smoke nativi di
ring, FPS, M8 e il laboratorio completo, inclusi colpi riflessi, critici,
Lazzo, Pinball, FPS temporaneo, pesca e feedback audio. M8 comprende cast,
trappola passiva, campo Tesla, loot e passaggio alla stanza successiva.
Passa anche Mostra effetto: ingressi Shop/Rest, chiusura, riavvio e resize,
sei film campione (Strike, Guard e Tesla al livello base e massimo),
48 catture e zero errori di timeline o dello smoke. Controllate visivamente
le catture dei due menu, ring, FPS, loot, nuova stanza e Lazzo.
Screenshot e log rimangono fuori dal repository. Windows resta da verificare.


### Secondo lotto sul codice di produzione — 16 ottobre 2026

Rest, Event e Treasure usano ora query di disponibilità del dominio `game`,
condivise con i comandi e richiamate direttamente da HUD, picking e input.
Le query controllano i vincoli locali senza copiare o validare l'intera run
per ogni pulsante; i comandi conservano validazione completa, stato temporaneo
e commit atomico. Rimangono distinti i risultati e le priorità degli errori,
la cura a salute piena, la seconda scelta gratuita di Blood Offering e la
reliquia del tesoro da risolvere prima di proseguire. Rimossi i controlli
paralleli dal renderer e accorpato il premio in oro secondario condiviso
da Healing Spring e Forgotten Armory.

I platform 2D/3D condividono l'aggiornamento di coyote time, jump buffer,
cooldown e avvio dash in un helper privato limitato ai due controller.
Struct, parametri e API restano invariati. Il contatto muro ricarica le dash
solo nel 2D; gravità, wall jump, integrazione e collisioni restano nei loro
controller. Non cambia l'ordine fra aggiornamento timer, avvio e consumo
della dash nel primo step.

La configurazione dello shader resin è unica per stanza, ologramma, scheda
personaggio, ring e dadi. Le modalità Board/Hologram/Model hanno valori
espliciti; i preset rimangono nelle scene. GLSL, gestione delle risorse,
guardie sullo shader assente e chiusura del pass sono invariati. Model
continua ad aggiornare solo camera, lanterna e modalità, conservando le
uniform della stanza che questa modalità non legge.

I confronti temporanei con la versione precedente danno risultati identici
su **432.000 step** dei controller (stato, collisioni ed eventi), **12.600
transazioni** dei nodi speciali e **3.000 stati validi** per la disponibilità
HUD. Il probe shader confronta **192 configurazioni** e **96 casi senza
shader**, con gli stessi valori e le stesse uniform modificate. I probe
rimangono fuori dal repository.

Aggiunte due regressioni: timer/refill/dash nei platform e una matrice di
25 limiti dei nodi speciali, inclusi overflow, salute, capienza, ID, upgrade
e fallimenti senza mutazioni. Nessun test eliminato: **1.321 procedure complete**
(**1.314** rapide), con **71 righe nette in meno nel codice di produzione**.

Validazione su macOS: `scripts/check.sh` completo superato, **1.321 test
con assert attivi e disattivati**, strict/vet e due build. Il report M7
resta identico al lotto precedente. Passano nella finestra nativa M8,
set dadi (sette modelli e quattro facce D4), ring, platform 2D/3D, Rest,
Event e Treasure. Passa anche l'intero smoke M7 view: QTE, ritmo indipendente
dei nemici, recupero, ologramma, feedback visivi, loot, stanza successiva,
reset della luce e quattro angoli della camera.

Su 62 catture comuni prima/dopo, **61 PNG sono identici byte per byte**,
compresi dadi, scheda personaggio, stanza e ologramma. Nel ring la cattura
in tempo reale mostra uno stato diverso dei combattenti e della relativa
barra HUD; tutti i pixel fuori da queste due aree sono identici. Controllate
visivamente anche le schermate dei due platform, del ring e dei dadi e il
menu Event. Log, screenshot e probe restano fuori dal repository; Windows
non verificato.


### Tesla, confini della scena e CI — 16 ottobre 2026

L'HUD Tesla usa una query locale che contiene rete, cooldown massimo,
candidato ring e disponibilità. Etichetta e pulsante condividono il risultato;
le condizioni di input del renderer restano separate dalle regole della rete.
`activate_tesla` sceglie ring o scarica sulla stessa rete appena interrogata.
I comandi non ricevono snapshot del renderer e non usano cache persistenti;
`begin_tesla_ring` e `activate_board_devices` mantengono la loro API. Geometria,
ordine dei bersagli, fuoco amico, cooldown, consumo delle quattro torri e costo
temporale restano invariati.

`main.odin` gestisce ora soltanto ingresso CLI e host (54 righe); il loop della
run resta in `roguelike_scene.odin` (878 righe). Input/esecuzione dei comandi,
startup, fixture/catture e lifecycle hanno quattro file con responsabilità
esplicite. Riavvio, ingresso nodo e completamento stanza ricevono la sessione
e mantengono i propri reset, report e ordine di rilascio delle risorse.
Non cambia il modello di ownership e non è stato introdotto un loop generico
comune a classico, M7 e minigiochi.

I confronti con lo stato precedente verificano **28.800 combinazioni Tesla**
(query, comandi, stato ed eventi) e **4.800 combinazioni HUD** senza differenze.
Per l'estrazione della scena, 52 dichiarazioni sono identiche e i corpi di
attach/update corrispondono espandendo i nuovi helper. Le regressioni esistenti
ora coprono anche preview Tesla superate da un cooldown e il percorso
timeline → ricompensa → Rest → nuova stanza → riavvio in classica e M7, con
input cancellato, profilo preservato e puntatori riconnessi. Il conteggio resta
**1.321 test completi / 1.314 rapidi**.

Validazione macOS con l'archivio ufficiale Odin fissato nella CI: script completo
superato, **1.321 test con assert attivi e disattivati**, strict/vet e due build.
Passano M7 headless e gli smoke nativi M8, launcher, Shop, Rest, Event, Treasure
e M7 view, compresi combattimento, ring, loot e cambio stanza. Il report M7 e
tutte le **62 catture confrontabili sono identici byte per byte** allo stato
precedente. Controllata visivamente anche la scena con i dispositivi Tesla.
Log, screenshot e probe rimangono fuori dal repository.

Il workflow macOS/Windows passa actionlint e i controlli di sintassi; checksum,
layout ed esecuzione dell'archivio macOS sono verificati. **Windows resta da
eseguire sul runner dopo la pubblicazione**: questo Mac non dispone del relativo
SDK, richiesto anche dal typecheck incrociato. La presenza del workflow non
equivale a una verifica Windows riuscita.

### Riduzione delle implementazioni parallele — 16 ottobre 2026

Rispetto a `dbb7208`, i sorgenti Odin passano da **138.796 a 136.555 righe**:
**2.112 righe di produzione e 129 di test in meno**. La conversione dei disegni
testuali in 40 PNG incorporati elimina 1.870 righe di produzione; è separazione
dei contenuti grafici dal codice, non riduzione della logica di gioco.
I PNG pesano complessivamente 12.509 byte e mantengono gli stessi pixel.

Rimossi i due sistemi inutilizzati di animazione loot/movimento precedenti alla
timeline, compresi i cinque test delle sole API obsolete. `Renderer` occupa
3.616 byte in meno. Le regressioni della timeline e del playback attivi restano.
Il materiale carta e i quad hanno un percorso condiviso in `engine/gfx`;
preview e compilazione delle carte condividono l'espansione dei destinatari.
Non cambiano regole, contenuti, ordine degli effetti o differenze Classic/M7.
Tre test dei disegni testuali sono convertiti in verifiche dei layout PNG;
una regressione comune copre alpha, silhouette e immagini non valide.

Validazione macOS: `scripts/check.sh` completo, **1.317 test con e senza assert**,
strict/vet e due build, usando il compilatore ufficiale fissato nella CI.
I confronti temporanei verificano 447.536 casi di targeting/compilazione,
2.848 casi di uniform/vertici/UV e 49 fogli colore/silhouette senza differenze.
Passano M7 headless, M8 e M7 view: combattimento, dispositivi, ring, loot e
stanza successiva. Il report stress e **59 catture M7/M8 sono identici byte per
byte**. Controllati avvio e rendering nativi dei sei minigiochi; le loro catture
a tempo reale non sono confronti deterministici. Passa anche Mostra effetto:
ingressi, resize, ripresa e sei film completi (Strike, Guard, Tesla base/max),
con zero errori e **101 catture identiche**. I probe restano fuori repo.
La verifica Windows resta da eseguire sul runner CI.

### Ritiro della modalità classica e della vista piatta — 16 ottobre 2026

Il gioco principale ha ora un solo runtime tattico 3D. Restano M8/M9,
i sei minigiochi, il ring della run, la scena a blocchi, gli sprite, la fog,
il cast, i QTE e l'ologramma. `--m7`, `--m8` e `--m9` sono alias compatibili;
`--classic`, `--flat` e gli smoke esclusivi ritirati producono un errore esplicito.
La proiezione ortografica 3D resta disponibile.

Misura rispetto allo stato immediatamente precedente a questo intervento
(incluso il refactor della sezione precedente, non rispetto a HEAD):

| Sorgenti Odin | Prima | Dopo | Riduzione netta |
|---|---:|---:|---:|
| Produzione, esclusi i file `_test.odin` | 88.264 | 83.966 | 4.298 |
| Test | 48.291 | 47.402 | 889 |
| Totale | 136.555 | 131.368 | 5.187 |
| Procedure di test | 1.317 | 1.285 | 32 |

Questa riduzione ritira implementazioni: catalogo alternativo, risposta nemica
sincrona, planner/BFS classico, HUD, picking e disegno della board 2D, camera
isometrica, vecchio D6 e smoke dedicati. Non sposta sorgenti fuori dal conteggio.
Circa 94 righe di replay diagnostico sono trasferite dalla produzione ai test
in questo stesso conteggio; le immagini PNG appartengono al refactor precedente.
Il catalogo unico contiene direttamente le 44 definizioni del gioco attuale;
preview, carte, menu e upgrade non ricevono più un selettore di modalità.

Rimossi anche i report di pulse e pesca che il runtime corrente lasciava vuoti:
`Card_Play_Report` passa da 193.472 a 96.760 byte e `Refocus_Report` da 97.448 a
448 byte sulla toolchain macOS ARM64 verificata. È una riduzione delle strutture
e delle copie potenziali, non una misura degli FPS. `advance_combat_pulse` resta
soltanto un helper dei test dei risolutori; il runtime usa il clock corrente.

Le regressioni comuni sono migrate a cast, beat e continuazioni espliciti;
quelle esclusive delle regole ritirate sono eliminate. La matrice generale
esamina i 4.096 seed precedenti e materializza 432 combinazioni distinte di nodo,
profondità e transizione fra famiglie, asserendone la copertura. Le matrici di
progressione/spawn e i golden vector restano separati. Lo smoke headless di
playtest avanza ora davvero venti decisioni, osserva il mondo e completa anche
l'ultima azione; una regressione copre QTE, recupero e stun.

I confronti temporanei, fuori repo, verificano senza differenze le 44 carte,
i testi a ogni upgrade, 16.000 set di offerte e 3.200 frame di combattimento
con eventi, deck, posizioni, intenti, clock e QTE. Le due configurazioni del
clock confrontate sono quelle delle sonde e del gioco reale.

Validazione macOS con il compilatore ufficiale della CI: `scripts/check.sh`
completo, **1.285 test con assert e 1.285 senza**, strict/vet e due build.
Passano M7 headless, M8 e M7 view, inclusi dispositivi, ring, combattimento,
loot e stanza successiva; avvio/rendering verificati per tutti i sei minigiochi.
**57 delle 59 catture M7/M8 sono identiche byte per byte**: le sole differenze
sono le offerte di Reward/Shop nelle vecchie fixture, che inizializzavano il
catalogo classico prima di attivare la vista tattica. L'oracle delle offerte
conferma che il pool della run tattica conserva risultati e RNG.
Passa anche il set dei sette dadi (D4/D6/D8/D10/D100/D12/D20). Mostra effetto
completa i sei film controllati senza eventi mancanti né errori della timeline;
le **101 catture sono identiche** al binario precedente. Resta un limite nella
misura nativa del frame pacing: 76/1.980 frame oltre 25 ms, contro la soglia
del 2%. Ripetuto nelle stesse condizioni, anche il binario precedente supera
la soglia (69/1.980). Non è dimostrata una regressione del renderer, ma questa
verifica delle prestazioni non è verde; soglie e codice non sono stati alterati.
La prova estesa delle meccaniche passa integralmente, compresi lazzo, Pinball,
FPS e pesca, su una copia temporanea con il solo limite FPS/VSYNC disattivato:
restano invariati passi di simulazione, fotogrammi, controlli e catture.
L'esecuzione ordinaria precedente era stata interrotta dal limite esterno di
360 secondi, senza errori funzionali; il probe completo è una verifica del
comportamento e del disegno, non delle prestazioni.
La verifica Windows resta affidata al runner CI.

### M7G: lavoro restante dopo il prototipo

Restano da svolgere le revisioni del codice e i playtest umani concordati:

- confrontare 15/20 secondi e 3×3/5×5/7×7 separatamente, poi insieme;
- valutare la leggibilità di minacce, carte e QTE, compreso l'uso dell'ologramma
  mentre il timer scorre e la durata del parry;
- misurare danni ed efficacia del movimento nel recupero fisso di un secondo,
  per tararne la durata senza reintrodurre blocchi crescenti;
- provare il nuovo ritmo dei bombaroli (preparazione, miccia 3, danno 3,
  recupero 2, limite condiviso 1), le spinte dei bruti e i barili accesi dai boss;
- valutare due nemici aggiuntivi, vista 7×7/9×9 e recupero di due pulse della
  schivata; confrontare la frequenza dei QTE e il valore di Afterimage;
- verificare il valore delle carte a lungo raggio con fog e delle combinazioni
  di pesca/creazione dentro la finestra temporale;
- decidere eventuali correzioni a progressione, costi, durata delle finestre
  e gestione dei rimpiazzi sulle evidenze delle run.

### Criteri per gli incrementi successivi

Per carte e geometrie: preview e compilazione devono concordare, zone e ID
restare validi, timeline seguire le mutazioni e test coprire composizione e
limiti. Per encounter: intenti committed e deterministici, geometria condivisa,
simulazioni headless con morti, blocchi, spawn e cambi di fase senza deadlock
o overflow. Per persistenza: save versionati con round trip, migrazioni e
corruzione diagnosticabili, replay dei comandi con stesso risultato finale.
Velocità o disattivazione dei feedback non devono cambiare il gameplay.

Restano fuori dallo scope attuale: Chest con stato/interazione e premio
one-shot; ulteriori status e binding degli oggetti; status persistenti fra
stanze, immunità e tipi di danno; cataloghi caricati da file; reroll, sconti
e vendita di carte; eventi concatenati;
animazioni complete fra pile, direzioni dei personaggi e raggruppamento
generale di azioni indipendenti. Audio, illustrazioni definitive, particelle,
hit stop e screen shake ulteriori appartengono agli incrementi di game feel.
Il fuoco con crescita e scadenza di Incendio e gli sblocchi persistenti delle
sfide sono già implementati; non fanno più parte del backlog storico.

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
- mantenere check, test e link in CI, aggiornando insieme toolchain e checksum.

Le nuove nozioni e decisioni vanno aggiornate nella sezione pertinente di questo
README, mantenendo un unico riferimento e distinguendo implementato e pianificato.
