[← Odin PP](../README.md)

# Direzione del gioco

Documento di direzione, versione 1 (22 ottobre 2026). Fissa dove va il gioco in
quattro ambiti: **Mappa**, **Progressione**, **Gameplay** e **Design**. Gli altri
documenti descrivono il gioco di oggi e restano validi finché una fase della
[roadmap](#6-roadmap) non ne sostituisce le regole.

Le voci marcate *(proposta)* sono scelte di partenza da confermare o tarare con
le partite; tutte le altre sono decise. Le decisioni ancora aperte sono raccolte
in [Decisioni](#5-decisioni).

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
| Run | una spedizione in un bioma, dall'ingresso all'estrazione o alla morte |
| Hub | il luogo fra una run e l'altra: deposito, zaino, mappa dei biomi, progressi |
| POI | punto d'interesse: un luogo della mappa con un contenuto (nemici, bottino, scoperta, servizio) |
| Segreto | un luogo che l'ologramma non segna finché non lo si trova esplorando |
| Scontro | lo stato di combattimento: comincia con l'ingaggio, finisce quando nessun nemico insegue più |
| Zaino | l'inventario della run: morendo si perde tutto, estraendosi va nel deposito |
| Deposito | l'inventario permanente dell'hub |
| Scoperta | una carta resa ottenibile nelle run future, senza ottenerla subito |
| Pool | le carte che possono comparire in premi e offerte di una run |
| Punti potenziamento | quelli che dà ogni livello della run; si spendono per migliorare le carte del mazzo |
| Estrazione | l'uscita dal bioma dopo il boss: minigioco e ritorno all'hub con lo zaino |
| Serie | le run vinte di fila senza morire |

## 1. Mappa

### 1.1 Il bioma come mappa aperta

- Ogni bioma è un'unica mappa aperta sulla griglia di oggi (una cella per passo),
  molto più grande di una stanza ma attraversabile. *(proposta)* Circa 96×96
  celle: 80×80 nei primi biomi, 112×112 negli ultimi. Oggi la stanza più grande
  è di 45×31. A piedi si attraversa in circa un minuto, in sella in 20–25 secondi.
- **Geografia fissa, contenuto variabile** *(proposta)*. Ogni bioma ha la stessa
  geografia a ogni run: rilievi, monoliti, ingresso, tana del boss e segreti
  fissi. Il seed della run cambia i nemici, il bottino e quali POI sono attivi
  fra quelli possibili. È il mito di Sisifo: il robot risale la stessa collina, e
  ciò che ricorda (i segreti trovati, la mappa imparata) vale qualcosa.
  L'alternativa è una geografia generata a ogni run, come le stanze di oggi.
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
| Officina *(proposta)* | un mercante | si spendono crediti | carte, rimozione di una carta, consumabili |
| Fonte *(proposta)* | un punto di ristoro | si usa una volta | cura |
| Prova | un elite o una sfida | si vince | una reliquia o un oggetto raro, molta esperienza |
| Tana del boss | il boss del bioma | si vince | l'**estrazione** |

- **Stati di un POI segnato.**
  - *Non visitato*: l'ologramma ne mostra un'area approssimativa e l'icona del tipo.
  - *Scoperto*: posizione esatta.
  - *Risolto*: spento.
- **Il Nido non chiude dentro.** Le ondate partono quando si entra nel suo
  centro. Uscendo dal suo raggio le ondate si interrompono e il nido resta
  attivo con i nemici rimasti *(proposta)*.
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
  ampio margine di vista *(proposta: circa 25×15 celle attorno al robot)*, e lo
  segue con un leggero ritardo.
- **La rotella resta alle carte** che si mirano con essa (Inondazione, Cannone).
- **Prestazioni.** Il mondo si disegna e si simula a blocchi (chunk). Lontano
  dal robot i nemici dormono.

### 1.5 Nemici nella mappa

- Il grosso dei nemici sta nei **POI**; nelle pianure girano **poche pattuglie**
  (2–4 nemici) che si possono affrontare o evitare.
- **Ingaggio.** Uno scontro comincia in tre casi:
  - un nemico ti vede entro il suo raggio *(proposta: 6 celle, con linea di vista)*;
  - un nemico ti colpisce;
  - attacchi tu.
- **Fine dello scontro.** Lo scontro finisce quando nessun nemico ingaggiato è
  vivo o ti insegue più *(proposta: un nemico smette di inseguire a 12 celle
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
| zaino | la run: morendo si perde **tutto**, anche ciò che era stato portato da casa; estraendosi tutto va nel deposito |
| deposito | sempre |
| carte scoperte, segreti trovati, biomi sbloccati, record dei minigiochi | sempre, anche quando la run fallisce |
| serie | fino alla prossima morte |

### 2.3 Le carte

- **Mazzo iniziale.** Ogni run parte dallo stesso mazzo base, uguale in tutti i
  biomi *(proposta: lo starter di oggi)*.
- **Pool.** All'inizio del gioco è un sottoinsieme del catalogo *(proposta: le
  comuni e alcune non comuni)*. Tutto il resto si scopre.
- **Ottenere una carta nella run.** Arriva dai premi dei Nidi e delle Prove (una
  fra tre, come oggi), dalle Officine e dagli eventi. Restano le regole di oggi
  su mazzo pieno, Skip e rarità.
- **Scoprire una carta.** Si scopre negli Archivi (anche segreti) e con imprese
  speciali. Il ring è il primo esempio: oggi Titan Grip e Storm Crown si
  sbloccano vincendolo. La carta non entra nel mazzo: entra nel pool delle run
  future, anche se questa run finisce con la morte. L'hub ne tiene l'archivio,
  con Mostra effetto.
- **Prova meccaniche.** Nel laboratorio tutte le carte restano disponibili,
  scoperte o no.

### 2.4 Esperienza, livelli e punti potenziamento

- I nemici lasciano frammenti di esperienza, raccolti dalla calamita del bottino
  di oggi.
- Ogni livello dà **un punto potenziamento** *(proposta: il livello `n` costa
  `4 + 2n` esperienza; da tarare)*.
- **Un punto alza di un livello una carta del mazzo**, entro il suo limite: dadi
  dal D4 al D20, Lazzo fino a 5, il Cannone che al secondo diventa laser e così
  via. I punti si possono tenere da parte per le carte che arriveranno più avanti
  nella run.
- **I punti si spendono fuori dagli scontri**, dalla scheda del personaggio
  (mazzo), mai durante un combattimento.
- **A fine run** il livello e i punti non spesi si perdono, comunque finisca.
- **Niente più upgrade da Shop e Rest.** L'esperienza diventa la sola fonte di
  potenziamenti *(proposta: un consumabile raro può dare un punto)*.

### 2.5 L'inventario: zaino e deposito

- **Lo zaino** ha un numero limitato di posti *(proposta: 12; i consumabili
  uguali si impilano)*. Le categorie sono queste.

  | Categoria | Che cosa contiene | Regole |
  |---|---|---|
  | Consumabili | cura, energia, una carta temporanea, un'esca per le pattuglie | si usano dallo zaino; in uno scontro costano tempo come un'azione |
  | Equipaggiamento | armi per l'attacco a urto (la Mannaia di ferro di oggi) e altri oggetti attivi | — |
  | Reliquie | passive come quelle di oggi | funzionano se stanno nello zaino *(proposta: al massimo 3 attive)* |
  | Crediti | l'oro di oggi | si spendono nelle Officine e nell'hub |
  | Frammenti di memoria | la storia | si portano a casa per leggerli |

- **Il deposito** dell'hub conserva tutto ciò che è stato estratto. Prima di una
  run si sceglie che cosa mettere nello zaino: è la posta in gioco.
- **Morte**: si perde tutto lo zaino.
- **Estrazione**: tutto lo zaino va nel deposito, comunque finisca il minigioco.
- **Una sola regola** *(proposta)*: tutto ciò che si raccoglie nella run va
  nello zaino ed è estraibile; non esistono oggetti validi solo per la run.

### 2.6 Estrazione e minigioco

- Battuto il boss si apre il portale e il robot entra in uno dei **minigiochi
  del bioma**, un cabinato della memoria del creatore.
- **Il risultato dà un bonus**, in stelle da 0 a 3 come oggi *(proposta)*:

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
  - 6 RANCH 7 (western a tempo)

  Andranno riletti in chiave futuristica o da cabinato; ne arriveranno altri.

### 2.7 Biomi e sblocchi

- Si parte con un solo bioma sbloccato. Vincere una run ne sblocca uno o più: la
  **mappa dei biomi** è un grafo. *(proposta: 6 biomi più uno segreto, con i
  nomi di lavoro qui sotto; il B6 si apre quando tutti gli altri sono vinti)*

  ```text
          ┌─► B2 ─┐       ┌─► B4 ─┐
   B1 ────┤       ├───────┤       ├───► B6, l'ultimo bioma
          └─► B3 ─┘       └─► B5 ─┘
                                        ?  il bioma segreto
  ```

- Il gioco **finisce** quando ogni bioma è stato vinto almeno una volta: è il
  finale normale.

### 2.8 Il finale e il true ending

- **Il bioma segreto si mostra.** Dopo il finale normale, la mappa dei biomi lo
  mostra come una sagoma spenta, con un indizio esplicito della condizione.
  Prima del finale ci sono solo indizi impliciti: glitch e frammenti di memoria.
- **La condizione** è una **serie senza morti** che comprende una vittoria in
  **ogni** bioma, l'ultimo compreso.
  - Contano le run vinte di fila.
  - Una morte azzera la serie *(proposta: anche abbandonare una run)*.
  - Vale **dalla primissima run**: chi finisce il gioco senza mai morire apre il
    bioma segreto subito.
- **L'hub mostra la serie** *(proposta: solo dopo il finale normale, per non
  svelare il segreto)*.
- **Il bioma segreto** ha l'ultimo vero boss e porta al **true ending**.

### 2.9 La mount

- **Uso.** Si evoca e si congeda fuori dagli scontri. È molto più veloce del
  passo a piedi *(proposta: tre volte)* e non si può usare in combattimento.
- **Forma.** Cambia in ogni bioma: un veicolo o una creatura del gioco di quel
  bioma.
- **Ingaggio in sella.** Se un nemico ti ingaggia mentre sei in sella puoi
  provare a seminarlo, perché la mount è più veloce dei nemici base. Se ti
  colpisce vieni disarcionato e comincia lo scontro.
- **Limiti.** In sella non si giocano carte e non si aprono POI.
- **Tecnica.** Riusa il sistema delle cavalcate del Dinosauro: stampa di
  cartoncino sotto la carta del robot, sella, passo, giro come la carta. Il
  Dinosauro resta una carta da combattimento.

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
- **Il resto non cambia**: le azioni costano tempo, il cast di una carta ferma il
  mondo, i dadi sono una pausa, l'energia si rigenera di 1 ogni 3 s fino a 3.
- **La mano.**
  - All'inizio dello scontro si pescano 5 carte.
  - Senza finestre la mano si ricarica in un altro modo *(proposta: una carta
    ogni 4 battiti fino al massimo, più il Refocus di oggi)*.
  - Finito lo scontro la mano si mette via e il mazzo si rimescola per il
    prossimo.
- **Fuori dagli scontri** si cammina tenendo premuto, anche in diagonale, si
  interagisce con i POI, si usa lo zaino, si spendono i punti e si evoca la
  mount. Le carte che oggi funzionano a stanza liberata (la Canna da Pesca)
  funzioneranno fuori dagli scontri, con un limite da rivedere.
- **Segreti del combattimento.** Le attività che si aprono durante lo scontro (il
  ring delle quattro Tesla, 6 RANCH 7) restano segreti del combattimento.

### 3.2 L'hub

| Zona | A che cosa serve |
|---|---|
| Deposito | gestire gli oggetti estratti e preparare lo zaino |
| Mappa dei biomi | una mappa larga con i biomi sbloccati e le sagome di quelli chiusi; da qui si parte |
| Progressi | statistiche, carte scoperte (con Mostra effetto), segreti, record dei minigiochi, serie |
| Cabinati *(proposta)* | rigiocare i minigiochi sbloccati per i record, senza premi |
| Prova meccaniche | il laboratorio delle carte di oggi |

### 3.3 Controlli *(proposta)*

| Input | Fuori dallo scontro | In scontro |
|---|---|---|
| `WASD` | cammina tenendo premuto, anche in diagonale | un passo; urto contro un nemico; diagonale solo sul battito |
| `E` | interagisce con un POI | — |
| `M` | evoca o congeda la mount (oggi `M` mostra la rotta, che sparisce) | — |
| `Z` | zaino | zaino; un consumabile costa tempo |
| `Tab` | ologramma del bioma | ologramma; il tempo continua |
| **PERSONAGGIO** | mazzo, punti, reliquie | come oggi, in pausa |
| carte, `1`–`8`, `F`, rotella | — | come oggi; la rotella mira le carte che la usano |

### 3.4 Che cosa cambia rispetto a oggi

| Oggi | Domani |
|---|---|
| rotta a DAG di stanze (Choose_Path) e stanze da 17×11 a 45×31 | una mappa aperta per bioma; le famiglie di stanza (Pilastri, Anello, Corti gemelle, Asimmetrica) diventano layout dei POI |
| finestra a tempo, `--decision-time`, stordimento a tempo scaduto | via; resta l'orologio dei battiti per nemici e critici |
| fog, `--vision`, zoom e rotazione della camera | via; camera fissa |
| reliquia iniziale fra tre, reliquie per la run | reliquie come oggetti dello zaino, portate da casa o trovate |
| Shop, Rest, Event, Treasure | POI: Officina, Fonte, eventi, Cache |
| upgrade allo Shop e al Rest | punti potenziamento dall'esperienza |
| oro | crediti nello zaino |
| Mannaia di ferro fra le stanze | equipaggiamento nello zaino |
| profilo M8 (vittorie del ring) | un profilo unico: scoperte, segreti, biomi, deposito, serie, record |
| Victory al boss di fine rotta | estrazione e minigioco a ogni boss di bioma |
| minigiochi dal menu | minigiochi dei biomi dopo l'estrazione e cabinati nell'hub |

**Restano** le altre parti del gioco:
- il catalogo delle carte, i dadi, gli status e gli intenti dei nemici;
- QTE, cast e Mostra effetto;
- la Prova meccaniche, il mondo neon e i cartoncini;
- le attività in combattimento.

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
- **Carte e HUD** restano come sono: la carta nel vuoto digitale è l'identità
  visiva.
- **Nemici** futuristici, o presi in prestito dai giochi cari al creatore.
  - *Proposta*: ogni bioma è il ricordo di un gioco (o di un genere) del
    creatore. I suoi nemici, la sua mount e i suoi minigiochi vengono da quel
    gioco, tutti di cartoncino nel mondo neon.
  - I nemici di oggi (Chaser, Archer, Brute, Bomber, Custode, Demolitore)
    restano come comportamenti e cambiano veste in ogni bioma.
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
oggi ne sono i primi esempi.

**Personaggi** (nomi di lavoro).
- *Il robot*: protagonista muto. Nell'hub appare com'è; nei biomi gioca con
  l'avatar del gioco, il Viandante di oggi *(proposta)*.
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

### Aperte, con una proposta

| Domanda | Proposta |
|---|---|
| Quanti biomi e come si collegano | 6 più il segreto, un grafo a rami ([2.7](#27-biomi-e-sblocchi)) |
| Geografia fissa o generata a ogni run | fissa, con contenuto variabile ([1.1](#11-il-bioma-come-mappa-aperta)) |
| Dimensioni della mappa | circa 96×96 celle, da 80×80 a 112×112 |
| Chiavi per la tana del boss | nessuna: sempre aperta |
| Posti dello zaino, reliquie attive | 12 posti, 3 reliquie attive |
| Valuta | crediti nello zaino (l'oro di oggi) |
| Pescata senza finestre | una carta ogni 4 battiti, più Refocus |
| Curva dell'esperienza | `4 + 2n` per il livello `n` |
| Mazzo iniziale e pool iniziale | lo starter di oggi; comuni e alcune non comuni |
| Abbandonare una run | conta come una morte |
| Nomi del robot, del creatore, dell'hub e dei biomi | da scegliere |
| Il protagonista nei biomi | il Viandante come avatar del robot |
| Minigiochi per bioma e bonus | 1–2 per bioma; bonus a stelle ([2.6](#26-estrazione-e-minigioco)) |
| Salvataggio a metà run | serve, perché una run dura 20–30 minuti: si salva all'uscita e si riprende dall'hub |
| Tema gotico | resta un'opzione nascosta finché serve |

## 6. Roadmap

Ogni fase si prova prima nella Prova meccaniche, o in un bioma di prova, e passa
al gioco normale quando è approvata.

| Fase | Contenuto | Fatta quando |
|---|---|---|
| 1 | Combattimento senza timer: via la finestra, critici sul battito, nuova pescata | uno scontro intero si gioca senza conto alla rovescia, con i critici sul battito |
| 2 | Camera fissa, niente fog né zoom | la stanza di oggi si gioca con la camera nuova, senza nebbia |
| 3 | Mappa aperta di prova: un bioma grande a chunk, POI, pattuglie, ingaggio, ologramma del bioma | si esplora, si ripulisce un nido e si torna a esplorare senza cambi di schermata |
| 4 | Mount | si attraversa il bioma in sella; uno scontro la impedisce |
| 5 | Zaino, deposito, hub minimo, estrazione e morte | una run porta a casa uno zaino; una morte lo perde |
| 6 | Esperienza, livelli e punti; scoperte e pool | si livella nella run; una carta scoperta compare nella run dopo |
| 7 | Mappa dei biomi, sblocchi, serie e finali | il grafo si apre vincendo; la serie si conta e si azzera |
| 8 | Minigiochi come estrazione e cabinati dell'hub | battere un boss porta al minigioco e al ritorno a casa |
| 9 | I biomi veri: direzione artistica, nemici, mount e narrativa | ogni bioma ha forma, nemici, mount, minigiochi e frammenti suoi |

### Note tecniche

- **Limiti di oggi.** La stanza ha limiti pensati per un'arena: 32 nemici e 32
  oggetti, 416 eventi per registro, `Room` sotto gli 8 KB. La mappa aperta
  chiede un contenitore del mondo a blocchi, con la simulazione attiva solo
  attorno al robot.
- **Determinismo.** Resta come oggi: seed della run e stream separati per mappa,
  incontri, bottino e premi. La grafica non consuma RNG.
- **Profilo.** Uno solo, versionato, al posto di `odin_pp_profile.json` del ring
  e del profilo dei minigiochi. Contiene scoperte, segreti, biomi, deposito,
  serie e record.
- **Salvataggio della run in corso**: oggi non esiste.
- **Prestazioni.** Chunk di disegno e di simulazione; gli smoke del mondo neon
  misurano già il costo per frame.
