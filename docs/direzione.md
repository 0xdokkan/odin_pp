[← Odin PP](../README.md)

# Direzione del gioco

Documento di direzione, versione 1.15 (22 ottobre 2026). Fissa dove va il gioco in
quattro ambiti: **Mappa**, **Progressione**, **Gameplay** e **Design**. Gli altri
documenti descrivono il gioco di oggi e restano validi finché una fase della
[roadmap](#6-roadmap) non ne sostituisce le regole.

Le voci marcate *(per ora)* sono **confermate momentaneamente**: valgono come
regole quando comincia lo sviluppo, e si possono rivedere con le prove e le
partite. Tutte le altre sono decise. Il riepilogo è in [Decisioni](#5-decisioni).

## In breve

Un robot che si è ribellato al suo creatore è costretto a rigiocare, dentro la
propria memoria virtuale, il gioco che il creatore amava, finché non lo batte.
Ogni **bioma** è una mappa aperta e desolata di neon e poligoni. Il robot la
esplora a piedi o in sella a una **mount** e combatte a battiti, con il suo mazzo,
nei **punti d'interesse**. Con l'**esperienza** potenzia le carte e intanto
riempie lo **zaino**. Se batte il **boss** si estrae: gioca un **minigioco** del
bioma e porta a casa ciò che ha raccolto. Se muore perde lo zaino, ma ciò che ha
*scoperto* resta nella sua memoria.

### Pilastri

| Pilastro | Che cosa significa nel gioco |
|---|---|
| Esplorare il vuoto | una mappa aperta, grande ma leggibile, senza nebbia, con punti segnati e segreti da trovare guardando il mondo |
| Combattere a tempo | il combattimento a battiti di oggi senza la finestra a tempo: intenti leggibili, critici sul battito, carte |
| Rischiare per portare a casa | ogni run è un'estrazione: lo zaino è in gioco finché il boss non cade |
| La memoria resta | scoperte, segreti, biomi sbloccati e la serie sopravvivono alla run fallita |
| Carta nel vuoto digitale | personaggi e oggetti di cartoncino dentro un mondo low poly di neon, senza texture |

### Glossario

| Termine | Significato |
|---|---|
| Bioma | una mappa aperta con il suo boss, i suoi nemici, la sua mount e i suoi minigiochi |
| Ramo | uno dei tre bracci della galassia (la discesa, l'ascesa, la paura), di tre biomi ciascuno |
| Corsia | il pericolo di un bioma che scatta su una fila o una colonna, come la Furnace di oggi |
| Run | una spedizione in un bioma, dall'ingresso all'estrazione o alla morte |
| Hub | il luogo fra una run e l'altra: deposito, zaino, mappa dei biomi, progressi |
| Galassia | la mappa dei biomi nell'hub: isolette 3D sparse nel vuoto, una per ogni bioma già sbloccato |
| POI | punto d'interesse: un luogo della mappa con un contenuto (nemici, bottino, scoperta, servizio) |
| Segreto | un luogo che l'ologramma non segna finché non lo si trova esplorando |
| Scontro | lo stato di combattimento: comincia con l'ingaggio, finisce quando nessun nemico insegue più |
| Zaino | l'inventario della run: una griglia limitata dove ogni oggetto occupa spazio secondo forma e grandezza, più tre posti per le reliquie attive; morendo si perde tutto, estraendosi va nel deposito |
| Deposito | l'inventario permanente dell'hub |
| Casinò | la zona dell'hub dove si scommettono i crediti del deposito |
| Sospeso | lo spazio del menu dello zaino dove un oggetto aspetta un posto mentre si sistema la griglia |
| Scoperta | una carta resa ottenibile nelle run future, senza ottenerla subito |
| Pool | le carte che possono comparire in premi e offerte di una run |
| Punti potenziamento | quelli che dà ogni livello della run; si spendono per migliorare le carte del mazzo |
| Energia | la barra blu, come una stamina o un mana, da cui le carte pagano il loro costo |
| Estrazione | l'uscita dal bioma dopo il boss: minigioco e ritorno all'hub con lo zaino |
| Serie | le run vinte di fila senza morire |
| Slot | uno dei tre salvataggi: una partita intera, salvata di continuo |

## 1. Mappa

### 1.1 Il bioma come mappa aperta

- Ogni bioma è un'unica mappa aperta sulla griglia di oggi (una cella per passo),
  molto più grande di una stanza ma attraversabile. *(per ora)* Circa 96×96
  celle: 80×80 nei primi biomi, 112×112 negli ultimi. Oggi la stanza più grande
  è di 45×31. A piedi si attraversa in circa un minuto, in sella in 20–25 secondi.
- **Geografia fissa, contenuto variabile.** Ogni bioma ha la stessa geografia a
  ogni run: rilievi, monoliti, ingresso, tana del boss e segreti fissi. Il seed
  della run cambia i nemici, il bottino e quali POI sono attivi fra quelli
  possibili. È il mito di Sisifo: il robot risale la stessa collina, e ciò che
  ricorda (i segreti trovati, la mappa imparata) vale qualcosa.
- **Il bioma è finito.** I POI non si rigenerano e le pattuglie sono in numero
  fisso per run. Senza timer è il contenuto finito a chiudere la run: non si
  può accumulare esperienza all'infinito.
- **Nessun muro attorno.** Il pavimento finisce nel vuoto con un bordo luminoso,
  come già nel mondo neon. Dentro, rocce, monoliti e rovine fanno da coperture e
  da punti di riferimento.

### 1.2 Punti d'interesse

| POI | Contenuto | Come si risolve | Premio |
|---|---|---|---|
| Nido | un generatore di nemici | si attiva entrando nel suo centro; le ondate vanno ripulite | una carta fra tre ed esperienza; a volte un oggetto |
| Cache | bottino | si apre; a volte la custodiscono 1–2 nemici | oggetti, consumabili, reliquie, crediti |
| Archivio | un terminale | si legge | una **scoperta**: la carta entra nel pool delle run future |
| Officina *(per ora)* | un mercante | si spendono crediti | carte, rimozione di una carta, consumabili |
| Fonte *(per ora)* | un punto di ristoro | si usa una volta | cura |
| Prova | un elite o una sfida | si vince | una reliquia o un oggetto raro, molta esperienza |
| Tana del boss | il boss del bioma | si vince | l'**estrazione** |

- **Stati di un POI segnato.**
  - *Non visitato*: l'ologramma ne mostra un'area approssimativa e l'icona del tipo.
  - *Scoperto*: posizione esatta.
  - *Risolto*: spento.
- **Il Nido non chiude dentro.** Le ondate partono quando si entra nel suo
  centro. Uscendo dal suo raggio le ondate si interrompono e il nido resta
  attivo con i nemici rimasti *(per ora)*.
- **I segreti** non compaiono sull'ologramma finché non sono stati trovati.
  - *Che cosa sono*: cache e archivi nascosti dietro i rilievi o nelle zone
    vuote, un elite dormiente, i frammenti di memoria della storia.
  - *Come si trovano*: guardando il mondo (una luce diversa, un monolite fuori
    posto, un suono).
  - *Una volta trovati* restano segnati per sempre: è la memoria del robot.

### 1.3 L'ologramma

- `Tab` mostra il **bioma intero** in miniatura, sullo stesso fondale neon di
  oggi. Ci sono il robot, la tana del boss e i POI segnati in modo grossolano
  (un'area e un'icona, non la cella esatta). I segreti compaiono solo dopo
  essere stati trovati.
- In uno scontro il tempo continua mentre l'ologramma è aperto, come oggi.

### 1.4 Visibilità e camera

- **Niente fog of war.** Tutto ciò che la camera inquadra è visibile:
  scompaiono la vista locale (`--vision`) e i blocchi di nebbia.
- **Niente zoom né rotazione.** La camera ha angolo e distanza fissi, con un
  ampio margine di vista *(per ora: circa 25×15 celle attorno al robot)*, e lo
  segue con un leggero ritardo.
- **La rotella è delle carte.** In uno scontro sceglie le carte della mano e,
  nel piazzamento, gira l'oggetto da piazzare (vedi [Controlli](#33-controlli)).
- **Prestazioni.** Il mondo si disegna e si simula a blocchi (chunk). Lontano
  dal robot i nemici dormono.

### 1.5 Nemici nella mappa

- Il grosso dei nemici sta nei **POI**; nelle pianure girano **poche pattuglie**
  (2–4 nemici) che si possono affrontare o evitare.
- **Ingaggio.** Uno scontro comincia in tre casi:
  - un nemico ti vede entro il suo raggio *(per ora: 6 celle, con linea di vista)*;
  - un nemico ti colpisce;
  - attacchi tu.
- **Fine dello scontro.** Lo scontro finisce quando nessun nemico ingaggiato è
  vivo o ti insegue più *(per ora: un nemico smette di inseguire a 12 celle
  dalla sua zona)*.
- **Difficoltà.** Cresce con il bioma e, dentro il bioma, con la distanza
  dall'ingresso: zone esterne e POI lontani hanno più nemici e varianti più forti.

### 1.6 Boss ed estrazione

- La tana del boss è segnata sull'ologramma dall'inizio ed è sempre aperta. Si
  può tentare presto, ancora deboli, o tardi, dopo aver ripulito il bioma.
- Batterlo è l'unico modo per uscire: si apre il portale di estrazione (vedi
  [Estrazione e minigioco](#26-estrazione-e-minigioco)).

## 2. Progressione

### 2.1 Il ciclo

```text
HUB ── si sceglie il bioma, si prepara lo zaino ──► RUN NEL BIOMA
 ▲                                                    │  esplorare, combattere,
 │                                                    │  raccogliere, livellare
 │                                                    ▼
 │◄── zaino nel deposito, sblocchi ◄── MINIGIOCO ◄── BOSS BATTUTO
 │
 │◄── zaino perso, scoperte e segreti restano, serie azzerata ◄── MORTE
```

### 2.2 Che cosa dura e che cosa no

| Che cosa | Quanto dura |
|---|---|
| mazzo, carte ottenute e loro potenziamenti | la run |
| esperienza, livello e punti potenziamento | la run: ogni run riparte dal livello 1 |
| zaino | la run: morendo si perde **tutto**, anche ciò che era stato portato da casa e le reliquie attive; estraendosi tutto va nel deposito |
| deposito | sempre |
| carte scoperte, segreti trovati, biomi sbloccati, record dei minigiochi | sempre, anche quando la run fallisce |
| serie | fino alla prossima morte |

Tutto questo vale per slot: ogni slot è una partita a sé
([Salvataggi e slot](#210-salvataggi-e-slot)).

### 2.3 Le carte

- **Mazzo iniziale.** Ogni run parte dallo stesso mazzo base, uguale in tutti i
  biomi *(per ora: lo starter di oggi)*.
- **Pool.** All'inizio del gioco è un sottoinsieme del catalogo *(per ora: le
  comuni e alcune non comuni)*. Tutto il resto si scopre.
- **Ottenere una carta nella run.** Arriva dai premi dei Nidi e delle Prove (una
  fra tre, come oggi), dalle Officine e dagli eventi. Restano le regole di oggi
  su mazzo pieno, Skip e rarità.
- **Scoprire una carta.** Si scopre negli Archivi (anche segreti) e con imprese
  speciali. Oggi Titan Grip e Storm Crown si sbloccano vincendo il ring delle
  Tesla; il ring diventa il minigioco della City pop e lo sblocco passa lì
  *(per ora)*. La carta non entra nel mazzo: entra nel pool delle run
  future, anche se questa run finisce con la morte. L'hub ne tiene l'archivio,
  con Mostra effetto.
- **Prova meccaniche.** Nel laboratorio tutte le carte restano disponibili,
  scoperte o no.

### 2.4 Esperienza, livelli e punti potenziamento

- I nemici lasciano frammenti di esperienza, raccolti dalla calamita del bottino
  di oggi.
- Ogni livello dà **un punto potenziamento** *(per ora: il livello `n` costa
  `4 + 2n` esperienza; da tarare)*.
- **Un punto alza di un livello una carta del mazzo**, entro il suo limite: dadi
  dal D4 al D20, Lazzo fino a 5, il Cannone che al secondo diventa laser e così
  via. I punti si possono tenere da parte per le carte che arriveranno più avanti
  nella run.
- **I punti si spendono fuori dagli scontri**, dalla scheda del personaggio
  (mazzo), mai durante un combattimento.
- **A fine run** il livello e i punti non spesi si perdono, comunque finisca.
- **Niente più upgrade da Shop e Rest.** L'esperienza diventa la sola fonte di
  potenziamenti *(per ora: un consumabile raro può dare un punto)*.

### 2.5 L'inventario: zaino e deposito

- **Lo zaino è una griglia limitata** *(per ora: 8×5 celle)*. Ogni oggetto
  occupa le celle della sua forma e della sua grandezza, e lo spazio è il limite
  dello zaino: il gioco è far entrare ciò che conta.
- **Tre posti per le reliquie attive**, fuori dalla griglia. Solo le reliquie
  messe lì funzionano; quelle nella griglia si portano soltanto. Un posto tiene
  una reliquia di qualunque forma: la forma conta solo nella griglia. Le
  reliquie attive si cambiano solo fuori dagli scontri, così non si scambiano
  passive a metà combattimento. Morendo si perdono anche queste;
  estraendosi vanno nel deposito come il resto dello zaino.

  ```text
  reliquie attive  ┌───┐ ┌───┐ ┌───┐        arma impugnata  ┌───┐
                   │ r │ │ r │ │   │                        │ a │
                   └───┘ └───┘ └───┘                        └───┘

  ┌───┬───┬───┬───┬───┬───┬───┬───┐
  │ A │ A │ A │ R │ R │ c │ c │   │    A  un'arma lunga, 1×3
  ├───┼───┼───┼───┼───┼───┼───┼───┤    R  una reliquia a L
  │ s │   │   │ R │   │ c │ c │   │    c  una reliquia quadrata, 2×2
  ├───┼───┼───┼───┼───┼───┼───┼───┤    s  una pila di consumabili, 1×1
  │   │   │   │   │   │   │   │   │
  ├───┼───┼───┼───┼───┼───┼───┼───┤
  │   │   │   │   │   │   │   │   │
  ├───┼───┼───┼───┼───┼───┼───┼───┤
  │   │   │   │   │   │   │   │   │
  └───┴───┴───┴───┴───┴───┴───┴───┘

  sospeso  ┌───┬───┐
           │ n │ n │    n  l'oggetto appena raccolto, in attesa di un posto
           └───┴───┘
  ```

- **Le forme** sono fatte di celle *(per ora)*:

  | Categoria | Che cosa contiene | Forma tipica | Regole |
  |---|---|---|---|
  | Consumabili | cura, energia, una carta temporanea, un'esca per le pattuglie | 1×1; i più grossi 1×2 | si usano dallo zaino; in uno scontro costano tempo come un'azione |
  | Equipaggiamento | armi per l'attacco a urto (la Mannaia di ferro di oggi) e altri oggetti attivi | strisce da 1×2 a 1×3 | l'arma impugnata ha un posto suo, fuori dalla griglia; quelle di riserva stanno nella griglia |
  | Reliquie | passive come quelle di oggi | una forma sua, più grande quanto più è rara (vedi sotto) | funzionano solo nei tre posti attivi; nella griglia si portano e basta |
  | Crediti | l'oro di oggi | 1×1 | si spendono nelle Officine e nell'hub |
  | Frammenti di memoria | la storia | 1×1 | si portano a casa per leggerli |

- **Le reliquie hanno ciascuna una forma sua**, e più sono rare più sono grandi.
  Portarne una rara nella griglia costa spazio; nei posti attivi, invece, ognuna
  ne occupa uno solo.

  | Rarità | Celle *(per ora)* | Forme d'esempio |
  |---|---|---|
  | comune | 1–2 | un quadratino, una barretta da due |
  | non comune | 3 | una L corta, una barra da tre |
  | rara | 4 | una T, una S, un quadrato 2×2 |
  | leggendaria | 5–6 | una croce, una U, una L lunga |

- **Sistemare.** Gli oggetti si spostano trascinandoli. Mentre se ne sposta uno,
  la rotella lo gira di un quarto di giro, come nel piazzamento delle carte
  *(per ora)*. Un oggetto si posa solo dove tutte le sue celle sono libere.
- **Pile.** I consumabili uguali e i crediti si impilano nella stessa cella
  *(per ora: fino a 5 consumabili, 99 crediti)*.
- **Il sospeso.** Nel menu dello zaino, accanto alla griglia, un oggetto può
  restare momentaneamente sospeso: quello appena raccolto che non trova posto, o
  uno tolto dalla griglia per sistemare gli altri. Così si riordina senza perdere
  niente e senza frustrazione.
  - *Quanti* *(per ora)*: fino a 3 oggetti, di qualunque forma.
  - *Chiudendo lo zaino* *(per ora)*: ciò che resta sospeso torna a terra, dove
    sta il robot, dopo un avviso.
  - *Raccogliere* *(per ora)*: la calamita non prende ciò che non entra;
    raccogliendolo a mano (`E`), lo zaino si apre con l'oggetto già sospeso.
- **Zaino pieno.** Ciò che non entra e non si sistema resta a terra, come oggi
  l'arma con la riserva piena. Per fare posto si può sempre lasciare a terra un
  oggetto dello zaino.
- **In uno scontro** lo zaino si apre, ma il tempo continua *(per ora)*.
- **Il deposito** dell'hub conserva tutto ciò che è stato estratto, in una
  griglia più grande, a pagine *(per ora)*. Prima di una run si sistema lo
  zaino: è la posta in gioco.
- **Zaini più grandi** *(per ora)*: si trovano nei biomi e, una volta estratti,
  si scelgono nell'hub prima di partire.
- **Morte**: si perde tutto lo zaino.
- **Estrazione**: tutto lo zaino va nel deposito, comunque finisca il minigioco.
- **Una sola regola** *(per ora)*: tutto ciò che si raccoglie nella run va
  nello zaino ed è estraibile; non esistono oggetti validi solo per la run.

### 2.6 Estrazione e minigioco

- Battuto il boss si apre il portale e il robot entra in uno dei **minigiochi
  del bioma**, un cabinato della memoria del creatore.
- **Il risultato dà un bonus**, in stelle da 0 a 3 come oggi *(per ora)*:

  | Stelle | Bonus |
  |---|---|
  | 0 | nessuno |
  | 1 | crediti |
  | 2 | un oggetto |
  | 3 | un oggetto raro o una scoperta |

- **Comunque finisca**, lo zaino torna nel deposito e la run è vinta.
- **I minigiochi già pronti** si possono assegnare ai biomi:
  - Torre di Cenere (platform 2D)
  - Guglie Sospese (platform 3D)
  - Arena delle Braci (twin-stick)
  - Cripta delle Rune (FPS)
  - Sigilli della Cripta (puzzle)
  - Ring delle Ombre (picchiaduro)
  - 6 RANCH 7 (western a tempo), che diventa la slot del casinò dell'hub
    (vedi [L'hub](#32-lhub))

  Andranno riletti in chiave futuristica o da cabinato; ne arriveranno altri.
  L'assegnazione, per ora, è nelle [bozze dei biomi](#43-i-biomi-bozze).

### 2.7 Biomi e sblocchi

- Si parte dalla **Robotica cibernetica**. Vincere una run ne sblocca uno o più,
  secondo rotte fisse. La Robotica cibernetica apre il primo bioma di ciascuno
  dei tre rami; ogni altro bioma apre il successivo del suo ramo *(per ora:
  rami e ordine sono quelli delle [bozze](#43-i-biomi-bozze))*.
- Lo **Spazio** è l'ultimo: si apre quando gli altri dieci biomi sono vinti.
- Il bioma segreto del true ending è a parte (vedi
  [2.8](#28-il-finale-e-il-true-ending)).
- Il gioco **finisce** quando ogni bioma è stato vinto almeno una volta: è il
  finale normale.

#### La galassia

Nell'hub la mappa dei biomi è una **galassia**: tante isolette 3D sparse nel
vuoto, nello stile del gioco.

**La galassia mostra solo i biomi già sbloccati.** Un bioma che si aprirà più
avanti non si vede in nessun modo, nemmeno come sagoma: la sua isola non c'è
finché una vittoria non la apre. All'inizio del gioco ci sono soltanto l'isola
dell'hub e quella della Robotica cibernetica. L'unica eccezione è il bioma segreto dopo il finale
normale (vedi sotto).

- **Lo spazio.** È il vuoto nero del mondo neon, con l'alone rosso
  all'orizzonte, stelle come punti di neon e polvere di poligoni a fil di ferro.
  Niente texture.
- **Le isole.** Ogni bioma è un'isoletta che galleggia: una roccia nera
  sfaccettata con gli spigoli al neon, come le colline del mondo neon. Sopra
  c'è il bioma in miniatura nella sua tinta, con la sua geografia come la mostra
  l'ologramma (vedi la geografia fissa in
  [1.1](#11-il-bioma-come-mappa-aperta)). Le isole stanno a distanze e altezze
  diverse e ruotano piano su sé stesse.
- **L'hub** è anch'esso un'isola: quella da cui il robot parte.
- **Le rotte e le isole nuove.** Gli sblocchi sono rotte di luce. Vincendo un
  bioma, una rotta parte dalla sua isola verso il vuoto e alla sua fine l'isola
  nuova si forma, poligono per poligono: prima non c'era.
- **Stati di un'isola.**

  | Stato | Come si vede |
  |---|---|
  | nuova | appena formata alla fine della sua rotta; resta segnata finché non la si visita *(per ora)* |
  | aperta | accesa nella sua tinta, con un faro che pulsa |
  | vinta | in cima un'insegna di cartoncino (il boss battuto) e le stelle del miglior minigioco |
  | nella serie | le isole vinte nella serie in corso sono unite da una catena di luce |

- **Scegliere un bioma.** Passando sopra un'isola compare il suo cartellino di
  carta: nome, boss, minigiochi, record. Scegliendola, la camera vola fino a lei
  e il cartoncino del robot salta dall'hub lungo la rotta: è l'ingresso nella
  run. *(per ora: si gira attorno alla galassia trascinando, senza zoom libero)*
- **L'isola segreta** non si vede prima del finale normale; ci sono solo indizi,
  come una stella che si spegne e si riaccende o un glitch. Dopo il finale
  appare come un'isola spenta ai margini della galassia, ancora chiusa: è la
  sola isola che si mostra prima di essere aperta, perché il finale deve
  lasciarla intravedere (vedi [2.8](#28-il-finale-e-il-true-ending)).

Schizzo della galassia vista dall'alto, solo per orientarsi: nel gioco le isole
sono sparse anche in altezza. Le rotte di luce sono `~`, `/` e `\`. È la
galassia a fine gioco, con tutti i biomi vinti; il giocatore la scopre un'isola
alla volta. I tre rami sono le braccia della galassia; Cyber è la Robotica
cibernetica, Cielo l'Isola nel cielo, Gotico il Southern gothic. Le rotte verso
lo Spazio si accendono solo quando gli altri dieci biomi sono vinti.

```text
       .               *                   .                    *
                  ( Far West )~~~~~( Egitto )~~~~~~( Inferno )~~
                /                                               \
  ( HUB )~( Cyber )~~( City pop )~~~( Montagne )~~~~( Cielo )~~~~~( Spazio )
                \                                               /
                  ( Giungla )~~~~~~( Vietnam )~~~~~( Gotico )~~~
       *               .                   *                    .    ( ? )
```

### 2.8 Il finale e il true ending

- **Il bioma segreto si mostra.** Dopo il finale normale, la galassia lo mostra
  come un'isola spenta ai margini, con un indizio esplicito della condizione.
  Prima del finale ci sono solo indizi impliciti: glitch e frammenti di memoria.
- **La condizione** è una **serie senza morti** che comprende una vittoria in
  **ogni** bioma, l'ultimo compreso: con le bozze di oggi, undici vittorie di
  fila.
  - Contano le run vinte di fila.
  - Una morte azzera la serie *(per ora: anche abbandonare una run)*.
  - Vale **dalla primissima run**: chi finisce il gioco senza mai morire apre il
    bioma segreto subito.
- **L'hub mostra la serie** *(per ora: solo dopo il finale normale, per non
  svelare il segreto)*.
- **Il bioma segreto** ha l'ultimo vero boss e porta al **true ending**.

### 2.9 La mount

- **Uso.** Si evoca e si congeda fuori dagli scontri. È molto più veloce del
  passo a piedi *(per ora: tre volte)* e non si può usare in combattimento.
- **Forma.** Cambia in ogni bioma: un veicolo o una creatura del gioco di quel
  bioma (vedi le [bozze](#43-i-biomi-bozze)).
- **Ingaggio in sella.** Se un nemico ti ingaggia mentre sei in sella puoi
  provare a seminarlo, perché la mount è più veloce dei nemici base. Se ti
  colpisce vieni disarcionato e comincia lo scontro.
- **Limiti.** In sella non si giocano carte e non si aprono POI.
- **Tecnica.** Riusa il sistema delle cavalcate del Dinosauro: stampa di
  cartoncino sotto la carta del robot, sella, passo, giro come la carta. Il
  Dinosauro resta una carta da combattimento.

### 2.10 Salvataggi e slot

- **Tre slot.** Il gioco ha tre slot di salvataggio indipendenti. Ognuno è una
  partita intera: deposito, scoperte, segreti, biomi sbloccati, serie, record dei
  minigiochi e l'eventuale run in corso. Le impostazioni (video, audio,
  controlli) sono comuni a tutti gli slot *(per ora)*.
- **Ogni slot si può avviare.** Uno slot vuoto inizia una partita nuova; uno slot
  pieno riprende esattamente da dove si era rimasti, nell'hub o a metà run.
- **Un solo salvataggio per slot, aggiornato quasi sempre.** Non ci sono
  salvataggi manuali né punti di ripristino: lo slot si riscrive di continuo,
  così un crash non fa perdere il progresso.

  | Quando | Che cosa si salva |
  |---|---|
  | fuori dagli scontri | a ogni cambiamento che conta (oggetto raccolto, POI risolto, punto speso, ingresso e uscita da un bioma, ogni modifica nell'hub) e comunque ogni pochi secondi di esplorazione *(per ora: 10 s)* |
  | in scontro | fra un battito e l'altro, quando il mondo è stabile *(per ora)* |
  | sempre | alla chiusura del gioco e quando la finestra perde il focus |
  | mai | a metà di un cast, di un lancio di dadi o di un minigioco: vale l'ultimo salvataggio stabile, e un minigioco interrotto riparte dall'inizio *(per ora)* |

- **Dopo un crash** si riprende dall'ultimo salvataggio, perdendo al massimo pochi
  secondi.
- **Gli slot non si copiano.** Il menu degli slot permette solo di avviarli o di
  cancellarli. Con un solo salvataggio aggiornato di continuo, una morte o uno
  zaino perso non si annullano: la serie senza morti e la posta dello zaino
  restano vere.
- **Cancellare** uno slot chiede una conferma esplicita e non si può annullare
  *(per ora: due conferme)*.
- **Chiudere il gioco non è abbandonare.** La run riprende dove era; abbandonarla
  è una scelta esplicita.
- **Il menu degli slot** mostra, per ognuno, se è vuoto oppure i biomi vinti, il
  tempo di gioco, la run in corso (e in quale bioma) e la data dell'ultimo
  salvataggio *(per ora)*.

## 3. Gameplay

### 3.1 Il combattimento senza timer

- **Via la finestra a tempo**: il conto alla rovescia, `--decision-time` e lo
  stordimento quando il tempo finisce.
- **Il mondo continua a battere** sul suo orologio, un battito al secondo. I
  nemici agiscono ai loro ritmi, con gli stessi intenti, telegrafi, QTE e regole
  di oggi.
- **Restano i critici a tempo**: l'azione fatta entro 0,15 s dal battito è
  critica, con la [tabella di oggi](regole/combattimento.md#colpo-a-tempo)
  (diagonale solo sul battito, urto doppio, carte x1,5 e così via). Cambia solo
  il riferimento: non più il secondo del conto alla rovescia ma il battito del
  mondo, che l'HUD mostra.
- **Restano**: le azioni costano tempo, il cast di una carta ferma il mondo, i
  dadi sono una pausa.
- **L'energia diventa una barra blu**, come una stamina, ma blu perché è un
  mana. Il giocatore la gestisce: spendere tutto in una carta forte o tenersi
  margine per quelle piccole.
  - *Il costo* di ogni carta dipende dalla sua efficacia: le carte deboli costano
    poco, le più forti molto. *(per ora: una barra da 100 punti; costi da 10 a
    70, per esempio Strike 15, Cannone 40, Buco Nero 60, Bomb Marley 70; tutte le
    carte vanno ritarate)*
  - *Si ricarica* durante lo scontro, sull'orologio del mondo: si ferma quando il
    mondo è fermo (cast, dadi, pausa) *(per ora: 8 punti al secondo)*. Si
    ricarica anche con i consumabili.
  - *Una carta si gioca* solo se nella barra c'è tutto il suo costo.
  - *All'inizio di ogni scontro* la barra è piena; fuori dagli scontri non si
    ricarica né si spende *(per ora)*.
  - *Gli effetti* che oggi danno energia (carte, reliquie come Swift Soles)
    riempiono la barra di una quantità di punti *(per ora: 20 punti per
    ogni energia di oggi)*.
  - *L'HUD* mostra la barra blu al posto delle tacche; scegliendo una carta, la
    parte che costerebbe si accende sulla barra.
  - *Un potenziamento* migliora l'effetto della carta, non il suo costo, salvo
    le carte che lo dicono *(per ora)*.
- **La mano.**
  - All'inizio dello scontro si pescano 5 carte.
  - Senza finestre la mano si ricarica in un altro modo *(per ora: una carta
    ogni 4 battiti fino al massimo, più il Refocus di oggi)*.
  - Finito lo scontro la mano si mette via e il mazzo si rimescola per il
    prossimo.
- **Fuori dagli scontri** si cammina tenendo premuto, anche in diagonale, si
  interagisce con i POI, si usa lo zaino, si spendono i punti e si evoca la
  mount. Le carte che oggi funzionano a stanza liberata (la Canna da Pesca)
  funzioneranno fuori dagli scontri, con un limite da rivedere.

### 3.2 L'hub

| Zona | A che cosa serve |
|---|---|
| Deposito | gestire gli oggetti estratti e preparare lo zaino |
| Galassia | la mappa dei biomi: isolette 3D sparse nel vuoto, solo per i biomi già sbloccati, aperti o vinti ([2.7](#27-biomi-e-sblocchi)); da qui si parte |
| Progressi | statistiche, carte scoperte (con Mostra effetto), segreti, record dei minigiochi, serie |
| Cabinati *(per ora)* | rigiocare i minigiochi sbloccati per i record, senza premi |
| Prova meccaniche | il laboratorio delle carte di oggi |
| Casinò | un po' di sano gioco d'azzardo con i crediti del deposito: la slot del ranch, Tre in fuga, roulette e dadi (vedi sotto) |

#### Il casinò

Nell'hub si scommettono i **crediti del deposito**, mai denaro vero: i crediti
non si comprano. Ogni gioco si salva nello slot di salvataggio come il resto.

- **Puntate** *(per ora)*: da 5 a 50 crediti a giocata.
- **Il banco** tiene sempre un piccolo vantaggio, dal 2 al 5 % secondo il gioco,
  così il casinò non diventa una miniera di crediti. Le probabilità si
  verificano nei test con milioni di giocate simulate, come oggi i bot dei
  minigiochi.

##### La slot del ranch

È il minigioco 6 RANCH 7 di oggi, cambiato. Non è più una gara fra due cowboy e
non finisce più a tre monete; non è più un tempismo da premere a ogni scocco.

- **Come si gioca.** Si punta, e il robot va a cavallo da giù verso su per una
  pista con le monete. Si pensa solo ad andare avanti e a saltare le
  staccionate; le monete sulla strada si raccolgono passandoci sopra.
- **Il cowboy.** Accanto alla pista c'è un cowboy di cartoncino con la pistola
  già in mano, pronta a sparare. Ogni volta che il robot raccoglie una moneta,
  il cowboy spara. Dalla pistola esce una bandierina:
  - **MANCATO**: non succede nulla e si continua;
  - **BANG**: parte davvero il proiettile, che colpisce il robot. La giocata
    finisce e si perde tutto ciò che si era guadagnato.
- **Incassare.** In qualsiasi momento si può smettere e incassare il valore
  raggiunto.
- **Monete e incasso sono due numeri diversi.** Le monete raccolte servono solo
  a far vedere a che punto si è. L'incasso cresce a ogni moneta, e ogni moneta
  in più pesa più della precedente; ma ogni moneta in più rende anche più
  probabile il BANG, basso all'inizio.
- **Staccionata mancata** *(per ora)*: il cavallo inciampa e rallenta per un
  momento, senza perdere nulla; il rischio resta tutto nella pistola.
- **Comandi** *(per ora)*: `W` per andare avanti, `Spazio` per saltare, `Invio`
  per incassare.

**I numeri** *(per ora)*. Il BANG parte dal 2 % e cresce di 3 punti a ogni
moneta, fino a un massimo del 60 %. L'incasso è calcolato in modo che, a
qualunque moneta ci si fermi, la puntata renda in media il 98 %: il banco tiene
il 2 %.

| Moneta | Probabilità di BANG | Si arriva fin qui | Incasso | Con 10 crediti |
|---|---|---|---|---|
| 1 | 2 % | 98 % | ×1,00 | 10 |
| 2 | 5 % | 93 % | ×1,05 | 10 |
| 3 | 8 % | 86 % | ×1,14 | 11 |
| 4 | 11 % | 76 % | ×1,29 | 12 |
| 5 | 14 % | 66 % | ×1,49 | 14 |
| 6 | 17 % | 54 % | ×1,80 | 18 |
| 7 | 20 % | 44 % | ×2,25 | 22 |
| 8 | 23 % | 34 % | ×2,92 | 29 |
| 9 | 26 % | 25 % | ×3,95 | 39 |
| 10 | 29 % | 18 % | ×5,56 | 55 |
| 11 | 32 % | 12 % | ×8,18 | 81 |
| 12 | 35 % | 8 % | ×12,59 | 125 |

Una moneta di rischio in più moltiplica l'incasso per `1 / (1 − BANG)`: per
questo, con un BANG basso all'inizio, i primi passi sono piccoli e la crescita
accelera dopo. Salti grossi già alle prime monete (per esempio 1, 3, 6, 10)
richiederebbero un BANG alto fin dalla seconda.

##### Tre in fuga

Un crash game alla Aviator: al posto dell'aereo corrono insieme **un dinosauro,
una Panda 4x4 e una moto futuristica**, tutti di cartoncino nel mondo neon.

- **Si sceglie uno dei tre** e si punta su di lui. Partono tutti e tre insieme e
  il moltiplicatore sale finché corrono.
- **Si incassa quando si vuole**, finché il proprio scelto è ancora in corsa: si
  prende la puntata per il moltiplicatore di quel momento.
- **Se il proprio scelto cade** (il dinosauro inciampa, la Panda si ribalta, la
  moto si sfascia in scintille di neon) prima dell'incasso, non si prende nulla.
  Se cade subito, alla partenza, si perde la puntata.
- Gli altri due continuano la loro corsa per lo spettacolo: ognuno cade per conto
  suo, e il loro destino non cambia quello del proprio scelto.
- **I numeri** *(per ora)*: per ciascuno dei tre la probabilità di arrivare
  almeno a ×M è `0,97 / M` (il banco tiene il 3 %; il 3 % delle volte cade alla
  partenza). Il moltiplicatore raddoppia ogni 6 secondi circa. I tre hanno gli
  stessi rischi e si distinguono solo per come cadono.

##### Roulette e dadi

- **Roulette** *(per ora)*: europea, un solo zero, ruota di cartoncino su un
  piatto al neon. Puntate classiche: numero pieno (35 a 1), rosso o nero, pari o
  dispari, basso o alto (1 a 1), dozzine e colonne (2 a 1). Il banco tiene il
  2,7 % con lo zero.
- **Dadi: duello di d20** *(per ora)*: il robot e il banco tirano un d20 con i
  dadi del gioco; vince il più alto, il pari va al banco. Paga 1 a 1; il banco
  tiene il 5 %.

### 3.3 Controlli

La tabella vale *(per ora)*, tranne la rotella con le carte, che è decisa (vedi
sotto).

| Input | Fuori dallo scontro | In scontro |
|---|---|---|
| `WASD` | cammina tenendo premuto, anche in diagonale | un passo; urto contro un nemico; diagonale solo sul battito |
| `E` | interagisce con un POI | — |
| `M` | evoca o congeda la mount (oggi `M` mostra la rotta, che sparisce) | — |
| `Z` | zaino | zaino; un consumabile costa tempo |
| `Tab` | ologramma del bioma | ologramma; il tempo continua |
| **PERSONAGGIO** | mazzo, punti, reliquie | come oggi, in pausa |
| rotella | nello zaino, gira l'oggetto che si sta spostando *(per ora)* | sceglie le carte della mano; nel piazzamento gira l'oggetto |
| clic sinistro | — | gioca la carta scelta sul bersaglio; con una carta da piazzare entra nel piazzamento, poi piazza |
| clic destro | — | esce dal piazzamento; poi toglie la scelta |
| trascinare le carte, `1`–`8`, `F` | — | come oggi |

#### La rotella e le carte

In uno scontro la rotella sceglie e gioca le carte senza dover andare sulla mano
con il mouse.

1. **Scorrere.** Se nessuna carta è scelta, il primo scatto della rotella
   sceglie la prima carta della mano. Ogni scatto in giù passa alla carta dopo.
   *(per ora: lo scatto in su torna alla carta prima, e ai bordi della mano la
   scelta ricomincia dall'altro capo; se una carta è già scelta con un tasto o
   un clic, la rotella parte da lei)*
2. **Giocare una carta normale.** Con una carta scelta, il clic sinistro su un
   bersaglio valido la gioca, come la scelta con i tasti di oggi. *(per ora:
   una carta su di sé si gioca con un clic sinistro in un punto qualsiasi della
   board)*
3. **Entrare nel piazzamento.** Se la carta scelta è da piazzare e da orientare
   (il Cannone, il Cannone laser, l'Inondazione: le carte che oggi usano la
   rotella), il clic sinistro entra nel **piazzamento**. L'oggetto segue il mouse
   sulla griglia con la sua anteprima e da quel momento la rotella serve
   **solo** a girarlo, un quarto di giro a scatto.
4. **Piazzare.** Il secondo clic sinistro piazza l'oggetto sulla cella sotto il
   mouse. Se la cella non è valida non succede nulla e si resta nel piazzamento.
5. **Ripensarci.** Il clic destro nel piazzamento ne esce senza giocare la carta.
   La carta resta scelta e la rotella torna a scorrere le carte dopo. Un altro
   clic destro toglie anche la scelta, come oggi.
6. **Dopo una giocata** la scelta si azzera, e lo scatto successivo riparte dalla
   prima carta *(per ora)*.

```text
NESSUNA CARTA ── rotella ──► CARTA SCELTA ── rotella ──► la carta dopo
      ▲                         │      ▲
      └──── clic destro ────────┘      │ clic destro
                                       │
              carta normale:           │       carta da piazzare:
              clic sinistro sul        │       clic sinistro
              bersaglio ──► GIOCATA    ▼
                                   PIAZZAMENTO ── rotella ──► gira l'oggetto
                                       │
                                       └── clic sinistro su una cella valida ──► GIOCATA
```

- **Il critico sul battito** si giudica sul clic che gioca o piazza: con la carta
  già scelta e già orientata basta cliccare a tempo.
- **Carte non giocabili** (energia che manca, nessun bersaglio): la rotella le
  sceglie comunque, in grigio, così la posizione di ogni carta resta prevedibile
  *(per ora)*.
- **Carte piazzate senza orientamento** (Buco Nero, Tesla Coil, Shock Floor,
  Pozza di Veleno, Incendio): un solo clic sulla cella, senza piazzamento
  *(per ora)*.
- Trascinare le carte, i tasti `1`–`8` e il clic sulla carta funzionano come
  oggi.
- **Tecnica.** Scelta, piazzamento e rotazione sono solo input e presentazione:
  non toccano il gioco. Solo il clic che piazza diventa una giocata, con la
  direzione data dalla rotella, come fa già oggi il Cannone.

### 3.4 Che cosa cambia rispetto a oggi

| Oggi | Domani |
|---|---|
| rotta a DAG di stanze (Choose_Path) e stanze da 17×11 a 45×31 | una mappa aperta per bioma; le famiglie di stanza (Pilastri, Anello, Corti gemelle, Asimmetrica) diventano layout dei POI |
| finestra a tempo, `--decision-time`, stordimento a tempo scaduto | via; resta l'orologio dei battiti per nemici e critici |
| fog, `--vision`, zoom e rotazione della camera | via; camera fissa |
| energia a tacche (3 al massimo, 1 ogni 3 s), carte che costano da 0 a 3 | una barra blu che si ricarica nello scontro e con i consumabili; ogni carta costa in base alla sua efficacia |
| rotella: zoom della camera, e mira dell'Inondazione e del Cannone | rotella: sceglie le carte della mano; nel piazzamento gira l'oggetto |
| reliquia iniziale fra tre, reliquie per la run | reliquie come oggetti dello zaino, portate da casa o trovate; ne funzionano tre alla volta, nei posti attivi |
| Shop, Rest, Event, Treasure | POI: Officina, Fonte, eventi, Cache |
| upgrade allo Shop e al Rest | punti potenziamento dall'esperienza |
| oro | crediti nello zaino |
| Mannaia di ferro fra le stanze | equipaggiamento nello zaino |
| profilo M8 (vittorie del ring), nessun salvataggio della run | tre slot di salvataggio, ognuno con scoperte, segreti, biomi, deposito, serie, record e la run in corso, salvato di continuo |
| Victory al boss di fine rotta | estrazione e minigioco a ogni boss di bioma |
| minigiochi dal menu | minigiochi dei biomi dopo l'estrazione e cabinati nell'hub |
| attività che si aprono dentro lo scontro: il ring delle quattro Tesla, 6 RANCH 7 con il 6 e il 7 di denari in mano | via; il Ring delle Ombre resta come minigioco della City pop; il 6 e il 7 di denari restano carte che danno crediti |
| 6 RANCH 7: gara fra due cowboy a chi arriva prima a tre monete | la slot del casinò dell'hub: si cavalca raccogliendo monete finché si vuole, sotto la pistola di un cowboy |

**Restano** le altre parti del gioco:
- il catalogo delle carte, i dadi, gli status e gli intenti dei nemici;
- QTE, cast e Mostra effetto;
- la Prova meccaniche, il mondo neon e i cartoncini.

## 4. Design

### 4.1 Direzione artistica

- **Il mondo** è virtuale, low poly, **senza texture**, al neon.
  - *Base*: il mondo neon di oggi (pavimento nero lucido con fili rossi, rocce
    nere sfaccettate, colline poligonali, alone all'orizzonte, grana).
  - *Biomi*: ognuno ha la sua tinta di neon e un suo linguaggio di forme.
  - *Desolazione*: grandi spazi vuoti, pochi segni, nessun muro attorno.
- **Personaggi e oggetti** restano di **cartoncino**: stampa pixel art con
  inchiostro e bordo di carta, come le carte vive, le bombe di Marley, la palla
  del cannone e i dinosauri.
- **Carte e HUD** restano come sono, salvo l'energia, che diventa la barra blu:
  la carta nel vuoto digitale è l'identità visiva.
- **La galassia dell'hub** usa gli stessi materiali del mondo: isolette di
  roccia nera sfaccettata con gli spigoli al neon, stelle di neon, nessuna
  texture; sopra le isole, insegne e cartellini di cartoncino.
- **Nemici** futuristici, o presi in prestito dai giochi cari al creatore.
  - *Per ora*: ogni bioma è il ricordo di un gioco (o di un genere) del
    creatore. I suoi nemici, la sua mount e i suoi minigiochi vengono da quel
    gioco, tutti di cartoncino nel mondo neon.
  - I nemici di oggi (Chaser, Archer, Brute, Bomber, Custode, Demolitore)
    restano come comportamenti e cambiano veste in ogni bioma.
  - Le bozze dei biomi sono in [4.3](#43-i-biomi-bozze).
- **Suono** generato da codice come oggi (`tools/audio`): sintetico per il
  mondo, analogico per i cabinati.

### 4.2 Narrativa (bozza)

**Premessa.** In un futuro e in un mondo che nessuno conosce, un robot si è
ribellato al suo creatore. Per punizione, o per prova, il creatore lo costringe
a rigiocare il gioco a cui teneva di più, dentro la memoria virtuale del robot,
finché non lo batte. A ogni morte la memoria si riavvolge e il robot ricomincia:
come Sisifo, spinge lo stesso masso sulla stessa collina.

**Il mondo.** I biomi sono ricordi: pezzi dei videogiochi amati dal creatore,
svuotati e ridotti a poligoni e neon, abitati da nemici di cartoncino. Il
cabinato del ranch 6-7, il 6 e il 7 di denari della Scopa e i dungeon gotici di
oggi ne sono i primi esempi. Anche i rami hanno un senso: la discesa finisce
all'Inferno, l'ascesa nel cielo, la paura nell'orrore; oltre tutti c'è lo
Spazio.

**Personaggi** (nomi di lavoro).
- *Il robot*: protagonista muto. Nell'hub appare com'è; nei biomi gioca con
  l'avatar del gioco, il Viandante di oggi *(per ora)*.
- *Il creatore*: assente. Parla attraverso frammenti di memoria, registri e la
  voce dell'hub.
- *I guardiani*: i boss, che tengono chiuso ogni ricordo.

**Come si racconta.** Niente lunghi filmati. La storia passa per frammenti di
memoria nei segreti e negli archivi, brevi messaggi del creatore nell'hub dopo
ogni bioma, l'ingresso di ogni boss, il finale e il true ending.

**I due finali (direzione).**
- *Finale normale*: il robot batte il gioco, ma il creatore non lo libera e il
  gioco ricomincia. Appare la sagoma del bioma segreto.
- *True ending*: solo una partita perfetta, la serie senza morti, apre l'ultimo
  ricordo: il gioco dentro il gioco, l'origine del creatore. Il robot smette di
  subire il masso e sceglie di spingerlo: bisogna immaginare Sisifo felice.

**La storia nelle meccaniche.**

| Meccanica | Lettura nella storia |
|---|---|
| morte, zaino perso | la memoria si riavvolge e le cose si perdono |
| scoperte e segreti che restano | ciò che il robot ha capito non si cancella: è la sua ribellione |
| estrazione | uscire da un ricordo |
| hub | la cella dove il robot aspetta fra un ricordo e l'altro |
| biomi | i giochi nella memoria del creatore |
| serie senza morti | la partita perfetta che il creatore pretende |

**Tono.** Fantascienza alta, desolata e malinconica, con l'ironia dei giochi del
creatore.

### 4.3 I biomi (bozze)

Undici bozze di bioma, più il bioma segreto, che resta a parte. Nomi, nemici,
boss, mount e minigiochi nuovi sono di lavoro: tutto ciò che sta in questa
sezione vale *(per ora)*, tranne i temi dei biomi, il bioma da cui si parte (la
Robotica cibernetica) e quello che si apre per ultimo (lo Spazio).

**Che cosa ha ogni bioma.**
- un'atmosfera, una tinta di neon e un suo linguaggio di forme low poly;
- un **terreno** con una sua regola e una **corsia**: il pericolo che scatta su
  una fila o una colonna, come la Furnace di oggi, rivestito dal bioma;
- i nemici di oggi rivestiti (Chaser, Archer, Brute, Bomber e Custode restano
  come comportamenti), più uno o due suoi;
- un boss, una mount e uno o due minigiochi;
- le sue **carte di casa**: quelle che i suoi archivi fanno scoprire più spesso.

**I rami.** La galassia ha tre rami, le sue braccia, di tre biomi ciascuno. La
difficoltà cresce lungo il ramo; lo Spazio è il più duro.

| Ramo | 1° | 2° | 3° |
|---|---|---|---|
| La discesa | Deserto del far west | Antico Egitto | Inferno |
| L'ascesa | City pop | Montagne innevate | Isola nel cielo |
| La paura | Giungla preistorica | Vietnam | Southern gothic |

| Bioma | Posto nella galassia | Neon | Mount | Minigiochi |
|---|---|---|---|---|
| Robotica cibernetica | il centro: si parte da qui | rosso cremisi (il mondo neon di oggi) | hoverbike | Scie di luce *(nuovo)* |
| Deserto del far west | discesa, 1° | ambra e arancio | cavallo | Duello a mezzogiorno *(nuovo)* |
| Giungla preistorica | paura, 1° | verde acido e giallo | parasaurolofo | Fuga dal T-Rex *(nuovo)* |
| City pop | ascesa, 1° | magenta e ciano | moto anni '80 | Ring delle Ombre, Karaoke *(nuovo)* |
| Antico Egitto | discesa, 2° | oro e turchese | cammello | Sigilli della Cripta |
| Vietnam | paura, 2° | verde oliva e giallo | jeep | Elicottero *(nuovo)* |
| Montagne innevate | ascesa, 2° | bianco ghiaccio e azzurro | motoslitta | Discesa *(nuovo)* |
| Inferno | discesa, 3° | arancio e giallo lava | cerbero | Torre di Cenere |
| Southern gothic | paura, 3° | bianco spento, verde palude e rosso sangue | cavallo nero | Cripta delle Rune |
| Isola nel cielo | ascesa, 3° | perla, oro e rosa | grifone | Guglie Sospese |
| Spazio | l'ultimo: si apre quando gli altri dieci sono vinti | viola e blu elettrico | astronave, cavalcata | Arena delle Braci |

Sei dei sette minigiochi di oggi trovano un bioma; il settimo, 6 RANCH 7,
diventa la slot del casinò dell'hub. Ne servono sei nuovi: Scie di luce, Fuga
dal T-Rex, Karaoke, Elicottero, Discesa e Duello a mezzogiorno.

#### Robotica cibernetica (si parte da qui)

- **Atmosfera.** Il ricordo più vicino al robot: una città-fabbrica di circuiti,
  torri di server spente, trincee di cavi, nastri trasportatori fermi. È il
  mondo neon di oggi.
- **Forme.** Il pavimento nero lucido con i fili cremisi, monoliti di dati,
  colonne di server, colline poligonali.
- **Terreno e corsia.** Piastre elettriche sparse, come la Shock Floor; la corsia
  è una griglia laser.
- **Nemici.** I programmi di difesa: droni ragno (Chaser), torrette laser
  (Archer), presse industriali (Brute), droni kamikaze (Bomber), antivirus con
  lo scudo (Custode).
- **Boss.** Il Supervisore, l'IA che il creatore ha messo a guardia del primo
  ricordo.
- **Mount.** Una hoverbike al neon.
- **Minigioco.** Scie di luce *(nuovo)*: moto che lasciano muri di luce dietro
  di sé; resta in pista chi non ci sbatte.
- **Carte di casa.** Cannone e Cannone laser, Tesla Coil, Shock Floor.

#### Deserto del far west

- **Atmosfera.** La frontiera del cabinato del ranch 6-7: mesas, canyon, binari,
  città fantasma, saloon vuoti, polvere.
- **Forme.** Mesas a gradoni, cactus a poche facce, binari al neon, sagome di
  case di legno.
- **Terreno e corsia.** Il deserto aperto, senza coperture fra un canyon e
  l'altro; la corsia è il treno che passa sui binari.
- **Nemici.** Banditi (Chaser), pistoleri (Archer), tori meccanici (Brute),
  bruti con la dinamite (Bomber), sceriffi corazzati (Custode).
- **Boss.** Il Fuorilegge, sul treno blindato.
- **Mount.** Il cavallo del cowboy di 6 RANCH 7.
- **Minigioco.** Duello a mezzogiorno *(nuovo)*: chi estrae per primo al
  segnale. 6 RANCH 7 è diventato la slot del casinò dell'hub.
- **Carte di casa.** Lazzo, il 6 e il 7 di denari.

#### Giungla preistorica

- **Atmosfera.** Vegetazione fitta, felci giganti, paludi, vulcani
  all'orizzonte, ossa enormi; tanta fauna paurosa che caccia in branco.
- **Forme.** Felci e alberi-torre a poche facce, rocce coperte di muschio
  luminoso.
- **Terreno e corsia.** Erba alta che nasconde i nemici finché non sono vicini:
  non è fog of war, è una copertura del terreno *(per ora, da provare)*. La corsia è una
  mandria in carica.
- **Nemici.** Raptor in branco (Chaser), sputatori di veleno (Archer),
  triceratopi che caricano (Brute), pterodattili che lasciano cadere sassi
  (Bomber), anchilosauri corazzati (Custode).
- **Boss.** Il T-Rex alfa.
- **Mount.** Un parasaurolofo, per non confondersi con i dinosauri della carta
  Dinosauro.
- **Minigioco.** Fuga dal T-Rex *(nuovo)*: una corsa a ostacoli, un saluto al
  dinosauro del browser senza rete.
- **Carte di casa.** Dinosauro, Pozza di Veleno, Lama Velenosa.

#### City pop

- **Atmosfera.** Una città giapponese degli anni '80, di notte: insegne, sale
  giochi, karaoke, vicoli bagnati, tetti, le famiglie della malavita alla Yakuza.
- **Forme.** Palazzi a blocchi come quinte di teatro, insegne al neon,
  distributori automatici, ponti; il pavimento lucido diventa asfalto bagnato.
- **Terreno e corsia.** Vicoli stretti fra i palazzi; la corsia è il traffico che
  passa sulle strade.
- **Nemici.** Teppisti (Chaser), sicari con la pistola (Archer), lottatori di
  sumo (Brute), lanciatori di molotov (Bomber), guardie del corpo (Custode).
- **Boss.** L'Oyabun, il capo della famiglia, sul tetto più alto.
- **Mount.** Una moto degli anni '80.
- **Minigiochi.** Ring delle Ombre, la rissa; Karaoke *(nuovo)*: il colpo a tempo
  diventa canto.
- **Carte di casa.** Bomb Marley, Pinball, Shove.

#### Antico Egitto

- **Atmosfera.** Dune, piramidi, obelischi, tombe, il fiume, la sfinge, le
  maledizioni.
- **Forme.** Piramidi a gradoni, obelischi come monoliti, colonne, ingressi di
  tombe.
- **Terreno e corsia.** Sabbie mobili che rallentano; le tombe sono POI
  sotterranei; la corsia è una tempesta di sabbia.
- **Nemici.** Mummie lente e resistenti (Chaser), sacerdoti arcieri (Archer),
  guardiani di pietra (Brute), scarabei esplosivi (Bomber), statue che
  proteggono (Custode).
- **Boss.** Il Faraone risorto.
- **Mount.** Un cammello.
- **Minigioco.** Sigilli della Cripta, dentro la piramide.
- **Carte di casa.** Dado del Destino.

#### Vietnam

- **Atmosfera.** Una guerra nella giungla umida: risaie a terrazze, fiumi,
  villaggi su palafitte, tunnel, elicotteri lontani, trappole. È il gioco di
  guerra della memoria del creatore: soldati di cartoncino, senza bandiere né
  fazioni reali.
- **Forme.** Palme a poche facce, risaie a gradoni, bunker, filo spinato.
- **Terreno e corsia.** Acqua delle risaie che rallenta, trappole nascoste,
  tunnel come scorciatoie e segreti; la corsia è un bombardamento.
- **Nemici.** Soldati (Chaser), cecchini (Archer), mitraglieri (Brute),
  granatieri (Bomber), ufficiali con lo scudo (Custode).
- **Boss.** L'elicottero da combattimento, che sorvola l'arena.
- **Mount.** Una jeep.
- **Minigioco.** Elicottero *(nuovo)*: uno sparatutto su binari dal portellone.
- **Carte di casa.** First Person Shooter, Incendio, Firebomb.

#### Montagne innevate

- **Atmosfera.** Silenzio e vento: vette, crepacci, bufere, rifugi abbandonati,
  una funivia ferma.
- **Forme.** Picchi sfaccettati, lastre di ghiaccio, i cavi della funivia al neon.
- **Terreno e corsia.** Ghiaccio su cui si scivola (i blocchi di ghiaccio di
  oggi), neve alta che rallenta; la corsia è una valanga.
- **Nemici.** Lupi delle nevi (Chaser), lanciatori di ghiaccio (Archer), yeti
  (Brute), rotolatori di palle di neve (Bomber), spiriti del ghiaccio (Custode).
- **Boss.** Il Re della Valanga, uno yeti enorme.
- **Mount.** Una motoslitta.
- **Minigioco.** Discesa *(nuovo)*: sci fra gli alberi, con lo yeti alle
  calcagna.
- **Carte di casa.** da scegliere.

#### Inferno

- **Atmosfera.** Vulcani, fiumi di lava, ponti di ossidiana, catene; i demoni
  più forti del gioco. È il fondo del ramo della discesa.
- **Forme.** Crateri, colonne di basalto esagonali, ossidiana nera lucida,
  crepe di lava al neon.
- **Terreno e corsia.** Lava che brucia (Bruciatura) e pavimento che si crepa;
  la corsia è un'eruzione.
- **Nemici.** Diavoletti (Chaser), demoni che lanciano fuoco (Archer), demoni
  corazzati (Brute), anime che esplodono (Bomber), guardiani infernali
  (Custode): tutti più forti della media.
- **Boss.** Il Signore dei Demoni.
- **Mount.** Un cerbero.
- **Minigioco.** Torre di Cenere.
- **Carte di casa.** Incendio, Firebomb, Thorn Coat.

#### Southern gothic

- **Atmosfera.** Horror di campagna: nebbia bassa, paludi, campi di granturco,
  chiese di legno, fienili, spaventapasseri, fantasmi, spiriti e un killer. La
  nebbia è solo atmosfera: non nasconde il gioco.
- **Forme.** Alberi spogli, steccati, case in rovina, croci, pozzi.
- **Terreno e corsia.** La palude rallenta. Al posto della corsia c'è il
  **killer**: un elite che segue il robot per la mappa e che si può solo
  seminare o affrontare a caro prezzo *(per ora, da provare)*.
- **Nemici.** Spiriti che attraversano le coperture (Chaser), cacciatori con il
  fucile (Archer), il bruto con la motosega (Brute), il predicatore con la
  lanterna che appicca il fuoco (Bomber), spaventapasseri (Custode). I nemici
  gotici di oggi sono la base naturale di questo bioma.
- **Boss.** Il Killer mascherato.
- **Mount.** Un cavallo nero.
- **Minigioco.** Cripta delle Rune, riletta come una casa infestata.
- **Carte di casa.** Movimento Ombra, Feretro.

#### Isola nel cielo

- **Atmosfera.** Isole sospese fra le nuvole, cascate che cadono nel vuoto,
  flora e fauna strane, fatate, spiritiche, angeliche. È la cima del ramo
  dell'ascesa.
- **Forme.** La mappa stessa è un arcipelago di isolette unite da ponti di luce;
  cristalli, archi, piume.
- **Terreno e corsia.** Ponti di luce che compaiono sul battito e il vuoto ai
  bordi; la corsia è una raffica di vento che spinge.
- **Nemici.** Fate veloci (Chaser), spiriti arcieri (Archer), golem di nuvola
  (Brute), uccelli di fuoco celeste (Bomber), angeli custodi con lo scudo
  (Custode).
- **Boss.** Il Serafino.
- **Mount.** Un grifone.
- **Minigioco.** Guglie Sospese.
- **Carte di casa.** Afterimage, Purifying Guard.

#### Spazio (l'ultimo)

- **Atmosfera.** Il ricordo più lontano: stazioni orbitali abbandonate, campi
  di asteroidi, pianeti all'orizzonte, il vuoto vero. Si apre quando gli altri
  dieci biomi sono vinti, e vincerlo è il finale normale.
- **Forme.** Asteroidi poligonali sospesi, piattaforme di stazione, anelli.
- **Terreno e corsia.** Bassa gravità: una spinta fa volare una casella in più
  *(per ora, da provare)*; pozzi gravitazionali che tirano come il Buco Nero; la corsia è
  una pioggia di meteore.
- **Nemici.** Sciami alieni (Chaser), torrette orbitali (Archer), mech (Brute),
  mine spaziali (Bomber), sentinelle (Custode).
- **Boss.** La Nave Madre.
- **Mount.** Un'astronave, che il robot **cavalca**: non sta dentro, ci sta
  sopra a cavalcioni, come su un cavallo.
- **Minigioco.** Arena delle Braci, riletta come sparatutto spaziale.
- **Carte di casa.** Buco Nero, Cannone laser.

### 4.4 Level design document (è ancora da implementare)

La struttura della mappa di ogni bioma: dove stanno l'ingresso, i POI, il boss,
i rilievi e i sentieri. Vale per tutti i biomi; ognuno la riveste con le sue
forme, il suo terreno e i suoi nemici ([4.3](#43-i-biomi-bozze)).

#### I tre POI ai lati

- **Tre POI maggiori, al centro di tre lati della mappa:** uno a sinistra, uno a
  destra e uno in alto. Il quarto lato, in basso, è quello da cui entra il
  robot *(per ora)*.
- **Uno dei tre è il POI del boss.** Non è fisso: all'inizio di ogni run il boss
  viene messo a caso in uno dei tre. Se in una run del Far West il boss è sul
  lato destro, nella run dopo nello stesso bioma può essere a sinistra o in
  alto.
- **La scelta viene dal seed della run**, come il resto del contenuto
  variabile; la geografia attorno ai tre POI resta fissa.
- **Cambia due regole di oggi:** la tana del boss esce dalla geografia fissa
  ([1.1](#11-il-bioma-come-mappa-aperta)), e l'ologramma la segna dall'inizio
  della run, dovunque sia toccata ([1.6](#16-boss-ed-estrazione)).
- **Ancora da decidere:** che cosa ospitano i due lati senza il boss, e come si
  riconosce dal mondo quale dei tre è il suo.

#### Level design strutturato da IA

La struttura che l'IA ha applicato ai biomi nello sviluppo di prova (poi
rimosso dal progetto). Resta qui come riferimento e base di partenza; la regola
dei tre POI ai lati la sostituisce dove le due non vanno d'accordo (la tana del
boss fissa a nord).

- **Forma.** Un'isola quadrata dagli angoli arrotondati che finisce nel vuoto,
  senza muri. Il bordo è irregolare, fra l'86 % e il 100 % del raggio, sempre
  uguale per lo stesso bioma. Lato: 80 celle nella Robotica cibernetica, 84 nei
  primi biomi dei rami, 88 nei secondi, 92 nei terzi, 96 nello Spazio, 72 nel
  bioma segreto.
- **Ingresso e tana.** L'ingresso è a sud, all'80 % del raggio dal centro; la
  tana del boss è a nord, al 74 %, in una radura libera di raggio 5 con il
  portale di estrazione al centro.
- **Siti.** Quindici in tutto, ciascuno su una radura libera di raggio 3:
  - *Dodici aperti*, entro il 66 % del raggio, ad almeno 11 celle l'uno
    dall'altro (la distanza cala di una cella alla volta, fino a 6, se l'isola
    è troppo piena). Ricevono il tipo secondo la distanza dall'ingresso, dal
    più vicino: Cache, Nido, Archivio, Fonte, Nido, Cache, Officina, Nido,
    Archivio, Cache, Nido, Prova.
  - *Tre segreti* (una Cache, un Archivio, una Prova con l'elite dormiente),
    entro l'80 % del raggio, fuori dai sentieri, chiusi da un anello di roccia
    con un solo varco rivolto verso l'esterno dell'isola.
- **Sentieri.** Linee dritte larghe due celle, dall'ingresso a ogni sito aperto
  e alla tana; le rocce non le occupano mai.
- **Rilievi.** Grappoli di roccia sparsi (uno ogni 45 celle nella Robotica, più
  radi o più fitti negli altri biomi), fatti di brevi cammini casuali e, una
  volta su sette circa, di monoliti 2×2. Sopra, le forme del bioma:
  - Deserto del far west: canyon, pareti lunghe 8–18 celle e spesse 2, con
    pochissime altre rocce;
  - City pop: isolati di 3–5 celle su una griglia di 7, separati da vicoli;
  - Antico Egitto: piramidi quadrate di lato 3–6;
  - Montagne innevate: creste, lunghe catene di roccia;
  - Giungla preistorica: grappoli fitti; Southern gothic: radi;
  - Isola nel cielo: canali di vuoto che tagliano l'isola, attraversati dai
    sentieri come ponti;
  - Spazio: crateri di vuoto fra gli asteroidi.
- **Nessuna sacca chiusa.** Ogni cella che dall'ingresso non si raggiunge
  diventa roccia; un sito rimasto tagliato fuori riceve un passaggio scavato
  fino all'ingresso.
- **Terreno.** Macchie del terreno del bioma, sempre le stesse: piastre singole
  nella Robotica, grandi macchie di erba, palude, risaie e ghiaccio, sabbie
  mobili più piccole, fiumi di lava nell'Inferno. Mai sull'ingresso, sulla tana
  e al centro dei siti.
- **Contenuto dal seed della run.**
  - Un sito aperto su sette resta vuoto, ma i Nidi attivi sono almeno due.
  - Metà delle Cache e un Archivio su tre hanno 1–2 guardie.
  - Ogni Nido manda 2–3 ondate da 2–3 nemici.
  - Ogni Prova ha un elite (un bruto o un custode resistente 2,2 volte) con una
    scorta.
  - Il boss ha due guardie.
  - Quattro pattuglie da 2–4 nemici camminano nelle pianure, lontano dai siti
    e dall'ingresso; nel Southern gothic c'è in più il Killer.
- **Difficoltà.** I nemici sono più forti con il bioma e, dentro il bioma, fino
  alla metà in più con la distanza dall'ingresso.

## 5. Decisioni

### Prese

| Tema | Decisione |
|---|---|
| Dove si combatte | nei POI, più poche pattuglie nelle pianure |
| Morte | si perde tutto lo zaino, anche ciò che era stato portato da casa |
| Scoperte e segreti | restano sempre, anche dopo una morte |
| Esperienza e livello | solo per la run; ogni run riparte dal livello 1 |
| Condizione del bioma segreto | serie senza morti con una vittoria in ogni bioma, attiva dalla prima run |
| Timer | via; restano i critici sul battito e la diagonale |
| Fog of war, zoom | via; camera fissa con ampio margine di vista |
| Ologramma | il bioma intero, POI segnati in modo grossolano, segreti solo se trovati |
| Mount | una forma per bioma, mai negli scontri |
| Estrazione | solo battendo il boss; minigioco del bioma per i bonus; lo zaino torna a casa comunque |
| Fine del gioco | tutti i biomi vinti; poi il bioma segreto e il true ending |
| Stile | mondo low poly senza texture al neon; personaggi e oggetti di cartoncino |
| Salvataggi | tre slot avviabili; in ogni slot un solo salvataggio, aggiornato quasi sempre; gli slot non si copiano, si possono solo cancellare |
| Biomi | undici bozze ([4.3](#43-i-biomi-bozze)); si parte dalla Robotica cibernetica; lo Spazio è l'ultimo, si apre quando gli altri dieci sono vinti; il bioma segreto è a parte |
| Geografia dei biomi | fissa a ogni run (rilievi, monoliti, ingresso, tana del boss, segreti); il seed della run cambia nemici, bottino e POI attivi |
| Energia | una barra blu, come una stamina o un mana; ogni carta ne costa in base alla sua efficacia; si ricarica durante lo scontro e con i consumabili |
| Zaino | una griglia limitata: ogni oggetto occupa le celle della sua forma e della sua grandezza |
| Reliquie attive | tre posti fuori dalla griglia; solo lì le reliquie funzionano; un posto tiene una reliquia di qualunque forma; si cambiano solo fuori dagli scontri; morendo si perdono come il resto dello zaino |
| Forma delle reliquie | ognuna ha una forma sua, più grande quanto più è rara |
| Sospeso | nel menu dello zaino un oggetto appena raccolto, o tolto dalla griglia, resta sospeso mentre si sistema |
| Attività dentro lo scontro | via: niente più ring delle quattro Tesla né 6 RANCH 7 aperti durante uno scontro; il ring resta come minigioco della City pop |
| Casinò dell'hub | slot del ranch (6 RANCH 7 riletto: monete raccolte a cavallo sotto la pistola di un cowboy, incasso quando si vuole), Tre in fuga (un crash game con dinosauro, Panda 4x4 e moto futuristica), roulette e dadi, con i crediti del deposito |
| Mappa dei biomi | una galassia di isolette 3D nello stile del gioco, unite da rotte di luce; mostra solo i biomi già sbloccati, salvo il bioma segreto dopo il finale |
| Rotella in scontro | sceglie le carte della mano (la prima, poi una a scatto); per le carte da orientare il clic sinistro entra nel piazzamento, dove la rotella gira l'oggetto; un altro clic sinistro piazza, il clic destro torna allo scorrimento |

### Confermate momentaneamente

Erano le decisioni aperte: ora valgono tutte *(per ora)*. Lo sviluppo parte da
qui, e ognuna si rivede quando le prove o le partite lo chiedono.

| Tema | Per ora |
|---|---|
| Quali bozze entrano nel gioco | tutte e undici, da confermare con le prime prove |
| Rami della galassia | la discesa, l'ascesa e la paura, tre biomi ciascuno ([4.3](#43-i-biomi-bozze)) |
| Nemici, boss, mount, minigiochi nuovi dei biomi | quelli delle bozze ([4.3](#43-i-biomi-bozze)) |
| Comandi della galassia | si gira trascinando, senza zoom libero |
| Rotella in su e ai bordi della mano | in su la carta prima; ai bordi si ricomincia dall'altro capo |
| Carte piazzate senza orientamento | un solo clic, senza piazzamento |
| Carte non giocabili e rotella | scelte comunque, in grigio |
| Dimensioni della mappa | circa 96×96 celle, da 80×80 a 112×112 |
| Chiavi per la tana del boss | nessuna: sempre aperta |
| Misura della griglia dello zaino | 8×5 celle; zaini più grandi da trovare |
| Forme, pile e rotazione degli oggetti | forme a celle; pile di 5 consumabili e 99 crediti; la rotella gira l'oggetto preso |
| Celle delle reliquie per rarità | comune 1–2, non comune 3, rara 4, leggendaria 5–6 |
| Sospeso: quanti oggetti, chiusura, raccolta | fino a 3; chiudendo lo zaino tornano a terra dopo un avviso; la calamita non prende ciò che non entra |
| Puntate del casinò | da 5 a 50 crediti |
| Curva della slot del ranch | BANG dal 2 %, +3 punti a moneta, fino al 60 %; incasso che restituisce il 98 % a ogni punto d'uscita |
| Tre in fuga | arrivare a ×M con probabilità 0,97 / M; stessi rischi per i tre; raddoppio ogni 6 s |
| Roulette e dadi | roulette europea; duello di d20 con il pari al banco |
| Deposito | una griglia più grande, a pagine |
| Valuta | crediti nello zaino (l'oro di oggi) |
| Pescata senza finestre | una carta ogni 4 battiti, più Refocus |
| Scala e ricarica della barra di energia | 100 punti, 8 al secondo del mondo, piena all'inizio di ogni scontro |
| Costi delle carte | da 10 a 70 secondo l'efficacia; tutto il catalogo da ritarare |
| Energia e potenziamenti | un potenziamento migliora l'effetto, non il costo |
| Curva dell'esperienza | `4 + 2n` per il livello `n` |
| Mazzo iniziale e pool iniziale | lo starter di oggi; comuni e alcune non comuni |
| Abbandonare una run | conta come una morte |
| Il protagonista nei biomi | il Viandante come avatar del robot |
| Minigiochi per bioma e bonus | 1–2 per bioma; bonus a stelle ([2.6](#26-estrazione-e-minigioco)) |
| Cadenza del salvataggio | a ogni cambiamento che conta e ogni 10 s in esplorazione; in scontro fra un battito e l'altro ([2.10](#210-salvataggi-e-slot)) |
| Impostazioni | comuni ai tre slot |
| Dove stanno i file degli slot | nella cartella utente del sistema, non più nella cartella di avvio |
| Tema gotico | resta un'opzione nascosta finché serve |

### Ancora aperte

Restano aperte solo le scelte per cui non c'è ancora un'idea.

| Tema | Stato |
|---|---|
| Nomi del robot, del creatore, dell'hub e dei biomi | da scegliere |
| Carte di casa delle Montagne innevate | da scegliere |
| I due lati senza boss ([4.4](#44-level-design-document-è-ancora-da-implementare)) | che cosa ospitano, e come si riconosce il lato del boss |

## 6. Roadmap

Ogni fase si prova prima nella Prova meccaniche, o in un bioma di prova, e passa
al gioco normale quando è approvata. Dalla fase 3 in poi ogni stato nuovo deve
poter entrare nel salvataggio.

| Fase | Contenuto | Fatta quando |
|---|---|---|
| 1 | Combattimento senza timer: via la finestra, critici sul battito, nuova pescata, energia a barra | uno scontro intero si gioca senza conto alla rovescia, con i critici sul battito e le carte pagate dalla barra blu |
| 2 | Camera fissa, niente fog né zoom; la rotella che sceglie e piazza le carte | la stanza di oggi si gioca con la camera nuova, senza nebbia, e la mano si gioca anche solo con rotella e clic |
| 3 | Mappa aperta di prova: un bioma grande a chunk, POI, pattuglie, ingaggio, ologramma del bioma | si esplora, si ripulisce un nido e si torna a esplorare senza cambi di schermata |
| 4 | Mount | si attraversa il bioma in sella; uno scontro la impedisce |
| 5 | Zaino a griglia, deposito, hub minimo, estrazione e morte; i tre slot con il salvataggio continuo | una run porta a casa uno zaino, una morte lo perde; chiudendo il gioco a metà run, o dopo un crash, si riprende dall'ultimo salvataggio |
| 6 | Esperienza, livelli e punti; scoperte e pool | si livella nella run; una carta scoperta compare nella run dopo |
| 7 | La galassia dei biomi, sblocchi, serie e finali | vincendo compaiono la rotta e l'isola nuova, mai prima; la serie si conta e si azzera |
| 8 | Minigiochi come estrazione e cabinati dell'hub; via le attività dentro lo scontro | battere un boss porta al minigioco e al ritorno a casa; nessuno scontro apre più il ring o 6 RANCH 7 |
| 9 | I biomi veri, dalle [bozze](#43-i-biomi-bozze); si parte dalla Robotica cibernetica, che è il mondo neon di oggi | ogni bioma ha forme, terreno, corsia, nemici, boss, mount, minigiochi e frammenti suoi |
| 10 | Il casinò dell'hub: la slot del ranch (da 6 RANCH 7), Tre in fuga, roulette e dadi | si scommettono crediti in tutti e quattro; le simulazioni confermano il vantaggio del banco |

### Note tecniche

- **Limiti di oggi.** La stanza ha limiti pensati per un'arena: 32 nemici e 32
  oggetti, 416 eventi per registro, `Room` sotto gli 8 KB. La mappa aperta
  chiede un contenitore del mondo a blocchi, con la simulazione attiva solo
  attorno al robot.
- **Determinismo.** Resta come oggi: seed della run e stream separati per i POI
  attivi, gli incontri, il bottino e i premi. La geografia di ogni bioma è fissa
  e non consuma RNG, come la grafica.
- **Slot.** Tre file versionati, uno per slot, al posto di `odin_pp_profile.json`
  del ring e del profilo dei minigiochi. Si scrivono su un file temporaneo e poi
  si rinominano, come il profilo di oggi: un crash a metà scrittura non rovina
  lo slot. Un file invalido resta da parte e il menu lo segnala.
- **Run in corso.** Oggi non si salva. Il determinismo aiuta: fra un battito e
  l'altro lo stato del mondo è stabile e si può scrivere per intero.
- **Prestazioni.** Chunk di disegno e di simulazione; gli smoke del mondo neon
  misurano già il costo per frame.
