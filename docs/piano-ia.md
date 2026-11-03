[← Odin PP](../README.md)

# Piano di lavoro: la carta «IA», il Nido di ragni, la Regina e il Lanciafiamme

Scritto il 3 novembre 2026 sul ramo `piano-ia`, partito da `piano-napoli` (commit `6ea365b`, uguale a
`origin/piano-napoli`). È lo stato più nuovo del gioco: le carte in prima persona, il succo dei colpi, le frecce
degli arcieri e le bombe dei bombaroli come proiettili veri, «Benvenuti a Napoli» nel gioco vero. Nessuno di questi
rami è ancora unito a `main`.

Il documento raccoglie le richieste dell'utente dello stesso giorno (parola per parola nell'appendice A). La prima è
una carta **«IA»**, cioè intelligenza artificiale. Da quando la giochi, per **30 secondi** ti consiglia sempre **la
mossa migliore** da fare in quel momento della partita:

1. se è meglio **muoversi**, ti illumina la **casella dove andare**: per evitare nemici e attacchi, o per metterti
   dove poi riesci a colpire, o in una posizione tattica;
2. se è meglio **giocare una carta**, ti illumina **la carta**; quando ce l'hai in mano ti illumina **la casella dove
   giocarla** (un nemico, una casella a terra, te stesso: dipende dalla carta);
3. se è meglio **colpire a mano** (il passo contro un nemico), ti illumina **la casella del nemico**.

La carta è **sempre in cerca** della mossa migliore. Il gioco è dinamico, quindi il calcolo è **veloce e continuo**;
guarda **qualche passo avanti**; e pensa anche al fatto che il giocatore può **non seguire** il consiglio e fare di
testa sua. È un'intelligenza superiore che ti dice sempre la prossima mossa giusta.

Lo stesso giorno l'utente ha aggiunto al piano **altre tre carte** e **una regola per sempre**:
- il **Nido di ragni**: lo posi a terra e per 20 secondi fa uscire dei ragnetti intangibili, che corrono dal nemico più
  vicino, gli danno un morso piccolo e muoiono. I nemici lo possono colpire, e ogni colpo gli toglie dei secondi;
- la **Regina**: un pezzo degli scacchi che posi sulla griglia e che nessuno può distruggere. Per 20 secondi guarda
  lungo le sue linee (le mosse della regina degli scacchi) e, appena un nemico ci entra, corre fino a lui e lo colpisce;
- il **Lanciafiamme**: per 20 secondi il Viandante impugna un lanciafiamme e non usa altre carte né colpi a mano.
  Spara tenendo premuto il tasto sinistro, guarda sempre verso il mouse e la fiamma lo segue, restando un attimo
  indietro quando gira. Ogni nemico bruciato prende danno al massimo una volta ogni 2 secondi, più uno stack di
  bruciatura, e intanto il Viandante cammina come sempre;
- la **regola per sempre**: da quando la IA esiste, ogni cosa nuova del gioco, fatta da questo PC o da altri, con
  Claude, con Codex o con un'altra IA, aggiorna anche la IA, così ha sempre tutte le informazioni per trovare la mossa
  migliore (sezione «La regola per sempre»).

Le fasi si eseguono **una alla volta, solo su comando dell'utente** («Esegui la Fase N»). All'inizio di ogni fase si
fanno le domande che servono; poi si va avanti da soli fino a fine fase, senza fermarsi a chiedere «passo
successivo?». Quando serve sapere come si fa una cosa, o come la fa un altro gioco, **si cerca su internet**. Tutto
si prova prima nel **laboratorio** (PROVA MECCANICHE) e passa al gioco vero solo nell'ultima fase. Grafica e suoni
fatti da codice. Si sceglie sempre la massima qualità e le prestazioni migliori. Ogni cambio a una carta si annota in
[registro-carte.md](registro-carte.md). Nei **check di ogni fase si prova solo quello che la fase tocca** (i test del
codice toccato e di chi lo usa, `odin check src -vet -strict-style`, l'atto del laboratorio della carta; il
benchmark solo se la fase tocca il fotogramma); la **verifica completa** (`scripts/check.ps1`, prova completa del
laboratorio, benchmark completo) si fa **solo nell'ultima fase**. I residui dei test (le catture in `build/captures`,
i file di prova) si cancellano a fine fase; il salvataggio vero in `AppData\Local\OdinPP` non si tocca mai. Sono
regole dell'utente e valgono per tutto il piano.

Parole del documento:
- **Consiglio:** quello che la IA mostra: la prossima mossa migliore.
- **Mossa:** un passo, un colpo a mano, una schivata, una carta su un bersaglio, una difesa, oppure aspettare.
- **Ricerca:** il calcolo che prova tante mosse di fila e sceglie la migliore.
- **Copia di prova:** una copia della stanza in cui la ricerca prova le mosse. La stanza vera non si tocca mai.
- **Radice:** la situazione da cui parte la ricerca.
- **Nodo:** una mossa provata nella copia di prova. Il **budget** della ricerca si conta in nodi, non in millisecondi.
- **Orizzonte:** quanti secondi del mondo la ricerca guarda avanti.
- **Thread:** un secondo «filo» di calcolo, che gira su un altro core del processore accanto al gioco.
- **Pensare in anticipo** (in inglese *pondering*): la ricerca prepara la risposta anche per le mosse che il consiglio
  non dice, così se fai di testa tua il consiglio nuovo è già pronto.
- **Battito:** un secondo del mondo; i nemici agiscono sui battiti.
- **Stato della partita:** quanto manca alla fine della run o della spedizione, e le cure che ci sono vicino.
- **Nido** e **ragnetti:** l'oggetto a terra del Nido di ragni e i ragnetti che fa uscire.
- **Linea:** una delle 8 direzioni in cui si muove la regina degli scacchi (in orizzontale, in verticale e in
  diagonale), lunga quanto la stanza.
- **Scia della fiamma:** quando il lanciafiamme gira, la fiamma già uscita continua dritta dove andava e resta un
  attimo indietro, come l'acqua di una canna che si sposta.

## Decisioni dell'utente (3 novembre 2026)

### La carta IA

| Domanda | Risposta |
|---|---|
| Costo e rarità | **Rara, 2 energia** (prezzo 8 nel negozio, peso 60 nelle offerte, 50 in spedizione): resta 1 energia per giocare subito la carta che la IA consiglia |
| Durata e potenziamenti | **30 s del mondo, +3 s a potenziamento**, fino a 5 potenziamenti come le carte in prima persona (al massimo 45 s); i secondi si fermano quando il mondo è fermo (dadi, scene) |
| Giocata critica (sul tick) | **+5 s** |
| Dove parte | **Solo laboratorio** fino all'ultima fase; lì si decide se entra nel gioco vero |
| Che cos'è la «mossa migliore» | **Equilibrata:** prima non morire, poi non prendere colpi (1 di vita persa pesa come 3 danni fatti), poi uccidere (un nemico ucciso vale come 10 danni), poi la posizione. **Le carte:** se una carta serve per evitare danni o per uccidere più in fretta o fare più danni, la IA non pensa a «sprecarla»; **a parità di danni e di utilità consiglia la mossa senza carta**. **Conta lo stato della partita:** più il giocatore è vicino a finire la run (meno nemici sulla mappa, meno luoghi da visitare), più la IA diventa **leggermente più aggressiva**, perché è più difficile perdere tanta vita e serve meno risparmiare carte e risorse; diventa un po' più aggressiva anche se **vicino c'è una cura**, anche fuori dal combattimento |
| Cosa sa la IA | **Tutto tranne i risultati dei dadi:** i nemici nella nebbia, le carte che pescherai e il loro ordine, i nemici sulla mappa; i dadi li tratta come incerti |
| Cosa mette nel calcolo | **Carte in mano e carte che vengono dopo, energia, tempi delle azioni, difesa a tasti, nemici sulla mappa, strutture vicine come la fontana** (per sapere quando essere più aggressiva; la fontana oggi non cura, ma la FONTE delle spedizioni sì: vedi sotto). **Non** il battito critico: la IA non ti dice di aspettare il tick |
| Durante le viste (prima persona, bastone, nonno) | **La IA si ferma coi suoi secondi:** niente consigli; i secondi ripartono quando la vista finisce |
| Cosa si vede | **La prossima mossa e una parola** breve sopra il Viandante: VAI, SCHIVA, COLPISCI, CARTA, DIFENDI, ASPETTA |
| Se fai di testa tua | **Ricalcola e avvisa se era pericolosa:** il consiglio nuovo subito e, per mezzo secondo, un **«!» rosso** con la vita che rischi |
| Colori | **Un colore solo, il ciano, con segni diversi:** impronta per il passo, mirino per il colpo a mano, cornice per la carta e per la sua casella |
| Le cure che conta | **Tutte le cure vere**, carte e altre fonti, **tranne la Canna da pesca** (e quindi anche il «Cibo pescato» che dà) |
| Film «Mostra effetto» | **Una scena con i tre consigli:** il passo per schivare un colpo annunciato, il colpo a mano, la carta con la sua casella |
| Suoni | **Da codice:** l'accensione della carta, un «tic» leggerissimo quando il consiglio cambia, un suono breve per l'avviso di pericolo |
| Icona e sigla | **Un cervello di circuiti** (metà con le pieghe, metà con le piste di circuito), sigla **IA** |

Decisioni prese **per regola**, senza domanda. La regola dell'utente è «sempre la massima qualità e le massime
prestazioni»:
- **Il calcolo gira su un thread a parte**, su un altro core. Il portatile ha un i7-11800H con 8 core e 16 thread, e il
  gioco ne usa uno solo. Così il gioco non perde fotogrammi e la ricerca ha a disposizione tutto un core. La stessa
  ricerca, fatta a pezzi dentro il fotogramma, serve per i test, per il film e come riserva.
