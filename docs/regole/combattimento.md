[← Odin PP](../../README.md)

## Controlli e loop di gioco

Prima del primo combattimento si sceglie una reliquia fra tre offerte, oppure
si usa Skip. Ogni stanza parte con cinque carte e tre energia. I nemici
annunciano già il piano per la prossima risposta: schivare o spostare un
bersaglio può invalidarlo, senza permettere all'IA di cambiarlo all'ultimo momento.

Il combattimento usa una finestra temporale, seguita da un secondo di recupero
con movimento libero. Le azioni consumano tempo; i nemici agiscono sui propri
ritmi, indipendenti dalle azioni del player. Le carte spendono il proprio tempo
durante il cast, con mondo fermo; i dadi sospendono anche il timer. I QTE possono
sospendere un attacco prima del danno. I comandi rifiutati non aggiungono costi.
Una pressione durante l'azione del player viene scartata: agisce una nuova
pressione dopo il suo completamento. L'energia si rigenera di uno ogni tre
secondi del mondo, fino al massimo di tre.

Alla morte dell'ultimo nemico la stanza passa a Loot. Ci si può muovere senza
pulse, raccogliere i drop rimasti ed entrare sull'uscita verde. Una stanza non
finale offre tre carte: scelta o Skip aprono la mappa. Un Elite offre prima una
reliquia. Shop, Rest, Event e Treasure hanno schermate dedicate; il boss porta
a Victory, la morte del player a Defeat.

