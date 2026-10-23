[← Odin PP](../README.md)

### Luce della portata delle carte

Selezionando una carta, la portata illumina le superfici del pavimento in blu:
la resina conserva ombre, incisioni e fughe. Un bordo continuo delimita il
perimetro, con un alone sfumato verso l’interno e una pulsazione lenta.
L’area interessata dal puntatore è ambra; il bersaglio e la destinazione di
movimento hanno angoli luminosi color menta. Rosso indica una giocata non
valida o un percorso bloccato. Senza energia la portata si attenua e il
bersaglio diventa rosso.

La luce viene disegnata in 3D prima delle minacce sul terreno e degli sprite,
con test di profondità: non attraversa gli ostacoli. Le guide specifiche di
Lazzo, Pinball e terreno restano disponibili. La fog segue solo la visibilità
attuale; cambiando carta, muovendosi o terminando il combattimento non rimane
illuminazione della selezione precedente.

[card_range_light.odin](../src/render/card_range_light.odin) prepara una sola
maschera locale per frame, usando il targeting condiviso e limitando la ricerca
al range massimo della carta. Materiale e alone riusano quella maschera;
il falloff usa alpha ai vertici, senza nuovi shader, texture o render target.

### Altezze del tabellone

Una cella con altezza sta sul suo piano rialzato: ogni gradino è alto 0,12 di cella
(`game.HEIGHT_STEP_DRAWN`). Il pavimento ha una colonna scura fino al piano del
tabellone e una linea sottile a ogni gradino sui lati che guardano una cella più
bassa, così un dirupo di dieci gradini si legge come dieci e una scala come
scalini. Personaggi, piedistalli, ombre, oggetti, anteprima del raggio, segni dei
bersagli, intenti e rombi del puntatore stanno alla quota della loro cella; mentre
un personaggio scivola da una cella all'altra sale il gradino in modo morbido
(`point_ground`, media pesata delle quattro celle intorno al punto). La telecamera
segue la quota del giocatore. Il puntatore sceglie la prima cella la cui cima sta
sopra il raggio (`pick_ground_cell`): la cima di un altopiano o la faccia di un
dirupo, non il pavimento dietro. Le quote vengono da una copia delle altezze
del livello, aggiornata quando la geometria cambia, mai da un puntatore al livello
([height_view.odin](../src/render/height_view.odin)). Solo il laboratorio ha altezze;
le spedizioni restano piatte (Fase 3).

### Bersagli in evidenza

Mentre si sceglie una carta, ogni nemico che una giocata valida colpirebbe
davvero ha la casella accesa in modo molto visibile: nucleo quasi bianco che
pulsa, contorno d'inchiostro, quattro angoli che respirano e un alone saturo.
Un fascio di luce con una colonna di scintille sale dalla casella fino al petto
del nemico, davanti al suo sprite. Quando il puntatore sta su una casella la cui
giocata colpirebbe quel nemico, gli angoli si chiudono e un anello si apre una
volta; gli altri bersagli restano nello stato «colpibile».

- **Colore.** Quattro tinte sono già del raggio (blu, ambra, menta, rosso) e le
  tinte dei biomi coprono quasi tutta la ruota, quindi nessun colore fisso si
  legge ovunque. Il segno è quindi bianco con contorno scuro (luminosità e
  forma), con alone **viola elettrico**, o **verde acido** nello Spazio, dove il
  viola è la tinta del bioma. Un test tiene l'alone ad almeno 40° di tinta da
  tutti gli altri colori, in ogni bioma e nel laboratorio.
- **Quali nemici.** Quelli che il piano degli effetti nomina (danno, spinta,
  stato): lo Scatto elenca i nemici sulla sua linea ma non ne colpisce nessuno,
  e quindi non ne segna. Le carte con esito casuale (le colonne di Bomb Marley,
  il dado del Dinosauro) e quelle che colpiscono più tardi (ordigni posati) non
  segnano nessuno. Eccezioni calcolate a parte: l'Inondazione segna tutti i
  nemici in gioco, il Cannone quelli sulla sua linea, il Buco Nero quelli nel
  suo 3×3 (sotto il puntatore).
- **Fuori vista.** Nemici fuori gioco, nella nebbia o dietro un muro (per le
  carte con linea di vista) non sono segnati.
- **Solo passaggio del mouse.** Con una carta sotto il mouse nella mano ma non
  scelta, raggio e bersagli compaiono più tenui (metà intensità) e la casella
  sotto il puntatore non viene valutata.
- **Lazzo e Pinball.** Usano questo segno: i vecchi mirini sui bersagli validi
  sono tolti. Restano l'anello e la freccia del Lazzo, la linea del Pinball e il
  mirino rosso «troppo pesante».

[card_hit_mark.odin](../src/render/card_hit_mark.odin) disegna il segno nel
passaggio 3D della luce del raggio (cella, angoli, anello) e le scintille dopo
gli sprite. Il calcolo è in `game.card_hit_enemies`, che usa lo stesso piano
degli effetti della giocata. L'animazione usa l'orologio degli sprite, non
quello del mondo, perché è proprio quando il mondo è fermo che si sceglie.

### Mostra effetto

Ovunque si guardi una carta, **MOSTRA EFFETTO** apre sopra la run una finestra
che la mostra al lavoro: un piccolo film in cui un guanto di carta la prende da
una piccola mano, la gioca sul suo bersaglio e una stanza di prova la risolve
con le regole vere del gioco. Ogni carta ha il suo film, a ogni livello, e così
ogni carta che verrà aggiunta. Finestra in
[effect_window.odin](../src/run/effect_window.odin), film in
[card_demo.odin](../src/run/card_demo.odin), scene in
[card_demo.odin](../src/game/card_demo.odin), guanto e didascalie in
[card_demo.odin](../src/render/card_demo.odin), pulsanti delle schermate in
[effect_entries.odin](../src/render/effect_entries.odin).

**Dove si apre.** I pulsanti hanno lo stile gotico dell'HUD e non stanno mai
sopra una carta (nemmeno quella che si alza sotto il mouse), un prezzo, una
scritta o un altro comando: un clic su di loro non sceglie, non compra e non
gira pagina.

