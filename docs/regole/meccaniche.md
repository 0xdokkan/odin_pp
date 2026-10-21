[← Odin PP](../../README.md)

### Movimento Ombra

`Movimento Ombra` (rara, energia 3, **0 s** di finestra, senza potenziamenti né
exhaust) fa sprofondare il Viandante nella propria ombra per **4 secondi
reali**. Il mondo si ferma del tutto: nemici, intenti e loro tempi, micce,
dispositivi, impulsi, clock e battiti del mondo, finestra, stordimento e
recuperi, arrivi della Prova restano esattamente dov'erano (18 s prima, 18 s
dopo). I 4 secondi partono quando la giocata ha finito di mostrarsi: il
cartoncino sprofonda, poi la carta va negli scarti e se ne pesca un'altra
(circa 0,9 s in tutto); fino ad allora, come durante ogni propria azione, una
pressione si perde, e l'arco sulla pozza e la barra dell'HUD cominciano a
calare solo quando l'ombra si può muovere. Il
Viandante è intangibile, nessun danno lo raggiunge, e può solo **muovere
l'ombra**: niente carte, attacchi, schivate, attese, Refocus o dispositivi. Ogni
passo dell'ombra dura 0,4 s e parte dalla sua casella con le regole normali del
movimento (muri, oggetti e nemici bloccano, nessuno viene urtato); una pressione
durante il passo si perde. L'ombra ha i suoi battiti, a 1, 2 e 3 secondi del suo
orologio (entro 0,15 s): due tasti premuti su uno di questi fanno il passo in
diagonale (CRITICO!), come sul secondo del mondo. Allo scadere, appena l'ultimo
passo è arrivato, il Viandante risale dove si trova l'ombra con un
teletrasporto: di nuovo tangibile, trappole e fuoco della casella d'arrivo
mordono come a ogni atterraggio e il magnete raccoglie il bottino vicino; poi il
mondo riprende, e un colpo annunciato sulla casella lasciata va a vuoto. Giocata
sul secondo non consuma lo scocco (niente CRITICO né bonus); si può giocare
anche da storditi, e lo stordimento riprende con gli stessi secondi. Una copia è
nel mazzo iniziale di ogni run tattica ([tactical_setup.odin](../../src/run/tactical_setup.odin))
e la carta compare fra ricompense e negozio.

Sul tavolo il cartoncino del Viandante scende sotto il pavimento fino al
cappuccio, scuro, dentro una pozza d'inchiostro viola che scivola di casella in
casella; i colori del mondo si spengono, e i suoi cartoncini, sigilli, lampade e
dispositivi restano nella posa in cui si sono fermati; anche ciò che il mondo
stava mostrando sul Viandante (un `MANCATO`, una parata, le loro scintille)
resta dove lui è sprofondato e non segue la pozza. Il bordo della pozza
segna i secondi rimasti, un anello d'oro si stringe verso ogni battito e si
accende sopra di esso. L'HUD diventa viola: `OMBRA` con i secondi dell'ombra, la
loro barra e la spia dei suoi battiti; sotto, la finestra ferma (`FERMO 18.0s`);
una linea viola si consuma a ogni passo e la riga di stato dice
`MONDO FERMO / SOLO PASSI / DIAGONALE SUL BATTITO`. La mano scrive
`OMBRA / SOLO PASSI` e la schivata `OMBRA`. La carta mostra `0s` di tempo,
`OMBRA 4s / MONDO FERMO` e `INTANGIBILE / SOLO PASSI`. Per non confondersi con
l'ombra, lo status di Afterimage nell'HUD si chiama ora `SCIA`. Regole in
[tactical_shadow.odin](../../src/game/tactical_shadow.odin), quadro in
[shadow_step.odin](../../src/render/shadow_step.odin).

