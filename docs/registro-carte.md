[← Odin PP](../README.md)

# Registro delle carte

Qui si segna ogni carta tolta dal gioco o cambiata, con quello che faceva, così da poterla confrontare o rimettere in
futuro. Le voci più recenti stanno in cima. Per ritrovare il commit di una voce:
`git log --all --grep "<titolo del commit>"`.

## 2026-11-03 — IA: i segni veri e il consiglio che resta fermo (solo laboratorio)

Commit **«Piano IA, Fase 5 fatta: le indicazioni vere»** sul ramo `piano-ia` ([piano](piano-ia.md), Fase 5). La carta
non cambia. Cambia come consiglia:
- **il consiglio resta fermo** finché il giocatore non fa la sua prossima azione (richiesta dell'utente dopo la prova:
  prima cambiava idea troppo spesso, a ogni nemico che si spostava). Cambia prima solo se un nemico annuncia un colpo
  sulla casella del Viandante, o se il consiglio non si può più fare (il nemico è morto, la carta non c'è più, la casella
  è occupata, i tasti della difesa sono comparsi);
- **i segni veri**, tutti ciano: un'impronta con una freccia per il passo (VAI, o SCHIVA quando esce da una casella
  minacciata), un mirino che respira per il colpo (COLPISCI) e per la freccia del Feretro (FRECCIA), la cornice sulla
  carta in mano e, quando la tieni, sulla casella del bersaglio (CARTA), la cornice sul tasto giusto nel riquadro della
  difesa (DIFENDI), un orologio sotto il Viandante per l'attesa (ASPETTA), la sola parola per il rimescolo
  (RIMESCOLA);
- **l'avviso:** se il giocatore fa una mossa che fa perdere almeno 2 di vita più del consiglio, sopra di lui compare per
  mezzo secondo un «!» rosso con la vita che rischia (per esempio «! -3»), o «! MORTE».
- Nella nebbia nessun segno: il consiglio non svela le caselle che non vedi.

## 2026-11-03 — IA: consiglia anche le carte (solo laboratorio)

Commit **«Piano IA, Fase 3 fatta: le carte nella ricerca»** sul ramo `piano-ia` ([piano](piano-ia.md), Fase 3). La
carta non cambia: ora la IA prova anche ogni carta della mano sui suoi bersagli migliori (al massimo 6), il riordino
della mano e le frecce del Feretro, e consiglia la carta con la cornice ciano nella mano e il segno sulla casella del
bersaglio («CARTA»). Non consiglia ancora le carte che aprono una vista e l'Ombra (Fase 7), né la canna da pesca e se
stessa.

## 2026-11-03 — IA: la ricerca della mossa migliore (solo laboratorio)

Commit **«Piano IA, Fase 2 fatta: la ricerca»** sul ramo `piano-ia` ([piano](piano-ia.md), Fase 2). La carta non cambia
(rarità, energia, secondi): mentre corrono i suoi secondi, ora consiglia davvero la mossa senza carte (passo, colpo a
mano, schivata, passo in diagonale, attesa, difesa a tasti) con segni provvisori: un quadrato ciano sulla casella, una
croce ciano sul nemico da colpire, la parola sopra il Viandante (VAI, SCHIVA, COLPISCI, ASPETTA, DIFENDI). Le carte nella
ricerca arrivano con la Fase 3, i segni veri con la Fase 5.

## 2026-11-03 — Carta nuova: IA (solo laboratorio)

Commit **«Piano IA, Fase 0 fatta: la carta e i suoi secondi»** sul ramo `piano-ia` ([piano](piano-ia.md), Fase 0).

| Carta | Nel codice | Rarità | Energia | Effetto | Peso nelle offerte | Dove sta |
|---|---|---:|---:|---|---:|---|
| IA | `IA` | rara | 2 | su di sé, lancio leggero (`time_cost` 1; sulla carta 0,26 s): per 30 secondi del mondo (+3 a potenziamento, fino a 5 potenziamenti; +5 sulla giocata critica) la IA consiglia la mossa migliore. I secondi si fermano quando il mondo è fermo e dentro le viste; giocata di nuovo, i secondi ripartono dal pieno | 60 (ma `Lab_Only`: mai offerta) | solo nell'arena «IA» del laboratorio, nel suo mazzo |