- **L'ispettore della carta**, in combattimento. Con il mouse su una carta della
  mano l'ispettore aggiunge in fondo una riga spenta, `I` `MOSTRA EFFETTO`: lì
  un clic prenderebbe la carta, quindi basta il tasto `I`. Scelta la carta (un
  clic, o il suo numero se ha un bersaglio), l'ispettore resta anche quando il
  mouse se ne va e la riga diventa un pulsante, che si clicca senza giocare,
  mirare o muovere niente; `I` vale ancora. Pulsante e tasto tacciono mentre il
  tavolo è occupato (una difesa, un cast, [Movimento Ombra](regole/meccaniche.md#movimento-ombra),
  un'azione o una pesca che si stanno ancora mostrando), e intanto il pulsante
  resta spento, come **PERSONAGGIO**; non c'è mentre la carta è trascinata né
  dietro gli occhi di [First Person Shooter](regole/meccaniche.md#first-person-shooter).
- **Lo slot della [Canna da Pesca](regole/meccaniche.md#canna-da-pesca)**, a stanza liberata: lo
  stesso ispettore, con il mouse sulla Canna o con la Canna scelta.
- **La scheda del personaggio** (**PERSONAGGIO**). Il riquadro **MAZZO** elenca
  il mazzo della run, una riga per carta e livello, nell'ordine in cui il mazzo
  li tiene la prima volta (`2x Strike`, `1x Pinball +2`): cinque righe, oppure
  quattro per pagina con `<`, `n/m` e `>` in fondo quando non ci stanno tutte.
  Un clic sceglie una riga (girare pagina sceglie la prima della pagina), e
  `I` `MOSTRA EFFETTO`, nella testa del riquadro, o il tasto `I` mostrano quella
  scelta. La finestra si apre sopra la scheda: `Esc` chiude la finestra e lascia
  aperta la scheda.
- **La ricompensa**: un pulsante sotto ogni carta offerta; `I` mostra quella
  sotto il mouse.
- **Il negozio**: un pulsante sotto il prezzo di ogni offerta, e
  `I  MOSTRA EFFETTO` nella riga dei comandi, a sinistra dell'upgrade, per la
  carta posseduta scelta per l'upgrade o la rimozione; `I` mostra l'offerta
  sotto il mouse, altrimenti la carta scelta.
- **Il riposo**: lo stesso `I  MOSTRA EFFETTO`, per la carta scelta per
  l'upgrade, finché il riposo non è risolto; anche qui `I`.

Le carte offerte si vedono come sono offerte, al livello 0; quelle del mazzo
come il mazzo le tiene, con il loro upgrade. La testa della finestra scrive il
nome della carta con il suo `+n` e
`MOSTRA EFFETTO / LE REGOLE DEL GIOCO IN UNA STANZA DI PROVA / TEMPO SOSPESO`.

**I comandi.** `Esc`, un clic destro o **CHIUDI** (in alto a destra, con il suo
`ESC`) chiudono la finestra; `R` o **RICOMINCIA** fanno ripartire il film dal
primo fotogramma. Un clic altrove, sul film compreso, non fa niente: il film non
si comanda, si guarda. Senza il focus la finestra non risponde e il film resta
fermo dov'è. `F1`–`F3`, `F9` e `F11` valgono anche a finestra aperta (il film
segue la scala); gli altri tasti della run, come `F5` e `F10`, aspettano che si
chiuda.

**La run ferma.** La finestra non è una scena dell'host ([Scene](engine.md#scene)) ma un
modale dentro la run: niente dissolvenza, niente `resume`. Finché è aperta,
`roguelike_update` le dà tutto il fotogramma, subito dopo il controllo del
focus: alla run non arriva nessun tasto né clic e non scorre nessuno dei suoi
orologi (la finestra del pulse e il mondo, la timeline, gli arrivi della Prova,
i cartoncini), quindi niente di quello che la run possiede cambia; sotto un velo
scuro resta la run com'era nell'ultimo fotogramma disegnato. Aprendosi, la
finestra fa lasciare alla run quello che teneva, come quando la finestra del
gioco perde il focus (`roguelike_suspend_input`: la carta presa o scelta, il
passo in attesa della diagonale, il trascinamento della camera, il mouse dietro
gli occhi); chiudendosi, la run riprende come al ritorno del focus: il primo
fotogramma legge i tasti come sono e non conta tempo, quindi né il clic che l'ha
chiusa né un tasto di quel fotogramma arrivano al tavolo. Non si apre mentre il
tavolo è occupato (`effect_window_refusal`): in pausa, con la mappa olografica,
con 6 RANCH 7 o il ring (anche quando un quadrato di Tesla sta per aprirlo),
durante la scelta di difesa, un cast o i dadi, dietro gli occhi di First Person
Shooter (anche mentre la vista scende o risale), in Movimento Ombra e finché il
tavolo mostra ancora un'azione. Ricompensa, negozio e riposo non mostrano il
tavolo: lì si apre sempre, qualunque cosa abbia lasciato la stanza.

**Le regole vere in una stanza di prova.** Il film non è un'animazione fatta a
mano. Ogni ripresa costruisce una stanza tattica sua (`create_card_demo_room`):
11x9 caselle muri compresi, il Viandante al centro con 22 di vita massima e 3 di
energia, la carta sola in mano (o la Canna nel mazzo), le regole del gioco con
le azioni a tempo, una finestra che non si accorcia, niente nebbia e quello che
la scena chiede. La carta si gioca come la gioca la mano, per le sue stesse
strade: un trascinamento lasciato sul bersaglio (`card_drop_target`), un clic e
un secondo clic per le carte senza bersaglio, lo slot della Canna con
`poll_fishing_command`. Poi la stanza va avanti solo con il proprio
`step_tactical_controller`, il controller del gioco, e le azioni della scena (un
passo, una freccia, ATTIVA, il grilletto dell'AK) passano dagli stessi comandi
del gioco quando il tavolo le lascia passare. La disegna il renderer del gioco
(tavolo, cartoncini vivi, colpi, dadi, HUD e mano): un renderer prestato
([effect_stage.odin](../src/render/effect_stage.odin)) con il suo stato di vista
(timeline, snapshot, etichette, attori, la superficie del tavolo) e gli asset
GPU del renderer della run, presi in prestito e mai scaricati. La run non viene
mai toccata: stanza, livello, giocatore, mazzo e dadi del film sono del film.
Tutto è deterministico, mai l'orologio: semi fissi per la stanza e per il mazzo,
i dadi della ripresa cercati una volta fra i semi perché il primo tiro mostri le
facce che la scena vuole, il flusso della Canna scelto perché la prima preda sia
cibo. I nemici stanno fermi dove sono, senza piani né colpi, tranne quelli che
la scena lascia liberi, e la stanza non si libera da sola all'ultima uccisione
(`Room_Content.endless`), salvo quella della Canna, già liberata.

**Il film.** Un guanto di cuoio in pixel art, ritagliato nella carta come i
pezzi del tavolo (la stampa, la linea d'inchiostro, il margine bianco, il
taglio), aspetta in basso, va alla carta, la prende chiudendo la mano e la porta
sul bersaglio: un nemico, una casella, una casella in linea retta. Le carte su
di sé o senza bersaglio si giocano con un doppio clic, come nella mano: il primo
la sceglie, il secondo la gioca. Ogni clic lascia sotto il dito un anello di
carta. Mentre il guanto porta la carta il mondo del film aspetta: il suo orologio
parte quando la carta è lasciata, così ogni ripresa mostra lo stesso. Una
didascalia in basso a sinistra dice cosa si fa, con il tasto da premere su un
tastino di carta quando ce n'è uno: `TRASCINA LA CARTA SUL NEMICO`,
`TRASCINA LA CARTA SU UNA CASELLA`, `TRASCINA LA CARTA IN LINEA RETTA` (o
`TRASCINA SUL NEMICO IN LINEA RETTA`), `DOPPIO CLIC SULLA CARTA`,
`TRASCINA LA CANNA SU UNA CASELLA`; poi `L'EFFETTO, CON LE REGOLE DEL GIOCO` e,
quando la scena lo chiede, quello che il Viandante fa dopo la carta:
`W: UN PASSO` (con il tasto della sua direzione), `W: COLPISCI IL NEMICO`,
`W: UN PASSO NELL'OMBRA`, `CTRL + CLIC SUL NEMICO: FRECCIA`,
`CLIC SU ATTIVA: SCARICA LE TESLA`, `MUOVI IL MOUSE: GIRI LA VISTA` e
`TIENI PREMUTO IL CLIC: SPARI`. Nei film in cui la mano cresce (carte che
pescano o creano carte) la didascalia sale sopra la riga dell'`ENERGIA`; non
copre mai una carta, lo slot della Canna o la barra degli oggetti. Quando la
carta cambia quello che la piastra VITA dell'HUD mostra del Viandante (uno
scudo, l'oro, una ferita, una cura, uno status), la piastra si accende con una
cornice di carta che batte tre volte mentre si spegne: Guard la accende con
`SCUDO 4`. Dietro gli occhi di First Person Shooter il guanto sparisce: la vista
gira e spara secondo il copione della ripresa, e il mouse vero non viene mai
catturato. Il tavolo del film è una vetrina (`Tactical_View.showcase`): tiene le
piastre dell'HUD e la barra degli oggetti (la Tesla vi clicca ATTIVA), non i
COMANDI, l'ispettore del nemico o un MOSTRA EFFETTO suo, e la sua camera mira
più vicino al Viandante (0,30 celle avanti invece di 1,10, che nel gioco
lasciano il fondo a una mano piena), perché quello che gli sta oltre resti in
vista sotto le piastre dell'HUD.

**Da capo.** Quando la carta ha mostrato tutto e la stanza si è fermata, la
ripresa resta un momento, il film si scurisce e riparte da capo: la stessa
stanza, gli stessi semi, la stessa ripresa, finché la finestra resta aperta.
**RICOMINCIA** la fa ripartire subito dal primo fotogramma. Una ripresa dura al
massimo 40 secondi (`CARD_DEMO_TAKE_LIMIT`); le più lunghe seguono le regole
delle loro carte: il Pinball circa 27 s (la palla rotola 20 s), l'Incendio 21 s
(finestre da 2 s, perché il fuoco cresca e si spenga), First Person Shooter +5
33 s (30 s di vista, con una raffica dell'AK ogni 3 s). Un fotogramma lento non
fa saltare il film: ogni passo conta al più un quindicesimo di secondo.

**La scala.** Il film si disegna in uno stage, un render target di 960x540,
durante l'update (i render target di raylib non si annidano: mai dentro il passo
del canvas, e i dadi del film prima ancora, fuori da ogni render target), e si
mostra opaco dopo il canvas, sui pixel della finestra, a tre quarti del canvas:
alla misura predefinita, 1280x720, lo stage sta in {160, 116, 960, 540} e ogni
suo pixel è un pixel della finestra. Alle altre misure segue il canvas (`F1`–`F3`
compresi), con il filtro nearest da 1:1 in su (a 1600x900 in
{200, 145, 1200, 675}) e bilineare quando la finestra è più piccola, perché
nessuna riga si perda (a 960x540 è largo 720). Su quei 960x540 il film disegna
tavolo, HUD e mano nelle misure del gioco, con la camera un po' più vicina (10
invece di 12,5), perché i cartoncini sembrino grandi come nel gioco.

**Una carta nuova.** Ogni carta ha un film senza scriverne una riga.
`card_demo_default_scene` ricava la scena dal targeting e dagli effetti della
carta: il gesto che il targeting chiede (doppio clic per `Self`, `Player` e
`None`; trascinata su un nemico, su una casella o lungo una linea per gli
altri), un nemico dove il bersaglio è un nemico, a due celle (dentro la portata,
mai oltre tre; accanto, se la carta lo vuole adiacente) alla destra del
Viandante sullo schermo; due nemici dentro l'area che colpisce, e un barile se
tocca gli oggetti; due nemici a portata di una carta che colpisce tutti; altre
carte nel mazzo (Strike, Guard e Arc Bolt) se pesca o scarta; sul Viandante lo
status che toglie. Quello che la ripresa deve mostrare viene dalla definizione
della carta (`card_demo_expected_events`): gli eventi di ogni suo effetto,
quanti nemici deve ferire, la pozza o il fuoco che lascia
(`card_demo_ground_expected`) e i colpi dell'AK. Lo switch su `Effect_Kind` è
esaustivo, e così quello su `Status_Kind` per ciò che il Viandante porta
(`card_demo_status_use`): un nuovo tipo di effetto o di status non compila
finché non dice come la sua ripresa lo mostra.
`test_every_card_has_a_demo_that_shows_its_effect` gioca ogni `Card_Id` a ogni
livello, due riprese uguali, e per una carta nuova che il default non mostra
fallisce dicendo quali eventi mancano. Vuole anche che ogni didascalia venga
dalla tabella del film (`CARD_DEMO_WORDS`), che lo smoke misura tutta nella sua
piastra: una didascalia nuova va lì.

Allora serve un override in `card_demo_scene`, la scena della carta che parte
dal default: un nemico libero che colpisca dopo la carta (Thorn Coat e Counter
Rune, il balestriere di Deflect), un'azione del Viandante dopo la carta (il
passo di Afterimage, l'urto caricato del Dado del Destino e di Lama Velenosa, la
freccia di Feretro, ATTIVA della Tesla, i quattro passi dell'ombra, le raffiche
dell'AK), altri nemici in fila o intorno (Chain Lightning, Storm Crown, Lazzo,
Pinball), le facce dei dadi (Sundering Blow 4+4, Prismatic Barrage 4/1/4, Twin
Venom 3/3, la faccia più alta di Fate Strike, Shock Floor 3, il d4 della Canna
a 3), una stanza diversa (già liberata per la Canna, finestre da 2 s per
l'Incendio, la nebbia per Battle Focus) o pozze già versate (l'anello della
Pozza di Veleno). Una scena può anche chiedere eventi oltre a quelli della carta
(`expects`) e più nemici feriti (`foe_hurt`), e cambiare con il livello (le
raffiche di First Person Shooter seguono i secondi della vista). Un override
serve anche quando il test passa ma la ripresa si vede male:
`test_card_demo_frames_its_scene` vuole ogni nemico, oggetto, bobina, pozza e
bersaglio di ogni scena sullo stage, dai piedi alla testa, fuori dalle piastre
VITA e del pulse, dall'ispettore, dalla mano, dallo slot della Canna e dalla
didascalia, sul tavolo 3D; il resto si guarda nelle immagini
dello smoke.

**Suoni.** Fuori dalla Prova meccaniche il film tace. Nella Prova il suo tavolo
è quello della prova: mette in coda i suoni della prova come il tavolo della
run, e la finestra li suona al volume degli effetti
(`effect_window_film_sounds`); il fondo della cripta tace finché la finestra è
aperta.

**Le verifiche.** [effect_window_test.odin](../src/integration/effect_window_test.odin) apre la
finestra da ogni ingresso e vuole la carta giusta al livello giusto, senza
scelte, acquisti o pagine girate; la run ferma e intatta mentre è aperta; la
chiusura solo con `Esc`, il clic destro o CHIUDI, senza clic che passino al
tavolo; un rifiuto per ogni stato occupato; lo stage 1:1 a 1280x720; ogni carta,
al primo livello e all'ultimo, che si apre, gira e si chiude senza lasciare
memoria; e con ogni carta a ogni livello, sul tavolo 3D, una
prima ripresa che mostra tutto quello che la carta promette e una seconda che
riparte da capo. [card_demo_test.odin](../src/integration/card_demo_test.odin) tiene i film a
30 e a 144 fotogrammi al secondo e a fotogrammi irregolari, sul tavolo della
vetrina con la didascalia mai sopra la mano, e la loro inquadratura;
[card_demo_test.odin](../src/game/card_demo_test.odin) costruisce la stanza di
ogni scena a ogni livello e tiene i default sul targeting delle carte;
[effect_entry_test.odin](../src/render/effect_entry_test.odin) tiene i pulsanti
lontani da carte, prezzi e comandi;
[effect_stage_test.odin](../src/render/effect_stage_test.odin) percorre con
`core:reflect` tutto il `Renderer` e fallisce se il renderer prestato non prende
in prestito una texture, uno shader, un font, una mesh o un modello, o se divide
con quello della run uno stato che deve essere suo.

Lo smoke `--smoke-effect-window` ([Verifica e smoke test](verifica.md#verifica-e-smoke-test))
apre la finestra vera da ogni ingresso, sulla run della sessione, e poi filma
una ripresa intera di ogni carta, al livello 0 e al più alto, attraverso la
finestra: ognuna deve mostrare l'effetto nel suo tempo, senza errori della
timeline e con la run ferma; a ogni fotogramma la didascalia sta intera nella
sua piastra, misurata con il font del gioco, la piastra non copre niente e il
guanto resta sullo stage; fuori dalla Prova non va in coda nessun suono, mentre
una ripresa di Strike come nella Prova suona i suoi, e il cursore non sparisce
mai. Misura anche il costo del fotogramma: con la finestra aperta il gioco deve
tenere i 60 fotogrammi al secondo, e più di un fotogramma su cinquanta in
ritardo lo fa fallire. Dura circa dieci minuti;
`-define:EFFECT_SMOKE_CARDS=,Strike,Pinball,` filma solo le carte nominate (con
i nomi di `Card_Id`):

```sh
odin run src -o:none -- --smoke-effect-window
odin run src -o:none -define:EFFECT_SMOKE_CARDS=,Strike,Pinball, -- --smoke-effect-window
```

### Il tavolo: cartoncini vivi, cerchi e segnalini

I personaggi del tavolo 3D sono **cartoncini vivi**: la figura è un disegno
animato su un cartoncino che resta fermo e non cambia mai forma né dimensione.
Il personaggio si muove dentro la carta e il bordo lo taglia quando ne esce; per
cambiare casella spinge il cartoncino, che scivola rigido (la spallata del
Viandante, la corsa del ghoul, i passi pesanti del bruto...). I disegni vanno a
12 al secondo, a 24 nei momenti più rapidi, con schiacciamento e allungamento,
linea viva e piccoli segni a matita. Generatore e regole sono in
[tools/art/README.md](../tools/art/README.md#cartoncini-vivi); il runtime è
[living_card.odin](../src/render/living_card.odin). I minigiochi (Platform 3D, FPS)
usano ancora i cartoncini classici.

Il Viandante ha un **cerchio d'azione**: una linea sottile oro, come il colpo
critico, con la forma del suo cartoncino. Batte i secondi: è al massimo subito
dopo uno scocco e si stringe fino a toccare la carta allo scocco successivo, il
momento giusto per un'azione critica; segue il tempo reale anche quando
un'azione consuma secondi.

**Le intenzioni dei nemici** stanno nello stesso cartellino della vita: cuore,
`12/18`, un divisore e un simbolo pixel **7×7** alto quanto le cifre. Spada,
freccia, carica, bomba, scudo, passo, ritirata, attesa, recupero e interruzione
hanno sagome distinte anche senza colore; la preparazione già impegnata usa
inchiostro rosso. Il simbolo segue il piano attuale, senza ricordare un vecchio
attacco dopo che è stato interrotto o il nemico è stato afferrato dal Lazzo.
Non ci sono più adesivi circolari, sigilli o quadranti separati sopra gli attori.

Sul **terreno** restano le conseguenze: le celle colpite si riempiono dai bordi
al centro e la cella del Viandante si contorna se è minacciata; un movimento
indica la cella d'arrivo con una freccia, una protezione collega l'alleato.
Le azioni imminenti acquistano luminosità, la figura trema appena prima di
agire e l'impatto lampeggia sulle celle coinvolte. Le minacce lontane restano
tenui ([intent_display.odin](../src/render/intent_display.odin)). Nel laboratorio
`F6` alterna `HUD + TERRENO` e `SOLO HUD`; la run usa sempre il primo.

La fog nasconde i cartellini dei nemici fuori vista. Gli avvisi di impatto
restano leggibili sulle celle visibili senza rivelare il lanciatore nascosto.
Il colore sul terreno dice il tipo di azione:

| Colore | Azione in arrivo |
|---|---|
| rosso | colpo ravvicinato: attacco, spinta, fendente, carica |
| arancio | colpo a distanza o ad area: mira, tiro, bombe, barili accesi |
| verde | movimento |
| viola | protezione di un alleato |

Recupero e attesa non hanno colore. I colori caldi staccano dal pavimento blu e
segnano le minacce;
verde e viola, vicini al blu, sono chiari; rosso e verde differiscono anche per
luminosità, per chi è daltonico ([living_ring.odin](../src/render/living_ring.odin)).

Danni e cure compaiono su **segnalini di carta**: piccoli cartoncini tagliati e
inchiostrati come quelli dei personaggi, che escono di lato dalla carta di chi è
colpito o curato con il numero in pixel, rosso per i danni e verde per le cure,
restano un attimo e cadono ([living_token.odin](../src/render/living_token.odin)).
Prendono il posto dei riquadri scuri con i numeri; un colpo critico mostra
ancora CRITICO. Ogni colpo ha il suo segnalino anche quando è uguale al
precedente: due urti da 2 sullo stesso nemico, uno dopo l'altro, ne mostrano due.

**I colpi si vedono sul tavolo.** Ogni colpo fisico, del Viandante o di un
nemico, ha la sua arma di carta: pixel art ritagliata con lo stesso bordo
bianco dei cartoncini vivi, disegnata da codice
([build_attack_props.py](../tools/art/README.md#armi-e-colpi-di-carta)).

- **Corpo a corpo**: l'arma di chi colpisce spazza **ogni casella** del colpo,
  dalla più lontana dalla telecamera alla più vicina, con una scia di carta; la
  stella dell'impatto cade sul cartoncino colpito e le caselle vuote perdono
  pezzetti di carta. Il fendente del bruto passa sulle sue tre caselle, il
  ghoul graffia due volte con gli artigli, la Picca della tempesta affonda.
- **A distanza**: il dardo della balestra (e la bomba del bombarolo, la brace
  che l'arcimago lancia su un barile) vola dal tiratore alla casella con un arco
  leggero, orientato sul suo volo: resta conficcato nel cartoncino colpito,
  rimbalza sullo scudo, si pianta nel pavimento se manca.
- **Ognuno ha la sua arma**: il Viandante la sua lanterna di ferro o l'arma M8
  che ha in mano (Mannaia di ferro, Picca della tempesta), anche nel colpo che
  ne consuma l'ultimo uso; ghoul gli artigli, balestriere il dardo, bruto la
  mannaia, bombarolo la bomba, custode il pastorale, arcimago il bastone.
- **Il tempo**: il colpo arriva sul disegno d'impatto della clip d'attacco di
  chi colpisce; il dardo parte lì, e la reazione del colpito, il suo segnalino
  e i suoni della Prova aspettano che arrivi. Una carica colpisce quando il
  cartoncino è arrivato, una spinta cede terreno quando il colpo cade. Quello
  che nello stesso battito tocca a chi ha colpito (la risposta delle Thorns, il
  morso del suo Veleno, la sua morte e il suo bottino) aspetta che abbia finito
  il colpo: prima si vede colpire, poi incassare o cadere. Un colpo che
  incontra uno Shield è un colpo solo anche nella corsia del giocatore:
  parata, scudo rotto e ferita partono insieme, con la stella rossa (oro se
  critico). La stella sta al centro del punto colpito, sopra il dardo
  conficcato; su un oggetto, sul lato della sua scatola verso la telecamera.
  Un colpo mai sferrato (un intento interrotto, una mira spezzata, un lancio
  che non parte, una carica parata prima di partire) non ha arma, né attacco
  né schivata: resta solo il MANCATO.

Per questi colpi le armi prendono il posto del taglio rosso generico e del
lampo sulla figura; magie e dispositivi restano come prima. Una carica
colpisce quando è arrivata, e un colpo che incontra uno Shield parte insieme
alla sua ferita. Il runtime è [attack_fx.odin](../src/render/attack_fx.odin):
`play_attack_swing`, `play_attack_projectile` e `reflect_attack_projectile`
(che rimanda un dardo al suo tiratore) servono anche a
[Deflect](regole/meccaniche.md#deflect-feretro-dado-del-destino-e-lama-velenosa): il dardo deviato
gira quando arriva, la risposta a un fendente è un colpo del Viandante, e la
freccia di Feretro vola come il dardo.

La vita dei nemici è un **cartellino di carta** sopra la testa, tagliato e
inchiostrato come i segnalini: un cuore rosso, `12/18` (la vita sul massimo)
e l'intento nelle stesse dimensioni a pixel ([living_heart.odin](../src/render/living_heart.odin)).
È ancorato al centro sopra la testa e segue la posizione presentata della carta,
compresi movimento e sollevamento del Lazzo. Il tremolio e i frame del disegno
non spostano il cartellino. Non cerca altre righe o colonne quando il player,
altri nemici o gli indicatori gli passano vicino; ai bordi non viene trascinato
lontano dal proprietario e può essere coperto dall’HUD insieme al nemico.
Bombe, micce e indicatori secondari usano il suo rettangolo come spazio occupato.
Le cifre della vita corrente riservano la larghezza del massimo: passando da
`10/18` a `9/18` la carta e l’icona dell’intento restano ferme. Il pixel raddoppia
quando la telecamera è vicina. Come il segnalino, il cuore aspetta che il colpo arrivi: finché
un dardo vola o un fendente non è calato, cuore e VITA dell'HUD mostrano ancora
la vita di prima, anche quando il colpo abbatte il nemico (un colpo `LETALE`, una
freccia sull'ultimo punto di vita): il cuore se ne va quando il colpo arriva
([world_playback.odin](../src/render/world_playback.odin)). L'ispettore del nemico
sotto il mouse dice lo stesso: vita e status come il tavolo li mostra, quindi
dopo un `Ctrl`+clic lo status della freccia compare anche lì quando arriva.
Prende il posto delle etichette scure sopra i nemici (la piastra nera con `HP 18/18`, la
riga colorata dell'intento come `MUOVE / 2.8s` e la barra rossa): vita e intento
condividono il cartellino compatto, lo scudo resta nell'anello e nel numero ai
piedi, e le etichette scure restano solo per bombe, micce e uscita. Il riquadro
del nemico sotto il mouse
resta visibile anche durante le animazioni e mentre la telecamera scorre con il
mouse fermo; lascia il posto solo alla difesa.

### Direzione grafica e perimetro della milestone

Gli attori mantengono i pixel e ricevono un bordo spesso avorio/nero, ricavato
dall'alpha reale con limiti dell'atlante. Il contorno ha una piccola oscillazione
indipendente: dilatazione esterna di 8 pixel sorgente e interna avorio di 6,
con un minimo nel mondo 3D di **4 pixel canvas esterni e 3 avorio**, così
player e tutti i nemici mantengono un contorno evidente anche quando piccoli.
Il ring conserva lo spessore sorgente 8/6; l'ologramma usa un bordo compatto
1,25/0,85 pixel canvas per non nascondere celle e marker. Il quad espanso e lo
shader usano gli stessi raggi.
L'oscillazione è in quattro passi distinta dalla clip interna; le clip d'azione sono quantizzate
in quattro pose. Si conservano corpi 2D, profondità 3D, blocchi plastici blu scuro
e HUD pixel. Dispositivi e campo hanno geometrie e rune dedicate, senza nascondere
la griglia o mostrare nemici coperti dalla fog.

Il ring introdotto in M8 converge nella scena condivisa basata su `fight`: la
vecchia simulazione laterale e il suo overlay sono rimossi. Il catalogo include
platform 2D/3D, arena a ondate, Cripta FPS, puzzle e ring; un
picchiaduro 3D più articolato resta una direzione futura. Non sono presenti una raccolta di
minigiochi completa, ruote, un inventario esteso di consumabili o un
salvataggio/ripristino della run. Bilanciamento delle reti, durata dei cast e
difficoltà delle sfide richiedono ancora partite umane.

## Timeline e input

Sorgenti: [presentation_timeline.odin](../src/render/presentation_timeline.odin),
[frame_timeline.odin](../src/render/frame_timeline.odin),
[gameplay_input.odin](../src/run/gameplay_input.odin).

### Due stati, un solo gameplay

Il percorso seguente descrive un segmento committed. In M7 un comando del
player può accodare un pulse, poi `Continue_Pulse` ne risolve i segmenti; un
QTE può sospendere la sequenza prima del danno. Ogni segmento cattura i propri
snapshot ed eventi. Nessuna correzione viene applicata a posteriori al replay.

```text
comando -> snapshot prima -> simulazione sincrona -> eventi + snapshot finale
                                |                         |
                            Room finale            replay sulla copia
```

`commit_gameplay_command` cattura le viste prima e dopo
`execute_gameplay_command`. Solo un risultato committed avvia la timeline;
un comando senza eventi non la rende busy. Room è già nello stato finale,
mentre `Room_Presentation` riproduce gli eventi su una copia arretrata.
La copia non viene mai scritta nella simulazione.

Movimento e loot usano questa timeline e `World_Playback`; il renderer non
mantiene code parallele per le vecchie animazioni. `clear_event_animations`
azzera i percorsi attivi e dimentica le pose degli attori durante le transizioni.
Il disegno delle figure e degli effetti usa il contratto condiviso di
[paper_draw.odin](../src/engine/gfx/paper_draw.odin): uniform del materiale carta,
espansione dei bordi e quad con UV esplicite. I chiamanti conservano le proprie
regole di opacità e la gestione di profondità, blend e pass di rendering.

La vista conserva attori, oggetti, trappole, loot, deck, status, reliquie,
famiglia, modifier e fase del boss. Gli ID restano validi anche se l'entità
è stata rimossa dalla Room. I cue rispettano il log: movimento, trigger,
Shield/danno, morte, drop e raccolta si mostrano nell'ordine causale.
Card_Played paga e sposta in Resolving; Draw riproduce reshuffle e RNG;
Create deve generare lo stesso ID; mismatch rollbackano la mutazione visuale.

`Explosion` nasconde la sorgente prima dei danni. Il countdown usa il pulse
dello snapshot. `Room_Hazard_Triggered` mostra Furnace e aggiorna la scadenza;
`Pulse_Advanced` sincronizza durate, energia, reliquie e nuova fase del boss.
La Fornace viene disarmata anche se il comando conclude Combat senza pulse.
Il set dei reaction binding non è copiato: i relativi eventi mostrano avvisi.

Di norma è attivo un cue; eventi contigui, compatibili e con lo stesso
`visual_group` esplicito possono animarsi insieme. Firebomb usa questa regola
per gli effetti diretti, applicando comunque le mutazioni in ordine e usando
la durata massima del gruppo. Somiglianza o vicinanza non autorizzano gruppi;
reazioni, movimenti e frontiere dei pulse restano separate.

Il delta residuo passa ai cue successivi, salvo i limiti per frame dei dadi.
Oltre dodici secondi nominali, la sequenza ordinaria comprime proporzionalmente
le durate. In M8 `fit_card_cast_timeline` adatta poi i gruppi non cinematici alla
durata della carta: dadi esclusi dal costo, cast e dadi non accelerabili con F4.
`PRESENTATION_TIME_SCALE` maggiore di uno le allunga; la velocità runtime
0.25x–4x scala invece il delta, viene conservata fra stanze/restart e non cambia
il gameplay. Corpi animati usano un clock cosmetico; clip evento seguono il cue.

### Input senza coda e transizioni

**Nessun comando resta in coda**, nella run, nella Prova
meccaniche e nei laboratori ( `route_gameplay_command` in
[beat_input.odin](../src/run/beat_input.odin)). Mentre è in corso l'azione del player
stesso, cioè la sua animazione nella timeline, i secondi di un'azione a tempo o
il passo da 0,4 s dell'ombra di [Movimento Ombra](regole/meccaniche.md#movimento-ombra), una
pressione viene scartata; agisce solo una pressione fatta dopo la fine
dell'azione. Il poll continua a girare, così hover, `Esc` e l'annullamento del
drag rispondono, ma il suo comando non viene tenuto. Lo stesso vale per la
freccia di Feretro (`Ctrl` + clic, il comando `Shoot`): un'azione da 1 s come le
altre, mai tenuta per dopo e mai segnata con lo scocco. La schivata
`Shift + WASD` che interrompe un'azione a tempo è una regola del gioco, non una
coda, e così il grilletto dell'AK di
[First Person Shooter](regole/meccaniche.md#first-person-shooter): finché il tasto è tenuto spara un
colpo ogni sesto di secondo come comando del mondo (`First_Person_Fire`, come i
giri del Lazzo e la corsa del Pinball), e da un fotogramma all'altro non porta
più del ritardo di un colpo; un clic fatto prima che la vista prenda il mouse
non spara finché non lo si rilascia. L'unico input che attraversa qualche
fotogramma è il passo premuto sul secondo, che aspetta al massimo
`BEAT_CHORD_SECONDS` (0,06 s) il tasto perpendicolare della diagonale: vive in
`Buffered_Gameplay_Command`, e ogni confine che svuota quella struttura
(controller bloccato, fine della finestra, QTE, pausa, mappa, schivata o
diagonale, perdita del focus, restart, nuova stanza, schermate) lo lascia
cadere. I comandi portano valori logici e ID, mai puntatori o indici visuali, e
la fase d'origine: un Move nato in Combat non diventa implicitamente un Move in
Loot. Tenere un tasto premuto non genera repeat.

La timeline dei nemici non blocca le azioni del player. Cast, cinematiche e
QTE mantengono blocchi espliciti; gli slot si riferiscono alla mano visibile,
e la camera resta indipendente.

`finish_room` e le schermate Reward, Victory e Defeat aspettano l'ultimo cue.
Restart, nuova stanza e cambio schermata svuotano la timeline e lasciano cadere
il passo in attesa; anche l'apertura manuale della mappa richiede idle e
cancella il vecchio contesto.

### Diagnostica ed estensioni

Timeline e log hanno 416 slot; lo snapshot conserva 32 nemici, 64 trappole,
32 oggetti e 96 drop (oro, cura e arma per ciascuno dei 32 nemici). `dropped_count` segnala perdite; `update_failures`
segnala eventi non applicabili. Lo snapshot `F8` mostra anche il passo in
attesa della diagonale (`chord_active`, `chord_direction`, `chord_timer`).
Controllare lo stato intermedio dei cue nei test: la convergenza finale può
nascondere errori nell'ordine visuale.

Per un evento nuovo: payload sufficiente, mapping esaustivo a cue, durata,
mutazioni start/finish, interpolazione, disegno e verifica di ordine e delta
in eccesso. Il renderer non deve recuperare payload mancanti dalla Room futura.
Per un comando nuovo: kind e payload stabili, polling senza mutazioni,
API autorevole, criterio committed, snapshot e fase d'origine
(`gameplay_command_is_valid`).

| Sintomo | Controllo |
|---|---|
| salto visivo / danno su entità scomparsa | ordine eventi, ID, payload from/to, start/finish, update_failures |
| ultimo feedback tagliato | guardia timeline idle prima della transizione |
| input perso | premuto durante la propria azione (scartato per regola) o a controller bloccato: `player_animation_blocks_input`, fase e timeline nello snapshot `F8` |
| comando vecchio nella stanza nuova | passo in attesa della diagonale non lasciato cadere a quel confine (`clear_gameplay_command_buffer`) |
| preview diversa dall'esito | targeting attivo su snapshot arretrato |
| coda incompleta | dropped_count e budget eventi |

## Sprite e animazioni personalizzate

Il renderer può sostituire il corpo del giocatore e dei nemici con PNG, sprite sheet PNG o GIF animate. Gli oggetti della scena restano mesh a blocchi. Supporta anche clip per lancio, proiettile, impatto e danno, sincronizzate con gli eventi di combattimento. Gli indicatori di salute, le intenzioni e le micce restano gestiti dal gioco. Senza un asset valido continua a essere usata la grafica incorporata di quel tipo o effetto.

Non sono incluse nuove illustrazioni: il sistema permette di inserire le proprie immagini senza ricompilare.

### Avvio rapido

1. Crea `assets/sprites.json`, prendendo come riferimento [assets/sprites.example.json](../assets/sprites.example.json).
2. Inserisci le immagini nelle posizioni indicate dal manifest. I percorsi dei file sono relativi alla cartella che contiene il manifest.
3. Avvia `odin run src -o:none`. Il manifest predefinito è `assets/sprites.json`, relativo alla directory di avvio.

Per usare un altro pacchetto:

```sh
odin run src -o:none -- --sprites=/percorso/del/pacchetto/sprites.json
```

Per cominciare con una sola immagine statica:

```json
{
  "version": 1,
  "sprites": [
    {
      "key": "player",
      "file": "player.png",
      "width": 32,
      "height": 48,
      "anchor": [0.5, 1.0]
    }
  ]
}
```

Non occorre specificare gli altri tipi. Riavvia il gioco dopo aver modificato il manifest o un'immagine; il caricamento avviene una sola volta all'avvio.

### Tipi e dimensioni

Le chiavi dei corpi, animate in loop durante l'attesa, sono `player`, `chaser`, `archer`, `brute`, `bomber`, `custodian`, `demolitionist`, `ice_block`, `fire`, `barrel` e `bomb`. Le clip evento usano le otto chiavi descritte più sotto. Ogni chiave può apparire una sola volta nello stesso manifest, che mantiene `version: 1`.

| Campo | Significato | Valore predefinito |
| --- | --- | --- |
| `file` | PNG o GIF; il formato viene riconosciuto dal contenuto | Obbligatorio |
| `width`, `height` | Dimensioni sul canvas con zoom 1; seguono lo zoom della camera | Dimensioni di un frame |
| `anchor` | Punto dell'immagine che coincide con la posizione dell'attore, oggetto o effetto, da 0 a 1 | `[0.5, 1.0]`, centro in basso |
| `columns`, `rows` | Griglia regolare dei frame di uno sheet PNG | `1`, `1` |
| `frames` | Numero di frame PNG usati, in ordine da sinistra a destra e dall'alto al basso | Tutte le celle dello sheet |
| `fps` | Velocità del loop in frame al secondo; ignorata dalle clip evento | `8` |

Lo zoom 1 usa tessere larghe 64 e alte 32 pixel. Per gli attori sono un buon punto di partenza immagini mostrate a 32 × 48 pixel; conviene assegnare sempre dimensioni esplicite se il file sorgente è grande. Gli sprite possono avere margini trasparenti: adatta `anchor`, per esempio `[0.5, 0.9]`, se i piedi non arrivano al bordo inferiore dell'immagine.

Le immagini vengono disegnate con filtro nearest-neighbor, adatto alla pixel art. La selezione usa l'alpha del frame visibile: la testa rialzata di uno sprite è cliccabile, mentre i margini trasparenti lasciano passare il puntatore. Il bersaglio resta sempre la cella dell'entità; portata, collisioni e regole delle carte restano invariati.

### GIF e sprite sheet

Per una GIF indica soltanto `file`, dimensioni, eventuale `anchor` e `fps`. Non impostare `columns`, `rows` o `frames`: i frame provengono dal file GIF. Le animazioni dei corpi vengono ripetute a velocità uniforme; le durate originali dei singoli frame GIF e il numero di ripetizioni non vengono usati. Raylib non espone le durate attraverso la funzione di caricamento impiegata.

Uno sprite sheet PNG deve avere dimensioni divisibili per `columns` e `rows`. `frames` permette di escludere celle vuote finali. Tutte le istanze del corpo di uno stesso tipo condividono la fase del loop. Questa animazione è cosmetica e non fa avanzare impulsi, intenzioni o RNG; le animazioni di spostamento e combattimento del gioco continuano ad applicarsi allo sprite.

### Clip collegate agli eventi

Le clip evento partono quando il renderer presenta il relativo lancio, volo, impatto o danno. Non vengono riprodotte continuamente: terminano insieme alla fase dell'evento che le contiene.

| Chiave | Uso |
| --- | --- |
| `player_cast` | Animazione del giocatore durante il lancio |
| `player_hit` | Animazione del giocatore quando subisce danno |
| `firebomb_cast` | Effetto di preparazione/lancio di Firebomb |
| `firebomb_projectile` | Proiettile di Firebomb, lungo il suo percorso |
| `firebomb_impact` | Impatto di Firebomb |
| `chain_bolt` | Effetto di un fulmine di Chain Lightning |
| `fate_cast` | Effetto di lancio di Fate Strike |
| `fate_impact` | Effetto di risoluzione di Fate Strike |

Le clip accettano PNG statici, sheet PNG e GIF con gli stessi campi dei corpi. Per un'esplosione o un fulmine centrato sulla posizione dell'effetto è spesso più comodo `anchor: [0.5, 0.5]`; per `player_cast` e `player_hit` usa dimensioni e anchor compatibili con il corpo `player`.

```json
{
  "version": 1,
  "sprites": [
    {
      "key": "firebomb_impact",
      "file": "effects/firebomb_impact.png",
      "columns": 4,
      "rows": 2,
      "frames": 8,
      "width": 112,
      "height": 96,
      "anchor": [0.5, 0.5]
    }
  ]
}
```

La durata di una clip si adatta alla durata della fase di presentazione del gioco. `fps` influenza soltanto i loop dei corpi: non accelera né rallenta un'azione. All'inizio viene mostrato il primo frame, alla fine l'ultimo, senza tornare al primo. Due impatti contemporanei possono usare lo stesso file e avere progressi diversi; non si azzerano né si sincronizzano a vicenda. Un PNG statico resta visibile per la durata della fase.

Il manifest può contenere insieme corpi e clip; è possibile sostituire soltanto gli effetti desiderati. Le clip mancanti mantengono gli effetti procedurali. Le clip non sono bersagli selezionabili e non alterano collisioni o risultati del combattimento. Questa versione non aggiunge animazioni distinte per direzione.

### Caricamento e limiti

I file condivisi da più chiavi usano la stessa texture, anche quando una chiave è un corpo in loop e l'altra è una clip evento. I frame GIF vengono riuniti in un atlas, caricato sulla GPU una sola volta; durante il gioco non vengono decodificate GIF né ricaricate texture. Le risorse GPU e le maschere alpha vengono liberate prima della chiusura della finestra.

- Manifest fino a 64 KiB, con un massimo di 19 associazioni: 11 corpi e 8 clip evento.
- File PNG/GIF fino a 16 MiB; massimo 128 frame e 8 milioni di pixel decodificati per file/atlas.
- Texture con lato massimo di 4096 pixel; budget complessivo di 32 milioni di pixel.
- Dimensioni visualizzate positive fino a 256 pixel per asse e velocità fino a 60 fps.

Dimensioni PNG e struttura GIF vengono controllate prima della decodifica. Manifest mancante, file non validi o configurazioni incompatibili conservano la grafica procedurale; un errore di un singolo sprite non impedisce il caricamento degli altri.

### Verifica grafica

```sh
odin run src -o:none -- --smoke-m7-view
```

Lo smoke esercita la scena 3D, la fog, l'ologramma, i menu e le transizioni.
I test di `sprite_assets` e `sprite_clip` conservano le regressioni del loader,
dei frame, dell'alpha e dei fallback. Il vecchio smoke del renderer piatto è ritirato.
