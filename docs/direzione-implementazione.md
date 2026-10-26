# Direzione: implementazione e verifiche

Revisione del 22 ottobre 2026. Riferimento: [direzione.md](../direzione.md).
Questa checklist descrive il codice e le verifiche di questa revisione; i
numeri di commit riportati nel documento di direzione non costituiscono una
verifica delle funzionalità.

## Avvio e comandi

- **Gioca** apre i tre slot della campagna. Uno slot nuovo conduce all'hub;
  uno slot con una spedizione attiva riprende il mondo salvato.
- `--expedition` apre una spedizione di prova; `--run` conserva l'accesso
  alla modalità precedente.
- Nel bioma: `WASD` cammina liberamente rispetto allo schermo (`W` verso
  l'alto), `M` evoca la mount, `E` interagisce, `Z` apre lo zaino, `Tab`
  apre l'ologramma e `U` apre il personaggio. In combattimento `WASD` torna
  a muovere di una cella lungo gli assi della griglia.
- In combattimento la rotella sceglie la carta. Le carte direzionali usano
  un clic per entrare nel piazzamento, la rotella per ruotare, un secondo
  clic per confermare; il clic destro torna alla selezione.
- Nell'inventario: trascinamento, rotella o `R` per ruotare, celle evidenziate
  per verificare lo spazio. Gli oggetti sospesi richiedono una conferma
  prima di essere lasciati a terra chiudendo lo zaino della spedizione.

## Copertura delle regole

| Ambito | Implementazione |
|---|---|
| Combattimento continuo | Nessuna scadenza decisionale nella spedizione; critici sul battito, costi delle azioni e pause di cast/dadi conservati. |
| Energia e mano | Barra da 100, ricarica di 8/s sul tempo del mondo, costi per carta, anteprima del costo; 5 carte iniziali e pescata ogni 4 battiti fino al limite della mano. |
| Camera e input | Camera fissa che segue il giocatore con un inseguimento indipendente dagli fps, nessuna nebbia di visibilità nella spedizione, rotella dedicata alle carte e al piazzamento. |
| Movimento libero | Fuori dagli scontri il robot scivola con accelerazione e frenata (3,6 celle/s a piedi, 8,4 in sella, metà su sabbia, acqua, neve e palude, inerzia sul ghiaccio) e un raggio di collisione di 0,3 celle che scorre lungo muri e spigoli. La cella sotto il suo centro resta la posizione della stanza: POI, trappole, lava, pattuglie e ingaggi leggono la stessa griglia. All'ingaggio il robot si allinea alla cella con una transizione morbida; spinte, pozzi gravitazionali e tunnel vengono adottati senza scatti. |
| Mondo aperto | Nuove mappe da 160, 192 o 224 celle per lato, geografia fissa per bioma; seed separato per i contenuti, gruppi di nemici finiti e simulazione locale. Le spedizioni salvate con la versione precedente conservano le loro dimensioni. |
| POI | Nove planimetrie da 21–29 celle: ingressi multipli, cortili, passaggi di aggiramento, coperture e ali di spawn. Pavimento e geometria usano le stesse celle delle collisioni. Nidi a ondate che si fermano uscendo dal raggio, cache, archivi, officine, fonti, prove, tane del boss, frammenti e tunnel; stati non visitato/scoperto/risolto. |
| Incontri | Ingaggio a distanza con linea di vista, pattuglie, guinzaglio e rientro all'esplorazione. I gruppi conservano danni e morti quando vengono rimossi dalla simulazione attiva. |
| Ologramma e segreti | Miniatura 3D dell'intero terreno con rilievi e cortili; aree approssimative dei POI, legenda per tipo e stato, posizione precisa del robot. Non mostra le posizioni dei nemici. Anche i POI scoperti restano aree indicative, secondo la richiesta successiva al documento. I segreti compaiono soltanto dopo il ritrovamento. |
| Mount | Forma del bioma, movimento accelerato fuori dagli scontri, discesa all'ingaggio o quando un pericolo la impone. |
| Zaino | Griglia iniziale 8×5, forme a celle e rotazioni, pile da 5 consumabili e 99 crediti, 3 reliquie attive, arma impugnata e 3 oggetti sospesi. |
| Deposito | Griglie da 12×8 su pagine aggiunte secondo necessità, trasferimenti reali, scelta della capacità dello zaino; crediti come oggetti impilati. |
| Oggetti a terra | Raccolta automatica soltanto quando lo spazio basta, raccolta manuale e sospeso; gli oggetti lasciati volontariamente richiedono `E` per evitare il ciclo di raccolta immediata. |
| Esca | Richiama la pattuglia libera più vicina entro 24 celle; aggira le coperture, si ferma sul segnale e poi torna al percorso iniziale. Bersaglio e durata restano nel salvataggio. |
| Esperienza | Costo del livello `4 + 2n`, punti per migliorare singole carte fuori dagli scontri, reset dei progressi temporanei a fine run. |
| Scoperte | Pool iniziale limitato; una scoperta persiste e diventa disponibile dalla run successiva. Archivio con anteprima isolata dell'effetto. |
| Estrazione e morte | Il boss apre l'uscita; il minigioco assegna soltanto il bonus. Anche una sconfitta nel cabinato estrae lo zaino. Morire o abbandonare perde tutti gli oggetti portati, comprese reliquie attive e arma. |
| Galassia | Robotica iniziale, tre rami, isole visibili soltanto dopo lo sblocco, Spazio dopo gli altri dieci biomi, sagoma del ricordo segreto dopo il finale normale. |
| Hub e record | Segreti e record consultabili per pagine, tutti i dodici cabinati compreso il Ring della City, punteggi e stelle nella scheda del bioma. Le isole vinte portano un cartello fisico di carta con boss e stelle; l'animazione di formazione si attiva solo sui nuovi sblocchi. |
| Serie e finali | Serie senza morti basata sui biomi distinti; ripetere lo stesso bioma non sostituisce quelli mancanti. Finale normale e accesso al ricordo del creatore. |
| Salvataggi | Tre slot indipendenti in cartella utente, snapshot del mondo, stato RNG, oggetti e avanzamento; file temporaneo sincronizzato e rinomina atomica, versione, checksum e validazione. I file non validi sono conservati e segnalati. |
| Casinò | Quattro giochi con crediti del deposito, puntate 5–50, esiti e puntata salvati prima della giocata; ripresa della stessa transazione dopo uscita o riavvio. |

Le implementazioni principali sono in [expedition](../src/expedition/),
[campaign](../src/campaign/), [campaignui](../src/campaignui/),
[expedition_scene.odin](../src/run/expedition_scene.odin) e
[campaign_hub.odin](../src/application/campaign_hub.odin).

I checkpoint ordinari copiano uno snapshot immutabile e lo affidano a un
worker; la coda conserva l'ultimo aggiornamento in attesa senza serializzare
il mondo sul frame di gioco. Chiusura, cambio slot, cancellazione e perdita
del focus attendono il completamento. Puntate e incassi del casinò usano
invece una scrittura sincrona prima di lasciare proseguire la giocata. Su una
mappa da 224×224, il benchmark di dieci checkpoint ha misurato 0,032 ms
medi per catturare lo snapshot da 1.270.624 byte e 0,103 ms medi per inserirlo
in coda (picco 0,164 ms). Il file JSON da circa 2,44 MB viene scritto dal
worker in circa 110 ms medi, fuori dal frame di gioco. Sono misure locali
sulla macchina di sviluppo, non una promessa su ogni piattaforma.

Il formato degli slot è alla versione 2 e legge anche la versione 1. Il
checksum viene verificato sui byte originali prima di applicare i nuovi
campi e ampliare gli array. Le vecchie mappe da 80, 96 e 112 celle vengono
ricostruite dalle celle salvate, senza rigenerare terreno, POI o nemici;
mantengono la dimensione originale anche nei salvataggi successivi. Le
dimensioni esplicite dei nuovi snapshot vengono validate prima del ripristino.
Solo la spedizione successiva usa la mappa più grande.

L'ologramma usa righe di celle unite per mantenere tutti i varchi e le zone
di vuoto. Sul bioma da 224×224, la preparazione della geometria ha richiesto
2,128 ms medi su 100 campioni (picco 2,277 ms): 1.934 strisce di terreno e
948 muri. Questa misura riguarda la costruzione della miniatura, non il
tempo totale del frame grafico.

In spedizione, il cibo pescato è un consumabile fisico: conserva il risultato
del d4, entra nello zaino, si può estrarre e cura soltanto quando viene usato.
Se il terreno è pieno, il premio resta nel bottino in attesa di spazio. Le
carte pescate entrano nell'archivio e la scoperta resta anche dopo una morte.
La pesca della modalità legacy mantiene la cura immediata.

## Biomi e terreno

I dodici ambienti, incluso il ricordo segreto, hanno metadati, geografia,
tinte, rilievi, nomi, mount, siti e frammenti propri. Dodici mount procedurali
hanno silhouette riconoscibili, arti o ruote animati e orientamento del
giocatore. Il Dinosauro da combattimento ha una sagoma separata. I sei
rig dei nemici indossano 72 combinazioni di accessori per bioma e ruolo.
Robot e mount usano una sagoma continua di cartoncino, bordo crema
irregolare, contorno d'inchiostro e stampa a colori piatti. Gli oggetti fisici
a terra hanno sagome di carta distinte per categoria. L'ambiente usa solidi
blu notte con spigoli al neon nella tinta del bioma. Il rendering delle
spedizioni ora separa ambiente HDR e personaggi di carta: bagliore e
regolazione dei toni agiscono sull'ambiente, mentre stampa, contorni crema
e interfaccia conservano i loro colori. Il pavimento riflette l'architettura
con sfocatura e lucidità proprie di ciascun bioma. Non vengono proiettate
ombre dinamiche dei neon. Ogni bioma ha le sue sagome: rocce e macchinari
industriali (Robotica/Cyber), monoliti (Far West, ricordo segreto), alberi a
chioma sfaccettata (Giungla, Vietnam), piramidi (Egitto,
Inferno), picchi (Montagne, Spazio), croci storte con la traversa chiara
(Southern gothic) e isolati a blocchi (City pop). I muri dei cortili sono
più bassi, con un solo contorno per tratto e le pieghe evidenziate.

In combattimento il pavimento attorno al robot e ai nemici diventa una
griglia di piastrelle nella tinta del bioma, con fughe scure, che sfuma
piastrella per piastrella lontano dallo scontro. Muri e ostacoli davanti al
robot, o ai nemici durante gli scontri, si diradano con un retino ordinato
che lascia visibili gli spigoli al neon: niente ordinamento delle trasparenze,
e il personaggio resta leggibile attraverso i fori.

Il centro del varco è completamente libero, per preservare la stampa del
personaggio; il retino sfuma soltanto ai bordi. Negli scontri l'inquadratura
corregge il proprio centro, entro sei celle, quando i combattenti vicini
finirebbero sotto la mano. Angolo, distanza e puntamento restano coerenti;
l'esplorazione conserva il suo inseguimento fluido originale.

La tela segue i pixel fisici dello schermo, compresi i display Retina,
mantenendo coordinate, input e impaginazione logici a 960×540. I bordi del
mondo sono nastri con copertura antialias calcolata in pixel. Il pavimento
è un unico piano con una texture di dati aggiornata solo quando cambia la
geometria: terreni, griglia e avvisi si animano nello shader.

Il colore dell'ambiente viene composto in RGBA16F, con estrazione delle
alte luci, sfocatura gaussiana e tone mapping. I segmenti neon vicini e le
luci mobili di robot, dispositivi e incendi illuminano le superfici. I
riflessi sono planari, renderizzati a metà risoluzione e sfocati; comprendono
l'architettura e i suoi neon, non le sagome di carta o gli oggetti posati
dalle carte. Questa scelta conserva l'effetto diorama e limita il costo GPU.
La superficie finale condivide la profondità dell'ambiente HDR, così il
passaggio al cartoncino conserva le occlusioni. Le risorse vengono ricreate
al ridimensionamento e rilasciate anche nelle viste temporanee.

Le mappe nuove raddoppiano ogni lato rispetto alle dimensioni iniziali:
l'area totale è quindi quattro volte maggiore. La geografia esterna sparge
le sagome del bioma: al massimo una cella solida per blocco di 3×3, con una
densità propria di ogni bioma e un margine dal bordo del vuoto. Una cella
libera conserva sempre due lati nel proprio blocco e gli ostacoli si toccano
solo attorno a uno spigolo di blocco, quindi nessuna sacca di pavimento resta
chiusa; un test lo verifica su tutti i biomi. City pop ed Egitto conservano
isolati e campi di piramidi; nei POI, gli ostacoli formano percorsi e
coperture. Nell'ologramma gli ostacoli sparsi restano bassi, perché cortili,
isolati e piramidi restino i punti di riferimento. Le spedizioni già salvate
conservano le celle con cui sono state create. I servizi occupano celle solide riconoscibili e si usano dalle
celle vicine; il varco del boss e i sigilli delle prove restano attraversabili.

Le regole comprendono
piastre elettriche, sabbie e acqua che rallentano, ghiaccio che fa scivolare,
lava e pavimento dell'Inferno che si frattura dopo l'avviso dell'eruzione,
trappole persistenti del Vietnam, killer itinerante del Southern
gothic, ponti di luce a battito, spinta aggiuntiva e pozzi gravitazionali
nello Spazio. Gli spettri gotici possono attraversare una copertura quando
esiste una cella di arrivo valida.

La generazione dell'Isola nel cielo mantiene raggiungibile ogni POI. Le
corsie e gli intenti dei boss cambiano con il bioma: laser incrociati,
colpi mirati, cariche, anelli, bombardamenti e inseguimento.

Le fratture dell'Inferno diventano lava permanente per quella spedizione e
sono salvate insieme alle celle del mondo. Rimangono attraversabili e
risparmiano i due passi attorno ai servizi, all'ingresso e all'uscita; non
possono separare un POI dal resto della mappa. La lava infligge danno sia
all'ingresso sia a ogni battito trascorso sulla cella, anche in esplorazione.

## Dodici cabinati

I sei minigiochi precedenti restano nel catalogo con presentazioni legate
ai biomi: catene e bagliori infernali nella Torre di Cenere; nuvole nelle
Guglie Sospese; stazione, droni alieni e Nave Madre nell'Arena; pavimenti
di legno, pannelli e ritratti nella casa infestata; piramidi, ankh e
sarcofagi nel puzzle; grattacieli al neon attorno alla rissa sul tetto.
Gli ID e le simulazioni dei cabinati esistenti sono conservati.

I sei nuovi hanno modelli
deterministici indipendenti dalla grafica, introduzione con i comandi,
pausa, punteggio, stelle e record attraverso la shell comune.

| ID | Titolo | Regola principale |
|---|---|---|
| `lightcycles` | Scie di luce | Quattro moto su una griglia; le scie diventano muri, le collisioni simultanee vengono risolte insieme. |
| `showdown` | Duello a mezzogiorno | Cinque estrazioni con segnale variabile; estrarre prima costa una vita, il tempo di reazione determina il punteggio. |
| `trex` | Fuga dal T-Rex | Corsa laterale, salto su rocce e tronchi, abbassamento sotto gli pterodattili; arrivo al portale. |
| `karaoke` | Karaoke | Quattro corsie, 64 note a 112 BPM, giudizi di precisione, combo e penalità per pressioni casuali; musica sintetica sincronizzata alla ripresa. |
| `helicopter` | Elicottero | Tiro dal portellone, bersagli con avviso prima dello sparo, 16 colpi e ricarica. |
| `descent` | Discesa | Sterzo con inerzia, alberi da evitare e portali da attraversare mentre lo yeti segue il giocatore. |

Codice: [memoryarcade](../src/memoryarcade/). Le grafiche sono procedurali:
ambiente geometrico al neon, silhouette con bordo di carta e inchiostro.
La grafica non consuma lo stream casuale della simulazione.

## Casinò: probabilità e persistenza

| Tavolo | Regola | Ritorno teorico |
|---|---|---|
| Slot del ranch | Rischio `min(0,02 + 0,03 × (moneta − 1), 0,60)`; incasso `0,98 / probabilità di sopravvivenza`. Le staccionate rallentano soltanto. | 98% a ogni moneta di uscita |
| Tre in fuga | Tre cadute indipendenti, stessa distribuzione per dinosauro/Panda/moto; `P(arrivare a M) = 0,97 / M`, raddoppio ogni 6 s. | 97% |
| Roulette europea | Un solo zero; numero pieno, colori, parità, basso/alto, dozzine e colonne. | 36/37, circa 97,30% |
| Duello di d20 | Due tiri uniformi; paga il doppio della puntata se il robot supera il banco. Il pari perde. | 95% |

Il ranch e Tre in fuga mostrano un incasso approssimativo: al momento
dell'incasso la frazione di credito viene arrotondata casualmente con
probabilità proporzionale alla frazione. Il risultato è fissato nello
snapshot. Questo evita che il semplice arrotondamento sempre verso il
basso aumenti il vantaggio del banco oltre quanto previsto con le puntate
piccole. La scelta di incassare precede il sorteggio dell'arrotondamento.

Il ranch mostra il proiettile e l'impatto del BANG. Tre in fuga distingue
l'inciampo del dinosauro, il ribaltamento della Panda e le scintille della
moto. Il tavolo dei dadi riusa la geometria a venti facce numerate e
smussate del combattimento.

La transazione memorizza gli esiti nascosti, la puntata, il selezionato,
il tempo, le monete e lo stream RNG. Il deposito viene addebitato prima del
salvataggio iniziale: questo checkpoint è sincrono e la giocata non parte
se la scrittura fallisce. La stessa barriera protegge l'incasso prima di
accettare una nuova puntata. Una transazione attiva non può essere sostituita da
un'altra. L'incasso viene accreditato una volta sola. Se l'accredito non
può essere completato, resta dovuto nella transazione.

La prova automatica esegue **1.000.000 di giocate per gioco**, controllando
le prime 12 uscite del ranch, quattro moltiplicatori per ciascuno dei tre
corridori e tutte le categorie di roulette. Una seconda verifica enumera
esattamente le 37 uscite della roulette. Nell'esecuzione registrata:
ranch 97,99% alla prima moneta e 97,75% alla dodicesima; Tre in fuga
96,74% a ×2 per il primo corridore; rosso alla roulette 97,31%; dadi 95,03%.
Le tolleranze dei test tengono conto della varianza dei premi.

## Verifiche ripetibili

```sh
odin check src -vet -strict-style
odin test src/game -define:ODIN_TEST_FULL=false
odin test src/expedition
odin test src/campaign
odin test src/campaignui
odin test src/memoryarcade -o:speed
odin test src/engine/audio
odin test src/render -define:ODIN_TEST_FULL=false
odin test src/run -define:ODIN_TEST_FULL=false
odin test src/application
```

Sono stati verificati replay deterministici dei sei nuovi cabinati su 16
seed ciascuno, loro conclusione entro 80 secondi, collisioni testa contro
testa, estrazione anticipata, giudizi musicali, ripresa delle scommesse e
probabilità del casinò. I test dell'inventario comprendono rotazioni,
collisioni, pile, scambio delle reliquie, consumo in scontro, morte,
estrazione a zero stelle, pool delle carte, finali e indipendenza dei tre
slot. I test del mondo comprendono geografia indipendente dal seed,
collegamenti dell'arcipelago, ondate finite, guinzaglio, trappole e snapshot.

Nella fase Retina/HDR, `scripts/check.sh` completo ha superato 1.427 test
sia con sia senza assert. I controlli includono i test del mondo, la ripresa dei nidi, gli
ingaggi dopo un'esca, l'ologramma completo, i segreti e i record dell'hub;
il movimento libero ha test propri (arresto e scivolamento lungo i muri,
nessun passaggio fra ostacoli in diagonale, trappole sulla nuova cella,
spinte esterne, attesa durante gli scontri, velocità in sella) e un test
verifica che gli ostacoli sparsi non chiudano pavimento in nessun bioma. Fanno fede gli esiti delle suite: i conteggi
cambiano quando vengono aggiunte regressioni.

Gli smoke producono PNG in `build/captures`:

```sh
./run.sh --smoke-hub
./run.sh --smoke-expedition
./run.sh --smoke-minigame=lightcycles
./run.sh --smoke-minigame=showdown
./run.sh --smoke-minigame=trex
./run.sh --smoke-minigame=karaoke
./run.sh --smoke-minigame=helicopter
./run.sh --smoke-minigame=descent
```

La verifica visiva dei sei nuovi cabinati e delle quattro tavole è stata
eseguita alla risoluzione logica nativa 960×540. Ha individuato e corretto
il verso di alcuni triangoli del fondale, la leggibilità dei dadi, il
tavolo della roulette e la corrispondenza tra fermata della ruota e numero
estratto. Sono state inoltre catturate e controllate le sei presentazioni
dei cabinati precedenti, il BANG, le tre cadute e i d20 veri del gioco;
le correzioni finali hanno eliminato il testo sovrapposto alle cadute e
reso leggibile il rivestimento di legno della casa infestata.

Gli smoke finali di hub e spedizione coprono la nuova legenda, l'ologramma
160×160 e 224×224, quattro POI, i dodici biomi, record e seconda pagina dei
cabinati. Lo smoke della spedizione cattura anche il robot dietro le mura
della tana (`dietro_muro`), poi guida la scena vera con i tasti tenuti
premuti: una corsa in sella (`camminata`) e una camminata verso una
pattuglia fino all'ingaggio (`ingaggio`), stampando posizione, cella e fase;
infine i dodici biomi con l'inquadratura delle catture di riferimento
(`centro_00`–`centro_11`), e quattro scontri con una carta scelta in Neve, Far West,
Giungla e Spazio (`bersagli_neve`, `bersagli_far_west`, `bersagli_giungla`,
`bersagli_spazio`: il segno dei nemici colpibili sui quattro biomi; con
`ODIN_PP_SMOKE_ONLY=hits` partono solo quelli). Dopo un'interruzione dovuta al monitor non
disponibile, la sessione grafica è tornata accessibile: le nuove catture
native sono state controllate. La mappa intera, gli indicatori e la legenda risultano leggibili;
il robot conserva il bordo di carta, la griglia di combattimento è visibile
e le schermate dell'hub non presentano sovrapposizioni. Tutti gli shader
della build finale sono stati compilati e caricati dal driver.

La successiva revisione Retina/HDR è stata verificata su Apple M1 a
2560×1440 pixel fisici. Lo smoke ridimensiona anche la finestra durante
zaino, scheda personaggio e ologramma, tornando poi alla dimensione iniziale.
Tre letture dei buffer RGBA16F verificano valori finiti superiori a 1
nell'ambiente e nei riflessi, bagliore non nullo e profondità condivisa;
la cache del pavimento resta invariata durante i fotogrammi senza modifiche
alla geometria. Le 39 immagini native sono raccolte nella
[galleria Retina e neon](../build/captures/renderer-retina-neon/index.html).
La cattura usa `LoadImageFromScreen`: `TakeScreenshot` nella versione
installata applicava due volte il fattore Retina.

Le verifiche di questa revisione comprendono nastri in prospettiva,
ortografica e specchio a quattro risoluzioni, clipping vicino alla camera,
normali delle facce, invalidazione e durata della cache del pavimento,
32 sorgenti luminose con selezione delle più vicine, luci che si spostano
o scompaiono e valori dei materiali per tutti i biomi. Il test nativo della
tela verifica anche input, ritagli, Fit/Integer/Stretch e target annidati.
Il modulo grafico di quella revisione comprendeva 329 test superati, incluse
tre prove dell'inquadratura: una riproduce lo scontro reale dello smoke e verifica
visibilità e puntamento dopo 35 fotogrammi. Anche la suite del renderer
senza assert è passata (329/329). Il controllo sorgente `-vet -strict-style`
è pulito. Lo smoke nativo finale si è chiuso con codice 0, producendo tutte
le 39 catture senza errori di compilazione degli shader.

Per eseguire una build ottimizzata:

```sh
odin build src -o:speed -out:build/odin_pp
./build/odin_pp --expedition
```

`run.sh` mantiene la compilazione rapida senza ottimizzazione per lo sviluppo.
`./run.sh --release --expedition` usa invece `-o:speed`; `--release` deve
precedere gli argomenti del gioco. Lo stesso comando è disponibile in
`run.ps1` su Windows. Cinque prove di `run.sh` con un compilatore simulato
verificano selezione dell'ottimizzazione, argomenti con spazi o vuoti,
directory di lavoro e propagazione del codice di uscita. PowerShell non è
installato sulla macchina di verifica: `run.ps1` è stato letto, ma non
eseguito in questa sessione.

## Revisione Cyber e prestazioni — 22 ottobre 2026

Questa fase successiva mantiene la risoluzione fisica nativa, l'ambiente HDR,
i riflessi planari e il passaggio separato della carta. Non introduce una
riduzione automatica della risoluzione. L'interruzione dovuta al monitor è
stata superata: la build finale ha completato lo smoke nativo con 40
catture e tre controlli HDR. Le immagini Retina descritte sopra restano
la documentazione della fase precedente; la verifica di questa fase
comprende anche il nuovo Cyber industriale e l'officina.
Il benchmark finale misura 64,89 fps nell'esplorazione iniziale e 52,89 fps
nello scontro Cyber: il miglioramento è misurato, ma l'obiettivo di 60 fps
costanti non è ancora raggiunto. I confronti e i limiti sono riportati sotto.

Nel codice sono presenti:

- **Cyber industriale:** rocce sfaccettate, armadi server, nastri e bracci
  meccanici, metallo smussato, recessi scuri e indicatori rossi selettivi.
  Una luce di riempimento fredda rende leggibili le facce scure; il neon
  Cyber ha emissione ridotta rispetto agli altri biomi. Il pavimento usa
  pannelli antracite con variazioni stabili, fughe sottili, oscuramento presso
  le pareti reali, rugosità variabile e piastre elettriche ciano. Le regole
  delle celle e la stampa dei personaggi restano separate dai materiali.
  Codice: [geometria Cyber](../src/render/expedition_cyber.odin),
  [materiali](../src/render/expedition_material.odin) e
  [pavimento](../src/render/expedition_floor.odin).
- **Cache dell'architettura:** geometria statica preparata e caricata in
  blocchi di 8×8 celle, riusata nei passaggi normale e riflesso. La chiave
  comprende identità e revisione della mappa, dimensioni, bioma e stato dei
  siti; tempo cosmetico, camera e fase di combattimento non la invalidano.
  Il disegno esclude i blocchi fuori campo e conserva la rivelazione degli
  attori dietro i muri. Se un caricamento rileva un errore, torna al percorso
  immediato e non ripete il tentativo a ogni frame per la stessa chiave.
  Codice: [expedition_geometry.odin](../src/render/expedition_geometry.odin).
- **Dati del pavimento compatti:** ogni cella occupa quattro byte RGBA con
  tipo, terreno, superficie, variazione e bordi precalcolati. Lo shader usa
  una sola lettura della texture dei dati; non legge quattro celle vicine
  per ricavare gli stessi bordi a ogni frammento. La texture cambia con la
  geometria, mentre gli avvisi e la griglia animata restano uniformi. La
  griglia non esegue i calcoli di distanza dagli attori quando è invisibile.
  Codice: [expedition_floor_data.odin](../src/render/expedition_floor_data.odin).
- **Sfocatura a nove letture:** bloom e riflessi accoppiano i campioni
  adiacenti usando il filtro bilineare, riproducendo i pesi della precedente
  gaussiana a diciassette campioni per passaggio. I pesi vengono calcolati
  sulla CPU, conservando energia, linee HDR sottili e comportamento ai bordi.
  Codice: [expedition_post.odin](../src/render/expedition_post.odin).
- **Illuminazione:** reciproci di lunghezza e raggio calcolati per sorgente,
  esclusione tramite distanza al quadrato prima dei calcoli speculari, fino
  a 32 luci con spazio riservato alle sorgenti mobili. Le nuove maschere
  conservative suddividono la zona vicina alla camera in 8×8 settori di
  otto unità; ogni frammento valuta solo le sorgenti che possono raggiungere
  il suo settore. Fuori dalla zona vengono considerate tutte le sorgenti;
  specchi e altezza non eliminano contributi validi. La modalità si può
  disattivare per confronto con `EXPEDITION_TILED_LIGHTS=false`.
  Codice: [expedition_lighting.odin](../src/render/expedition_lighting.odin).
- **Pozze sulle mappe grandi:** la cronologia grafica ora copre tutte le
  224×224 celle, compresa l'ultima riga. Mantiene un bit per cella, 6.272 byte
  per copia, senza introdurre memoria condivisa fra istantanee precedenti
  e successive. Il test verifica la vecchia soglia di 16.384 celle e le
  copie conservate durante le animazioni.
- **Testi dell'interfaccia:** i glifi dei sette atlanti Gothic vengono
  ritagliati sulla CPU, conservando coordinate della texture, spaziatura,
  margini e arrotondamento verso l'esterno sui pixel fisici. Questo evita
  il cambio dello scissor GL e lo svuotamento del batch per ogni etichetta.
  Il font predefinito o mancante conserva il percorso precedente per
  mantenere esattamente la sua rasterizzazione. Il confronto può usare
  `GOTHIC_CPU_TEXT_CLIP=false`. Codice:
  [gothic_text_clip.odin](../src/render/gothic_text_clip.odin).

Durante lo sviluppo la suite del renderer è passata a
**345/345 con e senza assert** dopo le
modifiche a pavimento, cache, blur e pozze; il controllo `-vet -strict-style`
è passato. Successivamente, le cinque regressioni delle maschere hanno
portato i test dell'illuminazione a **13/13**: comprendono oltre 50.000
campioni, bordi, coordinate negative, ultima sorgente, ricentramento e
riordino delle luci mobili. Anche i controlli sorgente con maschere abilitate
e disabilitate sono passati. La verifica completa precedente all'ultimo
intervento sui testi, registrata in
[cyber-tests.log](../build/captures/cyber-tests.log), ha superato **1.458/1.458 test con assert
e altrettanti senza assert**, compresi i controlli sorgente rigorosi.

Dopo l'aggiunta dei cinque test dei glifi sono passati il profilo rapido
di tutti i pacchetti, **1.456/1.456**, e l'intera suite del renderer senza
assert, **355/355**. I conteggi appartengono a profili diversi: il rapido
esclude alcune verifiche lunghe. Log:
[pacchetti finali](../build/captures/cyber-tests-quick-final.log) e
[renderer finale](../build/captures/cyber-tests-render-final.log).
Anche il controllo rigoroso con ritaglio CPU attivo e disattivo è passato.

La compilazione degli shader è stata inoltre verificata direttamente sul
driver Apple M1, OpenGL 4.1 e GLSL 4.10, tramite un contesto CGL fuori schermo:
**16/16 programmi** compilati e collegati, otto con maschere attive e otto
senza. Sei confronti di pixel RGBA32F hanno dato errore massimo zero per
sorgenti selezionate, bit 31, settore vuoto, punto fuori griglia e specchio.
Il [rapporto della verifica shader](../build/captures/cyber-validation-shaders.txt)
descrive procedura e limiti; questa prova non misura gli fps.

Una seconda prova nativa confronta il testo vecchio e nuovo senza tolleranza:
**48/48 confronti con zero pixel differenti e zero errori GL**, usando i
sette atlanti Jersey10 reali, scale fisiche 1×, 2× e 8/3×, target diretti e
ripristinati dopo un target annidato, più il font di ripiego. Copre ritagli
su tutti i lati, Unicode, righe multiple e caratteri mancanti. Il font di
ripiego mantiene lo scissor originale proprio perché le prime prove
avevano rilevato differenze sui confini dei texel.
Il [rapporto del testo](../build/captures/cyber-validation-text.txt) documenta
la politica finale e i limiti della prova.

Lo [smoke nativo](../build/captures/cyber-smoke.log) si è
chiuso con codice 0, ha esportato **40 PNG** e non ha segnalato errori degli
shader. I tre controlli dei buffer hanno confermato HDR, bloom, riflessi e
profondità condivisa anche durante il ridimensionamento. La verifica visiva
di Cyber, officina, combattimento, rivelazione dietro i muri e altri biomi
è positiva. Le immagini sono raccolte nella
[galleria Cyber industriale](../build/captures/cyber-industriale/index.html),
disponibile anche come [archivio ZIP](../build/captures/cyber-industriale.zip).
Restano separati i risultati del benchmark senza limite fps,
riportati di seguito.

### Primo benchmark senza limite fps

Il [log iniziale](../build/captures/cyber-benchmark-initial.log), conservato
anche come `/private/tmp/odin-cyber-benchmark-first.log`, registra il primo
passaggio completo su **Apple M1**, con `target_fps=0` e `vsync_hint=false`.
I seguenti casi usano tutti una tela fisica da **2560×1440**:

| Scena | Stage | Media frame | 95° percentile | FPS medi |
|---|---:|---:|---:|---:|
| Esplorazione iniziale Cyber | 0 | 17,011 ms | 19,169 ms | 58,79 |
| Scontro Cyber | 5 | 28,222 ms | 32,454 ms | 35,43 |
| Corsa in sella nel ricordo | 25 | 20,829 ms | 26,199 ms | 48,01 |
| Avvicinamento e ingaggio nel ricordo | 26 | 26,142 ms | 31,551 ms | 38,25 |
| Centro Cyber | 27 | 22,538 ms | 27,639 ms | 44,37 |
| Officina Cyber | 39 | 21,290 ms | 27,202 ms | 46,97 |

Sono risultati del primo passaggio, precedenti al completamento dell'ultima
rifinitura, della strumentazione dettagliata e delle maschere delle luci.
Il riferimento iniziale è circa 59 fps in esplorazione e 35 fps nello
scontro; non rappresenta il risultato del passaggio successivo.

### Passaggio intermedio con cache e maschere delle luci

Il [benchmark intermedio](../build/captures/cyber-benchmark-tiled.log) si è
concluso regolarmente, con gli stessi stage e dimensioni della tela. Include
cache dei blocchi, dati compatti del pavimento e maschere delle luci, ma
precede l'ottimizzazione del ritaglio dei testi dell'interfaccia:

| Scena | Stage | Media iniziale | Media intermedia | 95° percentile intermedio | FPS intermedi |
|---|---:|---:|---:|---:|---:|
| Esplorazione iniziale Cyber | 0 | 17,011 ms | 16,178 ms | 17,997 ms | 61,81 |
| Scontro Cyber | 5 | 28,222 ms | 25,100 ms | 29,382 ms | 39,84 |
| Corsa in sella nel ricordo | 25 | 20,829 ms | 15,839 ms | 17,415 ms | 63,14 |
| Avvicinamento e ingaggio nel ricordo | 26 | 26,142 ms | 20,725 ms | 21,913 ms | 48,25 |
| Centro Cyber | 27 | 22,538 ms | 15,263 ms | 15,859 ms | 65,52 |
| Officina Cyber | 39 | 21,290 ms | 16,160 ms | 16,673 ms | 61,88 |

Il confronto misura l'insieme delle modifiche fra due esecuzioni e non
isola il contributo delle maschere. **60 fps costanti non sono dimostrati**,
in particolare negli scontri.

Un successivo [confronto senza maschere](../build/captures/cyber-benchmark-untiled.log)
ha completato gli stage 0–7 con la stessa revisione di geometria e shader,
cambiando soltanto `EXPEDITION_TILED_LIGHTS=false`:

| Scena | Stage | Maschere disattivate | Maschere attive |
|---|---:|---:|---:|
| Esplorazione iniziale Cyber | 0 | 17,730 ms | 16,178 ms |
| Scontro Cyber | 5 | 27,796 ms | 25,100 ms |
| Uscita della tana Cyber | 6 | 23,050 ms | 17,983 ms |

Sono medie del frame su esecuzioni brevi svolte in sequenza, non misure GPU
né prove alternate ripetute. Indicano un miglioramento in questi campioni;
non stabiliscono un guadagno garantito delle maschere su ogni scena o
dispositivo. Entrambe le build precedono l'ottimizzazione del testo.

I contatori confermano zero ricostruzioni e caricamenti misurati dopo il
riscaldamento in tutte le scene ferme. Nella corsa, stage 25, vengono
caricati sette nuovi blocchi senza ricostruire la cache; nell'ingaggio,
stage 26, i nuovi caricamenti avvengono durante il riscaldamento.
Il profiler attribuisce alla sezione CPU `hud_hand_ms` 8,189 ms nello stage
0 e 15,497 ms nello stage 5. Questa osservazione ha motivato il successivo
intervento sui ritagli dei testi, incluso nel benchmark finale seguente.

### Risultato finale con ritaglio dei glifi

Il [benchmark finale](../build/captures/cyber-benchmark-final.log) ha
completato tutti i 40 stage con codice 0, maschere delle luci e ritaglio CPU
dei testi attivi. Mantiene risoluzione nativa, materiali, bloom e riflessi.
Questi sei casi usano tutti 2560×1440 pixel fisici:

| Scena | Stage | Media iniziale | Media finale | 95° percentile finale | FPS finali |
|---|---:|---:|---:|---:|---:|
| Esplorazione iniziale Cyber | 0 | 17,011 ms | 15,410 ms | 17,624 ms | 64,89 |
| Scontro Cyber | 5 | 28,222 ms | 18,907 ms | 24,747 ms | 52,89 |
| Corsa in sella nel ricordo | 25 | 20,829 ms | 16,913 ms | 19,870 ms | 59,12 |
| Avvicinamento e ingaggio nel ricordo | 26 | 26,142 ms | 17,104 ms | 19,368 ms | 58,47 |
| Centro Cyber | 27 | 22,538 ms | 16,385 ms | 21,548 ms | 61,03 |
| Officina Cyber | 39 | 21,290 ms | 16,415 ms | 17,228 ms | 60,92 |

Il tempo CPU registrato in `hud_hand_ms` scende a 0,168 ms nello stage 0
e 0,240 ms nello stage 5. Le attese del driver si redistribuiscono però fra
le sezioni: il tempo attribuito al mondo cresce rispetto al passaggio
intermedio. **Il beneficio va valutato sui frame completi**, non sottraendo
i tempi di una singola sezione CPU né interpretandoli come misure GPU.
Rispetto all'intermedio alcuni casi, fra cui corsa e centro Cyber, risultano
più lenti: le esecuzioni sequenziali non dimostrano un guadagno uniforme
su ogni scena. Rispetto al riferimento iniziale migliorano tutti i sei
casi riportati.

Anche nel log finale tutte le scene ferme hanno zero ricostruzioni e
caricamenti della geometria dopo il riscaldamento; la corsa carica sette
nuovi blocchi senza ricostruire la cache. Il bersaglio di **60 fps costanti
resta non raggiunto**: scontro, movimento e ingaggio rimangono sotto quella
media e i percentili mostrano frame più lenti anche dove la media la supera.
Le prossime aree da misurare sono i tempi GPU, il raggruppamento del disegno
della carta e il costo degli effetti attivi. Non è stato applicato alcun
preset a risoluzione ridotta per ottenere questi risultati.

### Ripetere il benchmark e leggere il profiler

Su una sessione grafica con monitor disponibile, dalla radice del progetto:

```sh
mkdir -p build
odin build src -o:speed -define:EXPEDITION_BENCHMARK=true -out:build/odin_pp-benchmark
./build/odin_pp-benchmark --smoke-expedition > build/expedition-benchmark.log 2>&1
rg '^(EXPEDITION BENCHMARK|CPU SUBMISSION|CPU SCENE|CPU WORLD|GEOMETRY CACHE)' build/expedition-benchmark.log
```

Il percorso comprende tutti gli stage dello smoke, 0–102 (fino al 25 ottobre
2026 si fermava al 50; i log della revisione Cyber precedente terminano allo
stage 39). Scarta i primi 20 frame di ogni scena,
ne misura 120, oppure 240 per corsa e ingaggio, e termina automaticamente.
Le scene ferme conservano uno stato di gioco prestabilito e aggiornano
presentazione e animazioni; soltanto corsa e ingaggio, stage 25 e 26,
eseguono l'aggiornamento completo della scena con input di movimento. La
misura dello scontro fermo descrive quindi il disegno di quella situazione,
non tutti i costi di una battaglia giocata.
Per misurare solo una parte si scelgono primo e ultimo stage in compilazione,
per esempio `-define:EXPEDITION_BENCHMARK_FIRST=63 -define:EXPEDITION_BENCHMARK_LAST=98`
(rilievi, ologrammi, montagna e grotte); `-define:EXPEDITION_BENCHMARK_LAST=7`
basta per un controllo breve. Gli stage prima del primo preparano comunque la
loro scena, senza misurarla, così ogni stage misurato parte come in un giro
intero. Ogni scena si disegna su un canvas fisso di 1920×1080 pixel, qualunque
siano la finestra e il ridimensionamento dello schermo
(`EXPEDITION_BENCHMARK_CANVAS_WIDTH` e `_HEIGHT`; 0 e 0 seguono la finestra,
come prima): il log lo riporta in `canvas_px`. Sui portatili con due schede
video la riga `Renderer:` del log dice quale scheda ha disegnato.
Le misure di partenza del 25 ottobre 2026, su Windows con una RTX 3060, sono
nella Fase 0 e nell'appendice A di [piano-profondita.md](piano-profondita.md).
Il benchmark disabilita il limite fps e la richiesta di VSYNC;
esclude screenshot e letture dei buffer GPU. Il compositore e il driver
possono comunque influenzare la presentazione. La prova visiva e HDR resta
un'esecuzione separata di `--smoke-expedition` compilata senza il flag.

Per confrontare le maschere con il percorso che valuta tutte le luci:

```sh
odin build src -o:speed -define:EXPEDITION_BENCHMARK=true -define:EXPEDITION_TILED_LIGHTS=false -out:build/odin_pp-benchmark-all-lights
./build/odin_pp-benchmark-all-lights --smoke-expedition > build/expedition-benchmark-all-lights.log 2>&1
```

Confrontare gli stessi stage e `canvas_px`, sullo stesso monitor e con lo
stesso carico di sistema; ripetere alternando l'ordine delle due build. Lo
smoke ridimensiona alcune schermate: con il canvas fisso i pixel disegnati
restano gli stessi, mentre con il canvas che segue la finestra le medie di
scene con tele diverse non misurano lo stesso lavoro.

`EXPEDITION BENCHMARK` riporta gli intervalli fra frame presentati, inclusi
aggiornamento, invio, presentazione e attese del driver. `CPU SUBMISSION`,
`CPU SCENE` e `CPU WORLD` misurano tempo CPU: scena, mondo, interfaccia,
ologramma e dieci sezioni del disegno, oltre a riflessi, blur, bloom e
composizione. **Non sono tempi GPU**; alcuni ambiti sono annidati e non
vanno sommati fra loro. Il primo log sopra contiene soltanto il dettaglio
`CPU SUBMISSION`, perché gli altri contatori sono stati aggiunti dopo.
`GEOMETRY CACHE` distingue ricostruzioni e caricamenti dall'inizio della
scena e dopo il riscaldamento: su una scena immobile senza modifiche i delta
misurati dovrebbero restare a zero; durante il movimento sono ammessi nuovi
blocchi. Un azzeramento dei contatori è segnalato separatamente.
Codice: [campaign_smoke.odin](../src/application/campaign_smoke.odin),
[expedition_scene.odin](../src/run/expedition_scene.odin) e
[tactical_renderer.odin](../src/render/tactical_renderer.odin).

## Rifinitura degli altri undici biomi e seconda ottimizzazione

La revisione estende la costruzione dedicata di Cyber agli altri undici
biomi. Geografia e regole delle celle restano quelle della campagna;
architetture, arredi dei nove tipi di POI e materiali ora distinguono i
percorsi. I personaggi mantengono la sagoma di cartoncino. La
[galleria finale contiene 51 catture native](../build/captures/biomi-rifiniti/index.html),
anche in [archivio ZIP](../build/captures/biomi-rifiniti.zip).

| Bioma | Elementi distintivi |
|---|---|
| West | Mesas stratificate, cactus, legno e ferro, pozzo, telegrafo e incudine; sabbia e passerelle di assi. |
| Giungla | Tronchi con radici, chiome a ombrello, fronde, ossa e idoli; terra e cortili di pietra. |
| City | Facciate, tetti e insegne magenta/ciano, chioschi e terminali; asfalto umido e marciapiedi. |
| Egitto | Arenaria, obelischi, capitelli, sarcofagi e altari turchesi; sabbia e lastre del tempio. |
| Vietnam | Bambù, sacchi, bunker, radio e memoriale; fango e camminamenti di pietra. |
| Neve | Roccia e ghiaccio, rifugi e apparati; superfici di pietra con brina. |
| Inferno | Corone basaltiche, fessure incandescenti, fornace e forgia; lastre scure e lava. |
| Gothic | Lapidi, croci, cripte, ferro e lanterne; pietra umida con muschio. |
| Cielo | Colonne, marmo, oro e astrolabi; grandi lastre con venature discrete. |
| Spazio | Asteroidi, cristalli, sonde e antenne; polvere opaca e pavimenti metallici. |
| Segreto | Ossidiana, cubi sospesi, oro e archivio del creatore con libro e piccolo robot. |

Le verifiche sulle immagini hanno portato a rifare le chiome della giungla,
attenuare le sommità troppo luminose di Neve/Cielo e i dettagli dorati del
Segreto, ridurre le emissioni di West/Egitto e rendere meno invadenti i
ponti del Cielo e gli anelli gravitazionali. Posizioni, forme e tempi dei
pericoli restano coerenti con la simulazione. Il pavimento conserva una
sola lettura della texture della mappa per frammento: le differenze dei
materiali usano il bioma uniforme e la variazione già memorizzata.

### Modifiche alle prestazioni

- Otto buffer di disegno in rotazione sostituiscono il singolo buffer
  dinamico predefinito. Il driver può lavorare sui precedenti mentre viene
  preparato il successivo. La risoluzione di mondo e interfaccia resta
  nativa; bloom e riflessi mantengono le dimensioni precedenti.
- Anche portali e arredi statici dei POI vengono caricati in mesh GPU e
  riusati per vista normale e riflessa. Il portale di uscita animato resta
  separato. Posizione, orientamento, stato, segreti e sconfitta del boss
  invalidano la cache; tempo, camera e animazioni non la invalidano.
- La selezione delle mesh che devono diventare trasparenti considera tutta
  la loro estensione. Un muro davanti al robot non resta opaco soltanto
  perché il centro del suo gruppo si trova dietro di lui.

Il caricamento dei buffer segue l'inizializzazione delle normali del
[sorgente ufficiale raylib 6.0](https://github.com/raysan5/raylib/blob/6.0/src/rlgl.h).
Il binding Odin del contenitore `RenderBatch` resta compatibile, mentre
quello del buffer interno è precedente: il codice non dereferenzia quella
struttura e lascia allocazione e rilascio alla libreria nativa. Ogni vista
possiede le proprie cache; il buffer globale della finestra usa un puntatore
stabile e viene rilasciato prima della chiusura del contesto grafico.

### Verifiche della revisione

- Suite completa: **1.482/1.482 test con assert e 1.482/1.482 senza assert**,
  [log delle due esecuzioni](../build/captures/biomes-tests.log).
- Verifiche focalizzate ripetute dopo le ultime correzioni di chiome e
  palette; controlli strict e build ottimizzate completati.
- Test di geometria su dodici biomi, nove tipi di POI e quattro rotazioni:
  normali finite, determinismo, limiti di complessità e rispetto degli
  ingombri. Trial e Tunnel restano bassi e attraversabili; i portali Boss
  conservano l'apertura. Test della cache e della trasparenza inclusi.
- Smoke finale: **51 catture**, uscita regolare e verifiche native
  HDR/bloom/riflessi superate anche dopo il ridimensionamento;
  [log grafico](../build/captures/biomes-smoke-final.log).

### Misure finali a risoluzione nativa

Due esecuzioni complete da 51 stage, con il confronto a buffer singolo
interposto fra loro: [prima esecuzione](../build/captures/biomes-benchmark-final-a.log),
[buffer precedente](../build/captures/biomes-benchmark-single-buffer.log),
[seconda esecuzione](../build/captures/biomes-benchmark-final-b.log).
Mac Apple M1, build `-o:speed`, 2560×1440 pixel nelle scene sotto; nessun
limite software fps, nessuno screenshot nel campione. Le build del confronto
hanno gli stessi asset, shader, cache e impostazioni: cambia soltanto
`WINDOW_RENDER_BATCH_BUFFERS`, 8 oppure 0 (batch predefinito di raylib).

| Scena Cyber | Buffer precedente, ms medi | Otto buffer, prova A | Otto buffer, prova B |
|---|---:|---:|---:|
| Esplorazione iniziale | 15.803 | 12.330 | 12.214 |
| Scena di scontro | 18.282 | 14.161 | 14.134 |
| Uscita della tana | 16.809 | 15.315 | 15.241 |
| Archivio | 17.739 | 14.097 | 14.054 |

Il miglioramento si ripete nelle due esecuzioni con buffer in rotazione;
sono comunque campioni brevi su una sola macchina, non una garanzia per
ogni dispositivo. I tempi indicano frame completi, non tempi GPU.

| Scena | FPS medi prova A | FPS medi prova B | 95° percentile prova B |
|---|---:|---:|---:|
| Esplorazione Cyber | 81.10 | 81.87 | 13.590 ms |
| Scena di scontro Cyber | 70.62 | 70.75 | 16.632 ms |
| Corsa nel ricordo | 70.38 | 70.46 | 16.908 ms |
| Avvicinamento e ingaggio | 67.64 | 68.15 | 17.528 ms |
| Centro Cyber | 80.21 | 80.61 | 14.604 ms |
| Officina Cyber | 72.70 | 72.55 | 15.897 ms |

Le scene dei nuovi biomi, con i materiali e la geometria rifiniti, misurano:

| Bioma | Centro, FPS prova A / B | Officina, FPS prova A / B |
|---|---:|---:|
| West | 71.82 / 72.14 | 68.21 / 68.87 |
| Giungla | 69.74 / 70.02 | 70.20 / 71.06 |
| City | 59.19 / 59.87 | 65.08 / 65.09 |
| Egitto | 71.99 / 72.48 | 70.31 / 69.34 |
| Vietnam | 87.48 / 88.05 | 89.33 / 89.56 |
| Neve | 72.92 / 73.22 | 68.97 / 69.38 |
| Inferno | 79.11 / 79.95 | 68.05 / 68.47 |
| Gothic | 84.86 / 85.06 | 85.03 / 85.36 |
| Cielo | 82.21 / 82.35 | 71.16 / 71.14 |
| Spazio | 76.31 / 76.40 | 69.12 / 69.10 |
| Segreto | 77.06 / 77.43 | 66.31 / 66.89 |

Le scene ferme hanno zero ricostruzioni e caricamenti misurati dopo il
riscaldamento in entrambe le prove. La corsa carica sette nuovi blocchi
senza ricostruire la cache. Solo gli stage 25 e 26 includono il vero
aggiornamento della scena con input; gli scontri fermi misurano il disegno
di quella situazione, non una battaglia completa giocata.

**60 fps costanti non sono ancora raggiunti in tutti gli scenari**: il centro
della City resta intorno a 59–60 fps medi; anche scene con medie superiori
presentano frame oltre 16,7 ms. I miglioramenti mantengono risoluzione nativa,
bloom e riflessi. Le prossime verifiche utili riguardano i tempi GPU e le
scene più dense della città, prima di qualsiasi ulteriore compromesso visivo.

Per ripetere il confronto con il vecchio buffer, compilare con
`-define:WINDOW_RENDER_BATCH_BUFFERS=0` oltre a `-define:EXPEDITION_BENCHMARK=true`.
`-define:EXPEDITION_BENCHMARK_LAST=7` limita il confronto agli otto scenari
iniziali; ometterlo esegue tutte le 51 scene. La build normale pronta da
avviare è `build/odin_pp`; conserva il limite fps delle impostazioni di gioco.

## Strutture su più caselle (Fase 6 del piano griglia)

- **Livello:** `level.Tile_Kind.Fence` (blocca il passo, non la vista); `src/level/structure.odin`
  legge le piante, le ruota e le specchia, controlla e posa; il catalogo è in
  `structure_catalog.odin`. Il livello tiene l'elenco, le piante ruotate e per ogni cella il numero
  della struttura sopra (`structure_index_at`).
- **Regole:** nessuna nuova (le caselle sono ordinarie); la vista lascia passare il muretto
  (`game.cell_blocks_line_of_sight`). `game.structure_visibility` è la funzione pura della trasparenza.
- **Spedizioni:** `World.structures` (24 al massimo) è salvato con il mondo; il ripristino ricostruisce
  l'indice dalle caselle salvate; il generatore posa le strutture di Robotica cibernetica dopo i servizi,
  cercando il posto libero più vicino in un ordine fisso, quindi la stessa geografia a ogni run.
- **Grafica:** vedi `docs/presentazione.md`.
- **Limiti:** per ora solo Robotica cibernetica (il bioma di prova scelto dall'utente) ha strutture; le
  piante non hanno altezze (le cifre `1`…`9` non sono accettate, le spedizioni restano piatte fino alla Fase 3);
  l'arredo degli edifici è minimo (pavimento, altare del tempietto); nei riflessi del pavimento non compare
  l'involucro; l'ologramma non mostra i muretti. La posa da parte del giocatore è la Fase 7.

## Rilievi delle spedizioni (Fase 3 del piano griglia)

- **Generatore:** `src/expedition/relief.odin` calcola le altezze come funzione pura del bioma e delle
  coordinate (cumuli, dune, terrazze, crateri, isole del Cielo, altopiani con scala), in due strati: il
  liscio, rilassato perché due celle vicine siano al massimo a un gradino, e piano attorno a servizi,
  partenza e pattuglie; e gli altopiani, con i loro dirupi, solo ben lontano da quel terreno piano.
  `level.set_height_table` scrive la tabella; `generate` la applica dopo i servizi e prima delle strutture.
- **Salvataggio:** `Snapshot.heights`, una tabella `[MAX_CELLS]u8` in più; manca nei salvataggi vecchi e
  vale zero (piatto).
- **Esplorazione:** `roam_blocked`, `walk`, `move_sleeping_group`, `patrol_move_toward` e `can_see` usano
  `game.step_height_blocked` e le altezze della linea di vista.
- **Renderer:** dalla Fase 1 del piano della profondità il rilievo è la superficie scolpita
  (`level/surface.odin`) in `render/expedition_terrain.odin`: rampe, pareti di roccia sfaccettate e un bordo
  al neon tenue in cima ai dirupi (prima erano terrazze). `Ink_Pass.lift` alza muri, prop, servizi e
  strutture alla quota della cella; l'ologramma in `run/expedition_hologram.odin`.
- **Limiti:** vedi l'Esito della Fase 3 nel piano.

## La montagna a spirale (Fase 4 del piano griglia)

- **Forma:** `src/level/mountain.odin`: `mountain_height(offset)` e `mountain_icy(offset)` sono funzioni pure della
  posizione rispetto al centro; una casella appartiene al giro più vicino e ha la quota di quel giro all'angolo
  suo (lunghezza del sentiero), quindi le caselle affiancate hanno la stessa quota. `mountain_stamp` la scrive
  su un `Level` (spiana mura e prop del quadrato).
- **Mappa:** `src/expedition/mountain.odin`: presente solo nella Neve 192×192; `apply_relief` la tratta come una
  zona piana, `generate` la alza dopo il rilievo e prima delle strutture, e `add_mountain_inhabitants` mette la
  pattuglia e la reliquia dopo le altre pattuglie (il flusso casuale dei contenuti arriva dopo, quindi le altre
  mappe non cambiano).
- **Terreno:** `game.expedition_terrain` (Neve) dà `.Plain` o `.Ice` nel quadrato della montagna.
- **Disegno:** il pavimento ha due programmi (`plain` e `tall`): il secondo apre una finestra tonda, con un bordo
  luminoso, attorno al robot nelle terrazze più alte dei suoi piedi (uniform di `set_expedition_reveal`, solo
  il primo punto), ed è usato solo dove una terrazza di 16 gradini o più è in vista (un `discard` costa il test di
  profondità anticipato). I nemici dietro un rilievo non si disegnano (`terrain_hides_actor`). L'ologramma
  raggruppa le altezze oltre 12 a bande di sei.
- **Attenzione:** in Odin un `defer` che cambia un risultato con nome non cambia il valore restituito.
- **Laboratorio:** `Mechanics_Lab_Arena.Mountain`, atto `mechanics_lab_mountain`, `ODIN_PP_LAB_ONLY=mountain`.

## Le caverne (Fase 5 del piano griglia, piano sotto dalla Fase 5 del piano profondità)

- **Piano dell'interno:** `src/level/cave.odin`: `cave_plan(seed)` dà 34×18 caselle con due o tre stanze, l'arrivo, il segreto
  e i punti dove aspettano i gruppi; `cave_plan_sized` una tavola più piccola, con due stanze (il Far West: 24×14,
  `expedition.cave_board`).
- **La grotta è un piano della mappa** (`src/expedition/cave.odin`): le stanze sono caselle del piano −1 (`CAVE_LAYER`) alla
  quota del terreno attorno, sotto un massiccio di roccia alto 14 gradini al bordo e fino a 18 dentro; un tunnel porta dalla
  prima stanza, attraverso l'anello di roccia, all'imbocco sul terreno aperto a ovest. Nella Neve la grotta della montagna
  è una stanza sola nel nucleo, con l'imbocco sul sentiero vicino a metà salita (`mountain_cave_room`). Niente dissolvenza e
  niente cambio di mappa: ci si entra camminando (`game.layer_step`), anche in sella e durante uno scontro.
- **Posti:** fissi per bioma (`cave_places`, generatore fisso), scelti prima dei rilievi (`plan_caves`), che tengono piano il
  terreno attorno a ogni massiccio (`cave_level_zones` in `apply_relief`); poi `place_caves` scava le grotte e mette un sito
  `Cave` all'imbocco per ognuna. La run sceglie quali 1–3 hanno nemici e segreto (`Cave.inhabited`); la montagna sempre.
- **Dove sta il giocatore:** `World.in_cave` (0 fuori, k+1 nella grotta k) si ricava a ogni `tick` dalla posizione
  (`cave_at`, `update_caves`), che segna anche le grotte visitate e saccheggiate. `cave_rock` dice se una casella della
  terra è roccia di un massiccio (la corsia dell'Inferno non la spacca; il disegno la fa di roccia nuda). Sotto la roccia il
  terreno del bioma non c'è (`game.expedition_terrain` dà `.Plain` fuori dalla terra). `in_scope` e `visible_sites` restano
  per compatibilità e dicono sempre «tutti».
- **Salvataggio:** i piani fuori dalla terra sono una lista di caselle (`Snapshot.layer_cells`, 29 bit ciascuna) e di pozze
  (`layer_pools`); `layers_version` vale `SNAPSHOT_LAYERS`: un salvataggio di prima non ce l'ha ed è rifiutato senza
  conversione (scelta dell'utente); il campo segna `Invalid_State` nello slot.
- **Esplorazione e pattuglie:** `roam_layer_cell` e `walk` passano dai piani come il passo; `patrol_move_toward` ha il campo
  delle distanze su tutti i piani (finestra di 65×65 per piano, in memoria temporanea).
- **Disegno:** `render/expedition_layers.odin` disegna le stanze con il programma del pavimento (`floorLayer` 1): pavimenti,
  pareti di roccia sfaccettate, il taglio della roccia alla quota del soffitto; `expedition_terrain.odin` apre la parete
  del massiccio sopra l'imbocco (`terrain_opening`). In grotta il programma «tall» dirada con un retino la terra sopra gli
  occhi del robot entro 6 caselle (`coverPoint`, la regola della Fase 4), la scurisce tutta (`dimBox`) e toglie al cielo il
  65% della luce delle stanze (`skyShade`); la lampada del robot è più forte e i nemici svegli hanno una luce. I nemici che
  dormono hanno un'entità loro (`expedition_member_entity`) per stare sul pavimento del loro piano. L'arco di luce
  sull'imbocco è `render/expedition_cave.odin`. L'ologramma, in grotta, toglie la roccia del suo massiccio e mostra le stanze,
  e segna gli imbocchi scoperti.
- **Smoke:** gli stage dall'87 entrano ed escono camminando nei quattro biomi (`ODIN_PP_SMOKE_ONLY=caves`); lo stage 103
  fotografa l'ologramma nella grotta della montagna.

## Strutture posate dal giocatore (Fase 7 del piano griglia)

- **Kit:** `campaign.Item_Kind.Structure_Kit` (variante = `level.Structure_Id`); `campaign.spend_structure_kit` lo spende alla posa;
  `campaignui` lo usa con **POSA** (`Output.place_structure`, non lo spende).
- **Regole:** `expedition/player_structures.odin`: `check_player_structure` / `place_player_structure` (limite, portata, nessun attore sopra,
  poi `level.place_check` con `structure_keep_clear`); `sync_structures` tiene la lista del mondo uguale a quella della mappa.
- **Salute:** `Placed_Structure.health`, `level.structure_max_health`, `damage_structure`, `remove_structure`; `game.strike_structures`
  è chiamata da `resolve_enemy_blow`.
- **Scena:** `expedition_begin_placement` / `expedition_placing_update`; il fantasma è `render.set_structure_ghost` (`expedition_ghost.odin`).

## Limiti dichiarati

- **Renderer:** i riflessi planari comprendono architettura e neon; carta e
  dispositivi posati dalle carte vengono composti dopo il tone mapping.
  Le luci non proiettano ombre dinamiche. La selezione mantiene fino a 32
  sorgenti vicine, riservando spazio al robot e agli effetti mobili.
  I due benchmark finali senza limite fps sull'Apple M1 a 2560×1440 misurano
  81–82 fps medi nell'esplorazione Cyber, circa 71 nello scontro fermo,
  70 nella corsa e 68 nell'avvicinamento. City resta intorno a 59–60 fps medi
  e persistono frame oltre 16,7 ms in alcune scene.
  **L'obiettivo di 60 fps costanti ovunque non è ancora raggiunto**.
  La verifica nativa grafica dell'ultima rifinitura è completata; i risultati
  valgono per quella macchina e sessione, non sono una garanzia per altri
  dispositivi. Risoluzione nativa, bloom e riflessi restano attivi.
- **Bilanciamento:** costi, esperienza, densità degli incontri e ricompense
  seguono i valori provvisori della direzione. I test verificano le regole;
  non sostituiscono le partite di bilanciamento con persone.
- **Arte dei boss e dei nemici:** silhouette, nomi, tinte e attacchi dei
  biomi sono distinti e i 72 abiti/accessori sono procedurali; le
  animazioni e i rig riusano quelli degli archetipi
  esistenti. Non ci sono dodici nuovi set completi di animazioni dei boss.
- **Oggetti dell'inventario:** le icone delle forme sono procedurali;
  non ogni oggetto ha un'illustrazione dedicata.
- **Riferimento grafico:** le catture dei biomi del 22 ottobre (stile a
  inchiostro) sono il riferimento; colori di pavimento, fili e spigoli sono
  stati misurati su quelle immagini. I cortili dei POI, aggiunti dopo,
  sono ridisegnati nello stesso stile; la posizione degli ostacoli sparsi
  è ricostruita, non copiata cella per cella dalle catture.
- **Audio delle carte:** si riusano gli effetti già prodotti per il gioco.
  Karaoke dispone del proprio accompagnamento sintetico a 112 BPM.
- **Scelte ancora aperte nel documento:** nomi definitivi e carte di casa
  delle Montagne innevate restano scelte creative da confermare.
- **Modalità precedente:** `--run` resta disponibile per confronto e
  compatibilità; non è stata eliminata.