| Contesto / input | Azione |
|---|---|
| hover su carta | mostra regole, costo e range |
| trascina carta sulla griglia | anteprima di area, percorso, landing e blocker; il rilascio prova la giocata |
| `1`–`8` in Combat | gioca una carta non spaziale o seleziona una carta spaziale (nella mano da dieci della Prova meccaniche anche `9` e `0`) |
| click su cella | conferma il bersaglio della carta selezionata |
| `Esc` / click destro | annulla selezione o drag |
| `WASD` | un passo per pressione; contro un nemico esegue un bump attack senza muovere il player |
| `Spazio` | attesa: costo di 1 secondo |
| `F` / Refocus | riordina la mano e richiede il refill; costo di 2 secondi |
| `V` con `--debug-abilities` | Afterimage; `C` resta assegnato alla diagonale |
| rotella / `R` nell’ologramma | zoom locale / ricentra l’ologramma |
| `M` fuori Combat | mostra o nasconde la rotta, a timeline idle |
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
| clic su **MOSTRA EFFETTO** / `I` in Reward, Shop o Rest | apre il film della carta ([Mostra effetto](../presentazione.md#mostra-effetto)): sotto una carta offerta quella, al livello 0; nella riga dei comandi di Shop e Rest la carta posseduta scelta / la ricompensa o l'offerta sotto il mouse, altrimenti la carta scelta |
| `Esc`, clic destro o **CHIUDI** / `R` o **RICOMINCIA**, nella finestra Mostra effetto | la chiude, senza clic che arrivino alla run / fa ripartire il film dal primo fotogramma |
| `L` / Leave | risolve un nodo speciale senza ricompensa |
| `Enter` / Continue dopo il risultato | completa il nodo speciale e torna alla mappa |
| `Enter` / Restart in Defeat | avvia una nuova run |
| `F5` | nuova run o laboratorio, con seed diverso |
| `F8` | salva uno snapshot diagnostico locale `odin_pp_input_N.txt`, senza cambiare lo stato |
| `F1`, `F2`, `F3` | scaling fit con letterbox, integer, stretch |
| `F4` | cambia velocità delle animazioni ordinarie: 1x, 2x, 4x; cast e dadi M8 restano a 1x |
| `F11` | fullscreen borderless |
| `F9` | diagnostica dell'host: FPS, grafico dei frame, stack delle scene |
| `F10` | torna al menu (run avviata dal menu) |

Per spostare un barile serve **Shove in mano, un'energia e adiacenza
ortogonale**. Trascinare la carta sul corpo del barile oppure selezionarla e
cliccare: la spinta va di una cella lontano dal player. Camminargli contro in
Combat non lo spinge. Shove accende un barile spento anche se la spinta è
bloccata; la scadenza è al terzo beat del mondo successivo all’innesco; durante il cast la miccia resta ferma.

## M8: versione 0.4

M8 introduce cast con controllo esplicito del tempo, carte-dispositivo,
equipaggiamento e il primo minigioco completo. `./run.sh` avvia questa versione;
`--m7`, `--m8` e `--m9` restano alias dello stesso gioco tattico 3D.
La modalità classica e la vista `--flat` sono state ritirate. Lo starter tattico include ora una Shock Floor e una Tesla Coil,
oltre alle carte già presenti: i nuovi dispositivi possono comparire anche
fra ricompense e offerte. Include anche il **6** e il **7 di denari**, carte con
la grafica della Scopa: costano 1, danno 6 e 7 oro e si esauriscono per il resto
del combattimento; non compaiono fra ricompense e offerte. Infine una copia di
**[Movimento Ombra](meccaniche.md#movimento-ombra)**, che invece si trova anche fra
ricompense e offerte delle run tattiche.

### Tre regole del tempo

| Stato | Countdown del pulse | Nemici, bombe, status e dispositivi |
|---|---|---|
| Decisione, movimento, targeting, ologramma | scorre; le azioni non-carta durano il tempo indicato | avanzano sui beat del mondo |
| Cast di una carta da `Ns` | scorre per la durata effettiva del cast, senza doppio addebito | fermi, compresa la presentazione nemica già in corso |
| Dadi / cinematica, pausa, scheda personaggio o attività M9 | fermo | fermi |
| [Movimento Ombra](meccaniche.md#movimento-ombra) | fermo; scorrono solo i 4 s dell'ombra | fermi, comprese le loro animazioni |
| Finestra [Mostra effetto](../presentazione.md#mostra-effetto) aperta | fermo | fermi, con le loro animazioni: la run non riceve il fotogramma, che è tutto del film e della sua stanza di prova |

Il cast occupa i comandi del player per la durata indicata sulla carta. Un
lancio di dadi all'interno della carta è una pausa completa aggiuntiva: non
riduce il pulse e non fa scadere il cast. `F4` e `--fast` non abbreviano né il
cast né questa cinematica. Alla ripresa non si scaricano beat accumulati durante
la pausa. QTE e perdita del focus mantengono le rispettive pause già esistenti.
La fog senza memoria e l'ologramma che consuma tempo restano attivi.

La policy riutilizzabile `Live / Cast / Cinematic` è in
[cast_playback.odin](../../src/render/cast_playback.odin): nuovi tipi di ruota o reveal
potranno dichiararsi cinematici nello stesso punto. Attualmente sono integrati
i dadi dal D4 al D20; non è ancora presente una carta con ruota. La risoluzione logica
resta una sola transazione deterministica, seguita dalla presentazione; il
renderer non tira nuovamente i dadi e non riapplica effetti.

### Colpo a tempo

Ogni volta che il countdown del pulse scocca un secondo intero (per esempio da
4,35 a 4), un'azione fatta **entro 0,15 s** da quell'istante, prima o dopo, è
**critica**. Ogni scocco premia una sola azione; i secondi saltati dal costo di
un'azione non scoccano, e la finestra appena aperta non conta come scocco.
Lo scocco si giudica alla pressione: un passo premuto in tempo resta critico
anche se parte qualche fotogramma dopo, mentre aspetta (al massimo 0,06 s) il
secondo tasto della diagonale. Non c'è coda: premuto mentre l'azione precedente
è ancora in corso, il passo si perde. L'HUD mostra una spia che si accende
nella finestra; l'azione critica mostra **CRITICO!**. Un passo in linea retta
resta sempre di una casella e non consuma lo scocco: sul secondo, il critico
del movimento è solo il passo in diagonale.

| Azione sul secondo | Effetto critico |
|---|---|
| Due tasti insieme (`W`+`D`, `S`+`A`...) | passo in diagonale (solo sul secondo) |
| Attacco a urto | danno doppio |
| Carta: danni | x1,5, almeno +2 |
| Carta: scudo, cura, oro | x1,5, almeno +1 |
| Carta: altri status | +1 potenza e +1 durata (Veleno, Bruciatura, Rallentamento e le cariche del Viandante: +1 stack, non hanno durata; Lama Velenosa: il dado più uno) |
| Carta: pesca, energia, carte create, reazioni | +1 (anche il primo colpo del Lazzo e il valore del Pinball, quello da cui parte e a cui lo riportano i muri) |
| Carta-dispositivo | danno x1,5 (almeno +2); la Tesla nasce con vita doppia, la Shock Floor con un colpo in più (massimo 21: un 20 del D20 più uno) |
| First Person Shooter | +2 s dietro gli occhi |
| Movimento Ombra, Dado del Destino | nessun critico: giocate sul secondo lasciano lo scocco all'azione dopo |
| Canna da Pesca | mai critica: pesca a stanza liberata, senza finestra |
| Freccia di Feretro | mai critica: non prende lo scocco |

Le regole e i numeri sono in [tactical_beat.odin](../../src/game/tactical_beat.odin).

## Modalità tattica M7

La demo avvia **M8 / 0.4**, costruita sul loop M7: scena 3D con sprite 2D,
fog locale, timer, recupero mobile di un secondo e QTE. Le regole qui sotto
sono aggiornate al cast M8; le note cronologiche M7 sono nella roadmap.
Il runtime offre un solo gioco principale, con questo catalogo e queste regole.
`--classic`, `--flat` e gli smoke dedicati alla vecchia versione vengono
rifiutati con un messaggio esplicito. La proiezione ortografica 3D resta disponibile.

```sh
odin run src -o:none
odin run src -o:none -- --decision-time=15 --vision=2
odin run src -o:none -- --vision=9
odin run src -o:none -- --orthographic
odin run src -o:none -- --no-fog
```

| Opzione | Valore / funzione |
|---|---|
| `--decision-time=20` | budget iniziale in secondi, default 20; ammessi 1–60 |
| `--vision=7` | lato della vista locale; default 7×7 (raggio 3), ammessi 2, 3, 5, 7 e 9 |
| `--no-fog` | vista completa per confronto e diagnostica |
| `--qte-time=1.2` | finestra QTE in secondi, default 1.2; ammessi 0.2–5 |
| `--perspective` / `--orthographic` | prospettiva 3D predefinita oppure proiezione ortografica |
| `--m7` / `--m8` / `--m9` | alias compatibili dello stesso gioco tattico 3D |
| `--smoke-m7` | simulazione tattica e stress headless riproducibili, senza aprire finestre |
| `--smoke-m7-view` | prova grafica di scena, oggetti 3D, fog, ologramma, QTE e menu |
| `--smoke-m8-view` | prova 3D di d4, dispositivi, offerta del ring, equipaggiamento, scheda personaggio, tag match e cambio stanza |
| `--smoke-western` | nuvoletta 6 RANCH 7: apertura automatica, volo delle carte, insegna, porte, corsa a tempo e premio |
| `--smoke-mechanics-lab` | Prova meccaniche in 3D: mano e testi, status, intenti, colpi, ombra, pozze, incendio, cariche, Lazzo, Pinball, FPS e pesca; replay e screenshot `odin_pp_mechanics_lab_*.png` / `odin_pp_living_*.png` |
| `--smoke-effect-window` | Mostra effetto: ingressi da ogni menu, isolamento della run, chiusura senza click-through, testi, film delle carte e tempi dei frame. `-define:EFFECT_SMOKE_CARDS=,Strike,Pinball,` limita le carte filmate. Screenshot `odin_pp_effect_*.png` |
| `--smoke-m9-view` | arena continua, duello con IA, presa in quattro pose, replay e FPS con ricarica e vittoria |

Anche i laboratori `--spell-lab` / `--dice-lab` usano ora il catalogo unico,
il cast e la scena 3D; mostrano la stanza intera per facilitare le prove.
Gli sprite esterni continuano a usare `--sprites`: nella scena 3D M7 sono
riservati ai personaggi; ghiaccio, barili, bombe e fuoco sono mesh a blocchi.
Le miniature dell'ologramma sono mesh procedurali separate dagli sprite degli attori.

HUD e carte conservano avorio, nero e cremisi, pergamena e cornici a gradini.
L'ambiente usa invece nero, grigio e blu: pareti scure, blocchi smussati,
grana fine e riflessi lucidi che cambiano con la camera. Nessun fondale o
torre decorativa circonda la stanza: il livello emerge da un vuoto nero uniforme.
Le carte usano il nuovo atlante `card-icons-pixel.png`, con sagome semplificate
e pixel più grossi. Reliquie, ricompense, mercante, riposo, eventi, tesori,
mappa della rotta e schermate terminali condividono font, palette e cornici.
Il font pixel **Jersey 10** è incorporato nel binario insieme agli atlanti:
non servono download o una directory di avvio particolare. Texture e canvas
M7 usano il filtro nearest; `F2` sceglie lo scaling intero per pixel uniformi,
mentre `F1` adatta la scena alla finestra. Licenza e provenienza del font sono
in [assets/fonts](../../assets/fonts/README.md); i prompt delle illustrazioni sono
in [assets/gothic/generation-prompts.md](../../assets/gothic/generation-prompts.md).
La mappa ha una griglia cremisi, miniature 3D illuminate e una legenda con
player, melee, ranged, miniboss, boss e uscita.

La revisione della scena usa il renderer OpenGL 3D di Raylib: pavimenti a volume,
muri con altezze e cornici, illuminazione direzionale e locale, profondità reale
e sprite billboard 2D per i soli personaggi. Oggetti, coperture, trappole,
portali sono costruiti da blocchi 3D; gli oggetti si selezionano sul
loro volume anche dopo una rotazione. La parallasse deriva dalla camera
prospettica e dalle geometrie. I muri in primo piano si abbassano per lasciare leggibile il player.
Durante Combat la fog non memorizza celle visitate e nasconde anche ciò che si trova dietro
muri/ostacoli; solo l’ologramma mostra l’intera stanza. La base scura fuori dalla
vista è composta da blocchi opachi di nebbia, identici per qualsiasi terreno
nascosto: non rivela altezze dei muri, oggetti o celle esplorate in precedenza.
Minacce e aree di esplosione sono disegnate sul pavimento 3D visibile;
le bombe mostrano i pulse rimasti prima della detonazione.

Alla fine del fight, dopo la scomparsa dell'ultimo nemico nella timeline, la
fog si apre sulla stanza e la luce fredda aumenta con una transizione di
1,2 secondi. Loot e portale ricevono marcatori discreti; in BOTTINO l'HUD
mostra movimento libero, senza countdown. Il nuovo Combat ripristina subito
la luce e la visibilità locale, anche riutilizzando renderer e Room. La
transizione usa il tempo della presentazione e non modifica pulse, timer,
RNG o regole dell'ologramma. I blocchi hanno ombre di contatto corte sul
pavimento, senza una shadow map aggiuntiva.

La vita di ogni nemico è un cartellino sopra la testa con cuore, vita e piccolo
simbolo dell'intento; le minacce restano indicate sul terreno ([Il tavolo](../presentazione.md#il-tavolo-cartoncini-vivi-cerchi-e-segnalini)); cartellini,
micce, annunci delle bombe e segnalini usano lo stesso posizionamento
per evitare sovrapposizioni fra testi.
Gli indicatori degli status mantengono la propria zona sul terreno. Bruciatura
e Rallentamento sono etichette di carta in pixel art sotto i piedi, ritagliate e
inchiostrate come i cuori (una fiamma, una clessidra e i loro stack), in fila
sotto i dischi degli status più vecchi; con i cuori raddoppiano il pixel quando
la camera è vicina. Le etichette restano dentro la zona della scena e usano un
collegamento sottile quando devono spostarsi. L'HUD tiene gli status separati
dai contatori; l'ispettore del nemico ne elenca nomi e stack (o potenza e secondi).

Le prime due profondità della rotta restano compatte: Combat **17×11**, quattro
nemici e spazio sicuro centrale. Dal terzo livello superficie, coperture e
composizione crescono a fasce: fino a **41×29 / 16 nemici** nei Combat avanzati
e **45×31 / 22 nemici** per il boss finale. La crescita segue la profondità della
rotta, anche passando dai nodi speciali. Le statistiche individuali conservano
le curve precedenti; cambiano numero, varietà e distribuzione delle squadre.
Vedi [progressione delle arene](progressione.md#progressione-delle-arene-tattiche) per la tabella.

La camera segue il player senza allontanarlo nelle stanze grandi; la mappa
olografica inquadra invece tutta la superficie al reset. Lo zoom manuale resta
libero. Il renderer scarta solo geometria sicuramente fuori schermo, senza
alterare fog, luce, minacce o picking; la fog continua a non memorizzare celle.

La mano M7 è una fila senza sovrapposizioni: fino a otto carte completamente
visibili, con energia richiesta, bersaglio/raggio, effetto, durata del cast in
secondi e stato di disponibilità. Hover e selezione aprono un pannello di
dettaglio, con il tasto `I` e, a carta scelta, il pulsante **MOSTRA EFFETTO**
([Mostra effetto](../presentazione.md#mostra-effetto)); con sette–otto carte il titolo e
l'illustrazione adottano un layout compatto; eventuali testi troppo lunghi
terminano con puntini e restano nel dettaglio. Nel gioco la mano non supera mai otto carte (`MAX_HAND_CARDS`); solo
regole che ne danno di più tutte insieme, come le dieci della Prova meccaniche,
le tengono, e allora le carte si sovrappongono su tutta la larghezza del canvas,
a 8 pixel dai bordi: restano larghe come in una mano piena di otto e ognuna
resta in vista quanto serve perché la successiva copra solo carta: ogni parola
della sua faccia (nome, righe, raggio), costo, tempo, l'icona intera (spostata
nella parte in vista), i segni della rarità (sotto il tempo) e il tasto,
misurati con il font del gioco a ogni fotogramma; lo spazio che avanza si divide
fra tutte e l'ultima resta intera. Quella sotto il mouse, o altrimenti la carta
mirata o scelta, si alza di 8 pixel e si disegna intera sopra le altre, e il
puntatore la trova nella sua striscia anche mentre si alza
([tactical_hand.odin](../../src/render/tactical_hand.odin)); `9` e `0` giocano la nona
e la decima, mentre i menu restano su `1`–`8`. Le carte le cui righe lì si
rimpicciolirebbero o si taglierebbero ne hanno una forma corta (Shock Floor,
Tesla Coil, Movimento Ombra con `OMBRA 4s` / `MONDO FERMO`, Pozza di Veleno,
Incendio, Deflect, Feretro, Dado del Destino, Lama Velenosa, Lazzo, Pinball e
First Person Shooter) e quelle il cui nome lì si taglierebbe un nome corto
(`Ombra`, `Pozza`, `Dado`, `Lama`, `FPS`; l'ispettore tiene il nome intero), che
dicono anche sulle carte più larghe (mani da cinque o sei, negozio, ricompense)
dove il nome intero, con il suo `+n`, non ci starebbe così com'è alla sua
misura: First Person Shooter è `FPS` su ogni carta della mano e dei menu,
`Movimento Ombra` diventa `Ombra` dove si stringerebbe: la Prova meccaniche
tiene in mano dieci carte, tutto il suo mazzo tranne la Canna da Pesca, che non
viene mai in mano (anche lei ha la sua forma corta, `Canna`, per uno slot più
stretto su un canvas più piccolo). Le sue carte sono larghe 109 pixel sul canvas
di 960, e il suo smoke misura con il font del gioco ogni parola di ogni carta
del mazzo a ogni livello che può raggiungere, sulla carta della mano (la Canna
sul suo slot) e nell'ispettore: ogni riga ci sta così com'è, senza stringere le
lettere (stretto, il font di pixel le attacca: `CTRL+CLIC` si leggerebbe
`CTRL+CUC`), rimpicciolirsi o tagliarsi, e nessun nome si taglia (solo con il
`+n` di un upgrade può stringersi o scendere di una misura); controlla anche che
di ognuna delle dieci carte si vedano tutte le parole, l'icona e il tasto prima
della successiva, nella mano come la dà e in qualunque ordine possa prendere,
che il puntatore trovi ognuna e che quella alzata resti dentro il canvas;
Pinball e First Person Shooter li misura anche sulle carte più larghe del gioco.
Le carte difensive indicano anche i QTE che abilitano. Le carte restano nella
loro posizione durante la selezione. Il catalogo tattico ora distingue mobilità
protetta, interruzione, ricognizione e contrattacco; rarità, lifetime e regole
di costruzione del mazzo restano condivisi. Il bilanciamento numerico è una
prima proposta giocabile, ancora da provare in run.

I nemici hanno queste cadenze e regole:

- **Bombaroli:** preparazione di 5 secondi, poi rilascio dopo 1 secondo sulla cella annunciata,
  senza inseguire il nuovo bersaglio. Una sola bomba nemica attiva o in preparazione
  nella stanza, miccia di **3 secondi**, **3 danni** e almeno **2 secondi di recupero**.
  I nemici rinviano il lancio anche se è già presente una bomba del player.
  Spostare il lanciatore dopo l'annuncio fa fallire il lancio. Le bombe del
  player conservano miccia di 2 secondi e 4 danni; non subiscono questa riduzione.
- **Inseguitori:** il percorso tiene conto di fuoco, trappole e zone di esplosione;
  i pericoli hanno un costo, non diventano muri invalicabili. Dopo ogni attacco,
  anche mancato, recuperano per un secondo. La cadenza normale è di 3 secondi.
- **Arcieri:** cercano una linea di tiro libera a distanza 2–5, arretrando
  quando necessario. **4 secondi per mirare/muovere**, rilascio sulla cella fissata dopo 1 secondo, poi recupero 1 secondo.
  La mira non infligge danno e non apre QTE; durante il tiro si possono usare le
  normali difese. Spostarli o stordirli interrompe il tiro. Da adiacenti e senza
  vie di fuga possono colpire per un solo danno.
- **Bruti:** cadenza di 5 secondi; il fendente adiacente copre tre celle frontali; recupero 1 dopo
  il fendente e 2 dopo la carica, anche mancata. Colpi e cariche possono
  spingere di una cella, attivando i pericoli
  della destinazione. Uno scudo che assorbe tutto il danno impedisce la spinta;
  le cariche ammettono le difese QTE abilitate da carte e condizioni.
- **Custodi:** agiscono ogni 4 secondi, proteggono gli altri archetipi con 2 Shield per 2 secondi,
  poi recuperano per 2 secondi. Non possono creare catene di protezione fra custodi.
  Spostarli, spezzare la linea di vista o stordirli annulla la protezione annunciata.
- **Boss:** cadenza normale di 5 secondi; conserva fasi, cariche e bombe, ma recupera almeno 1 secondo dopo
  un attacco e almeno 2 dopo carica/lancio. Può essere interrotto con Heavy Blow.
  Il Demolitionist può accendere un barile che minaccia il player, oltre a
  caricare e bombardare; il bersaglio annunciato non viene sostituito se spostato.

Gli avvisi sul pavimento sono leggibili anche quando il lanciatore è fuori
vista: segnalano l'impatto nella zona visibile senza scoprire il nemico.
Mira, preparazione, lancio, recupero, fendente, carica e protezione hanno
piccoli pittogrammi distinti nel cartellino della vita e colori sul terreno. L’hover su un nemico
visibile ne scrive l'intento con i secondi rimasti (`MUOVE / 2.8s`), il ruolo e
come rispondere.
Lo stordimento nasconde le minacce dell’intento interrotto, ma non disinnesca
esplosivi già presenti. Questi valori sono un primo bilanciamento da provare durante le run,
anche mentre il player si muove durante il recupero.

Il rework carte M7 usa lo stesso catalogo effettivo per costo, targeting, effetti,
mano, mercante, ricompense, upgrade e timeline. Il costo energetico resta distinto
dal **costo temporale**, centralizzato in `game/tactical_action_cost.odin`:

| Azione | Costo temporale / durata del cast |
|---|---:|
| Passo ordinario e diagonale eseguita sul battito | 0,8 s |
| Attacco base, attesa, schivata attiva, tentativo QTE diagonale, freccia di Feretro | 1 s |
| Refocus | 2 s |
| Clic su **ATTIVA** o **EQUIPAGGIA** in Combat | 1 s |
| Supporto, Guard, Afterimage, Battle Focus, Spark, Pozza di Veleno, Deflect, Feretro, Dado del Destino, Lama Velenosa | 1 s |
| Strike, Arc Bolt, Shove, Dash, Grappling Hook, Venom Needle, Fate Strike, Tesla Coil, Incendio, Lazzo (il lancio; il giro sta sul tempo del mondo), Pinball (il colpo; la corsa sta sul tempo del mondo) | 2 s |
| Piercing Ray, Cross Slash, Heavy Blow, Sundering Blow, Twin Venom, Shock Floor, Titan Grip | 3 s |
| Firebomb, Toxic Wave, Caustic Bloom, Chain Lightning, Prismatic Barrage, Storm Crown | 4 s |
| [Movimento Ombra](meccaniche.md#movimento-ombra) | 0 s: i suoi 4 s reali stanno fuori dalla finestra |
| [Canna da Pesca](meccaniche.md#canna-da-pesca) | 0 s: pesca a stanza liberata, dove non c'è finestra |
| [First Person Shooter](meccaniche.md#first-person-shooter) | 0 s: i suoi 20 s sono del mondo e i colpi dell'AK non costano tempo |

Le carte mostrano la durata `Ns`: il cast spende quei secondi una sola volta,
progressivamente, e ferma il mondo. Movimento Ombra mostra `0s`: non ha cast, la
carta di rimpiazzo arriva subito e la finestra resta ferma per tutta l'ombra.
Le altre azioni durano il tempo indicato, durante il quale finestra e mondo
continuano ad avanzare; non sottraggono lo stesso costo una seconda volta. Anche Spark a energia zero costa tempo.
La schivata base rimane accessibile fuori recupero, senza richiedere carte.

| Carta M7 | Energia | Effetto base / ruolo |
|---|---:|---|
| Strike | 1 | 3 danni; **+2** contro un nemico in recupero o stordito |
| Arc Bolt | 1 | 2 danni, tiro economico |
| Piercing Ray / Cross Slash | 2 | 3 danni in linea / a croce, nelle celle visibili |
| Guard | 1 | 4 Shield per 2 secondi; abilita Block e Parry |
| Thorn Coat | 1 | 2 Thorns per 3 secondi; abilita la deviazione (QTE `L`) contro gli arcieri |
| Counter Rune | 1 | contrattacco 3, 2 cariche, 4 secondi; Retain |
| Battle Focus | 1 | pesca fino a 2 carte; Survey per 3 secondi: lato della vista +2 (da 2×2 passa a 5×5), massimo 9; Exhaust / Ethereal |
| Spark Forge | 1 | crea fino a 2 Spark temporanee a costo 0 |
| Dash | 1 | 2 Shield **prima** di muovere, durata 2 secondi; movimento fino a 4 celle, senza usare il recupero della schivata |
| Shove | 1 | prima spinge di 1 cella, poi infligge 1 danno; allontana bombe e interrompe intenti tramite spostamento |
| Grappling Hook | 1 | 1 danno e trascina adiacente, raggio 2–4; interrompe gli intenti spostando il nemico |
| Heavy Blow | 2 | 4 danni e Stagger: salta l’azione annunciata e apre almeno 1 secondo di recupero dopo il pagamento del costo temporale |
| Venom Needle | 1 | 1 danno + 2 Veleno (danno a ogni azione del bersaglio, poi uno stack in meno) |
| Purifying Guard | 1 | 3 Shield per 2 secondi e rimuove il Veleno |
| Volatile Study | 2 | crea 1 Spark, pesca fino a 2 carte; Exhaust |
| Toxic Wave | 2 | 1 Veleno ai nemici visibili entro raggio Chebyshev 2 (5×5) |
| Movimento Ombra | 3 | 4 secondi reali nell'ombra: mondo e finestra fermi, intangibile, solo passi dell'ombra da 0,4 s (diagonale sui suoi battiti); risale sull'ultima casella dell'ombra. 0 s di finestra, giocabile anche da storditi |
| Pozza di Veleno | 1 | una pozza su una cella libera fino alla fine della stanza: 2 Veleno (+1 per upgrade) a un nemico per ogni sua cella in cui entra; le aree che chiude si riempiono ([Pozza di Veleno e Incendio](meccaniche.md#pozza-di-veleno-e-incendio)) |
| Incendio | 2 | un fuoco su una cella libera: 1 Bruciatura (+1 per upgrade) a ogni ingresso e a chi prende fuoco; cresce a croce di una casella a ogni nuova finestra e si spegne alla quinta |
| Deflect | 1 | una carica di RIFLESSO: il prossimo colpo nemico sul Viandante torna all'attaccante, senza scelta di difesa ([Deflect, Feretro, Dado del Destino e Lama Velenosa](meccaniche.md#deflect-feretro-dado-del-destino-e-lama-velenosa)) |
| Feretro | 2 | 3 frecce (+1 per upgrade): `Ctrl` + clic su un nemico in linea di tiro, 1 danno + Veleno 2, Bruciatura 1 o Rallentamento 1; 1 s a freccia |
| Dado del Destino | 2 | i prossimi 3 urti tirano il dado del suo livello: 1-3 status, 4 ruba vita, 5 critico, 6+ letale (boss e miniboss: critico) |
| Lama Velenosa | 1 | tira il suo dado: tanti urti con 2 Veleno |
| Lazzo | 2 | un nemico entro 4 celle, boss e miniboss inclusi, gira intorno al Viandante fino alla morte: sul perimetro colpi 1, 2, 3... e spinta, dentro il raggio solo spinta, -1 vita a ogni giro; schivare lo lascia andare ([Lazzo](meccaniche.md#lazzo)) |
| Canna da Pesca | 0 | mai in mano: a stanza liberata pesca da un suo slot una casella libera entro 3 celle, che diventa acqua; 95% cibo che cura un d4, 5% una carta nel mazzo; 1 pesca a stanza +1 per upgrade (fino a 6); una sola per run ([Canna da Pesca](meccaniche.md#canna-da-pesca)) |
| Pinball | 3 | un nemico accanto (non boss né miniboss) diventa una palla d'acciaio che rimbalza per 20 s del mondo a 7 caselle al secondo: i nemici che tocca prendono 2, 3, 4... (+1 per upgrade) e sono spinti di una cella, ogni muro la riporta a 2; poi scoppia e il nemico cade ([Pinball](meccaniche.md#pinball)) |
| First Person Shooter | 3 | 20 s del mondo (+2 per upgrade) dietro gli occhi del Viandante: un AK di carta da 6 colpi al secondo, 1 danno lungo il mirino, passi secondo la vista, niente carte; 0 s di finestra ([First Person Shooter](meccaniche.md#first-person-shooter)) |

Afterimage mantiene il bypass del recupero della schivata e lo Shield dopo il
movimento. Calculated Risk, Spark, Firebomb, Caustic Bloom e le formule delle
cinque carte con dadi/catene conservano i valori del catalogo base. **Aree e
rimbalzi colpiscono solo celle/nemici visibili**: nessun bersaglio occultato viene
rivelato dalla preview. Survey rispetta muri e ostacoli; quando scade, la vista
si restringe senza memoria dell’esplorazione. Con `--no-fog` non modifica la vista.
Le durate degli status avanzano ogni secondo del mondo; Veleno, Bruciatura e
Rallentamento non hanno durata: il Veleno morde le azioni di chi lo porta, la
Bruciatura brucia a ogni nuova finestra, il Rallentamento allunga gli intenti
del nemico ([Status](#status)). Durante cast e dadi il mondo
è fermo: non scadono status, micce, recuperi o cooldown dei dispositivi. Le carte con
pescata/creazione rispettano capienza e disponibilità; non garantiscono sempre
il numero massimo di carte scritto. Upgrade e keyword mantengono le policy esistenti.

| Input M7 | Azione |
|---|---|
| Pulsante **MAPPA 3D [TAB]** / `Tab` | apre/chiude la schermata olografica; **il countdown continua** |
| Trascinamento sinistro sulla mappa / rotella | ruota e inclina l’ologramma / zoom; `R` o **RICENTRA** ripristina la vista, `Esc` chiude |
| Trascinamento col tasto centrale sulla scena / rotella | orbita la camera 3D / zoom; gli assi WASD restano quelli della griglia |
| Clic su una carta / trascinamento | seleziona e mostra i dettagli / gioca sul bersaglio; un secondo clic gioca le carte senza bersaglio |
| `1`–`8` / clic destro o `Esc` | seleziona una carta con bersaglio o gioca subito una carta senza bersaglio / annulla la selezione (nella mano da dieci della Prova meccaniche anche `9` e `0`) |
| `Ctrl` + clic sinistro su un nemico | con le frecce di Feretro: scocca una freccia al nemico segnato (visibile e in linea di tiro); con `Ctrl` premuto il tavolo segna quelli raggiungibili |
| `I` / clic su **MOSTRA EFFETTO** nell'ispettore della carta | apre il film della carta sotto il mouse o di quella scelta, anche della Canna nel suo slot ([Mostra effetto](../presentazione.md#mostra-effetto)); il pulsante compare a carta scelta, e pulsante e tasto tacciono mentre il tavolo è occupato |
| nella scheda **PERSONAGGIO**: clic su una riga del **MAZZO** / `<`, `>` / **MOSTRA EFFETTO** o `I` | sceglie la carta con il suo livello / gira pagina / apre il film della riga scelta; `Esc` chiude prima la finestra, poi la scheda |
| mouse / tasto sinistro tenuto, dietro gli occhi di [First Person Shooter](meccaniche.md#first-person-shooter) | gira la vista / spara l'AK, 6 colpi al secondo; `WASD` sono passi secondo la vista, `P` o `Esc` mettono in pausa e liberano il mouse |
| `P` | pausa esplicita, con scena coperta; `P` riprende |
| `Q`, `E`, `Z`, `C` | tenta rispettivamente diagonale nord-ovest, nord-est, sud-ovest, sud-est sulla griglia |
| `WASD` durante QTE diagonale | due pressioni nell'ordine indicato: prima asse orizzontale, poi verticale |
| `Shift + WASD` | schivata attiva di 1–2 celle in linea; costo 1 secondo, recupero 2 secondi, senza carta richiesta |
| `J` / `K` durante scelta difesa | parata / parry, disponibili con Shield |
| `L` durante scelta difesa | deviazione di una freccia, disponibile con Thorns |
| `E` durante scelta difesa | schivata reattiva di una cella; poi `WASD` sceglie la landing; disponibile senza carte quando pronta |
| `WASD` dopo scelta parata/parry/deviazione | premi il tasto richiesto entro la finestra residua |
| rotella | zoom della camera locale |
| `M` | mappa della rotta fuori Combat; in Combat si usa l'ologramma |

`C` è riservato alla diagonale; l’equipaggiamento si usa con il mouse. I comandi ordinari
sono sospesi durante cast, dadi, QTE, ologramma e pausa; dentro
[Movimento Ombra](meccaniche.md#movimento-ombra) `WASD` muove soltanto l'ombra e tutto il
resto tace. I movimenti e le animazioni dei
nemici non bloccano movimento, carte o targeting del player. Durante il recupero
rimane disponibile la camminata ordinaria; carte, attacchi, refocus, schivata
attiva e diagonali sono sospesi. Le difese QTE restano disponibili secondo le
loro condizioni.

Il **pulse del player è una finestra di 20 secondi**, configurabile da 1 a 60,
che può contenere più azioni. Il countdown scorre mentre si decide. Movimento,
attacco, attesa, refocus, attivazione ed equipaggiamento **durano in tempo reale
il loro costo** (`Tactical_Config.timed_actions`): un passo da 0,8 s occupa il
Viandante per otto decimi di secondo, mentre il countdown e i nemici scorrono come sempre (un
battito al secondo). Un comando premuto nel frattempo viene **scartato**, mai
tenuto da parte per dopo: agisce solo una pressione fatta a fine azione. La
schivata (`Shift + WASD`) invece non aspetta e interrompe subito l'azione, e la
fine della finestra chiude anche l'azione in corso. L'HUD mostra **AZIONE** con
una linea dorata che si consuma. Con le regole di base (`DEFAULT_TACTICAL_CONFIG`, usate
dalle sonde di regressione) il costo si sottrae invece subito. Una carta avvia
un cast di `Ns`: durante questi
secondi il countdown scende, il mondo resta fermo e il costo non viene sottratto
una seconda volta. Gli input rifiutati non pagano costi. Una carta iniziata con
tempo residuo positivo completa il proprio cast anche se il countdown arriva
prima a zero; il recupero parte dopo il cast.

Fuori dai cast il tempo reale alimenta il **clock del mondo**. Solo nelle
sonde con `DEFAULT_TACTICAL_CONFIG` lo alimentano anche i costi immediati.
Ogni secondo matura un beat: agiscono solo i nemici giunti alla propria scadenza,
poi avanzano status, micce, recuperi e dispositivi (ogni nemico che ha agito
riceve subito il morso del proprio Veleno). La Bruciatura morde invece sul
comando di scadenza della finestra, quando aumenta `Tactical_State.cycle`
(il numero della finestra, distinto da `Room.pulse_count`, che conta i beat). I cast non accumulano beat
arretrati da recuperare tutti insieme. Gli intenti restano fissati fino alla
scadenza. Energia: +1 ogni 3 secondi del mondo, entro il massimo. Il rimpiazzo
della carta si pesca al termine del cast se Combat continua (subito, per una
carta da 0 s); non serve un beat nemico aggiuntivo. La velocità delle animazioni
non altera questi contratti.

Solo allo zero dell'intera finestra parte un **recupero di 1 secondo di tempo
attivo**. Si può camminare senza costo temporale aggiuntivo: i passi non
accorciano né prolungano il recupero. Camminare verso un nemico non permette un
attacco; collisioni e hazard mantengono le regole normali. Nemici, bombe, status
ed energia continuano sul clock condiviso. Allo scadere, dopo aver risolto gli
eventuali beat/QTE pendenti, riparte la finestra successiva.

**La finestra si accorcia** (`Tactical_Config.shrinking_window`): ogni finestra
che arriva a zero lascia alla successiva un secondo in meno (20, 19, 18...).
Quando non resta più neanche un secondo il Viandante è **stordito**: niente
passi, attacchi, schivate o difese, solo carte, per 1 secondo la prima volta
nella stanza, 2 la seconda, 3 la terza e così via; poi la finestra torna intera.
Ogni **6 carte giocate** annullano il calo della scadenza successiva e danno un
secondo in più: a 18, invece di scendere a 17, si riparte da 19. La finestra non
supera mai i 20 secondi iniziali. L'HUD mostra `STORDITO` e, accanto ai nemici,
la lunghezza della finestra e le carte contate (`MAX 19s / CARTE 4/6`). Con le
regole di base ogni finestra resta intera.

All'ingresso di **ogni nuova stanza** ciclo, debito di tempo, recupero schivata,
lunghezza della finestra, carte contate e stordimenti si azzerano. Le statistiche cumulative della run rimangono. Un timeout chiude
la finestra una sola volta, dopo la risoluzione del tempo già pagato; il secondo
di recupero trascorre realmente, senza aggiungere una Wait o beat immediati.

Dadi, QTE, pausa, scheda personaggio, la finestra di
[Mostra effetto](../presentazione.md#mostra-effetto), attività M9 e perdita del focus sospendono il
countdown dell’arena; Movimento Ombra lo ferma per i suoi 4 secondi. Cast,
movimento, animazioni nemiche, hover, targeting e
ologramma consumano tempo; durante il cast sono sospesi mondo e input ordinari.
Consultare la mappa
lascia avanzare anche i nemici, senza reset. Un input sullo stesso frame di un
beat viene eseguito subito dopo la risoluzione logica, mentre l’animazione nemica
prosegue. L'azione del player (la sua animazione, i suoi secondi o il passo
dell'ombra) occupa invece il suo input: una pressione fatta nel frattempo viene
scartata, non conservata, e solo una nuova pressione a fine azione agisce.
Lo stesso per cast e cinematiche: al termine della carta non parte nessuna
azione involontaria. L'unico input che aspetta qualche fotogramma è il passo
premuto sul secondo, in attesa del tasto della diagonale; ogni confine (fine
della finestra, QTE, pausa, mappa, schivata, perdita del focus, nuova stanza) lo
lascia cadere. Il targeting
delle carte sopravvive ai beat autonomi,
ma viene chiuso da timeout o QTE. Anche il recupero avanza durante le animazioni
e la consultazione dell'ologramma; QTE, pausa e perdita del focus lo sospendono.
L'HUD mostra `RECUPERO`, countdown decimale e carte disabilitate. La fine del
fight cancella subito il debito e consente il movimento nel Loot.

Una diagonale riuscita sposta di una cella e costa un secondo. Errore o
scadenza perdono la mossa e costano comunque un secondo; una landing inizialmente
bloccata non apre il QTE. I QTE difensivi intercettano attacchi ordinari melee,
cariche e frecce prima del danno: la parata aggiunge Shield 2 per quel pulse, il parry
annulla il colpo e infligge 2 danni, la deviazione restituisce il danno previsto,
la schivata usa movimento e hazard normali. Il parry restringe la finestra
residua a massimo 0.45 secondi; scegliere la difesa non rinnova la scadenza.
Attacchi ad area e hazard restano soggetti alle loro normali regole;
non tutti gli attacchi offrono un QTE. Shield e gli altri status mantengono
anche gli effetti automatici già esistenti.

La schivata non richiede carte: quella attiva attraversa al massimo due celle
ortogonali e costa un secondo; quella reattiva muove di una cella durante il
QTE dell'attacco in corso, senza aggiungere altro tempo. Dopo una schivata
riuscita devono passare due secondi del mondo completi, compresi i beat maturati nel recupero del player.
**Afterimage permette di schivare anche durante il recupero**, oltre al suo
effetto automatico. Fine combattimento e nuova run azzerano questo recupero.
La schivata non attraversa muri, oggetti solidi o nemici e non conferisce
invulnerabilità ai pericoli sul pavimento. Un tentativo attivo senza spazio
non consuma tempo; una landing reattiva bloccata fa fallire il QTE.

La fog non memorizza celle visitate. Le viste 3×3, 5×5, 7×7 e 9×9 sono centrate sul player; nel 2×2 il
quadrante include il player e segue il segno dell'ultima direzione. Gli angoli
fra due occlusori restano nascosti. L'ologramma mostra invece l'intera griglia
e le posizioni correnti: pedina ciano per il player, pedina rossa condivisa
per i nemici, modello viola/oro condiviso per Custode e Demolitore. Consultarlo
non estende il targeting delle carte oltre la visibilità locale.

## Azioni, impulsi, status e reazioni

Sorgenti: [action.odin](../../src/game/action.odin), [pulse.odin](../../src/game/pulse.odin),
[event.odin](../../src/game/event.odin), [status.odin](../../src/game/status.odin),
[reaction.odin](../../src/game/reaction.odin),
[reaction_definition.odin](../../src/game/reaction_definition.odin) e
[reaction_binding.odin](../../src/game/reaction_binding.odin).

### Azioni e commit

```text
Input / IA / trigger -> Action -> validazione -> effetti ordinati
                                            -> reazioni FIFO -> report
Il clock del mondo pianifica separatamente i beat e gli intenti pronti.
```

Il target primario descrive la scelta; i destinatari degli effetti possono
essere diversi, come per un'area o una carta che colpisce e concede Shield.
Gli effetti comprendono `Damage`, `Heal`, `Gain_Gold`, `Move`,
`Apply_Status`, `Remove_Status`, `Add_Reaction_Binding`, `Draw_Cards`,
`Discard_Cards` e `Create_Card`.

Il resolver valida fase, sorgente, target e almeno un effetto inizialmente
applicabile, se presente. Ricontrolla poi ogni effetto nell'ordine dichiarato:
un effetto diventato invalido incrementa `skipped_effects`, senza annullare
quelli già applicati. Per esempio, Grappling Hook può infliggere danno e
saltare il trascinamento se il bersaglio muore. Un'azione vuota come Wait resta valida.

`resolve_action_once` risolve una sola azione; `resolve_action` aggiunge il
dispatch reattivo. Nessuno dei due avanza il pulse. La transazione della carta
paga energia e cambia zone del deck, ripristinandole se l'intera azione è
rifiutata: non offre rollback globale degli effetti di un'azione già accettata.

### Ordine del pulse e degli eventi

Le azioni del player risolvono effetti, reazioni, raccolta magnetica e Veleno;
non eseguono direttamente una risposta nemica. Il clock accoda beat di un secondo,
consumati da `Continue_Pulse` in segmenti con un log limitato:

1. scadono i countdown nemici e si risolvono esplosivi e Furnace;
2. gli intenti pronti vengono ordinati per ID, con Protect prima degli altri;
3. ogni intento si risolve sulle celle annunciate; la difesa QTE può sospenderlo;
4. dopo ogni azione nemica mordono Veleno e Rallentamento, secondo le loro regole;
5. si chiude il beat: durate, energia ogni tre beat, pianificazione e `Pulse_Advanced`;
6. seguono raccolta, eventuale refill e sincronizzazione con Loot o Defeat.

La Bruciatura si risolve invece alla scadenza della finestra (`Timeout`).
Un combattimento concluso non avvia nuovi beat; il movimento in Loot non li
consuma. `Room.recent_events` conserva il segmento dell'ultimo comando e viene
azzerato dal successivo. La presentazione riceve ogni segmento nell'ordine.

### Status

Ogni combattente possiede uno `Status_Set` inline, con un posto per tipo
(`MAX_STATUSES_PER_ENTITY = len(Status_Kind)`) e una sola istanza per tipo. La
potenza deve essere positiva, e così la durata, tranne per gli status a
**stack** (`status_kind_stacks`: Veleno, Bruciatura, Rallentamento e le cariche
del Viandante): non ne hanno (`remaining_pulses` resta 0) e nessun pulse li
consuma; ogni applicazione aggiunge i propri stack.

| Status | Stacking | Comportamento |
|---|---|---|
| Shield | somma saturata della potenza, durata maggiore | assorbe danno dopo la difesa; a zero viene rimosso |
| Poison (Veleno) | somma saturata degli stack, senza durata | a ogni azione di chi lo porta infligge danno pari agli stack (sorgente System), poi perde uno stack; a zero finisce |
| Burn (Bruciatura) | somma saturata degli stack, senza durata | All'inizio di ogni nuova finestra (quando quella in corso scade e cambia il numero di pulse) infligge danno pari agli stack. Gli stack non calano mai: dura fino alla morte o alla fine della stanza |
| Slow (Rallentamento) | somma saturata degli stack, senza durata | Ogni stack fa aspettare 1 secondo in più il prossimo intento pianificato dal nemico (il conto alla rovescia dell'ispettore e le minacce sul terreno lo includono; `Enemy_Intent.slowed`); dopo l'azione così trattenuta perde uno stack. L'intento già in corso quando arriva non si allunga e non lo consuma. Il player non può esserne colpito |
| Thorns | potenza e durata maggiori | contraccolpo per danno effettivo ricevuto da un avversario vivo |
| Afterimage | potenza e durata maggiori | dopo il proprio `Moved` in Combat concede Shield pari alla potenza, per due pulse; in M7 permette schivate durante il recupero |
| Stagger | potenza e durata maggiori | M7: interrompe l’intento nemico, cancella mira/lancio preparati e lascia almeno 1 secondo sfruttabile dopo il costo della carta |
| Survey | potenza e durata maggiori | M7: lato della vista +2 (2×2 → 5×5), massimo 9, rispettando LoS e senza memoria |
| Deflect (RIFLESSO) | somma saturata degli stack, senza durata | solo il Viandante: il prossimo colpo nemico che lo colpirebbe torna all'attaccante; uno stack per colpo, fino alla fine della stanza |
| Arrows (FRECCE) | somma saturata degli stack, senza durata | solo il Viandante: frecce da scoccare con `Ctrl` + clic; uno stack a freccia, fino alla fine della stanza |
| Fate (DESTINO) | il massimo degli stack (3), senza durata | solo il Viandante: gli urti caricati tirano il dado dell'ultimo Dado del Destino, che il chip nomina (`DESTINO 3 d8`); uno stack a urto, fino alla fine della stanza |
| Venom_Blade (LAMA) | somma saturata degli stack, senza durata | solo il Viandante: urti con 2 Veleno; uno stack a urto, fino alla fine della stanza |

Il danno al player segue `danno base -> difesa -> Shield -> salute`; i nemici
non hanno ancora una statistica difesa. Il morso di Veleno e Bruciatura salta
la difesa (resta pari agli stack): solo lo Shield lo assorbe, e può concludere
il fight. La durata applicata prima della risposta nemica avanza già alla fine
di quel pulse.
Le durate di Shield, Thorns, Afterimage, Stagger e Survey avanzano sui beat
del mondo. La Bruciatura morde sul confine della finestra, con lo Shield
ancora disponibile in quel momento.

Sono **azioni** del player tutti i comandi accettati in combattimento: passo
(anche durante il recupero), attacco a urto, carta, attesa, schivata (anche
quella reattiva del QTE di difesa, appena atterra), diagonale (anche fallita),
refocus, Activate, Equip e la freccia di Feretro; il Veleno morde alla fine del comando, prima del
tempo del mondo che il comando fa scorrere. Non lo sono Movimento Ombra (la
carta, i passi dell'ombra e la risalita: nell'ombra il player è intangibile),
le altre risposte ai QTE di difesa (blocco, parata, deviazione) e l'anello
Tesla. Del nemico ogni intento risolto, di qualsiasi tipo; un intento
interrotto da Stagger non è un'azione. La Bruciatura in M7 morde sul comando
`Timeout`, con i suoi cue e i suoi suoni.

Veleno e Bruciatura del pavimento (pozze e fuochi,
[Pozza di Veleno e Incendio](meccaniche.md#pozza-di-veleno-e-incendio)) hanno sorgente System,
come i morsi: nessuna reliquia o reazione del Viandante li modifica.
Thorns non scatta su danno interamente assorbito, veleno, bruciatura o hazard neutrali.
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

Sorgenti: [targeting.odin](../../src/game/targeting.odin),
[movement.odin](../../src/game/movement.odin) e [hazard.odin](../../src/game/hazard.odin).

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
La portata blu indica gli anchor raggiungibili, non garantisce una giocata;
l’area ambra indica la footprint, il segno menta il bersaglio valido e il rosso
un blocco o una giocata impossibile. La luce rispetta la fog corrente.

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

Shove spinge prima di colpire; Grappling Hook applica danno prima del
trascinamento. Un blocker non annulla un effetto di danno ancora applicabile.
Dash concede Shield 2 prima del movimento: il percorso deve essere valido
prima di pagare. Tutte e tre usano Traverse. Grappling Hook si ferma al primo
attore e trascina il bersaglio fino alla cella adiacente al player.
Spostare un nemico non aggiorna il suo intento già committed: il piano stale
produce miss o blocco, poi viene ripianificato per il pulse successivo.

## Oggetti, esplosivi e loot

Sorgenti: [grid_object.odin](../../src/game/grid_object.odin),
[explosive.odin](../../src/game/explosive.odin), [room.odin](../../src/game/room.odin).

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

Pozze e fuochi delle carte della Fase 2 non sono oggetti: stanno sul pavimento
(`Room.ground`, [ground.odin](../../src/game/ground.odin)) e non occupano né posti né celle.
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
La preview Shove mostra percorso, landing e blocco della spinta, che precede
il danno anche quando il ghiaccio ha poca vita. Durante Loot il bump può rompere i solidi spostabili,
senza pulse, per liberare corridoi o uscita.

### Micce e combinazioni

Un barile o una bomba del player infligge **4 danni base nel 3x3** a player,
nemici e oggetti danneggiabili; una bomba nemica ne infligge **3**. La footprint esclude muri, ostacoli fissi e fuori
bounds; non richiede LoS fra le celle dell'area. Difesa e Shield valgono
normalmente. Preview e danno condividono le stesse celle.

La miccia avanza sui beat del mondo, non sul numero di azioni del player.
La scadenza interna è `pulse_count + fuse_pulses + 1`: il countdown visibile
segue questo confine e lo scoppio precede gli intenti nemici. Cast, dadi e
pause del mondo fermano anche la miccia. Spostare o colpire un
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
dopo gli spostamenti in Loot (in Loot pesca anche la [Canna da Pesca](meccaniche.md#canna-da-pesca)). La raccolta non paga energia o pulse e ignora
LoS, muri, ostacoli, trappole e uscita: raccogliere da quelle celle non significa
entrarci.

Ogni raccolta usa una normale Action Collect con Gain_Gold o Heal e rimuove il
drop soltanto se accettata. Una cura a vita piena viene consumata con guarigione
effettiva zero. `Loot_Dropped` precede `Loot_Collected`, poi Gold_Gained o Healed;
la simulazione assegna tutto subito, la timeline ne mostra il percorso.
`create_room` prealloca il drop d'oro di ogni nemico più i drop curativi previsti,
così il resolver non deve far crescere il buffer durante le uccisioni.