- **L'orizzonte è il più lungo possibile.** La ricerca guarda almeno **3 secondi del mondo**, cioè l'avviso più breve
  (l'inseguitore avvisa 3 s prima del colpo). Poi va più avanti finché ha tempo, fino a **6 s**, che coprono anche gli
  avvisi più lunghi (5 s per bruto, bombarolo e demolitore) e un passo in più. I numeri giusti li danno le misure della
  Fase 2.

Note sulle decisioni:
- **«Sa tutto tranne i dadi».** La copia di prova ha i nemici veri (anche quelli nella nebbia) e il mazzo vero, quindi
  anche l'ordine delle pescate. Per i dadi, quando il dado è uno solo (dal d4 al d20) la ricerca prova **ogni faccia**,
  tutte con lo stesso peso; quando i dadi sono di più, fa la media di qualche tiro di prova, sempre lo stesso (vedi
  «Come resta deterministica»).
- **Il battito critico non è nel calcolo.** La ricerca considera «normale» ogni tua azione. Se colpisci sul tick e fai
  una critica, la situazione cambia e la IA ricalcola, come per qualunque altro cambio.
- **I numeri dei pesi** (3 a 1 per la vita, 10 per un'uccisione, e quanto scendono verso la fine) sono una proposta.
  Si confermano all'inizio della Fase 2 e della Fase 6, e si ritoccano dopo la prova dell'utente.

### Le due carte nuove, la fontana e la regola per sempre

| Domanda | Risposta |
|---|---|
| Le carte nuove | **Nido di ragni** e **Regina**, nel piano dopo le fasi di laboratorio della IA (Fasi 9-12); poi il Lanciafiamme (Fasi 13-14) e il gioco vero (Fase 15) |
| Costo e rarità | **Nido di ragni: non comune, 2 energia**, come il Cannone (prezzo 6, peso 70, 40 in spedizione). **Regina: rara, 3 energia**, come il Buco Nero (prezzo 8, peso 60, 60 in spedizione) |
| Il nido e i nemici | **Un nemico che ha il nido accanto e non ha te accanto lo colpisce:** il nido fa anche un po' da esca. Il nido non ha una vita a numeri: **ogni colpo gli toglie gli stessi secondi**, qualunque colpo e di qualunque nemico; a zero secondi il nido sparisce |
| I ragnetti | **Camminano attorno ai muri** e attraversano nemici e Viandante (sono intangibili), 4 caselle al secondo; un morso piccolo al nemico più vicino, poi muoiono, senza esplodere |
| Le linee della Regina | **Si fermano a muri, coperture, oggetti e corpi, come i pezzi degli scacchi:** il primo nemico su una linea è quello che può raggiungere. Fra più nemici arrivati insieme sceglie il più vicino |
| La Regina e il passo | **Occupa la sua casella**, come un pezzo: chi vuole passare le gira attorno. Nessuno la può colpire né distruggere |
| Nomi | **«Nido di ragni»** («Nido» da solo si confonderebbe col NIDO dei luoghi delle spedizioni) e **«Regina»** |
| La fontana | **Niente fase per la fontana.** L'utente l'aveva chiesta pensando che nel gioco non ci fosse nessuna fonte che cura; nelle spedizioni invece la **FONTE** cura già (+16 vita, una volta) e c'è il **Kit di riparazione** (+12). La IA conta loro e tutte le altre cure vere |
| La regola per sempre | Da quando la IA esiste, **ogni cosa nuova del gioco aggiorna anche la IA**, da questo PC o da altri, con Claude, con Codex o con altre IA. È scritta qui, in [sviluppo.md](sviluppo.md), in `AGENTS.md` (che leggono Codex e gli altri agenti) e in `CLAUDE.md` (che legge Claude Code), e **il codice stesso la controlla** |

### I numeri scelti da Claude (il bilanciamento chiesto dall'utente)

| Cosa | Numero | Perché |
|---|---|---|
| Durata del nido | **20 s** del mondo (scelta dell'utente) | — |
| Ragnetti | il primo **subito**, poi **uno ogni 2 s**: 10 in tutto, se nessuno tocca il nido | un ritmo che si vede bene, un ragnetto ogni due battiti |
| Morso | **2 danni** (+1 a potenziamento, 2 potenziamenti come il Cannone; sul tick 4, con la stessa regola dei danni critici del Cannone) | «poco danno», quanto un colpo a mano del Viandante nel laboratorio; in tutto circa 20 danni, 1 al secondo, sempre a segno |
| Secondi tolti a ogni colpo | **3 s** | un inseguitore che colpisce il nido ogni 3 s lo fa durare circa la metà (10 s invece di 20), ma intanto quei colpi non arrivano a te; con due nemici attorno dura circa 7 s |
| Nidi insieme | al massimo **2**, come i cannoni | — |
| Durata della Regina | **20 s**: l'idea dell'utente, tenuta | — |
| Colpo della Regina | **4 danni** (+1 a potenziamento, 2 potenziamenti; sul tick 6) | un inseguitore (12 di vita) cade in 3 colpi |
| Ritmo della Regina | il primo colpo **appena** un nemico entra in una linea, poi **uno ogni 2 s** | al massimo 10 colpi, 40 danni: 2 al secondo come il Cannone, ma sempre a segno e indistruttibile, per questo è rara e costa 3 energia |
| Regine insieme | **una** | — |
| Dove si posano | come il Cannone: una casella libera da 1 a 3 caselle di distanza, in vista | — |

### Il Lanciafiamme

| Domanda | Risposta |
|---|---|
| Che cosa fa | Il Viandante **impugna un lanciafiamme per 20 s**: finché ce l'ha **non usa altre carte e non colpisce a mano**. Spara **tenendo premuto il tasto sinistro** |
| Il danno | Lo stesso nemico si può bruciare di continuo, ma prende danno **al massimo una volta ogni 2 s**; a ogni colpo prende anche **uno stack di bruciatura**. La fiamma può prendere più nemici insieme |
| La mira | Il Viandante **guarda sempre verso il mouse** e ruota di continuo per puntarlo; la fiamma esce dal lanciafiamme e segue la sua rotazione |
| La scia | Quando la fiamma si sposta, **resta per qualche fotogramma dov'era prima**, per sembrare più vera |
| Il movimento | **Quello di sempre:** i passi sulle caselle, anche mentre spara |
| Costo e rarità | **Rara, 3 energia**, come le carte in prima persona e Napoli (prezzo 8, peso 60, 60 in spedizione) |
| Danno e portata | **3 danni a colpo, fiamma lunga 3 caselle** |
| La IA intanto | **Si ferma, come nelle viste:** niente consigli, e i suoi secondi si fermano finché dura il lanciafiamme. La IA però conosce la carta, per consigliare quando giocarla (regola per sempre) |
| Cosa ferma la fiamma | **Muri e coperture** la fermano; passa sopra i **muretti bassi**, come la vista. **Accende anche barili e terreno:** i barili esplodono, il ghiaccio si scioglie, a terra resta il fuoco dell'Incendio |

## La regola per sempre: la IA conosce tutto il gioco

Decisa dall'utente il 3 novembre 2026 (le sue parole sono nell'appendice A). Vale **da quando la IA esiste nel
codice**, per sempre, per qualunque lavoro: fatto su questo PC o su un altro, da Claude, da Codex o da un'altra IA.

> Ogni volta che nel gioco si aggiunge o si cambia qualcosa, si aggiorna anche la IA, così ha sempre tutte le
> informazioni per trovare la mossa migliore.

**Cosa conta come «cosa nuova del gioco»:** una carta, un effetto, uno stato, un nemico, un oggetto della griglia, una
struttura, un tipo di casella o di terreno, un posto o un bioma della spedizione, un nodo della mappa della run, un
oggetto dello zaino, un comando del giocatore, una regola del combattimento.

**Cosa vuol dire «aggiornare la IA»:**
1. la copia di prova copia anche lo stato nuovo (un campo nuovo della stanza, del giocatore, di un nemico, di un
   oggetto o del livello);
2. la IA sa **usare** la cosa nuova: le sue mosse, per esempio una carta coi suoi bersagli buoni, o un comando nuovo;
3. la IA sa **quanto vale**, anche oltre l'orizzonte: i secondi che restano a un oggetto, uno stato che farà danno
   dopo, una cura che arriverà;
4. il **contesto** la conosce: un posto nuovo dice se cura e quanto, se è pericoloso, se conta per il progresso;
5. almeno **una situazione di prova** (un puzzle) mostra che la IA la usa bene; cose simili possono dividerla;
6. una riga nel [registro delle carte](registro-carte.md) (o nel CHANGELOG, se non è una carta) dice «IA aggiornata».

**Come il gioco lo controlla da solo**, anche quando chi scrive il codice non ha letto questa regola:
- **Non compila.** La IA ha una tabella per ogni elenco del gioco:
  - nel consigliere: carte (`[Card_Id]`), effetti (`Effect_Kind`), stati (`Status_Kind`), nemici
    (`[Enemy_Archetype]`), oggetti della griglia (`[Grid_Object_Kind]`), strutture (`level.Structure_Id`), caselle
    (`level.Tile_Kind`);
  - nel pilota e nel contesto (pacchetto `run`): i comandi del giocatore (`Gameplay_Command_Kind`), i posti delle
    spedizioni (`Site_Kind`), i nodi della run (`Node_Kind`), i biomi (`campaign.Biome`), gli oggetti dello zaino
    (`campaign.Item_Kind`).

  In Odin una tabella `[Elenco]Cosa` scritta per intero, o uno `switch` su un elenco senza `#partial`, non compila se
  manca una voce: è lo stesso trucco che usano già `CARD_DEFINITIONS` e i film di «Mostra effetto». Quindi una carta
  nuova senza la sua voce nella IA blocca la compilazione.
- **I test falliscono:**
  - un test elenca i campi di `Room`, `Player`, `Enemy`, `Grid_Object` e `level.Level` (con `core:reflect`) e fallisce
    se ne compare uno che la copia non conosce;
  - il test di equivalenza (copia contro gioco vero, Fase 1) fallisce se una regola nuova fa qualcosa che la copia non
    rifà uguale;
  - ogni carta della tabella deve avere il suo puzzle.
- **Il controllo sul server** (`.github/workflows/check.yml`, a ogni pull request e a ogni push su `main`) fa girare
  gli stessi controlli, chiunque abbia scritto il codice.
- **Le istruzioni per gli agenti:** `AGENTS.md` nella cartella del gioco (il formato aperto che leggono Codex, Jules,
  Cursor, Aider, Zed e altri), `CLAUDE.md` che lo importa (Claude Code legge `CLAUDE.md`, non `AGENTS.md`), e la regola
  in [sviluppo.md](sviluppo.md).

**Finché la IA non c'è ancora,** ogni fase della IA comincia guardando cosa è stato aggiunto al gioco dal commit di
partenza (anche dagli altri rami, quando arrivano) e lo mette nelle tabelle. Dagli altri PC la regola arriva quando il
ramo `piano-ia` va sul server (push solo su richiesta dell'utente) e viene unito; il controllo «non compila» scatta
comunque nel momento in cui i rami si uniscono.

## Stato delle fasi

| Fase | Contenuto | Dipende da | Stato | Commit |
|---|---|---|---|---|
| 0 | Base: la carta, i suoi secondi, l'arena del laboratorio; punto di partenza | — | Da fare | — |
| 1 | La copia di prova e il simulatore; il controllo dei campi (regola per sempre) | 0 | Da fare | — |
| 2 | La ricerca: passi, colpi a mano, schivate, attesa; i pesi; segni provvisori; le tabelle di comandi e nemici | 1 | Da fare | — |
| 3 | Le carte nella ricerca: mano, energia, mira, pescate future, dadi; le tabelle di carte, effetti e stati | 2 | Da fare | — |
| 4 | Il thread: calcolo continuo su un altro core, pensare in anticipo, ricalcolo immediato | 3 | Da fare | — |
| 5 | Le indicazioni vere: segni ciano, parole, carta e casella, difesa, avviso di pericolo | 4 | Da fare | — |
| 6 | Lo stato della partita: progresso, nemici sulla mappa, cure vere, aggressività; le tabelle di posti e zaino | 5 | Da fare | — |
| 7 | I casi speciali: Ombra, Lazzo, Pinball, Dinosauro, Napoli, piani e ascensori, mappe grandi; le tabelle di oggetti e caselle | 6 | Da fare | — |
| 8 | Aspetto e suoni della IA: icona, conto alla rovescia, accensione, suoni da codice | 5 | Da fare | — |
| 9 | Nido di ragni: regole e prototipo nel laboratorio; la IA lo conosce | 7 | Da fare | — |
| 10 | Nido di ragni: aspetto e suoni | 9 | Da fare | — |
| 11 | Regina: regole e prototipo nel laboratorio; la IA la conosce | 7 | Da fare | — |
| 12 | Regina: aspetto e suoni | 11 | Da fare | — |
| 13 | Lanciafiamme: regole e prototipo nel laboratorio; la IA lo conosce | 7 | Da fare | — |
| 14 | Lanciafiamme: aspetto e suoni | 13 | Da fare | — |
| 15 | Nel gioco vero: le quattro carte, «Mostra effetto», salvataggi, verifica completa, prova con l'utente | 8, 10, 12, 14 | Da fare | — |

## Come funziona oggi (punto di partenza)

- **L'orologio del combattimento** ([tactical_clock.odin](../src/game/tactical_clock.odin),
  [tactical.odin](../src/game/tactical.odin)). Il mondo batte ogni secondo (`TACTICAL_WORLD_BEAT_SECONDS`). Nel gioco
  come si gioca (`GAME_TACTICAL_CONFIG`: `timed_actions` e `windowless`) non c'è più la finestra a tempo: le azioni del
  giocatore durano il loro prezzo in tempo vero e intanto il mondo corre. `tactical_tick` riceve i secondi del
  fotogramma e `tactical_advance_clock` li somma; ogni secondo intero mette in coda un battito, che il controllore
  risolve con `continue_tactical_pulse`. L'ordine è sempre lo stesso: prima le frecce e le bombe in volo, poi
  esplosivi, stanza, Marley, cannoni, cavalcatura, Napoli, e infine i nemici in ordine di numero, uno per chiamata.
- **I prezzi delle azioni** ([tactical_action_cost.odin](../src/game/tactical_action_cost.odin)): passo
  `TACTICAL_MOVE_SECONDS` 0,8 s, colpo a mano e attesa 1 s, schivata 1 s, riordino della mano 2 s, tutti divisi per
  `TACTICAL_PLAYER_PACE` (2). Nel gioco, quindi, un passo dura 0,4 s e un colpo 0,5 s. Il lancio di una carta dura da
  0,15 a 0,6 s (`tactical_card_cast_seconds`, dal `time_cost` della carta: `tactical_card_time_cost`). Finché
  un'azione dura, `action_remaining` è sopra zero e il corpo è occupato.
- **Cosa si può fare e quando** ([tactical_policy.odin](../src/game/tactical_policy.odin)): `tactical_control_allowed`
  decide per azioni, passi, carte, ombra e prima persona (`tactical_allows_action`, `tactical_allows_movement`,
  `tactical_allows_cards`). Durante la difesa a tasti e mentre un battito si risolve il mondo è fermo.
- **I nemici** ([enemy_intent.odin](../src/game/enemy_intent.odin),
  [enemy_tactical_ai.odin](../src/game/enemy_tactical_ai.odin)). Ogni nemico ha:
  - un'intenzione (`Enemy_Intent`): il tipo, il percorso, fino a 16 caselle minacciate (`threatened_cells`), il danno,
    il battito previsto (`planned_pulse`);
  - un conto alla rovescia (`tactical_cooldown`). Un inseguitore avvisa 3 s prima; arciere e custode 4 s; bruto,
    bombarolo e demolitore 5 s (`tactical_enemy_base_seconds`). Il recupero e un colpo già caricato prendono 1 s, e il
    Rallentamento aggiunge secondi (`tactical_schedule_enemy`).

  L'intelligenza dei nemici **non usa numeri a caso**: pianifica in ordine di numero (`enemy_ids_in_planning_order`) su
  un campo di distanze (`rebuild_tactical_enemy_distances`). Dalla stessa situazione, quindi, i nemici fanno sempre la
  stessa cosa.
- **I nemici contro gli oggetti.** Un'intenzione può mirare a un oggetto invece che al giocatore
  (`Enemy_Intent.target_object`): oggi lo fa il demolitore coi barili (`plan_tactical_bomber`), e
  `resolve_enemy_intents` colpisce l'oggetto. Le strutture posate dal giocatore prendono i colpi che passano vicino
  (`strike_structures`). È la strada per il nido che fa da esca.
- **La difesa a tasti** (`offer_defense_qte` in [tactical.odin](../src/game/tactical.odin)). Quando un colpo sta per
  prenderti puoi difenderti se hai:
  - uno scudo, per la parata (`Block`, `Parry`);
  - le spine contro un arciere (`Deflect`);
  - la schivata pronta (`Dodge`).

  Il mondo si ferma 1,2 s (`qte_seconds`) e scegli la difesa; la parata lascia solo 0,45 s. Non c'è con i pugni o con
  la spada, seduti alla tavolata, contro le frecce, con Riflesso o con lo Stegosauro.
- **I comandi del giocatore** ([gameplay_runtime.odin](../src/run/gameplay_runtime.odin)). Ogni cosa che il giocatore
  fa è un `Gameplay_Command` (Move, Dodge, Wait, Play_Card, Defense, QTE_Key…), eseguito da `execute_gameplay_command`,
  che chiama le regole (`try_move_player`, `try_dodge_player`, `wait_player_turn`, `play_card`, `select_defense`…). Un
  passo contro un nemico è un colpo a mano (`player_bump`, dentro `try_move_player`). Il fotogramma lo guida
  [tactical_controller.odin](../src/run/tactical_controller.odin).

  Esiste già un modo di giocare **senza finestra e senza disegno**: la prova automatica
  `run_headless_playtest_decisions` ([playtest_smoke.odin](../src/devtools/playtest_smoke.odin)). Fa scorrere battiti,
  frecce e difese e sceglie le mosse con una regola semplice: allontanarsi dai nemici
  (`choose_max_distance_command`, [kiting.odin](../src/combatdebug/kiting.odin)).
- **Le carte** ([card.odin](../src/game/card.odin), [card_play.odin](../src/game/card_play.odin),
  [deck.odin](../src/game/deck.odin)).
  - **Le 59 carte del codice** (otto ritirate): ognuna ha una `Card_Definition` con costo, rarità, `time_cost`, mira
    (`targeting`) ed effetti.
  - **La mira:** `Targeting_Spec`, con regole come `Self`, `Opponent`, `Cell`, `Walkable_Cell`, dice dove si può
    giocare la carta; `card_drop_target` trasforma una casella nel bersaglio della carta, come fa il mouse.
  - **I controlli:** `play_card` controlla fase, visibilità (`tactical_target_visible`), mano ed energia, poi risolve.
  - **Mano ed energia:** la mano tiene fino a 10 carte (5 all'inizio); l'energia è 3 e torna di 1 a battito; in
    spedizione c'è il mana (100).
  - **Il mazzo:** è un array fisso col suo seme (`Deck_State.random_state`), quindi l'ordine delle pescate si può
    sapere.
- **Gli oggetti che il giocatore posa** ([emplacement.odin](../src/game/emplacement.odin)). Il Cannone e il Buco Nero
  sono oggetti della griglia (`Grid_Object`) che vivono `life` battiti del mondo e agiscono a ogni battito
  (`emplacement_beat`, chiamato da `continue_tactical_pulse`), poi spariscono.
  - Si posano su una casella libera (camminabile, senza copertura, oggetto, trappola o corpo: `emplacement_can_place`),
    al massimo 2 per tipo (`MAX_CANNONS`, `MAX_BLACK_HOLES`); la carta del Cannone mira una casella da 1 a 3 caselle di
    distanza, in vista.
  - Il loro stato sta nei campi dell'oggetto (`life`, `power`, `radius`, `facing`, `laser`); la tabella
    `GRID_OBJECT_DEFINITIONS` ([grid_object.odin](../src/game/grid_object.odin)) dice cosa ferma: il Cannone ferma i
    passi ma non la vista, il Buco Nero niente.
  - Una stanza tiene al massimo 32 oggetti (`MAX_GRID_OBJECTS_PER_ROOM`, 128 byte l'uno), in `room.objects`, una lista
    fuori dai 9 KB della stanza.
- **Le cose che si muovono da sole.** Le frecce e le bombe dei nemici volano sui secondi del mondo
  (`tactical_flight_tick` dentro `tactical_advance_clock`) e il controllore le fa avanzare con dei comandi del mondo
  (`Enemy_Flight`, `resolve_enemy_flights`); la palla del Pinball rotola allo stesso modo. È la strada per i ragnetti.
- **Le linee sulla griglia** ([targeting.odin](../src/game/targeting.odin)): `trace_targeting_line` traccia una linea
  fra due caselle e `targeting_path_blocker` trova la prima cosa che la ferma; il Cannone spara lungo la sua direzione
  (`cannon_line`). È la strada per le linee della Regina.
- **La bruciatura** (`Status_Kind.Burn`, [pulse.odin](../src/game/pulse.odin)): i suoi stack sono il danno di ogni
  morso e **non calano mai**. Nel gioco senza finestra morde ogni 4 battiti (`EXPEDITION_DRAW_BEATS`, in
  `expedition_finish_beat`), con tanti danni quanti sono gli stack.
- **I fuochi a terra, i barili, il ghiaccio** ([ground.odin](../src/game/ground.odin)). Un fuoco a terra (quello
  dell'Incendio) è una croce che allunga i bracci ogni 4 battiti, per 4 volte, poi si spegne. I bracci si fermano ai
  muri, e chi entra nel fuoco prende la bruciatura; **il Viandante no, mai**. Al massimo 32 fuochi per stanza
  (`MAX_GROUND_FIRES`). I barili sono oggetti che esplodono (`explosive`), come quando li prende la brace del
  demolitore; i blocchi di ghiaccio (`Ice_Block`) si rompono con un colpo.
- **Le viste come famiglia di armi** ([first_person.odin](../src/game/first_person.odin)). Ogni arma è una voce di
  `First_Person_Weapon` (AK, pugni, spada, arco, bastone, nonno), con le sue regole in `FIRST_PERSON_WEAPONS`: la carta,
  se si prende in groppa al Dinosauro, se la camera sta dietro la schiena.
  - Tutte hanno i secondi (+2 a potenziamento e +2 sul tick: `FIRST_PERSON_SECONDS_PER_UPGRADE`,
    `FIRST_PERSON_CRITICAL_SECONDS`), il divieto delle carte e il salvataggio (`First_Person_Save`).
  - Lo stato di ognuna sta in un `#raw_union` (`First_Person_Arms`), che pesa quanto l'arma più grande.
  - Nelle viste i passi vanno al ritmo del Viandante solo con spada e arco (`tactical_player_pace`).
- **Il mouse sul tabellone:** `pick_ground_cell` ([height_view.odin](../src/render/height_view.odin)) trova la casella
  sotto il mouse; l'Inondazione e il Cannone prendono già una direzione dal mouse
  ([flood_aim.odin](../src/run/flood_aim.odin)).
- **I numeri per il bilanciamento:**
  - i nemici del laboratorio ([sandbox.odin](../src/game/sandbox.odin)): inseguitore 12 di vita (colpo 2), arciere 10
    (2), bruto 18 (3), bombarolo 12 (2);
  - il Cannone ([cannon.odin](../src/game/cannon.odin)): 2 danni a battito per 20 battiti sul primo nemico della sua
    direzione, +1 a potenziamento;
  - il Buco Nero ([black_hole.odin](../src/game/black_hole.odin)): 4 danni a battito per 8 battiti nei 3×3 attorno;
  - sul tick, i danni di Cannone e Buco Nero crescono con `critical_damage` (+2, o metà in più se è di più).
- **I dadi** ([dice.odin](../src/game/dice.odin)): `Dice_State` del giocatore (un seme e il numero di tiri). Il
  laboratorio fissa una faccia cercando un seme che la dà (`mechanics_lab_dice_for_face`).
- **La stanza** ([room.odin](../src/game/room.odin)). `Room` pesa **9208 byte su 9216** (`size_of(Room) < 9*1024`,
  [event_test.odin](../src/game/event_test.odin)): restano **8 byte**. Dentro ci sono puntatori e liste che crescono:
  il giocatore, il livello, nemici, trappole, ostacoli, oggetti, bottino, il campo delle distanze, le pozze, il
  registro degli eventi. Il codice stesso avverte che «le copie di Room sono superficiali»: copiandola con un semplice
  `=`, la copia toccherebbe le stesse liste della stanza vera. `destroy_room` elenca tutto quello che la stanza
  possiede.
- **Quanto pesa una copia vera** (misurato oggi sul commit di partenza):
  - stanza 9208 byte, giocatore 6880 (di cui 6080 il mazzo);
  - un nemico 1056 byte (al massimo 32), un oggetto 128 (al massimo 32), una trappola 40, un bottino 56;
  - il registro degli eventi **103 184 byte** (416 eventi da 248 byte): non va copiato;
  - le tabelle per casella (le distanze dei nemici, 8 byte a casella, e le pozze, 4 byte), grandi quanto la mappa, e
    quattro volte tanto se la mappa ha gli strati: nelle spedizioni più grandi (224×224 caselle, con gli strati)
    arrivano a **1,6 MB e 0,8 MB**.
- **Il livello può cambiare durante il combattimento:**
  - le strutture posate dal giocatore prendono i colpi dei nemici e cadono (`strike_structures`,
    `level.damage_structure`);
  - il pavimento dell'Inferno si spacca (`expedition_fracture_floor`);
  - i cancelli si aprono.

  Ogni cambio fa salire il contatore `geometry_revision` del livello.
- **Le regole non suonano e non disegnano.** Il pacchetto `game` non importa raylib né l'audio: le regole scrivono solo
  eventi nel registro della stanza (`room.recent_events`). È il controllore che, dopo ogni comando, li passa al disegno
  (`begin_renderer_event_timeline` in `commit_gameplay_command`). Da lì la presentazione (`Room_Presentation`,
  [presentation_timeline.odin](../src/render/presentation_timeline.odin)) fa animazioni e suoni. Una copia con un
  registro suo non arriva mai al disegno. Le regole leggono il registro solo per sapere quanto spazio resta (nei giri
  del Lazzo e del Pinball).
- **I numeri a caso nelle regole.** Mazzo, dadi, arco della prima persona, pesche, Bomb Marley e Pinball hanno
  ognuno il suo seme dentro lo stato (`Deck_State`, `Dice_State`, `bow_random`, `marley_random`, `pinball_random`). Nel
  combattimento non c'è un generatore globale. Le uniche variabili globali del pacchetto sono tabelle che non cambiano
  (`CARD_DEFINITIONS`…).
- **Le viste e le scene ferme.** Durante le viste (prima persona, bastone, nonno) le carte non si giocano. Durante le
  scene «cinematiche» (i dadi, la visita del nonno) il mondo è fermo (`presentation_time_policy`).
- **I colori che il tabellone usa già** (il fondo è un blu scuro freddo):
  - minacce in rosso (`living_ring_color`, Strike) e in arancio (Ranged); mosse dei nemici in verde; protezione in
    viola; il tick del giocatore in oro ([living_ring.odin](../src/render/living_ring.odin));
  - la mira delle carte, che tinge il pavimento stesso (`card_range_floor_color`): portata in blu, effetto in arancio
    chiaro, bersaglio in acquamarina, mossa non valida in rosso (`CARD_LIGHT_*`,
    [card_range_light.odin](../src/render/card_range_light.odin)).

  Le caselle minacciate e le frecce dei nemici le disegna [intent_display.odin](../src/render/intent_display.odin); le
  parole sopra il Viandante [tactical_feedback.odin](../src/render/tactical_feedback.odin); la mano
  [tactical_hand.odin](../src/render/tactical_hand.odin).
- **La fontana oggi** (`level.Structure_Id.Fountain`, [structure_catalog.odin](../src/level/structure_catalog.odin)) è
  una struttura 2×2 del piano della griglia: il bordo ferma il passo ma non la vista.
  - Dove c'è: una fissa nel bioma Robotica cibernetica delle spedizioni (`CYBER_STRUCTURES`), una nell'arena delle
    strutture del laboratorio, e quelle che il Viandante posa col kit dello zaino
    ([player_structures.odin](../src/expedition/player_structures.odin)).
  - Quella posata da lui ha 8 di vita, e i nemici la rompono.
  - **Non cura e non si usa.** Nelle spedizioni a curare è un luogo, la FONTE (qui sotto).
- **Le cure vere di oggi:**
  - nelle spedizioni, la **FONTE** (`Site_Kind.Spring`): +16 vita, una volta sola
    ([expedition_scene.odin](../src/run/expedition_scene.odin));
  - nello zaino della spedizione, il **Kit di riparazione** (`campaign.Item_Kind.Healing`): +12;
  - il Riposo sulla mappa della run (30% della vita massima, `build_rest_node_state`);
  - le cure a terra lasciate dai nemici (`Loot_Kind.Healing`);
  - la tavolata di Napoli;
  - le carte, le reazioni e le reliquie che curano (`heal_effect`);
  - la vita rubata del Dado del destino;
  - il pesce della Canna da pesca e il «Cibo pescato» dello zaino, che la IA **non** conta (scelta dell'utente).
- **Quanto manca alla fine.** Nella run c'è la mappa (`Run_Map`: i nodi per profondità fino al boss, `Node_Kind`).
  Nella spedizione il mondo (`expedition.World`) ha i luoghi (`sites`, fra cui la FONTE e i NIDI dei nemici), i gruppi
  di nemici sulla mappa (`groups`, con i membri non ancora entrati nello scontro), il boss (`boss_defeated`) e
  l'estrazione.
- **I thread del gioco.** Ce n'è già uno, quello dei salvataggi della campagna
  ([save_queue.odin](../src/campaign/save_queue.odin), con `core:thread`). Il gioco gira a 60 fotogrammi al secondo con
  la sincronia verticale. Nel benchmark un'immagine costa circa 1,5 ms, cioè circa 650 immagini al secondo senza
  limite (Esito della Fase 7 di [piano-napoli.md](piano-napoli.md)).
- **Il laboratorio.** Ogni prova è un atto (`src/devtools/mechanics_lab_*.odin`), che si lancia da solo con
  `ODIN_PP_LAB_ONLY=<nome>`; le arene e i mazzi stanno in [mechanics_practice.odin](../src/run/mechanics_practice.odin).
  Il mazzo dell'arena piatta è pieno (11 carte con una mano da 10, controllato da un `#assert`), quindi la IA ha bisogno
  di un'arena sua.
- **Il film «Mostra effetto»** ([card_demo.odin](../src/game/card_demo.odin), [run/card_demo.odin](../src/run/card_demo.odin)):
  ogni carta lavora in una stanzetta 11×9 con le regole vere. Una scena è fatta di dati: i nemici, il gesto con cui si
  gioca la carta, le azioni dopo (`Card_Demo_Action_Kind`). Un test controlla che ogni carta mostri i suoi eventi
  (`card_demo_expected_events`).

## Come si incastra nel codice (proposta)

- **La carta IA:** `Card_Id.IA`, nome «IA». Rara, 2 energia, prezzo 8, peso 60, 50 in spedizione
  (`EXPEDITION_CARD_COSTS`), `Lab_Only` fino all'ultima fase, mira `Self`, fino a 5 potenziamenti. Ha un effetto nuovo,
  `.IA`, con i secondi nell'`amount` (30, +3 a potenziamento, +5 sulla giocata critica), risolto da `resolve_ia_card` in
  [spell.odin](../src/game/spell.odin) come Napoli e il Dinosauro. Un evento nuovo, `IA_Begun`, porta i secondi (per il
  suono e per la scritta). Le regole della carta stanno in un file suo, `game/ia.odin`.
- **I secondi della IA stanno nel giocatore, non nella stanza:** un campo `Tactical_State.ia_remaining`, accanto a
  `dinosaur_remaining`. La stanza non cresce di un byte, e il salvataggio della spedizione copia già tutto il giocatore
  (`out.player=room.player^`). I secondi scorrono in `tactical_advance_clock`, cioè solo quando il mondo corre (sono
  fermi durante dadi, scene e difesa a tasti), e **non scorrono durante le viste** (scelta dell'utente).
- **Il consigliere è un pacchetto nuovo, `src/advisor/`**, fatto come `game`: niente raylib, niente audio. Contiene:
  - la copia di prova;
  - il simulatore;
  - la ricerca e la valutazione;
  - il consiglio (`Advice`: il tipo, la casella, il nemico, la carta, il bersaglio, la difesa, la vita che rischi);
  - le **tabelle della regola per sempre**: una voce per ogni carta, effetto, stato, nemico, oggetto, struttura e
    casella del gioco.

  Importa solo `game`, `level` ed `engine/grid` (più `core:thread`, `core:sync`, `core:mem` e `core:reflect` nei
  test).
- **Il pilota sta nel controllore** (`run/advisor_driver.odin`). A ogni fotogramma:
  - guarda se la situazione è cambiata e, se sì, fa la fotografia per la ricerca;
  - legge l'ultimo consiglio pronto e lo passa al disegno;
  - dice al consigliere quale comando il giocatore ha fatto davvero (serve per l'avviso).

  Ha la tabella dei comandi del giocatore: ogni comando è una mossa della IA, o è escluso col suo motivo.
- **Il disegno sta in `render/advisor_view.odin`:**
  - i segni ciano sul pavimento, con la stessa tinta del pavimento di `card_range_floor_color`;
  - il mirino;
  - la cornice della carta nella mano ([tactical_hand.odin](../src/render/tactical_hand.odin));
  - la parola sopra il Viandante;
  - la difesa giusta nel riquadro della difesa a tasti;
  - l'avviso rosso.
- **Lo stato della partita lo prepara chi lo conosce** (`run/advisor_context.odin`). La run (la mappa, i riposi) e la
  scena della spedizione (i gruppi, i luoghi come la FONTE, lo zaino) riempiono un `advisor.Game_Context` e lo danno al
  pilota; qui stanno le tabelle di posti, nodi, biomi e oggetti dello zaino. Il consigliere non importa né `run` né
  `expedition`.
- **Il Nido di ragni:** `Card_Id.Spider_Nest`, nome «Nido di ragni», con un effetto nuovo che posa un oggetto nuovo
  della griglia, `Grid_Object_Kind.Spider_Nest`, nello stesso modo di Cannone e Buco Nero. Il nido ferma i passi ma non
  la vista; i secondi che gli restano stanno nel suo `life`. I ragnetti sono oggetti anche loro
  (`Grid_Object_Kind.Spiderling`), che non fermano niente e nessuno colpisce, e corrono sui secondi del mondo come le
  frecce. Il nido fa da esca con `target_object`, come i barili per il demolitore. Le regole stanno in
  `game/spider_nest.odin`.
- **La Regina:** `Card_Id.Queen`, nome «Regina», con un oggetto nuovo, `Grid_Object_Kind.Queen`, che ferma i passi e
  che nessuno può colpire. Guarda le sue 8 linee con lo stesso tracciato delle linee delle carte; corsa e colpo sono
  un'azione d'attacco come la mazzata di Napoli. Le regole stanno in `game/queen.odin`.
- **Il Lanciafiamme:** `Card_Id.Flamethrower`, «Lanciafiamme», con un'arma nuova della famiglia delle viste,
  `First_Person_Weapon.Flamethrower`, e un segno nuovo nelle sue regole: la camera **resta sul tabellone**. Dalla
  famiglia prende i secondi, il divieto delle carte, il salvataggio e la pausa della IA. La mira, la storia delle
  direzioni della fiamma e i nemici bruciati da poco stanno nel `#raw_union`, senza farlo crescere. Le regole stanno in
  `game/first_person_flame.odin`, i comandi in `run/first_person_input.odin`.
- **I tipi nuovi vanno in fondo agli elenchi** (`Card_Id`, `Grid_Object_Kind`, `Effect_Kind`), così i salvataggi
  vecchi non cambiano, come per la tavolata di Napoli.

## Come lavora la ricerca (proposta)

### Cosa prova

A ogni **radice** la ricerca elenca le mosse possibili:
- i **passi** nelle 4 direzioni (un passo contro un nemico è il colpo a mano; contro la tavolata si mangia);
- le **schivate**, nelle direzioni in cui si può atterrare (`tactical_dodge_destination`);
- **aspettare**, fino al prossimo battito o per mezzo secondo;
- ogni **carta** giocabile della mano, su pochi bersagli buoni (Fase 3);
- durante la difesa a tasti, **ogni difesa** possibile, con la direzione della schivata.

Per ogni mossa, la copia di prova esegue **lo stesso comando del gioco**. Poi fa scorrere il mondo fino al momento in
cui il Viandante è di nuovo libero: risolve i battiti, i colpi dei nemici, le frecce in volo e le difese. Da lì prova di
nuovo tutte le mosse. È la stessa idea della prova automatica `run_headless_playtest_decisions`, ma esatta (il tempo
avanza fino al momento giusto, non a passi di 0,25 s) e senza nessuno che guarda.

### Come sceglie

- **Profondità crescente** (in inglese *iterative deepening*, come nei programmi di scacchi). Prima guarda tutte le
  mosse a un passo, poi a due, poi a tre… Ogni giro finito dà un consiglio completo, migliore del giro prima. Si può
  fermare in qualunque momento e un consiglio pronto c'è sempre (si dice ricerca *anytime*).
- **Dopo i primi passi, una regola semplice e veloce** porta ogni ramo fino all'orizzonte (da 3 a 6 secondi del
  mondo), per esempio «resta fuori dalle caselle minacciate, avvicinati al nemico più debole». Così si vedono anche i
  colpi che arrivano più tardi, senza provare tutte le combinazioni. È l'idea delle «partite di prova» (*playout*) di
  MCTS e dei piani a orizzonte mobile dei giochi in tempo reale.
- **I dadi**, l'unica cosa che la IA non sa. Per una carta con un dado solo prova **ogni faccia** e fa la media: è
  l'*expectimax*, cioè la media pesata delle possibilità, come nei giochi coi dadi. Con più dadi usa un numero fisso di
  tiri di prova.
- **Una tabella delle situazioni già viste** (la *tabella delle trasposizioni*: ogni situazione ha un'impronta, come lo
  *Zobrist hashing* degli scacchi). Due strade che portano alla stessa situazione si calcolano una volta sola; e quando
  il giocatore fa la mossa, la situazione nuova è già nella tabella.
- **Un ordine fisso delle mosse** e una regola fissa a pari punteggio: prima senza carta, poi i passi in ordine nord,
  est, sud, ovest, e così via. Così la scelta è sempre la stessa.

### La valutazione (i pesi dell'utente)

Alla fine di ogni ramo la ricerca dà un punteggio alla situazione:
1. **Morto:** è il ramo peggiore di tutti, sempre.
2. **Vita persa:** −3 punti per ogni punto di vita perso. È una proposta: il peso scende un po' verso la fine della
   run e vicino a una cura (Fase 6).
3. **Danno fatto:** +1 per ogni punto di vita tolto ai nemici; **+10** per ogni nemico ucciso.
4. **Posizione:** pochi punti per stare fuori dalle caselle che verranno colpite, avere vie di fuga, essere a un passo
   da un nemico debole, non stare in fila con un arciere. È lo stesso principio delle «mappe di influenza» delle IA
   tattiche: una mappa del pericolo che informa la scelta.
5. **Le carte:** nessun costo se la carta fa evitare danni, uccidere prima o fare più danni. **A pari punteggio vince
   la mossa senza carta**, e poi quella che spende meno energia.
6. **Quello che dura oltre l'orizzonte:** quello che una cosa farà ancora dopo l'orizzonte conta col suo valore
   (i ragnetti che deve ancora fare un nido, i colpi che restano alla Regina, il veleno che farà danno): lo dice la
   tabella di ogni carta e di ogni oggetto.

### Come resta veloce e continua senza far calare i fotogrammi

- **Un thread a parte fa la ricerca**, su un altro core. Il fotogramma del gioco fa solo due cose piccole:
  - quando la situazione cambia, una **fotografia** della stanza: dai 25 ai 60 KB copiati, qualche microsecondo. Il
    livello e le pozze, che nelle spedizioni grandi arrivano a circa 1 MB, vanno al thread solo quando cambiano nella
    stanza vera, e lo dicono gli stessi contatori qui sotto;
  - a ogni fotogramma, la lettura dell'ultimo consiglio pronto.

  Il gioco non aspetta mai il thread.
- **I dati passano senza blocchi.** La fotografia va al thread e il consiglio torna indietro con un **triplo buffer**:
  tre caselle e un indice atomico, come il `TTripleBuffer` di Unreal. Chi scrive e chi legge non si fermano mai a
  vicenda.
- **Il thread lavora solo quando serve.** Quando ha finito (orizzonte massimo o tetto di nodi), aspetta la prossima
  fotografia senza consumare il core.
- **Le tabelle grandi non si copiano a ogni prova:**
  - le distanze dei nemici si ricalcolano comunque prima di usarle, quindi la ricerca ne tiene una sua sola e la
    riusa;
  - le pozze e il livello si copiano **una volta per radice**, e si ricopiano solo se un ramo li ha cambiati. Per il
    livello lo dice `geometry_revision`. Per le pozze serve un contatore di scritture: nelle regole c'è un solo punto
    che le scrive ([ground.odin](../src/game/ground.odin); `clear_ground` lo usa solo il laboratorio), e il contatore
    sta nei 4 byte liberi in fondo a `Ground_State`, che pesa 2080 byte ma ne usa 2076. La stanza resta di 9208 byte.
- **Il calcolo a pezzi resta:** lo stesso codice, con un numero fisso di nodi per fotogramma, serve per i test, per il
  film e come riserva.
- **Si misura tutto:**
  - nella Fase 1, quanto costa una copia e un secondo simulato, nel laboratorio e nella spedizione più grande;
  - nella Fase 4, il tempo di un fotogramma, col benchmark in ordine incrociato (ABBA), e il tempo fra un cambio e il
    primo consiglio.

### Come simula senza toccare la stanza vera

La **copia di prova** è una copia profonda, con una memoria tutta sua: un'*arena*, che si svuota in un colpo solo a ogni
radice. È il metodo che gli scacchi chiamano *copy-make*: invece di fare la mossa e poi disfarla, si lavora su una
copia.

| Cosa | Come si copia |
|---|---|
| Stanza (9 KB), giocatore (7 KB), nemici, trappole, ostacoli, oggetti, bottino | Copiati per intero a ogni prova (nel laboratorio circa 25 KB, qualche microsecondo) |
| Livello (strutture, strati, cancelli) e pozze | Copiati una volta per radice; ricopiati solo se un ramo li ha cambiati (`geometry_revision`, contatore delle pozze) |
| Distanze dei nemici | Mai copiate: una tabella di lavoro della ricerca, che il codice dei nemici riscrive prima di usarla |
| Registro degli eventi | Mai copiato: un registro di lavoro che nessuno legge, quindi niente animazioni, niente suoni, niente presentazione |
| Memoria presa durante la prova | `context.allocator` e `context.temp_allocator` sono l'arena della ricerca: la memoria del gioco non si sporca |

Nella copia gira **lo stesso codice delle regole**, chiamato nello stesso ordine del controllore, non una seconda
versione delle regole che col tempo resterebbe indietro: quando una carta cambia, la IA lo sa subito. Due test lo
garantiscono:
- **Isolamento:** la stanza vera è uguale byte per byte prima e dopo mille ricerche (stanza, giocatore, nemici,
  oggetti, livello, pozze), nessuna memoria del gioco è stata presa, nessun evento è arrivato al disegno.
- **Equivalenza:** la stessa partita giocata dal gioco vero e dalla copia, mossa per mossa, dà sempre la stessa stanza.

### Come resta deterministica per i test

- **Il budget si conta in nodi, non in millisecondi.** Dalla stessa situazione, dopo N nodi, il consiglio è sempre lo
  stesso, su qualunque PC. Il thread cambia solo **quando** il consiglio arriva (un PC lento lo dà qualche fotogramma
  dopo), mai **quale** consiglio arriva. È lo stesso trucco dei motori di scacchi, che con un numero fisso di nodi e un
  thread solo danno sempre la stessa mossa.
- **Nessun numero a caso fuori dai semi della copia**, ordine fisso delle mosse, regola fissa a pari punteggio.
- **Dadi fissi:** per ogni faccia di ogni dado c'è un seme che la dà, trovato una volta all'avvio come fa già il
  laboratorio (`mechanics_lab_dice_for_face`). Per più dadi, tiri di prova coi semi sempre uguali.
- **La tabella delle situazioni si svuota** all'inizio di ogni test.
- **Thread e pezzi danno lo stesso consiglio:** i test fanno girare la ricerca senza thread, a pezzi, con lo stesso
  numero di nodi, e la confrontano con quella del thread.

### Come ricalcola subito quando il giocatore fa di testa sua

- **Pensare in anticipo.** La ricerca prova sempre **tutte** le prime mosse, non solo la migliore, e per ognuna sa già
  la risposta migliore. È il *pondering* dei motori di scacchi, che pensano anche durante il tempo dell'avversario. Se il
  giocatore fa un'altra mossa, il consiglio per la situazione nuova è già nella tabella e si mostra **nello stesso
  fotogramma**; poi il thread riparte da lì e lo migliora.
- **Cosa fa ripartire la ricerca:** un comando del giocatore, un battito risolto, un'intenzione nuova di un nemico, un
  danno, una carta pescata, la difesa a tasti, la fine di una scena. Il pilota se ne accorge con un'impronta della
  situazione, presa a ogni fotogramma (pochi microsecondi): se l'impronta non cambia, il consiglio vale ancora.
- **Il tempo che passa.** Tra il consiglio e il tasto premuto passa qualche decimo di secondo. Per questo la ricerca
  riparte anche quando il mondo è andato avanti di un decimo di secondo dall'ultima radice (proposta), e prova le mosse
  con un piccolo margine di reazione (proposta: 0,15 s) da confermare nella Fase 4. Così un consiglio non vale solo per
  chi preme all'istante.
- **L'avviso.** Per ogni prima mossa la ricerca sa quanto vale. Se il giocatore fa una mossa che vale molto meno del
  consiglio (proposta: almeno **2 di vita in più persa**, o la morte possibile), sopra il Viandante compare per mezzo
  secondo un **«!» rosso** con la vita che rischia, per esempio «! −3». È come le partite rivedute degli scacchi, che
  chiamano «errore» una mossa che perde molto rispetto alla migliore.

## Fase 0 — Base: la carta, i suoi secondi, l'arena

**Obiettivo:** la carta IA esiste nel laboratorio, si gioca e conta i suoi secondi, che si fermano nelle viste.

Proposta (da confermare all'inizio della fase):
- **Tempo di lancio:** `time_cost` 1 (0,26 s sulla carta), perché è una carta leggera che non fa danno. Napoli e il
  Dinosauro hanno 2 (0,375 s).
- **Giocarla di nuovo mentre è attiva:** i secondi **ripartono dal pieno**, non si sommano.
- **L'arena del laboratorio:** un'arena nuova «IA», 23×17 come quella piatta, con muretti e coperture; dentro un
  inseguitore, un arciere, un bruto e un bombarolo. Il mazzo ha carte comuni da consigliare (per esempio Strike, Guard,
  Firebomb, Dash, Shove, Arc Bolt, Heavy Blow) più la IA; dalle Fasi 9 e 11 anche il Nido di ragni e la Regina.
- **Il conto alla rovescia provvisorio:** «IA 30» in ciano, nel riquadro dove le viste mostrano i loro secondi.
- **Sigla e icona provvisorie:** sigla `IA`, icona provvisoria disegnata da codice in una cella libera dell'atlante
  (quella vera, il cervello di circuiti, è della Fase 8).

Passi:
1. **Punto di partenza.** Le misure finali di Napoli sono state fatte sullo stesso commit `6ea365b`: 1893 test, 2562
   catture, 165 suoni, 1,535 ms a immagine nel benchmark (circa 650 al secondo), stanza di 9208 byte. Sono il
   riferimento. Non si rifà la verifica completa, che arriva nella Fase 15 in ordine incrociato col commit di partenza.
2. **La carta nel codice:** `Card_Id.IA` e la sua definizione (rara, 2 energia, prezzo 8, peso 60, `Lab_Only`, mira
   `Self`, 5 potenziamenti); l'effetto `.IA`; `resolve_ia_card`; l'evento `IA_Begun`. Poi le tabelle che lo chiedono:
   `EXPEDITION_CARD_COSTS` (50), `CARD_VISUALS`, le descrizioni, i suggerimenti della mano, l'anteprima dei
   potenziamenti, gli eventi attesi del film (`card_demo_expected_events`).
3. **I secondi:** `Tactical_State.ia_remaining`. Scorrono in `tactical_advance_clock`, sono fermi nelle viste
   (`tactical_first_person_active`) e quando il mondo è fermo, si azzerano a fine combattimento
   (`tactical_end_combat`); la critica aggiunge 5 s.
4. **Laboratorio:** l'arena «IA» col suo mazzo. Un atto nuovo, `mechanics_lab_ia` (`ODIN_PP_LAB_ONLY=ia`), gioca la
   carta e controlla i secondi: 30, 33 con un potenziamento, 35 con la critica. Poi apre e chiude una vista e controlla
   che i secondi si fermino. Catture `odin_pp_ia_card_NN.png`.
5. **Provvisori:** icona e suono provvisori. Servono subito perché un test vuole un suono diverso per ogni carta, come
   è successo con Napoli.
6. **Test** (`game/ia_test.odin`): la carta è rara, del laboratorio, da 2 energia; i secondi coi potenziamenti e con
   la critica; fermi nelle viste e durante la difesa a tasti; azzerati a fine combattimento; la stanza resta di 9208
   byte. Si aggiornano i test che contano le carte, le carte del laboratorio, le icone e i suoni.
7. Voce nuova in [registro-carte.md](registro-carte.md): «Carta nuova: IA (solo laboratorio)».

Check della fase: `odin check src -vet -strict-style`; i test della carta e quelli che contano carte, icone e suoni;
l'atto `ia`.

**Fatto quando:** nel laboratorio la carta si gioca e il conto alla rovescia scende solo col mondo e fuori dalle viste;
i test sono verdi.

## Fase 1 — La copia di prova e il simulatore

**Obiettivo:** il consigliere sa copiare la stanza e provarci sopra una mossa, esattamente come il gioco vero, senza
mai toccare la stanza vera.

Proposta (da confermare all'inizio della fase):
- **Il pacchetto `src/advisor/`**, con tre procedure:
  - `advisor_copy_room`: la copia profonda nell'arena, seguendo la tabella di «Come simula»;
  - `advisor_play`: una mossa, cioè lo stesso comando del gioco;
  - `advisor_run_until_free`: il mondo che scorre fino al prossimo momento in cui il Viandante è libero (battiti,
    frecce, bombe, difese).
- **I comandi:** `execute_gameplay_command` sta nel pacchetto `run`, che il consigliere non può importare (sarebbe un
  giro: `run` importa il consigliere). Il consigliere chiama quindi le stesse procedure delle regole
  (`try_move_player`, `try_dodge_player`, `wait_player_turn`, `play_card`, `select_defense`, `resolve_qte`,
  `continue_tactical_pulse`, `resolve_enemy_flights`…) nello stesso ordine del controllore. Un test controlla che le
  due strade restino uguali.
- **La difesa a tasti nella copia:** il Viandante della copia sceglie sempre la difesa migliore, perché la IA gliela
  illumina (Fase 5). Blocco, spine e schivata riescono (c'è 1,2 s di tempo); la parata, che lascia solo 0,45 s, conta
  per metà riuscita e per metà no, con una media come per i dadi. Senza difese il colpo arriva, come nel gioco.

Passi:
1. **La copia profonda**, con quello che si copia sempre, una volta per radice o mai.
2. **Il contatore di scritture delle pozze**, nei 4 byte liberi di `Ground_State` (la stanza resta di 9208 byte), e il
   controllo di `geometry_revision` per il livello.
3. **Il simulatore:** la mossa, poi il tempo, poi i battiti, nella stessa sequenza del controllore (`tactical_tick`,
   `continue_tactical_pulse`, `resolve_enemy_flights`…).
4. **Test di isolamento:** la stanza vera è uguale byte per byte prima e dopo mille copie e simulazioni (stanza,
   giocatore, nemici, oggetti, livello, pozze); il gioco non ha preso memoria (un allocatore che conta); nel registro
   vero non è arrivato nessun evento.
5. **Il primo controllo della regola per sempre:** un test elenca con `core:reflect` i campi di `Room`, `Player`,
   `Enemy`, `Grid_Object` e `level.Level`, li confronta con quelli che la copia conosce, e fallisce se ne compare uno
   nuovo.
6. **Test di equivalenza** (nel pacchetto dei test `integration`, che vede sia `run` sia il consigliere): 200 partite
   brevi, con mosse scelte a caso da un seme fisso, giocate due volte: dal gioco vero senza finestra
   (`execute_gameplay_command`) e dalla copia. Dopo ogni mossa le due stanze devono essere uguali.
7. **Test di determinismo:** la stessa simulazione fatta due volte dà la stessa stanza.
8. **Misure:** quanto costa una copia e quanto un secondo simulato, nell'arena IA, nell'arena delle strutture e nella
   spedizione più grande (224×224); quante simulazioni al secondo fa un core.

Check della fase: `odin check`; i test nuovi del pacchetto `advisor`; i test delle pozze (la fase tocca
[ground.odin](../src/game/ground.odin)). Niente laboratorio: non c'è ancora niente da vedere.

**Fatto quando:** la copia e il gioco vero restano uguali mossa per mossa; la stanza vera non cambia mai; le misure
sono scritte nell'Esito.

## Fase 2 — La ricerca: passi, colpi a mano, schivate, attesa

**Obiettivo:** la IA trova la mossa migliore senza le carte, e la si vede nel laboratorio con segni provvisori.

Proposta (da confermare all'inizio della fase):
- **La ricerca:** profondità crescente, tabella delle situazioni, una regola veloce per arrivare all'orizzonte (3 s,
  fino a 6 s se c'è tempo) e la valutazione coi pesi dell'utente.
- **Il calcolo a pezzi nel fotogramma:** un numero di nodi per fotogramma scelto in modo che costi al massimo 2 ms. Il
  thread arriva nella Fase 4.
- **Segni provvisori nel laboratorio:** un quadrato ciano sulla casella del passo, una croce ciano sul nemico da
  colpire, la parola sopra il Viandante.

Domande all'utente all'inizio della fase:
- **I pesi:** vita 3 a 1, uccisione +10, posizione pochi punti. Si guardano insieme alcune situazioni di prova.
- **I passi in diagonale** (Q ed E, con la loro difesa a tasti, `begin_diagonal_qte`): la IA li consiglia? Proposta:
  sì, quando il passo dritto non basta.
- **La regola veloce dopo i primi passi.** Proposta: «stai fuori dalle caselle minacciate, vai verso il nemico più
  debole, aspetta se sei già al sicuro».

Passi:
1. L'elenco delle mosse: passi, colpi, schivate, attesa; durante la difesa a tasti, le difese.
2. La valutazione: morte, vita, danno, uccisioni, posizione, coi pesi.
3. Profondità crescente, tabella delle situazioni, ordine fisso, regola veloce fino all'orizzonte; budget in nodi.
4. **Le tabelle di comandi e nemici** (regola per sempre): in `run/advisor_driver.odin` uno `switch` su
   `Gameplay_Command_Kind` (ogni comando è una mossa della IA, o è escluso col suo motivo); nel consigliere una voce
   per ogni nemico (`[Enemy_Archetype]`: quanto è pericoloso, quanto vale ucciderlo).
5. **Puzzle di prova**, situazioni dove tutto è annunciato come in Into the Breach:
   - il bruto sta per colpire tre caselle: la IA esce;
   - l'arciere è in fila: la IA esce dalla fila;
   - accanto c'è un nemico a 2 di vita: la IA lo colpisce;
   - due nemici colpiranno la stessa casella: la IA non ci va;
   - un passo salva adesso ma chiude in un angolo: la IA sceglie l'altro (serve guardare avanti).
6. **Il torneo:** 20 combattimenti fissi dell'arena IA giocati da soli, senza finestra. Il Viandante che segue sempre la
   IA gioca contro due avversari:
   - la regola semplice di oggi (`choose_max_distance_command`);
   - un Viandante senza IA, che colpisce sempre il nemico più vicino.

   Si contano vita persa, nemici uccisi e tempo. La IA deve perdere molta meno vita: quanta, si fissa all'inizio della
   fase (proposta: almeno un terzo in meno della regola semplice).
7. **Misure:** nodi al secondo; profondità raggiunta in 1, 10 e 100 ms; costo nel fotogramma.
8. **Laboratorio:** l'atto `ia` gioca la carta e segue i consigli per 10 s. Catture `odin_pp_ia_step_NN.png` e
   `odin_pp_ia_bump_NN.png`.

Check della fase: i test del pacchetto `advisor`; l'atto `ia`. Il benchmark no: senza la carta la ricerca non gira, e
la carta è solo nel laboratorio.

**Fatto quando:** i puzzle passano; nel torneo la IA perde molta meno vita; l'utente prova nel laboratorio.

## Fase 3 — Le carte nella ricerca

**Obiettivo:** la IA consiglia anche quale carta giocare e dove, sapendo l'energia, i tempi e le carte che arrivano.

Proposta (da confermare all'inizio della fase):
- **Le giocate:** ogni carta giocabile (energia, `tactical_allows_cards`, visibilità), ognuna su pochi bersagli buoni:
  - per le carte su un nemico, ogni nemico nella portata;
  - per le carte su una casella, le caselle che prendono più nemici (dalla forma, `build_target_shape`) e quelle
    utili (dove arrivare con Dash, dove mettere qualcosa);
  - per le carte su di sé, una giocata sola.
- **Il bersaglio:** `card_drop_target`, lo stesso del mouse.
- **Le carte coi dadi:** tutte le facce per un dado solo, tiri fissi per più dadi.
- **Le pescate:** la copia ha il mazzo vero, quindi sa cosa arriva (scelta dell'utente).
- **A pari punteggio:** la mossa senza carta.

Domande all'utente all'inizio della fase:
- **Quanti bersagli per carta.** Proposta: fino a 6, i migliori secondo una stima veloce; tutti se sono di meno.
- **Le carte che aprono una vista** (prima persona, Napoli con la faccia 1…) **e le carte «lunghe»** (Ombra, Lazzo,
  Pinball, Dinosauro, Marley). Proposta: la IA le consiglia, ma la loro durata la simula davvero solo dalla Fase 7;
  fino ad allora le valuta con una regola semplice (per esempio «vale come X danni») oppure non le consiglia.
- **Il riordino della mano** (Refocus, 2 s). Proposta: la IA lo consiglia quando nella mano non c'è niente di utile.

Passi:
1. L'elenco delle giocate e dei bersagli.
2. I dadi: le facce e i tiri fissi, con la tabella dei semi per ogni faccia, calcolata una volta all'avvio.
3. Energia e mana (spedizione), tempo di lancio, pescate.
4. **Le tabelle di carte, effetti e stati** (regola per sempre): `[Card_Id]Advisor_Card` (come si gioca la carta,
   quali bersagli provare, quanto vale oltre l'orizzonte, il suo puzzle) e due `switch` senza `#partial` su
   `Effect_Kind` e `Status_Kind` (quanto vale ogni effetto e ogni stato). Le carte simili possono dividere un puzzle.
5. **Puzzle di prova:**
   - una Firebomb su tre nemici vicini;
   - una Guard prima del colpo del bruto;
   - nessuna carta quando basta un passo (a pari punteggio);
   - una carta che uccide prima;
   - una carta che arriva con la prossima pescata e che conviene aspettare.
6. **Torneo con le carte:** lo stesso della Fase 2, col mazzo dell'arena.
7. **Laboratorio:** catture `odin_pp_ia_card_hint_NN.png`, con la carta illuminata e poi la sua casella quando la tieni.

Check della fase: i test del pacchetto `advisor`; i test delle carte toccate; l'atto `ia`.

**Fatto quando:** i puzzle con le carte passano; il torneo va meglio di quello della Fase 2; l'utente prova.

## Fase 4 — Il thread: calcolo continuo e ricalcolo immediato

**Obiettivo:** la ricerca gira di continuo su un altro core, il gioco non perde fotogrammi, e se il giocatore fa di
testa sua il consiglio nuovo è già pronto.

Proposta (da confermare all'inizio della fase):
- **Un thread solo per il consigliere**, creato al primo uso della carta e chiuso a fine combattimento.
- **La fotografia** si fa nel fotogramma, sul thread del gioco. Un triplo buffer la porta al thread e riporta indietro
  il consiglio. Un numero di «generazione» atomico dice al thread di lasciare una ricerca vecchia.
- **Il thread si ferma da solo** quando la ricerca è finita (orizzonte massimo o tetto di nodi), e aspetta la
  fotografia nuova con un semaforo (`core:sync`).
- **Pensare in anticipo:** per ogni prima mossa la risposta migliore resta pronta; il pilota riconosce il comando fatto
  e mostra subito il consiglio del ramo giusto.
- **Il margine di reazione** (0,15 s) e la ripartenza ogni decimo di secondo di mondo (vedi «Come ricalcola»).
- **I test** usano il calcolo a pezzi, con gli stessi nodi.

Domande all'utente all'inizio della fase:
- **Il tetto di nodi per radice.** Proposta: quanto basta, secondo le misure della Fase 2, per arrivare a 6 s di
  orizzonte.
- **Il margine di reazione:** 0,15 s, o un altro valore dopo la prova.

Passi:
1. Il thread, la fotografia, il triplo buffer, la generazione.
2. L'impronta della situazione e i motivi per ripartire.
3. Pensare in anticipo, e il consiglio immediato quando il giocatore devia.
4. **Test:**
   - stesso consiglio col thread e senza (100 situazioni);
   - fermare una ricerca a metà e ripartire non lascia memoria sporca;
   - il gioco non aspetta mai il thread (un test blocca il thread e controlla che i fotogrammi vadano avanti).
5. **Misure:**
   - benchmark in ordine incrociato (ABBA) con la IA attiva nel laboratorio e senza;
   - il tempo fra un cambio e il primo consiglio (nello stesso fotogramma se è già pronto, altrimenti in quanti ms);
   - quanto costa la fotografia nel fotogramma.

Check della fase: i test del pacchetto `advisor` e del pilota; l'atto `ia`; le misure dei fotogrammi (questa fase
tocca il fotogramma).

**Fatto quando:** nessun calo di fotogrammi misurabile; dopo una deviazione il consiglio arriva nello stesso
fotogramma; i test sono verdi.

## Fase 5 — Le indicazioni vere

**Obiettivo:** il giocatore vede e capisce al volo i consigli: segni ciano, la parola, la carta e la sua casella, la
difesa, l'avviso.

Proposta (da confermare guardando le catture):
- **Passo (VAI o SCHIVA):** un'impronta ciano sulla casella dove andare, con una freccia che parte dal Viandante.
  «SCHIVA» quando il passo esce da una casella minacciata, altrimenti «VAI».
- **Colpo a mano (COLPISCI):** un mirino ciano sulla casella del nemico, che respira piano.
- **Carta (CARTA):** una cornice ciano attorno alla carta nella mano. Quando la prendi (selezionata o trascinata), la
  cornice ciano va sulla casella del bersaglio: il nemico, la casella a terra o il Viandante stesso.
- **Difesa (DIFENDI):** la cornice ciano sul tasto della difesa giusta, nel riquadro della difesa a tasti, e la
  direzione della schivata.
- **Aspettare (ASPETTA):** un piccolo orologio ciano sotto il Viandante.
- **L'avviso:** il «!» rosso con la vita che rischi, per mezzo secondo, sopra il Viandante.
- **Il ciano:** un colore che oggi il tabellone non usa. Il blu della portata delle carte è più scuro e più azzurro,
  l'acquamarina del bersaglio è più verde. Proposta: `{90, 230, 255}`, da controllare nelle catture accanto agli altri
  colori, anche per chi distingue male i colori.

Domande all'utente all'inizio della fase:
- **I segni:** si guardano nelle catture.
- **La soglia dell'avviso:** 2 di vita in più persa, oppure un altro numero.
- **I nemici nella nebbia:** la IA li conosce (scelta dell'utente), ma il consiglio li deve mostrare? Proposta: no, il
  disegno non svela niente; un consiglio può sembrare strano, ma resta giusto.

Passi:
1. `render/advisor_view.odin`: i segni sul pavimento, il mirino, l'orologio, la parola, l'avviso.
2. La cornice della carta nella mano e sulla casella del bersaglio ([tactical_hand.odin](../src/render/tactical_hand.odin),
   [card_range_light.odin](../src/render/card_range_light.odin)).
3. La difesa nel riquadro della difesa a tasti.
4. Il pilota nel controllore: il consiglio va al disegno, il comando fatto va al consigliere.
5. **Laboratorio:** l'atto `ia` completo: passo, colpo, carta (con la casella quando la tieni), difesa, attesa,
   avviso. Catture `odin_pp_ia_<tipo>_NN.png`.
6. **Test del disegno**, come quelli di `intent_display_test.odin`: il segno giusto per ogni tipo di consiglio; nessun
   segno durante le viste.

Check della fase: i test del pacchetto `render` toccati; l'atto `ia`; il benchmark ABBA (la fase tocca il disegno di
ogni fotogramma).

**Fatto quando:** l'utente approva i segni nel laboratorio.

## Fase 6 — Lo stato della partita

**Obiettivo:** la IA tiene conto di quanto manca alla fine e delle cure vicine, e diventa un po' più aggressiva quando
se lo può permettere.

Proposta (numeri da confermare all'inizio della fase):
- **Il progresso**, da 0 a 1:
  - nella run, la profondità del nodo attuale sulla strada del boss e i nodi che restano;
  - nella spedizione, i gruppi di nemici sconfitti sul totale, i luoghi fatti, il boss;
  - nel laboratorio, un tasto per provarlo (0, 50 e 100%).
- **Le cure vicine:** tutte quelle vere tranne la Canna da pesca (e il Cibo pescato):
  - le carte che curano, in mano e nelle prossime pescate;
  - le cure a terra che si possono raggiungere;
  - la tavolata;
  - il Riposo sul prossimo nodo della run;
  - nelle spedizioni, la FONTE non ancora usata entro una certa distanza (proposta: 20 caselle), anche fuori dallo
    scontro, e il Kit di riparazione nello zaino.
- **L'aggressività:** il peso della vita scende da 3 (inizio della run) a 2 (fine), e di 0,5 in più quando c'è una
  cura vicina, mai sotto 1,5. La morte resta sempre il ramo peggiore.
- **I nemici sulla mappa:** i membri dei gruppi non ancora entrati nello scontro entrano nella copia come «pericoli
  fermi», cioè come caselle dove li si sveglia. Così la IA non ti porta da loro senza motivo, e li conta in «quanti
  nemici restano».
- **Chi prepara il contesto:** la run e la scena della spedizione (`run/advisor_context.odin`, `advisor.Game_Context`).
  Il consigliere non importa `run` né `expedition`.

Passi:
1. `Game_Context` e chi lo riempie: la run, la spedizione, il laboratorio.
2. I pesi che cambiano col contesto.
3. I gruppi della spedizione nella copia.
4. **Le tabelle di posti e zaino** (regola per sempre), in `run/advisor_context.odin`: una voce per ogni luogo della
   spedizione (`Site_Kind`: la FONTE cura 16 una volta, il NIDO è pericoloso…), per ogni nodo della run (`Node_Kind`),
   per ogni bioma (`campaign.Biome`) e per ogni oggetto dello zaino (`campaign.Item_Kind`: il Kit cura 12, il Cibo
   pescato non conta).
5. **Puzzle di prova** (coi pesi proposti):
   - a inizio run la IA non accetta di perdere 2 di vita per fare 5 danni in più (−6 + 5);
   - a fine run sì (−4 + 5);
   - a metà run, con una FONTE non ancora usata vicina, sì anche lì.
6. **Laboratorio:** il tasto del progresso; catture.
7. Riga nel registro delle carte: la IA conta lo stato della partita e tutte le cure vere.

Check della fase: i test del pacchetto `advisor` e di chi riempie il contesto; l'atto `ia`.

**Fatto quando:** i puzzle passano; l'utente prova i due estremi (inizio e fine run) nel laboratorio.

## Fase 7 — I casi speciali

**Obiettivo:** la IA non sbaglia mai nelle situazioni particolari del gioco: o le sa simulare, o sta zitta.

Proposta (da confermare all'inizio della fase):
- **Movimento Ombra** (il mondo è fermo e si muove solo l'ombra): la IA consiglia i passi dell'ombra, che hanno le loro
  regole nella copia, oppure sta zitta. Domanda all'utente.
- **Lazzo, Pinball, frecce e bombe in volo, Bomb Marley, cannoni, Buco Nero, Dinosauro, la tavolata di Napoli:** sono
  stato della stanza, quindi la copia li simula già. La fase li prova uno per uno con dei puzzle e controlla i tempi.
- **Prima persona, bastone, nonno:** la IA sta zitta e i suoi secondi si fermano (scelta dell'utente).
- **Piani, scale, ascensori, cancelli, altezze** (il piano della profondità): passi su altri strati, ascensori in
  viaggio (`lift_player_riding`); puzzle nelle arene dei piani.
- **Le spedizioni grandi** (224×224): il costo della fotografia e delle tabelle; le distanze dei nemici a finestra
  (`EXPEDITION_PATH_RADIUS`).
- **Quando non sa:** se una situazione non si può simulare (per esempio un caso nuovo che la copia non conosce), la IA
  non mostra niente e scrive «IA: …» nel riquadro. Mai un consiglio sbagliato.

Passi:
1. Un puzzle per ogni caso.
2. **Le tabelle di oggetti, strutture e caselle** (regola per sempre): una voce per ogni oggetto della griglia
   (`[Grid_Object_Kind]`: cosa vale, cosa ferma, quanto dura), per ogni struttura (`level.Structure_Id`) e per ogni
   tipo di casella (`level.Tile_Kind`).
3. Il torneo nelle arene speciali.
4. Le misure nelle mappe grandi.
5. **Test «consiglio possibile»:** in mille situazioni a caso il gioco accetta sempre la mossa consigliata.

Check della fase: i test del pacchetto `advisor` e dei casi toccati; gli atti del laboratorio dei casi provati.

**Fatto quando:** tutti i casi sono provati; in mille situazioni a caso non c'è nessun consiglio impossibile.

## Fase 8 — Aspetto e suoni della IA

**Obiettivo:** la carta IA ha il suo aspetto e i suoi suoni.

Proposta (da confermare all'inizio della fase):
- **L'icona:** un cervello di circuiti, metà con le pieghe e metà con le piste di circuito, ciano su fondo scuro; sigla
  **IA** (scelta dell'utente).
- **Il conto alla rovescia:** «IA» e i secondi, in ciano, che lampeggiano negli ultimi 5 s.
- **L'accensione:** una scia ciano che passa sul tabellone quando la carta parte, e si spegne alla fine.
- **I suoni, da codice** (scelta dell'utente), solo nel laboratorio come quelli delle altre carte. Domanda all'utente:
  anche nel gioco vero?

Passi:
1. **L'icona** in una cella libera dell'atlante (`tools/art/build_card_icons.py`), senza spostare di un pixel le icone
   che ci sono già.
2. **Il conto alla rovescia** e **l'accensione**.
3. **Suoni da codice** (`tools/audio/sfx_ia.py`):
   - `card_ia`: l'accensione elettronica (un ronzio che sale, due bip, un accordo pulito);
   - `ia_tick`: un tic leggerissimo quando il consiglio cambia, mai più di uno ogni 0,3 s;
   - `ia_warn`: due note brevi che scendono, per l'avviso;
   - `ia_off`: lo spegnimento.
4. **Laboratorio:** l'atto `ia` controlla che ogni suono suoni.

Check della fase: i test dei suoni e delle icone; l'atto `ia`.

**Fatto quando:** l'utente approva icona e suoni.

## Fase 9 — Nido di ragni: regole e prototipo; la IA lo conosce

**Obiettivo:** nel laboratorio il Nido di ragni si posa, fa uscire i ragnetti che mordono, i nemici accanto lo
colpiscono e gli tolgono secondi; e la IA lo sa usare (prima prova della regola per sempre).

Proposta (i numeri sono il bilanciamento scelto da Claude, da confermare all'inizio della fase):
- **La carta:** `Card_Id.Spider_Nest`, «Nido di ragni», non comune, 2 energia, prezzo 6, peso 70, 40 in spedizione,
  `Lab_Only` fino all'ultima fase, 2 potenziamenti. Si posa come il Cannone: una casella libera da 1 a 3 caselle di
  distanza, in vista. Al massimo 2 nidi insieme.
- **Il nido** (`Grid_Object_Kind.Spider_Nest`): ferma i passi ma non la vista; dura **20 s** del mondo (il suo `life`,
  in battiti); a zero secondi sparisce, e così a fine combattimento.
- **I ragnetti** (`Grid_Object_Kind.Spiderling`):
  - il primo esce **subito**, poi **uno ogni 2 s** (10 in tutto, se nessuno tocca il nido);
  - camminano **attorno ai muri**, attraversano nemici e Viandante, **4 caselle al secondo**, sul percorso più breve
    verso il nemico più vicino (contato in passi, non in linea d'aria);
  - arrivati al nemico gli danno un **morso di 2** (+1 a potenziamento; sul tick 4, con `critical_damage`), poi
    muoiono senza esplodere;
  - se il loro nemico muore prima, vanno dal più vicino; senza nemici aspettano nel nido; dopo 5 s senza arrivare
    muoiono;
  - nessuno li può colpire, non fermano nessuno.
- **I colpi al nido:** ogni colpo di un nemico che lo prende (anche un colpo diretto a te che passa sulla sua casella)
  gli toglie **3 s**, una volta per colpo, qualunque sia il danno e qualunque sia il nemico.
- **L'esca:** un nemico che ha il nido accanto e non ha te accanto lo prende di mira (`target_object`), come il
  demolitore coi barili.
- **In parole semplici:** se nessuno lo tocca fa circa 20 danni (1 al secondo, sempre a segno); un inseguitore che lo
  colpisce di continuo lo fa durare circa 10 s, ma intanto non colpisce te.

Domande all'utente all'inizio della fase:
- **I numeri** qui sopra.
- **I ragnetti e il terreno:** proposta, le trappole, le pozze e il fuoco non li toccano (sono intangibili).
- **Sigla e icona provvisorie:** proposta `NDR` e una ragnatela disegnata da codice.

Passi:
1. **Le regole** (`game/spider_nest.odin`): la carta, l'effetto, il nido sui battiti, i ragnetti sui secondi del mondo
   con un comando del mondo come le frecce, il morso come azione d'attacco, i colpi che tolgono secondi, l'esca.
   Eventi nuovi per la presentazione (il nido posato, il ragnetto che esce, il morso, il colpo al nido, la fine).
2. **Salvataggio:** la spedizione salva nido e ragnetti come gli altri oggetti; i tipi nuovi in fondo agli elenchi.
3. **Aspetto provvisorio:** un mucchietto di seta bianca e dei puntini neri che corrono; il conto dei secondi sul nido.
4. **La IA lo conosce** (regola per sempre):
   - la voce della carta nella tabella: le caselle da provare (al massimo 6: lontano dai nemici che lo
     colpirebbero, vicino a dove i ragnetti arrivano presto, o accanto a un nemico da attirare);
   - il valore oltre l'orizzonte: i ragnetti che restano per il morso, meno quello che i nemici gli toglieranno;
   - le voci dei due oggetti nuovi;
   - puzzle: il nido posato dove il bruto non arriva; il nido come esca per sfuggire a un inseguitore; uno Strike invece
     del nido quando un nemico a 2 di vita si uccide subito.
5. **Laboratorio:** atto `nido` (`ODIN_PP_LAB_ONLY=nido`) nell'arena IA: posa, ragnetti che girano attorno a un
   muretto, morsi, un inseguitore che colpisce il nido (−3 s), il nido che finisce. Catture `odin_pp_nido_NN.png`.
6. **Test:** il ritmo dei ragnetti, il percorso attorno ai muri, il morso coi potenziamenti e sul tick, −3 s a colpo
   (uno per colpo, anche per un colpo che prende nido e Viandante insieme), la fine a zero, l'esca, al massimo 2 nidi,
   il salvataggio, la stanza che resta di 9208 byte.
7. Voce nuova in [registro-carte.md](registro-carte.md): «Carta nuova: Nido di ragni (solo laboratorio)», con «IA
   aggiornata».

Check della fase: i test della carta e del consigliere; gli atti `nido` e `ia`.

**Fatto quando:** nel laboratorio il nido funziona come deciso e la IA lo usa bene nei suoi puzzle; i test sono verdi.

## Fase 10 — Nido di ragni: aspetto e suoni

**Obiettivo:** il nido e i ragnetti hanno il loro aspetto e i loro suoni.

Proposta (da confermare all'inizio della fase, guardando le catture):
- **Il nido:** una cupola di seta bianca con le uova e qualche filo teso, nello stile di resina e carta degli altri
  oggetti; a ogni colpo la seta si strappa un po'; un anello attorno mostra i secondi che restano.
- **I ragnetti:** piccoli, scuri, con le otto zampe che si muovono a scatti; il morso con un lampo piccolo sul nemico.
- **L'icona:** una ragnatela con un ragno, in una cella libera dell'atlante.
- **I suoni, da codice:** la seta che si tende (posa), le zampette (uscita), uno schiocco piccolo (morso), uno strappo
  (colpo al nido), il nido che si affloscia (fine).

Passi:
1. Il disegno del nido, dei ragnetti, del morso e dei secondi.
2. L'icona.
3. I suoni (`tools/audio/sfx_spider_nest.py`), solo nel laboratorio come gli altri.
4. Laboratorio: l'atto `nido` controlla catture e suoni.

Check della fase: i test del disegno, dei suoni e delle icone; l'atto `nido`.

**Fatto quando:** l'utente approva aspetto e suoni.

## Fase 11 — Regina: regole e prototipo; la IA la conosce

**Obiettivo:** nel laboratorio la Regina si posa, guarda le sue linee, corre dal primo nemico che ci entra e lo
colpisce; e la IA la sa usare.

Proposta (i numeri sono il bilanciamento scelto da Claude, da confermare all'inizio della fase):
- **La carta:** `Card_Id.Queen`, «Regina», rara, 3 energia, prezzo 8, peso 60, 60 in spedizione, `Lab_Only` fino
  all'ultima fase, 2 potenziamenti. Si posa come il Cannone: una casella libera da 1 a 3 caselle di distanza, in vista.
  Una sola Regina alla volta.
- **La Regina** (`Grid_Object_Kind.Queen`): occupa la sua casella e ferma i passi di tutti, come un pezzo; nessuno la
  può colpire né distruggere; dura **20 s** del mondo, poi sparisce, e così a fine combattimento.
- **Le linee:** le 8 direzioni della regina degli scacchi, lunghe quanto la stanza; muri, coperture, oggetti e corpi
  (anche il Viandante) le fermano. Il primo nemico su una linea è quello che può raggiungere.
- **Il colpo:** appena un nemico è su una delle sue linee e il colpo è pronto, la Regina corre lungo la linea fino alla
  casella accanto a lui, resta lì e lo colpisce: **4 danni** (+1 a potenziamento; sul tick 6). Poi aspetta **2 s**
  prima del colpo dopo; se il nemico le è ancora accanto, lo colpisce di nuovo.
- **Più nemici insieme:** il più vicino, in caselle lungo la linea; a pari distanza un ordine fisso delle direzioni
  (nord, nord-est, est…), così è sempre lo stesso.
- **Quando guarda:** alla fine di ogni battito e dopo ogni comando del giocatore, così «appena entra» vale anche per un
  nemico spinto da una carta.
- **In parole semplici:** al massimo 10 colpi, 40 danni; un inseguitore cade in 3 colpi.

Domande all'utente all'inizio della fase:
- **I numeri** qui sopra.
- **La vista:** proposta, la Regina non ferma la vista (è un pezzo, non un muro), anche se ferma i passi.
- **Le linee a terra:** proposta, una linea color avorio si accende un attimo sulla strada che sta per fare.
- **Sigla e icona provvisorie:** proposta `REG` e la sagoma della regina degli scacchi.

Passi:
1. **Le regole** (`game/queen.odin`): la carta, l'effetto, le 8 linee col tracciato delle linee delle carte, la corsa e
   il colpo come azione d'attacco, il tempo fra i colpi, la scelta del più vicino. Eventi nuovi per la presentazione
   (posata, corsa, colpo, fine).
2. **Salvataggio:** come per il nido.
3. **Aspetto provvisorio:** una regina degli scacchi semplice; la corsa come una scivolata veloce lungo la linea.
4. **La IA la conosce** (regola per sempre):
   - la voce della carta: le caselle da provare (quelle che vedono più nemici sulle loro linee, o che chiudono il
     corridoio da cui arriva un bruto, mai una che ti chiude la fuga);
   - il valore oltre l'orizzonte: i colpi che restano, per la probabilità di avere un nemico in linea;
   - la voce dell'oggetto nuovo: ferma i passi anche a te, e la copia lo sa;
   - puzzle: la Regina sulla diagonale di due nemici colpisce il più vicino; la Regina che chiude un corridoio; nessuna
     Regina dove ti chiuderebbe in un angolo.
5. **Laboratorio:** atto `regina` (`ODIN_PP_LAB_ONLY=regina`) nell'arena IA: un nemico che entra in diagonale, la
   corsa, il colpo, il più vicino fra due, una linea fermata da un muretto. Catture `odin_pp_regina_NN.png`.
6. **Test:** le 8 linee e i loro fermi, la corsa fino alla casella accanto, il danno coi potenziamenti e sul tick, i 2 s
   fra i colpi, il più vicino e l'ordine a pari distanza, la casella occupata (nessuno ci passa), nessuno la colpisce,
   la fine dopo 20 s, il salvataggio, la stanza che resta di 9208 byte.
7. Voce nuova in [registro-carte.md](registro-carte.md): «Carta nuova: Regina (solo laboratorio)», con «IA aggiornata».

Check della fase: i test della carta e del consigliere; gli atti `regina` e `ia`.

**Fatto quando:** nel laboratorio la Regina funziona come deciso e la IA la usa bene nei suoi puzzle; i test sono
verdi.

## Fase 12 — Regina: aspetto e suoni

**Obiettivo:** la Regina ha il suo aspetto e i suoi suoni.

Proposta (da confermare all'inizio della fase, guardando le catture):
- **La Regina:** un pezzo degli scacchi color avorio, con la corona a punte, nello stile di resina degli altri
  oggetti; nella corsa lascia una scia lungo la linea; al colpo si inclina come un pezzo che cattura; un anello alla
  base mostra i secondi che restano.
- **I colori:** avorio e oro scuro, lontani dal ciano della IA, dal rosso e dall'arancio delle minacce, dal verde delle
  mosse dei nemici.
- **L'icona:** la sagoma della regina, in una cella libera dell'atlante.
- **I suoni, da codice:** il «toc» di un pezzo posato sulla scacchiera, un fruscio veloce che sale (corsa), uno schiocco
  secco di legno (colpo), il pezzo che cade (fine).

Passi:
1. Il disegno della Regina, della corsa, del colpo e dei secondi.
2. L'icona.
3. I suoni (`tools/audio/sfx_queen.py`), solo nel laboratorio come gli altri.
4. Laboratorio: l'atto `regina` controlla catture e suoni.

Check della fase: i test del disegno, dei suoni e delle icone; l'atto `regina`.

**Fatto quando:** l'utente approva aspetto e suoni.

## Fase 13 — Lanciafiamme: regole e prototipo; la IA lo conosce

**Obiettivo:** nel laboratorio il Viandante impugna il lanciafiamme per 20 s, punta col mouse, brucia i nemici (al
massimo un colpo ogni 2 s per nemico, con la bruciatura), accende barili, ghiaccio e terreno, e intanto cammina come
sempre; e la IA sa quando consigliare la carta.

Proposta (i numeri in più sono di Claude, da confermare all'inizio della fase):
- **La carta:** `Card_Id.Flamethrower`, «Lanciafiamme», rara, 3 energia, prezzo 8, peso 60, 60 in spedizione,
  `Lab_Only` fino all'ultima fase, mira `Self`. Come le altre viste: **+2 s a potenziamento** (5 potenziamenti, al
  massimo 30 s) e **+2 s sul tick**.
- **Un'arma nuova della famiglia delle viste,** `First_Person_Weapon.Flamethrower`, con un segno nuovo nelle regole
  delle armi: la camera **resta sul tabellone**, senza discesa. Dalla famiglia prende i secondi, il divieto delle carte,
  il salvataggio e la pausa della IA (scelta dell'utente). Il suo stato sta nel `#raw_union`, non più grande dell'arma
  più grande di oggi: la stanza non cresce.
- **Il movimento di sempre:** WASD fa i passi sulle caselle del tabellone (non rispetto alla mira), al ritmo del
  Viandante (0,4 s), anche mentre spara. Un passo contro un nemico non lo colpisce: il passo si ferma.
- **La mira:** il punto del tabellone sotto il mouse dà la direzione. Il Viandante ruota verso di lei a **720° al
  secondo** (mezzo giro in un quarto di secondo): gira in fretta ma si vede girare, e la fiamma segue lui, non il mouse.
- **La fiamma:** lunga **3 caselle** dal bocchettone, larga da 0,4 a 1,2 caselle. Corre a **15 caselle al secondo**, e
  ogni pezzo di fiamma va dritto nella direzione in cui è uscito. Così, quando il Viandante gira, la punta resta
  indietro di circa un quinto di secondo (12 fotogrammi) e il centro di metà: è la scia che chiede l'utente. Le regole
  tengono le direzioni degli ultimi istanti, a passi fissi di 1/120 s come i passi fissi dei pugni, e colpiscono
  **dove la fiamma si vede**, non solo dove punta il bocchettone.
- **Il colpo:** ogni nemico toccato dalla fiamma prende **3 danni e 1 stack di bruciatura**, poi per **2 s** la fiamma
  non gli fa niente; se i nemici sono più di uno, ognuno ha il suo tempo. Una tabella piccola nello stato dell'arma
  ricorda i nemici bruciati da poco: è lo stesso principio del tempo di immunità di molti giochi, tenuto separato per
  ogni bersaglio.
- **Barili, ghiaccio e terreno:**
  - un barile toccato esplode, come quando lo prende la brace del demolitore;
  - un blocco di ghiaccio toccato si scioglie;
  - una casella dove la punta della fiamma resta almeno **1 s** prende fuoco come l'Incendio (1 di bruciatura), al
    massimo **un fuoco nuovo al secondo**; i fuochi a terra non toccano mai il Viandante.
- **Cosa la ferma:** muri e coperture sì, muretti bassi no.
- **In parole semplici:** un nemico tenuto nella fiamma per 20 s prende 30 danni diretti, e la sua bruciatura sale a 10
  stack: circa altri 30 danni mentre il lanciafiamme dura, poi 10 ogni 4 s finché vive. Con tre nemici nella fiamma, il
  triplo.

Domande all'utente all'inizio della fase:
- **I numeri** qui sopra: rotazione, velocità e larghezza della fiamma, fuoco a terra.
- **Schivata e difesa a tasti** mentre impugna il lanciafiamme. Proposta: restano come sempre.
- **Il tasto lasciato.** Proposta: la fiamma si spegne subito, ma quella già uscita finisce la sua corsa e brucia
  ancora.
- **Sigla e icona provvisorie.** Proposta: `LNF` e un lanciafiamme disegnato da codice.

Passi:
1. **Le regole** (`game/first_person_flame.odin`): l'arma, i secondi, la mira con la rotazione, la storia delle
   direzioni, la forma della fiamma e i colpi, la tabella dei 2 s, la bruciatura, barili, ghiaccio e fuoco a terra. Un
   comando a ogni fotogramma, come quello del bastone di Napoli (`First_Person_Club`): il tasto tenuto e il punto del
   mouse.
2. **Il ritmo dei passi:** `tactical_player_pace` dà il ritmo del Viandante anche ai passi del lanciafiamme (oggi solo a
   spada e arco); i passi seguono il tabellone, non la mira.
3. **I comandi** (`run/first_person_input.odin`, `drive_first_person_flame`): il mouse sul tabellone e il tasto
   sinistro tenuto.
4. **Salvataggio:** lo stato dell'arma in `First_Person_Save`, con la sua chiave, come le altre armi.
5. **Aspetto provvisorio:** una fiamma semplice fatta di puntini che vanno dritti (la scia si vede già); il Viandante
   che si gira verso il mouse.
6. **La IA lo conosce** (regola per sempre):
   - la voce della carta: quanto vale giocarla adesso. La copia fa girare il lanciafiamme con una regola semplice
     («punta il nemico più vicino») fino all'orizzonte, e conta i secondi che restano oltre l'orizzonte;
   - il comando nuovo nella tabella dei comandi, escluso: mentre il lanciafiamme dura la IA si ferma (scelta
     dell'utente);
   - puzzle: con tre nemici vicini la IA consiglia il lanciafiamme; con un nemico solo a 2 di vita consiglia il colpo
     a mano.
7. **Laboratorio:** la carta nel mazzo dell'arena «Prima persona» (muri, nicchie, coperture, un arciere e un bruto),
   più due barili e un blocco di ghiaccio. Un atto nuovo, `lanciafiamme` (`ODIN_PP_LAB_ONLY=lanciafiamme`):
   - il Viandante gira la fiamma da un nemico all'altro, e si vede la scia;
   - un nemico preso due volte a 2 s di distanza, con la bruciatura che sale;
   - un muro che ferma la fiamma e un muretto che non la ferma;
   - un barile che esplode, il ghiaccio che si scioglie, il fuoco a terra;
   - il Viandante che cammina mentre spara.

   Catture `odin_pp_lanciafiamme_NN.png`.
8. **Test:**
   - 3 danni e 1 bruciatura a colpo; mai due colpi allo stesso nemico in meno di 2 s; più nemici insieme;
   - la fiamma colpisce dove si vede, anche mentre il Viandante gira;
   - muri sì, muretti no; barili, ghiaccio e fuoco a terra;
   - i passi al ritmo di sempre; nessuna carta e nessun colpo a mano mentre dura;
   - i secondi coi potenziamenti e sul tick; il salvataggio; la stanza che resta di 9208 byte.
9. Voce nuova in [registro-carte.md](registro-carte.md): «Carta nuova: Lanciafiamme (solo laboratorio)», con «IA
   aggiornata».

Check della fase: i test della carta, delle armi della vista e del consigliere; gli atti `lanciafiamme` e
`prima_persona`.

**Fatto quando:** nel laboratorio il lanciafiamme funziona come deciso e l'utente lo prova; i test sono verdi.

## Fase 14 — Lanciafiamme: aspetto e suoni

**Obiettivo:** la fiamma è bella da vedere e si sente.

Proposta (da confermare all'inizio della fase, guardando le catture):
- **La fiamma:** tante particelle lasciate nel mondo, non attaccate al bocchettone. Così, quando il Viandante gira, la
  fiamma si piega e resta indietro come l'acqua di una canna: è il modo dei motori di gioco, le particelle «nello spazio
  del mondo». I colori vanno dal bianco e giallo al bocchettone all'arancio e al rosso, fino al fumo scuro in punta; la
  luce si somma (fusione additiva), con un po' di fumo sopra. La fiamma illumina il pavimento di arancio, e l'aria
  calda tremola un poco.
- **Il lanciafiamme:** un modello 3D di carta fatto da codice, come i guantoni e l'asso di bastoni, col serbatoio sulla
  schiena e il bocchettone che punta esattamente dove gira il Viandante. Il cartoncino del Viandante si specchia a
  destra o a sinistra secondo la mira.
- **I nemici bruciati:** il lampo del colpo e una fiammella che resta sulla loro carta finché bruciano.
- **L'icona:** un lanciafiamme con la fiammata, in una cella libera dell'atlante.
- **I suoni, da codice:** lo scatto dell'accensione, il ruggito continuo della fiamma (un rumore filtrato che respira),
  lo sfiato quando si spegne, il crepitio sui nemici, il colpo sordo del barile che prende fuoco. Solo nel laboratorio,
  come gli altri.

Passi:
1. Le particelle, da una riserva fissa: nessuna memoria presa a ogni fotogramma, un solo lotto di disegno.
2. Il modello del lanciafiamme e il Viandante che si specchia.
3. La luce sul pavimento e l'aria calda.
4. L'icona.
5. I suoni (`tools/audio/sfx_flamethrower.py`).
6. Laboratorio: l'atto `lanciafiamme` con una serie di catture fitte, per vedere bene la scia mentre gira.
7. Benchmark in ordine incrociato (ABBA) con la fiamma accesa: la fiamma si disegna a ogni fotogramma e non deve
   rallentare il gioco.

Check della fase: i test del disegno, dei suoni e delle icone; l'atto `lanciafiamme`; il benchmark ABBA.

**Fatto quando:** l'utente approva fiamma, scia e suoni.

## Fase 15 — Nel gioco vero

**Obiettivo:** se l'utente lo vuole, la IA, il Nido di ragni, la Regina e il Lanciafiamme passano al gioco vero, coi
film, i salvataggi e la verifica completa.

Proposta (da confermare all'inizio della fase):
- Le quattro carte entrano nelle offerte, nei negozi e nella collezione (si toglie `Lab_Only`).
- Ogni carta ha il suo film di «Mostra effetto».

Passi:
1. **Domanda all'utente:** le quattro carte entrano nelle offerte, nei negozi e nella collezione?
2. **I film di «Mostra effetto»** (`card_demo.odin`):
   - **IA**, una scena con i tre consigli: un nemico annuncia un colpo, la IA segna il passo per schivarlo e il
     Viandante lo fa; poi il mirino sul nemico, e il colpo a mano; poi la cornice su una carta e sulla sua casella, e la
     giocata. Il film fa girare la ricerca a pezzi (deterministica) e il Viandante segue il consiglio, con un'azione
     nuova del film;
   - **Nido di ragni:** il nido posato fra il Viandante e due nemici, i ragnetti che mordono, un inseguitore che lo
     colpisce e i secondi che calano;
   - **Regina:** la Regina posata, un nemico che entra nella sua diagonale, la corsa e il colpo, poi il secondo nemico;
   - **Lanciafiamme:** il Viandante gira la fiamma da un nemico all'altro (si vede la scia), la bruciatura che sale, un
     barile che esplode e il fuoco a terra; un'azione nuova del film tiene il tasto e muove la mira.

   I test controllano che ogni film mostri i suoi eventi.
3. **Run, spedizione e campagna:** i salvataggi (i secondi della IA stanno nel giocatore; nido, ragnetti e Regina sono
   oggetti; il lanciafiamme sta nella vista); i costi in spedizione (50, 40, 60, 60); la vita massima di 32 in
   spedizione.
4. **La regola per sempre:** si controlla che `AGENTS.md`, `CLAUDE.md` e [sviluppo.md](sviluppo.md) dicano ancora il
   vero, e che le tabelle della IA abbiano tutto quello che il gioco ha in quel momento (anche quello arrivato da altri
   rami).
5. **Verifica completa:** `scripts/check.ps1`, la prova completa del laboratorio, il benchmark in ordine incrociato col
   commit di partenza `6ea365b`. Le misure si spiegano in parole semplici.
6. **Documenti:** le regole ([meccaniche.md](regole/meccaniche.md)), il registro delle carte, il CHANGELOG, il README.
7. **Partita di prova con l'utente** e ritocco dei pesi e dei numeri delle due carte.

**Fatto quando:** l'utente approva e la verifica completa è verde.

## Rischi

- **La copia che tocca la stanza vera.** È il rischio più grave: basta un puntatore dimenticato e la ricerca cambia il
  gioco vero. Per questo la Fase 1 copia seguendo `destroy_room` (che elenca tutto quello che la stanza possiede), ha i
  test byte per byte, un allocatore che conta e il test dei campi con `core:reflect`, che fallisce quando qualcuno
  aggiunge un campo che la copia non conosce.
- **Le cose fuori dalla stanza.** La copia usa le regole vere, quindi una carta nuova è subito nella IA. Ma quello che
  sta fuori dalla stanza, come i gruppi della spedizione o i nemici che arrivano nel laboratorio (`sandbox_tick`), la
  copia non lo fa muovere. Il test di equivalenza della Fase 1, la Fase 6 e la Fase 7 lo tengono sotto controllo.
- **La regola per sempre aggirata.** Qualcuno potrebbe «spegnere» un controllo per far compilare (un `#partial`, una
  voce finta nella tabella). `AGENTS.md` e `CLAUDE.md` lo vietano, e ogni voce della tabella delle carte deve avere un
  puzzle che passa. Dagli altri PC la regola arriva solo quando il ramo va sul server: fino ad allora vale il controllo
  del codice al momento di unire i rami.
- **Il peso della stanza (8 byte liberi).** Lo stato della IA sta nel giocatore e nel consigliere; il contatore delle
  pozze sta nei 4 byte liberi in fondo a `Ground_State`; nido, ragnetti e Regina sono oggetti della lista della stanza,
  che sta fuori dai 9 KB. La stanza resta di 9208 byte.
- **Troppi oggetti.** Una stanza tiene 32 oggetti: due nidi con i loro ragnetti (al massimo 2 o 3 vivi a nido) e una
  Regina ci stanno, ma con tanti barili e trappole il limite si avvicina. Se è pieno, il ragnetto non esce (e il test lo
  prova).
- **La Regina che chiude la strada.** Occupa la sua casella e corre accanto ai nemici: può chiudere un corridoio anche
  al Viandante. Dura 20 s, la IA lo sa (lo prova un puzzle), e il disegno mostra dove sta per andare.
- **La fiamma che si vede e quella che colpisce.** Se fossero diverse, il giocatore si sentirebbe imbrogliato. Per
  questo le regole tengono la storia delle direzioni della fiamma, e un test confronta la forma disegnata con quella
  delle regole.
- **Troppa bruciatura.** Gli stack non calano mai: tenere un nemico forte (un boss) nella fiamma a lungo gliene dà
  tanti. I 2 s fra un colpo e l'altro li tengono a 10 in 20 s; la prova automatica di un minuto (come quella delle
  viste) e la partita di prova dell'utente lo controllano.
- **Barili e fuoco vicino al Viandante.** Un barile che esplode accanto a lui lo ferisce, come oggi; i fuochi a terra
  invece non lo toccano mai. I fuochi sono al massimo 32 per stanza, e il lanciafiamme ne accende al massimo uno al
  secondo.
- **Le particelle della fiamma e le prestazioni.** Una riserva fissa di particelle, nessuna memoria presa a ogni
  fotogramma, un solo lotto di disegno; il benchmark ABBA della Fase 14 lo misura.
- **Il thread.** Due thread che toccano la stessa memoria sono il bug più difficile da trovare. Regola fissa: il thread
  non legge mai la stanza vera, solo la fotografia fatta dal gioco; il consiglio torna in un triplo buffer; nel
  fotogramma non ci sono lock. Il calcolo a pezzi resta come riserva.
- **Troppe mosse da provare** (carte con molti bersagli, 32 nemici, mappe grandi). La ricerca le tiene sotto controllo
  con bersagli limitati, profondità crescente, tabella delle situazioni e budget in nodi. Un consiglio c'è sempre,
  anche se meno profondo.
- **La difesa a tasti** dura 1,2 s (0,45 s la parata). La IA ha il tempo di pensare, perché il mondo è fermo, ma il
  segno deve leggersi in un attimo.
- **Il «sa tutto».** La IA conosce i nemici nella nebbia e le pescate, quindi un consiglio può sembrare strano («perché
  non vado lì?»). Il disegno non svela i nemici nascosti (domanda della Fase 5). È la scelta dell'utente.
- **I tempi veri.** Il giocatore non preme subito. La ricerca riparte col tempo che passa e usa un margine di reazione;
  se nel frattempo arriva un battito, la situazione cambia e la ricerca riparte.
- **Le misure sul portatile** variano dal 7 al 21% da una corsa all'altra: si confrontano sempre vecchio e nuovo codice
  in ordine incrociato (ABBA).
- **Il lavoro in parallelo.** `piano-napoli` e `piano-prima-persona` sono rami di altre sessioni. Questo piano parte da
  `piano-napoli` e non li modifica; il checkout principale non si tocca.

## Fonti

Ricerca *anytime* e profondità crescente:
- [Time Management (Chessprogramming wiki)](https://www.chessprogramming.org/Time_Management): come si divide il tempo
  di una ricerca, guardando anche quanto cambia la mossa migliore da un giro all'altro
- [Iterative deepening (Mediocre Chess)](https://mediocrechess.sourceforge.net/guides/iterativedeepening.html) e
  [Time management (Mediocre Chess)](https://mediocrechess.sourceforge.net/guides/timemanagement.html): fermarsi a
  metà di un giro e tenere il risultato dell'ultimo giro finito
- [Time Management for Monte Carlo Tree Search (Baier, Winands)](https://dke.maastrichtuniversity.nl/m.winands/documents/time_management_for_monte_carlo_tree_search.pdf):
  MCTS si può fermare in qualunque momento, con più precisione della profondità crescente

Pensare in anticipo e copia della situazione:
- [Pondering (Chessprogramming wiki)](https://www.chessprogramming.org/Pondering) e
  [Permanent brain (Wikipedia)](https://en.wikipedia.org/wiki/Permanent_brain): pensare durante il tempo
  dell'avversario e riempire la tabella delle situazioni
- [Copy-Make (Chessprogramming wiki)](https://chessprogramming.org/Copy-Make) e
  [Unmake Move (Chessprogramming wiki)](https://chessprogramming.org/Unmake_Move): copiare la situazione invece di
  disfare la mossa
- [Zobrist Hashing (Chessprogramming wiki)](https://www.chessprogramming.org/Zobrist_Hashing) e
  [Transposition table (Wikipedia)](https://en.wikipedia.org/wiki/Transposition_table): l'impronta della situazione e la
  tabella delle situazioni già viste

Ricerca deterministica:
- [fishnet-tuning](https://github.com/niklasf/fishnet-tuning): un thread e un numero fisso di nodi, e l'hardware non
  conta più
- [SPEC CPU 2026, 706.stockfish_r](https://ftp.spec.org/cpu2026/docs/benchmarks/706.stockfish_r/706.stockfish_r.html):
  solo la ricerca a un thread è deterministica

Dadi e caso:
- [Expectiminimax (Wikipedia)](https://en.wikipedia.org/wiki/Expectiminimax): i nodi del caso fanno la media pesata
  delle possibilità
- [Berkeley CS188, expectimax (lezione)](https://inst.eecs.berkeley.edu/~cs188/archive/fa23/assets/lectures/cs188-fa23-lec07.pdf)
- [Writing a 2048 AI (Robert Xiao)](https://www.robertxiao.ca/hacking/2048-ai/): expectimax con tabella delle
  situazioni e taglio delle situazioni improbabili

MCTS e giochi in tempo reale:
- [A Survey of Monte Carlo Tree Search Methods (Browne e altri, 2012)](https://turing.iimas.unam.mx/~luis/cursos/IA2022-1/lecturas/SurveyMCTS.pdf)
  ([scheda](https://cris.maastrichtuniversity.nl/en/publications/a-survey-of-monte-carlo-tree-search-methods))
- [Open Loop Search for General Video Game Playing (Perez-Liebana e altri, GECCO 2015)](https://repository.essex.ac.uk/14734/):
  ricerca ad albero e piani a orizzonte mobile nei giochi in tempo reale
- [Analysis of Vanilla Rolling Horizon Evolution Parameters (Gaina e altri, 2017)](https://arxiv.org/pdf/1704.07075) e
  [Population Seeding Techniques for Rolling Horizon Evolution (Gaina e altri, 2017)](https://arxiv.org/pdf/1704.06942):
  i piani a orizzonte mobile, a confronto con MCTS
- [sts_lightspeed](https://github.com/maxisawesome/sts_lightspeed): un simulatore veloce del combattimento di Slay the
  Spire, fatto apposta per la ricerca ad albero

Posizione e pericoli:
- [Modular Tactical Influence Maps (Dave Mark, Game AI Pro 2, capitolo 30)](https://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter30_Modular_Tactical_Influence_Maps.pdf):
  la mappa del pericolo che informa la scelta, senza decidere da sola

Giochi che annunciano le mosse dei nemici o che aiutano il giocatore:
- [Road to the IGF: Subset Games' Into the Breach (Game Developer)](https://gamedeveloper.com/game-platforms/road-to-the-igf-subset-games-i-into-the-breach-i-):
  gli attacchi annunciati, perché ogni sconfitta sia colpa del giocatore
- [Into the Breach (GameSpot)](https://gamespot.com/reviews/into-the-breach-review-a-mechanized-masterpiece/1900-6416865/)
  e [Into the Breach (Nintendo Life)](https://nintendolife.com/reviews/switch-eshop/into_the_breach): ogni azione del
  nemico si vede prima, con l'ordine
- [Best Design 2019: Slay the Spire (PC Gamer)](https://www.pcgamer.com/uk/best-design-2019-slay-the-spire) e
  [How to Read Enemy Intent in Slay the Spire 2](https://sts2.untapped.gg/guides/how-to-read-enemy-intent): le
  intenzioni dei nemici sopra la testa
- [Super Guide (Super Mario Wiki)](https://www.mariowiki.com/Super_Guide): l'aiuto di Nintendo che, se lo chiedi, gioca
  il livello al posto tuo
- [How are moves classified? (Chess.com)](https://support.chess.com/en/articles/8572705-how-are-moves-classified-what-is-a-blunder-or-brilliant-and-etc):
  una mossa giudicata da quanto perde rispetto alla migliore, come l'avviso della IA

Thread e dati condivisi:
- [package core:sync (Odin)](https://pkg.odin-lang.org/core/sync)
- [TTripleBuffer (Unreal Engine)](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Core/TTripleBuffer):
  il triplo buffer senza blocchi fra due thread

Il Nido di ragni e la Regina:
- [Chess queen (Chess.com)](https://www.chess.com/terms/chess-queen) e
  [Definition: Chess Queen (ProofWiki)](https://proofwiki.org/wiki/Definition:Chess_Queen): la regina va di quante
  caselle vuole nelle 8 direzioni e non salta i pezzi
- [Spiderlings (Dota 2 Wiki)](https://dota2.fandom.com/wiki/Spiderlings) e
  [Broodmother (Liquipedia)](https://liquipedia.net/dota2/Broodmother): i ragnetti evocati con una vita breve, che
  corrono sul nemico
- [Practical Taunt (TV Tropes)](https://www.tvtropes.org/pmwiki/pmwiki.php/Main/PracticalTaunt) e
  [Decoy (Warframe Wiki)](https://wiki.warframe.com/w/Decoy): l'esca che si prende i colpi al posto del giocatore

Il Lanciafiamme:
- [Flame Thrower (Team Fortress 2 Wiki)](https://wiki.teamfortress.com/wiki/Flame_Thrower) e
  [Jungle Inferno Update (Team Fortress 2 Wiki)](https://wiki.teamfortress.com/wiki/Jungle_Inferno_Update): il
  lanciafiamme del Pyro, la bruciatura che dura quanto la fiamma ti ha toccato
- [TrailModule.worldSpace (Unity)](https://docs.unity3d.com/ScriptReference/ParticleSystem.TrailModule-worldSpace.html)
  e [Spawn particles with the rotation of the emitter (Unity Discussions)](https://discussions.unity.com/t/spawn-particles-with-the-rotation-of-the-emitter/663799):
  le particelle lasciate nello spazio del mondo restano indietro quando chi le spara gira
- [Quaternion.RotateTowards (Unity)](https://docs.unity3d.com/450/Documentation/ScriptReference/Quaternion.RotateTowards.html):
  girare verso un bersaglio con una velocità massima, senza mai superarlo
- [Invincibility frame (Terraria Wiki)](https://terraria.wiki.gg/wiki/Invincibility_frame): il tempo in cui lo stesso
  colpo non fa di nuovo danno allo stesso bersaglio, tenuto separato per ogni fonte di danno

La regola per sempre:
- [AGENTS.md, il formato aperto per gli agenti (InfoQ)](https://infoq.com/news/2025/08/agents-md/): il file che leggono
  Codex, Jules, Cursor, Aider, RooCode e Zed
- [CLAUDE.md e gli import con @ (documentazione di Claude Code)](https://code.claude.com/docs/en/claude-md): Claude Code
  legge `CLAUDE.md`, non `AGENTS.md`, e può importarlo con `@AGENTS.md`
- [Make CLAUDE.md Follow AGENTS.md (travis.media)](https://travis.media/blog/claude-md-import-agents-md): lo stesso
  import, senza collegamenti simbolici (che su Windows chiedono i permessi di amministratore)
- [Overview, `#partial switch` (Odin)](https://odin-lang.org/docs/overview/): lo `switch` su un elenco che deve avere
  tutte le voci, salvo `#partial`

## Appendice A — Le richieste dell'utente, parola per parola

La prima richiesta (3 novembre 2026):

> Quello che deve fare la carta si chiama IA, che sta per appunto intelligenza artificiale, ed è una carta che per 30
> secondi ti consiglia la miglior mossa da fare. Mi spiego. Da quando la usi ti appaiono delle indicazioni che ti
> guidano, per esempio, se la miglior mossa in quel momento della partita è muoversi, ti consiglia la casella in cui
> devi muoverti per evitare, non so, nemici, attacchi, o per spostarsi in modo adeguato per poi riuscire anche
> effettivamente a colpire nemici o mettersi in una posizione tattica. Se invece, per esempio, dovesse consigliare di
> usare una carta, ti illumina la carta da usare e quando ce l'hai in mano illumina la casella su cui dovrebbe usarla,
> se è un nemico, se è una casella per terra, dipendentemente dalla carta. Se invece ti consiglia di attaccare
> manualmente, quindi spostando il personaggio contro un nemico, ti fa illuminare la casella del nemico in un colore. In
> ogni caso, quello che deve fare la carta è stare costantemente in stato di ricerca della mossa migliore. Dato che è
> un gioco comunque abbastanza dinamico, questo calcolo deve essere abbastanza veloce. E anche consecutivo. Quindi deve
> anche pensare ai passi avanti rispetto a quello calcolato appena dopo. E anche deve pensare al fatto che il giocatore
> potrebbe non seguire le indicazioni che gli dà la carta e fare di testa sua. Quindi deve calcolare anche quelle
> casistiche. Quello che appunto deve fare la carta è quindi è simulare un'intelligenza superiore che ti consiglia
> sempre la mossa successiva migliore che puoi fare.

Le risposte scritte dall'utente alle prime domande:

> **Mossa migliore:** equilibrata ma se una carta serve per evitare danni o per uccidere più in fretta/fare più danni
> allora non tiene conto di sprecarla, a parità di danni e utilità, consiglia l'opzione che non prevede l'uso di una
> carta. La carta deve tenere conto nei suoi calcoli lo stato della partita in cui il giocatore si trova, più è vicino
> a completare la run, quindi meno nemici in mappa ci sono/luoghi da visitare ci sono, incomincia ad essere anche
> leggermente più aggressiva (la motivazione è che essendo più vicino a completare la partita allora è più difficile
> perdere tanta vita e c'è meno bisogno di non sprecare carte o risorse) ci può essere anche un aumento di aggressività
> se la carta rileva che nelle vicinanze ci sia una fontana che cura il giocatore (anche di luoghi che si trovano al
> di fuori del combattimento (la carta per funzionare deve sempre tenere conto anche di quello) )

> **Cosa sa la IA:** sa tutto tranne i risultati dei dadi

> **Cosa mette nel calcolo:** carte disponibili in mano, carte che vengono dopo, nemici in mappa, strutture vicine come
> fontana, così magari può consigliarti di essere più aggressivo; mano ed energia; tempi delle azioni; difesa a tasti

> **La fontana (prima risposta):** far curare la fontana in questo piano ma fai contare alla carta ia tutte le cure
> vere presenti, sia carte che altre fonti (ad eccezione della canna da pesca)

La seconda richiesta (3 novembre 2026):

> Vorrei che nel piano fossero aggiunte anche altre due corte. E vorrei anche un'aggiunta sulle regole generali dello
> sviluppo da ora in avanti, che comprende il fatto che dopo la creazione della carta IA, ogni volta che viene aggiunto
> un qualsiasi materiale di gioco all'interno della cartella di lavoro, cioè comunque all'interno del gioco, venga anche
> richiesto qualsiasi posto aggiuntivo, cioè qualsiasi cosa io faccia fare sia da questo PC che da altri, voglio che
> venga ricalcolata la funzionalità della carta IA, in modo tale che la carta IA ha sempre tutte le informazioni
> esistenti per far funzionare il suo funzionamento, cioè quello di dover calcolare tutte le cose migliori sempre. Deve
> avere sempre tutte le informazioni pronte. Le due carte che voglio aggiungere al piano di lavoro sono la prima e una
> carta nido che ogni tot secondi fa spawnare dei piccoli ragnetti intangibili che cercano il nemico più vicino e si
> fanno un effetto kamikaze, cioè non che non devono esplodere, però gli fanno un morso, gli fanno poco danno e poi
> muoiono in automatico. Questo nido può essere attaccato dai nemici, quindi ha una vita propria. Quando questa vita
> finisce, l'effetto della carta finisce. E oltre a questo, la carta ha una durata, cioè tu lo piazzi per terra e può
> spawnare un ragnetto ogni x secondi per un totale di 20 secondi. Dopo 20 secondi la carta piazzata viene distrutta.
> Se un nemico colpisce la struttura invece di avere una vita effettiva numerica, semplicemente toglie un numero di
> secondi alla fine della carta. Il numero di secondi che toglie non è dipendente dal danno che gli viene fatto, ma ha
> un calare di secondi standard per qualsiasi tipo di attacco da qualsiasi tipo di nemico. Questo numero di calo vorrei
> che lo bilanciassi tu. La seconda carta che vorrei aggiungere invece è un alfiere, come se fosse degli scacchi, che,
> o anzi meglio una regina, che e si tratta di un oggetto piazzabile sulla griglia, è intangibile dai nemici, ovvero non
> può essere distrutto, ha un timer di fai 20 secondi, poi magari bilancio tu in base all'effetto della carta, e quello
> che fa ha un range, cioè una portata di tiro infinita, ovvero per tutta l'area di combattimento della griglia, e
> appena un nemico entra in gittata di tiro, la regina corre come se fosse per la traiettoria e avvicina il nemico
> piazzandosi fianco a lui e lo colpisce facendogli un X di danno, valore che devi bilanciare tu. Se più nemici entrano
> contemporaneamente nella sua area di tiro, va da quello più vicino. per La sua area di tiro prende la griglia come se
> fosse una schacchiera e l'area di tiro è definibile dalle mosse della regina desgli scacchi, in sostanza può muoversi
> come lei.

Le risposte scritte dall'utente alle seconde domande:

> **La fontana (dopo aver saputo della FONTE):** Tolgo la fase della fontana

> **Dove scrivere la regola per sempre:** documenti, un CLAUDE.md e qualcosa che intervenga anche in caso di uso di
> altre IA come codex

La terza richiesta (3 novembre 2026):

> vorrei aggiungere una nuova carta nel documento del piano di lavoro. Questa carta permette al giocatore di
> equipaggiare un lanciafiamme, mentre è equipaggiato non può usare altre carte o attaccare normalmente, per 20 secondi
> il giocatore può usare un lanciafiamme che può essere usato sparando col tasto sinistro premuto, si può fare danno
> ripetuto sullo stesso nemico ma con un delay di prendere danno di 2 secondi da un hit ad un altro, ovvero se sparo
> sullo stesso nemico per tanto tempo esso prende danno una volta ogni due secondi. Insieme al danno il nemico o i
> nemici colpiti ottengono anche uno stack di status di bruciatura. Mentre stai usando questa carta, il giocatore guarda
> sempre nella direzione del mouse, quindi quando il mouse si sposta per esempio da destra a sinistra, anche il
> giocatore ruota fino a puntare a destra. (ruota costantemente per puntare la direzione del mouse) Girando la visuale
> decidi dove si spara con il lanciafiamme, la fiamma sparata di continua segue il movimento del lanciafiamme che segue
> la rotazione del personaggio. L'effetto della fiamma che cambia di posizione deve essere fatto in modo tale da
> rimanere per qualche frame nella posizione antecedente allo spostamento per dare un senso di realismo migliore.
> Durante l'uso di questa carta il movimento rimane quello del gioco standard, quindi il giocatore può spostarsi nelle
> caselle anche mentre spara.

Le risposte dell'utente alle domande sul Lanciafiamme: rara, 3 energia; 3 danni e 3 caselle; la IA si ferma come nelle
viste; la fiamma la fermano muri e coperture, e accende anche barili e terreno.