- **Fase 0:** la carta e i suoi secondi (nel giocatore, `Tactical_State.ia_remaining`: la stanza non cresce); i consigli
  arrivano con le fasi dopo. Scritta «IA 30s» sopra il Viandante e segnalino ciano sotto VITA («IA 28s», «IA FERMA» nelle
  viste).
- Prezzo nel negozio 8, prezzo in spedizione 50. Scelta dell'utente: resta solo nel laboratorio anche a fine piano.
- Icona provvisoria (cella 37 dell'atlante): un cervello di circuiti semplice, pieghe a sinistra e piste ciano a destra;
  sigla `IA`. Suono provvisorio fatto da codice (`card_ia`, tools/audio/sfx_ia.py): la carta che scatta, un ronzio che
  sale, due bip, un accordo pulito. Gli altri 245 suoni sono identici byte per byte.

## 2026-11-02 — Carta nuova: Benvenuti a Napoli (solo laboratorio)

Commit **«Piano di Napoli, Fase 0 fatta: la carta, il D4 e i quattro rami»** sul ramo `piano-napoli`
([piano](piano-napoli.md), Fase 0).

| Carta | Nel codice | Rarità | Energia | Effetto | Peso nelle offerte | Dove sta |
|---|---|---|---:|---|---:|---|
| Benvenuti a Napoli | `Napoli` | rara | 3 | su di sé, lo stesso tempo di lancio del Dinosauro (`time_cost` 2; sulla carta -0,4 s): un D4 (sempre un D4, a ogni livello) sceglie 1 **bastone** in terza persona per 30 s (+2 a potenziamento), 2 **tavolata** del nonno che cura metà della vita massima (+2), 3 **borsellino** di 15 oro (+2), 4 il Viandante diventa il **nonno** per un minuto con 30 di vita sua (+5). La giocata critica dà +3 s al bastone, ×1,5 a tavolata e borsellino, +10 di vita al nonno. Non si gioca in groppa al Dinosauro né dentro una vista | 60 (ma `Lab_Only`: mai offerta) | solo nell'arena «Prima persona» del laboratorio, nel suo mazzo |

- **Fase 0:** la carta tira il dado e dice il ramo uscito (scritta sul Viandante e pannello del dado: «2 TAVOLATA», «CURA
  11 VITA»); i quattro rami non fanno ancora nulla: arrivano con le Fasi 1-4 del piano.
- Prezzo nel negozio 8, prezzo in spedizione 60 (come le carte in prima persona); fino a 4 potenziamenti come le carte
  coi dadi.
- Icona (cella 36, in una decima riga nuova dell'atlante) e sigla `BAN` **provvisorie**, la scelta dell'utente: il
  Vesuvio visto dal golfo, il Monte Somma e il Gran Cono con la lava nel cratere, sotto un pennacchio di fumo a forma
  di pino. Suono provvisorio fatto da codice (`card_napoli`, tools/audio/sfx_napoli.py): la carta che scatta, il D4
  agitato in mano, poi un mandolino in tremolo sulla cadenza napoletana (Si bemolle maggiore, Mi maggiore, La minore);
  i suoni veri e la tarantella sono della Fase 6.
- Nel laboratorio `F12` fissa la faccia del D4 (A CASO, 1, 2, 3, 4); `F11` resta lo schermo intero.
- **2026-11-02, Fase 1** (commit «Piano di Napoli, Fase 1 fatta: il nonno porta tavolata e borsellino»): le facce 2 e 3
  fanno quello che dicono. 2: il nonno posa la **tavolata** accanto al Viandante, lontano dai nemici (blocca passi, vista e
  frecce, nessuno la colpisce, una alla volta, sparisce a fine combattimento); un passo contro di lei lo fa sedere **2
  secondi** occupato e senza difesa, la cura in due metà sui due battiti, poi la tavola si sparecchia; con tutto pieno
  attorno, cura subito. 3: il **borsellino**, l'oro subito. Mentre il nonno arriva il mondo è fermo per 2 secondi.
- **2026-11-03, Fase 2** (commit «Piano di Napoli, Fase 2 fatta: il bastone in terza persona»): la faccia 1 apre la
  vista del **bastone** (arma `Club` della vista, `game/first_person_club.odin`): camera dietro la spalla destra, il
  mouse gira la visuale (un po' anche su e giù), WASD fa passi sulla griglia da 0,5 s (dimezzati dal ritmo del
  Viandante come tutti i passi), clic sinistro (tenuto: una dopo l'altra) = **mazzata** sulla casella fra le 8 attorno
  più vicina alla visuale, segnata a terra. La mazzata dura 0,6 s (0,25 di carica, impatto, 0,35 di ritorno, il
  Viandante occupato): 8 danni (+1 a potenziamento) e stordimento coi **ritorni decrescenti** (2 battiti, poi 1, poi
  niente sullo stesso nemico, finché non passano 4 s senza mazzate su di lui). Senza nemico rompe un barile o un blocco
  di ghiaccio, altrimenti picchia il pavimento; una diagonale chiusa da due muri non si colpisce. Viandante e bastone
  provvisori (il cartoncino e un bastone semplice).
- **2026-11-03, Fase 3** (commit «Piano di Napoli, Fase 3 fatta: schiacciamento, succo e stelline»): la carta del nemico
  colpito dal bastone si **schiaccia** al 30% dell'altezza, larga circa 1,8 volte, resta piatta un attimo e torna su con
  una molla fino al 112% (0,6 s, solo immagine); la mazzata che uccide lo lascia **a frittella** mentre cade. Pausa di
  90 ms, scossa, schegge e polvere; a vuoto solo polvere e una scossa piccola. Sopra il nemico stordito girano tre
  **stelline**.
- **2026-11-03, Fase 4** (commit «Piano di Napoli, Fase 4 fatta: un minuto da nonno»): la faccia 4 trasforma il
  Viandante nel **nonno** per 60 s (arma `Nonno` della vista, `game/napoli_nonno.odin`), in terza persona e libero sulla
  mappa a 4 caselle al secondo, senza salto né scatto. Il bastone esce dalla tasca da solo in 1,2 s, poi il clic dà la
  mazzata del bastone sul nemico davanti (entro 1,2 caselle dal bordo del corpo, 45° per parte), fermo durante il colpo.
  Vita sua: 30 (+5 a potenziamento, +10 sul tick); le ferite vanno a lui, a zero se ne va e il Viandante ha la vita di
  prima, nella casella dove stava il nonno. Q una volta: cura il nonno di metà della sua vita e il Viandante di metà
  della sua; E una volta: 15 oro (+2).
- **2026-11-03, Fase 5** (commit «Piano di Napoli, Fase 5 fatta: asso, Viandante e nonno al mare in 3D»): l'asso di
  bastoni, il Viandante di spalle e il nonno **al mare** (cappello di paglia, canottiera, pantaloncini, sandali coi
  calzini) sono modelli 3D di carta fatti da codice; il Viandante sbiadisce solo quando copre la casella mirata. La
  tavolata ha il pranzo completo e si svuota mangiando; il nonno ospite resta una figurina, da nonno al mare. **Icona
  nuova:** la faccia del nonno al mare (non più il Vesuvio).
- **2026-11-03, Fase 6** (commit «Piano di Napoli, Fase 6 fatta: suoni CC0 e tarantella»): la carta ha i suoi suoni nel
  laboratorio: mazzata, boing, monete, posate, ciabatte e risata del nonno da file **CC0** di Freesound (fonti e licenze
  in `assets/audio/LICENZE.md`); fruscio del colpo, stelline e tasca da codice. Col bastone e col minuto da nonno suona
  una **tarantella** fatta da codice.
- **2026-11-03, Fase 7** (commit «Piano di Napoli, Fase 7 fatta: la carta nel gioco vero»): **entra nel gioco vero**
  (non più `Lab_Only`): offerte, negozi, collezione della campagna. Il film di «Mostra effetto» mostra una faccia a ogni
  giro (bastone, tavolata, borsellino, nonno), non più una per livello.

## 2026-11-03 — Dinosauro: il film mostra i quattro dinosauri

Commit **«Piano di Napoli, Fase 7 fatta: la carta nel gioco vero»** sul ramo `piano-napoli`
([piano](piano-napoli.md), Fase 7).

- Il film di «Mostra effetto» del Dinosauro mostra un dinosauro diverso a ogni giro (il film riparte da solo):
  Velociraptor, Stegosauro, Dilophosaurus, Giganotosauro, a qualunque livello. Prima il dinosauro dipendeva dal livello
  della carta, e una carta offerta o appena presa mostrava solo il Velociraptor. Le regole della carta non cambiano.

## 2026-10-30 — Tutte le carte: il lancio dura la metà

Commit **«Il Viandante va al doppio: passi, colpi e carte più rapidi»** sul ramo `gioco-piu-veloce`
([regole](regole/combattimento.md), «Ritmo del giocatore»).

- Nel gioco come si gioca (azioni a tempo) ogni carta lancia in metà dei suoi secondi (`TACTICAL_PLAYER_PACE` = 2,
  `game.tactical_player_pace`): 1 s → 0,5 s, 2 s → 1 s, 3 s → 1,5 s, 4 s → 2 s. Il `time_cost` delle definizioni resta il
  prezzo pieno, che valgono ancora le regole di base delle sonde. Il badge della carta e l'ispettore mostrano il prezzo
  dimezzato (`-1.5s`).
- Con la finestra a 20 s ci stanno il doppio delle carte; ogni sei carte giocate si vince ancora un secondo
  (`TACTICAL_CARDS_PER_SECOND`, invariato).
- Le carte a 0 s (Movimento Ombra, Canna da Pesca, le quattro di prima persona) non cambiano; i secondi propri delle
  meccaniche (ombra, giro del Lazzo, corsa del Pinball, festa di Bomb Marley, vista in prima persona) nemmeno.

## 2026-10-29 — Carta nuova: First Person Archer (solo laboratorio)

Commit **«Prima persona, Fase 6, passi 1-5: l'arco, regole e prototipo»** sul ramo `piano-prima-persona`
([piano](piano-prima-persona.md), Fase 6).

| Carta | Nel codice | Rarità | Energia | Effetto | Peso nelle offerte | Dove sta |
|---|---|---|---:|---|---:|---|
| First Person Archer | `First_Person_Archer` | rara | 3 | su di sé, 0 s di finestra: la vista in prima persona con l'arco per 30 s del mondo (+2 a potenziamento, fino a 40 a +5): a griglia come l'AK; destro tenuto tende (piena in 1,6 s), rilasciato tira, sinistro abbassa; da 1 a 4 rimbalzi sui muri secondo la carica, ognuno ×1,25 di velocità; danno 2,5 × partenza/12 × impatto/12, fino al 50% in più con i rimbalzi (da 4 a 14 dritto, fino a 44); tiro veloce (sotto 0,4 s) che cade a parabola, 1 danno, nessuno stato; 0,15 s per incoccare; cinque frecce a caso (veleno, fuoco, ghiaccio, stordente, dentata) con i loro stati; tre zone critiche sui muri (×1,6 e un rimbalzo gratis) | 60 (ma `Lab_Only`: mai offerta) | solo nell'arena «Prima persona» del laboratorio, nel suo mazzo |

- È la quarta arma della vista di First Person Shooter (`First_Person_Weapon.Bow`); non si gioca in groppa al Dinosauro.
- La freccia che torna sul Viandante rimbalza su di lui senza ferirlo, e conta come un rimbalzo gratis (la scelta
  dell'utente); vola e colpisce anche fuori vista; frecce infinite.
- Icona (cella 35): l'arco compound Neon di lato, la scelta dell'utente per la Fase 7. Suono della carta
  (`card_first_person_archer`): le carrucole che girano, la corda che vibra (Karplus-Strong), il fischio.
- **Fase 7 (aspetto e suoni):** l'arco è un compound Neon in 3D con le carrucole (la scelta dell'utente), frecce con la
  scia del loro colore, scintille ai rimbalzi, zone critiche come bersagli di carta con la luce che pulsa, la faretra
  attorno al mirino; suoni suoi (un ping più alto a ogni rimbalzo) e una musica sua nel laboratorio. Le regole non
  cambiano.
- **2026-10-29, Fase 8 chiusa con l'utente:** First Person Fencer, taglio pieno da 6 a 9 (nel bot la spada passa da 2,2
  a 3,1 danni al secondo); First Person Archer, a ogni rimbalzo anche una corda d'arpa pizzicata, una nota più alta
  ogni volta (pentatonica di la minore); le frecce ancora fuori quando la vista finisce finiscono il volo e colpiscono.
- **2026-10-29, corda al viso** (all'utente la mano che tendeva non convinceva; scelta fra tre pose in foto): tendendo,
  la corda arriva al viso come nel tiro vero e la mano esce dallo schermo in basso vicino alla guancia; l'arco resta
  inclinato di lato al mirino; a riposo sta più basso e si alza quando si tende.
- **2026-10-29, niente muri invisibili** (l'utente: tirando sopra un muretto la freccia rimbalzava): muretti, coperture
  e oggetti fermano la freccia solo fin dove sono disegnati (muretto 0,55, copertura 0,49, ogni oggetto la sua altezza);
  sopra ci passa, cadendoci sopra si pianta sul loro piano. Le zone critiche stanno solo sui muri alti.
- **2026-10-29, arco a destra** (la scelta dell'utente): l'arco nella vista sta a destra del mirino, vicino al braccio
  destro, tenuto con la mano destra; la sinistra tira la corda. È tutto lo stesso arco, specchiato.
- **2026-10-29, danni ribilanciati** (l'utente: a raffica faceva più danni dell'AK): il tiro rilasciato prima del primo
  livello è un **tiro veloce** che cade a parabola (tocca terra tra 2 e 4 caselle mirando dritto, manca un nemico a 3
  caselle circa una volta su tre), fa 1 danno e non dà stati; dopo ogni freccia la prossima si incocca in 0,15 s. Le
  frecce tese fanno di più: 2,5 × partenza/12 × impatto/12 (da 4 a 14 su un tiro dritto, prima da 2 a 5). Il bot, con
  nemici che non muoiono: AK 4,6 danni al secondo, arco teso 7,0, arco a raffica 2,5 (prima 474, per gli stati
  accumulati).
- **2026-10-29, frecce più grandi** (l'utente le trovava troppo piccole): ogni freccia in volo parte dalla punta della
  freccia incoccata sull'arco e raggiunge la sua linea vera dopo 2,5 m, così si vede di lato e non solo da dietro;
  tiene la stessa grandezza sullo schermo da 1 a 7,5 m (tre volte lo spessore vero a 3 m); a ogni rimbalzo diventa un
  ottavo più grande, fino a metà in più, come il danno. Solo l'aspetto: i cerchi delle regole non cambiano.

## 2026-10-29 — Carta nuova: First Person Fencer (solo laboratorio)

Commit **«Prima persona, Fase 4, passo 6: First Person Fencer nel laboratorio»** sul ramo `piano-prima-persona`
([piano](piano-prima-persona.md), Fase 4).

| Carta | Nel codice | Rarità | Energia | Effetto | Peso nelle offerte | Dove sta |
|---|---|---|---:|---|---:|---|
| First Person Fencer | `First_Person_Fencer` | rara | 3 | su di sé, 0 s di finestra: la vista in prima persona con la spada per 35 s del mondo (+2 a potenziamento, fino a 45 a +5; erano 20, alzati dopo la prova dell'utente): a griglia con passi di 0,3 s, `Q`/`E` di 90°, la lama mossa dal mouse (danno da velocità, ampiezza, linea, punto della lama e direzione: fino a 11), parata senza limite con il destro (perfetta entro 0,25 s), rampino con `Ctrl` | 60 (ma `Lab_Only`: mai offerta) | solo nell'arena «Prima persona» del laboratorio, nel suo mazzo |

- È la terza arma della vista di First Person Shooter (`First_Person_Weapon.Sword`); non si gioca in groppa al Dinosauro.
- **Dopo la prova dell'utente:** niente più attesa fra un taglio e l'altro (ogni passaggio sul petto taglia, anche al
  ritorno, dopo almeno un quinto di schermo di strada); affondo ×1,25 con un passo durante lo swing; colpo roteante ×1,5
  girando con `Q`/`E` nel verso della lama; striscia di sangue, lampo, fermo della lama e scossa al colpo.
- **Terza prova:** durata da 20 a **35 s** (pochi colpi senza i passi liberi né la distanza); il colpo roteante si vede
  (scia magenta dal giro, parole `COLPO ROTEANTE x1,5` accanto al nemico).
- **Fase 5 (aspetto e suoni):** la spada è uno zweihänder Neon (la scelta dell'utente); icona definitiva (cella 34, lo
  spadone in diagonale); la carta dice «SPADONE: TAGLIA E PARA» (stretta «SPADONE, PARATA»); cartellino del colpo
  («FENDENTE 9»), angoli della guardia attorno al mirino, scintille e lampo delle parate, catena del rampino; suoni suoi
  e una musica sua nel laboratorio. Le regole non cambiano.
- Icona (cella 34) e suono (`card_first_person_fencer`) **provvisori**: quelli definitivi sono della Fase 5, nello stile Neon.

## 2026-10-29 — First Person Brawler: critico senza mira, guantoni 3D

Commit **«Prima persona, Fase 2: critico senza mira e guantoni 3D»** sul ramo
`piano-prima-persona` ([piano](piano-prima-persona.md), Fase 2, dopo la prova).

- **Prima:** il critico voleva il pugno chiesto dal segno **e** il mirino sopra il segno (testa o corpo compresi).
- **Ora:** basta il pugno chiesto dal segno che prende quel nemico, dovunque. Il segno sta sul petto, dalla parte del suo
  pugno, solo come aiuto.
- **Aspetto:** i guantoni rossi di carta ai lati diventano guantoni in guardia al centro in basso: un modello 3D disegnato
  come pixel art di cartoncino (tinte piene, inchiostro, bordo di carta e spessore). Prima neri e oro; poi (Fase 3, scelta
  dell'utente) **Neon**: carbonio viola scuro, fasce e tubi magenta, bordo di luce ciano.
- **Icona e ispettore** (Fase 3): icona del guantone ridipinta Neon; nell'ispettore «SX JAB / DX CROSS / SHIFT GANCI» al
  posto di «NIENTE CARTE: SOLO I PUGNI»; riquadro dei secondi magenta.
- **Suono** (Fase 3): `card_first_person_brawler` non ha più la campanella (ora suona alla discesa nella vista): solo i
  guantoni battuti con un crepitio Neon.
- Danni, tempi, rarità, energia e durata non cambiano.

## 2026-10-28 — Carta nuova: First Person Brawler (solo laboratorio)

Commit **«Prima persona, Fase 2, passo 5: First Person Brawler nel laboratorio»** sul ramo `piano-prima-persona`
([piano](piano-prima-persona.md), Fase 2).

| Carta | Nel codice | Rarità | Energia | Effetto | Peso nelle offerte | Dove sta |
|---|---|---|---:|---|---:|---|
| First Person Brawler | `First_Person_Brawler` | rara | 3 | su di te, 0 s di finestra: la vista in prima persona con i pugni per 20 s del mondo (+2 a potenziamento, fino a 30 a +5): movimento libero a 5 caselle al secondo, salto, scatto con il doppio tocco, jab 3, cross 4, ganci 6, segni critici (triplo; il gancio critico stordisce 1 s) | 60 (ma `Lab_Only`: mai offerta) | solo nell'arena «Prima persona» del laboratorio, nel suo mazzo |

- È la seconda arma della vista di First Person Shooter (`First_Person_Weapon.Fists`, l'arma nei `charges` del suo
  effetto `.First_Person`); niente carte mentre dura, non si gioca in groppa al Dinosauro.
- Icona e sigla (`FPB`) **provvisorie**: un guantone rosso disegnato da codice nella cella 33 dell'atlante
  (`tools/art/build_card_icons.py`), e un suono provvisorio suo (`card_first_person_brawler`: i guantoni battuti e la
  campanella del ring); quelli definitivi sono della Fase 3, in stile cibernetico.

## 2026-10-25 — Revisione delle carte

Commit **«Carte: ritirate otto carte, cinque diventano potenziamenti»** sul ramo `revisione-carte` (partito da
`piano-griglia`).

### Come si toglie una carta, e come si rimette

- **Ritirata** vuol dire: nella sua definizione in [card.odin](../src/game/card.odin) c'è `traits = {.Retired}`. Il codice
  della carta resta tutto (regole, disegno, suoni, test), ma niente la dà: né il mazzo iniziale, né le ricompense, né i
  negozi, né le officine, né gli archivi dei biomi, né il ring. L'archivio dell'hub non la conta e non la mostra.
  Per **rimetterla** basta togliere quella riga (e, se si vuole, rimetterla dove stava: mazzo iniziale, ring, archivi;
  sotto è scritto dove stava ciascuna).
- **Diventata potenziamento** vuol dire: la carta base ha `evolves_to = .<carta>, evolve_level = CARD_EVOLVE_LEVEL`
  (`CARD_EVOLVE_LEVEL = 2`, in card.odin), e la carta che ne nasce ha `evolution_only = true` e `reward_weight = 0`. Al
  **secondo potenziamento** la carta base diventa l'altra, che riparte dal suo livello 0 e si potenzia per conto suo.
  Per **rimettere** la carta da sola: togliere le due righe dalla carta base, togliere `evolution_only = true` e ridarle il
  `reward_weight` scritto sotto.
- Le carte ritirate o diventate potenziamento **restano nei salvataggi**: se un mazzo di una spedizione in corso ne ha una,
  la si gioca fino alla fine di quella spedizione. Nelle scoperte della campagna restano segnate, solo nascoste.

### Carte ritirate (8)

| Carta | Nel codice | Rarità | Energia | Effetto (com'era) | Peso nelle offerte | Prima comparsa | Dove stava |
|---|---|---|---:|---|---:|---|---|
| Thorn Coat | `Thorn_Coat` | non comune | 25 | su di te: 2 spine per 3 s; abilita la deviazione (contro gli arcieri) | 85 | 15/07, `37487b6` | mazzo iniziale |
| Afterimage | `Afterimage` | non comune | 25 | su di te: schiva senza recupero; 1 scudo se ti muovi, per 4 s | 85 | 15/07, `37487b6` | mazzo iniziale |
| Counter Rune | `Counter_Rune` | rara | 25 | su di te: contrattacco 3; 2 cariche, retain | 65 | 15/07, `37487b6` | — |
| Battle Focus | `Battle_Focus` | rara | 15 | su di te: pesca 2; esplora, vista per 3 s fino a 9 celle; exhaust/ethereal | 65 | 16/07, `bc29683` | run tattica (`--run`), al posto di Toxic Wave |
| Spark Forge | `Spark_Forge` | non comune | 15 | su di te: crea 2 Spark temporanee a energia 0 | 75 | 16/07, `bc29683` | — |
| Spark | `Spark` | comune (temporanea) | 10 | raggio 1-2: 2 danni | 0 (temporanea) | 16/07, `bc29683` | nasceva solo da Spark Forge e Volatile Study |
| Volatile Study | `Volatile_Study` | rara | 20 | su di te: crea 1 Spark, pesca 2; exhaust | 60 | 17/07, `c3ec4b8` | — |
| Titan Grip | `Titan_Grip` | rara | 45 | raggio 1: 3 danni, lancia di 2; interrompe e stordisce 1 s | 65 | 09/10, `8f2b6ae` | premio del primo ring vinto; archivio del bioma Segreto |

### Carte diventate potenziamenti (5)

Ognuna si ottiene ora solo potenziando due volte la carta base; da sola non è più offerta, venduta né scoperta.

| Carta base | Diventa (al 2° potenziamento) | Rarità | Energia | Effetto della carta che ne nasce | Peso che aveva | Prima comparsa | Dove stava |
|---|---|---|---:|---|---:|---|---|
| Guard | **Purifying Guard** (`Purifying_Guard`) | non comune | 25 | su di te: 3 scudo per 2 s; rimuove il veleno | 80 | 17/07, `c3ec4b8` | archivio della Neve |
| Strike | **Cross Slash** (`Cross_Slash`) | non comune | 25 | raggio 1-3: 3 danni a croce; solo celle visibili | 90 | 15/07, `37487b6` | — |
| Arc Bolt | **Chain Lightning** (`Chain_Lightning`) | rara | 40 | raggio 1-4: 3 danni a nemico; salta fino a 3 visibili | 65 | 08/09, `5d7e91d` | archivio dello Spazio |
| Fate Strike | **Prismatic Barrage** (`Prismatic_Barrage`) | non comune | 50 | raggio 1-3: 3d4, ogni 4+ fa 3 danni; con 1-3, 1 scudo per dado | 75 | 08/09, `5d7e91d` | archivi dell'Egitto e dello Spazio |
| Venom Needle | **Twin Venom** (`Twin_Venom`) | non comune | 30 | raggio 1-3: max(2d4) + 1 danni; con una coppia, 2 veleno | 75 | 08/09, `5d7e91d` | — |

Fate Strike, che sale di dado a ogni potenziamento, ora arriva al d6 (livello 1) e al secondo potenziamento diventa
Prismatic Barrage, che riparte dal d4 e sale fino al d20 come prima.

### Cambiamenti che ne seguono

- **Mazzo iniziale** ([deck.odin](../src/game/deck.odin)): da 10 a **8 carte**. Thorn Coat e Afterimage sono uscite senza
  sostituti: Strike, Arc Bolt, Piercing Ray, Shove, Firebomb, Guard, Toxic Wave, Dash.
- **Run tattica** `--run` ([tactical_setup.odin](../src/run/tactical_setup.odin)): Toxic Wave non è più sostituita da Battle
  Focus; restano gli altri cambi (Fate Strike al posto di Arc Bolt, Heavy Blow al posto di Piercing Ray) e le cinque
  carte aggiunte: 13 carte invece di 15.
- **Ring** ([m8_ring.odin](../src/game/m8_ring.odin)): il primo ring vinto dà **Grappling Hook** invece di Titan Grip (la
  presa del ring passa all'uncino: rara, raggio 2-4, 1 danno e trascina il nemico accanto). Come prima Titan Grip, nelle
  run tattiche Grappling Hook non è offerto prima del primo ring vinto; nelle spedizioni non cambia nulla. Storm Crown resta
  al terzo ring.
- **Archivi dei biomi** (scoperte, [expedition_scene.odin](../src/run/expedition_scene.odin)): Neve, Purifying Guard →
  Sundering Blow; Egitto, Prismatic Barrage → Feretro; Spazio, Prismatic Barrage e Chain Lightning → Tesla Coil e Storm
  Crown; Segreto, Titan Grip → Grappling Hook.
- **Collezione**: una nuova funzione, `game.card_in_collection`, dice quali carte si scoprono, entrano nel pool di una
  spedizione e si contano nell'archivio e nell'hub («N / M carte scoperte»): non quelle del laboratorio, non le ritirate,
  non quelle che nascono da un potenziamento, non le temporanee.
- **Interfaccia**: nel pannello PERSONAGGIO una carta che cambia dice «Potenziamento X / 2: diventa <carta>»; nei negozi e
  nei riposi della run tattica l'anteprima del potenziamento che la cambia è «-> <carta>».
- **Restano com'erano**: i tasti di prova `C`/`V` con `--debug-abilities` (sono abilità di prova, non carte); le arene di
  prova `--spell-lab`, `--dice-lab` e gli smoke tattici, che usano alcune di queste carte per provarne le regole.

### Verifica

1651 test, con e senza assert (`scripts/check.ps1`). Due test nuovi
([card_evolution_test.odin](../src/game/card_evolution_test.odin)): le cinque carte cambiano al secondo potenziamento e poi
si potenziano per conto loro; le ritirate restano valide nel codice ma nessuna offerta, mazzo iniziale o collezione le
contiene. Gli altri test che contavano su queste carte sono stati aggiornati (mazzo di 8 carte, premio del ring, pool
delle offerte contato invece che scritto a mano, Fate Strike che cambia).