Nella Prova meccaniche anche l'ombra si sente
([lab_sounds.odin](../../src/render/lab_sounds.odin)): la carta sfila dalla mano e
una campana si ferma insieme al tempo, il Viandante sprofonda in un'onda
d'inchiostro, ogni passo dell'ombra è un fruscio morbido (mai gli stivali), la
diagonale sul battito suona il CRITICO e la risalita finisce con il cartoncino
posato sulla pietra. Lo smoke `--smoke-mechanics-lab` la gioca dalla mano e la
filma ([Verifica e smoke test](../verifica.md#verifica-e-smoke-test)).

### Pozza di Veleno e Incendio

Le prime carte della Fase 2 vivono sul pavimento della stanza tattica. Pozze e
fuochi non sono oggetti della griglia: non occupano uno dei 32 posti, non
bloccano niente, le bombe ci cadono sopra e i dispositivi ci si posano, e non
toccano mai il Viandante. Entrambe le carte puntano una **cella libera** a
distanza Chebyshev 1–3 con linea di vista: calpestabile, senza copertura, senza
nemici, oggetti di alcun tipo o il giocatore stesso (trappole e uscita vanno
bene). Restano fino alla fine della stanza, anche durante il bottino (una stanza
nuova parte pulita). Regole in [ground.odin](../../src/game/ground.odin).

`Pozza di Veleno` (comune, energia 1, **1 s** di finestra) versa una pozza. Un
**nemico** che entra in una sua cella, con qualunque movimento (un passo, ogni
cella di una carica, una spinta o un trascinamento, l'atterraggio di un
teletrasporto), prende **2 Veleno** (+1 per upgrade, +1 se giocata sul secondo),
e altrettanto per ogni cella di pozza in cui passa, anche da una cella di pozza
all'altra; uscirne non dà niente. Il Veleno arriva dal System, come quello dei
dispositivi: la reliquia Venom Vial non lo aumenta e le reazioni del Viandante
non lo vedono. Pozze vicine sono un'unica area e si disegnano come una sola chiazza.
Dopo ogni pozza il pavimento libero (calpestabile, senza coperture né oggetti che
bloccano, non ancora pozza) si divide in aree a 4 vicini: la più grande è
l'esterno, e ogni altra area che tocca una pozza è chiusa e **si riempie subito**
con il veleno della carta che l'ha chiusa; chi ci sta dentro prende quel Veleno.
Gli attori non chiudono mai un'area, muri, coperture e oggetti solidi sì. Una
tasca chiusa solo da muri o oggetti, senza pozze intorno, resta asciutta; due
aree a pari merito come più grandi restano entrambe esterne. Un nemico che entra
nella pozza con un proprio passo prende il Veleno subito e lo sente alla fine di
quella stessa azione (2 danni, poi ne resta 1).

`Incendio` (non comune, energia 2, **2 s** di finestra) accende un fuoco sulla
cella: un effetto del pavimento, non l'oggetto Fire (non accende barili e non
brucia il Viandante). Un **nemico** che entra in una cella in fiamme prende **1
Bruciatura** (+1 per upgrade, +1 se giocata sul secondo) a ogni ingresso. A ogni
nuova finestra, nello stesso momento in cui morde la Bruciatura, ogni fuoco cresce
a croce: bracci lunghi 1, poi 2, 3 e 4 caselle; un braccio si ferma per sempre al
primo muro, copertura o oggetto solido (anche se poi l'ostacolo si sposta); alla
quinta finestra, quando arriverebbe a 5, il fuoco si spegne. Un nemico sulla
casella che prende fuoco riceve la Bruciatura del fuoco più forte, una volta
sola anche se lo raggiungono due fuochi, e la sente dalla finestra dopo: prima
morde, poi il fuoco cresce, come per chi ci entra camminando. Al massimo 32 fuochi
per stanza; un fuoco può ardere sopra una pozza o un altro fuoco, una pozza non
si versa su un'altra pozza. I nemici non evitano pozze e fiamme: le attraversano
come il resto del pavimento.

Sul tavolo ([ground_fx.odin](../../src/render/ground_fx.odin)) pozze e bruciature sono
un decalco di carta disteso sul pavimento, in pixel art: il liquido verde (bruno
e braci sotto il fuoco) con il margine di carta bianca, la linea d'inchiostro e
il taglio della carta verso la camera, come cartoncini e oggetti di carta, e la
luce sul lato lontano del liquido. Quando la camera gira verso un altro lato del
tavolo, taglio e luce la seguono (alla diagonale più vicina) e il decalco si
ricuoce a poco a poco; una camera ferma vicino a un asse non lo ricuoce avanti e
indietro. Le
celle vicine si fondono in una chiazza dai bordi arrotondati, quelle che si
toccano solo in diagonale restano separate. La pozza compare quando la fiala di
carta lanciata dal Viandante atterra, con uno schizzo di gocce, e un'area chiusa
si allaga dalla cella versata verso l'esterno. Il fuoco arriva come una brace;
a ogni finestra le fiamme di carta spuntano sulle caselle nuove (più alte al
centro, più basse nell'ultima finestra) e alla fine si abbassano e spariscono con
la loro bruciatura. Un nemico che mette piede in una pozza schizza gocce verdi,
in una fiamma tira faville. Mirando, l'anteprima della carta colora di verde anche
le celle che la pozza riempirebbe, e di brace la croce intera che il fuoco
raggiungerebbe.
Le carte scrivono `2 VELENO A CELLA` / `SOLO NEMICI / STANZA` e
`1 BRUCIATURA A CELLA` / `CROCE: +1 A FINESTRA` (con sette carte in mano o più,
sulle carte strette, `Pozza` / `2 VELENO` / `A OGNI CELLA` e `1 BRUCIATURA` /
`CRESCE A CROCE`); l'ispettore aggiunge
`AREE CHIUSE: SI RIEMPIONO` / `OGNI CELLA ENTRATA AVVELENA` e
`CRESCE A OGNI NUOVA FINESTRA` / `SI SPEGNE ALLA QUINTA`. Le icone, nella quinta
riga dell'atlante ([build_card_icons.py](../../tools/art/build_card_icons.py)), sono una
fiala rovesciata nella sua pozza e un fuoco su una croce bruciata, con una
fiamma in fondo a ogni braccio.

Nella Prova meccaniche ognuna ha il suo suono: la Pozza è una fiala stappata, il
veleno che gorgoglia fuori e lo schizzo sulla pietra; l'Incendio un acciarino
battuto due volte, la vampata e il crepitio che si allarga. Una pozza in cui
entra un nemico schizza (`world_pool_splash`); un fuoco i cui bracci si allungano
a una nuova finestra rugge (`world_fire_spread`, una volta: un fuoco appena acceso
suona con la sua carta) e quello che alla quinta si spegne sfrigola via in un filo
di fumo con un'ultima brace (`world_fire_out`); un nemico che entra nel fuoco lo
fa divampare (`world_fire`). Lo smoke `--smoke-mechanics-lab` le gioca dalla
mano, le filma ([Verifica e smoke test](../verifica.md#verifica-e-smoke-test)) e ne controlla
le regole. L'anello chiuso dall'ultima pozza fa otto celle da 2 Veleno, e il
chaser rimasto dentro prende i suoi 2 una volta sola. Il chaser che attraversa
due pozze prende 2 Veleno a ogni cella e ogni suo passo morde i suoi stack: arriva
accanto al Viandante con 33 vita su 40 e 1 Veleno. Il Viandante entra in una
pozza sua senza prendere niente e senza schizzi. Il fuoco allunga i quattro
bracci di una casella a ogni finestra; prende il bruto alla seconda con 1
Bruciatura, che non cala mai e morde dalla terza (dopo la seconda, la terza, la
quarta e la quinta finestra il bruto ha 60, 59, 58 e 57 di vita); brucia la
casella del Viandante senza segnarlo; senza muri sulla sua strada deve ruggire
quattro volte e spegnersi una.

### Deflect, Feretro, Dado del Destino e Lama Velenosa

Le altre quattro carte della Fase 2 caricano il Viandante di **cariche**: status
a stack che porta solo lui (un nemico non ne riceve mai) e che si spendono una
alla volta con l'uso, fino all'ultima o alla fine della stanza (una stanza nuova
parte senza). Si giocano su di sé, con il loro tasto (`1`–`8`) o con un secondo
clic sulla carta. Tutte e quattro prendono **1 s** di finestra e
compaiono fra ricompense e negozio. Nell'HUD vengono
prima Veleno e Bruciatura del Viandante, che lo mordono (con tre o quattro cariche
non finiscono mai nel `+n`), poi le cariche: `RIFLESSO n`, `FRECCE n`,
`DESTINO n d8` (con il dado che tireranno gli urti caricati: quello dell'ultimo
Dado del Destino giocato, che compare con le sue cariche; un d4 se nella stanza
non ne è stato giocato nessuno), `LAMA n` (con poco spazio `RIF`, `FRE`,
`DES 3 d8`, `LAM`), poi gli altri status. Una carica si vede spesa quando il suo colpo arriva (la lanterna cala, la
freccia colpisce, il colpo rimandato raggiunge il Viandante), non quando parte;
l'ultima carica spesa fa sparire il suo chip. Un colpo, un urto o una freccia spendono le
loro cariche solo se vengono accettati. Ogni status ha ora un posto per tipo
(`MAX_STATUSES_PER_ENTITY = len(Status_Kind)`): il Viandante può portarli tutti
insieme, tranne il Rallentamento. Regole in
[player_charges.odin](../../src/game/player_charges.odin).

`Deflect` (non comune, energia 1, senza potenziamenti) dà una carica di
**RIFLESSO**; ogni giocata ne aggiunge una (giocata sul secondo, due). Il
prossimo colpo nemico che colpirebbe il Viandante (un attacco in mischia, un
dardo, il colpo di una carica) torna indietro: lui non subisce niente, né danno
né spinta, il suo Shield resta intatto, e l'attaccante prende il danno che
avrebbe preso lui (dopo la sua difesa, almeno 1); si spende una carica e per
quel colpo non si apre la scelta di difesa. Bombe, esplosioni, trappole,
pericoli, Veleno e Bruciatura non sono colpi e non la toccano; nell'ombra di
Movimento Ombra nessun colpo lo raggiunge e la carica resta. Sul tavolo il
dardo arriva al cartoncino del Viandante, che para, gira e torna nel
balestriere che l'ha tirato (è lo stesso dardo, mai un secondo); un fendente o
una carica vengono parati e il Viandante risponde con un colpo della sua
lanterna (o dell'arma M8 che ha in mano). `RIFLESSO` compare sopra di lui quando
il colpo torna indietro, una volta per colpo; se l'attaccante ha uno Scudo, sopra
l'attaccante si legge anche `PARATA n`, e un dardo rimandato che lo Scudo ferma
tutto rimbalza via invece di conficcarsi. Il chip `RIFLESSO` resta nell'HUD, al
suo posto, finché il colpo non raggiunge il Viandante.

`Feretro` (non comune, energia 2) dà **3 frecce** (+1 per upgrade, +1 sul
secondo); le giocate si sommano. Tenendo premuto `Ctrl` il tavolo segna con un
anello d'oro ai piedi i nemici che le frecce raggiungono: visibili e sulla
linea di tiro, con la LoS dei tiri del gioco (muri, ostacoli e oggetti opachi
la fermano, come la diagonale fra due blocchi; gli altri combattenti no; una
traccia di 12 celle al massimo);
quello sotto il mouse si accende, con la linea che la freccia farebbe. Un clic
sinistro su uno di loro scocca una freccia: è un'azione del Viandante come un
attacco a urto (1 s di finestra, il suo Veleno morde, si gira verso il
bersaglio), senza coda (premuta durante la propria azione si perde) e mai
critica. Vola come un dardo di carta e fa 1 danno più uno status scelto dai dadi
del giocatore: Veleno 2, Bruciatura 1 o Rallentamento 1. Lo status compare sul
nemico quando la freccia arriva: finché vola, quello che segue il tiro (lo
status, la caduta del nemico, la freccia spesa) aspetta, mentre il mondo e il
tempo della finestra vanno avanti. Con `Ctrl` premuto, un
clic che non cade su un nemico raggiungibile non fa niente (non prende né gioca
carte); sulla mano il clic resta della mano. La riga della mano scrive
`CTRL+CLIC SU UN NEMICO: FRECCIA (n)` e, con `Ctrl` premuto,
`CLIC SU UN NEMICO EVIDENZIATO: FRECCIA`.

`Dado del Destino` (rara, energia 2, carta con dadi: d4 al livello 0, poi la
scala fino al d20) carica i prossimi **3 attacchi a urto** (`DESTINO 3 d4`: il
chip dice anche il dado che tireranno): una
nuova giocata li riporta a 3, mai oltre, e il dado è quello dell'ultima carta
giocata. Giocata sul secondo non consuma lo scocco, come Movimento Ombra: non ha
una versione critica. A ogni urto caricato, dritto o in diagonale, il dado si
tira al colpo e decide: **1** Veleno, **2** Bruciatura, **3** Rallentamento, con
tanti stack quanto il risultato; **4** ruba vita (il Viandante guarisce del
danno inflitto, niente a vita piena); **5** critico (danno doppio; un urto già
critico sul secondo resta doppio, non quadruplo); **6 o più** letale: il nemico
cade, scudo compreso. Il boss (il Demolitore) e il miniboss (il Custode) non
cadono mai così: per loro è un critico. Con il d4 del livello 0 escono solo le
prime quattro facce. Sul tavolo, appena il colpo arriva, dal lato sinistro del
cartoncino colpito esce un cartellino di carta con il contorno in pixel del dado
(il triangolo del d4, il quadrato del d6, il rombo del d8, l'aquilone del d10, il
pentagono del d12, l'esagono del d20) e la faccia uscita nel colore di ciò che
fa. Si ferma accanto al cuore del nemico, mai sopra, nemmeno mentre spunta: da
un cartoncino stretto, come quello del Custode, esce più in là. Sopra il nemico
si legge `VELENO n`, `BRUCIATURA n`, `RALLENTAMENTO n`, `RUBA VITA +n`, `CRITICO`
o `LETALE`. Il critico fatto dal dado lo dice solo il dado, quando
compare: l'urto non lo annuncia prima. Un urto critico sul secondo dice `CRITICO`
da sé, se il dado non lo dice già. Due urti di fila sullo stesso nemico con la
stessa faccia mostrano ciascuno il suo dado e il suo suono.

`Lama Velenosa` (comune, energia 1, carta con dadi) tira il suo dado quando la
si gioca, come ogni carta con dadi (il lancio si vede a tutto schermo): il
risultato è il numero di **attacchi a urto avvelenati** (`LAMA n`; le giocate si
sommano, sul secondo uno in più). Ogni urto caricato lascia 2 Veleno; Lama e
Destino possono caricare lo stesso urto.

Le carte scrivono `+1 RIFLESSO` / `RIMANDA UN COLPO`, `3 FRECCE / CTRL+CLIC` /
`1 DANNO + 1 STATUS`, `1d4 SU 3 COLPI` / `UN TIRO A OGNI COLPO` e
`1d4 COLPI AVVELENATI` / `2 VELENO A COLPO` (con sette carte in mano o più
`+1 RIFLESSO` / `IL COLPO TORNA`, `3 FRECCE` / `CTRL+CLIC`, `Dado` /
`1d4 A COLPO` / `PER 3 COLPI` e `Lama` / `1d4 COLPI` / `2 VELENO L'UNO`);
l'ispettore aggiunge
`IL NEMICO PRENDE IL COLPO` / `NO BOMBE, TRAPPOLE, STATUS`,
`+ VEL 2 O BRU 1 O RAL 1` / `LINEA DI TIRO / 1s L'UNA`,
`1 VEL 2 BRU 3 RAL 4 VITA` / `5 CRITICO / 6+ LETALE` e
`IL DADO DECIDE I COLPI` / `LE CARICHE SI SOMMANO`. Per non confonderla con
Deflect, la difesa di Thorn Coat contro i dardi si legge ora
`ABILITA DEVIAZIONE` e `QTE: DEVIAZIONE (FRECCE)`, come il tasto `L`. Le icone,
nella quinta e nella sesta riga dell'atlante
([build_card_icons.py](../../tools/art/build_card_icons.py)), sono uno scudo tondo
d'acciaio da cui un dardo rimbalza via, una bara con la croce d'oro e tre frecce
che spuntano dalla testa, un d20 d'osso con il 20 in un anello viola e un pugnale
dall'elsa d'oro che gocciola veleno.

Nella Prova meccaniche ognuna ha il suo suono: lo scudo alzato e il colpo che
rimbalza via, il coperchio di una bara che cigola e tre frecce estratte, un dado
d'osso sul legno e una campana bassa del destino, un pugnale sfilato e una goccia
di veleno che sfrigola; ogni carica ha il suo suono quando arriva, il colpo
rimandato squilla quando raggiunge il Viandante (`pilgrim_deflect`), la freccia
ha la sua corda (`pilgrim_shoot`) e il dado del Destino rimbalza sul nemico
colpito (`ui_fate_die`). Lo smoke `--smoke-mechanics-lab` le gioca dalla mano, le
filma ([Verifica e smoke test](../verifica.md#verifica-e-smoke-test)) e ne controlla le regole.
Deflect rimanda un dardo, un fendente e una carica: per nessuno dei tre si apre
la scelta di difesa, anche se la schivata è pronta; il Viandante non perde vita
né casella, l'attaccante prende i 3 del colpo e la carica si spende. Il dardo è
uno solo, che va e torna; fendente e carica hanno la risposta della lanterna.
Feretro dà 3 frecce. Con `Ctrl` le frecce raggiungono il nemico sulla linea di
tiro, che il tavolo segna, e non quello dietro un blocco di copertura: un clic su
quest'ultimo non scocca niente. La freccia è un'azione da 1 s e lascia 1 danno e
uno solo fra Veleno 2, Bruciatura 1 e Rallentamento 1. Il Dado del Destino carica
3 urti con il d4 del livello 0; quando il d4 fa 2, l'urto lascia 2 danni e
Bruciatura 2. Giocato di nuovo, riporta gli urti a 3 e non oltre. Un 16 del d20
fa cadere il nemico, ma sul Custode è solo un critico (4 danni). Lama Velenosa
tira 3 e il suo urto lascia 2 danni e Veleno 2, con 2 cariche rimaste.

### Lazzo

`Lazzo` (rara, energia 2, **2 s** di finestra; compare fra
ricompense e negozio) prende al lazo un nemico e lo fa girare intorno
al Viandante finché non muore. Regole in [lasso.odin](../../src/game/lasso.odin),
tavolo in [lasso.odin](../../src/render/lasso.odin).

**Il lancio.** Il bersaglio è un nemico entro 4 celle (Chebyshev), visibile e
in linea di vista. Anche il boss (il Demolitore) e il miniboss (il Custode)
possono essere presi: il Lazzo non ha limiti di peso. Il lancio è il cast
della carta: per i suoi 2 s il mondo è fermo, come
per ogni carta. Il nemico gira su un vero cerchio intorno al centro della
casella del Viandante, e l'**anello** di raggio r sono tutte le caselle che quel
cerchio attraversa. Il **raggio** del giro, scelto prima di girare, è il più
grande fra 4 e 1 il cui anello non ha caselle solide (muri, fuori dalla stanza,
coperture, oggetti che bloccano il passo): un muro sulla quarta cella in linea
retta dà raggio 3, mentre una copertura più vicina, dentro l'anello di 4, non lo
accorcia (il nemico in volo ci passa sopra). Se anche l'anello di 1 ha una
casella solida (il Viandante accanto a un muro, che taglia tutti gli anelli) il
raggio è 1 e il nemico sbatte (vedi sotto). Il nemico viene tirato sulla casella
dell'anello dalla sua parte (se è solida, sulla libera più vicina lungo
l'anello; a pari distanza, nel verso del giro), perde il suo intento e il giro
parte da lì, in senso antiorario sul tavolo.

**Il giro.** Il primo giro dura 0,9 s, ogni giro dopo dura il 12% in meno di
quello prima (0,88 volte), fino a 8 giri al secondo (dal diciassettesimo): un
nemico da 60 di vita, da solo e senza colpi, cade dopo 60 giri, in 12,03 s, e i
colpi lo accorciano molto (`LASSO_FIRST_TURN_SECONDS`, `LASSO_TURN_SPEEDUP` e
`LASSO_FASTEST_TURN_SECONDS` in [lasso.odin](../../src/game/lasso.odin)). Il moto è
continuo e si risolve a passi esatti, casella per casella, sul tempo del mondo:
un fotogramma lungo non salta niente. Quando il nemico in volo entra in una
casella dell'anello occupata da un altro nemico, è il **colpo n** (1, poi
2, 3...): tutti e due prendono n danni dal Viandante e il colpito viene spinto
di n celle via dal Viandante (nella più vicina delle otto direzioni, al massimo
12). **Dentro il raggio**, invece, il passaggio della corda dà **solo la spinta
fino alla prima casella dell'anello**: anche un nemico vicino al Viandante
raggiunge il perimetro, senza oltrepassarlo. Questa distanza non dipende dalla
forza del contatto. Non ci sono danni diretti al nemico spinto né a quello in
volo; il contatto continua ad avanzare la progressione dei colpi del Lazzo.
La spinta segue le regole
consuete: si ferma prima di un muro o di un altro corpo, e le caselle in cui
entra (pozze, fuochi, scosse, pericoli) fanno il loro effetto, anche quando
il contatto con la corda non infligge danni.
La corda spinge ciascun nemico interno una volta per giro: stare sulla stessa
direzione non moltiplica i contatti a ogni fotogramma né aggiunge un colpo sul
perimetro nella stessa rotazione. Dal giro successivo il nemico portato sul
bordo può subire i normali danni della collisione con quello in volo.
Quando più nemici interni sono allineati, vengono risolti dal più lontano al
più vicino. Un ostacolo ferma la spinta. Se la casella dopo è solida (con raggio 1, o un oggetto messo
sull'anello durante il giro) è uno **schianto**: il colpo n lo prende solo il
nemico in volo, che rimbalza e torna indietro nell'altro verso. Ogni giro
intero percorso (360°, in un verso o nell'altro) gli costa **1 vita**. Il
giro finisce solo con la sua morte, e il suo loot cade dove muore.

**Il perno.** Il mondo continua: i nemici agiscono e la finestra scorre. Il
Viandante fa da perno: niente passi, urti, carte o frecce (premuti si perdono,
non restano in coda); i colpi nemici, la scelta di difesa, i QTE e Deflect
valgono come sempre. Ogni schivata o spostamento del Viandante, una spinta
compresa, **lascia andare** la corda: il nemico atterra sotto di sé o, se la
casella è occupata, sulla libera più vicina (entrandoci), e riparte subito con
un intento nuovo, senza stordimento (il tempo in volo chiude anche un recupero
in cui era; se la corda si molla nel mezzo di un battito, per una spinta o per
la schivata della scelta di difesa, l'intento arriva alla fine di quel battito,
con quelli degli altri). La mano lo ricorda quando si può: `LAZZO / SHIFT+WASD:
LO MOLLI`, e con la scelta di difesa aperta `LAZZO / E, POI WASD: LO MOLLI` (o
`LAZZO / DIFESA`, se la scelta non offre la schivata); a finestra scaduta, da
stordito o con la schivata in ricarica dice invece `LAZZO / IN RECUPERO`,
`LAZZO / STORDITO` o `LAZZO / SCHIVA FRA n`. In volo il nemico non agisce (il
suo Veleno quindi non morde), non entra in pozze, fuochi o scosse e nessuno lo
prende di mira; la sua Bruciatura continua a mordere.

**Upgrade e secondo.** Ogni upgrade dà +1 al primo colpo, fino al livello 5
(`PRIMO COLPO 1 -> 2`); giocato sul secondo, il primo colpo ha +1. La vita
persa a ogni giro resta 1.

**Sul tavolo.** La corda è una striscia di carta in pixel art: due trefoli di
canapa intrecciati fra due linee d'inchiostro, dentro il margine bianco. Durante
il lancio il Viandante si alza nella posa del suo cast, il braccio in su (mai
il salto con la lanterna e la capriola di un colpo), e il cappio aperto vola
dalla sua mano sopra il nemico, gli cade intorno alla vita e si stringe con una
torsione; il cartoncino si solleva e viene tirato su una curva alta fino
all'anello. Poi vola intorno al Viandante, sollevato dal pavimento, dove la
stanza dice che è, con la corda che resta indietro rispetto al giro e si
affloscia quando è lento; sul pavimento un anello di carta tratteggiato mostra
il raggio (senza le caselle solide, con tacche rosse dove sbatterà). Il
Viandante canalizza e si gira a seguirlo finché il giro non supera i 3 giri al
secondo. La spinta interna fa scivolare il nemico senza stelle o numeri di danno.
Ogni colpo sul perimetro fa una stella di carta rossa fra i due cartoncini, `COLPO n`
sopra il colpito e i segnalini di danno, e il colpito scivola via; uno schianto
fa una stella grigia e sbuffi di polvere di pietra al muro (pezzi di carta in
pixel art di [build_attack_props.py](../../tools/art/build_attack_props.py), come la
stella), con `SCHIANTO n`; a ogni giro intero un piccolo `-1` resta dove il
nemico era. Quando la corda lo lascia cade molle e il
cartoncino torna a terra con `MOLLATO` sopra, mentre il tavolo mostra quello che
ha mosso il Viandante (la schivata subito, una spinta quando il colpo del bruto
arriva); fino ad allora resta appeso alla corda tesa. Con un anello largo la
telecamera si allontana un poco e si accosta al Viandante, perché l'anello
intero si veda fra l'HUD e la mano, poi torna dov'era. L'HUD scrive `LAZZO` /
`GIRO n` e `LAZZO: COLPI n / PROSSIMO n / SCHIVA: LO MOLLI` (o, quando una
schivata non si può fare, `IN RECUPERO`, `STORDITO` o `SCHIVA FRA n` in fondo);
mentre gira, come nell'ombra, il riquadro tiene a destra solo `NEMICI n`, perché
le carte non si giocano e la riga ci stia intera anche con la finestra che si
accorcia.

**Il mirino.** Con la carta in mano, tutti i nemici validi hanno un mirino
color canapa, boss e miniboss compresi. L'anello che farebbe si vede
tratteggiato, con le sue caselle (rosse con una croce dove sbatterà, arancio
dove colpirà un nemico) e, per il nemico sotto il mouse, la casella da cui
partirà in verde e una freccia nel verso del giro.

La carta scrive `COLPI 1, 2, 3...` / `-1 VITA A OGNI GIRO` (con sette carte in
mano o più `COLPI 1, 2...` / `-1 VITA A GIRO`); l'ispettore aggiunge
`DENTRO IL RAGGIO: SOLO SPINTA` / `SCHIVA O SPINTA: LO MOLLI`. L'icona, nella
cella 23 dell'atlante (l'ultima della sesta riga,
[build_card_icons.py](../../tools/art/build_card_icons.py)), è un cappio di canapa
intrecciata, aperto, con la corda che scende dal nodo a un rotolo e a un capo
sfilacciato. Nella Prova meccaniche ha i suoi suoni, fatti da codice come gli
altri ([SOUND_SPEC.md](../../tools/audio/SOUND_SPEC.md)): la carta (il rotolo di canapa
sciolto dalla spalla e il cappio fatto girare una volta sopra la testa), il
lancio (il cappio lasciato andare in un fruscio pieno, la corda che scorre nel
guanto e il fischio del cappio che si allontana), la stretta quando il cappio
arriva al nemico (la corda che scorre nel nodo, il cigolio della canapa, la carta
stretta e lo strattone quando il cartoncino si alza), un fruscio a ogni giro che
sale di tono man mano che accelera (fino a otto al secondo), il colpo (due
cartoncini sbattuti insieme), lo schianto sul muro (pietra, sassolini, polvere)
e la corda mollata (la canapa che si allenta e il cartoncino che ricade).

Lo smoke `--smoke-mechanics-lab` lo gioca dalla mano, lo filma
([Verifica e smoke test](../verifica.md#verifica-e-smoke-test)) e ne controlla le regole. A
quattro celle dal muro ovest il raggio è 3, dove una cella più in là sarebbe 4:
il muro sta sulla quarta cella. Il mirino segna i nemici che può prendere e
l'anello, con i tre nemici fermi che ci stanno sopra; il Custode è un bersaglio
valido sia per la regola sia per la carta lasciata su di lui.
Lanciato su un nemico a quattro celle, che viene tirato dentro sull'anello, lo
fa girare mentre il mondo va avanti: colpo 1 sul nemico fermo a nord, spinto di una
cella, colpo 2 su quello a sud, spinto di due, colpo 3 su quello a nord-est,
spinto di tre in diagonale, ognuno ferito del numero del suo colpo e il nemico in
volo con lui; a ogni fotogramma la vita del nemico in volo è quella di partenza
meno i colpi e meno un punto per ogni giro intero, e niente altro. Intanto un
balestriere libero, messo giù dopo le immagini del mirino, prende la mira e tira
al perno: si apre la scelta di difesa, che nessuno sceglie, il colpo arriva e la
corda tiene. Il nemico in volo cade al dodicesimo giro e la corda si affloscia;
l'arena resta in combattimento, perché la stanza della prova non si libera mai.
Accanto al muro ovest il raggio è 1: il nemico sbatte nel muro, ogni schianto
con il suo numero solo su di lui, e a ogni schianto il giro torna indietro.
Intanto la riga dell'HUD sul giro sta intera, misurata con il font del gioco,
con la finestra fissa della prova e con quella che si accorcia del gioco, anche
con due cifre e una stanza piena. Una schivata lo lascia andare: atterra sotto
di sé e annuncia subito un intento nuovo, senza stordimento, e il suo
cartoncino cade con `MOLLATO` mentre la schivata si vede.

### Canna da Pesca

`Canna da Pesca` (non comune, energia 0, **0 s**; compare fra
ricompense e negozio) non si
gioca mai in combattimento: è un attrezzo da fine stanza. Regole in
[fishing.odin](../../src/game/fishing.odin), tavolo in [fishing.odin](../../src/render/fishing.odin).

**Mai in mano.** Quando comincia un combattimento la Canna va subito fra le
esaurite e ci resta: non si pesca, non si scarta, non torna con i rimescolamenti
(le esaurite non si rimescolano mai) e i contatori della mano non la contano.
Resta però una carta del mazzo come le altre: la scheda del personaggio la
mostra, il riposo e il negozio la potenziano, il negozio la può togliere.

**Lo slot.** Liberata la stanza (cade il suo ultimo nemico), in basso a destra,
dove starebbe la carta di una mano, compare lo slot della Canna con `PESCA n/m`
(le pesche che restano alla stanza, sulle sue). Si prende come una carta: la si
trascina su una casella, oppure un clic sulla Canna e poi un clic sulla casella;
`Esc` o il destro la rimettono giù. Mentre è presa il tavolo segna in blu le
caselle che può pescare, più chiare quelle già d'acqua, e in verde (o in rosso)
quella sotto il mouse. L'HUD scrive `CANNA DA PESCA n/m / RAGGIUNGI L'USCITA` e,
finite le pesche, `PESCHE FINITE`.

**La casella.** Una casella entro 3 celle (Chebyshev), in linea di vista, con le
regole della Pozza di Veleno (pavimento libero: niente coperture, oggetti,
nemici, non la propria) e in più, scelte della Canna, mai l'uscita, una
trappola, un bottino per terra, una pozza o un fuoco. Diventa **acqua** finché
non si lascia la stanza: la decalcomania di carta delle pozze, ma blu, con due
anelli di increspature intorno al centro di ogni casella e cerchi di luce che si
allargano. Un'acqua già fatta si pesca di nuovo.

**La pesca.** Circa tre secondi in cui il Viandante è occupato (i tasti premuti
intanto si perdono, come sempre): tira indietro la canna di carta e la lancia,
la lenza vola con il galleggiante sulla casella, che diventa acqua al tonfo; il
galleggiante galleggia finché un pesce abbocca (uno schizzo e un `!` di carta);
il Viandante tira su la canna, la preda esce dall'acqua fra gli spruzzi e gli
vola addosso. Il suo cartoncino si gira verso l'acqua e al lancio si alza nella
posa del suo cast, il braccio in su (mai il salto con la lanterna e la capriola
di un colpo), poi tiene ferma la canna, canalizzando, mentre è la canna a
riavvolgere (nessun chinarsi a raccogliere). L'HUD scrive `PESCA` / `PESCA IN
CORSO`.

**La preda.** Dal flusso proprio della stanza (il suo seme e i dadi della run,
mai l'orologio): **95% cibo** (pesce, mela, pane, formaggio o carne, che dice il
suo nome sopra il Viandante) che cura un **d4** tirato sui dadi della run e
mostrato con il dado 3D come gli altri tiri, fino alla vita massima, con il
segnalino verde `+n`; **5% una carta** del pool delle ricompense tattiche, con i
pesi di rarità del nodo della stanza e mai la Canna, che esce dall'acqua, resta
un momento sopra il Viandante con `CARTA PESCATA / nome` sotto il tavolo ed
entra nel mazzo della run. Con il mazzo pieno (32 carte) la preda è cibo.

**Pesche e upgrade.** Ogni stanza dà 1 pesca più il livello della Canna (fino al
livello 5: 6 pesche), da capo in ogni stanza. Gli upgrade alzano solo le pesche
(`PESCHE 1 -> 2`): la cura resta un d4 a ogni livello, perché la Canna non è
una carta dei dadi.

**Una per run.** Finché il mazzo ne ha una, nessuna offerta ne porta un'altra:
ricompense, negozio, Armeria dimenticata e prede la lasciano fuori. Tolta al
negozio, si può trovare di nuovo.

La carta scrive `1 PESCA A STANZA` (o `n PESCHE A STANZA`) / `CIBO d4 / 5% CARTA`
(su una carta stretta `Canna` / `1 PESCA` / `CIBO d4 O CARTA`, ma lo slot del
canvas del gioco è largo come la carta di una mano di cinque);
l'ispettore aggiunge `SOLO A STANZA LIBERATA` / `MAI IN MANO / UNA PER RUN`.
L'icona, nella cella 24 dell'atlante (la prima della settima riga,
[build_card_icons.py](../../tools/art/build_card_icons.py)), è una canna di legno con
l'impugnatura di sughero e il mulinello d'acciaio, la lenza che scende dalla
punta a un galleggiante rosso e bianco su uno stagno blu. La canna, il
galleggiante, le gocce, il `!` e le prede sono pezzi di carta di
[build_attack_props.py](../../tools/art/build_attack_props.py). Nella Prova meccaniche
ha i suoi suoni, fatti da codice come gli altri
([SOUND_SPEC.md](../../tools/audio/SOUND_SPEC.md)): la carta al lancio (la canna tirata
indietro e frustata in avanti, il mulinello che gira libero mentre la lenza
vola), il tonfo del galleggiante sull'acqua nuova, l'abboccata (il galleggiante
tirato sotto, uno schizzo, la lenza tesa), il mulinello che riavvolge con lo
spruzzo della preda che esce dall'acqua proprio quando si vede, la preda che
arriva nella mano (uno schiaffo bagnato sul guanto) o la carta pescata (la carta
scossa due volte e tre note di cristallo che salgono); il cartoncino del
Viandante non ne aggiunge di suoi (né il colpo di lanterna né le monete del
bottino raccolto).

La si prova con `F7`, che libera l'arena ([Prova meccaniche](../avvio.md#prova-meccaniche)),
e lo smoke `--smoke-mechanics-lab` la gioca, la filma
([Verifica e smoke test](../verifica.md#verifica-e-smoke-test)) e ne controlla le regole: la
Canna presa dallo slot e lasciata su una casella pesca un pesce (il suo d4 fa 3,
3 di vita) e la casella diventa acqua, sul tavolo 3D; la
stanza ha finito la sua pesca. In nessuna pesca il cartoncino del Viandante fa
sentire il colpo di lanterna, le monete del bottino o il cast di una carta. Potenziata a +1, come la potenzierebbero un
riposo o un negozio, `F7` di nuovo dà una stanza nuova senza acqua e con due
pesche (`PESCA 2/2`): dalla prima esce una carta, mai un'altra Canna, che entra
nel mazzo; la seconda, sulla stessa acqua (nessuna casella nuova), tira fuori un
pane che cura il 2 del suo d4. Poi le pesche della stanza sono finite, e un altro
`F7` le ridà tutte e due. Per ultima la regola di una Canna per run: con la
Canna nel mazzo nessuna di 400 offerte, estratte come le estraggono ricompense,
negozio e Armeria dimenticata (`card_offer_exclusions`), ne porta un'altra,
mentre le stesse estrazioni senza di lei ne portano.

### Pinball

`Pinball` (rara, energia 3, **2 s** di finestra; compare fra
ricompense e negozio) trasforma un nemico accanto al Viandante in una
grossa palla d'acciaio e la manda a rimbalzare per la stanza per 20 secondi; poi
la palla scoppia e il nemico cade. Regole in
[pinball.odin](../../src/game/pinball.odin), tavolo in
[pinball.odin](../../src/render/pinball.odin).

**Il colpo.** Il bersaglio è un nemico su una delle otto caselle intorno al
Viandante (diagonali comprese), visibile e in linea di vista: non dietro un
angolo chiuso da due blocchi. Il boss (il Demolitore) e il miniboss (il Custode)
sono troppo pesanti, come per il letale del Dado del Destino,
perché alla fine la palla muore: la carta li rifiuta e la mano scrive
`TROPPO PESANTE PER IL PINBALL`. Una palla alla volta: mentre una rotola, la
carta non prende nessun altro (`UNA PALLA ALLA VOLTA`). Il colpo è il cast della
carta: per i suoi 2 s il mondo è fermo, e la palla con lui. Il nemico diventa la
palla dov'è; i suoi status spariscono nello sbuffo (anche Veleno e Bruciatura:
la palla non ne porta), e con loro le sue reazioni e il suo intento. Il
Viandante la colpisce e la manda via da sé, nella direzione che va da lui al
nemico girata di 15–35 gradi interi a sinistra o a destra, perché non rimbalzi
mai su un asse solo. Il giro lo decide il flusso proprio della stanza
(`Room.pinball_random`, dal suo seme e dai dadi della run quando la stanza
comincia), mai l'orologio.

**La corsa.** La palla rotola sul tavolo a **7 caselle al secondo** per **20
secondi del mondo**: un disco di raggio 0,45 che rimbalza elastico su ogni cosa
solida (un muro, il bordo della stanza, una copertura, un oggetto che blocca il
passo come un barile, un blocco di ghiaccio o una bobina Tesla, che però non
prende mai danni) e su ogni nemico a terra, un respingente rotondo di raggio 0,4
al centro della sua casella. Il moto si risolve da un evento al successivo (un
contatto, il bordo della casella sotto la palla, la fine del suo tempo), mai a
fotogrammi: nessun muro viene attraversato e nessun nemico saltato a qualunque
frame rate, e la stessa stanza dà gli stessi rimbalzi comunque i secondi vengano
divisi in fotogrammi. La palla passa sopra il Viandante senza fargli niente (né
rimbalzo né danno) e sotto il nemico appeso al Lazzo. Un nemico che ci entra con
un passo, una spinta o un arrivo viene colpito subito. Nessuna bobina si posa
dove sta il suo disco; una cosa solida spinta lì comunque viene attraversata
finché il disco non ne esce.

**Il valore.** Parte da **2**. Un nemico toccato prende il valore come danno del
Viandante, con le regole normali (lo Shield lo assorbe, le reazioni rispondono,
la morte lascia il bottino, ma la stanza si libera solo con lo scoppio), e viene
spinto di **una cella** via dalla palla, nella più vicina delle otto direzioni,
con le regole della spinta: un muro, un ostacolo o un corpo lo fermano, e pozze,
fuochi e trappole della casella in cui entra fanno il loro effetto. La palla
rimbalza su di lui come su un respingente e il valore sale di uno: 2, 3, 4... Un
colpo per contatto: lo stesso nemico si colpisce di nuovo solo dopo che la palla
se n'è staccata. Ogni tocco di un muro o di un'altra cosa solida riporta il
valore a 2 (al valore della carta).

**La palla fuori dal mondo.** Per i suoi 20 secondi la palla è il nemico stesso,
ma fuori dal gioco: non occupa una casella, non agisce, non annuncia niente, non
porta status e niente la raggiunge: né danni, né status, né spinte, né carte
(aree, catene e Toxic Wave comprese), né le frecce di Feretro, le pozze, i
fuochi, le trappole, le esplosioni, le scariche Tesla o la protezione del
Custode. Il mondo intanto va avanti e il Viandante agisce liberamente (passi,
urti, carte, frecce); solo ciò che ferma il mondo (un cast, la scelta di difesa,
i dadi a tutto schermo, l'ombra di Movimento Ombra, la pausa) ferma anche la
palla. La stanza non si libera prima dello scoppio, perché la palla conta fra i
nemici; se cade il Viandante, la palla si ferma con il combattimento.

**Lo scoppio.** Finiti i 20 secondi la palla scoppia e il nemico cade dove si
trova: un'uccisione normale del Viandante (nemmeno uno Shield lo salva), con il
suo bottino lì e la stanza liberata se era l'ultimo.

**Upgrade e secondo.** Ogni upgrade dà +1 al valore di partenza, che è anche
quello a cui la riportano i muri, fino al livello 5 (`VALORE 2 -> 3`); giocata
sul secondo, +1 anche lei.

**Sul tavolo.** La palla è pixel art d'acciaio dipinta da codice, larga 1,2
caselle: una sfera in sei toni che riflette la stanza (la luce in alto,
l'orizzonte chiaro, il pavimento scuro in basso), il suo riflesso bianco, una
fascia del colore del nemico perché si sappia chi era (rossa per il ghoul,
azzurra per il balestriere, arancio per il bruto, viola per il bombarolo), la
linea d'inchiostro e il margine bianco di carta dei cartoncini con il suo
taglio. Durante il cast il cartoncino del nemico svanisce in uno sbuffo di carta
e la palla si gonfia oltre la sua misura e si assesta; il cartoncino del
Viandante tira il colpo con la sua lanterna (o con l'arma M8 che ha in mano) e
lo fa arrivare sulla palla proprio quando il cast finisce e la palla parte, con
una stella d'oro. Poi il tavolo la mostra dove la stanza dice che è, a ogni
fotogramma, con la fascia che gira con la corsa e un'ombra tonda e morbida
sotto. A ogni muro una stella grigia e uno sbuffo di polvere di pietra, a ogni
nemico una stella rossa fra la palla e il cartoncino e `COLPO n` sopra di lui.
Allo scoppio la palla si gonfia con un lampo bianco e si apre in carta e
coriandoli del suo colore, con `POP!` sopra la sua cima gonfia (il lampo e la
carta restano in vista); il cartoncino del nemico non torna più, nemmeno a
cadere. La telecamera resta sul Viandante, non segue la palla. Dietro gli occhi del
Viandante ([First Person Shooter](#first-person-shooter)) la palla sbiadisce
quando gli rotola addosso, e all'altezza degli occhi sparisce.

**Il mirino.** Con la carta in mano i nemici che può prendere hanno un mirino
d'acciaio, il boss e il miniboss in portata un mirino rosso e `TROPPO PESANTE`
sotto i piedi, lontano dai cuori dei vicini; per il
nemico sotto il mouse il tavolo traccia la partenza della palla (trattini di
carta sull'inchiostro, fino a dove il disco toccherebbe la prima cosa solida,
quattro caselle al massimo, e una punta), già girata come la girerà il flusso
della stanza.

**L'HUD.** Mentre la palla rotola l'HUD ha un chip d'acciaio subito dopo Veleno
e Bruciatura del Viandante: `PINBALL 14s x5`, i secondi che restano e il valore
(con poco spazio `PIN 14s x5`).

La carta scrive `COLPI 2, 3, 4...` / `MURO: TORNA A 2 / 20s` (con sette carte in
mano o più `COLPI 2, 3...` / `MURO: 2 / 20s`);
l'ispettore aggiunge `BOSS E MINIBOSS: TROPPO PESANTI` /
`DOPO 20s SCOPPIA E CADE`. L'icona, nella cella 25 dell'atlante (la seconda
della settima riga, [build_card_icons.py](../../tools/art/build_card_icons.py)), è una
palla cromata illuminata dall'alto a sinistra che colpisce un respingente (un
cappello rosso con un riflesso chiaro in cima, in un anello d'oro), con una
scintilla fra i due. Nella Prova meccaniche ha i suoi suoni, fatti da codice
come gli altri ([SOUND_SPEC.md](../../tools/audio/SOUND_SPEC.md)): la carta (uno
stantuffo tirato indietro, la molla che sale di tono e il cricchetto sempre più
fitto, fermato a fondo corsa; poi il cartoncino del nemico appallottolato come
un foglio e la palla che cade intera, un tintinnio d'acciaio), il colpo che la
manda via (ferro sull'acciaio, la palla che risuona, un fruscio che si
allontana), il tocco di un muro (un piccolo toc d'acciaio sulla pietra, breve,
anche più volte al secondo), il respingente di un nemico (un bong cavo, la carta
schiaffeggiata e lo squillo del respingente, sempre più acuto man mano che il
valore sale) e lo scoppio (un palloncino di carta, coriandoli che cadono, un
ultimo tintinnio). Finché è la palla il nemico non fa sentire niente di suo, e
il colpo del Viandante non aggiunge quello della lanterna.

Lo smoke `--smoke-mechanics-lab` la gioca dalla mano, la filma
([Verifica e smoke test](../verifica.md#verifica-e-smoke-test)) e ne controlla le regole. Il
Viandante sta al centro di un'arena nuova con un balestriere avvelenato accanto
a est, il Custode accanto a sud-ovest, un bruto a due celle e altri nemici
fermi; il flusso della stanza è fissato su un giro di 30 gradi a sinistra, e tre
ghoul fermi stanno sulla strada della palla. Per la corsa la telecamera si
allontana, perché la fila e il muro nord restino in vista, e per lo scoppio
ancora di più. Il mirino segna il balestriere e la sua partenza; sul Custode
scrive `TROPPO PESANTE` e né la regola né la carta lasciata su di lui lo
prendono, e il bruto a due celle è fuori portata. Il colpo costa 3 di energia,
toglie il Veleno al balestriere e tiene fermi il mondo e la palla per tutto il
cast; la palla parte nella direzione dal Viandante al balestriere girata di 30
gradi, e la lanterna la raggiunge entro un fotogramma e mezzo dalla fine del
cast. Poi la palla prende i tre ghoul uno dopo l'altro per 2, 3 e 4, ognuno
spinto di una cella via da lei, e il muro nord riporta 5 a 2. Per tutti i 20
secondi ogni nemico toccato prende il valore di quel momento, uno in più del
precedente, ogni cosa solida lo riporta a 2, ogni spinta è di una cella via
dalla palla e per ogni contatto il tavolo mostra la sua stella; la vita di ogni
nemico colpito scende di quanto ha preso, e niente altro. A ogni fotogramma il
disco della palla resta fuori da ogni casella solida, la sua direzione resta
unitaria e la vita del balestriere non cambia; un colpo, uno status, una freccia
o una carta su di lui vengono rifiutati. La palla rotola sopra il Viandante
senza fargli niente, lui fa un passo mentre lei rotola e il mondo batte un
secondo dopo l'altro. Il chip dell'HUD sta intero accanto ai morsi e alle
cariche, anche con un valore di due cifre. Scoppia nel fotogramma che porta la
palla ai suoi 20 secondi, dopo una ventina di battiti del mondo: il balestriere
cade sulla casella della palla con il suo bottino, senza che il suo cartoncino
ricompaia, e l'arena resta in combattimento.

### First Person Shooter

`First Person Shooter` (rara, energia 3, **0 s** di finestra;
compare fra ricompense e negozio) mette il Viandante dietro i suoi
occhi per **20 secondi del mondo**, con un AK di carta. Si gioca su di sé, con
il suo tasto o con un secondo clic sulla carta, a finestra aperta o da storditi,
ma non con la scelta di difesa aperta, con un nemico appeso al Lazzo o dentro
un'altra prima persona. Non ha cast: la carta di rimpiazzo arriva subito e la
finestra non perde niente. Regole in
[first_person.odin](../../src/game/first_person.odin), tavolo in
[first_person.odin](../../src/render/first_person.odin), mouse e tasti in
[first_person_input.odin](../../src/run/first_person_input.odin).

**La vista.** Mentre la carta si mostra, la telecamera scende dalla vista del
tavolo negli occhi del Viandante, nella sua casella, a 1,05 sopra il pavimento,
con un campo visivo di 70 gradi: guarda dove guarda lui se è entro 50 gradi da
dove guardava la telecamera, altrimenti lungo la direzione della griglia più
vicina a quello sguardo. Da lì la stanza è il tavolo 3D: nemici e oggetti sono i
soliti cartoncini e pezzi di carta, girati verso di lui. Il suo cartoncino
svanisce quando la telecamera lo raggiunge, i muri interni diventano interi e
opachi, quelli del bordo non si abbassano più verso la telecamera, e cuori,
sigilli e scritte restano solo sui nemici che l'occhio vede (mai dietro un
muro). Finiti i secondi, quando il combattimento finisce o se il
Viandante cade, la telecamera risale com'era scesa, in 0,6 s.

**Il mouse.** Il cursore sparisce ed è catturato: il mouse gira la vista (a
destra gira a destra, in su guarda in su), libera intorno e fino a 0,55 radianti
in su e in giù, con la sensibilità del mouse delle impostazioni. `P`, e qui
anche `Esc`, mettono in pausa e liberano il mouse; lo liberano anche la perdita
del focus, una finestra sopra il tavolo e la fine della vista. Un clic fatto
prima (quello che riprende dalla pausa, il doppio clic della carta) non spara
finché non lo si rilascia, come nella prova FPS di Cripta delle Rune, da cui
vengono anche la cattura e la sensibilità.

**L'AK.** In basso a destra c'è l'AK di carta del riferimento grafico fornito:
caricatore curvo, calcio e impugnatura in legno arancio, acciaio blu e bordo
avorio spesso. Non compaiono braccia, mani o maniche. La canna converge verso
il centro; caricatore e calcio proseguono oltre i bordi inferiore e destro.
La stampa PNG trasparente è incorporata nel gioco; risoluzione dell'immagine
e ingombro sullo schermo sono indipendenti. Provenienza e prompt sono in
`assets/gothic/first-person-ak.md`.
Entrata, rinculo, fiammata e origine del tracciante condividono la stessa
posizione della bocca; il mirino rimane libero al centro. Tenendo premuto il
tasto sinistro spara **6 colpi al secondo** da **1 danno**, senza munizioni e senza tempo di finestra. Ogni colpo segue la linea
del mirino dall'occhio, casella per casella, e il primo nemico che incontra lo
prende: un attacco normale del Viandante (lo Shield lo assorbe, le reazioni
rispondono, la morte lascia il bottino e può liberare la stanza). Un muro, il
bordo della stanza, una copertura o un oggetto che blocca il passo lo fermano,
qualunque sia la loro altezza, e così un angolo chiuso da due blocchi; il
pavimento lo ferma dove la linea lo raggiunge, e una casella fuori vista lo
perde. Ogni nemico è il suo cartoncino, girato verso l'occhio: il colpo lo
prende dovunque la linea ne incontri la carta, bordo bianco compreso, larga a
ogni altezza quanto la carta del cartoncino vivo (gli artigli larghi, la testa
più stretta), anche dove sporge sulla casella accanto a quella che la linea
attraversa; accanto alla carta e sopra la sua cima il colpo passa e va avanti.
La linea parte dall'occhio dove la vista lo mostra, anche mentre scivola da una
casella all'altra, e trova i cartoncini dove il tavolo li mostra, anche mentre
scivolano verso la casella nuova o saltano: il colpo va dove il mirino stava
sopra quello che si vedeva, e il mirino si scalda solo lì. Il nemico appeso al
Lazzo e la palla del [Pinball](#pinball) non sono corpi per i colpi; gli oggetti
non si danneggiano. Un colpo non è un'azione del Viandante: il suo Veleno non
morde e il suo cartoncino non colpisce. Il grilletto spara un colpo ogni sesto
di secondo e da un fotogramma all'altro porta al più il ritardo di un colpo,
quindi sono 6 al secondo a qualunque frame rate; i colpi aspettano mentre si
risolve un battito, mentre è aperta la scelta di difesa e durante un cast.

**I passi.** `W`, `A`, `S` e `D` fanno un passo di una casella secondo la vista:
`W` avanti (lungo la direzione della griglia più vicina alla vista), `S`
indietro, `A` a sinistra e `D` a destra, ognuno con le regole e il tempo di un
passo normale (contro un nemico è l'urto: si vede dove colpisce, sulla carta del
nemico, perché la lanterna svanisce con il cartoncino del Viandante e non passa
davanti agli occhi), e l'occhio scivola da una casella all'altra. Anche la
schivata (`Shift` + `WASD`) e l'atterraggio della schivata di difesa seguono la
vista; i tasti delle diagonali (`Q`, `E`, `Z`, `C`) tacciono, `Spazio` aspetta.

**Niente carte.** Per tutti quei secondi la mano scivola sotto il bordo dello
schermo e nessuna carta si gioca, nemmeno con i tasti; niente frecce di Feretro,
Refocus, abilità, 6 RANCH 7 o Movimento Ombra, e niente mappa (`Tab` e il
pulsante tacciono), e il puntatore non arriva a nessun pulsante: solo l'AK. Il
resto va avanti come sempre: l'orologio della finestra, gli intenti e i colpi
dei nemici con la loro scelta di difesa, i morsi della Bruciatura, i fuochi.

**Il tavolo e l'HUD.** Ogni colpo vola come un tracciante di carta dalla bocca
dell'AK fino a dove si ferma e lì fa una scintilla: una stella rossa su un
nemico, una stella d'oro e schegge di pietra su una cosa solida (sul corpo che
l'ha fermato, anche se basso), polvere sul pavimento. L'AK rincula a ogni colpo
con una fiammata alla bocca, in due disegni che si alternano; il mirino si
scalda sopra un nemico e ne segna gli angoli quando un colpo va a segno. Le
ferite dell'AK non fanno animare né il Viandante né il colpito e lasciano
piccoli segnalini di danno. In basso a sinistra, dove stava la mano, un riquadro
conta i secondi (`FPS 12s`, rosso negli ultimi 3); la riga di stato dice
`MIRA COL MOUSE / CLIC: SPARA / WASD: PASSI`, i pulsanti della mappa e del
personaggio sono spenti (il puntatore è della vista) e, a ogni ferita (un colpo
nemico, un morso della Bruciatura o del suo Veleno), i bordi dello schermo
lampeggiano di rosso e la vista trema un poco. Vita e finestra restano al loro
posto nell'HUD.

**Upgrade e secondo.** Ogni upgrade dà +2 s, fino al livello 5 (30 s,
`SECONDI 20 -> 22`); giocata sul secondo, +2 s anche lei.

La carta scrive `PRIMA PERSONA 20s` / `AK: 6 COLPI/s, 1 DANNO` (con sette carte
in mano o più `FPS` / `FPS 20s` / `AK: 6 COLPI/s`); l'ispettore aggiunge `NIENTE CARTE: SOLO L'AK` /
`WASD SECONDO LA VISTA`. L'icona, nella cella 26 dell'atlante (la terza della
settima riga, [build_card_icons.py](../../tools/art/build_card_icons.py)), è un AK di
profilo (calcio, impugnatura e paramano di legno, castello d'acciaio e
caricatore a banana) con la fiammata alla bocca e tre bossoli d'ottone che
volano via, dentro l'anello rosso di un mirino. Nella Prova meccaniche ha i suoi
suoni, fatti da codice come gli altri
([SOUND_SPEC.md](../../tools/audio/SOUND_SPEC.md)): la carta (l'AK preparato: il
caricatore inserito, la leva d'armamento tirata indietro e lasciata andare), la
discesa negli occhi (la stanza che arriva in un soffio, il cappuccio che si
chiude intorno alla vista con un tonfo morbido) e la risalita, ogni colpo (breve
e secco: lo schiocco della bocca, la carta del fucile, l'otturatore), il colpo
che ferisce (il cartoncino bucato, un tonfo sordo) e quello che si ferma sulla
pietra (una scheggia e il fischio del rimbalzo); il colpito non aggiunge la sua
ferita.

Lo smoke `--smoke-mechanics-lab` la gioca dalla mano, la filma
([Verifica e smoke test](../verifica.md#verifica-e-smoke-test)) e ne controlla le regole. Le
sue parole stanno sulla carta della mano a ogni livello, e anche su quelle più
larghe del gioco (mani da cinque e da sei, negozio, ricompense), dove il nome è
`FPS`. Giocata su di sé costa 3 di energia e nessun secondo di finestra, dura 20
secondi e non ha cast; una carta, un Refocus e una freccia vengono rifiutati. La
telecamera arriva negli occhi, il cartoncino del Viandante sparisce, la mano
scivola via e la discesa suona. Un secondo di grilletto tenuto, a 60 fotogrammi
al secondo, spara 6 colpi nel ghoul tre celle a nord, ognuno da un punto (il suo
cuore va da 40 a 34); in quei 72 fotogrammi la finestra e i secondi della vista
calano di 1,2 s e non di più, il Veleno del Viandante non morde e lui non perde
vita; suonano 6 colpi, né la lanterna né la ferita del ghoul. A ovest un blocco
di ghiaccio ferma un colpo e il balestriere dietro resta intatto; a sud il muro
del bordo ne ferma un altro. Con la vista a est `W`, `D`, `S` e `A` vanno a est,
sud, ovest e nord, e l'occhio scivola solo in avanti fino al centro della
casella; `W` contro un nemico è un urto e `Shift` con `D` schiva di due celle a
sud. Il colpo di un ghoul libero apre la scelta di difesa dietro gli occhi, con
i secondi della vista fermi come quelli del mondo, e `E` poi `A` schiva a nord,
la sinistra della vista; un colpo lasciato passare fa lampeggiare i bordi di
rosso. Nel recupero dopo la fine della finestra l'AK spara ancora. Finiti i 20
secondi, dopo una ventina di battiti del mondo, la vista finisce, la telecamera
risale con il suo suono e il mouse torna libero. Una copia +5 dura 30 secondi. Il
riquadro dei secondi e la riga dell'HUD ci stanno interi.

### Inondazione

`Inondazione` (non comune, energia 2, **2 s** di finestra, fino a tre
potenziamenti; compare fra ricompense e negozio) lancia un'onda che attraversa
tutta la mappa e sposta ogni nemico. Regole in
[flood.odin](../../src/game/flood.odin), onda in
[flood.odin](../../src/render/flood.odin).

**La direzione.** Si trascina la carta su una casella intorno al Viandante, da 1 a
3 celle di Chebyshev (la sua stessa casella non vale): l'onda va nel verso
dell'asse principale dal Viandante a quella casella, una delle quattro
direzioni, e in parità lungo la riga (est o ovest). Parte dal muro dietro di
sé, a metà del lato opposto, e corre fino al muro davanti, dove finisce: la
mappa intera, vista o no.

**L'effetto.** Tutto si risolve in una sola giocata, nell'ordine in cui il fronte
raggiunge le file dei nemici dalla parte lontana: la testa di una fila si
sposta per prima, così una fila con spazio davanti si sposta insieme. Prima si
spengono **tutti i fuochi** (gli Incendi del Viandante e gli oggetti Fuoco della
stanza), così nessun nemico finisce in una fiamma. Poi ogni nemico a terra viene
spinto di **1 casella** (+1 per upgrade, +1 sul colpo a tempo; fino a 4) nel
verso dell'onda, una sola volta, con le regole di spinta del gioco: un muro, una
copertura, un oggetto che blocca o un corpo (il Viandante compreso) fermano la
spinta prima, e su ogni casella in cui entra agiscono pozze, trappole e pericoli
(un nemico può morire così). L'onda non fa danni, non sposta il Viandante né gli
oggetti, e non tocca il nemico appeso al Lazzo né la palla del Pinball.

**Sul tavolo.** Un muro d'acqua a blocchi semitrasparenti, con la schiuma in cima,
attraversa la stanza in circa 1,9 secondi del cast, mentre il mondo è fermo: ogni
nemico parte spinto nel momento in cui il fronte lo raggiunge, e dove passa
sopra un fuoco sale un po' di vapore. Nella Prova meccaniche suonano la carta,
l'onda, ogni nemico bagnato e ogni fuoco spento. Il film di Mostra effetto
mostra tre nemici (uno contro il muro) e due fuochi.

### Bomb Marley

`Bomb Marley` (rara, energia 3, **2 s** di finestra, fino a cinque potenziamenti;
compare fra ricompense e negozio) apre una festa nella stanza: dal soffitto
scende una sfera da discoteca che illumina alcune caselle, e Bomb Marley lancia
bombe a ritmo lungo colonne intere. Chi sta su una casella illuminata è salvo.
Regole in [marley.odin](../../src/game/marley.odin), tavolo in
[marley.odin](../../src/render/marley.odin).

**Bomb Marley non è un nemico.** Non è un'entità della stanza: non ha casella,
vita né ID, quindi nessuna carta, colpo, freccia o palla lo raggiunge e nessun
nemico lo ha come bersaglio. Sta dietro il muro nord e lancia.

**Il ritmo.** La festa dura **35 secondi del mondo** e va a battiti di un
secondo, quindi il cast, i dadi, una difesa, Movimento Ombra e la pausa la fermano
come fermano il mondo. Ogni battito:

- le colonne annunciate **due battiti prima** cadono: la bomba attraversa tutta la
  colonna, sopra muri e coperture, e ogni personaggio (il Viandante e i nemici,
  boss e miniboss compresi) che non sta su una casella illuminata prende **6
  danni** (+1 per upgrade; lo Scudo li assorbe; niente scelta di difesa, Deflect non
  li rimanda); chi sta su una luce è salvo (`SALVO`); un barile nella colonna si
  accende; nell'ombra di Movimento Ombra il Viandante non li subisce. Ogni nemico
  ucciso da una bomba aggiunge **5 secondi** alla festa, **90 in tutto** al massimo
  (anche se l'ha spinto lì il Viandante);
- il tempo cala di un secondo; alla fine, con il combattimento o con la morte del
  Viandante, la festa finisce;
- le **luci** si spostano ogni 5 battiti, e le prossime si vedono 2 battiti prima
  (solo i bordi, lampeggianti). Sono tante quanti i personaggi in gioco meno 2,
  una meno ogni 10 secondi, mai meno di una e mai più di 16, così che non tutti
  possano salvarsi; una è sempre entro 3 caselle dal Viandante; le nuove luci cadono
  di preferenza dove non sta nessuno;
- vengono annunciate **nuove colonne**: poche all'inizio (una ogni due secondi), poi
  una, due e tre al secondo ogni 10 secondi, in proporzione per una stanza più
  larga di 17 caselle; metà sono la colonna di un personaggio.

Le luci e le colonne nascono dal solo flusso della stanza (`Room.marley_random`),
mai dall'orologio. Una sola festa alla volta: mentre suona, la carta viene
rifiutata. Il colpo a tempo aggiunge 5 secondi.

**I nemici.** Una colonna annunciata è una zona di pericolo, come lo scoppio di
una bomba: i nemici ne escono e non la attraversano se c'è un'altra strada. Un
nemico fuori dalle luci e non accanto al Viandante muove verso la luce libera più
vicina entro 3 celle. First Person Shooter si può giocare durante la festa e la vista
negli occhi mostra le stesse luci e colonne.

**Sul tavolo.** La sfera a specchietti scende in un secondo sopra il Viandante e ruota;
i fasci colorati (magenta, ciano, oro, verde, arancio) vanno dalla sfera alle caselle
salve, dove ci sono macchie di luce e un bordo d'oro; puntini di riflesso girano sul
pavimento. Le luci e le colonne si vedono anche nella nebbia (sopra i blocchi
della nebbia). Le colonne annunciate sono rosse, più accese e lampeggianti
all'ultimo battito, con una freccia che scende. La bomba rotola lungo la colonna
(mezzo secondo), lascia un lampo su ogni casella (verde dove si è salvi) e i
danni arrivano dopo. Bomb Marley è un cartoncino originale: una bomba con un berretto
rosso, oro e verde, occhiali scuri e dreadlock di miccia, che balla a tempo sul
muro nord sopra la colonna che sta per bombardare. L'HUD mostra `MARLEY 23s` fra i
chip. Nella Prova meccaniche suonano la carta, la sfera, le luci, l'avviso, la
bomba e il suo scoppio, la salvezza, i secondi guadagnati, la fine e un
groove reggae a 60 BPM (un battito `a`, uno `b`).

**Mostra effetto.** Il film mostra la carta sopra una stanza di prova con le luci e
la prima colonna fissate: due nemici in una colonna, uno in una luce e uno no. La
bomba salva il primo, ferisce il secondo e il film finisce pochi secondi dopo,
molto prima dei 35 secondi della festa.
